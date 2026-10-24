import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { parseIcs } from '../src/holidays.js';

const ics = (events) => ['BEGIN:VCALENDAR', ...events.flatMap(([d, s]) => ['BEGIN:VEVENT', `DTSTART;VALUE=DATE:${d.replace(/-/g, '')}`, `SUMMARY:${s}`, 'END:VEVENT']), 'END:VCALENDAR'].join('\r\n');
let feed = '', feedOk = true;
const pushed = [];
let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11h-'));
  app = createServer({
    dataDir: dir, dev: true, digest: false, holidays: false, now: () => Date.parse('2026-10-24T08:00:00Z'),
    webDir: path.resolve('../web'),
    holidaysFetch: async () => (feedOk ? { ok: true, text: async () => feed } : { ok: false, status: 503 }),
    pushFetch: async (url, opts) => { pushed.push(url); return { status: 201 }; },
  });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({ users: [
    { id: 'u-am', email: 'areej@e11-digital.com', role: 'am', active: true, name: 'Areej' },
    { id: 'u-so', email: 'zahir@e11-digital.com', role: 'social', active: true, name: 'Zahir' },
  ], meta: { occDates: { 'hijri-2027': { date: '2027-06-07', end: null } } } }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const call = async (who, p, body) => {
  const res = await fetch(base + p, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};

test('reads events from a calendar file, folded lines included', () => {
  const e = parseIcs('BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20270309\r\nSUMMARY:Eid al-Fitr\r\n  Holiday\r\nEND:VEVENT');
  assert.deepEqual(e, [{ date: '2027-03-09', summary: 'Eid al-Fitr Holiday' }]);
});

test('confirmed dates replace the estimates; tentative ones and dates set by hand are left alone', async () => {
  feed = ics([
    ['2027-02-09', 'Ramadan Start'], ['2027-03-11', 'Eid al-Fitr'], ['2027-03-12', 'Eid al-Fitr Holiday'],
    ['2027-05-15', 'Arafat Day (tentative)'], ['2027-05-16', 'Eid al-Adha'], ['2027-06-06', 'Islamic New Year'], ['2026-12-02', 'National Day'],
  ]);
  const r = await call('areej@e11-digital.com', '/api/holidays', {});
  assert.equal(r.status, 200);
  assert.equal(r.body.ok, true);
  const fix = app.store.get('meta', 'main').occDates;
  assert.deepEqual(fix['ramadan-2027'], { date: '2027-02-09', end: '2027-03-10', auto: true, at: fix['ramadan-2027'].at });
  assert.equal(fix['eidfitr-2027'].date, '2027-03-11');
  assert.equal(fix['eidfitr-2027'].end, '2027-03-13', 'the Eid keeps its 3 days');
  assert.equal(fix['eidadha-2027'].date, '2027-05-16', 'same as the estimate: marked confirmed');
  assert.equal(fix['arafat-2027'], undefined, 'tentative dates are not confirmations');
  assert.deepEqual(fix['hijri-2027'], { date: '2027-06-07', end: null }, 'a date set by hand is never overwritten');
  assert.deepEqual(r.body.changed.map((c) => c.id).sort(), ['eidfitr-2027', 'ramadan-2027']);
  assert.deepEqual(r.body.tentativeList, [{ name: 'Arafat Day', date: '2027-05-15' }], 'tentative dates are listed so people can see they were read');
});

test('checking again with the same calendar changes nothing', async () => {
  const before = JSON.stringify(app.store.get('meta', 'main').occDates);
  await call('areej@e11-digital.com', '/api/holidays', {});
  assert.equal(JSON.stringify(app.store.get('meta', 'main').occDates), before);
});

test('if the calendar cannot be read, the estimates stay and the reason is shown', async () => {
  feedOk = false;
  const r = await call('areej@e11-digital.com', '/api/holidays', {});
  assert.equal(r.body.ok, false);
  assert.match(r.body.error, /503/);
  assert.equal(app.store.get('meta', 'main').occDates['eidfitr-2027'].date, '2027-03-11');
  feedOk = true;
});

test('only Admins and Account Managers can check', async () => {
  assert.equal((await call('zahir@e11-digital.com', '/api/holidays')).status, 403);
  assert.equal((await call('areej@e11-digital.com', '/api/holidays')).status, 200);
});
