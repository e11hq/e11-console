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
  const st2 = await (await hub.fetch(new Request('https://hub.test/hub/status'))).json();
  assert.equal(st2.callsMs[0].via, 'line');
});
