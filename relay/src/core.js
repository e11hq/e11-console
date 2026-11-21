// E11 Talk on Cloudflare — the hub's heart (TALK-CF-A, Haris 2026-11-21: claude/talk-cloudflare-relay-plan.md).
// It runs E11 Talk's own code (server/src/talk.js), unchanged, over the Durable Object's SQLite — the same rules as the
// office, never a second copy of them. What it needs from E11 Console (people, clients, who sees which client) comes
// from the office, signed (dir.js). Every write it makes is noted and handed to `copy` — the office runs the same
// statements, in the same order, and keeps a full copy. Plain JavaScript, so it's tested outside Cloudflare too.
import { createTalk } from '../../server/src/talk.js';
import { makeDir } from './dir.js';

export class HubCore {
  // sql: ctx.storage.sql (or a stand-in in tests) · copy(batch): the office's copy · now: the clock
  constructor({ sql, dir = null, copy = () => {}, now = () => Date.now() }) {
    this.sql = sql; this.copy = copy; this.now = now;
    this.dir = makeDir(dir);
    globalThis.__hubSql = sql; globalThis.__hubLog = null;
    // (Talk's hourly clean-up: run by the hub's alarm, never a timer — a timer keeps the hub awake, and awake is what the
    //  free plan counts)
    const SI = globalThis.setInterval, ST = globalThis.setTimeout;
    let sweep = null;
    globalThis.setInterval = (fn) => { sweep = fn; return { unref() {} }; };
    globalThis.setTimeout = (fn, ms) => (ms === 60_000 ? { unref() {} } : ST(fn, ms));
    try {
      this.talk = createTalk({ dataDir: '/hub', dbFile: ':memory:', store: this.dir.store, access: this.dir.access, now });
    } finally { globalThis.setInterval = SI; globalThis.setTimeout = ST; }
    this.sweepFn = sweep;
    this.n = Number(this.meta('copyN') || 0);
  }
  // small settings of the hub's own (its own table — not Talk's, never copied)
  meta(k, v) {
    this.sql.exec('CREATE TABLE IF NOT EXISTS hub_meta (k TEXT PRIMARY KEY, v TEXT)');
    if (v === undefined) { const r = this.sql.exec('SELECT v FROM hub_meta WHERE k = ?', k).toArray()[0]; return r ? r.v : null; }
    this.sql.exec('INSERT INTO hub_meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v', k, v == null ? null : String(v));
  }
  // one call into Talk: what it wrote goes to the office as one numbered batch
  run(fn) {
    globalThis.__hubSql = this.sql;
    const log = []; globalThis.__hubLog = log;
    let out;
    try { out = fn(this.talk); } finally { globalThis.__hubLog = null; }
    if (log.length) {
      this.n += 1; this.meta('copyN', this.n);
      this.copy({ n: this.n, at: this.now(), stmts: log });
    }
    return out;
  }
  // E11 Console's people and clients, from the office
  setDir(snap) { this.dir.set(snap); this.meta('dirAt', this.now()); try { this.talk.peopleChanged(); } catch { /* fine */ } }

  // who's asking: the person (team member or client contact, by the email their sign-in proved) and this phone
  who(email, deviceKey) {
    const u = this.dir.access.userByEmail(email) || this.talk.contactByEmail(email);
    if (!u || u.active === false) return null;
    const dev = deviceKey ? this.run((t) => t.phoneFor(u, deviceKey)) || u : u;
    return { u, dev };
  }
  // the same calls, with the same answers, as the office's /api/talk/… (server.js talkRoute)
  state(w) { return this.run((t) => t.state(w.u)); }
  act(w, b) { return this.run((t) => t.act(w.u, b || {}, w.dev)); }
  sync(w, after, limit) { return this.run((t) => t.sync(w.dev, after, limit)); }
  ack(w, upto) { return this.run((t) => t.ack(w.dev, upto)); }
  got(w, group, msg) { return this.run((t) => t.got(w.dev, group, msg)); }
  sweep() { if (this.sweepFn) this.run(() => this.sweepFn()); }
  // the live line: Talk writes its live events to it ("event: talk\ndata: …")
  listen(devId, write) { return this.talk.listen(devId, { write }); }
}
