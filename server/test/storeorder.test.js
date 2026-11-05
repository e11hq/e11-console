// The store gives every kind back in the order it was first saved — the page's own order. Asked by kind alone, SQLite
// walked the (kind, id) key and gave statuses by id (CTR first), so the iPhone app's new tasks landed in CTR
// (Haris 2026-11-05).
import test from 'node:test';
import assert from 'node:assert/strict';
import { openStore } from '../src/store.js';

test('statuses come back To do first, as saved', () => {
  const s = openStore(':memory:');
  const st = [['st-todo', 'To do'], ['st-progress', 'In progress'], ['st-review', 'Review'], ['st-ctr', 'CTR'], ['st-done', 'Done']];
  s.importAll({ statuses: st.map(([id, name]) => ({ id, name })) });
  const want = st.map((x) => x[1]);
  assert.deepEqual(s.list('statuses').map((x) => x.name), want);
  assert.deepEqual(s.snapshot().data.statuses.map((x) => x.name), want);
  s.close();
});
