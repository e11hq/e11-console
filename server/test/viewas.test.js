import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com', AM = 'areej@e11-digital.com', ADMIN2 = 'arsal@e11-digital.com';
const apps = [];
async function start(version) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11va-'));
  const app = createServer({ dataDir: dir, dev: true, version, adminEmail: OWNER, digest: false, holidays: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  app.store.importAll({
    users: [
      { id: 'u-owner', email: OWNER, name: 'Haris', role: 'admin', active: true },
      { id: 'u-am', email: AM, name: 'Areej', role: 'am', active: true },
      { id: 'u-admin2', email: ADMIN2, name: 'Arsal', role: 'admin', active: true },
    ],
    projects: [{ id: 'p1', name: 'Ford', sections: [] }],
  }, 'test');
  apps.push({ app, dir });
  const base = `http://127.0.0.1:${port}`;
  return async (who, p, body) => {
    const res = await fetch(base + p, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    return { status: res.status, body: await res.json().catch(() => null) };
  };
}
after(async () => { for (const { app, dir } of apps) { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); } });

test('test site: the owner uses the app as a team member until switching back', async () => {
  const call = await start('1.5.4-test.130');
  assert.equal((await call(OWNER, '/api/me')).body.viewAs.as, null);
  assert.equal((await call(OWNER, '/api/view-as', { userId: 'u-am' })).status, 200);
  const me = (await call(OWNER, '/api/me')).body;
  assert.equal(me.user.id, 'u-am', 'every request is now as the AM');
  assert.deepEqual(me.viewAs.as, { id: 'u-am', name: 'Areej', role: 'am' });
  assert.equal(me.owner, false, 'with the AM’s rights, not the owner’s');
  // as an AM they can't add a client
  const add = await call(OWNER, '/api/push', { changes: [{ kind: 'projects', id: 'p-x', data: { id: 'p-x', name: 'X', sections: [] } }] });
  assert.equal(add.body.results[0].refused, true);
  // the phone subscriptions of that person are left alone
  assert.equal((await call(OWNER, '/api/push/subscribe', { subscription: { endpoint: 'https://x', keys: {} } })).body.viewingAs, true);
  // and back
  assert.equal((await call(OWNER, '/api/view-as', { userId: null })).status, 200);
  assert.equal((await call(OWNER, '/api/me')).body.user.id, 'u-owner');
});

test('only the owner, and never on the live site', async () => {
  const call = await start('1.5.4-test.130');
  assert.equal((await call(ADMIN2, '/api/view-as', { userId: 'u-am' })).status, 403, 'another Admin cannot');
  assert.equal((await call(ADMIN2, '/api/me')).body.viewAs, null);
  const live = await start('1.5.4');
  assert.equal((await live(OWNER, '/api/view-as', { userId: 'u-am' })).status, 404, 'not on the live site');
  assert.equal((await live(OWNER, '/api/me')).body.viewAs, null);
  assert.equal((await live(OWNER, '/api/me')).body.user.id, 'u-owner');
});
