import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11fin-'));
  app = createServer({ dataDir: dir, dev: true });
  app.cfSync = null;
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    users: [
      { id: 'u-admin', email: 'arsal@e11-digital.com', role: 'admin', active: true },
      { id: 'u-am', email: 'areej@e11-digital.com', role: 'am', active: true },
      { id: 'u-fa', email: 'fin@e11-digital.com', role: 'finance_admin', active: true },
      { id: 'u-fv', email: 'view@e11-digital.com', role: 'finance_viewer', active: true },
      { id: 'u-prod', email: 'ali@e11-digital.com', role: 'production', active: true },
      { id: 'u-amf', email: 'lana@e11-digital.com', role: 'am', fin: 'viewer', active: true },
      { id: 'u-prodf', email: 'moon@e11-digital.com', role: 'production', fin: 'admin', active: true },
      { id: 'u-socadm', email: 'aish@e11-digital.com', role: 'social', admin: true, active: true },
    ],
    projects: [{ id: 'p1', name: 'Ford' }],
    tasks: [{ id: 't1', projectId: 'p1', title: 'EDM', finance: 'LPO Pending', notesHtml: 'secret brief', comments: [{ id: 'c1', text: 'hi' }], attachments: [], assignees: ['u-am', 'u-prod', 'u-prodf'] }],
    finance: [{ id: 'f1', type: 'expense', name: 'Printer', amount: 500, date: '2026-10-02' }],
  }, 'test');
  for (const f of ['Finance/Expenses/inv.pdf', 'attachments/t1/a.txt']) {
    fs.mkdirSync(path.join(dir, 'files', path.dirname(f)), { recursive: true });
    fs.writeFileSync(path.join(dir, 'files', f), 'x');
  }
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const call = async (who, p, body) => {
  const res = await fetch(base + p, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const FA = 'fin@e11-digital.com', FV = 'view@e11-digital.com', AM = 'areej@e11-digital.com', ADMIN = 'arsal@e11-digital.com';
const PROD = 'ali@e11-digital.com', AMF = 'lana@e11-digital.com', PRODF = 'moon@e11-digital.com', SOCADM = 'aish@e11-digital.com';

test('finance people get slim tasks (no comments, description or people) and the finance records', async () => {
  const r = await call(FV, '/api/snapshot');
  const t = r.body.data.tasks[0];
  assert.equal(t.finance, 'LPO Pending');
  assert.equal(t.title, 'EDM');
  assert.equal(t.comments, undefined); assert.equal(t.notesHtml, undefined); assert.equal(t.assignees, undefined);
  assert.equal(r.body.data.finance.length, 1);
});

test('finance records are hidden from everyone else except Admins', async () => {
  assert.equal((await call(AM, '/api/snapshot')).body.data.finance.length, 0);
  assert.equal((await call(ADMIN, '/api/snapshot')).body.data.finance.length, 1);
});

test('only a Finance Admin adds or removes finance records', async () => {
  const add = (who, id) => call(who, '/api/push', { changes: [{ kind: 'finance', id, data: { id, type: 'expense', name: 'X', amount: 1, date: '2026-10-03' } }] });
  assert.equal((await add(FA, 'f2')).body.results[0].refused, false);
  assert.equal((await add(FV, 'f3')).body.results[0].refused, true);
  assert.equal((await add(ADMIN, 'f4')).body.results[0].refused, true);
  assert.equal((await add(AM, 'f5')).body.results[0].refused, true);
});

test('only Account Managers and Admins change a task’s Finance status', async () => {
  const snap = (await call(FA, '/api/snapshot')).body.data.tasks[0];
  const r = await call(FA, '/api/push', { changes: [{ kind: 'tasks', id: 't1', base: snap, data: { ...snap, finance: 'Invoiced' } }] });
  assert.equal(r.body.results[0].refused, true);
  const full = app.store.get('tasks', 't1');
  const p = await call(PROD, '/api/push', { changes: [{ kind: 'tasks', id: 't1', base: full, data: { ...full, finance: 'Retainer' } }] });
  assert.equal(p.body.results[0].refused, true);
  const ok = await call(PROD, '/api/push', { changes: [{ kind: 'tasks', id: 't1', base: full, data: { ...full, title: 'EDM v2' } }] });
  assert.equal(ok.body.results[0].refused, false, 'other edits still work');
  const cur = app.store.get('tasks', 't1');
  const a = await call(AM, '/api/push', { changes: [{ kind: 'tasks', id: 't1', base: cur, data: { ...cur, finance: 'Invoiced' } }] });
  assert.equal(a.body.results[0].refused, false);
  assert.equal(app.store.get('tasks', 't1').finance, 'Invoiced');
});

test('Finance access on top of another role; Admin rights on top of another role', async () => {
  // an Account Manager with Finance Viewer access sees the records but can't add them
  assert.equal((await call(AMF, '/api/snapshot')).body.data.finance.length >= 1, true);
  const add = await call(AMF, '/api/push', { changes: [{ kind: 'finance', id: 'fz', data: { id: 'fz', type: 'expense', name: 'Z', amount: 1, date: '2026-10-03' } }] });
  assert.equal(add.body.results[0].refused, true);
  // a Production person with Finance Admin access can add records and still uses the task app
  const add2 = await call(PRODF, '/api/push', { changes: [{ kind: 'finance', id: 'fy', data: { id: 'fy', type: 'expense', name: 'Y', amount: 1, date: '2026-10-03' } }] });
  assert.equal(add2.body.results[0].refused, false);
  assert.ok((await call(PRODF, '/api/snapshot')).body.data.tasks[0].comments, 'full tasks, not the Finance-only copy');
  // Admin rights on top: a Social person with admin: true can open the Admin-only routes
  assert.equal((await call(SOCADM, '/api/cloudflare')).status, 200);
  assert.equal((await call(PROD, '/api/cloudflare')).status, 403);
});

test('nobody gives themselves Admin rights or Finance access', async () => {
  const me = app.store.get('users', 'u-prod');
  const r = await call(PROD, '/api/push', { changes: [{ kind: 'users', id: 'u-prod', base: me, data: { ...me, admin: true, fin: 'admin' } }] });
  assert.equal(r.body.results[0].refused, true);
});

test('finance people cannot create tasks or projects', async () => {
  const r = await call(FA, '/api/push', { changes: [{ kind: 'tasks', id: 'tX', data: { id: 'tX', title: 'n' } }, { kind: 'projects', id: 'pX', data: { id: 'pX', name: 'n' } }] });
  assert.ok(r.body.results.every((x) => x.refused));
});

test('invoices: Finance people and Admins can open them; task files are closed to Finance', async () => {
  assert.equal((await call(FV, '/__file/Finance/Expenses/inv.pdf')).status, 200);
  assert.equal((await call(ADMIN, '/__file/Finance/Expenses/inv.pdf')).status, 200);
  assert.equal((await call(AM, '/__file/Finance/Expenses/inv.pdf')).status, 403);
  assert.equal((await call(FA, '/__file/attachments/t1/a.txt')).status, 403);
});

test('only a Finance Admin uploads invoices', async () => {
  const up = (who) => call(who, '/api/host/writeChunk', { dest: 'Finance/Expenses', name: 'i.pdf', b64: Buffer.from('pdf').toString('base64') });
  assert.equal((await up(FA)).status, 200);
  assert.equal((await up(FV)).status, 403);
  assert.equal((await up(AM)).status, 403);
});
