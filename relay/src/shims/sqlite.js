// node:sqlite's DatabaseSync, as E11 Talk's own code (server/src/talk.js) uses it, over a Durable Object's SQLite
// (ctx.storage.sql). The hub sets globalThis.__hubSql before it makes Talk. Every write is also noted, statement and
// values exactly as run, in globalThis.__hubLog — the office's copy runs the same statements, in the same order
// (TALK-CF-A, Haris 2026-11-21). PRAGMAs are the office's own file settings: not here.
const norm = (a) => a.map((v) => (v === undefined ? null : typeof v === 'boolean' ? (v ? 1 : 0) : typeof v === 'bigint' ? Number(v) : v));
const split = (text) => String(text).split(';').map((s) => s.trim()).filter(Boolean);
const writes = (t) => !/^\s*(SELECT|WITH\s[\s\S]*?\bSELECT)\b/i.test(t);

export class DatabaseSync {
  constructor() {
    this.sql = globalThis.__hubSql;
    if (!this.sql) throw new Error('E11 Talk hub: no database');
  }
  exec(text) { for (const s of split(text)) if (!/^PRAGMA\b/i.test(s)) this.sql.exec(s); }
  prepare(text) {
    const sql = this.sql;
    const note = (args) => { const log = globalThis.__hubLog; if (log && writes(text)) log.push([text, args]); };
    return {
      get: (...a) => { const v = norm(a); const r = sql.exec(text, ...v).toArray(); note(v); return r[0]; },
      all: (...a) => { const v = norm(a); const r = sql.exec(text, ...v).toArray(); note(v); return r; },
      run: (...a) => {
        const v = norm(a);
        const c = sql.exec(text, ...v); c.toArray();
        const id = sql.exec('SELECT last_insert_rowid() AS i').toArray()[0].i;
        note(v);
        return { changes: c.rowsWritten ?? 0, lastInsertRowid: id };
      },
    };
  }
  close() {}
}
