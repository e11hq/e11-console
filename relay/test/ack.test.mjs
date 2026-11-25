// An ack frees only what it frees (Haris 2026-11-25 — the whole clean-up ran on every ack: ~10,300 rows read each on
// Cloudflare): a message that has reached everyone leaves at once; nothing else is cleaned by an ack.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fakeSql } from './fake-sql.mjs';
import { HubCore } from '../src/core.js';

const DIR = { users: [{ id: 'u1', name: 'Haris', email: 'haris@e11.test', role: 'admin', active: true }, { id: 'u2', name: 'Lana', email: 'lana@e11.test', role: 'admin', active: true }],
  projects: [{ id: 'p1', name: 'Client One' }], clients: [], meta: {}, flags: { u1: { super: true } }, see: { u1: ['p1'], u2: ['p1'] } };

test('an ack: a message everyone has leaves the server at once; one still waiting for someone stays; no clean-up beyond it', () => {
  const sql = fakeSql();
  const h = new HubCore({ sql, dir: DIR });
  const a = h.who('haris@e11.test', 'phone-key-aaaaaaaaaaaa'), b = h.who('lana@e11.test', 'phone-key-bbbbbbbbbbbb');
  const gid = h.act(a, { act: 'newGroup', client: 'p1', name: 'Day', members: ['u2'] }).group.id;
  h.act(a, { act: 'send', group: gid, text: 'Hello' });
  const count = () => sql.db.prepare('SELECT COUNT(*) AS c FROM events').get().c;
  // (an old upload never sent: the clean-up's to let go, not an ack's)
  sql.db.prepare("INSERT INTO files (id, by, name, size, done, at) VALUES ('old-upload', 'u1', 'x.jpg', 1, 1, 0)").run();
  const before = count();
  const sb = h.sync(b, 0); h.ack(b, sb.last);
  const mid = count();
  assert.ok(mid < before + 5, 'Lana’s ack: what only she waited for is gone');
  // (each ack gives the others "got" — both phones pick everything up until nothing waits)
  for (let i = 0; i < 4; i++) for (const w of [a, b]) { const s = h.sync(w, 0); if (s.last) h.ack(w, s.last); }
  assert.equal(sql.db.prepare('SELECT COUNT(*) AS c FROM waiting').get().c, 0, 'nothing waits');
  assert.equal(count(), 0, 'every event everyone has: gone at once');
  assert.ok(sql.db.prepare("SELECT 1 FROM files WHERE id = 'old-upload'").get(), 'an ack cleans nothing else');
});
