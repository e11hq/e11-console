// Light viewing copies: a video in a task gets a 720p copy with its index at the start; viewing (?view=1) serves it
// once ready (the original until then); Download (no ?view) keeps the original; deleting the file removes the copy
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com';
let app, dir, base;
const REL = 'attachments/t1/clip.mp4';
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-view-'));
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER, driDir: path.join(dir, 'no-dri'), viewMinSize: 1, digest: false, holidays: false, occRemind: false, birthdays: false, scheduled: false, daily: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  const src = path.join(dir, 'files', REL);
  fs.mkdirSync(path.dirname(src), { recursive: true });
  // a 1080p clip with sound, its index at the END (like many exports)
  execFileSync('ffmpeg', ['-y', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc=size=1920x1080:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '3', '-c:v', 'libx264', '-preset', 'ultrafast', '-c:a', 'aac', '-shortest', src]);
  app.store.importAll({ users: [{ id: 'u-h', email: OWNER, name: 'Haris', role: 'admin', active: true }], projects: [], statuses: [],
    tasks: [{ id: 't1', title: 'T', assignees: [], createdBy: 'u-h', tags: [], comments: [], attachments: [{ id: 'a1', name: 'clip.mp4', path: REL, size: fs.statSync(src).size }] }] }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const get = (p) => fetch(base + p, { headers: { 'X-Dev-Email': OWNER } });
const probe = (file) => JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height,codec_name', '-of', 'json', file]).toString()).streams[0];
const moovFirst = (file) => { const b = fs.readFileSync(file); return b.indexOf('moov') < b.indexOf('mdat'); };

test('viewing serves the original until the light copy is ready, then the copy; Download keeps the original', async () => {
  const orig = Buffer.from(await (await get('/__file/' + REL + '?view=1')).arrayBuffer());
  assert.equal(orig.length, fs.statSync(path.join(dir, 'files', REL)).size, 'the original meanwhile');
  for (let i = 0; i < 200 && !app.views.ready(REL); i++) await new Promise((r) => setTimeout(r, 100));
  assert.ok(app.views.ready(REL), 'the copy got made');
  const out = path.join(dir, 'files', app.views.relOut(REL));
  const v = probe(out);
  assert.deepEqual([v.width, v.height, v.codec_name], [1280, 720, 'h264']);
  assert.ok(moovFirst(out), 'its index is at the start, so it plays at once');
  const viewed = Buffer.from(await (await get('/__file/' + REL + '?view=1')).arrayBuffer());
  assert.equal(viewed.length, fs.statSync(out).size, 'viewing gets the light copy');
  const ranged = await fetch(base + '/__file/' + REL + '?view=1', { headers: { 'X-Dev-Email': OWNER, Range: 'bytes=0-99' } });
  assert.equal(ranged.status, 206, 'and it can be streamed in parts');
  const dl = Buffer.from(await (await get('/__file/' + REL)).arrayBuffer());
  assert.equal(dl.length, fs.statSync(path.join(dir, 'files', REL)).size, 'Download is the original');
  assert.equal(app.views.stats().made, 1);
});
test('a video picked up by the scan, and the copy removed with its file', async () => {
  app.views.remove(REL);
  assert.equal(app.views.ready(REL), false);
  app.scanVideos();
  for (let i = 0; i < 200 && !app.views.ready(REL); i++) await new Promise((r) => setTimeout(r, 100));
  assert.ok(app.views.ready(REL), 'the scan makes copies for videos already in tasks');
  const t = app.store.get('tasks', 't1');
  app.store.apply([{ kind: 'tasks', id: 't1', data: { ...t, attachments: [] } }], 'test');
  const r = await fetch(base + '/api/host/trashMany', { method: 'POST', headers: { 'X-Dev-Email': OWNER, 'Content-Type': 'application/json' }, body: JSON.stringify({ paths: [REL] }) }).then((x) => x.json());
  assert.equal(r.deleted, 1);
  assert.equal(app.views.ready(REL), false, 'its light copy is gone too');
});
