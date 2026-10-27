// Final files: a CD-reviewed task completed → Client Assets › Files › <task> with each person's latest approved files
// (hard links), replaced on re-completion (old ones to the Trash), renamed with the task; folder rules enforced.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const ADMIN = 'haris@e11-digital.com', PROD = 'ali@e11-digital.com';
let app, dir, port, FILES;
const at = (m) => new Date(Date.now() - m * 60000).toISOString();
const put = (rel, txt) => { const f = path.join(FILES, rel); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, txt); };
async function push(email, kind, id, change, del) {
  const cur = app.store.get(kind, id);
  const r = await fetch(`http://127.0.0.1:${port}/api/push`, { method: 'POST', headers: { 'X-Dev-Email': email, 'Content-Type': 'application/json' }, body: JSON.stringify({ changes: [{ kind, id, base: cur, data: typeof change === 'function' ? change(JSON.parse(JSON.stringify(cur))) : { ...cur, ...change } }] }) });
  return (await r.json()).results[0].refused;
}
const client = () => app.store.get('clients', 'cl-ford');
const finalsOf = (tid) => client().folders.find((f) => f.finalOf === tid);
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-fin-'));
  FILES = path.join(dir, 'files');
  app = createServer({ dataDir: dir, dev: true, version: '1.6.5-test.1', adminEmail: ADMIN, digest: false, holidays: false, occRemind: false });
  port = await app.listen(0, '127.0.0.1');
  put('attachments/t1/edit-v2.mp4', 'video v2'); put('attachments/t1/edit-v1.mp4', 'video v1'); put('attachments/t1/post.png', 'png');
  const auto = (n) => ({ id: 'cf-' + n.toLowerCase(), name: n, dir: 'Clients/Ford/' + n, files: [], createdAt: at(999), createdBy: 'u-h', auto: true });
  app.store.importAll({
    meta: { cdUserId: 'u-cd' },
    users: [{ id: 'u-h', email: ADMIN, role: 'admin', active: true }, { id: 'u-cd', email: 'carine@e11-digital.com', role: 'am', active: true }, { id: 'u-p', email: PROD, role: 'production', active: true }, { id: 'u-s', email: 'sara@e11-digital.com', role: 'social', active: true }],
    clients: [{ id: 'cl-ford', name: 'Ford', dir: 'Clients/Ford', createdAt: at(999), createdBy: 'u-h', folders: ['Logos', 'Brand Guidelines', 'Fonts', 'Files'].map(auto) }],
    projects: [{ id: 'p1', name: 'Ford', clientId: 'cl-ford', sections: [{ id: 's-rev', name: 'Review' }, { id: 's-ctr', name: 'CTR' }, { id: 's-done', name: 'Done' }], ams: [] }],
    tasks: [{ id: 't1', projectId: 'p1', sectionId: 's-ctr', title: 'Ramadan reel', needsCD: true, cdStatus: 'approved', createdBy: 'u-h', assignees: ['u-p', 'u-s'],
      attachments: [{ id: 'a1', name: 'edit.mp4', path: 'attachments/t1/edit-v1.mp4', size: 8, reviewId: 'r1' }, { id: 'a2', name: 'edit.mp4', path: 'attachments/t1/edit-v2.mp4', size: 8, reviewId: 'r2' }, { id: 'a3', name: 'post.png', path: 'attachments/t1/post.png', size: 3, reviewId: 'r3' }],
      reviews: [
        { id: 'r1', by: 'u-p', at: at(60), files: ['a1'], state: 'amend', decidedAt: at(55), decidedBy: 'u-cd' },
        { id: 'r2', by: 'u-p', at: at(50), files: ['a2'], state: 'approved', decidedAt: at(40), decidedBy: 'u-cd' },
        { id: 'r3', by: 'u-s', at: at(45), files: ['a3'], state: 'approved', decidedAt: at(42), decidedBy: 'u-cd' }],
      clientApproval: { by: 'u-h', at: at(30) } }],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

test('completing files each person’s latest approved files in Files › <task>, as links that outlive the task’s copy', async () => {
  assert.equal(await push(ADMIN, 'tasks', 't1', { sectionId: 's-done', done: true, completedAt: new Date().toISOString() }), false);
  const f = finalsOf('t1');
  assert.ok(f, 'folder made');
  assert.equal(f.name, 'Ramadan reel'); assert.equal(f.parentId, 'cf-files'); assert.equal(f.dir, 'Clients/Ford/Files/Ramadan reel');
  assert.deepEqual(f.files.map((a) => a.final.srcId).sort(), ['a2', 'a3'], 'v2 only (not the amended v1), and Sara’s post');
  const v = f.files.find((a) => a.final.srcId === 'a2');
  assert.equal(v.final.assignee, 'u-p'); assert.equal(v.final.cdBy, 'u-cd'); assert.equal(v.final.clientBy, 'u-h'); assert.equal(v.final.createdBy, 'u-h');
  const full = path.join(FILES, v.path);
  assert.equal(fs.readFileSync(full, 'utf8'), 'video v2');
  assert.equal(fs.statSync(full).ino, fs.statSync(path.join(FILES, 'attachments/t1/edit-v2.mp4')).ino, 'a hard link, not a copy');
  fs.rmSync(path.join(FILES, 'attachments/t1/edit-v2.mp4'));
  assert.equal(fs.readFileSync(full, 'utf8'), 'video v2', 'still there once the task’s file is gone');
  const n = app.store.list('notifications').filter((x) => x.folderId === f.id);
  assert.ok(n.every((x) => /final files for “Ramadan reel”/.test(x.text)));
  assert.equal(new Set(n.map((x) => x.to)).size, n.length, 'one per person, not one per file');
  assert.ok(n.some((x) => x.to === 'u-p') && n.some((x) => x.to === 'u-s') && !n.some((x) => x.to === 'u-h'), 'the team, not the one who completed it');
});

test('folder rules: no loose files in Files or in a final folder; folders inside Files (not in Logos etc.)', async () => {
  const addFile = (fid) => (c) => { c.folders.find((x) => x.id === fid).files.push({ id: 'x' + fid, name: 'x.png', path: 'Clients/Ford/x.png', addedBy: 'u-p', addedAt: at(0) }); return c; };
  assert.equal(await push(PROD, 'clients', 'cl-ford', addFile('cf-files')), true, 'loose file in Files');
  assert.equal(await push(PROD, 'clients', 'cl-ford', addFile(finalsOf('t1').id)), true, 'file into a final folder');
  assert.equal(await push(PROD, 'clients', 'cl-ford', (c) => { c.folders.find((x) => x.finalOf).files.pop(); return c; }), true, 'file out of a final folder');
  assert.equal(await push(PROD, 'clients', 'cl-ford', (c) => { c.folders.find((x) => x.finalOf).name = 'Mine'; return c; }), true, 'rename a final folder');
  const sub = (pid, id) => (c) => { c.folders.push({ id, name: 'Shoot day', dir: 'Clients/Ford/Files/Shoot day', files: [], createdAt: at(0), createdBy: 'u-p', parentId: pid }); return c; };
  assert.equal(await push(PROD, 'clients', 'cl-ford', sub('cf-logos', 'cf-bad')), true, 'sub-folder in Logos');
  assert.equal(await push(PROD, 'clients', 'cl-ford', (c) => { c.folders.push({ id: 'cf-root', name: 'Mine', dir: 'Clients/Ford/Mine', files: [], createdAt: at(0), createdBy: 'u-p' }); return c; }), true, 'a folder on the client’s main page: Admins and AMs only');
  assert.equal(await push('carine@e11-digital.com', 'clients', 'cl-ford', (c) => { c.folders.push({ id: 'cf-root2', name: 'Social templates', dir: 'Clients/Ford/Social templates', files: [], createdAt: at(0), createdBy: 'u-cd' }); return c; }), false, 'an Account Manager makes one');
  assert.equal(await push(PROD, 'clients', 'cl-ford', sub('cf-files', 'cf-shoot')), false, 'sub-folder in Files');
  assert.equal(await push(PROD, 'clients', 'cl-ford', sub('cf-shoot', 'cf-deep')), false, 'a folder inside it (up to 5 levels)');
  assert.equal(await push(PROD, 'clients', 'cl-ford', addFile('cf-shoot')), false, 'files go in the sub-folder');
  assert.equal(await push(PROD, 'clients', 'cl-ford', (c) => { c.folders.push({ id: 'cf-fake', name: 'Fake', dir: 'Clients/Ford/Files/Fake', files: [], createdAt: at(0), createdBy: 'u-p', parentId: 'cf-files', finalOf: 't1' }); return c; }), true, 'nobody makes a final folder by hand');
});

test('reopened and completed again: the newest approved files replace the old ones (to the Trash); the task can’t be renamed', async () => {
  put('attachments/t1/edit-v3.mp4', 'video v3');
  assert.equal(await push(ADMIN, 'tasks', 't1', (t) => { t.done = false; t.completedAt = null; t.attachments.push({ id: 'a4', name: 'edit.mp4', path: 'attachments/t1/edit-v3.mp4', size: 8, reviewId: 'r4' });
    t.reviews.push({ id: 'r4', by: 'u-p', at: at(5), files: ['a4'], state: 'approved', decidedAt: at(4), decidedBy: 'u-cd' }); return t; }), false);
  assert.equal(await push(ADMIN, 'tasks', 't1', { done: true, completedAt: new Date().toISOString() }), false);
  const f = finalsOf('t1');
  assert.deepEqual(f.files.map((a) => a.final.srcId).sort(), ['a3', 'a4']);
  assert.equal(client().folders.filter((x) => x.finalOf === 't1').length, 1, 'same folder');
  const tr = app.store.list('trash').filter((x) => x.type === 'cafile' && x.data.folderId === f.id);
  assert.deepEqual(tr.map((x) => x.data.file.final.srcId), ['a2'], 'v2 is in the Trash');
  // (a task that went for CD review can't be renamed any more, so its final files folder keeps its name)
  const name = finalsOf('t1').name;
  assert.equal(await push(ADMIN, 'tasks', 't1', { title: 'Ramadan reel — final' }), true, 'renaming is refused');
  assert.equal(finalsOf('t1').name, name);
});

test('tasks without approved files, or not linked to a client, file nothing', async () => {
  app.store.importAll({ tasks: [{ id: 't2', projectId: 'p1', sectionId: 's-done', title: 'Plain', needsCD: false, assignees: ['u-p'], attachments: [], reviews: [] }] }, 'test');
  assert.equal(await push(ADMIN, 'tasks', 't2', { done: true }), false);
  assert.equal(finalsOf('t2'), undefined);
});

test('inside Files: folders up to 5 levels deep, files at any of them; nothing inside final files', async () => {
  const mk = (id, parentId, name = id) => (c) => { c.folders.push({ id, name, dir: 'Clients/Ford/Files/' + id, files: [], createdAt: at(0), createdBy: 'u-p', parentId }); return c; };
  let parent = 'cf-files';
  for (const lvl of [1, 2, 3, 4, 5]) {
    assert.equal(await push(PROD, 'clients', 'cl-ford', mk('cf-l' + lvl, parent)), false, `level ${lvl}`);
    parent = 'cf-l' + lvl;
  }
  assert.equal(await push(PROD, 'clients', 'cl-ford', mk('cf-l6', 'cf-l5')), true, 'no 6th level');
  assert.equal(await push(PROD, 'clients', 'cl-ford', (c) => { c.folders.find((x) => x.id === 'cf-l3').files.push({ id: 'l3f', name: 'x.png', path: 'Clients/Ford/Files/cf-l3/x.png', addedBy: 'u-p', addedAt: at(0) }); return c; }), false, 'files in a level-3 folder');
  assert.equal(await push(PROD, 'clients', 'cl-ford', mk('cf-in-final', finalsOf('t1').id)), true, 'no folders inside final files');
  // removing a folder with everything inside it: your own, in one go
  assert.equal(await push(PROD, 'clients', 'cl-ford', (c) => { c.folders = c.folders.filter((x) => !/^cf-l[2-5]$/.test(x.id)); return c; }), false, 'removes level 2 and all inside');
  assert.deepEqual(client().folders.filter((x) => /^cf-l\d$/.test(x.id)).map((x) => x.id), ['cf-l1']);
});
