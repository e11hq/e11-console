// Data store: one SQLite file (built into Node 22). Every item (task, project, user, client,
// notification, status, settings) is a row holding its JSON. A global revision number goes up
// with every change so apps can ask "what changed since revision N?".
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import { merge3, deepEqual } from './merge.js';

export const KINDS = ['users', 'projects', 'tasks', 'clients', 'notifications', 'statuses', 'trash', 'meta', 'finance', 'claims', 'plans', 'scheduled'];

export function openStore(file) {
  if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    PRAGMA busy_timeout = 5000;
    CREATE TABLE IF NOT EXISTS entities (
      kind TEXT NOT NULL, id TEXT NOT NULL, data TEXT, deleted INTEGER NOT NULL DEFAULT 0,
      rev INTEGER NOT NULL, updated_at TEXT NOT NULL, updated_by TEXT,
      PRIMARY KEY (kind, id)
    );
    CREATE INDEX IF NOT EXISTS entities_rev ON entities(rev);
    CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    INSERT OR IGNORE INTO kv(key, value) VALUES ('rev', '0'), ('schema', '1');
  `);
  const q = {
    rev: db.prepare(`SELECT value FROM kv WHERE key = 'rev'`),
    setRev: db.prepare(`UPDATE kv SET value = ? WHERE key = 'rev'`),
    get: db.prepare(`SELECT kind, id, data, deleted, rev FROM entities WHERE kind = ? AND id = ?`),
    put: db.prepare(`INSERT INTO entities(kind, id, data, deleted, rev, updated_at, updated_by) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(kind, id) DO UPDATE SET data = excluded.data, deleted = excluded.deleted, rev = excluded.rev, updated_at = excluded.updated_at, updated_by = excluded.updated_by`),
    all: db.prepare(`SELECT kind, id, data FROM entities WHERE deleted = 0`),
    since: db.prepare(`SELECT kind, id, data, deleted, rev FROM entities WHERE rev > ? ORDER BY rev`),
    kind: db.prepare(`SELECT id, data FROM entities WHERE kind = ? AND deleted = 0`),
    kvGet: db.prepare(`SELECT value FROM kv WHERE key = ?`),
    kvSet: db.prepare(`INSERT INTO kv(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value`),
  };
  const parse = (row) => (row && row.data ? JSON.parse(row.data) : null);
  const currentRev = () => Number(q.rev.get().value);

  function tx(fn) {
    db.exec('BEGIN IMMEDIATE');
    try { const r = fn(); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; }
  }

  return {
    db,
    rev: currentRev,
    get(kind, id) { const r = q.get.get(kind, String(id)); return r && !r.deleted ? parse(r) : null; },
    list(kind) { return q.kind.all(kind).map(parse); },
    kv: { get: (k) => { const r = q.kvGet.get(k); return r ? r.value : null; }, set: (k, v) => q.kvSet.run(k, String(v)) },
    // Whole data set, shaped like the app's data file
    snapshot() {
      const out = { meta: {} };
      KINDS.filter((k) => k !== 'meta').forEach((k) => { out[k] = []; });
      for (const r of q.all.all()) {
        if (r.kind === 'meta') out.meta = JSON.parse(r.data);
        else if (out[r.kind]) out[r.kind].push(JSON.parse(r.data));
      }
      return { rev: currentRev(), data: out };
    },
    since(rev) {
      return q.since.all(Number(rev) || 0).map((r) => ({ kind: r.kind, id: r.id, rev: r.rev, deleted: !!r.deleted, data: r.deleted ? null : parse(r) }));
    },
    // Apply a batch of changes. `check(change, current)` may return false (refuse) for each one.
    // Returns the stored result of every change so the app can update its copy.
    apply(changes, userId, check = () => true) {
      return tx(() => {
        let rev = currentRev();
        const now = new Date().toISOString();
        const results = [];
        for (const ch of changes) {
          if (!KINDS.includes(ch.kind) || ch.id == null) continue;
          const id = String(ch.id);
          const row = q.get.get(ch.kind, id);
          const current = row && !row.deleted ? parse(row) : null;
          if (!check(ch, current)) {
            results.push({ kind: ch.kind, id, refused: true, deleted: !current, data: current, rev: row ? row.rev : 0 });
            continue;
          }
          if (ch.del) {
            if (!current) { results.push({ kind: ch.kind, id, deleted: true, rev: row ? row.rev : 0 }); continue; }
            rev += 1;
            q.put.run(ch.kind, id, null, 1, rev, now, userId || null);
            results.push({ kind: ch.kind, id, deleted: true, rev });
            continue;
          }
          let data = ch.data;
          if (current && ch.base !== undefined) data = merge3(ch.base, ch.data, current);
          if (current && deepEqual(current, data)) { results.push({ kind: ch.kind, id, data: current, rev: row.rev, unchanged: true }); continue; }
          rev += 1;
          q.put.run(ch.kind, id, JSON.stringify(data), 0, rev, now, userId || null);
          results.push({ kind: ch.kind, id, data, rev });
        }
        q.setRev.run(String(rev));
        return { rev, results };
      });
    },
    // Load a full data file (used once when moving from the Mac app to the server)
    importAll(data, userId) {
      const changes = [];
      KINDS.forEach((k) => {
        if (k === 'meta') { if (data.meta) changes.push({ kind: 'meta', id: 'main', data: data.meta }); return; }
        (data[k] || []).forEach((x) => { if (x && x.id != null) changes.push({ kind: k, id: x.id, data: x }); });
      });
      return this.apply(changes, userId);
    },
    backup(file) { fs.mkdirSync(path.dirname(file), { recursive: true }); db.exec(`VACUUM INTO '${file.replace(/'/g, "''")}'`); return file; },
    close() { db.close(); },
  };
}
