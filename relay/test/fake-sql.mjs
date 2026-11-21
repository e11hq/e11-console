// A Durable Object's ctx.storage.sql, over node's own SQLite — exec(query, ...bindings) → a cursor.
import { DatabaseSync } from 'node:sqlite';
export function fakeSql(file = ':memory:') {
  const db = new DatabaseSync(file);
  return {
    db,
    exec(q, ...b) {
      const st = db.prepare(q);
      if (/^\s*(SELECT|WITH)\b/i.test(q) || /\bRETURNING\b/i.test(q)) { const rows = st.all(...b); return { toArray: () => rows, rowsWritten: 0 }; }
      try { const r = st.run(...b); return { toArray: () => [], rowsWritten: Number(r.changes) }; }
      catch (e) { if (/^\s*(CREATE|ALTER|DROP)\b/i.test(q) || true) throw e; }
    },
  };
}
