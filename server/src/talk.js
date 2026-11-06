/* E11 Talk (the chat app — project doc claude/client-groups-app-idea.md), the server's side. Stage 1 (Haris 2026-11-06):
   staff, groups under clients, built on the test server first.

   WhatsApp's way: messages live on the phones. The server keeps only the accounts' groups (who's in which, admins,
   pins, mutes) and passes everything else on — a message (and its photo / file) is held until every member's phone
   has it, then deleted; one never picked up goes after 30 days. Everything that happens in a group is an "event"
   (a message, an edit, a delete, a reaction, read up to here, the group changed) with a number (seq); each person
   has the events addressed to them waiting until their phone says it has them (ack).

   Its own database (db/talk.sqlite) — nothing of it goes into E11 Console's store or its live updates. */
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const KEEP_MS = 30 * 86400000;          // never picked up: gone after 30 days
const IDLE_MS = 90 * 86400000;          // a group with no new messages for 90 days is deleted (Haris 2026-11-05)
const EDIT_MS = 15 * 60000;             // edit your own message: 15 minutes (as WhatsApp)
const DEL_ALL_MS = 2 * 86400000;        // delete for everyone: about 2 days
const MAX_PINS = 5;
const FILE_MAX = 2 * 1024 * 1024 * 1024; // 2 GB a file (pieces of up to 8 MB)
const LINK_MS = 2 * 60000;               // a Mac's linking code: 2 minutes (Haris 2026-11-05)
const PHONE_MS = 30 * 86400000;         // a linked Mac goes when its phone hasn't opened E11 Talk for 30 days
const rid = (p) => p + '-' + crypto.randomBytes(8).toString('hex');
const clip = (s, n) => String(s == null ? '' : s).slice(0, n);

export function createTalk({ dataDir, store, access, apns = null, now = () => Date.now(), dbFile }) {
  const file = dbFile || path.join(dataDir, 'db', 'talk.sqlite');
  if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
  const relay = path.join(dataDir, 'talk-relay');
  fs.mkdirSync(relay, { recursive: true });
  const db = new DatabaseSync(file);
  db.exec(`
    PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA busy_timeout = 5000;
    CREATE TABLE IF NOT EXISTS groups (id TEXT PRIMARY KEY, client TEXT NOT NULL, name TEXT NOT NULL, creator TEXT NOT NULL,
      second TEXT, extra TEXT NOT NULL DEFAULT '[]', creator_off INTEGER NOT NULL DEFAULT 0, pic TEXT, created_at INTEGER NOT NULL, last_at INTEGER NOT NULL, gone INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS members (grp TEXT NOT NULL, uid TEXT NOT NULL, added_at INTEGER NOT NULL, added_by TEXT, PRIMARY KEY (grp, uid));
    CREATE TABLE IF NOT EXISTS prefs (uid TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, pinned_at INTEGER, muted_until INTEGER, PRIMARY KEY (uid, kind, id));
    CREATE TABLE IF NOT EXISTS events (seq INTEGER PRIMARY KEY AUTOINCREMENT, grp TEXT NOT NULL, type TEXT NOT NULL, data TEXT NOT NULL, at INTEGER NOT NULL, by TEXT);
    CREATE TABLE IF NOT EXISTS waiting (seq INTEGER NOT NULL, uid TEXT NOT NULL, PRIMARY KEY (seq, uid));
    CREATE INDEX IF NOT EXISTS waiting_uid ON waiting(uid, seq);
    CREATE TABLE IF NOT EXISTS sent (id TEXT PRIMARY KEY, grp TEXT NOT NULL, by TEXT NOT NULL, at INTEGER NOT NULL, files TEXT NOT NULL DEFAULT '[]');
    CREATE TABLE IF NOT EXISTS files (id TEXT PRIMARY KEY, by TEXT NOT NULL, name TEXT NOT NULL, size INTEGER NOT NULL DEFAULT 0, done INTEGER NOT NULL DEFAULT 0, at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS contacts (id TEXT PRIMARY KEY, email TEXT NOT NULL, name TEXT NOT NULL, client TEXT NOT NULL, by TEXT, at INTEGER NOT NULL, gone INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS macs (id TEXT PRIMARY KEY, uid TEXT NOT NULL, name TEXT NOT NULL, linked_at INTEGER NOT NULL, seen_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS link_codes (code TEXT PRIMARY KEY, uid TEXT NOT NULL, name TEXT NOT NULL, at INTEGER NOT NULL, mac TEXT);
    CREATE TABLE IF NOT EXISTS phone_seen (uid TEXT PRIMARY KEY, at INTEGER NOT NULL);
  `);
  const q = (sql) => db.prepare(sql);
  const Q = {
    group: q('SELECT * FROM groups WHERE id = ? AND gone = 0'),
    groupsOf: q('SELECT g.* FROM groups g JOIN members m ON m.grp = g.id WHERE m.uid = ? AND g.gone = 0'),
    members: q('SELECT uid, added_at FROM members WHERE grp = ?'),
    isMember: q('SELECT 1 FROM members WHERE grp = ? AND uid = ?'),
    addMember: q('INSERT OR IGNORE INTO members (grp, uid, added_at, added_by) VALUES (?, ?, ?, ?)'),
    dropMember: q('DELETE FROM members WHERE grp = ? AND uid = ?'),
    newGroup: q('INSERT INTO groups (id, client, name, creator, second, extra, pic, created_at, last_at) VALUES (?, ?, ?, ?, NULL, \'[]\', NULL, ?, ?)'),
    setGroup: q('UPDATE groups SET name = ?, second = ?, extra = ?, pic = ?, creator = ?, last_at = ? WHERE id = ?'),
    touch: q('UPDATE groups SET last_at = ? WHERE id = ?'),
    goneGroup: q('UPDATE groups SET gone = 1 WHERE id = ?'),
    prefs: q('SELECT kind, id, pinned_at, muted_until FROM prefs WHERE uid = ?'),
    pref: q('SELECT pinned_at, muted_until FROM prefs WHERE uid = ? AND kind = ? AND id = ?'),
    setPin: q('INSERT INTO prefs (uid, kind, id, pinned_at) VALUES (?, ?, ?, ?) ON CONFLICT(uid, kind, id) DO UPDATE SET pinned_at = excluded.pinned_at'),
    setMute: q('INSERT INTO prefs (uid, kind, id, muted_until) VALUES (?, \'group\', ?, ?) ON CONFLICT(uid, kind, id) DO UPDATE SET muted_until = excluded.muted_until'),
    pinsOf: q('SELECT id FROM prefs WHERE uid = ? AND kind = ? AND pinned_at IS NOT NULL ORDER BY pinned_at'),
    addEvent: q('INSERT INTO events (grp, type, data, at, by) VALUES (?, ?, ?, ?, ?)'),
    wait: q('INSERT OR IGNORE INTO waiting (seq, uid) VALUES (?, ?)'),
    pending: q('SELECT e.seq, e.grp, e.type, e.data, e.at, e.by FROM waiting w JOIN events e ON e.seq = w.seq WHERE w.uid = ? AND w.seq > ? ORDER BY w.seq LIMIT ?'),
    ack: q('DELETE FROM waiting WHERE uid = ? AND seq <= ?'),
    lastSeq: q('SELECT MAX(seq) AS s FROM events'),
    orphanEvents: q('SELECT seq FROM events WHERE seq NOT IN (SELECT seq FROM waiting)'),
    dropEvent: q('DELETE FROM events WHERE seq = ?'),
    oldEvents: q('SELECT seq FROM events WHERE at < ?'),
    dropWaiting: q('DELETE FROM waiting WHERE seq = ?'),
    putSent: q('INSERT OR REPLACE INTO sent (id, grp, by, at, files) VALUES (?, ?, ?, ?, ?)'),
    getSent: q('SELECT * FROM sent WHERE id = ?'),
    oldSent: q('SELECT id, files FROM sent WHERE at < ?'),
    dropSent: q('DELETE FROM sent WHERE id = ?'),
    newFile: q('INSERT INTO files (id, by, name, size, done, at) VALUES (?, ?, ?, 0, 0, ?)'),
    getFile: q('SELECT * FROM files WHERE id = ?'),
    growFile: q('UPDATE files SET size = ?, done = ? WHERE id = ?'),
    dropFile: q('DELETE FROM files WHERE id = ?'),
    oldFiles: q('SELECT id FROM files WHERE at < ?'),
    fileInUse: q('SELECT 1 FROM events WHERE data LIKE ? LIMIT 1'),
  };

  // ---------- people and clients (from E11 Console) ----------
  const userOf = (id) => store.get('users', String(id));
  const active = (u) => !!u && u.active !== false;
  const isFree = (u) => access.isFreelancer(u);
  const isBoss = (u) => access.isSuper(u) || access.isOffice(u);   // Super Admins and Office Admins
  const ROLE = { admin: 'Admin', office_admin: 'Office Admin', account_manager: 'Account Manager', production: 'Production', social: 'Social',
    freelancer: 'Freelancer', finance_admin: 'Finance', finance_viewer: 'Finance' };
  const cdId = () => (store.get('meta', 'main') || {}).cdUserId || null;
  function roleOf(u) {
    if (!u) return '';
    if (u.id === cdId()) return 'Creative Director';
    if (u.title) return String(u.title);
    return access.isSuper(u) ? (u.role === 'admin' ? 'Super Admin' : ROLE[u.role] || 'Admin') : ROLE[u.role] || '';
  }
  const personOf = (u) => ({ id: u.id, name: u.name || u.email, role: roleOf(u), photo: u.avatar || null, color: u.color || null });
  // a client = a client of E11 Console (its Clients list), with its Client Assets logo when it has one
  function clientsFor(u) {
    return store.list('projects').filter((p) => !p.inactive && access.canSee(u, 'projects', p)).map((p) => {
      const c = p.clientId ? store.get('clients', String(p.clientId)) : null;
      return { id: p.id, name: p.name, color: p.color || null, logo: (c && c.logo) || null };
    });
  }
  const clientById = (id) => { const p = store.get('projects', String(id)); return p && !p.inactive ? p : null; };

  /* ---------- client contacts (stage 3, Haris 2026-11-05): added by Super Admins and Office Admins — a name, an email and
     the client they belong to (several per client). A contact exists in E11 Talk only: signs in with that email's code,
     sees only the groups they're added to (under their own client), never "Seen by"; every E11 Console page and file
     refuses them. Removed: gone from every group and signed out at once. ---------- */
  const isContactId = (id) => String(id || '').startsWith('k-');
  const isContact = (u) => !!u && u.contact === true;
  const contactRow = (id) => db.prepare('SELECT * FROM contacts WHERE id = ? AND gone = 0').get(String(id || ''));
  function contactByEmail(email) {
    const r = db.prepare('SELECT * FROM contacts WHERE lower(email) = lower(?) AND gone = 0').get(String(email || ''));
    if (!r || !clientById(r.client)) return null;
    return { id: r.id, email: r.email, name: r.name, contact: true, client: r.client, role: 'contact', active: true };
  }
  function personOfId(id) {
    if (isContactId(id)) {
      const r = db.prepare('SELECT * FROM contacts WHERE id = ?').get(String(id));
      if (!r) return null;
      const c = clientById(r.client);
      return { id: r.id, name: r.name, role: c ? c.name : 'Client', photo: null, color: null, contact: true, client: r.client, ...(r.gone ? { gone: true } : {}) };
    }
    const x = userOf(id);
    return x ? { ...personOf(x), ...(active(x) ? {} : { gone: true }) } : null;
  }

  // ---------- groups ----------
  const extra = (g) => { try { return JSON.parse(g.extra || '[]'); } catch { return []; } };
  // admins: the creator (unless a Super / Office Admin took it away), the one second admin, and Super / Office Admins who made themselves admin
  const adminsOf = (g) => [...new Set([g.creator_off ? null : g.creator, g.second, ...extra(g)].filter(Boolean))];
  const isAdmin = (u, g) => adminsOf(g).includes(u.id);
  const member = (g, uid) => !!Q.isMember.get(g.id, uid);
  const canManage = (u, g) => isAdmin(u, g) || isBoss(u);   // picture, name, add / remove people, delete
  const memberIds = (g) => Q.members.all(g.id).map((m) => m.uid);
  const withClient = (g) => memberIds(g).some(isContactId);
  const staffIds = (g) => memberIds(g).filter((id) => !isContactId(id));
  function groupView(g, uid) {
    const ms = Q.members.all(g.id);
    const pref = Q.pref.get(uid, 'group', g.id) || {};
    return { id: g.id, client: g.client, name: g.name, creator: g.creator, creatorAdmin: !g.creator_off, second: g.second || null, admins: adminsOf(g), pic: g.pic || null,
      createdAt: g.created_at, lastAt: g.last_at, members: ms.map((m) => m.uid), pinnedAt: pref.pinned_at || null, mutedUntil: pref.muted_until || null,
      withClient: ms.some((m) => isContactId(m.uid)) };
  }
  // everything the app needs to draw its lists (the messages themselves come by sync)
  function state(u) {
    const groups = Q.groupsOf.all(u.id).filter((g) => clientById(g.client)).map((g) => groupView(g, u.id))
      .filter((g) => !isContact(u) || g.client === u.client);
    const ids = new Set([u.id]);
    groups.forEach((g) => g.members.forEach((m) => ids.add(m)));
    const pins = { groups: Q.pinsOf.all(u.id, 'group').map((r) => r.id), clients: Q.pinsOf.all(u.id, 'client').map((r) => r.id), clientGroups: Q.pinsOf.all(u.id, 'cgroup').map((r) => r.id) };
    // a client contact: their own client, their groups and the people in them — nothing else
    if (isContact(u)) {
      const c = clientById(u.client);
      const people = [...ids].map(personOfId).filter(Boolean);
      return { ok: true, me: { id: u.id, name: u.name, role: c ? c.name : 'Client', photo: null, color: null, contact: true, client: u.client, canMake: false, boss: false },
        clients: c ? [{ id: c.id, name: c.name, color: c.color || null, logo: ((c.clientId && store.get('clients', String(c.clientId))) || {}).logo || null }] : [], groups, people, pins, seq: Q.lastSeq.get().s || 0 };
    }
    // people who can be added (staff — freelancers too), and the client contacts in my groups
    const people = store.list('users').filter(active).map(personOf);
    const known = new Set(people.map((p) => p.id));
    for (const id of ids) if (!known.has(id)) { const x = personOfId(id); if (x) people.push(isContactId(id) ? x : { ...x, gone: true }); }
    const out = { ok: true, me: { ...personOf(u), canMake: !isFree(u), boss: isBoss(u) }, clients: clientsFor(u), groups, people, pins, seq: Q.lastSeq.get().s || 0,
      macs: macsOf(u.id).map((m) => ({ id: m.id, name: m.name, linkedAt: m.linked_at, seenAt: m.seen_at })) };
    // Super Admins and Office Admins: every client contact (to add them, or to a group)
    if (isBoss(u)) {
      const count = db.prepare('SELECT COUNT(*) AS n FROM members m JOIN groups g ON g.id = m.grp WHERE m.uid = ? AND g.gone = 0');
      out.contacts = db.prepare('SELECT * FROM contacts WHERE gone = 0 ORDER BY name').all().filter((r) => clientById(r.client))
        .map((r) => ({ id: r.id, name: r.name, email: r.email, client: r.client, groups: count.get(r.id).n }));
    }
    return out;
  }

  // ---------- events: addressed, kept until picked up ----------
  const listeners = new Map();   // uid -> Set of live streams
  function emit(g, type, data, by, to = memberIds(g)) {
    const at = now();
    const r = Q.addEvent.run(g.id, type, JSON.stringify(data), at, by || null);
    const seq = Number(r.lastInsertRowid);
    for (const uid of devicesFor(to, by)) waitFor(seq, uid);
    return seq;
  }
  // ---------- linked Macs (Haris 2026-11-05: "as WhatsApp links a computer") ----------
  // A linked Mac is a device of its person: it gets everything its person gets — and what its person does elsewhere —
  // each kept until that Mac has it, like a phone. Its id ("mac-…") stands in the waiting list beside the people.
  const macsOf = (uid) => db.prepare('SELECT * FROM macs WHERE uid = ?').all(String(uid));
  const isMacId = (id) => String(id || '').startsWith('mac-');
  function devicesFor(to, by) {
    const out = new Set(to);
    for (const uid of new Set([...to, ...(by ? [by] : [])])) if (!isMacId(uid)) for (const m of macsOf(uid)) out.add(m.id);
    return out;
  }
  function waitFor(seq, id) {
    Q.wait.run(seq, id);
    for (const s of listeners.get(id) || []) { try { s.write(`event: talk\ndata: ${JSON.stringify({ seq })}\n\n`); } catch { /* closed */ } }
  }
  // the Mac asks for a code to show (as its signed-in person): one use, gone after 2 minutes
  function linkCode(u, name) {
    const t = now();
    db.prepare('DELETE FROM link_codes WHERE at < ?').run(t - LINK_MS * 5);
    const code = crypto.randomBytes(12).toString('base64url');
    db.prepare('INSERT INTO link_codes (code, uid, name, at) VALUES (?, ?, ?, ?)').run(code, u.id, clip(name || 'Mac', 60), t);
    return { ok: true, code, expiresAt: t + LINK_MS };
  }
  // the Mac waits for its phone: linked (its id), or the code ran out
  function linkStatus(u, code) {
    const r = db.prepare('SELECT * FROM link_codes WHERE code = ? AND uid = ?').get(String(code || ''), u.id);
    if (!r) return { ok: true, expired: true };
    if (r.mac) { db.prepare('DELETE FROM link_codes WHERE code = ?').run(r.code); return { ok: true, mac: r.mac }; }
    return { ok: true, expired: now() - r.at > LINK_MS };
  }
  function unlinkMac(id, why = 'unlinked', tidy = true) {
    const m = db.prepare('SELECT * FROM macs WHERE id = ?').get(String(id || ''));
    if (!m) return false;
    for (const s of listeners.get(m.id) || []) { try { s.write(`event: unlinked\ndata: ${JSON.stringify({ why })}\n\n`); s.end(); } catch { /* closed */ } }
    db.prepare('DELETE FROM macs WHERE id = ?').run(m.id);
    db.prepare('DELETE FROM waiting WHERE uid = ?').run(m.id);
    if (tidy) sweep();
    return true;
  }
  // a request from a linked Mac: its person must be the one signed in on that Mac — anyone else, and the link is gone
  function macFor(u, id) {
    const m = db.prepare('SELECT * FROM macs WHERE id = ?').get(String(id || ''));
    if (!m) return null;
    if (m.uid !== u.id) { unlinkMac(m.id, 'someone else signed in'); return null; }
    db.prepare('UPDATE macs SET seen_at = ? WHERE id = ?').run(now(), m.id);
    return { ...u, id: m.id, person: u.id };
  }
  // the phone was here (the 30-day rule)
  const phoneSeen = (u) => { if (!isMacId(u.id)) db.prepare('INSERT INTO phone_seen (uid, at) VALUES (?, ?) ON CONFLICT(uid) DO UPDATE SET at = excluded.at').run(u.id, now()); };
  // the phone hands its chats (the last 90 days) to a Mac it just linked: one event for that Mac only, kept (with the
  // files it names) until the Mac has picked it up
  function history(u, macId, groups, files) {
    const m = db.prepare('SELECT * FROM macs WHERE id = ? AND uid = ?').get(String(macId || ''), u.id);
    if (!m) return bad('That Mac isn’t linked any more', 404);
    const mine = new Set(Q.groupsOf.all(u.id).map((g) => g.id));
    const gs = (Array.isArray(groups) ? groups : []).filter((g) => g && mine.has(String(g.group)));
    const fs2 = (Array.isArray(files) ? files : []).map(String).filter((id) => { const f = Q.getFile.get(id); return f && f.done; });
    const r = Q.addEvent.run('-', 'history', JSON.stringify({ groups: gs, files: fs2 }), now(), u.id);
    waitFor(Number(r.lastInsertRowid), m.id);
    return { ok: true, groups: gs.length, files: fs2.length };
  }
  // which of the phone's files the server still has (the rest the phone sends again, under the same id)
  function hasFiles(u, ids) {
    return { ok: true, have: (Array.isArray(ids) ? ids : []).map(String).filter((id) => { const f = Q.getFile.get(id); return f && f.done; }) };
  }
  function resend(u, id, name, offset, bytes, last) {
    id = String(id || '');
    if (!/^f-[0-9a-f]{16}$/.test(id)) return bad('Not a file');
    let f = Q.getFile.get(id);
    if (!f) { Q.newFile.run(id, u.id, clip(name || 'File', 200).replace(/[\\/]/g, '-'), now()); fs.writeFileSync(path.join(relay, id), ''); f = Q.getFile.get(id); }
    if (f.done) return { ok: true, id, size: f.size, done: true };
    if (f.by !== u.id) return bad('Not yours', 403);
    return upload(u, id, name, offset, bytes, last);
  }
  const evOut = (e) => ({ seq: e.seq, group: e.grp, type: e.type, at: e.at, by: e.by, ...JSON.parse(e.data) });
  function sync(u, after, limit = 500) {
    phoneSeen(u);
    const rows = Q.pending.all(u.id, Number(after) || 0, Math.min(1000, Number(limit) || 500));
    return { ok: true, events: rows.map(evOut), more: rows.length >= limit, last: rows.length ? rows[rows.length - 1].seq : Number(after) || 0 };
  }
  // the phone has everything up to here: those wait no more; an event nobody waits for is gone, with its files
  function ack(u, upto) {
    Q.ack.run(u.id, Number(upto) || 0);
    sweep();
    return { ok: true };
  }
  function filesIn(data) { const f = data && data.file; return [...(f && f.id ? [f.id] : []), ...(Array.isArray(data && data.files) ? data.files : [])]; }
  function dropFiles(ids) {
    for (const id of ids) {
      if (Q.fileInUse.get(`%"id":"${id}"%`)) continue;   // (still in an event someone hasn't picked up)
      try { fs.rmSync(path.join(relay, id), { force: true }); } catch { /* fine */ }
      Q.dropFile.run(id);
    }
  }
  function sweep() {
    const t = now();
    for (const r of Q.oldEvents.all(t - KEEP_MS)) Q.dropWaiting.run(r.seq);
    const gone = [];
    for (const r of Q.orphanEvents.all()) {
      const e = db.prepare('SELECT data FROM events WHERE seq = ?').get(r.seq);
      try { gone.push(...filesIn(JSON.parse(e.data))); } catch { /* fine */ }
      Q.dropEvent.run(r.seq);
    }
    dropFiles(gone);
    for (const r of Q.oldSent.all(t - KEEP_MS)) Q.dropSent.run(r.id);
    // uploads never sent in a message (or long gone)
    const stale = Q.oldFiles.all(t - KEEP_MS).map((r) => r.id);
    dropFiles(stale.filter((id) => !Q.fileInUse.get(`%"id":"${id}"%`)));
    // linked Macs: gone when their phone hasn't opened E11 Talk for 30 days, or their person has left the team
    for (const m of db.prepare('SELECT * FROM macs').all()) {
      const p = db.prepare('SELECT at FROM phone_seen WHERE uid = ?').get(m.uid);
      if (!active(userOf(m.uid)) || (p && p.at < t - PHONE_MS) || (!p && m.linked_at < t - PHONE_MS)) unlinkMac(m.id, 'phone away', false);
    }
    // groups with no new messages for 90 days: deleted, their people told (their phones clear it)
    for (const g of db.prepare('SELECT * FROM groups WHERE gone = 0 AND last_at < ?').all(t - IDLE_MS)) {
      const was = memberIds(g);
      Q.goneGroup.run(g.id);
      if (was.length) emit(g, 'gone', { group: g.id, why: 'inactive' }, null, was);
    }
  }
  const sweepTimer = setInterval(() => { try { sweep(); } catch (e) { console.error('talk sweep:', e.message); } }, 3600_000);
  if (sweepTimer.unref) sweepTimer.unref();
  const firstSweep = setTimeout(() => { try { sweep(); } catch { /* fine */ } }, 60_000);
  if (firstSweep.unref) firstSweep.unref();

  // ---------- notifications (E11 Talk's own phones) ----------
  function notify(g, from, text, msgId, mentions = []) {
    if (!apns || !apns.enabled()) return;
    const t = now();
    for (const uid of memberIds(g)) {
      if (uid === from.id) continue;
      const pref = Q.pref.get(uid, 'group', g.id) || {};
      if (pref.muted_until && pref.muted_until > t && !mentions.includes(uid)) continue;   // (muted — but an @mention still comes)
      const c = clientById(g.client);
      apns.sendTo(uid, { title: g.name, body: `${from.name || from.email}: ${text}`, tag: g.id, kind: 'talk', groupId: g.id, msgId, clientId: c ? c.id : null, category: 'talk-msg' }).catch(() => {});
    }
  }

  // ---------- what people do ----------
  const bad = (error, status = 400) => ({ ok: false, error, status });
  function needGroup(u, id, { mustBeIn = true } = {}) {
    const g = Q.group.get(String(id || ''));
    if (!g || !clientById(g.client)) return [null, bad('This group isn’t there any more', 404)];
    if (mustBeIn && !member(g, u.id)) return [null, bad('You’re not in this group', 403)];
    return [g, null];
  }
  const sys = (g, by, text, extraData = {}) => { const id = rid('m'); emit(g, 'msg', { id, kind: 'sys', text, ...extraData }, by); Q.touch.run(now(), g.id); return id; };
  const nameOf = (id) => { const x = personOfId(id); return x ? x.name : 'Someone'; };
  const changed = (g, by) => emit(g, 'group', { group: g.id }, by, memberIds(g));
  const cleanIds = (ids) => [...new Set((Array.isArray(ids) ? ids : []).map(String))].filter((id) => isContactId(id) ? !!contactRow(id) : active(userOf(id)));
  // client contacts may be added only by Super / Office Admins, and only to a group of their own client
  function contactsOK(u, g, ids) {
    const ks = ids.filter(isContactId);
    if (!ks.length) return null;
    if (!isBoss(u)) return bad('Only Super Admins and Office Admins add client contacts', 403);
    if (ks.some((k) => (contactRow(k) || {}).client !== g.client)) return bad('A client contact can only join their own client’s groups');
    return null;
  }
  const CONTACT_ACTS = new Set(['send', 'edit', 'del', 'react', 'read', 'leave', 'pin', 'mute']);

  function act(u, b) {
    const t = now();
    if (isContact(u) && !CONTACT_ACTS.has(String(b.act || ''))) return bad('Not allowed', 403);
    switch (String(b.act || '')) {
      // ---- client contacts: Super Admins and Office Admins ----
      case 'addContact': {
        if (!isBoss(u)) return bad('Only Super Admins and Office Admins add client contacts', 403);
        const name = clip(b.name, 80).trim(), email = clip(b.email, 200).trim().toLowerCase(), c = clientById(b.client);
        if (!name) return bad('Their name, please');
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return bad('That email doesn’t look right');
        if (!c) return bad('Pick their client');
        if (access.userByEmail(email)) return bad('That email is on the team already');
        if (db.prepare('SELECT 1 FROM contacts WHERE lower(email) = ? AND gone = 0').get(email)) return bad('That email is a client contact already');
        const id = rid('k');
        db.prepare('INSERT INTO contacts (id, email, name, client, by, at) VALUES (?, ?, ?, ?, ?, ?)').run(id, email, name, c.id, u.id, t);
        return { ok: true, contact: { id, name, email, client: c.id, groups: 0 } };
      }
      case 'removeContact': {
        if (!isBoss(u)) return bad('Only Super Admins and Office Admins remove client contacts', 403);
        const r = contactRow(b.id); if (!r) return { ok: true };
        db.prepare('UPDATE contacts SET gone = 1 WHERE id = ?').run(r.id);
        for (const m of db.prepare('SELECT grp FROM members WHERE uid = ?').all(r.id)) {
          const g = Q.group.get(m.grp); if (!g) continue;
          const was = memberIds(g);
          Q.dropMember.run(g.id, r.id);
          sys(Q.group.get(g.id), u.id, `${r.name} was removed`);
          emit(g, 'group', { group: g.id }, u.id, was);
        }
        return { ok: true };
      }
      case 'newGroup': {
        if (isFree(u)) return bad('Freelancers can’t make groups', 403);
        const c = clientById(b.client);
        if (!c || !access.canSee(u, 'projects', c)) return bad('Pick one of your clients');
        const name = clip(b.name, 80).trim();
        if (!name) return bad('Give the group a name');
        const ms = cleanIds(b.members);
        { const e = contactsOK(u, { client: c.id }, ms); if (e) return e; }
        const id = rid('g');
        Q.newGroup.run(id, c.id, name, u.id, t, t);
        Q.addMember.run(id, u.id, t, u.id);
        for (const m of ms) if (m !== u.id) Q.addMember.run(id, m, t, u.id);
        const g = Q.group.get(id);
        changed(g, u.id);
        sys(g, u.id, `${nameOf(u.id)} made the group “${name}”`);
        return { ok: true, group: groupView(g, u.id) };
      }
      case 'addPeople': {
        const [g, e] = needGroup(u, b.group, { mustBeIn: !isBoss(u) }); if (e) return e;
        if (!canManage(u, g)) return bad('Only the group’s admins add people', 403);
        const add = cleanIds(b.ids).filter((id) => !member(g, id));
        { const e2 = contactsOK(u, g, add); if (e2) return e2; }
        if (!add.length) return { ok: true, group: groupView(g, u.id) };
        for (const id of add) Q.addMember.run(g.id, id, t, u.id);
        changed(g, u.id);
        sys(g, u.id, `${nameOf(u.id)} added ${add.map(nameOf).join(', ')}`);
        return { ok: true, group: groupView(g, u.id) };
      }
      case 'removePerson': {
        const [g, e] = needGroup(u, b.group, { mustBeIn: !isBoss(u) }); if (e) return e;
        const id = String(b.id || '');
        if (!canManage(u, g)) return bad('Only the group’s admins remove people', 403);
        if (id === g.creator && !isBoss(u)) return bad('Only Super Admins and Office Admins can remove the group’s creator', 403);
        if (!member(g, id)) return { ok: true, group: groupView(g, u.id) };
        const was = memberIds(g);
        Q.dropMember.run(g.id, id);
        dropAdmin(g, id);
        sys(Q.group.get(g.id), u.id, `${nameOf(u.id)} removed ${nameOf(id)}`);
        emit(g, 'group', { group: g.id }, u.id, was);
        return { ok: true };
      }
      case 'leave': {
        const [g, e] = needGroup(u, b.group); if (e) return e;
        const was = memberIds(g);
        Q.dropMember.run(g.id, u.id);
        dropAdmin(g, u.id);
        sys(Q.group.get(g.id), u.id, `${nameOf(u.id)} left`);
        emit(g, 'group', { group: g.id }, u.id, was);
        return { ok: true };
      }
      case 'rename': case 'setPic': {
        const [g, e] = needGroup(u, b.group, { mustBeIn: !isBoss(u) }); if (e) return e;
        if (!canManage(u, g)) return bad('Only the group’s admins change it', 403);
        if (b.act === 'rename') {
          const name = clip(b.name, 80).trim(); if (!name) return bad('Give the group a name');
          Q.setGroup.run(name, g.second, g.extra, g.pic, g.creator, g.last_at, g.id);
          sys(Q.group.get(g.id), u.id, `${nameOf(u.id)} renamed the group to “${name}”`);
        } else {
          const pic = b.file ? String(b.file) : null;
          if (pic && !Q.getFile.get(pic)) return bad('That picture didn’t upload');
          Q.setGroup.run(g.name, g.second, g.extra, pic, g.creator, g.last_at, g.id);
          sys(Q.group.get(g.id), u.id, `${nameOf(u.id)} changed the group’s picture`);
        }
        changed(Q.group.get(g.id), u.id);
        return { ok: true, group: groupView(Q.group.get(g.id), u.id) };
      }
      case 'deleteGroup': {
        const [g, e] = needGroup(u, b.group, { mustBeIn: !isBoss(u) }); if (e) return e;
        if (!canManage(u, g)) return bad('Only the group’s admins delete it', 403);
        const was = memberIds(g);
        Q.goneGroup.run(g.id);
        emit(g, 'gone', { group: g.id, by: u.id }, u.id, was);
        return { ok: true };
      }
      // the creator (or a Super / Office Admin) picks the one second admin — or none
      case 'setSecond': {
        const [g, e] = needGroup(u, b.group, { mustBeIn: !isBoss(u) }); if (e) return e;
        if (!(u.id === g.creator && !g.creator_off) && !isBoss(u)) return bad('Only the group’s creator picks its second admin', 403);
        const id = b.id ? String(b.id) : null;
        if (id && !member(g, id)) return bad('Pick someone in the group');
        Q.setGroup.run(g.name, id, g.extra, g.pic, g.creator, g.last_at, g.id);
        if (id) sys(Q.group.get(g.id), u.id, `${nameOf(id)} is now an admin`);
        changed(Q.group.get(g.id), u.id);
        return { ok: true, group: groupView(Q.group.get(g.id), u.id) };
      }
      // Super Admins and Office Admins: admin of any group (added to it if they aren't in it)
      case 'makeMeAdmin': {
        if (!isBoss(u)) return bad('Only Super Admins and Office Admins', 403);
        const [g, e] = needGroup(u, b.group, { mustBeIn: false }); if (e) return e;
        if (!member(g, u.id)) Q.addMember.run(g.id, u.id, t, u.id);
        const x = extra(g); if (!adminsOf(g).includes(u.id)) x.push(u.id);
        Q.setGroup.run(g.name, g.second, JSON.stringify(x), g.pic, g.creator, g.last_at, g.id);
        sys(Q.group.get(g.id), u.id, `${nameOf(u.id)} is now an admin`);
        changed(Q.group.get(g.id), u.id);
        return { ok: true, group: groupView(Q.group.get(g.id), u.id) };
      }
      // Super Admins and Office Admins take someone's admin away — the creator's too (the second admin can't)
      case 'dropAdmin': {
        const [g, e] = needGroup(u, b.group, { mustBeIn: !isBoss(u) }); if (e) return e;
        const id = String(b.id || '');
        const may = isBoss(u) || (u.id === g.creator && !g.creator_off && id === g.second);
        if (!may) return bad('Not allowed', 403);
        // (re-adding a creator's admin: makeMeAdmin's way — or setting creator_off back by a Super / Office Admin)
        if (b.restore && isBoss(u) && id === g.creator) db.prepare('UPDATE groups SET creator_off = 0 WHERE id = ?').run(g.id); else dropAdmin(g, id);
        changed(Q.group.get(g.id), u.id);
        return { ok: true, group: groupView(Q.group.get(g.id), u.id) };
      }
      case 'pin': case 'pinClient': {
        // (the Clients tab keeps its own pins — up to 5 there too: Haris 2026-11-05)
        const kind = b.act === 'pin' ? (b.tab === 'clients' ? 'cgroup' : 'group') : 'client', id = String(b.id || '');
        if (kind !== 'client') { const [, e] = needGroup(u, id); if (e) return e; } else if (!clientById(id)) return bad('That client isn’t there');
        if (b.on) {
          const pins = Q.pinsOf.all(u.id, kind).map((r) => r.id);
          if (!pins.includes(id) && pins.length >= MAX_PINS) return { ok: false, full: true, pins, error: 'Pinned is full' };
          Q.setPin.run(u.id, kind, id, t);
        } else Q.setPin.run(u.id, kind, id, null);
        return { ok: true, pins: Q.pinsOf.all(u.id, kind).map((r) => r.id) };
      }
      case 'mute': {
        const [g, e] = needGroup(u, b.group); if (e) return e;
        const until = b.until === 'always' ? 9e15 : Number(b.until) || null;
        Q.setMute.run(u.id, g.id, until && until > t ? until : null);
        return { ok: true, mutedUntil: until && until > t ? until : null };
      }
      case 'send': {
        const [g, e] = needGroup(u, b.group); if (e) return e;
        const text = clip(b.text, 8000);
        let file = null;
        if (b.file) {
          const f = Q.getFile.get(String(b.file.id || ''));
          if (!f || f.by !== u.id || !f.done) return bad('The file didn’t upload — try again');
          file = { id: f.id, name: f.name, size: f.size, kind: ['photo', 'video', 'file', 'voice'].includes(b.file.kind) ? b.file.kind : 'file',
            w: Number(b.file.w) || null, h: Number(b.file.h) || null, secs: Number(b.file.secs) || null,
            wave: typeof b.file.wave === 'string' ? clip(b.file.wave.replace(/[^A-Za-z0-9+/=]/g, ''), 400) : null };   // (a voice message's waveform, made on the phone that recorded it)
        }
        if (!text.trim() && !file) return bad('Nothing to send');
        const id = rid('m'), mentions = cleanIds(b.mentions).filter((m) => member(g, m));
        const reply = b.reply && typeof b.reply === 'object' ? { id: clip(b.reply.id, 40), by: clip(b.reply.by, 40), text: clip(b.reply.text, 200), kind: clip(b.reply.kind, 10) } : null;
        Q.putSent.run(id, g.id, u.id, t, JSON.stringify(file ? [file.id] : []));
        const seq = emit(g, 'msg', { id, cid: clip(b.cid, 60), kind: file ? file.kind : 'text', text, file, reply, mentions }, u.id);
        Q.touch.run(t, g.id);
        notify(g, u, file && !text.trim() ? ({ photo: '📷 Photo', video: '🎥 Video', voice: '🎤 Voice message' }[file.kind] || `📄 ${file.name}`) : text, id, mentions);
        return { ok: true, id, seq, at: t };
      }
      case 'edit': case 'del': case 'react': {
        const s = Q.getSent.get(String(b.msg || ''));
        if (!s) return bad('That message has gone', 404);
        const [g, e] = needGroup(u, s.grp); if (e) return e;
        if (b.act === 'edit') {
          if (s.by !== u.id) return bad('Only your own messages', 403);
          if (t - s.at > EDIT_MS) return bad('Messages can be edited for 15 minutes');
          const text = clip(b.text, 8000); if (!text.trim()) return bad('Nothing to send');
          emit(g, 'edit', { id: s.id, text }, u.id);
        } else if (b.act === 'del') {
          if (s.by !== u.id) return bad('Only your own messages', 403);
          if (t - s.at > DEL_ALL_MS) return bad('Too late to delete it for everyone');
          emit(g, 'del', { id: s.id }, u.id);
          dropFiles(JSON.parse(s.files || '[]'));
        } else {
          const emoji = b.emoji ? clip(b.emoji, 16) : null;
          emit(g, 'react', { id: s.id, emoji }, u.id);
        }
        return { ok: true };
      }
      // read up to this message — the others see "Seen by"
      // ---- linked Macs: from the phone ----
      case 'linkMac': {
        const r = db.prepare('SELECT * FROM link_codes WHERE code = ?').get(String(b.code || ''));
        if (!r || r.mac || t - r.at > LINK_MS) return bad('That code has run out — show a new one on the Mac');
        if (r.uid !== u.id) return bad('This Mac is signed in to E11 Console as someone else', 403);
        if (macsOf(u.id).length >= 4) return bad('4 Macs at most — unlink one first');
        phoneSeen(u);
        const id = rid('mac');
        db.prepare('INSERT INTO macs (id, uid, name, linked_at, seen_at) VALUES (?, ?, ?, ?, ?)').run(id, u.id, r.name, t, t);
        db.prepare('UPDATE link_codes SET mac = ? WHERE code = ?').run(id, r.code);
        return { ok: true, mac: { id, name: r.name, linkedAt: t, seenAt: t } };
      }
      case 'unlinkMac': {
        const m = db.prepare('SELECT * FROM macs WHERE id = ? AND uid = ?').get(String(b.id || ''), u.id);
        if (!m) return bad('That Mac isn’t linked', 404);
        unlinkMac(m.id);
        return { ok: true };
      }
      case 'read': {
        const [g, e] = needGroup(u, b.group); if (e) return e;
        // ("Seen by" is never shown to clients — staff see it, the client's too)
        emit(g, 'read', { upto: clip(b.upto, 40) }, u.id, staffIds(g).filter((id) => id !== u.id));
        return { ok: true };
      }
      default: return bad('Unknown');
    }
  }
  // (the creator stays the group's creator — only their admin goes)
  function dropAdmin(g, id) {
    const x = extra(g).filter((a) => a !== id);
    Q.setGroup.run(g.name, g.second === id ? null : g.second, JSON.stringify(x), g.pic, g.creator, g.last_at, g.id);
    if (g.creator === id) db.prepare('UPDATE groups SET creator_off = 1 WHERE id = ?').run(g.id);
  }

  // ---------- files: held until passed on ----------
  function upload(u, id, name, offset, bytes, last) {
    if (!id) {
      id = rid('f');
      Q.newFile.run(id, u.id, clip(name || 'File', 200).replace(/[\\/]/g, '-'), now());
      fs.writeFileSync(path.join(relay, id), '');
    }
    const f = Q.getFile.get(String(id));
    if (!f || f.by !== u.id) return bad('Upload not found — please try again', 404);
    if (f.done) return bad('Already uploaded');
    if (Number(offset) !== f.size) return { ok: false, error: 'Out of step', size: f.size, status: 409 };
    if (f.size + bytes.length > FILE_MAX) return bad('That file is too big (2 GB at most)');
    fs.appendFileSync(path.join(relay, f.id), bytes);
    Q.growFile.run(f.size + bytes.length, last ? 1 : 0, f.id);
    return { ok: true, id: f.id, size: f.size + bytes.length, done: !!last };
  }
  // a file is for the people of a group it was sent in (or a group's picture)
  function fileFor(u, id) {
    const f = Q.getFile.get(String(id || ''));
    if (!f || !f.done) return null;
    const pid = u.person || u.id;   // (a linked Mac: its person's)
    if (f.by === pid) return f;
    const ev = db.prepare('SELECT e.grp FROM events e JOIN waiting w ON w.seq = e.seq WHERE w.uid = ? AND e.data LIKE ? LIMIT 1').get(u.id, `%"id":"${f.id}"%`);
    if (ev) return f;
    const pic = db.prepare('SELECT g.id FROM groups g JOIN members m ON m.grp = g.id WHERE m.uid = ? AND g.pic = ? AND g.gone = 0 LIMIT 1').get(pid, f.id);
    return pic ? f : null;
  }
  const filePath = (f) => path.join(relay, f.id);

  function listen(uid, res) {
    if (!listeners.has(uid)) listeners.set(uid, new Set());
    listeners.get(uid).add(res);
    return () => { const s = listeners.get(uid); if (s) { s.delete(res); if (!s.size) listeners.delete(uid); } };
  }
  // ---------- sample groups (test site only, the owner asks — Haris 2026-11-06: "fill in some dummy data") ----------
  // a few groups under real clients with you and some of the team, each with a short made-up conversation; every
  // group's name ends "(sample)" so nobody takes them for real
  function sample(u) {
    const team = store.list('users').filter((x) => active(x) && x.id !== u.id && !isFree(x)).slice(0, 6);
    const cl = clientsFor(u).slice(0, 3);
    if (!cl.length) return bad('No clients to put sample groups under');
    const P = (i) => team.length ? team[i % team.length] : u;
    const first = (x) => String(x.name || x.email).split(' ')[0];
    let t = now() - 3 * 3600_000;
    const at = () => (t += 4 * 60_000 + Math.floor(Math.random() * 6 * 60_000));
    const made = [];
    const plans = [
      { client: cl[0], name: 'Winter campaign (sample)', people: [0, 1, 2], talk: (g, a, b, c) => [
        [a, 'Morning all — the winter campaign brief is final, sharing the key dates today.'],
        [b, 'Great. Do we have the hero visual yet?'],
        [u, 'Not yet, first drafts by Thursday.'],
        [c, `@${u.name || u.email} can we move the shoot to Sunday? The studio is free then.`, [u.id]],
        [u, 'Sunday works 👍', null, { reply: 3 }],
        [a, 'Perfect, I’ll book it.', null, { react: [[b, '👍'], [c, '🙏']] }],
      ] },
      { client: cl[1] || cl[0], name: 'Shoot · 12 Nov (sample)', people: [1, 3], talk: (g, a, b) => [
        [a, 'Call time is 8:30 at the café — bring the 35mm.'],
        [b, 'On it, I’ll pick up the light kit tonight.'],
        [u, 'Thanks both. Shot list is in the task.'],
        [a, 'See you there!', null, { react: [[u, '❤️']] }],
      ] },
      { client: cl[2] || cl[0], name: 'General (sample)', people: [2, 4, 5], talk: (g, a, b, c) => [
        [b, 'Reminder: client review moved to 3 pm.'],
        [c, 'Noted, thanks.'],
        [a, 'Can someone share the latest logo files?'],
      ] },
    ];
    for (const pl of plans) {
      const id = rid('g'), ppl = [...new Set(pl.people.map(P))].filter((x) => x.id !== u.id);
      const creator = ppl[0] || u;
      const t0 = at();
      Q.newGroup.run(id, pl.client.id, pl.name, creator.id, t0, t0);
      Q.addMember.run(id, u.id, t0, creator.id);
      for (const x of ppl) Q.addMember.run(id, x.id, t0, creator.id);
      const g = Q.group.get(id);
      changed(g, creator.id);
      emit(g, 'msg', { id: rid('m'), kind: 'sys', text: `${first(creator)} made the group “${pl.name}”` }, creator.id);
      const lines = pl.talk(g, ...[0, 1, 2].map((i) => ppl[i] || creator));
      const ids = [];
      for (const [who, text, mentions, extra] of lines) {
        const mid = rid('m'); ids.push(mid);
        const tt = at();
        Q.putSent.run(mid, id, who.id, tt, '[]');
        const reply = extra && extra.reply != null ? { id: ids[extra.reply], by: lines[extra.reply][0].id, text: lines[extra.reply][1].slice(0, 200), kind: 'text' } : null;   // (reply: the line it answers, counted from 0)
        const r = Q.addEvent.run(id, 'msg', JSON.stringify({ id: mid, kind: 'text', text, file: null, reply, mentions: mentions || [] }), tt, who.id);
        for (const m of devicesFor(memberIds(g), who.id)) waitFor(Number(r.lastInsertRowid), m);
        for (const [rw, e] of (extra && extra.react) || []) emit(g, 'react', { id: mid, emoji: e }, rw.id);
      }
      // the others have seen up to the end (✓✓ on yours)
      for (const x of ppl) emit(g, 'read', { upto: ids[ids.length - 1] }, x.id, memberIds(g).filter((m) => m !== x.id));
      Q.touch.run(t, id);
      made.push(pl.name);
    }
    for (const s2 of listeners.get(u.id) || []) { try { s2.write(`event: talk\ndata: {}\n\n`); } catch { /* closed */ } }
    return { ok: true, made };
  }
  const isAdminOf = (u, gid) => { const g = Q.group.get(gid); return !!g && isAdmin(u, g); };
  return { state, act, sync, ack, sample, upload, contactByEmail, fileFor, filePath, listen, sweep, isAdminOf,
    linkCode, linkStatus, macFor, unlinkMac, history, hasFiles, resend, close: () => { clearInterval(sweepTimer); for (const set of listeners.values()) for (const r of set) try { r.end(); } catch { /* fine */ } db.close(); } };
}
