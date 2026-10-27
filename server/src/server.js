// E11 Console server: serves the app, keeps everyone's data in one place, pushes live changes
// to every open app, and stores files. No outside packages — only what ships with Node 22.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import { openStore } from './store.js';
import { createAuth } from './auth.js';
import { createAccess } from './access.js';
import { createFiles, mimeOf, httpError } from './files.js';
import { createCfSync } from './cfsync.js';
import { createWebPush, notifMessage } from './webpush.js';
import { createDigest } from './digest.js';
import { createOccasionReminders } from './occremind.js';
import { createBirthdays } from './birthdays.js';
import { createScheduled } from './scheduled.js';
import { createHolidaySync, DEFAULT_HOLIDAYS_URL } from './holidays.js';
import zlib from 'node:zlib';
import { sampleData } from './sample.js';
import { freshSample } from './sample-fresh.js';
import { createAppIcon } from './appicon.js';
import { createFinals } from './finals.js';
import { createPlans } from './plans.js';

const BODY_LIMIT = 12 * 1024 * 1024; // 2 MB upload pieces arrive as ~2.7 MB of base64

export function createServer(cfg) {
  const dataDir = cfg.dataDir;
  const store = cfg.store || openStore(cfg.dbFile || path.join(dataDir, 'db', 'e11.sqlite'));
  const auth = cfg.auth || createAuth({ team: cfg.cfTeam, aud: cfg.cfAud, dev: !!cfg.dev });
  const access = createAccess(store, { ownerEmail: cfg.adminEmail, plans: /-test\.|-dev$/.test(cfg.version || '0.0.0-dev') });   // (content plans: a trial on the test copy only)
  const files = createFiles(dataDir);
  const version = cfg.version || '0.0.0-dev';
  const webDir = cfg.webDir || null;
  const streams = new Set(); // open live-update connections
  const uploads = new Map(); // file path -> who is uploading it (pieces can only be added by them)
  const finals = createFinals({ store, files, access });
  const plans = createPlans({ store, files, access });
  const exportJobs = new Map();   // content plan exports in progress (id → { userId, state, export | error })
  const webPush = createWebPush({ store, fetchImpl: cfg.pushFetch || fetch, subject: cfg.pushSubject || 'mailto:admin@e11hq.com' });
  const digest = createDigest({ store, webPush, now: cfg.now || (() => Date.now()) });
  if (cfg.digest !== false) digest.start();
  // Inbox clean-up: read updates go after 60 days, any update after 180 days, so opening the app stays quick as
  // the months go by (each person's whole Inbox comes with every start). Runs a minute after start and twice a day.
  function pruneNotifications(now = Date.now()) {
    const READ = 60 * 86400000, ANY = 180 * 86400000;
    const old = store.list('notifications').filter((n) => { const at = Date.parse(n.at || 0) || 0; return at && (now - at > ANY || (n.read && now - at > READ)); });
    if (!old.length) return 0;
    const out = store.apply(old.map((n) => ({ kind: 'notifications', id: String(n.id), del: true })), 'inbox-cleanup');
    broadcast(out.rev, out.results, null, null);
    return old.length;
  }
  if (cfg.pruneInbox !== false) {
    const t1 = setTimeout(() => { try { pruneNotifications(); } catch (e) { console.error('Inbox clean-up failed:', e.message); } }, 60_000);
    const t2 = setInterval(() => { try { pruneNotifications(); } catch (e) { console.error('Inbox clean-up failed:', e.message); } }, 12 * 3600_000);
    if (t1.unref) t1.unref(); if (t2.unref) t2.unref();
  }
  // Once: Account Managers and Admins are taken off every task they're assigned to (only Production, Social,
  // Freelancers and the Creative Director are assigned now)
  if (!store.kv.get('unassign-managers-v1')) {
    try {
      const users = new Map(store.list('users').map((x) => [x.id, x]));
      const cd = (store.get('meta', 'main') || {}).cdUserId || null;
      const off = (id) => { const x = users.get(id); return !!x && id !== cd && (x.role === 'am' || x.role === 'admin'); };
      const ops = [];
      for (const t of store.list('tasks')) {
        const gone = (t.assignees || []).filter(off);
        if (!gone.length) continue;
        const next = { ...t, assignees: (t.assignees || []).filter((id) => !off(id)) };
        for (const k of ['prio', 'partsDone']) if (next[k]) { next[k] = { ...next[k] }; gone.forEach((id) => delete next[k][id]); }
        ops.push({ kind: 'tasks', id: t.id, data: next });
      }
      if (ops.length) store.apply(ops, 'unassign-managers');
      store.kv.set('unassign-managers-v1', JSON.stringify({ at: new Date().toISOString(), tasks: ops.length }));
    } catch (e) { console.error('Unassigning managers failed:', e.message); }
  }
  const occRemind = createOccasionReminders({ store, webDir, webPush, isAdm: (u) => access.isSuper(u), now: cfg.now || (() => Date.now()) });
  if (cfg.occRemind !== false && webDir) occRemind.start();
  // Birthdays: the rest of the staff are told in the morning (Inbox + phone)
  const birthdays = createBirthdays({ store, webPush, notifMessage, deliver: (out) => broadcast(out.rev, out.results, null, null), now: cfg.now || (() => Date.now()) });
  if (cfg.birthdays !== false) birthdays.start();
  // Scheduled comments: posted by the server at their time (or cancelled when the task is completed or deleted first)
  const scheduled = createScheduled({ store, access, webPush, notifMessage, deliver: (out) => broadcast(out.rev, out.results, null, null), now: cfg.now || (() => Date.now()) });
  if (cfg.scheduled !== false) scheduled.start();
  // Confirmed dates for Ramadan, the Eids… from a public UAE holiday calendar (off on a dev server unless a URL is given)
  const holidays = createHolidaySync({
    store, webDir: cfg.webDir, url: cfg.holidaysUrl || DEFAULT_HOLIDAYS_URL, fetchImpl: cfg.holidaysFetch || fetch, now: cfg.now || (() => Date.now()),
    onChange: (rev, results, changed) => {
      broadcast(rev, results, null, null);
      if (!changed.length) return;
      const f = (d) => new Date(d + 'T00:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' });
      const body = changed.map((c) => `${c.name}: ${f(c.date)} (was ${f(c.was)})`).join(' · ');
      const managers = store.list('users').filter((x) => x.active !== false && (access.isSuper(x) || x.role === 'am'));
      for (const m of managers) webPush.sendTo(m.id, { title: 'Occasion date confirmed', body, tag: 'occasion' }).catch(() => {});
      for (const st of streams) { const su = store.get('users', st.userId) || st.user; if (su && (access.isSuper(su) || su.role === 'am')) send(st, 'occasion', { changed }); }
    },
  });
  if (cfg.holidays !== false && (!cfg.dev || cfg.holidaysUrl)) holidays.start();
  const macDir = cfg.macDir || (webDir ? path.join(webDir, '..', 'mac') : null);
  const appIcon = createAppIcon({ store, defaultFile: macDir && path.join(macDir, 'AppIcon.png') });
  // The newest Mac app (native part) the installer hands out; older Mac apps are asked to update
  // (the Swift app when its build is here — mac/bin/E11Console.zip — otherwise the earlier script app)
  const macSwift = !!macDir && fs.existsSync(path.join(macDir, 'bin', 'E11Console.zip'));
  const macShell = (() => {
    try {
      if (macSwift) { const m = fs.readFileSync(path.join(macDir, 'swift', 'main.swift'), 'utf8').match(/let SHELL_VERSION = (\d+)/); if (m) return Number(m[1]); }
      const m = fs.readFileSync(path.join(macDir, 'main.js'), 'utf8').match(/var SHELL_VERSION = (\d+);/); return m ? Number(m[1]) : 1;
    } catch { return 1; }
  })();
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
    // Test site only: the owner may use the app as any team member (see viewAsTarget)
    req.realUser = u;
    const as = viewAsTarget(u);
    if (as) { req.viewingAs = as; return as; }
    // Live site only: the owner stepped in with Owner view on this device (Admin rights and Finance Admin on top, nothing stored)
    const ov = ownerViewOf(req, u);
    if (ov) { req.ownerView = ov.mode; return { ...u, admin: true, fin: 'admin', _ov: ov.mode }; }
    return u;
  }
  /* "Owner view" — LIVE SITE ONLY (never on the test copy; keep it in future updates). The owner (ADMIN_EMAIL) may use
     the app day to day with another role (e.g. Production) and quietly step in with Admin rights from the bottom of
     My profile. Nothing is stored or announced: their role stays as it is for everyone; the rights live in a cookie
     on that one device, for that browser session only, and lapse after 15 minutes without use. It starts "look only"
     (the server refuses every change) until they choose "Allow changes". The app also switches it off on every
     reload. Changes made with changes allowed show under their name like any other. */
  // ---- Video hardware check (cached 10 minutes) ----
  let videoHw = null;
  const sh = (cmd, args, timeout) => new Promise((resolve) => execFile(cmd, args, { timeout }, (err, stdout, stderr) => resolve({ ok: !err, out: String(stdout || '') + String(stderr || '') })));
  async function videoHardware(fresh) {
    if (videoHw && !fresh && Date.now() - videoHw.at < 600000) return videoHw.result;
    const dir = cfg.driDir || '/dev/dri';
    let devices = [];
    try { devices = fs.readdirSync(dir).filter((n) => /^renderD\d+$/.test(n)); } catch { devices = []; }
    let result;
    if (!devices.length) result = { state: 'missing', title: 'Not available', detail: 'The NAS isn’t passing its video hardware to the app (no /dev/dri). Videos are converted with the processor instead.' };
    else {
      const dev = `${dir}/${devices[0]}`;
      const info = await sh('vainfo', ['--display', 'drm', '--device', dev], 15000);
      const driver = (info.out.match(/Driver version:\s*(.+)/) || [])[1] || '';
      const h264 = /VAProfileH264\w*\s*:\s*VAEntrypointEncSlice/.test(info.out);
      const hevc = /VAProfileHEVC\w*\s*:\s*VAEntrypointEncSlice/.test(info.out);
      const t0 = Date.now();
      const enc = await sh('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-init_hw_device', `vaapi=va:${dev}`, '-filter_hw_device', 'va', '-f', 'lavfi', '-i', 'testsrc=size=1280x720:rate=25', '-t', '2',
        '-vf', 'format=nv12,hwupload', '-c:v', 'h264_vaapi', '-f', 'null', '-'], 30000);
      const secs = ((Date.now() - t0) / 1000).toFixed(1);
      result = enc.ok
        ? { state: 'ready', title: 'Intel Quick Sync is working', detail: `${driver || 'Intel driver loaded'} · H.264${hevc ? ' and HEVC' : ''} encoding · test clip (2 s of 720p) converted in ${secs} s`, device: dev }
        : { state: 'error', title: info.ok ? 'Found, but the test conversion failed' : 'Found, but the driver didn’t load', detail: (driver ? driver + ' · ' : '') + (h264 ? 'H.264 listed · ' : '') + (enc.out || info.out).trim().split('\n').slice(-2).join(' ').slice(0, 300), device: dev };
    }
    videoHw = { at: Date.now(), result: { ...result, checkedAt: new Date().toISOString() } };
    return videoHw.result;
  }
  const errorCounts = new Map();                // person -> times of their recent error reports (a cap per hour)
  const OV_IDLE = 15 * 60000;
  const ownerViews = new Map();                 // cookie token -> { userId, mode: 'look' | 'edit', until }
  const ownerViewOk = (u) => !isTestSite && !!cfg.adminEmail && !!u && isOwner(u);
  const cookieOf = (req, name) => { const m = String(req.headers.cookie || '').match(new RegExp('(?:^|;\\s*)' + name + '=([^;]+)')); return m ? decodeURIComponent(m[1]) : null; };
  function ownerViewOf(req, u) {
    if (!ownerViewOk(u)) return null;
    const tok = cookieOf(req, 'e11_ov');
    const v = tok && ownerViews.get(tok);
    if (!v) return null;
    if (v.userId !== u.id || v.until < Date.now()) { ownerViews.delete(tok); return null; }
    v.until = Date.now() + OV_IDLE;
    req.ownerViewToken = tok;
    return v;
  }
  const ovCookie = (req, tok) => `e11_ov=${tok ? encodeURIComponent(tok) : ''}; Path=/; HttpOnly; SameSite=Lax${/https/.test(String(req.headers['x-forwarded-proto'] || '')) || req.socket.encrypted ? '; Secure' : ''}${tok ? '' : '; Max-Age=0'}`;
  // what a stream sends: the person as stored, with Owner view on top while it lasts
  function streamUser(s) {
    const u = store.get('users', s.userId) || s.user;
    const v = s.ovToken && ownerViews.get(s.ovToken);
    return v && v.userId === u.id && v.until >= Date.now() && ownerViewOk(u) ? { ...u, admin: true, fin: 'admin', _ov: v.mode } : u;
  }
  /* "View as" — a testing aid on the TEST copy only (never on the live site): the owner (ADMIN_EMAIL) picks a team
     member and, until they switch back, the server treats every request of theirs as that person — what they see,
     what they may change, their role's rules. The choice is kept on the server (kv "view-as"), so it holds on every
     device and after reloads. Their phone subscriptions are left alone while viewing as someone. */
  const isTestSite = /-test\.|-dev$/.test(version);
  function viewAsTarget(real) {
    if (!isTestSite || !real || !isOwner(real)) return null;
    let v = null; try { v = JSON.parse(store.kv.get('view-as') || 'null'); } catch { v = null; }
    if (!v || !v.userId || v.userId === real.id) return null;
    const t = store.get('users', String(v.userId));
    return t && t.active !== false ? t : null;
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
      const u = streamUser(s);
      // What someone can see changed (a freelancer's clients, which Client Assets a client uses, or a client switched
      // on / off): reload their data
      if (changed.some((r) => (r.kind === 'users' && r.id === u.id) || r.kind === 'projects' || r.kind === 'meta')) {
        const was = s.lastAccess, now = accessKey(u);
        s.lastAccess = now;
        if (was !== undefined && was !== now) { send(s, 'resync', { rev }); continue; }
      }
      const list = changed.map((r) => forUser(u, r)).filter((r) => !(r.hidden && r.kind === 'notifications'));
      list.push(...ownViewDelta(s, u, changed));
      if (!list.length) continue;
      send(s, 'changes', { rev, client: fromClient || null, by: byUser || null, changes: list });
    }
  }
  // A client renamed by an Admin: its Client Assets folder takes the new name too (also while the client is inactive,
  // when the app can't see the folder), unless it was named differently already or another folder has the new name
  const keyOf = (n) => String(n || '').toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/&/g, 'and').replace(/[^a-z0-9\u0600-\u06ff]+/g, '');
  function renameLinkedAssets(results, before) {
    const ops = [];
    for (const r of results) {
      if (r.kind !== 'projects' || r.refused || r.unchanged || r.deleted) continue;
      const pr = store.get('projects', String(r.id)), old = before.get(String(r.id));
      if (!pr || !pr.clientId || !old || old === pr.name) continue;
      const c = store.get('clients', pr.clientId);
      if (!c || c.name === pr.name || keyOf(c.name) !== keyOf(old)) continue;
      if (store.list('clients').some((x) => x.id !== c.id && keyOf(x.name) === keyOf(pr.name))) continue;
      ops.push({ kind: 'clients', id: c.id, data: { ...c, name: pr.name } });
    }
    if (!ops.length) return;
    const out = store.apply(ops, 'rename');
    broadcast(out.rev, out.results, null, null);
  }
  // Production and Freelancers see only what they're part of, so one change can show or hide other things too (a
  // subtask assigned to them brings its parent task and client; taken off, they go): send those as well
  const VIEW_KINDS = ['tasks', 'projects', 'clients'];
  const viewIds = (u) => { const v = access.ownView(u); return { tasks: v.tasks, projects: v.projects, clients: new Set(store.list('clients').filter((c) => access.canSee(u, 'clients', c)).map((c) => c.id)) }; };
  function ownViewDelta(s, u, changed) {
    if (!access.ownOnly(u)) { s.lastView = null; return []; }
    if (!changed.some((r) => VIEW_KINDS.includes(r.kind))) return [];
    const was = s.lastView, now = viewIds(u);
    s.lastView = now;
    if (!was) return [];
    const done = new Set(changed.map((r) => r.kind + ':' + r.id));
    const out = [], rev = store.rev();
    for (const kind of VIEW_KINDS) {
      for (const id of now[kind]) if (!was[kind].has(id) && !done.has(kind + ':' + id)) { const d = store.get(kind, id); if (d && access.canSee(u, kind, d)) out.push({ kind, id, data: access.shape(u, kind, d), rev }); }
      for (const id of was[kind]) if (!now[kind].has(id) && !done.has(kind + ':' + id)) out.push({ kind, id, deleted: true, rev, hidden: true });
    }
    return out;
  }
  const accessKey = (u) => JSON.stringify([u.role === 'freelancer' ? u.projectIds || [] : null, u.role, !!u.admin, access.finLevel(u) || null, access.ownOnly(u), store.list('projects').map((p) => [p.id, p.clientId || null, !!p.inactive])]);
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
    if (p === '/install' || p === '/install/legacy' || p === '/install/main.js' || p === '/install/AppIcon.png' || p === '/install/E11Console.zip') {
      const file = p === '/install' || p === '/install/legacy' ? 'install.sh' : p === '/install/E11Console.zip' ? 'bin/E11Console.zip' : p.slice('/install/'.length);
      const full = macDir && path.join(macDir, file);
      if (!full || !fs.existsSync(full)) return json(res, 404, { ok: false, error: 'Installer not available' });
      if (file === 'install.sh') {
        const host = String(req.headers['x-forwarded-host'] || req.headers.host || 'console.e11hq.com').replace(/[^\w.:-]/g, '');
        const scheme = /^(localhost|127\.)/.test(host) ? 'http' : 'https';
        const body = fs.readFileSync(full, 'utf8').replace('__SERVER__', `${scheme}://${host}`).replace('__LEGACY__', p === '/install/legacy' ? '1' : '0');
        res.writeHead(200, { 'Content-Type': 'text/x-shellscript; charset=utf-8', 'Cache-Control': 'no-cache' });
        return res.end(body);
      }
      res.writeHead(200, { 'Content-Type': mimeOf(full), 'Cache-Control': 'no-cache' });
      return fs.createReadStream(full).pipe(res);
    }

    const u = await who(req, res);
    if (!u) return;

    // Owner view, look only: nothing changes (reading, files, previews and this device's notifications still work)
    if (req.ownerView === 'look' && req.method !== 'GET' && req.method !== 'HEAD') {
      const okPath = ['/api/owner-view', '/api/peek', '/api/push/subscribe', '/api/push/unsubscribe', '/api/push/status', '/api/client-error'].includes(p)
        || (p.startsWith('/api/host/') && ['docPreview', 'pdfPages', 'thumb', 'exportFiles'].includes(p.slice('/api/host/'.length)));
      if (p === '/api/push') {
        const body = await readBody(req);
        const results = (Array.isArray(body.changes) ? body.changes : []).filter(Boolean).map((ch) => {
          const cur = store.get(ch.kind, String(ch.id));
          return cur ? { kind: ch.kind, id: ch.id, data: access.shape(u, ch.kind, cur), rev: store.rev(), refused: true } : { kind: ch.kind, id: ch.id, deleted: true, rev: store.rev(), refused: true };
        });
        return json(res, 200, { ok: true, rev: store.rev(), results, lookOnly: true });
      }
      if (!okPath) return json(res, 403, { ok: false, error: 'Owner view is look only — choose Allow changes first', lookOnly: true });
    }

    // Errors from people's apps (startup crashes etc.): kept (last 100) so their cause can be found; a few per person per hour
    if (p === '/api/client-error' && req.method === 'POST') {
      const body = await readBody(req, 64 * 1024).catch(() => ({}));
      const now = Date.now(), mine = (errorCounts.get(u.id) || []).filter((t) => now - t < 3600000);
      if (mine.length >= 20) return json(res, 200, { ok: true, dropped: true });
      mine.push(now); errorCounts.set(u.id, mine);
      const clip = (v, n) => String(v == null ? '' : v).slice(0, n);
      const entry = { at: new Date(now).toISOString(), user: u.email, where: clip(body.where, 20), message: clip(body.message, 500), stack: clip(body.stack, 2000),
        version: clip(body.version, 40), ua: clip(body.ua, 300), standalone: !!body.standalone, width: Number(body.width) || 0, page: clip(body.page, 200) };
      let list = []; try { list = JSON.parse(store.kv.get('client-errors') || '[]'); } catch { list = []; }
      list.push(entry); store.kv.set('client-errors', JSON.stringify(list.slice(-100)));
      console.error(`[app error] ${entry.user} ${entry.where} ${entry.version} ${entry.standalone ? '(Home Screen app) ' : ''}${entry.message}`);
      return json(res, 200, { ok: true });
    }
    // ...the owner reads them
    if (p === '/api/client-errors' && req.method === 'GET') {
      if (!isOwner(req.realUser || u)) return json(res, 403, { ok: false, error: 'Only the owner can see this' });
      let list = []; try { list = JSON.parse(store.kv.get('client-errors') || '[]'); } catch { list = []; }
      return json(res, 200, { ok: true, errors: list.reverse() });
    }

    // Owner view (live site, owner only): { mode: 'look' | 'edit' | 'off' }
    if (p === '/api/owner-view' && req.method === 'POST') {
      if (isTestSite) return json(res, 404, { ok: false, error: 'Not available on the test site' });
      if (!ownerViewOk(req.realUser || u)) return json(res, 403, { ok: false, error: 'Only the owner can do this' });
      const body = await readBody(req);
      const mode = ['look', 'edit'].includes(body && body.mode) ? body.mode : 'off';
      const me0 = req.realUser || u;
      let tok = cookieOf(req, 'e11_ov');
      if (tok) { const v = ownerViews.get(tok); if (!v || v.userId !== me0.id) tok = null; }
      if (mode === 'off') { if (tok) ownerViews.delete(tok); tok = null; }
      else {
        if (!tok) tok = crypto.randomBytes(24).toString('base64url');
        ownerViews.set(tok, { userId: me0.id, mode, until: Date.now() + OV_IDLE });
      }
      const out = JSON.stringify({ ok: true, mode: tok ? mode : null, idleMinutes: OV_IDLE / 60000 });
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Set-Cookie': ovCookie(req, tok), 'Content-Length': Buffer.byteLength(out) });
      return res.end(out);
    }

    if (p === '/api/me') return json(res, 200, { ok: true, user: access.shape(u, 'users', u), owner: isOwner(u), appIcon: appIcon.info(), macShell, version, rev: store.rev(),
      ownerView: req.ownerView || null, canOwnerView: ownerViewOk(req.realUser || u),
      // (Admins: whose account only its owner may change, so the Team page shows it locked)
      ownerId: access.isAdm(u) && cfg.adminEmail ? (access.userByEmail(cfg.adminEmail) || {}).id || null : null,
      viewAs: isTestSite && isOwner(req.realUser) ? { real: { id: req.realUser.id, name: req.realUser.name || req.realUser.email }, as: req.viewingAs ? { id: u.id, name: u.name || u.email, role: u.role } : null } : null });

    // Test site, owner only: choose whom to view the app as (userId), or null to be yourself again
    if (p === '/api/view-as' && req.method === 'POST') {
      if (!isTestSite) return json(res, 404, { ok: false, error: 'Not available on the live site' });
      if (!isOwner(req.realUser)) return json(res, 403, { ok: false, error: 'Only the owner can do this' });
      const body = await readBody(req);
      const id = body && body.userId ? String(body.userId) : null;
      if (id && (!store.get('users', id) || store.get('users', id).active === false)) return json(res, 400, { ok: false, error: 'No such team member' });
      if (!id || id === req.realUser.id) store.kv.set('view-as', 'null'); else store.kv.set('view-as', JSON.stringify({ userId: id, at: new Date().toISOString() }));
      return json(res, 200, { ok: true });
    }

    // Mac app Dock icon: everyone reads it; only the owner changes it (every open Mac app swaps it live)
    if (p === '/api/app-icon' && req.method === 'GET') {
      const buf = appIcon.png();
      if (!buf) return json(res, 404, { ok: false, error: 'No icon' });
      res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'no-cache', 'Content-Length': buf.length });
      return res.end(buf);
    }
    if (p === '/api/app-icon/info') return json(res, 200, { ok: true, ...appIcon.info(), canEdit: isOwner(u) });
    if ((p === '/api/app-icon' || p === '/api/app-icon/reset' || p === '/api/app-icon/auto') && req.method === 'POST') {
      if (!isOwner(u)) return json(res, 403, { ok: false, error: 'Only the owner can change the app icon' });
      let info;
      try { info = p.endsWith('/reset') ? appIcon.reset(u.id) : p.endsWith('/auto') ? appIcon.setAuto(u.id) : (await readBody(req).then((b) => appIcon.set(b.png, u.id, b.preset))); } catch (e) { return json(res, e.status || 400, { ok: false, error: e.message }); }
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
    // The NAS's video hardware (Intel Quick Sync), for the owner's App updates page: is it passed in, does the driver
    // load, and can it actually encode a short test clip
    if (p === '/api/system/video') {
      if (!isOwner(req.realUser || u)) return json(res, 403, { ok: false, error: 'Only the owner can see this' });
      return json(res, 200, { ok: true, video: await videoHardware(url.searchParams.get('fresh') === '1') });
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
    // Morning summary: today's, for this person's open app (shown once per device); a test send to yourself
    if (p === '/api/digest') return json(res, 200, { ok: true, ...digest.forUser(u) });
    if (p === '/api/occ-reminders') return json(res, 200, { ok: true, ...occRemind.forUser(u) });
    // Occasion dates: when the holiday calendar was last read (Admins and Account Managers can check now)
    if (p === '/api/holidays') {
      if (!(access.isAdm(u) || u.role === 'am')) return json(res, 403, { ok: false, error: 'Admins and Account Managers only' });
      const s = req.method === 'POST' ? await holidays.check() : holidays.status();
      return json(res, 200, { ok: true, ...s });
    }
    if (p === '/api/digest/test' && req.method === 'POST') {
      const m = digest.preview(u);
      const r = await webPush.sendTo(u.id, { ...m, tag: 'digest-test' }, { ttl: 600 }).catch(() => ({ sent: 0 }));
      return json(res, 200, { ok: true, ...m, phones: r.sent || 0 });
    }
    if (p === '/api/push/key') return json(res, 200, { ok: true, key: webPush.publicKey() });
    if (p === '/api/push/subscribe' && req.method === 'POST') {
      const body = await readBody(req);
      if (req.viewingAs) return json(res, 200, { ok: true, devices: 0, viewingAs: true });   // (don't touch that person's phones)
      const n = webPush.subscribe(u.id, body.subscription, req.headers['user-agent']);
      return json(res, 200, { ok: true, devices: n });
    }
    if (p === '/api/push/unsubscribe' && req.method === 'POST') {
      const body = await readBody(req);
      if (req.viewingAs) return json(res, 200, { ok: true, viewingAs: true });
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

    // Test copy only, owner only: wipe everything (except the owner's account) and start again with fresh sample data
    // set up the way the app works now. A backup of the database is kept first; files go to the trash folder.
    if (p === '/api/sample/reset' && req.method === 'POST') {
      if (!/-test\.|-dev$/.test(version)) return json(res, 403, { ok: false, error: 'Only on the test copy' });
      if (!isOwner(req.realUser || u)) return json(res, 403, { ok: false, error: 'Only the owner can do this' });
      const owner = req.realUser || u;
      store.backup(path.join(dataDir, 'backups', `before-sample-reset-${Date.now()}.sqlite`));
      // 1. every record except the owner's account
      const dels = [];
      for (const k of ['projects', 'tasks', 'clients', 'notifications', 'statuses', 'trash', 'finance', 'claims', 'plans']) store.list(k).forEach((x) => dels.push({ kind: k, id: String(x.id), del: true }));
      store.list('users').forEach((x) => { if (x.id !== owner.id) dels.push({ kind: 'users', id: String(x.id), del: true }); });
      if (dels.length) store.apply(dels, 'sample-reset');
      store.apply([{ kind: 'meta', id: 'main', data: { createdAt: new Date().toISOString() } }], 'sample-reset');
      for (const k of ['view-as', 'digest-sent', 'occ-remind-sent']) store.kv.set(k, k === 'view-as' ? 'null' : '{}');
      // 2. files (task attachments, Client Assets, Finance, claims, previews) moved to the trash folder; profile photos stay
      const filesRoot = path.join(dataDir, 'files');
      const bin = path.join(dataDir, 'trash', new Date().toISOString().slice(0, 10), `sample-reset-${Date.now()}`);
      fs.mkdirSync(bin, { recursive: true });
      for (const d of ['Clients', 'Finance', 'Claims', '.thumbs']) { const src = path.join(filesRoot, d); if (fs.existsSync(src)) fs.renameSync(src, path.join(bin, d)); }
      // (the owner stays, so their saved signature stays too)
      const sigWas = path.join(bin, 'Claims', owner.id, 'signature');
      if (fs.existsSync(sigWas)) { fs.mkdirSync(path.join(filesRoot, 'Claims', owner.id), { recursive: true }); fs.renameSync(sigWas, path.join(filesRoot, 'Claims', owner.id, 'signature')); }
      const att = path.join(filesRoot, 'attachments');
      if (fs.existsSync(att)) for (const d of fs.readdirSync(att)) if (d !== '_avatars') fs.renameSync(path.join(att, d), path.join(bin, 'attachments-' + d));
      // 3. the fresh sample
      const data = freshSample(store, owner.id, filesRoot);
      const { rev } = store.importAll(data, owner.id);
      for (const st of streams) send(st, 'resync', { rev });    // every open app reloads its data
      return json(res, 200, { ok: true, rev, tasks: data.tasks.length, people: data.users.length, clients: data.projects.length });
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

    if (p === '/api/snapshot' && req.method === 'GET') return sendText(req, res, 200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }, Buffer.from(JSON.stringify({ ok: true, version, ...visibleSnapshot(u) })));

    if (p === '/api/push' && req.method === 'POST') {
      const body = await readBody(req);
      const changes = Array.isArray(body.changes) ? body.changes : [];
      const fresh = new Set(changes.filter((ch) => ch && ch.kind === 'notifications' && !ch.del && !store.get('notifications', String(ch.id))).map((ch) => String(ch.id)));
      const restoring = new Set(changes.filter((ch) => ch && !ch.del && ch.kind !== 'trash').map((ch) => `${ch.kind}:${ch.id}`));
      const namesBefore = new Map(changes.filter((ch) => ch && ch.kind === 'projects' && !ch.del).map((ch) => [String(ch.id), (store.get('projects', String(ch.id)) || {}).name]));
      const tasksBefore = new Map(changes.filter((ch) => ch && ch.kind === 'tasks').map((ch) => [String(ch.id), store.get('tasks', String(ch.id))]));
      const { rev, results } = store.apply(changes, u.id, (ch, current) => access.canWrite(u, ch, current, { restoring }));
      broadcast(rev, results, body.client, u.id);
      renameLinkedAssets(results, namesBefore);
      // a CD-reviewed task just completed: its final files go into Client Assets › Files
      let filed = null;
      try { filed = finals.afterPush(results, tasksBefore, u.id); } catch (e) { console.error('final files:', e.message); }
      if (filed) {
        broadcast(filed.rev, filed.results, null, null);
        filed.results.filter((r) => r.kind === 'notifications' && !r.refused && r.data && r.data.to)
          .filter((r) => { const to = store.get('users', String(r.data.to)); return !!to && access.canSee(to, 'notifications', r.data); })
          .forEach((r) => webPush.sendTo(r.data.to, notifMessage(store, r.data)).catch(() => {}));
      }
      // content plans: a plan whose tasks are all complete is client approved; an approved plan's PowerPoint is filed
      let planned = [];
      try { planned = plans.afterPush(results.concat(filed ? filed.results : []), u.id, (ops) => store.apply(ops, 'plans')); } catch (e) { console.error('content plans:', e.message); }
      for (const out of planned) {
        broadcast(out.rev, out.results, null, null);
        out.results.filter((r) => r.kind === 'notifications' && !r.refused && r.data && r.data.to)
          .filter((r) => { const to = store.get('users', String(r.data.to)); return !!to && access.canSee(to, 'notifications', r.data); })
          .forEach((r) => webPush.sendTo(r.data.to, notifMessage(store, r.data)).catch(() => {}));
      }
      // new notifications also go to the person's phone
      results.filter((r) => r.kind === 'notifications' && fresh.has(String(r.id)) && !r.refused && !r.deleted && r.data && r.data.to && r.data.to !== u.id)
        .filter((r) => { const to = store.get('users', String(r.data.to)); return !!to && access.canSee(to, 'notifications', r.data); })   // (only what they'd see in their Inbox)
        .forEach((r) => webPush.sendTo(r.data.to, notifMessage(store, r.data)).catch(() => {}));
      if (results.some((r) => r.kind === 'users' && !r.refused && !r.unchanged)) cfSync.schedule();
      // a task completed or deleted cancels its scheduled comments straight away (and the author hears now)
      if (results.some((r) => (r.kind === 'tasks' || r.kind === 'scheduled') && !r.refused && !r.unchanged)) setTimeout(() => scheduled.tick().catch(() => {}), 50);
      return json(res, 200, { ok: true, rev, results: results.map((r) => ({ ...forUser(u, r), refused: !!r.refused })) });
    }

    // A task link opened by someone who sees only their own tasks: they may read it and comment (view only)
    if (p === '/api/peek' && req.method === 'POST') {
      const body = await readBody(req);
      if (!access.ownOnly(u)) return json(res, 200, { ok: true });
      const t = access.addPeek(u, String((body && body.taskId) || ''));
      if (!t) return json(res, 404, { ok: false, error: 'That task is not available' });
      for (const s of streams) if (s.userId === u.id) s.lastView = viewIds(u);
      return json(res, 200, { ok: true });
    }

    // Live updates (Server-Sent Events). Sends anything missed since `since`, then changes as they happen.
    if (p === '/api/events' && req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
      res.write('retry: 3000\n\n');
      const s = { res, userId: u.id, user: u, client: url.searchParams.get('client') || null, ovToken: req.ownerViewToken || null };
      s.lastAccess = accessKey(u);
      s.lastView = access.ownOnly(u) ? viewIds(u) : null;
      streams.add(s);
      send(s, 'hello', { version, rev: store.rev(), appIcon: appIcon.info() });
      const since = Number(url.searchParams.get('since'));
      if (Number.isFinite(since) && since > 0 && since < store.rev()) {
        const missed = store.since(since);
        // (for someone who sees only their own tasks, what they can see may have moved while away: reload instead)
        if (access.ownOnly(u) && missed.some((r) => VIEW_KINDS.includes(r.kind))) send(s, 'resync', { rev: store.rev() });
        else if (missed.length) send(s, 'changes', { rev: store.rev(), client: null, changes: missed.map((r) => forUser(u, r)).filter((r) => !(r.hidden && r.kind === 'notifications')) });
      }
      const ping = setInterval(() => { try { res.write('event: ping\ndata: {}\n\n'); } catch { /* closed */ } }, 25000);
      req.on('close', () => { clearInterval(ping); streams.delete(s); });
      return;
    }

    // Content plans: the client export (PowerPoint + PDF) and reading the client's PowerPoint back
    if (p === '/api/plan-export' && req.method === 'POST') {
      const body = await readBody(req);
      const pl = store.get('plans', String((body && body.planId) || ''));
      if (!pl || !access.canSee(u, 'plans', pl) || !access.planMaker(u, pl)) return json(res, 403, { ok: false, error: 'Not allowed' });
      // (it runs in the background: a deck with videos and its PDF can take longer than a request may last)
      const job = 'job-' + crypto.randomBytes(8).toString('hex');
      exportJobs.set(job, { userId: u.id, state: 'running', at: Date.now() });
      plans.exportDeck(u, body || {}).then((r) => {
        if (r.error) { exportJobs.set(job, { userId: u.id, state: 'error', error: r.error, at: Date.now() }); return; }
        const out = store.apply(r.ops, u.id);
        broadcast(out.rev, out.results, null, u.id);
        exportJobs.set(job, { userId: u.id, state: 'done', export: r.exp, at: Date.now() });
      }).catch((e) => { console.error('plan export:', e.message); exportJobs.set(job, { userId: u.id, state: 'error', error: 'The export failed — please try again', at: Date.now() }); });
      for (const [k, v] of exportJobs) if (Date.now() - v.at > 3600_000) exportJobs.delete(k);
      return json(res, 200, { ok: true, job });
    }
    if (p === '/api/plan-export' && req.method === 'GET') {
      const j = exportJobs.get(String(url.searchParams.get('job') || ''));
      if (!j || j.userId !== u.id) return json(res, 404, { ok: false, error: 'Export not found' });
      if (j.state === 'error') return json(res, 200, { ok: true, state: 'error', error: j.error });
      return json(res, 200, { ok: true, state: j.state, export: j.export || null });
    }
    if (p === '/api/plan-return' && req.method === 'POST') {
      const body = await readBody(req);
      const r = plans.readReturn(u, body || {});
      if (r.error) return json(res, r.status || 400, { ok: false, error: r.error });
      return json(res, 200, { ok: true, ...r.result });
    }
    // Content plans: when tasks are made from a skeleton, its posts' reference files are linked into each new task
    if (p === '/api/plan-refs' && req.method === 'POST') {
      const body = await readBody(req);
      const pl = store.get('plans', String((body && body.planId) || ''));
      if (!pl || !access.canSee(u, 'plans', pl) || !access.planMaker(u, pl) || !/^[\w-]{3,80}$/.test(String(body.taskId || ''))) return json(res, 403, { ok: false, error: 'Not allowed' });
      const tk = store.get('tasks', String(body.taskId));   // (a task still being made, or one of this plan's)
      if (tk && tk.planId !== pl.id) return json(res, 403, { ok: false, error: 'Not allowed' });
      const out = [];
      for (const r of (body.files || []).slice(0, 40)) {
        const fp = String((r && r.path) || '');
        if (!fp.startsWith(`attachments/${pl.id}/`)) continue;
        try { out.push({ ...files.linkToTask(fp, body.taskId, r.name), w: r.w, h: r.h }); } catch { /* a missing file is skipped */ }
      }
      return json(res, 200, { ok: true, files: out });
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
        else if (body.dest && (access.isFinance(u) || u.role === 'freelancer' || !access.canReadFile(u, String(body.dest) + '/x'))) return deny('You can’t add files to this client');
        if (!body.dest && access.isFinance(u) && body.taskId !== '_uploads') return deny();
        if (!body.dest && access.ownOnly(u) && body.taskId !== '_uploads') { const t = store.get('tasks', String(body.taskId || '')); if (!t || !access.canSee(u, 'tasks', t)) return deny(); }
        // later pieces may only be added to a file this person started uploading
        if (body.path) { const up = uploads.get(body.path); if (!up || up.userId !== u.id) return deny('Upload not found — please try again'); }
        const out = await files.commands.writeChunk(body, u);
        uploads.set(out.path, { userId: u.id, at: Date.now() });
        if (uploads.size > 500) for (const [k, v] of uploads) if (Date.now() - v.at > 6 * 3600_000) uploads.delete(k);
        return json(res, 200, out);
      }
      if (cmd === 'makeDir' && !manager && !(u.role !== 'freelancer' && String(body.path || '').startsWith('Clients/') && access.canReadFile(u, String(body.path) + '/x'))) return deny();
      if (access.isFinance(u) && !['writeChunk', 'thumb', 'processImage', 'docPreview', 'pdfPages', 'exportFiles', 'claimPdf', 'expenseReport'].includes(cmd)) return deny();
      if (cmd === 'expenseReport' && !access.finLevel(u)) return deny('Only people with Finance access can download the expenses report');
      if (cmd === 'expenseReport' && (body.files || []).some((x) => { const fp = String((x && x.path) || ''); return !(fp.startsWith('Finance/') || fp.startsWith('Claims/')) || !access.canReadFile(u, fp); })) return deny();
      if (cmd === 'claimPdf' && !(String(body.userId || '') === u.id || access.finLevel(u))) return deny();
      if (cmd === 'trashMany' || cmd === 'trashPath') {
        const paths = body.paths || [body.path];
        // Client Assets: Admins anything; others only what's no longer in any client (they removed it, which the data rules allow)
        if (u.role === 'freelancer' && paths.some((x) => String(x || '').startsWith('Clients/'))) return deny();
        if (!access.isAdm(u)) {
          const live = new Set(store.list('clients').flatMap((c) => [c.dir, c.logo, ...(c.folders || []).flatMap((f) => [f.dir, ...(f.files || []).map((a) => a.path)])]).filter(Boolean));
          if (paths.some((x) => { const v = String(x || ''); return v.startsWith('Clients/') && [...live].some((l) => l === v || l.startsWith(v.replace(/\/$/, '') + '/')); })) return deny();
        }
        if (paths.some((x) => !access.canReadFile(u, String(x || '')))) return deny();
      }
      if (cmd === 'claimPdf' && (body.receipts || []).some((x) => !access.canReadFile(u, String(x || '')) || !String(x || '').startsWith('Claims/'))) return deny();
      if (['thumb', 'processImage', 'docPreview', 'pdfPages'].includes(cmd) && !access.canReadFile(u, String(body.path || '')) && !(cmd === 'processImage' && uploads.get(body.path) && uploads.get(body.path).userId === u.id)) return deny();
      // a client logo: Admins and AMs; anyone else only from their own upload (the first image in a client's Logos folder)
      if (cmd === 'processImage' && body.kind === 'logo' && !manager && !(u.role !== 'freelancer' && !access.isFinance(u) && uploads.get(body.path) && uploads.get(body.path).userId === u.id)) return deny();
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
    // app.js?v=1.5.4 — each update has new names, so a versioned file never changes: devices keep it until the next
    // update (a year at most) instead of fetching it again every day. The page itself and sw.js are always checked.
    const versioned = /[?&]v=/.test(req.url || '');
    const cache = html || /sw\.js$/.test(full) ? 'no-cache' : versioned ? 'public, max-age=31536000, immutable' : 'public, max-age=86400';
    const textual = /^(text\/|application\/(javascript|json|manifest\+json)|image\/svg)/.test(type);
    if (!textual) {
      res.writeHead(200, { 'Content-Type': type, 'Cache-Control': cache, 'X-Content-Type-Options': 'nosniff' });
      if (req.method === 'HEAD') return res.end();
      return fs.createReadStream(full).pipe(res);
    }
    // text files go out compressed (Brotli or gzip, made once per file and version and kept in memory)
    const body = html
      // every local script and stylesheet (a new file can't be missed), so an update reaches everyone at once
      ? Buffer.from(fs.readFileSync(full, 'utf8').replace(/(src|href)="([\w-]+\.(?:js|css))"/g, `$1="$2?v=${encodeURIComponent(version)}"`))
      : fs.readFileSync(full);
    return sendText(req, res, 200, { 'Content-Type': type, 'Cache-Control': cache, 'X-Content-Type-Options': 'nosniff' }, body, `${full}|${fs.statSync(full).mtimeMs}|${version}`);
  }
  // Compressed text: Brotli when the browser takes it, else gzip, else as is; small things go as they are
  const packed = new Map();
  function sendText(req, res, status, headers, body, key) {
    const accept = String(req.headers['accept-encoding'] || '');
    const enc = body.length < 1400 ? null : /\bbr\b/.test(accept) ? 'br' : /\bgzip\b/.test(accept) ? 'gzip' : null;
    if (!enc) { res.writeHead(status, { ...headers, 'Content-Length': body.length, Vary: 'Accept-Encoding' }); return res.end(req.method === 'HEAD' ? undefined : body); }
    const k = key ? `${enc}|${key}` : null;
    let out = k && packed.get(k);
    if (!out) {
      out = enc === 'br' ? zlib.brotliCompressSync(body, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: key ? 9 : 4 } }) : zlib.gzipSync(body, { level: key ? 9 : 6 });
      if (k) { packed.set(k, out); if (packed.size > 200) packed.delete(packed.keys().next().value); }
    }
    res.writeHead(status, { ...headers, 'Content-Encoding': enc, 'Content-Length': out.length, Vary: 'Accept-Encoding' });
    return res.end(req.method === 'HEAD' ? undefined : out);
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
    digest, holidays, occRemind, birthdays, scheduled, pruneNotifications,
    close: () => new Promise((ok) => { digest.stop(); holidays.stop(); occRemind.stop(); birthdays.stop(); scheduled.stop(); for (const s of streams) try { s.res.end(); } catch { /* ignore */ } server.close(() => { store.close(); ok(); }); }),
    broadcastVersion: (v) => { for (const s of streams) send(s, 'version', { version: v }); },
  };
}
