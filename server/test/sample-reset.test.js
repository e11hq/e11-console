import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com';
async function start(version) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11sr-'));
  const app = createServer({ dataDir: dir, dev: true, version, adminEmail: OWNER, digest: false, holidays: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  app.store.importAll({ users: [{ id: 'u-owner', email: OWNER, name: 'Haris', role: 'admin', active: true }, { id: 'u-old', email: 'old@e11-digital.com', role: 'am', active: true }],
    projects: [{ id: 'p-old', name: 'Old client', sections: [] }], tasks: [{ id: 't-old', projectId: 'p-old', title: 'Old task' }] }, 'test');
  fs.mkdirSync(path.join(dir, 'files', 'attachments', 't-old'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'files', 'attachments', 't-old', 'a.txt'), 'x');
  const call = async (who, p, body) => {
    const res = await fetch(`http://127.0.0.1:${port}${p}`, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    return { status: res.status, body: await res.json().catch(() => null) };
  };
  return { app, dir, call };
}

test('test copy: the owner wipes everything and starts again with sample data in the new setup', async () => {
  const { app, dir, call } = await start('1.5.4-test.130');
  assert.equal((await call('old@e11-digital.com', '/api/sample/reset', {})).status, 403, 'only the owner');
  const r = await call(OWNER, '/api/sample/reset', {});
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const s = app.store;
  assert.ok(s.get('users', 'u-owner'), 'the owner stays');
  assert.equal(s.get('users', 'u-old'), null, 'everyone else goes');
  assert.equal(s.get('tasks', 't-old'), null);
  assert.equal(s.get('projects', 'p-old'), null);
  assert.ok(!fs.existsSync(path.join(dir, 'files', 'attachments', 't-old')), 'old files moved to the trash folder');
  const projects = s.list('projects'), clients = s.list('clients'), users = new Map(s.list('users').map((u) => [u.id, u]));
  assert.equal(projects.length, 6);
  assert.ok(projects.every((p) => p.clientId && clients.some((c) => c.id === p.clientId)), 'every client has its Client Assets');
  assert.ok(clients.every((c) => ['Logos', 'Brand Guidelines', 'Fonts', 'Files'].every((n) => c.folders.some((f) => f.name === n && f.auto))));
  assert.ok(projects.some((p) => p.inactive), 'an inactive client');
  assert.ok(projects.some((p) => (p.ams || []).some((a) => a.onLeave)), 'an AM on leave with a cover');
  const cd = s.get('meta', 'main').cdUserId;
  const bad = s.list('tasks').filter((t) => (t.assignees || []).some((id) => id !== cd && !['production', 'social', 'freelancer'].includes((users.get(id) || {}).role)));
  assert.equal(bad.length, 0, 'only Production, Social, Freelancers and the CD are assigned');
  assert.ok(s.list('tasks').some((t) => t.cdRule === 2) && s.list('tasks').some((t) => !t.parentId && !t.cdRule), 'newer and older tasks');
  assert.ok(s.list('tasks').every((t) => !(t.cdRule && t.needsCD && (t.assignees || []).includes(cd))), 'no new task needs CD review with the CD on it');
  assert.ok(fs.existsSync(path.join(dir, 'files', 'Clients', 'Ford & Lincoln', 'Logos', 'Ford & Lincoln logo.svg')), 'files are on disk');
  await app.close(); fs.rmSync(dir, { recursive: true, force: true });
});

test('never on the live site', async () => {
  const { app, dir, call } = await start('1.5.4');
  assert.equal((await call(OWNER, '/api/sample/reset', {})).status, 403);
  assert.ok(app.store.get('tasks', 't-old'), 'nothing touched');
  await app.close(); fs.rmSync(dir, { recursive: true, force: true });
});
