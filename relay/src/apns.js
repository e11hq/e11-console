// E11 Talk's notifications from Cloudflare itself (TALK-CF-A, Haris 2026-11-22 01:00 "A") — when the office can't be
// reached: the same notifications the office sends (server/src/apns.js — the same words, the quiet wake for ✓✓ and
// files, muted groups and Out of Office already decided by Talk's own code before it asks). Apple's key is the one the
// NAS uses, kept as Cloudflare secrets added by Haris (APNS_KEY — the .p8 text, APNS_KEY_ID, APNS_TEAM_ID); the phones'
// notification addresses come from the office with E11 Console's people (dir.push), kept here.
const b64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const enc = new TextEncoder();
const HOSTS = { production: 'https://api.push.apple.com', sandbox: 'https://api.sandbox.push.apple.com' };

export function makeApns({ key, keyId, teamId, topic = 'ae.e11.talk.ios', subs = () => ({}), now = () => Date.now(), go = (...a) => fetch(...a) }) {
  const on = !!(key && keyId && teamId);
  let jwt = null, jwtAt = 0, priv = null;
  async function signer() {
    if (priv) return priv;
    const pem = String(key).replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
    const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
    priv = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
    return priv;
  }
  // the provider token: ES256, an hour at Apple; made again every 50 minutes
  async function bearer() {
    if (jwt && now() - jwtAt < 50 * 60_000) return jwt;
    const head = b64u(enc.encode(JSON.stringify({ alg: 'ES256', kid: keyId })));
    const body = b64u(enc.encode(JSON.stringify({ iss: teamId, iat: Math.floor(now() / 1000) })));
    const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, await signer(), enc.encode(head + '.' + body));
    jwt = `${head}.${body}.${b64u(sig)}`; jwtAt = now();
    return jwt;
  }
  async function post(env, token, payload, ttl, kind = 'alert', prio = '10') {
    try {
      const r = await go(`${HOSTS[env] || HOSTS.production}/3/device/${token}`, { method: 'POST', body: JSON.stringify(payload), headers: {
        authorization: `bearer ${await bearer()}`, 'apns-topic': topic, 'apns-push-type': kind, 'apns-priority': prio,
        'apns-expiration': String(Math.floor(now() / 1000) + ttl), 'content-type': 'application/json' } });
      let reason = ''; try { reason = (await r.json()).reason || ''; } catch { /* 200: empty */ }
      return { status: r.status, reason };
    } catch (e) { return { status: 0, reason: e.message }; }
  }
  // the same notification as the office's (apns.js payloadOf)
  function payloadOf(msg) {
    const data = {};
    for (const k of ['kind', 'clientId', 'groupId', 'msgId', 'tag']) if (msg[k] != null) data[k] = msg[k];
    return { aps: { alert: { title: String(msg.title || 'E11 Talk'), body: String(msg.body || '') }, sound: 'default', 'thread-id': String(msg.tag || msg.kind || 'e11'),
      ...(Number.isInteger(msg.badge) ? { badge: msg.badge } : {}), ...(msg.kind === 'talk' && msg.msgId ? { 'mutable-content': 1, 'content-available': 1 } : {}),
      ...(msg.category ? { category: String(msg.category) } : {}) }, e11: data };
  }
  const list = (uid) => (subs()[String(uid)] || []).filter((s) => s && /^[0-9a-f]{32,200}$/.test(String(s.token || '')));
  return {
    on,
    async sendTo(uid, msg, { ttl = 4 * 86400 } = {}) {
      if (!on) return { sent: 0, why: 'no-key' };
      const rs = await Promise.all(list(uid).map((s) => post(s.env, s.token, payloadOf(msg), ttl)));
      return { sent: rs.filter((r) => r.status === 200).length, results: rs };
    },
    async wake(uid, e11 = {}) {
      if (!on) return { sent: 0 };
      const rs = await Promise.all(list(uid).map((s) => post(s.env, s.token, { aps: { 'content-available': 1 }, e11: { quiet: true, ...e11 } }, 86400, 'background', '5')));
      return { sent: rs.filter((r) => r.status === 200).length, results: rs };
    },
  };
}
