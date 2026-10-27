// Network check (test copy only): the owner's app opens and uploads are recorded with the address, route (Cloudflare or
// local network), app, and upload size and speed; nobody else's; not on the live site
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

const OWNER = 'haris@e11-digital.com', AM = 'areej@e11-digital.com';
const apps = [];
after(async () => { for (const [a, d] of apps) { await a.close(); fs.rmSync(d, { recursive: true, force: true }); } });
async function start(version) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-netlog-'));
  const app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER, version, digest: false, holidays: false, occRemind: false, birthdays: false, scheduled: false, daily: false });
  const port = await app.listen(0, '127.0.0.1');
  app.store.importAll({ users: [{ id: 'u-h', email: OWNER, name: 'Haris', role: 'admin', active: true }, { id: 'u-a', email: AM, name: 'Areej', role: 'am', active: true }], projects: [], tasks: [{ id: 't1', title: 'T', comments: [], attachments: [], tags: [], assignees: [], createdBy: 'u-h' }], statuses: [] }, 'test');
  apps.push([app, dir]);
  return `http://127.0.0.1:${port}`;
}
const MACAPP = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)';
test('the owner’s opens and uploads are recorded on the test copy', async () => {
  const base = await start('1.8.1-test.5');
  const h = (who, extra = {}) => ({ 'X-Dev-Email': who, 'User-Agent': MACAPP, ...extra });
  await fetch(base + '/api/me', { headers: h(OWNER, { 'CF-Connecting-IP': '94.200.1.2', 'CF-Ray': '8d1a2b3c4d5e6f70-DXB' }) });
  await fetch(base + '/api/me', { headers: h(OWNER, { 'CF-Connecting-IP': '94.200.1.2', 'CF-Ray': '8d1a2b3c4d5e6f71-DXB' }) });   // same again: once
  await fetch(base + '/api/me', { headers: h(AM, { 'CF-Connecting-IP': '5.5.5.5', 'CF-Ray': 'x-DXB' }) });   // someone else: not recorded
  const data = Buffer.alloc(300000, 1);
  const r1 = await fetch(base + '/api/host/writeChunkBin?taskId=t1&name=clip.mp4&offset=0', { method: 'POST', headers: h(OWNER), body: data.subarray(0, 200000) }).then((r) => r.json());
  await fetch(base + `/api/host/writeChunkBin?taskId=t1&path=${encodeURIComponent(r1.path)}&offset=200000`, { method: 'POST', headers: h(OWNER), body: data.subarray(200000) });
  const L = await fetch(base + '/api/netlog', { headers: h(OWNER) }).then((r) => r.json());
  assert.equal(L.on, true);
  const opens = L.entries.filter((e) => e.kind === 'open'), ups = L.entries.filter((e) => e.kind === 'upload');
  assert.equal(opens.length, 1);
  assert.deepEqual([opens[0].ip, opens[0].via, opens[0].colo, opens[0].app], ['94.200.1.2', 'cloudflare', 'DXB', 'Mac app']);
  assert.equal(ups.length, 1, 'one row per file');
  assert.equal(ups[0].size, 300000); assert.equal(ups[0].via, 'direct'); assert.ok(ups[0].mbps > 0);
  await fetch(base + '/api/netlog/note', { method: 'POST', headers: { ...h(OWNER), 'Content-Type': 'application/json' }, body: JSON.stringify({ id: ups[0].id, note: 'office cable' }) });
  assert.equal((await fetch(base + '/api/netlog', { headers: h(OWNER) }).then((r) => r.json())).entries.find((e) => e.id === ups[0].id).note, 'office cable');
  assert.equal((await fetch(base + '/api/netlog', { headers: h(AM) })).status, 404, 'only the owner');
});
test('not on the live site', async () => {
  const base = await start('1.8.1');
  await fetch(base + '/api/me', { headers: { 'X-Dev-Email': OWNER } });
  assert.equal((await fetch(base + '/api/netlog', { headers: { 'X-Dev-Email': OWNER } })).status, 404);
});
