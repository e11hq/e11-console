// Content plans (trial, test copy only): who sees them, who makes and changes them, one plan per client per month
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com', EXEC = 'amelia@e11-digital.com', EXEC2 = 'maya@e11-digital.com', MGR = 'aish@e11-digital.com',
  AM = 'areej@e11-digital.com', CD = 'carine@e11-digital.com', PROD = 'ali@e11-digital.com', FREE = 'sam@gmail.com', OFFICE = 'arsal@e11-digital.com';
const USERS = [
  { id: 'u-h', email: OWNER, role: 'admin', active: true },
  { id: 'u-ex', email: EXEC, role: 'social', active: true },
  { id: 'u-ex2', email: EXEC2, role: 'social', active: true },
  { id: 'u-mg', email: MGR, role: 'social', active: true },
  { id: 'u-am', email: AM, role: 'am', active: true },
  { id: 'u-cd', email: CD, role: 'am', active: true },
  { id: 'u-p', email: PROD, role: 'production', active: true },
  { id: 'u-f', email: FREE, role: 'freelancer', active: true, projectIds: ['p-ford'] },
  { id: 'u-o', email: OFFICE, role: 'office_admin', active: true },
];
const DATA = {
  meta: { cdUserId: 'u-cd', socialMgrIds: ['u-mg'] },
  users: USERS,
  projects: [{ id: 'p-ford', name: 'Ford', sections: [], ams: [{ id: 'u-am' }], socials: ['u-ex'] }, { id: 'p-kia', name: 'KIA', sections: [], socials: ['u-ex2'] }, { id: 'p-off', name: 'Old', sections: [], inactive: true, socials: ['u-ex'] }],
  plans: [{ id: 'pl-1', projectId: 'p-ford', month: '2026-12', status: 'draft', createdBy: 'u-ex', posts: [] }, { id: 'pl-off', projectId: 'p-off', month: '2026-12', status: 'draft', createdBy: 'u-ex', posts: [] }],
  statuses: [],
};
const start = async (version) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-plans-'));
  const app = createServer({ dataDir: dir, dev: true, version, adminEmail: OWNER, digest: false, holidays: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  app.store.importAll(JSON.parse(JSON.stringify(DATA)), 'test');
  const call = async (who, p, body) => { const r = await fetch(`http://127.0.0.1:${port}${p}`, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined }); return { status: r.status, body: await r.json() }; };
  const push = (who, changes) => call(who, '/api/push', { changes }).then((r) => r.body.results);
  return { app, dir, call, push };
};
let T;
before(async () => { T = await start('1.6.5-test.1'); });
after(async () => { await T.app.close(); fs.rmSync(T.dir, { recursive: true, force: true }); });
const plan = (id) => T.app.store.get('plans', id);

test('Social, AMs, the CD and Admins see plans; Production, Freelancers and Office Admins don’t; an inactive client’s plan is hidden', async () => {
  for (const who of [EXEC, MGR, AM, CD, OWNER]) {
    const ids = (await T.call(who, '/api/snapshot')).body.data.plans.map((x) => x.id);
    assert.deepEqual(ids, ['pl-1'], who);
  }
  for (const who of [PROD, FREE, OFFICE]) assert.deepEqual((await T.call(who, '/api/snapshot')).body.data.plans, [], who);
});

test('the client’s Social Executive and the Social Manager change a plan; AMs, the CD, Admins and other executives can’t', async () => {
  const base = plan('pl-1');
  const post = { id: 'pp-1', day: '2026-12-02', title: 'National Day', format: 'reel', channels: ['ig'], refs: [] };
  assert.equal((await T.push(EXEC, [{ kind: 'plans', id: 'pl-1', base, data: { ...base, posts: [post] } }]))[0].refused, false, 'executive');
  const b2 = plan('pl-1');
  assert.equal((await T.push(MGR, [{ kind: 'plans', id: 'pl-1', base: b2, data: { ...b2, posts: b2.posts.concat({ ...post, id: 'pp-2' }) } }]))[0].refused, false, 'Social Manager');
  const b3 = plan('pl-1');
  for (const who of [AM, CD, OWNER, EXEC2]) {
    assert.equal((await T.push(who, [{ kind: 'plans', id: 'pl-1', base: b3, data: { ...b3, posts: [] } }]))[0].refused, true, who);
  }
  assert.equal(plan('pl-1').posts.length, 2);
  assert.equal((await T.push(EXEC, [{ kind: 'plans', id: 'pl-1', base: b3, data: { ...b3, month: '2027-01' } }]))[0].refused, true, 'a plan stays with its month');
});

test('starting a plan: your clients only (the Social Manager any), one per client per month', async () => {
  const mk = (id, pid, by, month = '2027-01') => ({ kind: 'plans', id, data: { id, projectId: pid, month, status: 'draft', createdBy: by, posts: [] } });
  assert.equal((await T.push(EXEC, [mk('pl-a', 'p-kia', 'u-ex')]))[0].refused, true, 'not their client');
  assert.equal((await T.push(EXEC2, [mk('pl-b', 'p-kia', 'u-ex2')]))[0].refused, false, 'their client');
  assert.equal((await T.push(MGR, [mk('pl-c', 'p-kia', 'u-mg')]))[0].refused, true, 'that month already has a plan');
  assert.equal((await T.push(MGR, [mk('pl-d', 'p-ford', 'u-mg')]))[0].refused, false, 'the Social Manager: any client');
  assert.equal((await T.push(AM, [mk('pl-e', 'p-ford', 'u-am', '2027-02')]))[0].refused, true, 'AMs don’t make plans');
  assert.equal((await T.push(EXEC, [mk('pl-f', 'p-ford', 'u-mg', '2027-03')]))[0].refused, true, 'made by yourself');
});

test('only Admins pick the Social Manager or a client’s Social people', async () => {
  const meta = T.app.store.get('meta', 'main');
  assert.equal((await T.push(AM, [{ kind: 'meta', id: 'main', base: meta, data: { ...meta, socialMgrIds: ['u-ex'] } }]))[0].refused, true);
  const p = T.app.store.get('projects', 'p-ford');
  assert.equal((await T.push(EXEC, [{ kind: 'projects', id: 'p-ford', base: p, data: { ...p, socials: ['u-ex', 'u-ex2'] } }]))[0].refused, true);
  assert.equal((await T.push(EXEC, [{ kind: 'projects', id: 'p-ford', base: p, data: { ...p, planSkips: ['diwali'] } }]))[0].refused, false, 'skipping an occasion for the client');
  assert.equal((await T.push(OWNER, [{ kind: 'meta', id: 'main', base: meta, data: { ...meta, socialMgrIds: ['u-mg', 'u-ex2'] } }]))[0].refused, false);
});

test('the live site: no content plans (a trial on the test copy only)', async () => {
  const L = await start('1.6.5');
  try {
    const base = L.app.store.get('plans', 'pl-1');
    assert.equal((await L.push(EXEC, [{ kind: 'plans', id: 'pl-1', base, data: { ...base, posts: [{ id: 'x', day: '2026-12-01', title: 'x' }] } }]))[0].refused, true);
  } finally { await L.app.close(); fs.rmSync(L.dir, { recursive: true, force: true }); }
});

test('approval: Social sends; the CD or the Social Manager approves or sends back; nobody approves their own; locked while waiting', async () => {
  const mk = { kind: 'plans', id: 'pl-ap', data: { id: 'pl-ap', projectId: 'p-ford', month: '2027-05', status: 'draft', createdBy: 'u-ex', posts: [{ id: 'p1', day: '2027-05-02', title: 'One' }] } };
  assert.equal((await T.push(EXEC, [mk]))[0].refused, false);
  const cur = () => plan('pl-ap');
  const put = (who, data) => T.push(who, [{ kind: 'plans', id: 'pl-ap', base: cur(), data }]).then((r) => r[0].refused);
  assert.equal(await put(AM, { ...cur(), status: 'review' }), true, 'an AM can’t send it');
  assert.equal(await put(EXEC, { ...cur(), status: 'approved' }), true, 'Social can’t approve');
  assert.equal(await put(EXEC, { ...cur(), status: 'review', review: { to: 'cd', by: 'u-ex', round: 1 } }), false, 'Social sends it');
  assert.equal(await put(EXEC, { ...cur(), posts: [{ ...cur().posts[0], title: 'Changed' }] }), true, 'locked while waiting');
  assert.equal(await put(EXEC, { ...cur(), posts: [{ ...cur().posts[0], check: { state: 'ok', by: 'u-ex' } }] }), true, 'Social can’t mark posts');
  assert.equal(await put(CD, { ...cur(), posts: [{ ...cur().posts[0], check: { state: 'changes', note: 'Shorter', by: 'u-cd' } }] }), false, 'the CD marks a post');
  assert.equal(await put(CD, { ...cur(), posts: [{ ...cur().posts[0], title: 'CD edit' }] }), true, 'the CD doesn’t edit the posts');
  assert.equal(await put(CD, { ...cur(), status: 'changes' }), false, 'the CD sends it back');
  assert.equal(await put(EXEC, { ...cur(), posts: [{ ...cur().posts[0], title: 'Shorter', check: undefined }] }), false, 'Social changes it (and clears the mark)');
  assert.equal(await put(EXEC, { ...cur(), status: 'review', round: 2 }), false, 'and sends it again');
  assert.equal(await put(MGR, { ...cur(), status: 'approved', approval: { by: 'u-mg' } }), false, 'the Social Manager approves (any skeleton waiting)');
  assert.equal(cur().status, 'approved');
  assert.equal(await put(EXEC, { ...cur(), posts: [] }), true, 'approved: locked');
  assert.equal(await put(EXEC, { ...cur(), status: 'draft', approval: null }), false, 'reopened as a draft');
  // made by the Social Manager: only the CD approves
  const own = { kind: 'plans', id: 'pl-own', data: { id: 'pl-own', projectId: 'p-kia', month: '2027-05', status: 'draft', createdBy: 'u-mg', posts: [{ id: 'q', day: '2027-05-03', title: 'Q' }] } };
  assert.equal((await T.push(MGR, [own]))[0].refused, false);
  const o = () => plan('pl-own');
  assert.equal((await T.push(MGR, [{ kind: 'plans', id: 'pl-own', base: o(), data: { ...o(), status: 'review' } }]))[0].refused, false);
  assert.equal((await T.push(MGR, [{ kind: 'plans', id: 'pl-own', base: o(), data: { ...o(), status: 'approved' } }]))[0].refused, true, 'not your own');
  assert.equal((await T.push(CD, [{ kind: 'plans', id: 'pl-own', base: o(), data: { ...o(), status: 'approved' } }]))[0].refused, false, 'the CD');
});

test('the client round: when every task of a plan is complete the plan is client approved, and its PowerPoint goes to Client Assets with the final files', async () => {
  const dir = path.join(T.dir, 'files', 'attachments', 'pl-cr', 'exports');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'Ford – Content plan – June 2027 – Round 1.pptx'), 'pptx');
  fs.mkdirSync(path.join(T.dir, 'files', 'attachments', 't-a'), { recursive: true });
  fs.writeFileSync(path.join(T.dir, 'files', 'attachments', 't-a', 'a.png'), 'png');
  fs.mkdirSync(path.join(T.dir, 'files', 'attachments', 't-b'), { recursive: true });
  fs.writeFileSync(path.join(T.dir, 'files', 'attachments', 't-b', 'b.png'), 'png');
  const exp = { id: 'ex-1', round: 1, at: '2027-05-20T08:00:00Z', by: 'u-ex', pptx: { name: 'Ford – Content plan – June 2027 – Round 1.pptx', path: 'attachments/pl-cr/exports/Ford – Content plan – June 2027 – Round 1.pptx', size: 4 }, pdf: null, posts: ['a', 'b'], line: 0 };
  const task = (id, post) => ({ id, title: `Post ${post}`, projectId: 'p-ford', assignees: ['u-p'], needsCD: true, cdStatus: 'approved', planId: 'pl-cr', planPostId: post, attachments: [{ id: 'f' + id, name: `${post}.png`, path: `attachments/${id}/${post}.png` }], reviews: [{ id: 'r' + id, by: 'u-p', files: ['f' + id], state: 'approved', at: '2027-05-19T08:00:00Z', decidedAt: '2027-05-19T09:00:00Z', decidedBy: 'u-cd' }] });
  T.app.store.apply([
    { kind: 'clients', id: 'cl-ford', data: { id: 'cl-ford', name: 'Ford', dir: 'Clients/Ford', folders: [{ id: 'f-files', name: 'Files', dir: 'Clients/Ford/Files', files: [], auto: true }] } },
    { kind: 'projects', id: 'p-ford', data: { ...T.app.store.get('projects', 'p-ford'), clientId: 'cl-ford' } },
    { kind: 'plans', id: 'pl-cr', data: { id: 'pl-cr', projectId: 'p-ford', month: '2027-06', status: 'approved', createdBy: 'u-ex', posts: [{ id: 'a', day: '2027-06-02', title: 'A', taskId: 't-a' }, { id: 'b', day: '2027-06-05', title: 'B', taskId: 't-b' }], exports: [exp] } },
    { kind: 'tasks', id: 't-a', data: task('t-a', 'a') }, { kind: 'tasks', id: 't-b', data: task('t-b', 'b') },
  ], 'test');
  const done = (id) => { const t = T.app.store.get('tasks', id); return { kind: 'tasks', id, base: t, data: { ...t, done: true, completedAt: new Date().toISOString(), clientApproval: { by: 'u-ex', at: new Date().toISOString() } } }; };
  assert.equal((await T.push(EXEC, [done('t-a')]))[0].refused, false);
  assert.equal(T.app.store.get('plans', 'pl-cr').clientApproved, undefined, 'one post left: not yet');
  let c = T.app.store.get('clients', 'cl-ford');
  const pf = c.folders.find((f) => f.planOf === 'pl-cr');
  assert.ok(pf && pf.name === 'Content plan – June 2027' && pf.parentId === 'f-files', 'the plan’s folder in Files');
  assert.ok(c.folders.some((f) => f.finalOf === 't-a' && f.parentId === pf.id && f.files.length === 1), 'the task’s final files inside it');
  assert.equal((await T.push(EXEC, [done('t-b')]))[0].refused, false);
  const pl = T.app.store.get('plans', 'pl-cr');
  assert.ok(pl.clientApproved && pl.clientApproved.auto, 'every post approved: the plan is client approved');
  c = T.app.store.get('clients', 'cl-ford');
  const pf2 = c.folders.find((f) => f.planOf === 'pl-cr');
  assert.ok(pf2.files.some((f) => /Round 1\.pptx$/.test(f.name)), 'the approved PowerPoint is filed with them');
  assert.ok(c.folders.filter((f) => f.parentId === pf2.id && f.finalOf).length === 2, 'next to a folder per task');
  assert.ok(pl.filedDeck);
  const notes = T.app.store.list('notifications').filter((n) => n.planId === 'pl-cr' && n.kind === 'plan-client').map((n) => n.to).sort();
  assert.deepEqual(notes, ['u-am', 'u-ex2', 'u-mg'].sort(), 'the Social Managers (u-ex2 was made one above) and the AM are told, not the person who did it');
});

test('a new plan can’t carry exports, approvals, tasks or the client’s answers (only the steps and the server write those)', async () => {
  const mk = (id, extra, post) => ({ kind: 'plans', id, data: { id, projectId: 'p-ford', month: '2028-0' + id.slice(-1), status: 'draft', createdBy: 'u-ex', posts: [{ id: 'x', day: '2028-01-02', title: 'X', ...(post || {}) }], ...(extra || {}) } });
  const bad = [
    mk('pl-n1', { exports: [{ id: 'ex', pptx: { path: 'Claims/u-o/r.jpg', name: 'r.jpg' } }] }),
    mk('pl-n2', { clientApproved: { at: 'x', by: 'u-ex' } }),
    mk('pl-n3', { approval: { by: 'u-cd', at: 'x' } }),
    mk('pl-n4', { filedDeck: { at: 'x' } }),
    mk('pl-n5', null, { taskId: 't-other' }),
    mk('pl-n6', null, { client: { state: 'approved' } }),
    mk('pl-n7', null, { check: { state: 'ok' } }),
  ];
  for (const ch of bad) assert.equal((await T.push(EXEC, [ch]))[0].refused, true, ch.id);
  assert.equal((await T.push(EXEC, [mk('pl-n8')]))[0].refused, false, 'a plain new plan is fine');
});

test('a save made from a copy before the server’s own change (an export, client approval) still goes through', async () => {
  T.app.store.apply([{ kind: 'plans', id: 'pl-st', data: { id: 'pl-st', projectId: 'p-ford', month: '2029-01', status: 'approved', createdBy: 'u-ex', posts: [{ id: 'a', day: '2029-01-02', title: 'A' }] } }], 'test');
  const old = T.app.store.get('plans', 'pl-st');
  // the server writes an export meanwhile
  T.app.store.apply([{ kind: 'plans', id: 'pl-st', data: { ...old, exports: [{ id: 'ex-s', round: 1, at: 'x', by: 'u-ex', posts: ['a'] }], log: [{ act: 'export', by: 'u-ex', at: 'x', round: 1 }] } }], 'plans');
  const now = new Date().toISOString();
  const r = await T.push(EXEC, [{ kind: 'plans', id: 'pl-st', base: old, data: { ...old, sent: { round: 1, at: now, by: 'u-ex' }, log: [{ act: 'client-sent', by: 'u-ex', at: now, round: 1 }] } }]);
  assert.equal(r[0].refused, false);
  const pl = T.app.store.get('plans', 'pl-st');
  assert.equal(pl.exports.length, 1, 'the export stays');
  assert.ok(pl.sent, 'and the save is kept');
  // but a made-up export from a stale copy is still refused
  const r2 = await T.push(EXEC, [{ kind: 'plans', id: 'pl-st', base: old, data: { ...old, exports: [{ id: 'ex-fake', pptx: { path: 'Claims/x.jpg' } }] } }]);
  assert.equal(r2[0].refused, true);
});

test('plan reference files go only into a new task or one of the plan’s own, and only by someone who makes tasks', async () => {
  const dir = path.join(T.dir, 'files', 'attachments', 'pl-1');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'ref.png'), 'png');
  T.app.store.apply([{ kind: 'tasks', id: 't-foreign', data: { id: 't-foreign', title: 'Other', projectId: 'p-kia' } }], 'test');
  const files = [{ path: 'attachments/pl-1/ref.png', name: 'ref.png' }];
  assert.equal((await T.call(EXEC, '/api/plan-refs', { planId: 'pl-1', taskId: 't-foreign', files })).status, 403, 'not someone else’s task');
  assert.equal((await T.call(PROD, '/api/plan-refs', { planId: 'pl-1', taskId: 't-newone', files })).status, 403, 'not Production');
  const ok = await T.call(EXEC, '/api/plan-refs', { planId: 'pl-1', taskId: 't-newone', files });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.files.length, 1);
});
