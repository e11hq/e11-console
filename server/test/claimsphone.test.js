// Expense claims on the iPhone (Haris 2026-11-10): everyone's own claim approved / paid / added by hand reaches the phone;
// the team's submitted claims only an Office Admin with finance access; the rest of the Inbox as before.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const R = require('../../web/rules.js');

test('which claim notifications reach the phone', () => {
  const prod = { id: 'p', role: 'production' }, oa = { id: 'o', role: 'office_admin', fin: 'admin' }, oaNo = { id: 'q', role: 'office_admin' }, fa = { id: 'f', role: 'finance_admin' };
  for (const k of ['claim-ok', 'claim-paid', 'claim-hand']) assert.equal(R.onPhone({ kind: k }, prod), true, k);
  assert.equal(R.onPhone({ kind: 'claim' }, oa), true);
  assert.equal(R.onPhone({ kind: 'claim' }, oaNo), false);
  assert.equal(R.onPhone({ kind: 'claim' }, fa), false);
  assert.equal(R.onPhone({ kind: 'claim' }, prod), false);
  assert.equal(R.onPhone({ kind: 'comment' }, prod), true);
});

test('the app\'s Inbox has them as the phone does', () => {
  const db = { users: [{ id: 'o', role: 'office_admin', fin: 'viewer', name: 'Om' }, { id: 'p', role: 'production', name: 'Pa' }], projects: [], tasks: [],
    notifications: [
      { id: 'n1', to: 'o', from: 'p', kind: 'claim', text: 'submitted their October expense claim', at: '2026-11-01T08:00:00Z' },
      { id: 'n2', to: 'p', from: 'o', kind: 'claim-ok', text: 'marked your October expense claim <b>HR approved</b>', at: '2026-11-01T08:00:00Z' },
      { id: 'n3', to: 'p', from: 'o', kind: 'claim', text: 'x', at: '2026-11-01T08:00:00Z' },
    ] };
  assert.deepEqual(R.make(db, 'o', '2026-11-10').inbox('all').rows.map((r) => r.id), ['n1']);
  assert.deepEqual(R.make(db, 'p', '2026-11-10').inbox('all').rows.map((r) => r.id), ['n2']);
});
