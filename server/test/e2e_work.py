"""Account Managers and Admins: Home shows "Your created tasks", My Tasks lists the tasks they created with
filters (Created date, People, Assigned to me; Admin also Account managers), My Day uses created tasks
(Admin: "E11 Day" with every AM's and Admin's tasks). Other roles keep their assigned-task pages."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18199; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.7-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def login(email, vp=(1300, 800)):
            ctx = await b.new_context(viewport={'width': vp[0], 'height': vp[1]}, base_url=BASE, has_touch=vp[0] < 500)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(4000)
            return ctx, pg, errs
        E = None
        # ---- Admin
        ctx, pg, errs = await login(ADMIN); E = pg.evaluate
        am = await E("(db.users.find(u=>u.role==='am')||{}).id")
        amEmail = await E(f"userById('{am}').email")
        # give the AM a couple of created tasks and the admin one, made today / long ago
        await E(f"""(()=>{{ const p=db.projects[0].id; const prod=db.users.find(u=>u.role==='production').id;
          const mk=(id,by,created,ass)=>{{const t=newTaskObj?null:null;}};
          const base=db.tasks[0];
          const add=(id,title,by,created,ass,due)=>{{ const t=JSON.parse(JSON.stringify(base)); Object.assign(t,{{id,title,createdBy:by,createdAt:created,assignees:ass,done:false,completedAt:null,parentId:null,projectId:p,due,partsDone:{{}},reviews:[],attachments:[],comments:[],activity:[]}}); db.tasks.push(t); }};
          add('wA1','AM task today','{am}',new Date().toISOString(),[prod],todayStr());
          add('wA2','AM task old','{am}','2025-01-05T10:00:00.000Z',[],null);
          add('wH1','Admin created today',currentUserId,new Date().toISOString(),[prod],todayStr());
          add('wH2','Admin created old',currentUserId,'2025-02-01T10:00:00.000Z',[],addDays(todayStr(),3));
          commit(); return true; }})()""")
        await pg.wait_for_timeout(800)
        await E("go('home')"); await pg.wait_for_timeout(300)
        check('Team’s created tasks' in await pg.locator('.hm-lead .hm-card h2').first.inner_text(), 'Admin home says "Team’s created tasks"')
        rows = await E("[...document.querySelectorAll('.hm-lead .hm-row')].map(r=>{const u=userById(task(r.dataset.task).createdBy); return !!u && (u.role==='am'||isAdm(u));})")
        check(rows and all(rows), f'it lists tasks created by AMs and Admins ({len(rows)})')
        check(await pg.locator('.hm-proj').count() == await E("db.projects.length"), 'Admin home shows all projects')
        await pg.click('[data-action="home-view-all"]'); await pg.wait_for_timeout(300)
        check(await E("ui.view") == 'mytasks', 'View all opens My Tasks')
        ids = await E("Work.list().map(t=>t.id)")
        check('wH1' in ids and 'wH2' in ids and 'wA1' not in ids and all(await E("Work.list().map(t=>t.createdBy===currentUserId)")), 'My Tasks shows only the Admin’s created tasks')
        check(await pg.locator('.wf-bar [data-action="wf-ams"]').count() == 1, 'Admin has the Account managers filter')
        await pg.click('.wf-bar [data-action="wf-created"]'); await pg.wait_for_timeout(200)
        await pg.locator('.wf-menu .mi', has_text='Today').click(); await pg.wait_for_timeout(300)
        ids = await E("Work.list().map(t=>t.id)")
        check('wH1' in ids and 'wH2' not in ids, 'Created date: Today filters the list')
        check(await pg.locator('.wf-chip', has_text='Created: Today').count() == 1, 'and shows a removable chip')
        await pg.click('[data-action="mt-tab"][data-tab="done"]'); await pg.wait_for_timeout(200)
        check(await pg.locator('.wf-chip', has_text='Created: Today').count() == 1, 'the filter stays on the Done tab')
        await pg.click('[data-action="mt-tab"][data-tab="todo"]'); await pg.wait_for_timeout(200)
        await pg.click('[data-action="wf-clear-created"]'); await pg.wait_for_timeout(200)
        check('wH2' in await E("Work.list().map(t=>t.id)"), 'removing the chip clears the filter')
        await pg.click('.wf-bar [data-action="wf-people"]'); await pg.wait_for_timeout(200)
        heads = await E("[...document.querySelectorAll('.wf-menu .wf-mh')].map(h=>h.textContent)")
        check(heads[:1] == ['Production'] and set(heads) <= {'Production', 'Social', 'Freelancers'}, f'People list is grouped by role {heads}')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'work_people.png'))
        await pg.locator('.wf-menu .wf-person').first.click(); await pg.wait_for_timeout(300)
        sel = await E("Work.f().people[0]")
        check(all(await E(f"Work.list().map(t=>t.assignees.includes('{sel}'))")), 'People filter shows only tasks assigned to that person')
        await pg.click('[data-action="wf-reset"]'); await pg.wait_for_timeout(200)
        await pg.click('.wf-bar [data-action="wf-ams"]'); await pg.wait_for_timeout(200)
        await pg.locator('.wf-menu .wf-person').first.click(); await pg.wait_for_timeout(300)
        ids = await E("Work.list().map(t=>t.id)")
        check('wA1' in ids and 'wA2' in ids and 'wH1' not in ids, 'Account managers filter shows that AM’s created tasks')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'work_admin.png'))
        await pg.click('[data-action="wf-reset"]'); await pg.click('[data-action="wf-assigned"]'); await pg.wait_for_timeout(200)
        check(all(await E("Work.list().map(t=>onMyList(t))")), '"Assigned to me" switches back to tasks assigned to them')
        await E("go('today')"); await pg.wait_for_timeout(300)
        check(await pg.locator('#title-area').inner_text() == 'E11 Day' and 'E11 Day' in await pg.locator('.nav-item[data-nav="today"]').inner_text(), 'Admin’s My Day is called E11 Day')
        rows = await E("[...document.querySelectorAll('#content .task-row')].map(r=>r.dataset.task)")
        check('wA1' in rows and 'wH1' in rows, 'E11 Day shows tasks created by AMs and Admins')
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        # ---- Account Manager
        ctx, pg, errs = await login(amEmail); E = pg.evaluate
        await E("go('home')"); await pg.wait_for_timeout(300)
        rows = await E("[...document.querySelectorAll('.hm-lead .hm-row')].map(r=>r.dataset.task)")
        mineOnly = await E("[...document.querySelectorAll('.hm-lead .hm-row')].every(r=>task(r.dataset.task).createdBy===currentUserId)")
        check(rows and mineOnly and 'wH1' not in rows, 'AM home lists only their created tasks')
        projs = await E("[...document.querySelectorAll('.hm-proj[data-project]')].map(c=>c.dataset.project)")
        want = await E("[...new Set(db.tasks.filter(t=>!t.parentId&&t.createdBy===currentUserId).map(t=>t.projectId))].filter(id=>proj(id))")
        check(set(projs) == set(want), f'AM home shows only projects with their tasks {projs} vs {want}')
        await E("go('mytasks')"); await pg.wait_for_timeout(300)
        check(await pg.locator('.wf-bar [data-action="wf-ams"]').count() == 0 and await pg.locator('.wf-bar').count() == 1, 'AM gets the filters, without Account managers')
        await E("go('today')"); await pg.wait_for_timeout(300)
        check(await pg.locator('#title-area').inner_text() == 'My Day', 'AM keeps "My Day"')
        rows = await E("[...document.querySelectorAll('#content .task-row')].map(r=>r.dataset.task)")
        check('wA1' in rows and 'wH1' not in rows, 'AM My Day shows their created tasks')
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        # ---- AM on the phone
        ctx, pg, errs = await login(amEmail, (390, 844)); E = pg.evaluate
        await E("go('mytasks')"); await pg.wait_for_timeout(400)
        check(await pg.locator('#content .wf-bar').count() == 1, 'phone My Tasks has the filters')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'work_phone.png'))
        await ctx.close()
        # ---- Production keeps assigned lists, no filters
        prodEmail = None
        ctx, pg, errs = await login(ADMIN); prodEmail = await pg.evaluate("db.users.find(u=>u.role==='production').email"); await ctx.close()
        ctx, pg, errs = await login(prodEmail); E = pg.evaluate
        await E("go('mytasks')"); await pg.wait_for_timeout(300)
        check(await pg.locator('.wf-bar').count() == 0 and all(await E("Work.list().map(t=>onMyList(t))")), 'Production keeps their assigned tasks, no filters')
        await E("go('home')"); await pg.wait_for_timeout(300)
        check(await pg.locator('.hm-member .hm-next').count() == 1 and await pg.locator('.hm-lead').count() == 0, 'Production gets the Up next home')
        await ctx.close()
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
