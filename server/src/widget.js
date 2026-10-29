// Widgets (iPhone home and lock screen, Mac desktop): one small summary per person, for the categories they may see.
//   production — their own open tasks: due today, overdue, waiting for CD review, the next few, this week Mon–Fri
//   social     — content plans for the month being planned (next month from the 15th), their states, posts today
//   finance    — jobs by Finance status, money out this month, subscriptions billed in the next 7 days
// Who: Production people, freelancers, Account Managers and Admins get "production"; Social people, Account
// Managers, the CD and Admins get "social"; anyone with Finance access gets "finance". Office Admins and Finance-only
// people have no tasks. The widget picks the person's own category; Admins choose in Edit Widget.
// Read only. The widget asks with the app's own Cloudflare sign-in, so nothing here is open without signing in.
import { dubaiNow } from './digest.js';

const DAY = 86400000;
const toT = (s) => Date.parse(s + 'T00:00:00Z');
const plus = (s, n) => new Date(toT(s) + n * DAY).toISOString().slice(0, 10);
const FIN = ['To be invoiced', 'LPO Pending', 'Quote to be sent', 'Invoiced', 'Retainer'];
const FIN_C = { 'Quote to be sent': '#9aa4b2', 'LPO Pending': '#f9be33', Invoiced: '#3ddc97', Retainer: '#a875ff', 'To be invoiced': '#ff8a4c' };
const daysIn = (m) => { const [y, mo] = m.split('-').map(Number); return new Date(Date.UTC(y, mo, 0)).getUTCDate(); };
const addMonths = (m, n) => { const [y, mo] = m.split('-').map(Number); const d = new Date(Date.UTC(y, mo - 1 + n, 1)); return d.toISOString().slice(0, 7); };
const pad2 = (n) => String(n).padStart(2, '0');
const prioRank = (p) => { if (p === 'urgent' || p === 'high') return 0; const n = Number(p); return Number.isInteger(n) && n >= 1 && n <= 10 ? n : 99; };

export function createWidget({ store, access, occRemind = null, now = () => Date.now() }) {
  const meta = () => store.get('meta', 'main') || {};
  const cdId = () => meta().cdUserId || null;
  const isMgr = (u) => u.role === 'social' && (meta().socialMgrIds || []).includes(u.id);
  const finLevel = (u) => (u.role === 'finance_admin' ? 'admin' : u.role === 'finance_viewer' ? 'viewer' : u.fin === 'admin' || u.fin === 'viewer' ? u.fin : null);
  const finOnly = (u) => u.role === 'finance_admin' || u.role === 'finance_viewer';
  const office = (u) => u.role === 'office_admin' && u.admin !== true;
  const adm = (u) => access.isAdm(u);

  function categories(u) {
    const out = [];
    if (!finOnly(u) && !office(u) && (['production', 'freelancer', 'am'].includes(u.role) || adm(u))) out.push('production');
    if (!finOnly(u) && !office(u) && (u.role === 'social' || u.role === 'am' || adm(u) || u.id === cdId())) out.push('social');
    if (finLevel(u)) out.push('finance');
    return out;
  }
  // the person's own one (first on the list), e.g. a Social person with Finance access gets Social
  const mainOf = (u, cats) => (u.role === 'social' && cats.includes('social') ? 'social' : finOnly(u) ? 'finance' : cats[0] || null);

  const projects = () => { const m = new Map(); store.list('projects').forEach((p) => m.set(p.id, p)); return m; };
  const short = (s, n = 60) => { s = String(s || '').replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1) + '…' : s; };

  function production(u, day) {
    const P = projects();
    const off = (id) => { const p = P.get(id); return !p || p.inactive; };
    const all = store.list('tasks').filter((t) => !t.parentId && !t.deleted && !off(t.projectId) && (t.assignees || []).includes(u.id));
    const isDone = (t) => !!t.done || !!(t.partsDone || {})[u.id];
    const mine = all.filter((t) => !isDone(t));
    const waiting = mine.filter((t) => {
      if (!t.needsCD) return false;
      const list = (t.reviews || []).filter((r) => r.by === u.id && (r.epoch || 0) === (t.reviewEpoch || 0) && r.state !== 'withdrawn');
      const last = list[list.length - 1];
      return !!last && last.state === 'pending';
    }).length;
    const sorted = mine.filter((t) => t.due).sort((a, b) => a.due.localeCompare(b.due) || prioRank((a.prio || {})[u.id]) - prioRank((b.prio || {})[u.id]));
    // this week, Monday to Friday (Dubai): due that day, and how many of those are finished
    const wd = new Date(toT(day)).getUTCDay();
    const mon = plus(day, wd === 0 ? -6 : 1 - wd);
    const week = [0, 1, 2, 3, 4].map((i) => { const d = plus(mon, i); const l = all.filter((t) => t.due === d); return { day: d, due: l.length, done: l.filter(isDone).length }; });
    return {
      dueToday: mine.filter((t) => t.due === day).length,
      doneToday: all.filter((t) => t.due === day && isDone(t)).length,
      overdue: mine.filter((t) => t.due && t.due < day).length,
      waitingCD: waiting,
      open: mine.length,
      next: sorted.slice(0, 5).map((t) => { const p = P.get(t.projectId) || {}; return { id: t.id, title: short(t.title || 'Untitled task'), client: p.name || '', color: p.color || '#7c6cff', due: t.due }; }),
      week,
    };
  }

  function social(u, day) {
    const P = projects();
    const mgr = isMgr(u) || adm(u) || u.id === cdId() || u.role === 'am';
    const mine = (p) => !!p && !p.inactive && (mgr || (p.socials || []).includes(u.id));
    const month = Number(day.slice(8, 10)) >= 15 ? addMonths(day.slice(0, 7), 1) : day.slice(0, 7);
    const plans = store.list('plans').filter((pl) => mine(P.get(pl.projectId)));
    const ofMonth = plans.filter((pl) => pl.month === month);
    const clients = [...P.values()].filter((p) => mine(p));
    const count = (s) => ofMonth.filter((pl) => (pl.status || 'draft') === s).length;
    const today = [];
    plans.forEach((pl) => (pl.posts || []).forEach((x) => { if (x.day === day) { const p = P.get(pl.projectId) || {}; today.push({ planId: pl.id, title: short(x.title || 'Untitled post', 40), client: p.name || '', color: p.color || '#7c6cff', channels: (x.channels || []).slice(0, 3), format: x.format || '' }); } }));
    const changes = ofMonth.filter((pl) => pl.status === 'changes').map((pl) => ({ planId: pl.id, client: (P.get(pl.projectId) || {}).name || '', note: short(((pl.log || []).filter((l) => l.act === 'changes').pop() || {}).note || '', 60), by: (() => { const l = (pl.log || []).filter((x) => x.act === 'changes').pop(); const w = l && store.get('users', String(l.by)); return w ? String(w.name || '').split(/\s+/)[0] : ''; })() }));
    let next = null;
    try { next = occRemind && occRemind.nextOccasion ? occRemind.nextOccasion(day) : null; } catch { next = null; }
    return {
      month, clients: clients.length,
      approved: count('approved'), review: count('review'), changes: count('changes'), draft: count('draft'),
      missing: Math.max(0, clients.length - ofMonth.length),
      today: today.slice(0, 6), todayCount: today.length, todayClients: new Set(today.map((x) => x.client)).size,
      sentBack: changes.slice(0, 3),
      nextOccasion: next,
    };
  }

  function finance(u, day) {
    const P = projects();
    const ts = store.list('tasks').filter((t) => !t.parentId && !t.deleted && !(P.get(t.projectId) || {}).inactive);
    const by = FIN.map((s) => ({ status: s, color: FIN_C[s], count: ts.filter((t) => t.finance === s).length }));
    const recs = (type) => store.list('finance').filter((x) => x.type === type && !x.deleted);
    const m = day.slice(0, 7);
    let spent = 0;
    recs('reimb').concat(recs('expense')).forEach((r) => { if (String(r.date || '').slice(0, 7) === m) spent += Number(r.amount) || 0; });
    const subs = [];
    recs('sub').forEach((s) => {
      const start = s.startMonth || String(s.createdAt || '').slice(0, 7) || m;
      const ended = s.endedAt ? new Date(s.endedAt).toISOString().slice(0, 10) : null;
      const billed = `${m}-${pad2(Math.min(Number(s.day) || 1, daysIn(m)))}`;
      if (start <= m && billed <= day && (!ended || billed <= ended)) spent += Number(s.amount) || 0;
      // billed in the next 7 days (this month or next)
      for (const mm of [m, addMonths(m, 1)]) {
        const d = `${mm}-${pad2(Math.min(Number(s.day) || 1, daysIn(mm)))}`;
        if (d >= day && d <= plus(day, 7) && start <= mm && (!ended || d <= ended)) subs.push({ name: short(s.name, 30), date: d, amount: Number(s.amount) || 0 });
      }
    });
    subs.sort((a, b) => a.date.localeCompare(b.date));
    return { month: m, statuses: by, spent: Math.round(spent * 100) / 100, subsSoon: subs.slice(0, 4), subsSoonCount: subs.length };
  }

  return {
    categories,
    summary(u) {
      const t = dubaiNow(now());
      const cats = categories(u);
      const out = { ok: true, at: new Date(now()).toISOString(), day: t.day, name: String(u.name || '').trim().split(/\s+/)[0] || '', categories: cats, main: mainOf(u, cats) };
      if (cats.includes('production')) out.production = production(u, t.day);
      if (cats.includes('social')) out.social = social(u, t.day);
      if (cats.includes('finance')) out.finance = finance(u, t.day);
      return out;
    },
  };
}
