import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { createServer } from '../src/server.js';
import { createAuth } from '../src/auth.js';

let app, base, dir;
const users = [
  { id: 'u-admin', email: 'arsal@e11-digital.com', name: 'Muhammad Arsal', role: 'admin', active: true, prefs: {}, hash: 'SECRET', salt: 'S' },
  { id: 'u-am', email: 'areej@e11-digital.com', name: 'Areej Masri', role: 'am', active: true, prefs: {} },
  { id: 'u-prod', email: 'haris@e11-digital.com', name: 'Muhammad Haris Sharif', role: 'production', active: true, prefs: {} },
  { id: 'u-free', email: 'free@gmail.com', name: 'Freelancer', role: 'freelancer', active: true, prefs: {}, projectIds: ['p-ford'] },
  { id: 'u-gone', email: 'gone@e11-digital.com', name: 'Gone', role: 'social', active: false, prefs: {} },
];
const seed = {
  meta: { cdUserId: 'u-am' },
  users,
  projects: [{ id: 'p-ford', name: 'Ford', sections: [] }, { id: 'p-alain', name: 'ALAIN', sections: [] }],
  tasks: [
    { id: 't-ford', projectId: 'p-ford', title: 'Ford EDM', comments: [], tags: [], assignees: ['u-prod'] },
    { id: 't-alain', projectId: 'p-alain', title: 'ALAIN reel', comments: [], tags: [], assignees: [] },
  ],
  clients: [{ id: 'cl-ford', name: 'Ford', folders: [] }],
  notifications: [{ id: 'n1', to: 'u-prod', from: 'u-am', text: 'hi', read: false }, { id: 'n2', to: 'u-am', from: 'u-prod', text: 'x', read: false }],
  statuses: [{ id: 'st-todo', name: 'To do' }],
};

const call = async (who, p, opts = {}) => {
  const res = await fetch(base + p, { ...opts, headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json', ...(opts.headers || {}) }, body: opts.body ? JSON.stringify(opts.body) : undefined });
  const type = res.headers.get('content-type') || '';
  return { status: res.status, body: type.includes('json') ? await res.json() : await res.text(), headers: res.headers };
};
const ADMIN = 'arsal@e11-digital.com', AM = 'areej@e11-digital.com', PROD = 'haris@e11-digital.com', FREE = 'free@gmail.com';

// Read Server-Sent Events from /api/events
function listen(who, query = '') {
  const events = [];
  const ctrl = new AbortController();
  const ready = fetch(`${base}/api/events?${query}`, { headers: { 'X-Dev-Email': who }, signal: ctrl.signal }).then(async (res) => {
    const reader = res.body.getReader();
    let buf = '';
    (async () => {
      try {
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          buf += Buffer.from(value).toString('utf8');
          let i;
          while ((i = buf.indexOf('\n\n')) >= 0) {
            const block = buf.slice(0, i); buf = buf.slice(i + 2);
            const ev = /event: (.+)/.exec(block), data = /data: (.+)/.exec(block);
            if (ev && data) events.push({ event: ev[1], data: JSON.parse(data[1]) });
          }
        }
      } catch { /* aborted */ }
    })();
  });
  return { events, ready, close: () => ctrl.abort() };
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-'));
  app = createServer({ dataDir: dir, dev: true, version: '1.0.0-test', adminEmail: ADMIN });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll(seed, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

test('health needs no sign-in', async () => {
  const r = await fetch(base + '/api/health');
  assert.equal(r.status, 200);
  assert.equal((await r.json()).version, '1.0.0-test');
});

test('unknown or deactivated people are refused', async () => {
  assert.equal((await call('stranger@gmail.com', '/api/me')).status, 403);
  assert.equal((await call('gone@e11-digital.com', '/api/me')).status, 403);
  const page = await fetch(base + '/', { headers: { 'X-Dev-Email': 'stranger@gmail.com', Accept: 'text/html' } });
  assert.equal(page.status, 403);
  assert.match(await page.text(), /Ask an Admin to add you/);
});

test('snapshot hides password data and other people’s notifications', async () => {
  const r = await call(PROD, '/api/snapshot');
  assert.equal(r.status, 200);
  const admin = r.body.data.users.find((u) => u.id === 'u-admin');
  assert.equal(admin.hash, undefined);
  assert.deepEqual(r.body.data.notifications.map((n) => n.id), ['n1']);
  assert.equal(r.body.data.tasks.length, 2);
  assert.equal(r.body.data.meta.cdUserId, 'u-am');
});

test('freelancer only sees their own projects and tasks', async () => {
  const r = await call(FREE, '/api/snapshot');
  assert.deepEqual(r.body.data.projects.map((p) => p.id), ['p-ford']);
  assert.deepEqual(r.body.data.tasks.map((t) => t.id), ['t-ford']);
  const bad = await call(FREE, '/api/push', { method: 'POST', body: { changes: [{ kind: 'tasks', id: 't-alain', data: { id: 't-alain', projectId: 'p-alain', title: 'hacked' } }] } });
  assert.equal(bad.body.results[0].refused, true);
  const moved = await call(FREE, '/api/push', { method: 'POST', body: { changes: [{ kind: 'tasks', id: 't-ford', base: seed.tasks[0], data: { ...seed.tasks[0], projectId: 'p-alain' } }] } });
  assert.equal(moved.body.results[0].refused, true, 'cannot move a task out of their projects');
  assert.equal(app.store.get('tasks', 't-alain').title, 'ALAIN reel');
});

test('two people comment on the same task at once and both comments are kept, live to others', async () => {
  const watcher = listen(ADMIN, 'client=admin-mac');
  await watcher.ready; await wait(100);
  const snap = (await call(PROD, '/api/snapshot')).body;
  const t0 = snap.data.tasks.find((t) => t.id === 't-ford');
  const a = { ...t0, comments: [{ id: 'c-haris', text: 'From Haris' }] };
  const b = { ...t0, comments: [{ id: 'c-areej', text: 'From Areej' }] };
  const r1 = await call(PROD, '/api/push', { method: 'POST', body: { client: 'haris-mac', changes: [{ kind: 'tasks', id: 't-ford', base: t0, data: a }] } });
  const r2 = await call(AM, '/api/push', { method: 'POST', body: { client: 'areej-mac', changes: [{ kind: 'tasks', id: 't-ford', base: t0, data: b }] } });
  assert.equal(r1.status, 200); assert.equal(r2.status, 200);
  const merged = r2.body.results[0].data;
  assert.deepEqual(merged.comments.map((c) => c.id).sort(), ['c-areej', 'c-haris']);
  await wait(200);
  const changes = watcher.events.filter((e) => e.event === 'changes');
  assert.equal(changes.length, 2, 'admin received both changes live');
  assert.equal(changes[1].data.client, 'areej-mac');
  assert.deepEqual(changes[1].data.changes[0].data.comments.length, 2);
  watcher.close();
});

test('catching up: an app that was offline gets what it missed', async () => {
  const before = app.store.rev();
  await call(ADMIN, '/api/push', { method: 'POST', body: { changes: [{ kind: 'projects', id: 'p-new', data: { id: 'p-new', name: 'KOREA 360', sections: [] } }] } });
  const late = listen(PROD, `since=${before}`);
  await late.ready; await wait(200);
  const got = late.events.filter((e) => e.event === 'changes').flatMap((e) => e.data.changes);
  assert.ok(got.some((c) => c.id === 'p-new'));
  assert.equal(late.events[0].event, 'hello');
  late.close();
});

test('only Admins add or remove a client; Account Managers can still rename one', async () => {
  const add = (who, id) => call(who, '/api/push', { method: 'POST', body: { changes: [{ kind: 'projects', id, data: { id, name: 'New client', sections: [] } }] } });
  assert.equal((await add(AM, 'p-am')).body.results[0].refused, true);
  assert.equal((await add(PROD, 'p-prod')).body.results[0].refused, true);
  assert.ok(!(await add(ADMIN, 'p-adm')).body.results[0].refused);
  const ren = await call(AM, '/api/push', { method: 'POST', body: { changes: [{ kind: 'projects', id: 'p-adm', data: { id: 'p-adm', name: 'Renamed', sections: [] } }] } });
  assert.ok(!ren.body.results[0].refused);
  const del = (who) => call(who, '/api/push', { method: 'POST', body: { changes: [{ kind: 'projects', id: 'p-adm', del: true }] } });
  assert.equal((await del(AM)).body.results[0].refused, true);
  assert.ok(!(await del(ADMIN)).body.results[0].refused);
});

test('permissions: production cannot edit settings, clients or other people', async () => {
  const meta = await call(PROD, '/api/push', { method: 'POST', body: { changes: [{ kind: 'meta', id: 'main', data: { cdUserId: 'u-prod' } }] } });
  assert.equal(meta.body.results[0].refused, true);
  const cl = await call(PROD, '/api/push', { method: 'POST', body: { changes: [{ kind: 'clients', id: 'cl-x', data: { id: 'cl-x', name: 'X', folders: [] } }] } });
  assert.equal(cl.body.results[0].refused, true);
  const other = await call(PROD, '/api/push', { method: 'POST', body: { changes: [{ kind: 'users', id: 'u-am', data: { ...users[1], name: 'nope' } }] } });
  assert.equal(other.body.results[0].refused, true);
  const promote = await call(PROD, '/api/push', { method: 'POST', body: { changes: [{ kind: 'users', id: 'u-prod', base: users[2], data: { ...users[2], role: 'admin' } }] } });
  assert.equal(promote.body.results[0].refused, true);
  const office = await call(PROD, '/api/push', { method: 'POST', body: { changes: [{ kind: 'users', id: 'u-prod', base: users[2], data: { ...users[2], office: 'Dubai' } }] } });
  assert.equal(office.body.results[0].refused, false);
  assert.equal(app.store.get('users', 'u-prod').office, 'Dubai');
  const amClient = await call(AM, '/api/push', { method: 'POST', body: { changes: [{ kind: 'clients', id: 'cl-alain', data: { id: 'cl-alain', name: 'ALAIN', folders: [] } }] } });
  assert.equal(amClient.body.results[0].refused, false);
  const amDel = await call(AM, '/api/push', { method: 'POST', body: { changes: [{ kind: 'clients', id: 'cl-alain', del: true }] } });
  assert.equal(amDel.body.results[0].refused, true, 'only Admin deletes a client');
  const admDel = await call(ADMIN, '/api/push', { method: 'POST', body: { changes: [{ kind: 'clients', id: 'cl-alain', del: true }] } });
  assert.equal(admDel.body.results[0].deleted, true);
  assert.equal(app.store.get('clients', 'cl-alain'), null);
});

test('password fields survive when a user edits their profile', async () => {
  const snap = (await call(ADMIN, '/api/snapshot')).body.data.users.find((u) => u.id === 'u-admin');
  await call(ADMIN, '/api/push', { method: 'POST', body: { changes: [{ kind: 'users', id: 'u-admin', base: snap, data: { ...snap, office: 'HQ' } }] } });
  const stored = app.store.get('users', 'u-admin');
  assert.equal(stored.hash, 'SECRET');
  assert.equal(stored.office, 'HQ');
});

test('files: chunked upload, range download, thumbnails, trash, zip', async () => {
  const big = crypto.randomBytes(3 * 1024 * 1024 + 123);
  let pathRel = null, last;
  for (let off = 0; off < big.length; off += 2 * 1024 * 1024) {
    last = await call(PROD, '/api/host/writeChunk', { method: 'POST', body: { taskId: 't-ford', name: 'reel.bin', path: pathRel, b64: big.subarray(off, off + 2 * 1024 * 1024).toString('base64') } });
    pathRel = last.body.path;
  }
  assert.equal(pathRel, 'attachments/t-ford/reel.bin');
  assert.equal(last.body.size, big.length);
  const part = await fetch(`${base}/__file/${pathRel}`, { headers: { 'X-Dev-Email': PROD, Range: 'bytes=100-199' } });
  assert.equal(part.status, 206);
  assert.deepEqual(Buffer.from(await part.arrayBuffer()), big.subarray(100, 200));
  // escaping the files folder is refused
  assert.equal((await fetch(`${base}/__file/..%2F..%2Fetc%2Fpasswd`, { headers: { 'X-Dev-Email': PROD } })).status, 400);
  assert.equal((await call(PROD, '/api/host/writeChunk', { method: 'POST', body: { dest: '../x', name: 'a', b64: 'AA==' } })).status, 403);
  // client assets: only Admin/AM upload
  assert.equal((await call(PROD, '/api/host/writeChunk', { method: 'POST', body: { dest: 'Clients/Ford/Logos', name: 'a.txt', b64: 'AA==' } })).status, 403);
  const logoPng = path.join(dir, 'files', 'attachments', 'logo.png');
  execFileSync('ffmpeg', ['-v', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=1200x800', '-frames:v', '1', logoPng]);
  const up = await call(AM, '/api/host/writeChunk', { method: 'POST', body: { dest: 'Clients/Ford/Logos', name: 'Ford Logo.png', b64: fs.readFileSync(logoPng).toString('base64') } });
  assert.equal(up.body.path, 'Clients/Ford/Logos/Ford Logo.png');
  const th = await call(PROD, '/api/host/thumb', { method: 'POST', body: { id: 'f1', path: up.body.path } });
  assert.equal(th.body.thumb, '.thumbs/f1/thumb.png');
  const thumbRes = await fetch(`${base}/__file/${th.body.thumb}`, { headers: { 'X-Dev-Email': PROD } });
  assert.equal(thumbRes.headers.get('content-type'), 'image/png');
  const logo = await call(AM, '/api/host/processImage', { method: 'POST', body: { path: up.body.path, kind: 'logo' } });
  assert.match(logo.body.path, /^Clients\/_logos\/client-.+\.png$/);
  const pdf = path.join(dir, 'files', 'attachments', 't-ford', 'brief.pdf');
  execFileSync('ffmpeg', ['-v', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=600x800', '-frames:v', '1', pdf.replace('.pdf', '.png')]);
  // make a one-page PDF from the image with pdftoppm's sibling tool if present; otherwise skip
  let pdfOk = false;
  try { execFileSync('python3', ['-c', `from PIL import Image; Image.open(${JSON.stringify(pdf.replace('.pdf', '.png'))}).convert('RGB').save(${JSON.stringify(pdf)})`]); pdfOk = true; } catch { /* no PIL */ }
  if (pdfOk) {
    const pth = await call(PROD, '/api/host/thumb', { method: 'POST', body: { id: 'f2', path: 'attachments/t-ford/brief.pdf' } });
    assert.equal(pth.body.thumb, '.thumbs/f2/thumb.png');
  }
  // zip of several files
  const z = await call(PROD, '/api/host/exportFiles', { method: 'POST', body: { folder: 'Ford - Logos', paths: [up.body.path, pathRel] } });
  assert.equal(z.body.count, 2);
  const zipRes = await fetch(base + z.body.url, { headers: { 'X-Dev-Email': PROD } });
  const zipFile = path.join(dir, 'out.zip');
  fs.writeFileSync(zipFile, Buffer.from(await zipRes.arrayBuffer()));
  const listing = execFileSync('python3', ['-c', `import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(z.testzip()); print(sorted((i.filename,i.file_size) for i in z.infolist()))`, zipFile]).toString();
  assert.match(listing, /^None/);
  assert.match(listing, new RegExp(`'reel.bin', ${big.length}`));
  // trash keeps the file for 30 days instead of deleting it
  const tr = await call(PROD, '/api/host/trashMany', { method: 'POST', body: { paths: [pathRel] } });
  assert.equal(tr.body.trashed, 1);
  assert.equal(fs.existsSync(path.join(dir, 'files', pathRel)), false);
  const day = new Date().toISOString().slice(0, 10);
  assert.equal(fs.existsSync(path.join(dir, 'trash', day, pathRel)), true);
});

test('import is admin-only and takes a backup first', async () => {
  assert.equal((await call(AM, '/api/import', { method: 'POST', body: { data: seed } })).status, 403);
  const r = await call(ADMIN, '/api/import', { method: 'POST', body: { data: { tasks: [{ id: 't-imported', title: 'From Mac', comments: [] }] } } });
  assert.equal(r.status, 200);
  assert.ok(fs.readdirSync(path.join(dir, 'backups')).some((f) => f.startsWith('before-import-')));
  assert.equal(app.store.get('tasks', 't-imported').title, 'From Mac');
});

test('Cloudflare token check: valid token accepted, wrong app / expired / forged refused', async () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'k1', alg: 'RS256' };
  const fetchImpl = async (url) => { assert.equal(url, 'https://e11hq.cloudflareaccess.com/cdn-cgi/access/certs'); return { ok: true, json: async () => ({ keys: [jwk] }) }; };
  const auth = createAuth({ team: 'e11hq', aud: 'AUD123', fetchImpl });
  const sign = (payload, key = privateKey, kid = 'k1') => {
    const h = Buffer.from(JSON.stringify({ alg: 'RS256', kid, typ: 'JWT' })).toString('base64url');
    const p = Buffer.from(JSON.stringify(payload)).toString('base64url');
    return `${h}.${p}.${crypto.sign('RSA-SHA256', Buffer.from(`${h}.${p}`), key).toString('base64url')}`;
  };
  const now = Math.floor(Date.now() / 1000);
  const good = { iss: 'https://e11hq.cloudflareaccess.com', aud: ['AUD123'], email: 'Areej@e11-digital.com', exp: now + 600, iat: now };
  assert.deepEqual(await auth.identify({ headers: { 'cf-access-jwt-assertion': sign(good) }, url: '/' }), { email: 'areej@e11-digital.com', sub: null });
  assert.equal((await auth.identify({ headers: { cookie: 'a=b; CF_Authorization=' + sign(good) }, url: '/' })).email, 'areej@e11-digital.com');
  await assert.rejects(auth.identify({ headers: { 'cf-access-jwt-assertion': sign({ ...good, aud: ['OTHER'] }) }, url: '/' }), /Wrong application/);
  await assert.rejects(auth.identify({ headers: { 'cf-access-jwt-assertion': sign({ ...good, exp: now - 3600 }) }, url: '/' }), /expired/);
  const other = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey;
  await assert.rejects(auth.identify({ headers: { 'cf-access-jwt-assertion': sign(good, other) }, url: '/' }), /Bad signature/);
  await assert.rejects(auth.identify({ headers: {}, url: '/?as=x@y.com' }), /Not signed in/);
  // development shortcut is OFF unless explicitly enabled
  const prodAuth = createAuth({ team: 'e11hq', aud: 'AUD123', fetchImpl });
  await assert.rejects(prodAuth.identify({ headers: { 'x-dev-email': 'arsal@e11-digital.com' }, url: '/' }), /Not signed in/);
});

test('import replaces the first-sign-in Admin account with the same person from the Mac', async () => {
  const d2 = fs.mkdtempSync(path.join(os.tmpdir(), 'e11i-'));
  const a2 = createServer({ dataDir: d2, dev: true, adminEmail: 'haris@e11-digital.com' });
  const port = await a2.listen(0, '127.0.0.1');
  const h = { 'X-Dev-Email': 'haris@e11-digital.com', 'Content-Type': 'application/json' };
  const me1 = await (await fetch(`http://127.0.0.1:${port}/api/me`, { headers: h })).json();
  assert.equal(me1.user.role, 'admin');
  const r = await fetch(`http://127.0.0.1:${port}/api/import`, { method: 'POST', headers: h, body: JSON.stringify({ data: { users: [{ id: 'u-haris-mac', email: 'Haris@e11-digital.com', role: 'admin', name: 'Muhammad Haris Sharif', active: true }], tasks: [] } }) });
  assert.equal(r.status, 200);
  const me2 = await (await fetch(`http://127.0.0.1:${port}/api/me`, { headers: h })).json();
  assert.equal(me2.user.id, 'u-haris-mac');
  assert.equal(a2.store.list('users').length, 1);
  await a2.close(); fs.rmSync(d2, { recursive: true, force: true });
});
