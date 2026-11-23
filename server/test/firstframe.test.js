// A video's picture is its very first frame (as E11 Talk's), and one made the old way (1 second in) is made again once
// (Haris 2026-11-23 10:30)
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createFiles } from '../src/files.js';

const px = (png) => execFileSync('ffmpeg', ['-v', 'error', '-i', png, '-vf', 'crop=1:1:10:10,format=rgb24', '-f', 'rawvideo', '-'])
test('a video’s picture: its first frame; an old one (no .first) made again once', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'e11ff-'));
  fs.mkdirSync(path.join(root, 'files', 'attachments'), { recursive: true });
  const vid = path.join(root, 'files', 'attachments', 'clip.mp4');
  // red for its first second, then blue
  execFileSync('ffmpeg', ['-v', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=64x64:d=1', '-f', 'lavfi', '-i', 'color=c=blue:s=64x64:d=2',
    '-filter_complex', '[0:v][1:v]concat=n=2:v=1[v]', '-map', '[v]', '-pix_fmt', 'yuv420p', vid]);
  const files = createFiles(root);
  // an old picture (blue — 1 second in), made before
  const dir = path.join(root, 'files', '.thumbs', 'v1'); fs.mkdirSync(dir, { recursive: true });
  execFileSync('ffmpeg', ['-v', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=64x64', '-frames:v', '1', path.join(dir, 'thumb.png')]);
  const r = await files.commands.thumb({ id: 'v1', path: 'attachments/clip.mp4' });
  assert.equal(r.thumb, '.thumbs/v1/thumb.png');
  const c = px(path.join(dir, 'thumb.png'));
  assert.ok(c[0] > 200 && c[2] < 60, 'red — the first frame: ' + [...c]);
  assert.ok(fs.existsSync(path.join(dir, '.first')));
  const t0 = fs.statSync(path.join(dir, 'thumb.png')).mtimeMs;
  await files.commands.thumb({ id: 'v1', path: 'attachments/clip.mp4' });
  assert.equal(fs.statSync(path.join(dir, 'thumb.png')).mtimeMs, t0, 'made once, then kept');
});
