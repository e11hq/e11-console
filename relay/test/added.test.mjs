// Added to a group under a client they aren't on in E11 Console: the client shows for them in Talk (name and logo), and
// they're told "Haris added you to …" (Haris 2026-11-25 10:45 — Yousef couldn't see a group he was in).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fakeSql } from './fake-sql.mjs';
import { HubCore } from '../src/core.js';

const DIR = { users: [{ id: 'u1', name: 'Haris', email: 'haris@e11.test', role: 'admin', active: true }, { id: 'u2', name: 'Yousef', email: 'yousef@e11.test', role: 'production', active: true },
  { id: 'u3', name: 'Lana', email: 'lana@e11.test', role: 'production', active: true }],
  projects: [{ id: 'p1', name: 'Client One' }, { id: 'p2', name: 'Client Two', color: '#123456' }], clients: [], meta: {}, flags: { u1: { super: true } },
  see: { u1: ['p1', 'p2'], u2: ['p1'], u3: ['p1'] } };

test('a group under a client they aren’t on: the client shows for them, and they’re told they were added', () => {
  const sent = [];
  const h = new HubCore({ sql: fakeSql(), dir: DIR, apns: { enabled: () => true, sendTo: async (uid, p) => { sent.push([uid, p]); }, wake: async () => {} } });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), y = h.who('yousef@e11.test', 'phone-key-bbbbbbbbbbbb'), l = h.who('lana@e11.test', 'phone-key-cccccccccccc');
  assert.ok(!h.state(y).clients.some((c) => c.id === 'p2'), 'not on Client Two: not shown before');
  const g = h.act(a, { act: 'newGroup', client: 'p2', name: 'Shoot day', members: ['u2'] }).group;
  const s = h.state(y);
  assert.ok(s.groups.some((x) => x.id === g.id));
  assert.deepEqual(s.clients.find((c) => c.id === 'p2'), { id: 'p2', name: 'Client Two', color: '#123456', logo: null });
  assert.equal(s.clients.filter((c) => c.id === 'p1').length, 1, 'their own client once');
  assert.deepEqual(sent.map(([u, p]) => [u, p.body, p.groupId]), [['u2', 'Haris added you to Shoot day', g.id]], 'the maker isn’t told');
  // added later: told too; the one adding isn't
  sent.length = 0;
  assert.ok(h.act(a, { act: 'addPeople', group: g.id, ids: ['u3'] }).ok);
  assert.deepEqual(sent.map(([u, p]) => [u, p.body]), [['u3', 'Haris added you to Shoot day']]);
  assert.ok(h.state(l).clients.some((c) => c.id === 'p2'));
  // not in it: still not shown
  h.act(a, { act: 'removePerson', group: g.id, id: 'u3' });
  assert.ok(!h.state(l).clients.some((c) => c.id === 'p2'));
});
