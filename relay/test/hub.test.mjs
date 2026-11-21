import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { fakeSql } from './fake-sql.mjs';
import { HubCore } from '../src/core.js';

const DIR = {
  users: [{ id: 'u1', name: 'Haris', email: 'haris@e11.test', role: 'admin', active: true }, { id: 'u2', name: 'Lana', email: 'lana@e11.test', role: 'production', active: true }, { id: 'u3', name: 'Free', email: 'free@e11.test', role: 'freelancer', active: true }],
  projects: [{ id: 'p1', name: 'Client One', color: '#f00' }],
  clients: [], meta: {},
  flags: { u1: { super: true }, u3: { free: true } },
  see: { u1: ['p1'], u2: ['p1'] },
};
let t0 = Date.parse('2026-11-22T06:00:00Z');
const now = () => t0;
function hub() { const batches = []; const h = new HubCore({ sql: fakeSql(), dir: DIR, copy: (b) => batches.push(b), now }); return { h, batches }; }

test('the hub runs Talk: a group, a message, sync and ack, ✓✓', () => {
  const { h } = hub();
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), b = h.who('lana@e11.test', 'phone-key-bbbbbbbbbbbb');
  assert.ok(a && b && a.dev.id.startsWith('ph-'));
  const st = h.state(a); assert.equal(st.ok, true); assert.equal(st.clients.length, 1);
  const g = h.act(a, { act: 'newGroup', client: 'p1', name: 'Shoot', members: ['u2'] });
  assert.equal(g.ok, true, JSON.stringify(g));
  const gid = g.group.id;
  const m = h.act(a, { act: 'send', group: gid, text: 'Hello' });
  assert.equal(m.ok, true, JSON.stringify(m));
  const s = h.sync(b, 0); assert.ok(s.events.some((e) => e.type === 'msg' && e.text === 'Hello'), JSON.stringify(s));
  assert.equal(h.ack(b, s.last).ok, true);
  const sa = h.sync(a, 0); assert.ok(sa.events.some((e) => e.type === 'got'), 'the sender gets ✓✓');
});

test('the live line gets the message at once', () => {
  const { h } = hub();
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), b = h.who('lana@e11.test', 'phone-key-bbbbbbbbbbbb');
  const lines = []; h.listen(b.dev.id, (s) => lines.push(s));
  const gid = h.act(a, { act: 'newGroup', client: 'p1', name: 'Live', members: ['u2'] }).group.id;
  h.act(a, { act: 'send', group: gid, text: 'Now' });
  assert.ok(lines.some((l) => l.includes('"text":"Now"')), lines.join('|'));
});

test('a freelancer can’t make a group; someone outside can’t send', () => {
  const { h } = hub();
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), f = h.who('free@e11.test', 'phone-key-ffffffffffff');
  assert.equal(h.act(f, { act: 'newGroup', client: 'p1', name: 'X', members: [] }).ok, false);
  const gid = h.act(a, { act: 'newGroup', client: 'p1', name: 'Y', members: ['u2'] }).group.id;
  assert.equal(h.act(f, { act: 'send', group: gid, text: 'hi' }).ok, false);
});

test('the office’s copy: running the same statements in order gives the same Talk', () => {
  const { h, batches } = hub();
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), b = h.who('lana@e11.test', 'phone-key-bbbbbbbbbbbb');
  const gid = h.act(a, { act: 'newGroup', client: 'p1', name: 'Copy', members: ['u2'] }).group.id;
  h.act(a, { act: 'send', group: gid, text: 'One' }); h.act(b, { act: 'send', group: gid, text: 'Two' });
  const s = h.sync(b, 0); h.ack(b, s.last); h.act(b, { act: 'read', group: gid, upto: 'x' });
  // the office: a fresh Talk database (the office's own schema, made by Talk's code) + every batch, in order
  const office = new HubCore({ sql: fakeSql(), dir: DIR, copy: () => {}, now }).sql.db;
  for (const bt of batches) for (const [q, v] of bt.stmts) office.prepare(q).run(...v);
  for (const tbl of ['groups', 'members', 'events', 'waiting', 'sent', 'phones']) {
    const x = h.sql.db.prepare(`SELECT * FROM ${tbl} ORDER BY 1, 2`).all(), y = office.prepare(`SELECT * FROM ${tbl} ORDER BY 1, 2`).all();
    assert.deepEqual(y, x, tbl);
  }
  assert.deepEqual(batches.map((x) => x.n), batches.map((_, i) => i + 1));
});

test('reads write nothing to the copy', () => {
  const { h, batches } = hub();
  const a = h.who('haris@e11.test');
  const before = batches.length; h.state(a); h.state(a);
  assert.equal(batches.length, before);
});
