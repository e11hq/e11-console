import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { createCfSync } from '../src/cfsync.js';

let app, base, dir;
const calls = [];
// Pretend Cloudflare API
const cfFetch = async (url, opts) => {
  calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null, auth: opts.headers.Authorization });
  if (opts.method === 'GET') return { ok: true, json: async () => ({ success: true, result: [{ id: 'g-other', name: 'Something else' }] }) };
  if (opts.method === 'POST') return { ok: true, json: async () => ({ success: true, result: { id: 'g-free' } }) };
  return { ok: true, json: async () => ({ success: true, result: { id: 'g-free' } }) };
};

before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11f-'));
  app = createServer({ dataDir: dir, dev: true, cfAccountId: 'acc1', cfApiToken: 'tok', cfFetch });
  app.cfSync = null;
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    users: [
      { id: 'u-admin', email: 'arsal@e11-digital.com', role: 'admin', active: true },
      { id: 'u-am', email: 'areej@e11-digital.com', role: 'am', active: true },
      { id: 'u-free', email: 'Sam.Design@gmail.com', role: 'freelancer', active: true, projectIds: ['p-ford'] },
    ],
    projects: [{ id: 'p-ford', name: 'Ford', clientId: 'cl-ford' }, { id: 'p-alain', name: 'ALAIN', clientId: 'cl-alain' }],
    clients: [{ id: 'cl-ford', name: 'Ford', dir: 'Clients/Ford', folders: [] }, { id: 'cl-alain', name: 'ALAIN', dir: 'Clients/ALAIN', folders: [] }],
    tasks: [{ id: 't-ford', projectId: 'p-ford', title: 'F' }, { id: 't-alain', projectId: 'p-alain', title: 'A' }],
  }, 'test');
  for (const f of ['attachments/t-ford/a.txt', 'attachments/t-alain/b.txt', 'Clients/Ford/Logos/f.txt', 'Clients/ALAIN/Logos/a.txt']) {
    fs.mkdirSync(path.join(dir, 'files', path.dirname(f)), { recursive: true });
    fs.writeFileSync(path.join(dir, 'files', f), 'x');
  }
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

const call = async (who, p, body) => {
  const res = await fetch(base + p, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const FREE = 'sam.design@gmail.com';

test('freelancer sees only the client assets of their projects', async () => {
  const r = await call(FREE, '/api/snapshot');
  assert.deepEqual(r.body.data.clients.map((c) => c.id), ['cl-ford']);
});

test('freelancer can open files only from their tasks and clients', async () => {
  assert.equal((await call(FREE, '/__file/attachments/t-ford/a.txt')).status, 200);
  assert.equal((await call(FREE, '/__file/attachments/t-alain/b.txt')).status, 403);
  assert.equal((await call(FREE, '/__file/Clients/Ford/Logos/f.txt')).status, 200);
  assert.equal((await call(FREE, '/__file/Clients/ALAIN/Logos/a.txt')).status, 403);
  assert.equal((await call('areej@e11-digital.com', '/__file/attachments/t-alain/b.txt')).status, 200);
  assert.equal((await call(FREE, '/api/host/thumb', { id: 'x', path: 'attachments/t-alain/b.txt' })).status, 403);
  assert.equal((await call(FREE, '/api/host/trashMany', { paths: ['attachments/t-alain/b.txt'] })).status, 403);
  const z = await call(FREE, '/api/host/exportFiles', { folder: 'x', paths: ['attachments/t-ford/a.txt', 'attachments/t-alain/b.txt'] });
  assert.equal(z.body.count, 1, 'zip only includes allowed files');
  assert.equal((await call(FREE, '/api/host/writeChunk', { taskId: 't-alain', name: 'x.txt', b64: 'AA==' })).status, 403);
  assert.equal((await call(FREE, '/api/host/writeChunk', { taskId: 't-ford', name: 'x.txt', b64: 'AA==' })).status, 200);
});

test('nobody can add pieces to a file someone else is uploading', async () => {
  const first = await call('areej@e11-digital.com', '/api/host/writeChunk', { taskId: 't-ford', name: 'big.bin', b64: 'AAAA' });
  assert.equal(first.status, 200);
  assert.equal((await call(FREE, '/api/host/writeChunk', { path: first.body.path, b64: 'AAAA' })).status, 403);
  assert.equal((await call('areej@e11-digital.com', '/api/host/writeChunk', { path: first.body.path, b64: 'AAAA' })).body.size, 6);
  assert.equal((await call('areej@e11-digital.com', '/api/host/writeChunk', { path: 'attachments/t-alain/b.txt', b64: 'AAAA' })).status, 403);
});

test('Production cannot delete or upload client assets', async () => {
  app.store.apply([{ kind: 'users', id: 'u-prod', data: { id: 'u-prod', email: 'haris@e11-digital.com', role: 'production', active: true } }], 'test');
  assert.equal((await call('haris@e11-digital.com', '/api/host/trashMany', { paths: ['Clients/Ford/Logos/f.txt'] })).status, 403);
  assert.equal((await call('haris@e11-digital.com', '/api/host/makeDir', { path: 'Clients/Ford/New' })).status, 403);
});

test('Cloudflare sync: the freelancer group holds only non-company, active emails', async () => {
  let users = [
    { email: 'arsal@e11-digital.com', active: true },
    { email: 'Sam.Design@gmail.com', active: true },
    { email: 'old@outlook.com', active: false },
    { email: 'pat@outlook.com', active: true },
  ];
  calls.length = 0;
  const sync = createCfSync({ accountId: 'acc1', token: 'tok', listUsers: () => users, fetchImpl: cfFetch, delayMs: 0, log: { error() {} } });
  const s1 = await sync.syncNow();
  assert.equal(s1.ok, true);
  assert.deepEqual(s1.emails, ['pat@outlook.com', 'sam.design@gmail.com']);
  assert.equal(calls[0].method, 'GET');
  assert.equal(calls[1].method, 'POST', 'creates the group the first time');
  assert.equal(calls[2].method, 'PUT');
  assert.equal(calls[2].url, 'https://api.cloudflare.com/client/v4/accounts/acc1/access/groups/g-free');
  assert.deepEqual(calls[2].body.include, [{ email: { email: 'pat@outlook.com' } }, { email: { email: 'sam.design@gmail.com' } }]);
  assert.equal(calls[2].auth, 'Bearer tok');
  // remove the last freelancers: group keeps a placeholder (Cloudflare needs at least one rule)
  users = [{ email: 'arsal@e11-digital.com', active: true }];
  calls.length = 0;
  await sync.syncNow();
  assert.equal(calls.length, 1, 'group id remembered');
  assert.deepEqual(calls[0].body.include, [{ email: { email: 'nobody@invalid.e11hq.com' } }]);
});

test('Cloudflare sync: errors are reported, not thrown; off when not configured', async () => {
  const bad = createCfSync({ accountId: 'a', token: 't', groupId: 'g', listUsers: () => [], fetchImpl: async () => ({ ok: false, status: 403, json: async () => ({ success: false, errors: [{ message: 'Authentication error' }] }) }), log: { error() {} } });
  const s = await bad.syncNow();
  assert.equal(s.ok, false);
  assert.equal(s.error, 'Authentication error');
  const off = createCfSync({ listUsers: () => [] });
  assert.equal((await off.syncNow()).configured, false);
});

test('only Admins see the Cloudflare status', async () => {
  assert.equal((await call('areej@e11-digital.com', '/api/cloudflare')).status, 403);
  const r = await call('arsal@e11-digital.com', '/api/cloudflare');
  assert.equal(r.status, 200);
  assert.equal(r.body.configured, true);
});

test('raw upload pieces land at their own place: any order, sent twice is never doubled, same access rules', async () => {
  const raw = async (who, q, buf) => {
    const res = await fetch(base + '/api/host/writeChunkBin?' + new URLSearchParams(q), { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/octet-stream' }, body: buf });
    return { status: res.status, body: await res.json().catch(() => null) };
  };
  const AM = 'areej@e11-digital.com';
  const a = Buffer.alloc(5, 'a'), b = Buffer.alloc(5, 'b'), c = Buffer.alloc(3, 'c');
  const first = await raw(AM, { taskId: 't-ford', name: 'video.mp4' }, a);
  assert.equal(first.status, 200);
  const p = first.body.path;
  assert.equal((await raw(AM, { path: p, offset: 10 }, c)).status, 200);   // last piece first
  assert.equal((await raw(AM, { path: p, offset: 5 }, b)).status, 200);
  assert.equal((await raw(AM, { path: p, offset: 5 }, b)).body.size, 13); // the same piece again: not doubled
  assert.equal(fs.readFileSync(path.join(dir, 'files', p), 'utf8'), 'aaaaabbbbbccc');
  assert.equal((await raw(FREE, { path: p, offset: 0 }, a)).status, 403);  // someone else's upload
  assert.equal((await raw(FREE, { taskId: 't-alain', name: 'x.bin' }, a)).status, 403); // a task they can't see
  assert.equal((await raw(AM, { path: p, offset: -1 }, a)).status, 400);
});
