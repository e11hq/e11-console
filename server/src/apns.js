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

export function createApns({ store, keyFile = '', keyId = '', teamId = '', topic = 'ae.e11.console.ios', hosts = HOSTS, connectOpts = {}, now = () => Date.now(), log = console }) {
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
  const load = () => { try { return JSON.parse(store.kv.get('apns-subs') || '{}'); } catch { return {}; } };
  const save = (v) => store.kv.set('apns-subs', JSON.stringify(v));
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
  const loadP = () => { try { return JSON.parse(store.kv.get('apns-pending') || '{}'); } catch { return {}; } };
  const saveP = (v) => store.kv.set('apns-pending', JSON.stringify(v));
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
  function post(env, token, payload, ttl) {
    return new Promise((resolve) => {
      let req;
      try {
        req = session(env).request({ ':method': 'POST', ':path': `/3/device/${token}`, authorization: `bearer ${bearer()}`, 'apns-topic': topic,
          'apns-push-type': 'alert', 'apns-priority': '10', 'apns-expiration': String(Math.floor(now() / 1000) + ttl), 'content-type': 'application/json' });
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
  function payloadOf(msg, pid) {
    const data = {};
    for (const k of ['taskId', 'nid', 'kind', 'clientId', 'folderId', 'commentId', 'planId', 'view']) if (msg[k] != null) data[k] = msg[k];
    if (pid) data.pid = pid;
    // (mutable-content: the app's Notification Service Extension sees each one first — it confirms it arrived)
    return { aps: { alert: { title: String(msg.title || 'E11 Console'), body: String(msg.body || '') }, sound: 'default', 'thread-id': String(msg.taskId || msg.tag || msg.kind || 'e11'),
      ...(Number.isInteger(msg.badge) ? { badge: msg.badge } : {}), ...(pid ? { 'mutable-content': 1 } : {}) }, e11: data };
  }
  async function push1(s, msg, pid, ttl, tries) {
    const r = await post(s.env, s.token, payloadOf(msg, s.ack ? pid : null), ttl);
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
    if (!list.length || !enabled()) return { sent: 0 };
    const pid = crypto.randomBytes(8).toString('hex');
    let sent = 0;
    const gone = [];
    await Promise.all(list.map(async (s) => {
      const r = await push1(s, msg, pid, ttl, 0);
      if (r.status === 200) sent++;
      else if (r.status === 410 || ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic'].includes(r.reason)) gone.push(s.token);
      else log.error('APNs push failed', r.status, r.reason);
    }));
    if (gone.length) { const all = load(); all[userId] = (all[userId] || []).filter((s) => !gone.includes(s.token)); save(all); gone.forEach(dropPending); }
    return { sent, removed: gone.length };
  }
  return { enabled, register, unregister, devices, sendTo, ack, pendingFor, close: () => { for (const s of Object.values(sessions)) try { s.close(); } catch { /* fine */ } } };
}
