// The whole chain: the hub's writes → the office's own copy code (server/src/talkrelay.js) → the same Talk at the office.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fakeSql } from './fake-sql.mjs';
import { HubCore } from '../src/core.js';
import { createTalkRelay, TALK_TABLES } from '../../server/src/talkrelay.js';

const DIR = { users: [{ id: 'u1', name: 'Haris', email: 'haris@e11.test', role: 'admin', active: true }, { id: 'u2', name: 'Lana', email: 'lana@e11.test', role: 'production', active: true }],
  projects: [{ id: 'p1', name: 'Client One' }], clients: [], meta: {}, flags: { u1: { super: true } }, see: { u1: ['p1'], u2: ['p1'] } };

test('the office’s copy, through its own code, equals the hub', async () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'hubcopy-')), file = path.join(d, 'talk.sqlite');
  new HubCore({ sql: fakeSql(file), dir: DIR });   // (the office's Talk database, made by Talk's own code)
  const ok = async () => new Response('{"ok":true}', { status: 200, headers: { 'content-type': 'application/json' } });
  const office = createTalkRelay({ dbFile: file, relayUrl: 'https://hub.test', store: { list: () => [], get: () => null }, access: {}, fetchImpl: ok });
  await office.load();   // (the switch-over: the hub takes the office's Talk — both empty here)
  const batches = [];
  const h = new HubCore({ sql: fakeSql(), dir: DIR, copy: (b) => batches.push(b) });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), b = h.who('lana@e11.test', 'phone-key-bbbbbbbbbbbb');
  const gid = h.act(a, { act: 'newGroup', client: 'p1', name: 'Chain', members: ['u2'] }).group.id;
  for (let i = 0; i < 20; i++) h.act(i % 2 ? b : a, { act: 'send', group: gid, text: 'm' + i });
  const s = h.sync(b, 0); h.ack(b, s.last); h.act(b, { act: 'react', group: gid, id: s.events.find((e) => e.type === 'msg').id, emoji: '👍' });
  h.act(a, { act: 'mute', group: gid, until: Date.now() + 3600_000 }); h.sweep();
  const r = office.copy(batches);
  assert.equal(r.ok, true); assert.equal(r.done, batches.length);
  const odb = fakeSql(file).db;
  for (const t of TALK_TABLES) assert.deepEqual(odb.prepare(`SELECT * FROM ${t} ORDER BY 1, 2`).all(), h.sql.db.prepare(`SELECT * FROM ${t} ORDER BY 1, 2`).all(), t);
  office.close();
});
