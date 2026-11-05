"""Part B step 6: New task, Home's search and My Tasks' filters without the page. The shared brain (web/appme-tasks.js,
E11AppMe) against what the page sends the iPhone app today, in a page that is the iPhone app (its bridge faked, shell 26):
- New task: the form's args (formSheet), the Client and Assign to sheets (nativeSheet) and what each row does (formSet),
  the Assign to row after ticks; for the owner (Super Admin), an Account Manager on their client's page, the CD, Production,
  a freelancer, Social, the Office Admin;
- Home's search (home {search}) for words, clients, people, flags, a typo and nothing;
- My Tasks: signal() (mytasks), the Due date / People / Account managers sheets and what each row sets, a chip's ✕,
  Assigned to me and Clear all, on both tabs.
Then the server's tkNew (server/src/appact-tasks.js, a Node run over the same records) against the page's submit
(__e11Form submit): the same records (the task, its activity, Inbox updates), the same refusals; and through the route
(POST /api/app/act): rights, the answer's id, kv 'app-act-tasks' = 'off'."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json, re, shutil, sqlite3
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT = 18361; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
AREEJ, CARINE, YOUSEF, SAM, ARSAL, AISH, RANIA = 'areej@e11-digital.com', 'carine@e11-digital.com', 'yousef@e11-digital.com', 'sam.rivera.design@gmail.com', 'arsal@e11-digital.com', 'aishwarya@e11-digital.com', 'rania.finance@e11-digital.com'
DATA = tempfile.mkdtemp(); DBFILE = os.path.join(DATA, 'db', 'e11.sqlite'); WORK = tempfile.mkdtemp()

DUMP = """import { openStore } from %s; const s = openStore(process.argv[2]); process.stdout.write(JSON.stringify(s.snapshot().data));""" % json.dumps(ROOT + '/server/src/store.js')
RUN = """import fs from 'node:fs'; import { createTaskActs } from %s;
const [pre, who, body] = [JSON.parse(fs.readFileSync(process.argv[2], 'utf8')), process.argv[3], JSON.parse(process.argv[4])];
const copy = (v) => (v == null ? null : JSON.parse(JSON.stringify(v)));
const store = { get: (k, id) => copy(k === 'meta' ? (id === 'main' ? pre.meta : null) : (pre[k] || []).find((x) => String(x.id) === String(id))), list: (k) => copy(pre[k] || []), rev: () => 1, kv: { get: () => null, set: () => {} } };
const acts = createTaskActs({ store, now: () => Date.now() });
const u = pre.users.find((x) => x.email === who);
process.stdout.write(JSON.stringify(acts.tkNew(u, body)));""" % json.dumps(ROOT + '/server/src/appact-tasks.js')
open(os.path.join(WORK, 'dump.mjs'), 'w').write(DUMP); open(os.path.join(WORK, 'run.mjs'), 'w').write(RUN)

# the iPhone app around the page (shell 26: native sheets and forms, the app's own Home and My Tasks)
BRIDGE = """window.__cap = { form: null, sets: [], sheets: [], home: [], mytasks: [], closed: [] };
window.webkit = { messageHandlers: { e11ios: { postMessage(raw) {
  const m = JSON.parse(raw), c = window.__cap, a = m.args || {};
  let r = { ok: true };
  if (m.cmd === 'appInfo') r = { ok: true, shell: 26 };
  else if (m.cmd === 'formSheet') { c.form = a; return; }   // (the form stays open)
  else if (m.cmd === 'formSet') c.sets.push(a);
  else if (m.cmd === 'formClose') c.closed.push(a);
  else if (m.cmd === 'nativeSheet') { c.sheets.push(a); r = { ok: true, index: -1 }; }
  else if (m.cmd === 'home' && a.search) c.home.push(a.search);
  else if (m.cmd === 'mytasks') c.mytasks.push(a);
  setTimeout(() => window.__e11NativeReply && window.__e11NativeReply(m.id, r), 1);
} } } };"""

# the brain in the page, the sheets' items kept, a person / a sheet put the same way on both sides
SETUP = """(async () => {
  const src = await (await fetch('/appme-tasks.js', { cache: 'no-store' })).text(); (0, eval)(src);
  if (!window.__wrapped) { const o = NativeSheet.open; NativeSheet.open = (a, items, opts) => { window.__items = items; return o(a, items, opts); }; window.__wrapped = true; }
  window.__sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  window.__data = async () => (await (await fetch('/api/snapshot', { cache: 'no-store' })).json()).data;
  // (a person: the page's photo is a loaded picture, the brain's its file — compared as "a photo")
  window.__pp = (p) => (!p ? null : p.photo || p.initials === '' ? 'photo' : { initials: p.initials, color: p.color });
  window.__sheet = (s) => !s ? null : ({ search: s.search || null, empty: s.empty || null, multi: !!s.multi,
    sections: (s.sections || []).map((x) => ({ header: x.header || null, rows: x.rows.map((r) => ({ label: r.label, sub: r.sub || '', checked: !!r.checked, multi: !!r.multi, find: r.find || '', person: __pp(r.person), act: r.i >= 0 })) })) });
  return { phone: Phone.on, me: currentUserId };
})()"""

NEWTASK = """async ([view, pid]) => {
  const out = {};
  const data = await __data(), me = currentUserId, now = Date.now(), B = E11AppMe;
  __cap.form = null; __cap.sets = []; __cap.sheets = [];
  if (view === 'project') { ui.view = 'project'; ui.projectId = pid; } else { ui.view = view; }
  Phone.quickAdd();
  await __sleep(2600);
  out.pageForm = __cap.form ? JSON.parse(JSON.stringify(__cap.form)) : null;
  if (out.pageForm && out.pageForm.assign) out.pageForm.assign.person = __pp(out.pageForm.assign.person);
  const b = B.newTaskForm(E11Rules, data, me, now, { view, projectId: pid });
  out.appForm = b ? JSON.parse(JSON.stringify(b.args)) : null;
  if (out.appForm && out.appForm.assign) out.appForm.assign.person = __pp(out.appForm.assign.person);
  if (!b || !out.pageForm) return out;
  const state = b.state;
  // Client: the sheet, and what every row sets on the form
  __e11Form({ key: 'new-task', ev: 'pick', field: 'client' }); await __sleep(400);
  const items = __items, ps = __cap.sheets.pop();
  const bc = B.newTaskClients(E11Rules, data, me, now, state);
  out.clients = { page: __sheet(ps), app: __sheet(bc.sheet) };
  const prow = ps.sections.flatMap((s) => s.rows), brow = bc.sheet.sections.flatMap((s) => s.rows);
  out.clientActs = [];
  prow.forEach((r, n) => { __cap.sets = []; items[r.i].run(); const got = __cap.sets.pop() || {}; delete got.key; out.clientActs.push({ page: got, app: brow[n] ? bc.acts[brow[n].i].form : null }); });
  // pick the second client (or No client), on both sides
  const pickN = Math.min(2, prow.length - 1);
  items[prow[pickN].i].run(); state.client = bc.acts[brow[pickN].i].client;
  out.picked = state.client;
  if (!state.canAssign) return Object.assign(out, { state });
  // Assign to: the sheet, which person each row ticks, then two ticks and the row's new look
  __e11Form({ key: 'new-task', ev: 'pick', field: 'assign' }); await __sleep(2600);
  const pitems = __items, pp = __cap.sheets.pop();
  const bp = B.newTaskPeople(E11Rules, data, me, now, state);
  out.people = { page: __sheet(pp), app: __sheet(bp.sheet) };
  const raw = NativeSheet.rows(pitems).flatMap((s) => s.rows), bprow = bp.sheet.sections.flatMap((s) => s.rows);
  out.peopleActs = raw.map((r, n) => ({ page: r.personUid ? { toggle: r.personUid } : r.label === 'Nobody yet' ? { none: true } : null, app: bprow[n] ? bp.acts[bprow[n].i] : null }));
  const ticks = bprow.filter((r) => bp.acts[r.i].toggle && bp.acts[r.i].toggle !== me && bp.acts[r.i].toggle !== (data.meta || {}).cdUserId).slice(1, 3);
  for (const r of ticks) {
    __cap.sets = [];
    const n = bprow.indexOf(r);
    pitems[raw[n].i].run(); await __sleep(2400);
    const id = bp.acts[r.i].toggle; state.who = state.who.includes(id) ? state.who.filter((x) => x !== id) : state.who.concat(id);
    const got = (__cap.sets.pop() || {}).assign || null;
    const mine = B.newTaskWho(E11Rules, data, me, now, state);
    out.who = (out.who || []).concat([{ page: got && { label: got.label, person: __pp(got.person) }, app: { label: mine.label, person: __pp(mine.person) } }]);
  }
  out.state = state;
  return out;
}"""

SEARCH = """async (qs) => {
  const data = await __data(), out = [];
  for (const q of qs) {
    __cap.home = [];
    __e11Home({ ev: 'find', q }); await __sleep(50);
    out.push({ q, page: JSON.parse(JSON.stringify(__cap.home.pop() || null)), app: JSON.parse(JSON.stringify(E11AppMe.search(E11Rules, data, currentUserId, Date.now(), q))) });
  }
  return out;
}"""

MYTASKS = """async (cases) => {
  const data = await __data(), me = currentUserId, now = Date.now(), B = E11AppMe, out = [];
  const clean = (x) => JSON.parse(JSON.stringify(x));
  go('mytasks'); await __sleep(300);
  const set = (F) => { ui.workF = Object.assign({ created: null, due: null, finished: false, cd: false, people: [], ams: [], team: false, assigned: false }, clean(F)); };
  const signal = async () => { __cap.mytasks = []; window.__e11MyTasksResend(); await __sleep(450); const s = __cap.mytasks.filter((x) => x.show).pop(); if (s) delete s.light; return s ? clean(s) : null; };
  for (const [F, tab] of cases) {
    set(F); ui.myTasksTab = tab === 'done' ? 'done' : 'todo';
    const r = { F, tab, page: await signal(), app: clean(B.myTasksSignal(E11Rules, data, me, now, Work.f(), tab)), menus: [], ops: [] };
    // the filter sheets and what each row sets
    for (const k of (r.page ? r.page.buttons.map((x) => x.k) : []).filter((k) => k !== 'assigned')) {
      __cap.sheets = [];
      workMenu(document.body, k); await __sleep(300);
      const ps = __cap.sheets.pop(), items = __items, bm = B.myTasksFilterMenu(E11Rules, data, me, now, k, clean(Work.f()));
      const m = { k, page: __sheet(ps), app: __sheet(bm.sheet), acts: [] };
      const prow = ps.sections.flatMap((s) => s.rows), brow = bm.sheet.sections.flatMap((s) => s.rows);
      prow.forEach((row, n) => {
        const F0 = Work.f(), keep = JSON.stringify(F0);
        items[row.i].run();
        m.acts.push({ page: clean(Work.f()), app: brow[n] ? bm.acts[brow[n].i].set : null });
        Object.assign(F0, JSON.parse(keep)); ui.workF = F0;
      });
      r.menus.push(m);
    }
    // a chip's ✕, Assigned to me, Clear all
    const ops = (r.page ? r.page.chips : []).map((c) => ({ chip: { act: c.act, id: c.id } })).concat([{ assigned: true }, { reset: true }]);
    for (const op of ops) {
      set(F);
      const want = clean(B.myTasksFilters(E11Rules, data, me, now, clean(Work.f()), op).filters);
      if (op.chip) __e11MyTasks({ ev: 'chip', act: op.chip.act, id: op.chip.id }); else if (op.assigned) __e11MyTasks({ ev: 'filter', k: 'assigned' }); else __e11MyTasks({ ev: 'reset' });
      r.ops.push({ op, page: clean(Work.f()), app: want });
    }
    out.push(r);
  }
  set({}); ui.myTasksTab = 'todo';
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

def node(script, *args):
    r = subprocess.run(['node', '--no-warnings', os.path.join(WORK, script), *args], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr[-2000:])
    return json.loads(r.stdout)
def dump(): return node('dump.mjs', DBFILE)

ISO = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$')
def norm(v, new_ids):
    if isinstance(v, str): return '<time>' if ISO.match(v) else '<new>' if v in new_ids else v
    if isinstance(v, list): return [norm(x, new_ids) for x in v]
    if isinstance(v, dict):
        # (an activity line's own id is new on each side)
        return {k: ('<id>' if k == 'id' and 'actor' in v else norm(x, new_ids)) for k, x in v.items()}
    return v
def index(data):
    out = {}
    for k, v in data.items():
        if k == 'meta': out[('meta', 'main')] = v
        else:
            for x in v: out[(k, str(x['id']))] = x
    return out
def rows_of(pre, post):
    a, b = index(pre), index(post)
    new_ids = {i for (k, i) in b if (k, i) not in a}
    rows = []
    for key in sorted(set(a) | set(b)):
        x, y = a.get(key), b.get(key)
        if json.dumps(x, sort_keys=True) == json.dumps(y, sort_keys=True): continue
        rows.append(json.dumps([key[0], '<new>' if key[1] in new_ids else key[1], None if y is None else norm(y, new_ids)], sort_keys=True))
    return sorted(rows)
def applied(pre, changes):
    post = json.loads(json.dumps(pre))
    for ch in changes:
        lst = post.setdefault(ch['kind'], [])
        j = next((n for n, x in enumerate(lst) if str(x['id']) == str(ch['id'])), None)
        if j is None: lst.append(ch['data'])
        else: lst[j] = ch['data']
    return post

async def main():
    subprocess.run(['fuser', '-k', f'{PORT}/tcp'], stderr=subprocess.DEVNULL)
    env = {**os.environ, 'DATA_DIR': DATA, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': ROOT + '/web', 'APP_VERSION': '1.6.1-test.1'}
    srv = subprocess.Popen(['node', ROOT + '/server/src/index.js'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ok = []
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    def same(a, b, what):
        d = diff(a, b); check(not d, what, '\n   ' + '\n   '.join(d))
    def post(path, who, body):
        req = urllib.request.Request(BASE + path, method='POST', data=json.dumps(body).encode(), headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
        return json.loads(urllib.request.urlopen(req).read())
    def act(who, body): return post('/api/app/act', who, {'ev': 'tkNew', **body})
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE + '/api/health'); break
            except Exception: time.sleep(0.1)
        urllib.request.urlopen(urllib.request.Request(BASE + '/api/me', headers={'X-Dev-Email': ADMIN}))
        post('/api/sample/reset', ADMIN, {})
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

            async def submit(pg, who, ev, body, what, want_ok=True):
                """the page's submit and the server's tkNew from the same records"""
                await pg.evaluate("persist(0)"); await pg.wait_for_timeout(1500)
                pre = dump(); p = os.path.join(WORK, 'pre.json'); open(p, 'w').write(json.dumps(pre))
                mine = node('run.mjs', p, who, json.dumps(body))
                await pg.evaluate("() => { __cap.sets = []; __cap.closed = []; }")
                await pg.evaluate("(ev) => __e11Form({ key: 'new-task', ev: 'submit', ...ev })", ev)
                await pg.wait_for_timeout(2500)
                after = dump()
                alert = await pg.evaluate("(__cap.sets.find((x) => x.alert) || {}).alert || null")
                me = next(x for x in pre['users'] if x['email'] == who)
                site = [r for r in rows_of(pre, after) if not r.startswith(json.dumps(['users', me['id']])[:-1])]
                srv_rows = rows_of(pre, applied(pre, mine['changes'])) if mine.get('ok') else []
                check(site == srv_rows, f'{what}: the same records ({len(site)})', '\n   only on the website: ' + '\n            '.join(r for r in site if r not in srv_rows) + '\n   only on the server:  ' + '\n            '.join(r for r in srv_rows if r not in site))
                check(bool(mine.get('ok')) == want_ok and (want_ok or mine.get('error') == alert), f'{what}: {"done" if want_ok else "refused: " + str(mine.get("error"))}', f'server {json.dumps(mine)[:300]} page alert {alert}')
                if want_ok:
                    tid = mine['answer']['id']
                    check(any(c['kind'] == 'tasks' and c['id'] == tid for c in mine['changes']), f'{what}: answer.id is the new task')
                return mine

            def form_checks(r, who, label):
                same(r['appForm'], r['pageForm'], f'{label}: the form\'s args')
                if not r.get('pageForm'): return
                same(r['clients']['app'], r['clients']['page'], f'{label}: the Client sheet')
                same([x['app'] for x in r['clientActs']], [x['page'] for x in r['clientActs']], f'{label}: what each client row sets ({len(r["clientActs"])})')
                if 'people' in r:
                    same(r['people']['app'], r['people']['page'], f'{label}: the Assign to sheet')
                    same([x['app'] for x in r['peopleActs']], [x['page'] for x in r['peopleActs']], f'{label}: who each row ticks ({len(r["peopleActs"])})')
                    same([x['app'] for x in r.get('who', [])], [x['page'] for x in r.get('who', [])], f'{label}: the Assign to row after ticks ({len(r.get("who", []))})')

            QS = ['kia', 'Ford', 'frod', 'overdue', 'urgent', 'review kia', 'zahir', 'social post', 'zzqqxx', '', '   ', 'deepal campaign', 'me']
            FCASES = [({}, 'all'), ({'due': 'late'}, 'all'), ({'due': 'week', 'people': ['u-ali', 'u-maya']}, 'all'), ({'ams': ['u-lina'], 'people': ['u-omar']}, 'all'),
                      ({'team': True, 'cd': True}, 'all'), ({'assigned': True, 'due': 'today'}, 'done'), ({'ams': ['u-lina', 'u-lana'], 'team': False}, 'done')]

            # ---------- per person: the form, its sheets, search, My Tasks, then the submit ----------
            PEOPLE = [(ADMIN, 'home', None), (AREEJ, 'project', 'p-kia'), (CARINE, 'mytasks', None), (YOUSEF, 'home', None), (SAM, 'home', None), (AISH, 'home', None), (ARSAL, 'home', None)]
            for who, view, pid in PEOPLE:
                ctx, pg, errs, s = await open_as(who)
                check(s['phone'], f'{who}: the page is the phone')
                r = await pg.evaluate(NEWTASK, [view, pid])
                form_checks(r, who, f'{who} ({view})')
                if not r.get('pageForm'):
                    check(r['appForm'] is None, f'{who}: no New task for them on either side')
                    pre = dump(); p = os.path.join(WORK, 'pre.json'); open(p, 'w').write(json.dumps(pre))
                    mine = node('run.mjs', p, who, json.dumps({'title': 'Not mine', 'projectId': '', 'who': []}))
                    check(mine.get('ok') is False and mine.get('status') == 403, f'{who}: tkNew refused', json.dumps(mine)[:200])
                else:
                    st = r['state']
                    body_desc = 'See https://e11.example/brief?x=1&y=2\nand <b>the</b> “notes”'
                    ev = {'title': f'New from {who.split("@")[0]}', 'desc': body_desc, 'due': r['pageForm']['due'] or '2026-12-01', 'cd': bool(r['pageForm'].get('cd'))}
                    body = {'title': ev['title'], 'projectId': st['client'], 'due': ev['due'], 'desc': ev['desc'], 'who': st['who'], 'cd': ev['cd'], 'view': view, 'ctxProjectId': pid or ''}
                    await submit(pg, who, ev, body, f'{who}: New task ({len(st["who"])} assigned, client {st["client"] or "none"}, CD {ev["cd"]})')
                # search
                for x in await pg.evaluate(SEARCH, QS):
                    same(x['app'], x['page'], f'{who}: search “{x["q"]}” ({(x["page"] or {}).get("total")} found)')
                # My Tasks (not for the Office Admin)
                if who != ARSAL:
                    for x in await pg.evaluate(MYTASKS, FCASES):
                        lbl = f'{who}: My Tasks {json.dumps(x["F"])} {x["tab"]}'
                        same(x['app'], x['page'], lbl + ': signal')
                        for m in x['menus']:
                            same(m['app'], m['page'], f'{lbl}: the {m["k"]} sheet')
                            same([a['app'] for a in m['acts']], [a['page'] for a in m['acts']], f'{lbl}: what each {m["k"]} row sets ({len(m["acts"])})')
                        same([o['app'] for o in x['ops']], [o['page'] for o in x['ops']], f'{lbl}: chips ✕ / Assigned to me / Clear all ({len(x["ops"])})')
                check(not errs, f'{who}: no page errors', errs)
                await ctx.close()

            # ---------- more submits: the owner — no client, nobody, CD review on/off; the CD ticked with CD review ----------
            ctx, pg, errs, s = await open_as(ADMIN)
            async def fresh(view='home', pid=None):
                return await pg.evaluate(NEWTASK, [view, pid])
            r = await fresh()
            # (the picker chose a client; tick the CD by hand on both sides)
            await pg.evaluate("""async () => { __e11Form({ key: 'new-task', ev: 'pick', field: 'assign' }); await __sleep(2600);
              const it = __items, rows = NativeSheet.rows(it).flatMap((s) => s.rows); const r = rows.find((x) => x.personUid === (db.meta.cdUserId)); if (r) it[r.i].run(); await __sleep(300); }""")
            st = r['state']
            await submit(pg, ADMIN, {'title': 'Needs the CD', 'desc': '', 'due': '', 'cd': True}, {'title': 'Needs the CD', 'projectId': st['client'], 'due': '', 'desc': '', 'who': st['who'] + ['u-karim'], 'cd': True}, 'owner: CD review on with the CD assigned', want_ok=False)
            await submit(pg, ADMIN, {'title': 'CD does it', 'desc': '', 'due': '', 'cd': False}, {'title': 'CD does it', 'projectId': st['client'], 'due': '', 'desc': '', 'who': st['who'] + ['u-karim'], 'cd': False}, 'owner: the CD assigned, CD review off')
            r = await fresh('project', 'p-ford')
            await pg.evaluate("async () => { __e11Form({ key: 'new-task', ev: 'pick', field: 'client' }); await __sleep(400); __items[0].run(); }")   # (No client)
            st = r['state']
            await submit(pg, ADMIN, {'title': 'Just mine', 'desc': '', 'due': '', 'cd': True}, {'title': 'Just mine', 'projectId': '', 'due': '', 'desc': '', 'who': st['who'], 'cd': True}, 'owner: no client, CD review asked (off: no client)')
            check(not errs, 'owner: no page errors', errs)
            await ctx.close()
            await b.close()

        # ---------- through the route ----------
        r = act(AREEJ, {'title': '  Route task ', 'projectId': 'p-kia', 'due': '2026-12-03', 'desc': 'x', 'who': ['u-ali'], 'cd': True})
        t = next((x for x in dump()['tasks'] if x['id'] == r.get('id')), None)
        check(r.get('ok') is True and t and t['title'] == 'Route task' and t['assignees'] == ['u-ali'] and t['needsCD'] is True and t['createdBy'] == 'u-lina'
              and any(c['kind'] == 'tasks' for c in r.get('changes', [])), 'route: an AM makes a task in their client (answer.id, the task back)', json.dumps(r)[:400])
        check(any(n.get('taskId') == r.get('id') and n['to'] == 'u-ali' and n['kind'] == 'assigned' for n in dump()['notifications']), 'route: the person assigned gets an Inbox update')
        r = act(AREEJ, {'title': 'Not her client', 'projectId': 'p-ford', 'who': []}); check(r.get('ok') is False, 'route: an AM can\'t start a task in another AM\'s client', json.dumps(r)[:200])
        r = act(ADMIN, {'title': '', 'projectId': ''}); check(r.get('ok') is False and r.get('error') == 'Give the task a name', 'route: no title refused', json.dumps(r)[:200])
        r = act(ADMIN, {'title': 'x', 'who': ['u-lina']}); check(r.get('ok') is False, 'route: an AM can\'t be assigned', json.dumps(r)[:200])
        r = act(YOUSEF, {'title': 'x'}); check(r.get('ok') is False and r.get('error') == 'Your role can’t do this', 'route: Production can\'t create', json.dumps(r)[:200])
        r = act(RANIA, {'title': 'x'}); check(r.get('ok') is False, 'route: Finance can\'t create', json.dumps(r)[:200])
        r = act(ADMIN, {'title': 'Mine', 'op': 'op-1'}); r2 = act(ADMIN, {'title': 'Mine', 'op': 'op-1'})
        check(r.get('ok') and r2.get('id') == r.get('id') and sum(1 for x in dump()['tasks'] if x['title'] == 'Mine') == 1, 'route: a retry (same op) makes one task')
        con = sqlite3.connect(DBFILE, timeout=10); con.execute("insert or replace into kv (key, value) values ('app-act-tasks', 'off')"); con.commit(); con.close()
        r = act(ADMIN, {'title': 'Off'}); check(r.get('off') is True, 'route: kv app-act-tasks off → back to the page', json.dumps(r)[:200])
    finally:
        srv.terminate()
        shutil.rmtree(DATA, ignore_errors=True); shutil.rmtree(WORK, ignore_errors=True)
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
