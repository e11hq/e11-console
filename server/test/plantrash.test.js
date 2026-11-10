// Trash Skeleton (Haris 2026-11-10): only its maker and the Social Manager, only before any task is made from it; it waits
// in the Trash for 30 days and Admins / Account Managers put it back; its link files…/p/<id>
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com', EXEC = 'amelia@e11-digital.com', EXEC2 = 'maya@e11-digital.com', MGR = 'aish@e11-digital.com', AM = 'areej@e11-digital.com', CD = 'carine@e11-digital.com';
const DATA = {
  meta: { cdUserId: 'u-cd', socialMgrIds: ['u-mg'] },
  users: [
    { id: 'u-h', email: OWNER, role: 'admin', active: true },
    { id: 'u-ex', email: EXEC, role: 'social', active: true },
    { id: 'u-ex2', email: EXEC2, role: 'social', active: true },
    { id: 'u-mg', email: MGR, role: 'social', active: true },
    { id: 'u-am', email: AM, role: 'am', active: true },
    { id: 'u-cd', email: CD, role: 'am', active: true },
  ],
  projects: [{ id: 'p-ford', name: 'Ford', sections: [], ams: [{ id: 'u-am' }], socials: ['u-ex', 'u-ex2'] }],
  plans: [
    { id: 'pl-1', projectId: 'p-ford', month: '2026-12', status: 'review', createdBy: 'u-ex', posts: [{ id: 'x1', title: 'A' }] },
    { id: 'pl-2', projectId: 'p-ford', month: '2027-01', status: 'approved', createdBy: 'u-ex', posts: [{ id: 'x2', title: 'B', taskId: 't-1' }] },
    { id: 'pl-3', projectId: 'p-ford', month: '2027-02', status: 'draft', createdBy: 'u-ex2', posts: [] },
  ],
  statuses: [],
};
let app, dir, port;
const call = async (who, p, body) => { const r = await fetch(`http://127.0.0.1:${port}${p}`, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined }); return { status: r.status, body: await r.json() }; };
const act = (who, body) => call(who, '/api/app/act', body).then((r) => r.body);
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-pltrash-'));
  app = createServer({ dataDir: dir, dev: true, version: '1.9.30-test.1', adminEmail: OWNER, digest: false, holidays: false, occRemind: false });
  port = await app.listen(0, '127.0.0.1');
  app.store.importAll(JSON.parse(JSON.stringify(DATA)), 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

test('only its maker and the Social Manager trash a skeleton, and never once a task is made from it', async () => {
  for (const who of [EXEC2, AM, CD, OWNER]) assert.equal((await act(who, { ev: 'plTrash', plan: 'pl-1' })).ok, false, who);
  assert.equal((await act(MGR, { ev: 'plTrash', plan: 'pl-2' })).ok, false, 'tasks made');
  const r = await act(EXEC, { ev: 'plTrash', plan: 'pl-1' });
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(app.store.get('plans', 'pl-1'), null);
  const it = app.store.list('trash').find((x) => x.type === 'plan');
  assert.equal(it.key, 'plans:pl-1'); assert.equal(it.data.plan.id, 'pl-1');
  assert.equal((await act(MGR, { ev: 'plTrash', plan: 'pl-3' })).ok, true, 'Social Manager');
});

test('the website’s own delete follows the same rule (push)', async () => {
  const base = app.store.get('plans', 'pl-2');
  const res = (await call(EXEC, '/api/push', { changes: [{ kind: 'plans', id: 'pl-2', base, del: true }] })).body.results;
  assert.equal(res[0].refused, true);
});

test('an Account Manager puts it back from the Trash; a Social Executive can’t', async () => {
  const it = app.store.list('trash').find((x) => x.key === 'plans:pl-1');
  assert.equal((await act(EXEC, { ev: 'trRestore', id: it.id })).ok, false);
  const r = await act(AM, { ev: 'trRestore', id: it.id });
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(app.store.get('plans', 'pl-1').status, 'review');
  assert.ok(!app.store.list('trash').some((x) => x.key === 'plans:pl-1'));
});

test('files…/p/<id> goes on to the website’s ?plan=; the apps are told /p/ is theirs', async () => {
  const aasa = await (await fetch(`http://127.0.0.1:${port}/.well-known/apple-app-site-association`)).json();
  assert.ok(aasa.applinks.details[0].components.some((c) => c['/'] === '/p/*'));
});
