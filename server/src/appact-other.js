// Part B step 3: the iPhone app's own pages' actions for Content plans, the Trash and the Team, done on the server — the
// same rules, refusals, notifications, activity lines and logs as the website's handlers the app used to send them to
// (web/phone.js NativeMe → web/plans.js Plans.native.act, web/app.js restoreTrash / eraseTrashFlow / emptyTrashFlow,
// cdToggleFlow, memberMenu, addMemberFlow). Each handler is named as the phone.js event and takes (u, body):
//   { ok: true, changes: [{ kind, id, base, data } | { kind, id, del: true }], messages: [], answer: {}, filesGone?: [] }
//   { ok: false, status, error, ... }
// It changes nothing itself: the route checks every change with access.canWrite and saves them all or none. The page's
// questions (Approve? Delete forever? Remove? …) are asked by the app before it sends the action.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const ROLES = { admin: 'Super Admin', office_admin: 'Office Admin', am: 'Account Manager', production: 'Production', social: 'Social', freelancer: 'Freelancer', finance_admin: 'Finance only · Admin', finance_viewer: 'Finance only · Viewer' };
const FIN_ACCESS = { '': 'No Finance access', admin: 'Finance Admin', viewer: 'Finance Viewer' };
const DEFAULT_FOLDERS = ['Logos', 'Brand Guidelines', 'Fonts', 'Files'];
const DENIED = 'Your role can’t do this';   // (the website's denied())

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const unesc = (s) => String(s).replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const fileRefsIn = (html) => { const out = []; String(html || '').replace(/data-fpath="([^"]*)"/g, (_, p) => { out.push(unesc(p)); return ''; }); return out; };
const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const monthLabel = (m) => { const [y, mm] = String(m || '').split('-').map(Number); return `${MONTHS[mm - 1]} ${y}`; };
const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
const isAdm = (u) => !!u && (u.role === 'admin' || u.role === 'office_admin' || u.admin === true);
const isOffice = (u) => !!u && u.role === 'office_admin' && u.admin !== true;
const isSuper = (u) => isAdm(u) && !isOffice(u);
const isFinUser = (u) => !!u && (u.role === 'finance_admin' || u.role === 'finance_viewer');
const isManager = (u) => !!u && (isAdm(u) || u.role === 'am');
const fullName = (u) => (u ? (u.name || String(u.email || '').split('@')[0]) : 'Former member');
const validEmail = (s) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(s).trim());

export function createOtherActs({ store, now = () => Date.now(), webDir, ownerEmail } = {}) {
  const owner = String(ownerEmail ?? process.env.ADMIN_EMAIL ?? '').toLowerCase();
  const nowISO = () => new Date(now()).toISOString();
  const uid = () => now().toString(36) + Math.random().toString(36).slice(2, 8);
  const fail = (status, error, extra = {}) => ({ ok: false, status, error, ...extra });
  const done = (changes, messages = [], answer = {}, more = {}) => ({ ok: true, changes, messages, answer, ...more });

  // the shared task rules (web/rules.js — the website runs the same file): activity lines and the notifications about them
  const dir = webDir || process.env.WEB_DIR || path.resolve(here, '../../web');
  const rulesFile = path.join(dir, 'rules.js');
  let R = null, rulesAt = '';
  function rulesLib() {
    const m = String(fs.statSync(rulesFile).mtimeMs);
    if (!R || m !== rulesAt) {
      R = vm.runInNewContext(`${fs.readFileSync(rulesFile, 'utf8')}; E11Rules`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN, encodeURIComponent });
      rulesAt = m;
    }
    return R;
  }

  const meta = () => store.get('meta', 'main') || {};
  const userById = (id) => (id ? store.get('users', String(id)) : null);
  const cdUserId = (m = meta()) => { const id = m.cdUserId; const u = id && userById(id); return u && u.active !== false ? id : null; };
  const cdActing = (m = meta()) => !!(m.cdActing && cdUserId(m));
  const socialMgrIds = (m = meta()) => (m.socialMgrIds || []).filter((id) => { const u = userById(id); return u && u.active !== false && u.role === 'social'; });
  const firstName = (id) => fullName(userById(id)).split(' ')[0];
  const isOwner = (x) => !!owner && !!x && String(x.email || '').toLowerCase() === owner;
  // a record changed: { kind, id, base (as it was), data (as it is now) }
  const changed = (kind, base, data) => ({ kind, id: String(data.id), base: clone(base), data: clone(data) });

  /* ================= Content plans (web/plans.js) ================= */
  const isMgr = (u) => !!u && u.role === 'social' && socialMgrIds().includes(u.id);
  const sentTo = (pl, k) => { const t = pl && pl.review && pl.review.to; return !t || t === 'both' || t === k; };
  const canApprove = (pl, u) => !!pl && !!u && ((u.id === cdUserId() && sentTo(pl, 'cd')) || (isMgr(u) && pl.createdBy !== u.id && sentTo(pl, 'sm')));
  const approverIds = (pl, to) => {
    const cd = cdUserId(), sm = socialMgrIds().filter((id) => id !== pl.createdBy);
    return [...new Set(to === 'cd' ? [cd] : to === 'sm' ? sm : [cd, ...sm])].filter(Boolean);
  };
  const nameOf = (pl) => { const p = store.get('projects', String(pl.projectId)); return `${p ? p.name : 'A client'} · ${monthLabel(pl.month)}`; };
  // (Plans' notify: one each, never to the person acting or someone no longer here)
  function planNotify(u, out, ids, pl, kind, text, snippet = '') {
    [...new Set(ids)].forEach((to) => {
      const x = to && userById(to);
      if (!x || to === u.id || x.active === false) return;
      const n = { id: uid(), to, from: u.id, kind, planId: pl.id, text, snippet: String(snippet || '').slice(0, 300), at: nowISO(), read: false };
      out.push({ kind: 'notifications', id: n.id, data: n });
    });
  }
  const logIt = (u, pl, act, extra = {}) => { pl.log = (pl.log || []).concat({ act, by: u.id, at: nowISO(), round: pl.round || 1, ...extra }); pl.updatedAt = nowISO(); };
  // Plans.native.act: the checks every one of them makes first
  function planFor(u, body) {
    const pl = store.get('plans', String(body.plan || ''));
    if (!pl) return { err: fail(404, 'This plan is no longer here') };
    if (!canApprove(pl, u)) return { err: fail(403, 'Only the Social Manager or the Creative Director can do this') };
    if (pl.status !== 'review') return { err: fail(409, 'It isn’t waiting for approval any more') };
    return { pl, base: clone(pl) };
  }
  // a post marked: Looks good (state 'ok'), Ask for changes with a note (state 'changes'), or the mark taken off
  function plReview(u, body) {
    const { pl, base, err } = planFor(u, body); if (err) return err;
    const x = (pl.posts || []).find((y) => y.id === body.post); if (!x) return fail(404, 'This post is no longer here');
    const note = String(body.note || '').trim();
    if (body.state === 'changes' && !note) return fail(400, 'Say what should change');
    if (body.state === 'ok' || body.state === 'changes') x.check = { state: body.state, note: body.state === 'changes' ? note : '', by: u.id, at: nowISO() }; else delete x.check;
    pl.updatedAt = nowISO();
    return done([changed('plans', base, pl)], [body.state === 'ok' ? 'Marked Looks good' : 'Marked Ask for changes']);
  }
  // the whole skeleton approved (not while a post is marked Ask for changes)
  function plApprove(u, body) {
    const { pl, base, err } = planFor(u, body); if (err) return err;
    const flagged = (pl.posts || []).filter((x) => x.check && x.check.state === 'changes').length;
    if (flagged) return fail(409, `${plural(flagged, 'post')} ${flagged === 1 ? 'is' : 'are'} marked Ask for changes — send it back instead`);
    const at = nowISO();
    (pl.posts || []).forEach((x) => { if (!x.check || x.check.state !== 'ok') x.check = { state: 'ok', by: u.id, at }; });
    pl.status = 'approved';
    pl.approval = { by: u.id, at, round: pl.round || 1 };
    logIt(u, pl, 'approved');
    const out = [changed('plans', base, pl)];
    planNotify(u, out, [pl.createdBy, pl.review && pl.review.by, ...approverIds(pl, (pl.review && pl.review.to) || 'both')], pl, 'plan-ok', `approved the content skeleton for <b>${esc(nameOf(pl))}</b>`);
    return done(out, ['Content skeleton approved']);
  }
  // sent back for changes: a note, or posts marked Ask for changes (or both)
  function plBack(u, body) {
    const { pl, base, err } = planFor(u, body); if (err) return err;
    const note = String(body.note || '').trim();
    const flagged = (pl.posts || []).filter((x) => x.check && x.check.state === 'changes');
    if (!note && !flagged.length) return fail(400, 'Say what should change');
    pl.status = 'changes';
    logIt(u, pl, 'changes', { note });
    const out = [changed('plans', base, pl)];
    planNotify(u, out, [pl.createdBy, pl.review && pl.review.by, ...approverIds(pl, (pl.review && pl.review.to) || 'both')], pl, 'plan-changes', `asked for changes on the content skeleton for <b>${esc(nameOf(pl))}</b>`, note || flagged.map((x) => `${x.title}: ${x.check.note || 'changes'}`).join(' · '));
    return done(out, ['Sent back to Social']);
  }

  /* ================= The Trash (web/app.js) ================= */
  // (who sees it: Admins and Account Managers; Office Admins only Client Assets items — access.js canSee)
  const trashSeen = (u, it) => !!it && (isOffice(u) ? ['cafile', 'cafolder'].includes(it.type) : isAdm(u) || u.role === 'am');
  function trashFiles(it) {
    const d = it.data || {};
    const fromTasks = (list) => (list || []).flatMap((t) => (t.attachments || []).concat(...(t.comments || []).map((c) => c.attachments || [])));
    if (it.type === 'task') return fromTasks(d.tasks);
    if (it.type === 'project') return fromTasks(d.tasks);
    if (it.type === 'comment') return (d.comments || []).flatMap((c) => c.attachments || []);
    if (it.type === 'attachment') return d.att ? [d.att] : [];
    if (it.type === 'cafile') return d.file ? [d.file] : [];
    if (it.type === 'cafolder') return [d.folder, ...(d.inner || [])].filter(Boolean).flatMap((x) => x.files || []);
    return [];
  }
  function trashPaths(it) {
    const paths = [];
    trashFiles(it).forEach((a) => { if (!a.linked) paths.push(a.path, '.thumbs/' + a.id); });
    if (it.type === 'task' || it.type === 'project') (it.data.tasks || []).forEach((t) => paths.push('attachments/' + t.id));
    if (it.type === 'cafolder' && it.data.folder && it.data.folder.dir) paths.push(it.data.folder.dir);
    return paths;
  }
  // every file still in use (the website's usedPaths: tasks, comments, descriptions, scheduled comments, the rest of the
  // Trash, Client Assets) — a file erased with a Trash item goes only when nothing else uses it (copies are shared)
  function usedPaths(goneIds) {
    const s = new Set();
    const add = (a) => { if (a && a.path) { s.add(a.path); if (a.thumb) s.add(a.thumb); } };
    store.list('tasks').forEach((t) => {
      (t.attachments || []).forEach(add);
      (t.comments || []).forEach((c) => { (c.attachments || []).forEach(add); fileRefsIn(c.html).forEach((p) => s.add(p)); });
      fileRefsIn(t.notesHtml).forEach((p) => s.add(p));
    });
    store.list('scheduled').forEach((x) => { if (x.state !== 'sent') (x.attachments || []).forEach(add); });
    store.list('trash').filter((x) => !goneIds.has(x.id)).forEach((it) => trashFiles(it).forEach(add));
    store.list('clients').forEach((c) => { if (c.logo) s.add(c.logo); (c.folders || []).forEach((f) => (f.files || []).forEach(add)); });
    return [...s];
  }
  function safePaths(paths, goneIds) {
    const used = usedPaths(goneIds);
    return (paths || []).filter((p) => p && !used.some((x) => x === p || x.startsWith(p.replace(/\/$/, '') + '/') || (p.startsWith('.thumbs/') && x.startsWith(p))));
  }
  // the task rules over the whole data, for activity lines and their notifications (new ones collected in db.notifications)
  function taskRules(u, tasks) {
    const db = { users: store.list('users'), projects: store.list('projects'), tasks, statuses: store.list('statuses'), plans: store.list('plans'), meta: meta(), notifications: [] };
    const env = { nowISO, nowMs: () => now(), uid };
    const L = rulesLib();
    return { db, rules: L.withEnv(env, db, u.id, L.dubaiDay(now())) };
  }
  // the tasks the website has (an inactive client's are hidden from everyone, and can't be changed — access.js)
  function liveTasks() {
    const all = store.list('tasks');
    const off = new Set(store.list('projects').filter((p) => p.inactive).map((p) => p.id));
    if (!off.size) return all;
    const byId = new Map(all.map((t) => [t.id, t]));
    const pid = (t) => t.projectId || (t.parentId && byId.get(t.parentId) ? byId.get(t.parentId).projectId || null : null);
    return all.filter((t) => !off.has(pid(t)));
  }
  const isAutoFolder = (c, f) => !!f.auto || (DEFAULT_FOLDERS.includes(f.name) && (!f.createdBy || f.createdBy === c.createdBy) && Math.abs(Date.parse(f.createdAt || 0) - Date.parse(c.createdAt || 0)) < 60000);
  const isFilesTop = (c, f) => !!f && !f.parentId && f.name === 'Files' && isAutoFolder(c, f);
  const folderDup = (c, name, exceptId, parentId) => c.folders.find((f) => f.id !== exceptId && (f.parentId || null) === (parentId || null) && f.name.trim().toLowerCase() === name.trim().toLowerCase());

  // put back where it was: tasks (and their subtasks), a client with its tasks (Admins), a comment or a file into its
  // task, a Client Assets file into its folder, a folder (and the folders that were in it) into its client
  function trRestore(u, body) {
    const it = store.get('trash', String(body.id || ''));
    if (it && it.type === 'project' && !isAdm(u) && trashSeen(u, it)) return fail(403, 'Only Admins restore clients');
    if (!isManager(u)) return fail(403, DENIED);
    if (!it || !trashSeen(u, it)) return fail(404, 'Already restored or no longer in the Trash');
    const d = clone(it.data || {});
    const out = [];
    let msg = '', open = null;
    if (it.type === 'task' || it.type === 'project') {
      const projects = store.list('projects');
      const proj = (id) => projects.find((p) => p.id === id);
      if (it.type === 'project' && !proj(d.project.id)) { projects.push(d.project); out.push({ kind: 'projects', id: String(d.project.id), data: clone(d.project) }); }
      const all = liveTasks();
      const exists = (id) => all.some((x) => x.id === id);
      const tasks = (d.tasks || []).filter((t) => !exists(t.id));
      const ids = new Set(tasks.map((t) => t.id));
      const statuses = store.list('statuses');
      const st0 = () => (statuses[0] || { id: 'st-todo' }).id;
      tasks.forEach((t) => {
        const p = proj(t.projectId);
        if (t.projectId && !p) { t.projectId = null; t.sectionId = st0(); }
        else if (p && !p.sections.some((s) => s.id === t.sectionId)) t.sectionId = p.sections[0].id;
        else if (!t.projectId && !statuses.some((s) => s.id === t.sectionId)) t.sectionId = st0();
        if (t.parentId && !ids.has(t.parentId) && !exists(t.parentId)) t.parentId = null;
        all.push(t);
      });
      const root = tasks.find((t) => !t.parentId || !ids.has(t.parentId)) || tasks[0];
      let notes = [];
      if (it.type === 'task' && root) {
        const { db, rules } = taskRules(u, all);
        rules.logActivity(root, 'restored this task from the Trash');
        rules.notifyWatchers(root, 'restore', 'restored from the Trash');
        notes = db.notifications;
        open = root.id;
        msg = `Restored “${root.title || 'Untitled task'}”${it.projectId && !proj(it.projectId) ? ' to My Tasks — its client is in the Trash' : ''}`;
      } else msg = `Restored the client “${d.project.name}” with ${tasks.filter((t) => !t.parentId).length} tasks`;
      tasks.forEach((t) => out.push({ kind: 'tasks', id: String(t.id), data: clone(t) }));
      notes.forEach((n) => out.push({ kind: 'notifications', id: String(n.id), data: clone(n) }));
    } else if (it.type === 'comment' || it.type === 'attachment') {
      const all = liveTasks();
      const t = all.find((x) => x.id === d.taskId);
      if (!t) return fail(409, 'Restore its task first');
      const base = clone(t);
      const { db, rules } = taskRules(u, all);
      t.comments = t.comments || []; t.attachments = t.attachments || [];
      if (it.type === 'comment') {
        (d.comments || []).forEach((c) => { if (!t.comments.some((x) => x.id === c.id)) t.comments.push(c); });
        t.comments.sort((a, b) => a.at.localeCompare(b.at));
        rules.logActivity(t, 'restored a comment from the Trash');
      } else {
        if (!t.attachments.some((x) => x.id === d.att.id)) t.attachments.push(d.att);
        rules.logActivity(t, `restored attachment <b>${esc(d.att.name)}</b>`);
      }
      t.updatedAt = nowISO();
      out.push(changed('tasks', base, t));
      db.notifications.forEach((n) => out.push({ kind: 'notifications', id: String(n.id), data: clone(n) }));
      msg = `Restored to “${t.title || 'Untitled task'}”`; open = t.id;
    } else if (it.type === 'cafile') {
      const c = store.get('clients', String(d.clientId || '')); const f = c && (c.folders || []).find((x) => x.id === d.folderId);
      if (!f) return fail(409, 'Its folder is gone');
      const base = clone(c);
      if (!f.files.some((x) => x.id === d.file.id)) f.files.push(d.file);
      out.push(changed('clients', base, c));
      msg = `Restored “${d.file.name}”`;
    } else if (it.type === 'cafolder') {
      const c = store.get('clients', String(d.clientId || ''));
      if (!c) return fail(409, 'Its Client Assets are gone');
      const base = clone(c);
      const f = { ...d.folder };
      if (!c.folders.some((x) => x.id === f.id)) {
        // (the folder it was in is gone: back into Files, or onto the client's main page)
        if (f.parentId && !c.folders.some((x) => x.id === f.parentId)) { const fl = c.folders.find((x) => isFilesTop(c, x)); if (fl && !f.finalOf) f.parentId = fl.id; else if (!fl) delete f.parentId; else f.parentId = fl.id; }
        if (folderDup(c, f.name, null, f.parentId)) f.name = `${f.name} (restored)`;
        c.folders.push(f);
        (d.inner || []).forEach((x) => { if (!c.folders.some((y) => y.id === x.id)) c.folders.push({ ...x }); });
      }
      if (!same(base, c)) out.push(changed('clients', base, c));
      msg = `Restored the folder “${f.name}”${(d.inner || []).length ? ` and the ${(d.inner || []).length} folder${(d.inner || []).length === 1 ? '' : 's'} in it` : ''} to ${c.name}`;
    } else return fail(400, 'This can’t be restored');
    out.push({ kind: 'trash', id: String(it.id), del: true });
    return done(out, [msg], open ? { open } : {});
  }
  // deleted for good (Admins): the Trash entries, and their files when nothing else uses them (filesGone: for the
  // server's own trash folder, as the website's safeTrash)
  function erase(u, items) {
    const gone = new Set(items.map((x) => x.id));
    const paths = items.flatMap(trashPaths);
    return { changes: items.map((x) => ({ kind: 'trash', id: String(x.id), del: true })), filesGone: safePaths(paths, gone) };
  }
  // (Office Admins: Client Assets items are only put in and taken back out — never deleted forever; access.js)
  const mayErase = (u) => isAdm(u) && !isOffice(u);
  function trForever(u, body) {
    if (!mayErase(u)) return fail(403, DENIED);
    const it = store.get('trash', String(body.id || ''));
    if (!it) return fail(404, 'Already deleted or no longer in the Trash');
    const r = erase(u, [it]);
    return done(r.changes, ['Deleted forever'], {}, { filesGone: r.filesGone });
  }
  function trEmpty(u) {
    if (!mayErase(u)) return fail(403, DENIED);
    const items = store.list('trash');
    if (!items.length) return done([], []);
    const r = erase(u, items);
    return done(r.changes, ['The Trash is empty'], {}, { filesGone: r.filesGone });
  }

  /* ================= The Team (web/app.js) ================= */
  // The Creative Director switch (a person's row). Making someone CD while another person is: body.choice 'cd' (they
  // take over) or 'acting' (Acting CD while the CD is away — not for the CD coming back); without it the answer is the
  // page's question (need: 'choice', ask). Switching off the CD: an Acting CD's CD comes back, else no CD.
  function cd(u, body) {
    if (!isAdm(u)) return fail(403, DENIED);
    const id = String(body.id || '');
    const x = userById(id);
    if (!x) return fail(404, 'This person is no longer on the team');
    const m0 = meta(), m = clone(m0);
    const cur = cdUserId(m0);
    const title = cdActing(m0) ? 'Acting CD' : 'Creative Director';
    let msg;
    if (cur === id) {
      if (cdActing(m0) && m0.cdHomeId && userById(m0.cdHomeId)) { m.cdUserId = m0.cdHomeId; m.cdHomeId = null; m.cdActing = false; msg = `${fullName(userById(m.cdUserId))} is CD again`; }
      else { m.cdUserId = null; m.cdActing = false; m.cdHomeId = null; msg = 'No Creative Director now'; }
      return done([{ kind: 'meta', id: 'main', base: m0, data: m }], [msg]);
    }
    let acting = false;
    if (cur) {
      const returning = m0.cdHomeId === id;
      const choices = [];
      if (!returning) choices.push({ label: `Acting CD while ${firstName(cur)} is away`, value: 'acting' });
      choices.push({ label: returning ? `Make ${firstName(id)} CD again` : `Make ${firstName(id)} Creative Director`, value: 'cd', primary: true });
      const choice = String(body.choice || '');
      if (!choices.some((c) => c.value === choice)) {
        const curName = fullName(userById(cur));
        return fail(409, 'Are you sure?', { need: 'choice', ask: { title: 'Are you sure?', body: `${curName} is the ${title}. Only one person can be CD at a time — ${curName} will be switched off and all pending review requests move to ${fullName(x)}.`, choices } });
      }
      acting = choice === 'acting';
      if (acting) m.cdHomeId = cdActing(m0) ? m0.cdHomeId : cur;
      else m.cdHomeId = null;
    }
    m.cdUserId = id;
    m.cdActing = acting;
    return done([{ kind: 'meta', id: 'main', base: m0, data: m }], [`${fullName(x)} is now ${acting ? 'Acting CD' : 'the Creative Director'}`]);
  }
  // A person's menu (touch and hold their row): body.act —
  //   'role' (body.role)       their role; your own only as the owner (with Admin rights)
  //   'admin'                  Super Admin rights on top of their role, on / off
  //   'fin' (body.fin)         Finance access: '' | 'admin' | 'viewer' (yours too)
  //   'socialMgr'              a Social person as the Social Manager, on / off
  //   'restore' / 'remove'     access back / removed from the team (unassigned from their tasks)
  //   'clients' (body.projectIds, or body.project to tick one)   the clients a freelancer can see
  // answer.clients: true — a freelancer now: the app asks which clients they can see next (as the website does)
  const supers = () => store.list('users').filter((x) => isSuper(x) && x.active !== false);
  function member(u, body) {
    if (!isAdm(u)) return fail(403, DENIED);
    const x0 = userById(String(body.id || ''));
    if (!x0) return fail(404, 'This person is no longer on the team');
    const x = clone(x0);
    const act = String(body.act || '');
    const mine = x.id === u.id;
    const save = (msgs, answer = {}) => done([changed('users', x0, x)], msgs, answer);
    if (isOwner(x) && !mine && !isOwner(u)) return fail(403, 'Only the owner can change this account');
    if (act === 'fin') {
      if (isFinUser(x)) return fail(400, 'Not available');
      const k = String(body.fin || '');
      if (!Object.prototype.hasOwnProperty.call(FIN_ACCESS, k)) return fail(400, 'Not available');
      x.fin = k || undefined;
      const l = FIN_ACCESS[k];
      if (mine) return save([k ? `You now have ${l} access` : 'You no longer have Finance access']);
      return save([k ? `${fullName(x)} now has ${l} access` : `${fullName(x)} no longer has Finance access`]);
    }
    if (act === 'role') {
      const k = String(body.role || '');
      if (!ROLES[k]) return fail(400, 'Not available');
      if (mine) {
        // (the owner — only the owner — may work as another role, as long as someone else is a Super Admin)
        if (!isOwner(u) || !isAdm(x)) return fail(403, DENIED);
        if (x.role === k) return done([], []);
        if (k !== 'admin' && !store.list('users').some((y) => y.id !== x.id && isSuper(y) && y.active !== false)) return fail(409, 'Make another Super Admin first');
        x.role = k;
        return save([`You now work as ${ROLES[k]}`]);
      }
      if (isSuper(x) && k !== 'admin' && !x.admin && supers().length < 2) return fail(409, 'Keep at least one Super Admin');
      x.role = k;
      return save([`${fullName(x)} is now ${ROLES[k]}`], k === 'freelancer' ? { clients: true } : {});
    }
    if (mine) return fail(403, DENIED);   // (your own row: only the extras)
    if (act === 'admin') {
      if (x.role === 'admin' || isFinUser(x)) return fail(400, 'Not available');
      if (x.admin && supers().length < 2) return fail(409, 'Keep at least one Super Admin');
      x.admin = x.admin ? undefined : true;
      return save([x.admin ? `${fullName(x)} now also has Admin rights` : `${fullName(x)} no longer has Admin rights`]);
    }
    if (act === 'socialMgr') {
      if (x.role !== 'social' || x.active === false) return fail(400, 'Not available');
      const m0 = meta(), m = clone(m0);
      const on = socialMgrIds(m0).includes(x.id);
      m.socialMgrIds = on ? socialMgrIds(m0).filter((y) => y !== x.id) : socialMgrIds(m0).concat(x.id);
      return done([{ kind: 'meta', id: 'main', base: m0, data: m }], [on ? `${fullName(x)} is no longer Social Manager` : `${fullName(x)} is now Social Manager — they can make or edit any client’s content plan`]);
    }
    if (act === 'restore') {
      if (x.active !== false) return fail(400, 'Not available');
      x.active = true;
      return save([]);
    }
    if (act === 'remove') {
      if (x.active === false) return fail(400, 'Not available');
      if (isSuper(x) && supers().length < 2) return fail(409, 'Keep at least one Super Admin');
      x.active = false;
      const out = [changed('users', x0, x)];
      // (unassigned from their tasks, with an activity line on each — not by an Office Admin, who doesn't change tasks;
      //  nor a completed task — they're locked, the server keeps them as they are when the website tries)
      if (!isOffice(u)) {
        const all = liveTasks();
        const byId = new Map(all.map((t) => [t.id, t]));
        const locked = (t) => { const p = t.parentId ? byId.get(t.parentId) || store.get('tasks', String(t.parentId)) : null; return t.parentId ? !!(p && p.done && !p.parentId) : !!t.done; };
        const { db, rules } = taskRules(u, all);
        const trunc = (v, n) => { v = String(v == null ? '' : v).replace(/\s+/g, ' ').trim(); return v.length > n ? v.slice(0, n - 1) + '…' : v; };
        all.forEach((t) => {
          if (!(t.assignees || []).includes(x.id) || locked(t)) return;
          const base = clone(t);
          t.assignees = t.assignees.filter((y) => y !== x.id);
          if (t.prio) delete t.prio[x.id];
          rules.logActivity(t, `unassigned <span class="chg-old">${esc(trunc(fullName(x), 80))}</span>`);
          out.push(changed('tasks', base, t));
        });
        db.notifications.forEach((n) => out.push({ kind: 'notifications', id: String(n.id), data: clone(n) }));
      }
      return done(out, []);
    }
    if (act === 'clients') {
      if (x.role !== 'freelancer') return fail(400, 'Not available');
      const pids = new Set(store.list('projects').map((p) => p.id));
      if (Array.isArray(body.projectIds)) x.projectIds = [...new Set(body.projectIds.map(String))].filter((id) => pids.has(id));
      else {
        const pid = String(body.project || '');
        if (!pids.has(pid)) return fail(404, 'This client is no longer here');
        x.projectIds = Array.isArray(x.projectIds) ? x.projectIds : [];
        x.projectIds = x.projectIds.includes(pid) ? x.projectIds.filter((y) => y !== pid) : x.projectIds.concat(pid);
      }
      return save(Array.isArray(body.projectIds) ? [`${fullName(x)} can see ${plural(x.projectIds.length, 'client')}`] : []);
    }
    return fail(400, 'Not available');
  }
  // Add team member: body { name, email, role, admin: 'yes' | '', fin: '' | 'admin' | 'viewer' } — someone who left
  // (same email) comes back with the new role
  function addMember(u, body) {
    if (!isAdm(u)) return fail(403, DENIED);
    const v = { name: String(body.name || '').trim(), email: String(body.email || '').trim(), role: String(body.role || 'production').trim(), admin: String(body.admin || '').trim(), fin: String(body.fin || '').trim() };
    if (!validEmail(v.email)) return fail(400, 'Enter a valid email address');
    const users = store.list('users');
    if (users.some((y) => String(y.email || '').toLowerCase() === v.email.toLowerCase() && y.active !== false)) return fail(409, 'Someone with this email is already on the team');
    if (!ROLES[v.role]) return fail(400, 'Choose a role');
    if (!Object.prototype.hasOwnProperty.call(FIN_ACCESS, v.fin)) return fail(400, 'Not available');
    const was = users.find((y) => String(y.email || '').toLowerCase() === v.email.toLowerCase()) || null;
    let x;
    if (was) { x = clone(was); x.active = true; x.setup = false; x.role = v.role; if (v.name) x.name = v.name; }
    else x = { id: 'u-' + uid(), email: v.email.toLowerCase(), name: v.name, role: v.role, avatar: null, setup: false, active: true, createdAt: nowISO(), createdBy: u.id, prefs: {} };
    const finOnly = v.role === 'finance_admin' || v.role === 'finance_viewer';
    x.admin = v.admin === 'yes' && v.role !== 'admin' && !finOnly ? true : undefined;
    x.fin = v.fin && !finOnly ? v.fin : undefined;
    const ch = was ? changed('users', was, x) : { kind: 'users', id: x.id, data: clone(x) };
    return done([ch], [`Added ${v.email} as ${ROLES[v.role]}`], { id: x.id, ...(v.role === 'freelancer' ? { clients: true } : {}) });
  }

  return { plReview, plApprove, plBack, trRestore, trForever, trEmpty, cd, member, addMember };
}
