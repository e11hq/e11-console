// Widgets: each person's summary for the categories they may see (/api/widget)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const clock = Date.parse('2026-10-29T08:00:00Z'); // Thursday 29 Oct, 12:00 Dubai
let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11w-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    meta: { socialMgrIds: ['u-mgr'], cdUserId: 'u-cd' },
    users: [
      { id: 'u-prod', email: 'prod@e11-digital.com', role: 'production', active: true, name: 'Yousef A' },
      { id: 'u-soc', email: 'soc@e11-digital.com', role: 'social', active: true, name: 'Zahir H' },
      { id: 'u-mgr', email: 'mgr@e11-digital.com', role: 'social', active: true, name: 'Maya M' },
      { id: 'u-fin', email: 'fin@e11-digital.com', role: 'finance_viewer', active: true, name: 'Fatima F' },
      { id: 'u-adm', email: 'adm@e11-digital.com', role: 'admin', active: true, name: 'Haris' },
      { id: 'u-office', email: 'office@e11-digital.com', role: 'office_admin', active: true, name: 'Office', fin: 'viewer' },
      { id: 'u-cd', email: 'cd@e11-digital.com', role: 'production', active: true, name: 'Carine' },
      { id: 'u-am', email: 'am@e11-digital.com', role: 'am', active: true, name: 'Leila' },
    ],
    projects: [
      { id: 'p1', name: 'Northline', color: '#3a7bd5', socials: ['u-soc'] },
      { id: 'p2', name: 'Fortis', color: '#f2a03e', socials: [], ams: [{ id: 'u-am' }] },
      { id: 'p3', name: 'Old', color: '#000', inactive: true, socials: ['u-soc'] },
    ],
    tasks: [
      { id: 't1', projectId: 'p1', title: 'Offer Pack', assignees: ['u-prod'], due: '2026-10-29', finance: 'To be invoiced' },
      { id: 't2', projectId: 'p2', title: 'Campaign', assignees: ['u-prod'], due: '2026-10-27', finance: 'LPO Pending' },
      { id: 't3', projectId: 'p1', title: 'Done today', assignees: ['u-prod'], due: '2026-10-29', done: true, finance: 'Invoiced' },
      { id: 't4', projectId: 'p1', title: 'Review', assignees: ['u-prod'], needsCD: true, reviews: [{ by: 'u-prod', state: 'pending', epoch: 0 }], due: '2026-10-30' },
      { id: 't5', projectId: 'p3', title: 'Hidden client', assignees: ['u-prod'], due: '2026-10-29', finance: 'To be invoiced' },
      { id: 't6', projectId: 'p1', title: 'Sub', parentId: 't1', assignees: ['u-prod'], due: '2026-10-29' },
      { id: 't7', projectId: 'p2', title: 'AM client task', assignees: ['u-cd'], due: '2026-10-29', createdBy: 'u-adm' },
      { id: 't8', projectId: 'p1', title: 'Admin made', assignees: ['u-cd'], due: '2026-10-28', createdBy: 'u-adm' },
    ],
    plans: [
      { id: 'pl1', projectId: 'p1', month: '2026-11', status: 'approved', posts: [{ id: 'x1', day: '2026-10-29', title: 'Reel', channels: ['IG'] }] },
      { id: 'pl2', projectId: 'p2', month: '2026-11', status: 'changes', log: [{ act: 'changes', by: 'u-cd', note: 'Tighten copy' }], posts: [] },
      { id: 'pl3', projectId: 'p3', month: '2026-11', status: 'draft', posts: [{ id: 'x2', day: '2026-10-29', title: 'Hidden' }] },
    ],
    finance: [
      { id: 'f1', type: 'expense', name: 'Printer', amount: 1200, date: '2026-10-05' },
      { id: 'f2', type: 'reimb', userId: 'u-prod', amount: 300.5, date: '2026-10-20' },
      { id: 'f3', type: 'expense', name: 'Last month', amount: 999, date: '2026-09-30' },
      { id: 'f4', type: 'sub', name: 'Adobe CC', amount: 1240, day: 31, startMonth: '2026-01' },
      { id: 'f5', type: 'sub', name: 'Figma', amount: 410, day: 2, startMonth: '2026-01' },
    ],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const get = async (who) => (await fetch(base + '/api/widget', { headers: { 'X-Dev-Email': who } })).json();

test('Production: own open tasks, due today / overdue / CD, the week', async () => {
  const w = await get('prod@e11-digital.com');
  assert.deepEqual(w.categories, ['production']);
  assert.equal(w.main, 'production');
  const p = w.production;
  assert.equal(p.dueToday, 1); assert.equal(p.doneToday, 1); assert.equal(p.overdue, 1); assert.equal(p.waitingCD, 1);
  assert.deepEqual(p.next.map((x) => x.id), ['t2', 't1', 't4']);
  assert.equal(p.next[0].client, 'Fortis');
  assert.deepEqual(p.week.map((d) => d.day), ['2026-10-26', '2026-10-27', '2026-10-28', '2026-10-29', '2026-10-30']);
  assert.deepEqual(p.week[3], { day: '2026-10-29', due: 2, done: 1 });
  assert.equal(w.social, undefined); assert.equal(w.finance, undefined);
});

test('Social: own clients only; next month from the 15th; posts today; sent back', async () => {
  const w = await get('soc@e11-digital.com');
  assert.deepEqual(w.categories, ['social']);
  const s = w.social;
  assert.equal(s.month, '2026-11');
  assert.equal(s.clients, 1); assert.equal(s.approved, 1); assert.equal(s.changes, 0);
  assert.deepEqual(s.today.map((x) => x.title), ['Reel']);
  const m = (await get('mgr@e11-digital.com')).social;
  assert.equal(m.clients, 2); assert.equal(m.changes, 1);
  assert.deepEqual(m.sentBack, [{ planId: 'pl2', client: 'Fortis', note: 'Tighten copy', by: 'Carine' }]);
});

test('Finance: statuses, money out this month, subscriptions in the next 7 days', async () => {
  const w = await get('fin@e11-digital.com');
  assert.deepEqual(w.categories, ['finance']);
  assert.equal(w.main, 'finance');
  const f = w.finance;
  assert.deepEqual(f.statuses.map((x) => [x.status, x.count]), [['To be invoiced', 1], ['LPO Pending', 1], ['Quote to be sent', 0], ['Invoiced', 1], ['Retainer', 0]]);
  assert.equal(f.spent, 1500.5 + 410);   // Figma billed on the 2nd; Adobe on the 31st (not yet)
  assert.deepEqual(f.subsSoon.map((x) => [x.name, x.date]), [['Adobe CC', '2026-10-31'], ['Figma', '2026-11-02']]);
});

test('Admins: tasks and plans (Finance only with Finance access); Office Admins only Finance', async () => {
  assert.deepEqual((await get('adm@e11-digital.com')).categories, ['production', 'social']);
  assert.deepEqual((await get('office@e11-digital.com')).categories, ['finance']);
  assert.deepEqual((await get('cd@e11-digital.com')).categories, ['production', 'social']);
});

test('Production widget: a Super Admin sees the team\'s tasks, an AM their own clients\' (Haris 2026-10-30)', async () => {
  const a = (await get('adm@e11-digital.com')).production;
  assert.equal(a.scope, 'team'); assert.equal(a.title, 'Team');
  // the team = every AM's clients' tasks + every Admin's own: t2, t7 (the AM's client Fortis), t8 (made by the Admin)
  assert.deepEqual(a.next.map((x) => x.id).sort(), ['t2', 't7', 't8']);
  assert.equal(a.dueToday, 1); assert.equal(a.overdue, 2);
  const m = (await get('am@e11-digital.com')).production;
  assert.equal(m.scope, 'clients'); assert.equal(m.title, 'My clients');
  assert.deepEqual(m.next.map((x) => x.id), ['t2', 't7']);
  const p = (await get('prod@e11-digital.com')).production;
  assert.equal(p.scope, 'mine'); assert.equal(p.title, 'My day');
});
