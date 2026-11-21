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

const TALK_TABLES = ['groups', 'members', 'prefs', 'events', 'waiting', 'sent', 'files', 'contacts', 'macs', 'link_codes', 'phone_seen',
  'phones', 'bare_seen', 'needs', 'opts', 'unread', 'file_kept', 'file_had', 'asks'];
const HOUR = 3600_000, RETRY = 30_000;
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

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
      const r2 = bindingR2({ bucket: env.TALK_FILES, secret: env.R2_LINK_SECRET, base: String(env.PUBLIC || '').replace(/\/$/, '') });
      // (notifications: sent by the office for now — the phones' notification tokens are there; once Apple's key is in
      //  Cloudflare, sent from here, office or not. E11 Console's Talk count: the office works it out from its copy)
      const apns = { enabled: () => !!this.office, sendTo: (uid, p) => this.later('/api/talk/relay/push', { uid, p }), wake: (uid, p) => this.later('/api/talk/relay/push', { uid, p, wake: true }) };
      this.core = new HubCore({ sql, copy: (b) => this.toOffice(b), r2: r2.on ? r2 : null, apns, onUnread: (uids) => { this.later('/api/talk/relay/unread', { uids }); } });
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
      if (!this.core.meta('dirAt')) await this.askDir();
      const d = this.core.dir.snapshot || {};
      return json({ ok: true, dirAt: Number(this.core.meta('dirAt') || 0) || null, people: (d.users || []).length, clients: (d.projects || []).length,
        copyN: this.core.n, waiting: this.ctx.storage.sql.exec('SELECT COUNT(*) AS c FROM hub_outbox').toArray()[0].c, officeKey: !!this.core.meta('officeKey') });
    }
    if (p.startsWith('/office/')) return this.fromOffice(req, p);
    // (the front door's memory of who each sign-in is — a fingerprint and an email; only the Worker reaches this)
    if (p === '/who-cache') {
      const sql = this.ctx.storage.sql;
      if (req.method === 'POST') { const b = await req.json(); sql.exec('INSERT OR REPLACE INTO hub_who (fp, email, at) VALUES (?, ?, ?)', b.fp, b.email, Date.now()); return json({ ok: true }); }
      const r = sql.exec('SELECT email, at FROM hub_who WHERE fp = ?', url.searchParams.get('fp') || '').toArray()[0];
      return json(r || {});
    }
    const email = req.headers.get('x-hub-email');
    if (!this.core.meta('dirAt')) await this.askDir();
    if (!email) return json({ ok: false, error: 'Who?' }, 401);
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
      case 'act': return this.core.act(w, b);
      case 'sync': return this.core.sync(w, b.after, b.limit);
      case 'ack': return this.core.ack(w, b.upto);
      case 'got': return this.core.got(w, b.groupId, b.msgId);
      case 'r2/start': return this.core.r2Start(w, b);
      case 'r2/done': return this.core.r2Done(w, b);
      case 'ask': return this.core.ask(w, b);
      case 'asks': return this.core.asks(w);
      case 'resend/start': return this.core.resendStart(w, b);
      case 'history/share': return this.core.shareHistory(w, b);
      default: return null;   // (Macs, sign-in… the office's for now)
    }
  }

  // ---------- the live line ----------
  hear(ws) {
    const a = ws.deserializeAttachment(); if (!a || !a.dev) return;
    ws.stop = this.core.listen(a.dev, (s) => { try { ws.send(s); } catch { /* closed */ } });
  }
  async webSocketMessage(ws, msg) {
    let m; try { m = JSON.parse(typeof msg === 'string' ? msg : new TextDecoder().decode(msg)); } catch { return; }
    const a = ws.deserializeAttachment() || {};
    const w = this.core.who(a.email, a.device);
    if (!w) { ws.close(4003, 'Signed out'); return; }
    const r = await this.call(w, String(m.call || ''), m.body || {});
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
      const j = r.ok ? await r.json() : null;
      if (j && j.ok && j.dir) { this.core.setDir(j.dir); this.core.meta('dir', JSON.stringify(j.dir)); }
    } catch { /* next time */ }
  }
  async alarm() {
    const last = Number(this.core.meta('sweptAt') || 0);
    if (Date.now() - last >= HOUR - 60_000) { this.core.sweep(); this.core.meta('sweptAt', Date.now()); }
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
    return { ok: true, n: this.core.n };
  }
}
