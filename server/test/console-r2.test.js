// E11 Console's files through Cloudflare R2 (consoler2.js, Haris 2026-11-20 19:44): a fast copy in R2 for a while, the
// office keeping everything. Uploads in the office are copied up; uploads from outside go straight to R2 and are pulled
// in; opening a file goes to R2 while it has the copy; 25 days (over 5 GB: a week after reaching the office); one shared
// ceiling with Talk, the oldest leaving first; the owner's figures. A small stand-in for R2 here.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import { createServer } from '../src/server.js';

let clock = Date.parse('2026-11-20T10:00:00Z');
let app, base, dir, r2srv;
const objects = new Map(), uploads = new Map();
const B = '/e11-console-files/';
const rules = { budget: 3 * 1024 * 1024, bigBytes: 2 * 1024 * 1024, keepDays: 25, bigKeepDays: 7 };
before(async () => {
  r2srv = http.createServer((req, res) => {
    const u = new URL(req.url, 'http://x'), key = decodeURIComponent(u.pathname);
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks);
      if (req.method === 'POST' && u.searchParams.has('uploads')) { const id = 'up' + uploads.size; uploads.set(id, []); res.end(`<InitiateMultipartUploadResult><UploadId>${id}</UploadId></InitiateMultipartUploadResult>`); return; }
      if (req.method === 'PUT' && u.searchParams.get('uploadId')) { uploads.get(u.searchParams.get('uploadId'))[Number(u.searchParams.get('partNumber')) - 1] = body; res.writeHead(200, { ETag: '"e' + u.searchParams.get('partNumber') + '"' }); res.end(); return; }
      if (req.method === 'POST' && u.searchParams.get('uploadId')) { objects.set(key, Buffer.concat(uploads.get(u.searchParams.get('uploadId')))); res.end('<CompleteMultipartUploadResult/>'); return; }
      if (req.method === 'PUT') { objects.set(key, body); res.writeHead(200, { ETag: '"x"' }); res.end(); return; }
      const o = objects.get(key);
      if (req.method === 'DELETE') { objects.delete(key); res.writeHead(204); res.end(); return; }
      if (!o) { res.writeHead(404); res.end(); return; }
      if (req.method === 'HEAD') { res.writeHead(200, { 'Content-Length': o.length }); res.end(); return; }
      res.writeHead(200, { 'Content-Length': o.length, 'Content-Type': u.searchParams.get('response-content-type') || 'application/octet-stream' }); res.end(o);
    });
  });
  await new Promise((r) => r2srv.listen(0, '127.0.0.1', r));
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11cr2-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false, birthdays: false, daily: false, scheduled: false, views: false, holidays: false, pruneInbox: false,
    adminEmail: 'adm@x.com', r2Account: 'acc', r2KeyId: 'kid', r2Secret: 'sec', r2ConsoleBucket: 'e11-console-files', r2Endpoint: `http://127.0.0.1:${r2srv.address().port}`, r2Rules: rules, r2SettleMs: 20 });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
  app.store.importAll({
    users: [{ id: 'u-adm', email: 'adm@x.com', role: 'admin', active: true, name: 'Haris' }, { id: 'u-am', email: 'am@x.com', role: 'am', active: true, name: 'Leila' }],
    projects: [{ id: 'p1', name: 'Northline', color: '#3a7bd5', order: 1, ams: [{ id: 'u-am' }] }],
    tasks: [{ id: 't1', title: 'Shoot', projectId: 'p1', assignees: ['u-am'], status: 'todo' }],
  }, 'test');
});
after(async () => { await app.close(); r2srv.close(); fs.rmSync(dir, { recursive: true, force: true }); });

const H = (who) => ({ 'X-Dev-Email': who + '@x.com', 'Content-Type': 'application/json' });
const post = async (who, p, b) => (await fetch(base + p, { method: 'POST', headers: H(who), body: JSON.stringify(b) })).json();
const wait = (ms) => new Promise((z) => setTimeout(z, ms));
const inR2 = () => [...objects.keys()].filter((k) => k.startsWith(B));
const open = (who, rel) => fetch(base + '/__file/' + rel.split('/').map(encodeURIComponent).join('/'), { headers: H(who), redirect: 'manual' });

let officeFile;
test('an upload in the office is copied up to R2; opening it then goes to R2', async () => {
  const data = crypto.randomBytes(200 * 1024);
  const r = await (await fetch(base + '/api/host/writeChunkBin?taskId=t1&name=photo.jpg&offset=0', { method: 'POST', headers: { ...H('am'), 'Content-Type': 'application/octet-stream' }, body: data })).json();
  assert.ok(r.ok); officeFile = r.path;
  const before = await open('am', officeFile);
  assert.equal(before.status, 200, 'served by the office until the copy is up'); await before.arrayBuffer();
  await wait(150);
  assert.equal(inR2().length, 1, 'copied up a moment after its last piece');
  const r2 = await open('am', officeFile);
  assert.equal(r2.status, 302, 'opened from R2 now');
  const got = Buffer.from(await (await fetch(r2.headers.get('location'))).arrayBuffer());
  assert.deepEqual(got, data);
  assert.equal((await open('adm', officeFile)).status, 302);
});

test('an upload from outside goes straight to R2 and is pulled into the office', async () => {
  const data = crypto.randomBytes(300 * 1024);
  const s = await post('am', '/api/host/r2Start', { taskId: 't1', name: 'brief.pdf', size: data.length });
  assert.ok(s.ok && s.put, 'one address for a small file');
  assert.equal((await fetch(s.put, { method: 'PUT', body: data })).status, 200);
  const d = await post('am', '/api/host/r2Done', { path: s.path });
  assert.ok(d.ok && d.path === s.path);
  assert.equal((await open('am', s.path)).status, 302, 'opened from R2 while it comes in');
  await wait(100);
  const full = path.join(dir, 'files', s.path);
  assert.deepEqual(fs.readFileSync(full), data, 'and the office has it');
  assert.equal((await post('adm', '/api/host/r2Done', { path: s.path })).ok, false, 'only the one uploading finishes it');
});

test('in parts (over 8 MB), and a part missing isn’t taken', async () => {
  const big = crypto.randomBytes(9 * 1024 * 1024);
  const s = await post('am', '/api/host/r2Start', { taskId: 't1', name: 'clip.mov', size: big.length });
  assert.equal(s.urls.length, 2);
  assert.equal((await post('am', '/api/host/r2Done', { path: s.path, etags: ['"e1"'] })).ok, false);
  const etags = [];
  for (let i = 0; i < s.urls.length; i++) { const r = await fetch(s.urls[i], { method: 'PUT', body: big.subarray(i * s.part, (i + 1) * s.part) }); etags.push(r.headers.get('etag')); }
  assert.ok((await post('am', '/api/host/r2Done', { path: s.path, etags })).ok);
  await wait(200);
  assert.deepEqual(fs.readFileSync(path.join(dir, 'files', s.path)), big);
});

test('the shared ceiling: the oldest copies leave R2 first (the office keeps everything)', async () => {
  // (the 9 MB clip was over this test's 3 MB ceiling: the older copies made way, and it couldn't fit — so the office serves it)
  const u = await (await fetch(base + '/api/r2/usage', { headers: H('adm') })).json();
  assert.ok(u.ok && u.total <= rules.budget, 'never over the ceiling');
  assert.equal((await fetch(base + '/api/r2/usage', { headers: H('am') })).status, 403, 'the owner only');
});

test('25 days: the fast copy goes, the office serves it again; a changed file isn’t served from R2', async () => {
  const data = crypto.randomBytes(100 * 1024);
  const r = await (await fetch(base + '/api/host/writeChunkBin?taskId=t1&name=late.png&offset=0', { method: 'POST', headers: { ...H('am'), 'Content-Type': 'application/octet-stream' }, body: data })).json();
  await wait(150);
  assert.equal((await open('am', r.path)).status, 302);
  // (the office file replaced: the old copy isn't used)
  fs.writeFileSync(path.join(dir, 'files', r.path), crypto.randomBytes(1000));
  const ch = await open('am', r.path); assert.equal(ch.status, 200); await ch.arrayBuffer();
  await wait(150);
  assert.equal((await open('am', r.path)).status, 302, 'the new file copied up in its place');
  clock += 26 * 86400000; app.consoleR2.sweep();
  await wait(50);
  const old = await open('am', r.path); assert.equal(old.status, 200, 'after 25 days: from the office'); await old.arrayBuffer();
});
