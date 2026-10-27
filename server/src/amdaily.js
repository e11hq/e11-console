// Morning round-up for Account Managers and Super Admins: at 9:00 Dubai, Monday to Friday (not on UAE public
// holidays), each gets one Inbox update and a phone notification, e.g. "3 overdue · 5 due today · 2 waiting for CD".
// An Account Manager's numbers cover their own work (every task in the clients they look after, plus their own tasks
// without a client — the same tasks as their Home page, web/app.js Work.leadSet); a Super Admin's cover the whole
// team (every AM's and Admin's). Opening it shows the summary card with the lists (web/daily.js), worked out again
// with the latest data. Anyone can switch it off on My profile (prefs.notifOff.daily).
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { dubaiNow } from './digest.js';

const START = 9 * 60;
const plusDay = (s, n) => new Date(Date.parse(s + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10);

// UAE public holidays (private sector): what the holiday calendar marks as a public holiday (holidays.js keeps them),
// and the app's own occasion dates for the ones it knows (confirmed moon dates included), in case the calendar
// can't be read
const PUBLIC_KEYS = new Set(['newyear', 'eidfitr', 'arafat', 'eidadha', 'hijri', 'mawlid', 'nationalday']);
export function publicHolidayFinder({ store, webDir }) {
  let src = null;
  const occ = (meta) => {
    if (!webDir) return null;
    try {
      src = src || fs.readFileSync(path.join(webDir, 'calendar.js'), 'utf8').split('const Cal =')[0];
      return vm.runInNewContext(`${src}; Occasions`, { db: { meta }, Intl, Date, Math, Number, String, Object, Array, JSON, parseInt });
    } catch { return null; }
  };
  return function holidayOn(day) {
    let fromCal = [];
    try { fromCal = JSON.parse(store.kv.get('holiday-sync') || '{}').publicDays || []; } catch { /* none yet */ }
    if (fromCal.some((h) => h.date === day)) return fromCal.find((h) => h.date === day).name || 'Public holiday';
    const O = occ(store.get('meta', 'main') || {});
    const hit = O && O.between(day, day).find((o) => PUBLIC_KEYS.has(o.key) && !o.custom);
    return hit ? hit.name : null;
  };
}

export const dailyRole = (u, isSuper) => !!u && u.active !== false && (u.role === 'am' || isSuper(u));

// The numbers for one person (the same rules as the summary card in web/daily.js)
export function dailyFor(store, access, user, day) {
  const team = access.isSuper(user);
  const projects = store.list('projects');
  const off = new Set(projects.filter((p) => p.inactive).map((p) => p.id));
  const top = store.list('tasks').filter((t) => !t.parentId && !off.has(t.projectId));
  const users = store.list('users');
  const isAmOnly = (u) => !!u && u.role === 'am' && !access.isAdm(u);
  const hasClients = (id) => projects.some((p) => (p.ams || []).some((a) => a.id === id));
  const amClients = (id) => new Set(projects.filter((p) => (p.ams || []).some((a) => a.id === id && !a.onLeave)).map((p) => p.id));
  function ofAm(id) {
    const pids = amClients(id), own = !hasClients(id);
    return top.filter((t) => (t.projectId ? pids.has(t.projectId) || (own && t.createdBy === id) : t.createdBy === id));
  }
  const ids = team ? users.filter((u) => u.active !== false && (u.role === 'am' || access.isAdm(u))).map((u) => u.id) : [user.id];
  const set = new Map();
  for (const id of ids) {
    const u = users.find((x) => x.id === id);
    (isAmOnly(u) ? ofAm(id) : top.filter((t) => t.createdBy === id)).forEach((t) => set.set(t.id, t));
  }
  const open = [...set.values()].filter((t) => !t.done);
  const cd = (store.get('meta', 'main') || {}).cdUserId || null;
  const epoch = (t) => t.reviewEpoch || 0;
  const state = (t, u) => { const l = (t.reviews || []).filter((r) => r.by === u && (r.epoch || 0) === epoch(t) && r.state !== 'withdrawn'); return l.length ? l[l.length - 1].state : 'none'; };
  const reviewers = (t) => (t.assignees || []).filter((u) => u !== cd);
  const anyState = (t, s) => !!t.needsCD && reviewers(t).some((u) => state(t, u) === s);
  const lastOk = (t) => (t.reviews || []).filter((r) => r.state === 'approved').map((r) => r.decidedAt || r.at || '').sort().pop() || '';
  const clientMissing = (t) => (t.reviews || []).some((r) => r.state === 'approved') && !(t.clientApproval && String(t.clientApproval.at || '') >= lastOk(t));
  const sched = store.list('scheduled').filter((s) => s.authorId === user.id && s.state === 'waiting' && new Date(Date.parse(s.sendAt) + 4 * 3600000).toISOString().slice(0, 10) === day);
  return {
    team,
    overdue: open.filter((t) => t.due && t.due < day).length,
    today: open.filter((t) => t.due === day).length,
    cd: open.filter((t) => anyState(t, 'pending')).length,
    amend: open.filter((t) => anyState(t, 'amend')).length,
    client: open.filter(clientMissing).length,
    sched: sched.length,
  };
}

const first = (u) => String(u.name || String(u.email || '').split('@')[0]).trim().split(/\s+/)[0];
export function dailyText(n) {
  const parts = [];
  if (n.overdue) parts.push(`${n.overdue} overdue`);
  parts.push(n.today ? `${n.today} due today` : 'nothing due today');
  if (n.cd) parts.push(`${n.cd} waiting for CD`);
  if (n.amend) parts.push(`${n.amend} with amendments`);
  if (n.client) parts.push(`${n.client} need client approval`);
  if (n.sched) parts.push(`${n.sched} scheduled comment${n.sched === 1 ? '' : 's'} today`);
  const s = parts.join(' · ');
  if (!n.overdue && !n.today && !n.cd && !n.amend && !n.client && !n.sched) return 'All clear today — nothing overdue or due today.';
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function createDaily({ store, access, webDir, webPush, notifMessage, deliver, now = () => Date.now(), log = console }) {
  const holidayOn = publicHolidayFinder({ store, webDir });
  const load = () => { try { return JSON.parse(store.kv.get('daily-sent') || '{}'); } catch { return {}; } };
  let timer = null;
  async function tick() {
    const t = dubaiNow(now());
    if (t.weekday < 1 || t.weekday > 5 || t.minutes < START) return 0;
    if (holidayOn(t.day)) return 0;
    let sent = load();
    if (sent.day !== t.day) sent = { day: t.day, ids: [] };
    const todo = store.list('users').filter((u) => dailyRole(u, access.isSuper) && !((u.prefs || {}).notifOff || {}).daily && !sent.ids.includes(u.id));
    let made = 0;
    for (const u of todo) {
      sent.ids.push(u.id);
      store.kv.set('daily-sent', JSON.stringify(sent));   // marked first: a crash never sends twice
      try { if (await send(u, t)) made++; } catch (e) { log.error('Daily summary failed', e.message); }
    }
    return made;
  }
  function make(u, t) {
    const n = dailyFor(store, access, u, t.day);
    const at = new Date(now()).toISOString(), id = 'n-dy' + crypto.randomBytes(6).toString('hex');
    const out = store.apply([{ kind: 'notifications', id, data: { id, to: u.id, from: u.id, kind: 'daily', day: t.day, team: n.team, counts: n, title: `Good morning, ${first(u)}`,
      text: `<b>${n.team ? 'Your team’s day' : 'Your day'}</b>: ${dailyText(n)}`, snippet: '', at, read: false } }], 'daily');
    if (deliver) deliver(out);
    return out;
  }
  async function send(u, t) {
    const out = make(u, t);
    const r = out.results.find((x) => !x.refused && x.data);
    if (!r) return false;
    try { await webPush.sendTo(u.id, notifMessage(store, r.data), { ttl: Math.max(60, Math.floor((t.endOfDay - now()) / 1000)) }); } catch { /* phone offline */ }
    return true;
  }
  return {
    tick,
    holidayOn,
    // one now, for yourself (a try-out from My profile): Inbox and phone, any day and time
    sendNow(u) { const t = dubaiNow(now()); send(u, t).catch(() => {}); return true; },
    start() { if (!timer) { timer = setInterval(() => { tick().catch((e) => log.error('daily summary:', e.message)); }, 30_000); if (timer.unref) timer.unref(); tick().catch(() => {}); } },
    stop() { if (timer) { clearInterval(timer); timer = null; } },
  };
}
