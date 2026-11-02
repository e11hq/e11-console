// The iPhone app's own Clients tab (Part B, 2026-11-02): GET /api/clients — the list (who sees which client, open and
// overdue counts, Account Managers, inactive ones apart) and a client's page (its Client Assets folders on top, its tasks
// by status as Home's cards; completed ones only when asked).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const clock = Date.parse('2026-10-29T08:00:00Z');
let app, base, dir;
const S = [{ id: 's1', name: 'To do', color: '#87909e' }, { id: 's2', name: 'In progress', color: '#a875ff' }, { id: 's5', name: 'Done', color: '#3ddc97' }];
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11c-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    users: [
      { id: 'u-adm', email: 'adm@e11-digital.com', role: 'admin', active: true, name: 'Haris' },
      { id: 'u-am', email: 'am@e11-digital.com', role: 'am', active: true, name: 'Leila' },
      { id: 'u-prod', email: 'prod@e11-digital.com', role: 'production', active: true, name: 'Yousef A' },
    ],
    clients: [{ id: 'c1', name: 'Northline', folders: [{ id: 'f1', name: 'Logos', files: [{ id: 'a', name: 'l.png', path: 'Clients/c1/l.png' }, { id: 'b', name: 'l2.png', path: 'Clients/c1/l2.png' }] }, { id: 'f2', name: 'Fonts', files: [] }, { id: 'f3', name: 'Old', parentId: 'f1', files: [{ id: 'c', name: 'x.png', path: 'Clients/c1/x.png' }] }] }],
    projects: [
      { id: 'p1', name: 'Northline', color: '#3a7bd5', clientId: 'c1', order: 1, ams: [{ id: 'u-am' }], sections: S },
      { id: 'p2', name: 'Southgate', color: '#e5484d', order: 2, ams: [], sections: S },
      { id: 'p3', name: 'Old Co', color: '#888888', order: 3, inactive: true, ams: [], sections: S },
    ],
    tasks: [
      { id: 't1', projectId: 'p1', sectionId: 's2', title: 'Offer pack', assignees: ['u-prod'], createdBy: 'u-am', due: '2026-10-27', comments: [], activity: [] },
      { id: 't2', projectId: 'p1', sectionId: 's1', title: 'Banner', assignees: [], createdBy: 'u-am', comments: [], activity: [] },
      { id: 't3', projectId: 'p1', sectionId: 's5', title: 'Finished', assignees: ['u-prod'], createdBy: 'u-am', done: true, completedAt: '2026-10-28T08:00:00Z', comments: [], activity: [] },
      { id: 't4', projectId: 'p2', sectionId: 's1', title: 'Other', assignees: [], createdBy: 'u-adm', comments: [], activity: [] },
    ],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const get = async (who, q) => (await (await fetch(base + '/api/clients?' + q, { headers: { 'X-Dev-Email': who } })).json());

test('the list: counts, Account Managers, inactive apart', async () => {
  const r = await get('adm@e11-digital.com', 'view=list');
  assert.equal(r.ok, true);
  const m = r.home;
  assert.equal(m.kind, 'clients');
  assert.deepEqual(m.rows.map((x) => x.name), ['Northline', 'Southgate']);
  assert.deepEqual(m.inactive.map((x) => x.name), ['Old Co']);
  const n = m.rows[0];
  assert.equal(n.open, 2); assert.equal(n.late, 1); assert.deepEqual(n.ams, ['u-am']);
  assert.match(m.date, /2 clients · 3 open tasks/);
});

test('the list: production sees only the clients they work on', async () => {
  const m = (await get('prod@e11-digital.com', 'view=list')).home;
  assert.deepEqual(m.rows.map((x) => x.name), ['Northline']);
});

test('a client\'s page: folders on top, tasks by status as Home\'s cards, completed only when asked', async () => {
  let m = (await get('adm@e11-digital.com', 'view=client&id=p1')).home;
  assert.equal(m.kind, 'client'); assert.equal(m.title, 'Northline'); assert.equal(m.open, 2);
  assert.deepEqual(m.assets.folders.map((f) => [f.name, f.files]), [['Logos', 3], ['Fonts', 0]]);
  assert.deepEqual(m.groups.map((g) => g.name), ['To do', 'In progress']);
  const c = m.groups[1].cards[0];
  assert.equal(c.title, 'Offer pack'); assert.equal(c.late, true); assert.ok(c.icon && c.meta);
  m = (await get('adm@e11-digital.com', 'view=client&id=p1&done=1')).home;
  assert.deepEqual(m.groups.map((g) => g.name), ['To do', 'In progress', 'Done']);
  assert.equal((await get('prod@e11-digital.com', 'view=client&id=p2')).home, null, 'not their client');
});
