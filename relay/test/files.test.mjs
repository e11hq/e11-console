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

test('a file’s "it’s all there" with its message — one call sends both', async () => {
  const bucket = fakeBucket(), e = env(bucket);
  const h = new HubCore({ sql: fakeSql(), dir: DIR, r2: bindingR2({ bucket, secret: e.R2_LINK_SECRET, base: e.PUBLIC }) });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), b = h.who('lana@e11.test', 'phone-key-bbbbbbbbbbbb');
  const gid = h.act(a, { act: 'newGroup', client: 'p1', name: 'One call', members: ['u2'] }).group.id;
  const bytes = new Uint8Array(500).fill(3);
  const s = await h.r2Start(a, { name: 'p.heic', size: bytes.byteLength });
  await serveR2(new Request(s.put, { method: 'PUT', body: bytes }), e, path(s.put));
  const d = await h.r2Done(a, { id: s.id, send: { group: gid, text: 'Look', cid: 'c-1', file: { id: s.id, kind: 'photo', key: 'A'.repeat(43) + '=' } } });
  assert.equal(d.ok, true, JSON.stringify(d));
  assert.ok(d.sent && d.sent.ok && d.sent.id, 'the message too: ' + JSON.stringify(d.sent));
  assert.ok(h.sync(b, 0).events.some((x) => x.type === 'msg' && x.text === 'Look'), 'Lana has it');
  const plain = await h.r2Done(a, { id: s.id }); assert.equal(plain.sent, undefined, 'without one: as before');
});

test('a piece is written into storage as it arrives (a stream of the length the phone gave)', async () => {
  globalThis.FixedLengthStream = class { constructor(n) { const t = new TransformStream(); this.readable = t.readable; this.writable = t.writable; this.n = n; } };
  try {
    const bucket = fakeBucket(), e = env(bucket);
    const h = new HubCore({ sql: fakeSql(), dir: DIR, r2: bindingR2({ bucket, secret: e.R2_LINK_SECRET, base: e.PUBLIC }) });
    const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa');
    const s = await h.r2Start(a, { name: 'v.mp4', size: 700 });
    const r = await serveR2(new Request(s.put, { method: 'PUT', body: new Uint8Array(700).fill(9), headers: { 'content-length': '700' } }), e, path(s.put));
    assert.equal(r.status, 200);
    assert.equal(bucket.objs.get('msg/' + s.id).byteLength, 700);
    const big = await serveR2(new Request(s.put, { method: 'PUT', body: new Uint8Array(1), headers: { 'content-length': String(PART + 1) } }), e, path(s.put));
    assert.equal(big.status, 413);
  } finally { delete globalThis.FixedLengthStream; }
});

test('an upload let go by the phone goes at once; one in a message stays; unsent ones go after a day', async () => {
  let t = Date.parse('2026-11-22T08:00:00Z');
  const bucket = fakeBucket(), e = env(bucket);
  const h = new HubCore({ sql: fakeSql(), dir: DIR, now: () => t, r2: bindingR2({ bucket, secret: e.R2_LINK_SECRET, base: e.PUBLIC }) });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), b = h.who('lana@e11.test', 'phone-key-bbbbbbbbbbbb');
  const gid = h.act(a, { act: 'newGroup', client: 'p1', name: 'Drop', members: ['u2'] }).group.id;
  const up = async () => { const s = await h.r2Start(a, { name: 'p.heic', size: 10 }); await serveR2(new Request(s.put, { method: 'PUT', body: new Uint8Array(10) }), e, path(s.put)); await h.r2Done(a, { id: s.id }); return s.id; };
  const gone = await up();
  assert.ok(bucket.objs.has('msg/' + gone));
  assert.equal((await h.r2Drop(b, { id: gone })).ok, true); assert.ok(bucket.objs.has('msg/' + gone), 'not someone else’s to let go');
  await h.r2Drop(a, { id: gone }); await new Promise((r) => setTimeout(r, 10));
  assert.ok(!bucket.objs.has('msg/' + gone), 'let go at once');
  const sent = await up();
  h.act(a, { act: 'send', group: gid, text: '', file: { id: sent, kind: 'photo', key: 'A'.repeat(43) + '=' } });
  assert.equal((await h.r2Drop(a, { id: sent })).kept, true); assert.ok(bucket.objs.has('msg/' + sent), 'in a message: stays');
  const left = await up();
  t += 25 * 3600_000; h.sweep(); await new Promise((r) => setTimeout(r, 10));
  assert.ok(!bucket.objs.has('msg/' + left), 'never sent: gone after a day');
  assert.ok(bucket.objs.has('msg/' + sent), 'the sent one: by its own rules');
});

test('a group deleted: its files go at once — one also sent in another group stays', async () => {
  const bucket = fakeBucket(), e = env(bucket);
  const h = new HubCore({ sql: fakeSql(), dir: DIR, r2: bindingR2({ bucket, secret: e.R2_LINK_SECRET, base: e.PUBLIC }) });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa');
  const g1 = h.act(a, { act: 'newGroup', client: 'p1', name: 'One', members: ['u2'] }).group.id;
  const g2 = h.act(a, { act: 'newGroup', client: 'p1', name: 'Two', members: ['u2'] }).group.id;
  const up = async () => { const s = await h.r2Start(a, { name: 'p.heic', size: 10 }); await serveR2(new Request(s.put, { method: 'PUT', body: new Uint8Array(10) }), e, path(s.put)); await h.r2Done(a, { id: s.id }); return s.id; };
  const only = await up(), both = await up();
  const key = 'A'.repeat(43) + '=';
  h.act(a, { act: 'send', group: g1, text: '', file: { id: only, kind: 'photo', key } });
  h.act(a, { act: 'send', group: g1, text: '', file: { id: both, kind: 'photo', key } });
  h.act(a, { act: 'send', group: g2, text: '', file: { id: both, kind: 'photo', key } });
  assert.equal(h.act(a, { act: 'deleteGroup', group: g1 }).ok, true);
  await new Promise((r) => setTimeout(r, 10));
  assert.ok(!bucket.objs.has('msg/' + only), 'its own file: gone at once');
  assert.ok(bucket.objs.has('msg/' + both), 'also in another group: stays');
});

test('deleted for everyone: its file goes at once, even before the other phone picked it up; its notification replaced quietly', async () => {
  const bucket = fakeBucket(), e = env(bucket), sent = [];
  const apns = { enabled: () => true, sendTo: async (uid, p) => { sent.push([uid, p]); }, wake: async () => {} };
  const h = new HubCore({ sql: fakeSql(), dir: DIR, apns, r2: bindingR2({ bucket, secret: e.R2_LINK_SECRET, base: e.PUBLIC }) });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa');
  const gid = h.act(a, { act: 'newGroup', client: 'p1', name: 'Del', members: ['u2'] }).group.id;
  const s = await h.r2Start(a, { name: 'p.heic', size: 10 }); await serveR2(new Request(s.put, { method: 'PUT', body: new Uint8Array(10) }), e, path(s.put)); await h.r2Done(a, { id: s.id });
  const m = h.act(a, { act: 'send', group: gid, text: '', file: { id: s.id, kind: 'photo', key: 'A'.repeat(43) + '=' } });
  const first = sent.find(([u, p]) => u === 'u2' && p.kind === 'talk');
  assert.equal(first[1].collapse, m.id, 'the notification carries its message id to be replaced');
  assert.equal(h.act(a, { act: 'del', msg: m.id }).ok, true);
  await new Promise((r) => setTimeout(r, 10));
  assert.ok(!bucket.objs.has('msg/' + s.id), 'gone at once');
  const rep = sent.find(([u, p]) => u === 'u2' && p.kind === 'talkdel');
  assert.ok(rep && rep[1].collapse === m.id && rep[1].quiet === true && rep[1].body === 'This message was deleted');
});
