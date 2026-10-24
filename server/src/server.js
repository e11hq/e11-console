// E11 Console server: serves the app, keeps everyone's data in one place, pushes live changes
// to every open app, and stores files. No outside packages — only what ships with Node 22.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { openStore } from './store.js';
import { createAuth } from './auth.js';
import { createAccess } from './access.js';
import { createFiles, mimeOf, httpError } from './files.js';
import { createCfSync } from './cfsync.js';
import { createWebPush, notifMessage } from './webpush.js';
import { sampleData } from './sample.js';
import { createAppIcon } from './appicon.js';

const BODY_LIMIT = 12 * 1024 * 1024; // 2 MB upload pieces arrive as ~2.7 MB of base64

export function createServer(cfg) {
  const dataDir = cfg.dataDir;
  const store = cfg.store || openStore(cfg.dbFile || path.join(dataDir, 'db', 'e11.sqlite'));
  const auth = cfg.auth || createAuth({ team: cfg.cfTeam, aud: cfg.cfAud, dev: !!cfg.dev });
  const access = createAccess(store);
  const files = createFiles(dataDir);
  const version = cfg.version || '0.0.0-dev';
  const webDir = cfg.webDir || null;
  const streams = new Set(); // open live-update connections
  const uploads = new Map(); // file path -> who is uploading it (pieces can only be added by them)
  const webPush = createWebPush({ store, fetchImpl: cfg.pushFetch || fetch, subject: cfg.pushSubject || 'mailto:admin@e11hq.com' });
  const macDir = cfg.macDir || (webDir ? path.join(webDir, '..', 'mac') : null);
  const appIcon = createAppIcon({ store, defaultFile: macDir && path.join(macDir, 'AppIcon.png') });
  // The newest Mac app (native part) the installer hands out; older Mac apps are asked to update
  const macShell = (() => { try { const m = fs.readFileSync(path.join(macDir, 'main.js'), 'utf8').match(/var SHELL_VERSION = (\d+);/); return m ? Number(m[1]) : 1; } catch { return 1; } })();
  // The owner (ADMIN_EMAIL) controls things that change every Mac, like the Dock icon. No owner set: any Admin.
  const isOwner = (u) => (cfg.adminEmail ? String(u.email || '').toLowerCase() === cfg.adminEmail.toLowerCase() : access.isAdm(u));
  const cfSync = cfg.cfSync || createCfSync({ accountId: cfg.cfAccountId, token: cfg.cfApiToken, groupId: cfg.cfGroupId, listUsers: () => store.list('users'), fetchImpl: cfg.cfFetch || fetch });

  /* ---------- helpers ---------- */
  const json = (res, status, body) => {
    const s = JSON.stringify(body);
    res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Content-Length': Buffer.byteLength(s) });
    res.end(s);
  };
  // Raw bytes (upload pieces sent as-is: no base64, a third smaller and nothing to decode)
  const readRaw = (req, limit = BODY_LIMIT) => new Promise((resolve, reject) => {
    let size = 0; const parts = [];
    req.on('data', (c) => { size += c.length; if (size > limit) { reject(httpError(413, 'Too large')); req.destroy(); } else parts.push(c); });
    req.on('end', () => resolve(Buffer.concat(parts)));
    req.on('error', reject);
  });
  const readBody = (req, limit = BODY_LIMIT) => new Promise((resolve, reject) => {
    let size = 0; const parts = [];
    req.on('data', (c) => { size += c.length; if (size > limit) { reject(httpError(413, 'Too large')); req.destroy(); } else parts.push(c); });
    req.on('end', () => { try { resolve(parts.length ? JSON.parse(Buffer.concat(parts).toString('utf8')) : {}); } catch { reject(httpError(400, 'Bad JSON')); } });
    req.on('error', reject);
  });
  const page = (res, status, title, body) => {
    res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#0e0e11;color:#ececf1;font:15px/1.5 -apple-system,Segoe UI,Inter,sans-serif">
<div style="max-width:440px;padding:32px;text-align:center"><div style="font-size:20px;font-weight:700;margin-bottom:8px">${title}</div><div style="color:#9d9da8">${body}</div></div>`);
  };
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // The person making this request (null + error page if they can't be identified)
  async function who(req, res) {
    let id;
    try { id = await auth.identify(req); } catch (e) {
      if (wantsHtml(req)) page(res, 401, 'Please sign in', esc(e.message));
      else json(res, 401, { ok: false, error: e.message });
      return null;
    }
    let u = access.userByEmail(id.email);
    // Very first sign-in on an empty server: the configured admin email becomes the first Admin
    if (!u && cfg.adminEmail && id.email === cfg.adminEmail.toLowerCase() && !store.list('users').length) {
      u = { id: 'u-' + crypto.randomBytes(5).toString('hex'), email: id.email, name: '', role: 'admin', avatar: null, setup: true, active: true, createdAt: new Date().toISOString(), prefs: {} };
      store.apply([{ kind: 'users', id: u.id, data: u }], u.id);
    }
    if (!u) {
      const msg = `You're signed in as <b>${esc(id.email)}</b>, but there's no E11 Console account for this email yet. Ask an Admin to add you on the Team page.`;
      if (wantsHtml(req)) page(res, 403, 'No account yet', msg); else json(res, 403, { ok: false, error: 'No E11 Console account for ' + id.email });
      return null;
    }
    return u;
  }
  const wantsHtml = (req) => req.method === 'GET' && /text\/html/.test(req.headers.accept || '') && !req.url.startsWith('/api/');

  function visibleSnapshot(u) {
    const snap = store.snapshot();
    const data = {};
    for (const [kind, val] of Object.entries(snap.data)) {
      data[kind] = kind === 'meta' ? val : val.filter((x) => access.canSee(u, kind, x)).map((x) => access.shape(u, kind, x));
    }
    return { rev: snap.rev, data };
  }
  const forUser = (u, r) => {
    if (r.deleted) return { kind: r.kind, id: r.id, deleted: true, rev: r.rev };
    if (!access.canSee(u, r.kind, r.data)) return { kind: r.kind, id: r.id, deleted: true, rev: r.rev, hidden: true };
    return { kind: r.kind, id: r.id, data: access.shape(u, r.kind, r.data), rev: r.rev };
  };

  // Tell every open app about changes (each person only receives what they're allowed to see)
  function broadcast(rev, results, fromClient, byUser) {
    const changed = results.filter((r) => !r.refused && !r.unchanged);
    if (!changed.length) return;
    for (const s of streams) {
      const u = store.get('users', s.userId) || s.user;
      // A freelancer's access changed (their projects, or which client a project belongs to): reload their data
      if (u.role === 'freelancer' && changed.some((r) => (r.kind === 'users' && r.id === u.id) || r.kind === 'projects')) {
        const was = s.lastAccess, now = JSON.stringify([u.projectIds || [], store.list('projects').map((p) => [p.id, p.clientId || null])]);
        s.lastAccess = now;
        if (was !== undefined && was !== now) { send(s, 'resync', { rev }); continue; }
      }
      const list = changed.map((r) => forUser(u, r)).filter((r) => !(r.hidden && r.kind === 'notifications'));
      if (!list.length) continue;
      send(s, 'changes', { rev, client: fromClient || null, by: byUser || null, changes: list });
    }
  }
  const send = (s, event, data) => { try { s.res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`); } catch { /* closed */ } };

  /* ---------- routes ---------- */
  async function handle(req, res) {
    const url = new URL(req.url, 'http://local');
    const p = decodeURIComponent(url.pathname);

    if (p === '/api/health') return json(res, 200, { ok: true, version, rev: store.rev() });

    // Mac app installer (no sign-in: these files hold no data — Cloudflare lets /install through)
    // New installs get the icon the owner chose
    if (p === '/install/AppIcon.png' && appIcon.info().custom) {
      res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'no-cache' });
      return res.end(appIcon.png());
    }
    if (p === '/install' || p === '/install/main.js' || p === '/install/AppIcon.png') {
      const file = p === '/install' ? 'install.sh' : p.slice('/install/'.length);
      const full = macDir && path.join(macDir, file);
      if (!full || !fs.existsSync(full)) return json(res, 404, { ok: false, error: 'Installer not available' });
      if (file === 'install.sh') {
        const host = String(req.headers['x-forwarded-host'] || req.headers.host || 'console.e11hq.com').replace(/[^\w.:-]/g, '');
        const scheme = /^(localhost|127\.)/.test(host) ? 'http' : 'https';
        const body = fs.readFileSync(full, 'utf8').replace('__SERVER__', `${scheme}://${host}`);
        res.writeHead(200, { 'Content-Type': 'text/x-shellscript; charset=utf-8', 'Cache-Control': 'no-cache' });
        return res.end(body);
      }
      res.writeHead(200, { 'Content-Type': mimeOf(full), 'Cache-Control': 'no-cache' });
      return fs.createReadStream(full).pipe(res);
    }

    const u = await who(req, res);
    if (!u) return;

    if (p === '/api/me') return json(res, 200, { ok: true, user: access.shape(u, 'users', u), owner: isOwner(u), appIcon: appIcon.info(), macShell, version, rev: store.rev() });

    // Mac app Dock icon: everyone reads it; only the owner changes it (every open Mac app swaps it live)
    if (p === '/api/app-icon' && req.method === 'GET') {
      const buf = appIcon.png();
      if (!buf) return json(res, 404, { ok: false, error: 'No icon' });
      res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'no-cache', 'Content-Length': buf.length });
      return res.end(buf);
    }
    if (p === '/api/app-icon/info') return json(res, 200, { ok: true, ...appIcon.info(), canEdit: isOwner(u) });
    if ((p === '/api/app-icon' || p === '/api/app-icon/reset') && req.method === 'POST') {
      if (!isOwner(u)) return json(res, 403, { ok: false, error: 'Only the owner can change the app icon' });
      let info;
      try { info = p.endsWith('/reset') ? appIcon.reset(u.id) : appIcon.set((await readBody(req)).png, u.id); } catch (e) { return json(res, e.status || 400, { ok: false, error: e.message }); }
      for (const s of streams) send(s, 'appicon', info);
      return json(res, 200, { ok: true, ...info });
    }

    // App updates (the launcher runs inside the same container): Admins see status and can update or roll back
    if (p === '/api/updates') {
      if (!access.isAdm(u)) return json(res, 403, { ok: false, error: 'Admins only' });
      if (!cfg.launcherUrl) return json(res, 200, { ok: true, managed: false, running: version });
      const action = req.method === 'POST' ? (await readBody(req)).action : null;
      const route = action === 'check' ? '/check' : action === 'update' ? '/update' : action === 'rollback' ? '/rollback' : '/status';
      const r = await fetch(cfg.launcherUrl + route, { method: action ? 'POST' : 'GET' }).then((x) => x.json()).catch((e) => ({ ok: false, error: 'Updater not reachable: ' + e.message }));
      return json(res, 200, { managed: true, ...r });
    }
    // "What's new" for everyone after an update
    if (p === '/api/whatsnew') {
      if (!cfg.launcherUrl) return json(res, 200, { ok: true, version, notes: '' });
      const r = await fetch(cfg.launcherUrl + '/status').then((x) => x.json()).catch(() => null);
      const n = r && r.currentNotes;
      return json(res, 200, { ok: true, version, name: n ? n.name : version, notes: n ? n.notes : '', publishedAt: n ? n.publishedAt : null });
    }

    // Cloudflare access for freelancers: status, and "sync now" for Admins
    if (p === '/api/cloudflare') {
      if (!access.isAdm(u)) return json(res, 403, { ok: false, error: 'Admins only' });
      if (req.method === 'POST') await cfSync.syncNow();
      return json(res, 200, { ok: true, ...cfSync.status() });
    }

    // Phone notifications: the server's public key, and turning them on / off for this device
    if (p === '/api/push/key') return json(res, 200, { ok: true, key: webPush.publicKey() });
    if (p === '/api/push/subscribe' && req.method === 'POST') {
      const body = await readBody(req);
      const n = webPush.subscribe(u.id, body.subscription, req.headers['user-agent']);
      return json(res, 200, { ok: true, devices: n });
    }
    if (p === '/api/push/unsubscribe' && req.method === 'POST') {
      const body = await readBody(req);
      webPush.unsubscribe(u.id, String(body.endpoint || ''));
      return json(res, 200, { ok: true });
    }
    if (p === '/api/push/status' && req.method === 'POST') {
      const body = await readBody(req);
      return json(res, 200, { ok: true, on: webPush.has(u.id, String(body.endpoint || '')), devices: webPush.devices(u.id) });
    }
    if (p === '/api/push/test' && req.method === 'POST') {
      const r = await webPush.sendTo(u.id, { title: 'E11 Console', body: 'Notifications are on. This is how they’ll look on this phone.', tag: 'test' });
      return json(res, 200, { ok: true, ...r });
    }

    // Test copy only: fill it with sample people, projects, tasks, comments and replies for trying things out
    if (p === '/api/sample' && req.method === 'POST') {
      if (!access.isAdm(u)) return json(res, 403, { ok: false, error: 'Admins only' });
      if (!/-test\.|-dev$/.test(version)) return json(res, 403, { ok: false, error: 'Sample data is only for the test copy' });
      const data = sampleData(store, u.id, path.join(dataDir, 'files'));
      const { rev, results } = store.importAll(data, u.id);
      broadcast(rev, results, null, u.id);
      return json(res, 200, { ok: true, rev, tasks: data.tasks.length, people: data.users.length });
    }

    if (p === '/api/snapshot' && req.method === 'GET') return json(res, 200, { ok: true, version, ...visibleSnapshot(u) });

    if (p === '/api/push' && req.method === 'POST') {
      const body = await readBody(req);
      const changes = Array.isArray(body.changes) ? body.changes : [];
      const fresh = new Set(changes.filter((ch) => ch && ch.kind === 'notifications' && !ch.del && !store.get('notifications', String(ch.id))).map((ch) => String(ch.id)));
      const restoring = new Set(changes.filter((ch) => ch && !ch.del && ch.kind !== 'trash').map((ch) => `${ch.kind}:${ch.id}`));
      const { rev, results } = store.apply(changes, u.id, (ch, current) => access.canWrite(u, ch, current, { restoring }));
      broadcast(rev, results, body.client, u.id);
      // new notifications also go to the person's phone
      results.filter((r) => r.kind === 'notifications' && fresh.has(String(r.id)) && !r.refused && !r.deleted && r.data && r.data.to && r.data.to !== u.id)
        .forEach((r) => webPush.sendTo(r.data.to, notifMessage(store, r.data)).catch(() => {}));
      if (results.some((r) => r.kind === 'users' && !r.refused && !r.unchanged)) cfSync.schedule();
      return json(res, 200, { ok: true, rev, results: results.map((r) => ({ ...forUser(u, r), refused: !!r.refused })) });
    }

    // Live updates (Server-Sent Events). Sends anything missed since `since`, then changes as they happen.
    if (p === '/api/events' && req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
      res.write('retry: 3000\n\n');
      const s = { res, userId: u.id, user: u, client: url.searchParams.get('client') || null };
      if (u.role === 'freelancer') s.lastAccess = JSON.stringify([u.projectIds || [], store.list('projects').map((p) => [p.id, p.clientId || null])]);
      streams.add(s);
      send(s, 'hello', { version, rev: store.rev(), appIcon: appIcon.info() });
      const since = Number(url.searchParams.get('since'));
      if (Number.isFinite(since) && since > 0 && since < store.rev()) {
        const missed = store.since(since);
        if (missed.length) send(s, 'changes', { rev: store.rev(), client: null, changes: missed.map((r) => forUser(u, r)).filter((r) => !(r.hidden && r.kind === 'notifications')) });
      }
      const ping = setInterval(() => { try { res.write('event: ping\ndata: {}\n\n'); } catch { /* closed */ } }, 25000);
      req.on('close', () => { clearInterval(ping); streams.delete(s); });
      return;
    }

    if (p.startsWith('/api/host/') && req.method === 'POST') {
      const cmd = p.slice('/api/host/'.length);
      const fn = files.commands[cmd === 'writeChunkBin' ? 'writeChunk' : cmd];
      if (!fn) return json(res, 404, { ok: false, error: 'Unknown command ' + cmd });
      // writeChunkBin: the same as writeChunk, with the details in the address and the piece as raw bytes
      const bin = cmd === 'writeChunkBin';
      let body;
      if (bin) {
        const q = new URL(req.url, 'http://x').searchParams;
        body = {};
        for (const k of ['taskId', 'dest', 'name', 'path', 'offset']) if (q.has(k)) body[k] = q.get(k);
        body.data = await readRaw(req, BODY_LIMIT);
      } else body = await readBody(req, cmd === 'expenseReport' ? 96 * 1024 * 1024 : BODY_LIMIT);   // up to a year of report pages
      const manager = access.isAdm(u) || u.role === 'am';
      const deny = (msg) => json(res, 403, { ok: false, error: msg || 'Not allowed' });
      if (cmd === 'writeChunk' || bin) {
        if (body.dest && String(body.dest).startsWith('Finance/')) { if (access.finLevel(u) !== 'admin') return deny('Only a Finance Admin can add invoices'); }
        else if (body.dest && String(body.dest).startsWith('Claims/')) { if (String(body.dest).split('/')[1] !== u.id) return deny('You can only add files to your own claims'); }
        else if (body.dest && !manager) return deny('Only Admins and Account Managers can upload client assets');
        if (!body.dest && access.isFinance(u) && body.taskId !== '_uploads') return deny();
        if (!body.dest && u.role === 'freelancer' && body.taskId !== '_uploads') { const t = store.get('tasks', String(body.taskId || '')); if (!t || !access.canSee(u, 'tasks', t)) return deny(); }
        // later pieces may only be added to a file this person started uploading
        if (body.path) { const up = uploads.get(body.path); if (!up || up.userId !== u.id) return deny('Upload not found — please try again'); }
        const out = await files.commands.writeChunk(body, u);
        uploads.set(out.path, { userId: u.id, at: Date.now() });
        if (uploads.size > 500) for (const [k, v] of uploads) if (Date.now() - v.at > 6 * 3600_000) uploads.delete(k);
        return json(res, 200, out);
      }
      if (cmd === 'makeDir' && !manager) return deny();
      if (access.isFinance(u) && !['writeChunk', 'thumb', 'processImage', 'docPreview', 'pdfPages', 'exportFiles', 'claimPdf', 'expenseReport'].includes(cmd)) return deny();
      if (cmd === 'expenseReport' && !(access.finLevel(u) || access.isAdm(u))) return deny('Only Admins and Finance can download the expenses report');
      if (cmd === 'expenseReport' && (body.files || []).some((x) => { const fp = String((x && x.path) || ''); return !(fp.startsWith('Finance/') || fp.startsWith('Claims/')) || !access.canReadFile(u, fp); })) return deny();
      if (cmd === 'claimPdf' && !(String(body.userId || '') === u.id || access.finLevel(u))) return deny();
      if (cmd === 'trashMany' || cmd === 'trashPath') {
        const paths = body.paths || [body.path];
        if (paths.some((x) => String(x || '').startsWith('Clients/')) && !manager) return deny();
        if (paths.some((x) => !access.canReadFile(u, String(x || '')))) return deny();
      }
      if (cmd === 'claimPdf' && (body.receipts || []).some((x) => !access.canReadFile(u, String(x || '')) || !String(x || '').startsWith('Claims/'))) return deny();
      if (['thumb', 'processImage', 'docPreview', 'pdfPages'].includes(cmd) && !access.canReadFile(u, String(body.path || '')) && !(cmd === 'processImage' && uploads.get(body.path) && uploads.get(body.path).userId === u.id)) return deny();
      if (cmd === 'processImage' && body.kind === 'logo' && !manager) return deny();
      if (cmd === 'exportFiles') body.paths = (body.paths || []).filter((x) => access.canReadFile(u, String(x || '')));
      return json(res, 200, await fn(body, u));
    }

    if (p.startsWith('/api/zip/')) return files.serveZip(res, p.slice('/api/zip/'.length));

    // One-time move from the Mac app: an Admin uploads the whole data file
    if (p === '/api/import' && req.method === 'POST') {
      if (!access.isAdm(u)) return json(res, 403, { ok: false, error: 'Only an Admin can import data' });
      const body = await readBody(req, 90 * 1024 * 1024);
      if (!body || !body.data) return json(res, 400, { ok: false, error: 'No data' });
      store.backup(path.join(dataDir, 'backups', `before-import-${Date.now()}.sqlite`));
      // The Admin account made on first sign-in is replaced by the same person's account from the Mac
      const incoming = new Map((body.data.users || []).map((x) => [String(x.email || '').toLowerCase(), String(x.id)]));
      const dupes = store.list('users').filter((x) => incoming.has(String(x.email || '').toLowerCase()) && incoming.get(String(x.email || '').toLowerCase()) !== x.id);
      if (dupes.length) store.apply(dupes.map((x) => ({ kind: 'users', id: x.id, del: true })), u.id);
      const { rev, results } = store.importAll(body.data, u.id);
      broadcast(rev, results, null, u.id);
      cfSync.schedule();
      return json(res, 200, { ok: true, rev, count: results.length });
    }

    if (p.startsWith('/__file/') && (req.method === 'GET' || req.method === 'HEAD')) {
      const rel = p.slice('/__file/'.length);
      if (!access.canReadFile(u, rel)) return json(res, 403, { ok: false, error: 'Not allowed' });
      if (url.searchParams.get('w')) return files.serveSized(req, res, rel, url.searchParams.get('w'));
      return files.serve(req, res, rel);
    }

    if (p.startsWith('/api/')) return json(res, 404, { ok: false, error: 'Not found' });
    return serveWeb(req, res, p);
  }

  function serveWeb(req, res, p) {
    if (!webDir || !fs.existsSync(path.join(webDir, 'index.html'))) return page(res, 200, 'E11 Console server', `Running version ${esc(version)}.`);
    let rel = p === '/' ? 'index.html' : p.replace(/^\/+/, '');
    if (rel.split('/').includes('..')) return json(res, 400, { ok: false });
    let full = path.join(webDir, rel);
    if (!fs.existsSync(full) || fs.statSync(full).isDirectory()) full = path.join(webDir, 'index.html');
    const type = mimeOf(full);
    const html = type.startsWith('text/html');
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': html || /sw\.js$/.test(full) ? 'no-cache' : 'public, max-age=86400', 'X-Content-Type-Options': 'nosniff' });
    if (req.method === 'HEAD') return res.end();
    if (html) {
      // app.js?v=1.2.0 — every version gets fresh files, older ones can be cached for a day
      const v = encodeURIComponent(version);
      return res.end(fs.readFileSync(full, 'utf8').replace(/(src|href)="(app\.js|styles\.css|studio\.css|phone\.js|phone\.css|finance\.js|finance\.css|home\.js|home\.css|claims\.js|claims\.css)"/g, `$1="$2?v=${v}"`));
    }
    fs.createReadStream(full).pipe(res);
  }

  const server = http.createServer((req, res) => {
    handle(req, res).catch((e) => {
      const status = e.status || 500;
      if (status >= 500) console.error(new Date().toISOString(), req.method, req.url, e);
      if (!res.headersSent) json(res, status, { ok: false, error: status >= 500 ? 'Server error' : e.message });
      else try { res.end(); } catch { /* ignore */ }
    });
  });
  server.keepAliveTimeout = 65000;

  return {
    server, store, files, cfSync, webPush,
    listen: (port, host) => new Promise((ok) => server.listen(port, host, () => ok(server.address().port))),
    close: () => new Promise((ok) => { for (const s of streams) try { s.res.end(); } catch { /* ignore */ } server.close(() => { store.close(); ok(); }); }),
    broadcastVersion: (v) => { for (const s of streams) send(s, 'version', { version: v }); },
  };
}
