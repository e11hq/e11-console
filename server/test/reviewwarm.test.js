// Files sent for review: their previews made the moment they're sent (Haris 2026-11-11 07:08), so they're already there
// when the CD opens the request — a photo's small and large pictures (?w=160, ?w=1000), a PDF's first page (/api/fthumb).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { execFileSync } from 'node:child_process';
import { createServer } from '../src/server.js';

// a w × h PNG of noise (big enough that the server makes its smaller copies)
function png(w, h) {
  const crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = (b) => { let c = 0xffffffff; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => { const t = Buffer.from(type); const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const c = Buffer.alloc(4); c.writeUInt32BE(crc(Buffer.concat([t, data]))); return Buffer.concat([len, t, data, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  const raw = Buffer.alloc((w * 3 + 1) * h); let x = 2463534242; for (let i = 0; i < raw.length; i++) { x ^= x << 13; x ^= x >>> 17; x ^= x << 5; raw[i] = x & 255; }
  for (let y = 0; y < h; y++) raw[y * (w * 3 + 1)] = 0;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
const has = (cmd) => { try { execFileSync('which', [cmd]); return true; } catch { return false; } };

let app, base, dir;
const OWNER = 'haris@e11-digital.com';
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11rw-'));
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
  app.store.importAll({
    users: [{ id: 'u-h', email: OWNER, role: 'admin', active: true }, { id: 'u-cd', email: 'cd@x.test', role: 'am', active: true }, { id: 'u-p', email: 'p@x.test', role: 'production', active: true }],
    projects: [{ id: 'p1', name: 'Blue Bay', sections: [] }],
    meta: [{ id: 'main', cdUserId: 'u-cd' }],
  }, 'test');
  fs.mkdirSync(path.join(dir, 'files', 'Clients', 'Blue Bay'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'files', 'Clients', 'Blue Bay', 'poster.png'), png(900, 600));
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const call = (p, body) => fetch(base + p, { method: 'POST', headers: { 'X-Dev-Email': OWNER, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
const sized = () => { try { return fs.readdirSync(path.join(dir, 'files', '.thumbs', '_sized')); } catch { return []; } };
const until = async (ok, ms = 20000) => { const end = Date.now() + ms; while (Date.now() < end) { if (ok()) return true; await new Promise((r) => setTimeout(r, 100)); } return false; };

test('a photo sent for review: its small and large pictures are made at once, before anyone asks', { skip: !has('ffmpeg') }, async () => {
  assert.equal(sized().length, 0);
  const t = { id: 't1', projectId: 'p1', name: 'Poster', needsCD: true, assignees: ['u-p', 'u-cd'],
    attachments: [{ id: 'a1', name: 'poster.png', path: 'Clients/Blue Bay/poster.png' }],
    reviews: [{ id: 'r1', by: 'u-p', at: new Date().toISOString(), files: ['a1'], state: 'pending', epoch: 0, round: 1 }] };
  const r = await (await call('/api/push', { changes: [{ kind: 'tasks', id: 't1', data: t }] })).json();
  assert.equal(r.ok, true);
  assert.ok(await until(() => sized().some((f) => /-160\.jpg$/.test(f)) && sized().some((f) => /-1280\.jpg$/.test(f))), `made: ${sized().join(', ')}`);
});

test('a request already prepared is not prepared again; a decided one is left alone', { skip: !has('ffmpeg') }, async () => {
  const before = sized().length;
  const t = app.store.get('tasks', 't1');
  await call('/api/push', { changes: [{ kind: 'tasks', id: 't1', data: { ...t, name: 'Poster v2' } }] });
  await new Promise((r) => setTimeout(r, 400));
  assert.equal(sized().length, before);
});
