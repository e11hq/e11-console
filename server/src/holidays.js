// Confirmed dates for moon-based occasions. Twice a day the server reads a public UAE holiday calendar
// (Google's "Holidays in United Arab Emirates" by default; HOLIDAYS_ICS_URL changes it) and, when it lists a
// confirmed date for Ramadan, Eid al-Fitr, Arafat Day, Eid al-Adha, Islamic New Year or the Prophet's Birthday
// that differs from the app's estimate, saves it in meta.occDates[id] = { date, end, auto: true, at }.
// A date an Admin or Account Manager corrected by hand (no `auto`) is never touched. If the calendar can't be
// read, nothing changes and the app keeps its estimates.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

export const DEFAULT_HOLIDAYS_URL = 'https://calendar.google.com/calendar/ical/en.ae%23holiday%40group.v.calendar.google.com/public/basic.ics';

const KEYS = [
  ['ramadan', /ramad(h)?an/i, /end|last/i],
  ['eidfitr', /eid\s*(al|ul|-)?[\s-]*fitr/i, null],
  ['arafat', /arafat|arafah/i, null],
  ['eidadha', /eid\s*(al|ul|-)?[\s-]*adha/i, null],
  ['hijri', /(hijri|islamic|hijra)\s*new\s*year|muharram/i, null],
  ['mawlid', /prophet|mawlid|milad/i, null],
];

// RFC 5545, just enough: unfold lines, read SUMMARY and DTSTART of each event
export function parseIcs(text) {
  const lines = String(text || '').replace(/\r\n[ \t]/g, '').replace(/\n[ \t]/g, '').split(/\r?\n/);
  const out = [];
  let ev = null;
  for (const l of lines) {
    if (l === 'BEGIN:VEVENT') ev = {};
    else if (l === 'END:VEVENT') { if (ev && ev.summary && ev.date) out.push(ev); ev = null; }
    else if (ev) {
      const m = /^([A-Z-]+)(;[^:]*)?:(.*)$/.exec(l);
      if (!m) continue;
      if (m[1] === 'SUMMARY') ev.summary = m[3].replace(/\\,/g, ',').replace(/\\;/g, ';').trim();
      if (m[1] === 'DTSTART') { const d = /(\d{4})(\d{2})(\d{2})/.exec(m[3]); if (d) ev.date = `${d[1]}-${d[2]}-${d[3]}`; }
    }
  }
  return out;
}

const DAY = 86400000;
const toT = (s) => Date.parse(s + 'T00:00:00Z');
const plus = (s, n) => new Date(toT(s) + n * DAY).toISOString().slice(0, 10);
const diff = (a, b) => Math.round((toT(b) - toT(a)) / DAY);

export function createHolidaySync({ store, webDir, url = DEFAULT_HOLIDAYS_URL, fetchImpl = fetch, now = () => Date.now(), log = console, onChange = () => {} }) {
  // the app's own occasion list (web/calendar.js), so the server and the app agree on ids and estimates
  function occasions(meta) {
    const src = fs.readFileSync(path.join(webDir, 'calendar.js'), 'utf8').split('const Cal =')[0];
    return vm.runInNewContext(`${src}; Occasions`, { db: { meta }, Intl, Date, Math, Number, String, Object, Array, JSON, parseInt });
  }
  const status = () => { try { return JSON.parse(store.kv.get('holiday-sync') || '{}'); } catch { return {}; } };
  const saveStatus = (s) => store.kv.set('holiday-sync', JSON.stringify(s));

  async function check() {
    const at = new Date(now()).toISOString();
    let events;
    try {
      const res = await fetchImpl(url, { headers: { 'User-Agent': 'E11 Console' } });
      if (!res.ok) throw new Error(`The holiday calendar answered ${res.status}`);
      events = parseIcs(await res.text());
      if (!events.length) throw new Error('The holiday calendar was empty');
    } catch (e) {
      const s = { ...status(), at, ok: false, error: e.message };
      saveStatus(s); log.error('Holiday check failed:', e.message);
      return s;
    }
    const today = new Date(now() + 4 * 3600000).toISOString().slice(0, 10);   // Dubai
    const from = plus(today, -30), to = plus(today, 420);
    // confirmed dates from the calendar, earliest per key and cluster ("Eid al-Fitr" plus its holiday days)
    const found = [];
    for (const [key, re, not] of KEYS) {
      const hits = events.filter((e) => re.test(e.summary) && !(not && not.test(e.summary)) && !/tentative|expected|estimated/i.test(e.summary) && e.date >= from && e.date <= to)
        .map((e) => e.date).sort();
      hits.forEach((d) => { if (!found.some((f) => f.key === key && Math.abs(diff(f.date, d)) <= 10)) found.push({ key, date: d }); });
    }
    // listed but not final yet (e.g. "Eid al-Fitr (tentative)"): shown on the calendar page so people know they were read
    const tentative = [];
    for (const [key, re, not] of KEYS) {
      events.filter((e) => re.test(e.summary) && !(not && not.test(e.summary)) && /tentative|expected|estimated/i.test(e.summary) && e.date >= today && e.date <= to)
        .forEach((e) => { if (!tentative.some((t) => t.key === key && Math.abs(diff(t.date, e.date)) <= 10)) tentative.push({ key, date: e.date, summary: e.summary }); });
    }
    const meta = { ...(store.get('meta', 'main') || {}) };
    const fixes = { ...(meta.occDates || {}) };
    const O = occasions({ ...meta, occDates: {} });   // the app's own estimates, before any correction
    const changed = [];
    for (const f of found) {
      const est = O.between(plus(f.date, -12), plus(f.date, 12)).filter((o) => o.key === f.key)
        .sort((a, b) => Math.abs(diff(a.date, f.date)) - Math.abs(diff(b.date, f.date)))[0];
      if (!est) continue;
      const cur = fixes[est.id];
      if (cur && !cur.auto) continue;                                   // set by hand: leave it
      let end = est.end ? plus(f.date, diff(est.date, est.end)) : null;
      if (f.key === 'ramadan') { const eid = found.find((x) => x.key === 'eidfitr' && diff(f.date, x.date) > 25 && diff(f.date, x.date) < 32); if (eid) end = plus(eid.date, -1); }
      const was = cur ? { date: cur.date, end: cur.end } : { date: est.date, end: est.end };
      if (was.date === f.date && (was.end || null) === (end || null)) {
        if (!cur) { fixes[est.id] = { date: f.date, end, auto: true, at }; changed.push({ id: est.id, name: est.name, date: f.date, was: est.date, same: true }); }
        continue;
      }
      fixes[est.id] = { date: f.date, end, auto: true, at };
      changed.push({ id: est.id, name: est.name, date: f.date, was: was.date });
    }
    if (changed.length) {
      const { rev, results } = store.apply([{ kind: 'meta', id: 'main', data: { ...meta, occDates: fixes } }], 'holidays');
      onChange(rev, results, changed.filter((c) => !c.same));
    }
    const names = { ramadan: 'Ramadan', eidfitr: 'Eid al-Fitr', arafat: 'Arafat Day', eidadha: 'Eid al-Adha', hijri: 'Islamic New Year', mawlid: 'Prophet’s Birthday' };
    const s = { at, ok: true, error: null, found: found.length, foundList: found.map((f) => ({ name: names[f.key], date: f.date })).sort((a, b) => a.date.localeCompare(b.date)), events: events.length,
      tentativeList: tentative.map((f) => ({ name: names[f.key], date: f.date })).sort((a, b) => a.date.localeCompare(b.date)).slice(0, 6), lastChange: changed.filter((c) => !c.same).length ? at : status().lastChange || null, changed: changed.filter((c) => !c.same).length ? changed.filter((c) => !c.same) : status().changed || [] };
    saveStatus(s);
    return s;
  }

  let timer = null, first = null;
  return {
    check,
    status,
    start() { if (timer) return; first = setTimeout(() => check().catch(() => {}), 60_000); timer = setInterval(() => check().catch(() => {}), 12 * 3600_000); if (first.unref) first.unref(); if (timer.unref) timer.unref(); },
    stop() { clearTimeout(first); clearInterval(timer); timer = null; },
  };
}
