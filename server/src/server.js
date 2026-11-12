// E11 Console server: serves the app, keeps everyone's data in one place, pushes live changes
// to every open app, and stores files. No outside packages — only what ships with Node 22.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import { openStore } from './store.js';
import { createAuth } from './auth.js';
import { createSignin } from './signin.js';
import { signinPage } from './signin-page.js';
// The message an admin sends with a sign-in code (Haris 2026-11-11, project doc own-sign-in-plan.md): new user or forgot password
function signinMessage({ first, email, code, until, by, newUser, site }) {
  return newUser
    ? `Hi ${first},\n\nWelcome to E11 Console! Here's how to sign in for the first time:\n\n1. Open E11 Console: the iPhone app, the Mac app, or ${site}\n2. Your email (your username): ${email}\n3. Your sign-in code: ${code}\n4. Set your own password; the app opens once it's set.\n\nThe code works once and only until ${until}. If it runs out, just ask me for a new one.\n\nOn your iPhone or Mac you'll stay signed in, and Face ID / Touch ID gets you back in.\n\nPlease don't share this code with anyone.\n\n${by}`
    : `Hi ${first},\n\nHere's a new sign-in code for E11 Console:\n\nEmail: ${email}\nCode: ${code}\n\nSign in with it and set a new password. Your old password stops working once you do. The code works once and only until ${until}.\n\nPlease don't share this code with anyone.\n\n${by}`;
}
import { createAccess } from './access.js';
import { createFiles, mimeOf, httpError, IMAGES } from './files.js';
import { createCfSync } from './cfsync.js';
import { createWebPush, notifMessage } from './webpush.js';
import { createDigest } from './digest.js';
import { createWidget } from './widget.js';
import { createHomeView } from './homeview.js';
import { createOccasionReminders } from './occremind.js';
import { createBirthdays } from './birthdays.js';
import { createScheduled } from './scheduled.js';
import { createDaily } from './amdaily.js';
import { createLinks } from './links.js';
import { createViewCopies } from './viewcopy.js';
import { createOffice } from './office.js';
import { createApns } from './apns.js';
import { createTalk } from './talk.js';
import { createHolidaySync, DEFAULT_HOLIDAYS_URL } from './holidays.js';
import { createAppStart } from './appstart.js';
import { claimSheetFor } from './claimsheet.js';
import zlib from 'node:zlib';
import { sampleData } from './sample.js';
import { freshSample } from './sample-fresh.js';
import { createAppIcon } from './appicon.js';
import { createFinals } from './finals.js';
import { createFileLinks } from './flinks.js';
import { createPlans } from './plans.js';
import { createReview, resetDue, REVIEW_USER_ID } from './review.js';
import { demoData, DEMO_REVIEWER } from './demo.js';

const BODY_LIMIT = 12 * 1024 * 1024; // 2 MB upload pieces arrive as ~2.7 MB of base64

export function createServer(cfg) {
  const dataDir = cfg.dataDir;
  const store = cfg.store || openStore(cfg.dbFile || path.join(dataDir, 'db', 'e11.sqlite'));
  const auth = cfg.auth || createAuth({ team: cfg.cfTeam, aud: cfg.cfAud, dev: !!cfg.dev });
  // E11 Talk's own Cloudflare sign-in (the "E11 Talk" Access application: talk.e11hq.com and talk-test.e11hq.com — Haris
  // 2026-11-06). Its audience tag is public (it's in every sign-in token), so it lives here. Only /api/talk/ on those hosts.
  const TALK_AUD = 'f254001f22f0f8099b13ef7e8d68f3fd465d498cbdbf3e21d316cbab644f2e7b';
  const talkAuth = cfg.talkAuth || createAuth({ team: cfg.cfTeam, aud: TALK_AUD, dev: !!cfg.dev });
  const talkHost = (req) => /^talk(-test)?\./.test(String(req.headers.host || ''));
  const access = createAccess(store, { ownerEmail: cfg.adminEmail, plans: true, now: cfg.now });   // (content plans: on everywhere since 2026-10-28)
  const files = createFiles(dataDir);
  // Our own sign-in (signin.js, Haris 2026-11-11): only where SIGNIN_ISSUER is set — the test copy first
  const signin = cfg.signinIssuer ? createSignin({
    db: store.db, now: cfg.now, ownerEmail: cfg.adminEmail, ownerCodeHash: cfg.ownerCodeHash, issuer: cfg.signinIssuer.replace(/\/$/, ''),
    clients: cfg.signinClients || [], keyFile: path.join(dataDir, 'signin-key.pem'),
    findUser: (e) => access.userByEmail(e), onCodeUsed: (x) => codeUsedNotice(x),
  }) : null;
  // The App Review copy (review.js): only when REVIEW_PASSWORD is set — never on the live or test copy
  const review = cfg.reviewPassword ? createReview({ store, password: cfg.reviewPassword, email: cfg.reviewEmail || undefined }) : null;
  const version = cfg.version || '0.0.0-dev';
  const webDir = cfg.webDir || null;
  const streams = new Set(); // open live-update connections
  const uploads = new Map(); // file path -> who is uploading it (pieces can only be added by them)
  const finals = createFinals({ store, files, access });
  const plans = createPlans({ store, files, access });
  const exportJobs = new Map();   // content plan exports in progress (id → { userId, state, export | error })
  const webPush = createWebPush({ store, fetchImpl: cfg.pushFetch || fetch, subject: cfg.pushSubject || 'mailto:admin@e11hq.com' });
  // the native iPhone app's notifications (apns.js) go out with every phone/browser notification
  const apns = createApns({ store, keyFile: cfg.apnsKeyFile, keyId: cfg.apnsKeyId, teamId: cfg.apnsTeamId, topic: cfg.apnsTopic || 'ae.e11.console.ios', hosts: cfg.apnsHosts, connectOpts: cfg.apnsConnectOpts });
  // E11 Talk (talk.js): its own database, its own phones for notifications (the same Apple key, its own app)
  const talkApns = createApns({ store, keyFile: cfg.apnsKeyFile, keyId: cfg.apnsKeyId, teamId: cfg.apnsTeamId, topic: cfg.talkTopic || 'ae.e11.talk.ios', kvPrefix: 'talk-apns', hosts: cfg.apnsHosts, connectOpts: cfg.apnsConnectOpts });
  let talk = null;
  const talkNow = () => talk || (talk = createTalk({ dataDir, store, access, apns: talkApns, dbFile: cfg.talkDbFile, now: cfg.now || (() => Date.now()), links: () => fileLinks }));
  { const webSend = webPush.sendTo;
    webPush.sendTo = async (userId, msg, opts) => {
      // (the iPhone app: expense claims only as rules.js onPhone says — everyone's own claim approved / paid / added, the
      //  team's submitted ones to an Office Admin with finance access — and its badge counts the same; Haris 2026-11-10)
      const pu = store.get('users', String(userId));
      const claim = !homeView.onPhone({ kind: (msg && msg.kind) || '' }, pu);
      let phoneMsg = msg && Number.isInteger(msg.badge) ? { ...msg, badge: store.list('notifications').filter((x) => x.to === userId && !x.read && homeView.onPhone(x, pu)).length } : msg;
      // (held on the iPhone: Apple's expanded notification with the app's preview of it — a comment's with Reply, its thread
      //  passed along so the reply lands in it; anything about a task with Mark as Read and Open Task — Haris 2026-11-10)
      if (phoneMsg && phoneMsg.taskId && phoneMsg.nid && !phoneMsg.category) {
        const t = store.get('tasks', String(phoneMsg.taskId));
        const c = phoneMsg.commentId && t ? (t.comments || []).find((x) => x.id === phoneMsg.commentId) : null;
        phoneMsg = { ...phoneMsg, category: c ? 'e11.comment' : 'e11.task', ...(c ? { threadId: c.parentId || c.id } : {}) };
      }
      const [a, b] = await Promise.all([webSend(userId, msg, opts), claim ? Promise.resolve({ sent: 0 }) : apns.sendTo(userId, phoneMsg, opts).catch((e) => { console.error('APNs:', e.message); return { sent: 0 }; })]);
      return { sent: (a.sent || 0) + (b.sent || 0), removed: (a.removed || 0) + (b.removed || 0), apns: b.results || [], apnsWhy: b.why || '' };
    }; }
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
  // (the occasion reminders go only to those who make Content plans' posts: Social Managers and a client's Social
  //  Executives — Haris 2026-11-10)
  const planPoster = (u) => access.isSocialMgr(u) || store.list('projects').some((p) => !p.archived && !p.deleted && !p.inactive && access.planEditor(u, p.id));
  const occRemind = createOccasionReminders({ store, webDir, webPush, poster: planPoster, now: cfg.now || (() => Date.now()) });
  if (cfg.occRemind !== false && webDir) occRemind.start();
  const widget = createWidget({ store, access, occRemind: webDir ? occRemind : null, now: cfg.now || (() => Date.now()) });
  const homeView = createHomeView({ webDir, now: cfg.now || (() => Date.now()) });
  const appStart = createAppStart({ webDir: webDir || path.resolve(path.dirname(new URL(import.meta.url).pathname), '../../web') });
  const homeOps = new Map();   // (the app's Home actions already done: their answers, for a retry)
  // Part B step 3: the iPhone app's actions on its own pages, straight to the server (no website in between) — each
  // group on its own switch: kv 'app-act-<group>' = 'off' sends the app back to the page for it
  const ACT_GROUP = { rvApprove: 'reviews', rvAmend: 'reviews', clApprove: 'claims', clPaid: 'claims', clAdd: 'claims', clPerson: 'claims', clMark: 'claims', exAdd: 'expenses', exEnd: 'expenses', exInv: 'expenses', exDel: 'expenses', pfSet: 'profile' };
  let appActs = null;
  async function loadAppActs() {
    if (appActs) return appActs;
    const all = {};
    const now = cfg.now || (() => Date.now());
    // (Client Assets — step 5 — also gets the server's own access rules and files: the person's visible data, the logo)
    for (const [file, fn] of [['./appact-reviews.js', 'createReviewActs'], ['./appact-money.js', 'createMoneyActs'], ['./appact-other.js', 'createOtherActs'], ['./appact-me.js', 'createMeActs'], ['./appact-assets.js', 'createAssetActs'], ['./appact-tasks.js', 'createTaskActs']]) {
      try { const m = await import(file); Object.assign(all, m[fn]({ store, now, webDir, access, files })); } catch (e) { if (e.code !== 'ERR_MODULE_NOT_FOUND') console.error('app actions', file, e.message); }
    }
    return (appActs = all);
  }
  const actGroup = (ev) => ACT_GROUP[ev] || (/^pl/.test(ev) ? 'plans' : /^tr/.test(ev) ? 'trash' : /^ca/.test(ev) ? 'assets' : /^tk/.test(ev) ? 'tasks' : 'team');
  // Birthdays: the rest of the staff are told in the morning (Inbox + phone)
  const birthdays = createBirthdays({ store, webPush, notifMessage, deliver: (out) => broadcast(out.rev, out.results, null, null), now: cfg.now || (() => Date.now()) });
  if (cfg.birthdays !== false) birthdays.start();
  // (links to clients deleted before the server unlinked them itself — once, at start)
  setTimeout(() => { try { unlinkGoneClients(null); } catch (e) { console.error('unlink clients:', e.message); } }, 1500);
  // Scheduled comments: posted by the server at their time (or cancelled when the task is completed or deleted first)
  const scheduled = createScheduled({ store, access, webPush, notifMessage, deliver: (out) => broadcast(out.rev, out.results, null, null), now: cfg.now || (() => Date.now()) });
  if (cfg.scheduled !== false) scheduled.start();
  // Confirmed dates for Ramadan, the Eids… from a public UAE holiday calendar (off on a dev server unless a URL is given)
  // Light viewing copies of videos (viewcopy.js): every video in tasks, comments, Client Assets and plans, in the
  // background; checked a minute after start, every 3 minutes, and a few seconds after changes arrive
  const views = createViewCopies({ files, dri: cfg.driDir || '/dev/dri', minSize: cfg.viewMinSize });
  // File links (flinks.js): one short public link per file, files.e11hq.com/f/<token> (the test copy: its own)
  const testCopy = /-test\./.test(version);
  const filesUrl = cfg.filesUrl || (cfg.dev ? '' : testCopy ? 'https://files-test.e11hq.com' : 'https://files.e11hq.com');
  const filesHost = filesUrl ? new URL(filesUrl).host : '';
  const brandSvg = (() => { try { return fs.readFileSync(path.join(webDir || '', 'brand', 'e11-mark.svg'), 'utf8').replace(/<\?xml[^>]*>/, '').replace(/<title>.*?<\/title>/, '').replace(/fill="#000000"/g, 'fill="currentColor"').replace(/ width="\d+" height="\d+"/, ' role="img" aria-label="E11"'); } catch { return '<b style="font-size:30px">E11</b>'; } })();
  const fileLinks = createFileLinks({ store, files, views, base: filesUrl, teamId: cfg.appleTeamId || cfg.apnsTeamId || '', brandSvg });
  function scanVideos() {
    try {
      const add = (a) => { if (a && a.path) views.want(a.path); };
      for (const t of store.list('tasks')) { (t.attachments || []).forEach(add); (t.comments || []).forEach((c) => (c.attachments || []).forEach(add)); }
      for (const c of store.list('clients')) (c.folders || []).forEach((f) => (f.files || []).forEach(add));
      for (const pl of store.list('plans')) JSON.stringify(pl).replace(/"path":"([^"]+)"/g, (_, x) => { views.want(x); return ''; });
    } catch (e) { console.error('video scan failed', e.message); }
  }
  let scanSoon = null;
  const scanLater = () => { clearTimeout(scanSoon); scanSoon = setTimeout(scanVideos, 5000); if (scanSoon.unref) scanSoon.unref(); };
  const scanTimers = [];
  if (cfg.views !== false && !cfg.dev) { const a = setTimeout(scanVideos, 60_000), b = setInterval(scanVideos, 3 * 60_000); [a, b].forEach((x) => x.unref && x.unref()); scanTimers.push(a, b); }
  // Fast office use (office.js): copies from the NAS shared folder, and uploads/downloads over the office network
  const office = createOffice({ store, files, cfg: { shareDir: cfg.shareDir, shareName: cfg.shareName, officeIp: cfg.officeIp, localUrl: cfg.localUrl }, ipOf: (req) => netInfo(req).ip });
  const links = createLinks({ store, dataDir, fetcher: cfg.linkFetch });
  const daily = createDaily({ store, access, webDir, webPush, notifMessage, deliver: (out) => broadcast(out.rev, out.results, null, null), now: cfg.now || (() => Date.now()) });
  if (cfg.daily !== false && (!cfg.dev || cfg.daily)) daily.start();   // (not on a developer's copy unless asked)
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
      // the version of the Mac app actually in the build (mac/bin/SHELL_VERSION, from the zip): older Mac apps are asked to
      // update to that — never to a newer one the build doesn't have yet (that would ask again after every update)
      if (macSwift) { try { const n = Number(fs.readFileSync(path.join(macDir, 'bin', 'SHELL_VERSION'), 'utf8').trim()); if (n > 0) return n; } catch { /* not written: main.swift */ } }
      if (macSwift) { const m = fs.readFileSync(path.join(macDir, 'swift', 'main.swift'), 'utf8').match(/let SHELL_VERSION = (\d+)/); if (m) return Number(m[1]); }
      const m = fs.readFileSync(path.join(macDir, 'main.js'), 'utf8').match(/var SHELL_VERSION = (\d+);/); return m ? Number(m[1]) : 1;
    } catch { return 1; }
  })();
  // The owner (ADMIN_EMAIL) controls things that change every Mac, like the Dock icon. No owner set: any Admin.
  const isOwner = (u) => (review ? false : cfg.adminEmail ? String(u.email || '').toLowerCase() === cfg.adminEmail.toLowerCase() : access.isAdm(u));
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
  async function who(req, res, known) {
    let id = known;
    try { if (!id) id = review ? review.identify(req) : await auth.identify(req); } catch (e) {
      if (review && wantsHtml(req)) { res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }); res.end(review.page()); }
      else if (wantsHtml(req)) page(res, 401, 'Please sign in', esc(e.message));
      else json(res, 401, { ok: false, error: e.message });
      return null;
    }
    // (a password set with a sign-in code ends every sign-in made before it — silently: signin.js)
    if (signin && id.iat && id.iat * 1000 < signin.revokedBefore(id.email)) {
      if (wantsHtml(req)) page(res, 401, 'Please sign in again', 'Your password was changed. Sign in again with the new one.');
      else json(res, 401, { ok: false, error: 'Please sign in again' });
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
  // Who may add a file where (uploads, office-network uploads, copies from the shared folder): a reason, or null
  function uploadDenied(u, body) {
    if (body.dest && String(body.dest).startsWith('Finance/')) { if (access.finLevel(u) !== 'admin') return 'Only a Finance Admin can add invoices'; }
    else if (body.dest && String(body.dest).startsWith('Claims/')) { if (String(body.dest).split('/')[1] !== u.id) return 'You can only add files to your own claims'; }
    else if (body.dest && (access.isFinance(u) || u.role === 'freelancer' || !access.canReadFile(u, String(body.dest) + '/x'))) return 'You can’t add files to this client';
    if (!body.dest && access.isFinance(u) && body.taskId !== '_uploads') return 'Not allowed';
    if (!body.dest && access.ownOnly(u) && body.taskId !== '_uploads') { const t = store.get('tasks', String(body.taskId || '')); if (!t || !access.canSee(u, 'tasks', t)) return 'Not allowed'; }
    return null;
  }
  function netInfo(req) {
    const h = req.headers;
    const ip = String(h['cf-connecting-ip'] || String(h['x-forwarded-for'] || '').split(',')[0] || req.socket.remoteAddress || '').trim().replace(/^::ffff:/, '');
    const ray = String(h['cf-ray'] || '');
    const ua = String(h['user-agent'] || '');
    const app = /iPhone|iPad|Android/.test(ua) ? (/iPad/.test(ua) ? 'iPad' : /Android/.test(ua) ? 'Android phone' : 'iPhone')
      : /Macintosh/.test(ua) && !/Safari\//.test(ua) ? 'Mac app' : /Edg\//.test(ua) ? 'Edge' : /Chrome\//.test(ua) ? 'Chrome' : /Firefox\//.test(ua) ? 'Firefox' : /Safari\//.test(ua) ? 'Safari' : 'Other';
    return { ip, via: ray ? 'cloudflare' : 'direct', colo: ray.includes('-') ? ray.split('-').pop() : null, app };
  }
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
  // files nothing on the server uses any more (deleting is for good): checked against every record as text — plain, as
  // JSON and HTML-escaped — so a path another task, comment, client, claim, plan… still holds is kept
  function unusedPaths(paths) {
    const hay = ['users', 'projects', 'tasks', 'clients', 'meta', 'finance', 'claims', 'plans', 'scheduled'].map((k) => JSON.stringify(store.list(k))).join('\n');
    const forms = (x) => [x, JSON.stringify(x).slice(1, -1), x.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/</g, '&lt;').replace(/>/g, '&gt;')];
    return (paths || []).map((x) => String(x || '')).filter((x) => x && !forms(x).some((f) => hay.includes(f)));
  }
  const forUser = (u, r) => {
    if (r.deleted) return { kind: r.kind, id: r.id, deleted: true, rev: r.rev };
    if (!access.canSee(u, r.kind, r.data)) return { kind: r.kind, id: r.id, deleted: true, rev: r.rev, hidden: true };
    return { kind: r.kind, id: r.id, data: access.shape(u, r.kind, r.data), rev: r.rev };
  };

  // Tell every open app about changes (each person only receives what they're allowed to see)
  // Files sent for review: their previews made the moment they're sent (Haris 2026-11-11 07:08: "You can do these 3") —
  // the small and large pictures of a photo, a video's frame, a PDF's or a document's first page — so they're already
  // there when the CD opens the request (and her phone fetches them before she does). The same pictures the app asks for
  // (appme-money.js picOf: ?w=160 and ?w=1000, /api/fthumb), made once each, one after another, never in the way of a save.
  const warmedReviews = new Set();
  let warmChain = Promise.resolve();
  function warmReviews(tasks) {
    for (const t of tasks) {
      if (!t || !t.needsCD) continue;
      for (const r of t.reviews || []) {
        if (r.state !== 'pending' || warmedReviews.has(r.id)) continue;
        warmedReviews.add(r.id);
        for (const id of r.files || []) {
          const a = (t.attachments || []).find((x) => x.id === id);
          if (!a || !a.path) continue;
          const e = String(a.name || a.path).split('.').pop().toLowerCase();
          if (!IMAGES.includes(e) && a.thumb) continue;   // (its picture made already)
          warmChain = warmChain.then(async () => {
            try {
              if (IMAGES.includes(e)) { await files.makeSized(a.path, 160); await files.makeSized(a.path, 1000); }
              else if (/^(pdf|mp4|mov|m4v|webm|avi|mkv|doc|docx|ppt|pptx|xls|xlsx)$/.test(e)) await files.commands.thumb({ id: a.id, path: a.path });
            } catch (err) { console.error('Review preview:', err.message); }
          });
        }
      }
    }
  }
  if (cfg.warmReviews !== false) setTimeout(() => warmReviews(store.list('tasks')), 30_000).unref?.();
  function broadcast(rev, results, fromClient, byUser) {
    const changed = results.filter((r) => !r.refused && !r.unchanged);
    if (!changed.length) return;
    if (cfg.warmReviews !== false) warmReviews(changed.filter((r) => r.kind === 'tasks' && !r.del).map((r) => store.get('tasks', String(r.id))));
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
  // A Client Assets client deleted: the Clients list entries linked to it are unlinked by the server itself — part of a
  // delete that was allowed, whoever did it (an Office Admin may delete a client but not change those entries: the
  // link was left pointing at nothing, an inactive entry showed "Hidden" — Haris 2026-11-05). Also once at start, for
  // links left by deletes before this (none: nothing to do).
  function unlinkGoneClients(results) {
    const gone = new Set((results || []).filter((r) => r.kind === 'clients' && r.deleted && !r.refused).map((r) => String(r.id)));
    if (results && !gone.size) return;
    const ops = store.list('projects').filter((p) => p.clientId && (results ? gone.has(String(p.clientId)) : !store.get('clients', String(p.clientId))))
      .map((p) => { const d = { ...p }; delete d.clientId; return { kind: 'projects', id: String(p.id), data: d }; });
    if (!ops.length) return;
    const out = store.apply(ops, 'unlink');
    broadcast(out.rev, out.results, null, null);
  }
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

  // Save a person's changes and do what follows (live updates, final files, content plans, phone notifications…):
  // what /api/push does for the website, and the iPhone app's Home actions (/api/home/act) too
  // An email is either on the Team or an E11 Talk client contact, never both (Haris 2026-11-12: a client added to the Team
  // for testing with the same email became staff in E11 Talk — his client groups gone, nothing reaching him). Client
  // Contacts already refuses a Team email; this is the other way: a person added, brought back or given a new email.
  const TALK_CLASH = 'That email is a client contact in E11 Talk — use another email, or remove the contact first';
  function clashesTalkContact(ch, current) {
    if (!ch || ch.kind !== 'users' || ch.del || !ch.data || ch.data.active === false || !ch.data.email) return false;
    const email = String(ch.data.email).toLowerCase();
    const isNew = !current || current.active === false || String(current.email || '').toLowerCase() !== email;
    if (!isNew) return false;
    try { return !!talkNow().contactByEmail(email); } catch { return false; }
  }
  function pushAs(u, changes, client) {
      const fresh = new Set(changes.filter((ch) => ch && ch.kind === 'notifications' && !ch.del && !store.get('notifications', String(ch.id))).map((ch) => String(ch.id)));
      const restoring = new Set(changes.filter((ch) => ch && !ch.del && ch.kind !== 'trash').map((ch) => `${ch.kind}:${ch.id}`));
      const namesBefore = new Map(changes.filter((ch) => ch && ch.kind === 'projects' && !ch.del).map((ch) => [String(ch.id), (store.get('projects', String(ch.id)) || {}).name]));
      const tasksBefore = new Map(changes.filter((ch) => ch && ch.kind === 'tasks').map((ch) => [String(ch.id), store.get('tasks', String(ch.id))]));
      const { rev, results } = store.apply(changes, u.id, (ch, current) => !clashesTalkContact(ch, current) && access.canWrite(u, ch, current, { restoring }));
      broadcast(rev, results, client, u.id);
      renameLinkedAssets(results, namesBefore);
      unlinkGoneClients(results);
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
      if (cfg.views !== false && results.some((r) => ['tasks', 'clients', 'plans'].includes(r.kind) && !r.refused && !r.unchanged)) scanLater();
    return { rev, results };
  }

  // ---------- E11 Talk ----------
  // who's asking: someone on the team (as every other address), or a client contact — who exists in E11 Talk only, so
  // every E11 Console page and file (who() above) still refuses them
  async function talkWho(req, res) {
    let id;
    try { id = review ? review.identify(req) : talkHost(req) ? await talkAuth.identify(req) : await auth.identify(req); } catch (e) { json(res, 401, { ok: false, error: e.message }); return null; }
    // (E11 Talk is always the account signed in on the phone — never View as on the test site, never Owner view on live:
    //  Haris 2026-11-11; View as had turned Talk into that person — their chats shown, the phone's notifications moved)
    if (review || access.userByEmail(id.email)) { const w = await who(req, res, id); return w ? (req.realUser || w) : null; }
    const k = talkNow().contactByEmail(id.email);
    if (k) return k;
    json(res, 403, { ok: false, error: 'No E11 Talk account for ' + id.email });
    return null;
  }
  async function talkRoute(req, res, p, url, u) {
    const t = talkNow();
    const out = (r) => json(res, r.status || (r.ok === false ? 400 : 200), r);
    try {
      // ---- a linked Mac (E11 Console's Mac app, as its signed-in person): its own messages to pick up ----
      const macId = String(req.headers['x-talk-mac'] || '');
      let dev = u;
      if (macId) {
        dev = t.macFor(u, macId);
        if (!dev) return json(res, 410, { ok: false, unlinked: true, error: 'This Mac isn’t linked any more' });
        if (p === '/api/talk/link/leave' && req.method === 'POST') { t.unlinkMac(macId, 'signed out'); return out({ ok: true }); }
      }
      if (p.startsWith('/api/talk/link/')) {
        if (String(u.id).startsWith('k-')) return json(res, 403, { ok: false, error: 'Not for client contacts' });
        if (p === '/api/talk/link/code' && req.method === 'POST') { const b = await readBody(req, 16 * 1024); return out(t.linkCode(u, b.name)); }
        if (p === '/api/talk/link/status' && req.method === 'GET') return out(t.linkStatus(u, url.searchParams.get('code')));
        if (p === '/api/talk/link/has' && req.method === 'POST') { const b = await readBody(req, 1024 * 1024); return out(t.hasFiles(u, b.ids)); }
        if (p === '/api/talk/link/file' && req.method === 'POST') {
          const bytes = await readRaw(req, 8 * 1024 * 1024 + 1024);
          const q = url.searchParams;
          return out(t.resend(u, q.get('id') || '', q.get('name') || '', q.get('offset') || '0', bytes, q.get('last') === '1'));
        }
        if (p === '/api/talk/link/history' && req.method === 'POST') { const b = await readBody(req, 64 * 1024 * 1024); return out(t.history(u, b.mac, b.groups, b.files)); }
      }
      if (p === '/api/talk/state' && req.method === 'GET') return out(t.state(u));
      if (p === '/api/talk/act' && req.method === 'POST') return out(t.act(u, await readBody(req, 256 * 1024)));
      // (test site only, the owner: sample groups and messages — talk.js sample)
      if (p === '/api/talk/sample' && req.method === 'POST') { if (!testCopy || !isOwner(req.realUser || u)) return json(res, 403, { ok: false, error: 'Only the owner, on the test site' }); return out(t.sample(req.realUser || u)); }
      if (p === '/api/talk/sync' && req.method === 'GET') return out(t.sync(dev, url.searchParams.get('after'), url.searchParams.get('limit')));
      if (p === '/api/talk/ack' && req.method === 'POST') { const b = await readBody(req, 16 * 1024); return out(t.ack(dev, b.upto)); }
      if (p === '/api/talk/stream' && req.method === 'GET') {
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
        res.write('retry: 3000\n\n');
        const stop = t.listen(dev.id, res);
        const ping = setInterval(() => { try { res.write(': ping\n\n'); } catch { /* closed */ } }, 25000);
        req.on('close', () => { clearInterval(ping); stop(); });
        return;
      }
      // a file piece (raw bytes, up to 8 MB): ?id= (none for the first) &name= &offset= &last=1
      if (p === '/api/talk/upload' && req.method === 'POST') {
        const bytes = await readRaw(req, 8 * 1024 * 1024 + 1024);
        const q = url.searchParams;
        return out(t.upload(u, q.get('id') || '', q.get('name') || '', q.get('offset') || '0', bytes, q.get('last') === '1'));
      }
      if (p.startsWith('/api/talk/file/') && (req.method === 'GET' || req.method === 'HEAD')) {
        const f = t.fileFor(dev, p.slice('/api/talk/file/'.length));
        if (!f) return json(res, 404, { ok: false, error: 'That file has gone' });
        const full = t.filePath(f), size = fs.statSync(full).size;
        const m = /^bytes=(\d*)-(\d*)$/.exec(String(req.headers.range || ''));
        const type = mimeOf(f.name);
        if (m && (m[1] || m[2])) {
          const start = m[1] ? Number(m[1]) : Math.max(0, size - Number(m[2])), end = m[1] && m[2] ? Math.min(size - 1, Number(m[2])) : size - 1;
          if (start >= size || start > end) { res.writeHead(416, { 'Content-Range': `bytes */${size}` }); return res.end(); }
          res.writeHead(206, { 'Content-Type': type, 'Content-Length': end - start + 1, 'Content-Range': `bytes ${start}-${end}/${size}`, 'Accept-Ranges': 'bytes', 'Cache-Control': 'private, max-age=86400' });
          return req.method === 'HEAD' ? res.end() : fs.createReadStream(full, { start, end }).pipe(res);
        }
        res.writeHead(200, { 'Content-Type': type, 'Content-Length': size, 'Accept-Ranges': 'bytes', 'Cache-Control': 'private, max-age=86400' });
        return req.method === 'HEAD' ? res.end() : fs.createReadStream(full).pipe(res);
      }
      if (p === '/api/talk/push' && req.method === 'POST') {
        const b = await readBody(req, 16 * 1024);
        if (b.off) { talkApns.unregister(b.token); return out({ ok: true }); }
        return out(talkApns.register(u.id, b.token, b.env, { ack: b.ack === true }) ? { ok: true, push: talkApns.enabled() } : { ok: false, error: 'Bad token' });
      }
      if (p === '/api/talk/push/ack' && req.method === 'POST') { const b = await readBody(req, 16 * 1024); return out(await talkApns.ack(u.id, b.token, b.pid)); }
      return json(res, 404, { ok: false, error: 'Not found' });
    } catch (e) {
      console.error('talk:', e.message);
      return json(res, e.status || 500, { ok: false, error: e.status ? e.message : 'Something went wrong' });
    }
  }

  /* ---------- routes ---------- */
  // ---------- our own sign-in (signin.js) ----------
  let markSvg = null;
  const mark = () => {
    if (markSvg === null) { try { markSvg = '<span>' + fs.readFileSync(path.join(webDir, 'brand', 'e11-mark.svg'), 'utf8').replace(/<title>.*?<\/title>/, '').replace(/fill="#000000"/g, 'fill="currentColor"') + '</span>'; } catch { markSvg = '<span style="font-size:40px;font-weight:800">E11</span>'; } }
    return markSvg;
  };
  // (Cloudflare's sign-in request, checked each time: our one client, and its own callback address)
  const signinReq = (o) => {
    const r = { client_id: String(o.client_id || ''), redirect_uri: String(o.redirect_uri || ''), state: String(o.state || ''), nonce: String(o.nonce || '') };
    return signin.redirectOk(signin.client(r.client_id), r.redirect_uri) ? r : null;
  };
  const finish = (res, email, r) => {
    const code = signin.authCode(email, { clientId: r.client_id, redirectUri: r.redirect_uri, nonce: r.nonce });
    const to = new URL(r.redirect_uri); to.searchParams.set('code', code); if (r.state) to.searchParams.set('state', r.state);
    return json(res, 200, { ok: true, redirect: to.toString() });
  };
  async function signinRoute(req, res, p, url) {
    const noStore = { 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' };
    if (p === '/.well-known/openid-configuration') return json(res, 200, signin.discovery());
    if (p === '/oidc/jwks') return json(res, 200, signin.jwks());
    if (p === '/oidc/authorize' && req.method === 'GET') {
      const r = signinReq(Object.fromEntries(url.searchParams));
      if (!r || url.searchParams.get('response_type') !== 'code') return page(res, 400, 'Sign-in link not valid', 'Open E11 Console again to sign in.');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', ...noStore, 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'" });
      return res.end(signinPage({ mark: mark(), req: r }));
    }
    if (p === '/oidc/token' && req.method === 'POST') {
      const raw = await readRaw(req, 64 * 1024).catch(() => Buffer.alloc(0));
      const f = Object.fromEntries(new URLSearchParams(raw.toString('utf8')));
      let id = f.client_id, secret = f.client_secret;
      const basic = String(req.headers.authorization || '').match(/^Basic (.+)$/i);
      if (basic) { const [a, b] = Buffer.from(basic[1], 'base64').toString('utf8').split(':'); id = decodeURIComponent(a || ''); secret = decodeURIComponent(b || ''); }
      if (f.grant_type !== 'authorization_code') return json(res, 400, { error: 'unsupported_grant_type' });
      const out = signin.exchange({ code: f.code, clientId: id, clientSecret: secret, redirectUri: f.redirect_uri });
      return json(res, out.error ? 400 : 200, out);
    }
    if (p === '/oidc/userinfo') {
      const m = String(req.headers.authorization || '').match(/^Bearer (.+)$/i);
      const u = m ? signin.userinfo(m[1]) : null;
      return u ? json(res, 200, u) : json(res, 401, { error: 'invalid_token' });
    }
    if (p.startsWith('/oidc/api/') && req.method === 'POST') {
      const body = await readBody(req, 16 * 1024).catch(() => ({}));
      const r = signinReq(body.req || {});
      if (!r) return json(res, 400, { ok: false, error: 'Open E11 Console again to sign in.' });
      const what = p.slice('/oidc/api/'.length);
      if (what === 'start') return json(res, 200, signin.start(body.email));
      if (what === 'password') { const x = signin.signInPassword(body.email, body.password); return x.ok ? finish(res, x.email, r) : json(res, 200, x); }
      if (what === 'code') return json(res, 200, signin.useCode(body.email, body.code));
      if (what === 'owner') return json(res, 200, signin.useOwnerCode(body.email, body.code));
      if (what === 'setpw') { const x = signin.setPassword(body.ticket, body.password); return x.ok ? finish(res, x.email, r) : json(res, 200, x); }
      // (the app, after Face ID / Touch ID: its device key instead of the password)
      if (what === 'device') { const x = signin.useDevice(body.key); return x.ok ? finish(res, x.email, r) : json(res, 200, x); }
    }
    return json(res, 404, { ok: false, error: 'Not found' });
  }
  // (a password set with an admin's code: every other Super Admin and Office Admin told — Inbox and a push; not the admin
  //  who made it, not the person. The owner's codes tell no one — signin.js never calls this for them)
  function codeUsedNotice({ email, madeBy }) {
    const person = access.userByEmail(email), maker = access.userByEmail(madeBy);
    if (!person) return;
    const first = String(person.name || person.email).split(' ')[0];
    // (the Inbox puts who did it in front, as every notification: the words after it, and what came of it as the snippet)
    const text = `made a sign-in code for ${person.name || person.email}`, snippet = `${first}’s password was changed`;
    const at = new Date().toISOString();
    const to = store.list('users').filter((x) => access.isAdm(x) && x.active !== false && !x.removed && x.id !== person.id && (!maker || x.id !== maker.id));
    const notes = to.map((x) => ({ id: 'n-' + crypto.randomBytes(6).toString('hex'), to: x.id, from: maker ? maker.id : null, taskId: null, kind: 'signin', text, snippet, commentId: null, at, read: false }));
    if (!notes.length) return;
    const out = store.apply(notes.map((n) => ({ kind: 'notifications', id: n.id, data: n })), 'signin');
    broadcast(out.rev, out.results, null, null);
    notes.forEach((n) => webPush.sendTo(n.to, notifMessage(store, n)).catch(() => {}));
  }

  async function handle(req, res) {
    const url = new URL(req.url, 'http://local');
    const p = decodeURIComponent(url.pathname);

    if (p === '/api/health') return json(res, 200, { ok: true, version, rev: store.rev() });

    // Our own sign-in (signin.js): its page and the OpenID Connect answers Cloudflare asks for — no sign-in needed to reach them
    if (signin && (p.startsWith('/oidc/') || p === '/.well-known/openid-configuration')) return signinRoute(req, res, p, url);

    // The privacy policy and support page (web/legal): public, no sign-in, no data — the App Store links to them
    if ((p === '/privacy' || p === '/support') && webDir) {
      const f = path.join(webDir, 'legal', p.slice(1) + '.html');
      if (fs.existsSync(f)) { res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=300' }); return res.end(req.method === 'HEAD' ? undefined : fs.readFileSync(f)); }
    }

    // App Review copy only: its own sign-in (review.js); no Mac installer here
    if (review) {
      if (p === '/review/sign-in' && req.method === 'POST') {
        const raw = (await readRaw(req, 8192)).toString('utf8');
        const f = new URLSearchParams(raw);
        const r = review.signIn(netInfo(req).ip, f.get('email'), f.get('password'));
        if (!r.ok) { res.writeHead(r.wait ? 429 : 401, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }); return res.end(review.page({ error: r.error, email: f.get('email') || '' })); }
        res.writeHead(303, { Location: '/', 'Set-Cookie': review.cookie(req, r.token), 'Cache-Control': 'no-store' });
        return res.end();
      }
      if (p === '/review/sign-in') { res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }); return res.end(review.page()); }
      if (p === '/review/sign-out') {
        review.signOut(req);
        res.writeHead(303, { Location: '/review/sign-in', 'Set-Cookie': review.cookie(req, null), 'Cache-Control': 'no-store' });
        return res.end();
      }
      if (p.startsWith('/install')) return json(res, 404, { ok: false, error: 'Not on the App Review copy' });
    }

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

    // File links (flinks.js): the public page, its file and picture — no sign-in; the files address shows nothing else
    // Task links (Haris 2026-11-04): files…/t/<task> — the iPhone and Mac apps open the task (universal links); anywhere
    // else it goes on to the website's own ?task= link (its sign-in, and the Mac app's own hand-off from the browser)
    if (filesHost && /^\/t\/[A-Za-z0-9_-]{1,80}\/?$/.test(p) && (req.method === 'GET' || req.method === 'HEAD') && String(req.headers['x-forwarded-host'] || req.headers.host || '') === filesHost) {
      const id = p.slice(3).replace(/\/$/, '');
      res.writeHead(302, { Location: `${testCopy ? 'https://test.e11hq.com' : 'https://console.e11hq.com'}/?task=${encodeURIComponent(id)}`, 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' });
      return res.end();
    }
    // Content skeleton links (Haris 2026-11-10): files…/p/<plan> — the apps open it; anywhere else the website's ?plan=
    if (filesHost && /^\/p\/[A-Za-z0-9_-]{1,80}\/?$/.test(p) && (req.method === 'GET' || req.method === 'HEAD') && String(req.headers['x-forwarded-host'] || req.headers.host || '') === filesHost) {
      const id = p.slice(3).replace(/\/$/, '');
      res.writeHead(302, { Location: `${testCopy ? 'https://test.e11hq.com' : 'https://console.e11hq.com'}/?plan=${encodeURIComponent(id)}`, 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' });
      return res.end();
    }
    if ((p.startsWith('/f/') || p.startsWith('/d/') || p.endsWith('apple-app-site-association') || (p === '/robots.txt' && filesHost && String(req.headers['x-forwarded-host'] || req.headers.host || '') === filesHost)) && (req.method === 'GET' || req.method === 'HEAD')) {
      if (await fileLinks.serve(req, res, p)) return;
    }
    if (filesHost && String(req.headers['x-forwarded-host'] || req.headers.host || '') === filesHost) { res.writeHead(404, { 'Content-Type': 'text/plain', 'X-Robots-Tag': 'noindex, nofollow' }); return res.end('Not found'); }

    // E11 Talk (talk.js) — the chat app's own addresses: the team as everywhere, and client contacts (E11 Talk only)
    if (p.startsWith('/api/talk/')) { const tu = await talkWho(req, res); if (!tu) return; return talkRoute(req, res, p, url, tu); }
    // (E11 Talk's pictures — people's photos and client logos — on Talk's own address, signed in as Talk is: Console's
    //  file address asked for Console's sign-in, so Talk showed initials everywhere, Haris 2026-11-12. The team: what they
    //  may read in E11 Console. A client contact: their own client's logo and the team's photos, nothing else.)
    if (talkHost(req) && p.startsWith('/__file/') && (req.method === 'GET' || req.method === 'HEAD')) {
      const tu = await talkWho(req, res); if (!tu) return;
      const rel = p.slice('/__file/'.length);
      let ok;
      if (tu.contact) {
        const pr = store.get('projects', String(tu.client || '')), cl = pr && pr.clientId ? store.get('clients', String(pr.clientId)) : null;
        ok = (cl && cl.logo === rel) || store.list('users').some((x) => x.active !== false && x.avatar === rel);
      } else ok = access.canReadFile(tu, rel);
      if (!ok) return json(res, 403, { ok: false, error: 'Not allowed' });
      if (url.searchParams.get('w')) return files.serveSized(req, res, rel, url.searchParams.get('w'));
      return files.serve(req, res, rel);
    }

    const u = await who(req, res);
    if (!u) return;
    // (the iPhone app's sign-in comes back here: reaching it means signed in — a tiny page, not the whole website, which the
    //  app no longer shows)
    if (p === '/app/in') { res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }); return res.end('<!doctype html><meta name="viewport" content="width=device-width"><title>E11 Console</title>'); }

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
      const entry = { at: new Date(now).toISOString(), user: u.email, where: clip(body.where, 20), message: clip(body.message, body.where === 'slow' ? 2000 : 500), stack: clip(body.stack, body.where === 'slow' ? 3000 : 2000),
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

    // Sign-in codes (signin.js): any Super Admin or Office Admin makes one for anyone; the owner, through the owner's view,
    // too — kept out of the admins' record and telling no one
    if (signin && p === '/api/signin/code' && req.method === 'POST') {
      const real = req.realUser || u, byOwner = isOwner(real);
      if (!byOwner && !access.isAdm(real)) return json(res, 403, { ok: false, error: 'Only Super Admins and Office Admins make sign-in codes' });
      const body = await readBody(req, 4096);
      const t = store.get('users', String(body.userId || ''));
      if (!t || t.removed || t.active === false) return json(res, 404, { ok: false, error: 'Not on the team' });
      const r = signin.makeCode(t.email, real.email, { byOwner });
      if (!r.ok) return json(res, 400, r);
      const name = t.name || t.email, by = real.name || real.email, newUser = !r.hasPassword;
      const until = new Date(r.expires).toLocaleString('en-GB', { timeZone: process.env.TZ || 'Asia/Dubai', weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit', hour12: true });
      return json(res, 200, { ...r, name, by, newUser, until, message: signinMessage({ first: String(name).split(/\s+/)[0], email: r.email, code: r.code, until, by, newUser, site: isTestSite ? 'test.e11hq.com' : 'console.e11hq.com' }) });
    }
    // (the iPhone / Mac app, signed in: its device key — kept while still good, else a new one; dropped on sign-out)
    if (signin && p === '/api/signin/device' && req.method === 'POST') {
      const body = await readBody(req, 4096);
      if (body.drop) return json(res, 200, signin.dropDevice(body.key));
      return json(res, 200, signin.deviceKey((req.realUser || u).email, body.key, body.name));
    }
    if (signin && p === '/api/signin/codes') {
      const real = req.realUser || u, owner = isOwner(real);
      if (!owner && !access.isAdm(real)) return json(res, 403, { ok: false, error: 'Only Super Admins and Office Admins' });
      return json(res, 200, { ok: true, codes: signin.codesRecord({ owner }) });
    }
    if (p === '/api/me') return json(res, 200, { ok: true, user: access.shape(u, 'users', u), owner: isOwner(u), review: !!review, signin: !!signin, appIcon: appIcon.info(), macShell, version, rev: store.rev(), office: office.info(req),
      // (E11 Talk in the Mac app's sidebar: on the test site while it's built — Haris 2026-11-06; live when E11 Talk goes live)
      talk: isTestSite && !review,
      ownerView: req.ownerView || null, canOwnerView: ownerViewOk(req.realUser || u),
      // (Admins: whose account only its owner may change, so the Team page shows it locked)
      ownerId: access.isAdm(u) && cfg.adminEmail ? (access.userByEmail(cfg.adminEmail) || {}).id || null : null,
      viewAs: isTestSite && isOwner(req.realUser) ? { real: { id: req.realUser.id, name: req.realUser.name || req.realUser.email }, as: req.viewingAs ? { id: u.id, name: u.name || u.email, role: u.role } : null } : null });

    // A claim's PDF, drawn by the server (Haris 2026-11-05: for the iPhone, the Mac app and the website alike): the sheet,
    // then its receipts — your own claim, or anyone's with Finance access (as the page's claimPdf)
    if (p === '/api/app/claimPdf' && req.method === 'POST') {
      const body = await readBody(req);
      const c = store.get('claims', String((body && body.id) || ''));
      if (!c || !(c.userId === u.id || access.finLevel(u))) return json(res, 404, { ok: false, error: 'That claim isn’t available' });
      if (c.byHand) { const r0 = (c.groups || []).flatMap((g) => g.items || []).find((i) => i.receipt); return r0 ? json(res, 200, { ok: true, path: r0.receipt.path, name: r0.receipt.name || 'Claim.pdf', size: r0.receipt.size || 0 }) : json(res, 404, { ok: false, error: 'This claim has no PDF' }); }
      try {
        const s = await claimSheetFor(c, c.userId ? store.get('users', c.userId) : null, store.get('meta', 'main') || {}, { resolve: files.resolve, webDir: webDir || path.resolve(path.dirname(new URL(import.meta.url).pathname), '../../web') });
        const r = await files.commands.claimPdf({ userId: c.userId || ('p-' + (c.personId || 'x')), month: c.month, name: s.name, sheet: s.pdf, receipts: s.receipts.filter((x) => String(x || '').startsWith('Claims/')) });
        return json(res, 200, r);
      } catch (e) { return json(res, 500, { ok: false, error: 'Could not make the PDF: ' + e.message }); }
    }

    // The iPhone app starting on its own (Part B step 8): signed in — who, and the startup screen's memo
    if (p === '/api/app/start') {
      // (and Me's own rows that only the server can say — step 9: the owner (About › App updates), whose account is locked,
      //  the Test site rows — View as… and Start fresh — as the page's NativeMe model had them)
      const real = req.realUser || u, owner = isOwner(real);
      const me9 = {
        owner, ownerId: access.isAdm(u) && cfg.adminEmail ? (access.userByEmail(cfg.adminEmail) || {}).id || null : null,
        testSite: isTestSite,
        viewAs: isTestSite && owner ? { real: { id: real.id, name: real.name || real.email }, as: req.viewingAs ? { id: u.id, name: u.name || u.email } : null } : null,
        sample: isTestSite && owner && !req.viewingAs,
        signin: !!signin,   // (our own sign-in on: New Sign-in Code in Team members)
      };
      try { return json(res, 200, { ok: true, ...appStart.start(u, store.get('meta', 'main') || {}, (cfg.now || Date.now)(), appIcon.info()), ...me9, version, review: !!review }); }
      catch (e) { return json(res, 500, { ok: false, error: e.message }); }
    }

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

    // App updates (the launcher runs inside the same container): only the owner sees status and can update or roll back
    if (p === '/api/updates') {
      if (!isOwner(req.realUser || u)) return json(res, 403, { ok: false, error: 'Only the owner manages app updates' });
      if (!cfg.launcherUrl) return json(res, 200, { ok: true, managed: false, running: version });
      const action = req.method === 'POST' ? (await readBody(req)).action : null;
      if (review && action) return json(res, 403, { ok: false, error: 'Updates are automatic on the App Review copy' });
      const route = action === 'check' ? '/check' : action === 'update' ? '/update' : action === 'rollback' ? '/rollback' : '/status';
      const r = await fetch(cfg.launcherUrl + route, { method: action ? 'POST' : 'GET' }).then((x) => x.json()).catch((e) => ({ ok: false, error: 'Updater not reachable: ' + e.message }));
      return json(res, 200, { managed: true, ...r });
    }
    // The NAS's video hardware (Intel Quick Sync), for the owner's App updates page: is it passed in, does the driver
    // load, and can it actually encode a short test clip
    if (p === '/api/system/video') {
      if (!isOwner(req.realUser || u)) return json(res, 403, { ok: false, error: 'Only the owner can see this' });
      return json(res, 200, { ok: true, video: await videoHardware(url.searchParams.get('fresh') === '1'), lightCopies: views.stats() });
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

    // Link previews in comments (links.js): the page's details, and its picture or icon, read by the server
    if (p === '/api/link' && req.method === 'GET') {
      const r = await links.look(url.searchParams.get('u') || '');
      return json(res, 200, r);
    }
    if (p === '/api/link/img' && req.method === 'GET') {
      const r = await links.image(url.searchParams.get('u') || '').catch(() => null);
      if (!r) { res.writeHead(404, { 'Cache-Control': 'private, max-age=3600' }); return res.end(); }
      res.writeHead(200, { 'Content-Type': r.type, 'Cache-Control': 'private, max-age=86400', 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'none'; sandbox" });
      return fs.createReadStream(r.file).pipe(res);
    }
    // Read receipts: a person @mentioned in a comment has seen it (opened the update, or the comment came into view
    // in the task). Saved on the comment as seen[userId] = time; everyone who sees the task sees it.
    if (p === '/api/seen' && req.method === 'POST') {
      const b = await readBody(req, 64 * 1024).catch(() => ({}));
      if (req.viewingAs || u._ov) return json(res, 200, { ok: true, skipped: true });   // (looking as someone else isn't them seeing it)
      const t = b && b.taskId ? store.get('tasks', String(b.taskId)) : null;
      if (!t || !access.canSee(u, 'tasks', t)) return json(res, 404, { ok: false });
      const ids = new Set((Array.isArray(b.ids) ? b.ids : []).map(String).slice(0, 200));
      const at = new Date().toISOString();
      let n = 0;
      const comments = (t.comments || []).map((c) => {
        if (!ids.has(c.id) || c.authorId === u.id || (c.seen || {})[u.id] || !String(c.html || '').includes(`data-user="${u.id}"`)) return c;
        n++;
        return { ...c, seen: { ...(c.seen || {}), [u.id]: at } };
      });
      if (n) { const out = store.apply([{ kind: 'tasks', id: t.id, data: { ...t, comments } }], u.id); broadcast(out.rev, out.results, null, null); }
      return json(res, 200, { ok: true, marked: n });
    }

    // The native iPhone app: its notification address (device token) for this person; signing out removes it
    if (p === '/api/apns/register' && req.method === 'POST') {
      const b = await readBody(req, 16 * 1024).catch(() => ({}));
      if (req.viewingAs) return json(res, 200, { ok: true, viewingAs: true });
      return json(res, apns.register(u.id, b.token, b.env, { ack: b.ack === true, platform: b.platform }) ? 200 : 400, { ok: true, push: apns.enabled() });
    }
    // The app's Notification Service Extension: notification pid arrived on this device — the older ones that didn't
    // are sent again (apns.js ack)
    if (p === '/api/apns/ack' && req.method === 'POST') {
      const b = await readBody(req, 16 * 1024).catch(() => ({}));
      if (req.viewingAs) return json(res, 200, { ok: true });
      const r = await apns.ack(u.id, b.token, b.pid);
      return json(res, r.ok ? 200 : 404, r);
    }
    // A notification held on the iPhone (the app's Notification Content Extension): what it's about, as the app's Inbox peek
    // shows it — the task's name, client, status and facts, and for a comment that comment and the one before it
    if (p === '/api/notif-peek' && req.method === 'POST') {
      const b = await readBody(req, 16 * 1024).catch(() => ({}));
      const data = visibleSnapshot(u).data;
      const n = (data.notifications || []).find((x) => x.id === String(b.nid || '') && x.to === u.id);
      if (!n || !n.taskId) return json(res, 200, { ok: true, peek: null });
      let tk = null;
      try { tk = homeView.taskPage(u, data, n.taskId); } catch (e) { console.error('notif peek:', e.message); }
      if (!tk) return json(res, 200, { ok: true, peek: null });
      const t = (data.tasks || []).find((x) => x.id === n.taskId);
      const c = n.commentId && t ? (t.comments || []).find((x) => x.id === n.commentId) : null;
      let comments = [], people = tk.people || {}, canReply = false;
      if (c) {
        let fd = null;
        try { fd = homeView.commentsFeed(u, data, n.taskId, c.parentId || null); } catch (e) { console.error('notif peek:', e.message); }
        const items = (fd && fd.items) || [], i = items.findIndex((x) => x.id === c.id);
        if (i >= 0) { comments = items.slice(Math.max(0, i - 1), i + 1); people = { ...people, ...(fd.people || {}) }; canReply = fd.canWrite !== false && !fd.readOnly; }
      }
      const prio = (tk.prio || []).find((x) => x.key === u.id) || (tk.prio || []).find((x) => x.label);
      return json(res, 200, { ok: true, peek: {
        taskId: n.taskId, me: u.id, title: tk.title || '', client: tk.client || null, done: !!tk.done,
        status: tk.status ? { name: tk.status.name, rgb: tk.status.rgb } : null, dates: tk.dates || null,
        creator: tk.creator ? tk.creator.id : null, assignees: (tk.assignees || []).map((x) => x.id), prio: prio ? prio.label : '',
        desc: String(tk.desc || '').slice(0, 400), comments, people, canReply, threadId: c ? (c.parentId || c.id) : null,
      } });
    }
    if (p === '/api/apns/unregister' && req.method === 'POST') { const b = await readBody(req, 16 * 1024).catch(() => ({})); apns.unregister(b.token); return json(res, 200, { ok: true }); }

    // Phone notifications: the server's public key, and turning them on / off for this device
    // Morning summary: today's, for this person's open app (shown once per device); a test send to yourself
    if (p === '/api/digest') return json(res, 200, { ok: true, ...digest.forUser(u) });
    // Widgets (iPhone, Mac): this person's summary for the categories they may see (read only)
    if (p === '/api/widget' && req.method === 'GET') return json(res, 200, widget.summary(u));
    // The iPhone app's Home, worked out here (homeview.js, with the website's own rules: web/rules.js). Switch: the kv
    // 'home-server' set to 'off' sends the app back to getting Home from the page behind it (no app build needed).
    if (p === '/api/home' && req.method === 'GET') {
      if (store.kv.get('home-server') === 'off') return json(res, 200, { ok: true, off: true, rev: store.rev() });
      let home = null;
      try { home = homeView.home(u, visibleSnapshot(u).data); } catch (e) { console.error('home:', e.message); return json(res, 500, { ok: false, error: 'Home could not be worked out' }); }
      return json(res, 200, { ok: true, rev: store.rev(), home });
    }
    // …the app's My Tasks (the same rules; its filters in the address)
    // the iPhone app's native Comments (shell 30+): a task's comments (or one thread) as the app draws them
    if (p === '/api/comments' && req.method === 'GET') {
      if (store.kv.get('comments-server') === 'off') return json(res, 200, { ok: true, off: true, rev: store.rev() });
      let fd = null;
      try { fd = homeView.commentsFeed(u, visibleSnapshot(u).data, url.searchParams.get('id'), url.searchParams.get('thread')); } catch (e) { console.error('comments:', e.message); return json(res, 500, { ok: false, error: 'The comments could not be worked out' }); }
      return json(res, 200, { ok: true, rev: store.rev(), feed: fd });
    }
    // the iPhone app's own copy of the data (iOS app data plan): on unless the kv 'app-copy' is 'off' — then the app asks
    // for each screen again, as before (no app build needed)
    // (Part B step 1: the app's own tab bar — kv 'app-tabs' = 'off' turns it back to the page's, without an app build)
    if (p === '/api/appcopy' && req.method === 'GET') return json(res, 200, { ok: true, on: store.kv.get('app-copy') !== 'off', tabs: store.kv.get('app-tabs') !== 'off',
      // (Part B step 2: each page group from the app's own copy — kv 'app-me-<group>' = 'off' gives it back to the page)
      me: Object.fromEntries(['me', 'profile', 'team', 'trash', 'claims', 'expenses', 'overview', 'reviews', 'plans', 'assets'].map((g) => [g, store.kv.get('app-me-' + g) !== 'off'])) });
    // the iPhone app's native task page (shell 30+): the task as this person sees it, with what they may change
    if (p === '/api/task' && req.method === 'GET') {
      if (store.kv.get('task-server') === 'off') return json(res, 200, { ok: true, off: true, rev: store.rev() });
      let tk = null;
      try { tk = homeView.taskPage(u, visibleSnapshot(u).data, url.searchParams.get('id')); } catch (e) { console.error('task page:', e.message); return json(res, 500, { ok: false, error: 'The task could not be worked out' }); }
      return json(res, 200, { ok: true, rev: store.rev(), task: tk });
    }
    // a file's picture for the app (a video's frame, a PDF's / Office file's first page), made the first time it's asked for
    // a file's link: made (or the same one again), turned off / on, or where a link's file is (to open it in the app)
    if (p === '/api/flink') {
      const origin = `${/^(localhost|127\.)/.test(String(req.headers.host || '')) ? 'http' : 'https'}://${String(req.headers['x-forwarded-host'] || req.headers.host || '').replace(/[^\w.:-]/g, '')}`;
      if (req.method === 'GET' && url.searchParams.get('token')) return json(res, 200, fileLinks.where(u, url.searchParams.get('token'), access.canReadFile));
      const body = req.method === 'POST' ? await readBody(req).catch(() => ({})) : { path: url.searchParams.get('path') };
      // (which of these files' links are turned off — the app's file sheets say Turn on link)
      if (body && Array.isArray(body.paths)) return json(res, 200, { ok: true, off: fileLinks.offOf(body.paths.slice(0, 500).map(String).filter((x) => /^d:/.test(x) || access.canReadFile(u, x))) });
      // a Client Assets folder's link (made, or off / on)
      if (body && body.client && body.folder) {
        const c = store.get('clients', String(body.client)); const f = c && (c.folders || []).find((x) => x.id === String(body.folder));
        if (!c || !f) return json(res, 200, { ok: false, error: 'That folder isn’t in Client Assets any more' });
        if (!access.canReadFile(u, (f.dir || c.dir || 'Clients/x') + '/_')) return json(res, 403, { ok: false, error: 'Not allowed' });
        if (typeof body.off === 'boolean') { if (!access.isAdm(u)) return json(res, 403, { ok: false, error: 'Only Admins can turn a link off or on' }); return json(res, 200, fileLinks.folderSetOff(u, c.id, f.id, body.off, origin)); }
        if (body.state) { const r = fileLinks.folderLink(u, c.id, f.id, origin); return json(res, 200, r); }
        return json(res, 200, fileLinks.folderLink(u, c.id, f.id, origin));
      }
      const fp = String((body && body.path) || '');
      if (!fp || !access.canReadFile(u, fp)) return json(res, 403, { ok: false, error: 'Not allowed' });
      // (turning a link off or on: Admins only — Haris 2026-11-03)
      if (body && typeof body.off === 'boolean') { if (!access.isAdm(u)) return json(res, 403, { ok: false, error: 'Only Admins can turn a link off or on' }); return json(res, 200, fileLinks.setOff(u, fp, body.off, origin)); }
      return json(res, 200, fileLinks.linkFor(u, fp, origin));
    }
    if (p === '/api/fthumb' && req.method === 'GET') {
      const fp = String(url.searchParams.get('path') || '');
      if (!fp || !access.canReadFile(u, fp)) return json(res, 403, { ok: false, error: 'Not allowed' });
      let r = null;
      try { r = await files.commands.thumb({ id: url.searchParams.get('id') || undefined, path: fp }); } catch { r = null; }
      if (!r || !r.thumb) return json(res, 404, { ok: false, error: 'No picture' });
      return files.serve(req, res, r.thumb);
    }
    if (p === '/api/inbox' && req.method === 'GET') {
      if (store.kv.get('inbox-server') === 'off') return json(res, 200, { ok: true, off: true, rev: store.rev() });
      let list = null;
      try { list = homeView.inbox(u, visibleSnapshot(u).data, url.searchParams); } catch (e) { console.error('inbox:', e.message); return json(res, 500, { ok: false, error: 'The Inbox could not be worked out' }); }
      return json(res, 200, { ok: true, rev: store.rev(), home: list });
    }
    if (p === '/api/clients' && req.method === 'GET') {
      if (store.kv.get('clients-server') === 'off') return json(res, 200, { ok: true, off: true, rev: store.rev() });
      let m = null;
      try { m = homeView.clients(u, visibleSnapshot(u).data, url.searchParams); } catch (e) { console.error('clients:', e.message); return json(res, 500, { ok: false, error: 'Clients could not be worked out' }); }
      return json(res, 200, { ok: true, rev: store.rev(), home: m });
    }
    if (p === '/api/mytasks' && req.method === 'GET') {
      if (store.kv.get('mytasks-server') === 'off') return json(res, 200, { ok: true, off: true, rev: store.rev() });
      let list = null;
      try { list = homeView.myTasks(u, visibleSnapshot(u).data, url.searchParams); } catch (e) { console.error('mytasks:', e.message); return json(res, 500, { ok: false, error: 'My Tasks could not be worked out' }); }
      return json(res, 200, { ok: true, rev: store.rev(), home: list });
    }
    // …and its actions (Done / reopen, Due, Delete and its Undo): saved as the website would save them, then the fresh
    // Home. `op` (the app's id for the action) makes a retry after a lost answer harmless.
    if (p === '/api/home/act' && req.method === 'POST') {
      const body = await readBody(req);
      // (My Tasks' actions go by My Tasks' own switch)
      if (store.kv.get(body && body.from === 'mytasks' ? 'mytasks-server' : body && body.from === 'inbox' ? 'inbox-server' : body && body.from === 'task' ? 'task-server' : 'home-server') === 'off') return json(res, 200, { ok: false, off: true, error: 'Try again in a moment' });
      const op = body && body.op ? String(body.op).slice(0, 80) : null;
      const freshHome = () => { try { return homeView.home(u, visibleSnapshot(u).data); } catch { return null; } };
      // (the iPhone app with its own copy of the data — iOS app data plan, step 3: it gets the records that changed and
      //  draws every screen from its copy; Home or the task page aren't worked out again here, which was the slow part)
      const copy = !!(body && body.copy);
      // (a retry of an action already done: its answer again, with Home as it is now)
      const seen = op && homeOps.get(u.id + ':' + op);
      if (seen && copy) return json(res, 200, { ...seen, rev: store.rev() });
      if (seen) return json(res, 200, { ...seen, rev: store.rev(), ...(body.from === 'task' ? { task: (() => { try { return homeView.taskPage(u, visibleSnapshot(u).data, body.page || body.id); } catch { return null; } })() } : { home: freshHome() }) });
      let r;
      try { r = homeView.act(u, visibleSnapshot(u).data, body || {}, store); } catch (e) { console.error('home act:', e.message); return json(res, 200, { ok: false, error: 'That didn’t work — try again' }); }
      let out;
      if (!r.ok) out = { ok: false, error: r.error, need: r.need || null, why: !!r.why, status: r.status };
      else {
        // all or nothing: the task (and Trash) changes are checked first — refused, nothing is saved or sent (no
        // notifications about a change that didn't happen)
        const restoring = new Set(r.changes.filter((ch) => !ch.del && ch.kind !== 'trash').map((ch) => `${ch.kind}:${ch.id}`));
        const allowed = r.changes.filter((ch) => ch.kind === 'tasks' || ch.kind === 'trash').every((ch) => access.canWrite(u, ch, store.get(ch.kind, String(ch.id)), { restoring }));
        if (!allowed) out = { ok: false, error: 'Your role doesn’t allow this', status: 403 };
        else {
          let pushed = null;
          if (r.changes.length) pushed = pushAs(u, r.changes, body.client || null);
          // (Undo: the Trash entry of what this person just deleted goes too — whoever may delete may undo it)
          if (r.sysChanges && r.sysChanges.length) { const out2 = store.apply(r.sysChanges, u.id); broadcast(out2.rev, out2.results, null, u.id); }
          // (a new client's Client Assets folders, made on the NAS as the website does)
          for (const d of r.dirs || []) { try { files.commands.makeDir({ path: d }); } catch (e) { console.error('makeDir:', e.message); } }
          out = { ok: true, messages: r.messages, undo: r.undo || null, ...(r.created ? { created: r.created } : {}) };
          if (copy) out.changes = pushed ? pushed.results.filter((x) => !x.refused).map((x) => forUser(u, x)).filter((x) => !(x.hidden && x.kind === 'notifications')) : [];
        }
      }
      if (op) { homeOps.set(u.id + ':' + op, out); if (homeOps.size > 1000) homeOps.delete(homeOps.keys().next().value); }
      if (copy) return json(res, 200, { ...out, rev: store.rev() });
      // (the native task page: that task as it is now)
      if (body && body.from === 'task') { let tk = null; try { tk = homeView.taskPage(u, visibleSnapshot(u).data, body.page || body.id); } catch (e) { console.error('task page:', e.message); } return json(res, 200, { ...out, rev: store.rev(), task: tk }); }
      return json(res, 200, { ...out, rev: store.rev(), home: freshHome() });
    }
    // (Part B step 3) one of the app's actions: done here as the website would, every change checked against the person's
    // rights, all or nothing; answers with what the page answered plus the changed records for the app's copy
    if (p === '/api/app/act' && req.method === 'POST') {
      const body = await readBody(req);
      const ev = String((body && body.ev) || '').slice(0, 40);
      const acts = await loadAppActs();
      if (!acts[ev] || store.kv.get('app-act-' + actGroup(ev)) === 'off') return json(res, 200, { ok: false, off: true });
      const op = body.op ? String(body.op).slice(0, 80) : null;
      const seen = op && homeOps.get(u.id + ':act:' + op);
      if (seen) return json(res, 200, { ...seen, rev: store.rev() });
      let r;
      try { r = acts[ev](u, body); } catch (e) { console.error('app act', ev, e.message); return json(res, 200, { ok: false, error: 'That didn’t work — try again' }); }
      let out;
      if (!r || !r.ok) out = { ok: false, error: (r && r.error) || 'That didn’t work — try again', status: r && r.status, ...(r && r.need ? { need: r.need, ask: r.ask } : {}) };   // (need/ask: the question to put first — the CD switch's choice)
      else {
        const changes = r.changes || [];
        const restoring = new Set(changes.filter((ch) => !ch.del && ch.kind !== 'trash').map((ch) => `${ch.kind}:${ch.id}`));
        const allowed = changes.every((ch) => access.canWrite(u, ch, store.get(ch.kind, String(ch.id)), { restoring }));
        if (changes.some((ch) => clashesTalkContact(ch, store.get(ch.kind, String(ch.id))))) out = { ok: false, error: TALK_CLASH, status: 409 };
        else if (!allowed) out = { ok: false, error: 'Your role doesn’t allow this', status: 403 };
        else {
          const pushed = changes.length ? pushAs(u, changes, null) : null;
          if (r.sysChanges && r.sysChanges.length) { const o2 = store.apply(r.sysChanges, u.id); broadcast(o2.rev, o2.results, null, u.id); }
          // (files deleted for good: as the website's trashMany through /api/host — never one something else still uses)
          if (r.filesGone && r.filesGone.length) { try { const gone = unusedPaths(r.filesGone); gone.forEach((x) => views.remove(x)); files.commands.trashMany({ paths: gone }); } catch (e) { console.error('app act files:', e.message); } }
          // (Client Assets folders made on the NAS, as the website's Host makeDir)
          for (const d of r.dirs || []) { try { files.commands.makeDir({ path: d }); } catch (e) { console.error('makeDir:', e.message); } }
          // (after answering: what the website does once its save is in — a new client logo from the Logos folder —
          //  saved as this person, sent to every open app)
          if (typeof r.later === 'function') setImmediate(() => Promise.resolve().then(r.later).then((more) => { if (more && more.length) pushAs(u, more, null); }).catch((e) => console.error('app act later', ev, e.message)));
          out = { ok: true, ...(r.answer || {}), messages: r.messages || [],
            changes: pushed ? pushed.results.filter((x) => !x.refused).map((x) => forUser(u, x)).filter((x) => !(x.hidden && x.kind === 'notifications')) : [] };
        }
      }
      if (op) { homeOps.set(u.id + ':act:' + op, out); if (homeOps.size > 1000) homeOps.delete(homeOps.keys().next().value); }
      return json(res, 200, { ...out, rev: store.rev() });
    }
    if (p === '/api/occ-reminders') return json(res, 200, { ok: true, ...occRemind.forUser(u) });
    // Occasion dates: when the holiday calendar was last read (Admins and Account Managers can check now)
    if (p === '/api/holidays') {
      if (!(access.isAdm(u) || u.role === 'am')) return json(res, 403, { ok: false, error: 'Admins and Account Managers only' });
      const s = req.method === 'POST' ? await holidays.check() : holidays.status();
      return json(res, 200, { ok: true, ...s });
    }
    // AMs' and Super Admins' morning summary: one now, for yourself (My profile › Notifications), any day
    if (p === '/api/daily/test' && req.method === 'POST') {
      if (!(u.role === 'am' || access.isSuper(u))) return json(res, 403, { error: 'For Account Managers and Super Admins' });
      const out = daily.sendNow(u);
      return json(res, 200, { ok: true, id: out });
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
      const body = await readBody(req).catch(() => ({}));
      const r = await webPush.sendTo(u.id, { title: 'E11 Console', body: 'Notifications are on. This is how they’ll look on this phone.', tag: 'test' });
      // (the iPhone app asks about itself: was this phone sent to, and what Apple said — token kept out of the answer)
      const mine = String((body && body.token) || '').toLowerCase();
      const me = mine ? (r.apns || []).find((x) => x.token === mine) : null;
      return json(res, 200, { ok: true, sent: r.sent, removed: r.removed, apnsWhy: r.apnsWhy,
        devices: (r.apns || []).map((x) => ({ platform: x.platform, env: x.env, status: x.status, reason: x.reason })),
        ...(mine ? { thisPhone: me ? { status: me.status, reason: me.reason, env: me.env } : { status: 0, reason: 'not registered on this site' } } : {}) });
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
      for (const k of ['view-as', 'digest-sent', 'occ-remind-sent', 'daily-sent']) store.kv.set(k, k === 'view-as' ? 'null' : '{}');
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
      // (the sample's file links — the old ones pointed at files now in the trash folder)
      store.kv.set('flinks', JSON.stringify(data._flinks || {})); delete data._flinks;
      const { rev } = store.importAll(data, owner.id);
      for (const st of streams) send(st, 'resync', { rev, wiped: true });    // every open app reloads its data (its unsaved old changes dropped)
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
      // (a page still holding the person before — View as… just switched, its last save on the way: not this person's
      //  changes; nothing saved, the page told — it was refused, "Some changes weren't allowed": Haris 2026-11-05)
      if (body.me && String(body.me) !== String(u.id)) return json(res, 200, { ok: true, rev: store.rev(), results: [], stale: true });
      const { rev, results } = pushAs(u, changes, body.client);
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
      // (access: a short mark of what this person may see — an app that keeps its copy between launches sends the one it
      //  had, and gets a fresh download if it changed while it was away)
      const accessMark = crypto.createHash('sha1').update(s.lastAccess).digest('hex').slice(0, 12);
      send(s, 'hello', { version, rev: store.rev(), appIcon: appIcon.info(), access: accessMark });
      const since = Number(url.searchParams.get('since'));
      const hadMark = url.searchParams.get('access');
      if (hadMark && hadMark !== accessMark && Number.isFinite(since) && since > 0) send(s, 'resync', { rev: store.rev() });
      else if (Number.isFinite(since) && since > 0 && since < store.rev()) {
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

    // Fast office use (office.js): start / follow / stop a copy from the NAS shared folder; a pass for the office network
    if (p.startsWith('/api/share/') && req.method === 'POST') {
      const b = await readBody(req, 64 * 1024).catch(() => ({}));
      if (p === '/api/share/copy') {
        const target = b.dest ? { dest: String(b.dest) } : { taskId: String(b.taskId || '') };
        const why = uploadDenied(u, target);
        if (why) return json(res, 403, { ok: false, error: why });
        try { return json(res, 200, { ok: true, job: office.startCopy(u, target, b) }); } catch (e) { return json(res, e.status || 500, { ok: false, error: e.message }); }
      }
      if (p === '/api/share/status') { const st = office.status(u, b.job); return st ? json(res, 200, { ok: true, ...st }) : json(res, 404, { ok: false, error: 'No such copy' }); }
      if (p === '/api/share/cancel') { office.cancel(u, b.job); return json(res, 200, { ok: true }); }
    }
    if (p === '/api/local/ticket' && req.method === 'POST') {
      const b = await readBody(req, 64 * 1024).catch(() => ({}));
      if (!office.info(req).local) return json(res, 409, { ok: false, error: 'Not in the office' });
      if (b.kind === 'file') {
        const fp = String(b.path || '');
        if (!fp || !access.canReadFile(u, fp)) return json(res, 403, { ok: false, error: 'Not allowed' });
        return json(res, 200, { ok: true, ...office.ticket(u, { k: 'file', path: fp }) });
      }
      const target = b.dest ? { dest: String(b.dest) } : { taskId: String(b.taskId || '') };
      const why = uploadDenied(u, target);
      if (why) return json(res, 403, { ok: false, error: why });
      return json(res, 200, { ok: true, ...office.ticket(u, { k: 'up', target, name: String(b.name || 'file').slice(0, 200) }) });
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
        { const why = uploadDenied(u, body); if (why) return deny(why); }
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
        // deleting is for good now: never a file something else still uses (another task, a comment, Client Assets, a
        // claim, Finance, a plan, a scheduled comment, a profile photo…), checked against everything on the server —
        // the app's own check only sees what that person sees. (Items still in the app's Trash are checked by the app.)
        body = { paths: unusedPaths(paths) };
        body.paths.forEach((x) => views.remove(x));   // (its light copy goes too)
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
      if (url.searchParams.get('view')) return files.serve(req, res, views.viewPath(rel));   // a video's light copy (when ready)
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

  /* App Review copy only: the made-up demo data (demo.js), fresh on an empty copy and every night from 3:00 Dubai.
     Everything in this copy's own data folder is replaced — it never holds anything else. */
  function loadDemo(day) {
    const dels = [];
    for (const k of ['users', 'projects', 'tasks', 'clients', 'notifications', 'statuses', 'trash', 'finance', 'claims', 'plans']) store.list(k).forEach((x) => dels.push({ kind: k, id: String(x.id), del: true }));
    if (dels.length) store.apply(dels, 'demo-reset');
    store.apply([{ kind: 'meta', id: 'main', data: { createdAt: new Date().toISOString() } }], 'demo-reset');
    for (const k of ['digest-sent', 'occ-remind-sent', 'daily-sent', 'bday-sent']) store.kv.set(k, '{}');
    const filesRoot = path.join(dataDir, 'files');
    fs.rmSync(filesRoot, { recursive: true, force: true });
    fs.mkdirSync(filesRoot, { recursive: true });
    store.apply([{ kind: 'users', id: REVIEW_USER_ID, data: { ...DEMO_REVIEWER, email: review.user, createdAt: new Date(Date.now() - 400 * 86400000).toISOString() } }], 'demo-reset');
    const data = demoData(store, REVIEW_USER_ID, filesRoot);
    const { rev } = store.importAll(data, REVIEW_USER_ID);
    store.kv.set('demo-loaded', JSON.stringify({ day, at: new Date().toISOString() }));
    for (const st of streams) send(st, 'resync', { rev });
    console.log(`App Review demo data loaded: ${data.tasks.length} tasks, ${data.users.length} people`);
    return data;
  }
  let demoTimer = null;
  if (review) {
    const check = () => { try { const r = resetDue(store); if (r.due) loadDemo(r.day); } catch (e) { console.error('App Review demo data failed:', e); } };
    // (after the server is answering, not before: building the demo takes ~10 s here and much longer on the NAS, and the
    //  updater gives a new version 30 s to answer — the review copy's 2 AM update to 1.9.11 was rolled back that way)
    const first = setTimeout(check, 5000); if (first.unref) first.unref();
    demoTimer = setInterval(check, 10 * 60000); if (demoTimer.unref) demoTimer.unref();
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
    server, store, files, cfSync, webPush, get talk() { return talkNow(); },
    listen: (port, host) => new Promise((ok) => {
      // the office-network port (HTTPS, own certificate), when the NAS has it set up
      if (cfg.localPort) office.listen(cfg.localPort, office.localHandler({ readRaw, json, users: (id) => store.get('users', String(id)), uploads, canStill: (u, target, fp) => (fp ? access.canReadFile(u, fp) : !uploadDenied(u, target)) }));
      server.listen(port, host, () => ok(server.address().port));
    }),
    office, apns,
    digest, holidays, occRemind, birthdays, scheduled, daily, views, scanVideos, pruneNotifications,
    loadDemo,
    close: () => new Promise((ok) => { clearInterval(demoTimer); digest.stop(); holidays.stop(); occRemind.stop(); birthdays.stop(); scheduled.stop(); daily.stop(); apns.close(); talkApns.close(); if (talk) talk.close(); scanTimers.forEach((x) => { clearTimeout(x); clearInterval(x); }); office.close(); for (const s of streams) try { s.res.end(); } catch { /* ignore */ } server.close(() => { store.close(); ok(); }); }),
    broadcastVersion: (v) => { for (const s of streams) send(s, 'version', { version: v }); },
  };
}
