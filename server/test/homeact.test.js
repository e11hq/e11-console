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
  assert.equal(c1.canDue, true); assert.equal(c1.doneReady, true, 'Done also moves it to the Done status'); assert.equal(c1.why, '');
  assert.ok(!cards.some((c) => c.id === 't4'), 'another AM\'s client is not on their Home');
});

test('Done: ready → completed, logged, the people on it told', async () => {
  let r = await act('am@e11-digital.com', { act: 'done', id: 't2', op: 'op-1' });
  assert.equal(r.ok, true); assert.deepEqual(r.messages, ['Task completed']);
  assert.equal(T('t2').done, true); assert.ok(T('t2').completedAt);
  assert.equal(T('t2').activity.at(-1).text, 'completed this task'); assert.equal(T('t2').activity.at(-1).actor, 'u-am');
  assert.ok(notesFor('t2').some((n) => n.to === 'u-prod' && n.kind === 'done' && n.text === 'completed'), 'the assignee is told');
  assert.ok(r.home && !r.home.groups.some((g) => g.cards.some((c) => c.id === 't2')), 'the fresh Home comes back, the completed task gone from it');
  assert.ok(!r.home.groups.some((g) => ['In progress', 'Completed today'].includes(g.name)));
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

test('Refused by the server\'s own checks: nothing saved, nobody told', async () => {
  app.store.apply([{ kind: 'users', id: 'u-off', data: { id: 'u-off', email: 'off@e11-digital.com', role: 'office_admin', active: true, name: 'Office' } }], 'test');
  const n0 = app.store.list('notifications').length;
  const r = await act('off@e11-digital.com', { act: 'reopen', id: 't3' });
  assert.equal(r.ok, false);
  assert.equal(T('t3').done, true);
  assert.equal(app.store.list('notifications').length, n0);
});

test('Undo by someone who isn\'t a manager (the CD) works and empties the Trash entry', async () => {
  app.store.apply([{ kind: 'tasks', id: 't9', data: { id: 't9', projectId: 'p1', sectionId: 's2', title: 'CD made', assignees: ['u-prod'], createdBy: 'u-cd', comments: [], activity: [] } }], 'test');
  let r = await act('cd@e11-digital.com', { act: 'delete', id: 't9' });
  assert.equal(r.ok, true, JSON.stringify(r));
  r = await act('cd@e11-digital.com', { act: 'undoDelete', trashId: r.undo });
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(T('t9').title, 'CD made');
  assert.equal(app.store.list('trash').filter((x) => x.key === 'tasks:t9').length, 0);
});

test('A date that isn\'t one is refused', async () => {
  const r = await act('am@e11-digital.com', { act: 'due', id: 't1', due: '2026-13-45' });
  assert.equal(r.ok, false); assert.equal(T('t1').due, '2026-11-23');
});

test('The shared rules switch notifications off by the same groups as the profile page (app.js NOTIF_TYPES)', async () => {
  const { createRequire } = await import('node:module');
  const R = createRequire(import.meta.url)('../../web/rules.js');
  const groups = R.NOTIF_GROUPS_OF();
  const src = fs.readFileSync(new URL('../../web/app.js', import.meta.url), 'utf8');
  const block = src.slice(src.indexOf('const NOTIF_TYPES = ['), src.indexOf('];', src.indexOf('const NOTIF_TYPES = [')));
  const want = {};
  for (const m of block.matchAll(/\{ k: '([^']+)', kinds: \[([^\]]*)\]/g)) for (const kind of m[2].match(/'([^']+)'/g).map((x) => x.slice(1, -1))) want[kind] = m[1];
  assert.ok(Object.keys(want).length > 10);
  assert.deepEqual({ ...groups }, want);
});

test('Done on a task still in progress: to the Done status and complete, in one go; CD review in the way → why', async () => {
  app.store.apply([
    { kind: 'tasks', id: 't10', data: { id: 't10', projectId: 'p1', sectionId: 's2', title: 'Mid way', assignees: ['u-prod'], createdBy: 'u-am', comments: [], activity: [] } },
    { kind: 'tasks', id: 't11', data: { id: 't11', projectId: 'p1', sectionId: 's2', title: 'Needs CD', assignees: ['u-prod'], createdBy: 'u-am', needsCD: true, comments: [], activity: [] } },
    { kind: 'tasks', id: 't12', data: { id: 't12', projectId: 'p1', sectionId: 's2', title: 'With the CD', assignees: ['u-prod'], createdBy: 'u-am', needsCD: true, reviews: [{ by: 'u-prod', state: 'pending', epoch: 0 }], comments: [], activity: [] } },
  ], 'test');
  const n0 = notesFor('t10').length;
  let r = await act('am@e11-digital.com', { act: 'done', id: 't10' });
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.equal(T('t10').sectionId, 's3'); assert.equal(T('t10').done, true);
  assert.deepEqual(T('t10').activity.map((a) => a.text.replace(/<[^>]+>/g, '')), ['changed the status In progress→Done', 'completed this task']);
  assert.deepEqual(notesFor('t10').slice(n0).map((n) => n.kind), ['done'], 'one notification: completed');
  r = await act('am@e11-digital.com', { act: 'done', id: 't11' });
  assert.equal(r.ok, false); assert.equal(r.error, 'Waiting for CD approval'); assert.equal(T('t11').sectionId, 's2');
  r = await act('am@e11-digital.com', { act: 'done', id: 't12' });
  assert.equal(r.ok, false); assert.equal(r.error, 'Files are with the CD for review'); assert.equal(T('t12').done, undefined);
});

test('Today: no heading of its own, its tasks by priority in runs under their client, each card one line', async () => {
  app.store.apply([
    { kind: 'projects', id: 'p3', data: { id: 'p3', name: 'Deepal', color: '#3366ff', ams: [{ id: 'u-am' }], sections: [{ id: 'd1', name: 'In progress', color: '#a875ff' }, { id: 'd3', name: 'Done', color: '#3ddc97' }] } },
    { kind: 'tasks', id: 'a1', data: { id: 'a1', projectId: 'p1', sectionId: 's2', title: 'F1', assignees: ['u-prod'], createdBy: 'u-am', due: '2026-10-29', prio: { 'u-am': 1 }, comments: [{ id: 'c' }], activity: [] } },
    { kind: 'tasks', id: 'a2', data: { id: 'a2', projectId: 'p3', sectionId: 'd1', title: 'D2', assignees: ['u-prod'], createdBy: 'u-am', due: '2026-10-29', prio: { 'u-am': 2 }, comments: [], activity: [] } },
    { kind: 'tasks', id: 'a3', data: { id: 'a3', projectId: 'p1', sectionId: 's2', title: 'F3', assignees: ['u-prod'], createdBy: 'u-am', due: '2026-10-29', prio: { 'u-am': 3 }, comments: [], activity: [] } },
  ], 'test');
  const h = (await home('am@e11-digital.com')).home;
  assert.equal(h.groups[0].anchor, true); assert.equal(h.groups[0].name, 'Today');
  const runs = h.groups.filter((g) => g.today);
  assert.deepEqual(runs.slice(0, 3).map((g) => [g.name, g.cards[0].id, g.n === g.cards.length]), [['Northline', 'a1', true], ['Deepal', 'a2', true], ['Northline', 'a3', true]]);
  assert.deepEqual(runs[0].dot, [58, 123, 213]);
  const c = runs[0].cards[0];
  assert.equal(c.inline, true);
  assert.deepEqual(c.meta.map((m) => m.t), ['In progress', '1 comment'], 'no client, no date');
});
