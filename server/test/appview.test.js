// The iPhone app's own copy (iOS app data plan): web/appview.js keeps a person's data in the phone's JavaScript engine,
// takes the live changes and works out the screens — the same answers as the server's routes.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const src = ['rules.js', 'appview.js'].map((f) => fs.readFileSync(new URL('../../web/' + f, import.meta.url), 'utf8')).join(';\n');
const engine = () => vm.runInNewContext(`${src}; ({ E11Rules, E11AppView })`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN, encodeURIComponent });

const data = {
  users: [{ id: 'u1', name: 'Haris A', email: 'h@x.test', role: 'admin', admin: true }],
  projects: [{ id: 'p1', name: 'Northline', color: '#3366ff' }],
  statuses: [], plans: [], meta: {},
  tasks: [{ id: 't1', title: 'Offer pack', projectId: 'p1', assignees: ['u1'], comments: [{ id: 'c1', text: 'Hi', html: 'Hi', authorId: 'u1', at: new Date().toISOString(), attachments: [], parentId: null, reactions: {} }], attachments: [], checklist: [], activity: [], createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() }],
  notifications: [],
};

test('the copy: loaded, a screen worked out from it, a live change applied, saved and loaded again', () => {
  const { E11AppView: V } = engine();
  assert.equal(V.ready(), false); assert.equal(V.screen('task', 't1'), '', 'nothing before the copy is there');
  assert.equal(V.load(JSON.stringify({ rev: 5, me: 'u1', data })), 5);
  let s = JSON.parse(V.screen('task', 't1'));
  assert.equal(s.rev, 5); assert.equal(s.model.title, 'Offer pack'); assert.equal(s.model.client.name, 'Northline');
  const feed = JSON.parse(V.screen('comments', 't1')).model;
  assert.equal(feed.items.length, 1);
  // a change from the live stream: the title, and a new task
  V.apply([{ kind: 'tasks', id: 't1', data: { ...data.tasks[0], title: 'Offer pack v2' } }, { kind: 'tasks', id: 't2', data: { ...data.tasks[0], id: 't2', title: 'New' } }], 7);
  s = JSON.parse(V.screen('task', 't1'));
  assert.equal(s.model.title, 'Offer pack v2'); assert.equal(s.rev, 7);
  assert.equal(JSON.parse(V.screen('task', 't2')).model.title, 'New');
  V.apply([{ kind: 'tasks', id: 't2', deleted: true }], 8);
  assert.equal(JSON.parse(V.screen('task', 't2')).model, null, 'deleted: gone');
  // saved and loaded in a fresh engine: the same
  const saved = V.save();
  const { E11AppView: W } = engine();
  assert.equal(W.load(saved), 8);
  assert.equal(JSON.parse(W.screen('task', 't1')).model.title, 'Offer pack v2');
  assert.ok(JSON.parse(W.screen('home')).model, 'Home too');
});
