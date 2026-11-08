// Socials (Haris 2026-11-08): a Social Executive's Home and My Tasks show the tasks they're assigned to and the tasks they
// created from a content plan; a Social Manager's, the tasks they're assigned to and every task made from a plan by them
// or by any Social Executive. On the plan tasks they have the creator's swipes (Done, Due, Trash); on the tasks they're
// assigned to, their role's. Search: a Social Executive — their clients, their tasks and their plan tasks; a Social
// Manager — no clients, their tasks and the plan tasks. Everyone else as before.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const src = ['rules.js', 'appview.js', 'appme-tasks.js'].map((f) => fs.readFileSync(new URL('../../web/' + f, import.meta.url), 'utf8')).join(';\n');
const engine = () => vm.runInNewContext(`${src}; ({ E11Rules, E11AppView, E11AppMe })`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN, encodeURIComponent, RegExp });

const now = new Date().toISOString(), today = now.slice(0, 10);
const T = (id, o) => ({ id, title: id, projectId: 'p1', assignees: [], comments: [], attachments: [], checklist: [], activity: [], createdAt: now, updatedAt: now, due: today, ...o });
const data = {
  users: [
    { id: 'u-a', name: 'Haris Admin', email: 'a@x.test', role: 'admin', active: true },
    { id: 'u-se', name: 'Sara Exec', email: 'se@x.test', role: 'social', active: true },
    { id: 'u-se2', name: 'Omar Exec', email: 'se2@x.test', role: 'social', active: true },
    { id: 'u-sm', name: 'Mona Manager', email: 'sm@x.test', role: 'social', active: true },
    { id: 'u-p', name: 'Ali Designer', email: 'p@x.test', role: 'production', active: true },
  ],
  projects: [{ id: 'p1', name: 'Northline', color: '#3366ff', socials: ['u-se'] }, { id: 'p2', name: 'Orbit', color: '#ff3366', socials: ['u-se2'] }],
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
  assert.deepEqual(ids(screen(V, 'home')), ['plan-se', 'plan-se2', 'plan-sm']);
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

test('search: a Social Executive finds their clients and tasks; a Social Manager no clients', () => {
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
  assert.equal(s.clients.length, 0, 'no clients for a Social Manager');
  assert.deepEqual([...s.tasks.map((t) => t.id)].sort(), ['done-plan-se', 'plan-se', 'plan-sm']);
});

test('everyone else as before: an Admin\'s search finds every client and task', () => {
  const { R, M } = as('u-a');
  const s = M.search(R, data, 'u-a', Date.now(), 'Northline');
  assert.ok(s.clients.length >= 1);
  assert.ok(s.tasks.length >= 6);
});
