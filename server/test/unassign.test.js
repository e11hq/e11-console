import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

test('once, Account Managers and Admins come off every task; the CD, Production and Freelancers stay', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11un-'));
  const opts = { dataDir: dir, dev: true, digest: false, holidays: false, occRemind: false };
  let app = createServer(opts);
  app.store.importAll({
    users: [
      { id: 'u-am', email: 'am@e11-digital.com', role: 'am', active: true },
      { id: 'u-adm', email: 'adm@e11-digital.com', role: 'admin', active: true },
      { id: 'u-cd', email: 'cd@e11-digital.com', role: 'admin', active: true },
      { id: 'u-prod', email: 'p@e11-digital.com', role: 'production', active: true },
      { id: 'u-free', email: 'f@gmail.com', role: 'freelancer', active: true },
    ],
    meta: { cdUserId: 'u-cd' },
    tasks: [{ id: 't1', title: 'T', assignees: ['u-am', 'u-adm', 'u-cd', 'u-prod', 'u-free'], prio: { 'u-am': 1, 'u-prod': 2 }, partsDone: { 'u-adm': 'x' } }],
  }, 'test');
  app.store.kv.set('unassign-managers-v1', '');   // (as on a server that already had its data)
  await app.close();
  app = createServer(opts);                     // the next start does it
  const t = app.store.get('tasks', 't1');
  assert.deepEqual(t.assignees, ['u-cd', 'u-prod', 'u-free']);
  assert.deepEqual(t.prio, { 'u-prod': 2 });
  assert.deepEqual(t.partsDone, {});
  await app.close();
  fs.rmSync(dir, { recursive: true, force: true });
});
