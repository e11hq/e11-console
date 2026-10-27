// Once a task first goes for CD review, its name, description and client (and its subtasks' names) are locked for
// everyone (Admins too); everything else stays open; pinned brief updates can't be edited
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com', AM = 'areej@e11-digital.com';
let app, dir, base;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-idlock-'));
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER, digest: false, holidays: false, occRemind: false, birthdays: false, scheduled: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  const t = (id, extra = {}) => ({ id, title: 'Task ' + id, notes: 'brief', notesHtml: 'brief', projectId: 'p1', sectionId: 's1', assignees: [], createdBy: 'u-a', comments: [], attachments: [], tags: [], reviews: [], ...extra });
  app.store.importAll({ users: [
    { id: 'u-h', email: OWNER, name: 'Haris', role: 'admin', active: true },
    { id: 'u-a', email: AM, name: 'Areej', role: 'am', active: true },
  ], projects: [{ id: 'p1', name: 'KIA', sections: [{ id: 's1', name: 'To do' }, { id: 's2', name: 'Doing' }], ams: [{ id: 'u-a' }] }, { id: 'p2', name: 'Ford', sections: [{ id: 's9', name: 'To do' }] }],
  tasks: [t('open'), t('old', { reviews: [{ id: 'r1', by: 'u-p', at: '2026-10-20T10:00:00Z', state: 'approved' }] }), t('sub', { parentId: 'old', title: 'Sub' }),
    t('new', { lockedAt: '2026-10-27T10:00:00Z', comments: [{ id: 'c1', text: 'logo bigger', html: 'logo bigger', authorId: 'u-a' }, { id: 'c2', text: 'ok', html: 'ok', authorId: 'u-a' }], briefPins: [{ cid: 'c1', by: 'u-a', at: '2026-10-27T10:00:00Z' }] })], statuses: [] }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
async function push(who, id, change) {
  const cur = app.store.get('tasks', id);
  const data = typeof change === 'function' ? change(JSON.parse(JSON.stringify(cur))) : { ...cur, ...change };
  const r = await fetch(base + '/api/push', { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify({ changes: [{ kind: 'tasks', id, base: cur, data }] }) }).then((x) => x.json());
  return !!r.results[0].refused;
}

test('a task never sent for review can still be renamed', async () => {
  assert.equal(await push(AM, 'open', { title: 'Renamed' }), false);
});
test('after CD review: name, description and client are locked, also for the owner', async () => {
  assert.equal(await push(OWNER, 'old', { title: 'Another job' }), true, 'name');
  assert.equal(await push(OWNER, 'old', { notes: 'new brief', notesHtml: 'new brief' }), true, 'description');
  assert.equal(await push(AM, 'old', { projectId: 'p2', sectionId: 's9' }), true, 'client');
  assert.equal(await push(OWNER, 'sub', { title: 'Another sub' }), true, 'a subtask’s name');
  assert.equal(await push(OWNER, 'new', { lockedAt: null }), true, 'the lock can’t be taken off');
});
test('everything else stays open', async () => {
  assert.equal(await push(AM, 'old', { sectionId: 's2', done: false, due: '2026-11-01', tags: ['x'] }), false);
  assert.equal(await push(AM, 'old', (t) => { t.comments.push({ id: 'cx', text: 'hi', authorId: 'u-a' }); return t; }), false);
});
test('a pinned brief update can’t be edited; other comments can', async () => {
  assert.equal(await push(AM, 'new', (t) => { t.comments[0].text = 'logo smaller'; t.comments[0].html = 'logo smaller'; return t; }), true);
  assert.equal(await push(AM, 'new', (t) => { t.comments[1].text = 'ok!'; t.comments[1].html = 'ok!'; return t; }), false);
});
