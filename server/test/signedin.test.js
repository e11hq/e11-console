// Signed in to E11 Console on any app (iPhone, Mac, website — all start from /api/snapshot): noted once, so Team members
// shows them Active; E11 Talk's own calls don't count (Haris 2026-11-25 20:39 — Yousef showed "Hasn't signed in yet").
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com';
let app, base, dir;
const call = async (email, p) => { const r = await fetch(base + p, { headers: { 'X-Dev-Email': email } }); return { status: r.status, body: await r.json().catch(() => null) }; };
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11si-'));
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
  app.store.importAll({ users: [{ id: 'u-own', email: OWNER, role: 'admin', active: true, setup: true },
    { id: 'u-y', email: 'yousef@e11-digital.com', role: 'production', active: true, setup: false },
    { id: 'u-t', email: 'talkonly@e11-digital.com', role: 'production', active: true, setup: false }], projects: [] }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

test('first Console sign-in noted once; Talk alone doesn’t mark it; the welcome screen is untouched', async () => {
  assert.equal((await call('yousef@e11-digital.com', '/api/snapshot')).status, 200);
  const y = app.store.get('users', 'u-y');
  assert.ok(y.signedInAt, 'noted');
  assert.equal(y.setup, false, 'the welcome screen still shows where it did');
  const at = y.signedInAt;
  await call('yousef@e11-digital.com', '/api/snapshot');
  assert.equal(app.store.get('users', 'u-y').signedInAt, at, 'once');
  await call('talkonly@e11-digital.com', '/api/talk/state');
  assert.equal(app.store.get('users', 'u-t').signedInAt, undefined, 'Talk doesn’t count');
  await call(OWNER, '/api/snapshot');
  assert.equal(app.store.get('users', 'u-own').signedInAt, undefined, 'already set up: nothing added');
});
