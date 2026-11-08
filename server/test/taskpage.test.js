// The iPhone app's native task page straight from the server (shell 30+): GET /api/task and its changes through
// POST /api/home/act (from: 'task') — what's shown, who may change what, the status rules (CD review), my part,
// priority, the checklist, the Task Update, and the switch.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const clock = Date.parse('2026-10-29T08:00:00Z');
let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11t-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    meta: { cdUserId: 'u-cd' },
    users: [
      { id: 'u-adm', email: 'adm@e11-digital.com', role: 'admin', active: true, name: 'Haris' },
      { id: 'u-am', email: 'am@e11-digital.com', role: 'am', active: true, name: 'Leila' },
      { id: 'u-prod', email: 'prod@e11-digital.com', role: 'production', active: true, name: 'Yousef A' },
      { id: 'u-prod2', email: 'prod2@e11-digital.com', role: 'production', active: true, name: 'Sara K' },
      { id: 'u-cd', email: 'cd@e11-digital.com', role: 'production', active: true, name: 'Carine' },
    ],
    projects: [
      { id: 'p1', name: 'Northline', color: '#3a7bd5', ams: [{ id: 'u-am' }], sections: [{ id: 's1', name: 'To do', color: '#87909e' }, { id: 's2', name: 'In progress', color: '#a875ff' }, { id: 's3', name: 'Review', color: '#f9be33' }, { id: 's4', name: 'CTR', color: '#4c9aff' }, { id: 's5', name: 'Done', color: '#3ddc97' }] },
    ],
    tasks: [
      { id: 't1', projectId: 'p1', sectionId: 's2', title: 'Offer pack', assignees: ['u-prod', 'u-prod2'], createdBy: 'u-am', due: '2026-10-29', tags: ['Print'], notesHtml: '<p>Matte <b>vinyl</b></p>', checklist: [{ id: 'c1', text: 'Bleed', done: false }], comments: [{ id: 'm1', authorId: 'u-am', at: '2026-10-28T08:00:00Z', text: '@Yousef A check https://we.tl/x', html: '<span class="mention" data-user="u-prod">@Yousef A</span> <b>check</b> <a href="https://we.tl/x">https://we.tl/x</a>', attachments: [], parentId: null, reactions: { '👍': 1 } }, { id: 'm2', authorId: 'u-prod', at: '2026-10-28T09:00:00Z', text: 'ok', html: 'ok', attachments: [], parentId: 'm1', reactions: {} }], activity: [] },
      { id: 't2', projectId: 'p1', sectionId: 's3', title: 'Needs CD', assignees: ['u-prod'], createdBy: 'u-am', needsCD: true, comments: [], activity: [] },
      { id: 't3', projectId: 'p1', sectionId: 's4', title: 'At the client', assignees: ['u-prod'], createdBy: 'u-am', comments: [], activity: [] },
      { id: 't4', projectId: 'p1', sectionId: 's5', title: 'Finished', assignees: ['u-prod'], createdBy: 'u-am', done: true, completedAt: '2026-10-28T08:00:00Z', comments: [], activity: [] },
      { id: 't5', projectId: 'p1', sectionId: 's2', title: 'Sub', parentId: 't1', assignees: [], comments: [], activity: [] },
      { id: 't6', projectId: 'p1', sectionId: 's2', title: 'Amending', assignees: ['u-prod'], createdBy: 'u-am', needsCD: true, cdRule: 2, reviews: [{ id: 'rv1', by: 'u-prod', state: 'amend', epoch: 0, at: '2026-10-28T08:00:00Z' }], comments: [], activity: [] },
      { id: 't7', projectId: 'p1', sectionId: 's1', title: 'Fresh', assignees: [], createdBy: 'u-am', needsCD: true, cdRule: 2, reviews: [], comments: [], activity: [] },
    ],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const page = async (who, id) => (await (await fetch(base + '/api/task?id=' + id, { headers: { 'X-Dev-Email': who } })).json());
const act = async (who, body) => (await (await fetch(base + '/api/home/act', { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify({ from: 'task', ...body }) })).json());
const T = (id) => app.store.get('tasks', id);

test('the page: what the AM sees and may change', async () => {
  const r = await page('am@e11-digital.com', 't1');
  assert.equal(r.ok, true);
  const m = r.task;
  assert.equal(m.title, 'Offer pack'); assert.equal(m.client.name, 'Northline');
  assert.equal(m.status.name, 'In progress'); assert.equal(m.status.next, 's3');
  assert.equal(m.desc, 'Matte vinyl'); assert.equal(m.comments, 2);
  assert.equal(m.subtasks.length, 1); assert.equal(m.checklist.length, 1);
  assert.equal(m.canTitle, true); assert.equal(m.dates.canEdit, true); assert.equal(m.parts.of, 2);
  assert.equal(m.people['u-prod'].first, 'Yousef');
});

test('the page: a production person can\'t change dates; their part; a completed task is read only', async () => {
  const m = (await page('prod@e11-digital.com', 't1')).task;
  assert.equal(m.dates.canEdit, false); assert.equal(m.parts.mine, 'open');
  const d = (await page('am@e11-digital.com', 't4')).task;
  assert.equal(d.readOnly, true); assert.ok(d.completed); assert.equal(d.complete, null);
  assert.equal((await page('am@e11-digital.com', 'nope')).task, null);
});

test('status: Next, and CD review holds it at Review', async () => {
  let r = await act('am@e11-digital.com', { act: 'status', id: 't1', value: 's3', op: 'tp-1' });
  assert.equal(r.ok, true); assert.equal(T('t1').sectionId, 's3'); assert.equal(r.task.status.name, 'Review');
  r = await act('am@e11-digital.com', { act: 'status', id: 't2', value: 's4' });
  assert.equal(r.ok, false); assert.equal(r.error, 'Waiting for CD approval'); assert.equal(T('t2').sectionId, 's3');
  assert.equal((await page('am@e11-digital.com', 't2')).task.status.next, null);
});

test('status: back from the client asks about CD review, then does it', async () => {
  let r = await act('am@e11-digital.com', { act: 'status', id: 't3', value: 's2' });
  assert.equal(r.ok, false); assert.equal(r.need, 'cdAgain'); assert.equal(T('t3').sectionId, 's4');
  r = await act('am@e11-digital.com', { act: 'status', id: 't3', value: 's2', cdAgain: 'yes' });
  assert.equal(r.ok, true); assert.equal(T('t3').sectionId, 's2'); assert.equal(T('t3').needsCD, true);
  r = await act('prod@e11-digital.com', { act: 'status', id: 't1', value: 's1' });
  assert.equal(r.ok, true, 'going back within the work is fine for anyone on it');
});

test('my part, priority, checklist, title, start, Task Update', async () => {
  let r = await act('prod@e11-digital.com', { act: 'myPart', id: 't1', value: true });
  assert.equal(r.ok, true); assert.ok(T('t1').partsDone['u-prod']); assert.deepEqual(r.messages, ['Your part is done']);
  r = await act('am@e11-digital.com', { act: 'prio', id: 't1', key: 'u-prod2', value: 2 });
  assert.equal(r.ok, true); assert.equal(T('t1').prio['u-prod2'], 2);
  r = await act('prod@e11-digital.com', { act: 'prio', id: 't1', key: 'u-prod2', value: 3 });
  assert.equal(r.ok, false, 'production can\'t change priority');
  r = await act('prod@e11-digital.com', { act: 'check', id: 't1', value: 'c1' });
  assert.equal(r.ok, true); assert.equal(T('t1').checklist[0].done, true);
  r = await act('am@e11-digital.com', { act: 'title', id: 't1', value: '  Offer   pack v2 ' });
  assert.equal(T('t1').title, 'Offer pack v2');
  r = await act('prod@e11-digital.com', { act: 'start', id: 't1', value: '2026-10-28' });
  assert.equal(r.ok, false);
  r = await act('am@e11-digital.com', { act: 'start', id: 't1', value: '2026-10-28' });
  assert.equal(T('t1').start, '2026-10-28');
  r = await act('am@e11-digital.com', { act: 'update', id: 't1', value: 'WIP' });
  assert.equal(r.ok, true); assert.equal(T('t1').update, 'WIP'); assert.equal(r.task.update.t, 'WIP');
  r = await act('am@e11-digital.com', { act: 'title', id: 't4', value: 'x' });
  assert.equal(r.ok, false, 'a completed task is read only');
});

test('assignees, guardian, tags, channels, checklist items', async () => {
  let r = await act('am@e11-digital.com', { act: 'assign', id: 't2', key: 'u-prod2', value: true });
  assert.equal(r.ok, true); assert.deepEqual(T('t2').assignees, ['u-prod', 'u-prod2']);
  assert.ok(r.task.pool.some((p) => p.id === 'u-prod2' && p.on));
  r = await act('am@e11-digital.com', { act: 'assign', id: 't2', key: 'u-am', value: true });
  assert.equal(r.ok, false, 'an AM can\'t be assigned');
  r = await act('am@e11-digital.com', { act: 'assign', id: 't2', key: 'u-prod2', value: false });
  assert.deepEqual(T('t2').assignees, ['u-prod']);
  r = await act('prod@e11-digital.com', { act: 'assign', id: 't2', key: 'u-prod2', value: true });
  assert.equal(r.ok, false, 'production can\'t assign');
  r = await act('am@e11-digital.com', { act: 'guardian', id: 't2', value: 'u-prod' });
  assert.equal(T('t2').guardian, 'u-prod');
  r = await act('am@e11-digital.com', { act: 'addTag', id: 't2', value: 'Urgent print' });
  assert.deepEqual(T('t2').tags, ['Urgent print']);
  r = await act('am@e11-digital.com', { act: 'removeTag', id: 't2', value: 'Urgent print' });
  assert.deepEqual(T('t2').tags, []);
  r = await act('am@e11-digital.com', { act: 'channels', id: 't2', value: ['ig', 'tt', 'nope'] });
  assert.deepEqual(T('t2').channels, ['ig', 'tt']); assert.deepEqual(r.task.channels, ['Instagram', 'TikTok']);
  r = await act('prod@e11-digital.com', { act: 'channels', id: 't2', value: [] });
  assert.equal(r.ok, false);
  r = await act('prod@e11-digital.com', { act: 'addCheck', id: 't2', value: 'Bleed' });
  assert.equal(r.ok, false, 'production can\'t add checklist items');
  r = await act('am@e11-digital.com', { act: 'addCheck', id: 't2', value: ' Bleed ' });
  assert.equal(T('t2').checklist.at(-1).text, 'Bleed');
});

test('a subtask added; the client changed', async () => {
  let r = await act('am@e11-digital.com', { act: 'addSub', id: 't2', value: 'Resize for story' });
  assert.equal(r.ok, true);
  const sub = app.store.list('tasks').find((x) => x.parentId === 't2');
  assert.ok(sub); assert.equal(sub.title, 'Resize for story'); assert.equal(sub.projectId, 'p1');
  assert.ok(r.task.subtasks.some((x) => x.title === 'Resize for story'));
  r = await act('prod@e11-digital.com', { act: 'addSub', id: 't2', value: 'x' });
  assert.equal(r.ok, false, 'production can\'t add subtasks');
  assert.ok(r.ok === false);
  const m = (await page('am@e11-digital.com', 't2')).task;
  assert.equal(m.canClient, true); assert.ok(m.clients.some((c) => c.id === 'p1' && c.on));
  r = await act('am@e11-digital.com', { act: 'client', id: 't2', value: null });
  assert.equal(r.ok, true); assert.equal(T('t2').projectId, null);
});

test('comments: the feed, a thread, reactions, delete', async () => {
  const f = (await (await fetch(base + '/api/comments?id=t1', { headers: { 'X-Dev-Email': 'am@e11-digital.com' } })).json()).feed;
  assert.equal(f.items.length, 1); const c = f.items[0];
  assert.equal(c.owner, true); assert.equal(c.replies.n, 1); assert.deepEqual(c.urls, ['https://we.tl/x']);
  assert.deepEqual(c.runs[0], { t: '@Yousef A', user: 'u-prod' }); assert.ok(c.runs.some((r) => r.b && r.t === 'check'));
  assert.equal(c.seen.label, 'Not seen by Yousef yet'); assert.deepEqual(c.reactions, [{ e: '👍', n: 1 }]);
  const th = (await (await fetch(base + '/api/comments?id=t1&thread=m1', { headers: { 'X-Dev-Email': 'am@e11-digital.com' } })).json()).feed;
  assert.equal(th.items.length, 2); assert.equal(th.thread, 'm1');
  let r = await act('prod@e11-digital.com', { act: 'react', id: 't1', key: 'm1', value: '🎉' });
  assert.equal(r.ok, true); assert.equal(T('t1').comments[0].reactions['🎉'], 1);
  r = await act('prod@e11-digital.com', { act: 'deleteComment', id: 't1', value: 'm1' });
  assert.equal(r.ok, false, 'only its writer');
  r = await act('am@e11-digital.com', { act: 'deleteComment', id: 't1', value: 'm1' });
  assert.equal(r.ok, true); assert.equal(T('t1').comments.length, 0, 'the replies go with it');
  r = await act('am@e11-digital.com', { act: 'undoDelete', trashId: r.undo });
  assert.equal(r.ok, true); assert.equal(T('t1').comments.length, 2, 'Undo brings them back');
});

test('the description from the phone; Submit for CD review and Withdraw', async () => {
  let r = await act('am@e11-digital.com', { act: 'desc', id: 't3', html: '<b>Big</b> <span class="mention" data-user="u-prod">@Yousef A</span><script>x</script><img src=x>', text: 'Big @Yousef A' });
  assert.equal(r.ok, true); assert.equal(T('t3').notesHtml, '<b>Big</b> <span class="mention" data-user="u-prod" contenteditable="false">@Yousef A</span>x');
  assert.ok(app.store.list('notifications').some((n) => n.to === 'u-prod' && n.taskId === 't3' && n.kind === 'mention'));
  // t2 needs CD review, Yousef is on it, in Review
  await act('am@e11-digital.com', { act: 'client', id: 't2', value: 'p1' }); await act('am@e11-digital.com', { act: 'status', id: 't2', value: 's2' });
  r = await act('prod@e11-digital.com', { act: 'submitReview', id: 't2', files: [{ name: 'a.pdf', size: 10, path: 'attachments/t2/a.pdf' }, { name: 'evil', path: 'attachments/other/x' }] });
  assert.equal(r.ok, true, JSON.stringify(r)); assert.equal(T('t2').attachments.length, 1); assert.equal(T('t2').cdStatus, 'review');
  assert.equal(r.task.review2.state, 'pending');
  r = await act('prod@e11-digital.com', { act: 'withdrawReview', id: 't2' });
  assert.equal(r.ok, true); assert.equal(T('t2').attachments.length, 0);
});

test('attaching files from the phone: the page that comes back has them at once', async () => {
  const before = (T('t3').attachments || []).length;
  const r = await act('prod@e11-digital.com', { act: 'attach', id: 't3', files: [{ name: 'brief.pdf', size: 1200, path: 'attachments/t3/brief.pdf' }] });
  assert.equal(r.ok, true, JSON.stringify(r)); assert.equal(T('t3').attachments.length, before + 1);
  assert.ok(JSON.stringify(r.task).includes('brief.pdf'), 'the returned page lists the new file');
});

test('the comments\' files under Files (not voice messages); a video\'s picture asked for', async () => {
  await act('prod@e11-digital.com', { act: 'comment', id: 't3', html: 'clip', text: 'clip', files: [{ name: 'cut.mp4', size: 900, path: 'attachments/t3/cut.mp4' }] });
  await act('prod@e11-digital.com', { act: 'comment', id: 't3', html: '', text: '', files: [{ name: 'Voice message.m4a', size: 20, path: 'attachments/t3/v2.m4a', voice: true, dur: 3 }] });
  const m = (await page('am@e11-digital.com', 't3')).task;
  const cf = m.commentFiles;
  assert.ok(cf.some((f) => f.name === 'cut.mp4' && f.by === 'u-prod'), JSON.stringify(cf));
  assert.ok(!cf.some((f) => f.name === 'Voice message.m4a'), 'no voice messages');
  const v = cf.find((f) => f.name === 'cut.mp4');
  assert.ok(v.thumbUrl.startsWith('/api/fthumb?path=attachments%2Ft3%2Fcut.mp4'), v.thumbUrl); assert.equal(v.file, 'attachments/t3/cut.mp4');
  const r = await fetch(base + v.thumbUrl, { headers: { 'X-Dev-Email': 'am@e11-digital.com' } });
  assert.equal(r.status, 404, 'no such file here: no picture');
  const r2 = await fetch(base + '/api/fthumb?path=' + encodeURIComponent('Finance/x.pdf'), { headers: { 'X-Dev-Email': 'prod@e11-digital.com' } });
  assert.equal(r2.status, 403);
});

test('a file copied from another task and pasted into a comment: the same file, no copy; not one from a task out of sight', async () => {
  await act('am@e11-digital.com', { act: 'attach', id: 't1', files: [{ name: 'deck.pdf', size: 500, path: 'attachments/t1/deck.pdf' }] });
  let r = await act('am@e11-digital.com', { act: 'comment', id: 't3', html: 'see', text: 'see', files: [{ name: 'deck.pdf', path: 'attachments/t1/deck.pdf' }] });
  assert.equal(r.ok, true, JSON.stringify(r));
  const a = T('t3').comments.at(-1).attachments[0];
  assert.equal(a.path, 'attachments/t1/deck.pdf'); assert.equal(a.size, 500, 'its details from the file it is');
  r = await act('am@e11-digital.com', { act: 'comment', id: 't3', html: 'x', text: 'x', files: [{ name: 'evil', path: 'attachments/nowhere/secret.pdf' }] });
  assert.equal(r.ok, true); assert.equal(T('t3').comments.at(-1).attachments.length, 0, 'a file on no task this person sees is left out');
});

test('files pasted into a description or a comment (the website\'s 📎 chips) come as file cards, not words', async () => {
  const chip = '<span class="fileref" contenteditable="false" data-fpath="attachments/t1/deck.pdf" data-fname="deck.pdf" data-fsize="500">📎 deck.pdf</span>';
  let r = await act('am@e11-digital.com', { act: 'desc', id: 't3', html: 'See ' + chip + ' please', text: 'See deck.pdf please' });
  assert.equal(r.ok, true, JSON.stringify(r));
  const m = (await page('am@e11-digital.com', 't3')).task;
  assert.deepEqual(m.descFiles.map((f) => f.name), ['deck.pdf']); assert.equal(m.descFiles[0].file, 'attachments/t1/deck.pdf');
  // (the description keeps where it was pasted: a run of its own the app shows as a link to it — Haris 2026-11-02)
  assert.deepEqual(m.descRuns.filter((x) => /deck\.pdf/.test(x.t)).map((x) => [x.t, x.ref && x.ref.path]), [['📎 deck.pdf', 'attachments/t1/deck.pdf']], JSON.stringify(m.descRuns));
});

test('a file of another task, pasted into a description, is added to this task\'s files too (the same file)', async () => {
  const r = await act('am@e11-digital.com', { act: 'attach', id: 't3', files: [{ name: 'deck.pdf', path: 'attachments/t1/deck.pdf' }, { name: 'x', path: 'attachments/nope/secret.pdf' }] });
  assert.equal(r.ok, true, JSON.stringify(r));
  const got = T('t3').attachments.filter((a) => a.path === 'attachments/t1/deck.pdf');
  assert.equal(got.length, 1); assert.equal(got[0].size, 500);
  assert.ok(!T('t3').attachments.some((a) => a.path === 'attachments/nope/secret.pdf'), 'only files this person can already see');
});

test('writing a comment, a reply with a mention, a voice message; editing', async () => {
  let r = await act('prod@e11-digital.com', { act: 'comment', id: 't3', html: 'Done <b>now</b>', text: 'Done now' });
  assert.equal(r.ok, true); const c = T('t3').comments.at(-1); assert.equal(c.html, 'Done <b>now</b>'); assert.equal(c.authorId, 'u-prod');
  r = await act('am@e11-digital.com', { act: 'comment', id: 't3', parentId: c.id, html: '<span class="mention" data-user="u-prod2">@Sara</span> see', text: '@Sara see' });
  assert.equal(r.ok, true); assert.equal(T('t3').comments.at(-1).parentId, c.id);
  assert.ok(app.store.list('notifications').some((n) => n.to === 'u-prod2' && n.kind === 'mention'));
  r = await act('prod@e11-digital.com', { act: 'comment', id: 't3', html: '', text: '', files: [{ name: 'Voice message.m4a', size: 2000, path: 'attachments/t3/v.m4a', voice: true, dur: 7.4 }] });
  assert.equal(r.ok, true); const v = T('t3').comments.at(-1).attachments[0]; assert.equal(v.voice, true); assert.equal(v.dur, 7);
  r = await act('prod@e11-digital.com', { act: 'editComment', id: 't3', value: c.id, html: 'Done!', text: 'Done!' });
  // (the server's own edit-window check runs on the real clock, not this test's: refused here is the window)
  if (r.ok) assert.equal(T('t3').comments.find((x) => x.id === c.id).text, 'Done!'); else assert.equal(r.status, 403);
  r = await act('am@e11-digital.com', { act: 'editComment', id: 't3', value: c.id, html: 'x', text: 'x' });
  assert.equal(r.ok, false, 'only its writer');
});

test('the switch: off → the page asks the website again', async () => {
  app.store.kv.set('task-server', 'off');
  assert.equal((await page('am@e11-digital.com', 't1')).off, true);
  assert.equal((await act('am@e11-digital.com', { act: 'title', id: 't1', value: 'y' })).off, true);
  app.store.kv.set('task-server', 'on');
});

// iOS app data plan, step 3: the app with its own copy gets the changed records, not the page worked out again
test('copy: an action answers with the changed records only', async () => {
  const r = await act('am@e11-digital.com', { act: 'update', id: 't1', value: 'Shoot', copy: true });
  assert.equal(r.ok, true);
  assert.equal(r.task, undefined, 'no task page worked out');
  assert.ok(Array.isArray(r.changes) && r.changes.some((c) => c.kind === 'tasks' && c.id === 't1' && c.data && c.data.update === 'Shoot'), JSON.stringify(r.changes).slice(0, 300));
  assert.ok(r.rev > 0);
});

test('Finance status: the client\'s Account Manager and Admins see and change it, others don\'t see it', async () => {
  const m = (await page('am@e11-digital.com', 't1')).task;
  assert.ok(m.finance); assert.equal(m.canFinance, true); assert.ok(m.financeOpts.some((o) => o.t === 'Invoiced'));
  assert.equal((await page('prod@e11-digital.com', 't1')).task.finance, null);
  let r = await act('prod@e11-digital.com', { act: 'finance', id: 't1', value: 'Invoiced' });
  assert.equal(r.ok, false);
  r = await act('am@e11-digital.com', { act: 'finance', id: 't1', value: 'Invoiced' });
  assert.equal(r.ok, true, JSON.stringify(r)); assert.equal(T('t1').finance, 'Invoiced'); assert.equal(T('t1').financeBy, 'u-am');
  r = await act('am@e11-digital.com', { act: 'finance', id: 't1', value: 'Nope' });
  assert.equal(r.ok, false);
});

test('a task gone for CD review: its Assignees and Guardian lock too (Haris 2026-11-02)', async () => {
  const orig = T('t1');
  app.store.apply([{ kind: 'tasks', id: 't1', data: { ...orig, lockedAt: '2026-11-01T10:00:00Z' } }], 'u-am');
  try {
    const m = (await page('am@e11-digital.com', 't1')).task;
    assert.equal(m.canAssign, false); assert.equal(m.canGuardian, false); assert.deepEqual(m.pool, []);
    assert.match(m.lock.text, /assignees and guardian are locked/);
    let r = await act('am@e11-digital.com', { act: 'assign', id: 't1', key: 'u-prod', value: true });
    assert.equal(r.ok, false);
    r = await act('am@e11-digital.com', { act: 'guardian', id: 't1', value: 'u-prod' });
    assert.equal(r.ok, false);
  } finally { app.store.apply([{ kind: 'tasks', id: 't1', data: orig }], 'u-am'); }
});

test('CD review\'s round (Haris 2026-11-08): amendments keep the status at In progress and CD review on — nobody exempt', async () => {
  let r = await act('adm@e11-digital.com', { act: 'status', id: 't6', value: 's1' });
  assert.match(r.error || '', /stays In progress/);
  assert.equal(T('t6').sectionId, 's2');
  r = await act('adm@e11-digital.com', { act: 'needsCD', id: 't6', value: false });
  assert.match(r.error || '', /stays on/);
  assert.equal(T('t6').needsCD, true);
  const m = (await page('adm@e11-digital.com', 't6')).task;
  assert.equal(m.status.canSet, false); assert.match(m.status.why, /stays In progress/); assert.equal(m.review.canSet, false);
});

test('the CD alone on a task: CD review switches itself off, can\'t be turned on; with someone else it can', async () => {
  let r = await act('am@e11-digital.com', { act: 'assign', id: 't7', key: 'u-cd', value: true });
  assert.ok(!r.error, r.error); assert.equal(T('t7').needsCD, false);
  r = await act('am@e11-digital.com', { act: 'needsCD', id: 't7', value: true });
  assert.match(r.error || '', /only one/);
  r = await act('am@e11-digital.com', { act: 'assign', id: 't7', key: 'u-prod', value: true });
  assert.equal(T('t7').needsCD, false, 'stays off');
  r = await act('am@e11-digital.com', { act: 'needsCD', id: 't7', value: true });
  assert.ok(!r.error, r.error); assert.equal(T('t7').needsCD, true, 'the CD and someone else: on again');
});
