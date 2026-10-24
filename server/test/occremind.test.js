import { test } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createOccasionReminders, sendDay } from '../src/occremind.js';

const webDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'web');
const dubai = (day, hm = '10:31') => Date.parse(`${day}T${hm}:00+04:00`);

function setup({ tasks = [], projects = [{ id: 'p1' }, { id: 'p2' }], meta = {} } = {}) {
  const kv = new Map();
  const users = [
    { id: 'soc', role: 'social' }, { id: 'am', role: 'am' }, { id: 'adm', role: 'admin' },
    { id: 'prod', role: 'production' }, { id: 'old', role: 'social', active: false },
  ];
  const store = {
    get: (k) => (k === 'meta' ? meta : null),
    list: (k) => ({ users, projects, tasks }[k] || []),
    kv: { get: (k) => kv.get(k), set: (k, v) => kv.set(k, v) },
  };
  const sent = [];
  const webPush = { sendTo: async (id, m) => { sent.push({ id, ...m }); return { sent: 1 }; } };
  let clock = 0;
  const r = createOccasionReminders({ store, webDir, webPush, isAdm: (u) => u.role === 'admin', now: () => clock });
  return { r, sent, at: (t) => { clock = t; } };
}

test('reminder days: 45, 30, 14 and 7 before, weekends moved to Friday', () => {
  // Christmas 2026 is a Friday: 45 → 10 Nov (Tue), 30 → 25 Nov (Wed), 14 → 11 Dec (Fri), 7 → 18 Dec (Fri)
  assert.equal(sendDay('2026-12-25', 45), '2026-11-10');
  assert.equal(sendDay('2026-12-25', 7), '2026-12-18');
  // UAE National Day 2 Dec 2026: 30 before is Mon 2 Nov; 7 before is Wed 25 Nov; 14 before is Wed 18 Nov
  assert.equal(sendDay('2026-12-02', 30), '2026-11-02');
  // a Saturday moves to Friday, a Sunday too
  assert.equal(sendDay('2026-12-19', 7), '2026-12-11');     // 12 Dec is a Saturday
  assert.equal(sendDay('2026-12-20', 7), '2026-12-11');     // 13 Dec is a Sunday
});

test('Social, AMs and Admins get it at 10:30, once; Production and inactive people do not', async () => {
  const { r, sent, at } = setup();
  at(dubai('2026-11-10', '10:29'));
  assert.equal(await r.tick(), 0);
  at(dubai('2026-11-10'));
  await r.tick();
  const xmas = sent.filter((m) => m.title === 'Christmas in 45 days');
  assert.deepEqual(xmas.map((m) => m.id).sort(), ['adm', 'am', 'soc']);
  assert.match(xmas[0].body, /25 Dec · Nothing planned yet\. Tap to plan\./);
  assert.equal(xmas[0].view, 'calendar');
  const before = sent.length;
  await r.tick();
  assert.equal(sent.length, before, 'never sent twice');
});

test('says how many clients have posts planned; skipped when every client has', async () => {
  const one = setup({ tasks: [{ id: 't1', projectId: 'p1', occasion: 'christmas-2026' }] });
  one.at(dubai('2026-11-25'));
  await one.r.tick();
  const m = one.sent.find((x) => x.title === 'Christmas in 30 days');
  assert.match(m.body, /1 of 2 clients have posts planned/);

  const all = setup({ tasks: [{ id: 't1', projectId: 'p1', occasion: 'christmas-2026' }, { id: 't2', projectId: 'p2', occasion: 'christmas-2026' }] });
  all.at(dubai('2026-11-25'));
  await all.r.tick();
  assert.equal(all.sent.filter((x) => x.title.startsWith('Christmas')).length, 0);
});

test('the open app gets the same list, only for people who should', () => {
  const { r, at } = setup();
  at(dubai('2026-11-10'));
  assert.ok(r.forUser({ id: 'soc', role: 'social' }).list.some((x) => x.name === 'Christmas'));
  assert.equal(r.forUser({ id: 'prod', role: 'production' }).list.length, 0);
  at(dubai('2026-11-10', '09:00'));
  assert.equal(r.forUser({ id: 'soc', role: 'social' }).list.length, 0);
});

test('custom occasions and corrected dates are included', async () => {
  const { r, sent, at } = setup({ meta: { occasions: [{ id: 'occ-x-2027', name: 'Ford anniversary', date: '2027-01-14' }] } });
  at(dubai('2026-12-31'));   // 14 days before 14 Jan
  await r.tick();
  assert.ok(sent.some((m) => m.title === 'Ford anniversary in 14 days'));
});
