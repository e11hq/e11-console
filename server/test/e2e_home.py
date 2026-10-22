"""Home page: Account Managers / Admins get "Your created tasks", the month chart, schedule, checklist and
Team on time; Production / Social get Up next (checklist ticks, Next task, Submit for review), My pipeline
by Task Update, My week, Recent activity, CD reviews, Amendments to fix, Latest files and On-time streak."""
import asyncio, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18233; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
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
            b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            async def login(email):
                ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3500)
                await pg.evaluate("go('home')"); await pg.wait_for_timeout(300)
                return ctx, pg, errs

            # ---- Admin: layout A
            ctx, pg, errs = await login(ADMIN); E = pg.evaluate
            check(await pg.locator('.hm-lead').count() == 1, 'Admin gets the Account Manager home')
            check(await pg.locator('.hm-stat').count() == 3, 'three stat cards')
            await pg.click('.hm-tab[data-v="all"]'); await pg.wait_for_timeout(200)
            n = await pg.locator('.hm-lead .hm-row').count()
            want = await E("Math.min(6, topTasks().filter(t=>{const u=userById(t.createdBy); return !t.done && !!u && (u.role==='am'||isAdm(u));}).length)")
            check(n == want, f'All open lists the open tasks you created ({n} of {want})')
            for k, js in [('late', 't.due && t.due < todayStr()'), ('today', 't.due === todayStr()')]:
                await pg.click(f'.hm-tab[data-v="{k}"]'); await pg.wait_for_timeout(200)
                ids = await E("[...document.querySelectorAll('.hm-lead .hm-row')].map(r=>r.dataset.task)")
                ok = await E(f"[...document.querySelectorAll('.hm-lead .hm-row')].every(r=>{{const t=task(r.dataset.task); return {js};}})")
                cnt = await E(f"document.querySelector('.hm-tab[data-v=\"{k}\"] i').textContent")
                check(ok and len(ids) == min(6, int(cnt)), f'{k} tab lists only its tasks ({len(ids)} / {cnt})')
            await pg.click('.hm-tab[data-v="created"]'); await pg.wait_for_timeout(200)
            check('tasks created' in await pg.locator('.hm-big').inner_text(), 'chart switches to Tasks created')
            bars = await pg.locator('.hm-bar').count()
            check(bars == await E("new Date(new Date().getFullYear(), new Date().getMonth()+1, 0).getDate()"), f'one bar per day of the month ({bars})')
            # schedule day pick
            await pg.locator('.hm-day').first.click(); await pg.wait_for_timeout(200)
            check(await pg.locator('.hm-day.on').count() == 1 and await E("Home.st.day") is not None, 'picking a day in Schedule works')
            await pg.click('.hm-stat >> nth=0'); await pg.wait_for_timeout(300)
            check(await E("ui.view") == 'mytasks', 'stat card opens My Tasks')
            check(not errs, f'no page errors {errs}')
            await ctx.close()

            # ---- Production: layout C
            prod = None
            ctx, pg, errs = await login(ADMIN)
            prod = await pg.evaluate("(()=>{ const ids=new Set(db.tasks.filter(t=>!t.parentId&&!t.done).flatMap(t=>t.assignees||[])); const u=db.users.find(u=>u.role==='production'&&ids.has(u.id)); return u.email; })()")
            await ctx.close()
            ctx, pg, errs = await login(prod); E = pg.evaluate
            check(await pg.locator('.hm-member').count() == 1 and await pg.locator('.hm-lead').count() == 0, 'Production gets the Up next home')
            first = await E("Home.st.next"); t1 = await pg.locator('.hm-next h2').inner_text()
            if await pg.locator('[data-hm="next"]').count():
                await pg.click('[data-hm="next"]'); await pg.wait_for_timeout(200)
                check(await pg.locator('.hm-next h2').inner_text() != t1, 'Next task moves to the next one')
            # checklist tick on Up next
            hid = await E("document.querySelector('.hm-next [data-hm=\"open\"]').dataset.v")
            await E(f"(()=>{{ const t=task('{hid}'); if(!(t.checklist||[]).length){{ t.checklist=[{{id:'hc1',text:'Test item',done:false}}]; commit(); }} }})()"); await pg.wait_for_timeout(300)
            before = await E(f"task('{hid}').checklist[0].done")
            await pg.locator('.hm-next .hm-sub-i').first.click(); await pg.wait_for_timeout(300)
            check(await E(f"task('{hid}').checklist[0].done") != before, 'ticking the checklist on Up next saves it on the task')
            # pipeline lanes = Task Updates of my open tasks
            lanes = await E("[...document.querySelectorAll('.hm-lane')].map(l=>l.dataset.v)")
            ups = await E("[...new Set(myTop().filter(myOpen).map(t=>t.update||''))]")
            check(lanes and all(l in ups for l in lanes), f'pipeline lanes are your Task Updates {lanes}')
            if len(lanes) > 1:
                await pg.locator('.hm-lane').nth(1).click(); await pg.wait_for_timeout(200)
                ids = await E("[...document.querySelectorAll('.hm-lane-list [data-task]')].map(r=>task(r.dataset.task).update||'')")
                check(ids and all(x == lanes[1] for x in ids), 'clicking a lane lists its tasks')
            check(await pg.locator('.hm-cal > div').count() == 5, 'My week shows Monday to Friday')
            check(await pg.locator('.hm-rev').count() == 1, 'CD reviews card')
            am = await E("myTop().filter(myOpen).filter(t=>needsCD(t)&&reviewState(t)==='amend').length")
            check(await pg.locator('.hm-am').count() == am, f'Amendments to fix lists {am} tasks')
            # bottom: left column not shorter than right
            hl = await E("document.querySelector('.hm-grid > .hm-col').getBoundingClientRect().bottom")
            hr = await E("document.querySelector('.hm-grid > aside.hm-col').getBoundingClientRect().bottom")
            check(hl >= hr - 1, f'left column reaches the bottom of the right one ({hl:.0f} / {hr:.0f})')
            # Submit for review opens the dialog
            sub = pg.locator('.hm-next [data-hm="submit"]')
            if await sub.count():
                await sub.click(); await pg.wait_for_timeout(300)
                ok = await E(f"canSubmitNow(task('{hid}'))")
                check(await pg.locator('.sr-dlg').count() == 1 if ok else 'left To Do' in (await pg.locator('#toast-root').inner_text()) or await pg.locator('#toast-root .toast').count() > 0, 'Submit files for review opens the submit dialog (or explains why not yet)')
                await pg.keyboard.press('Escape'); await pg.wait_for_timeout(200)
                if await pg.locator('.sr-dlg').count(): await E("document.querySelector('#overlay-root').innerHTML=''")
            # open task from a pipeline row
            await pg.locator('.hm-lane-list [data-task]').first.click(); await pg.wait_for_timeout(400)
            check(await E("!!ui.taskId"), 'clicking a task opens it')
            await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'home_member.png'))
            check(not errs, f'no page errors {errs}')
            await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
