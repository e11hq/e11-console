// The iPhone app's Home straight from the server: GET /api/home and its actions (POST /api/home/act) — Done (and why
// not), the client approval question, reopen, Due, Delete and Undo, who may do what, and a retried action done once.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const clock = Date.parse('2026-10-29T08:00:00Z'); // Thursday 29 Oct, 12:00 Dubai
let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11h-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    meta: { cdUserId: 'u-cd' },
    users: [
      { id: 'u-adm', email: 'adm@e11-digital.com', role: 'admin', active: true, name: 'Haris' },
      { id: 'u-am', email: 'am@e11-digital.com', role: 'am', active: true, name: 'Leila' },
      { id: 'u-am2', email: 'am2@e11-digital.com', role: 'am', active: true, name: 'Omar' },
      { id: 'u-prod', email: 'prod@e11-digital.com', role: 'production', active: true, name: 'Yousef A' },
      { id: 'u-cd', email: 'cd@e11-digital.com', role: 'production', active: true, name: 'Carine' },
    ],
    projects: [
      { id: 'p1', name: 'Northline', color: '#3a7bd5', ams: [{ id: 'u-am' }], sections: [{ id: 's1', name: 'To do', color: '#87909e' }, { id: 's2', name: 'In progress', color: '#a875ff' }, { id: 's3', name: 'Done', color: '#3ddc97' }] },
      { id: 'p2', name: 'Fortis', color: '#f2a03e', ams: [{ id: 'u-am2' }], sections: [{ id: 'q1', name: 'To do', color: '#87909e' }, { id: 'q3', name: 'Done', color: '#3ddc97' }] },
    ],
    tasks: [
      { id: 't1', projectId: 'p1', sectionId: 's2', title: 'Offer pack', assignees: ['u-prod'], createdBy: 'u-am', due: '2026-10-29', comments: [], activity: [] },
      { id: 't2', projectId: 'p1', sectionId: 's3', title: 'Ready', assignees: ['u-prod'], createdBy: 'u-am', due: '2026-10-29', comments: [], activity: [] },
      { id: 't3', projectId: 'p1', sectionId: 's3', title: 'CD approved', assignees: ['u-prod'], createdBy: 'u-am', due: '2026-10-28', needsCD: true, cdStatus: 'approved', reviews: [{ by: 'u-prod', state: 'approved', epoch: 0, decidedAt: '2026-10-28T10:00:00Z' }], comments: [], activity: [] },
      { id: 't4', projectId: 'p2', sectionId: 'q3', title: 'Other client', assignees: ['u-prod'], createdBy: 'u-am2', due: '2026-10-29', comments: [], activity: [] },
      { id: 't5', projectId: 'p1', sectionId: 's2', title: 'To delete', assignees: ['u-prod'], createdBy: 'u-am', due: '2026-10-30', comments: [], activity: [] },
    ],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const home = async (who) => (await (await fetch(base + '/api/home', { headers: { 'X-Dev-Email': who } })).json());
const act = async (who, body) => (await (await fetch(base + '/api/home/act', { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify(body) })).json());
const T = (id) => app.store.get('tasks', id);
const notesFor = (id) => app.store.list('notifications').filter((n) => n.taskId === id);

test('Home: the AM\'s My Day with what they may do on each card', async () => {
  const r = await home('am@e11-digital.com');
  assert.equal(r.ok, true);
  assert.equal(r.home.title, 'My Day');
  assert.equal(r.home.date, 'Thursday, October 29');
  const cards = r.home.groups.flatMap((g) => g.cards);
  const c1 = cards.find((c) => c.id === 't1');
  assert.equal(c1.canDue, true); assert.equal(c1.doneReady, false); assert.equal(c1.why, 'Set the status to Done first');
  assert.ok(!cards.some((c) => c.id === 't4'), 'another AM\'s client is not on their Home');
});

test('Done: not ready → why; ready → completed, logged, the people on it told', async () => {
  let r = await act('am@e11-digital.com', { act: 'done', id: 't1' });
  assert.equal(r.ok, false); assert.equal(r.error, 'Set the status to Done first');
  assert.equal(T('t1').done, undefined);
  r = await act('am@e11-digital.com', { act: 'done', id: 't2', op: 'op-1' });
  assert.equal(r.ok, true); assert.deepEqual(r.messages, ['Task completed']);
  assert.equal(T('t2').done, true); assert.ok(T('t2').completedAt);
  assert.equal(T('t2').activity.at(-1).text, 'completed this task'); assert.equal(T('t2').activity.at(-1).actor, 'u-am');
  assert.ok(notesFor('t2').some((n) => n.to === 'u-prod' && n.kind === 'done' && n.text === 'completed'), 'the assignee is told');
  assert.ok(r.home.groups.find((g) => g.name === 'Completed today').cards.some((c) => c.id === 't2'), 'the fresh Home comes back');
  // the same action again (a retry after a lost answer) is done once
  const n = T('t2').activity.length;
  r = await act('am@e11-digital.com', { act: 'done', id: 't2', op: 'op-1' });
  assert.equal(r.ok, true); assert.equal(T('t2').activity.length, n);
});

test('Done on a CD-approved task asks about the client\'s approval first', async () => {
  let r = await act('am@e11-digital.com', { act: 'done', id: 't3' });
  assert.equal(r.ok, false); assert.equal(r.need, 'clientApproval');
  r = await act('am@e11-digital.com', { act: 'done', id: 't3', clientApproval: 'none' });
  assert.equal(r.ok, true);
  assert.equal(T('t3').done, true); assert.equal(T('t3').clientApproval.none, true);
  assert.ok(T('t3').activity.some((a) => /client approval isn’t needed/.test(a.text)));
});

test('Reopen and Due', async () => {
  let r = await act('am@e11-digital.com', { act: 'reopen', id: 't2' });
  assert.equal(r.ok, true); assert.equal(T('t2').done, false);
  r = await act('am@e11-digital.com', { act: 'due', id: 't1', due: '2026-11-23' });
  assert.equal(r.ok, true); assert.equal(T('t1').due, '2026-11-23');
  assert.match(T('t1').activity.at(-1).text, /changed the <b>due date<\/b>.*Oct 29.*Nov 23/);
  assert.ok(notesFor('t1').some((n) => n.to === 'u-prod' && n.kind === 'due'));
  r = await act('prod@e11-digital.com', { act: 'due', id: 't1', due: '2026-11-24' });
  assert.equal(r.ok, false, 'Production don\'t change dates'); assert.equal(T('t1').due, '2026-11-23');
});

test('An AM on another AM\'s client: view only', async () => {
  const r = await act('am@e11-digital.com', { act: 'done', id: 't4' });
  assert.equal(r.ok, false); assert.equal(T('t4').done, undefined);
});

test('Delete → the Trash, and Undo brings it back', async () => {
  let r = await act('prod@e11-digital.com', { act: 'delete', id: 't5' });
  assert.equal(r.ok, false, 'Production don\'t delete tasks');
  r = await act('am@e11-digital.com', { act: 'delete', id: 't5' });
  assert.equal(r.ok, true); assert.ok(r.undo);
  assert.equal(T('t5'), null);
  const it = app.store.get('trash', r.undo);
  assert.equal(it.type, 'task'); assert.equal(it.deletedBy, 'u-am'); assert.equal(it.data.tasks[0].id, 't5');
  assert.ok(notesFor('t5').some((n) => n.to === 'u-prod' && n.kind === 'trash'));
  r = await act('am@e11-digital.com', { act: 'undoDelete', trashId: it.id });
  assert.equal(r.ok, true); assert.equal(T('t5').title, 'To delete'); assert.equal(app.store.get('trash', it.id), null);
});

test('The switch sends the app back to the page', async () => {
  app.store.kv.set('home-server', 'off');
  const r = await home('am@e11-digital.com');
  assert.equal(r.off, true); assert.equal(r.home, undefined);
  app.store.kv.set('home-server', 'on');
});
