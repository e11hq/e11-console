import test from 'node:test';
import assert from 'node:assert/strict';
import { usage } from '../src/usage.js';

test('usage: the highest share of the free day, from Cloudflare’s figures', async () => {
  const seen = [];
  const go = async (url, o) => {
    const b = JSON.parse(o.body); seen.push(b);
    const x = b.query.includes('workersInvocationsAdaptive(') ? [{ sum: { requests: 2000 } }]
      : b.query.includes('durableObjectsInvocationsAdaptiveGroups') ? [{ sum: { requests: 1000 } }]
      : [{ sum: { activeTime: 3600e6, inboundWebsocketMsgCount: 2000, rowsRead: 1000, rowsWritten: 30000 } }];
    return { json: async () => ({ data: { viewer: { accounts: [{ x }] } } }) };
  };
  const r = await usage({ token: 't', account: 'acc', now: Date.UTC(2026, 10, 22, 5), go });
  assert.equal(r.ok, true); assert.equal(r.day, '2026-11-22');
  assert.equal(r.highest, 'rowsWritten'); assert.equal(r.percent, 30);
  assert.equal(r.figures.requests, 3100);
  assert.equal(seen.length, 3); assert.equal(seen[0].variables.a, 'acc');
});

test('usage: one part refused — the others still count; none — not ok', async () => {
  const half = async (url, o) => ({ json: async () => (JSON.parse(o.body).query.includes('Periodic') ? { errors: [{ message: 'no field' }] } : { data: { viewer: { accounts: [{ x: [{ sum: { requests: 5000 } }] }] } } }) });
  const r = await usage({ token: 't', account: 'a', go: half });
  assert.equal(r.ok, true); assert.equal(r.percent, 10); assert.ok(r.errors.hub);
  const none = await usage({ token: 't', account: 'a', go: async () => { throw new Error('down'); } });
  assert.equal(none.ok, false);
  assert.equal((await usage({ account: 'a' })).ok, false);
});
