/* The app's own New task form, Home search and My Tasks filters, worked out from a person's data (Part B step 6,
   2026-11-05) — exactly what the page builds for the app today (web/phone.js nativeQuickAdd: the form's args, its client
   and people pickers and the assign row; NativeHome __e11Home 'find': the search model; NativeMyTasks: signal() and the
   filter sheets of app.js workMenu, the chips' ✕, Assigned to me, Clear all), so the iPhone app needs no page for them.
   It only reads; New task itself is done by the server (POST /api/app/act tkNew — server/src/appact-tasks.js).
   R: E11Rules · data: this person's /api/snapshot data · me: their id · nowMs: the clock (a number, or a function).
   "Today" is Dubai's (the page uses the phone's own day).

   The My Tasks filters — the object the app keeps (app.js Work.f(), ui.workF), M.MY_TASKS_DEFAULT:
     { created: null,          // (the website's Created date filter: not on the phone, kept as is)
       due: null,              // 'late' | 'today' | 'week' | null
       finished: false,        // (the website's Finished in the last 7 days: not on the phone, kept as is)
       cd: false,              // Waiting for CD review (set by Home's In review box)
       people: [],             // assignees' ids (People: Account Managers, Admins, the CD)
       ams: [],                // Account Managers whose tasks are shown (Admins and the CD)
       team: false,            // All Account Managers & Admins (Admins and the CD; clears ams)
       assigned: false }       // Assigned to me (the CD)
   The list itself: E11AppView.screen('mytasks', JSON of { tab: 'all' | 'done', due, people: [ids], ams: [ids], team,
   assigned, cd }) — myTasksQuery(filters, tab) gives it.

   Sheets are as appme-people.js's: { sheet: { sections: [{ header?, rows: [{ i, label, sub?, checked?, multi?, find?,
   person? }] }], search?, empty?, multi? }, acts: [...] } (row i → acts[i]). A person: { initials, color: [r,g,b],
   photo?: their picture's file path } (the page's NativeSheet.personFor, before the picture is loaded). */
var E11AppMe = (typeof E11AppMe !== 'undefined' && E11AppMe) || {};
(function (M) {
  'use strict';
  const ROLES = { admin: 'Super Admin', office_admin: 'Office Admin', am: 'Account Manager', production: 'Production', social: 'Social', freelancer: 'Freelancer', finance_admin: 'Finance only · Admin', finance_viewer: 'Finance only · Viewer' };
  const ASSIGNABLE = new Set(['production', 'social', 'freelancer']);
  const COLORS = ['#5b8cff', '#3ddc97', '#ffb547', '#ff6b6b', '#c27cff', '#4fd1c5', '#ff8fc7', '#f2f26d', '#9aa0ab'];
  const AV_COLORS = ['#7b68ee', '#4c9aff', '#3ddc97', '#f9be33', '#ff8a4c', '#e5484d', '#ff8fc7', '#4fd1c5', '#a875ff'];
  const DUE_L = { late: 'Overdue', today: 'Today', week: 'This week' };
  const DEFAULT = { created: null, due: null, finished: false, cd: false, people: [], ams: [], team: false, assigned: false };
  M.MY_TASKS_DEFAULT = DEFAULT;

  const msOf = (nowMs) => (typeof nowMs === 'function' ? nowMs() : nowMs == null ? Date.now() : Number(nowMs));
  // (a middle "Al" is skipped: Yousef Al Hwij → YH, Lana Al Ramli → LR, Al-Ramli too — Haris 2026-11-08)
  const initials = (name) => { const w = String(name || '').trim().split(/\s+/).filter(Boolean); if (w.length > 2 && /^al$/i.test(w[1])) w.splice(1, 1); const two = w.slice(0, 2).map((x, i) => (i > 0 ? x.replace(/^al-(?=.)/i, '') : x)[0] || ''); return two.join('').toUpperCase() || '?'; };
  const avColor = (id) => { let h = 0; for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) >>> 0; return AV_COLORS[h % AV_COLORS.length]; };
  const normPrio = (p) => { if (p === 'urgent' || p === 'high') return 'urgent'; const n = Number(p); return Number.isInteger(n) && n >= 1 && n <= 10 ? n : 'none'; };
  const prioRank = (p) => { p = normPrio(p); return p === 'urgent' ? 0 : p === 'none' ? 99 : p; };
  const mentionsIn = (html) => { const out = new Set(); String(html || '').replace(/data-user="([^"]+)"/g, (_, id) => { out.add(id); return ''; }); return out; };
  // app.js notifPlainHTML (the browser's textContent), without a DOM
  const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '–', mdash: '—', hellip: '…', lsquo: '‘', rsquo: '’', ldquo: '“', rdquo: '”', bull: '•', middot: '·', copy: '©', reg: '®', trade: '™', times: '×', euro: '€', pound: '£' };
  const decode = (s) => s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') { const n = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10); try { return String.fromCodePoint(n); } catch (x) { return m; } }
    return Object.prototype.hasOwnProperty.call(ENT, e) ? ENT[e] : m;
  });
  const plainHTML = (html) => decode(String(html || '').replace(/<(br|\/p|\/li|\/div)>/gi, ' $&').replace(/<!--[\s\S]*?-->/g, '').replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, (m) => m.replace(/<[^>]*>/g, '')).replace(/<\/?[a-z][^>]*>/gi, '')).replace(/\s+/g, ' ').trim();
  // app.js smart search: whole words, starts, parts, then one or two letters off
  const sNorm = (s) => String(s || '').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '').replace(/[’'`]/g, '');
  const sWords = (s) => sNorm(s).split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  function editDist(a, b, max) {
    if (Math.abs(a.length - b.length) > max) return max + 1;
    const prev2 = new Array(b.length + 1), prev = new Array(b.length + 1), cur = new Array(b.length + 1);
    for (let j = 0; j <= b.length; j++) prev[j] = j;
    for (let i = 1; i <= a.length; i++) {
      cur[0] = i; let best = cur[0];
      for (let j = 1; j <= b.length; j++) {
        const cost = a[i - 1] === b[j - 1] ? 0 : 1;
        let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
        if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1);
        cur[j] = v; if (v < best) best = v;
      }
      if (best > max) return max + 1;
      for (let j = 0; j <= b.length; j++) { prev2[j] = prev[j]; prev[j] = cur[j]; }
    }
    return prev[b.length];
  }
  const typoLimit = (w) => (w.length >= 8 ? 2 : w.length >= 4 ? 1 : 0);
  function termMatches(term, vocab) {
    const out = new Map();
    let close = false;
    vocab.forEach((w) => {
      if (w === term) { out.set(w, 1); close = true; } else if (w.startsWith(term)) { out.set(w, 0.85); close = true; } else if (term.length >= 3 && w.includes(term)) { out.set(w, 0.55); close = true; }
    });
    let fuzzy = null;
    if (!close && typoLimit(term)) {
      let bestD = 99;
      vocab.forEach((w) => {
        const lim = typoLimit(term);
        const d = Math.min(editDist(term, w, lim), w.length > term.length ? editDist(term, w.slice(0, term.length), lim) : 99);
        if (d <= lim) { out.set(w, d === 1 ? 0.45 : 0.3); if (d < bestD || (d === bestD && fuzzy && w.length < fuzzy.length)) { bestD = d; fuzzy = w; } }
      });
    }
    return { words: out, fuzzy };
  }

  // ---------- the person's world: app.js's helpers on their data (normalize where it matters) ----------
  function world(R, data, meId, nowMs) {
    data = data || {};
    const now = msOf(nowMs), today = R.dubaiDay(now);
    const meta = data.meta || {};
    const users = (Array.isArray(data.users) ? data.users : []).map((u) => (u.prefs && u.active != null ? u : Object.assign({}, u, { prefs: u.prefs || {}, active: u.active == null ? true : u.active })));
    const firstAdmin = users.length ? (users.find((u) => u.role === 'admin') || users[0]).id : 'u-haris';
    const projects = (Array.isArray(data.projects) ? data.projects : []).map((p, i) => (p.color ? p : Object.assign({}, p, { color: COLORS[i % COLORS.length] })));
    const tasks = (Array.isArray(data.tasks) ? data.tasks : []).map((t) => {
      if (Array.isArray(t.assignees) && t.needsCD != null && t.createdBy) return t;
      const x = Object.assign({}, t);
      if (!Array.isArray(x.assignees)) x.assignees = [firstAdmin];
      if (!x.createdBy) x.createdBy = firstAdmin;
      if (x.needsCD == null) x.needsCD = !x.parentId && !x.done && !!x.projectId && x.cdStatus !== 'approved';
      return x;
    });
    const clients = Array.isArray(data.clients) ? data.clients : [];
    const db = { users, projects, tasks, statuses: data.statuses || [], plans: data.plans || [], meta };
    const r = R.withEnv({ nowISO: () => new Date(msOf(nowMs)).toISOString(), nowMs: () => msOf(nowMs) }, db, meId, today);
    const userById = (id) => users.find((u) => u.id === id) || null;
    const me = () => userById(meId);
    const fullName = (u) => (u ? (u.name || String(u.email || '').split('@')[0]) : 'Former member');
    const proj = (id) => projects.find((p) => p.id === id);
    const task = (id) => tasks.find((t) => t.id === id);
    const isAdm = (u) => !!u && (u.role === 'admin' || u.role === 'office_admin' || u.admin === true);
    const cdUserId = () => { const id = meta.cdUserId; const u = id && userById(id); return u && u.active !== false ? id : null; };
    const isCD = (id = meId) => !!id && id === cdUserId();
    const cdTitle = () => (meta.cdActing && cdUserId() ? 'Acting CD' : 'Creative Director');
    const socialMgrIds = () => (meta.socialMgrIds || []).filter((id) => { const u = userById(id); return u && u.active !== false && u.role === 'social'; });
    const roleOf = (u) => (u && u.id === cdUserId() ? cdTitle() : u && socialMgrIds().includes(u.id) ? 'Social Manager' : (u && (ROLES[u.role] || u.role)) || '');
    const assignable = (u) => !!u && u.active !== false && (ASSIGNABLE.has(u.role) || u.id === cdUserId());
    const activeUsers = () => users.filter((u) => u.active !== false).sort((a, b) => fullName(a).localeCompare(fullName(b)));
    const byOrder = (a, b) => (a.order || 0) - (b.order || 0);
    // (app.js amScope / amClientOk: an AM's rights on their own clients' tasks)
    function amScope(t, u = me()) {
      if (!u || isAdm(u) || u.role !== 'am' || isCD(u.id)) return true;
      if (!t) return true;
      if (!projects.some((p) => (p.ams || []).some((a) => a.id === u.id))) return true;
      const root = t.parentId ? task(t.parentId) || t : t;
      if (root.createdBy === u.id || t.createdBy === u.id) return true;
      const p = root.projectId ? proj(root.projectId) : null;
      return !!p && (p.ams || []).some((a) => a.id === u.id && !a.onLeave);
    }
    const amClientOk = (p) => amScope({ projectId: p.id, createdBy: null });
    const person = (id) => { const u = userById(id); return Object.assign({ initials: initials(fullName(u)), color: R.rgbOf(avColor(id || 'x')) }, u && u.avatar ? { photo: u.avatar } : {}); };
    return { R, r, now, today, meta, users, projects, tasks, clients, meId, userById, me, fullName, proj, task, isAdm, cdUserId, isCD, cdTitle, roleOf, assignable, activeUsers, byOrder, amScope, amClientOk, person };
  }

  // ---------- New task (phone.js quickAdd → nativeQuickAdd) ----------
  // ctx: { view: the page on screen ('home', 'today', 'mytasks', 'project', …), projectId: the client open (view 'project') }
  // → { args: what the page sends NativeForm.open (formSheet), state: { client, who: [ids], mgr, canAssign, project } }
  //   (project: the client the form was opened in — its picker keeps it even when it's inactive); null: can't create
  M.newTaskForm = function (R, data, meId, nowMs, ctx) {
    const W = world(R, data, meId, nowMs), u = W.me();
    if (!u) return null;
    ctx = ctx || {};
    const inProject = ctx.view === 'project' && ctx.projectId && W.proj(ctx.projectId) ? ctx.projectId : '';
    const tctx = inProject ? { projectId: inProject } : null;   // (app.js taskCtx)
    if (!W.r.can('createTask', tctx)) return null;
    const mgr = W.isAdm(u) || u.role === 'am' || W.isCD();
    const canAssign = W.r.can('assign', tctx);
    const state = { client: inProject, who: W.assignable(u) ? [meId] : [], mgr, canAssign, project: inProject };
    const due = ctx.view === 'today' || ctx.view === 'home' || ctx.view === 'mytasks' || ctx.view === 'inbox' ? W.today : '';   // (the Inbox's too — Haris 2026-11-06)
    const args = Object.assign({ kind: 'task', key: 'new-task', title: 'New task', titleHint: 'What needs doing?', descHint: 'Details, links or notes for the team', client: clientName(W, state.client) },
      canAssign ? { assign: whoOf(W, state.who) } : {}, { due }, mgr ? { cd: !!inProject && !!W.cdUserId(), noCD: !W.cdUserId() } : {},
      { button: 'Create task', color: 'blue', dock: 'New task', required: 'title' });
    return { args, state };
  };
  const clientName = (W, id) => (id && W.proj(id) ? W.proj(id).name : 'No client (My Tasks)');
  const nameOf = (W, id) => (id === W.meId ? 'Me' : W.fullName(W.userById(id)));
  function whoOf(W, ids) {
    ids = ids || [];
    if (!ids.length) return { label: 'Nobody yet' };
    const label = ids.length === 1 ? nameOf(W, ids[0]) : ids.length === 2 ? `${nameOf(W, ids[0])}, ${nameOf(W, ids[1])}` : `${nameOf(W, ids[0])} + ${ids.length - 1} others`;
    return { label, person: W.person(ids[0]) };
  }
  // the Assign to row for the form (whoOf): { label, person? }
  M.newTaskWho = function (R, data, meId, nowMs, state) {
    const W = world(R, data, meId, nowMs);
    return whoOf(W, (state && state.who) || []);
  };
  // Client: No client first, a divider, then the clients — acts [{ client: id | '', form: { client: its name, cd? } }]
  // (form: what the page sets on the form — picking a client turns CD review on for managers, No client off)
  M.newTaskClients = function (R, data, meId, nowMs, state) {
    const W = world(R, data, meId, nowMs);
    if (!W.me()) return null;
    state = state || {};
    const cur = state.client || '', inProject = state.project || '';
    const list = W.projects.filter((p) => (!p.inactive && W.amClientOk(p)) || p.id === inProject).sort(W.byOrder);
    const acts = [];
    const act = (id) => { acts.push({ client: id, form: Object.assign({ client: clientName(W, id) }, state.mgr ? { cd: !!id && !!W.cdUserId() } : {}) }); return acts.length - 1; };
    const sections = [{ rows: [{ i: act(''), label: 'No client (My Tasks)', checked: !cur }] }];
    if (list.length) sections.push({ rows: list.map((p) => ({ i: act(p.id), label: p.name, checked: cur === p.id, find: p.name })) });
    const sheet = { sections };
    if (list.length > 7) { sheet.search = 'Search clients'; sheet.empty = 'No client matches “%@”'; }
    return { sheet, acts };
  };
  // Assign to: ticks (the sheet stays open), Me first when you can be assigned, then the groups, Nobody yet last —
  // acts [{ toggle: uid } | { none: true }]; after each, newTaskWho(state) is the row's new look
  M.newTaskPeople = function (R, data, meId, nowMs, state) {
    const W = world(R, data, meId, nowMs), u = W.me();
    if (!u) return null;
    const who = (state && state.who) || [];
    const acts = [], sections = [{ rows: [] }];
    const cur = () => sections[sections.length - 1];
    const row = (x) => { acts.push({ toggle: x.id }); return { i: acts.length - 1, label: x.id === meId ? 'Me' : W.fullName(x), sub: W.roleOf(x), person: W.person(x.id), checked: who.includes(x.id), multi: true, find: `${W.fullName(x)} ${x.email} ${W.roleOf(x)}` }; };
    if (W.assignable(u)) cur().rows.push(row(u));
    // (app.js assignGroups: Production, Social, Freelancers, the CD, Others — each by name)
    const pool = W.activeUsers().filter((x) => x.id !== meId && W.assignable(x));
    const group = (x) => (x.id === W.cdUserId() ? 'cd' : x.role === 'production' || x.role === 'social' || x.role === 'freelancer' ? x.role : 'other');
    [['production', 'Production'], ['social', 'Social'], ['freelancer', 'Freelancers'], ['cd', W.cdTitle()], ['other', 'Others']].forEach(([k, l]) => {
      const us = pool.filter((x) => group(x) === k).sort((a, b) => W.fullName(a).localeCompare(W.fullName(b)));
      if (!us.length) return;
      if (cur().rows.length || cur().header) sections.push({ rows: [] });
      cur().header = l;
      us.forEach((x) => cur().rows.push(row(x)));
    });
    acts.push({ none: true });
    sections.push({ rows: [{ i: acts.length - 1, label: 'Nobody yet', checked: !who.length }] });
    return { sheet: { sections: sections.filter((s) => s.rows.length), search: 'Search people', empty: 'No one matches “%@”', multi: true }, acts };
  };

  // ---------- Home's search (NativeHome 'find': app.js taskSearch(q, { limit: 80 })) ----------
  // → { q, total, clients: [{ id, name, ini, rgb, open }], tasks: [cards as Home's (rules.js cardOf)] }
  const FIELD_LABEL = { project: 'Client', client: 'Client Assets', tag: 'Tag', people: 'Assigned to', status: 'Status', creator: 'Created by', desc: 'Description', check: 'Checklist', sub: 'Subtask', parent: 'Part of' };
  M.search = function (R, data, meId, nowMs, q) {
    const W = world(R, data, meId, nowMs), u = W.me();
    if (!u) return null;
    const qs = String(q || '').trim();
    if (!qs) return { q: q || '', clients: [], tasks: [], total: 0 };
    const terms = sWords(qs);
    if (!terms.length) return { q, total: undefined, clients: [], tasks: [] };   // (taskSearch's own answer: no total)
    const r = W.r;
    const clientOfProject = (p) => (p && p.clientId ? W.clients.find((c) => c.id === p.clientId) || null : null);
    const subtasksOf = (id) => W.tasks.filter((t) => t.parentId === id).sort(W.byOrder);
    const dn = (s) => { const [y, m, d] = String(s).split('-').map(Number); return Date.UTC(y, m - 1, d) / 86400000; };
    const dayDiff = (s) => Math.round(dn(s) - dn(W.today));
    function prioOf(t) {
      const pr = t.prio || {};
      if (pr[meId] != null) return normPrio(pr[meId]);
      if ((t.assignees || []).includes(meId)) return 'none';
      const vals = Object.values(pr).map(normPrio);
      return vals.length ? vals.sort((a, b) => prioRank(a) - prioRank(b))[0] : 'none';
    }
    const isMine = (t) => (t.assignees || []).includes(meId);
    const FLAGS = {
      overdue: (t) => !t.done && t.due && dayDiff(t.due) < 0,
      today: (t) => !t.done && t.due && dayDiff(t.due) === 0,
      tomorrow: (t) => !t.done && t.due && dayDiff(t.due) === 1,
      urgent: (t) => prioOf(t) === 'urgent',
      done: (t) => t.done, completed: (t) => t.done,
      open: (t) => !t.done,
      mine: isMine, me: isMine,
      unassigned: (t) => !(t.assignees || []).length,
      review: (t) => t.cdStatus === 'review', approved: (t) => t.cdStatus === 'approved',
    };
    function partOfTask(t, id, deep = true) {
      if (!t) return false;
      if ((t.assignees || []).includes(id) || t.createdBy === id || t.guardian === id) return true;
      if ((t.comments || []).some((c) => mentionsIn(c.html).has(id)) || mentionsIn(t.notesHtml).has(id)) return true;
      if (!deep) return false;
      return (t.parentId && partOfTask(W.task(t.parentId), id, false)) || subtasksOf(t.id).some((x) => partOfTask(x, id, false));
    }
    const ownSearchOnly = (x) => !!x && ['production', 'freelancer'].includes(x.role) && !W.isAdm(x) && !W.isCD(x.id);
    // (Socials: the tasks they're assigned to and their content-plan tasks — a Social Executive's own, a Social Manager's and
    //  every Social Executive's; clients: a Social Executive's own, a Social Manager every Social Executive's — Haris 2026-11-08; as app.js)
    const isSocialU = (x) => !!x && x.role === 'social' && !W.isAdm(x) && !W.isCD(x.id);
    const smIds = ((W.meta && W.meta.socialMgrIds) || []).filter((id) => { const x = W.userById(id); return x && x.active !== false && x.role === 'social'; });
    const socialPlanTask = (t) => !!t && !t.parentId && !!t.planId && (t.createdBy === u.id || smIds.includes(u.id));
    const searchOwnOk = (t) => (isSocialU(u) ? (t.assignees || []).includes(u.id) || socialPlanTask(t) : !['production', 'freelancer'].includes(u.role) || W.isAdm(u) || W.isCD(u.id) || partOfTask(t, u.id));
    const socialClientOk = (p) => !isSocialU(u) || (smIds.includes(u.id) ? (p.socials || []).some((id) => { const x = W.userById(id); return !!x && x.active !== false && x.role === 'social'; }) : (p.socials || []).includes(u.id));
    const searchClientOk = (p) => !ownSearchOnly(u) || W.tasks.some((t) => t.projectId === p.id && partOfTask(t, u.id, false)) || (u.role === 'freelancer' && (u.projectIds || []).includes(p.id));
    const amSidebarOk = (p) => searchClientOk(p) && (u.role !== 'am' || W.isAdm(u) || W.isCD(u.id) || !W.projects.some((x) => (x.ams || []).some((a) => a.id === u.id)) || (p.ams || []).some((a) => a.id === u.id && !a.onLeave));
    const people = (ids) => (ids || []).map((id) => W.fullName(W.userById(id))).join(' ');
    function taskFields(t) {
      const p = W.proj(t.projectId), cl = p ? clientOfProject(p) : null, sec = r.sectionOf(t);
      const f = [
        { k: 'title', w: 10, text: t.title }, { k: 'project', w: 6, text: p ? p.name : 'My Tasks' }, { k: 'client', w: 5, text: cl ? cl.name : '' },
        { k: 'tag', w: 5, text: (t.tags || []).join(' ') }, { k: 'people', w: 4, text: people(t.assignees) }, { k: 'status', w: 3, text: sec ? sec.name : '' },
        { k: 'creator', w: 2, text: people([t.createdBy]) }, { k: 'desc', w: 2.5, text: t.notesHtml ? plainHTML(t.notesHtml) : t.notes },
        { k: 'check', w: 1.5, text: (t.checklist || []).map((c) => c.text).join(' · ') }, { k: 'sub', w: 2, text: subtasksOf(t.id).map((s) => s.title).join(' · ') },
      ];
      (t.comments || []).forEach((c) => f.push({ k: 'comment', w: 1.2, text: c.text || plainHTML(c.html), who: c.authorId, reply: !!c.parentId }));
      if (t.parentId) { const par = W.task(t.parentId); if (par) f.push({ k: 'parent', w: 3, text: par.title }); }
      return f;
    }
    // (each word's best field kept too: why a task was found — app.js searchWhy; Haris 2026-11-06)
    const docs = W.tasks.filter((t) => !r.amReadOnly(t) && searchOwnOk(t)).map((t) => {
      const words = new Map(), fields = taskFields(t), at = new Map();
      fields.forEach((fl, i) => sWords(fl.text).forEach((w) => { if (!words.has(w) || words.get(w) < fl.w) { words.set(w, fl.w); at.set(w, i); } }));
      Object.keys(FLAGS).forEach((k) => { if (FLAGS[k](t)) { words.set('#' + k, 4); at.set('#' + k, -1); } });
      return { t, words, fields, at };
    });
    const vocab = new Set();
    docs.forEach((d) => d.words.forEach((_, w) => { if (w[0] !== '#') vocab.add(w); }));
    const fixed = [];
    const per = terms.map((term) => {
      const m = termMatches(term, vocab);
      if (m.fuzzy && !m.words.has(term)) fixed.push({ from: term, to: m.fuzzy });
      return { term, words: m.words, flag: FLAGS[term] ? '#' + term : null };
    });
    const found = [];
    docs.forEach((d) => {
      let score = 0; const hits = [];
      for (const pt of per) {
        let best = 0, bestWord = null, bestField = -1;
        if (pt.flag && d.words.has(pt.flag)) { best = 4; bestWord = pt.term; }
        pt.words.forEach((qq, w) => { const e = d.words.get(w); if (e && e * qq > best) { best = e * qq; bestWord = w; bestField = d.at.get(w); } });
        if (!best) return;
        score += best; hits.push({ word: bestWord, field: bestField });
      }
      if (!d.t.done) score += 1.5;
      if (d.t.parentId) score -= 1;
      found.push({ t: d.t, score, hits, fields: d.fields });
    });
    found.sort((a, b) => b.score - a.score || (a.t.done - b.t.done) || String(b.t.updatedAt || '').localeCompare(String(a.t.updatedAt || '')));
    const projs = W.projects.filter((p) => !p.inactive && amSidebarOk(p) && socialClientOk(p)).filter((p) => {
      const ws = new Set(sWords(`${p.name} ${(clientOfProject(p) || {}).name || ''}`));
      return per.every((pt) => [...pt.words.keys()].some((w) => ws.has(w)));
    });
    return {
      q, total: found.length,
      clients: projs.map((p) => ({ id: p.id, name: p.name, ini: initials(p.name), rgb: R.rgbOf(p.color), open: W.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done && (!r.seenTask || r.seenTask(t))).length })),   // (as this person's lists have them)
      tasks: found.slice(0, 80).map((h) => Object.assign(r.cardOf(h.t), whyOf(h) ? { found: whyOf(h) } : {})),
      fixed, marks: [...new Set(terms.concat(fixed.map((f) => f.to)))].slice(0, 12),   // (what was typed, and what a typo was read as — few, so marking stays quick)
    };
    // where the words were found when it isn't the title (app.js searchWhy): { label, text } — a window of the text around
    // the first word, as the website's
    function whyOf(h) {
      const fi = h.hits.map((x) => x.field).filter((i) => i > 0).sort((a, b) => h.fields[b].w - h.fields[a].w)[0];
      if (fi == null) return null;
      const fl = h.fields[fi];
      const ws = h.hits.filter((x) => x.field === fi).map((x) => x.word);
      let text = String(fl.text || '').replace(/\s+/g, ' ');
      const at = Math.max(0, sNorm(text).indexOf(ws[0] || ''));
      if (text.length > 90) { const st = Math.max(0, at - 30); text = (st ? '…' : '') + text.slice(st, st + 90) + (st + 90 < text.length ? '…' : ''); }
      const who = fl.who === meId ? 'you' : String(W.fullName(W.userById(fl.who)) || '').split(' ')[0];
      const label = fl.k === 'comment' ? `${fl.reply ? 'Reply' : 'Comment'} by ${who || 'someone'}` : FIELD_LABEL[fl.k] || '';
      return { label, text };
    }
  };

  // ---------- My Tasks' filters (NativeMyTasks, app.js Work.f / workMenu) ----------
  const fOf = (f) => {
    const x = Object.assign({}, DEFAULT, f || {});
    x.people = Array.isArray(x.people) ? x.people.slice() : [];
    x.ams = Array.isArray(x.ams) ? x.ams.slice() : [];
    return x;
  };
  M.myTasksDefault = () => ({ filters: fOf(null) });
  // what the page sends the app (NativeMyTasks signal(), without `light` — the phone's own theme): { show, tab, q, buttons:
  // [{ k, t, on }], chips: [{ t, act, id? }], me }. q: the server's /api/mytasks query string.
  M.myTasksSignal = function (R, data, meId, nowMs, filters, tab) {
    const W = world(R, data, meId, nowMs);
    if (!W.me()) return null;
    const F = fOf(filters), ok = W.r.myTasksFilters();
    const q = [];
    if (F.due && ['late', 'today', 'week'].includes(F.due)) q.push('due=' + F.due);
    if (ok.includes('people') && F.people.length) q.push('people=' + F.people.join(','));
    if (ok.includes('ams') && F.team) q.push('team=1');
    else if (ok.includes('ams') && F.ams.length) q.push('ams=' + F.ams.join(','));
    if (ok.includes('assigned') && F.assigned) q.push('assigned=1');
    if (F.cd) q.push('cd=1');
    const name = (id) => W.fullName(W.userById(id));
    const chips = [];
    if (F.due && DUE_L[F.due]) chips.push({ t: `Due: ${DUE_L[F.due]}`, act: 'due' });
    if (F.cd) chips.push({ t: 'Waiting for CD review', act: 'cd' });
    if (ok.includes('assigned') && F.assigned) chips.push({ t: 'Assigned to me', act: 'assigned' });
    if (ok.includes('ams') && F.team) chips.push({ t: 'All Account Managers & Admins', act: 'team' });
    if (ok.includes('ams') && !F.team) F.ams.forEach((id) => chips.push({ t: `${name(id)}’s tasks`, act: 'am', id }));
    if (ok.includes('people')) F.people.forEach((id) => chips.push({ t: name(id), act: 'person', id }));
    const L = { due: 'Due date', people: 'People', ams: 'Account managers', assigned: 'Assigned to me' };
    const buttons = ok.map((k) => ({ k, t: L[k], on: k === 'due' ? !!F.due : k === 'people' ? F.people.length > 0 : k === 'ams' ? (F.team || F.ams.length > 0) : !!F.assigned }));
    return { show: true, tab: tab === 'done' ? 'done' : 'all', q: q.join('&'), buttons, chips, me: meId };
  };
  // the list's own question for E11AppView.screen('mytasks', …) / /api/mytasks: { tab, due, people, ams, team, assigned, cd }
  M.myTasksQuery = function (R, data, meId, nowMs, filters, tab) {
    const F = fOf(filters);
    return { tab: tab === 'done' ? 'done' : 'all', due: F.due || null, people: F.people, ams: F.ams, team: !!F.team, assigned: !!F.assigned, cd: !!F.cd };
  };
  // a filter button's sheet (workMenu): 'due' (one choice, tapped again: off), 'people' / 'ams' (ticks, the sheet stays
  // open) — acts [{ set: the whole new filters object }]
  M.myTasksFilterMenu = function (R, data, meId, nowMs, kind, filters) {
    const W = world(R, data, meId, nowMs);
    if (!W.me() || !['due', 'people', 'ams'].includes(kind)) return null;
    const F = fOf(filters), acts = [], sections = [{ rows: [] }];
    const cur = () => sections[sections.length - 1];
    const act = (fn) => { const n = fOf(F); fn(n); acts.push({ set: n }); return acts.length - 1; };
    if (kind === 'due') {
      Object.keys(DUE_L).forEach((k) => cur().rows.push({ i: act((n) => { n.due = F.due === k ? null : k; }), label: DUE_L[k], checked: F.due === k }));
      return { sheet: { sections }, acts };
    }
    const key = kind === 'ams' ? 'ams' : 'people';
    const roles = kind === 'ams' ? [['am', 'Account Managers']] : [['production', 'Production'], ['social', 'Social'], ['freelancer', 'Freelancers']];
    if (kind === 'ams') cur().rows.push({ i: act((n) => { n.team = !F.team; if (n.team) n.ams = []; }), label: 'All Account Managers & Admins', checked: !!F.team });
    roles.forEach(([role, label]) => {
      const us = W.activeUsers().filter((x) => x.role === role && x.id !== meId);
      if (!us.length) return;
      if (cur().rows.length || cur().header) sections.push({ rows: [] });
      cur().header = label;
      us.forEach((x) => cur().rows.push({ i: act((n) => { n[key] = F[key].includes(x.id) ? F[key].filter((y) => y !== x.id) : F[key].concat(x.id); if (key === 'ams') n.team = false; }),
        label: W.fullName(x), person: W.person(x.id), checked: F[key].includes(x.id), multi: true, find: `${W.fullName(x)} ${x.email}` }));
    });
    const out = sections.filter((s) => s.rows.length);
    // (nobody to pick: the page's sheet has only its "Nobody here yet" title — no sections; empty says it)
    return { sheet: Object.assign({ sections: out, multi: true }, out.length ? {} : { empty: 'Nobody here yet' }), acts };
  };
  // a chip's ✕ / Assigned to me / Clear all on the filters: op { chip: { act, id? } } | { assigned: true } | { reset: true }
  // → { filters: the new filters }
  M.myTasksFilters = function (R, data, meId, nowMs, filters, op) {
    const F = fOf(filters);
    op = op || {};
    if (op.reset) return { filters: fOf(null) };
    if (op.assigned) F.assigned = !F.assigned;
    const c = op.chip;
    if (c) {
      if (c.act === 'due') F.due = null; else if (c.act === 'cd') F.cd = false; else if (c.act === 'assigned') F.assigned = false; else if (c.act === 'team') F.team = false;
      else if (c.act === 'am') F.ams = F.ams.filter((x) => x !== c.id); else if (c.act === 'person') F.people = F.people.filter((x) => x !== c.id);
    }
    return { filters: F };
  };

  // ---------- Opening an update: a notification tapped, an Inbox row (Part B step 7) ----------
  // app.js openNotif(id) and phone.js openFrom(taskId, nid, hint) / TaskLink.open(id), worked out without the page.
  // notifOpen(nid, hint) → { read: [ids], go, wait? }
  //   read: this person's unread notifications that openNotif marks read (the app sends them to /api/home/act readList)
  //   go: null (nothing happens) or one of
  //     { to: 'task', id, tab: 'details' | 'comments', focus: commentId | '', thread?: the comment's thread, desc?: true }
  //        (desc: an @mention in the description — the website opens it; the page's native task page shows Details)
  //     { to: 'review', id: reviewId | null, tab: 'active' | 'reviewed' | null }   (the CD; null tab: as it was)
  //     { to: 'plan', id } · { to: 'assets', client, folder | null } · { to: 'daily' } · { to: 'birthday', person, title }
  //        (person: { id, name, ini, color, photo } — whose birthday; title: "<first name>’s birthday")
  //     { to: 'schedCancel', id: schedId }
  //     { to: 'claim', page: 'fin-reimb' | 'claims', claimId | null, month? }   (Claims.openNotif; on the phone the page
  //        itself only says "Claims are on the computer")
  //     { to: 'trash', q, toast }   (a manager: the Trash, searched for the task)
  //     { toast, home?: true }      (home: an Office Admin — Home, unless a Finance page is showing)
  //   wait: the notification isn't in the copy yet — go is where openFrom goes meanwhile; ask again when it arrives
  // hint: the push's own { taskId, kind, commentId, clientId, folderId, planId }
  const notifKeyOf = (n) => (n.kind === 'sched-cancel' ? 'sched:' + n.schedId : n.kind === 'daily' ? 'daily:' + n.id : null) || n.taskId || (n.kind === 'birthday' ? 'bday:' + n.from + ':' + String(n.at).slice(0, 10) : n.kind === 'asset' ? 'asset:' + n.clientId : n.planId ? 'plan:' + n.planId : n.id);
  M.notifKey = notifKeyOf;
  function opener(W, data) {
    const u = W.me();
    const isOffice = (x = u) => !!x && x.role === 'office_admin' && x.admin !== true;
    const isFinUser = (x = u) => !!x && (x.role === 'finance_admin' || x.role === 'finance_viewer');
    const finLevel = (x = u) => (!x ? null : x.role === 'finance_admin' ? 'admin' : x.role === 'finance_viewer' ? 'viewer' : x.fin === 'admin' || x.fin === 'viewer' ? x.fin : null);
    const isManager = (x = u) => !!x && (W.isAdm(x) || x.role === 'am');
    const tasks = Array.isArray(data.tasks) ? data.tasks : [];
    const task = (id) => tasks.find((t) => t.id === id);
    const notifs = Array.isArray(data.notifications) ? data.notifications : [];
    const myNotifs = () => notifs.filter((n) => n.to === W.meId);
    const plans = Array.isArray(data.plans) ? data.plans : [];
    const planById = (id) => plans.find((p) => p.id === id) || null;
    const canSeePlans = (x = u) => !!x && x.active !== false && !isFinUser(x) && !isOffice(x) && (W.isAdm(x) || x.role === 'am' || x.role === 'social' || W.isCD(x.id));
    const clientById = (id) => W.clients.find((c) => c.id === id) || null;
    // (app.js partOfTask / searchClientOk / amSidebarOk / caVisible)
    const partOfTask = (t, id) => !!t && ((t.assignees || []).includes(id) || t.createdBy === id || t.guardian === id || (t.comments || []).some((c) => mentionsIn(c.html).has(id)) || mentionsIn(t.notesHtml).has(id));
    const ownSearchOnly = (x = u) => !!x && ['production', 'freelancer'].includes(x.role) && !W.isAdm(x) && !W.isCD(x.id);
    const searchClientOk = (p) => !ownSearchOnly(u) || tasks.some((t) => t.projectId === p.id && partOfTask(t, u.id)) || (u.role === 'freelancer' && (u.projectIds || []).includes(p.id));
    const amSidebarOk = (p) => searchClientOk(p) && (!u || u.role !== 'am' || W.isAdm(u) || W.isCD(u.id) || !W.projects.some((x) => (x.ams || []).some((a) => a.id === u.id)) || (p.ams || []).some((a) => a.id === u.id && !a.onLeave));
    const caVisible = (c) => { const linked = W.projects.filter((p) => p.clientId === c.id); return !linked.length || linked.some((p) => amSidebarOk(p)); };
    // openClient(id, folder)
    const assets = (cid, fid) => {
      const c = clientById(cid);
      if (!c) return { toast: 'That client has been removed' };
      if (!caVisible(c)) return { toast: 'Not shared with you' };
      return { to: 'assets', client: c.id, folder: (c.folders || []).some((x) => x.id === fid) ? fid : null };
    };
    // Claims.openNotif(n) (as off the phone)
    const claimMonth = () => { const d = W.today; if (Number(d.slice(8, 10)) < 28) return d.slice(0, 7); const [y, m] = d.slice(0, 7).split('-').map(Number); const n = new Date(Date.UTC(y, m, 1)); return n.toISOString().slice(0, 7); };
    const claim = (n) => (n.kind === 'claim' ? (finLevel() ? { to: 'claim', page: 'fin-reimb', claimId: n.claimId || null, month: n.month || claimMonth() } : null) : { to: 'claim', page: 'claims', claimId: n.claimId || null });
    // openTask(id): an Office Admin has no task pages
    const openTask = (id, tab, extra) => (isOffice() ? { toast: 'Not in the Office Admin view', home: true } : Object.assign({ to: 'task', id, tab: tab || 'details', focus: '' }, extra || {}));
    const trashTitle = (it) => {
      const d = it.data || {};
      if (it.type === 'task') return (d.tasks && (d.tasks.find((t) => !t.parentId || !d.tasks.some((x) => x.id === t.parentId)) || d.tasks[0]) || {}).title || 'Untitled task';
      return d.project ? d.project.name : 'Client';
    };
    return { u, isOffice, finLevel, isManager, task, notifs, myNotifs, planById, canSeePlans, assets, claim, openTask, trashTitle, ownSearchOnly };
  }
  M.notifOpen = function (R, data, meId, nowMs, nid, hint) {
    const W = world(R, data, meId, nowMs);
    if (!W.me()) return null;
    data = data || {};
    const O = opener(W, data);
    hint = hint || {};
    const n = nid ? O.notifs.find((x) => x.id === nid) : null;
    // ---- not in the copy (yet): phone.js openFrom ----
    if (!n) {
      const taskId = hint.taskId || null;
      if (taskId && !nid) return { read: [], go: M.taskLinkOpen(R, data, meId, nowMs, taskId).go };
      const k = hint.kind || '';
      let go = null;
      if ((k === 'review' || k === 'review-wd') && W.isCD()) go = { to: 'review', id: null, tab: null };
      else if (k === 'asset' && hint.clientId && W.clients.some((c) => c.id === hint.clientId)) go = O.assets(hint.clientId, hint.folderId);
      else if (/^claim/.test(k)) go = O.claim({ kind: k });
      else if (k === 'daily') go = { to: 'daily' };   // (the round-up is worked out afresh: it needn't wait for the update)
      else if (/^plan/.test(k) && hint.planId && O.planById(hint.planId)) go = { to: 'plan', id: hint.planId };
      else if (taskId && O.task(taskId)) go = O.openTask(taskId, ['comment', 'mention', 'review-amend'].includes(hint.kind) && hint.commentId ? 'comments' : 'details');
      return Object.assign({ read: [], go }, nid ? { wait: true } : {});
    }
    // ---- app.js openNotif ----
    const marked = [];
    const mark = (x) => { if (!x.read && !marked.includes(x.id)) marked.push(x.id); };
    const out = (go) => ({ read: marked, go });
    if (n.kind === 'birthday') {
      mark(n);
      const b = W.userById(n.from), name = W.fullName(b);
      return out({ to: 'birthday', title: `${name.split(' ')[0]}’s birthday`, person: { id: n.from, name, ini: initials(name), color: avColor(n.from || 'x'), photo: b && b.avatar ? '/__file/' + String(b.avatar).split('/').map(encodeURIComponent).join('/') : null } });
    }
    if (n.kind === 'daily') { mark(n); return out({ to: 'daily' }); }
    if (n.kind === 'sched-cancel') { mark(n); return out({ to: 'schedCancel', id: n.schedId || null }); }
    if (/^claim/.test(n.kind)) { O.myNotifs().forEach((x) => { if (x.claimId && x.claimId === n.claimId) mark(x); }); return out(O.claim(n)); }
    if (n.planId) {
      O.myNotifs().forEach((x) => { if (notifKeyOf(x) === notifKeyOf(n)) mark(x); });
      if (!O.canSeePlans() || !O.planById(n.planId)) return out({ toast: 'Content skeleton not found' });
      return out({ to: 'plan', id: n.planId });
    }
    if (n.kind === 'asset') {
      O.myNotifs().forEach((x) => { if (notifKeyOf(x) === notifKeyOf(n)) mark(x); });
      if (!W.clients.some((c) => c.id === n.clientId)) return out({ toast: 'Client Assets not found' });
      return out(O.assets(n.clientId, n.folderId));
    }
    O.myNotifs().forEach((x) => { if (x.taskId === n.taskId) mark(x); });
    const t = O.task(n.taskId);
    if (!t) {
      const trash = Array.isArray(data.trash) ? data.trash : [];
      const inTrash = trash.find((x) => (x.type === 'task' || x.type === 'project') && (x.key === 'tasks:' + n.taskId || ((x.data || {}).tasks || []).some((y) => y.id === n.taskId)));
      if (inTrash && O.isManager()) return out({ to: 'trash', q: O.trashTitle(inTrash), toast: 'That task is in the Trash' });
      return out({ toast: O.isManager() ? 'That task has been deleted' : 'That task is in the Trash — ask an Account Manager if it should come back' });
    }
    if ((n.kind === 'review' || n.kind === 'review-wd') && W.isCD()) {
      // the submission this update is about, on Review Requests
      const rs = (t.reviews || []).filter((r) => r.by === n.from && r.state !== 'withdrawn');
      const r = rs.filter((x) => x.at <= n.at).pop() || rs[rs.length - 1] || null;
      let tab = 'active';
      if (r && r.state !== 'pending') {
        const recent = (x) => (x.state === 'approved' || x.state === 'amend') && x.decidedAt && (W.now - new Date(x.decidedAt)) < 15 * 864e5;
        if ((Array.isArray(data.tasks) ? data.tasks : []).some((tk) => (tk.reviews || []).some((x) => x.id === r.id && recent(x)))) tab = 'reviewed';   // (app.js reviewedRecent)
      }
      return out({ to: 'review', id: r ? r.id : null, tab });
    }
    const comments = t.comments || [];
    let c = null;
    if (n.kind === 'review-amend' && n.commentId) c = comments.find((x) => x.id === n.commentId) || null;
    if (n.kind === 'comment' || n.kind === 'mention') {
      // older notifications have no comment id: the author's comment closest in time
      c = (n.commentId && comments.find((x) => x.id === n.commentId))
        || comments.filter((x) => x.authorId === n.from).sort((a, b) => Math.abs(new Date(a.at) - new Date(n.at)) - Math.abs(new Date(b.at) - new Date(n.at)))[0] || null;
    }
    if (c) return out(O.openTask(t.id, 'comments', Object.assign({ focus: c.id }, c.parentId ? { thread: c.parentId } : {})));
    if (n.kind === 'mention') return out(O.openTask(t.id, 'details', { desc: true }));
    return out(O.openTask(t.id, 'details'));
  };
  // ---------- The morning round-up (Part B step 8): web/daily.js nativeShow, worked out without the page ----------
  // daily() → the app's own sheet (dailySheet): { title, sub, foot, open: the first section with something | '',
  //   sections: [{ k, l, sym, rgb, n, rows: [{ id, t, m, d, late }], more: { t } | null, filter: My Tasks' filter | null }],
  //   team: the whole team's (a Super Admin — My Tasks gets team: true too) } · null: not one who gets it (AMs, Super Admins)
  const D_SYM = { overdue: 'flag.fill', today: 'calendar', cd: 'checkmark.shield.fill', amend: 'pencil', client: 'checkmark', sched: 'clock.fill' };
  const D_RGB = { red: [255, 59, 48], amber: [255, 159, 10], accent: [10, 132, 255], sched: [142, 92, 247] };
  M.daily = function (R, data, meId, nowMs) {
    const W = world(R, data, meId, nowMs), u = W.me(), r = W.r;
    data = data || {};
    const isOffice = !!u && u.role === 'office_admin' && u.admin !== true;
    const team = !!u && W.isAdm(u) && !isOffice;
    if (!u || !(u.role === 'am' || team)) return null;
    const today = W.today;
    const ids = team ? W.users.filter((x) => x.active !== false && (x.role === 'am' || W.isAdm(x))).map((x) => x.id) : [u.id];
    const open = r.leadSet(ids).filter((t) => !t.done && !(W.proj(t.projectId) || {}).inactive);
    const byDue = (a, b) => (a.due || '9999').localeCompare(b.due || '9999');
    const hasApproved = (t) => (t.reviews || []).some((x) => x.state === 'approved');
    const amend = (t) => r.needsCD(t) && r.reviewersOf(t).some((x) => r.reviewState(t, x) === 'amend');
    const dubaiDay = (iso) => new Date(Date.parse(iso) + 4 * 3600000).toISOString().slice(0, 10);
    const sched = (Array.isArray(data.scheduled) ? data.scheduled : []).filter((s) => s.authorId === u.id && s.state === 'waiting' && dubaiDay(s.sendAt) === today)
      .sort((a, b) => String(a.sendAt).localeCompare(String(b.sendAt)));
    const S = [
      { k: 'overdue', l: 'Overdue', tone: 'red', tasks: open.filter((t) => t.due && t.due < today).sort(byDue), filter: { due: 'late' } },
      { k: 'today', l: 'Due today', tone: 'amber', tasks: open.filter((t) => t.due === today), filter: { due: 'today' } },
      { k: 'cd', l: 'Waiting for CD review', tone: 'accent', tasks: open.filter(r.reviewPending), filter: { cd: true } },
      { k: 'amend', l: 'Amendments sent back', tone: 'red', tasks: open.filter(amend) },
      { k: 'client', l: 'Client approval missing', tone: 'amber', tasks: open.filter((t) => hasApproved(t) && !r.clientApprovalFresh(t)) },
      { k: 'sched', l: 'Your comments scheduled today', tone: 'accent', sched },
    ];
    const n = (s) => (s.sched ? s.sched.length : s.tasks.length);
    const now = new Date(W.now);
    const clock = (d) => d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Dubai' });
    const first = S.find((s) => n(s));
    const sections = S.map((s) => {
      const c = n(s);
      // (7 lines at most — "See … in My Tasks" is one of them)
      const room = s.filter ? 6 : 7;
      const rows = s.sched
        ? s.sched.slice(0, 7).map((x) => { const t = W.task(x.taskId); return { id: x.taskId, t: r.trunc(x.text || 'Files', 70), m: t ? (t.title || 'Untitled task') : '', d: clock(new Date(x.sendAt)), late: false }; })
        : s.tasks.slice(0, room).map((t) => { const p = W.proj(t.projectId); return { id: t.id, t: t.title || 'Untitled task', m: p ? p.name : '', d: t.due ? r.fmtDay(t.due) : '', late: !!(t.due && t.due < today) }; });
      return { k: s.k, l: s.l, sym: D_SYM[s.k] || 'circle', rgb: s.k === 'sched' ? D_RGB.sched : D_RGB[s.tone] || D_RGB.accent, n: c, rows,
        more: s.filter && c ? { t: c > 6 ? `See all ${c} in My Tasks` : 'See them in My Tasks' } : null, filter: s.filter || null };
    });
    const when = now.toLocaleDateString('en-US', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Dubai' });
    const first1 = (W.fullName(u) || '').split(' ')[0];
    return {
      title: `Good morning, ${first1}`, sub: `${when} · ${team ? 'the whole team’s tasks' : r.hasClients(u.id) ? 'your clients’ tasks' : 'your tasks'}`,
      foot: `Up to date as of ${clock(now)}`, open: first ? first.k : '', sections, team,
    };
  };
  // ---------- A scheduled comment that wasn't sent, tapped (step 9): schedule.js openCancelled, worked out here ----------
  // schedOpen(id) → { task, thread, text } (back into the comment box on the task's Comments) · { trash: q } (a manager:
  // the task is in the Trash) · { toast }
  M.schedOpen = function (R, data, meId, nowMs, id) {
    const W = world(R, data, meId, nowMs);
    if (!W.me()) return null;
    data = data || {};
    const s = (Array.isArray(data.scheduled) ? data.scheduled : []).find((x) => x.id === id);
    if (!s) return { toast: 'Gone after 30 days' };
    const t = W.task(s.taskId);
    if (t) {
      const thread = s.replyTo && (t.comments || []).some((c) => c.id === s.replyTo) ? s.replyTo : null;
      return { task: t.id, thread, text: s.text || plainHTML(s.html || ''), files: (s.attachments || []).length };
    }
    const O = opener(W, data);
    const trash = Array.isArray(data.trash) ? data.trash : [];
    const inTrash = trash.find((it) => ((it.data || {}).tasks || []).some((x) => x && x.id === s.taskId));
    if (inTrash && O.isManager()) return { trash: O.trashTitle(inTrash), toast: 'The task is in the Trash' };
    return { toast: 'Its task has been deleted' };
  };
  // ---------- The pop-ups (step 9): when each is due, as the page decided (app.js Announce.check, ProfileAsk.maybe,
  // OccasionHello.birthday; claims.js reminderDue) — the app shows them as its own and says what was seen (pfSet 'seen')
  // pops() → { announce: { id, title, body, ask, from, fromName, when } | null, profileAsk: 'both' | 'birthday' | 'city' |
  //   null, birthday: { key, title, sub, person } | null, claims: { month, today } | null } — "today" and the clock are
  //   Dubai's
  M.pops = function (R, data, meId, nowMs) {
    const W = world(R, data, meId, nowMs), u = W.me();
    if (!u) return null;
    data = data || {};
    const prefs = u.prefs || {};
    const dub = new Date(W.now + 4 * 3600000), today = W.today;
    const personOf = (id) => { const x = W.userById(id); return { id, name: W.fullName(x), ini: initials(W.fullName(x)), color: avColor(id || 'x'), photo: x && x.avatar ? '/__file/' + String(x.avatar).split('/').map(encodeURIComponent).join('/') : null }; };
    // the announcement (once — closed with Got it)
    const a = W.meta.announcement && W.meta.announcement.id ? W.meta.announcement : null;
    const fmtWhen = (iso) => new Date(iso).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Dubai' });
    const announce = a && a.by !== u.id && prefs.annSeen !== a.id ? (() => {
      const from = W.userById(a.by);
      return { id: a.id, title: a.title || '', body: a.body || '', ask: 'If you have any questions, please contact Muhammad Arsal.', from: from ? personOf(from.id) : { name: 'E11', ini: 'E11', color: '#5b8cff' },
        fromName: from ? W.fullName(from).split(' ')[0] : 'E11', when: a.at ? fmtWhen(a.at) : '' };
    })() : null;
    // the birthday / city nudge (staff, once per person)
    const profileAsk = u.role !== 'freelancer' && !prefs.profileAsked && !(u.bday && u.country && u.city)
      ? (!u.bday && !(u.country && u.city) ? 'both' : !u.bday ? 'birthday' : 'city') : null;
    // your own birthday (29 Feb on 28 Feb in other years) — once that day (the app remembers on this phone)
    const isBday = (md) => {
      if (!/^\d{2}-\d{2}$/.test(String(md || ''))) return false;
      if (md === today.slice(5)) return true;
      const y = Number(today.slice(0, 4)), leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
      return md === '02-29' && !leap && today.slice(5) === '02-28';
    };
    const birthday = isBday(u.bday) ? { key: today + ':' + u.id, title: `Happy birthday, ${W.fullName(u).split(' ')[0]}`, sub: 'Wishing you a wonderful year · from all of us at E11', person: personOf(u.id) } : null;
    // the claims reminder: the 20th to the 27th, from 11:30, while this month's own claim is missing or a draft, once a day
    const isFinUser = u.role === 'finance_admin' || u.role === 'finance_viewer';
    const d = dub.getUTCDate(), mins = dub.getUTCHours() * 60 + dub.getUTCMinutes(), m = today.slice(0, 7);
    const own = (Array.isArray(data.claims) ? data.claims : []).find((c) => c.id === `cl-${u.id}-${m}`);
    const claims = !isFinUser && u.active !== false && d >= 20 && d <= 27 && mins >= 11 * 60 + 30 && !(own && own.state !== 'draft') && prefs.claimNag !== today
      ? { month: new Date(Date.UTC(Number(m.slice(0, 4)), Number(m.slice(5, 7)) - 1, 1)).toLocaleDateString('en-US', { month: 'long', timeZone: 'UTC' }), today: d } : null;
    return { announce, profileAsk, birthday, claims, today };
  };
  // ---------- The startup screen's four rows (Part B step 8): app.js Splash values(), worked out without the page ----------
  // startRows() → { list: [Clients, Your tasks, Inbox, the fourth], label4, cd } · null: not a member
  M.startRows = function (R, data, meId, nowMs) {
    const W = world(R, data, meId, nowMs), u = W.me();
    if (!u) return null;
    data = data || {};
    const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
    let open = 0, today = 0;
    try { const D = W.r.day(); const o = D.tasks.filter(D.open); open = o.length; today = o.filter((t) => t.due && t.due === W.today).length; } catch (e) { /* none */ }
    const unread = (Array.isArray(data.notifications) ? data.notifications : []).filter((n) => n.to === meId && !n.read).length;
    const cd = W.isCD();
    // (app.js activeReviews: the CD's requests waiting)
    const waiting = cd ? W.tasks.filter((t) => !t.done && !t.parentId && t.needsCD).reduce((n, t) => n + (t.reviews || []).filter((x) => x.state === 'pending' && (x.epoch || 0) === (t.reviewEpoch || 0)).length, 0) : 0;
    return {
      cd, label4: cd ? 'Review requests' : 'Client Assets',
      list: [`${W.projects.filter((p) => !p.archived).length} synced`, `${open} open · ${today} today`, unread ? `${unread > 99 ? '99+' : unread} new` : 'all read',
        cd ? (waiting ? `${waiting} waiting` : 'none waiting') : plural(W.clients.length, 'client', 'clients')],
    };
  };
  // A shared task link in the iPhone app (TaskLink.open → show): { go } —
  //   { to: 'task', id, tab: 'details', focus: '' } · { toast, home: true } (an Office Admin)
  //   { peek: true, id, toast } — Production / Freelancers: not one of theirs; ask the server (POST /api/peek { taskId }),
  //     take the new copy, then ask again with peeked = true (toast if it still isn't there)
  //   { toast: 'That task is not available' }
  M.taskLinkOpen = function (R, data, meId, nowMs, taskId, peeked) {
    const W = world(R, data, meId, nowMs);
    if (!W.me()) return null;
    const O = opener(W, data || {});
    if (O.isOffice()) return { go: { toast: 'Not in the Office Admin view', home: true } };
    if (O.task(taskId)) return { go: O.openTask(taskId, 'details') };
    if (!peeked && O.ownSearchOnly()) return { go: { peek: true, id: taskId, toast: 'That task is not available' } };
    return { go: { toast: 'That task is not available' } };
  };
})(E11AppMe);
if (typeof module !== 'undefined' && module.exports) module.exports = E11AppMe;
