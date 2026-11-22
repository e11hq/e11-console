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
