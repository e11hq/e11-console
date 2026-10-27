// Light viewing copies of videos (Haris, 2026-10-27: "light copy for all viewing"). Every video in a task, a comment,
// Client Assets or a plan gets a 720p H.264 copy with its index at the start ("faststart"), so it starts in a second or
// two and plays smoothly through the office internet line (~1 MB/s up), which an original (~3 MB/s) can't. Made in the
// background, one at a time, with the NAS's Intel Quick Sync when the container has it (/dev/dri), otherwise with
// the processor. Viewing uses the copy (`/__file/<path>?view=1`); Download always gives the original. Small videos
// (under 8 MB) are shown as they are. Copies live in files/.thumbs/_view/<key>.mp4 and can be rebuilt any time.
import { execFile } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const VIDEO_EXT = ['mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv'];
const isVideo = (p) => VIDEO_EXT.includes(String(p).split('.').pop().toLowerCase());
const defaultRun = (cmd, args, timeout) => new Promise((resolve) => execFile(cmd, args, { timeout, maxBuffer: 4 * 1024 * 1024 }, (err, out, errOut) => resolve({ ok: !err, out: String(errOut || out || '') })));
// 720p: the long side at most 1280, the short side at most 720 (portrait videos stay portrait), even sizes
const SCALE = "scale='if(gt(iw,ih),min(1280,iw),-2)':'if(gt(iw,ih),-2,min(1280,ih))'";

export function createViewCopies({ files, dri = '/dev/dri', minSize = 8 * 1000 * 1000, run = defaultRun, log = console, now = () => Date.now() }) {
  const REL_DIR = '.thumbs/_view';
  const key = (rel) => crypto.createHash('sha1').update(String(rel)).digest('hex').slice(0, 24);
  const relOut = (rel) => `${REL_DIR}/${key(rel)}.mp4`;
  const queue = [];
  const failed = new Map();   // key → time of a failed try (tried again a day later)
  let busy = null;            // rel being converted
  let done = 0, lastMs = 0, lastWith = null;
  function device() {
    try { const d = fs.readdirSync(dri).find((n) => /^renderD\d+$/.test(n)); return d ? path.join(dri, d) : null; } catch { return null; }
  }
  const exists = (rel) => { try { return fs.statSync(files.resolve(relOut(rel))).size > 0; } catch { return false; } };
  function sizeOf(rel) { try { return fs.statSync(files.resolve(rel)).size; } catch { return -1; } }
  // a video that should have a light copy and doesn't yet: queued (once)
  function want(rel) {
    rel = String(rel || '');
    if (!rel || !isVideo(rel) || rel.startsWith('.thumbs/')) return false;
    if (exists(rel) || busy === rel || queue.includes(rel)) return false;
    const f = failed.get(key(rel));
    if (f && now() - f < 24 * 3600_000) return false;
    const size = sizeOf(rel);
    if (size < minSize) return false;
    queue.push(rel);
    kick();
    return true;
  }
  async function make(rel) {
    const src = files.resolve(rel), out = files.resolve(relOut(rel)), tmp = out + '.part';
    fs.mkdirSync(path.dirname(out), { recursive: true });
    const tail = ['-c:a', 'aac', '-b:a', '128k', '-ac', '2', '-movflags', '+faststart', '-f', 'mp4', tmp];
    const timeout = 60 * 60_000;
    const dev = device();
    const t0 = now();
    let r = { ok: false };
    if (dev) {
      // decoding on the video hardware too when it can (it falls back to the processor by itself), encoding on it
      r = await run('ffmpeg', ['-y', '-v', 'error', '-init_hw_device', `vaapi=va:${dev}`, '-filter_hw_device', 'va', '-hwaccel', 'vaapi', '-hwaccel_device', 'va', '-i', src,
        '-vf', `${SCALE},format=nv12,hwupload`, '-c:v', 'h264_vaapi', '-b:v', '2500k', '-maxrate', '3000k', '-bufsize', '6000k', ...tail], timeout);
      if (r.ok) lastWith = 'Quick Sync';
    }
    if (!r.ok) {
      r = await run('ffmpeg', ['-y', '-v', 'error', '-i', src, '-vf', SCALE, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '26', '-maxrate', '3000k', '-bufsize', '6000k',
        '-pix_fmt', 'yuv420p', ...tail], timeout);
      if (r.ok) lastWith = 'processor';
    }
    if (r.ok && fs.existsSync(tmp) && fs.statSync(tmp).size > 0) {
      fs.renameSync(tmp, out);
      done++; lastMs = now() - t0;
      return true;
    }
    fs.rmSync(tmp, { force: true });
    failed.set(key(rel), now());
    log.error('Light copy failed for', rel, (r.out || '').trim().split('\n').slice(-1)[0] || '');
    return false;
  }
  async function kick() {
    if (busy) return;
    while (queue.length) {
      busy = queue.shift();
      try { if (fs.existsSync(files.resolve(busy)) && !exists(busy)) await make(busy); } catch (e) { log.error('Light copy:', e.message); }
      busy = null;
    }
  }
  return {
    want,
    // the copy to show for this video: the light copy when it's ready (queued otherwise), else the original itself
    viewPath(rel) { if (isVideo(rel) && exists(rel)) return relOut(rel); want(rel); return rel; },
    ready: exists,
    remove(rel) { try { fs.rmSync(files.resolve(relOut(rel)), { force: true }); } catch { /* fine */ } },
    stats() { return { waiting: queue.length + (busy ? 1 : 0), working: busy ? path.basename(busy) : null, made: done, lastSeconds: lastMs ? Math.round(lastMs / 1000) : null, lastWith }; },
    idle: () => !busy && !queue.length,
    relOut,
  };
}
