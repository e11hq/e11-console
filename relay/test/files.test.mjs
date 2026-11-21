import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fakeSql } from './fake-sql.mjs';
import { fakeBucket } from './fake-bucket.mjs';
import { HubCore } from '../src/core.js';
import { bindingR2, serveR2, PART } from '../src/r2.js';

const DIR = { users: [{ id: 'u1', name: 'Haris', email: 'haris@e11.test', role: 'admin', active: true }, { id: 'u2', name: 'Lana', email: 'lana@e11.test', role: 'production', active: true }],
  projects: [{ id: 'p1', name: 'Client One' }], clients: [], meta: {}, flags: { u1: { super: true } }, see: { u1: ['p1'], u2: ['p1'] } };
const env = (bucket) => ({ TALK_FILES: bucket, R2_LINK_SECRET: 'test-secret-123', PUBLIC: 'https://relay.test' });
const path = (u) => new URL(u).pathname;

test('a photo: sent through the relay to R2, the message, the other phone fetches it', async () => {
  const bucket = fakeBucket(), e = env(bucket);
  const h = new HubCore({ sql: fakeSql(), dir: DIR, r2: bindingR2({ bucket, secret: e.R2_LINK_SECRET, base: e.PUBLIC }) });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), b = h.who('lana@e11.test', 'phone-key-bbbbbbbbbbbb');
  const gid = h.act(a, { act: 'newGroup', client: 'p1', name: 'Files', members: ['u2'] }).group.id;
  const bytes = new Uint8Array(1000).fill(7);
  const s = await h.r2Start(a, { name: 'photo.heic', size: bytes.byteLength });
  assert.equal(s.ok, true, JSON.stringify(s)); assert.ok(s.put.startsWith('https://relay.test/r2/put/'));
  const put = await serveR2(new Request(s.put, { method: 'PUT', body: bytes }), e, path(s.put));
  assert.equal(put.status, 200); assert.ok(put.headers.get('etag'));
  const d = await h.r2Done(a, { id: s.id }); assert.equal(d.ok, true, JSON.stringify(d));
  const m = h.act(a, { act: 'send', group: gid, text: '', file: { id: s.id, kind: 'photo', key: 'A'.repeat(43) + '=' } });
  assert.equal(m.ok, true, JSON.stringify(m));
  const f = h.fileFor(b, s.id); assert.ok(f, 'Lana may fetch it');
  const url = await h.talk.r2.getUrl(h.talk.r2Key(f));
  const got = await serveR2(new Request(url), e, path(url));
  assert.equal(got.status, 200); assert.equal((await got.arrayBuffer()).byteLength, 1000);
  const part = await serveR2(new Request(url, { headers: { range: 'bytes=10-19' } }), e, path(url));
  assert.equal(part.status, 206); assert.equal(part.headers.get('content-range'), 'bytes 10-19/1000');
});

test('a big video in 8 MB parts, put together in order', async () => {
  const bucket = fakeBucket(), e = env(bucket);
  const h = new HubCore({ sql: fakeSql(), dir: DIR, r2: bindingR2({ bucket, secret: e.R2_LINK_SECRET, base: e.PUBLIC }) });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa');
  const size = PART * 2 + 5;
  const s = await h.r2Start(a, { name: 'v.mp4', size });
  assert.equal(s.urls.length, 3);
  const etags = [];
  for (let i = 0; i < 3; i++) { const n = i < 2 ? PART : 5; const r = await serveR2(new Request(s.urls[i], { method: 'PUT', body: new Uint8Array(n).fill(i) }), e, path(s.urls[i])); etags.push(r.headers.get('etag')); }
  const d = await h.r2Done(a, { id: s.id, etags }); assert.equal(d.ok, true, JSON.stringify(d));
  assert.equal(bucket.objs.get('msg/' + s.id).byteLength, size);
});

test('an address can’t be changed, reused for something else, or used late', async () => {
  const e = env(fakeBucket());
  const r2 = bindingR2({ bucket: e.TALK_FILES, secret: e.R2_LINK_SECRET, base: e.PUBLIC });
  const url = await r2.getUrl('msg/f-1');
  const bad = url.slice(0, -3) + 'abc';
  assert.equal((await serveR2(new Request(bad), e, path(bad))).status, 403);
  assert.equal((await serveR2(new Request(url, { method: 'PUT', body: 'x' }), e, path(url).replace('/get/', '/put/'))).status, 403);
  const old = bindingR2({ bucket: e.TALK_FILES, secret: e.R2_LINK_SECRET, base: e.PUBLIC, now: () => Date.now() - 2 * 3600_000 });
  const late = await old.getUrl('msg/f-1');
  assert.equal((await serveR2(new Request(late), e, path(late))).status, 403);
});
