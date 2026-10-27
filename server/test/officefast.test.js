// Fast office use: copies from the NAS shared folder (checked by size + fingerprint, inside the share only, same
// upload rules), and the office-network port (passes only in the office, uploads and downloads with a pass, its own
// certificate whose fingerprint the server hands out)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import https from 'node:https';
import crypto from 'node:crypto';
import { createServer } from '../src/server.js';
import { fingerprint } from '../src/office.js';

const OWNER = 'haris@e11-digital.com', PROD = 'ali@e11-digital.com', OFFICE = '5.30.68.204';
let app, dir, share, base, lport;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-office-'));
  share = path.join(dir, 'E11 Share');
  fs.mkdirSync(path.join(share, 'KIA', 'Final'), { recursive: true });
  fs.writeFileSync(path.join(share, 'KIA', 'Final', 'video.mp4'), crypto.randomBytes(3 * 1024 * 1024 + 123));
  fs.writeFileSync(path.join(dir, 'secret.txt'), 'outside the share');
  fs.symlinkSync(path.join(dir, 'secret.txt'), path.join(share, 'link.txt'));
  lport = 20000 + Math.floor(Math.random() * 20000);
  app = createServer({ dataDir: path.join(dir, 'data'), dev: true, adminEmail: OWNER, shareDir: share, officeIp: OFFICE, localUrl: `https://127.0.0.1:${lport}`, localPort: lport,
    digest: false, holidays: false, occRemind: false, birthdays: false, scheduled: false, daily: false, views: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({ users: [{ id: 'u-h', email: OWNER, name: 'Haris', role: 'admin', active: true }, { id: 'u-p', email: PROD, name: 'Ali', role: 'production', active: true }],
    projects: [{ id: 'p1', name: 'KIA', sections: [{ id: 's1', name: 'To do' }] }], statuses: [],
    tasks: [{ id: 't1', title: 'Mine', projectId: 'p1', sectionId: 's1', assignees: ['u-p'], createdBy: 'u-h', tags: [], comments: [], attachments: [] },
      { id: 't2', title: 'Not Ali’s', projectId: 'p1', sectionId: 's1', assignees: [], createdBy: 'u-h', tags: [], comments: [], attachments: [] }] }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const post = (who, p, body, ip) => fetch(base + p, { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json', ...(ip ? { 'CF-Connecting-IP': ip, 'CF-Ray': 'x-DXB' } : {}) }, body: JSON.stringify(body) }).then(async (r) => ({ status: r.status, ...(await r.json()) }));
const src = () => path.join(share, 'KIA', 'Final', 'video.mp4');
async function until(fn) { for (let i = 0; i < 100; i++) { const v = await fn(); if (v) return v; await new Promise((r) => setTimeout(r, 50)); } return null; }

test('the app is told what this office setup offers', async () => {
  const me = await fetch(base + '/api/me', { headers: { 'X-Dev-Email': PROD, 'CF-Connecting-IP': OFFICE, 'CF-Ray': 'x-DXB' } }).then((r) => r.json());
  assert.deepEqual(me.office, { share: true, shareName: 'E11 Share', local: true });
  const out = await fetch(base + '/api/me', { headers: { 'X-Dev-Email': PROD, 'CF-Connecting-IP': '94.1.2.3', 'CF-Ray': 'x-LHR' } }).then((r) => r.json());
  assert.equal(out.office.local, false, 'outside the office: no office network');
});
test('a file from the shared folder is copied into the task (size and fingerprint must match)', async () => {
  const size = fs.statSync(src()).size, fp = fingerprint(src(), size);
  assert.equal((await post(PROD, '/api/share/copy', { taskId: 't1', rel: 'KIA/Final/video.mp4', size, fp: 'nope' })).status, 409, 'a different file');
  assert.equal((await post(PROD, '/api/share/copy', { taskId: 't1', rel: 'KIA/Final/video.mp4', size: size + 1, fp })).status, 409, 'a different size');
  assert.equal((await post(PROD, '/api/share/copy', { taskId: 't2', rel: 'KIA/Final/video.mp4', size, fp })).status, 403, 'only where they may add files');
  const r = await post(PROD, '/api/share/copy', { taskId: 't1', rel: 'KIA/Final/video.mp4', size, fp });
  assert.equal(r.ok, true);
  const st = await until(async () => { const s = await post(PROD, '/api/share/status', { job: r.job }); return s.state === 'done' && s; });
  assert.ok(st && st.file, 'the copy finished');
  assert.equal(st.file.name, 'video.mp4'); assert.equal(st.file.size, size);
  const copied = path.join(dir, 'data', 'files', st.file.path);
  assert.ok(st.file.path.startsWith('attachments/t1/'));
  assert.ok(fs.readFileSync(copied).equals(fs.readFileSync(src())), 'the same bytes');
  assert.equal((await post(OWNER, '/api/share/status', { job: r.job })).status, 404, 'only the person who started it follows it');
});
test('nothing outside the shared folder', async () => {
  for (const rel of ['../secret.txt', 'link.txt', '/etc/passwd', 'KIA/../../secret.txt', 'KIA/Final']) {
    const r = await post(PROD, '/api/share/copy', { taskId: 't1', rel, size: 17, fp: 'x' });
    assert.ok(r.status >= 400, rel + ' refused');
  }
});
function call(url, opts = {}, body) {
  return new Promise((ok, no) => {
    const req = https.request(url, { method: opts.method || 'GET', rejectUnauthorized: false, agent: false, headers: opts.headers || {} }, (res) => {
      const cert = res.socket && res.socket.getPeerCertificate ? res.socket.getPeerCertificate() : null;
      const parts = []; res.on('data', (c) => parts.push(c)); res.on('end', () => ok({ status: res.statusCode, body: Buffer.concat(parts), cert }));
    });
    req.on('error', no); if (body) req.write(body); req.end();
  });
}
test('office network: passes only in the office; uploads in pieces; downloads; the certificate matches', async () => {
  assert.equal((await post(PROD, '/api/local/ticket', { kind: 'up', taskId: 't1', name: 'cut.mov', size: 10 }, '94.1.2.3')).status, 409, 'not outside');
  assert.equal((await post(PROD, '/api/local/ticket', { kind: 'up', taskId: 't2', name: 'cut.mov', size: 10 }, OFFICE)).status, 403, 'not into a task they can’t add to');
  const tk = await post(PROD, '/api/local/ticket', { kind: 'up', taskId: 't1', name: 'cut.mov', size: 10 }, OFFICE);
  assert.equal(tk.ok, true); assert.equal(tk.url, `https://127.0.0.1:${lport}`);
  const ping = await call(tk.url + '/local/ping');
  assert.equal(ping.status, 200);
  assert.equal(ping.cert.fingerprint256.replace(/:/g, '').toLowerCase(), tk.cert, 'the office port shows the certificate the server named');
  const data = crypto.randomBytes(5 * 1024 * 1024);
  const q = (o) => `${tk.url}/local/upload?t=${encodeURIComponent(tk.token)}&offset=${o}`;
  assert.equal((await call(`${tk.url}/local/upload?t=bad&offset=0`, { method: 'POST' }, data.subarray(0, 10))).status, 403, 'no pass, no upload');
  const a = JSON.parse((await call(q(0), { method: 'POST' }, data.subarray(0, 3 * 1024 * 1024))).body);
  const b = JSON.parse((await call(q(3 * 1024 * 1024), { method: 'POST' }, data.subarray(3 * 1024 * 1024))).body);
  assert.equal(a.path, b.path); assert.equal(b.size, data.length);
  assert.ok(fs.readFileSync(path.join(dir, 'data', 'files', b.path)).equals(data), 'the whole file arrived');
  const ft = await post(PROD, '/api/local/ticket', { kind: 'file', path: b.path }, OFFICE);
  const got = await call(`${ft.url}/local/file?t=${encodeURIComponent(ft.token)}`);
  assert.equal(got.status, 200); assert.ok(got.body.equals(data), 'downloaded over the office network');
  const part = await call(`${ft.url}/local/file?t=${encodeURIComponent(ft.token)}`, { headers: { Range: 'bytes=0-9' } });
  assert.equal(part.status, 206);
  assert.equal((await call(`${ft.url}/local/file?t=${encodeURIComponent(tk.token)}`)).status, 404, 'an upload pass isn’t a download pass');
  const other = await post(PROD, '/api/local/ticket', { kind: 'file', path: 'attachments/t2/x.bin' }, OFFICE);
  assert.equal(other.status, 403, 'only files they may see');
});
