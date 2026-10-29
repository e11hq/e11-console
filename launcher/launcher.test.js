// Full update cycle against a pretend GitHub: first install, update with backup, a broken release
// that is rolled back automatically, a manual roll back, and the Admin endpoints in the app.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createLauncher } from './launcher.js';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'e11l-'));
const DIST = path.join(tmp, 'dist');
const DATA = path.join(tmp, 'data');
const PORT = 18190, CONTROL = 18191;
let gh, ghPort, launcher;
let latest = null;                 // { version, notes }
const requests = [];
const SELF = path.join(tmp, 'running-launcher.js'); fs.writeFileSync(SELF, '// an older updater');
let newLauncher = 0;

function bundle(version, broken = false) {
  execFileSync(path.join(ROOT, 'scripts', 'bundle.sh'), [version], { env: { ...process.env, OUT_DIR: DIST } });
  if (broken) {
    const x = path.join(tmp, 'broken'); fs.rmSync(x, { recursive: true, force: true }); fs.mkdirSync(x);
    execFileSync('tar', ['-xzf', path.join(DIST, `e11-console-${version}.tar.gz`), '-C', x]);
    fs.writeFileSync(path.join(x, 'e11-console', 'server', 'src', 'index.js'), 'throw new Error("broken release")');
    execFileSync('tar', ['-czf', path.join(DIST, `e11-console-${version}.tar.gz`), '-C', x, 'e11-console']);
  }
}
const api = async (who, p, body) => {
  const r = await fetch(`http://127.0.0.1:${PORT}${p}`, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, body: await r.json().catch(() => null) };
};
const ctl = async (p, method = 'POST') => (await fetch(`http://127.0.0.1:${CONTROL}${p}${p.includes('update') || p.includes('rollback') ? '?wait=1' : ''}`, { method })).json();

before(async () => {
  bundle('1.0.0'); bundle('1.1.0'); bundle('1.2.0', true);
  gh = http.createServer((req, res) => {
    requests.push({ url: req.url, auth: req.headers.authorization, accept: req.headers.accept });
    if (req.url === '/repos/e11hq/e11-console/releases/latest') {
      if (!latest) { res.writeHead(404); return res.end('{}'); }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ name: `E11 Console ${latest.version}`, body: latest.notes, published_at: '2026-10-20T10:00:00Z', assets: [{ name: `e11-console-${latest.version}.tar.gz`, url: `http://127.0.0.1:${ghPort}/assets/${latest.version}`, size: 1 }] }));
    }
    const m = /^\/assets\/(.+)$/.exec(req.url);
    if (m) { res.writeHead(200, { 'Content-Type': 'application/octet-stream' }); return res.end(fs.readFileSync(path.join(DIST, `e11-console-${m[1]}.tar.gz`))); }
    res.writeHead(404); res.end();
  });
  await new Promise((ok) => gh.listen(0, '127.0.0.1', ok));
  ghPort = gh.address().port;
  latest = { version: '1.0.0', notes: '## First version\n- Tasks and projects' };
  launcher = createLauncher({
    env: { DATA_DIR: DATA, PORT: String(PORT), LAUNCHER_PORT: String(CONTROL), GITHUB_API: `http://127.0.0.1:${ghPort}`, GITHUB_TOKEN: 'secret-token', UPDATE_HOUR: 'off', AUTH_DEV: '1', ADMIN_EMAIL: 'arsal@e11-digital.com', HEALTH_TIMEOUT_MS: '15000', NODE_NO_WARNINGS: '1' },
    childStdio: 'ignore', log: () => {},
    selfPath: SELF, onNewLauncher: () => { newLauncher++; },
  });
  await launcher.start();
});
after(async () => { await launcher.stop(); gh.close(); fs.rmSync(tmp, { recursive: true, force: true }); });

test('first start downloads and runs the latest release', async () => {
  const h = await (await fetch(`http://127.0.0.1:${PORT}/api/health`)).json();
  assert.equal(h.version, '1.0.0');
  assert.ok(requests.every((r) => r.auth === 'Bearer secret-token'), 'token sent to GitHub');
  assert.ok(requests.some((r) => r.accept === 'application/octet-stream'), 'asset downloaded as a file');
  // make some data: the first admin signs in and creates a task
  await api('arsal@e11-digital.com', '/api/me');
  const r = await api('arsal@e11-digital.com', '/api/push', { changes: [{ kind: 'tasks', id: 't1', data: { id: 't1', title: 'Survives updates' } }] });
  assert.equal(r.status, 200);
});

test('a new release is found, installed with a database backup, and data is kept', async () => {
  latest = { version: '1.1.0', notes: '## Faster\n- **Client Assets** search\n- Fixes' };
  const s = await ctl('/check');
  assert.equal(s.available.version, '1.1.0');
  const u = await ctl('/update');
  assert.equal(u.ok, true);
  assert.equal(u.version, '1.1.0');
  const h = await (await fetch(`http://127.0.0.1:${PORT}/api/health`)).json();
  assert.equal(h.version, '1.1.0');
  const snap = await api('arsal@e11-digital.com', '/api/snapshot');
  assert.equal(snap.body.data.tasks.find((t) => t.id === 't1').title, 'Survives updates');
  assert.ok(fs.readdirSync(path.join(DATA, 'backups')).some((f) => /^before-admin-1\.0\.0-to-1\.1\.0-.+\.sqlite$/.test(f)), 'database copied before the update');
  assert.equal(u.status.previous, '1.0.0');
  assert.equal(u.status.available, null);
});

test('the updater updates itself: a release with a different launcher.js is kept and switched to', async () => {
  await new Promise((ok) => setTimeout(ok, 1500));
  const adopted = path.join(DATA, 'app', 'launcher', 'launcher.js');
  assert.ok(fs.existsSync(adopted), 'the new updater is kept in /data/app/launcher');
  assert.equal(fs.readFileSync(adopted, 'utf8'), fs.readFileSync(path.join(ROOT, 'launcher', 'launcher.js'), 'utf8'));
  assert.ok(newLauncher >= 1, 'boot.js is asked to switch to it');
});

test('Admins see the update status in the app; others don’t; everyone gets What’s new', async () => {
  const a = await api('arsal@e11-digital.com', '/api/updates');
  assert.equal(a.status, 200);
  assert.equal(a.body.managed, true);
  assert.equal(a.body.current, '1.1.0');
  const w = await api('arsal@e11-digital.com', '/api/whatsnew');
  assert.match(w.body.notes, /Client Assets/);
  // a second person who is not an Admin
  await api('arsal@e11-digital.com', '/api/push', { changes: [{ kind: 'users', id: 'u-prod', data: { id: 'u-prod', email: 'haris@e11-digital.com', role: 'production', active: true } }] });
  assert.equal((await api('haris@e11-digital.com', '/api/updates')).status, 403);
  // the page asks browsers for the new files
  const html = await (await fetch(`http://127.0.0.1:${PORT}/`, { headers: { 'X-Dev-Email': 'haris@e11-digital.com' } })).text();
  assert.match(html, /app\.js\?v=1\.1\.0/);
});

test('a release that doesn’t start is rolled back automatically', async () => {
  latest = { version: '1.2.0', notes: 'broken' };
  const u = await ctl('/update');
  assert.equal(u.ok, false);
  assert.match(u.error, /did not start/);
  const h = await (await fetch(`http://127.0.0.1:${PORT}/api/health`)).json();
  assert.equal(h.version, '1.1.0', 'still on the working version');
  assert.equal(u.status.current, '1.1.0');
});

test('one-click roll back to the previous version, keeping the data', async () => {
  const r = await api('arsal@e11-digital.com', '/api/updates', { action: 'rollback' });
  assert.equal(r.body.started, true, 'the app gets an immediate answer');
  let h = null;
  for (let i = 0; i < 80 && !(h && h.version === '1.0.0'); i++) { await new Promise((ok) => setTimeout(ok, 250)); try { h = await (await fetch(`http://127.0.0.1:${PORT}/api/health`)).json(); } catch { /* restarting */ } }
  assert.equal(h.version, '1.0.0');
  let st = null;
  for (let i = 0; i < 80 && !(st && st.lastResult); i++) { st = await (await fetch(`http://127.0.0.1:${CONTROL}/status`)).json(); if (!st.lastResult) await new Promise((ok) => setTimeout(ok, 250)); }
  assert.equal(st.lastResult.ok, true);
  assert.equal(st.lastResult.action, 'rollback');
  const snap = await api('arsal@e11-digital.com', '/api/snapshot');
  assert.ok(snap.body.data.tasks.some((t) => t.id === 't1'));
});

test('restart of the launcher keeps running the chosen version', async () => {
  await launcher.stop();
  launcher = createLauncher({
    env: { DATA_DIR: DATA, PORT: String(PORT), LAUNCHER_PORT: String(CONTROL), GITHUB_API: `http://127.0.0.1:${ghPort}`, GITHUB_TOKEN: 'secret-token', UPDATE_HOUR: 'off', AUTH_DEV: '1', NODE_NO_WARNINGS: '1' },
    childStdio: 'ignore', log: () => {},
  });
  await launcher.start();
  let v = null;
  for (let i = 0; i < 40 && v !== '1.0.0'; i++) { try { v = (await (await fetch(`http://127.0.0.1:${PORT}/api/health`)).json()).version; } catch { /* starting */ } await new Promise((r) => setTimeout(r, 250)); }
  assert.equal(v, '1.0.0');
});
