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
  // (what of the Inbox reaches the iPhone — rules.js onPhone, the same as the app's Inbox)
  function onPhone(n, u) { return load().onPhone(n, u); }
  function V() { loadBoth(); return view; }
  // data: what this person's own app downloads (visibleSnapshot in server.js) — the screens are web/appview.js's
  function home(u, data) { return V().home(load(), data, u.id, now); }
  // the app's My Tasks (GET /api/mytasks?tab=all|done&due=&people=a,b&ams=&team=1&assigned=1&cd=1)
  function myTasks(u, data, q) {
    return V().myTasks(load(), { ...data, users: data.users || [] }, u.id, now, { tab: q.get('tab'), due: q.get('due'), people: q.get('people') || '', ams: q.get('ams') || '', team: q.get('team') === '1', assigned: q.get('assigned') === '1', cd: q.get('cd') === '1' }, u);
  }
  // the app's Inbox (GET /api/inbox?tab=all|unread|mentions)
  function inbox(u, data, q) { return V().inbox(load(), data, u.id, now, q.get('tab'), u); }
  // the app's Clients tab (GET /api/clients?view=list|client&id=&done=1)
  function clients(u, data, q) { return V().clients(load(), data, u.id, now, { view: q.get('view') === 'client' ? 'client' : 'list', id: q.get('id') || '', done: q.get('done') === '1' }); }
  // ---------- the app's Home actions (POST /api/home/act) ----------
  // Done / reopen, the due date, to the Trash and back — done here with the same shared rules the website uses, on the
  // same data this person's own app has (what they may see), so the activity lines, notifications and checks are
  // exactly the website's. Returns the changes to save (as the website would push them) and a short message.
  // body: { act: 'done' | 'reopen' | 'due' | 'delete' | 'undoDelete', id, due, clientApproval: 'yes' | 'none', trashId }
  // (the actions themselves are web/appview.js's homeAct — the same code the iPhone app runs on its own copy first, so a
  //  change shows at once and the server's answer agrees: Haris 2026-11-07)
  function act(u, data, body, store) {
    const env = { nowISO: () => new Date(now()).toISOString(), nowMs: () => now(), uid: () => now().toString(36) + Math.random().toString(36).slice(2, 8) };
    return V().homeAct(load(), data, u, body, env, store);
  }
  // the app's native task page (GET /api/task?id=) — null: not there, or not for this person
  function taskPage(u, data, id) { return V().taskPage(load(), data, u.id, now, id); }
  // the app's native Comments (GET /api/comments?id=&thread=)
  function commentsFeed(u, data, id, thread) { return V().commentsFeed(load(), data, u.id, now, id, thread); }
  return { home, myTasks, inbox, clients, act, taskPage, commentsFeed, onPhone };
}
