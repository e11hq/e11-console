// The owner's "Video hardware" check on the App updates page
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com';
async function start(driDir) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11vh-'));
  const app = createServer({ dataDir: dir, dev: true, version: '1.6.5-test.1', adminEmail: OWNER, driDir, digest: false, holidays: false, occRemind: false });
  const port = await app.listen(0, '127.0.0.1');
  app.store.importAll({ users: [{ id: 'u-o', email: OWNER, role: 'admin', active: true }, { id: 'u-a', email: 'ali@e11-digital.com', role: 'admin', active: true }] }, 'test');
  const call = async (who, p) => { const r = await fetch(`http://127.0.0.1:${port}${p}`, { headers: { 'X-Dev-Email': who } }); return { status: r.status, body: await r.json() }; };
  return { app, dir, call };
}

test('video hardware: owner only; says when the NAS passes none in, or when it is there but does not work', async () => {
  const none = await start(path.join(os.tmpdir(), 'no-such-dri-' + Date.now()));
  assert.equal((await none.call('ali@e11-digital.com', '/api/system/video')).status, 403);
  const r = await none.call(OWNER, '/api/system/video');
  assert.equal(r.body.video.state, 'missing');
  assert.match(r.body.video.detail, /dev\/dri/);
  await none.app.close();
  // a render device that isn't real hardware: found, but the test conversion fails (message, not a crash)
  const fake = fs.mkdtempSync(path.join(os.tmpdir(), 'dri-'));
  fs.writeFileSync(path.join(fake, 'renderD128'), '');
  const f = await start(fake);
  const v = (await f.call(OWNER, '/api/system/video?fresh=1')).body.video;
  assert.equal(v.state, 'error');
  assert.ok(v.title && v.device.endsWith('renderD128'));
  await f.app.close();
});
