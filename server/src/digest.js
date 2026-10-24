// Morning summary for Production and Social: at 10:30 (Dubai), Monday to Friday, each person gets a short
// "how your day looks" notification. Phones with notifications on get it as a push straight away; an app that's
// open (Mac, browser) shows it as a banner, and an app opened later that day shows it once — never after midnight.
// Nothing goes in the Inbox. Anyone can switch it off (holidays) with prefs.digestOff.

const DUBAI_OFFSET = 4 * 3600_000; // Dubai has no daylight saving
const START = 10 * 60 + 30;          // 10:30

const ymd = (d) => d.toISOString().slice(0, 10);
// Dubai's date, weekday (0 = Sunday) and minutes past midnight
export function dubaiNow(now = Date.now()) {
  const d = new Date(now + DUBAI_OFFSET);
  return { day: ymd(d), weekday: d.getUTCDay(), minutes: d.getUTCHours() * 60 + d.getUTCMinutes(), endOfDay: Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1) - DUBAI_OFFSET };
}
// Monday to Friday, from 10:30 until midnight
export const digestTime = (t) => t.weekday >= 1 && t.weekday <= 5 && t.minutes >= START;

export const digestRole = (u) => !!u && u.active !== false && (u.role === 'production' || u.role === 'social');
export const digestWanted = (u) => digestRole(u) && !((u.prefs || {}).digestOff);

// Same order as the Home page: by due date (none last), then the person's own priority
const prioRank = (p) => { if (p === 'urgent' || p === 'high') return 0; const n = Number(p); return Number.isInteger(n) && n >= 1 && n <= 10 ? n : 99; };

export function digestFor(store, user, day) {
  const first = String(user.name || user.email || '').trim().split(/\s+/)[0] || '';
  const mine = store.list('tasks').filter((t) => !t.parentId && !t.done && (t.assignees || []).includes(user.id) && !(t.partsDone || {})[user.id]);
  const dueToday = mine.filter((t) => t.due === day).length;
  const overdue = mine.filter((t) => t.due && t.due < day).length;
  // their own files waiting with the CD (latest submission this round, not withdrawn)
  const waiting = mine.filter((t) => {
    if (!t.needsCD) return false;
    const list = (t.reviews || []).filter((r) => r.by === user.id && (r.epoch || 0) === (t.reviewEpoch || 0) && r.state !== 'withdrawn');
    const last = list[list.length - 1];
    return !!last && last.state === 'pending';
  }).length;
  const next = mine.slice().sort((a, b) => (a.due || '9999').localeCompare(b.due || '9999') || prioRank((a.prio || {})[user.id]) - prioRank((b.prio || {})[user.id]))[0];
  const parts = [dueToday ? `${dueToday} due today` : 'Nothing due today'];
  if (overdue) parts.push(`${overdue} overdue`);
  if (waiting) parts.push(`${waiting} waiting for CD review`);
  let body = parts.join(' · ') + '.';
  if (next) body += ` First up: ${next.title || 'Untitled task'}`;
  else if (!mine.length) body = 'Nothing due today and nothing open on your list — a clear day.';
  return { title: first ? `Good morning, ${first}` : 'Good morning', body, tag: 'digest-' + day };
}

export function createDigest({ store, webPush, now = () => Date.now(), log = console }) {
  const load = () => { try { return JSON.parse(store.kv.get('digest-sent') || '{}'); } catch { return {}; } };
  // Phones: one push per person per day, from 10:30 (or as soon as the server is up after that)
  async function tick() {
    const t = dubaiNow(now());
    if (!digestTime(t)) return 0;
    let sent = load();
    if (sent.day !== t.day) sent = { day: t.day, ids: [] };
    const todo = store.list('users').filter((u) => digestWanted(u) && !sent.ids.includes(u.id));
    let n = 0;
    for (const u of todo) {
      sent.ids.push(u.id);
      store.kv.set('digest-sent', JSON.stringify(sent));          // marked first: a crash never sends twice
      try { const r = await webPush.sendTo(u.id, digestFor(store, u, t.day), { ttl: Math.max(60, Math.floor((t.endOfDay - now()) / 1000)) }); n += r.sent || 0; }
      catch (e) { log.error('Morning summary failed', e.message); }
    }
    return n;
  }
  let timer = null;
  return {
    tick,
    start() { if (!timer) { timer = setInterval(() => { tick().catch(() => {}); }, 30_000); if (timer.unref) timer.unref(); tick().catch(() => {}); } },
    stop() { clearInterval(timer); timer = null; },
    // For the person's own open app: today's summary, if it's time and they want it
    forUser(user) {
      const t = dubaiNow(now());
      if (!digestTime(t) || !digestWanted(user)) return { due: false, day: t.day };
      return { due: true, day: t.day, ...digestFor(store, user, t.day) };
    },
    preview(user) { const t = dubaiNow(now()); return digestFor(store, user, t.day); },
  };
}
