// The iPhone app's native task page straight from the server (shell 30+): GET /api/task and its changes through
// POST /api/home/act (from: 'task') — what's shown, who may change what, the status rules (CD review), my part,
// priority, the checklist, the Task Update, and the switch.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const clock = Date.parse('2026-10-29T08:00:00Z');
let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11t-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    meta: { cdUserId: 'u-cd' },
    users: [
      { id: 'u-adm', email: 'adm@e11-digital.com', role: 'admin', active: true, name: 'Haris' },
      { id: 'u-am', email: 'am@e11-digital.com', role: 'am', active: true, name: 'Leila' },
      { id: 'u-prod', email: 'prod@e11-digital.com', role: 'production', active: true, name: 'Yousef A' },
      { id: 'u-prod2', email: 'prod2@e11-digital.com', role: 'production', active: true, name: 'Sara K' },
      { id: 'u-cd', email: 'cd@e11-digital.com', role: 'production', active: true, name: 'Carine' },
    ],
    projects: [
      { id: 'p1', name: 'Northline', color: '#3a7bd5', ams: [{ id: 'u-am' }], sections: [{ id: 's1', name: 'To do', color: '#87909e' }, { id: 's2', name: 'In progress', color: '#a875ff' }, { id: 's3', name: 'Review', color: '#f9be33' }, { id: 's4', name: 'CTR', color: '#4c9aff' }, { id: 's5', name: 'Done', color: '#3ddc97' }] },
    ],
    tasks: [
      { id: 't1', projectId: 'p1', sectionId: 's2', title: 'Offer pack', assignees: ['u-prod', 'u-prod2'], createdBy: 'u-am', due: '2026-10-29', tags: ['Print'], notesHtml: '<p>Matte <b>vinyl</b></p>', checklist: [{ id: 'c1', text: 'Bleed', done: false }], comments: [{ id: 'm1' }], activity: [] },
      { id: 't2', projectId: 'p1', sectionId: 's3', title: 'Needs CD', assignees: ['u-prod'], createdBy: 'u-am', needsCD: true, comments: [], activity: [] },
      { id: 't3', projectId: 'p1', sectionId: 's4', title: 'At the client', assignees: ['u-prod'], createdBy: 'u-am', comments: [], activity: [] },
      { id: 't4', projectId: 'p1', sectionId: 's5', title: 'Finished', assignees: ['u-prod'], createdBy: 'u-am', done: true, completedAt: '2026-10-28T08:00:00Z', comments: [], activity: [] },
      { id: 't5', projectId: 'p1', sectionId: 's2', title: 'Sub', parentId: 't1', assignees: [], comments: [], activity: [] },
    ],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const page = async (who, id) => (await (await fetch(base + '/api/task?id=' + id, { headers: { 'X-Dev-Email': who } })).json());
const act = async (who, body) => (await (await fetch(base + '/api/home/act', { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify({ from: 'task', ...body }) })).json());
const T = (id) => app.store.get('tasks', id);

test('the page: what the AM sees and may change', async () => {
  const r = await page('am@e11-digital.com', 't1');
  assert.equal(r.ok, true);
  const m = r.task;
  assert.equal(m.title, 'Offer pack'); assert.equal(m.client.name, 'Northline');
  assert.equal(m.status.name, 'In progress'); assert.equal(m.status.next, 's3');
  assert.equal(m.desc, 'Matte vinyl'); assert.equal(m.comments, 1);
  assert.equal(m.subtasks.length, 1); assert.equal(m.checklist.length, 1);
  assert.equal(m.canTitle, true); assert.equal(m.dates.canEdit, true); assert.equal(m.parts.of, 2);
  assert.equal(m.people['u-prod'].first, 'Yousef');
});

test('the page: a production person can\'t change dates; their part; a completed task is read only', async () => {
  const m = (await page('prod@e11-digital.com', 't1')).task;
  assert.equal(m.dates.canEdit, false); assert.equal(m.parts.mine, 'open');
  const d = (await page('am@e11-digital.com', 't4')).task;
  assert.equal(d.readOnly, true); assert.ok(d.completed); assert.equal(d.complete, null);
  assert.equal((await page('am@e11-digital.com', 'nope')).task, null);
});

test('status: Next, and CD review holds it at Review', async () => {
  let r = await act('am@e11-digital.com', { act: 'status', id: 't1', value: 's3', op: 'tp-1' });
  assert.equal(r.ok, true); assert.equal(T('t1').sectionId, 's3'); assert.equal(r.task.status.name, 'Review');
  r = await act('am@e11-digital.com', { act: 'status', id: 't2', value: 's4' });
  assert.equal(r.ok, false); assert.equal(r.error, 'Waiting for CD approval'); assert.equal(T('t2').sectionId, 's3');
  assert.equal((await page('am@e11-digital.com', 't2')).task.status.next, null);
});

test('status: back from the client asks about CD review, then does it', async () => {
  let r = await act('am@e11-digital.com', { act: 'status', id: 't3', value: 's2' });
  assert.equal(r.ok, false); assert.equal(r.need, 'cdAgain'); assert.equal(T('t3').sectionId, 's4');
  r = await act('am@e11-digital.com', { act: 'status', id: 't3', value: 's2', cdAgain: 'yes' });
  assert.equal(r.ok, true); assert.equal(T('t3').sectionId, 's2'); assert.equal(T('t3').needsCD, true);
  r = await act('prod@e11-digital.com', { act: 'status', id: 't1', value: 's1' });
  assert.equal(r.ok, true, 'going back within the work is fine for anyone on it');
});

test('my part, priority, checklist, title, start, Task Update', async () => {
  let r = await act('prod@e11-digital.com', { act: 'myPart', id: 't1', value: true });
  assert.equal(r.ok, true); assert.ok(T('t1').partsDone['u-prod']); assert.deepEqual(r.messages, ['Your part is done']);
  r = await act('am@e11-digital.com', { act: 'prio', id: 't1', key: 'u-prod2', value: 2 });
  assert.equal(r.ok, true); assert.equal(T('t1').prio['u-prod2'], 2);
  r = await act('prod@e11-digital.com', { act: 'prio', id: 't1', key: 'u-prod2', value: 3 });
  assert.equal(r.ok, false, 'production can\'t change priority');
  r = await act('prod@e11-digital.com', { act: 'check', id: 't1', value: 'c1' });
  assert.equal(r.ok, true); assert.equal(T('t1').checklist[0].done, true);
  r = await act('am@e11-digital.com', { act: 'title', id: 't1', value: '  Offer   pack v2 ' });
  assert.equal(T('t1').title, 'Offer pack v2');
  r = await act('prod@e11-digital.com', { act: 'start', id: 't1', value: '2026-10-28' });
  assert.equal(r.ok, false);
  r = await act('am@e11-digital.com', { act: 'start', id: 't1', value: '2026-10-28' });
  assert.equal(T('t1').start, '2026-10-28');
  r = await act('am@e11-digital.com', { act: 'update', id: 't1', value: 'WIP' });
  assert.equal(r.ok, true); assert.equal(T('t1').update, 'WIP'); assert.equal(r.task.update.t, 'WIP');
  r = await act('am@e11-digital.com', { act: 'title', id: 't4', value: 'x' });
  assert.equal(r.ok, false, 'a completed task is read only');
});

test('the switch: off → the page asks the website again', async () => {
  app.store.kv.set('task-server', 'off');
  assert.equal((await page('am@e11-digital.com', 't1')).off, true);
  assert.equal((await act('am@e11-digital.com', { act: 'title', id: 't1', value: 'y' })).off, true);
  app.store.kv.set('task-server', 'on');
});
