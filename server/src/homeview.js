// The iPhone app's Home straight from the server (iPhone app 25+): GET /api/home → the same model the app used to get
// from the page behind it (NativeHome in phone.js), worked out here with the same shared rules file (web/rules.js), from
// what this person may see (the same data their own app downloads). Read only.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

export function createHomeView({ webDir, now = () => Date.now() }) {
  const dir = webDir || path.resolve(here, '../../web');
  const file = path.join(dir, 'rules.js'), viewFile = path.join(dir, 'appview.js');
  let rules = null, view = null, loadedAt = '';
  // (read again when a file changes — a new version installed). The screens are web/appview.js — the same file the
  // iPhone app runs on its own copy of the data (iOS app data plan), so the two always agree.
  function loadBoth() {
    const m = fs.statSync(file).mtimeMs + ':' + fs.statSync(viewFile).mtimeMs;
    if (!rules || m !== loadedAt) {
      const both = vm.runInNewContext(`${fs.readFileSync(file, 'utf8')}; ${fs.readFileSync(viewFile, 'utf8')}; ({ E11Rules, E11AppView })`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN, encodeURIComponent });
      rules = both.E11Rules; view = both.E11AppView;
      loadedAt = m;
    }
  }
  function load() { loadBoth(); return rules; }
  function V() { loadBoth(); return view; }
  // data: what this person's own app downloads (visibleSnapshot in server.js) — the screens are web/appview.js's
  function home(u, data) { return V().home(load(), data, u.id, now); }
  // the app's My Tasks (GET /api/mytasks?tab=all|done&due=&people=a,b&ams=&team=1&assigned=1&cd=1)
  function myTasks(u, data, q) {
    return V().myTasks(load(), { ...data, users: data.users || [] }, u.id, now, { tab: q.get('tab'), due: q.get('due'), people: q.get('people') || '', ams: q.get('ams') || '', team: q.get('team') === '1', assigned: q.get('assigned') === '1', cd: q.get('cd') === '1' }, u);
  }
  // the app's Inbox (GET /api/inbox?tab=all|unread|mentions)
  function inbox(u, data, q) { return V().inbox(load(), data, u.id, now, q.get('tab'), u); }
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
    // the Inbox's: one read / unread, or all read (only this person's own)
    if (a === 'read' || a === 'unread' || a === 'readAll' || a === 'unreadList') {
      const mine = db.notifications.filter((n) => n.to === u.id && !/^claim/.test(n.kind || ''));   // (claims: on the computer)
      const changes = [];
      const set = (n, v) => { if (!!n.read !== v) { const base = JSON.parse(JSON.stringify(n)); n.read = v; changes.push({ kind: 'notifications', id: n.id, base, data: n }); } };
      if (a === 'readAll') mine.forEach((n) => set(n, true));
      // (the Inbox's Mark all unread: only the ones in the list on screen — Haris, 2026-11-01)
      else if (a === 'unreadList') { const ids = new Set(String(body.id || '').split(',').filter(Boolean).slice(0, 500)); mine.filter((n) => ids.has(n.id)).forEach((n) => set(n, false)); }
      else { const n = mine.find((x) => x.id === String(body.id || '')); if (!n) return fail(404, 'This update is no longer here'); set(n, a === 'read'); }
      return { ok: true, changes, messages: a === 'readAll' && changes.length ? ['All marked read'] : a === 'unreadList' && changes.length ? ['Marked unread'] : [] };
    }
    let messages = [], undo = null;
    if (a === 'undoDelete') {
      const it = store.get('trash', String(body.trashId || ''));
      if (!it || !['task', 'comment'].includes(it.type) || it.deletedBy !== u.id) return fail(404, 'Already restored or no longer in the Trash');
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
      if (!rules.canReopen(t)) return fail(403, 'Completed tasks are locked — only Admins can reopen them');
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
    } else if (['title', 'start', 'status', 'myPart', 'prio', 'check', 'needsCD', 'update', 'clientApproval', 'assign', 'guardian', 'addTag', 'removeTag', 'channels', 'addCheck', 'addSub', 'client', 'react', 'deleteComment', 'desc', 'submitReview', 'withdrawReview', 'comment', 'editComment', 'attach'].includes(a)) {
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
      else if (a === 'assign') { if (!rules.can('assign', t)) return fail(403, 'Your role doesn’t allow assigning'); r = rules.setAssignee(t, String(body.key || ''), !!body.value); }
      else if (a === 'guardian') { if (!rules.can('assign', t) || t.parentId) return fail(403, 'Your role doesn’t allow this'); r = rules.setGuardian(t, body.value ? String(body.value) : null); }
      else if (a === 'addTag') { if (!rules.can('addTag', t)) return fail(403, 'Your role doesn’t allow adding tags'); r = rules.addTag(t, body.value); }
      else if (a === 'removeTag') { if (!rules.can('removeTag', t)) return fail(403, 'Your role doesn’t allow removing tags'); r = rules.removeTag(t, String(body.value || '')); }
      else if (a === 'channels') { const u0 = (data.users || []).find((x) => x.id === u.id); if (!u0 || !(u0.role === 'admin' || u0.admin === true || u0.role === 'am' || u0.role === 'social') || t.parentId) return fail(403, 'Your role doesn’t allow this'); r = rules.setChannels(t, Array.isArray(body.value) ? body.value : []); }
      else if (a === 'addSub') { if (!rules.can('createTask', t) || t.parentId) return fail(403, 'Your role doesn’t allow adding subtasks'); r = rules.addSubtask(t, body.value); }
      else if (a === 'client') { if (!rules.can('editProject', t) || t.parentId || rules.idLocked(t)) return fail(403, 'The client can’t be changed'); r = rules.setClient(t, body.value ? String(body.value) : null); }
      else if (a === 'react') r = rules.toggleReaction(t, String(body.key || ''), String(body.value || ''));
      else if (a === 'deleteComment') { const d = rules.deleteComment(t, String(body.value || '')); if (d.error) return fail(409, d.error); undo = d.undo; r = d.messages; }
      else if (a === 'desc') { if (!rules.can('editDesc', t) || rules.idLocked(t)) return fail(403, 'The description can’t be changed'); r = rules.setDesc(t, body.html, body.text, true); }
      else if (a === 'submitReview') r = rules.submitReview(t, Array.isArray(body.files) ? body.files : []);
      else if (a === 'withdrawReview') r = rules.withdrawReview(t);
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
  // the app's native task page (GET /api/task?id=) — null: not there, or not for this person
  function taskPage(u, data, id) { return V().taskPage(load(), data, u.id, now, id); }
  // the app's native Comments (GET /api/comments?id=&thread=)
  function commentsFeed(u, data, id, thread) { return V().commentsFeed(load(), data, u.id, now, id, thread); }
  return { home, myTasks, inbox, act, taskPage, commentsFeed };
}
