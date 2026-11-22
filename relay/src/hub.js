// E11 Talk on Cloudflare — the hub: one Durable Object for the whole team (TALK-CF-A, claude/talk-cloudflare-relay-plan.md).
// One hub, not one per group: however busy, it can't pass the free plan's running time (awake all day is 83%).
// - Talk itself: core.js (E11 Talk's own code over this object's SQLite).
// - The phones' live lines: WebSockets with hibernation (asleep costs nothing; "ping" answered without waking).
// - The office's copy: every batch of writes sent to the office, signed, in order; kept here only while the office can't
//   be reached (then sent again by the alarm). A gap the office notices (a batch lost) → it asks for a full copy (dump).
// - From the office (signed): E11 Console's people and clients (dir), news for open apps (tell), Talk's data (load).
import { DurableObject } from 'cloudflare:workers';
import { HubCore } from './core.js';
import { newKey, signHeaders, verify } from './sign.js';
import { bindingR2 } from './r2.js';
import { makeApns } from './apns.js';
import { usage } from './usage.js';

const TALK_TABLES = ['groups', 'members', 'prefs', 'events', 'waiting', 'sent', 'files', 'contacts', 'macs', 'link_codes', 'phone_seen',
  'phones', 'bare_seen', 'needs', 'opts', 'unread', 'file_kept', 'file_had', 'asks'];
const HOUR = 3600_000, RETRY = 30_000;
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

const ONE_MAX = 1024 * 1024;   // (r2/one: a voice note's size at most, locked)
export class TalkHub extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.env = env;
    // (the office's own public name for what the hub sends it, signed — talklink, let through by Cloudflare like a linked Mac)
    this.office = String(env.OFFICE_LINK || env.OFFICE || '').replace(/\/$/, '');
    this.queue = []; this.flushing = null;
    ctx.blockConcurrencyWhile(async () => {
      const sql = ctx.storage.sql;
      sql.exec('CREATE TABLE IF NOT EXISTS hub_outbox (n INTEGER PRIMARY KEY, body TEXT NOT NULL)');
      sql.exec('CREATE TABLE IF NOT EXISTS hub_who (fp TEXT PRIMARY KEY, email TEXT NOT NULL, at INTEGER NOT NULL)');
      // (files: Talk's R2 bucket through this Worker's own binding — no R2 keys)
      const r2 = bindingR2({ bucket: env.TALK_FILES, secret: env.R2_LINK_SECRET, base: String(env.PUBLIC || '').replace(/\/$/, ''),
        // (uploads straight to R2's own addresses once its key is here — as up to 2026-11-21; Haris 2026-11-22 22:02)
        s3: env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY ? { account: env.ACCOUNT_ID, keyId: env.R2_ACCESS_KEY_ID, secret: env.R2_SECRET_ACCESS_KEY, name: env.TALK_BUCKET || 'e11-talk-files' } : null });
      // (notifications: sent by the office for now — the phones' notification tokens are there; once Apple's key is in
      //  Cloudflare, sent from here, office or not. E11 Console's Talk count: the office works it out from its copy)
      // (the office sends them while it can be reached — it also sends again any a phone missed; it can't: Cloudflare sends
      //  them itself, with Apple's key and the phones' addresses — Haris 2026-11-22 01:00 "A")
      this.apple = makeApns({ key: env.APNS_KEY, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC || 'ae.e11.talk.ios', subs: () => (this.core && this.core.dir.snapshot.push) || {} });
      // (Cloudflare sends it straight to Apple — one hop, the office's internet not in the way (Haris 2026-11-22 13:07); the
      //  office only when Apple's key isn't here, no phone of theirs is known here, or Apple couldn't be reached for one)
      const toOffice = (uid, p, wake) => this.later('/api/talk/relay/push', { uid, p, ...(wake ? { wake: true } : {}) });
      const notify = async (uid, p, wake) => {
        try {
          if (this.apple.on) {
            const r = await (wake ? this.apple.wake(uid, p) : this.apple.sendTo(uid, p));
            const rs = (r && r.results) || [];
            // (a phone of theirs has it — done: the office would send it to every phone again; every address Apple says is
            //  gone (400 / 410) — done too: the office has the same ones. Anything else (Apple not reached, the key
            //  refused): the office sends it)
            if (rs.some((x) => x.status === 200)) return;
            if (rs.length && rs.every((x) => x.status === 400 || x.status === 410)) return;
          }
          await toOffice(uid, p, wake);
        } catch { /* never in the way */ }
      };
      const apns = { enabled: () => !!this.office || this.apple.on, sendTo: (uid, p) => { const x = notify(uid, p, false); try { this.ctx.waitUntil(x); } catch { /* fine */ } return x; }, wake: (uid, p) => { const x = notify(uid, p, true); try { this.ctx.waitUntil(x); } catch { /* fine */ } return x; } };
      this.core = new HubCore({ sql, copy: (b) => this.toOffice(b), r2: r2.on ? r2 : null, apns, onUnread: (uids) => { this.later('/api/talk/relay/unread', { uids }); } });
      sql.exec("DELETE FROM hub_meta WHERE k = 'callsMs'");   // (the call timer's list, 2026-11-22 — taken out)
      const d = this.core.meta('dir'); if (d) try { this.core.dir.set(JSON.parse(d)); } catch { /* the office sends it again */ }
      if (!this.core.meta('key')) { const k = await newKey(); this.core.meta('key', k.priv); this.core.meta('pub', k.pub); }
      // (lines kept open while the hub slept: listening again)
      for (const ws of ctx.getWebSockets()) this.hear(ws);
      try { ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong')); } catch { /* older runtime */ }
      if (!(await ctx.storage.getAlarm())) await ctx.storage.setAlarm(Date.now() + HOUR);
    });
  }

  // ---------- requests (from the Worker: phones, already identified by email; the office, signed) ----------
  async fetch(req) {
    const url = new URL(req.url), p = url.pathname;
    if (p === '/hub/key') return json({ ok: true, key: this.core.meta('pub') });
    // (how it's doing — no names, no messages: when the office last sent E11 Console's people, how far the copy is, what waits)
    if (p === '/hub/status') {
      // (where Cloudflare runs the hub — its airport code, e.g. DXB; found once)
      if (!this.colo) { try { const t = await (await fetch('https://www.cloudflare.com/cdn-cgi/trace')).text(); this.colo = (/colo=(\w+)/.exec(t) || [])[1] || '?'; } catch { this.colo = '?'; } }
      if (!this.core.meta('dirAt')) await this.askDir();
      const d = this.core.dir.snapshot || {};
      return json({ ok: true, colo: this.colo, dirAt: Number(this.core.meta('dirAt') || 0) || null, people: (d.users || []).length, clients: (d.projects || []).length,
        phones: Object.values((d.push) || {}).reduce((a, x) => a + (x || []).length, 0), apple: this.apple.on, copyN: this.core.n, waiting: this.ctx.storage.sql.exec('SELECT COUNT(*) AS c FROM hub_outbox').toArray()[0].c, officeKey: !!this.core.meta('officeKey'), ...(this.dirErr ? { dirErr: this.dirErr } : {}) });
    }
    if (p.startsWith('/office/')) return this.fromOffice(req, p);
    if (!this.core.meta('dirAt')) await this.askDir();
    // (the office said this sign-in isn't anyone's: sign in again · the office couldn't be asked and this phone isn't
    //  remembered: 503 — the app tries the office itself; never signed out because the office was down)
    const email = await this.whoIs(req);
    if (email === null) return json({ ok: false, error: 'Sign in again' }, 401);
    if (!email) return json({ ok: false, error: 'Can’t check your sign-in right now' }, 503);
    // (one place has Talk at a time: before the switch-over, or while the office has taken over, the office — phones go there)
    if (await this.officeHas()) return json({ ok: false, office: true, error: 'E11 Talk is with the office right now' }, 409);
    const w = this.core.who(email, req.headers.get('x-talk-device'));
    if (!w) return json({ ok: false, error: 'No E11 Talk account for ' + email }, 403);
    if (p === '/line') {
      if (req.headers.get('upgrade') !== 'websocket') return json({ ok: false, error: 'A live line' }, 426);
      const [client, server] = Object.values(new WebSocketPair());
      this.ctx.acceptWebSocket(server);
      server.serializeAttachment({ email, device: req.headers.get('x-talk-device') || '', dev: w.dev.id });
      this.hear(server);
      return new Response(null, { status: 101, webSocket: client });
    }
    // a message's file: off to its R2 address for 15 minutes (counted as fetched, as the office does for ?r2=1)
    if (p.startsWith('/api/talk/file/') && (req.method === 'GET' || req.method === 'HEAD')) {
      const f = this.core.fileFor(w, p.slice('/api/talk/file/'.length));
      if (!f || f.store !== 'r2' || !this.core.talk.r2) return json({ ok: false, error: 'That file has gone' }, 404);
      if (f.lock === 'p' && url.searchParams.get('pieces') !== '1') return json({ ok: false, error: 'Update E11 Talk' }, 409);
      this.core.fetched(w, f.id);
      return new Response(null, { status: 302, headers: { Location: await this.core.talk.r2.getUrl(this.core.talk.r2Key(f)), 'cache-control': 'no-store' } });
    }
    const r = await this.call(w, p.replace('/api/talk/', ''), req.method === 'POST' ? await req.json().catch(() => ({})) : Object.fromEntries(url.searchParams));
    return r ? json(r, r.status || (r.ok === false ? 400 : 200)) : json({ ok: false, error: 'Not here' }, 404);
  }
  // the calls a phone makes — the same as the office's /api/talk/…, the same answers
  async call(w, name, b) {
    switch (name) {
      case 'state': return this.core.state(w);
      case 'act': return this.act(w, b);
      case 'sync': return this.core.sync(w, b.after, b.limit);
      case 'ack': return this.core.ack(w, b.upto);
      case 'got': return this.core.got(w, b.groupId, b.msgId);
      case 'r2/start': return this.core.r2Start(w, b);
      case 'r2/drop': return this.core.r2Drop(w, b);
      case 'r2/done': return this.core.r2Done(w, b);
      case 'r2/one': return this.r2One(w, b);
      case 'ask': return this.core.ask(w, b);
      case 'asks': return this.core.asks(w);
      case 'resend/start': return this.core.resendStart(w, b);
      case 'history/share': return this.core.shareHistory(w, b);
      default: return null;   // (Macs, sign-in… the office's for now)
    }
  }

  // a small file (a voice note) and its message in one call — the phone sends the locked bytes with the message, the hub puts
  // them in R2 itself: one trip instead of three (start, the file, "it's all there"); Haris 2026-11-22 19:06. The same records
  // as the three calls make (the office's copy sees nothing new). Anything wrong: the phone goes the usual way.
  async r2One(w, b) {
    let bytes;
    try { bytes = Uint8Array.from(atob(String(b.data || '')), (c) => c.charCodeAt(0)); } catch { return { ok: false, error: 'Bad file', status: 400 }; }
    if (!bytes.length || bytes.length > ONE_MAX || !this.env.TALK_FILES || !b.send || typeof b.send !== 'object') return { ok: false, error: 'Not this way', status: 400 };
    const s = await this.core.r2Start(w, { name: b.name, size: bytes.length });
    if (!s || !s.ok || !s.put) return s && s.ok ? { ok: false, error: 'Not this way', status: 400 } : s;
    try { await this.env.TALK_FILES.put(this.core.talk.r2Key({ id: s.id }), bytes); }
    catch (e) { this.core.r2Drop(w, { id: s.id }); return { ok: false, error: String(e.message || e), status: 502 }; }
    const send = { ...b.send, file: { ...(b.send.file || {}), id: s.id } };
    const r = await this.core.r2Done(w, { id: s.id, etags: [], send });
    return r && r.ok ? { ...r, id: s.id } : r;
  }

  // E11 Console's tasks stay in the office (Haris 2026-11-22 02:58 "keep it only local"): # — finding tasks, and a chat's task
  // cards — asked of the office for this person; sharing one (picked, or its link in the words): the office lends that task
  // for this one call
  async act(w, b) {
    b = b || {};
    if (b.act === 'tasks' || b.act === 'taskCards' || b.act === 'tasksById') {
      const r = await this.officeTasks(w, b);
      return r || (b.act === 'tasks' ? { ok: false, error: 'Tasks can’t be reached right now', status: 503 } : { ok: true, cards: [] });
    }
    const ids = [];
    if (b.task && typeof b.task === 'object' && b.task.id) ids.push(String(b.task.id));
    for (const m of String(b.text || '').matchAll(/https?:\/\/files(?:-test)?\.e11hq\.com\/t\/([A-Za-z0-9_%.-]{1,120})/gi)) ids.push(decodeURIComponent(m[1]));
    if (!ids.length) return this.core.act(w, b);
    const r = await this.officeTasks(w, { act: 'get', ids: ids.slice(0, 20), group: b.group });
    if (!r && b.task) return { ok: false, error: 'Tasks can’t be reached right now', status: 503 };
    this.core.dir.lend((r && r.tasks) || [], (r && r.projects) || []);
    try { return await this.core.act(w, b); } finally { this.core.dir.lend(); }
  }
  async officeTasks(w, b) {
    if (!this.office) return null;
    const path = '/api/talk/relay/tasks', text = JSON.stringify({ email: w.u.email, act: b.act, group: b.group, q: b.q, ids: b.ids, all: b.all === true });
    try {
      const h = await signHeaders(this.core.meta('key'), 'POST', path, text);
      const r = await fetch(this.office + path, { method: 'POST', body: text, headers: { 'content-type': 'application/json', ...h }, signal: AbortSignal.timeout(8000) });
      try { return await r.json(); } catch { return null; }
    } catch { return null; }
  }

  // ---------- who this phone is (the office says, by the phone's own sign-in; remembered by fingerprint) ----------
  // remembered and under a day old: at once · older (up to 30 days): at once, checked with the office behind the answer ·
  // never seen: the office asked now (the only time a phone waits for it)
  async whoIs(req) {
    const fp = req.headers.get('x-hub-fp') || '';
    const sql = this.ctx.storage.sql, DAY = 86400_000;
    const row = fp ? sql.exec('SELECT email, at FROM hub_who WHERE fp = ?', fp).toArray()[0] : null;
    if (row && Date.now() - row.at < DAY) return row.email;
    const ask = this.askWho(req).then((email) => { if (email) sql.exec('INSERT OR REPLACE INTO hub_who (fp, email, at) VALUES (?, ?, ?)', fp, email, Date.now()); return email; });
    if (row && Date.now() - row.at < 30 * DAY) { this.ctx.waitUntil(ask.catch(() => null)); return row.email; }
    return ask.catch(() => undefined);
  }
  async askWho(req) {
    const h = {};
    for (const k of ['cookie', 'authorization', 'cf-access-jwt-assertion', 'x-talk-key', 'x-talk-device']) { const v = req.headers.get(k); if (v) h[k] = v; }
    const r = await fetch(String(this.env.OFFICE).replace(/\/$/, '') + '/api/talk/relay/who', { headers: h, signal: AbortSignal.timeout(8000) });
    const html = (r.headers.get('content-type') || '').includes('text/html');   // (Cloudflare's sign-in page: not signed in)
    if (r.status === 401 || r.status === 403 || html) return null;
    if (!r.ok) throw new Error('The office said ' + r.status);
    const j = await r.json().catch(() => null);
    return j && j.ok && j.email ? String(j.email) : null;
  }

  // ---------- who has Talk (the office says) — never waited for: the last answer (kept) is used, and asked again behind it
  // once a minute (10 s while the office has it); the office also tells the hub at once when it changes (/office/mode) ----------
  async officeHas() {
    if (this.officeMode === undefined) this.officeMode = this.core.meta('officeMode');
    const t = Date.now(), every = this.officeMode && this.officeMode !== 'hub' ? 10_000 : 60_000;
    if ((!this.modeAt || t - this.modeAt > every) && !this.modeAsking) {
      this.modeAt = t;
      this.modeAsking = (async () => {
        try {
          const r = await fetch(this.office + '/api/talk/relay/mode', { signal: AbortSignal.timeout(3000) });
          const j = r.ok ? await r.json() : null;
          if (j && j.mode) this.setOfficeMode(j.mode);
        } catch { /* the office can't be reached: the hub */ }
      })().finally(() => { this.modeAsking = null; });
      if (this.officeMode == null) await this.modeAsking; else this.ctx.waitUntil(this.modeAsking);
    }
    return this.officeMode != null && this.officeMode !== 'hub';
  }
  setOfficeMode(m) { if (m === this.officeMode) return; this.officeMode = m; this.core.meta('officeMode', m); }

  // ---------- the live line ----------
  hear(ws) {
    const a = ws.deserializeAttachment(); if (!a || !a.dev) return;
    ws.stop = this.core.listen(a.dev, (s) => { try { ws.send(s); } catch { /* closed */ } });
  }
  async webSocketMessage(ws, msg) {
    let m; try { m = JSON.parse(typeof msg === 'string' ? msg : new TextDecoder().decode(msg)); } catch { return; }
    if (await this.officeHas()) { ws.send(JSON.stringify({ id: m.id, r: { ok: false, office: true, error: 'E11 Talk is with the office right now' } })); return; }
    const a = ws.deserializeAttachment() || {};
    const w = this.core.who(a.email, a.device);
    if (!w) { ws.close(4003, 'Signed out'); return; }
    // (something went wrong here: no answer (null) — the phone sends the same call the usual way)
    let r; try { r = await this.call(w, String(m.call || ''), m.body || {}); } catch (e) { ws.send(JSON.stringify({ id: m.id, r: null, err: String(e && e.message || e).slice(0, 200) })); return; }
    ws.send(JSON.stringify({ id: m.id, r: r || { ok: false, error: 'Not here' } }));
  }
  webSocketClose(ws) { try { ws.stop && ws.stop(); } catch { /* fine */ } }
  webSocketError(ws) { this.webSocketClose(ws); }

  // ---------- the office's copy ----------
  toOffice(batch) {
    this.queue.push(batch);
    if (!this.flushing) this.flushing = Promise.resolve().then(() => this.flush()).finally(() => { this.flushing = null; });
    this.ctx.waitUntil(this.flushing);
  }
  async flush() {
    // (kept ones first — the office runs them in order)
    const kept = this.ctx.storage.sql.exec('SELECT n, body FROM hub_outbox ORDER BY n').toArray();
    const fresh = this.queue.splice(0);
    const all = [...kept.map((r) => JSON.parse(r.body)), ...fresh];
    if (!all.length) return;
    const ok = await this.post('/api/talk/relay/copy', { batches: all });
    if (ok) { if (kept.length) this.ctx.storage.sql.exec('DELETE FROM hub_outbox WHERE n <= ?', kept[kept.length - 1].n); return; }
    // the office can't be reached: kept here, sent again soon (the only time the copy costs a save)
    for (const b of fresh) this.ctx.storage.sql.exec('INSERT OR REPLACE INTO hub_outbox (n, body) VALUES (?, ?)', b.n, JSON.stringify(b));
    const due = Date.now() + RETRY, cur = await this.ctx.storage.getAlarm();
    if (!cur || cur > due) await this.ctx.storage.setAlarm(due);
  }
  // something for the office that needn't wait or be kept (a notification, Console's count): sent once, behind the answer
  later(path, body) { const p = this.post(path, body).catch(() => false); try { this.ctx.waitUntil(p); } catch { /* fine */ } return p; }
  async post(path, body) {
    if (!this.office) return false;
    const text = JSON.stringify(body);
    try {
      const h = await signHeaders(this.core.meta('key'), 'POST', path, text);
      const r = await fetch(this.office + path, { method: 'POST', body: text, headers: { 'content-type': 'application/json', ...h } });
      return r.ok;
    } catch { return false; }
  }
  // E11 Console's people and clients: asked of the office when the hub has none, or they're over a day old (the office also
  // sends them whenever they change)
  async askDir() {
    const at = Number(this.core.meta('dirAt') || 0);
    if (at && Date.now() - at < 86400_000) return;
    const text = '{}', path = '/api/talk/relay/dir';
    try {
      const h = await signHeaders(this.core.meta('key'), 'POST', path, text);
      const r = await fetch(this.office + path, { method: 'POST', body: text, headers: { 'content-type': 'application/json', ...h } });
      const j = r.ok ? await r.json().catch(() => null) : null;
      if (j && j.ok && j.dir) { this.core.setDir(j.dir); this.core.meta('dir', JSON.stringify(j.dir)); this.dirErr = null; }
      else this.dirErr = `the office said ${r.status}${j && j.error ? ' — ' + j.error : ''}`;
    } catch (e) { this.dirErr = e.message; /* next time */ }
  }
  async alarm() {
    const last = Number(this.core.meta('sweptAt') || 0);
    // (only while the hub has Talk)
    if (Date.now() - last >= HOUR - 60_000 && !(await this.officeHas())) { this.core.sweep(); this.core.meta('sweptAt', Date.now()); }
    await this.askDir();
    await this.flush();
    const left = this.ctx.storage.sql.exec('SELECT COUNT(*) AS c FROM hub_outbox').toArray()[0].c;
    await this.ctx.storage.setAlarm(Date.now() + (left ? RETRY : HOUR));
  }

  // ---------- from the office (signed with the office's key) ----------
  async officeKey(fresh = false) {
    let k = this.core.meta('officeKey');
    if ((!k || fresh) && this.office) {
      try { const r = await fetch(this.office + '/api/talk/relay/key'); const j = await r.json(); if (j && j.key) { k = j.key; this.core.meta('officeKey', k); } } catch { /* the kept one */ }
    }
    return k;
  }
  async fromOffice(req, p) {
    const body = await req.text();
    let ok = await verify(await this.officeKey(), req.method, p, body, req.headers);
    if (!ok) ok = await verify(await this.officeKey(true), req.method, p, body, req.headers);   // (the office made a new key)
    if (!ok) return json({ ok: false, error: 'Not signed by the office' }, 403);
    const b = body ? JSON.parse(body) : {};
    switch (p) {
      case '/office/dir': this.core.setDir(b.dir); this.core.meta('dir', JSON.stringify(b.dir)); return json({ ok: true });
      case '/office/tell':
        if (b.ev === 'tasks') this.core.talk.tasksChanged(b.ids || []); else if (b.ev === 'links') this.core.talk.linksChanged(); else if (b.ev === 'people') this.core.talk.peopleChanged();
        return json({ ok: true });
      // the office's whole Talk, once (moving it here) — or the office asking for this hub's whole Talk (a gap in its copy)
      case '/office/load': return json(this.load(b));
      case '/office/dump': return json(this.dump());
      // (the office's word that who has Talk changed — at once, not at the next minute's asking)
      case '/office/mode': this.setOfficeMode(String(b.mode || '')); this.modeAt = Date.now(); return json({ ok: true });
      // the owner's test (through the office): Cloudflare sends one notification itself to that person's phones — Apple's answer
      case '/office/pushtest': {
        if (!this.apple.on) return json({ ok: false, error: 'Apple’s key isn’t in Cloudflare yet' });
        const r = await this.apple.sendTo(String(b.uid || ''), { title: 'E11 Talk', body: 'A test from Cloudflare — notifications work without the office', kind: 'test', tag: 'test' });
        return json({ ok: true, ...r });
      }
      // the owner's About line in Talk (through the office): how much of Cloudflare's free day is used — Cloudflare's own figures
      case '/office/usage': return json(await usage({ token: this.env.CF_ANALYTICS_TOKEN, account: this.env.ACCOUNT_ID }));
      default: return json({ ok: false, error: 'Not here' }, 404);
    }
  }
  dump() {
    const sql = this.ctx.storage.sql, tables = {};
    for (const t of TALK_TABLES) tables[t] = sql.exec(`SELECT * FROM ${t}`).toArray();
    return { ok: true, n: this.core.n, tables };
  }
  load(b) {
    if (!b || !b.tables) return { ok: false, error: 'Nothing to load' };
    const sql = this.ctx.storage.sql;
    this.ctx.storage.transactionSync(() => {
      for (const t of TALK_TABLES) {
        const rows = b.tables[t]; if (!Array.isArray(rows)) continue;
        sql.exec(`DELETE FROM ${t}`);
        for (const r of rows) { const k = Object.keys(r); if (k.length) sql.exec(`INSERT INTO ${t} (${k.join(',')}) VALUES (${k.map(() => '?').join(',')})`, ...k.map((x) => r[x])); }
      }
    });
    this.core.n = Number(b.n || 0); this.core.meta('copyN', this.core.n);
    // (the office's whole Talk now: what waited for it from before is already in it, or was never the office's)
    sql.exec('DELETE FROM hub_outbox'); this.queue = [];
    this.setOfficeMode('hub'); this.modeAt = Date.now();
    return { ok: true, n: this.core.n };
  }
}
