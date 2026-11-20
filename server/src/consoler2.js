// E11 Console's files through Cloudflare R2 (Haris 2026-11-20 19:15–19:44, project doc claude/console-r2-files-plan.md).
// The office server keeps every file for good; R2 holds a fast copy for a while, so opening one from outside the office
// doesn't go out over the office line:
//   • originals: 25 days after they went up (over 5 GB: a week after they're safely in the office);
//   • light video copies and previews (v/): 25 days; thumbnails and smaller photos (t/): as long as there's room;
//   • Console and Talk together at most 143 GB — over it, the oldest copies leave first (originals, then previews, then
//     thumbnails). Under Cloudflare's free 10 GB it costs nothing.
// Uploads from outside go straight into R2 (start → the phone or browser puts the parts → done) and are pulled into the
// office in the background; uploads in the office (and copies from E11 Share) are copied up in the background. A copy is
// only used while the office file is still the same one (its size and time). Off without R2's keys / bucket.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { DatabaseSync } from 'node:sqlite';

const DAY = 86400000;
// a file is 5 GB at most (Haris 2026-11-20 19:53) — every upload, the office's and R2's
export const MAX_FILE = 5 * 1e9;
export const R2_RULES = { keepDays: 25, bigBytes: 5 * 1e9, bigKeepDays: 7, budget: 143 * 1e9, free: 10 * 1e9, perGbMonth: 0.015 };

export function createConsoleR2({ r2, files, dataDir, dbFile, now = () => Date.now(), talkBytes = () => 0, log = console, rules: given = null, settleMs = 60000 }) {
  const rules = { ...R2_RULES, ...(given || {}) };
  const on = !!(r2 && r2.on);
  let closed = false;
  const file = dbFile || path.join(dataDir, 'db', 'r2.sqlite');
  if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec(`CREATE TABLE IF NOT EXISTS objs (rel TEXT PRIMARY KEY, key TEXT NOT NULL, kind TEXT NOT NULL, size INTEGER NOT NULL,
    mtime REAL, put_at INTEGER NOT NULL, office_at INTEGER, pulling INTEGER NOT NULL DEFAULT 0, upload TEXT, by TEXT)`);
  const Q = {
    get: db.prepare('SELECT * FROM objs WHERE rel = ?'),
    put: db.prepare('INSERT OR REPLACE INTO objs (rel, key, kind, size, mtime, put_at, office_at, pulling, upload, by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'),
    del: db.prepare('DELETE FROM objs WHERE rel = ?'),
    total: db.prepare('SELECT COALESCE(SUM(size), 0) AS n FROM objs'),
    all: db.prepare('SELECT * FROM objs'),
  };
  // what kind of copy a path is: a light video copy or a page preview (v/), a thumbnail or a smaller photo (t/), an original
  const kindOf = (rel) => (rel.startsWith('.thumbs/_view/') || /^\.thumbs\/[^/]+\/(preview\.pdf|pages\/)/.test(rel) ? 'v' : rel.startsWith('.thumbs/') ? 't' : 'f');
  const keyOf = (rel) => kindOf(rel) + '/' + crypto.createHash('sha256').update(rel).digest('hex').slice(0, 40);
  const statOf = (rel) => { try { const st = fs.statSync(files.resolve(rel)); return st.isFile() ? st : null; } catch { return null; } };
  const relOf = (full) => path.relative(files.root, full).split(path.sep).join('/');
  // (no copies of pages a browser would run: those are only ever served by the office, with its own safety rules)
  const unsafe = (rel) => /\.(html?|svg|xml|xhtml)$/i.test(rel);

  /* ---------- the fast copy for a file, when there is one ---------- */
  // a link to R2 for this office file (or null: the office serves it). The same link for half an hour, so browsers keep
  // what they fetched; it works for an hour at most.
  function link(rel, { download = false } = {}) {
    if (!on || !rel || unsafe(rel)) return null;
    const o = Q.get.get(rel);
    if (!o) { want(rel); return null; }
    if (!o.pulling) {
      const st = statOf(rel);
      if (!st || st.size !== o.size || Math.abs(st.mtimeMs - o.mtime) > 1) { forget(rel); want(rel); return null; }   // (not the same file any more)
    }
    const name = path.basename(rel);
    return r2.getUrl(o.key, { slot: 30 * 60000, expires: 3600, type: mime(name), download: download ? name : null });
  }

  /* ---------- copies going up (one at a time, in the background) ---------- */
  const queue = [], queued = new Set();
  let busy = false;
  // a file asked for from outside, or just uploaded in the office: copied up if it should be there
  function want(rel) {
    if (!on || !rel || unsafe(rel) || queued.has(rel) || Q.get.get(rel)) return;
    const st = statOf(rel);
    if (!st || st.size === 0) return;
    const kind = kindOf(rel);
    if (kind === 'f' && now() - st.mtimeMs > rules.keepDays * DAY) return;   // (an older original: the office serves it)
    if (st.size > rules.budget / 4) return;
    queued.add(rel); queue.push(rel); kick();
  }
  // the office wrote a file (an upload's piece): copied up a minute after its last piece
  const settle = new Map();
  function touched(rel) {
    if (!on || !rel) return;
    clearTimeout(settle.get(rel));
    const t = setTimeout(() => { settle.delete(rel); if (!closed) want(rel); }, settleMs);
    if (t.unref) t.unref();
    settle.set(rel, t);
  }
  async function kick() {
    if (busy || closed) return;
    busy = true;
    try {
      while (queue.length && !closed) {
        const rel = queue.shift(); queued.delete(rel);
        try { await copyUp(rel); } catch (e) { log.error('R2 copy up:', rel, e.message); }
      }
    } finally { busy = false; }
  }
  async function copyUp(rel) {
    const st = statOf(rel);
    if (!st || Q.get.get(rel)) return;
    if (!(await room(st.size))) return;
    const key = keyOf(rel), full = files.resolve(rel);
    const s = await r2.start(key, st.size);
    if (s.put) {
      const r = await fetchPut(s.put, fs.readFileSync(full));
      if (!r) throw new Error('put failed');
    } else {
      const fd = fs.openSync(full, 'r'), etags = [];
      try {
        for (let i = 0; i < s.urls.length; i++) {
          const len = Math.min(s.part, st.size - i * s.part), buf = Buffer.alloc(len);
          fs.readSync(fd, buf, 0, len, i * s.part);
          const e = await fetchPut(s.urls[i], buf);
          if (!e) throw new Error('part failed');
          etags.push(e);
        }
      } finally { fs.closeSync(fd); }
      await r2.complete(key, s.upload, etags);
    }
    const again = statOf(rel);
    if (!again || again.size !== st.size || again.mtimeMs !== st.mtimeMs) { await r2.del(key).catch(() => {}); return; }   // (changed meanwhile)
    Q.put.run(rel, key, kindOf(rel), st.size, st.mtimeMs, now(), now(), 0, null, null);
  }
  async function fetchPut(url, body) {
    for (let i = 0; i < 3; i++) {
      try {
        const r = await r2.fetch(url, { method: 'PUT', body });
        if (r.ok) return r.headers.get('etag') || '"ok"';
      } catch { /* tried again */ }
    }
    return null;
  }

  /* ---------- uploads straight into R2 (from outside the office) ---------- */
  // the file's place in the office is kept for it (empty until it's pulled in); the caller has checked who may add it
  async function startUpload(u, target, name, size) {
    if (!on) return { ok: false, error: 'Not here', status: 404 };
    size = Number(size);
    if (!Number.isInteger(size) || size <= 0) return { ok: false, error: 'Bad size', status: 400 };
    if (size > MAX_FILE) return { ok: false, error: 'Files up to 5 GB can be uploaded', status: 413 };
    const out = files.newUploadFile(target, String(name || 'file'));
    const key = keyOf(out.rel);
    try {
      await room(size);
      const s = await r2.start(key, size);
      Q.put.run(out.rel, key, 'f', size, null, now(), null, 1, s.upload || null, u.id);
      return { ok: true, path: out.rel, name: path.basename(out.full), ...(s.put ? { put: s.put } : { part: s.part, urls: s.urls }) };
    } catch (e) { fs.rmSync(out.full, { force: true }); Q.del.run(out.rel); return { ok: false, error: e.message, status: 502 }; }
  }
  // every part is in: put together, checked, and pulled into the office in the background (waiters: ready())
  const pulls = new Map();
  async function finishUpload(u, rel, etags) {
    const o = Q.get.get(String(rel || ''));
    if (!o || !o.pulling || o.by !== u.id) return { ok: false, error: 'Upload not found — please try again', status: 404 };
    try {
      if (o.upload) {
        if (!Array.isArray(etags) || etags.length !== Math.ceil(o.size / r2.PART)) return { ok: false, error: 'Part of the file didn’t arrive — please try again', status: 400 };
        await r2.complete(o.key, o.upload, etags.map(String));
      }
      const got = await r2.size(o.key);
      if (got !== o.size) return { ok: false, error: 'Part of the file didn’t arrive — please try again', status: 400 };
    } catch (e) { return { ok: false, error: e.message, status: 502 }; }
    db.prepare('UPDATE objs SET upload = NULL WHERE rel = ?').run(o.rel);
    if (!pulls.has(o.rel)) pulls.set(o.rel, pull(o).finally(() => pulls.delete(o.rel)));
    return { ok: true, path: o.rel, name: path.basename(o.rel), size: o.size };
  }
  async function pull(o) {
    const full = files.resolve(o.rel), tmp = full + '.r2part';
    for (let i = 0; i < 3; i++) {
      try {
        const r = await r2.get(o.key);
        if (!r.ok) throw new Error('R2 answered ' + r.status);
        await pipeline(Readable.fromWeb(r.body), fs.createWriteStream(tmp));
        if (fs.statSync(tmp).size !== o.size) throw new Error('short');
        fs.renameSync(tmp, full);
        const st = fs.statSync(full);
        db.prepare('UPDATE objs SET pulling = 0, mtime = ?, office_at = ? WHERE rel = ?').run(st.mtimeMs, now(), o.rel);
        await room(0);   // (it had to go up whatever the room; now it's in the office, back under the ceiling — oldest first)
        return true;
      } catch (e) { fs.rmSync(tmp, { force: true }); log.error('R2 pull:', o.rel, e.message); }
    }
    return false;
  }
  // a file still being pulled in: wait for it (a thumbnail or a copy into Client Assets needs the office's own file)
  function ready(rel, ms = 120000) {
    const p = pulls.get(String(rel || ''));
    if (!p) return Promise.resolve(true);
    return Promise.race([p, new Promise((ok) => { const t = setTimeout(() => ok(false), ms); if (t.unref) t.unref(); })]);
  }
  // after a restart: pulls that hadn't finished, started again
  function resume() {
    if (closed) return;
    for (const o of Q.all.all()) if (o.pulling && !o.upload && !pulls.has(o.rel)) pulls.set(o.rel, pull(o).finally(() => pulls.delete(o.rel)));
  }

  /* ---------- letting copies go ---------- */
  function forget(rel) {
    const o = Q.get.get(rel);
    if (!o) return;
    Q.del.run(rel);
    r2.del(o.key).catch((e) => log.error('R2 delete:', e.message));
  }
  // a file deleted for good in the office: its copy goes too
  function remove(rels) { for (const r of rels || []) if (r) forget(String(r)); }
  // room for size more bytes under the shared ceiling: the oldest copies leave first (originals, previews, thumbnails)
  async function room(size) {
    let used = total() + size;
    if (used <= rules.budget) return true;
    const order = { f: 0, v: 1, t: 2 };
    const olds = Q.all.all().filter((o) => !o.pulling).sort((a, b) => order[a.kind] - order[b.kind] || a.put_at - b.put_at);
    for (const o of olds) { if (used <= rules.budget) break; forget(o.rel); used -= o.size; }
    return used <= rules.budget;
  }
  // the time rules (hourly): originals 25 days (over 5 GB: a week after reaching the office), previews 25 days
  function sweep() {
    const t = now();
    for (const o of Q.all.all()) {
      if (o.pulling) { if (t - o.put_at > 2 * DAY) { Q.del.run(o.rel); r2.del(o.key).catch(() => {}); } continue; }   // (never finished)
      const gone = o.kind === 'f' ? (o.size > rules.bigBytes ? (o.office_at || o.put_at) + rules.bigKeepDays * DAY < t : o.put_at + rules.keepDays * DAY < t)
        : o.kind === 'v' ? o.put_at + rules.keepDays * DAY < t : false;
      if (gone || !statOf(o.rel)) forget(o.rel);
    }
  }
  const timer = on ? setInterval(() => { try { sweep(); } catch (e) { log.error('R2 sweep:', e.message); } }, 3600_000) : null;
  if (timer && timer.unref) timer.unref();
  const resumeT = on ? setTimeout(resume, 5000) : null;
  if (resumeT && resumeT.unref) resumeT.unref();

  /* ---------- for the owner's About ---------- */
  const total = () => Number(Q.total.get().n) + Number(talkBytes() || 0);
  function usage() {
    const c = Number(Q.total.get().n), tk = Number(talkBytes() || 0), all = c + tk;
    const cost = Math.max(0, all - rules.free) / 1e9 * rules.perGbMonth;
    return { on, console: c, talk: tk, total: all, budget: rules.budget, free: rules.free, cost: Math.round(cost * 100) / 100 };
  }

  return { on, link, want, touched, startUpload, finishUpload, ready, remove, sweep, usage, relOf, close: () => { closed = true; clearInterval(timer); clearTimeout(resumeT); for (const t of settle.values()) clearTimeout(t); db.close(); } };
}

const TYPES = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif', webp: 'image/webp', heic: 'image/heic', pdf: 'application/pdf',
  mp4: 'video/mp4', mov: 'video/quicktime', m4v: 'video/x-m4v', webm: 'video/webm', mp3: 'audio/mpeg', m4a: 'audio/mp4', wav: 'audio/wav', zip: 'application/zip' };
function mime(name) { return TYPES[String(name).split('.').pop().toLowerCase()] || 'application/octet-stream'; }
