// Notifications for the native iPhone app through Apple's push service (APNs). The same messages as the phone /
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
  function register(userId, token, env) {
    token = String(token || '').toLowerCase();
    if (!/^[0-9a-f]{32,200}$/.test(token)) return false;
    const all = load();
    for (const k of Object.keys(all)) all[k] = (all[k] || []).filter((s) => s.token !== token);   // a phone signed in as someone else now
    all[userId] = (all[userId] || []).concat({ token, env: env === 'sandbox' ? 'sandbox' : 'production', at: new Date(now()).toISOString() }).slice(-10);
    save(all);
    return true;
  }
  function unregister(token) {
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
  async function sendTo(userId, msg, { ttl = 86400 } = {}) {
    const list = load()[userId] || [];
    if (!list.length || !enabled()) return { sent: 0 };
    const data = {};
    for (const k of ['taskId', 'nid', 'kind', 'clientId', 'folderId', 'commentId', 'planId', 'view']) if (msg[k] != null) data[k] = msg[k];
    const payload = { aps: { alert: { title: String(msg.title || 'E11 Console'), body: String(msg.body || '') }, sound: 'default', 'thread-id': String(msg.taskId || msg.tag || msg.kind || 'e11'),
      ...(Number.isInteger(msg.badge) ? { badge: msg.badge } : {}) }, e11: data };
    let sent = 0;
    const gone = [];
    await Promise.all(list.map(async (s) => {
      const r = await post(s.env, s.token, payload, ttl);
      if (r.status === 200) sent++;
      else if (r.status === 410 || ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic'].includes(r.reason)) gone.push(s.token);
      else log.error('APNs push failed', r.status, r.reason);
    }));
    if (gone.length) { const all = load(); all[userId] = (all[userId] || []).filter((s) => !gone.includes(s.token)); save(all); }
    return { sent, removed: gone.length };
  }
  return { enabled, register, unregister, devices, sendTo, close: () => { for (const s of Object.values(sessions)) try { s.close(); } catch { /* fine */ } } };
}
