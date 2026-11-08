/* The app's own screens, worked out from a person's data (iOS app data plan, 2026-11-02): Home, My Tasks, the Inbox, a
   task's page and its comments, as the iPhone app draws them. One file, run in two places so they can never disagree:
   - the server (server/src/homeview.js) for /api/home, /api/mytasks, /api/inbox, /api/task, /api/comments;
   - the iPhone app itself (iPhone's JavaScript engine), on its own copy of the data, with no request at all.
   It only reads; the rules are the shared ones (web/rules.js, E11Rules). Changes still go to the server. */
var E11AppView = (function () {
  'use strict';
  const fileUrl = (p) => '/__file/' + String(p).split('/').map(encodeURIComponent).join('/');
  // a file as the app gets it: its address, its picture's (a video's frame, a PDF's or Office file's first page — made
  // on the server the first time it's asked for: /api/fthumb), and its place on the server (for its page pictures)
  const THUMBED = ['mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv', 'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'odt', 'odp', 'ods', 'rtf'];
  function appFile(f) {
    const ext = String(f.name || '').split('.').pop().toLowerCase();
    f.file = f.path || null;
    f.url = f.path ? fileUrl(f.path) + '?view=1' : null;
    f.thumbUrl = f.thumb ? fileUrl(f.thumb) + '?view=1' : f.path && ext === 'svg' ? fileUrl(f.path) + '?view=1' : f.path && THUMBED.includes(ext) ? '/api/fthumb?path=' + encodeURIComponent(f.path) + '&id=' + encodeURIComponent(f.id || '') : null;
    delete f.path; delete f.thumb;
  }
  const photos = (m) => { for (const p of Object.values(m.people || {})) { if (p.photo) p.photo = fileUrl(p.photo) + '?view=1'; } };
  const base = (data) => ({ users: data.users || [], projects: data.projects || [], tasks: data.tasks || [], statuses: data.statuses || [], plans: data.plans || [], meta: data.meta || {} });
  const envOf = (nowMs) => ({ nowISO: () => new Date(nowMs()).toISOString(), nowMs: () => nowMs() });
  const userOf = (data, id) => (data.users || []).find((x) => x.id === id) || { id };

  // R: E11Rules · data: this person's data (what their app downloads) · me: their id · nowMs: the clock
  // Finance only people (finance_admin / finance_viewer): Finance is on the computer (Haris 2026-11-05) — the iPhone app
  // shows them just that, and Me
  const finOnly = (data, me) => { const u = (data.users || []).find((x) => x.id === me); return !!u && (u.role === 'finance_admin' || u.role === 'finance_viewer'); };
  function home(R, data, me, nowMs) {
    const today = R.dubaiDay(nowMs());
    if (finOnly(data, me)) return { show: true, plain: true, title: 'Finance', date: 'On the computer', me, today, stats: [0, 0, 0], add: false, canDelete: false, people: {},
      groups: [{ name: '', n: 0, empty: 'Finance is on the computer — open E11 Console on your Mac or at console.e11hq.com.', cards: [] }] };
    const m = R.home(base(data), me, today);
    if (!m) return null;
    photos(m);   // (the app fetches them itself, a small copy, signed in as it is)
    return Object.assign({}, m, { today });
  }
  // q: the filters — { tab: 'all' | 'done', due, people: [], ams: [], team, assigned, cd }
  function myTasks(R, data, me, nowMs, q, who) {
    const u = who || userOf(data, me);
    if (u.role === 'finance_admin' || u.role === 'finance_viewer' || (u.role === 'office_admin' && u.admin !== true)) return null;
    const today = R.dubaiDay(nowMs());
    const list = (v) => (Array.isArray(v) ? v : String(v || '').split(',')).map((x) => String(x).trim()).filter(Boolean).slice(0, 100);
    const F = { due: ['late', 'today', 'week'].includes(q.due) ? q.due : null, people: list(q.people), ams: list(q.ams), team: !!q.team, assigned: !!q.assigned, cd: !!q.cd };
    const m = R.withEnv(envOf(nowMs), base(data), me, today).myTasks(F, q.tab === 'done' ? 'done' : 'all');
    photos(m);
    return Object.assign({}, m, { today });
  }
  function inbox(R, data, me, nowMs, tab, who) {
    const u = who || userOf(data, me);
    if (u.role === 'finance_admin' || u.role === 'finance_viewer') return null;
    const today = R.dubaiDay(nowMs());
    const m = R.make(Object.assign(base(data), { notifications: data.notifications || [] }), me, today).inbox(['unread', 'mentions'].includes(tab) ? tab : 'all');
    if (!m) return null;
    photos(m);
    return Object.assign({}, m, { today });
  }
  // the Clients tab (Part B): q = { view: 'list' | 'client', id, done }
  function clients(R, data, me, nowMs, q) {
    const today = R.dubaiDay(nowMs());
    const r = R.withEnv(envOf(nowMs), Object.assign(base(data), { clients: data.clients || [] }), me, today);
    const m = q && q.view === 'client' ? r.clientPage(String(q.id || ''), !!q.done) : r.clientsList();
    if (!m) return null;
    photos(m);
    const logo = (x) => { if (x && x.logo) x.logo = fileUrl(x.logo) + '?view=1'; };
    logo(m); (m.rows || []).concat(m.inactive || []).forEach(logo);
    return Object.assign({}, m, { today });
  }
  // a task's page — null: not there, or not for this person
  function taskPage(R, data, me, nowMs, id) {
    const today = R.dubaiDay(nowMs());
    const m = R.withEnv(envOf(nowMs), base(data), me, today).taskPage(String(id || ''));
    if (!m) return null;
    photos(m);
    for (const f of (m.files || []).concat(m.commentFiles || [], m.descFiles || [])) appFile(f);
    return Object.assign({}, m, { today });
  }
  // a task's comments, or one thread's
  function commentsFeed(R, data, me, nowMs, id, thread) {
    const m = R.withEnv(envOf(nowMs), Object.assign(base(data), { scheduled: data.scheduled || [] }), me, R.dubaiDay(nowMs())).commentsFeed(String(id || ''), thread ? String(thread) : null);
    if (!m) return null;
    photos(m);
    for (const it of m.items) for (const f of it.files) appFile(f);
    return m;
  }

  // the tab bar (Part B step 1, Haris 2026-11-04): the same tabs, labels and counts as the page's (phone.js chrome), from
  // the person's data — the app draws its tab bar from this at once, without the website. `plans`: the Plans tab's
  // count isn't worked out here yet (its rules are still the website's) — null: the app keeps the page's.
  function tabs(R, data, me, nowMs) {
    const users = data.users || [], meta = data.meta || {};
    const u = users.find((x) => x.id === me);
    if (!u || u.active === false) return null;
    const isAdm = u.role === 'admin' || u.role === 'office_admin' || u.admin === true;
    const office = u.role === 'office_admin' && u.admin !== true;
    const fin = u.role === 'finance_admin' ? 'admin' : u.role === 'finance_viewer' ? 'viewer' : u.fin === 'admin' || u.fin === 'viewer' ? u.fin : null;
    const cdU = meta.cdUserId && users.find((x) => x.id === meta.cdUserId && x.active !== false);
    const cd = !!cdU && cdU.id === me;
    const finUser = u.role === 'finance_admin' || u.role === 'finance_viewer';
    const unread = (data.notifications || []).filter((n) => n.to === me && !n.read && !/^claim/.test(n.kind || '')).length;
    const T = (v, label, badge) => ({ v, label, badge: badge ? (badge > 99 ? '99+' : String(badge)) : '' });
    if (finOnly(data, me)) return { tabs: [T('today', 'Finance'), T('me', 'Me')], plans: false, photo: u.avatar ? fileUrl(u.avatar) : null };
    if (office) {
      const hr = fin ? (data.claims || []).filter((c) => c.state === 'submitted').length : 0;
      return { tabs: [T('today', 'Overview'), T('inbox', 'Inbox', unread), ...(fin ? [T('fin-reimb', 'Claims', hr), T('fin-expenses', 'Expenses')] : [T('team', 'Team'), T('clients', 'Client Assets')]), T('me', 'Me')], plans: false, admin: isAdm, photo: u.avatar ? fileUrl(u.avatar) : null };
    }
    const today = R.dubaiDay(nowMs());
    const r = R.withEnv(envOf(nowMs), base(data), me, today);
    let due = 0; try { const d = r.myDayData(); due = d && d.due ? d.due.length : 0; } catch (e) { due = 0; }
    // the CD's requests waiting (app.js activeReviews)
    const rv = cd ? (data.tasks || []).filter((t) => !t.done && !t.parentId && t.needsCD).reduce((n, t) => n + (t.reviews || []).filter((x) => x.state === 'pending' && (x.epoch || 0) === (t.reviewEpoch || 0)).length, 0) : 0;
    const social = u.role === 'social' && !finUser && !office;
    // (Plans' count from web/appme-plans.js when the app has it — step 2; else the page's)
    const pw = social && typeof E11AppMe !== 'undefined' && typeof E11AppMe.plansWaiting === 'function' ? (() => { try { return E11AppMe.plansWaiting(R, data, me, nowMs); } catch (e) { return null; } })() : null;
    const third = cd ? T('reviews', 'Reviews', rv) : social ? T('plans', 'Plans', pw || 0) : T('projects', 'Clients');
    return { tabs: [T('today', r.dayTitle(), due), T('mytasks', 'My Tasks'), T('inbox', 'Inbox', unread), third, T('me', 'Me')], plans: social && pw == null, admin: isAdm, photo: u.avatar ? fileUrl(u.avatar) : null };
  }

  // ---------- the app's own copy (iPhone): kept here, in the engine, as the website keeps its own ----------
  // load(json): the download (/api/snapshot) or the saved copy · apply(changes): the live stream's · save(): to keep
  let copy = null;   // { rev, me, data }
  const KEYED = (kind) => kind !== 'meta';
  function load(json) {
    const s = typeof json === 'string' ? JSON.parse(json) : json;
    copy = { rev: Number(s.rev) || 0, me: s.me || null, data: s.data || {} };
    return copy.rev;
  }
  function apply(changes, rev) {
    if (!copy) return false;
    for (const ch of changes || []) {
      if (!ch || !ch.kind) continue;
      if (!KEYED(ch.kind)) { if (!ch.deleted && ch.data) copy.data.meta = ch.data; continue; }
      const list = copy.data[ch.kind] || (copy.data[ch.kind] = []);
      const i = list.findIndex((x) => x && x.id === ch.id);
      if (ch.deleted) { if (i >= 0) list.splice(i, 1); }
      else if (ch.data) { if (i >= 0) list[i] = ch.data; else list.push(ch.data); }
    }
    if (Number(rev) > copy.rev) copy.rev = Number(rev);
    return true;
  }
  // ---------- the actions (POST /api/home/act): Done / reopen, due, Trash, the Inbox's read, the task page's ----------
  // Done here with the shared rules on what this person may see — the server runs exactly this, and the iPhone app runs
  // it on its own copy first (localAct), so a change shows at once and the server's answer confirms it.
  // Returns { ok, changes, messages, undo } or { ok: false, status, error, … }.
  function homeAct(R, data, u, body, env, store) {
    const clone = (v) => JSON.parse(JSON.stringify(v));
    const today = R.dubaiDay(env.nowMs());
    const db = { users: data.users || [], projects: data.projects || [], tasks: clone(data.tasks || []), statuses: data.statuses || [], plans: data.plans || [], meta: data.meta || {}, notifications: clone(data.notifications || []), trash: [] };
    const rules = R.withEnv(env, db, u.id, today);
    const before = new Map(db.tasks.map((t) => [t.id, JSON.stringify(t)]));
    const notifBefore = new Map(db.notifications.map((n) => [n.id, JSON.stringify(n)]));
    const fail = (status, error, extra = {}) => ({ ok: false, status, error, ...extra });
    const t = db.tasks.find((x) => x.id === String(body.id || ''));
    const a = String(body.act || '');
    // the Inbox's: one read / unread, or all read (only this person's own)
    if (a === 'read' || a === 'unread' || a === 'readAll' || a === 'unreadList' || a === 'readList') {
      // (readList: what opening an update marks read — E11AppMe.notifOpen's `read`, claims included as the website's
      //  openNotif marks them)
      const mine = db.notifications.filter((n) => n.to === u.id && (a === 'readList' || !/^claim/.test(n.kind || '')));   // (claims: on the computer)
      const changes = [];
      const set = (n, v) => { if (!!n.read !== v) { const base = JSON.parse(JSON.stringify(n)); n.read = v; changes.push({ kind: 'notifications', id: n.id, base, data: n }); } };
      if (a === 'readAll') mine.forEach((n) => set(n, true));
      else if (a === 'readList') { const ids = new Set((Array.isArray(body.ids) ? body.ids : String(body.id || '').split(',')).map(String).filter(Boolean).slice(0, 500)); mine.filter((n) => ids.has(n.id)).forEach((n) => set(n, true)); }
      // (the Inbox's Mark all unread: only the ones in the list on screen — Haris, 2026-11-01)
      else if (a === 'unreadList') { const ids = new Set(String(body.id || '').split(',').filter(Boolean).slice(0, 500)); mine.filter((n) => ids.has(n.id)).forEach((n) => set(n, false)); }
      else { const n = mine.find((x) => x.id === String(body.id || '')); if (!n) return fail(404, 'This update is no longer here'); set(n, a === 'read'); }
      return { ok: true, changes, messages: a === 'readAll' && changes.length ? ['All marked read'] : a === 'unreadList' && changes.length ? ['Marked unread'] : [] };
    }
    let messages = [], undo = null;
    if (a === 'undoDelete') {
      const it = store.get('trash', String(body.trashId || ''));
      if (!it || !['task', 'comment', 'attachment'].includes(it.type) || it.deletedBy !== u.id) return fail(404, 'Already restored or no longer in the Trash');
      const changes = [];
      // a comment (and its replies) back into its task
      if (it.type === 'comment') {
        const tk = (data.tasks || []).find((x) => x.id === (it.data || {}).taskId);
        if (!tk) return fail(404, 'Its task is no longer here');
        const base = JSON.parse(JSON.stringify(tk)), next = JSON.parse(JSON.stringify(tk));
        for (const c of (it.data.comments || [])) if (!next.comments.some((x) => x.id === c.id)) next.comments.push(c);
        next.comments.sort((a, b) => String(a.at).localeCompare(String(b.at)));
        return { ok: true, changes: [{ kind: 'tasks', id: tk.id, base, data: next }], sysChanges: [{ kind: 'trash', id: it.id, del: true }], messages: [] };
      }
      // a task's file back on its task
      if (it.type === 'attachment') {
        const tk = (data.tasks || []).find((x) => x.id === (it.data || {}).taskId);
        if (!tk) return fail(404, 'Its task is no longer here');
        const base = JSON.parse(JSON.stringify(tk)), next = JSON.parse(JSON.stringify(tk));
        next.attachments = next.attachments || [];
        if (it.data.att && !next.attachments.some((x) => x.id === it.data.att.id)) next.attachments.push(it.data.att);
        return { ok: true, changes: [{ kind: 'tasks', id: tk.id, base, data: next }], sysChanges: [{ kind: 'trash', id: it.id, del: true }], messages: [] };
      }
      for (const x of (it.data && it.data.tasks) || []) if (!store.get('tasks', String(x.id))) changes.push({ kind: 'tasks', id: x.id, data: x });
      return { ok: true, changes, sysChanges: [{ kind: 'trash', id: it.id, del: true }], messages: [] };
    }
    // a client changed from the app's Clients list (its long press): Admins only — name, colour, Account Managers (on
    // leave), Social Executives; as the website's Edit client saves it
    if (a === 'editClient') {
      const me0 = (data.users || []).find((x) => x.id === u.id);
      if (!me0 || !(me0.role === 'admin' || me0.admin === true)) return fail(403, 'Only Admins change clients');
      const p = (data.projects || []).find((x) => x.id === String(body.id || ''));
      if (!p) return fail(404, 'This client is no longer here');
      const name = String(body.name || '').replace(/\s+/g, ' ').trim().slice(0, 80);
      if (!name) return fail(400, 'A client needs a name');
      const key = (n) => String(n || '').toLowerCase().replace(/&/g, 'and').replace(/[^a-z0-9\u0600-\u06ff]+/g, '');
      const dup = (data.projects || []).find((x) => x.id !== p.id && key(x.name) === key(name));
      if (dup) return fail(409, `There is already a client named “${dup.name}”.`);
      const users = data.users || [];
      const ok = (id, role) => users.some((x) => x.id === id && x.active !== false && x.role === role);
      const seen = new Set();
      const ams = (Array.isArray(body.ams) ? body.ams : []).filter((x) => x && ok(String(x.id), 'am') && !seen.has(String(x.id)) && seen.add(String(x.id))).map((x) => (x.onLeave ? { id: String(x.id), onLeave: true } : { id: String(x.id) }));
      const socials = [...new Set((Array.isArray(body.socials) ? body.socials : []).map(String))].filter((id) => ok(id, 'social'));
      const base = clone(p), next = clone(p);
      next.name = name; next.ams = ams;
      if (typeof body.color === 'string' && /^#[0-9a-f]{6}$/i.test(body.color)) next.color = body.color;
      if (socials.length) next.socials = socials; else delete next.socials;
      // (Active / inactive — the website's switch; Haris 2026-11-03)
      const wasOn = !p.inactive;
      if (typeof body.active === 'boolean') { if (body.active) delete next.inactive; else next.inactive = true; }
      const changes = [{ kind: 'projects', id: p.id, base, data: next }];
      // (its linked Client Assets folder takes the new name, unless another one already has it — as the website)
      let kept = false;
      const all = store && store.list ? store.list('clients') : (data.clients || []);
      const c = p.clientId ? all.find((x) => x.id === p.clientId) : null;
      if (c && p.name !== name) {
        if (all.some((x) => x.id !== c.id && key(x.name) === key(name))) kept = true;
        else changes.push({ kind: 'clients', id: c.id, base: clone(c), data: { ...clone(c), name } });
      }
      const nowOn = !next.inactive;
      const msg = wasOn !== nowOn ? (nowOn ? `${name} is active again — its tasks and Client Assets are back` : `${name} is inactive — hidden from everyone with its tasks, Client Assets and Finance history`)
        : kept ? 'Renamed — folder name kept' : 'Client saved';
      return { ok: true, changes, messages: [msg] };
    }
    // a new client from the app's Clients list (Admins only — Haris 2026-11-03): as the website's New client — the client
    // with its statuses, and its Client Assets folder (Logos, Brand Guidelines, Fonts, Files) made with it and linked; an
    // existing Client Assets folder of that name is reused. `dirs`: the folders to make on the NAS.
    if (a === 'addClient') {
      const me0 = (data.users || []).find((x) => x.id === u.id);
      if (!me0 || !(me0.role === 'admin' || me0.admin === true)) return fail(403, 'Only Admins add clients');
      const name = String(body.name || '').replace(/\s+/g, ' ').trim().slice(0, 80);
      if (!name) return fail(400, 'A client needs a name');
      const key = (n) => String(n || '').toLowerCase().replace(/&/g, 'and').replace(/[^a-z0-9\u0600-\u06ff]+/g, '');
      const projects = store && store.list ? store.list('projects') : (data.projects || []);
      const dup = projects.find((x) => key(x.name) === key(name));
      if (dup) return fail(409, `There is already a client named “${dup.name}”.`);
      const users = data.users || [];
      const ok = (id, role) => users.some((x) => x.id === id && x.active !== false && x.role === role);
      const seen = new Set();
      const ams = (Array.isArray(body.ams) ? body.ams : []).filter((x) => x && ok(String(x.id), 'am') && !seen.has(String(x.id)) && seen.add(String(x.id))).map((x) => (x.onLeave ? { id: String(x.id), onLeave: true } : { id: String(x.id) }));
      const socials = [...new Set((Array.isArray(body.socials) ? body.socials : []).map(String))].filter((id) => ok(id, 'social'));
      const COLORS = ['#5b8cff', '#3ddc97', '#ffb547', '#ff6b6b', '#c27cff', '#4fd1c5', '#ff8fc7', '#f2f26d', '#9aa0ab'];
      const used = new Set(projects.map((x) => x.color));
      const color = typeof body.color === 'string' && /^#[0-9a-f]{6}$/i.test(body.color) ? body.color : (COLORS.find((c) => !used.has(c)) || COLORS[0]);
      const at = env.nowISO();
      const np = { id: env.uid(), name, color, view: 'list', createdAt: at,
        order: projects.length ? Math.max(...projects.map((x) => x.order || 0)) + 1 : 1,
        sections: [['To do', '#87909e'], ['In progress', '#a875ff'], ['Review', '#f9be33'], ['CTR', '#ff8a4c'], ['Done', '#3ddc97']].map(([n, c]) => ({ id: env.uid(), name: n, color: c })),
        ams };
      if (socials.length) np.socials = socials;
      if (body.active === false) np.inactive = true;
      const changes = [], dirs = [];
      const clients = store && store.list ? store.list('clients') : (data.clients || []);
      let c = clients.find((x) => key(x.name) === key(name));
      if (!c) {
        const safe = (t) => String(t).replace(/[\/:\\]/g, '-').replace(/^\.+/, '').replace(/\s+/g, ' ').trim().slice(0, 80) || 'Untitled';
        const free = (base, n, taken) => { let d = `${base}/${safe(n)}`, i = 2; while (taken.some((x) => String(x).toLowerCase() === d.toLowerCase())) d = `${base}/${safe(n)} (${i++})`; return d; };
        c = { id: 'cl-' + env.uid(), name, logo: null, dir: '', folders: [], createdAt: at, createdBy: u.id };
        c.dir = free('Clients', name, clients.map((x) => x.dir || ''));
        for (const fn of ['Logos', 'Brand Guidelines', 'Fonts', 'Files']) {
          const f = { id: 'cf-' + env.uid(), name: fn, dir: free(c.dir, fn, c.folders.map((x) => x.dir)), files: [], createdAt: at, createdBy: u.id, auto: true };
          c.folders.push(f); dirs.push(f.dir);
        }
        changes.push({ kind: 'clients', id: c.id, data: c });
      }
      np.clientId = c.id;
      changes.unshift({ kind: 'projects', id: np.id, data: np });
      return { ok: true, changes, dirs, created: np.id, messages: [`Added ${name}${np.inactive ? ' (inactive)' : ' — its Client Assets folder is ready'}`] };
    }
    if (!t) return fail(404, 'This task is no longer here');
    // (no Home, no Home actions: Office Admins and Finance-only people)
    if (u.role === 'finance_admin' || u.role === 'finance_viewer' || (u.role === 'office_admin' && u.admin !== true)) return fail(403, 'Your role doesn’t allow this');
    const view = () => fail(403, 'View only — you can’t change this task');
    if (a === 'done') {
      if (t.done) return { ok: true, changes: [], messages: [] };
      if (rules.amReadOnly(t)) return view();
      // (to the Done status and complete, in one go — unless the CD's review is in the way)
      const blocked = rules.finishBlocked(t);
      if (blocked) return fail(409, blocked, { why: true });
      if (rules.asksClientApproval(t)) {
        if (!['yes', 'none'].includes(body.clientApproval)) return fail(409, 'Did the client approve?', { need: 'clientApproval' });
        rules.setClientApproval(t, body.clientApproval === 'none' ? { none: true } : {});
      }
      messages = rules.finish(t);
      messages.unshift('Task completed');
    } else if (a === 'reopen') {
      if (!t.done) return { ok: true, changes: [], messages: [] };
      if (rules.amReadOnly(t)) return view();
      if (!rules.canReopen(t)) return fail(403, 'Completed tasks are locked — only Admins can reopen them');
      messages = rules.setDone(t, false);
    } else if (a === 'due') {
      if (!rules.can('editDates', t) || rules.amReadOnly(t)) return fail(403, 'Your role doesn’t allow changing dates');
      // (a completed task is read only, as on the website — Haris 2026-11-08)
      if (rules.doneLocked(t)) return fail(403, 'Completed tasks are locked — only Admins can reopen them');
      const v = body.due == null || body.due === '' ? null : String(body.due);
      if (v && !(/^\d{4}-\d{2}-\d{2}$/.test(v) && new Date(v + 'T00:00:00Z').toISOString().slice(0, 10) === v)) return fail(400, 'Not a date');
      messages = rules.setDue(t, v);
    } else if (a === 'delete') {
      if (!rules.can('deleteTask', t) || rules.amReadOnly(t)) return fail(403, 'Your role doesn’t allow deleting tasks');
      const r = rules.deleteTask(t);
      undo = r.item.id;
      messages = ['Moved to the Trash'];
    } else if (['title', 'start', 'status', 'myPart', 'prio', 'check', 'needsCD', 'update', 'clientApproval', 'assign', 'guardian', 'addTag', 'removeTag', 'channels', 'addCheck', 'addSub', 'client', 'react', 'deleteComment', 'desc', 'submitReview', 'withdrawReview', 'comment', 'editComment', 'attach', 'finance', 'removeFile'].includes(a)) {
      // the native task page's (shell 30+) — each checked as the website checks it
      if ((!['react', 'deleteComment', 'comment', 'editComment', 'attach'].includes(a) && rules.amReadOnly(t)) || rules.doneLocked(t)) return view();   // (a view-only task: comments still)
      let r = [];
      if (a === 'title') { if (!rules.can('editTitle', t) || rules.idLocked(t)) return fail(403, 'The name can’t be changed'); r = rules.setTitle(t, body.value); }
      else if (a === 'start') {
        if (!rules.can('editDates', t)) return fail(403, 'Your role doesn’t allow changing dates');
        const v = body.value == null || body.value === '' ? null : String(body.value);
        if (v && !(/^\d{4}-\d{2}-\d{2}$/.test(v) && new Date(v + 'T00:00:00Z').toISOString().slice(0, 10) === v)) return fail(400, 'Not a date');
        r = rules.setStart(t, v);
      }
      else if (a === 'status') r = rules.setStatus(t, String(body.value || ''), body.cdAgain);
      else if (a === 'myPart') r = rules.setMyPart(t, !!body.value);
      else if (a === 'prio') { if (!rules.can('editPriority', t)) return fail(403, 'Your role doesn’t allow changing priority'); r = rules.setPrio(t, String(body.key || '_'), body.value); }
      else if (a === 'check') r = rules.toggleCheck(t, String(body.value || ''));
      else if (a === 'needsCD') r = rules.setNeedsCD(t, !!body.value);
      else if (a === 'update') { if (t.parentId) return fail(400, 'Not on a subtask'); r = rules.setUpdate(t, body.value ? String(body.value) : null); }
      else if (a === 'finance') { if (t.parentId || !rules.canFinance(t)) return fail(403, 'Your role doesn’t allow changing the Finance status'); r = rules.setFinance(t, body.value ? String(body.value) : null); }
      else if ((a === 'assign' || a === 'guardian') && rules.peopleLocked(t)) return fail(403, `${a === 'assign' ? 'Assignees are' : 'Guardian is'} locked since this task went for CD review`);
      else if (a === 'assign') { if (!rules.can('assign', t)) return fail(403, 'Your role doesn’t allow assigning'); r = rules.setAssignee(t, String(body.key || ''), !!body.value); }
      else if (a === 'guardian') { if (!rules.can('assign', t) || t.parentId) return fail(403, 'Your role doesn’t allow this'); r = rules.setGuardian(t, body.value ? String(body.value) : null); }
      else if (a === 'addTag') { if (!rules.can('addTag', t)) return fail(403, 'Your role doesn’t allow adding tags'); r = rules.addTag(t, body.value); }
      else if (a === 'removeTag') { if (!rules.can('removeTag', t)) return fail(403, 'Your role doesn’t allow removing tags'); r = rules.removeTag(t, String(body.value || '')); }
      else if (a === 'channels') { const u0 = (data.users || []).find((x) => x.id === u.id); if (!u0 || !(u0.role === 'admin' || u0.admin === true || u0.role === 'am' || u0.role === 'social') || t.parentId) return fail(403, 'Your role doesn’t allow this'); r = rules.setChannels(t, Array.isArray(body.value) ? body.value : []); }
      else if (a === 'addSub') { if (!rules.can('createTask', t) || t.parentId) return fail(403, 'Your role doesn’t allow adding subtasks'); r = rules.addSubtask(t, body.value); }
      else if (a === 'client') { if (!rules.can('editProject', t) || t.parentId || rules.idLocked(t)) return fail(403, 'The client can’t be changed'); r = rules.setClient(t, body.value ? String(body.value) : null); }
      else if (a === 'react') r = rules.toggleReaction(t, String(body.key || ''), String(body.value || ''));
      else if (a === 'deleteComment') { const d = rules.deleteComment(t, String(body.value || '')); if (d.error) return fail(409, d.error); undo = d.undo; r = d.messages; }
      else if (a === 'desc') { if (!rules.can('editDesc', t) || rules.idLocked(t)) return fail(403, 'The description can’t be changed'); r = rules.setDesc(t, body.html, body.text, !body.chips); }   // (apps that keep the 📎 chips themselves — 2026-11-02 on — can delete one)
      else if (a === 'submitReview') r = rules.submitReview(t, Array.isArray(body.files) ? body.files : []);
      else if (a === 'withdrawReview') r = rules.withdrawReview(t);
      else if (a === 'removeFile') { const d = rules.removeAttachment(t, String(body.value || '')); if (d.error) return fail(409, d.error); undo = d.undo; r = d.messages; }
      else if (a === 'attach') r = rules.attachFilesTo(t, Array.isArray(body.files) ? body.files : []);
      else if (a === 'comment') r = rules.postComment(t, body.parentId ? String(body.parentId) : null, body.html, body.text, Array.isArray(body.files) ? body.files : []);
      else if (a === 'editComment') r = rules.editComment(t, String(body.value || ''), body.html, body.text);
      else if (a === 'addCheck') { if (!rules.can('addChecklist', t)) return fail(403, 'Your role doesn’t allow adding checklist items'); r = rules.addCheck(t, body.value); }
      else if (a === 'clientApproval') {
        const ca = (rules.taskPage(t.id) || {}).clientApproval;
        if (!ca || !ca.canSet) return fail(403, 'Your role doesn’t allow this');
        rules.setClientApproval(t, body.value === 'yes' ? {} : body.value === 'none' ? { none: true } : null);
      }
      if (r && !Array.isArray(r)) {
        if (r.error) return fail(409, r.error);
        if (r.need) return fail(409, 'Does this need CD review again?', { need: r.need });
        r = r.messages || [];
      }
      messages = r;
    } else return fail(400, 'Unknown action');
    // what changed, as the website pushes it (each with the version it started from, merged on the server)
    const changes = [];
    const after = new Map(db.tasks.map((x) => [x.id, x]));
    for (const [id, was] of before) {
      const x = after.get(id);
      if (!x) changes.push({ kind: 'tasks', id, del: true });
      else if (JSON.stringify(x) !== was) changes.push({ kind: 'tasks', id, base: JSON.parse(was), data: x });
    }
    for (const x of db.tasks) if (!before.has(x.id)) changes.push({ kind: 'tasks', id: x.id, data: x });   // (new: a subtask)
    for (const n of db.notifications) {
      const was = notifBefore.get(n.id);
      if (!was) changes.push({ kind: 'notifications', id: n.id, data: n });
      else if (JSON.stringify(n) !== was) changes.push({ kind: 'notifications', id: n.id, base: JSON.parse(was), data: n });
    }
    for (const it of db.trash) changes.push({ kind: 'trash', id: it.id, data: it });
    return { ok: true, changes, messages, undo };
  }

  // the iPhone app: an action done on its own copy at once, before the server (Haris 2026-11-07: "all changes instantly,
  // then the server"). Actions the server alone can do (a new comment, files, a review, a new client, a subtask, Trash's
  // undo) wait for it as before. → JSON { ok, undo: [how things were], need, error } or null (not done here)
  const SERVER_ONLY = ['undoDelete', 'editClient', 'addClient', 'comment', 'editComment', 'attach', 'submitReview', 'withdrawReview', 'addSub', 'desc', 'removeFile', 'deleteComment'];
  function localAct(body) {
    if (!copy || !R() || !body) return null;
    const a = String(body.act || '');
    if (!a || SERVER_ONLY.includes(a)) return null;
    const u = (copy.data.users || []).find((x) => x && x.id === copy.me);
    if (!u) return null;
    const env = { nowISO: () => new Date(now()).toISOString(), nowMs: () => now(), uid: () => 'local-' + now().toString(36) + Math.random().toString(36).slice(2, 8) };
    let r;
    try { r = homeAct(R(), copy.data, u, body, env, null); } catch (e) { return null; }
    if (!r || !r.ok) return JSON.stringify({ ok: false, error: (r && r.error) || '', need: (r && r.need) || null });
    const undo = [], apply1 = [];
    for (const ch of r.changes || []) {
      if (!ch || !KEYED(ch.kind) || ch.kind === 'trash') continue;
      const list = copy.data[ch.kind] || [];
      const old = list.find((x) => x && x.id === ch.id);
      undo.push(old ? { kind: ch.kind, id: ch.id, data: JSON.parse(JSON.stringify(old)) } : { kind: ch.kind, id: ch.id, deleted: true });
      apply1.push(ch.del ? { kind: ch.kind, id: ch.id, deleted: true } : { kind: ch.kind, id: ch.id, data: ch.data });
    }
    apply(apply1, 0);
    return JSON.stringify({ ok: true, undo, messages: r.messages || [] });
  }

  // one thing changed on the phone at once, before the server's answer (the iPhone app: a new due date moved its card
  // straight away — Haris 2026-11-07); gives back how it was, to put back if the server says no. The server's answer
  // (its own changes) then replaces it as usual.
  function patch(kind, id, fields) {
    if (!copy || !KEYED(kind) || !fields) return null;
    const list = copy.data[kind] || [];
    const i = list.findIndex((x) => x && x.id === id);
    if (i < 0) return null;
    const base = list[i];
    const next = Object.assign(JSON.parse(JSON.stringify(base)), fields);
    Object.keys(fields).forEach((k) => { if (fields[k] === null) delete next[k]; });
    list[i] = next;
    return JSON.stringify([{ kind, id, data: base }]);
  }
  const save = () => (copy ? JSON.stringify(copy) : '');
  const ready = () => !!copy;
  const rev = () => (copy ? copy.rev : 0);
  // the screens from the copy, as JSON (what the server's routes send)
  const now = () => Date.now();
  const R = () => (typeof E11Rules !== 'undefined' ? E11Rules : null);
  function screen(kind, a, b) {
    if (!copy || !R()) return '';
    let m = null;
    try {
      if (kind === 'task') m = taskPage(R(), copy.data, copy.me, now, a);
      else if (kind === 'comments') m = commentsFeed(R(), copy.data, copy.me, now, a, b || null);
      else if (kind === 'home') m = home(R(), copy.data, copy.me, now);
      else if (kind === 'inbox') m = inbox(R(), copy.data, copy.me, now, a);
      else if (kind === 'mytasks') m = myTasks(R(), copy.data, copy.me, now, a ? JSON.parse(a) : {});
      else if (kind === 'clients') m = clients(R(), copy.data, copy.me, now, a ? JSON.parse(a) : {});
      else if (kind === 'tabs') m = tabs(R(), copy.data, copy.me, now);
      // (Part B step 2: Me's pages, Claims, Expenses, Overview, Reviews, Team, Trash, Plans, Client Assets — web/appme-*.js)
      else if (kind === 'me') { const f = typeof E11AppMe !== 'undefined' && E11AppMe[a]; if (typeof f !== 'function') return ''; m = f.apply(null, [R(), copy.data, copy.me, now].concat(b ? JSON.parse(b) : [])); }
    } catch (e) { return JSON.stringify({ error: String(e && e.message || e) }); }
    return JSON.stringify({ model: m, rev: copy.rev });
  }

  return { fileUrl, appFile, home, myTasks, inbox, clients, taskPage, commentsFeed, tabs, load, apply, patch, homeAct, localAct, save, ready, rev, screen };
})();
if (typeof module !== 'undefined' && module.exports) module.exports = E11AppView;
