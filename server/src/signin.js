// Our own sign-in (Haris 2026-11-11; plan: project doc claude/own-sign-in-plan.md). Cloudflare Access stays in front and
// uses this server as its only sign-in provider (OpenID Connect, "Generic OIDC"): Cloudflare sends people to our page,
// we check who they are, and hand Cloudflare a signed token with their email. No email and no SMS anywhere.
//  · The email is the username. A password once set; else a 4-digit sign-in code an admin made (one use, that email only,
//    24 hours, a new one cancels the old, 5 wrong tries stop it). The first sign-in with a code opens nothing until a
//    new password is set.
//  · The owner's standing code: the owner signs in with it the first time, or whenever the owner's password isn't set or
//    is forgotten. Kept only as a hash in the NAS settings (OWNER_CODE_HASH); 5 wrong tries lock it for an hour.
//  · A password set with a code: the old one stops at once and every sign-in of that person ends, silently (tokens made
//    before then are refused — revokedBefore). If an admin made the code, the other admins are told (onCodeUsed).
//  · Passwords and codes are kept only as hashes (scrypt), in tables of their own — never in the synced data.
import crypto from 'node:crypto';
import fs from 'node:fs';

const CODE_LIFE = 24 * 3600_000, TICKET_LIFE = 15 * 60_000, AUTH_CODE_LIFE = 2 * 60_000, TOKEN_LIFE = 3600;
const MAX_TRIES = 5, PASSWORD_LOCK = 15 * 60_000, OWNER_LOCK = 3600_000, MIN_PASSWORD = 8;

// ---------- hashes ----------
export function hashSecret(secret, salt = crypto.randomBytes(16)) {
  const h = crypto.scryptSync(String(secret), salt, 32, { N: 16384, r: 8, p: 1 });
  return `scrypt$${salt.toString('base64')}$${h.toString('base64')}`;
}
export function checkSecret(secret, stored) {
  const [kind, salt, h] = String(stored || '').split('$');
  if (kind !== 'scrypt' || !salt || !h) return false;
  const want = Buffer.from(h, 'base64');
  const got = crypto.scryptSync(String(secret), Buffer.from(salt, 'base64'), want.length, { N: 16384, r: 8, p: 1 });
  return want.length === got.length && crypto.timingSafeEqual(want, got);
}
const b64u = (b) => Buffer.from(b).toString('base64url');
const rand = (n = 24) => crypto.randomBytes(n).toString('base64url');

export function createSignin({ db, now = () => Date.now(), ownerEmail = '', ownerCodeHash = '', findUser, issuer = '', clients = [], keyFile = '', onCodeUsed = () => {} }) {
  const owner = String(ownerEmail || '').toLowerCase();
  db.exec(`
    CREATE TABLE IF NOT EXISTS signin_passwords (email TEXT PRIMARY KEY, hash TEXT NOT NULL, set_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS signin_codes (id TEXT PRIMARY KEY, email TEXT NOT NULL, hash TEXT NOT NULL, made_by TEXT NOT NULL,
      by_owner INTEGER NOT NULL DEFAULT 0, made_at INTEGER NOT NULL, expires INTEGER NOT NULL, tries INTEGER NOT NULL DEFAULT 0,
      used_at INTEGER, cancelled INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS signin_state (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS signin_devices (id TEXT PRIMARY KEY, email TEXT NOT NULL, hash TEXT NOT NULL, name TEXT NOT NULL DEFAULT '',
      made_at INTEGER NOT NULL, used_at INTEGER, gone INTEGER NOT NULL DEFAULT 0);
  `);
  const q = {
    pwGet: db.prepare(`SELECT hash, set_at FROM signin_passwords WHERE email = ?`),
    pwSet: db.prepare(`INSERT INTO signin_passwords(email, hash, set_at) VALUES (?, ?, ?) ON CONFLICT(email) DO UPDATE SET hash = excluded.hash, set_at = excluded.set_at`),
    codeLive: db.prepare(`SELECT * FROM signin_codes WHERE email = ? AND used_at IS NULL AND cancelled = 0 AND expires > ? ORDER BY made_at DESC LIMIT 1`),
    codeCancel: db.prepare(`UPDATE signin_codes SET cancelled = 1 WHERE email = ? AND used_at IS NULL AND cancelled = 0`),
    codeAdd: db.prepare(`INSERT INTO signin_codes(id, email, hash, made_by, by_owner, made_at, expires) VALUES (?, ?, ?, ?, ?, ?, ?)`),
    codeTry: db.prepare(`UPDATE signin_codes SET tries = tries + 1 WHERE id = ?`),
    codeUsed: db.prepare(`UPDATE signin_codes SET used_at = ? WHERE id = ?`),
    codeGet: db.prepare(`SELECT * FROM signin_codes WHERE id = ?`),
    codesFor: db.prepare(`SELECT id, email, made_by, by_owner, made_at, expires, used_at, cancelled FROM signin_codes ORDER BY made_at DESC LIMIT ?`),
    devAdd: db.prepare(`INSERT INTO signin_devices(id, email, hash, name, made_at) VALUES (?, ?, ?, ?, ?)`),
    devGet: db.prepare(`SELECT * FROM signin_devices WHERE id = ?`),
    devUsed: db.prepare(`UPDATE signin_devices SET used_at = ? WHERE id = ?`),
    devGone: db.prepare(`UPDATE signin_devices SET gone = 1 WHERE id = ?`),
    stGet: db.prepare(`SELECT value FROM signin_state WHERE key = ?`),
    stSet: db.prepare(`INSERT INTO signin_state(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value`),
  };
  const st = { get: (k) => { const r = q.stGet.get(k); return r ? JSON.parse(r.value) : null; }, set: (k, v) => q.stSet.run(k, JSON.stringify(v)) };
  const norm = (e) => String(e || '').trim().toLowerCase();

  // ---------- who may sign in ----------
  // (on the team and not removed — the Team page decides; the owner always)
  const member = (email) => { const e = norm(email); if (e && e === owner) return findUser(e) || { email: e }; const u = findUser(e); return u && !u.removed && u.active !== false ? u : null; };

  // ---------- tries and locks (per email and what's tried) ----------
  function locked(key) { const s = st.get('lock:' + key); return s && s.until > now() ? s.until : 0; }
  function failed(key, max, lockFor) {
    const s = st.get('lock:' + key) || { n: 0, until: 0 };
    const n = (s.until && s.until <= now() ? 0 : s.n) + 1;
    st.set('lock:' + key, { n, until: n >= max ? now() + lockFor : 0 });
  }
  const cleared = (key) => st.set('lock:' + key, { n: 0, until: 0 });

  // ---------- what the first screen needs: password, code, or the owner code ----------
  function start(email) {
    const e = norm(email);
    if (!member(e)) return { ok: false, error: 'That email isn’t on the team. Check it, or ask your admin.' };
    const hasPw = !!q.pwGet.get(e);
    return { ok: true, email: e, password: hasPw, owner: e === owner && !!ownerCodeHash };
  }

  // ---------- passwords ----------
  function signInPassword(email, password) {
    const e = norm(email);
    if (!member(e)) return { ok: false, error: 'Wrong email or password.' };
    const until = locked('pw:' + e);
    if (until) return { ok: false, error: 'Too many tries. Try again in a few minutes, or use a sign-in code.', locked: until };
    const row = q.pwGet.get(e);
    if (!row || !checkSecret(password, row.hash)) { failed('pw:' + e, MAX_TRIES, PASSWORD_LOCK); return { ok: false, error: 'Wrong email or password.' }; }
    cleared('pw:' + e);
    return { ok: true, email: e };
  }

  // ---------- sign-in codes (admins and the owner make them) ----------
  function makeCode(forEmail, byEmail, { byOwner = false } = {}) {
    const e = norm(forEmail);
    if (!member(e)) return { ok: false, error: 'Not on the team' };
    const code = String(crypto.randomInt(0, 10000)).padStart(4, '0');
    const id = rand(12), at = now(), expires = at + CODE_LIFE;
    q.codeCancel.run(e);
    q.codeAdd.run(id, e, hashSecret(code), norm(byEmail), byOwner ? 1 : 0, at, expires);
    return { ok: true, code, expires, email: e, hasPassword: !!q.pwGet.get(e) };
  }
  // (the code checked: a ticket to set the new password — the code itself is used up only when the password is set)
  function useCode(email, code) {
    const e = norm(email);
    const c = member(e) ? q.codeLive.get(e, now()) : null;
    if (!c) return { ok: false, error: 'No sign-in code for this email, or it has run out. Ask your admin for a new one.' };
    if (c.tries >= MAX_TRIES) return { ok: false, error: 'Too many wrong tries — this code has stopped. Ask your admin for a new one.' };
    if (!/^\d{4}$/.test(String(code)) || !checkSecret(String(code), c.hash)) {
      q.codeTry.run(c.id);
      const left = MAX_TRIES - c.tries - 1;
      return { ok: false, error: left > 0 ? `That code isn’t right. ${left} ${left === 1 ? 'try' : 'tries'} left.` : 'Too many wrong tries — this code has stopped. Ask your admin for a new one.' };
    }
    return { ok: true, ticket: ticket({ email: e, code: c.id }) };
  }
  function useOwnerCode(email, code) {
    const e = norm(email);
    if (!owner || e !== owner || !ownerCodeHash) return { ok: false, error: 'No sign-in code for this email, or it has run out.' };
    const until = locked('owner');
    if (until) return { ok: false, error: 'Too many tries. Try again in an hour.', locked: until };
    if (!checkSecret(String(code), ownerCodeHash)) { failed('owner', MAX_TRIES, OWNER_LOCK); return { ok: false, error: 'That code isn’t right.' }; }
    cleared('owner');
    return { ok: true, ticket: ticket({ email: e, owner: true }) };
  }
  // (a short-lived ticket, signed by the server: the code was right; nothing opens until the password is set)
  const ticketKey = (() => { let k = st.get('ticketKey'); if (!k) { k = rand(32); st.set('ticketKey', k); } return k; })();
  function ticket(o) {
    const body = b64u(JSON.stringify({ ...o, exp: now() + TICKET_LIFE }));
    return body + '.' + crypto.createHmac('sha256', ticketKey).update(body).digest('base64url');
  }
  function readTicket(t) {
    const [body, sig] = String(t || '').split('.');
    if (!body || !sig) return null;
    const want = crypto.createHmac('sha256', ticketKey).update(body).digest('base64url');
    if (want.length !== sig.length || !crypto.timingSafeEqual(Buffer.from(want), Buffer.from(sig))) return null;
    const o = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    return o.exp > now() ? o : null;
  }
  function setPassword(ticketStr, password) {
    const t = readTicket(ticketStr);
    if (!t) return { ok: false, error: 'That took too long — sign in with your code again.' };
    if (String(password || '').length < MIN_PASSWORD) return { ok: false, error: `At least ${MIN_PASSWORD} characters.` };
    let c = null;
    if (t.code) {
      c = q.codeGet.get(t.code);
      if (!c || c.used_at || c.cancelled || c.expires <= now()) return { ok: false, error: 'This code has already been used or has run out. Ask your admin for a new one.' };
      q.codeUsed.run(now(), c.id);
    }
    q.pwSet.run(t.email, hashSecret(password), now());
    // (every sign-in of theirs made before now ends — silently; they sign in again with the new password. Not for the
    //  owner's standing code: it signs nothing out — the plan)
    if (!t.owner) st.set('revoked:' + t.email, now());
    cleared('pw:' + t.email);
    if (c && !c.by_owner) { try { onCodeUsed({ email: t.email, madeBy: c.made_by }); } catch { /* the sign-in still goes on */ } }
    return { ok: true, email: t.email };
  }
  // (a token made before this moment no longer counts — Cloudflare's or ours)
  const revokedBefore = (email) => Number(st.get('revoked:' + norm(email)) || 0);
  function codesRecord({ owner: ownerView = false, limit = 200 } = {}) {
    return q.codesFor.all(limit).filter((c) => ownerView || !c.by_owner).map((c) => ({ email: c.email, madeBy: c.made_by, byOwner: !!c.by_owner, madeAt: c.made_at, expires: c.expires, used: c.used_at, cancelled: !!c.cancelled }));
  }
  // (removed from the team: every sign-in stops — the Team page calls this)
  const endAll = (email) => st.set('revoked:' + norm(email), now());

  // ---------- device keys: the iPhone / Mac app signed in for good (Haris 2026-11-11) ----------
  // A key made for a signed-in app, kept in its Keychain; with Face ID / Touch ID it signs that device back in on our page
  // without a password. Stops on its own when the password is set again with a code, or the person leaves the team (a key
  // made before their sign-ins were ended counts no more); a device signed out drops its own.
  const DEVICE_SEP = '.';
  function deviceRow(key) {
    const [id, secret] = String(key || '').split(DEVICE_SEP);
    if (!id || !secret) return null;
    const d = q.devGet.get(id);
    if (!d || d.gone || !checkSecret(secret, d.hash) || !member(d.email) || d.made_at < revokedBefore(d.email)) return null;
    return d;
  }
  // (the app, signed in as email: its key still good — kept; else a new one)
  function deviceKey(email, key, name = '') {
    const e = norm(email);
    const d = deviceRow(key);
    if (d && d.email === e) return { ok: true, key, kept: true };
    if (!member(e)) return { ok: false, error: 'Not on the team' };
    const id = rand(12), secret = rand(32);
    q.devAdd.run(id, e, hashSecret(secret), String(name || '').slice(0, 80), now());
    return { ok: true, key: id + DEVICE_SEP + secret };
  }
  function useDevice(key) {
    const d = deviceRow(key);
    if (!d) return { ok: false, error: 'This device needs to sign in again.' };
    q.devUsed.run(now(), d.id);
    return { ok: true, email: d.email };
  }
  function dropDevice(key) { const d = deviceRow(key); if (d) q.devGone.run(d.id); return { ok: true }; }

  // ---------- OpenID Connect: what Cloudflare asks of its sign-in provider ----------
  // the signing key: made once, kept on the NAS (keyFile), never in chat or GitHub
  let keyPem = null;
  if (keyFile) {
    try { keyPem = fs.readFileSync(keyFile, 'utf8'); } catch {
      const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
      keyPem = privateKey.export({ type: 'pkcs8', format: 'pem' });
      fs.writeFileSync(keyFile, keyPem, { mode: 0o600 });
    }
  } else {
    keyPem = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey.export({ type: 'pkcs8', format: 'pem' });
  }
  const privateKey = crypto.createPrivateKey(keyPem), publicJwk = crypto.createPublicKey(privateKey).export({ format: 'jwk' });
  const kid = crypto.createHash('sha256').update(publicJwk.n).digest('base64url').slice(0, 16);
  const jwks = () => ({ keys: [{ ...publicJwk, kid, use: 'sig', alg: 'RS256' }] });
  const discovery = () => ({
    issuer, authorization_endpoint: issuer + '/oidc/authorize', token_endpoint: issuer + '/oidc/token', jwks_uri: issuer + '/oidc/jwks',
    userinfo_endpoint: issuer + '/oidc/userinfo', response_types_supported: ['code'], subject_types_supported: ['public'],
    id_token_signing_alg_values_supported: ['RS256'], scopes_supported: ['openid', 'email', 'profile'],
    token_endpoint_auth_methods_supported: ['client_secret_basic', 'client_secret_post'], claims_supported: ['sub', 'email', 'email_verified', 'name'],
  });
  const client = (id) => clients.find((c) => c.id === id) || null;
  const redirectOk = (c, uri) => !!c && c.redirects.includes(uri);
  function sign(payload) {
    const head = b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT', kid }));
    const body = b64u(JSON.stringify(payload));
    return `${head}.${body}.${crypto.sign('RSA-SHA256', Buffer.from(`${head}.${body}`), privateKey).toString('base64url')}`;
  }
  // (signed in: a one-use code for Cloudflare, two minutes)
  function authCode(email, { clientId, redirectUri, nonce }) {
    const code = rand(24);
    st.set('authcode:' + code, { email: norm(email), clientId, redirectUri, nonce: nonce || null, exp: now() + AUTH_CODE_LIFE });
    return code;
  }
  function exchange({ code, clientId, clientSecret, redirectUri }) {
    const c = client(clientId);
    if (!c || !clientSecret || c.secret.length !== String(clientSecret).length || !crypto.timingSafeEqual(Buffer.from(c.secret), Buffer.from(String(clientSecret)))) return { error: 'invalid_client' };
    const a = st.get('authcode:' + code);
    st.set('authcode:' + code, null);
    if (!a || a.exp <= now() || a.clientId !== clientId || a.redirectUri !== redirectUri) return { error: 'invalid_grant' };
    const u = member(a.email);
    if (!u) return { error: 'invalid_grant' };
    const t = Math.floor(now() / 1000);
    const claims = { iss: issuer, aud: clientId, sub: a.email, email: a.email, email_verified: true, name: u.name || a.email, iat: t, exp: t + TOKEN_LIFE, ...(a.nonce ? { nonce: a.nonce } : {}) };
    const access = rand(24);
    st.set('access:' + access, { email: a.email, exp: now() + TOKEN_LIFE * 1000 });
    return { id_token: sign(claims), access_token: access, token_type: 'Bearer', expires_in: TOKEN_LIFE };
  }
  function userinfo(accessToken) {
    const a = st.get('access:' + accessToken);
    if (!a || a.exp <= now()) return null;
    const u = member(a.email);
    return u ? { sub: a.email, email: a.email, email_verified: true, name: u.name || a.email } : null;
  }

  return { start, signInPassword, makeCode, useCode, useOwnerCode, setPassword, revokedBefore, codesRecord, endAll, deviceKey, useDevice, dropDevice, discovery, jwks, client, redirectOk, authCode, exchange, userinfo, readTicket };
}
