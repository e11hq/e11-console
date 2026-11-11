// The Office Admin's pages on the iPhone, fully Apple (Haris 2026-11-11, "A–I go for it", "use same function we have"):
// the claims of any of the last 12 months (B1), who has none / hasn't answered (D1), a claim opened (E1), the ended
// subscriptions and the missing invoices (F1), and the website's own actions — all at once (C1), an invoice added
// afterwards, an office expense removed.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { createMoneyActs } from '../src/appact-money.js';

const src = ['rules.js', 'appview.js', 'appme-money.js'].map((f) => fs.readFileSync(new URL('../../web/' + f, import.meta.url), 'utf8')).join(';\n');
const engine = () => vm.runInNewContext(`${src}; ({ E11Rules, E11AppMe })`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN, encodeURIComponent, RegExp });
const NOW = Date.parse('2026-11-11T08:00:00Z');   // (Dubai: Nov 11 — the claim month is November)
const data = () => ({
  users: [
    { id: 'u-oa', name: 'Arsal Office', email: 'oa@x.test', role: 'office_admin', fin: 'admin', active: true },
    { id: 'u-om', name: 'Omar Khalil', email: 'om@x.test', role: 'production', active: true },
    { id: 'u-sr', name: 'Sam Rivers', email: 'sr@x.test', role: 'production', active: true },
    { id: 'u-rh', name: 'Rana Haddad', email: 'rh@x.test', role: 'am', active: true },
    { id: 'u-kd', name: 'Karim Dar', email: 'kd@x.test', role: 'social', active: true },
  ],
  projects: [], tasks: [], meta: {}, clients: [],
  claims: [
    { id: 'c1', userId: 'u-om', month: '2026-11', state: 'submitted', submittedAt: '2026-11-08T09:00:00Z',
      groups: [{ id: 'g1', date: '2026-11-03', title: 'Client meeting', items: [{ id: 'i1', desc: 'Taxi', amount: 48, receipt: { path: 'Claims/r1.jpg', name: 'r1.jpg' } }, { id: 'i2', desc: 'Lunch', amount: 210 }] }] },
    { id: 'c2', userId: 'u-sr', month: '2026-11', state: 'approved', submittedAt: '2026-11-07T09:00:00Z', groups: [{ id: 'g2', date: '2026-11-02', title: 'Supplies', items: [{ id: 'i3', desc: 'Tape', amount: 95 }] }] },
    { id: 'c3', userId: 'u-rh', month: '2026-11', state: 'none' },
    { id: 'c4', userId: 'u-om', month: '2026-10', state: 'paid', paidOn: '2026-10-30', submittedAt: '2026-10-20T09:00:00Z', groups: [{ id: 'g4', date: '2026-10-10', title: 'Old', items: [{ id: 'i4', desc: 'Old taxi', amount: 30 }] }] },
  ],
  finance: [
    { id: 's1', type: 'sub', name: 'Canva Pro', amount: 55, day: 5, startMonth: '2026-09', invoices: { '2026-11': { path: 'Finance/Subscriptions/2026-11/c.pdf', name: 'c.pdf' } }, endedAt: null },
    { id: 's2', type: 'sub', name: 'Slack Pro', amount: 95, day: 1, startMonth: '2026-06', invoices: {}, endedAt: '2026-10-31T10:00:00Z' },
    { id: 'e1', type: 'expense', name: 'Studio lights', amount: 840, date: '2026-11-06', invoice: null },
    { id: 'e2', type: 'expense', name: 'Water', amount: 180, date: '2026-10-02', invoice: null },
    { id: 'r9', type: 'reimb', userId: 'u-sr', claimId: 'c2', amount: 95, date: '2026-11-09' },
  ],
});
const run = (fn, ...args) => { const { E11Rules: R, E11AppMe: M } = engine(); return JSON.parse(JSON.stringify(M[fn](R, data(), 'u-oa', NOW, ...args))); };

test('Claims: the claim month first, any of the last 12 picked; No claims and Not answered yet', () => {
  const m = run('claims');
  assert.equal(m.month, '2026-11');
  assert.equal(m.pick.length, 12); assert.equal(m.pick[0].m, '2026-11'); assert.equal(m.pick[11].m, '2025-12');
  assert.deepEqual(m.need.map((r) => r.id), ['c1']);
  assert.deepEqual(m.all.map((r) => r.id), ['c1', 'c2']);
  assert.deepEqual(m.none.map((r) => r.name), ['Rana Haddad']);
  assert.deepEqual(m.waiting.map((r) => r.name), ['Arsal Office', 'Karim Dar']);
  assert.equal(m.open, 2); assert.equal(m.toApprove, 1);
  assert.match(m.foot, /Open until 27 November/);
  const oct = run('claims', '2026-10');
  assert.deepEqual(oct.all.map((r) => r.id), ['c4']);
  assert.equal(oct.waiting.length, 0);   // (a closed month: nobody's waited for)
  assert.match(oct.foot, /This month is closed/);
  assert.equal(run('claims', '2020-01').month, '2026-11');   // (not one of the 12: the claim month)
});

test('A claim opened: its items by day, each receipt a file', () => {
  const c = run('claim', 'c1');
  assert.equal(c.name, 'Omar Khalil'); assert.equal(c.amt, '⃃258.00'); assert.equal(c.pill, 'Submitted');
  assert.equal(c.groups.length, 1); assert.equal(c.groups[0].items.length, 2);
  assert.equal(c.groups[0].items[0].receipt.path, 'Claims/r1.jpg'); assert.equal(c.groups[0].items[1].receipt, null);
  assert.equal(run('claim', 'c3').gone, true);
});

test('Expenses: subscriptions with this month’s invoice and the missing ones, the ended apart, any month’s office expenses', () => {
  const x = run('expenses');
  assert.deepEqual(x.subs.map((s) => s.name), ['Canva Pro']);
  assert.deepEqual(x.subs[0].missing.map((m) => m.m), ['2026-09', '2026-10']);
  assert.equal(x.subs[0].lk, 'miss'); assert.equal(x.subs[0].inv, true);
  assert.deepEqual(x.ended.map((s) => s.name), ['Slack Pro']); assert.match(x.ended[0].sub, /^Ended Oct 31/);
  assert.deepEqual(x.office.map((o) => o.name), ['Studio lights']);
  assert.deepEqual(run('expenses', '2026-10').office.map((o) => o.name), ['Water']);
});

const store = (d) => ({ get: (k, id) => (d[k] || []).find((x) => String(x.id) === String(id)) || null, list: (k) => d[k] || [] });
const acts = () => createMoneyActs({ store: store(data()), now: NOW });
const OA = { id: 'u-oa', role: 'office_admin', fin: 'admin' }, PROD = { id: 'u-om', role: 'production' };

test('Mark All HR Approved and Set All Paid On: several claims at once, the same rules as one', () => {
  const a = acts().clApprove(OA, { ids: ['c1', 'c2', 'c4'] });
  assert.equal(a.ok, true); assert.equal(a.answer.n, 1);   // (only the Submitted one)
  const p = acts().clPaid(OA, { ids: ['c1', 'c2', 'c4'], date: '2026-11-10' });
  assert.equal(p.ok, true); assert.equal(p.answer.n, 2); assert.equal(p.answer.text, '2 claims marked paid');
  assert.equal(acts().clApprove(PROD, { ids: ['c1'] }).ok, false);
  assert.equal(acts().clApprove(OA, { id: 'c1' }).answer.n, 1);   // (one, as before)
});

test('An invoice added afterwards; an office expense removed (a subscription is ended, never removed)', () => {
  const f = { path: 'Finance/Subscriptions/2026-10/x.pdf', name: 'x.pdf', size: 10 };
  const s = acts().exInv(OA, { id: 's1', month: '2026-10', invoice: f });
  assert.equal(s.ok, true); assert.equal(s.changes[0].data.invoices['2026-10'].path, f.path); assert.ok(s.changes[0].data.invoices['2026-11']);
  const e = acts().exInv(OA, { id: 'e1', invoice: f });
  assert.equal(e.changes[0].data.invoice.path, f.path);
  assert.equal(acts().exInv(OA, { id: 'r9', invoice: f }).ok, false);   // (a claim's payment: its claim is its paper)
  assert.equal(acts().exInv(PROD, { id: 'e1', invoice: f }).ok, false);
  const d = acts().exDel(OA, { id: 'e1' });
  assert.equal(d.ok, true); assert.equal(d.changes[0].del, true);
  assert.equal(acts().exDel(OA, { id: 's1' }).ok, false);
  assert.equal(acts().exDel(OA, { id: 'r9' }).ok, false);
});
