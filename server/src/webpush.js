// Web Push: notifications on phones (iPhone home-screen app, Android) and browsers, even when the app is closed.
// Standard Web Push (RFC 8030) with message encryption (RFC 8291, aes128gcm) and VAPID sign-in (RFC 8292),
// written with node:crypto so no outside packages are needed.
import crypto from 'node:crypto';

const b64u = (buf) => Buffer.from(buf).toString('base64url');
const unb64u = (s) => Buffer.from(String(s || ''), 'base64url');

// Encrypt one message for one subscription (RFC 8291). Returns the request body.
export function encryptPayload(sub, payload, { salt = crypto.randomBytes(16), ecdh = null } = {}) {
  const uaPublic = unb64u(sub.keys && sub.keys.p256dh);
  const auth = unb64u(sub.keys && sub.keys.auth);
  if (uaPublic.length !== 65 || auth.length < 16) throw new Error('Bad subscription keys');
  const server = ecdh || crypto.createECDH('prime256v1');
  if (!ecdh) server.generateKeys();
  const asPublic = server.getPublicKey();
  const shared = server.computeSecret(uaPublic);
  const keyInfo = Buffer.concat([Buffer.from('WebPush: info\0'), uaPublic, asPublic]);
  const ikm = Buffer.from(crypto.hkdfSync('sha256', shared, auth, keyInfo, 32));
  const cek = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: aes128gcm\0'), 16));
  const nonce = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: nonce\0'), 12));
  const cipher = crypto.createCipheriv('aes-128-gcm', cek, nonce);
  const body = Buffer.concat([cipher.update(Buffer.concat([Buffer.from(payload), Buffer.from([2])])), cipher.final(), cipher.getAuthTag()]);
  const rs = Buffer.alloc(4); rs.writeUInt32BE(4096);
  return Buffer.concat([salt, rs, Buffer.from([asPublic.length]), asPublic, body]);
}

export function createWebPush({ store, fetchImpl = fetch, subject = 'mailto:admin@e11hq.com', log = console }) {
  // Server keys, made once and kept in the database
  let vapid = null;
  try { vapid = JSON.parse(store.kv.get('vapid') || 'null'); } catch { vapid = null; }
  if (!vapid || !vapid.jwk || !vapid.publicKey) {
    const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const jwk = privateKey.export({ format: 'jwk' });
    const publicKey = b64u(Buffer.concat([Buffer.from([4]), unb64u(jwk.x), unb64u(jwk.y)]));
    vapid = { jwk, publicKey };
    store.kv.set('vapid', JSON.stringify(vapid));
  }
  const signKey = crypto.createPrivateKey({ key: vapid.jwk, format: 'jwk' });

  const loadSubs = () => { try { return JSON.parse(store.kv.get('pushsubs') || '{}'); } catch { return {}; } };
  const saveSubs = (s) => store.kv.set('pushsubs', JSON.stringify(s));

  const jwtCache = new Map();
  function vapidHeader(endpoint) {
    const aud = new URL(endpoint).origin;
    const hit = jwtCache.get(aud);
    if (hit && hit.exp - 3600 > Date.now() / 1000) return hit.header;
    const exp = Math.floor(Date.now() / 1000) + 12 * 3600;
    const data = `${b64u(JSON.stringify({ typ: 'JWT', alg: 'ES256' }))}.${b64u(JSON.stringify({ aud, exp, sub: subject }))}`;
    const sig = crypto.sign('sha256', Buffer.from(data), { key: signKey, dsaEncoding: 'ieee-p1363' });
    const header = `vapid t=${data}.${b64u(sig)}, k=${vapid.publicKey}`;
    jwtCache.set(aud, { exp, header });
    return header;
  }

  function subscribe(userId, sub, ua = '') {
    if (!sub || !/^https:\/\//.test(String(sub.endpoint || '')) || !sub.keys || !sub.keys.p256dh || !sub.keys.auth) throw Object.assign(new Error('Bad subscription'), { status: 400 });
    const all = loadSubs();
    // one device belongs to one person: remove it from anyone else first
    for (const k of Object.keys(all)) all[k] = all[k].filter((s) => s.endpoint !== sub.endpoint);
    all[userId] = (all[userId] || []).concat({ endpoint: sub.endpoint, keys: { p256dh: sub.keys.p256dh, auth: sub.keys.auth }, ua: String(ua).slice(0, 200), at: new Date().toISOString() }).slice(-10);
    saveSubs(all);
    return all[userId].length;
  }
  function unsubscribe(userId, endpoint) {
    const all = loadSubs();
    all[userId] = (all[userId] || []).filter((s) => s.endpoint !== endpoint);
    saveSubs(all);
  }
  const devices = (userId) => (loadSubs()[userId] || []).length;
  const has = (userId, endpoint) => (loadSubs()[userId] || []).some((s) => s.endpoint === endpoint);

  async function sendTo(userId, message, { ttl = 86400 } = {}) {
    const list = loadSubs()[userId] || [];
    if (!list.length) return { sent: 0 };
    const payload = JSON.stringify(message);
    let sent = 0;
    const gone = [];
    await Promise.all(list.map(async (s) => {
      try {
        const res = await fetchImpl(s.endpoint, {
          method: 'POST',
          headers: { Authorization: vapidHeader(s.endpoint), 'Content-Encoding': 'aes128gcm', 'Content-Type': 'application/octet-stream', TTL: String(ttl), Urgency: 'high' },
          body: encryptPayload(s, payload),
        });
        if (res.status === 404 || res.status === 410) gone.push(s.endpoint);
        else if (res.status >= 200 && res.status < 300) sent++;
        else log.error('Push failed', res.status, new URL(s.endpoint).host);
      } catch (e) { log.error('Push failed', e.message); }
    }));
    if (gone.length) { const all = loadSubs(); all[userId] = (all[userId] || []).filter((s) => !gone.includes(s.endpoint)); saveSubs(all); }
    return { sent, removed: gone.length };
  }

  return { publicKey: () => vapid.publicKey, subscribe, unsubscribe, devices, has, sendTo };
}

// Words for the phone banner, matching the in-app alert
export function notifMessage(store, n) {
  const strip = (s) => String(s || '').replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\s+/g, ' ').trim();
  const from = store.get('users', n.from);
  const t = n.taskId ? store.get('tasks', n.taskId) : null;
  const name = from ? (from.name || String(from.email || '').split('@')[0]) : 'E11 Console';
  const body = `${strip(n.text)}${t ? ` “${t.title || 'Untitled task'}”` : ''}${n.snippet ? ' — ' + strip(n.snippet) : ''}`;
  const unread = store.list('notifications').filter((x) => x.to === n.to && !x.read).length;
  // (kind and place travel with it, so a tap opens the right page even before the update reaches the app)
  if (n.kind === 'sched-cancel') return { title: `Scheduled ${/scheduled reply/.test(String(n.text || '')) ? 'reply' : 'comment'} not sent`, body: (strip(n.text) + (n.snippet ? ' — ' + strip(n.snippet) : '')).slice(0, 300), taskId: n.taskId || null, nid: n.id, tag: n.id, badge: unread, kind: 'sched-cancel' };
  if (n.kind === 'daily') return { title: n.title || 'Good morning', body: strip(n.text).slice(0, 300), taskId: null, nid: n.id, tag: n.id, badge: unread, kind: 'daily' };
  if (n.kind === 'birthday') return { title: 'Birthday today', body: strip(n.text).slice(0, 300), taskId: null, nid: n.id, tag: n.id, badge: unread, kind: 'birthday' };
  return { title: name, body: body.slice(0, 300), taskId: n.taskId || null, nid: n.id, tag: n.taskId || n.id, badge: unread, kind: n.kind || null, clientId: n.clientId || null, folderId: n.folderId || null, commentId: n.commentId || null, planId: n.planId || null };
}
