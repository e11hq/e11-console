// The App Review copy (review.js + demo.js): its own password sign-in, only when REVIEW_PASSWORD is set; nothing but
// made-up data (no real staff, clients or emails anywhere — data or files); fresh again every night from 3:00 Dubai
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { resetDue } from '../src/review.js';

const PW = 'apple-review-2026!';
const OFF = { digest: false, holidays: false, occRemind: false, birthdays: false, daily: false, scheduled: false, views: false, pruneInbox: false };
let app, dir, base;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-review-'));
  app = createServer({ dataDir: dir, webDir: new URL('../../web', import.meta.url).pathname, version: '1.9.4', reviewPassword: PW, adminEmail: 'haris@e11-digital.com', ...OFF });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

const signIn = (email, password, ip = '1.1.1.1') => fetch(base + '/review/sign-in', { method: 'POST', redirect: 'manual', headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'CF-Connecting-IP': ip }, body: new URLSearchParams({ email, password }) });
const cookieOf = (r) => String(r.headers.get('set-cookie') || '').split(';')[0];

// every real name, brand and address the sample is built from
const REAL = ['nadia', 'khashem', 'areej', 'masri', 'lana', 'ramli', 'carine', 'jaoude', 'raza', 'jabra', 'maab', 'osama', 'zaahir', 'zahir', 'hamid', 'hameed', 'aishwarya', 'sanjay',
  'maria', 'amelia', 'aouidat', 'hajj', 'yousef', 'hwij', 'arsal', 'haris', 'sharif', 'muhammad', 'ford', 'lincoln', 'bronco', 'kia', 'deepal', 'tayer', 'alain', 'hre', 'korea',
  'korea360', 'cpt', 'asv', 'gebriel', 'bizreh', 'forta', 'nakheel', 'jebel', 'dragon city', 'e11-digital', 'gmail', 'clickup', 'automechanika', 'moon'];
const realIn = (s) => REAL.filter((w) => new RegExp(`(?<![a-z])${w}(?![a-z])`, 'i').test(s.replace(/_/g, ' ')));

test('the demo is loaded on its own at start: made-up people, clients and work', () => {
  const users = app.store.list('users'), tasks = app.store.list('tasks'), projects = app.store.list('projects');
  assert.ok(users.length >= 15 && tasks.length >= 30 && projects.length >= 12, `${users.length} people, ${tasks.length} tasks`);
  const me = app.store.get('users', 'u-review');
  assert.equal(me.name, 'Alex Morgan'); assert.equal(me.email, 'review@e11hq.com'); assert.equal(me.role, 'admin');
  assert.ok(projects.some((p) => p.name === 'Northline Motors'));
  assert.ok(users.find((u) => u.name === 'Claire Dubois').avatar, 'drawn portraits');
});

test('nothing real anywhere: the data, file names and the files that hold text', () => {
  const snap = JSON.stringify(app.store.snapshot().data);
  assert.deepEqual(realIn(snap), []);
  const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]));
  const files = walk(path.join(dir, 'files'));
  assert.ok(files.length > 40);
  assert.deepEqual(files.map((f) => path.relative(dir, f)).filter((f) => realIn(f).length), []);
  for (const f of files.filter((x) => /\.(svg|txt|json)$/.test(x))) assert.deepEqual(realIn(fs.readFileSync(f, 'utf8')), [], f);
  // every file the data points at is there
  const paths = [...snap.matchAll(/"path":"([^"]+)"/g)].map((m) => m[1]);
  assert.ok(paths.length > 40);
  for (const p of paths) assert.ok(fs.existsSync(path.join(dir, 'files', ...p.split('/'))), p);
});

test('not signed in: the App Review sign-in page, and no data', async () => {
  const r = await fetch(base + '/', { headers: { Accept: 'text/html' } });
  assert.equal(r.status, 200);
  assert.match(await r.text(), /App Review sign-in/);
  assert.equal((await fetch(base + '/api/me')).status, 401);
  // Cloudflare's headers and the developer header mean nothing here
  assert.equal((await fetch(base + '/api/me', { headers: { 'X-Dev-Email': 'review@e11hq.com', 'Cf-Access-Jwt-Assertion': 'a.b.c' } })).status, 401);
  assert.equal((await fetch(base + '/install')).status, 404);
});

test('the right email and password sign in; the account is not the owner', async () => {
  assert.equal((await signIn('review@e11hq.com', 'wrong-password', '2.2.2.2')).status, 401);
  assert.equal((await signIn('someone@e11hq.com', PW, '2.2.2.2')).status, 401);
  const r = await signIn(' Review@E11HQ.com ', PW, '2.2.2.2');
  assert.equal(r.status, 303);
  const c = cookieOf(r);
  assert.match(String(r.headers.get('set-cookie')), /HttpOnly/);
  const me = await fetch(base + '/api/me', { headers: { Cookie: c } }).then((x) => x.json());
  assert.equal(me.user.name, 'Alex Morgan'); assert.equal(me.review, true); assert.equal(me.owner, false);
  const snap = await fetch(base + '/api/snapshot', { headers: { Cookie: c } }).then((x) => x.json());
  assert.ok(snap.data.tasks.length >= 30);
  const up = await fetch(base + '/api/updates', { method: 'POST', headers: { Cookie: c, 'Content-Type': 'application/json' }, body: '{"action":"update"}' });
  assert.ok(up.status === 403 || (await up.json()).managed === false);
  // signing out ends it
  await fetch(base + '/review/sign-out', { headers: { Cookie: c }, redirect: 'manual' });
  assert.equal((await fetch(base + '/api/me', { headers: { Cookie: c } })).status, 401);
});

test('five wrong passwords: that address waits, even with the right one', async () => {
  for (let i = 0; i < 5; i++) assert.equal((await signIn('review@e11hq.com', 'nope' + i, '3.3.3.3')).status, 401);
  assert.equal((await signIn('review@e11hq.com', PW, '3.3.3.3')).status, 429);
  assert.equal((await signIn('review@e11hq.com', PW, '4.4.4.4')).status, 303);
});

test('the demo starts fresh once a day, from 3:00 Dubai', () => {
  const kv = new Map(); const store = { kv: { get: (k) => kv.get(k), set: (k, v) => kv.set(k, v) } };
  assert.equal(resetDue(store, Date.parse('2026-11-02T10:00:00Z')).due, true);   // never loaded
  kv.set('demo-loaded', JSON.stringify({ day: '2026-11-02' }));
  assert.equal(resetDue(store, Date.parse('2026-11-02T19:59:00Z')).due, false);  // 23:59 the same day
  assert.equal(resetDue(store, Date.parse('2026-11-02T22:30:00Z')).due, false);  // 02:30 the next day
  assert.equal(resetDue(store, Date.parse('2026-11-02T23:05:00Z')).due, true);   // 03:05 the next day
});

test('a changed demo goes back to the made-up start', () => {
  const t = app.store.list('tasks')[0];
  app.store.apply([{ kind: 'tasks', id: t.id, data: { ...t, title: 'Changed by the reviewer' } }], 'u-review');
  app.loadDemo('2026-11-03');
  assert.notEqual(app.store.get('tasks', t.id).title, 'Changed by the reviewer');
  assert.equal(JSON.parse(app.store.kv.get('demo-loaded')).day, '2026-11-03');
});

test('without REVIEW_PASSWORD (live and test) there is no password sign-in at all', async () => {
  const d2 = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-review-off-'));
  const live = createServer({ dataDir: d2, version: '1.9.4', ...OFF });
  const b2 = `http://127.0.0.1:${await live.listen(0, '127.0.0.1')}`;
  try {
    const r = await fetch(b2 + '/review/sign-in', { method: 'POST', redirect: 'manual', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ email: 'review@e11hq.com', password: PW }) });
    assert.equal(r.status, 401);
    assert.equal(r.headers.get('set-cookie'), null);
    assert.equal(live.store.list('users').length, 0, 'no demo data either');
  } finally { await live.close(); fs.rmSync(d2, { recursive: true, force: true }); }
});

test('the privacy policy and support page open without signing in', async () => {
  for (const p of ['/privacy', '/support']) {
    const r = await fetch(base + p);
    assert.equal(r.status, 200);
    assert.match(await r.text(), p === '/privacy' ? /Privacy policy/ : /Support/);
  }
});
