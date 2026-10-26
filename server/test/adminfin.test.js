// Super Admins and Office Admins see Finance only with Finance access (+ Finance Admin / + Finance Viewer), and can add it
// to themselves. An Office Admin with Finance access gets the tasks' Finance view (so the Finance pages aren't empty).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com';
let app, base, dir;
const call = async (email, p, body) => { const r = await fetch(base + p, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': email, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined }); return { status: r.status, body: await r.json().catch(() => null) }; };
const snap = async (email) => (await call(email, '/api/snapshot')).body.data;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11af-'));
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    users: [
      { id: 'u-own', email: OWNER, role: 'admin', active: true },
      { id: 'u-sa', email: 'sa@e11-digital.com', role: 'admin', active: true },
      { id: 'u-saf', email: 'saf@e11-digital.com', role: 'admin', fin: 'viewer', active: true },
      { id: 'u-oa', email: 'oa@e11-digital.com', role: 'office_admin', active: true },
      { id: 'u-oaf', email: 'oaf@e11-digital.com', role: 'office_admin', fin: 'admin', active: true },
    ],
    projects: [{ id: 'p1', name: 'Ford' }],
    tasks: [{ id: 't1', projectId: 'p1', title: 'EDM', finance: 'Invoiced', notesHtml: 'brief', assignees: [] }],
    finance: [{ id: 'f1', type: 'expense', name: 'Printer', amount: 500, date: '2026-10-02' }],
  }, 'test');
  fs.mkdirSync(path.join(dir, 'files', 'Finance', 'Expenses'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'files', 'Finance', 'Expenses', 'inv.pdf'), 'pdf');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

test('no Finance access: no finance records or invoices — Super Admin and Office Admin alike', async () => {
  for (const who of ['sa@e11-digital.com', 'oa@e11-digital.com']) {
    assert.equal((await snap(who)).finance.length, 0, who);
    assert.equal((await call(who, '/__file/Finance/Expenses/inv.pdf')).status, 403, who);
  }
  assert.equal((await snap('oa@e11-digital.com')).tasks.length, 0, 'an Office Admin without Finance: no tasks at all');
});

test('with Finance access: records and invoices; an Office Admin gets the tasks’ Finance view (no briefs)', async () => {
  for (const who of ['saf@e11-digital.com', 'oaf@e11-digital.com']) {
    assert.equal((await snap(who)).finance.length, 1, who);
    assert.equal((await call(who, '/__file/Finance/Expenses/inv.pdf')).status, 200, who);
  }
  const t = (await snap('oaf@e11-digital.com')).tasks;
  assert.equal(t.length, 1); assert.equal(t[0].finance, 'Invoiced'); assert.equal(t[0].notesHtml, undefined);
});

test('an Office Admin can give themselves Finance access, like a Super Admin', async () => {
  const me = app.store.get('users', 'u-oa');
  const r = await call('oa@e11-digital.com', '/api/push', { changes: [{ kind: 'users', id: 'u-oa', base: me, data: { ...me, fin: 'viewer' } }] });
  assert.equal(r.body.results[0].refused, false);
  assert.equal((await snap('oa@e11-digital.com')).finance.length, 1);
  assert.equal((await snap('oa@e11-digital.com')).tasks.length, 1, 'and now sees the tasks’ Finance view');
});
