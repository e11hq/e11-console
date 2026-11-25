// node:sqlite's DatabaseSync, as E11 Talk's own code (server/src/talk.js) uses it, over a Durable Object's SQLite
// (ctx.storage.sql). The hub sets globalThis.__hubSql before it makes Talk. Every write is also noted, statement and
// values exactly as run, in globalThis.__hubLog — the office's copy runs the same statements, in the same order
// (TALK-CF-A, Haris 2026-11-21). PRAGMAs are the office's own file settings: not here.
const norm = (a) => a.map((v) => (v === undefined ? null : typeof v === 'boolean' ? (v ? 1 : 0) : typeof v === 'bigint' ? Number(v) : v));
const split = (text) => String(text).split(';').map((s) => s.trim()).filter(Boolean);
// (a statement that read more than 500 rows: said in the Worker's log — the rows and the statement's start — to find
//  what reads Cloudflare's rows-read; logging only, nothing else changes: Haris 2026-11-25 12:39)
const heavy = (c, text) => { try { const n = c.rowsRead || 0; globalThis.__rows = (globalThis.__rows || 0) + n; if (n > 500) console.log(`[rows] ${n} ${String(text).replace(/\s+/g, ' ').slice(0, 160)}`); } catch { /* fine */ } };
const writes = (t) => !/^\s*(SELECT|WITH\s[\s\S]*?\bSELECT)\b/i.test(t);

export class DatabaseSync {
  constructor() {
    this.sql = globalThis.__hubSql;
    if (!this.sql) throw new Error('E11 Talk hub: no database');
  }
  exec(text) { for (const s of split(text)) if (!/^PRAGMA\b/i.test(s)) { const c = this.sql.exec(s); c.toArray(); heavy(c, s); } }
  prepare(text) {
    const sql = this.sql;
    const note = (args) => { const log = globalThis.__hubLog; if (log && writes(text)) log.push([text, args]); };
    return {
      get: (...a) => { const v = norm(a); const c = sql.exec(text, ...v), r = c.toArray(); heavy(c, text); note(v); return r[0]; },
      all: (...a) => { const v = norm(a); const c = sql.exec(text, ...v), r = c.toArray(); heavy(c, text); note(v); return r; },
      run: (...a) => {
        const v = norm(a);
        const c = sql.exec(text, ...v); c.toArray(); heavy(c, text);
        const id = sql.exec('SELECT last_insert_rowid() AS i').toArray()[0].i;
        note(v);
        return { changes: c.rowsWritten ?? 0, lastInsertRowid: id };
      },
    };
  }
  close() {}
}
