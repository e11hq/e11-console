import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11t-'));
  app = createServer({ dataDir: dir, dev: true });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
  app.store.importAll({
    users: [
      { id: 'u-admin', email: 'haris@e11-digital.com', role: 'admin', active: true },
      { id: 'u-am', email: 'areej@e11-digital.com', role: 'am', active: true },
      { id: 'u-prod', email: 'yousef@e11-digital.com', role: 'production', active: true },
    ],
    tasks: [{ id: 't1', title: 'Ford EDM', comments: [], attachments: [] }],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const push = async (who, changes) => (await fetch(base + '/api/push', { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify({ changes }) })).json();
const snap = async (who) => (await fetch(base + '/api/snapshot', { headers: { 'X-Dev-Email': who } })).json();
const ADMIN = 'haris@e11-digital.com', AM = 'areej@e11-digital.com', PROD = 'yousef@e11-digital.com';
const item = (id, by, extra = {}) => ({ id, type: 'comment', deletedAt: new Date().toISOString(), deletedBy: by, key: 'tasks:t1', data: { taskId: 't1', comments: [{ id: 'c' + id }] }, ...extra });

test('trash: anyone can put their own deletion in, only Admins and Account Managers see it', async () => {
  const r = await push(PROD, [{ kind: 'trash', id: 'tr1', data: item('tr1', 'u-prod') }]);
  assert.equal(r.results[0].refused, false);
  assert.equal(r.results[0].hidden, true); // Yousef doesn't get it back
  assert.equal((await push(PROD, [{ kind: 'trash', id: 'tr2', data: item('tr2', 'u-am') }])).results[0].refused, true); // not in someone else's name
  assert.equal(((await snap(PROD)).data.trash || []).length, 0);
  assert.equal((await snap(AM)).data.trash.length, 1);
  assert.equal((await push(PROD, [{ kind: 'trash', id: 'tr1', del: true }])).results[0].refused, true);
});

test('trash: Account Managers clear an item only when restoring it (or after 30 days); Admins delete forever', async () => {
  assert.equal((await push(AM, [{ kind: 'trash', id: 'tr1', del: true }])).results[0].refused, true); // no "delete forever" for AMs
  const t1 = app.store.get('tasks', 't1');
  const r = await push(AM, [{ kind: 'tasks', id: 't1', base: t1, data: { ...t1, comments: [{ id: 'ctr1' }] } }, { kind: 'trash', id: 'tr1', del: true }]);
  assert.ok(r.results.every((x) => !x.refused), 'restore = put the comment back + clear the Trash item');
  await push(AM, [{ kind: 'trash', id: 'old', data: item('old', 'u-am', { deletedAt: new Date(Date.now() - 31 * 86400000).toISOString() }) }]);
  assert.equal((await push(AM, [{ kind: 'trash', id: 'old', del: true }])).results[0].refused, false); // expired
  await push(AM, [{ kind: 'trash', id: 'tr3', data: item('tr3', 'u-am') }]);
  assert.equal((await push(ADMIN, [{ kind: 'trash', id: 'tr3', del: true }])).results[0].refused, false);
});
