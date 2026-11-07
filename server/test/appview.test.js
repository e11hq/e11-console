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

// one thing changed on the phone at once (the iPhone app's new due date), and put back
import { createRequire } from 'node:module';
test('appview patch: changed at once, the old one given back', () => {
  const V = createRequire(import.meta.url)('../../web/appview.js');
  V.load({ ok: true, rev: 3, me: 'u1', data: { tasks: [{ id: 't1', title: 'A', due: '2026-11-07' }], meta: {} } });
  const undo = V.patch('tasks', 't1', { due: '2026-11-08' });
  assert.equal(JSON.parse(V.save()).data.tasks[0].due, '2026-11-08');
  V.apply(JSON.parse(undo), 0);
  assert.equal(JSON.parse(V.save()).data.tasks[0].due, '2026-11-07');
  V.patch('tasks', 't1', { due: null });
  assert.equal(JSON.parse(V.save()).data.tasks[0].due, undefined);
  assert.equal(V.patch('tasks', 'nope', { due: 'x' }), null);
});

// the iPhone app does an action on its own copy first (localAct) — exactly what the server's homeAct does
test('localAct: the same change on the phone as on the server, and the way back', () => {
  const d0 = JSON.parse(JSON.stringify(data));
  d0.tasks[0].checklist = [{ id: 'k1', text: 'Logo', done: false }];
  d0.projects[0].sections = [{ id: 's1', name: 'To do', color: '#888' }, { id: 's2', name: 'Done', color: '#3d9' }]; d0.tasks[0].sectionId = 's1';
  const strip = (t) => JSON.parse(JSON.stringify(t, (k, v) => (k === 'at' || k === 'id' && typeof v === 'string' && /^local-|^[a-z0-9]{12,}$/.test(v) || k === 'updatedAt' || k === 'doneAt' || k === 'completedAt' ? undefined : v)));
  for (const body of [{ act: 'due', id: 't1', due: '2026-11-20' }, { act: 'check', id: 't1', value: 'k1' }, { act: 'done', id: 't1' }]) {
    const { E11AppView: P, E11Rules: R } = engine();
    P.load(JSON.stringify({ rev: 1, me: 'u1', data: d0 }));
    const r = JSON.parse(P.localAct(body));
    assert.equal(r.ok, true, body.act);
    const phone = JSON.parse(P.save()).data.tasks.find((x) => x.id === 't1');
    const env = { nowISO: () => new Date().toISOString(), nowMs: () => Date.now(), uid: () => Date.now().toString(36) + 'abcdef' };
    const s = P.homeAct(R, JSON.parse(JSON.stringify(d0)), d0.users[0], body, env, null);
    const server = s.changes.find((c) => c.kind === 'tasks' && c.id === 't1').data;
    assert.deepEqual(strip(phone), strip(server), body.act);
    // the way back: as it was
    P.apply(r.undo, 0);
    assert.deepEqual(strip(JSON.parse(P.save()).data.tasks.find((x) => x.id === 't1')), strip(d0.tasks[0]), body.act + ' undone');
  }
  // what only the server does: not done on the phone
  const { E11AppView: P } = engine();
  P.load(JSON.stringify({ rev: 1, me: 'u1', data: d0 }));
  assert.equal(P.localAct({ act: 'comment', id: 't1', text: 'x' }), null);
});
