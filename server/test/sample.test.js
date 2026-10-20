import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

async function withServer(version, fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11s-'));
  const app = createServer({ dataDir: dir, dev: true, version });
  const port = await app.listen(0, '127.0.0.1');
  app.store.importAll({ users: [{ id: 'u-a', email: 'haris@e11-digital.com', role: 'admin', active: true, name: 'Haris' }, { id: 'u-b', email: 'yousef@e11-digital.com', role: 'production', active: true }] }, 'test');
  const call = (who) => fetch(`http://127.0.0.1:${port}/api/sample`, { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: '{}' }).then(async (r) => ({ status: r.status, body: await r.json() }));
  try { await fn(call, app); } finally { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); }
}

test('sample data: never on the live app', () => withServer('1.1.3', async (call, app) => {
  assert.equal((await call('haris@e11-digital.com')).status, 403);
  assert.equal(app.store.list('tasks').length, 0);
}));

test('sample data: test copy, Admins only, keeps existing people', () => withServer('1.1.3-test.26', async (call, app) => {
  assert.equal((await call('yousef@e11-digital.com')).status, 403);
  const r = await call('haris@e11-digital.com');
  assert.equal(r.status, 200);
  assert.ok(app.store.list('tasks').length >= 15);
  assert.equal(app.store.list('users').filter((u) => u.email === 'yousef@e11-digital.com').length, 1);
  assert.equal(app.store.list('users').filter((u) => u.email === 'haris@e11-digital.com').length, 1);
}));
