/* E11 Talk on Cloudflare — the office's side (TALK-CF-A, Haris 2026-11-21/22; project doc claude/talk-cloudflare-relay-plan.md).
   Talk's hub on Cloudflare (relay/, talkline.e11hq.com) runs Talk's own code (talk.js). The office keeps a full copy and
   is the stand-in. Who's in charge of Talk — one place at a time (relay_meta "mode"):
   - office    (until the switch-over): the office, exactly as before. The hub refuses phones.
   - switching (a few seconds): Talk's data going to the hub; Talk asks phones to wait a moment.
   - hub       (after it): the hub. The office's own Talk only reads (Console's count, older apps' live line); older Talk
               apps that still ask the office are passed through to the hub; the hub's writes arrive here as the copy.
   - takeover  (the hub refuses — a free limit, TALK-CF-A — or can't be reached): the office answers as before; every 10
               minutes it tries to hand Talk back — its whole Talk, as at the switch-over — then the hub again.
   Trust, nothing on the NAS: each side makes its own Ed25519 key (here: Talk's database) and fetches the other's public
   key from the other's own address; each signs what it sends (x-e11-ts, x-e11-sig over "METHOD\nPATH\nTS\nBODY", 5 min). */
import { DatabaseSync } from 'node:sqlite';
import crypto from 'node:crypto';

export const TALK_TABLES = ['groups', 'members', 'prefs', 'events', 'waiting', 'sent', 'files', 'contacts', 'macs', 'link_codes', 'phone_seen',
  'phones', 'bare_seen', 'needs', 'opts', 'unread', 'file_kept', 'file_had', 'asks'];
// what older Talk apps ask the office that the hub answers (the rest — notifications, the live line, Macs — stay here)
const RELAYED = /^\/api\/talk\/(state|act|sync|ack|got|r2\/start|r2\/done|ask|asks|resend\/start|history\/share|file\/.+)$/;
const SKEW = 5 * 60_000, BACK_EVERY = 10 * 60_000;
const SPKI_ED25519 = Buffer.from('302a300506032b6570032100', 'hex');
const writes = (q) => !/^\s*(SELECT|PRAGMA)\b/i.test(q);
// the hub saying it can't take more today (Cloudflare's free limit) — or not answering at all
const refused = (status, text) => status === 429 || status === 503 || /\b1027\b|exceeded|limit/i.test(String(text || '').slice(0, 400));

export function createTalkRelay({ dbFile, relayUrl = '', store, access, apns = null, unreadTell = null, fetchImpl = null, now = () => Date.now() }) {
  const go = fetchImpl || ((...a) => fetch(...a));
  const base = String(relayUrl || '').replace(/\/$/, '');
  const raw = new DatabaseSync(dbFile);
  raw.exec('PRAGMA busy_timeout = 5000; CREATE TABLE IF NOT EXISTS relay_meta (k TEXT PRIMARY KEY, v TEXT)');
  const meta = (k, v) => {
    if (v === undefined) { const r = raw.prepare('SELECT v FROM relay_meta WHERE k = ?').get(k); return r ? r.v : null; }
    raw.prepare('INSERT INTO relay_meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v').run(k, v == null ? null : String(v));
  };
  let mode = meta('mode') || 'office';
  const setMode = (m) => { mode = m; meta('mode', m); meta('modeAt', now()); };
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

  // ---------- Talk's own database, as talk.js gets it ----------
  // office / takeover: as always · switching / hub: Talk here only reads (its own writes would make it differ from the
  // hub's — the copy keeps it the same)
  const quiet = (q) => (mode === 'hub' || mode === 'switching') && writes(q);
  const talkDb = {
    exec: (t) => { if (mode === 'office' || mode === 'takeover' || !/\b(INSERT|UPDATE|DELETE)\b/i.test(t)) raw.exec(t); },
    prepare(q) {
      const st = raw.prepare(q);
      return {
        get: (...a) => { if (quiet(q)) return undefined; return st.get(...a); },
        all: (...a) => { if (quiet(q)) return []; return st.all(...a); },
        run: (...a) => { if (quiet(q)) return { changes: 0, lastInsertRowid: 0 }; return st.run(...a); },
      };
    },
    close() {},
  };

  // ---------- the copy (the hub's writes, run here in order) ----------
  function replaceAll(tables) {
    raw.exec('BEGIN');
    try {
      for (const t of TALK_TABLES) {
        const rows = tables[t]; if (!Array.isArray(rows)) continue;
        raw.prepare(`DELETE FROM ${t}`).run();
        for (const r of rows) { const k = Object.keys(r); if (k.length) raw.prepare(`INSERT INTO ${t} (${k.join(',')}) VALUES (${k.map(() => '?').join(',')})`).run(...k.map((x) => r[x])); }
      }
      raw.exec('COMMIT');
    } catch (e) { raw.exec('ROLLBACK'); throw e; }
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
  // older apps' live line here: told there's something new as the copy brings it
  const lines = new Map();
  function listen(devId, res) {
    if (!lines.has(devId)) lines.set(devId, new Set());
    lines.get(devId).add(res);
    return () => { const s = lines.get(devId); if (s) { s.delete(res); if (!s.size) lines.delete(devId); } };
  }
  function nudge(stmts) {
    for (const [q, v] of stmts) {
      if (!/INSERT\s+(OR\s+IGNORE\s+)?INTO\s+waiting\s*\(seq,\s*uid\)\s*VALUES/i.test(q)) continue;
      for (const res of lines.get(String(v[1])) || []) { try { res.write(`event: talk\ndata: ${JSON.stringify({ seq: v[0] })}\n\n`); } catch { /* closed */ } }
    }
  }
  function copy(batches) {
    // (only while the hub has Talk — before the switch-over, or while the office has taken over, it waits: the hub keeps it,
    //  and the office's whole Talk replaces the hub's when it hands back)
    if (meta('linked') !== '1' || mode !== 'hub') return { ok: false, error: 'Not now', status: 409 };
    let last = Number(meta('lastN') || 0), done = 0;
    for (const b of [...(batches || [])].sort((x, y) => x.n - y.n)) {
      if (b.n <= last) continue;
      if (b.n !== last + 1) { resync().catch((e) => console.error('talk relay resync:', e.message)); return { ok: true, gap: true, last }; }
      raw.exec('BEGIN');
      try { for (const [q, v] of b.stmts || []) raw.prepare(q).run(...(v || [])); meta('lastN', b.n); raw.exec('COMMIT'); }
      catch (e) { raw.exec('ROLLBACK'); resync().catch((x) => console.error('talk relay resync:', x.message)); return { ok: true, gap: true, last, error: e.message }; }
      last = b.n; done += 1;
      nudge(b.stmts || []);
    }
    return { ok: true, last, done };
  }

  // ---------- the switch-over, and back ----------
  async function load() {
    const tables = {};
    for (const t of TALK_TABLES) tables[t] = raw.prepare(`SELECT * FROM ${t}`).all();
    const r = await toHub('/office/load', { n: 0, tables });
    if (!r || !r.ok) throw new Error((r && r.error) || 'The hub didn’t take it');
    meta('lastN', 0); meta('linked', '1'); meta('linkedAt', now());
    return { ok: true, rows: Object.values(tables).reduce((a, x) => a + x.length, 0) };
  }
  // the owner's button: Talk to the hub (to = 'hub') — or back to the office for good (to = 'office': the hub's latest taken)
  async function switchTo(to) {
    if (to === 'hub') {
      if (mode === 'hub') return { ok: true, mode };
      setMode('switching');
      try { const r = await load(); setMode('hub'); return { ...r, mode }; } catch (e) { setMode('office'); return { ok: false, error: e.message, mode }; }
    }
    if (to === 'office') {
      if (mode === 'office') return { ok: true, mode };
      const was = mode;
      setMode('switching');
      try { if (was === 'hub') await resync(); setMode('office'); meta('linked', '0'); return { ok: true, mode }; } catch (e) { setMode(was); return { ok: false, error: e.message, mode }; }
    }
    return { ok: false, error: 'hub or office' };
  }
  // the hub refused or can't be reached: the office answers, keeping what it writes
  function takeOver(why) { if (mode !== 'hub') return; setMode('takeover'); meta('takeoverWhy', String(why || '').slice(0, 200)); console.error('talk relay: the office takes over —', why); }
  // every 10 minutes while the office has it: its whole Talk to the hub (as at the switch-over); the hub again
  let handing = null;
  async function handBack() {
    if (mode !== 'takeover' || handing) return handing;
    handing = (async () => {
      try { await load(); setMode('hub'); return true; } catch { return false; }
    })().finally(() => { handing = null; });
    return handing;
  }
  const backTimer = setInterval(() => { handBack().catch(() => {}); }, BACK_EVERY); backTimer.unref?.();

  // older apps asking the office: passed to the hub (true: answered). Not: the office answers itself (false).
  async function pass(req, res, p, url) {
    if (mode === 'office' || mode === 'takeover' || !RELAYED.test(p) || !base) return false;
    if (mode === 'switching') { res.writeHead(503, { 'Content-Type': 'application/json', 'Retry-After': '3' }); res.end(JSON.stringify({ ok: false, error: 'One moment — E11 Talk is moving' })); return true; }
    let body = null;
    if (req.method === 'POST') { const parts = []; for await (const c of req) parts.push(c); body = Buffer.concat(parts); req.relayBody = body; }
    const h = { accept: 'application/json' };
    for (const k of ['cookie', 'x-talk-device', 'content-type', 'range']) if (req.headers[k]) h[k] = req.headers[k];
    let r, t = '';
    try {
      r = await go(base + p + (url.search || ''), { method: req.method, headers: h, body, redirect: 'manual' });
      if (r.status !== 302) t = await r.text();
    } catch (e) { takeOver('the hub can’t be reached: ' + e.message); return false; }
    if (refused(r.status, t) && r.status !== 409) { takeOver(`the hub refused (${r.status})`); return false; }
    const out = { 'Content-Type': r.headers.get('content-type') || 'application/json', 'Cache-Control': 'no-store' };
    if (r.status === 302) { res.writeHead(302, { Location: r.headers.get('location'), 'Cache-Control': 'no-store' }); res.end(); return true; }
    res.writeHead(r.status, out); res.end(t);
    return true;
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
  function dirSoon() { if (!base || dirTimer) return; dirTimer = setTimeout(() => { dirTimer = null; sendDir(); }, 2000); dirTimer.unref?.(); }
  const tell = (ev, data = {}) => (base ? toHub('/office/tell', { ev, ...data }).catch(() => null) : null);

  // ---------- what the hub asks of the office ----------
  async function push(b) {
    if (!apns || !apns.enabled() || !b || !b.uid || !b.p) return { ok: true, sent: false };
    if (b.wake) { if (apns.wake) await apns.wake(String(b.uid), b.p).catch(() => {}); } else await apns.sendTo(String(b.uid), b.p).catch(() => {});
    return { ok: true, sent: true };
  }
  function unread(b) { if (unreadTell && Array.isArray(b && b.uids)) unreadTell(b.uids.map(String)); return { ok: true }; }

  return { db: talkDb, publicKey: () => meta('pub'), mode: () => mode, fromHub, copy, resync, load, switchTo, takeOver, handBack, pass, listen,
    dir, sendDir, dirSoon, tell, push, unread, sign, linked: () => meta('linked') === '1', lastN: () => Number(meta('lastN') || 0),
    status: () => ({ mode, linked: meta('linked') === '1', lastN: Number(meta('lastN') || 0), modeAt: Number(meta('modeAt') || 0) || null, takeoverWhy: mode === 'takeover' ? meta('takeoverWhy') : null }),
    close: () => { clearTimeout(dirTimer); clearInterval(backTimer); raw.close(); } };
}
