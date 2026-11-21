/* E11 Talk on Cloudflare — the office's side (TALK-CF-A, Haris 2026-11-21/22; project doc claude/talk-cloudflare-relay-plan.md).
   Talk's hub on Cloudflare (relay/, talkline.e11hq.com) runs Talk's own code (talk.js); this keeps the office's full copy
   and is its stand-in. Nothing here changes Talk on its own: until the hub has been given the office's Talk (load) the
   copy is refused, and E11 Talk works with the office exactly as before.
   - Trust, nothing on the NAS: the office makes its own Ed25519 key (kept in Talk's database, relay_meta) and publishes the
     public half (/api/talk/relay/key); the hub's comes from the hub's own address (/hub/key). Each signs what it sends:
     x-e11-ts + x-e11-sig over "METHOD\nPATH\nTS\nBODY", within 5 minutes.
   - The copy: the hub's writes, statement by statement, numbered; run here in order. A number missing → the hub's whole
     Talk is fetched (dump) and taken as it is.
   - To the hub: E11 Console's people and clients as Talk needs them (dir), and news for open chats (tell). */
import { DatabaseSync } from 'node:sqlite';
import crypto from 'node:crypto';

export const TALK_TABLES = ['groups', 'members', 'prefs', 'events', 'waiting', 'sent', 'files', 'contacts', 'macs', 'link_codes', 'phone_seen',
  'phones', 'bare_seen', 'needs', 'opts', 'unread', 'file_kept', 'file_had', 'asks'];
const SKEW = 5 * 60_000;
const SPKI_ED25519 = Buffer.from('302a300506032b6570032100', 'hex');

export function createTalkRelay({ dbFile, relayUrl = '', store, access, apns = null, unreadTell = null, fetchImpl = null, now = () => Date.now() }) {
  const go = fetchImpl || ((...a) => fetch(...a));
  const base = String(relayUrl || '').replace(/\/$/, '');
  const db = new DatabaseSync(dbFile);   // (Talk's own database — a second connection; WAL lets both work)
  db.exec('PRAGMA busy_timeout = 5000; CREATE TABLE IF NOT EXISTS relay_meta (k TEXT PRIMARY KEY, v TEXT)');
  const meta = (k, v) => {
    if (v === undefined) { const r = db.prepare('SELECT v FROM relay_meta WHERE k = ?').get(k); return r ? r.v : null; }
    db.prepare('INSERT INTO relay_meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v').run(k, v == null ? null : String(v));
  };
  // the office's own key, made once
  if (!meta('priv')) {
    const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519');
    meta('priv', privateKey.export({ type: 'pkcs8', format: 'pem' }));
    meta('pub', publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64'));
  }
  const text = (m, p, ts, body) => Buffer.from(`${m.toUpperCase()}\n${p}\n${ts}\n${body || ''}`);
  function sign(method, p, body) {
    const ts = String(now());
    return { 'x-e11-ts': ts, 'x-e11-sig': crypto.sign(null, text(method, p, ts, body), crypto.createPrivateKey(meta('priv'))).toString('base64') };
  }
  const okSig = (pub, method, p, body, h) => {
    const ts = h['x-e11-ts'], sig = h['x-e11-sig'];
    if (!pub || !ts || !sig || Math.abs(now() - Number(ts)) > SKEW) return false;
    try {
      const key = crypto.createPublicKey({ key: Buffer.concat([SPKI_ED25519, Buffer.from(pub, 'base64')]), format: 'der', type: 'spki' });
      return crypto.verify(null, text(method, p, ts, body), key, Buffer.from(sig, 'base64'));
    } catch { return false; }
  };
  async function hubKey(fresh = false) {
    let k = meta('hubKey');
    if ((!k || fresh) && base) {
      try { const r = await go(base + '/hub/key'); const j = await r.json(); if (j && j.key) { k = j.key; meta('hubKey', k); } } catch { /* the kept one */ }
    }
    return k;
  }
  // a request from the hub: signed with its key? (a new key of the hub's: fetched once more)
  async function fromHub(method, p, body, headers) {
    const h = Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), Array.isArray(v) ? v[0] : v]));
    if (okSig(await hubKey(), method, p, body, h)) return true;
    return okSig(await hubKey(true), method, p, body, h);
  }
  async function toHub(p, body) {
    if (!base) return null;
    const t = JSON.stringify(body);
    const r = await go(base + p, { method: 'POST', body: t, headers: { 'content-type': 'application/json', ...sign('POST', p, t) } });
    if (!r.ok) throw new Error('The hub said ' + r.status);
    return r.json();
  }

  // ---------- the copy ----------
  function replaceAll(tables) {
    db.exec('BEGIN');
    try {
      for (const t of TALK_TABLES) {
        const rows = tables[t]; if (!Array.isArray(rows)) continue;
        db.prepare(`DELETE FROM ${t}`).run();
        for (const r of rows) { const k = Object.keys(r); if (k.length) db.prepare(`INSERT INTO ${t} (${k.join(',')}) VALUES (${k.map(() => '?').join(',')})`).run(...k.map((x) => r[x])); }
      }
      db.exec('COMMIT');
    } catch (e) { db.exec('ROLLBACK'); throw e; }
  }
  let resyncing = null;
  async function resync() {
    if (resyncing) return resyncing;
    resyncing = (async () => {
      const r = await toHub('/office/dump', {});
      if (!r || !r.ok || !r.tables) throw new Error('No copy from the hub');
      replaceAll(r.tables); meta('lastN', r.n); meta('resyncAt', now());
      return r.n;
    })().finally(() => { resyncing = null; });
    return resyncing;
  }
  // the hub's batches, in order; one already here is skipped; one missing → the whole of it again
  function copy(batches) {
    if (meta('linked') !== '1') return { ok: false, error: 'Not linked yet', status: 409 };
    let last = Number(meta('lastN') || 0), done = 0;
    for (const b of [...(batches || [])].sort((x, y) => x.n - y.n)) {
      if (b.n <= last) continue;
      if (b.n !== last + 1) { resync().catch((e) => console.error('talk relay resync:', e.message)); return { ok: true, gap: true, last }; }
      db.exec('BEGIN');
      try { for (const [q, v] of b.stmts || []) db.prepare(q).run(...(v || [])); meta('lastN', b.n); db.exec('COMMIT'); }
      catch (e) { db.exec('ROLLBACK'); resync().catch((x) => console.error('talk relay resync:', x.message)); return { ok: true, gap: true, last, error: e.message }; }
      last = b.n; done += 1;
    }
    return { ok: true, last, done };
  }
  // moving the office's Talk to the hub, once (step 2 — the switch-over): the hub takes it all, the copy starts at 0
  async function load() {
    const tables = {};
    for (const t of TALK_TABLES) tables[t] = db.prepare(`SELECT * FROM ${t}`).all();
    const r = await toHub('/office/load', { n: 0, tables });
    if (!r || !r.ok) throw new Error((r && r.error) || 'The hub didn’t take it');
    meta('lastN', 0); meta('linked', '1'); meta('linkedAt', now());
    return { ok: true, rows: Object.values(tables).reduce((a, x) => a + x.length, 0) };
  }

  // ---------- E11 Console's people and clients, as Talk needs them ----------
  function dir() {
    const users = store.list('users').map((u) => ({ id: u.id, name: u.name || null, email: u.email || null, role: u.role || null, title: u.title || null,
      avatar: u.avatar || null, color: u.color || null, active: u.active !== false, ...(u.away ? { away: u.away } : {}) }));
    const projects = store.list('projects').map((p) => ({ id: p.id, name: p.name, color: p.color || null, clientId: p.clientId || null, ...(p.inactive ? { inactive: true } : {}) }));
    const clients = store.list('clients').map((c) => ({ id: c.id, name: c.name || null, logo: c.logo || null }));
    const m = store.get('meta', 'main') || {};
    const flags = {}, see = {};
    for (const u of store.list('users')) {
      if (u.active === false) continue;
      flags[u.id] = { free: !!access.isFreelancer(u), super: !!access.isSuper(u), office: !!access.isOffice(u) };
      see[u.id] = store.list('projects').filter((p) => access.canSee(u, 'projects', p)).map((p) => String(p.id));
    }
    return { users, projects, clients, meta: { cdUserId: m.cdUserId || null, socialMgrIds: m.socialMgrIds || [] }, flags, see };
  }
  let dirTimer = null;
  const sendDir = () => toHub('/office/dir', { dir: dir() }).catch(() => null);
  // (a burst of changes: one send, two seconds later)
  function dirSoon() { if (!base || dirTimer) return; dirTimer = setTimeout(() => { dirTimer = null; sendDir(); }, 2000); dirTimer.unref?.(); }
  const tell = (ev, data = {}) => (base ? toHub('/office/tell', { ev, ...data }).catch(() => null) : null);

  // ---------- what the hub asks of the office ----------
  async function push(b) {
    if (!apns || !apns.enabled() || !b || !b.uid || !b.p) return { ok: true, sent: false };
    if (b.wake) { if (apns.wake) await apns.wake(String(b.uid), b.p).catch(() => {}); } else await apns.sendTo(String(b.uid), b.p).catch(() => {});
    return { ok: true, sent: true };
  }
  function unread(b) { if (unreadTell && Array.isArray(b && b.uids)) unreadTell(b.uids.map(String)); return { ok: true }; }

  return { publicKey: () => meta('pub'), fromHub, copy, resync, load, dir, sendDir, dirSoon, tell, push, unread, sign, linked: () => meta('linked') === '1',
    lastN: () => Number(meta('lastN') || 0), close: () => { clearTimeout(dirTimer); db.close(); } };
}
