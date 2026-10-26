// Office Admin: Admin rights (Team, Client Assets, App updates, Finance per access) without the task app
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com', LANA = 'lana@e11-digital.com', ARSAL = 'arsal@e11-digital.com', AM = 'areej@e11-digital.com';
let app, dir, call, push;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-office-'));
  app = createServer({ dataDir: dir, dev: true, version: '1.6.5-test.1', adminEmail: OWNER, digest: false, holidays: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  app.store.importAll({
    meta: { cdUserId: null },
    users: [
      { id: 'u-h', email: OWNER, role: 'admin', active: true },
      { id: 'u-l', email: LANA, role: 'admin', active: true },
      { id: 'u-a', email: ARSAL, role: 'office_admin', fin: 'admin', active: true },
      { id: 'u-am', email: AM, role: 'am', active: true },
      { id: 'u-p', email: 'ali@e11-digital.com', role: 'production', active: true },
    ],
    projects: [{ id: 'p-ford', name: 'Ford', sections: [], clientId: 'cl-ford' }],
    clients: [{ id: 'cl-ford', name: 'Ford', dir: 'Clients/Ford', folders: [{ id: 'f1', name: 'Logos', dir: 'Clients/Ford/Logos', files: [], auto: true }] }],
    tasks: [{ id: 't1', projectId: 'p-ford', title: 'Ford EDM', notesHtml: 'brief', comments: [{ id: 'c1', text: 'hi' }], assignees: ['u-p'], finance: 'LPO Pending' }],
    notifications: [
      { id: 'n-task', to: 'u-a', from: 'u-l', taskId: 't1', kind: 'edit', text: 'changed', at: '2026-10-26T08:00:00Z' },
      { id: 'n-asset', to: 'u-a', from: 'u-l', kind: 'asset', clientId: 'cl-ford', folderId: 'f1', text: 'added a file', at: '2026-10-26T08:00:00Z' },
    ],
    trash: [
      { id: 'tr-task', type: 'task', key: 'tasks:t9', deletedAt: '2026-10-25T08:00:00Z', deletedBy: 'u-l', data: { tasks: [{ id: 't9', title: 'Old' }] } },
      { id: 'tr-file', type: 'cafile', key: 'clients:cl-ford', deletedAt: '2026-10-25T08:00:00Z', deletedBy: 'u-l', data: { clientId: 'cl-ford', folderId: 'f1', file: { id: 'a1', name: 'logo.png', path: 'Clients/Ford/Logos/logo.png' } } },
    ],
    statuses: [],
  }, 'test');
  call = async (who, p, body) => { const r = await fetch(`http://127.0.0.1:${port}${p}`, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined }); return { status: r.status, body: await r.json() }; };
  push = (who, changes) => call(who, '/api/push', { changes }).then((r) => r.body.results);
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

test('an Office Admin gets no task app: only the slim job list Finance needs, no task updates in the Inbox', async () => {
  const d = (await call(ARSAL, '/api/snapshot')).body.data;
  const t = d.tasks.find((x) => x.id === 't1');
  assert.ok(t && t.finance === 'LPO Pending', 'the Finance job list');
  assert.equal(t.notesHtml, undefined); assert.equal(t.comments, undefined); assert.equal(t.assignees, undefined);
  assert.deepEqual(d.notifications.map((n) => n.id), ['n-asset'], 'Client Assets updates, not task ones');
  assert.ok(d.clients.some((c) => c.id === 'cl-ford'), 'Client Assets');
});

test('an Office Admin can’t add or change clients, or change tasks beyond a job’s Finance status', async () => {
  const p = app.store.get('projects', 'p-ford');
  assert.equal((await push(ARSAL, [{ kind: 'projects', id: 'p-new', data: { id: 'p-new', name: 'New', sections: [] } }]))[0].refused, true);
  assert.equal((await push(ARSAL, [{ kind: 'projects', id: 'p-ford', base: p, data: { ...p, color: '#fff' } }]))[0].refused, true);
  const slim = (await call(ARSAL, '/api/snapshot')).body.data.tasks.find((x) => x.id === 't1');
  assert.equal((await push(ARSAL, [{ kind: 'tasks', id: 't1', base: slim, data: { ...slim, title: 'Renamed' } }]))[0].refused, true, 'no task edits');
  const r = await push(ARSAL, [{ kind: 'tasks', id: 't1', base: slim, data: { ...slim, finance: 'Invoiced', financeAt: '2026-10-26T09:00:00Z', financeBy: 'u-a' } }]);
  assert.equal(r[0].refused, false, 'Finance status');
  const full = app.store.get('tasks', 't1');
  assert.equal(full.finance, 'Invoiced'); assert.equal(full.notesHtml, 'brief', 'nothing else lost'); assert.deepEqual(full.assignees, ['u-p']);
});

test('an Office Admin manages the team and Client Assets like an Admin', async () => {
  const u = app.store.get('users', 'u-p');
  assert.equal((await push(ARSAL, [{ kind: 'users', id: 'u-p', base: u, data: { ...u, role: 'social' } }]))[0].refused, false);
  const owner = app.store.get('users', 'u-h');
  assert.equal((await push(ARSAL, [{ kind: 'users', id: 'u-h', base: owner, data: { ...owner, role: 'production' } }]))[0].refused, true, 'not the owner');
  const c = app.store.get('clients', 'cl-ford');
  const auto = c.folders.find((f) => f.id === 'f1');
  assert.equal((await push(ARSAL, [{ kind: 'clients', id: 'cl-ford', base: c, data: { ...c, folders: c.folders.filter((f) => f !== auto) } }]))[0].refused, false, 'full Client Assets rights');
});

test('Trash: only Client Assets items, restore yes, delete forever no', async () => {
  const d = (await call(ARSAL, '/api/snapshot')).body.data;
  assert.deepEqual(d.trash.map((x) => x.id), ['tr-file']);
  assert.equal((await push(ARSAL, [{ kind: 'trash', id: 'tr-file', del: true }]))[0].refused, true, 'no delete forever');
  assert.equal((await push(ARSAL, [{ kind: 'trash', id: 'tr-task', del: true }]))[0].refused, true);
  const c = app.store.get('clients', 'cl-ford');
  const folders = [...c.folders, { id: 'f1', name: 'Logos', dir: 'Clients/Ford/Logos', files: [{ id: 'a1', name: 'logo.png', path: 'Clients/Ford/Logos/logo.png' }], auto: true }];
  const r = await push(ARSAL, [{ kind: 'clients', id: 'cl-ford', base: c, data: { ...c, folders } }, { kind: 'trash', id: 'tr-file', del: true }]);
  assert.deepEqual(r.map((x) => x.refused), [false, false], 'restore');
  assert.ok(app.store.get('trash', 'tr-task'), 'the task item stays');
});
