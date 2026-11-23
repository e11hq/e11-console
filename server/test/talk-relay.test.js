// E11 Talk on Cloudflare — the office's side (talkrelay.js, TALK-CF-A): its key, who a phone is, the copy (in order, a
// gap → the hub's whole Talk), signatures refused when wrong, moving the office's Talk to the hub, what the hub is told.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { createServer } from '../src/server.js';

let clock = Date.parse('2026-11-22T06:00:00Z');
let app, base, dir;
const hub = crypto.generateKeyPairSync('ed25519');
const hubPub = hub.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64');
const seen = [];   // what the office sent the hub
let dumpTables = null;
let hubAnswer = null;   // how the hub answers an older app's request passed to it
const fakeFetch = async (url, o = {}) => {
  const p = new URL(url).pathname;
  seen.push({ p, body: o.body ? JSON.parse(o.body) : null, headers: o.headers || {} });
  const ok = (j) => new Response(JSON.stringify(j), { status: 200, headers: { 'content-type': 'application/json' } });
  if (p === '/hub/key') return ok({ ok: true, key: hubPub });
  if (p === '/office/load') return ok({ ok: true, n: 0 });
  if (p === '/office/dump') return ok({ ok: true, n: 7, tables: dumpTables });
  if (p.startsWith('/api/talk/')) return hubAnswer ? hubAnswer(p, o) : ok({ ok: true, fromHub: true });
  return ok({ ok: true });
};
const signed = (p, body, at = clock) => {
  const ts = String(at), t = JSON.stringify(body);
  const sig = crypto.sign(null, Buffer.from(`POST\n${p}\n${ts}\n${t}`), hub.privateKey).toString('base64');
  return { method: 'POST', body: t, headers: { 'content-type': 'application/json', 'x-e11-ts': ts, 'x-e11-sig': sig } };
};
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11relay-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false, birthdays: false, daily: false, scheduled: false, views: false, holidays: false, pruneInbox: false,
    talkRelayUrl: 'https://hub.test', talkRelayFetch: fakeFetch, talkRelayStart: false });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
  app.store.importAll({
    users: [{ id: 'u-adm', email: 'adm@x.com', role: 'admin', active: true, name: 'Haris' }, { id: 'u-des', email: 'des@x.com', role: 'production', active: true, name: 'Yousef' },
      { id: 'u-fr', email: 'fr@x.com', role: 'freelancer', active: true, name: 'Free', projectIds: ['p1'] }],
    clients: [{ id: 'c1', name: 'Northline', logo: 'Clients/c1/logo.png', folders: [] }],
    projects: [{ id: 'p1', name: 'Northline', color: '#3a7bd5', clientId: 'c1', order: 1, ams: [] }, { id: 'p2', name: 'Southgate', order: 2, ams: [] }],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const H = (who) => ({ 'X-Dev-Email': who + '@x.com', 'Content-Type': 'application/json' });
const post = (p, body, at) => fetch(base + p, signed(p, body, at));
const talkDb = () => new (require('node:sqlite').DatabaseSync)(path.join(dir, 'db', 'talk.sqlite'));
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);

test('the office’s key and who a phone is', async () => {
  const k = await (await fetch(base + '/api/talk/relay/key')).json();
  assert.equal(k.ok, true); assert.equal(Buffer.from(k.key, 'base64').length, 32);
  const w = await (await fetch(base + '/api/talk/relay/who', { headers: H('des') })).json();
  assert.deepEqual(w, { ok: true, email: 'des@x.com' });
});

test('nothing unsigned, wrongly signed or old is taken', async () => {
  assert.equal((await fetch(base + '/api/talk/relay/copy', { method: 'POST', body: '{}' })).status, 403);
  const other = crypto.generateKeyPairSync('ed25519');
  const t = JSON.stringify({ batches: [] }), ts = String(clock);
  const bad = crypto.sign(null, Buffer.from(`POST\n/api/talk/relay/copy\n${ts}\n${t}`), other.privateKey).toString('base64');
  assert.equal((await fetch(base + '/api/talk/relay/copy', { method: 'POST', body: t, headers: { 'x-e11-ts': ts, 'x-e11-sig': bad } })).status, 403);
  assert.equal((await post('/api/talk/relay/copy', { batches: [] }, clock - 10 * 60_000)).status, 403);
});

test('the copy is refused until the hub has the office’s Talk; moving it sends every table', async () => {
  const r = await post('/api/talk/relay/copy', { batches: [{ n: 1, stmts: [] }] });
  assert.equal(r.status, 409);
  // (a group made the old way, at the office, before the switch-over)
  await (await fetch(base + '/api/talk/state', { headers: H('adm') })).json();
  const g = await (await fetch(base + '/api/talk/act', { method: 'POST', headers: H('adm'), body: JSON.stringify({ act: 'newGroup', client: 'p1', name: 'Before', members: ['u-des'] }) })).json();
  assert.ok(g.ok);
  const res = await app.talkRelay().switchTo('hub');
  assert.equal(res.ok, true); assert.equal(res.mode, 'hub');
  const sent = seen.find((x) => x.p === '/office/load');
  assert.ok(sent.body.tables.groups.some((x) => x.name === 'Before'));
  assert.ok(sent.headers['x-e11-sig'], 'signed by the office');
});

test('the copy: run in order, one already here skipped, a gap → the hub’s whole Talk', async () => {
  const st = (k, v) => ['INSERT INTO opts (uid, key, val) VALUES (?, ?, ?) ON CONFLICT(uid, key) DO UPDATE SET val = excluded.val', ['u-des', k, v]];
  let r = await (await post('/api/talk/relay/copy', { batches: [{ n: 1, stmts: [st('a', 1)] }, { n: 2, stmts: [st('b', 2)] }] })).json();
  assert.deepEqual([r.ok, r.last, r.done], [true, 2, 2]);
  r = await (await post('/api/talk/relay/copy', { batches: [{ n: 2, stmts: [st('b', 99)] }] })).json();
  assert.equal(r.done, 0);
  const db = talkDb();
  assert.equal(db.prepare("SELECT val FROM opts WHERE uid = 'u-des' AND key = 'b'").get().val, 2, 'a batch already here isn’t run twice');
  // a gap: the hub's whole Talk taken instead
  dumpTables = { opts: [{ uid: 'u-des', key: 'whole', val: 7 }], groups: [] };
  r = await (await post('/api/talk/relay/copy', { batches: [{ n: 5, stmts: [st('c', 3)] }] })).json();
  assert.equal(r.gap, true);
  await new Promise((ok) => setTimeout(ok, 50));
  assert.ok(seen.some((x) => x.p === '/office/dump'));
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM opts').get().c, 1);
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM groups').get().c, 0);
  assert.equal(app.talkRelay().lastN(), 7);
  db.close();
});

test('what the hub is told: E11 Console’s people and clients, as Talk needs them', () => {
  const d = app.talkRelay().dir();
  assert.ok(d.users.some((u) => u.id === 'u-des' && u.email === 'des@x.com'));
  assert.deepEqual(d.flags['u-fr'], { free: true, super: false, office: false });
  assert.ok(d.flags['u-adm'].super);
  assert.deepEqual(d.see['u-fr'], ['p1'], 'a freelancer sees only their own client');
  assert.ok(d.clients.some((c) => c.id === 'c1' && c.logo));
  assert.ok('icons' in d, 'the occasion icons go to the hub too, as Talk had them from the office');
});

test('the hub asks for E11 Console’s people and clients itself', async () => {
  const r = await (await post('/api/talk/relay/dir', {})).json();
  assert.equal(r.ok, true); assert.ok(r.dir.users.some((u) => u.id === 'u-adm'));
  assert.equal((await fetch(base + '/api/talk/relay/dir', { method: 'POST', body: '{}' })).status, 403);
});

test('notifications and Console’s count, asked by the hub', async () => {
  assert.equal((await (await post('/api/talk/relay/push', { uid: 'u-des', p: { title: 'x', body: 'y' } })).json()).ok, true);
  assert.equal((await (await post('/api/talk/relay/unread', { uids: ['u-des'] })).json()).ok, true);
});

test('after the switch-over: an older app asking the office is passed to the hub; the office’s own Talk only reads', async () => {
  assert.equal(app.talkRelay().mode(), 'hub');
  const st = await (await fetch(base + '/api/talk/state', { headers: H('des') })).json();
  assert.equal(st.fromHub, true);
  const before = seen.filter((x) => x.p === '/api/talk/act').length;
  const r = await (await fetch(base + '/api/talk/act', { method: 'POST', headers: H('des'), body: JSON.stringify({ act: 'mute', group: 'g-x', until: 1 }) })).json();
  assert.equal(r.fromHub, true);
  const sent = seen.filter((x) => x.p === '/api/talk/act');
  assert.equal(sent.length, before + 1);
  assert.equal(sent[sent.length - 1].body.act, 'mute', 'the body went with it');
  assert.equal((await (await fetch(base + '/api/talk/relay/mode')).json()).mode, 'hub');
});

test('the hub refuses (a free limit): the office takes over and answers itself; then hands its whole Talk back', async () => {
  hubAnswer = async () => new Response('error code: 1027', { status: 429 });
  const st = await (await fetch(base + '/api/talk/state', { headers: H('adm') })).json();
  assert.equal(st.ok, true); assert.ok(!st.fromHub, 'answered by the office');
  assert.equal(app.talkRelay().mode(), 'takeover');
  // (the office writes again while it has Talk)
  const g = await (await fetch(base + '/api/talk/act', { method: 'POST', headers: H('adm'), body: JSON.stringify({ act: 'newGroup', client: 'p1', name: 'During', members: [] }) })).json();
  assert.ok(g.ok, JSON.stringify(g));
  assert.equal((await post('/api/talk/relay/copy', { batches: [{ n: 8, stmts: [] }] })).status, 409, 'the hub’s copy waits while the office has Talk');
  hubAnswer = null;
  const loads = seen.filter((x) => x.p === '/office/load').length;
  assert.equal(await app.talkRelay().handBack(), true);
  assert.equal(app.talkRelay().mode(), 'hub');
  const last = seen.filter((x) => x.p === '/office/load');
  assert.equal(last.length, loads + 1);
  assert.ok(last[last.length - 1].body.tables.groups.some((x) => x.name === 'During'), 'what the office did goes back with it');
});

test('the switch-over is the owner’s only', async () => {
  assert.equal((await fetch(base + '/api/talk/relay/switch', { method: 'POST', headers: H('des'), body: JSON.stringify({ to: 'office' }) })).status, 403);
  const s = await (await fetch(base + '/api/talk/relay/status', { headers: H('adm') })).json();
  assert.equal(s.mode, 'hub');
  dumpTables = { groups: [] };
  const back = await (await fetch(base + '/api/talk/relay/switch', { method: 'POST', headers: H('adm'), body: JSON.stringify({ to: 'office' }) })).json();
  assert.equal(back.mode, 'office');
  const st = await (await fetch(base + '/api/talk/state', { headers: H('adm') })).json();
  assert.ok(!st.fromHub, 'the office again');
});
