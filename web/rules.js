/* E11 Console — shared rules (the website and the server run this same file)
   The iPhone app's Home comes straight from the server (/api/home, iPhone app 25+); the website's own NativeHome uses
   the same code, so both always show the same thing. Moved here from app.js / phone.js (Work.day, myDayData, cardOf…)
   — one copy. Pure: it reads a copy of the data it's given and changes nothing.

   E11Rules.home(db, meId, today) → the Home model the app draws (title, date, boxes, groups, cards — each with what this
   person may do on it). db: { users, projects, tasks, statuses, plans, meta }; today: 'YYYY-MM-DD' (Dubai). */
var E11Rules = (() => {
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const MON3 = MONTHS.map((m) => m.slice(0, 3));
  const WDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const AV_COLORS = ['#7b68ee', '#4c9aff', '#3ddc97', '#f9be33', '#ff8a4c', '#e5484d', '#ff8fc7', '#4fd1c5', '#a875ff'];
  const CD = { review: { label: 'Internal Review', color: '#f9be33' }, approved: { label: 'Approved', color: '#3ddc97' } };
  const LIMITED = new Set(['editProject', 'editPriority', 'assign', 'removeTag', 'editDesc', 'deleteTask', 'deleteChecklist', 'editTitle', 'createTask', 'deleteProject']);
  const NO_DATES_CHECKLIST = ['editDates', 'addChecklist', 'editChecklist', 'deleteChecklist'];
  const ROLE_DENY = { production: NO_DATES_CHECKLIST, social: ['editDates', 'editChecklist', 'deleteChecklist'], freelancer: NO_DATES_CHECKLIST };
  const ROLE_ALLOW = { social: ['editDesc'] };
  const DEFAULT_STATUSES = [
    { id: 'st-todo', name: 'To do', color: '#87909e' }, { id: 'st-progress', name: 'In progress', color: '#a875ff' },
    { id: 'st-review', name: 'Review', color: '#f9be33' }, { id: 'st-ctr', name: 'CTR', color: '#ff8a4c' }, { id: 'st-done', name: 'Done', color: '#3ddc97' },
  ];

  // ---------- dates (days only, no time zone: 'YYYY-MM-DD') ----------
  const dayNum = (s) => { const [y, m, d] = String(s).split('-').map(Number); return Date.UTC(y, m - 1, d) / 86400000; };
  const ofNum = (n) => new Date(n * 86400000).toISOString().slice(0, 10);
  const wdayOf = (s) => new Date(dayNum(s) * 86400000).getUTCDay();
  // Dubai's day (UTC+4, no summer time) for a moment
  const dubaiDay = (ms) => new Date(ms + 4 * 3600000).toISOString().slice(0, 10);
  const longDate = (s) => { const [, m, d] = s.split('-').map(Number); return `${WDAYS[wdayOf(s)]}, ${MONTHS[m - 1]} ${d}`; };

  // ---------- small helpers ----------
  const normPrio = (p) => { if (p === 'urgent' || p === 'high') return 'urgent'; const n = Number(p); return Number.isInteger(n) && n >= 1 && n <= 10 ? n : 'none'; };
  const prioRank = (p) => { p = normPrio(p); return p === 'urgent' ? 0 : p === 'none' ? 99 : p; };
  const isDoneName = (n) => /^(done|complete|completed)$/i.test(String(n).trim());
  const isToDoName = (n) => /^to ?-?do$/i.test(String(n).trim());
  const mentionsIn = (html) => { const out = new Set(); String(html || '').replace(/data-user="([^"]+)"/g, (_, id) => { out.add(id); return ''; }); return out; };
  const initials = (name) => String(name || '').trim().split(/\s+/).slice(0, 2).map((w) => w[0] || '').join('').toUpperCase() || '?';
  const avColor = (id) => { let h = 0; for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) >>> 0; return AV_COLORS[h % AV_COLORS.length]; };
  // '#rrggbb' / '#rgb' / 'rgb(…)' → [r, g, b] (what the app takes); anything else → null
  function rgbOf(css) {
    const s = String(css || '').trim();
    let m = /^#([0-9a-f]{6})$/i.exec(s);
    if (m) { const v = parseInt(m[1], 16); return [(v >> 16) & 255, (v >> 8) & 255, v & 255]; }
    m = /^#([0-9a-f]{3})$/i.exec(s);
    if (m) return m[1].split('').map((c) => parseInt(c + c, 16));
    m = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)/i.exec(s);
    return m ? [+m[1], +m[2], +m[3]] : null;
  }

  function make(db, meId, today) {
    const users = db.users || [], projects = db.projects || [], tasks = db.tasks || [], meta = db.meta || {};
    const uMap = new Map(users.map((u) => [u.id, u])), pMap = new Map(projects.map((p) => [p.id, p])), tMap = new Map(tasks.map((t) => [t.id, t]));
    const userById = (id) => uMap.get(id) || null;
    const proj = (id) => pMap.get(id);
    const task = (id) => tMap.get(id);
    const me = () => userById(meId);
    const fullName = (u) => (u ? (u.name || String(u.email || '').split('@')[0]) : 'Former member');
    const topTasks = () => tasks.filter((t) => !t.parentId);
    const statuses = () => (Array.isArray(db.statuses) && db.statuses.length ? db.statuses : DEFAULT_STATUSES);
    const dayDiff = (s) => dayNum(s) - dayNum(today);

    // ---------- who ----------
    const isAdm = (u) => !!u && (u.role === 'admin' || u.role === 'office_admin' || u.admin === true);
    const isOffice = (u) => !!u && u.role === 'office_admin' && u.admin !== true;
    const isFinUser = (u) => !!u && (u.role === 'finance_admin' || u.role === 'finance_viewer');
    const cdUserId = () => { const id = meta.cdUserId; const u = id && userById(id); return u && u.active !== false ? id : null; };
    const isCD = (id) => !!id && id === cdUserId();
    const isManager = (u) => !!u && (isAdm(u) || u.role === 'am');
    const seesAll = () => isAdm(me()) || isCD(meId);
    const lead = () => isManager(me()) || seesAll();
    const socialMgrIds = () => (meta.socialMgrIds || []).filter((id) => { const u = userById(id); return u && u.active !== false && u.role === 'social'; });
    const planById = (id) => (db.plans || []).find((p) => p.id === id) || null;
    const socialsOf = (p) => ((p && p.socials) || []).filter((id) => { const u = userById(id); return u && u.active !== false; });
    const canEditClient = (pid, u) => !!u && u.role === 'social' && u.active !== false && (socialMgrIds().includes(u.id) || socialsOf(proj(pid)).includes(u.id));
    const socialManages = (t) => { const pl = t && t.planId && planById(t.planId); return !!pl && canEditClient(pl.projectId, me()); };

    function amScope(t, u = me()) {
      if (!u || isAdm(u) || u.role !== 'am' || isCD(u.id)) return true;
      if (!t) return true;
      if (!projects.some((p) => (p.ams || []).some((a) => a.id === u.id))) return true;
      const root = t.parentId ? task(t.parentId) || t : t;
      if (root.createdBy === u.id || t.createdBy === u.id) return true;
      const p = root.projectId ? proj(root.projectId) : null;
      return !!p && (p.ams || []).some((a) => a.id === u.id && !a.onLeave);
    }
    // can(perm, t): as app.js's can() (t given — the app's Home always asks about a task, or about none)
    function can(perm, t) {
      const u = me();
      if (!u) return false;
      if (isFinUser(u)) return false;
      if (perm === 'manageUsers') return isAdm(u);
      if (isOffice(u)) return false;
      if (isAdm(u) || isCD(u.id)) return true;
      if (u.role === 'am') return amScope(t || null) || !LIMITED.has(perm);
      if (u.role === 'social' && t && t.planId && socialManages(t)) return true;
      if ((ROLE_DENY[u.role] || []).includes(perm)) return false;
      if ((ROLE_ALLOW[u.role] || []).includes(perm)) return true;
      return !LIMITED.has(perm);
    }
    const subtasksOf = (id) => tasks.filter((t) => t.parentId === id);
    function partOfTask(t, id, deep = true) {
      if (!t) return false;
      if ((t.assignees || []).includes(id) || t.createdBy === id || t.guardian === id) return true;
      if ((t.comments || []).some((c) => mentionsIn(c.html).has(id)) || mentionsIn(t.notesHtml).has(id)) return true;
      if (!deep) return false;
      return (t.parentId && partOfTask(task(t.parentId), id, false)) || subtasksOf(t.id).some((x) => partOfTask(x, id, false));
    }
    const ownSearchOnly = (u) => !!u && ['production', 'freelancer'].includes(u.role) && !isAdm(u) && !isCD(u.id);
    const peekOnly = (t, u = me()) => !!t && ownSearchOnly(u) && !partOfTask(t, u.id);
    const amReadOnly = (t, u = me()) => !!t && !!u && ((u.role === 'am' && !isAdm(u) && !isCD(u.id) && !amScope(t, u)) || peekOnly(t, u));

    // ---------- statuses, CD review, priority ----------
    const statusList = (t) => { const p = proj(t.projectId); return p ? p.sections : statuses(); };
    const sectionOf = (t) => {
      const p = proj(t.projectId);
      if (p) return (p.sections || []).find((s) => s.id === t.sectionId) || null;
      const list = statuses();
      return list.find((s) => s.id === t.sectionId) || list[0] || null;
    };
    const statusInfo = (t) => { if (t.done) return { name: 'Complete', color: '#3ddc97' }; const s = sectionOf(t); return s ? { name: s.name, color: s.color } : { name: 'Open', color: '#87909e' }; };
    const needsCD = (t) => !!t && !t.parentId && !!t.needsCD;
    const reviewersOf = (t) => (t.assignees || []).filter((u) => u !== cdUserId());
    const epochOf = (t) => t.reviewEpoch || 0;
    const lastReview = (t, u) => { const l = (t.reviews || []).filter((r) => r.by === u && (r.epoch || 0) === epochOf(t) && r.state !== 'withdrawn'); return l[l.length - 1] || null; };
    const reviewState = (t, u) => { const r = lastReview(t, u); return r ? r.state : 'none'; };
    const reviewPending = (t) => needsCD(t) && reviewersOf(t).some((u) => reviewState(t, u) === 'pending');
    const cdOK = (t) => !needsCD(t) || t.cdStatus === 'approved' || ((t.assignees || []).length > 0 && reviewersOf(t).length === 0);
    const canComplete = (t) => !!t.parentId || (!!sectionOf(t) && isDoneName(sectionOf(t).name) && cdOK(t));
    // the short reason a task can't be completed yet (the app's toasts are short — Haris, 2026-10-31)
    function completeBlocked(t) {
      if (canComplete(t)) return '';
      const s = sectionOf(t), needDone = !(s && isDoneName(s.name)), needCD = !cdOK(t);
      return needDone && needCD ? 'Set to Done and get CD approval first' : needCD ? 'Waiting for CD approval' : 'Set the status to Done first';
    }
    function prioOf(t, who = meId) {
      const pr = t.prio || {};
      if (who && pr[who] != null) return normPrio(pr[who]);
      if (who && (t.assignees || []).includes(who)) return 'none';
      const vals = Object.values(pr).map(normPrio);
      return vals.length ? vals.sort((a, b) => prioRank(a) - prioRank(b))[0] : 'none';
    }
    const byPrio = (a, b) => prioRank(prioOf(a)) - prioRank(prioOf(b));
    const isUrgent = (t) => prioOf(t) === 'urgent';
    const partDone = (t, u = meId) => !!(t.partsDone || {})[u];

    // ---------- whose tasks (Work.day in app.js) ----------
    const isMine = (t) => (t.assignees || []).includes(meId);
    const myOpen = (t) => !t.done && !partDone(t);
    const myDoneAt = (t) => (t.done ? t.completedAt : (t.partsDone || {})[meId] || null);
    const needsOwner = (t) => !t.parentId && !t.done && !(t.assignees || []).length && t.createdBy === meId;
    const onMyList = (t) => isMine(t) || needsOwner(t);
    const amClients = (id) => projects.filter((p) => (p.ams || []).some((a) => a.id === id && !a.onLeave)).map((p) => p.id);
    const hasClients = (id) => projects.some((p) => (p.ams || []).some((a) => a.id === id));
    const createdBy = (ids) => { const set = new Set(ids); return topTasks().filter((t) => set.has(t.createdBy)); };
    function ofAms(ids) {
      const pids = new Set(), byOwn = new Set();
      ids.forEach((id) => { if (hasClients(id)) amClients(id).forEach((x) => pids.add(x)); byOwn.add(id); });
      return topTasks().filter((t) => (t.projectId ? pids.has(t.projectId) || (byOwn.has(t.createdBy) && !hasClients(t.createdBy)) : byOwn.has(t.createdBy)));
    }
    function leadSet(ids) {
      const am = ids.filter((id) => { const u = userById(id); return u && u.role === 'am' && !isAdm(u); });
      const rest = ids.filter((id) => !am.includes(id));
      const set = new Map();
      ofAms(am).forEach((t) => set.set(t.id, t));
      createdBy(rest).forEach((t) => set.set(t.id, t));
      return [...set.values()];
    }
    function day() {
      if (!lead()) return { tasks: tasks.filter(onMyList), open: myOpen, doneAt: myDoneAt, doneTasks: tasks.filter(isMine) };
      const who = seesAll() ? users.filter((x) => x.role === 'am' || isAdm(x)).map((x) => x.id) : [meId];
      const ts = leadSet(who);
      return { tasks: ts, open: (t) => !t.done, doneAt: (t) => (t.done ? t.completedAt || null : null), doneTasks: ts };
    }
    const dayTitle = () => (seesAll() ? 'E11 Day' : 'My Day');
    // Home's groups (phone.js myDayData)
    function myDayData() {
      const D = day();
      const open = D.tasks.filter(D.open);
      const sortP = (a, b) => byPrio(a, b) || (a.due || '').localeCompare(b.due || '') || String(a.createdAt || '').localeCompare(String(b.createdAt || ''));
      const overdue = open.filter((t) => t.due && t.due < today).sort(sortP);
      const due = open.filter((t) => t.due === today).sort(sortP);
      const going = open.filter((t) => t.start && t.start <= today && t.due && t.due > today).sort(sortP);
      const done = D.doneTasks.filter((t) => D.doneAt(t) && dubaiDay(Date.parse(D.doneAt(t))) === today);
      const review = open.filter((t) => t.cdStatus === 'review').length;
      return { overdue, due, going, done, review };
    }

    // ---------- the cards ----------
    function fmtDue(s) {
      if (!s) return '';
      const d = dayDiff(s);
      if (d === 0) return 'Today';
      if (d === 1) return 'Tomorrow';
      if (d === -1) return 'Yesterday';
      if (d > 1 && d < 7) return WDAYS[wdayOf(s)];
      const [y, m, dd] = s.split('-').map(Number);
      return `${MON3[m - 1]} ${dd}${y !== Number(today.slice(0, 4)) ? `, ${y}` : ''}`;
    }
    function mwDue(t) {
      if (!t.due) return '';
      const d = dayDiff(t.due);
      if (!t.done && d < 0) return d === -1 ? 'Yesterday' : `${-d} days ago`;
      return fmtDue(t.due);
    }
    const peopleOn = new Set();
    function cardOf(t, o = {}) {
      const p = proj(t.projectId), s = statusInfo(t);
      const open = !t.done && !partDone(t);
      const late = open && t.due && dayDiff(t.due) < 0;
      const metaL = [p ? { t: p.name, dot: rgbOf(p.color) } : { t: 'My Tasks' }];
      if (o.status !== false) metaL.push({ t: s.name });
      if (t.due) metaL.push({ t: mwDue(t), b: late ? 'late' : dayDiff(t.due) === 0 && open ? 'today' : 'plain' });
      const nc = (t.comments || []).length;
      if (nc) metaL.push({ t: `${nc} comment${nc === 1 ? '' : 's'}`, cm: true });
      const pr = prioOf(t);
      const badge = isUrgent(t) && !t.done ? { t: 'Urgent', urgent: true } : typeof normPrio(pr) === 'number' ? { t: String(normPrio(pr)) } : null;
      const c = t.cdStatus && !t.done ? CD[t.cdStatus] : null;
      const st = sectionOf(t);
      let kind = 'mid', frac = 0.5;
      if (t.done || (st && isDoneName(st.name))) kind = 'done';
      else if (!st || isToDoName(st.name)) kind = 'todo';
      else { const list = statusList(t) || []; const i = list.indexOf(st); frac = list.length > 1 ? i / (list.length - 1) : 0.5; }
      const ids = t.assignees || [];
      ids.slice(0, 2).forEach((id) => peopleOn.add(id));
      return {
        id: t.id, title: t.title || '', late: !!late, done: !!t.done, meta: metaL,
        icon: { kind, frac, rgb: rgbOf(t.done ? '#3ddc97' : s.color) },
        badge, cd: c ? { t: t.cdStatus === 'approved' ? 'CD Approved' : 'CD Review', check: t.cdStatus === 'approved', rgb: rgbOf(c.color) } : null,
        av: ids.slice(0, 2).map((id) => ({ id, done: !!partDone(t, id) })), more: Math.max(0, ids.length - 2),
        // (swiped right: Done — ready means the page's own tick would complete it now, else `why` — and Due, for those
        //  who may change dates)
        due: t.due || '', canDone: !t.parentId && !amReadOnly(t), doneReady: !!t.done || canComplete(t), why: t.done ? '' : completeBlocked(t),
        canDue: can('editDates', t), canDelete: can('deleteTask', t),
      };
    }
    function home() {
      const u = me();
      if (!u || u.active === false || isOffice(u) || isFinUser(u)) return null;
      const { overdue, due, going, done, review } = myDayData();
      const grp = (name, list, o = {}) => (list.length || o.empty ? { name, n: list.length, empty: list.length ? '' : o.empty || '', cards: list.map((t) => cardOf(t, o)) } : null);
      peopleOn.add(meId);
      const groups = [grp('Today', due, { empty: 'Nothing due today 🎉' }), grp('In progress', going), grp('Overdue', overdue), grp('Completed today', done, { status: false })].filter(Boolean);
      return {
        show: true, title: dayTitle(), date: longDate(today), me: meId, stats: [due.length, overdue.length, review], groups,
        add: can('createTask'), canDelete: can('deleteTask'),
        // the people on it: initials and colour (and their photo's file, for the app to fetch)
        people: Object.fromEntries([...peopleOn].map((id) => { const p = userById(id); return [id, { initials: initials(fullName(p)), color: rgbOf(avColor(id || 'x')), photo: p && p.avatar ? p.avatar : null }]; })),
      };
    }
    return { home, myDayData, cardOf, can, amReadOnly, canComplete, completeBlocked, dayTitle, statusInfo, sectionOf };
  }

  return { make, home: (db, meId, today) => make(db, meId, today).home(), dubaiDay, rgbOf };
})();
if (typeof module !== 'undefined' && module.exports) module.exports = E11Rules;
