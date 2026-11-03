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
  function home(R, data, me, nowMs) {
    const today = R.dubaiDay(nowMs());
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
    } catch (e) { return JSON.stringify({ error: String(e && e.message || e) }); }
    return JSON.stringify({ model: m, rev: copy.rev });
  }

  return { fileUrl, appFile, home, myTasks, inbox, clients, taskPage, commentsFeed, load, apply, save, ready, rev, screen };
})();
if (typeof module !== 'undefined' && module.exports) module.exports = E11AppView;
