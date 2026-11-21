// E11 Talk's message files through Cloudflare R2 (r2.js, Haris 2026-11-20 17:52): the phone puts a file straight into R2
// (in 8 MB parts when bigger), locked with its own key; the group's phones are sent to R2 for it; older apps and Macs get it
// through the server, unlocked; it goes from R2 on the same rules as before. A small stand-in for R2 here.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import { createServer } from '../src/server.js';
import { presign } from '../src/r2.js';

let clock = Date.parse('2026-11-20T10:00:00Z');
let app, base, dir, r2srv, r2base;
const objects = new Map(), uploads = new Map();
before(async () => {
  // (R2's stand-in: put, parts, put together, head, get with a range, delete)
  r2srv = http.createServer((req, res) => {
    const u = new URL(req.url, 'http://x'), key = decodeURIComponent(u.pathname);
    assert.ok(u.searchParams.get('X-Amz-Signature'), 'every request signed');
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
      const m = /^bytes=(\d+)-(\d+)$/.exec(req.headers.range || '');
      const part = m ? o.subarray(Number(m[1]), Number(m[2]) + 1) : o;
      res.writeHead(m ? 206 : 200, { 'Content-Length': part.length }); res.end(part);
    });
  });
  await new Promise((r) => r2srv.listen(0, '127.0.0.1', r));
  r2base = `http://127.0.0.1:${r2srv.address().port}`;
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11talkr2-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false, birthdays: false, daily: false, scheduled: false, views: false, holidays: false, pruneInbox: false,
    r2Account: 'acc', r2KeyId: 'kid', r2Secret: 'sec', r2Bucket: 'e11-talk-files', r2Endpoint: r2base });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
  app.store.importAll({
    users: [
      { id: 'u-am', email: 'am@x.com', role: 'am', active: true, name: 'Leila' },
      { id: 'u-des', email: 'des@x.com', role: 'production', active: true, name: 'Yousef' },
      { id: 'u-adm', email: 'adm@x.com', role: 'admin', active: true, name: 'Haris' },
    ],
    clients: [{ id: 'c1', name: 'Northline', folders: [] }],
    projects: [{ id: 'p1', name: 'Northline', color: '#3a7bd5', clientId: 'c1', order: 1, ams: [{ id: 'u-am' }] }],
  }, 'test');
});
after(async () => { await app.close(); r2srv.close(); fs.rmSync(dir, { recursive: true, force: true }); });

const H = (who) => ({ 'X-Dev-Email': who + '@x.com', 'Content-Type': 'application/json' });
const post = async (who, p, b) => (await fetch(base + p, { method: 'POST', headers: H(who), body: JSON.stringify(b) })).json();
const sync = async (who) => (await fetch(base + '/api/talk/sync?after=0', { headers: H(who) })).json();
// (the phone's lock: AES-GCM, Apple's combined form — nonce, the file, tag)
const lock = (data, key) => { const n = crypto.randomBytes(12), c = crypto.createCipheriv('aes-256-gcm', key, n); const x = Buffer.concat([c.update(data), c.final()]); return Buffer.concat([n, x, c.getAuthTag()]); };
const unlock = (b, key) => { const d = crypto.createDecipheriv('aes-256-gcm', key, b.subarray(0, 12)); d.setAuthTag(b.subarray(b.length - 16)); return Buffer.concat([d.update(b.subarray(12, b.length - 16)), d.final()]); };

test('signing: AWS’s own example presigned address', () => {
  const u = presign({ method: 'GET', host: 'examplebucket.s3.amazonaws.com', path: '/test.txt', keyId: 'AKIAIOSFODNN7EXAMPLE', secret: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', region: 'us-east-1', expires: 86400, now: Date.UTC(2013, 4, 24) });
  assert.ok(u.endsWith('X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404'));
});

let G;
test('a photo straight to R2, locked; the other phone sent to R2 for it; a Mac gets it unlocked through the server', async () => {
  G = (await post('am', '/api/talk/act', { act: 'newGroup', client: 'p1', name: 'Shoot', members: ['u-des'] })).group.id;
  const key = crypto.randomBytes(32), photo = crypto.randomBytes(300 * 1024), sealed = lock(photo, key);
  const s = await post('am', '/api/talk/r2/start', { name: 'IMG.jpg', size: sealed.length });
  assert.ok(s.ok && s.put && !s.urls, 'small: one address');
  assert.equal((await fetch(s.put, { method: 'PUT', body: sealed })).status, 200);
  const d = await post('am', '/api/talk/r2/done', { id: s.id });
  assert.ok(d.ok && d.done);
  const m = await post('am', '/api/talk/act', { act: 'send', group: G, file: { id: s.id, kind: 'photo', key: key.toString('base64') } });
  assert.ok(m.ok);
  const ev = (await sync('des')).events.find((e) => e.file && e.file.id === s.id);
  assert.equal(ev.file.key, key.toString('base64'), 'the key goes with the message');
  assert.ok(objects.get('/e11-talk-files/msg/' + s.id), 'in the bucket under msg/');
  // (a newer phone: off to R2)
  const r = await fetch(base + '/api/talk/file/' + s.id + '?r2=1', { headers: H('des'), redirect: 'manual' });
  assert.equal(r.status, 302);
  const got = Buffer.from(await (await fetch(r.headers.get('location'))).arrayBuffer());
  assert.deepEqual(unlock(got, key), photo, 'what R2 gives is the locked file, which opens with the key');
  // (an older app or a Mac: through the server, unlocked)
  const old = await fetch(base + '/api/talk/file/' + s.id, { headers: H('des') });
  assert.equal(old.status, 200);
  assert.deepEqual(Buffer.from(await old.arrayBuffer()), photo);
  assert.equal((await fetch(base + '/api/talk/file/' + s.id + '?r2=1', { headers: H('adm'), redirect: 'manual' })).status, 404, 'not for people outside the group');
});

test('a big video in 8 MB parts; a part missing isn’t taken', async () => {
  const big = crypto.randomBytes(17 * 1024 * 1024 + 5);
  const s = await post('am', '/api/talk/r2/start', { name: 'clip.mp4', size: big.length });
  assert.equal(s.urls.length, 3);
  assert.equal((await post('am', '/api/talk/r2/done', { id: s.id, etags: ['"e1"'] })).ok, false, 'parts missing');
  const etags = [];
  for (let i = 0; i < s.urls.length; i++) { const r = await fetch(s.urls[i], { method: 'PUT', body: big.subarray(i * s.part, (i + 1) * s.part) }); etags.push(r.headers.get('etag')); }
  const d = await post('am', '/api/talk/r2/done', { id: s.id, etags });
  assert.ok(d.ok && d.done);
  assert.deepEqual(objects.get('/e11-talk-files/msg/' + s.id), big);
  assert.equal((await post('des', '/api/talk/r2/done', { id: s.id, etags })).ok, false, 'only the sender finishes it');
});

test('gone from R2 on the same rules: a day after every phone has it', async () => {
  const s = await post('am', '/api/talk/r2/start', { name: 'a.pdf', size: 5 });
  await fetch(s.put, { method: 'PUT', body: Buffer.from('HELLO') });
  await post('am', '/api/talk/r2/done', { id: s.id });
  await post('am', '/api/talk/act', { act: 'send', group: G, file: { id: s.id, kind: 'file' } });
  for (const w of ['am', 'des']) { const x = await sync(w); if (x.last) await post(w, '/api/talk/ack', { upto: x.last }); }
  const r = await fetch(base + '/api/talk/file/' + s.id, { headers: H('des') });
  assert.equal(await r.text(), 'HELLO', 'not locked: as it is');
  await new Promise((z) => setTimeout(z, 30));
  assert.ok(objects.has('/e11-talk-files/msg/' + s.id), 'still there just after');
  clock += 25 * 3600000; app.talk.sweep();
  await new Promise((z) => setTimeout(z, 50));
  assert.ok(!objects.has('/e11-talk-files/msg/' + s.id), 'deleted from R2 a day after');
});

test('too big, or no R2 keys: refused (the phone then sends the usual way)', async () => {
  assert.equal((await post('am', '/api/talk/r2/start', { name: 'x', size: 2 * 1024 * 1024 * 1024 })).ok, false);
});

test('a group’s picture in R2 under grp/ (out of the 31-day rule), locked: its key with the group; older apps get it unlocked (Haris 2026-11-21)', async () => {
  const key = crypto.randomBytes(32), pic = crypto.randomBytes(40 * 1024), sealed = lock(pic, key);
  const s = await post('am', '/api/talk/r2/start', { name: 'group.jpg', size: sealed.length, keep: true });
  assert.ok(s.ok && s.put);
  assert.equal((await fetch(s.put, { method: 'PUT', body: sealed })).status, 200);
  assert.ok((await post('am', '/api/talk/r2/done', { id: s.id })).ok);
  assert.ok([...objects.keys()].some((k) => k.endsWith('/grp/' + s.id)), 'kept under grp/');
  const r = await post('am', '/api/talk/act', { act: 'setPic', group: G, file: s.id, key: key.toString('base64') });
  assert.ok(r.ok && r.group.pic === s.id && r.group.picKey === key.toString('base64'), 'the group carries its key');
  const st = await (await fetch(base + '/api/talk/state', { headers: H('des') })).json();
  const g = (st.groups || []).find((x) => x.id === G);
  assert.equal(g && g.picKey, key.toString('base64'), 'the other member gets the key');
  const old = await fetch(base + '/api/talk/file/' + s.id, { headers: H('des') });
  assert.deepEqual(Buffer.from(await old.arrayBuffer()), pic, 'an older app: unlocked through the server');
  const pr = await fetch(base + '/api/talk/file/' + s.id + '?r2=1', { headers: H('des'), redirect: 'manual' });
  assert.equal(pr.status, 302, 'a newer phone: straight to R2');
});

test('a link’s preview picture in R2, locked: its key goes with the link (Haris 2026-11-21)', async () => {
  const key = crypto.randomBytes(32), img = crypto.randomBytes(20 * 1024), sealed = lock(img, key);
  const s = await post('am', '/api/talk/r2/start', { name: 'preview.jpg', size: sealed.length });
  await fetch(s.put, { method: 'PUT', body: sealed });
  assert.ok((await post('am', '/api/talk/r2/done', { id: s.id })).ok);
  const m = await post('am', '/api/talk/act', { act: 'send', group: G, text: 'https://example.com/a', link: { url: 'https://example.com/a', title: 'A', img: { id: s.id, key: key.toString('base64') } } });
  assert.ok(m.ok);
  const ev = (await sync('des')).events.find((e) => e.id === m.id);
  assert.equal(ev.link.img.id, s.id);
  assert.equal(ev.link.img.key, key.toString('base64'), 'the key with the picture');
  const old = await fetch(base + '/api/talk/file/' + s.id, { headers: H('des') });
  assert.deepEqual(Buffer.from(await old.arrayBuffer()), img, 'an older app: unlocked through the server');
});
