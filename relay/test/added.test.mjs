// E11 Talk on its own (Haris 2026-11-25 10:45 / 11:11 — "talk should not be dependant on what to show and what not"):
// being in a group is all it takes to see it under its client, whatever someone is on in E11 Console; the team (not
// freelancers) starts a group under any active client; a client made inactive keeps its groups for the people in them;
// people added are told "Haris added you to …".
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fakeSql } from './fake-sql.mjs';
import { HubCore } from '../src/core.js';

const dir = (inactive = false) => ({ users: [{ id: 'u1', name: 'Haris', email: 'haris@e11.test', role: 'admin', active: true }, { id: 'u2', name: 'Yousef', email: 'yousef@e11.test', role: 'production', active: true },
  { id: 'u3', name: 'Lana', email: 'lana@e11.test', role: 'production', active: true }, { id: 'u4', name: 'Free', email: 'free@e11.test', role: 'freelancer', active: true, projectIds: ['p1'] }],
  projects: [{ id: 'p1', name: 'Client One' }, { id: 'p2', name: 'Client Two', color: '#123456', ...(inactive ? { inactive: true } : {}) }], clients: [], meta: {}, flags: { u1: { super: true }, u4: { free: true } },
  see: { u1: ['p1', 'p2'], u2: ['p1'], u3: ['p1'], u4: ['p1'] } });
const apns = (sent) => ({ enabled: () => true, sendTo: async (uid, p) => { sent.push([uid, p]); }, wake: async () => {} });

test('a group under a client they aren’t on in E11 Console: shown under it; they’re told they were added', () => {
  const sent = [];
  const h = new HubCore({ sql: fakeSql(), dir: dir(), apns: apns(sent) });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), y = h.who('yousef@e11.test', 'phone-key-bbbbbbbbbbbb'), l = h.who('lana@e11.test', 'phone-key-cccccccccccc');
  const g = h.act(a, { act: 'newGroup', client: 'p2', name: 'Shoot day', members: ['u2'] }).group;
  const s = h.state(y);
  assert.ok(s.groups.some((x) => x.id === g.id));
  assert.deepEqual(s.clients.find((c) => c.id === 'p2'), { id: 'p2', name: 'Client Two', color: '#123456', logo: null });
  assert.equal(s.clients.filter((c) => c.id === 'p2').length, 1, 'once');
  assert.deepEqual(sent.map(([u, p]) => [u, p.body, p.groupId]), [['u2', 'Haris added you to Shoot day', g.id]], 'the maker isn’t told');
  sent.length = 0;
  assert.ok(h.act(a, { act: 'addPeople', group: g.id, ids: ['u3'] }).ok);
  assert.deepEqual(sent.map(([u, p]) => [u, p.body]), [['u3', 'Haris added you to Shoot day']]);
  assert.ok(h.state(l).groups.some((x) => x.id === g.id));
});

test('the team starts a group under any active client; freelancers still can’t', () => {
  const h = new HubCore({ sql: fakeSql(), dir: dir() });
  const y = h.who('yousef@e11.test', 'phone-key-bbbbbbbbbbbb'), f = h.who('free@e11.test', 'phone-key-dddddddddddd');
  assert.ok(h.state(y).clients.some((c) => c.id === 'p2'), 'every active client offered');
  assert.equal(h.act(y, { act: 'newGroup', client: 'p2', name: 'Mine', members: [] }).ok, true);
  assert.equal(h.act(f, { act: 'newGroup', client: 'p1', name: 'X', members: [] }).ok, false);
  assert.ok(!h.state(f).clients.some((c) => c.id === 'p2'), 'a freelancer: their own clients');
});

test('a client made inactive keeps its groups for the people in them; no new group under it', () => {
  const sql = fakeSql();
  const h = new HubCore({ sql, dir: dir() });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa');
  const gid = h.act(a, { act: 'newGroup', client: 'p2', name: 'Old work', members: ['u2'] }).group.id;
  h.setDir(dir(true));
  const y = h.who('yousef@e11.test', 'phone-key-bbbbbbbbbbbb');
  const s = h.state(y);
  assert.ok(s.groups.some((x) => x.id === gid));
  assert.ok(s.clients.some((c) => c.id === 'p2'), 'its client shown for the group');
  assert.equal(h.act(y, { act: 'send', group: gid, text: 'still here' }).ok, true);
  assert.equal(h.act(a, { act: 'newGroup', client: 'p2', name: 'New', members: [] }).ok, false);
});
