// CD review on: a task can't move past Review (CTR, Done…) or be completed until the CD approves — for everyone,
// Admins included, and also with nobody assigned. Switching CD review off is the way out.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const ADMIN = 'haris@e11-digital.com';
let app, dir, push;
const S = [{ id: 's-todo', name: 'To do' }, { id: 's-prog', name: 'In Progress' }, { id: 's-rev', name: 'Review' }, { id: 's-ctr', name: 'CTR' }, { id: 's-done', name: 'Done' }];
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-cd-'));
  app = createServer({ dataDir: dir, dev: true, version: '1.6.5-test.1', adminEmail: ADMIN, digest: false, holidays: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  app.store.importAll({
    meta: { cdUserId: 'u-cd' },
    users: [{ id: 'u-h', email: ADMIN, role: 'admin', active: true }, { id: 'u-cd', email: 'carine@e11-digital.com', role: 'am', active: true }, { id: 'u-p', email: 'ali@e11-digital.com', role: 'production', active: true }],
    projects: [{ id: 'p1', name: 'Ford', sections: S }],
    tasks: [
      { id: 't-none', projectId: 'p1', sectionId: 's-prog', title: 'Nobody yet', needsCD: true, assignees: [] },
      { id: 't-one', projectId: 'p1', sectionId: 's-rev', title: 'Ali', needsCD: true, assignees: ['u-p'] },
      { id: 't-cd', projectId: 'p1', sectionId: 's-prog', title: 'CD alone', needsCD: true, assignees: ['u-cd'] },
      { id: 't-off', projectId: 'p1', sectionId: 's-prog', title: 'No review', needsCD: false, assignees: [] },
    ],
  }, 'test');
  push = async (id, change) => {
    const cur = app.store.get('tasks', id);
    const r = await fetch(`http://127.0.0.1:${port}/api/push`, { method: 'POST', headers: { 'X-Dev-Email': ADMIN, 'Content-Type': 'application/json' }, body: JSON.stringify({ changes: [{ kind: 'tasks', id, base: cur, data: { ...cur, ...change } }] }) });
    return (await r.json()).results[0].refused;
  };
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

test('needs CD review, not approved: no CTR, no Done, no completing — even for an Admin, even with nobody assigned', async () => {
  for (const id of ['t-none', 't-one']) {
    assert.equal(await push(id, { sectionId: 's-ctr' }), true, `${id}: CTR`);
    assert.equal(await push(id, { sectionId: 's-done' }), true, `${id}: Done`);
    assert.equal(await push(id, { done: true, completedAt: new Date().toISOString() }), true, `${id}: complete`);
  }
  assert.equal(await push('t-none', { sectionId: 's-rev' }), false, 'up to Review is fine');
});

test('approved, done by the CD alone, or CD review off: free to move and complete', async () => {
  assert.equal(await push('t-one', { cdStatus: 'approved', sectionId: 's-ctr' }), false, 'approved (in the same save)');
  assert.equal(await push('t-one', { sectionId: 's-done', done: true, completedAt: new Date().toISOString() }), false);
  assert.equal(await push('t-cd', { sectionId: 's-done', done: true }), false, 'the CD’s own task');
  assert.equal(await push('t-off', { sectionId: 's-done', done: true }), false, 'no CD review');
  assert.equal(await push('t-none', { needsCD: false }), false, 'switching it off');
  assert.equal(await push('t-none', { sectionId: 's-ctr' }), false, '...then it moves');
});
