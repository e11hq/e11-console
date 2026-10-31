// The iPhone app's Home straight from the server (iPhone app 25+): GET /api/home → the same model the app used to get
// from the page behind it (NativeHome in phone.js), worked out here with the same shared rules file (web/rules.js), from
// what this person may see (the same data their own app downloads). Read only.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

export function createHomeView({ webDir, now = () => Date.now() }) {
  const file = path.join(webDir || path.resolve(here, '../../web'), 'rules.js');
  let rules = null, loadedAt = 0;
  // (read again when the file changes — a new version installed)
  function load() {
    const m = fs.statSync(file).mtimeMs;
    if (!rules || m !== loadedAt) {
      const src = fs.readFileSync(file, 'utf8');
      rules = vm.runInNewContext(`${src}; E11Rules`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN });
      loadedAt = m;
    }
    return rules;
  }
  const fileUrl = (p) => '/__file/' + String(p).split('/').map(encodeURIComponent).join('/');
  // data: what this person's own app downloads (visibleSnapshot in server.js)
  function home(u, data) {
    const R = load();
    const today = R.dubaiDay(now());
    const m = R.home({ users: data.users || [], projects: data.projects || [], tasks: data.tasks || [], statuses: data.statuses || [], plans: data.plans || [], meta: data.meta || {} }, u.id, today);
    if (!m) return null;
    // photos: the app fetches them itself (a small copy), signed in as it is
    for (const p of Object.values(m.people || {})) { if (p.photo) p.photo = fileUrl(p.photo) + '?view=1'; }
    return { ...m, today };
  }
  // ---------- the app's Home actions (POST /api/home/act) ----------
  // Done / reopen, the due date, to the Trash and back — done here with the same shared rules the website uses, on the
  // same data this person's own app has (what they may see), so the activity lines, notifications and checks are
  // exactly the website's. Returns the changes to save (as the website would push them) and a short message.
  // body: { act: 'done' | 'reopen' | 'due' | 'delete' | 'undoDelete', id, due, clientApproval: 'yes' | 'none', trashId }
  const clone = (v) => JSON.parse(JSON.stringify(v));
  function act(u, data, body, store) {
    const R = load();
    const today = R.dubaiDay(now());
    const db = { users: data.users || [], projects: data.projects || [], tasks: clone(data.tasks || []), statuses: data.statuses || [], plans: data.plans || [], meta: data.meta || {}, notifications: clone(data.notifications || []), trash: [] };
    const env = { nowISO: () => new Date(now()).toISOString(), nowMs: () => now(), uid: () => now().toString(36) + Math.random().toString(36).slice(2, 8) };
    const rules = R.withEnv(env, db, u.id, today);
    const before = new Map(db.tasks.map((t) => [t.id, JSON.stringify(t)]));
    const notifBefore = new Map(db.notifications.map((n) => [n.id, JSON.stringify(n)]));
    const fail = (status, error, extra = {}) => ({ ok: false, status, error, ...extra });
    const t = db.tasks.find((x) => x.id === String(body.id || ''));
    const a = String(body.act || '');
    let messages = [], undo = null;
    if (a === 'undoDelete') {
      const it = store.get('trash', String(body.trashId || ''));
      if (!it || it.type !== 'task' || it.deletedBy !== u.id) return fail(404, 'Already restored or no longer in the Trash');
      const changes = [];
      for (const x of (it.data && it.data.tasks) || []) if (!store.get('tasks', String(x.id))) changes.push({ kind: 'tasks', id: x.id, data: x });
      return { ok: true, changes, sysChanges: [{ kind: 'trash', id: it.id, del: true }], messages: [] };
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
      messages = rules.setDone(t, false);
    } else if (a === 'due') {
      if (!rules.can('editDates', t) || rules.amReadOnly(t)) return fail(403, 'Your role doesn’t allow changing dates');
      const v = body.due == null || body.due === '' ? null : String(body.due);
      if (v && !(/^\d{4}-\d{2}-\d{2}$/.test(v) && new Date(v + 'T00:00:00Z').toISOString().slice(0, 10) === v)) return fail(400, 'Not a date');
      messages = rules.setDue(t, v);
    } else if (a === 'delete') {
      if (!rules.can('deleteTask', t) || rules.amReadOnly(t)) return fail(403, 'Your role doesn’t allow deleting tasks');
      const r = rules.deleteTask(t);
      undo = r.item.id;
      messages = ['Moved to the Trash'];
    } else return fail(400, 'Unknown action');
    // what changed, as the website pushes it (each with the version it started from, merged on the server)
    const changes = [];
    const after = new Map(db.tasks.map((x) => [x.id, x]));
    for (const [id, was] of before) {
      const x = after.get(id);
      if (!x) changes.push({ kind: 'tasks', id, del: true });
      else if (JSON.stringify(x) !== was) changes.push({ kind: 'tasks', id, base: JSON.parse(was), data: x });
    }
    for (const n of db.notifications) {
      const was = notifBefore.get(n.id);
      if (!was) changes.push({ kind: 'notifications', id: n.id, data: n });
      else if (JSON.stringify(n) !== was) changes.push({ kind: 'notifications', id: n.id, base: JSON.parse(was), data: n });
    }
    for (const it of db.trash) changes.push({ kind: 'trash', id: it.id, data: it });
    return { ok: true, changes, messages, undo };
  }
  return { home, act };
}
