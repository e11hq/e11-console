// A notification held on the iPhone (Haris 2026-11-10): POST /api/notif-peek gives what it's about — the task's name,
// client and status, and for a comment that comment with the one before it and its thread for Reply; only the person's own
// notifications. The iPhone's notification gets its category (Reply on a comment) and the comment's thread.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const clock = Date.parse('2026-10-29T08:00:00Z');
let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11p-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    meta: { cdUserId: 'u-cd' },
    users: [
      { id: 'u-am', email: 'am@e11-digital.com', role: 'am', active: true, name: 'Leila' },
      { id: 'u-prod', email: 'prod@e11-digital.com', role: 'production', active: true, name: 'Yousef A' },
      { id: 'u-cd', email: 'cd@e11-digital.com', role: 'production', active: true, name: 'Carine' },
    ],
    projects: [{ id: 'p1', name: 'Northline', color: '#3a7bd5', ams: [{ id: 'u-am' }], sections: [{ id: 's1', name: 'To do', color: '#87909e' }, { id: 's2', name: 'In progress', color: '#a875ff' }] }],
    tasks: [{ id: 't1', projectId: 'p1', sectionId: 's2', title: 'Offer pack', assignees: ['u-prod'], createdBy: 'u-am', due: '2026-10-30', comments: [
      { id: 'm1', authorId: 'u-am', at: '2026-10-28T08:00:00Z', text: 'First', html: 'First', attachments: [], parentId: null, reactions: {} },
      { id: 'm2', authorId: 'u-prod', at: '2026-10-28T09:00:00Z', text: 'A reply', html: 'A reply', attachments: [], parentId: 'm1', reactions: {} },
    ], activity: [] }],
    notifications: [
      { id: 'n1', to: 'u-am', from: 'u-prod', kind: 'comment', taskId: 't1', commentId: 'm2', text: 'replied', at: '2026-10-28T09:00:00Z', read: false },
      { id: 'n2', to: 'u-prod', from: 'u-am', kind: 'assigned', taskId: 't1', text: 'assigned you', at: '2026-10-28T07:00:00Z', read: false },
    ],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const peek = async (who, nid) => (await (await fetch(base + '/api/notif-peek', { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify({ nid }) })).json());

test('a reply: the task, the reply with the comment before it, its thread for Reply', async () => {
  const r = await peek('am@e11-digital.com', 'n1');
  assert.equal(r.ok, true);
  const p = r.peek;
  assert.equal(p.title, 'Offer pack'); assert.equal(p.client.name, 'Northline'); assert.equal(p.status.name, 'In progress');
  assert.deepEqual(p.comments.map((c) => c.id), ['m1', 'm2']);
  assert.equal(p.threadId, 'm1'); assert.equal(p.canReply, true);
  assert.ok(p.people['u-prod']);
});

test('a change: the task\'s facts, no comments; someone else\'s notification: nothing', async () => {
  const p = (await peek('prod@e11-digital.com', 'n2')).peek;
  assert.equal(p.comments.length, 0); assert.deepEqual(p.assignees, ['u-prod']); assert.equal(p.creator, 'u-am');
  assert.equal((await peek('prod@e11-digital.com', 'n1')).peek, null);
});
