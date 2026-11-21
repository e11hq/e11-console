// E11 Talk on Cloudflare — the hub's heart (TALK-CF-A, Haris 2026-11-21: claude/talk-cloudflare-relay-plan.md).
// It runs E11 Talk's own code (server/src/talk.js), unchanged, over the Durable Object's SQLite — the same rules as the
// office, never a second copy of them. What it needs from E11 Console (people, clients, who sees which client) comes
// from the office, signed (dir.js). Every write it makes is noted and handed to `copy` — the office runs the same
// statements, in the same order, and keeps a full copy. Plain JavaScript, so it's tested outside Cloudflare too.
import { createTalk } from '../../server/src/talk.js';
import { makeDir } from './dir.js';

export class HubCore {
  // sql: ctx.storage.sql (or a stand-in in tests) · copy(batch): the office's copy · now: the clock
  // r2: files through R2 (r2.js) — null: none here
  constructor({ sql, dir = null, copy = () => {}, now = () => Date.now(), r2 = null }) {
    this.sql = sql; this.copy = copy; this.now = now;
    this.dir = makeDir(dir);
    globalThis.__hubSql = sql; globalThis.__hubLog = null;   // (Talk's own tables made: the office has them already)
    // (Talk's hourly clean-up: run by the hub's alarm, never a timer — a timer keeps the hub awake, and awake is what the
    //  free plan counts)
    const SI = globalThis.setInterval, ST = globalThis.setTimeout;
    let sweep = null;
    globalThis.setInterval = (fn) => { sweep = fn; return { unref() {} }; };
    globalThis.setTimeout = (fn, ms) => (ms === 60_000 ? { unref() {} } : ST(fn, ms));
    try {
      this.talk = createTalk({ dataDir: '/hub', dbFile: ':memory:', store: this.dir.store, access: this.dir.access, now, r2 });
    } finally { globalThis.setInterval = SI; globalThis.setTimeout = ST; }
    this.sweepFn = sweep;
    this.n = Number(this.meta('copyN') || 0);
    // every write from here on, in the order it ran — calls that wait for R2 may run side by side, so it's one list for
    // the whole hub, not one per call; what's there after a call goes to the office
    this.log = []; globalThis.__hubLog = this.log;
  }
  // small settings of the hub's own (its own table — not Talk's, never copied)
  meta(k, v) {
    this.sql.exec('CREATE TABLE IF NOT EXISTS hub_meta (k TEXT PRIMARY KEY, v TEXT)');
    if (v === undefined) { const r = this.sql.exec('SELECT v FROM hub_meta WHERE k = ?', k).toArray()[0]; return r ? r.v : null; }
    this.sql.exec('INSERT INTO hub_meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v', k, v == null ? null : String(v));
  }
  // one call into Talk (waiting for R2 or not): what was written goes to the office as numbered batches, in order
  run(fn) {
    globalThis.__hubSql = this.sql; globalThis.__hubLog = this.log;
    let out;
    try { out = fn(this.talk); } catch (e) { this.ship(); throw e; }
    if (out && typeof out.then === 'function') return out.finally(() => this.ship());
    this.ship();
    return out;
  }
  ship() {
    if (!this.log.length) return;
    const stmts = this.log.splice(0);
    this.n += 1; this.meta('copyN', this.n);
    this.copy({ n: this.n, at: this.now(), stmts });
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
  // files (R2) — the same calls as the office's
  r2Start(w, b) { return this.run((t) => t.r2Start(w.u, b.name, b.size, b.keep === true)); }
  r2Done(w, b) { return this.run((t) => t.r2Done(w.u, b.id, b.etags, b.back ? { key: b.key, lock: b.lock } : null)); }
  ask(w, b) { return this.run((t) => t.ask(w.u, w.dev, b.group, b.file)); }
  asks(w) { return this.run((t) => t.asksFor(w.u, w.dev)); }
  resendStart(w, b) { return this.run((t) => t.resendStart(w.u, w.dev, b.file, b.size)); }
  shareHistory(w, b) { return this.run((t) => t.shareHistory(w.u, b.group, b.to, b.msgs, b.keys, b.since)); }
  // a file this phone may have: its place in R2 (and counted as fetched, as the office does for ?r2=1)
  fileFor(w, id) { return this.run((t) => t.fileFor(w.dev, id)); }
  fetched(w, id) { return this.run((t) => t.fetched(w.dev, id)); }
  // the live line: Talk writes its live events to it ("event: talk\ndata: …")
  listen(devId, write) { return this.talk.listen(devId, { write }); }
}
