// Part B step 6: the iPhone app's New task, done on the server — exactly as the page's nativeQuickAdd submit and
// app.js createTask do it (web/phone.js): the same new record (id, fields, status, order, Needs CD review), the people
// assigned with their activity lines and Inbox updates (the shared rules, web/rules.js — the client's Account Managers
// hear of each too), and the same refusals ("Give the task a name", "Turn off CD review first"). Handlers take (u, body):
//   { ok: true, changes: [{ kind, id, data }], messages: [], answer: { id } } | { ok: false, status, error }
// It changes nothing itself: the route checks every change with access.canWrite and saves them all or none.
//
//   tkNew(u, { title, projectId, due, desc, who: [ids], cd })
//     projectId: the client picked ('' / null: none, My Tasks) · due: 'YYYY-MM-DD' or '' · desc: the description as
//     typed · who: the people ticked (only used when the person may assign; else they're on it themselves when they
//     can be assigned) · cd: Needs CD review (only for Admins, Account Managers and the CD)
//     view / ctxProjectId (optional): the page the form was opened on — an Account Manager's rights there (taskCtx)
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { createAccess } from './access.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const DENIED = 'Your role can’t do this';
const ASSIGNABLE = new Set(['production', 'social', 'freelancer']);
const DEFAULT_STATUSES = [{ id: 'st-todo', name: 'To do', color: '#87909e' }];
const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const linkify = (html) => html.replace(/(https?:\/\/[^\s<]+)/g, '<a href="#" data-action="open-url" data-url="$1">$1</a>');
const isAdm = (u) => !!u && (u.role === 'admin' || u.role === 'office_admin' || u.admin === true);
const fullName = (u) => (u ? (u.name || String(u.email || '').split('@')[0]) : 'Former member');

export function createTaskActs({ store, now = () => Date.now(), webDir, access } = {}) {
  const acc = access || createAccess(store, { plans: true });
  const nowISO = () => new Date(now()).toISOString();
  const uid = () => now().toString(36) + Math.random().toString(36).slice(2, 8);
  const fail = (status, error) => ({ ok: false, status, error });

  // the shared task rules (web/rules.js — the website runs the same file)
  const dir = webDir || process.env.WEB_DIR || path.resolve(here, '../../web');
  const rulesFile = path.join(dir, 'rules.js');
  let RL = null, rulesAt = '';
  function rulesLib() {
    const m = String(fs.statSync(rulesFile).mtimeMs);
    if (!RL || m !== rulesAt) {
      RL = vm.runInNewContext(`${fs.readFileSync(rulesFile, 'utf8')}; E11Rules`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN, encodeURIComponent });
      rulesAt = m;
    }
    return RL;
  }
  // what this person's page has (the server's visibleSnapshot): its db, as app.js normalize leaves it where it matters
  function view(u) {
    const vis = (k) => store.list(k).filter((x) => acc.canSee(u, k, x)).map((x) => clone(acc.shape(u, k, x)));
    const statuses = store.list('statuses');
    return { users: vis('users'), projects: vis('projects'), tasks: vis('tasks'), statuses: statuses.length ? statuses : DEFAULT_STATUSES, plans: vis('plans'), meta: store.get('meta', 'main') || {}, notifications: [] };
  }

  function tkNew(u, body = {}) {
    const db = view(u);
    const L = rulesLib();
    const rules = L.withEnv({ nowISO, nowMs: () => now(), uid }, db, u.id, L.dubaiDay(now()));
    const userById = (id) => db.users.find((x) => x.id === id) || null;
    const proj = (id) => db.projects.find((p) => p.id === id);
    const cdU = db.meta.cdUserId && userById(db.meta.cdUserId);
    const cdUserId = cdU && cdU.active !== false ? cdU.id : null;
    const assignable = (x) => !!x && x.active !== false && (ASSIGNABLE.has(x.role) || x.id === cdUserId);
    // (the form's page: a client's own page gives an Account Manager that client's rights — app.js taskCtx)
    const ctxPid = body.view === 'project' && body.ctxProjectId && proj(String(body.ctxProjectId)) ? String(body.ctxProjectId) : '';
    const tctx = ctxPid ? { projectId: ctxPid } : null;
    if (!rules.can('createTask', tctx)) return fail(403, DENIED);
    const title = String(body.title == null ? '' : body.title).trim();
    if (!title) return fail(400, 'Give the task a name');
    const pid = body.projectId ? String(body.projectId) : '';
    const p = pid ? proj(pid) : null;
    // (the client picker: active clients the person may start tasks in, and the one the form was opened in)
    if (pid && !p) return fail(404, 'That client is no longer here');
    const amOk = (x) => x.role !== 'am' || isAdm(x) || cdUserId === x.id || !db.projects.some((q) => (q.ams || []).some((a) => a.id === x.id)) || (p.ams || []).some((a) => a.id === x.id && !a.onLeave);
    if (p && pid !== ctxPid && (p.inactive || !amOk(u))) return fail(403, 'You can’t start tasks in that client');
    const due = body.due ? String(body.due) : '';
    if (due && !/^\d{4}-\d{2}-\d{2}$/.test(due)) return fail(400, 'Not a date');
    const mgr = isAdm(u) || u.role === 'am' || cdUserId === u.id;
    const canAssign = rules.can('assign', tctx);
    let who;
    if (canAssign) {
      who = [...new Set((Array.isArray(body.who) ? body.who : []).map(String))];
      if (who.some((id) => !assignable(userById(id)))) return fail(400, 'Only Production, Social, Freelancers and the CD can be assigned');
    } else who = assignable(u) ? [u.id] : [];
    const cdOn = mgr && !!body.cd && !!cdUserId;   // (no CD set: no CD review — Haris 2026-11-06)
    if (cdOn && cdUserId && who.includes(cdUserId)) return fail(409, 'Turn off CD review first');
    const desc = String(body.desc == null ? '' : body.desc);
    // app.js createTask
    const at = nowISO();
    const t = {
      id: uid(), projectId: p ? p.id : null, sectionId: null, parentId: null,
      title, notes: desc, done: false, completedAt: null, due: due || null, prio: {},
      tags: [], attachments: [], comments: [], checklist: [], activity: [], start: null, createdAt: at, updatedAt: at,
      cdRule: 2, cdStatus: '', assignees: [], createdBy: u.id, reviews: [], needsCD: !!p && !!cdUserId,
      ...(desc ? { notesHtml: linkify(esc(desc)).replace(/\n/g, '<br>') } : {}),
    };
    t.activity.push({ id: uid(), at, text: 'created this task', actor: u.id });
    t.sectionId = p ? (p.sections && p.sections[0] ? p.sections[0].id : null) : db.statuses[0].id;
    const sibs = db.tasks.filter((x) => !x.parentId && x.projectId === t.projectId && x.sectionId === t.sectionId);
    t.order = sibs.length ? Math.max(...sibs.map((x) => x.order || 0)) + 1 : 1;
    db.tasks.push(t);
    if (mgr) t.needsCD = !!(cdOn && t.projectId);
    if (who.length) {
      t.assignees = [...who];
      who.filter((x) => x !== u.id).forEach((x) => { rules.logActivity(t, `assigned <b>${esc(fullName(userById(x)))}</b>`); rules.pushNotif(x, t, 'assigned', 'assigned you to'); });
    }
    const changes = [{ kind: 'tasks', id: String(t.id), data: clone(t) }];
    db.notifications.forEach((n) => changes.push({ kind: 'notifications', id: String(n.id), data: clone(n) }));
    return { ok: true, changes, messages: [`Created “${title}”`], answer: { id: t.id } };
  }

  // "New task from this" (app.js taskFrom — step 9): a new task in the same client with the same people, tags,
  // description, channels and guardian, based on it; the iPhone asks its name first (the page made it blank and asked)
  function tkFrom(u, body = {}) {
    const db = view(u);
    const L = rulesLib();
    const rules = L.withEnv({ nowISO, nowMs: () => now(), uid }, db, u.id, L.dubaiDay(now()));
    const src = db.tasks.find((t) => t.id === String(body.id || ''));
    if (!src || src.parentId) return fail(404, 'That task is not available');
    const tctx = src.projectId ? { projectId: src.projectId } : null;
    if (!rules.can('createTask', tctx)) return fail(403, DENIED);
    const title = String(body.title == null ? '' : body.title).trim();
    if (!title) return fail(400, 'Give the task a name');
    const at = nowISO();
    const p = src.projectId ? db.projects.find((x) => x.id === src.projectId) : null;
    const t = {
      id: uid(), projectId: src.projectId || null, sectionId: null, parentId: null,
      title, notes: src.notes || '', notesHtml: src.notesHtml || '', done: false, completedAt: null, due: null, prio: {},
      tags: (src.tags || []).slice(), attachments: [], comments: [], checklist: [], activity: [], start: null, createdAt: at, updatedAt: at,
      cdRule: 2, cdStatus: '', assignees: (src.assignees || []).slice(), createdBy: u.id, reviews: [], needsCD: !!src.projectId && !!(db.meta.cdUserId && (db.users.find((x) => x.id === db.meta.cdUserId) || {}).active !== false && db.users.some((x) => x.id === db.meta.cdUserId)),
      channels: (src.channels || []).slice(), basedOn: src.id, ...(src.guardian ? { guardian: src.guardian } : {}),
    };
    t.activity.push({ id: uid(), at, text: 'created this task', actor: u.id });
    if (t.needsCD && t.assignees.length === 1 && t.assignees[0] === db.meta.cdUserId) t.needsCD = false;   // (the CD alone on it: no CD review — Haris 2026-11-08)
    rules.logActivity(t, `started this from <b>${esc(src.title || 'Untitled task')}</b>`);
    t.sectionId = p ? (p.sections && p.sections[0] ? p.sections[0].id : null) : db.statuses[0].id;
    const sibs = db.tasks.filter((x) => !x.parentId && x.projectId === t.projectId && x.sectionId === t.sectionId);
    t.order = sibs.length ? Math.max(...sibs.map((x) => x.order || 0)) + 1 : 1;
    db.tasks.push(t);
    t.assignees.filter((x) => x !== u.id).forEach((x) => rules.pushNotif(x, t, 'assigned', 'assigned you to'));
    const changes = [{ kind: 'tasks', id: String(t.id), data: clone(t) }];
    db.notifications.forEach((n) => changes.push({ kind: 'notifications', id: String(n.id), data: clone(n) }));
    return { ok: true, changes, messages: [`Created “${title}”`], answer: { id: t.id } };
  }

  return { tkNew, tkFrom };
}
