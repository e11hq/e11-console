// Scheduled comments: only the author sees one until its time; the server posts it then with the usual
// notifications; a task completed or deleted first cancels it and tells the author; files stay readable to the author
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { whenText } from '../src/scheduled.js';

const OWNER = 'haris@e11-digital.com';
let app, dir, base, clock = Date.parse('2026-10-27T09:00:00Z');   // 13:00 Dubai
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-sched-'));
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER, digest: false, holidays: false, occRemind: false, birthdays: false, scheduled: false, now: () => clock });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  const task = (id, extra = {}) => ({ id, title: 'Task ' + id, projectId: 'p1', sectionId: 's1', assignees: ['u-p'], createdBy: 'u-a', comments: [{ id: 'c0', text: 'first', html: 'first', authorId: 'u-s', at: '2026-10-26T10:00:00Z', parentId: null }], attachments: [], tags: [], ...extra });
  app.store.importAll({ users: [
    { id: 'u-h', email: OWNER, name: 'Haris Sharif', role: 'admin', active: true },
    { id: 'u-a', email: 'areej@e11-digital.com', name: 'Areej Masri', role: 'am', active: true },
    { id: 'u-p', email: 'yousef@e11-digital.com', name: 'Yousef Al Hwij', role: 'production', active: true },
    { id: 'u-q', email: 'qasim@e11-digital.com', name: 'Qasim', role: 'production', active: true },
    { id: 'u-s', email: 'amelia@e11-digital.com', name: 'Amelia', role: 'social', active: true },
    { id: 'u-m', email: 'maria@e11-digital.com', name: 'Maria', role: 'social', active: true, prefs: { notifOff: { comment: true } } },
  ], projects: [{ id: 'p1', name: 'KIA', sections: [{ id: 's1', name: 'To do' }], ams: [{ id: 'u-a' }] }],
  tasks: [task('t1'), task('t2'), task('t3'), task('t4')], statuses: [] }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const push = (who, changes) => fetch(base + '/api/push', { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify({ changes }) }).then((r) => r.json());
const snap = (who) => fetch(base + '/api/snapshot', { headers: { 'X-Dev-Email': who } }).then((r) => r.json());
const sched = (id, taskId, extra = {}) => ({ kind: 'scheduled', id, data: { id, taskId, authorId: 'u-p', replyTo: null, text: 'Hi Amelia', html: 'Hi <span class="mention" data-user="u-s">@Amelia</span>', attachments: [{ id: 'f1', name: 'cut.mp4', path: `attachments/${taskId}/cut.mp4`, size: 5 }], taskTitle: 'Task ' + taskId, sendAt: '2026-10-28T05:00:00Z', createdAt: '2026-10-27T09:00:00Z', state: 'waiting', ...extra } });

test('Dubai time in the wording', () => {
  assert.equal(whenText('2026-10-28T05:00:00Z'), 'Wed, Oct 28 · 9:00 AM');
});

test('only the author makes and sees a scheduled comment; nobody can mark it sent', async () => {
  let r = await push('yousef@e11-digital.com', [sched('s1', 't1')]);
  assert.ok(!r.results[0].refused, 'the author schedules it');
  r = await push('yousef@e11-digital.com', [sched('s-x', 't1', { authorId: 'u-s' })]);
  assert.ok(r.results[0].refused, 'not in someone else’s name');
  r = await push('yousef@e11-digital.com', [sched('s-y', 't1', { state: 'sent' })]);
  assert.ok(r.results[0].refused, 'not already sent');
  assert.equal((await snap('yousef@e11-digital.com')).data.scheduled.length, 1);
  assert.equal((await snap('amelia@e11-digital.com')).data.scheduled.length, 0, 'others don’t see it');
  assert.equal((await snap(OWNER)).data.scheduled.length, 0, 'not even Admins');
  r = await push('amelia@e11-digital.com', [{ kind: 'scheduled', id: 's1', del: true }]);
  assert.ok(r.results[0].refused, 'others can’t cancel it');
});

test('at its time the server posts it and notifies the mention, watchers and the client’s AM', async () => {
  assert.equal(await app.scheduled.tick(), 0, 'not before its time');
  clock = Date.parse('2026-10-28T05:00:30Z');
  assert.equal(await app.scheduled.tick(), 1);
  const t = app.store.get('tasks', 't1');
  const c = t.comments.at(-1);
  assert.equal(c.text, 'Hi Amelia'); assert.equal(c.authorId, 'u-p'); assert.equal(c.attachments.length, 1);
  const s = app.store.get('scheduled', 's1');
  assert.equal(s.state, 'sent'); assert.equal(s.commentId, c.id);
  const ns = app.store.list('notifications').filter((n) => n.commentId === c.id);
  const by = Object.fromEntries(ns.map((n) => [n.to, n.kind]));
  assert.deepEqual(by, { 'u-s': 'mention', 'u-a': 'comment' }, 'Amelia (mentioned) and Areej (creator / AM); not the author');
  assert.equal(await app.scheduled.tick(), 0, 'sent once');
});

test('a reply notifies the thread; a switched-off type is respected', async () => {
  app.store.apply([{ kind: 'tasks', id: 't4', data: { ...app.store.get('tasks', 't4'), comments: app.store.get('tasks', 't4').comments.concat({ id: 'c1', text: 'me too', authorId: 'u-m', parentId: 'c0', at: '2026-10-26T11:00:00Z' }) } }], 'test');
  await push('yousef@e11-digital.com', [sched('s4', 't4', { replyTo: 'c0', html: 'Noted', text: 'Noted', sendAt: '2026-10-28T05:00:00Z' })]);
  await app.scheduled.tick();
  const c = app.store.get('tasks', 't4').comments.at(-1);
  assert.equal(c.parentId, 'c0');
  const to = app.store.list('notifications').filter((n) => n.commentId === c.id).map((n) => n.to).sort();
  assert.deepEqual(to, ['u-a', 'u-s'], 'Amelia (thread) and Areej; Maria switched comments off');
});

test('a task completed first cancels it and tells the author', async () => {
  await push('yousef@e11-digital.com', [sched('s2', 't2', { sendAt: '2026-10-29T05:00:00Z' })]);
  app.store.apply([{ kind: 'tasks', id: 't2', data: { ...app.store.get('tasks', 't2'), done: true } }], 'test');
  await app.scheduled.tick();
  const s = app.store.get('scheduled', 's2');
  assert.equal(s.state, 'cancelled'); assert.equal(s.reason, 'completed');
  const n = app.store.list('notifications').find((x) => x.kind === 'sched-cancel' && x.schedId === 's2');
  assert.equal(n.to, 'u-p'); assert.equal(n.taskId, 't2');
  assert.match(n.text, /Your scheduled comment wasn’t sent: <b>Task t2<\/b> was completed before Thu, Oct 29 · 9:00 AM/);
  assert.equal(app.store.get('tasks', 't2').comments.length, 1, 'not posted');
  // the author may mark it taken back as a draft, nothing else
  let r = await push('yousef@e11-digital.com', [{ kind: 'scheduled', id: 's2', data: { ...s, drafted: true } }]);
  assert.ok(!r.results[0].refused);
  r = await push('yousef@e11-digital.com', [{ kind: 'scheduled', id: 's2', data: { ...s, drafted: true, state: 'waiting' } }]);
  assert.ok(r.results[0].refused);
});

test('a task deleted first cancels it; its files stay readable to the author', async () => {
  await push('yousef@e11-digital.com', [sched('s3', 't3', { sendAt: '2026-10-29T05:00:00Z', replyTo: 'c0' })]);
  fs.mkdirSync(path.join(dir, 'files', 'attachments', 't3'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'files', 'attachments', 't3', 'cut.mp4'), 'video');
  app.store.apply([{ kind: 'tasks', id: 't3', del: true }], 'test');
  await app.scheduled.tick();
  const s = app.store.get('scheduled', 's3');
  assert.equal(s.state, 'cancelled'); assert.equal(s.reason, 'deleted'); assert.equal(s.taskTitle, 'Task t3');
  const n = app.store.list('notifications').find((x) => x.kind === 'sched-cancel' && x.schedId === 's3');
  assert.match(n.text, /Your scheduled reply wasn’t sent: <b>Task t3<\/b> was deleted before/);
  assert.equal(n.taskId, undefined);
  const f = await fetch(base + '/__file/attachments/t3/cut.mp4', { headers: { 'X-Dev-Email': 'yousef@e11-digital.com' } });
  assert.equal(f.status, 200, 'the author can still download the files');
  const g = await fetch(base + '/__file/attachments/t3/cut.mp4', { headers: { 'X-Dev-Email': 'qasim@e11-digital.com' } });
  assert.notEqual(g.status, 200, 'other Production people can’t');
});
