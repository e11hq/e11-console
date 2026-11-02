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
    // (lookups by id: a plain search for the first few, a map once it's asked often — the website calls these rules for
    //  every single change, so building maps up front each time was slow with thousands of tasks)
    const finder = (list) => { let m = null, n = 0; return (id) => { if (m) return m.get(id); if (++n > 12) { m = new Map(list.map((x) => [x.id, x])); return m.get(id); } return list.find((x) => x.id === id); }; };
    const uFind = finder(users), pFind = finder(projects), tFind = finder(tasks);
    const userById = (id) => uFind(id) || null;
    const proj = (id) => pFind(id);
    const task = (id) => tFind(id);
    const me = () => userById(meId);
    const fullName = (u) => (u ? (u.name || String(u.email || '').split('@')[0]) : 'Former member');
    const topTasks = () => tasks.filter((t) => !t.parentId);
    const statuses = () => (Array.isArray(db.statuses) && db.statuses.length ? db.statuses : DEFAULT_STATUSES);
    const dayDiff = (s) => dayNum(s) - dayNum(today);
    const env = make.env || {};
    // (the day something was done: the device's own on the website, Dubai's on the server)
    const dayOf = env.dayOf || ((iso) => dubaiDay(Date.parse(iso)));

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
    // a completed task is locked (read only, comments too) for its 30 days — its subtasks with it; only Admins reopen it,
    // and whoever completed it may undo that for a few seconds (Haris, 2026-11-01)
    const UNDO_MS = 10000;
    const doneLocked = (t) => { if (!t) return false; const root = t.parentId ? task(t.parentId) || t : t; return !!root.done && !root.parentId; };
    const canReopen = (t) => !!t && !!t.done && (isAdm(me()) || (t.completedBy === meId && nowMs() - Date.parse(t.completedAt || 0) < UNDO_MS));
    // the app's Done (swipe right): to the Done status and complete, in one go (Haris, 2026-10-31) — unless the CD's
    // review is in the way (the website's own rules for a status change: files with the CD lock it; with CD review on,
    // nothing goes past Review until the CD approves)
    const doneSection = (t) => (statusList(t) || []).find((x) => isDoneName(x.name)) || null;
    function finishBlocked(t) {
      if (t.done || canComplete(t)) return '';
      if (reviewPending(t)) return 'Files are with the CD for review';
      if (!cdOK(t)) return 'Waiting for CD approval';
      if (!doneSection(t)) return 'This task has no Done status';
      return '';
    }
    const canFinish = (t) => !t.done && !finishBlocked(t);
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
      const done = D.doneTasks.filter((t) => D.doneAt(t) && dayOf(D.doneAt(t)) === today);
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
      // (o.client / o.due false: under the app's Today, where the client is the heading and every task is today's)
      const metaL = o.client === false ? [] : [p ? { t: p.name, dot: rgbOf(p.color) } : { t: 'My Tasks' }];
      if (o.status !== false) metaL.push({ t: s.name });
      if (t.due && o.due !== false) metaL.push({ t: mwDue(t), b: late ? 'late' : dayDiff(t.due) === 0 && open ? 'today' : 'plain' });
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
        id: t.id, title: t.title || '', late: !!late, done: !!t.done, meta: metaL, inline: !!o.inline,
        icon: { kind, frac, rgb: rgbOf(t.done ? '#3ddc97' : s.color) },
        badge, cd: c ? { t: t.cdStatus === 'approved' ? 'CD Approved' : 'CD Review', check: t.cdStatus === 'approved', rgb: rgbOf(c.color) } : null,
        av: ids.slice(0, 2).map((id) => ({ id, done: !!partDone(t, id) })), more: Math.max(0, ids.length - 2),
        // (swiped right: Done — ready means the page's own tick would complete it now, else `why` — and Due, for those
        //  who may change dates)
        due: t.due || '', canDone: !t.parentId && !amReadOnly(t) && (!t.done || canReopen(t)), doneReady: !!t.done || canFinish(t), why: t.done ? '' : finishBlocked(t),
        // (held by the CD's review: the app shows a faded orange CD · Review instead of Done)
        cdHold: !t.done && !canComplete(t) && (reviewPending(t) || !cdOK(t)),
        canDue: can('editDates', t) && !amReadOnly(t), canDelete: can('deleteTask', t) && !amReadOnly(t),
      };
    }
    // ---------- My Tasks (the iPhone app's, 2026-11-01): All (open) · Done (the last 30 days) ----------
    // F: { due: 'late'|'today'|'week', people: [ids], ams: [ids], team, assigned, cd } — the filters this person may use
    // (myTasksFilters); All in groups Today · Next · Overdue · No due date (by date, then priority), Done newest first.
    // (The website's My Tasks keeps its own: Work.list in app.js.)
    const byDayThenPrio = (a, b) => (a.due || '9999').localeCompare(b.due || '9999') || byPrio(a, b) || String(a.createdAt || '').localeCompare(String(b.createdAt || ''));
    // who sees which filter (Haris, 2026-11-01): Due date everyone; People Account Managers, Admins and the CD; Account
    // managers Admins and the CD; Assigned to me the CD only (Account Managers and Admins aren't assigned)
    function myTasksFilters() {
      const u = me(), out = ['due'];
      if (!u) return out;
      if (lead()) out.push('people');
      if (seesAll()) out.push('ams');
      if (isCD(meId)) out.push('assigned');
      return out;
    }
    const weekEnd = () => ofNum(dayNum(today) + (6 - ((wdayOf(today) + 6) % 7)));
    const dueOk = (t, k) => (k === 'late' ? !!t.due && t.due < today : k === 'today' ? t.due === today : k === 'week' ? !!t.due && t.due >= today && t.due <= weekEnd() : true);
    function myTasks(F0 = {}, tab = 'all') {
      const ok = new Set(myTasksFilters());
      const F = { due: ok.has('due') ? F0.due || null : null, people: ok.has('people') ? F0.people || [] : [], ams: ok.has('ams') ? F0.ams || [] : [], team: ok.has('ams') && !!F0.team, assigned: ok.has('assigned') && !!F0.assigned, cd: !!F0.cd };
      const personal = !lead() || F.assigned;
      const teamIds = () => users.filter((x) => x.role === 'am' || isAdm(x)).map((x) => x.id);
      const creators = seesAll() && F.team ? teamIds() : seesAll() && F.ams.length ? F.ams : [meId];
      let l = personal ? topTasks().filter(onMyList) : leadSet(creators);
      if (F.people.length) l = l.filter((t) => (t.assignees || []).some((x) => F.people.includes(x)));
      if (F.cd) l = l.filter((t) => reviewPending(t));
      const openOf = (t) => (personal ? myOpen(t) : !t.done);
      const doneAtOf = (t) => (personal ? myDoneAt(t) : t.done ? t.completedAt || null : null);
      const open = l.filter(openOf).filter((t) => dueOk(t, F.due));
      let groups;
      if (tab === 'done') {
        const cut = nowMs() - 30 * 86400000;
        const list = l.filter((t) => doneAtOf(t) && Date.parse(doneAtOf(t)) > cut && (F.due === 'late' || dueOk(t, F.due))).sort((a, b) => String(doneAtOf(b)).localeCompare(String(doneAtOf(a))));
        groups = [{ name: 'Last 30 days', n: list.length, empty: list.length ? '' : 'Tasks completed in the last 30 days show here.', cards: list.map((t) => {
          // (no due date or status on a completed task's card: the tick and "Completed Oct 31" say it — Haris, 2026-11-01)
          const c = cardOf(t, { due: false, status: false });
          // (a completed task is locked: said on its card)
          const at = t.completedAt ? dayOf(t.completedAt) : '';
          if (t.done) c.meta.push({ t: `Completed${at ? ' ' + fmtDay(at) : ''} — read only`, line: true, lock: true });
          return c;
        }) }];
      } else {
        const g = (name, list, empty) => (list.length || empty ? { name, n: list.length, empty: list.length ? '' : empty || '', cards: list.sort(byDayThenPrio).map((t) => cardOf(t)) } : null);
        groups = [g('Today', open.filter((t) => t.due === today), F.due === 'today' ? 'Nothing due today 🎉' : ''), g('Next', open.filter((t) => t.due && t.due > today)),
          g('Overdue', open.filter((t) => t.due && t.due < today)), g('No due date', open.filter((t) => !t.due))].filter(Boolean);
        if (!groups.length) groups = [{ name: 'All', n: 0, empty: 'No open tasks here.', cards: [] }];
      }
      peopleOn.add(meId);
      return {
        show: true, kind: 'mytasks', tab: tab === 'done' ? 'done' : 'all', title: 'My Tasks', date: `${open.length} open task${open.length === 1 ? '' : 's'}`,
        me: meId, filters: [...ok], groups, add: can('createTask'), canDelete: can('deleteTask'),
        people: Object.fromEntries([...peopleOn].map((id) => { const p = userById(id); return [id, { initials: initials(fullName(p)), color: rgbOf(avColor(id || 'x')), photo: p && p.avatar ? p.avatar : null }]; })),
      };
    }
    function home() {
      const u = me();
      if (!u || u.active === false || isOffice(u) || isFinUser(u)) return null;
      const { overdue, due, review } = myDayData();
      peopleOn.add(meId);
      // the app's Home (Haris, 2026-10-31): Today, then Overdue — no In progress, and a completed task leaves Home.
      // Today has no heading of its own (only a mark the Due today box scrolls to): its tasks in priority order, each run
      // of one client's tasks under that client's name (its colour dot and how many in the run), the card a single line
      // (status · comments · CD chip)
      const groups = [{ name: 'Today', anchor: true, n: due.length, empty: due.length ? '' : 'Nothing due today 🎉', cards: [] }];
      for (const t of due) {
        const last = groups[groups.length - 1];
        const pid = t.projectId || null;
        if (last.anchor || last.pid !== pid) { const p = pid ? proj(pid) : null; groups.push({ name: p ? p.name : 'My Tasks', dot: p ? rgbOf(p.color) : null, today: true, pid, n: 0, empty: '', cards: [] }); }
        const g = groups[groups.length - 1];
        g.cards.push(cardOf(t, { client: false, due: false, inline: true })); g.n = g.cards.length;
      }
      groups.forEach((g) => { delete g.pid; });
      if (overdue.length) groups.push({ name: 'Overdue', n: overdue.length, empty: '', cards: overdue.map((t) => cardOf(t)) });
      return {
        show: true, title: dayTitle(), date: longDate(today), me: meId, stats: [due.length, overdue.length, review], groups,
        add: can('createTask'), canDelete: can('deleteTask'),
        // the people on it: initials and colour (and their photo's file, for the app to fetch)
        people: Object.fromEntries([...peopleOn].map((id) => { const p = userById(id); return [id, { initials: initials(fullName(p)), color: rgbOf(avColor(id || 'x')), photo: p && p.avatar ? p.avatar : null }]; })),
      };
    }
    // ---------- the app's Inbox (iPhone app 28+): every notification its own row, as Mail's messages ----------
    // a row: who did what (bold), the task (or what it's about), one line of detail, when — Haris, 2026-11-01:
    // "Areej mentioned you" / "KIA | Sheikh Zayed Heritage Festival Screens" / "Kindly find the feedback below, …"
    const plainOf = (h) => String(h || '').replace(/<(br|\/p|\/li|\/div)>/gi, ' ').replace(/<[^>]*>/g, '')
      .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
    const firstOf = (id) => { const u = userById(id); return u ? fullName(u).split(' ')[0] : 'Someone'; };
    function inboxRow(n) {
      const t = n.taskId ? task(n.taskId) : null;
      const who = firstOf(n.from);
      const text = plainOf(n.text);
      const val = plainOf(((String(n.text || '').match(/<b>([^<]*)<\/b>(?![^]*<b>)/) || [])[1]) || '');
      const cm = n.commentId && t ? (t.comments || []).find((x) => x.id === n.commentId) : null;
      const said = cm ? plainOf(cm.html || cm.text) : plainOf(n.snippet);
      // what it is about: the task — or the morning round-up, a birthday, claims, a plan, a client's assets
      const about = n.kind === 'sched-cancel' ? `Scheduled ${/scheduled reply/.test(n.text || '') ? 'reply' : 'comment'}` : t ? (t.title || 'Untitled task')
        : n.kind === 'birthday' ? 'Birthday' : n.kind === 'daily' ? 'Morning round-up' : /^claim/.test(n.kind) ? 'Expense claims' : n.kind === 'asset' ? 'Client Assets' : n.planId ? 'Content plan' : 'Deleted task';
      // who did what: short, so it fits one line (the sentence's verb up to "to / on / for / from / :")
      const verb = text.replace(/\s*(?:—.*)?$/, '').split(/ (?:to|on|for|from|in|of)\b| —|:/)[0].replace(/\s+/g, ' ').trim();
      let head = `${who} ${verb}`, desc = val || '';
      if (n.kind === 'mention') { head = `${who} mentioned you`; desc = said; }
      else if (n.kind === 'comment') { head = `${who} ${/repl/.test(n.text || '') ? 'replied' : 'commented'}`; desc = said; }
      else if (n.kind === 'assigned') { head = /Guardian/.test(text) ? `${who} made you Guardian` : `${who} assigned you`; desc = ''; }
      else if (n.kind === 'unassigned') { head = `${who} removed you`; desc = ''; }
      else if (n.kind === 'status') { head = `${who} changed the status`; desc = val ? `Status: ${val}` : ''; }
      else if (n.kind === 'cd') { head = val === 'Approved' ? `${who} approved it (CD)` : `${who} set CD Review`; desc = val ? `CD ${val}` : ''; }
      else if (n.kind === 'review') { head = `${who} sent files for review`; desc = text.replace(/ for your review on$/, ''); desc = desc.charAt(0).toUpperCase() + desc.slice(1); }
      else if (n.kind === 'review-ok') { head = `${who} approved the files`; desc = /moved to CTR/.test(text) ? 'All approved — moved to CTR' : ''; }
      else if (n.kind === 'review-amend') { head = `${who} requested amendments`; desc = said; }
      else if (n.kind === 'review-wd') { head = `${who} withdrew a submission`; desc = ''; }
      else if (n.kind === 'priority') { head = `${who} set your priority`; desc = val ? `Priority: ${val}` : ''; }
      else if (n.kind === 'update') { head = `${who} set the Task Update`; desc = val; }
      else if (n.kind === 'allparts') { head = `${who} finished the last part`; desc = 'All parts are done — ready for review'; }
      else if (n.kind === 'part') { head = `${who} reopened your part`; desc = ''; }
      else if (n.kind === 'birthday') { head = `${who}’s birthday 🎂`; desc = `Today is ${who}’s birthday`; }
      else if (n.kind === 'daily') { head = 'Your morning round-up'; desc = text; }
      else if (n.kind === 'sched-cancel') { head = 'Not sent'; desc = text + (n.snippet ? ` · “${plainOf(n.snippet)}”` : ''); }
      else if (/^claim|^plan|^asset/.test(n.kind)) { desc = plainOf(n.snippet) || val; }
      if (!desc && n.snippet) desc = plainOf(n.snippet);
      return { id: n.id, read: !!n.read, from: n.from || null, head, title: about, desc, at: n.at, mention: n.kind === 'mention' };
    }
    function inbox(tab = 'all') {
      const u = me();
      if (!u || u.active === false) return null;
      // (expense claims are on the computer: not in the app's Inbox, nor its counts — Haris, 2026-11-01)
      const mine = (db.notifications || []).filter((n) => n.to === meId && !/^claim/.test(n.kind || ''));
      const unread = mine.filter((n) => !n.read).length;
      // (All: the newest 200 — and every unread one and every mention as well, so the app's Unread and Mentions, picked
      //  from these, miss none)
      const byNew = (a, b) => String(b.at).localeCompare(String(a.at));
      const all = mine.slice().sort(byNew);
      const list = tab === 'unread' ? all.filter((n) => !n.read) : tab === 'mentions' ? all.filter((n) => n.kind === 'mention')
        : all.filter((n, i) => i < 200 || !n.read || n.kind === 'mention');
      const rows = list.map(inboxRow);
      rows.forEach((r) => { if (r.from) peopleOn.add(r.from); });
      peopleOn.add(meId);
      return {
        show: true, kind: 'inbox', tab, title: 'Inbox', add: can('createTask'), date: unread ? `${unread} unread update${unread === 1 ? '' : 's'}` : 'All caught up', me: meId, unread, rows,
        empty: tab === 'unread' ? 'Inbox zero 🎉' : tab === 'mentions' ? 'No mentions yet' : 'Nothing here yet',
        people: Object.fromEntries([...peopleOn].map((id) => { const p = userById(id); return [id, { initials: initials(fullName(p)), color: rgbOf(avColor(id || 'x')), photo: p && p.avatar ? p.avatar : null }]; })),
      };
    }
    // ---------- actions (they change the data they were given; the website and the server both use them) ----------
    // env: { nowISO(), nowMs(), uid() }. Activity lines, notifications and the Trash go into db.tasks[].activity,
    // db.notifications and db.trash, exactly as the website always did.

    const nowISO = () => (env.nowISO ? env.nowISO() : new Date().toISOString());
    const nowMs = () => (env.nowMs ? env.nowMs() : Date.now());
    const newId = () => (env.uid ? env.uid() : Date.now().toString(36) + Math.random().toString(36).slice(2, 8));
    const notifs = () => db.notifications || (db.notifications = []);
    const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const trunc = (v, n = 140) => { v = String(v == null ? '' : v).replace(/\s+/g, ' ').trim(); return v.length > n ? v.slice(0, n - 1) + '…' : v; };
    const fmtDay = (d) => { if (!d) return ''; const [y, m, dd] = d.split('-').map(Number); return `${MON3[m - 1]} ${dd}${y !== Number(today.slice(0, 4)) ? `, ${y}` : ''}`; };
    function chg(oldV, newV, long) {
      const o = trunc(oldV, long ? 220 : 80), n = trunc(newV, long ? 220 : 80);
      const empty = '<i class="chg-empty">empty</i>';
      return `<span class="chg${long ? ' long' : ''}"><span class="chg-old">${o ? esc(o) : empty}</span><span class="chg-arrow">→</span><span class="chg-new">${n ? esc(n) : empty}</span></span>`;
    }
    const prioLabel = (p) => { p = normPrio(p); return p === 'urgent' ? 'Urgent' : p === 'none' ? 'No priority' : `Priority ${p}`; };
    const prioOwnerName = (key) => (key === '_' ? '' : fullName(userById(key)));
    function creatorOf(t) {
      const root = t && t.parentId ? task(t.parentId) || t : t;
      const id = t && t.createdBy;
      const u = id && userById(id);
      if (!u || u.role !== 'am' || isAdm(u)) return id || null;
      const p = root && root.projectId ? proj(root.projectId) : null;
      if (!p || !(p.ams || []).length) return id;
      return (p.ams || []).some((a) => a.id === id && !a.onLeave) ? id : null;
    }
    function watchersOf(t) {
      const set = new Set((t.assignees || []).concat(creatorOf(t) ? [creatorOf(t)] : []));
      if (t.parentId) { const p = task(t.parentId); if (p) watchersOf(p).forEach((x) => set.add(x)); }
      return [...set];
    }
    function clientAmsOf(t) {
      const root = t && t.parentId ? task(t.parentId) || t : t;
      const p = root && root.projectId ? proj(root.projectId) : null;
      return p ? (p.ams || []).filter((a) => !a.onLeave).map((a) => a.id) : [];
    }
    const NOTIF_GROUPS = { assigned: 'assign', unassigned: 'assign', mention: 'mention', comment: 'comment', status: 'status', done: 'status', update: 'update', cd: 'cd', edit: 'client', due: 'due', priority: 'priority', attach: 'attach', part: 'part', allparts: 'part', 'review-ok': 'result', 'review-amend': 'result', review: 'review', 'review-wd': 'review-wd', daily: 'daily' };
    const notifOn = (u, kind) => { const g = NOTIF_GROUPS[kind]; return !g || !((u.prefs || {}).notifOff || {})[g]; };
    // one notification per person; never to the person who made the change
    function pushNotif(to, t, kind, text, extra = {}) {
      if (!to || !meId || to === meId || !t) return;
      const u = userById(to);
      if (!u || u.active === false) return;
      if (!notifOn(u, kind)) return;
      if (to === cdUserId() && !['review', 'review-wd', 'mention'].includes(kind) && (t.parentId ? (task(t.parentId) || t) : t).createdBy !== to) return;   // the CD: their own tasks and review requests only
      // one update per change: a specific one (status, comment…) replaces the general "changed …" sent moments before
      const recent = nowMs() - 4000;
      const same = (n) => n.to === to && n.taskId === t.id && n.from === meId && !n.read && Date.parse(n.at) > recent;
      const list = notifs();
      if (kind === 'edit' && list.some((n) => same(n) && n.kind !== 'edit')) return;
      if (kind !== 'edit') {
        const gen = list.find((n) => same(n) && n.kind === 'edit');
        if (gen) { Object.assign(gen, { kind, text, snippet: extra.snippet || '', commentId: extra.commentId || null, at: nowISO() }); return; }
      }
      list.push({ id: newId(), to, from: meId, taskId: t.id, kind, text, snippet: extra.snippet || '', commentId: extra.commentId || null, at: nowISO(), read: false });
      if (list.length > 5000) list.splice(0, list.length - 5000);
    }
    function notifyWatchers(t, kind, text, extra = {}) {
      const skip = new Set(extra.skip || []);
      new Set(watchersOf(t).concat(clientAmsOf(t))).forEach((u) => { if (!skip.has(u)) pushNotif(u, t, kind, text, extra); });   // (+ the client's Account Managers)
    }
    function logActivity(t, text) {
      t.activity = t.activity || [];
      t.activity.push({ id: newId(), at: nowISO(), text, actor: meId });
      if (t.activity.length > 300) t.activity.splice(0, t.activity.length - 300);
      // the client's Account Managers hear about every change on its tasks (whoever made it)
      clientAmsOf(t).forEach((u) => pushNotif(u, t, 'edit', `${text} on`));
    }
    function logChange(t, label, oldV, newV, long) {
      if (String(oldV || '') === String(newV || '')) return;
      logActivity(t, `changed ${label} ${chg(oldV, newV, long)}`);
    }
    // each priority number once per person per day: after a task's day changes (or it's reopened) → the messages to show
    const dayKey = (t) => t.due || 'none';
    const prioTakenBy = (n, d, key, exceptId) => tasks.find((x) => !x.done && !partDone(x, key) && x.id !== exceptId && dayKey(x) === d && normPrio((x.prio || {})[key]) === n) || null;
    function checkPrioConflict(t) {
      const out = [];
      if (t.done) return out;
      Object.entries(t.prio || {}).forEach(([key, v]) => {
        const p = normPrio(v);
        if (typeof p !== 'number') return;
        const other = prioTakenBy(p, dayKey(t), key, t.id);
        if (!other) return;
        delete t.prio[key];
        const who = prioOwnerName(key);
        logActivity(t, `cleared ${who ? `<b>${esc(who)}</b>’s` : 'the'} <b>priority</b> ${chg(prioLabel(p), prioLabel('none'))} (already used by another task that day)`);
        out.push(`${who ? who + '’s ' : ''}Priority ${p} is already used by “${other.title || 'Untitled task'}” ${t.due ? 'on ' + fmtDue(t.due) : 'with no due date'} — cleared`);
      });
      return out;
    }
    function setDone(t, done) {
      if (!!t.done !== !!done) {
        logActivity(t, done ? 'completed this task' : 'reopened this task');
        notifyWatchers(t, 'done', done ? 'completed' : 'reopened');
      }
      t.done = done;
      t.completedAt = done ? nowISO() : null;
      t.completedBy = done ? meId : null;   // (who completed it: they may undo it for a few seconds)
      t.updatedAt = nowISO();
      return !done && tasks.includes(t) ? checkPrioConflict(t) : [];
    }
    function setDue(t, v) {
      const o = t.due;
      t.due = v || null;
      if (o === t.due) return [];
      logChange(t, 'the <b>due date</b>', fmtDay(o), fmtDay(t.due));
      notifyWatchers(t, 'due', t.due ? `changed the due date to <b>${esc(fmtDay(t.due))}</b>` : 'removed the due date');
      const out = checkPrioConflict(t);
      t.updatedAt = nowISO();
      return out;
    }
    // a status change (app.js moveTask): logged; the people on it told unless `quiet` (Done's own "completed" says it)
    function moveToStatus(t, sectionId, quiet) {
      if (t.sectionId !== sectionId) {
        const list = statusList(t) || [];
        const from = list.find((x) => x.id === t.sectionId), to = list.find((x) => x.id === sectionId);
        if (to) { logChange(t, 'the <b>status</b>', from ? from.name : '', to.name); if (!quiet) notifyWatchers(t, 'status', `changed the status to <b>${esc(to.name)}</b>`); }
      }
      t.sectionId = sectionId;
      descendants(t.id).forEach((d) => { d.sectionId = sectionId; });
      const sibs = db.tasks.filter((x) => !x.parentId && x.projectId === t.projectId && x.sectionId === sectionId && x.id !== t.id).sort((a, b) => (a.order || 0) - (b.order || 0));
      sibs.push(t);
      sibs.forEach((x, i) => { x.order = i + 1; });
      t.updatedAt = nowISO();
    }
    // the app's Done: to the Done status (when it isn't there yet), then complete → the messages to show
    function finish(t) {
      if (!canComplete(t)) { const d = doneSection(t); if (d) moveToStatus(t, d.id, true); }
      return setDone(t, true);
    }
    // completing a task the CD approved asks whether the client approved (kept with the final files)
    const lastCDApprovalAt = (t) => (t.reviews || []).filter((r) => r.state === 'approved').map((r) => r.decidedAt || r.at || '').sort().pop() || '';
    const clientApprovalFresh = (t) => !!t.clientApproval && String(t.clientApproval.at || '') >= lastCDApprovalAt(t);
    const cdApprovedNow = (t) => !t.parentId && t.cdStatus === 'approved';
    const asksClientApproval = (t) => !t.done && cdApprovedNow(t) && !clientApprovalFresh(t);
    function setClientApproval(t, v) {
      if (v === null) { delete t.clientApproval; logActivity(t, 'cleared the <b>client approval</b>'); }
      else { t.clientApproval = { ...v, by: meId, at: nowISO() }; logActivity(t, v.none ? 'noted that <b>client approval isn’t needed</b>' : 'recorded the <b>client’s approval</b>'); }
      t.updatedAt = nowISO();
    }
    function descendants(id) {
      const out = [];
      const walk = (pid) => db.tasks.filter((t) => t.parentId === pid).forEach((t) => { out.push(t); walk(t.id); });
      walk(id);
      return out;
    }
    // a task (and its subtasks) to the Trash; the people on it hear about it, so a mistake is spotted early
    function deleteTask(t) {
      const ids = [t.id, ...descendants(t.id).map((d) => d.id)];
      if (t.parentId && task(t.parentId)) logActivity(task(t.parentId), `deleted subtask <span class="chg-old">${esc(trunc(t.title || 'Untitled task', 80))}</span>`);
      const set = new Set(ids);
      const removed = db.tasks.filter((x) => set.has(x.id));
      db.tasks = db.tasks.filter((x) => !set.has(x.id));
      if (!t.parentId) notifyWatchers(t, 'trash', `moved <b>${esc(t.title || 'Untitled task')}</b> to the Trash —`);
      db.trash = db.trash || [];
      const item = { id: 'tr-' + newId(), type: 'task', deletedAt: nowISO(), deletedBy: meId, key: 'tasks:' + t.id, projectId: t.projectId, projectName: (proj(t.projectId) || {}).name || '', data: { tasks: removed } };
      db.trash.push(item);
      return { ids, removed, item };
    }

    // ---------- the iPhone app's native task page (shell 30+, 2026-11-01): GET /api/task?id= ----------
    // Everything the Details tab shows, worked out here (the website's own rules), with what this person may change.
    const TAG_HUES = ['#5b8cff', '#3ddc97', '#ffb547', '#ff6b6b', '#c27cff', '#4fd1c5', '#ff8fc7', '#9aa0ab'];
    const tagRgb = (name) => { let h = 0; for (const c of String(name).toLowerCase()) h = (h * 31 + c.charCodeAt(0)) >>> 0; return rgbOf(TAG_HUES[h % TAG_HUES.length]); };
    // the Finance status (app.js FINANCE): seen and changed by Account Managers (their clients' tasks) and Admins
    const FINANCE = { 'Quote to be sent': '#9aa4b2', 'LPO Pending': '#f9be33', 'Invoiced': '#3ddc97', 'Retainer': '#a875ff', 'To be invoiced': '#ff8a4c' };
    const canFinance = (t) => isManager(me()) && amScope(t);
    const UPDATES = ['WIP', 'Brief to come', 'Amendments', 'Minor Amendments', 'Shoot', 'Edit Video', 'Adaptations', 'On hold', 'Oversee', 'Followup', 'Meeting', 'Reel Cover', 'Ready to Post', 'Ongoing', 'Redesign', 'Awaiting client assets', 'Storyboard', 'Open files', 'Brainstorm', 'Briefing', 'Out of scope', 'Dispatch', 'Copy Writing', 'Edit images', 'HTML', 'Mockup'];
    const FIELD_COLORS = ['#f9be33', '#4c9aff', '#ff6b70', '#3ddc97', '#a875ff', '#ff8a4c', '#4fd1c5', '#ff8fc7', '#9aa4b2', '#7b68ee'];
    const updateRgb = (v) => rgbOf(FIELD_COLORS[Math.max(0, UPDATES.indexOf(v)) % FIELD_COLORS.length]);
    const CHANNEL_NAMES = { ig: 'Instagram', tt: 'TikTok', li: 'LinkedIn', x: 'X', fb: 'Facebook', yt: 'YouTube', sc: 'Snapchat', edm: 'EDM' };
    const SEC_REVIEW = /^(internal )?review$/i, SEC_CTR = /^ctr$/i;
    const lockRoot = (t) => (t && t.parentId ? task(t.parentId) || t : t);
    const idLocked = (t) => { const r = lockRoot(t); return !!r && (!!r.lockedAt || (r.reviews || []).length > 0); };
    const peopleLocked = (t) => !!t && !t.parentId && idLocked(t);   // (Assignees and Guardian too — Haris 2026-11-02)
    const lockedSince = (t) => { const r = lockRoot(t); return (r && (r.lockedAt || (r.reviews || []).map((x) => x.at).filter(Boolean).sort()[0])) || null; };
    const iReview = (t) => needsCD(t) && isMine(t) && !isCD(meId);
    const statusLocked = (t) => reviewPending(t);
    function pastReview(t, sectionId) {
      const list = statusList(t) || [], to = list.findIndex((x) => x.id === sectionId), s = list[to];
      if (!s) return false;
      if (SEC_CTR.test(String(s.name).trim()) || isDoneName(s.name)) return true;
      const rv = list.findIndex((x) => SEC_REVIEW.test(String(x.name).trim()));
      return rv >= 0 && to > rv;
    }
    const plainOfHtml = (h) => String(h || '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h\d)>/gi, '\n').replace(/<li[^>]*>/gi, '• ').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\n{3,}/g, '\n\n').trim();
    const firstName = (id) => (id === meId ? 'You' : (fullName(userById(id)) || '').split(' ')[0] || 'Someone');
    function taskPage(id) {
      const t = task(id);
      const u = me();
      if (!t || !u || isFinUser(u)) return null;
      const ro = amReadOnly(t) || doneLocked(t);
      const pp = new Set();
      const person = (pid) => { if (pid) pp.add(pid); return pid; };
      const p = proj(t.projectId), parent = t.parentId ? task(t.parentId) : null;
      const s = statusInfo(t), list = statusList(t) || [];
      const at = list.findIndex((x) => x.id === t.sectionId);
      const lockedId = idLocked(t);
      const ids = t.assignees || [];
      const cdWait = !t.parentId && needsCD(t) && !cdOK(t);
      const m = {
        id: t.id, me: meId, title: t.title || '', done: !!t.done, sub: !!t.parentId, parent: parent ? { id: parent.id, title: parent.title || 'Untitled task' } : null,
        client: p ? { id: p.id, name: p.name, rgb: rgbOf(p.color || '#87909e') } : null,
        readOnly: ro, why: doneLocked(t) ? 'Completed tasks are read only' : amReadOnly(t) ? 'View only — you can’t change this task' : '',
        canTitle: !ro && can('editTitle', t) && !lockedId,
        lock: lockedId ? { text: `${t.parentId ? 'Its name is locked with its main task' : 'Name, description, client, assignees and guardian are locked'} — ${t.parentId ? 'it' : 'this task'} went for CD review${lockedSince(t) ? ` on ${fmtDay(String(lockedSince(t)).slice(0, 10))}` : ''}.`, from: !t.parentId && can('createTask', t) } : null,
        basedOn: t.basedOn && task(t.basedOn) ? { id: t.basedOn, title: task(t.basedOn).title || 'Untitled task' } : null,
        kids: db.tasks.filter((x) => x.basedOn === t.id).map((x) => ({ id: x.id, title: x.title || 'Untitled task' })),
        completed: t.done ? { at: t.completedAt ? dayOf(t.completedAt) : '', label: t.completedAt ? fmtDay(dayOf(t.completedAt)) : '', left: t.completedAt ? Math.max(0, 30 - Math.floor((nowMs() - Date.parse(t.completedAt)) / 86400000)) : null, canReopen: canReopen(t), canFrom: !t.parentId && can('createTask', t) } : null,
        status: { name: s.name, rgb: rgbOf(s.color), canSet: !ro && !t.done && !statusLocked(t), why: statusLocked(t) ? 'The status is locked while files are with the CD for review' : '',
          next: !ro && !t.done && !statusLocked(t) && at < list.length - 1 && !(cdWait && pastReview(t, (list[Math.max(0, at) + 1] || {}).id)) ? (list[Math.max(0, at) + 1] || {}).id || null : null,
          options: list.map((x) => ({ id: x.id, name: x.name, rgb: rgbOf(x.color || '#87909e'), on: !t.done && x.id === t.sectionId, locked: cdWait && x.id !== t.sectionId && pastReview(t, x.id) })) },
        cd: !t.parentId && (needsCD(t) || t.cdStatus) && t.cdStatus && CD[t.cdStatus] ? { label: t.cdStatus === 'approved' ? 'CD Approved' : 'CD · Review', rgb: rgbOf(CD[t.cdStatus].color), check: t.cdStatus === 'approved' } : null,
        creator: t.createdBy && userById(t.createdBy) ? { id: person(t.createdBy), when: t.createdAt ? fmtDay(dayOf(t.createdAt)) : '' } : null,
        assignees: ids.map((x) => ({ id: person(x), done: partDone(t, x) })), canAssign: !ro && can('assign', t) && !(lockedId && !t.parentId),
        parts: !t.parentId && !t.done && ids.length ? {
          n: ids.filter((x) => partDone(t, x)).length, of: ids.length,
          chips: ids.map((x) => ({ id: x, name: firstName(x), done: partDone(t, x), pending: !partDone(t, x) && needsCD(t) && reviewState(t, x) === 'pending' })),
          mine: isMine(t) && !ro ? (iReview(t) ? (reviewState(t, meId) === 'approved' ? 'approved' : reviewState(t, meId) === 'pending' ? 'pending' : 'review') : partDone(t) ? 'done' : 'open') : null,
        } : null,
        dates: { start: t.start || '', due: t.due || '', startLabel: t.start ? fmtDay(t.start) : '', dueLabel: t.due ? fmtDay(t.due) : '', late: !t.done && !!t.due && dayDiff(t.due) < 0, today: !t.done && !!t.due && dayDiff(t.due) === 0, canEdit: !ro && can('editDates', t) },
        prio: (ids.length > 1 || (ids.length === 1 && ids[0] !== meId) ? ids : [ids[0] || '_']).map((k) => {
          const v = k === '_' ? normPrio((t.prio || {})._) : prioOf(t, k);
          if (k !== '_') person(k);
          // (taken: the numbers this person already has on other tasks that day — greyed in the app's sheet, as the website's)
          return { key: k, name: k === '_' ? '' : firstName(k), v: v === 'none' ? '' : String(v), label: v === 'urgent' ? 'Urgent' : v === 'none' ? '' : String(v), taken: !ro && can('editPriority', t) ? prioTaken(t, k) : [] };
        }), canPrio: !ro && can('editPriority', t),
        tags: (t.tags || []).map((g) => ({ t: g, rgb: tagRgb(g) })), canTags: !ro && can('addTag', t), canRemoveTag: !ro && can('removeTag', t), allTags: !ro && can('addTag', t) ? allTags() : [],
        pool: !ro && can('assign', t) && !(lockedId && !t.parentId) ? assignPool(t) : [], channelKeys: t.channels || [], canChannels: !ro && !t.parentId && !!u && (isAdm(u) || u.role === 'am' || u.role === 'social'), canGuardian: !ro && !t.parentId && can('assign', t) && !lockedId,
        canClient: !ro && !t.parentId && can('editProject', t) && !lockedId, clients: !ro && !t.parentId && can('editProject', t) && !lockedId ? movable().map((p) => ({ id: p.id, name: p.name, rgb: rgbOf(p.color || '#87909e'), on: p.id === t.projectId })) : [], allChannels: Object.entries(CHANNEL_NAMES).map(([k, n]) => ({ k, n })),
        channels: (t.channels || []).map((c) => CHANNEL_NAMES[c] || c),
        guardian: t.guardian && userById(t.guardian) ? person(t.guardian) : null,
        // (the Finance status: only for whoever may see and change it — Haris 2026-11-02, above Client on the app's page)
        finance: !t.parentId && canFinance(t) ? { v: t.finance || '', rgb: t.finance ? rgbOf(FINANCE[t.finance] || '#9aa4b2') : null } : null,
        financeOpts: !t.parentId && canFinance(t) && !ro ? Object.keys(FINANCE).map((k) => ({ t: k, rgb: rgbOf(FINANCE[k]) })) : [], canFinance: !t.parentId && canFinance(t) && !ro,
        update: t.update ? { t: t.update, rgb: updateRgb(t.update) } : null, updates: UPDATES, updateRgbs: UPDATES.map(updateRgb),
        canFields: !ro && !t.parentId,
        review: !t.parentId && !t.done ? { on: !!t.needsCD, canSet: !ro && !!u && (isAdm(u) || u.role === 'am' || isCD(meId)) && !reviewPending(t), who: cdUserId() ? fullName(userById(cdUserId())) : '' } : null,
        clientApproval: cdApprovedNow(t) ? (() => { const ca = t.clientApproval, fresh = clientApprovalFresh(t);
          return { state: ca && fresh ? (ca.none ? 'none' : 'yes') : ca ? 'old' : 'missing', text: ca && fresh ? (ca.none ? 'Not needed' : `Approved · ${firstName(ca.by)} · ${fmtDay(dayOf(ca.at))}`) : ca ? 'Out of date' : 'Missing', canSet: !ro && !t.done && !!u && (isAdm(u) || u.role === 'am' || t.createdBy === meId) }; })() : null,
        desc: t.notesHtml ? plainOfHtml(t.notesHtml) : String(t.notes || '').trim(), descRuns: runsOf({ html: t.notesHtml || '', text: t.notes || '' }, true), descFiles: fileRefsOf(t.notesHtml), canDesc: !ro && can('editDesc', t) && !lockedId, mentionable: !ro && can('editDesc', t) && !lockedId ? mentionable() : [],
        review2: !t.parentId && needsCD(t) && isMine(t) && !isCD(meId) && !ro ? { state: reviewState(t, meId), canSubmit: !t.done && !(sectionOf(t) && isToDoName(sectionOf(t).name)), cd: cdUserId() ? fullName(userById(cdUserId())) : '', since: (lastReview(t, meId) || {}).at || '' } : null,
        subtasks: subtasksOf(t.id).map((x) => { (x.assignees || []).slice(0, 1).forEach(person); return { id: x.id, title: x.title || 'Untitled', done: !!x.done, due: x.due ? fmtDay(x.due) : '', late: !x.done && !!x.due && dayDiff(x.due) < 0, av: (x.assignees || [])[0] || null, canTick: !ro && !amReadOnly(x) }; }),
        canAddSub: !ro && !t.parentId && can('createTask', t),
        checklist: (t.checklist || []).map((c) => ({ id: c.id, text: c.text || '', done: !!c.done })), canCheck: !ro, canAddCheck: !ro && can('addChecklist', t),
        files: (t.attachments || []).filter((a) => !a.reviewId || (t.reviews || []).some((r) => r.id === a.reviewId && r.state === 'approved')).map((a) => ({ id: a.id, name: a.name || 'File', size: a.size || 0, path: a.path || null, thumb: a.thumb || null, type: a.type || '' })),
        // the comments' own files (not voice messages), newest first: their own group under Files (the app only)
        commentFiles: (t.comments || []).slice().reverse().flatMap((c) => (c.attachments || []).filter((a) => !a.voice).map((a) => { person(c.authorId); return { id: a.id, name: a.name || 'File', size: a.size || 0, path: a.path || null, thumb: a.thumb || null, type: a.type || '', by: c.authorId || null, at: c.at || '' }; })),
        activity: (t.activity || []).slice(-30).reverse().map((a) => { person(a.actor); return { who: a.actor || null, text: plainOfHtml(a.text).replace(/\s*→\s*/g, ' → '), at: a.at || '' }; }),
        comments: (t.comments || []).length, canDelete: !ro && can('deleteTask', t),
        complete: t.done ? null : { ok: !ro && canComplete(t), why: ro ? '' : completeBlocked(t), show: !ro && !t.parentId },
      };
      m.people = Object.fromEntries([...pp].filter(Boolean).map((pid) => { const x = userById(pid); return [pid, { name: fullName(x) || 'Someone', first: firstName(pid), initials: initials(fullName(x) || '?'), color: rgbOf(avColor(pid || 'x')), photo: x && x.avatar ? x.avatar : null }]; }));
      return m;
    }
    // ---------- step 1b: assignees, guardian, tags, channels, checklist items (as app.js does them) ----------
    const ASSIGNABLE = new Set(['production', 'social', 'freelancer']);
    const assignable = (x) => !!x && x.active !== false && (ASSIGNABLE.has(x.role) || x.id === cdUserId());
    const struck = (v) => `<span class="chg-old">${esc(trunc(v, 80))}</span>`;
    // who may be picked (the people sheet): those assigned first, then everyone else who may be assigned
    function assignPool(t) {
      const ids = t.assignees || [];
      const others = users.filter((x) => assignable(x) && !ids.includes(x.id)).sort((a, b) => fullName(a).localeCompare(fullName(b)));
      return ids.map(userById).filter(Boolean).concat(others).map((x) => ({ id: x.id, name: fullName(x), role: x.id === cdUserId() ? 'Creative Director' : ({ production: 'Production', social: 'Social', freelancer: 'Freelancer' })[x.role] || '', on: ids.includes(x.id), photo: x.avatar || null, initials: initials(fullName(x) || '?'), color: rgbOf(avColor(x.id)) }));
    }
    function syncCDOf(t) {
      if (!needsCD(t)) return;
      const rv = reviewersOf(t);
      if (!rv.length) return;
      const st = rv.map((x) => reviewState(t, x)), prev = t.cdStatus || '';
      t.cdStatus = st.includes('pending') ? 'review' : st.every((x) => x === 'approved') ? 'approved' : '';
      if (prev === t.cdStatus) return;
      if (prev && t.cdStatus) logChange(t, 'the <b>CD Status</b>', CD[prev].label, CD[t.cdStatus].label);
      else if (t.cdStatus) logActivity(t, `CD Status is now <b>${esc(CD[t.cdStatus].label)}</b>`);
      else logActivity(t, `CD Status cleared ${struck(CD[prev].label)}`);
    }
    function setAssignee(t, uid, on) {
      const x = userById(uid);
      if (on && !assignable(x)) return { error: 'Only Production, Social, Freelancers and the CD can be assigned' };
      if (on && uid === cdUserId() && t.cdRule && needsCD(t)) return { error: 'Turn off “Needs CD review” to assign the CD' };
      const has = (t.assignees || []).includes(uid);
      if (!!on === has) return [];
      if (on) {
        t.assignees = (t.assignees || []).concat(uid);
        t.prio = t.prio || {};
        if (t.prio._ != null) { const v = normPrio(t.prio._); delete t.prio._; if (!(typeof v === 'number' && prioTakenBy(v, dayKey(t), uid, t.id))) t.prio[uid] = v; }
        logActivity(t, `assigned <b>${esc(fullName(x))}</b>`);
        pushNotif(uid, t, 'assigned', 'assigned you to');
      } else {
        t.assignees = t.assignees.filter((y) => y !== uid);
        if (t.prio) delete t.prio[uid];
        if (t.partsDone) delete t.partsDone[uid];
        (t.reviews || []).forEach((r) => { if (r.by === uid && r.state === 'pending') r.state = 'withdrawn'; });
        logActivity(t, `unassigned ${struck(fullName(x))}`);
        pushNotif(uid, t, 'unassigned', 'removed you from');
      }
      syncCDOf(t);
      t.updatedAt = nowISO();
      return [];
    }
    function setGuardian(t, v) {
      v = v || null;
      if (v && !userById(v)) return { error: 'That person is no longer here' };
      const old = t.guardian || null;
      if (old === v) return [];
      t.guardian = v;
      logChange(t, 'the <b>Guardian</b>', old ? fullName(userById(old)) : '', v ? fullName(userById(v)) : '');
      if (v) pushNotif(v, t, 'assigned', 'made you the Guardian of');
      t.updatedAt = nowISO();
      return [];
    }
    function addTag(t, v) {
      v = String(v || '').trim().replace(/,$/, '').slice(0, 40);
      if (!v) return [];
      t.tags = t.tags || [];
      if (!t.tags.some((g) => g.toLowerCase() === v.toLowerCase())) { t.tags.push(v); logActivity(t, `added tag <b>${esc(v)}</b>`); t.updatedAt = nowISO(); }
      return [];
    }
    function removeTag(t, v) {
      const i = (t.tags || []).indexOf(v);
      if (i < 0) return [];
      logActivity(t, `removed tag ${struck(v)}`);
      t.tags.splice(i, 1); t.updatedAt = nowISO();
      return [];
    }
    const allTags = () => { const n = {}; tasks.forEach((x) => (x.tags || []).forEach((g) => { n[g] = (n[g] || 0) + 1; })); return Object.keys(n).sort((a, b) => n[b] - n[a] || a.localeCompare(b)).slice(0, 60); };
    function setChannels(t, v) {
      v = [...new Set((v || []).map(String).filter((k) => CHANNEL_NAMES[k]))];
      const names = (ks) => (ks || []).map((k) => CHANNEL_NAMES[k] || k).join(', ');
      if (names(t.channels) === names(v)) return [];
      logChange(t, 'the <b>channels</b>', names(t.channels), names(v));
      t.channels = v; t.updatedAt = nowISO();
      return [];
    }
    function addCheck(t, text) {
      text = String(text || '').trim().slice(0, 300);
      if (!text) return [];
      t.checklist = t.checklist || [];
      t.checklist.push({ id: newId(), text, done: false });
      logActivity(t, `added checklist item <b>${esc(text)}</b>`);
      t.updatedAt = nowISO();
      return [];
    }
    // a subtask (app.js createTask with a parent): the parent's client and status, logged on both
    function addSubtask(t, title) {
      title = String(title || '').replace(/\s+/g, ' ').trim().slice(0, 300);
      if (!title || t.parentId) return [];
      const at = nowISO();
      const sibs = db.tasks.filter((x) => x.parentId === t.id);
      const n = { id: newId(), projectId: t.projectId, sectionId: t.sectionId, parentId: t.id, title, notes: '', done: false, completedAt: null, due: null, prio: {},
        tags: [], attachments: [], comments: [], checklist: [], activity: [{ id: newId(), at, text: 'created this task', actor: meId }], start: null, createdAt: at, updatedAt: at,
        cdRule: 2, cdStatus: '', assignees: [], createdBy: meId, reviews: [], needsCD: false, order: sibs.length + 1 };
      db.tasks.push(n);
      logActivity(t, `added subtask <b>${esc(title)}</b>`);
      t.updatedAt = at;
      return [];
    }
    // the clients this person may move a task into (app.js amClientOk): everyone's for Admins and the CD
    const movable = () => { const u = me(); return projects.filter((p) => !p.archived && (isAdm(u) || isCD(meId) || amScope({ projectId: p.id, createdBy: null }, u))); };
    function setClient(t, pid) {
      const p = pid ? proj(pid) : null;
      if (pid && !p) return { error: 'That client is no longer here' };
      if ((t.projectId || null) === (p ? p.id : null)) return [];
      if (p && !movable().includes(p)) return { error: 'You can’t move tasks into that client' };
      const oldP = proj(t.projectId);
      logChange(t, 'the <b>client</b>', oldP ? oldP.name : 'My Tasks', p ? p.name : 'My Tasks');
      t.projectId = p ? p.id : null;
      t.sectionId = p && p.sections[0] ? p.sections[0].id : (statuses()[0] || {}).id || null;
      const sibs = db.tasks.filter((x) => !x.parentId && x.projectId === t.projectId && x.sectionId === t.sectionId && x.id !== t.id);
      t.order = sibs.length ? Math.max(...sibs.map((x) => x.order || 0)) + 1 : 1;
      descendants(t.id).forEach((d) => { d.projectId = t.projectId; d.sectionId = t.sectionId; });
      t.updatedAt = nowISO();
      return [];
    }
    // ---------- the native Comments (step 2): the feed as runs of text, files, reactions, Seen by, threads ----------
    const ENT = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&nbsp;': ' ' };
    const unent = (v) => String(v).replace(/&(amp|lt|gt|quot|#39|nbsp);/g, (m) => ENT[m] || m);
    // a comment's words → [{ t, b, i, u, s, link, user }] (what the app draws); new lines as "\n"
    // the files pasted into a description or comment (the website's 📎 chips: data-fpath …) — shown as file cards
    function fileRefsOf(html) {
      const out = [], seenP = new Set();
      String(html || '').replace(/<span[^>]*data-fpath="([^"]+)"[^>]*>/gi, (tag, p) => {
        const path = unent(p); if (seenP.has(path)) return tag; seenP.add(path);
        const at = (k) => { const m = new RegExp(k + '="([^"]*)"', 'i').exec(tag); return m ? unent(m[1]) : ''; };
        out.push({ id: 'ref-' + out.length + '-' + path.length, name: at('data-fname') || path.split('/').pop(), size: Number(at('data-fsize')) || 0, path, thumb: at('data-fthumb') || null });
        return tag;
      });
      return out;
    }
    // refs: a pasted file's chip kept in its place as a run of its own ({ t: '📎 name', ref: { path, name, size, thumb } })
    //  — the description's, so the app shows where it is and opens it (Haris 2026-11-02); a comment's stay out of the words
    function runsOf(c, refs) {
      if (!c.html) return [{ t: String(c.text || '') }];
      const out = [], st = { b: 0, i: 0, u: 0, s: 0, link: null, user: null, li: 0, ref: 0 };
      const push = (t) => { if (!t) return; const r = { t }; if (st.b) r.b = 1; if (st.i) r.i = 1; if (st.u) r.u = 1; if (st.s) r.s = 1; if (st.link) r.link = st.link; if (st.user) r.user = st.user; out.push(r); };
      String(c.html).replace(/<[^>]+>|[^<]+/g, (tok) => {
        if (tok[0] !== '<') { if (!st.ref) push(unent(tok)); return ''; }
        const m = /^<\s*(\/)?\s*([a-z0-9]+)([^>]*)>/i.exec(tok); if (!m) return '';
        const close = !!m[1], tag = m[2].toLowerCase(), attrs = m[3] || '';
        if (tag === 'b' || tag === 'strong') st.b += close ? -1 : 1;
        else if (tag === 'i' || tag === 'em') st.i += close ? -1 : 1;
        else if (tag === 'u') st.u += close ? -1 : 1;
        else if (tag === 's' || tag === 'strike' || tag === 'del') st.s += close ? -1 : 1;
        else if (tag === 'br') push('\n');
        else if (tag === 'li') { if (!close) push((out.length && !/\n$/.test(out[out.length - 1].t) ? '\n' : '') + '• '); }
        else if (tag === 'p' || tag === 'div' || tag === 'ul' || tag === 'ol') { if (close) push('\n'); }
        else if (tag === 'a') { if (close) st.link = null; else { const h = /href="([^"]+)"/i.exec(attrs); st.link = h ? unent(h[1]) : null; } }
        else if (tag === 'span') {
          // (a file pasted in — the website's 📎 chip: shown as a file card, not as words)
          if (!close && /data-fpath=/i.test(attrs)) {
            if (refs) {
              const at = (k) => { const m2 = new RegExp(k + '="([^"]*)"', 'i').exec(attrs); return m2 ? unent(m2[1]) : ''; };
              const path = at('data-fpath'), name = at('data-fname') || path.split('/').pop();
              out.push({ t: '📎 ' + name, ref: { path, name, size: Number(at('data-fsize')) || 0, thumb: at('data-fthumb') || null } });
            }
            st.ref++; return '';
          }
          if (close && st.ref) { st.ref--; return ''; }
          const u = /data-user="([^"]+)"/i.exec(attrs); if (u && !close) st.user = u[1]; else if (close) st.user = null;
        }
        return '';
      });
      while (out.length && /^\s*$/.test(out[out.length - 1].t)) out.pop();
      if (out.length) out[out.length - 1].t = out[out.length - 1].t.replace(/\n+$/, '');
      return out;
    }
    const urlsIn = (c) => { const f = []; const add = (u) => { u = String(u || '').replace(/[),.;:!?'"\]]+$/, ''); if (/^https?:\/\//i.test(u) && !f.includes(u)) f.push(u); };
      String(c.text || '').replace(/https?:\/\/[^\s<>"']+/gi, (m) => { add(m); return m; }); String(c.html || '').replace(/href="(https?:\/\/[^"]+)"/gi, (_, m) => { add(m.replace(/&amp;/g, '&')); return _; });
      const off = new Set(c.noPreview || []); return f.filter((u) => !off.has(u)).slice(0, 3); };
    function seenOf(c) {
      const who = [...mentionsIn(c.html)].filter((x) => x !== c.authorId && userById(x));
      if (!who.length) return null;
      const seen = c.seen || {}, yes = who.filter((x) => seen[x]).sort((a, b) => String(seen[a]).localeCompare(String(seen[b]))), no = who.filter((x) => !seen[x]);
      const nm = (x) => (x === meId ? 'You' : firstName(x));
      const label = !yes.length ? (who.length === 1 ? `Not seen by ${nm(who[0])} yet` : 'Not seen yet') : who.length === 1 ? `Seen${who[0] === meId ? '' : ` by ${nm(who[0])}`}` : no.length ? `Seen by ${yes.length} of ${who.length}` : 'Seen by everyone mentioned';
      return { label, on: yes.length > 0, at: yes.length === 1 && who.length === 1 ? seen[yes[0]] : null, who: yes.slice(0, 5) };
    }
    function commentsFeed(id, threadId) {
      const t = task(id);
      if (!t || !me()) return null;
      const pp = new Set();
      const ro = amReadOnly(t) || doneLocked(t);
      const all = t.comments || [];
      const kids = (pid) => all.filter((x) => x.parentId === pid);
      const item = (c) => {
        pp.add(c.authorId);
        const reps = c.parentId ? [] : kids(c.id);
        const rx = Object.entries(c.reactions || {}).map(([e, v]) => ({ e, n: Array.isArray(v) ? v.length : Number(v) || 0 })).filter((r) => r.n);   // (as the website keeps them: a count each)
        const sn = seenOf(c); if (sn) sn.who.forEach((x) => pp.add(x));
        reps.slice(-3).forEach((r) => pp.add(r.authorId));
        return {
          id: c.id, who: c.authorId, at: c.at, edited: !!c.editedAt, owner: !!t.createdBy && c.authorId === t.createdBy, mine: c.authorId === meId,
          runs: runsOf(c), text: String(c.text || ''), mentionsMe: mentionsIn(c.html).has(meId),
          files: (c.attachments || []).map((a) => ({ id: a.id, name: a.name || 'File', size: a.size || 0, path: a.path || null, thumb: a.thumb || null, w: a.w || 0, h: a.h || 0, voice: !!a.voice, dur: a.dur || 0 })).concat(fileRefsOf(c.html).map((f) => ({ ...f, id: c.id + '-' + f.id, w: 0, h: 0, voice: false, dur: 0 }))),
          urls: urlsIn(c), reactions: rx, seen: sn,
          replies: reps.length ? { n: reps.length, last: reps[reps.length - 1].at, people: [...new Set(reps.map((r) => r.authorId).reverse())].slice(0, 3) } : null,
          canEdit: !ro && c.authorId === meId && nowMs() - Date.parse(c.at || 0) < 10 * 60000, canDelete: !ro && (c.authorId === meId || isAdm(me())), canReply: !ro && !c.parentId,
        };
      };
      const root = threadId ? all.find((c) => c.id === threadId && !c.parentId) : null;
      const list = threadId ? (root ? [root, ...kids(root.id)] : []) : all.filter((c) => !c.parentId);
      // your own scheduled comments on it, at the end (as the website's)
      const sched = (db.scheduled || []).filter((x) => x.taskId === t.id && x.authorId === meId && x.state === 'waiting' && (!root || x.replyTo === root.id)).sort((a, b) => String(a.sendAt).localeCompare(String(b.sendAt))).map((x) => ({ id: x.id, at: x.sendAt, text: plainOfHtml(x.html || '') || String(x.text || ''), files: (x.attachments || []).length }));
      const out = { id: t.id, me: meId, creator: t.createdBy || null, thread: root ? root.id : null, readOnly: ro, canWrite: !doneLocked(t), scheduled: sched, mentionable: doneLocked(t) ? [] : mentionable(), items: list.map(item), n: all.length, parents: Object.fromEntries(all.filter((c) => c.parentId).map((c) => [c.id, c.parentId])) };
      out.people = Object.fromEntries([...pp].filter(Boolean).map((pid) => { const x = userById(pid); return [pid, { name: fullName(x) || 'Someone', first: firstName(pid), initials: initials(fullName(x) || '?'), color: rgbOf(avColor(pid || 'x')), photo: x && x.avatar ? x.avatar : null }]; }));
      return out;
    }
    // a comment and its replies to the Trash (app.js deleteComment) → its Trash entry, for Undo
    function deleteComment(t, cid) {
      const c = (t.comments || []).find((x) => x.id === cid);
      if (!c) return { error: 'That comment is no longer here' };
      if (c.authorId !== meId && !isAdm(me())) return { error: 'Only its writer can delete it' };
      const group = t.comments.filter((x) => x.id === cid || x.parentId === cid);
      const ids = new Set(group.map((x) => x.id));
      t.comments = t.comments.filter((x) => !ids.has(x.id));
      db.trash = db.trash || [];
      const item = { id: 'tr-' + newId(), type: 'comment', deletedAt: nowISO(), deletedBy: meId, key: 'tasks:' + t.id, taskTitle: t.title, data: { taskId: t.id, comments: group } };
      db.trash.push(item);
      t.updatedAt = nowISO();
      return { messages: ['Comment deleted'], undo: item.id };
    }
    function toggleReaction(t, cid, emoji) {
      const c = (t.comments || []).find((x) => x.id === cid);
      if (!c) return { error: 'That comment is no longer here' };
      if (!['👍', '✅', '🎉', '❤️', '👀', '🙏'].includes(emoji)) return { error: 'Not a reaction' };
      // (app.js toggleReaction: on or off)
      c.reactions = c.reactions || {};
      c.reactions[emoji] = c.reactions[emoji] ? 0 : 1;
      if (!c.reactions[emoji]) delete c.reactions[emoji];
      t.updatedAt = nowISO();
      return [];
    }
    // ---------- the description, edited on the phone (HTML the app built: only these tags are kept) ----------
    function cleanHtml(h) {
      return String(h || '').slice(0, 40000).replace(/<[^>]*>/g, (tag) => {
        const m = /^<\s*(\/)?\s*([a-z0-9]+)([^>]*)>$/i.exec(tag);
        if (!m) return '';
        const close = m[1] ? '/' : '', name = m[2].toLowerCase(), attrs = m[3] || '';
        if (['b', 'i', 'u', 's', 'br', 'p', 'ul', 'ol', 'li', 'div'].includes(name)) return `<${close}${name}>`;
        if (name === 'a') { if (close) return '</a>'; const h = /href="(https?:\/\/[^"]+)"/i.exec(attrs); return h ? `<a href="${h[1].replace(/"/g, '')}" target="_blank" rel="noopener">` : '<a>'; }
        if (name === 'span') {
          if (close) return '</span>';
          // (a pasted file's chip, as the website writes it, kept)
          const fp = /data-fpath="([^"]+)"/i.exec(attrs);
          if (fp) { const at = (k) => { const x = new RegExp(k + '="([^"]*)"', 'i').exec(attrs); return x ? x[1].replace(/"/g, '') : ''; };
            return `<span class="fileref" contenteditable="false" data-fpath="${fp[1].replace(/"/g, '')}" data-fname="${at('data-fname')}" data-fsize="${at('data-fsize')}"${at('data-fthumb') ? ` data-fthumb="${at('data-fthumb')}"` : ''}>`; }
          const u = /data-user="([^"]+)"/i.exec(attrs); return u && userById(u[1]) ? `<span class="mention" data-user="${esc(u[1])}" contenteditable="false">` : '<span>';
        }
        return '';
      });
    }
    // keepFiles (the iPhone app, which writes the words only): the files pasted into it stay — the ones it had, at the end
    function setDesc(t, html, text, keepFiles) {
      let clean = cleanHtml(html);
      const plain = String(text == null ? '' : text).slice(0, 20000);
      if (keepFiles) {
        const had = new Set(fileRefsOf(clean).map((f) => f.path));
        const keep = [];
        String(t.notesHtml || '').replace(/<span[^>]*data-fpath="([^"]+)"[^>]*>[\s\S]*?<\/span>/gi, (whole, p) => { if (!had.has(unent(p))) { had.add(unent(p)); keep.push(whole); } return whole; });
        if (keep.length) clean = cleanHtml(clean + '<p>' + keep.join(' ') + '</p>');
      }
      if (clean === (t.notesHtml || '') && plain === (t.notes || '')) return [];
      const before = mentionsIn(t.notesHtml);
      t.notesHtml = clean; t.notes = plain;
      logActivity(t, 'changed the <b>description</b>');
      mentionsIn(t.notesHtml).forEach((x) => { if (!before.has(x)) pushNotif(x, t, 'mention', 'mentioned you in the description of', { snippet: trunc(t.notes, 160) }); });
      t.updatedAt = nowISO();
      return [];
    }
    // the people who can be @mentioned (everyone active, not Finance-only)
    const mentionable = () => users.filter((x) => x.active !== false && !isFinUser(x)).map((x) => ({ id: x.id, name: fullName(x), initials: initials(fullName(x) || '?'), color: rgbOf(avColor(x.id)) }));
    // ---------- Submit for CD review / Withdraw (app.js submitReview / withdrawReview) ----------
    const secNamedOf = (t, re) => (statusList(t) || []).find((x) => re.test(String(x.name).trim()));
    function submitReview(t, files) {
      if (!(needsCD(t) && isMine(t) && !isCD(meId))) return { error: 'This task doesn’t need your files for CD review' };
      if (t.done || (sectionOf(t) && isToDoName(sectionOf(t).name))) return { error: 'Move the task to In Progress first' };
      const list = (files || []).filter((f) => f && f.path && String(f.path).startsWith(`attachments/${t.id}/`)).slice(0, 30);
      if (!list.length) return { error: 'No files' };
      t.reviews = t.reviews || []; t.attachments = t.attachments || [];
      const round = t.reviews.filter((r) => r.by === meId && r.state !== 'withdrawn').length + 1;
      const r = { id: newId(), by: meId, at: nowISO(), files: [], state: 'pending', epoch: epochOf(t), round };
      const atts = list.map((f) => ({ id: newId(), name: String(f.name || 'File').slice(0, 200), size: Number(f.size) || 0, path: String(f.path), type: String(f.type || ''), w: Number(f.w) || undefined, h: Number(f.h) || undefined, addedAt: nowISO(), addedBy: meId, reviewId: r.id }));
      r.files = atts.map((a) => a.id);
      t.reviews.push(r);
      if (!t.lockedAt) t.lockedAt = r.at;
      atts.forEach((a) => t.attachments.push(a));
      logActivity(t, `submitted ${atts.length === 1 ? `<b>${esc(atts[0].name)}</b>` : `<b>${atts.length} files</b>`} for CD review${round > 1 ? ` (round ${round})` : ''}`);
      const cd = cdUserId();
      if (cd) pushNotif(cd, t, 'review', `submitted ${atts.length === 1 ? '1 file' : atts.length + ' files'} for your review on`);
      const rv = secNamedOf(t, SEC_REVIEW); if (rv && t.sectionId !== rv.id) moveToStatus(t, rv.id, true);
      syncCDOf(t);
      t.updatedAt = nowISO();
      return { messages: [cd ? `Sent to ${firstName(cd)} for review` : 'Submitted — no Creative Director is set yet'] };
    }
    function withdrawReview(t) {
      const r = lastReview(t, meId);
      if (!r || r.state !== 'pending') return { error: 'Nothing to withdraw' };
      r.state = 'withdrawn';
      t.attachments = (t.attachments || []).filter((a) => a.reviewId !== r.id);
      logActivity(t, 'withdrew their submission for CD review');
      const cd = cdUserId();
      if (cd) pushNotif(cd, t, 'review-wd', 'withdrew their submission for');
      if (!reviewPending(t)) { const pg = secNamedOf(t, /^in ?-?progress$/i); if (pg && t.sectionId !== pg.id) moveToStatus(t, pg.id, true); }
      syncCDOf(t);
      t.updatedAt = nowISO();
      return { messages: ['Submission withdrawn'] };
    }
    // ---------- writing a comment from the phone (step 3; app.js postComment / saveEdit) ----------
    // a file already on a task this person can see (a task's own or a comment's) — pasted after Copy, as the website's
    // file references: the same file, no second copy (it stays while anything still uses it)
    function knownFile(path) {
      for (const x of db.tasks || []) for (const a of (x.attachments || []).concat(...(x.comments || []).map((c) => c.attachments || []))) if (a && a.path === path) return a;
      return null;
    }
    function postComment(t, parentId, html, text, files) {
      const clean = cleanHtml(html), plain = String(text || '').trim().slice(0, 20000);
      const list = (files || []).filter((f) => f && f.path && (String(f.path).startsWith(`attachments/${t.id}/`) || knownFile(String(f.path)))).slice(0, 30)
        .map((f) => { const k = String(f.path).startsWith(`attachments/${t.id}/`) ? null : knownFile(String(f.path));
          return { id: newId(), name: String(f.name || (k && k.name) || 'File').slice(0, 200), size: Number(f.size) || (k && k.size) || 0, path: String(f.path), type: String(f.type || (k && k.type) || ''), ...(k && k.thumb ? { thumb: k.thumb } : {}), ...(f.voice ? { voice: true, dur: Math.max(0, Math.round(Number(f.dur) || 0)) } : {}), addedAt: nowISO(), addedBy: meId }; });
      if (!plain && !list.length) return { error: 'Nothing to send' };
      if (parentId) { const p = (t.comments || []).find((c) => c.id === parentId); if (!p || p.parentId) return { error: 'That comment is no longer here' }; }
      t.comments = t.comments || [];
      const cid = newId();
      t.comments.push({ id: cid, text: plain, html: clean, at: nowISO(), attachments: list, parentId: parentId || null, reactions: {}, authorId: meId });
      const mentioned = mentionsIn(clean);
      mentioned.forEach((x) => pushNotif(x, t, 'mention', `mentioned you in a ${parentId ? 'reply' : 'comment'} on`, { snippet: trunc(plain, 160), commentId: cid }));
      if (parentId) {
        const ppl = new Set(t.comments.filter((c) => c.id === parentId || c.parentId === parentId).map((c) => c.authorId));
        ppl.forEach((x) => { if (!mentioned.has(x) && !watchersOf(t).includes(x)) pushNotif(x, t, 'comment', 'replied in a thread on', { snippet: trunc(plain, 160), commentId: cid }); });
      }
      const voice = list.some((f) => f.voice);
      notifyWatchers(t, 'comment', parentId ? 'replied to a comment on' : 'commented on', { snippet: trunc(plain || (voice ? 'Voice message' : `${list.length} file${list.length === 1 ? '' : 's'}`), 160), skip: [...mentioned], commentId: cid });
      t.updatedAt = nowISO();
      return { messages: [], id: cid };
    }
    function editComment(t, cid, html, text) {
      const c = (t.comments || []).find((x) => x.id === cid);
      if (!c) return { error: 'That comment is no longer here' };
      if (c.authorId !== meId) return { error: 'Only its writer can edit it' };
      if (nowMs() - Date.parse(c.at || 0) > 10 * 60000 + 60000) return { error: 'The 10 minutes to edit it have passed' };
      const clean = cleanHtml(html), plain = String(text || '').trim();
      if (!plain && !(c.attachments || []).length) return { error: 'Nothing left — delete it instead' };
      const before = mentionsIn(c.html);
      mentionsIn(clean).forEach((x) => { if (!before.has(x)) pushNotif(x, t, 'mention', 'mentioned you in a comment on', { snippet: trunc(plain, 160), commentId: c.id }); });
      c.text = plain; c.html = clean; c.editedAt = nowISO();
      t.updatedAt = nowISO();
      return [];
    }
    // files attached on the phone (app.js attachFiles): on the task, logged, the people on it told
    function attachFilesTo(t, files) {
      // (a file of another task's, or from Client Assets, that this person can already see — pasted into the description:
      //  added here too, the same file, nothing copied; Haris 2026-11-02 — as a comment does)
      const have = new Set((t.attachments || []).map((a) => a.path));
      const list = (files || []).filter((f) => f && f.path && !have.has(String(f.path)) && (String(f.path).startsWith(`attachments/${t.id}/`) || knownFile(String(f.path)))).slice(0, 30)
        .map((f) => { const k = String(f.path).startsWith(`attachments/${t.id}/`) ? null : knownFile(String(f.path));
          return { id: newId(), name: String(f.name || (k && k.name) || 'File').slice(0, 200), size: Number(f.size) || (k && k.size) || 0, path: String(f.path), type: String(f.type || (k && k.type) || ''), ...(k && k.thumb ? { thumb: k.thumb } : {}), addedAt: nowISO(), addedBy: meId }; });
      if (!list.length) return { error: 'No files' };
      t.attachments = (t.attachments || []).concat(list);
      const what = list.length === 1 ? `<b>${esc(list[0].name)}</b>` : list.length + ' files';
      logActivity(t, `attached ${what}`);
      notifyWatchers(t, 'attach', `attached ${what}`);
      t.updatedAt = nowISO();
      return { messages: [list.length === 1 ? 'File attached' : `${list.length} files attached`] };
    }
    // ---------- the native task page's changes (POST /api/task/act) → messages, or { error } / { need } ----------
    function setTitle(t, v) {
      v = String(v == null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, 300);
      if (v === (t.title || '')) return [];
      logChange(t, 'the <b>title</b>', t.title || '', v);
      t.title = v; t.updatedAt = nowISO();
      return [];
    }
    function setStart(t, v) {
      const o = t.start; t.start = v || null;
      if (o === t.start) return [];
      logChange(t, 'the <b>start date</b>', fmtDay(o), fmtDay(t.start)); t.updatedAt = nowISO();
      return [];
    }
    // the status (app.js changeStatus): cdAgain 'yes' | 'no' answers "Does this need CD review again?" when it goes back
    function setStatus(t, sectionId, cdAgain) {
      const list = statusList(t) || [];
      if (!list.some((x) => x.id === sectionId)) return { error: 'That status is no longer here' };
      if (t.sectionId === sectionId && !t.done) return { messages: [] };
      if (statusLocked(t)) return { error: 'The status is locked while files are with the CD for review' };
      if (!t.parentId && needsCD(t) && !cdOK(t) && pastReview(t, sectionId)) return { error: 'Waiting for CD approval' };
      const from = list.findIndex((x) => x.id === t.sectionId), to = list.findIndex((x) => x.id === sectionId);
      const fromS = list[from], toS = list[to];
      const back = !t.parentId && fromS && toS && to < from && (SEC_CTR.test(fromS.name.trim()) || isDoneName(fromS.name)) && !(SEC_CTR.test(toS.name.trim()) || isDoneName(toS.name));
      if (back) {
        const u = me();
        if (!((u && (isAdm(u) || u.role === 'am')) || t.createdBy === meId)) return { error: 'Only an Account Manager or the task’s creator can send it back' };
        const cdOnIt = t.cdRule && cdUserId() && (t.assignees || []).includes(cdUserId());
        const ans = cdOnIt ? 'no' : cdAgain;
        if (ans !== 'yes' && ans !== 'no') return { need: 'cdAgain' };
        t.partsDone = {};
        if (ans === 'yes') {
          t.needsCD = true; t.reviewEpoch = epochOf(t) + 1;
          if (t.cdStatus) logChange(t, 'the <b>CD Status</b>', CD[t.cdStatus] ? CD[t.cdStatus].label : '', '');
          t.cdStatus = '';
          logActivity(t, 'sent it back for changes — <b>needs CD review again</b>');
        } else { t.needsCD = false; logActivity(t, 'sent it back for changes — <b>no CD review needed</b>'); }
      }
      const out = t.done ? setDone(t, false) : [];
      moveToStatus(t, sectionId);
      return { messages: out };
    }
    function setMyPart(t, done) {
      if (!isMine(t)) return { error: 'This isn’t your task' };
      if (iReview(t)) return { error: 'Your part is done when the CD approves your files' };
      t.partsDone = t.partsDone || {};
      if (!!t.partsDone[meId] === !!done) return { messages: [] };
      if (done) {
        t.partsDone[meId] = nowISO();
        const all = (t.assignees || []).length > 0 && t.assignees.every((x) => partDone(t, x));
        const lead2 = [...new Set([creatorOf(t)].concat(clientAmsOf(t)).filter(Boolean))];
        logActivity(t, all ? 'finished their part — <b>all parts are done</b>, ready for review' : 'finished their part');
        notifyWatchers(t, 'part', 'finished their part of', { skip: all ? lead2 : [] });
        if (all) lead2.forEach((x) => pushNotif(x, t, 'allparts', 'marked the last part done — all parts are done, ready for review:'));
        t.updatedAt = nowISO();
        return { messages: ['Your part is done'] };
      }
      delete t.partsDone[meId];
      logActivity(t, 'reopened their part');
      t.updatedAt = nowISO();
      return { messages: checkPrioConflict(t) };
    }
    function setPrio(t, key, k) {
      t.prio = t.prio || {};
      k = normPrio(k);
      const cur = normPrio(t.prio[key]);
      if (cur === k) return [];
      if (typeof k === 'number' && prioTakenBy(k, dayKey(t), key, t.id)) return { error: `Priority ${k} is already used that day` };
      const who = prioOwnerName(key);
      logChange(t, who ? `<b>${esc(who)}</b>’s <b>priority</b>` : 'the <b>priority</b>', prioLabel(cur), prioLabel(k));
      if (k === 'none') delete t.prio[key]; else t.prio[key] = k;
      if (who) {
        pushNotif(key, t, 'priority', `set your priority to <b>${esc(prioLabel(k))}</b> on`);
        notifyWatchers(t, 'priority', `changed <b>${esc(who)}</b>’s priority to <b>${esc(prioLabel(k))}</b> on`, { skip: [key] });
      } else notifyWatchers(t, 'priority', `changed the priority to <b>${esc(prioLabel(k))}</b> on`);
      t.updatedAt = nowISO();
      return [];
    }
    // which numbers are taken that day (the priority sheet greys them)
    const prioTaken = (t, key) => { const out = []; for (let n = 1; n <= 10; n++) if (prioTakenBy(n, dayKey(t), key, t.id)) out.push(n); return out; };
    function toggleCheck(t, cid) {
      const c = (t.checklist || []).find((x) => x.id === cid);
      if (!c) return { error: 'That item is no longer here' };
      c.done = !c.done;
      logActivity(t, `${c.done ? 'checked' : 'unchecked'} <b>${esc(c.text)}</b>`);
      t.updatedAt = nowISO();
      return [];
    }
    function setNeedsCD(t, on) {
      const u = me();
      if (!(u && (isAdm(u) || u.role === 'am' || isCD(meId)))) return { error: 'Your role doesn’t allow this' };
      if (on && t.cdRule && cdUserId() && (t.assignees || []).includes(cdUserId())) return { error: 'The CD is assigned, so no CD review is needed' };
      if (reviewPending(t)) return { error: 'Files are with the CD — change this after they decide' };
      if (!!t.needsCD === !!on) return [];
      t.needsCD = !!on;
      logActivity(t, on ? 'turned on <b>CD review</b> for this task' : 'turned off <b>CD review</b> for this task');
      if (on) {   // (app.js syncCD)
        const rv = reviewersOf(t);
        if (rv.length) {
          const st = rv.map((x) => reviewState(t, x)), prev = t.cdStatus || '';
          t.cdStatus = st.includes('pending') ? 'review' : st.every((x) => x === 'approved') ? 'approved' : '';
          if (prev !== t.cdStatus) { if (prev && t.cdStatus) logChange(t, 'the <b>CD Status</b>', CD[prev].label, CD[t.cdStatus].label); else if (t.cdStatus) logActivity(t, `CD Status is now <b>${esc(CD[t.cdStatus].label)}</b>`); }
        }
      }
      t.updatedAt = nowISO();
      return [];
    }
    function setFinance(t, v) {
      v = v || null;
      if (v && !FINANCE[v]) return { error: 'Not a Finance status' };
      const old = t.finance || null;
      if (old === v) return [];
      t.finance = v; t.financeAt = nowISO(); t.financeBy = meId;
      logChange(t, 'the <b>Finance</b> status', old, v);
      t.updatedAt = nowISO();
      return [];
    }
    function setUpdate(t, v) {
      const old = t.update || null; v = v || null;
      if (old === v) return [];
      if (v && !UPDATES.includes(v)) return { error: 'Not a Task Update' };
      t.update = v;
      logChange(t, 'the <b>Task Update</b>', old, v);
      const to = new Set(watchersOf(t)); if (t.guardian) to.add(t.guardian);
      to.forEach((x) => pushNotif(x, t, 'update', v ? `set the Task Update to <b>${esc(v)}</b> on` : 'cleared the Task Update on'));
      t.updatedAt = nowISO();
      return [];
    }

    // ---------- the app's Clients tab (iPhone, Part B — Haris 2026-11-02): the list, and a client's page ----------
    // who sees which client: as the website's phone list (amSidebarOk): Production / Freelancers the clients they work on,
    // an Account Manager theirs (while not on leave), everyone else all; inactive ones apart
    const clientSeen = (p, u = me()) => {
      if (!u) return false;
      if (ownSearchOnly(u) && !tasks.some((t) => t.projectId === p.id && partOfTask(t, u.id, false)) && !(u.role === 'freelancer' && (u.projectIds || []).includes(p.id))) return false;
      return u.role !== 'am' || isAdm(u) || isCD(u.id) || !projects.some((x) => (x.ams || []).some((a) => a.id === u.id)) || (p.ams || []).some((a) => a.id === u.id && !a.onLeave);
    };
    const byOrderP = (a, b) => (a.order || 0) - (b.order || 0);
    const clientRec = (p) => (p && p.clientId ? (db.clients || []).find((c) => c.id === p.clientId) || null : null);
    const peopleOf = (ids) => Object.fromEntries([...ids].map((id) => { const p = userById(id); return [id, { initials: initials(fullName(p)), color: rgbOf(avColor(id || 'x')), photo: p && p.avatar ? p.avatar : null }]; }));
    function clientRow(p) {
      const open = tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done);
      const late = open.filter((t) => t.due && dayDiff(t.due) < 0).length;
      const c = clientRec(p);
      const ams = (p.ams || []).filter((a) => !a.onLeave).map((a) => a.id).filter((id) => userById(id)).slice(0, 3);
      // (the long press's sheet: every Account Manager with "on leave", the Social Executives, the colour)
      const amsAll = (p.ams || []).filter((a) => userById(a.id)).map((a) => ({ id: a.id, onLeave: !!a.onLeave }));
      const socials = (p.socials || []).filter((id) => userById(id));
      return { id: p.id, name: p.name || 'Client', ini: initials(p.name), rgb: rgbOf(p.color), color: p.color || '', logo: c && c.logo ? c.logo : null, open: open.length, late, ams, amsAll, socials };
    }
    function clientsList() {
      const u = me();
      if (!u || isOffice(u) || isFinUser(u)) return null;
      const seen = projects.filter((p) => clientSeen(p, u)).sort(byOrderP);
      const rows = seen.filter((p) => !p.inactive).map(clientRow), inactive = seen.filter((p) => p.inactive).map(clientRow);
      const ppl = new Set([meId]); rows.concat(inactive).forEach((r) => { r.amsAll.forEach((a) => ppl.add(a.id)); r.socials.forEach((id) => ppl.add(id)); });
      // (Admins change a client from the list's long press — everyone else sees it read only; Haris 2026-11-02)
      const canEdit = isAdm(u) && !isOffice(u);
      const pool = (role) => users.filter((x) => x.active !== false && x.role === role).sort((a, b) => fullName(a).localeCompare(fullName(b))).map((x) => x.id);
      const amPool = canEdit ? pool('am') : [], sePool = canEdit ? pool('social') : [];
      amPool.concat(sePool).forEach((id) => ppl.add(id));
      const names = Object.fromEntries([...ppl].map((id) => [id, fullName(userById(id))]));
      const nOpen = rows.reduce((n, r) => n + r.open, 0);
      return { show: true, kind: 'clients', title: 'Clients', date: `${rows.length} client${rows.length === 1 ? '' : 's'} · ${nOpen} open task${nOpen === 1 ? '' : 's'}`, me: meId, rows, inactive, people: peopleOf(ppl),
        canEdit, amPool, sePool, smIds: socialMgrIds(), names };
    }
    // a client's page: its Client Assets folders on top, then its tasks by status (open ones, or all with showDone) —
    // the same cards as Home (Haris: "the task cards will be consistent")
    const FOLDER_RGB = ['#0a84ff', '#af52de', '#ff9f0a', '#34c759', '#30b0c7', '#ff375f', '#5e5ce6'];
    function clientPage(pid, showDone) {
      const u = me();
      const p = proj(pid);
      if (!u || !p || !clientSeen(p, u)) return null;
      const c = clientRec(p);
      const count = (f, all) => (f.files || []).length + all.filter((x) => x.parentId === f.id).reduce((n, x) => n + count(x, all), 0);
      const fl = c ? (c.folders || []) : [];
      const folders = fl.filter((f) => !f.parentId).map((f, i) => ({ id: f.id, name: f.name || 'Folder', files: count(f, fl), rgb: rgbOf(FOLDER_RGB[i % FOLDER_RGB.length]) }));
      let open = 0;
      const groups = (p.sections || []).map((s) => {
        const all = tasks.filter((t) => t.projectId === p.id && t.sectionId === s.id && !t.parentId).sort((a, b) => (isUrgent(b) ? 1 : 0) - (isUrgent(a) ? 1 : 0) || byOrderP(a, b));
        const ts = showDone ? all : all.filter((t) => !t.done);
        open += all.filter((t) => !t.done).length;
        return ts.length ? { name: s.name, dot: rgbOf(s.color), n: ts.length, empty: '', cards: ts.map((t) => cardOf(t, { status: false })) } : null;
      }).filter(Boolean);
      if (!groups.length) groups.push({ name: 'Tasks', n: 0, empty: showDone ? 'No tasks yet.' : 'No open tasks — tap Show completed to see the done ones.', cards: [] });
      peopleOn.add(meId);
      return {
        show: true, kind: 'client', id: p.id, title: p.name || 'Client', date: `${open} open task${open === 1 ? '' : 's'}`, me: meId, rgb: rgbOf(p.color), ini: initials(p.name),
        logo: c && c.logo ? c.logo : null, assets: c ? { id: c.id, name: c.name, folders } : null, showDone: !!showDone, open, groups,
        add: can('createTask'), canDelete: can('deleteTask'), people: peopleOf(peopleOn),
      };
    }

    return { peopleLocked, home, myTasks, myTasksFilters, inbox, inboxRow, clientsList, clientPage, setFinance, canFinance, myDayData, cardOf, can, amReadOnly, canComplete, completeBlocked, dayTitle, statusInfo, sectionOf,
      notifGroups: NOTIF_GROUPS, doneLocked, canReopen, finish, finishBlocked, canFinish, moveToStatus, logActivity, logChange, pushNotif, notifyWatchers, checkPrioConflict, setDone, setDue, setClientApproval, asksClientApproval, deleteTask, watchersOf, creatorOf, clientAmsOf, fmtDue,
      taskPage, setTitle, setStart, setStatus, setMyPart, setPrio, prioTaken, toggleCheck, setNeedsCD, setUpdate, idLocked,
      setAssignee, setGuardian, addTag, removeTag, setChannels, addCheck, addSubtask, setClient, commentsFeed, toggleReaction, deleteComment, setDesc, submitReview, withdrawReview, postComment, editComment, mentionable, attachFilesTo };
  }

  // (the clock and new ids for the actions: the website's own, or the server's)
  const withEnv = (env, db, meId, today) => { make.env = env; try { return make(db, meId, today); } finally { make.env = null; } };
  return { make, withEnv, NOTIF_GROUPS_OF: (db) => make(db || {}, null, '2000-01-01').notifGroups, home: (db, meId, today) => make(db, meId, today).home(), dubaiDay, rgbOf };
})();
if (typeof module !== 'undefined' && module.exports) module.exports = E11Rules;
