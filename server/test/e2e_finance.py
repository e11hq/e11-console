"""Finance people: own layout (Dashboard / Projects / Expenses), dashboard counts + monthly graph + overview,
Finance Admin sets task Finance status and adds subscriptions / reimbursements / extra expenses (with invoice),
Expenses page + all-transactions list with month filter and 50 per page. Viewer only looks; Admin can look."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18202; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
FA = 'fina@e11-digital.com'; FV = 'finv@e11-digital.com'
SHOTS = tempfile.gettempdir()
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def push(who, changes):
    req = urllib.request.Request(BASE + '/api/push', method='POST', data=json.dumps({'changes': changes}).encode(), headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
    return json.loads(urllib.request.urlopen(req).read())
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.7-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    # this test builds its own Finance numbers: clear the sample's Finance statuses, finished jobs and records
    snap = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/snapshot', headers={'X-Dev-Email': ADMIN})).read())['data']
    push(ADMIN, [{'kind': 'users', 'id': 'u-tmpfa', 'data': {'id': 'u-tmpfa', 'email': 'tmpfa@e11-digital.com', 'role': 'finance_admin', 'active': True, 'setup': True}}])
    push('tmpfa@e11-digital.com', [{'kind': 'finance', 'id': r['id'], 'del': True} for r in snap['finance']])
    clean = []
    for t in snap['tasks']:
        if t['id'].startswith('smp-fin-'): clean.append({'kind': 'tasks', 'id': t['id'], 'del': True})
        elif t.get('finance'): n = dict(t); n['finance'] = None; n['financeAt'] = None; clean.append({'kind': 'tasks', 'id': t['id'], 'base': t, 'data': n})
    push(ADMIN, clean)
    snap = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/snapshot', headers={'X-Dev-Email': ADMIN})).read())['data']
    now = time.strftime('%Y-%m')
    users = [{'id': 'u-fa', 'email': FA, 'name': 'Fatima Finance', 'role': 'finance_admin', 'active': True, 'setup': True},
             {'id': 'u-fv', 'email': FV, 'name': 'Victor Viewer', 'role': 'finance_viewer', 'active': True, 'setup': True}]
    tasks = [t for t in snap['tasks'] if not t.get('parentId')][:6]
    ch = [{'kind': 'users', 'id': u['id'], 'data': u} for u in users]
    statuses = ['Invoiced', 'Invoiced', 'LPO Pending', 'Retainer', 'To be invoiced', 'Quote to be sent']
    for t, s in zip(tasks, statuses):
        n = dict(t); n['finance'] = s; n['financeAt'] = time.strftime('%Y-%m-%dT10:00:00.000Z')
        ch.append({'kind': 'tasks', 'id': t['id'], 'base': t, 'data': n})
    # one invoiced last month
    t7 = [t for t in snap['tasks'] if not t.get('parentId')][6]
    lm = time.strftime('%Y-%m', time.localtime(time.time() - 32 * 86400))
    n = dict(t7); n['finance'] = 'Invoiced'; n['financeAt'] = lm + '-10T10:00:00.000Z'
    ch.append({'kind': 'tasks', 'id': t7['id'], 'base': t7, 'data': n})
    push(ADMIN, ch)
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def login(email, vp=(1300, 860)):
            ctx = await b.new_context(viewport={'width': vp[0], 'height': vp[1]}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e) + ' @ ' + str(getattr(e, 'stack', ''))[:400]))
            await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(5, 5); await pg.wait_for_timeout(3500)
            return ctx, pg, errs
        # ---------------- Finance Admin
        ctx, pg, errs = await login(FA); E = pg.evaluate
        check(await E("ui.view") == 'fin-dash' and await E("document.body.classList.contains('fin-mode')"), 'Finance Admin opens on the Finance Dashboard')
        nav = await E("[...document.querySelectorAll('#sidebar .nav-item')].filter(a=>a.offsetParent).map(a=>a.textContent.trim())")
        check([x.rstrip('0123456789') for x in nav] == ['Dashboard', 'Clients', 'Expenses', 'Reimbursements'], f'their sidebar: {nav}')
        check(not await pg.locator('#topbar .search').is_visible(), 'no task search')
        stats = await E("[...document.querySelectorAll('.fa-stat')].map(s=>[s.querySelector('.fa-sl').textContent.trim(), +s.querySelector('.fa-n').textContent])")
        check(dict(stats) == {'Quote to be sent': 1, 'LPO Pending': 1, 'Invoiced': 3, 'Retainer': 1, 'To be invoiced': 1}, f'5 status counts {stats}')
        bars = await E("[...document.querySelectorAll('.fa-pt em')].map(e=>+e.textContent.split('·')[1].trim().split(' ')[0])")
        check(len(bars) == 6 and bars[-1] == 2 and bars[-2] == 1, f'Monthly Graph (Invoiced) last 6 months {bars}')
        await pg.click('[data-fin-graph="Retainer"]'); await pg.wait_for_timeout(200)
        check(await E("[...document.querySelectorAll('.fa-pt em')].map(e=>+e.textContent.split('·')[1].trim().split(' ')[0]).pop()") == 1, 'graph tabs switch status')
        await pg.locator('.fa-pt').nth(5).hover(); await pg.wait_for_timeout(200)
        check(await pg.locator('.fa-pt').nth(5).locator('em').is_visible(), 'hovering a point shows its month and count')
        await pg.click('[data-fin-span="12"]'); await pg.wait_for_timeout(200)
        check(await pg.locator('.fa-pt').count() == 12, 'Last 12 months switch')
        await pg.click('.fa-stat[data-fin-graph="Invoiced"]'); await pg.wait_for_timeout(200)
        check('Invoiced' in await pg.locator('.fa-big span').inner_text(), 'clicking a status card shows it on the graph')
        ov = await E("[document.querySelector('.fa-hero-n').textContent, document.querySelector('.fa-hero .fa-chip').className, document.querySelector('.fa-hero .fa-chip').textContent]")
        check(ov[0] == '2' and 'good' in ov[1] and '100%' in ov[2], f'Invoiced this month: 2, up 100% vs last month {ov}')
        await pg.screenshot(path=os.path.join(SHOTS, 'fin_dash.png'), full_page=True)
        # Projects: set a status
        await E("go('fin-projects')"); await pg.wait_for_timeout(200)
        await pg.click('[data-fin-proj="LPO Pending"]'); await pg.wait_for_timeout(300)
        check(await pg.locator('.fp-row').count() == 1, 'Projects filter by status')
        await pg.click('[data-fin-proj="all"]'); await pg.wait_for_timeout(200)
        check(await pg.locator('[data-fin-set]').count() == 0, 'Finance Admin sees Finance status but can’t change it')
        await pg.screenshot(path=os.path.join(SHOTS, 'fin_projects.png'))
        # Add pages via the Me menu
        await pg.click('#me-chip'); await pg.wait_for_timeout(200)
        items = await E("[...document.querySelectorAll('.menu .mi')].map(e=>e.textContent.trim())")
        check(all(x in items for x in ['Add subscriptions', 'Add Staff Reimbursements', 'Add Extra Expense']) and 'Team members' not in items, f'Me menu {items}')
        await pg.locator('.menu .mi', has_text='Add subscriptions').click(); await pg.wait_for_timeout(300)
        await pg.click('[data-fin-new="sub"]'); await pg.wait_for_timeout(200)
        await pg.fill('.fin-form [name="name"]', 'Adobe CC'); await pg.fill('.fin-form [name="amount"]', '1200.5'); await pg.select_option('.fin-form [name="day"]', '1')
        async with pg.expect_file_chooser() as fc:
            await pg.click('.fin-form [data-pick]')
        f = await fc.value
        inv = os.path.join(SHOTS, 'invoice.pdf'); open(inv, 'wb').write(b'%PDF-1.4 test')
        await f.set_files(inv); await pg.wait_for_timeout(1500)
        check('invoice.pdf' in await pg.locator('.fin-inv-name').inner_text(), 'invoice attached in the form')
        await pg.click('.fin-form button[type="submit"]'); await pg.wait_for_timeout(500)
        sub = await E("db.finance.find(x=>x.type==='sub')")
        check(sub and sub['amount'] == 1200.5 and sub['invoices'].get(now, {}).get('path', '').startswith('Finance/'), f'subscription saved with this month’s invoice')
        check(await E(f"Fin.transactions().filter(x=>x.kind==='sub').length") == 1, 'recorded as this month’s payment (billing day already passed)')
        await pg.screenshot(path=os.path.join(SHOTS, 'fin_subs.png'))
        # reimbursement with an extra person
        await E("go('fin-reimb')"); await pg.wait_for_timeout(200)
        await pg.click('[data-fin-new="reimb"]'); await pg.wait_for_timeout(200)
        await pg.fill('.fin-form [name="newPerson"]', 'Omar Driver'); await pg.click('.fin-form [data-addp]'); await pg.wait_for_timeout(200)
        check(await E("document.querySelector('.fin-form [name=who]').selectedOptions[0].textContent") == 'Omar Driver', 'an extra person can be added to the list')
        await pg.fill('.fin-form [name="amount"]', '250')
        await pg.click('.fin-form .fin-date'); await pg.wait_for_timeout(200)
        check(await pg.locator('.dp-pop').count() == 1, 'payment date opens the calendar')
        await pg.locator('.dp-day:not(.out)', has_text='1').first.click(); await pg.wait_for_timeout(200)
        await pg.screenshot(path=os.path.join(SHOTS, 'fin_reimb_form.png'))
        await pg.click('.fin-form button[type="submit"]'); await pg.wait_for_timeout(400)
        r = await E("db.finance.find(x=>x.type==='reimb')")
        check(r and r['amount'] == 250 and r['date'] == now + '-01' and r.get('personId'), f'reimbursement saved {r and r["date"]}')
        # extra expenses (many, for paging)
        await E("go('fin-extra')"); await pg.wait_for_timeout(200)
        await pg.click('[data-fin-new="expense"]'); await pg.wait_for_timeout(200)
        await pg.fill('.fin-form [name="name"]', 'Studio lights'); await pg.fill('.fin-form [name="amount"]', '')
        await pg.click('.fin-form button[type="submit"]'); await pg.wait_for_timeout(200)
        check('AED' in await pg.locator('.fin-form .dlg-err').inner_text(), 'amount must be a number')
        await pg.fill('.fin-form [name="amount"]', '3000'); await pg.click('.fin-form button[type="submit"]'); await pg.wait_for_timeout(300)
        await E(f"""(()=>{{ for(let i=0;i<60;i++) db.finance.push({{id:'x'+i,type:'expense',name:'Item '+i,amount:10,date:'{lm}-0'+(1+i%9),createdAt:nowISO()}}); persist(0); }})()""")
        await pg.wait_for_timeout(1200)
        await E("go('fin-expenses')"); await pg.wait_for_timeout(300)
        total = await E("document.querySelector('.fa-stat .fa-n').textContent")
        check(total == 'AED 4,450.50', f'this month’s spending: {total}')
        check(await pg.locator('.fa > .fa-card .fx-row').count() == 5, 'recent 5 transactions')
        ends = await E("[...document.querySelectorAll('.fa-end b')].map(e=>e.textContent)")
        check(len(ends) == 3 and 'AED 3,000.00' in ends, f'cash flow overview: one curve per kind {ends}')
        await pg.click('[data-fin-exm="prev"]'); await pg.wait_for_timeout(200)
        check(await E("document.querySelector('.fa-stat .fa-n').textContent") == 'AED 600.00', 'Last month switch')
        await pg.click('[data-fin-exm="cur"]'); await pg.wait_for_timeout(200)
        await pg.screenshot(path=os.path.join(SHOTS, 'fin_expenses.png'), full_page=True)
        await pg.click('.fa > .fa-card [data-fin-all="all"]'); await pg.wait_for_timeout(300)
        check(await pg.locator('.fin-list .fx-row').count() == 50 and 'Page 1 of 2' in await pg.locator('.fin-pages').inner_text(), 'View all: 50 per page')
        await pg.select_option('[data-fin-month]', lm); await pg.wait_for_timeout(200)
        check(await pg.locator('.fin-list .fx-row').count() == 50 and '60 transactions' in await pg.locator('.fl-sum').inner_text(), 'month filter')
        await pg.click('[data-fin-page="1"]'); await pg.wait_for_timeout(200)
        check(await pg.locator('.fin-list .fx-row').count() == 10, 'page 2')
        await pg.screenshot(path=os.path.join(SHOTS, 'fin_list.png'))
        check(not errs, f'no page errors {errs}')
        await pg.wait_for_timeout(1000)
        await ctx.close()
        # ---------------- Viewer
        ctx, pg, errs = await login(FV); E = pg.evaluate
        check(await E("db.finance.length") > 60, 'Viewer sees the records')
        await E("go('fin-projects')"); await pg.wait_for_timeout(200)
        check(await pg.locator('[data-fin-set]').count() == 0, 'Viewer cannot change Finance status')
        await pg.click('#me-chip'); await pg.wait_for_timeout(200)
        check(await pg.locator('.menu .mi', has_text='Add subscriptions').count() == 0, 'no Add pages for a Viewer')
        await pg.keyboard.press('Escape'); await E("closeMenus(); go('fin-subs')"); await pg.wait_for_timeout(200)
        check(await E("ui.view") == 'fin-dash', 'Viewer is sent back from Add pages')
        await E("go('home')"); await pg.wait_for_timeout(200)
        check(await E("ui.view") == 'fin-dash', 'Finance people can’t open the task app')
        check(await E("db.tasks.every(t => !t.comments.length && !t.notesHtml)"), 'tasks arrive without comments or descriptions')
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        # ---------------- phone-size screen for finance
        ctx, pg, errs = await login(FA, (390, 844)); E = pg.evaluate
        check(not await E("document.body.classList.contains('phone')"), 'finance people don’t get the phone task tabs')
        check(await pg.locator('#fin-phone').is_visible() and not await pg.locator('#app').is_visible(), 'on a phone they see a note to use a computer')
        await pg.screenshot(path=os.path.join(SHOTS, 'fin_phone.png'), full_page=True)
        await ctx.close()
        # ---------------- Admin
        ctx, pg, errs = await login(ADMIN); E = pg.evaluate
        check(await pg.locator('.fin-admin-nav').count() == 1, 'Admin has Finance in the sidebar')
        await pg.click('.fin-admin-nav'); await pg.wait_for_timeout(300)
        check(await E("ui.view") == 'fin-dash' and await pg.locator('#title-area [data-fin-go]').count() == 3, 'Admin sees the Finance pages with tabs')
        await pg.click('#title-area [data-fin-go="fin-projects"]'); await pg.wait_for_timeout(300)
        tid = await E("document.querySelector('[data-fin-set]').dataset.finSet")
        await pg.click(f'[data-fin-set="{tid}"]'); await pg.wait_for_timeout(200)
        await pg.locator('.fl-menu .mi .fl-pill').get_by_text('Invoiced', exact=True).click(); await pg.wait_for_timeout(300)
        check(await E(f"task('{tid}').finance") == 'Invoiced', 'Admin changes a task’s Finance status on the Finance Projects page')
        await pg.click('#title-area [data-fin-go="fin-expenses"]'); await pg.wait_for_timeout(300)
        check(await pg.locator('[data-fin-new]').count() == 0, 'Admin only looks at expenses (no adding)')
        # an Admin gives themselves Finance Admin access from their own row
        await E("go('team')"); await pg.wait_for_timeout(300)
        await pg.click(f'[data-action="member-menu"][data-id="{await E("currentUserId")}"]'); await pg.wait_for_timeout(200)
        await pg.locator('.menu .mi', has_text='Finance Admin').click(); await pg.wait_for_timeout(300)
        await pg.click('#me-chip'); await pg.wait_for_timeout(200)
        check(await pg.locator('.menu .mi', has_text='Add subscriptions').count() == 1, 'an Admin can give themselves Finance Admin access')
        await E("closeMenus()")
        # Team page: Admin rights and Finance access on top of a role
        prod = await E("db.users.find(u=>u.role==='production').id")
        await E("go('team')"); await pg.wait_for_timeout(300)
        await E(f"""(()=>{{ const u=userById('{prod}'); u.fin='admin'; u.admin=true; persist(0); renderContent(); }})()""")
        await pg.wait_for_timeout(1500)
        await E("renderContent()"); await pg.wait_for_timeout(200)
        await pg.locator('.role-pill.xtra').first.scroll_into_view_if_needed()
        check(await pg.locator('.role-pill.xtra:visible').count() >= 2, 'Team page shows “+ Admin” and “+ Finance Admin”')
        await pg.screenshot(path=os.path.join(SHOTS, 'fin_team.png'))
        prodEmail = await E(f"userById('{prod}').email")
        await pg.screenshot(path=os.path.join(SHOTS, 'fin_admin.png'))
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        # ---------------- Production person with Finance Admin access + Admin rights
        ctx, pg, errs = await login(prodEmail); E = pg.evaluate
        check(await E("ui.view") == 'home' and not await E("document.body.classList.contains('fin-mode')"), 'they keep the normal task app')
        check(await pg.locator('.fin-admin-nav').count() == 1, 'with Finance in their sidebar')
        await pg.click('#me-chip'); await pg.wait_for_timeout(200)
        items = await E("[...document.querySelectorAll('.menu .mi')].map(e=>e.textContent.trim())")
        check('Add subscriptions' in items and 'App updates' in items, f'and the Finance Admin pages + Admin items in their menu')
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
