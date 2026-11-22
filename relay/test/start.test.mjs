import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fakeSql } from './fake-sql.mjs';
import { fakeBucket } from './fake-bucket.mjs';

// the hub started as Cloudflare starts it — its constructor, its status page, a call down the line
test('the hub starts, answers its status, and takes a call down the live line', async () => {
  globalThis.WebSocketRequestResponsePair = class { constructor(a, b) { this.a = a; this.b = b; } };
  const { TalkHub } = await import('../src/hub.js');
  let ready;
  const ctx = {
    storage: { sql: fakeSql(), getAlarm: async () => null, setAlarm: async () => {} },
    blockConcurrencyWhile: (fn) => { ready = fn(); return ready; },
    getWebSockets: () => [], setWebSocketAutoResponse: () => {}, waitUntil: () => {}, acceptWebSocket: () => {},
  };
  const env = { OFFICE: '', OFFICE_LINK: '', HUB_NAME: 'test', PUBLIC: 'https://hub.test', TALK_FILES: fakeBucket(), R2_LINK_SECRET: 'x' };
  const hub = new TalkHub(ctx, env);
  await ready;
  hub.core.setDir({ users: [{ id: 'u1', name: 'Haris', email: 'haris@e11.test', role: 'admin', active: true }], projects: [{ id: 'p1', name: 'C' }], clients: [], meta: {}, flags: { u1: { super: true } }, see: { u1: ['p1'] } });
  hub.colo = 'TST';
  const st = await (await hub.fetch(new Request('https://hub.test/hub/status'))).json();
  assert.equal(st.ok, true, JSON.stringify(st)); assert.equal(st.people, 1);
  const sent = [];
  const ws = { deserializeAttachment: () => ({ email: 'haris@e11.test', device: 'phone-key-aaaaaaaaaaaa', dev: 'x' }), send: (s) => sent.push(JSON.parse(s)), close: () => {} };
  hub.officeHas = async () => false;
  await hub.webSocketMessage(ws, JSON.stringify({ id: 7, call: 'state', body: {} }));
  assert.equal(sent[0].id, 7); assert.equal(sent[0].r.ok, true, JSON.stringify(sent[0]));
});

test('a notification goes from Cloudflare straight to Apple; the office only when Apple can’t be reached', async () => {
  globalThis.WebSocketRequestResponsePair = class {};
  const { TalkHub } = await import('../src/hub.js');
  let ready;
  const ctx = { storage: { sql: fakeSql(), getAlarm: async () => 1, setAlarm: async () => {} }, blockConcurrencyWhile: (fn) => { ready = fn(); return ready; },
    getWebSockets: () => [], setWebSocketAutoResponse: () => {}, waitUntil: () => {}, acceptWebSocket: () => {} };
  const hub = new TalkHub(ctx, { OFFICE: 'https://office.test', OFFICE_LINK: 'https://office.test', PUBLIC: 'https://hub.test', TALK_FILES: fakeBucket(), R2_LINK_SECRET: 'x' });
  await ready;
  hub.core.setDir({ users: [{ id: 'u1', name: 'Haris', email: 'haris@e11.test', role: 'admin', active: true }, { id: 'u2', name: 'Lana', email: 'lana@e11.test', role: 'production', active: true }],
    projects: [{ id: 'p1', name: 'C' }], clients: [], meta: {}, flags: { u1: { super: true } }, see: { u1: ['p1'], u2: ['p1'] } });
  const toOffice = [], toApple = [];
  hub.later = async (path, b) => { if (path === '/api/talk/relay/push') toOffice.push(b.uid); return true; };
  let answer = { status: 200 };
  let lastMsg = null;
  hub.apple = { on: true, sendTo: async (uid, p) => { toApple.push(uid); lastMsg = p; return { sent: answer.status === 200 ? 1 : 0, results: [answer] }; }, wake: async () => ({ sent: 1, results: [{ status: 200 }] }) };
  const a = hub.core.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa');
  const gid = hub.core.act(a, { act: 'newGroup', client: 'p1', name: 'N', members: ['u2'] }).group.id;
  const settle = () => new Promise((r) => setTimeout(r, 30));
  hub.core.act(a, { act: 'send', group: gid, text: 'One' }); await settle();
  assert.ok(toApple.includes('u2'), 'Apple asked: ' + JSON.stringify(toApple));
  assert.ok(lastMsg.m && lastMsg.m.type === 'msg' && lastMsg.m.text === 'One' && lastMsg.m.group === gid && lastMsg.m.seq > 0, 'the message rides along: ' + JSON.stringify(lastMsg.m)); assert.deepEqual(toOffice, [], 'the office not asked');
  answer = { status: 0, reason: 'unreachable' };
  hub.core.act(a, { act: 'send', group: gid, text: 'Two' }); await settle();
  assert.ok(toOffice.includes('u2'), 'Apple not reached: the office sends it');
  toOffice.length = 0; answer = { status: 410, reason: 'Unregistered' };
  hub.core.act(a, { act: 'send', group: gid, text: 'Three' }); await settle();
  assert.deepEqual(toOffice, [], 'an address Apple says is gone: not sent again by the office');
});

test('a voice note and its message in one call (r2/one); a file fetched in one trip through the front door', async () => {
  globalThis.WebSocketRequestResponsePair = class { constructor(a, b) { this.a = a; this.b = b; } };
  const { TalkHub } = await import('../src/hub.js');
  const { serveR2 } = await import('../src/r2.js');
  let ready;
  const ctx = {
    storage: { sql: fakeSql(), getAlarm: async () => null, setAlarm: async () => {} },
    blockConcurrencyWhile: (fn) => { ready = fn(); return ready; },
    getWebSockets: () => [], setWebSocketAutoResponse: () => {}, waitUntil: () => {}, acceptWebSocket: () => {},
  };
  const bucket = fakeBucket();
  const env = { OFFICE: '', OFFICE_LINK: '', HUB_NAME: 'test', PUBLIC: 'https://hub.test', TALK_FILES: bucket, R2_LINK_SECRET: 'x-secret-123' };
  const hub = new TalkHub(ctx, env);
  await ready;
  hub.core.setDir({ users: [{ id: 'u1', name: 'Haris', email: 'haris@e11.test', role: 'admin', active: true }, { id: 'u2', name: 'Lana', email: 'lana@e11.test', role: 'production', active: true }],
    projects: [{ id: 'p1', name: 'C' }], clients: [], meta: {}, flags: { u1: { super: true } }, see: { u1: ['p1'], u2: ['p1'] } });
  hub.officeHas = async () => false;
  const a = hub.core.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), b = hub.core.who('lana@e11.test', 'phone-key-bbbbbbbbbbbb');
  const gid = hub.core.act(a, { act: 'newGroup', client: 'p1', name: 'Voice', members: ['u2'] }).group.id;
  const bytes = new Uint8Array(3000).fill(9);
  const data = btoa(String.fromCharCode(...bytes));
  const r = await hub.call(a, 'r2/one', { name: 'Voice message.m4a', data, send: { group: gid, text: '', cid: 'c-v', file: { id: '', kind: 'voice', secs: 2, key: 'A'.repeat(43) + '=' } } });
  assert.equal(r.ok, true, JSON.stringify(r)); assert.ok(r.id && r.sent && r.sent.ok, JSON.stringify(r));
  assert.equal(bucket.objs.get('msg/' + r.id).byteLength, 3000);
  const ev = hub.core.sync(b, 0).events.find((x) => x.type === 'msg' && x.file && x.file.kind === 'voice');
  assert.ok(ev && ev.file.id === r.id, 'Lana has it, with its file: ' + JSON.stringify(ev));
  // too big, or no message: not this way (the phone goes the usual way)
  assert.equal((await hub.call(a, 'r2/one', { name: 'x', data })).ok, false);
  // fetched through the front door: the hub's R2 address followed there — the bytes in one answer
  const f = hub.core.fileFor(b, r.id);
  const loc = await hub.core.talk.r2.getUrl(hub.core.talk.r2Key(f));
  const got = await serveR2(new Request(loc), env, new URL(loc).pathname);
  assert.equal(got.status, 200); assert.equal((await got.arrayBuffer()).byteLength, 3000);
});

test('the front door hands over a file itself when the hub points it at R2 — and passes anything else through', async () => {
  globalThis.WebSocketRequestResponsePair = class { constructor(a, b) { this.a = a; this.b = b; } };
  const front = (await import('../src/index.js')).default;
  const { bindingR2 } = await import('../src/r2.js');
  const bucket = fakeBucket(); bucket.objs.set('msg/f-1', new Uint8Array(1234).fill(1));
  const r2 = bindingR2({ bucket, secret: 's-123456', base: 'https://talk.test' });
  const loc = await r2.getUrl('msg/f-1');
  let answer = () => new Response(null, { status: 302, headers: { Location: loc } });
  const env = { TALK_FILES: bucket, R2_LINK_SECRET: 's-123456', HUB: { idFromName: () => 'x', get: () => ({ fetch: async () => answer() }) } };
  const r = await front.fetch(new Request('https://talk.test/api/talk/file/f-1?r2=1&pieces=1', { headers: { authorization: 'Bearer t' } }), env, {});
  assert.equal(r.status, 200); assert.equal((await r.arrayBuffer()).byteLength, 1234);
  const part = await front.fetch(new Request('https://talk.test/api/talk/file/f-1', { headers: { range: 'bytes=0-9' } }), env, {});
  assert.equal(part.status, 206);
  answer = () => new Response('{"ok":false}', { status: 404 });
  assert.equal((await front.fetch(new Request('https://talk.test/api/talk/file/f-2'), env, {})).status, 404);
  answer = () => new Response(null, { status: 302, headers: { Location: 'https://elsewhere.test/x' } });
  assert.equal((await front.fetch(new Request('https://talk.test/api/talk/file/f-3'), env, {})).status, 302);
});
