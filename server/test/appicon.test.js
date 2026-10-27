import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { createServer } from '../src/server.js';

// A real w × h PNG (solid colour) built with Node only
function png(w, h) {
  const crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = (b) => { let c = 0xffffffff; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => { const t = Buffer.from(type); const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const c = Buffer.alloc(4); c.writeUInt32BE(crc(Buffer.concat([t, data]))); return Buffer.concat([len, t, data, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  const raw = Buffer.alloc((w * 3 + 1) * h); for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) raw[y * (w * 3 + 1) + 1 + x * 3] = 120;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

let app, base, dir, macDir;
const OWNER = 'haris@e11-digital.com', ADMIN2 = 'arsal@e11-digital.com', AM = 'areej@e11-digital.com';
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11i-'));
  macDir = path.join(dir, 'mac'); fs.mkdirSync(macDir);
  fs.writeFileSync(path.join(macDir, 'AppIcon.png'), png(256, 256));
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER, macDir });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
  app.store.importAll({ users: [
    { id: 'u-h', email: OWNER, role: 'admin', active: true },
    { id: 'u-a', email: ADMIN2, role: 'admin', active: true },
    { id: 'u-m', email: AM, role: 'am', active: true },
  ] }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const call = (who, p, body) => fetch(base + p, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });

test('app icon: starts as the default and everyone can read it', async () => {
  const me = await (await call(AM, '/api/me')).json();
  assert.equal(me.owner, false);
  assert.equal(me.appIcon.custom, false);
  assert.equal((await (await call(OWNER, '/api/me')).json()).owner, true);
  const r = await call(AM, '/api/app-icon');
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('content-type'), 'image/png');
});

test('app icon: only the owner can change it — not other Admins or Account Managers', async () => {
  const b64 = png(512, 512).toString('base64');
  assert.equal((await call(ADMIN2, '/api/app-icon', { png: b64 })).status, 403);
  assert.equal((await call(AM, '/api/app-icon', { png: b64 })).status, 403);
  assert.equal((await call(AM, '/api/app-icon/reset', {})).status, 403);
  const ok = await (await call(OWNER, '/api/app-icon', { png: b64 })).json();
  assert.equal(ok.ok, true); assert.equal(ok.custom, true);
  const got = Buffer.from(await (await call(AM, '/api/app-icon')).arrayBuffer());
  assert.equal(got.toString('base64'), b64);
  // new Mac installs get it too (no sign-in needed for the installer)
  const inst = Buffer.from(await (await fetch(base + '/install/AppIcon.png')).arrayBuffer());
  assert.equal(inst.toString('base64'), b64);
});

test('app icon: rejects files that are not square PNGs of a sensible size', async () => {
  assert.equal((await call(OWNER, '/api/app-icon', { png: Buffer.from('hello world, not an image at all').toString('base64') })).status, 400);
  assert.equal((await call(OWNER, '/api/app-icon', { png: png(512, 300).toString('base64') })).status, 400);
  assert.equal((await call(OWNER, '/api/app-icon', { png: png(64, 64).toString('base64') })).status, 400);
});

test('app icon: reset goes back to the default with a new version', async () => {
  const before = (await (await call(OWNER, '/api/app-icon/info')).json()).v;
  const r = await (await call(OWNER, '/api/app-icon/reset', {})).json();
  assert.equal(r.custom, false);
  assert.notEqual(r.v, before);
  const inst = Buffer.from(await (await fetch(base + '/install/AppIcon.png')).arrayBuffer());
  assert.equal(inst.length, fs.readFileSync(path.join(macDir, 'AppIcon.png')).length);
});

test('app icon: Automatic by default; a seasonal pick remembers which one; Automatic again on request (owner only)', async () => {
  const b64 = png(512, 512).toString('base64');
  await call(OWNER, '/api/app-icon/auto', {});
  let i = await (await call(OWNER, '/api/app-icon/info')).json();
  assert.equal(i.auto, true);
  assert.equal(i.custom, false);
  i = await (await call(OWNER, '/api/app-icon', { png: b64, preset: 'ramadan' })).json();
  assert.equal(i.auto, false); assert.equal(i.preset, 'ramadan'); assert.equal(i.custom, true);
  i = await (await call(OWNER, '/api/app-icon', { png: b64, preset: '../x' })).json();
  assert.equal(i.preset, null, 'only simple names are kept');
  assert.equal((await call(AM, '/api/app-icon/auto', {})).status, 403);
  i = await (await call(OWNER, '/api/app-icon/reset', {})).json();
  assert.equal(i.auto, false, 'Everyday is a choice of its own');
  i = await (await call(OWNER, '/api/app-icon/auto', {})).json();
  assert.equal(i.auto, true); assert.equal(i.preset, null);
});
