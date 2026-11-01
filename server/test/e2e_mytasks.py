"""The iPhone app's My Tasks from the server (/api/mytasks, web/rules.js) lists exactly the tasks the website's own My
Tasks does (Work.list) for every person and filter: All (open: Today · Next · Overdue · No due date) and Done (the last
30 days; the Overdue filter doesn't apply there); and each role gets its own filters."""
import asyncio, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18301; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.8-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            async def login(email):
                ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE, timezone_id='Asia/Dubai')
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3000)
                return ctx, pg, errs
            ctx, pg, _ = await login(ADMIN)
            people = await pg.evaluate("db.users.filter(u=>u.active!==false && !['finance_admin','finance_viewer'].includes(u.role) && !(u.role==='office_admin'&&!u.admin)).map(u=>({email:u.email, role:u.role, id:u.id}))")
            await ctx.close()
            compared = 0
            for p in people:
                ctx, pg, errs = await login(p['email'])
                info = await pg.evaluate("({ lead: Work.lead(), all: seesAll(), cd: isCD(), someone: (db.tasks.find(t=>(t.assignees||[]).length)||{assignees:[]}).assignees[0] || null })")
                want_f = ['due'] + (['people'] if info['lead'] else []) + (['ams'] if info['all'] else []) + (['assigned'] if info['cd'] else [])
                combos = [({}, ''), ({'due': 'late'}, 'due=late'), ({'due': 'today'}, 'due=today'), ({'due': 'week'}, 'due=week')]
                if info['lead'] and info['someone']: combos.append(({'people': [info['someone']]}, 'people=' + info['someone']))
                if info['all']: combos.append(({'team': True}, 'team=1'))
                if info['cd']: combos.append(({'assigned': True}, 'assigned=1'))
                combos.append(({'cd': True}, 'cd=1'))
                for F, q in combos:
                    for tab in ('all', 'done'):
                        exp = await pg.evaluate("""([F, tab]) => {
                          ui.workF = null; Object.assign(Work.f(), F);
                          if (tab === 'done' && F.due === 'late') Work.f().due = null;   // (Done: the Overdue filter doesn't apply)
                          const L = Work.list(), cut = Date.now() - 30*86400000, today = todayStr();
                          let ids;
                          if (tab === 'all') ids = L.filter(Work.openOf).filter((t) => !F.due || dueIn(t, F.due)).map((t) => t.id);
                          else ids = L.filter((t) => Work.doneAtOf(t) && new Date(Work.doneAtOf(t)).getTime() > cut && (!F.due || F.due === 'late' || dueIn(t, F.due))).map((t) => t.id);
                          ui.workF = null;
                          return ids.sort();
                        }""", [F, tab])
                        r = await pg.evaluate("(q) => fetch('/api/mytasks?' + q).then((r) => r.json())", f'tab={tab}&{q}')
                        h = r.get('home') or {}
                        got = sorted(c['id'] for g in h.get('groups', []) for c in g['cards'])
                        ok = got == exp and h.get('filters') == want_f
                        if not ok: print('   ', p['email'], tab, q, 'got', len(got), 'want', len(exp), h.get('filters'), want_f)
                        check(ok, f"{p['role']} {p['email']} · {tab} · {q or 'no filter'}: {len(got)} tasks")
                        compared += 1
                # the order: Today · Next · Overdue · No due date
                r = await pg.evaluate("fetch('/api/mytasks?tab=all').then((r) => r.json())")
                names = [g['name'] for g in r['home']['groups']]
                order = ['Today', 'Next', 'Overdue', 'No due date', 'All']
                check(names == sorted(names, key=order.index), f"{p['email']}: groups in order {names}")
                check(not errs, f"{p['email']}: no page errors {errs[:1]}")
                await ctx.close()
            check(compared > 40, f'{compared} lists compared')
            await b.close()
    finally:
        srv.terminate()
    print('FAILS', len(fails), fails)
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
