// Occasion reminders: 45, 30, 14 and 7 days before every occasion, at 10:30 (Dubai), Social, Account Managers
// and Admins are reminded to plan posts ("Ramadan in 45 days · 2 of 5 clients have posts planned").
// A reminder is skipped when every client already has a post linked to the occasion. A reminder that would land
// on a Saturday or Sunday goes out on the Friday before. Phones get a notification; an app that's open (or opened
// later that day) shows it once.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { dubaiNow } from './digest.js';

export const STEPS = [45, 30, 14, 7];
const START = 10 * 60 + 30;
const DAY = 86400000;
const toT = (s) => Date.parse(s + 'T00:00:00Z');
const plus = (s, n) => new Date(toT(s) + n * DAY).toISOString().slice(0, 10);
const weekday = (s) => new Date(toT(s)).getUTCDay();
const fmt = (s) => new Date(s + 'T00:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' });

// the day a reminder goes out: N days before, moved back to Friday if that's a weekend
export function sendDay(date, n) {
  let d = plus(date, -n);
  const w = weekday(d);
  if (w === 6) d = plus(d, -1); else if (w === 0) d = plus(d, -2);
  return d;
}
// Account Managers and Admins create the posts; Social can't create tasks but set the Occasion on the ones they have
const tail = (u, isAdm) => (u.role === 'am' || isAdm(u) ? ' Plan posts in the Content calendar.' : ' Set the Occasion on your post tasks so they count as planned.');
export const remindRole = (u, isAdm) => !!u && u.active !== false && (u.role === 'social' || u.role === 'am' || isAdm(u));

export function createOccasionReminders({ store, webDir, webPush, isAdm, now = () => Date.now(), log = console }) {
  function occasions(meta) {
    const src = fs.readFileSync(path.join(webDir, 'calendar.js'), 'utf8').split('const Cal =')[0];
    return vm.runInNewContext(`${src}; Occasions`, { db: { meta }, Intl, Date, Math, Number, String, Object, Array, JSON, parseInt });
  }
  // the reminders due on a day: [{ id, name, date, days, planned, total, title, body }]
  function dueOn(day) {
    const meta = store.get('meta', 'main') || {};
    const O = occasions(meta);
    const projects = store.list('projects').filter((p) => !p.archived && !p.deleted);
    const tasks = store.list('tasks').filter((t) => !t.deleted && !t.parentId && t.occasion);
    const out = [];
    for (const o of O.between(plus(day, 1), plus(day, 50))) {
      if (o.date <= day) continue;
      const n = STEPS.find((k) => sendDay(o.date, k) === day);
      if (!n) continue;
      const planned = new Set(tasks.filter((t) => t.occasion === o.id && projects.some((p) => p.id === t.projectId)).map((t) => t.projectId)).size;
      if (projects.length && planned >= projects.length) continue;      // every client has posts planned
      const days = Math.round((toT(o.date) - toT(day)) / DAY);
      out.push({
        id: o.id, name: o.name, date: o.date, days, step: n, planned, total: projects.length,
        title: `${o.name} in ${days} days`,
        body: `${o.est ? 'Expected ' : ''}${fmt(o.date)} · ${planned ? `${planned} of ${projects.length} clients have posts planned` : 'Nothing planned yet'}.`,
      });
    }
    return out;
  }
  const load = () => { try { return JSON.parse(store.kv.get('occ-remind-sent') || '{}'); } catch { return {}; } };
  async function tick() {
    const t = dubaiNow(now());
    if (t.minutes < START) return 0;
    let list;
    try { list = dueOn(t.day); } catch (e) { log.error('Occasion reminders failed', e.message); return 0; }
    if (!list.length) return 0;
    const sent = load();
    // forget old entries (kept 60 days)
    for (const k of Object.keys(sent)) if (sent[k] < plus(t.day, -60)) delete sent[k];
    const people = store.list('users').filter((u) => remindRole(u, isAdm));
    let n = 0;
    for (const r of list) {
      const key = `${r.id}:${r.step}`;
      if (sent[key]) continue;
      sent[key] = t.day;
      store.kv.set('occ-remind-sent', JSON.stringify(sent));          // marked first: a crash never sends twice
      for (const u of people) {
        try { const res = await webPush.sendTo(u.id, { title: r.title, body: r.body + tail(u, isAdm), tag: 'occ-' + key, view: 'calendar' }, { ttl: Math.max(60, Math.floor((t.endOfDay - now()) / 1000)) }); n += res.sent || 0; }
        catch (e) { log.error('Occasion reminder failed', e.message); }
      }
    }
    return n;
  }
  let timer = null;
  return {
    tick, dueOn,
    start() { if (!timer) { timer = setInterval(() => { tick().catch(() => {}); }, 60_000); if (timer.unref) timer.unref(); tick().catch(() => {}); } },
    stop() { clearInterval(timer); timer = null; },
    // for the person's own open app: today's reminders, from 10:30 until midnight
    forUser(user) {
      const t = dubaiNow(now());
      if (t.minutes < START || !remindRole(user, isAdm)) return { day: t.day, list: [] };
      try { return { day: t.day, list: dueOn(t.day).map((r) => ({ ...r, body: r.body + tail(user, isAdm) })) }; } catch { return { day: t.day, list: [] }; }
    },
  };
}
