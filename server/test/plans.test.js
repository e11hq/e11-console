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
