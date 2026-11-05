"""Part B step 7: opening an update without the page. The shared brain (web/appme-tasks.js, E11AppMe.notifOpen /
taskLinkOpen) against the page itself, in a page that is the iPhone app (its bridge faked, shell 30: the app's own task
page), for the owner, the CD, an Account Manager, Production, Social, a freelancer, the Office Admin and Finance:
- every kind of update as an Inbox row (app.js openNotif): comment, mention (in a comment, a reply, the description, an
  old one without a comment id), reply, review, review-wd, review-amend, review-ok, assigned, status, plan-*, asset,
  claim-*, daily, birthday, sched-cancel; a deleted task; a task in the Trash (a manager: the Trash with a search; not:
  a note); `read` is exactly what openNotif marks, `go` where the page goes (the app's task page and its tab / comment /
  thread, Review Requests' tab and submission, Content plans, Client Assets, Claims, the round-up, the Trash, toasts);
- a phone notification tapped before its update is in the copy (phone.js openFrom, by the push's own hint);
- a shared task link (TaskLink.open): one of theirs, not there, an Office Admin, Production asking the server first.
Then /api/home/act readList marks what notifOpen says, own only."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json, shutil
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT = 18367; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
AREEJ, CARINE, YOUSEF, SAM, ARSAL, AISH, RANIA = 'areej@e11-digital.com', 'carine@e11-digital.com', 'yousef@e11-digital.com', 'sam.rivera.design@gmail.com', 'arsal@e11-digital.com', 'aishwarya@e11-digital.com', 'rania.finance@e11-digital.com'
DATA = tempfile.mkdtemp()

# the iPhone app around the page (shell 30: the app's own task page)
BRIDGE = """window.__cap = { pages: [] };
window.webkit = { messageHandlers: { e11ios: { postMessage(raw) {
  const m = JSON.parse(raw), a = m.args || {};
  let r = { ok: true };
  if (m.cmd === 'appInfo') r = { ok: true, shell: 30 };
  else if (m.cmd === 'taskPage' && a.open) window.__cap.pages.push(a);
  else if (m.cmd === 'nativeSheet') r = { ok: true, index: -1 };
  setTimeout(() => window.__e11NativeReply && window.__e11NativeReply(m.id, r), 1);
} } } };"""

# the brain in the page; what the page does is caught (nothing is saved: persist does nothing)
SETUP = """(async () => {
  const src = await (await fetch('/appme-tasks.js', { cache: 'no-store' })).text(); (0, eval)(src);
  window.__sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  window.persist = () => {};
  const C = window.__obs = { reset() { Object.assign(C, { toasts: [], plans: [], clients: [], claims: [], daily: 0, sched: [], web: null, thread: null, desc: false }); __cap.pages = []; } };
  C.reset();
  const t0 = window.toast; window.toast = (m, ...x) => { C.toasts.push(m); };
  Plans.open = (id) => { C.plans.push(id); };
  const oc = window.openClient; window.openClient = (id, f) => { C.clients.push([id, f]); return oc(id, f); };
  Daily.show = () => { C.daily++; };
  Sched.openCancelled = (n) => { C.sched.push(n.schedId || null); };
  // Claims: as off the phone (on the phone the page only says "Claims are on the computer") — where it goes
  const co = Claims.openNotif;
  Claims.openNotif = (n) => {
    const d = Object.getOwnPropertyDescriptor(Phone, 'on'); Object.defineProperty(Phone, 'on', { get: () => false, configurable: true });
    const g = window.go; let to = null; window.go = (v) => { to = v; };
    try { co(n); } finally { window.go = g; Object.defineProperty(Phone, 'on', d); }
    const d0 = todayStr(), cm = Number(d0.slice(8, 10)) >= 28 ? new Date(Date.UTC(+d0.slice(0, 4), +d0.slice(5, 7), 1)).toISOString().slice(0, 7) : d0.slice(0, 7);
    C.claims.push(to ? Object.assign({ to: 'claim', page: to, claimId: n.claimId || null }, to === 'fin-reimb' ? { month: n.month || cm } : {}) : null);
  };
  // the app's task page: the thread / description the website would open with it
  const w = NativeTask.wants;
  NativeTask.wants = (id, ft) => { C.thread = ui.pendingThread || null; C.desc = !!ui.focusDesc; return w(id, ft); };
  // (Finance people have no phone pages: the website's task page — where it would open, caught before it's drawn)
  const ot = window.openTask;
  window.openTask = (id, ft) => {
    if (isOffice() || Phone.on) return ot(id, ft);
    const f = ui.cmFocus && ui.cmFocus.task === id ? ui.cmFocus : null;
    C.web = Object.assign({ to: 'task', id, tab: ui.forceTab === 'comments' || f ? 'comments' : 'details', focus: f ? f.id : '' }, ui.pendingThread ? { thread: ui.pendingThread } : {}, ui.focusDesc ? { desc: true } : {});
    ui.forceTab = null; ui.pendingThread = null; ui.cmFocus = null; ui.focusComment = null; ui.focusDesc = false;
  };
  for (let i = 0; i < 40 && !NativeTask.on(); i++) await __sleep(100);
  return { phone: Phone.on, native: NativeTask.on(), me: currentUserId };
})()"""

# the records each person gets, made in their own copy (a task of theirs, a reply, reviews, plans, clients, claims, the Trash)
MAKE = """() => {
  const me = currentUserId, now = Date.now(), at = (m) => new Date(now - m * 60000).toISOString();
  const others = db.users.filter((u) => u.id !== me && u.active !== false).map((u) => u.id);
  const [o1, o2, o3] = others;
  let T = db.tasks.find((t) => !t.parentId && t.projectId && !t.done && (t.comments || []).length);
  if (!T) { T = { id: 'tk-own', title: 'Own task', projectId: (db.projects[0] || {}).id || null, sectionId: null, assignees: [me], createdBy: o1, comments: [{ id: 'c-own', authorId: o1, at: at(50), html: 'hi', text: 'hi', parentId: null }], activity: [] }; db.tasks.push(T); }
  const c1 = T.comments[T.comments.length - 1];
  T.comments.push({ id: 'c-reply', authorId: o2, at: at(20), html: 'a reply', text: 'a reply', parentId: c1.id, reactions: {} });
  const T2 = { id: 'tk-rev', title: 'Review task', projectId: T.projectId, sectionId: T.sectionId, assignees: [o1, o2], createdBy: me, needsCD: true, comments: [], activity: [],
    reviews: [{ id: 'rv-old', by: o1, state: 'approved', at: at(60 * 24 * 3), decidedAt: at(60 * 24 * 2), files: [] }, { id: 'rv-new', by: o1, state: 'pending', at: at(30), files: [] },
              { id: 'rv-dec', by: o2, state: 'amend', at: at(60 * 24 * 20), decidedAt: at(60 * 24 * 19), files: [] }, { id: 'rv-wd', by: o3, state: 'withdrawn', at: at(40), files: [] }] };
  db.tasks.push(T2);
  const T3 = db.tasks.find((t) => t.id !== T.id && !t.parentId && t.id !== 'tk-rev') || T;
  db.trash = db.trash || [];
  db.trash.push({ id: 'tr-x', type: 'task', key: 'tasks:gone-2', data: { tasks: [{ id: 'gone-2', title: 'Trashed thing' }] }, deletedAt: at(10), deletedBy: o1 });
  const pl = (db.plans || [])[0], cl = (db.clients || []).find((c) => (c.folders || []).length), cl2 = (db.clients || []).find((c) => c !== cl && Array.isArray(c.folders));   // (Finance's copy: clients without their folders — the page's openNotif can't open those)
  const cm = (db.claims || []).find((c) => c.userId !== me) || (db.claims || [])[0];
  const N = [];
  const add = (id, n) => N.push(Object.assign({ id, to: me, from: o1, text: n.kind, snippet: '', at: at(N.length + 1), read: false }, n));
  add('n-comment', { kind: 'comment', taskId: T.id, commentId: c1.id, from: c1.authorId });
  add('n-comment-old', { kind: 'comment', taskId: T.id, from: c1.authorId, at: at(25) });
  add('n-mention-reply', { kind: 'mention', taskId: T.id, commentId: 'c-reply', from: o2 });
  add('n-mention-desc', { kind: 'mention', taskId: T3.id, from: 'u-nobody' });
  add('n-reply', { kind: 'comment', taskId: T.id, commentId: 'c-reply', from: o2, text: 'replied in a thread on' });
  add('n-review', { kind: 'review', taskId: 'tk-rev', from: o1, at: at(29) });
  add('n-review-old', { kind: 'review', taskId: 'tk-rev', from: o1, at: at(60 * 24 * 3 - 1) });
  add('n-review-dec', { kind: 'review', taskId: 'tk-rev', from: o2, at: at(60 * 24 * 20 - 1) });
  add('n-review-wd', { kind: 'review-wd', taskId: 'tk-rev', from: o3 });
  add('n-amend', { kind: 'review-amend', taskId: T.id, commentId: c1.id });
  add('n-amend-gone', { kind: 'review-amend', taskId: T3.id, commentId: 'c-nothere' });
  add('n-review-ok', { kind: 'review-ok', taskId: T3.id });
  add('n-assigned', { kind: 'assigned', taskId: T3.id });
  add('n-status', { kind: 'status', taskId: T3.id });
  if (pl) { add('n-plan-ok', { kind: 'plan-ok', planId: pl.id }); add('n-plan-changes', { kind: 'plan-changes', planId: pl.id }); add('n-plan-client', { kind: 'plan-client', planId: pl.id }); add('n-plan-tasks', { kind: 'plan-tasks', planId: pl.id }); }
  add('n-plan-gone', { kind: 'plan-ok', planId: 'pl-gone' });
  if (cl) { add('n-asset', { kind: 'asset', clientId: cl.id, folderId: cl.folders[0].id }); add('n-asset-2', { kind: 'asset', clientId: cl.id, folderId: 'cf-gone' }); }
  if (cl2) add('n-asset-other', { kind: 'asset', clientId: cl2.id, folderId: null });
  add('n-asset-gone', { kind: 'asset', clientId: 'cl-gone', folderId: null });
  const cid = cm ? cm.id : 'cl-x';
  add('n-claim', { kind: 'claim', taskId: null, claimId: cid, month: cm ? cm.month : '2026-10' });
  add('n-claim-ok', { kind: 'claim-ok', taskId: null, claimId: cid, month: cm ? cm.month : '2026-10' });
  add('n-claim-paid', { kind: 'claim-paid', taskId: null, claimId: 'cl-y' });
  add('n-claim-hand', { kind: 'claim-hand', taskId: null });
  add('n-daily', { kind: 'daily', from: null, title: 'Good morning' });
  add('n-daily-2', { kind: 'daily', from: null, title: 'Good morning' });
  add('n-birthday', { kind: 'birthday', from: o2 });
  add('n-birthday-2', { kind: 'birthday', from: o2 });
  add('n-sched', { kind: 'sched-cancel', schedId: 'sc-1', taskId: T.id, from: null });
  add('n-gone', { kind: 'comment', taskId: 'gone-1', commentId: 'x' });
  add('n-trash', { kind: 'assigned', taskId: 'gone-2' });
  add('n-other', { kind: 'comment', taskId: T.id, to: o1 });   // (someone else's — never marked by this person)
  db.notifications = db.notifications.filter((n) => n.to !== me).concat(N);
  return { ids: N.filter((n) => n.to === me).map((n) => n.id), T: T.id, c1: c1.id, T3: T3.id, pl: pl ? pl.id : null, cl: cl ? cl.id : null, f: cl ? cl.folders[0].id : null, cm: cid };
}"""

# open each on both sides; the page's moves put as the brain's go
CASE = """async (cs) => {
  const out = [], me = currentUserId, C = __obs, clean = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
  const pageGo = (view0) => {
    const p = __cap.pages[__cap.pages.length - 1];
    if (p) { const f = (p.focus || '').split('~'); return Object.assign({ to: 'task', id: p.open, tab: p.tab, focus: f[1] || '' }, C.thread ? { thread: C.thread } : {}, C.desc ? { desc: true } : {}); }
    if (C.web) return C.web;
    if (ui.taskId) return { web: ui.taskId };   // (the website's task page drawn — shouldn't happen here)
    if (ui.view === 'reviews' && view0 !== 'reviews') return { to: 'review', id: ui.rvFocus ? ui.rvFocus.id : null, tab: ui.rrTab === 'zz' ? null : ui.rrTab };
    if (C.plans.length) return { to: 'plan', id: C.plans[0] };
    if (C.claims.length) return C.claims[0];
    if (C.daily) return { to: 'daily' };
    if (C.sched.length) return { to: 'schedCancel', id: C.sched[0] };
    if (ui.view === 'client' && C.clients.length) return { to: 'assets', client: ui.clientId, folder: ui.folderId || null };
    if (ui.view === 'trash') return { to: 'trash', q: ui.trashQ, toast: C.toasts[0] };
    if (C.toasts.length) return C.toasts[0] === 'Not in the Office Admin view' ? { toast: C.toasts[0], home: true } : { toast: C.toasts[0] };
    return null;
  };
  for (const c of cs) {
    // everything of theirs unread, Home, nothing caught
    db.notifications.forEach((n) => { if (n.to === me) n.read = false; });
    if (ui.taskId) closeDetail();
    ui.pendingThread = null; ui.focusDesc = false; ui.rvFocus = null; ui.rrTab = 'zz'; ui.trashQ = '';
    go('home'); await __sleep(60);
    C.reset();
    const data = clean(db), now = Date.now();
    let app, before = new Set(db.notifications.filter((n) => n.read).map((n) => n.id));
    if (c.link) app = { read: [], go: E11AppMe.taskLinkOpen(E11Rules, data, me, now, c.link, c.peeked).go };
    else app = E11AppMe.notifOpen(E11Rules, data, me, now, c.nid || null, c.hint || null);
    if (c.tap) window.__e11PushTap(Object.assign({ taskId: null, nid: null }, c.tap));
    else if (c.link) window.__e11PushTap({ taskId: c.link, nid: null });
    else if (window.__e11Inbox) window.__e11Inbox({ ev: 'open', id: c.nid }); else openNotif(c.nid);
    await __sleep(c.wait || 250);
    const read = db.notifications.filter((n) => n.read && !before.has(n.id)).map((n) => n.id);
    out.push({ c, app: clean(app), page: { read, go: clean(pageGo('home')) } });
  }
  return out;
}"""

def diff(a, b, path=''):
    out = []
    if type(a) != type(b): return [f'{path}: {json.dumps(a)[:200]} != {json.dumps(b)[:200]}']
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b: out.append(f'{path}.{k}: only in {"app" if k in a else "page"}')
            else: out += diff(a[k], b[k], f'{path}.{k}')
    elif isinstance(a, list):
        if len(a) != len(b): out.append(f'{path}: {len(a)} items != {len(b)}')
        for i, (x, y) in enumerate(zip(a, b)): out += diff(x, y, f'{path}[{i}]')
    elif a != b: out.append(f'{path}: {json.dumps(a)[:200]} != {json.dumps(b)[:200]}')
    return out[:12]

async def main():
    subprocess.run(['fuser', '-k', f'{PORT}/tcp'], stderr=subprocess.DEVNULL)
    env = {**os.environ, 'DATA_DIR': DATA, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': ROOT + '/web', 'APP_VERSION': '1.6.1-test.1'}
    srv = subprocess.Popen(['node', ROOT + '/server/src/index.js'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ok = []
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    def same(a, b, what):
        d = diff(a, b); check(not d, what, '\n   ' + '\n   '.join(d))
    def req(path, who, body=None):
        r = urllib.request.Request(BASE + path, method='POST' if body is not None else 'GET', data=json.dumps(body).encode() if body is not None else None, headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
        return json.loads(urllib.request.urlopen(r).read())
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE + '/api/health'); break
            except Exception: time.sleep(0.1)
        req('/api/me', ADMIN); req('/api/sample/reset', ADMIN, {})
        all_tasks = [t['id'] for t in req('/api/snapshot', ADMIN)['data']['tasks'] if not t.get('parentId')]
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            async def open_as(who):
                ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, base_url=BASE, timezone_id='Asia/Dubai')
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': who, 'url': BASE}])
                await ctx.add_init_script(BRIDGE)
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(4500)
                s = await pg.evaluate(SETUP)
                return ctx, pg, errs, s

            PEOPLE = [(ADMIN, 'owner'), (CARINE, 'the CD'), (AREEJ, 'an AM'), (YOUSEF, 'Production'), (AISH, 'Social'), (SAM, 'a freelancer'), (ARSAL, 'the Office Admin'), (RANIA, 'Finance')]
            for who, role in PEOPLE:
                ctx, pg, errs, s = await open_as(who)
                check((s['phone'] or who == RANIA) and s['native'], f'{role}: the page is the iPhone app with its own task page' + (' (Finance: no phone pages)' if who == RANIA else ''), s)
                k = await pg.evaluate(MAKE)
                # every update, as an Inbox row
                cases = [{'nid': i} for i in k['ids']]
                # tapped before it's in the copy: by the push's hint
                hints = [
                    {'taskId': k['T'], 'kind': 'review'}, {'taskId': k['T'], 'kind': 'review-wd'},
                    {'taskId': k['T'], 'kind': 'comment', 'commentId': k['c1']}, {'taskId': k['T'], 'kind': 'mention', 'commentId': k['c1']},
                    {'taskId': k['T'], 'kind': 'review-amend', 'commentId': k['c1']}, {'taskId': k['T'], 'kind': 'mention'},
                    {'taskId': k['T'], 'kind': 'status'}, {'taskId': 'gone-1', 'kind': 'comment', 'commentId': 'x'},
                    *([{'kind': 'asset', 'clientId': k['cl'], 'folderId': k['f']}, {'kind': 'asset', 'clientId': k['cl'], 'folderId': 'cf-gone'}] if k['cl'] else []), {'kind': 'asset', 'clientId': 'cl-gone'},
                    {'kind': 'claim'}, {'kind': 'claim-ok'}, {'kind': 'plan-ok', 'planId': k['pl']}, {'kind': 'plan-ok', 'planId': 'pl-gone'},
                    {'kind': 'daily'}, {'kind': 'birthday'},
                ]
                for n, h in enumerate(hints):
                    nid = f'late-{n}'
                    cases.append({'nid': nid, 'hint': h, 'tap': {'nid': nid, **{x: h.get(x) for x in ('taskId', 'kind', 'commentId', 'clientId', 'folderId', 'planId')}}})
                # shared links
                theirs = set(await pg.evaluate("db.tasks.map((t) => t.id)"))
                cases += [{'link': k['T']}, {'link': 'tk-not-there'}]
                res = await pg.evaluate(CASE, cases)
                for r in res:
                    c = r['c']
                    lbl = f"{role}: {('link ' + c['link']) if c.get('link') else ('tapped early ' + json.dumps(c['hint'])) if c.get('hint') else c['nid']}"
                    app = r['app'] or {}
                    want_go = app.get('go')
                    if want_go and want_go.get('to') == 'birthday': want_go = None   # (the page: just read)
                    if want_go and want_go.get('peek'): want_go = {'toast': want_go['toast']}   # (no peek for a task that isn't anywhere)
                    same(want_go, r['page']['go'], lbl + ': where it goes')
                    same(sorted(app.get('read') or []), sorted(r['page']['read']), lbl + f": read ({len(r['page']['read'])})")
                    if os.environ.get('SHOW'): print('   ', role, c.get('nid') or c.get('link'), json.dumps(r['page']['go'])[:150], len(r['page']['read']))
                    if c.get('hint'): check(app.get('wait') is True, lbl + ': waits for the update')
                # Production / a freelancer: a task that isn't theirs — the brain asks for the server first; then the same
                other = next((t for t in all_tasks if t not in theirs), None)
                if who in (YOUSEF, SAM) and other:
                    data = await pg.evaluate("JSON.parse(JSON.stringify(db))")
                    first = await pg.evaluate("(id) => E11AppMe.taskLinkOpen(E11Rules, JSON.parse(JSON.stringify(db)), currentUserId, Date.now(), id).go", other)
                    check(first.get('peek') is True and first.get('id') == other, f'{role}: a task not theirs — ask the server first', first)
                    got = await pg.evaluate("""async (id) => { __obs.reset(); go('home'); await __sleep(50); window.__e11PushTap({ taskId: id, nid: null }); await __sleep(2500);
                      const p = __cap.pages.pop(); return { page: p ? { to: 'task', id: p.open, tab: p.tab, focus: (p.focus || '').split('~')[1] || '' } : __obs.toasts[0] ? { toast: __obs.toasts[0] } : null,
                        app: E11AppMe.taskLinkOpen(E11Rules, JSON.parse(JSON.stringify(db)), currentUserId, Date.now(), id, true).go }; }""", other)
                    same(got['app'], got['page'], f'{role}: … after the server answered ({json.dumps(got["page"])[:60]})')
                check(not errs, f'{role}: no page errors', errs)
                await ctx.close()
            await b.close()

        # ---------- /api/home/act readList: what notifOpen marks, own only ----------
        d = req('/api/snapshot', AREEJ)['data']
        mine = [n for n in d['notifications'] if n['to'] == 'u-lina']
        node = subprocess.run(['node', '-e', """
const R = require(process.argv[1]), M = require(process.argv[2]); const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
d.notifications.forEach((n) => { if (n.to === 'u-lina') n.read = false; });
const n = d.notifications.find((x) => x.to === 'u-lina' && x.taskId);
process.stdout.write(JSON.stringify({ n: n && n.id, r: n ? M.notifOpen(R, d, 'u-lina', Date.now(), n.id) : null }));""", ROOT + '/web/rules.js', ROOT + '/web/appme-tasks.js'], input=json.dumps(d), capture_output=True, text=True)
        o = json.loads(node.stdout or '{}') if not node.returncode else {}
        check(o.get('r') and o['r'].get('read'), 'readList: notifOpen in node gives a read list', node.stderr[-400:])
        if o.get('r'):
            ids = o['r']['read']; tid = next(n['taskId'] for n in mine if n['id'] == o['n'])
            req('/api/home/act', AREEJ, {'act': 'unreadList', 'id': ','.join(n['id'] for n in mine), 'from': 'inbox'})
            others = [n['id'] for n in req('/api/snapshot', ADMIN)['data']['notifications'] if n['to'] != 'u-lina' and not n.get('read')][:3]
            r = req('/api/home/act', AREEJ, {'act': 'readList', 'ids': ids + others, 'from': 'inbox'})
            after = {n['id']: n for n in req('/api/snapshot', AREEJ)['data']['notifications']}
            check(r.get('ok') and all(after[i]['read'] for i in ids) and all(not after[n['id']]['read'] for n in mine if n['id'] not in ids)
                  and set(ids) == {n['id'] for n in mine if n.get('taskId') == tid}, f'readList: marks the {len(ids)} update(s) on its task, nothing else', json.dumps(r)[:300])
            snap = {n['id']: n for n in req('/api/snapshot', ADMIN)['data']['notifications']}
            check(all(not snap[i]['read'] for i in others if i in snap), "readList: someone else's stay as they are")
    finally:
        srv.terminate()
        shutil.rmtree(DATA, ignore_errors=True)
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
