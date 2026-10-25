import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { createServer } from '../src/server.js';

const webDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'web');
const EMAIL = 'a@e11-digital.com';
async function start() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11l-'));
  const app = createServer({ dataDir: dir, dev: true, webDir, version: '9.9.9', digest: false, holidays: false, occRemind: false, pruneInbox: false });
  const port = await app.listen(0, '127.0.0.1');
  app.store.importAll({ users: [{ id: 'u-a', email: EMAIL, role: 'admin', active: true }] }, 't');
  return { app, dir, base: `http://127.0.0.1:${port}` };
}

test('Inbox clean-up: read updates after 60 days, any after 180 days', async () => {
  const { app, dir } = await start();
  const ago = (d) => new Date(Date.now() - d * 86400000).toISOString();
  app.store.importAll({ notifications: [
    { id: 'n1', to: 'u-a', at: ago(10), read: true }, { id: 'n2', to: 'u-a', at: ago(70), read: true },
    { id: 'n3', to: 'u-a', at: ago(70), read: false }, { id: 'n4', to: 'u-a', at: ago(200), read: false },
  ] }, 't');
  assert.equal(app.pruneNotifications(), 2);
  assert.deepEqual(app.store.list('notifications').map((n) => n.id).sort(), ['n1', 'n3']);
  await app.close(); fs.rmSync(dir, { recursive: true, force: true });
});

test('app files: versioned ones kept for a year, compressed; the page always checked', async () => {
  const { app, dir, base } = await start();
  const h = { 'X-Dev-Email': EMAIL, 'Accept-Encoding': 'br, gzip' };
  const page = await fetch(base + '/', { headers: { ...h, Accept: 'text/html' } });
  assert.equal(page.headers.get('cache-control'), 'no-cache');
  const html = await page.text();
  assert.match(html, /app\.js\?v=9\.9\.9/);
  const js = await fetch(base + '/app.js?v=9.9.9', { headers: h });
  assert.equal(js.headers.get('cache-control'), 'public, max-age=31536000, immutable');
  assert.equal(js.headers.get('content-encoding'), 'br');
  const text = await js.text();                       // (fetch unpacks it)
  assert.equal(text, fs.readFileSync(path.join(webDir, 'app.js'), 'utf8'));
  const plain = await fetch(base + '/app.js?v=9.9.9', { headers: { 'X-Dev-Email': EMAIL, 'Accept-Encoding': 'identity' } });
  assert.equal(plain.headers.get('content-encoding'), null, 'no compression when the browser can’t take it');
  const snap = await fetch(base + '/api/snapshot', { headers: { 'X-Dev-Email': EMAIL, 'Accept-Encoding': 'gzip' } });
  assert.ok((await snap.json()).ok);
  await app.close(); fs.rmSync(dir, { recursive: true, force: true });
});
