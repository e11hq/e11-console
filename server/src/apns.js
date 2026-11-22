// Notifications for the native iPhone and Mac App Store apps through Apple's push service (APNs). The same messages as the phone /
// browser notifications (webpush.js notifMessage), sent to every iPhone app the person has signed in on.
// Needs the push key from the Apple Developer account, on the NAS (never in the code): APNS_KEY_FILE (the .p8 file),
// APNS_KEY_ID, APNS_TEAM_ID. Without them nothing is sent (the app still works). No outside packages: HTTP/2 and
// the ES256 token are Node's own.
import http2 from 'node:http2';
import crypto from 'node:crypto';
import fs from 'node:fs';

const b64u = (b) => Buffer.from(b).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const HOSTS = { production: 'https://api.push.apple.com', sandbox: 'https://api.sandbox.push.apple.com' };

export function createApns({ store, keyFile = '', keyId = '', teamId = '', topic = 'ae.e11.console.ios', kvPrefix = 'apns', hosts = HOSTS, connectOpts = {}, now = () => Date.now(), log = console }) {
  let key = null;
  function signingKey() {
    if (key) return key;
    if (!keyFile || !keyId || !teamId) return null;
    try { key = crypto.createPrivateKey(fs.readFileSync(keyFile, 'utf8')); } catch (e) { log.error('APNs key:', e.message); key = null; }
    return key;
  }
  const enabled = () => !!signingKey();
  // the provider token: ES256, valid an hour at Apple; renewed every 50 minutes
  let jwt = null, jwtAt = 0;
  function bearer() {
    if (jwt && now() - jwtAt < 50 * 60_000) return jwt;
    const head = b64u(JSON.stringify({ alg: 'ES256', kid: keyId }));
    const body = b64u(JSON.stringify({ iss: teamId, iat: Math.floor(now() / 1000) }));
    const sig = crypto.sign('sha256', Buffer.from(head + '.' + body), { key: signingKey(), dsaEncoding: 'ieee-p1363' });
    jwt = `${head}.${body}.${b64u(sig)}`; jwtAt = now();
    return jwt;
  }
  // the iPhones signed in, per person: kv apns-subs = { userId: [{ token, env, at }] }
  // (E11 Talk keeps its own list — kvPrefix 'talk-apns' — its phones aren't E11 Console's)
  const load = () => { try { return JSON.parse(store.kv.get(`${kvPrefix}-subs`) || '{}'); } catch { return {}; } };
  const save = (v) => store.kv.set(`${kvPrefix}-subs`, JSON.stringify(v));
  // ack: the app confirms each notification it gets (its Notification Service Extension: iPhone app 16+, Mac App
  // Store app) — then the ones it didn't get are sent again (see ack below)
  function register(userId, token, env, opts = {}) {
    token = String(token || '').toLowerCase();
    if (!/^[0-9a-f]{32,200}$/.test(token)) return false;
    const all = load();
    for (const k of Object.keys(all)) all[k] = (all[k] || []).filter((s) => s.token !== token);   // a phone signed in as someone else now
    if (!(all[userId] || []).length) dropPending(token);
    all[userId] = (all[userId] || []).concat({ token, env: env === 'sandbox' ? 'sandbox' : 'production', at: new Date(now()).toISOString(),
      ...(opts.ack ? { ack: true } : {}), ...(opts.platform === 'mac' ? { platform: 'mac' } : {}) }).slice(-10);
    save(all);
    return true;
  }
  // ---- No missed notifications (Haris, 2026-10-30) ----
  // Apple keeps only the newest notification for a phone / Mac that's offline and drops the earlier ones. So each
  // one sent to an app that confirms (ack) is remembered per device (kv apns-pending = { token: [{ pid, msg, at,
  // tries }] }) until the app says it arrived. When a confirmation comes in (the device is reachable again), every
  // older one still unconfirmed is sent again — up to 3 times, for up to 4 days. Nothing is kept for apps that don't
  // confirm (older iPhone apps).
  const KEEP = 4 * 86400000, MAX = 60;
  const loadP = () => { try { return JSON.parse(store.kv.get(`${kvPrefix}-pending`) || '{}'); } catch { return {}; } };
  const saveP = (v) => store.kv.set(`${kvPrefix}-pending`, JSON.stringify(v));
  function dropPending(token) { const p = loadP(); if (p[token]) { delete p[token]; saveP(p); } }
  function ownerOf(token) { const all = load(); for (const [uid, list] of Object.entries(all)) { const s = (list || []).find((x) => x.token === token); if (s) return { uid, s }; } return null; }
  // the app says notification pid arrived on this device: forget it, and send again the older ones that didn't
  async function ack(userId, token, pid) {
    token = String(token || '').toLowerCase();
    const o = ownerOf(token);
    if (!o || o.uid !== userId) return { ok: false };
    const p = loadP(), list = p[token] || [];
    const hit = list.find((x) => x.pid === String(pid || ''));
    const t = now();
    const cut = hit ? Date.parse(hit.at) : t - 60_000;   // (sent before the one that just arrived — or a minute ago)
    const keep = [], again = [];
    for (const x of list) {
      if (x.pid === String(pid || '') || t - Date.parse(x.at) >= KEEP) continue;
      if (Date.parse(x.at) < cut && x.tries < 3) again.push(x); else keep.push(x);
    }
    p[token] = keep;
    if (!keep.length) delete p[token];
    saveP(p);
    let resent = 0;
    for (const x of again) {
      const r = await push1(o.s, x.msg, x.pid, 4 * 86400, x.tries + 1);
      if (r.status === 200) resent++;
    }
    return { ok: true, resent };
  }
  const pendingFor = (token) => (loadP()[String(token || '').toLowerCase()] || []).map((x) => ({ pid: x.pid, tries: x.tries }));
  function unregister(token) {
    dropPending(String(token || '').toLowerCase());
    const all = load();
    for (const k of Object.keys(all)) all[k] = (all[k] || []).filter((s) => s.token !== String(token || '').toLowerCase());
    save(all);
  }
  const devices = (userId) => (load()[userId] || []).length;
  // one HTTP/2 connection per APNs host, kept open
  const sessions = {};
  function session(env) {
    const s = sessions[env];
    if (s && !s.closed && !s.destroyed) return s;
    const n = http2.connect(hosts[env], connectOpts);
    n.on('error', (e) => { log.error('APNs connection:', e.message); });
    n.on('goaway', () => { try { n.close(); } catch { /* fine */ } });
    n.setTimeout(60 * 60_000, () => { try { n.close(); } catch { /* fine */ } });
    if (n.unref) n.unref();
    sessions[env] = n;
    return n;
  }
  // (collapse: E11 Talk's message id — a later notification with the same one replaces it in place, Haris 2026-11-22 16:22)
  function post(env, token, payload, ttl, kind = 'alert', prio = '10', collapse = null) {
    return new Promise((resolve) => {
      let req;
      try {
        req = session(env).request({ ':method': 'POST', ':path': `/3/device/${token}`, authorization: `bearer ${bearer()}`, 'apns-topic': topic,
          'apns-push-type': kind, 'apns-priority': prio, 'apns-expiration': String(Math.floor(now() / 1000) + ttl), 'content-type': 'application/json',
          ...(collapse ? { 'apns-collapse-id': String(collapse).slice(0, 64) } : {}) });
      } catch (e) { return resolve({ status: 0, reason: e.message }); }
      let status = 0, body = '';
      req.on('response', (h) => { status = h[':status']; });
      req.on('data', (c) => { body += c; });
      req.on('end', () => { let reason = ''; try { reason = JSON.parse(body || '{}').reason || ''; } catch { /* fine */ } resolve({ status, reason }); });
      req.on('error', (e) => resolve({ status: 0, reason: e.message }));
      req.setTimeout(15000, () => { req.close(); resolve({ status: 0, reason: 'timeout' }); });
      req.end(JSON.stringify(payload));
    });
  }
  // msg: { title, body, taskId, nid, tag, badge, kind, clientId, folderId, commentId, planId, view } (webpush.js notifMessage)
  // (E11 Talk: the message itself rides along — its notification helper keeps it, so Talk opens with it already there;
  //  only when it fits Apple's 4 KB: else without its small picture, else without it — as before. Haris 2026-11-22 13:35)
  function withMessage(out, m) {
    if (!m || typeof m !== 'object') return out;
    const fits = (x) => Buffer.byteLength(JSON.stringify(x)) <= 3900;
    const a = { ...out, e11: { ...out.e11, m } };
    if (fits(a)) return a;
    if (m.file && m.file.thumb) { const b = { ...out, e11: { ...out.e11, m: { ...m, file: { ...m.file, thumb: undefined } } } }; if (fits(b)) return b; }
    return out;
  }
  function payloadOf(msg, pid) {
    const data = {};
    for (const k of ['taskId', 'nid', 'kind', 'clientId', 'folderId', 'commentId', 'threadId', 'planId', 'view', 'groupId', 'msgId', 'gone']) if (msg[k] != null) data[k] = msg[k];
    if (pid) data.pid = pid;
    // (mutable-content: the app's Notification Service Extension sees each one first — it confirms it arrived; E11 Talk's
    //  message ones too: its helper tells the sender's ✓✓ — Haris 2026-11-19 21:42)
    // (quiet: no sound, no banner — E11 Talk's "This message was deleted" taking the place of the message's own)
    const out = { aps: { alert: { title: String(msg.title || (kvPrefix === 'apns' ? 'E11 Console' : 'E11 Talk')), body: String(msg.body || '') }, ...(msg.quiet ? { 'interruption-level': 'passive' } : { sound: 'default' }), 'thread-id': String(msg.taskId || msg.tag || msg.kind || 'e11'),
      ...(Number.isInteger(msg.badge) ? { badge: msg.badge } : {}), ...(pid || (msg.kind === 'talk' && msg.msgId) ? { 'mutable-content': 1 } : {}),
      // (E11 Talk's messages also wake the app quietly, so its photos and videos start downloading with Talk closed —
      //  Haris 2026-11-21 15:34 "Yes, include it")
      ...(msg.kind === 'talk' && msg.msgId ? { 'content-available': 1 } : {}),
      ...(msg.category ? { category: String(msg.category) } : {}) }, e11: data };   // (E11 Talk's and E11 Console's: reply from the banner)
    return withMessage(out, msg.m);
  }
  async function push1(s, msg, pid, ttl, tries) {
    const r = await post(s.env, s.token, payloadOf(msg, s.ack ? pid : null), ttl, 'alert', '10', msg.collapse || null);
    if (s.ack && r.status === 200) {
      const p = loadP(), t = now();
      p[s.token] = (p[s.token] || []).filter((x) => t - Date.parse(x.at) < KEEP && x.pid !== pid)
        .concat({ pid, msg, at: tries ? ((loadP()[s.token] || []).find((x) => x.pid === pid) || {}).at || new Date(t).toISOString() : new Date(t).toISOString(), tries }).slice(-MAX);
      saveP(p);
    }
    return r;
  }
  async function sendTo(userId, msg, { ttl = 4 * 86400 } = {}) {
    const list = load()[userId] || [];
    if (!list.length || !enabled()) return { sent: 0, results: [], why: !enabled() ? 'no-key' : 'no-devices' };
    const pid = crypto.randomBytes(8).toString('hex');
    let sent = 0;
    const gone = [], results = [];
    await Promise.all(list.map(async (s) => {
      const r = await push1(s, msg, pid, ttl, 0);
      results.push({ token: s.token, platform: s.platform || 'iphone', env: s.env, status: r.status, reason: r.reason || '' });
      if (r.status === 200) sent++;
      else if (r.status === 410 || ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic'].includes(r.reason)) gone.push(s.token);
      else log.error('APNs push failed', r.status, r.reason);
    }));
    if (gone.length) { const all = load(); all[userId] = (all[userId] || []).filter((s) => !gone.includes(s.token)); save(all); gone.forEach(dropPending); }
    if (sent && msg.collapse && msg.replaceable) keepC(msg.collapse, userId);
    return { sent, removed: gone.length, results };
  }
  // a notification taken back (Haris 2026-11-22 19:47 — E11 Console's deleted comment, as E11 Talk's deleted message): the
  // same tag again, quietly — no sound, no banner — with new words, so Apple replaces the one still showing; only to the
  // people it reached, within 4 days (kv apns-collapse = { tag: { at, to: [userId] } }); the old one never sent again
  const loadC = () => { try { return JSON.parse(store.kv.get(`${kvPrefix}-collapse`) || '{}'); } catch { return {}; } };
  const saveC = (v) => store.kv.set(`${kvPrefix}-collapse`, JSON.stringify(v));
  function keepC(tag, userId) {
    const c = loadC(), t = now();
    for (const [k, v] of Object.entries(c)) if (t - Date.parse(v.at) > KEEP) delete c[k];
    const e = c[tag] || { at: new Date(t).toISOString(), to: [] };
    if (!e.to.includes(String(userId))) e.to.push(String(userId));
    c[tag] = e;
    const keys = Object.keys(c); if (keys.length > 3000) keys.slice(0, keys.length - 3000).forEach((k) => delete c[k]);
    saveC(c);
  }
  async function replace(tag, msg) {
    const c = loadC(), e = c[tag];
    if (!e || now() - Date.parse(e.at) > KEEP) return { sent: 0 };
    delete c[tag]; saveC(c);
    const p = loadP(); let changed = false;
    for (const k of Object.keys(p)) { const keep = (p[k] || []).filter((x) => !(x.msg && x.msg.collapse === tag)); if (keep.length !== (p[k] || []).length) { p[k] = keep; changed = true; } }
    if (changed) saveP(p);
    let sent = 0;
    // (gone: an app in front shows no banner for it)
    for (const uid of e.to) { const r = await sendTo(uid, { ...msg, collapse: tag, quiet: true, replaceable: false, badge: undefined, gone: 1 }); sent += r.sent || 0; }
    return { sent };
  }
  // a quiet note to someone's iPhones (Haris 2026-11-16): something read or unread on the Mac, the website or another phone —
  // the icon's count set (a count-only notification: no banner, no sound, nothing in Notification Centre), and the app woken
  // briefly to take the read ones' notifications off this iPhone (iPhone decides how soon)
  async function quiet(userId, { badge, read = [] }) {
    const list = load()[userId] || [];
    if (!list.length || !enabled()) return { sent: 0 };
    let sent = 0;
    await Promise.all(list.map(async (s) => {
      const a = Number.isInteger(badge) ? await post(s.env, s.token, { aps: { badge } }, 3600, 'alert', '5') : { status: 0 };
      const b = await post(s.env, s.token, { aps: { 'content-available': 1 }, e11: { quiet: true, ...(Number.isInteger(badge) ? { badge } : {}), read: read.slice(0, 200) } }, 3600, 'background', '5');
      if (a.status === 200 || b.status === 200) sent++;
    }));
    return { sent };
  }
  // a quiet wake-up for someone's iPhones (no banner, no sound): E11 Talk's "Ask the group" — the app looks whether it has
  // the file asked for and sends it (Haris 2026-11-20 21:36). iPhone decides how soon it wakes the app.
  async function wake(userId, e11 = {}) {
    const list = load()[userId] || [];
    if (!list.length || !enabled()) return { sent: 0 };
    let sent = 0;
    await Promise.all(list.map(async (s) => { const r = await post(s.env, s.token, { aps: { 'content-available': 1 }, e11: { quiet: true, ...e11 } }, 86400, 'background', '5'); if (r.status === 200) sent++; }));
    return { sent };
  }
  return { enabled, register, unregister, devices, sendTo, replace, quiet, wake, ack, pendingFor, close: () => { for (const s of Object.values(sessions)) try { s.close(); } catch { /* fine */ } } };
}
