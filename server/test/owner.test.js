// The owner (ADMIN_EMAIL): their account is protected on every site; "Owner view" (live site only) lets them, while
// working with another role, quietly step in with Admin rights on one device — look only until they allow changes.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com', LANA = 'lana@e11-digital.com', ALI = 'ali@e11-digital.com';
const seed = {
  meta: { cdUserId: null },
  users: [
    { id: 'u-haris', email: OWNER, name: 'Haris', role: 'production', active: true, prefs: {} },
    { id: 'u-lana', email: LANA, name: 'Lana', role: 'admin', active: true, prefs: {} },
    { id: 'u-ali', email: ALI, name: 'Ali', role: 'production', active: true, prefs: {} },
  ],
  projects: [{ id: 'p-ford', name: 'Ford', sections: [] }, { id: 'p-alain', name: 'ALAIN', sections: [] }],
  tasks: [
    { id: 't-mine', projectId: 'p-ford', title: 'Mine', comments: [], assignees: ['u-haris'] },
    { id: 't-other', projectId: 'p-alain', title: 'Other', comments: [], assignees: ['u-ali'] },
  ],
  clients: [], notifications: [], statuses: [],
};

async function start(version) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-owner-'));
  const app = createServer({ dataDir: dir, dev: true, version, adminEmail: OWNER });
  const port = await app.listen(0, '127.0.0.1');
  app.store.importAll(JSON.parse(JSON.stringify(seed)), 'test');
  const base = `http://127.0.0.1:${port}`;
  const call = async (who, p, { body, cookie } = {}) => {
    const res = await fetch(base + p, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) }, body: body ? JSON.stringify(body) : undefined });
    const type = res.headers.get('content-type') || '';
    return { status: res.status, body: type.includes('json') ? await res.json() : await res.text(), setCookie: res.headers.get('set-cookie') };
  };
  return { app, dir, call, close: async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); } };
}
const userPush = (s, who, data, opts = {}) => s.call(who, '/api/push', { body: { changes: [{ kind: 'users', id: data.id, base: s.app.store.get('users', data.id), data }] }, ...opts });

let live, testSite;
before(async () => { live = await start('1.6.2'); testSite = await start('1.6.2-test.137'); });
after(async () => { await live.close(); await testSite.close(); });

for (const site of ['live', 'test']) {
  test(`${site}: only the owner changes the owner's role, rights, email or active state`, async () => {
    const s = site === 'live' ? live : testSite;
    const h = () => s.app.store.get('users', 'u-haris');
    for (const change of [{ role: 'admin' }, { admin: true }, { fin: 'admin' }, { active: false }, { email: 'x@e11-digital.com' }, { projectIds: ['p-ford'] }]) {
      const r = await userPush(s, LANA, { ...h(), ...change });
      assert.equal(r.body.results[0].refused, true, `an Admin can't set ${JSON.stringify(change)} on the owner`);
    }
    assert.equal(h().role, 'production'); assert.equal(h().active, true);
    // nobody takes the owner's email for another account, or makes a new one with it
    assert.equal((await userPush(s, LANA, { ...s.app.store.get('users', 'u-ali'), email: OWNER })).body.results[0].refused, true);
    const add = await s.call(LANA, '/api/push', { body: { changes: [{ kind: 'users', id: 'u-x', data: { id: 'u-x', email: OWNER.toUpperCase(), role: 'admin', active: true } }] } });
    assert.equal(add.body.results[0].refused, true);
    // Admins still manage everyone else
    assert.equal((await userPush(s, LANA, { ...s.app.store.get('users', 'u-ali'), role: 'social' })).body.results[0].refused, false);
    await userPush(s, LANA, { ...s.app.store.get('users', 'u-ali'), role: 'production' });
    // the owner's profile (name) can still be edited by the owner
    assert.equal((await userPush(s, OWNER, { ...h(), name: 'Haris S' })).body.results[0].refused, false);
  });
}

test('Owner view is live only, and owner only', async () => {
  assert.equal((await testSite.call(OWNER, '/api/owner-view', { body: { mode: 'look' } })).status, 404);
  assert.equal((await testSite.call(OWNER, '/api/me')).body.canOwnerView, false);
  assert.equal((await live.call(LANA, '/api/owner-view', { body: { mode: 'look' } })).status, 403);
  assert.equal((await live.call(LANA, '/api/me')).body.canOwnerView, false);
  assert.equal((await live.call(OWNER, '/api/me')).body.canOwnerView, true);
});

test('Owner view: look only, then changes allowed, then off — on this device only, nothing stored', async () => {
  const on = await live.call(OWNER, '/api/owner-view', { body: { mode: 'look' } });
  assert.equal(on.status, 200); assert.equal(on.body.mode, 'look');
  const cookie = on.setCookie.split(';')[0];
  assert.match(on.setCookie, /HttpOnly/); assert.doesNotMatch(on.setCookie, /Max-Age|Expires/, 'a session cookie: gone when the app closes');
  // with the cookie: Admin rights (sees everything); without it (another device): still Production
  const snap = (await live.call(OWNER, '/api/snapshot', { cookie })).body.data;
  assert.ok(snap.tasks.some((t) => t.id === 't-other'), 'sees every task');
  assert.equal(snap.users.find((u) => u.id === 'u-haris').admin, true);
  assert.equal(snap.users.find((u) => u.id === 'u-haris').role, 'production', 'role unchanged');
  const me = (await live.call(OWNER, '/api/me', { cookie })).body;
  assert.equal(me.ownerView, 'look'); assert.equal(me.user.admin, true);
  const other = (await live.call(OWNER, '/api/snapshot')).body.data;
  assert.ok(!other.tasks.some((t) => t.id === 't-other'), 'other devices stay Production');
  // others never see it
  const lanaSees = (await live.call(LANA, '/api/snapshot')).body.data.users.find((u) => u.id === 'u-haris');
  assert.equal(lanaSees.admin, undefined); assert.equal(lanaSees.role, 'production');
  assert.equal(live.app.store.get('users', 'u-haris').admin, undefined, 'nothing stored');
  // look only: every change refused, files can't be added
  const t = live.app.store.get('tasks', 't-other');
  const r = await live.call(OWNER, '/api/push', { cookie, body: { changes: [{ kind: 'tasks', id: 't-other', base: t, data: { ...t, title: 'Changed' } }] } });
  assert.equal(r.body.results[0].refused, true); assert.equal(live.app.store.get('tasks', 't-other').title, 'Other');
  assert.equal((await live.call(OWNER, '/api/host/makeDir', { cookie, body: { dir: 'Clients/X' } })).status, 403);
  // changes allowed: an Admin change goes through, under their name; their stored role stays Production
  const ed = await live.call(OWNER, '/api/owner-view', { cookie, body: { mode: 'edit' } });
  assert.equal(ed.body.mode, 'edit');
  const r2 = await live.call(OWNER, '/api/push', { cookie, body: { changes: [{ kind: 'tasks', id: 't-other', base: t, data: { ...t, title: 'Changed' } }] } });
  assert.equal(r2.body.results[0].refused, false); assert.equal(live.app.store.get('tasks', 't-other').title, 'Changed');
  // saving their own profile in Owner view doesn't store the Admin rights
  const mine = snap.users.find((u) => u.id === 'u-haris');
  const r3 = await live.call(OWNER, '/api/push', { cookie, body: { changes: [{ kind: 'users', id: 'u-haris', base: mine, data: { ...mine, name: 'Haris Sharif' } }] } });
  assert.equal(r3.body.results[0].refused, false);
  assert.equal(live.app.store.get('users', 'u-haris').name, 'Haris Sharif');
  assert.ok(!live.app.store.get('users', 'u-haris').admin, 'Admin rights not saved');
  assert.equal(live.app.store.get('users', 'u-haris').role, 'production');
  // off: back to Production, the cookie is cleared
  const off = await live.call(OWNER, '/api/owner-view', { cookie, body: { mode: 'off' } });
  assert.equal(off.body.mode, null); assert.match(off.setCookie, /Max-Age=0/);
  assert.ok(!(await live.call(OWNER, '/api/snapshot', { cookie })).body.data.tasks.some((x) => x.id === 't-other'), 'the old cookie no longer works');
});

test('Owner view lapses after 15 minutes without use', async () => {
  const on = await live.call(OWNER, '/api/owner-view', { body: { mode: 'look' } });
  const cookie = on.setCookie.split(';')[0];
  assert.equal((await live.call(OWNER, '/api/me', { cookie })).body.ownerView, 'look');
  const realNow = Date.now;
  try {
    Date.now = () => realNow() + 16 * 60000;
    assert.equal((await live.call(OWNER, '/api/me', { cookie })).body.ownerView, null);
  } finally { Date.now = realNow; }
  assert.equal((await live.call(OWNER, '/api/me', { cookie })).body.ownerView, null, 'stays off');
});
