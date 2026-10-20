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

  /* ---------- helpers ---------- */
  const json = (res, status, body) => {
    const s = JSON.stringify(body);
    res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Content-Length': Buffer.byteLength(s) });
    res.end(s);
  };
  const readBody = (req) => new Promise((resolve, reject) => {
    let size = 0; const parts = [];
    req.on('data', (c) => { size += c.length; if (size > BODY_LIMIT) { reject(httpError(413, 'Too large')); req.destroy(); } else parts.push(c); });
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

    const u = await who(req, res);
    if (!u) return;

    if (p === '/api/me') return json(res, 200, { ok: true, user: access.shape(u, 'users', u), version, rev: store.rev() });

    if (p === '/api/snapshot' && req.method === 'GET') return json(res, 200, { ok: true, version, ...visibleSnapshot(u) });

    if (p === '/api/push' && req.method === 'POST') {
      const body = await readBody(req);
      const changes = Array.isArray(body.changes) ? body.changes : [];
      const { rev, results } = store.apply(changes, u.id, (ch, current) => access.canWrite(u, ch, current));
      broadcast(rev, results, body.client, u.id);
      return json(res, 200, { ok: true, rev, results: results.map((r) => ({ ...forUser(u, r), refused: !!r.refused })) });
    }

    // Live updates (Server-Sent Events). Sends anything missed since `since`, then changes as they happen.
    if (p === '/api/events' && req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
      res.write('retry: 3000\n\n');
      const s = { res, userId: u.id, user: u, client: url.searchParams.get('client') || null };
      streams.add(s);
      send(s, 'hello', { version, rev: store.rev() });
      const since = Number(url.searchParams.get('since'));
      if (Number.isFinite(since) && since > 0 && since < store.rev()) {
        const missed = store.since(since);
        if (missed.length) send(s, 'changes', { rev: store.rev(), client: null, changes: missed.map((r) => forUser(u, r)).filter((r) => !(r.hidden && r.kind === 'notifications')) });
      }
      const ping = setInterval(() => { try { res.write(': ping\n\n'); } catch { /* closed */ } }, 25000);
      req.on('close', () => { clearInterval(ping); streams.delete(s); });
      return;
    }

    if (p.startsWith('/api/host/') && req.method === 'POST') {
      const cmd = p.slice('/api/host/'.length);
      const fn = files.commands[cmd];
      if (!fn) return json(res, 404, { ok: false, error: 'Unknown command ' + cmd });
      const body = await readBody(req);
      if (['makeDir', 'trashMany', 'trashPath'].includes(cmd) && u.role === 'freelancer') {
        const paths = cmd === 'makeDir' ? [body.path] : (body.paths || [body.path]);
        if (paths.some((x) => String(x || '').startsWith('Clients/'))) return json(res, 403, { ok: false, error: 'Not allowed' });
      }
      if (cmd === 'writeChunk' && body.dest && !['admin', 'am'].includes(u.role)) return json(res, 403, { ok: false, error: 'Only Admins and Account Managers can upload client assets' });
      return json(res, 200, await fn(body, u));
    }

    if (p.startsWith('/api/zip/')) return files.serveZip(res, p.slice('/api/zip/'.length));

    // One-time move from the Mac app: an Admin uploads the whole data file
    if (p === '/api/import' && req.method === 'POST') {
      if (u.role !== 'admin') return json(res, 403, { ok: false, error: 'Only an Admin can import data' });
      const body = await readBody(req);
      if (!body || !body.data) return json(res, 400, { ok: false, error: 'No data' });
      store.backup(path.join(dataDir, 'backups', `before-import-${Date.now()}.sqlite`));
      const { rev, results } = store.importAll(body.data, u.id);
      broadcast(rev, results, null, u.id);
      return json(res, 200, { ok: true, rev, count: results.length });
    }

    if (p.startsWith('/__file/') && (req.method === 'GET' || req.method === 'HEAD')) return files.serve(req, res, p.slice('/__file/'.length));

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
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': html || /sw\.js$/.test(full) ? 'no-cache' : 'public, max-age=300', 'X-Content-Type-Options': 'nosniff' });
    if (req.method === 'HEAD') return res.end();
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
    server, store, files,
    listen: (port, host) => new Promise((ok) => server.listen(port, host, () => ok(server.address().port))),
    close: () => new Promise((ok) => { for (const s of streams) try { s.res.end(); } catch { /* ignore */ } server.close(() => { store.close(); ok(); }); }),
    broadcastVersion: (v) => { for (const s of streams) send(s, 'version', { version: v }); },
  };
}
