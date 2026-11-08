// Socials (Haris 2026-11-08): a Social Executive's Home and My Tasks show the tasks they're assigned to and the tasks they
// created from a content plan; a Social Manager's, the tasks they're assigned to and every task made from a plan by them
// or by any Social Executive. On the plan tasks they have the creator's swipes (Done, Due, Trash); on the tasks they're
// assigned to, their role's. Search: a Social Executive — their clients, their tasks and their plan tasks; a Social
// Manager — every Social Executive's clients, their tasks and the plan tasks. Everyone else as before.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const src = ['rules.js', 'appview.js', 'appme-tasks.js'].map((f) => fs.readFileSync(new URL('../../web/' + f, import.meta.url), 'utf8')).join(';\n');
const engine = () => vm.runInNewContext(`${src}; ({ E11Rules, E11AppView, E11AppMe })`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN, encodeURIComponent, RegExp });

const now = new Date().toISOString(), today = now.slice(0, 10);
const T = (id, o) => ({ id, title: id, projectId: 'p1', sectionId: 's1', assignees: [], comments: [], attachments: [], checklist: [], activity: [], createdAt: now, updatedAt: now, due: today, ...o });
const data = {
  users: [
    { id: 'u-a', name: 'Haris Admin', email: 'a@x.test', role: 'admin', active: true },
    { id: 'u-se', name: 'Sara Exec', email: 'se@x.test', role: 'social', active: true },
    { id: 'u-se2', name: 'Omar Exec', email: 'se2@x.test', role: 'social', active: true },
    { id: 'u-sm', name: 'Mona Manager', email: 'sm@x.test', role: 'social', active: true },
    { id: 'u-p', name: 'Ali Designer', email: 'p@x.test', role: 'production', active: true },
    { id: 'u-am', name: 'Areej AM', email: 'am@x.test', role: 'am', active: true },
    { id: 'u-am0', name: 'Nour AM', email: 'am0@x.test', role: 'am', active: true },
    { id: 'u-y', name: 'Yousef Prod', email: 'y@x.test', role: 'production', active: true },
  ],
  projects: [{ id: 'p1', name: 'Northline', color: '#3366ff', socials: ['u-se'], sections: [{ id: 's1', name: 'To do' }] }, { id: 'p2', name: 'Orbit', color: '#ff3366', socials: ['u-se2'], ams: [{ id: 'u-am' }], sections: [{ id: 's1', name: 'To do' }] }],
  statuses: [], meta: { socialMgrIds: ['u-sm'] },
  plans: [{ id: 'pl1', projectId: 'p1', month: today.slice(0, 7), posts: [] }, { id: 'pl2', projectId: 'p2', month: today.slice(0, 7), posts: [] }],
  tasks: [
    T('mine-se', { assignees: ['u-se'], createdBy: 'u-a' }),                       // Sara is assigned
    T('plan-se', { planId: 'pl1', createdBy: 'u-se', assignees: ['u-p'] }),         // Sara made it from a plan
    T('plan-se2', { planId: 'pl2', projectId: 'p2', createdBy: 'u-se2', assignees: ['u-p'] }),   // Omar made it from a plan
    T('plan-sm', { planId: 'pl1', createdBy: 'u-sm', assignees: ['u-p'] }),         // Mona made it from a plan
    T('plan-admin', { planId: 'pl1', createdBy: 'u-a', assignees: ['u-p'] }),       // an Admin made it from a plan
    T('other', { createdBy: 'u-a', assignees: ['u-p'] }),                           // nothing to do with them
    T('done-plan-se', { planId: 'pl1', createdBy: 'u-se', assignees: ['u-p'], done: true, completedAt: now }),
  ],
  notifications: [],
};
const as = (me) => { const { E11Rules: R, E11AppView: V, E11AppMe: M } = engine(); V.load(JSON.stringify({ rev: 1, me, data })); return { R, V, M }; };
const ids = (m) => (m.groups || []).flatMap((g) => g.cards || []).map((c) => c.id).sort();
const card = (m, id) => (m.groups || []).flatMap((g) => g.cards || []).find((c) => c.id === id);
const screen = (V, k, a) => JSON.parse(V.screen(k, a)).model;

test('a Social Executive: their tasks and the plan tasks they made — Home, My Tasks All and Done', () => {
  const { V } = as('u-se');
  assert.deepEqual(ids(screen(V, 'home')), ['mine-se', 'plan-se']);
  assert.deepEqual(ids(screen(V, 'mytasks', JSON.stringify({ tab: 'all' }))), ['mine-se', 'plan-se']);
  assert.deepEqual(ids(screen(V, 'mytasks', JSON.stringify({ tab: 'done' }))), ['done-plan-se']);
});

test('a Social Manager: their tasks and every plan task by them or a Social Executive', () => {
  const { V } = as('u-sm');
  assert.deepEqual(ids(screen(V, 'home')), ['plan-admin', 'plan-se', 'plan-se2', 'plan-sm']);   // (any plan task, an Admin's too)
  assert.deepEqual(ids(screen(V, 'mytasks', JSON.stringify({ tab: 'done' }))), ['done-plan-se']);
});

test('swipes: the creator\'s on plan tasks, their role\'s on tasks they\'re assigned to', () => {
  let { V } = as('u-se');
  let h = screen(V, 'home');
  assert.equal(card(h, 'plan-se').canDue, true, 'plan task: Due');
  assert.equal(card(h, 'plan-se').canDelete, true, 'plan task: Trash');
  assert.equal(card(h, 'mine-se').canDue, false, 'assigned: no Due');
  assert.equal(card(h, 'mine-se').canDelete, false, 'assigned: no Trash');
  ({ V } = as('u-sm'));
  h = screen(V, 'home');
  assert.equal(card(h, 'plan-se2').canDue, true, 'a Social Executive\'s plan task: Due for the manager');
  assert.equal(card(h, 'plan-se2').canDelete, true, 'a Social Executive\'s plan task: Trash for the manager');
});

test('search: a Social Executive finds their clients and tasks; a Social Manager every Social Executive\'s clients', () => {
  let { R, M } = as('u-se');
  let s = M.search(R, data, 'u-se', Date.now(), 'Northline');
  assert.deepEqual([...s.tasks.map((t) => t.id)].sort(), ['done-plan-se', 'mine-se', 'plan-se']);
  assert.ok(s.clients.some((c) => c.name === 'Northline'), 'their client');
  s = M.search(R, data, 'u-se', Date.now(), 'Orbit');
  assert.equal(s.clients.length, 0, 'not their client'); assert.equal(s.tasks.length, 0);
  s = M.search(R, data, 'u-se', Date.now(), 'Ali');   // a person: only on their tasks
  assert.deepEqual([...s.tasks.map((t) => t.id)].sort(), ['done-plan-se', 'plan-se']);
  ({ R, M } = as('u-sm'));
  s = M.search(R, data, 'u-sm', Date.now(), 'Northline');
  assert.ok(s.clients.some((c) => c.name === 'Northline'), 'a Social Executive\'s client, for the Social Manager');
  assert.ok(M.search(R, data, 'u-sm', Date.now(), 'Orbit').clients.some((c) => c.name === 'Orbit'), 'every Social Executive\'s');
  assert.deepEqual([...s.tasks.map((t) => t.id)].sort(), ['done-plan-se', 'plan-admin', 'plan-se', 'plan-sm']);
});

test('everyone else as before: an Admin\'s search finds every client and task', () => {
  const { R, M } = as('u-a');
  const s = M.search(R, data, 'u-a', Date.now(), 'Northline');
  assert.ok(s.clients.length >= 1);
  assert.ok(s.tasks.length >= 6);
});

// a client's page and the Clients list's counts, as each role's lists have them (Haris 2026-11-08): Admins and the CD
// everything; Production / Socials their own lists'
test('a client\'s page: everything for an Admin, each one\'s own tasks for the rest', () => {
  const page = (me) => { const { V } = as(me); return screen(V, 'clients', JSON.stringify({ view: 'client', id: 'p1', done: true })); };
  assert.deepEqual(ids(page('u-a')), ['done-plan-se', 'mine-se', 'other', 'plan-admin', 'plan-se', 'plan-sm']);
  assert.deepEqual(ids(page('u-se')), ['done-plan-se', 'mine-se', 'plan-se']);
  assert.deepEqual(ids(page('u-sm')), ['done-plan-se', 'plan-admin', 'plan-se', 'plan-sm']);
  assert.deepEqual(ids(page('u-p')), ['done-plan-se', 'other', 'plan-admin', 'plan-se', 'plan-sm']);
  const { V } = as('u-se');
  const row = screen(V, 'clients').rows.find((r) => r.id === 'p1');
  assert.equal(row.open, 2, 'the list\'s count: the same open tasks as the page');
});

// the Clients list (Haris 2026-11-08): an AM only the clients they look after — none given yet, none; Production only the
// clients they work on
test('the Clients list: an AM\'s own clients, none when they have none; Production only where they work', () => {
  const rows = (me) => { const { V } = as(me); return [...screen(V, 'clients').rows.map((r) => r.id)].sort(); };
  assert.deepEqual(rows('u-am'), ['p2']);
  assert.deepEqual(rows('u-am0'), [], 'an AM given no clients yet: none');
  assert.deepEqual(rows('u-y'), [], 'Production with nothing on a client: not listed');
  // @mentioned on a task: that client listed, and its page has that task — for every role
  const m = JSON.parse(JSON.stringify(data));
  m.tasks.find((t) => t.id === 'other').comments = [{ id: 'c1', html: '<span class="mention" data-user="u-y">@Yousef</span> <span class="mention" data-user="u-am0">@Nour</span>', text: '@Yousef @Nour', authorId: 'u-a', at: now }];
  for (const who of ['u-y', 'u-am0']) {
    const { E11AppView: V } = engine(); V.load(JSON.stringify({ rev: 1, me: who, data: m }));
    assert.deepEqual([...screen(V, 'clients').rows.map((r) => r.id)], ['p1'], who + ': the client they\'re mentioned on');
    assert.deepEqual(ids(screen(V, 'clients', JSON.stringify({ view: 'client', id: 'p1', done: true }))), ['other'], who + ': the task they\'re mentioned in');
  }
  // the Guardian of a task: the same
  const g = JSON.parse(JSON.stringify(data));
  g.tasks.find((t) => t.id === 'other').guardian = 'u-am0';
  { const { E11AppView: V } = engine(); V.load(JSON.stringify({ rev: 1, me: 'u-am0', data: g }));
    assert.deepEqual([...screen(V, 'clients').rows.map((r) => r.id)], ['p1'], 'the client they\'re Guardian on');
    assert.deepEqual(ids(screen(V, 'clients', JSON.stringify({ view: 'client', id: 'p1', done: true }))), ['other'], 'the task they\'re Guardian of'); }
  assert.deepEqual(rows('u-p'), ['p1', 'p2']);
  assert.deepEqual(rows('u-a'), ['p1', 'p2']);
});

// a task's Guardian (Production, Social, Freelancers): on their Home, My Tasks All / Done and search too (Haris 2026-11-08)
test('a Guardian: the task on Home, My Tasks All and Done, and in search', () => {
  const g = JSON.parse(JSON.stringify(data));
  g.tasks.find((t) => t.id === 'other').guardian = 'u-y';
  g.tasks.push(T('done-guard', { createdBy: 'u-a', assignees: ['u-p'], guardian: 'u-y', done: true, completedAt: now }));
  g.tasks.push(T('guard-se', { createdBy: 'u-a', assignees: ['u-p'], guardian: 'u-se', title: 'Zebra launch' }));
  let { E11AppView: V, E11Rules: R, E11AppMe: M } = engine(); V.load(JSON.stringify({ rev: 1, me: 'u-y', data: g }));
  assert.deepEqual(ids(screen(V, 'home')), ['other']);
  assert.deepEqual(ids(screen(V, 'mytasks', JSON.stringify({ tab: 'all' }))), ['other']);
  assert.deepEqual(ids(screen(V, 'mytasks', JSON.stringify({ tab: 'done' }))), ['done-guard']);
  assert.deepEqual([...M.search(R, g, 'u-y', Date.now(), 'other').tasks.map((t) => t.id)], ['other']);
  ({ E11AppView: V, E11Rules: R, E11AppMe: M } = engine()); V.load(JSON.stringify({ rev: 1, me: 'u-se', data: g }));
  assert.ok(ids(screen(V, 'home')).includes('guard-se'), 'a Social Executive who is Guardian: on Home');
  assert.deepEqual([...M.search(R, g, 'u-se', Date.now(), 'Zebra').tasks.map((t) => t.id)], ['guard-se'], 'and in search');
});
