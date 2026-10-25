"""Clients: only Admins add one; a new client gets its Client Assets folder (Logos, Brand Guidelines, Fonts, Files),
linked; anyone adds folders and files and removes their own; AMs remove anyone's; the folders made with the client
are Admin-only; deleting a client keeps its Client Assets."""
import asyncio, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18281; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.5.4-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def as_user(email):
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(3500); await pg.mouse.click(5, 5); await pg.wait_for_timeout(500)
            return ctx, pg, errs
        # the Admin adds a client
        ctx, pg, errs = await as_user(ADMIN)
        E = pg.evaluate
        check(await pg.locator('.nav-heading [data-action="new-project"]').is_visible(), 'the Admin sees + New client')
        await pg.locator('.nav-heading [data-action="new-project"]').click(); await pg.wait_for_timeout(300)
        await pg.locator('#overlay-root input').first.fill('Nissan Test'); await pg.keyboard.press('Enter'); await pg.wait_for_timeout(800)
        r = await E("(() => { const p = db.projects.find(x => x.name === 'Nissan Test'); const c = p && clientById(p.clientId); return c ? { name: c.name, folders: c.folders.map(f => [f.name, !!f.auto]) } : null; })()")
        check(r and r['name'] == 'Nissan Test' and [f[0] for f in r['folders']] == ['Logos', 'Brand Guidelines', 'Fonts', 'Files'] and all(f[1] for f in r['folders']), f'its Client Assets folder is made and linked {r}')
        cid = await E("db.projects.find(x => x.name === 'Nissan Test').clientId")
        await E("Sync.push()"); await pg.wait_for_timeout(800)
        check(not errs, f'no page errors (Admin) {errs}')
        AM = await E("(db.users.find(u => u.role === 'am' && u.active !== false && !u.admin) || {}).email")
        PROD = await E("(db.users.find(u => u.role === 'production' && u.active !== false && !u.admin && !u.fin) || {}).email")
        # an AM can't add a client
        ctx2, am, errs2 = await as_user(AM)
        check(not await am.locator('.nav-heading [data-action="new-project"]').is_visible(), 'an AM has no + New client')
        # Production: adds a folder, sees no options on the folders made with the client
        ctx3, pr, errs3 = await as_user(PROD)
        role = await pr.evaluate("me() && me().role")
        await pr.evaluate(f"openClient('{cid}')"); await pr.wait_for_timeout(500)
        check(await pr.locator('[data-action="add-cfolder"]').count() == 1, f'{role} can add a folder')
        check(await pr.locator('[data-action="cfolder-menu"]').count() == 0, 'no options on Logos, Fonts… for them')
        await pr.evaluate(f"(() => {{ const c = clientById('{cid}'); newFolder(c, 'Mood boards'); const f = c.folders.find(x => x.name === 'Logos'); f.files.push({{ id: 'pf1', name: 'mine.png', path: f.dir + '/mine.png', addedBy: currentUserId }}); assetNotify(c, f, 'added', ['mine.png']); persist(0); render(); }})()")
        await pr.evaluate("Sync.push()"); await pr.wait_for_timeout(800)
        check(await pr.locator('[data-action="cfolder-menu"]').count() == 1, 'options on their own folder')
        await pr.evaluate(f"(() => {{ ui.folderId = clientById('{cid}').folders.find(x => x.name === 'Logos').id; go('client'); }})()"); await pr.wait_for_timeout(400)
        check(await pr.locator('[data-action="ca-upload"]').count() == 1, 'they can upload files')
        check(await pr.locator('[data-action="ca-remove"][data-id="pf1"]').count() == 1, 'they can delete their own file')
        # the AM sees Production's file and folder as removable, but not Logos
        await am.wait_for_timeout(1500)
        await am.evaluate(f"openClient('{cid}', clientById('{cid}').folders.find(x => x.name === 'Logos').id)"); await am.wait_for_timeout(400)
        check(await am.locator('[data-action="ca-remove"][data-id="pf1"]').count() == 1, "the AM can delete anyone's file")
        await am.evaluate(f"openClient('{cid}')"); await am.wait_for_timeout(400)
        names = await am.evaluate(f"[...document.querySelectorAll('.cf-card')].filter(c => c.querySelector('[data-action=\"cfolder-menu\"]')).map(c => c.querySelector('.cf-name').textContent)")
        check(names == ['Mood boards'], f"the AM gets options only on added folders {names}")
        # the first image Production uploads into Logos becomes the client's logo; the sidebar shows it
        await pr.evaluate(f"openClient('{cid}', clientById('{cid}').folders.find(x => x.name === 'Logos').id)"); await pr.wait_for_timeout(300)
        await pr.evaluate("""(async () => { const c = document.createElement('canvas'); c.width = 300; c.height = 120; const g = c.getContext('2d'); g.fillStyle = '#c00'; g.fillRect(0, 0, 300, 120);
          const b = await new Promise((r) => c.toBlob(r, 'image/png')); await uploadIntoFolder([new File([b], 'nissan-logo.png', { type: 'image/png' })]); })()""")
        for _ in range(30):
            await pr.wait_for_timeout(300)
            if await pr.evaluate(f"!!clientById('{cid}').logo"): break
        lg = await pr.evaluate(f"[clientById('{cid}').logo, clientById('{cid}').logoAuto]")
        check(bool(lg[0]) and lg[0].startswith('Clients/_logos/') and lg[1] is True, f'the first logo file becomes the client logo {lg}')
        await pg.wait_for_timeout(1500)
        pid0 = await E("db.projects.find(x => x.name === 'Nissan Test').id")
        check(await pg.locator(f'#project-list [data-project="{pid0}"] .nav-clogo img').count() == 1, 'the sidebar shows the logo instead of the colour')
        # an Admin's own logo wins, and later uploads don't replace it
        await E(f"(() => {{ const c = clientById('{cid}'); c.logo = 'Clients/_logos/manual.png'; delete c.logoAuto; persist(0); }})()")
        await E("Sync.push()"); await pg.wait_for_timeout(1200)
        await pr.evaluate("""(async () => { const c = document.createElement('canvas'); c.width = 50; c.height = 50; const b = await new Promise((r) => c.toBlob(r, 'image/png')); await uploadIntoFolder([new File([b], 'other.png', { type: 'image/png' })]); })()""")
        await pr.wait_for_timeout(2500)
        check(await E(f"clientById('{cid}').logo") == 'Clients/_logos/manual.png', "the Admin's logo stays")
        # a logo the Admin chooses also goes into Logos; the same file name again replaces it
        mk = """async (w) => { const c = document.createElement('canvas'); c.width = w; c.height = 40; c.getContext('2d').fillRect(0, 0, w, 40); const b = await new Promise((r) => c.toBlob(r, 'image/png')); return new File([b], 'Brand Logo.png', { type: 'image/png' }); }"""
        await E(f"(async () => {{ const mk = {mk}; await saveLogoOriginal(clientById('{cid}'), await mk(100)); }})()"); await pg.wait_for_timeout(800)
        first = await E(f"clientById('{cid}').folders.find(f => f.name === 'Logos').files.filter(a => a.name === 'Brand Logo.png').map(a => [a.id, a.size])")
        await E(f"(async () => {{ const mk = {mk}; await saveLogoOriginal(clientById('{cid}'), await mk(400)); }})()"); await pg.wait_for_timeout(800)
        second = await E(f"clientById('{cid}').folders.find(f => f.name === 'Logos').files.filter(a => a.name === 'Brand Logo.png').map(a => [a.id, a.size])")
        check(len(first) == 1 and len(second) == 1 and first[0][0] != second[0][0] and first[0][1] != second[0][1], f'the chosen logo lands in Logos and replaces one of the same name {first} → {second}')
        # the Admin and the client's Account Manager get an Inbox update about the file
        await pg.wait_for_timeout(1200)
        n = await E(f"myNotifs().filter(n => n.kind === 'asset' && n.clientId === '{cid}').map(n => n.text + ' · ' + n.snippet)")
        check(any('added a file to Nissan Test › Logos' in x and 'mine.png' in x for x in n), f'the Admin gets an Inbox update {n}')
        await E("go('inbox')"); await pg.wait_for_timeout(400)
        row = pg.locator('.ib-row', has_text='Client Assets').first
        check(await row.count() == 1 and 'Nissan Test' in await row.inner_text(), 'it shows in the Inbox under the client')
        await row.click(); await pg.wait_for_timeout(500)
        check(await E("ui.view") == 'client' and await E("clientById(ui.clientId).name") == 'Nissan Test' and await E("(clientById(ui.clientId).folders.find(f => f.id === ui.folderId) || {}).name") == 'Logos', 'clicking it opens that folder')
        prod_n = await pr.evaluate("myNotifs().filter(n => n.kind === 'asset').length")
        check(prod_n == 0, 'the person who added it is not notified')
        # Account Managers see every task in the clients they look after (by anyone, old ones too); the one covering
        # while another is on leave sees them while covering
        r = await E("""(() => {
          const ams = db.users.filter(u => u.role === 'am' && u.active !== false && !u.admin).slice(0, 2).map(u => u.id);
          const p = db.projects.find(x => x.name === 'Ford & Lincoln') || db.projects[0];
          const others = topTasks().filter(t => t.projectId === p.id).length;
          const me0 = currentUserId;
          const as = (id, fn) => { currentUserId = id; try { return fn(); } finally { currentUserId = me0; } };
          const has = (id) => as(id, () => Work.home().filter(t => t.projectId === p.id).length);
          p.ams = [{ id: ams[0] }];
          const a1 = has(ams[0]), b1 = has(ams[1]);
          p.ams = [{ id: ams[0], onLeave: true }, { id: ams[1] }];
          const a2 = has(ams[0]), b2 = has(ams[1]);
          p.ams = [{ id: ams[0] }];
          const b3 = has(ams[1]);
          delete p.ams;
          return { others, a1, b1, a2, b2, b3 };
        })()""")
        check(r['others'] > 0 and r['a1'] == r['others'], f"an AM sees all their client's tasks, by anyone {r}")
        check(r['a2'] == 0 and r['b2'] == r['others'] and r['b3'] < r['others'], f'the cover sees them only while covering {r}')
        # the client's Account Manager hears about every change on its tasks, once per change
        r = await E("""(() => {
          const am = db.users.find(u => u.role === 'am' && u.active !== false && !u.admin);
          const t = topTasks().find(x => x.projectId && x.createdBy !== am.id && !(x.assignees || []).includes(am.id));
          const p = proj(t.projectId); const was = p.ams; p.ams = [{ id: am.id }];
          const mine = () => db.notifications.filter(n => n.to === am.id && n.taskId === t.id);
          const n0 = mine().length;
          logActivity(t, 'changed the status from <b>To do</b> to <b>Review</b>'); notifyWatchers(t, 'status', 'changed the status to <b>Review</b> on');
          const afterStatus = mine().slice(n0).map(n => n.kind);
          db.notifications.forEach(n => { if (n.to === am.id) n.read = true; });
          logActivity(t, 'changed the title');
          const afterTitle = mine().slice(n0).map(n => n.kind);
          p.ams = [{ id: am.id, onLeave: true }];
          logActivity(t, 'changed the due date');
          const onLeave = mine().slice(n0).length;
          p.ams = was;
          return { afterStatus, afterTitle, onLeave };
        })()""")
        check(r['afterStatus'] == ['status'], f"one update for a status change (not two) {r}")
        check(r['afterTitle'] == ['status', 'edit'], f'any other change too {r}')
        check(r['onLeave'] == 2, f'not while on leave {r}')
        await E("go('profile')"); await pg.wait_for_timeout(600)
        check(await pg.locator('#pf-push').count() == 1, 'My profile has Notifications on this computer')
        await E("go('home')"); await pg.wait_for_timeout(300)
        # an AM's extra rights only on their clients' tasks (and tasks they created); elsewhere like Production
        r = await am.evaluate("""(() => {
          const me0 = me(); const ps = db.projects.filter(p => !p.inactive);
          const mineP = ps[0], otherP = ps[1];
          const was = [mineP.ams, otherP.ams]; mineP.ams = [{ id: me0.id }]; otherP.ams = [];
          const inMine = topTasks().find(t => t.projectId === mineP.id && t.createdBy !== me0.id);
          const inOther = topTasks().find(t => t.projectId === otherP.id && t.createdBy !== me0.id);
          const own = { id: 'x', projectId: otherP.id, createdBy: me0.id };
          const res = { mine: can('assign', inMine), other: can('assign', inOther), otherComment: can('createTask', inOther) === false, ownElsewhere: can('editTitle', own),
            pickerHasOther: amClientOk(otherP), pickerHasMine: amClientOk(mineP) };
          mineP.ams = [{ id: me0.id, onLeave: true }]; res.onLeave = can('assign', inMine);
          mineP.ams = was[0]; otherP.ams = was[1];
          return res;
        })()""")
        check(r == {'mine': True, 'other': False, 'otherComment': True, 'ownElsewhere': True, 'pickerHasOther': False, 'pickerHasMine': True, 'onLeave': False}, f"AM rights follow their clients {r}")
        # a replaced AM stops getting updates on tasks they created in that client; the new AM gets them
        r = await E("""(() => {
          const ams = db.users.filter(u => u.role === 'am' && u.active !== false && !u.admin).slice(0, 2);
          const t = topTasks().find(x => x.projectId && !(x.assignees || []).some(id => ams.some(a => a.id === id)));
          const p = proj(t.projectId); const was = [p.ams, t.createdBy];
          t.createdBy = ams[0].id;
          const got = (id) => db.notifications.filter(n => n.to === id && n.taskId === t.id && n.text === 'TEST-CHANGE on').length;
          p.ams = [{ id: ams[0].id }];
          notifyWatchers(t, 'status', 'TEST-CHANGE on');
          const before = [got(ams[0].id), got(ams[1].id)];
          db.notifications.forEach(n => { n.read = true; });
          p.ams = [{ id: ams[1].id }];
          notifyWatchers(t, 'status', 'TEST-CHANGE on');
          const after = [got(ams[0].id), got(ams[1].id)];
          p.ams = was[0]; t.createdBy = was[1];
          return { before, after };
        })()""")
        check(r == {'before': [1, 0], 'after': [1, 1]}, f'the replaced AM stops, the new AM gets them {r}')
        # Edit client list: switch a client off, rename it (its Client Assets folder follows)
        await E("go('clientlist')"); await pg.wait_for_timeout(400)
        check(await pg.locator('.cl-row').count() >= 3, 'Edit client list shows the clients')
        pid = await E("db.projects.find(x => x.name === 'Nissan Test').id")
        await pg.locator(f'[data-cl="active"][data-id="{pid}"]').click(); await pg.wait_for_timeout(300)
        check(await pg.locator(f'#project-list [data-project="{pid}"]').count() == 0, 'an inactive client leaves the sidebar')
        await pg.locator('[data-cl="tab"][data-tab="inactive"]').click(); await pg.wait_for_timeout(200)
        await pg.locator(f'[data-cl="edit"][data-id="{pid}"]').click(); await pg.wait_for_timeout(300)
        await pg.locator('.cd-dlg input[name=name]').fill('Nissan Middle East')
        await pg.locator('[data-cd="active"]').click()
        await pg.locator('.cd-dlg [type=submit]').click(); await pg.wait_for_timeout(400)
        r = await E(f"(() => {{ const p = proj('{pid}'); return [p.name, !!p.inactive, clientById(p.clientId).name]; }})()")
        check(r == ['Nissan Middle East', False, 'Nissan Middle East'], f'rename + active again; Client Assets follows {r}')
        check(await pg.locator(f'#project-list [data-project="{pid}"]').count() == 1, 'back in the sidebar')
        check(not await am.evaluate("isAdmin()") and await am.evaluate("(() => { go('clientlist'); return ui.view; })()") == 'home', 'an AM cannot open Edit client list')
        await E("(() => { const p = db.projects.find(x => x.name === 'Nissan Middle East'); p.name = 'Nissan Test'; persist(0); })()")
        # deleting the client keeps its Client Assets
        await E("(() => { const p = db.projects.find(x => x.name === 'Nissan Test'); db.projects = db.projects.filter(x => x.id !== p.id); persist(0); })()")
        await E("Sync.push()"); await pg.wait_for_timeout(600)
        check(await E(f"!!clientById('{cid}')"), 'deleting the client keeps its Client Assets folder')
        fr = await E(f"(() => {{ const u = me(); const r = u.role, a = u.admin; u.role = 'freelancer'; u.admin = false; const c = clientById('{cid}'); const v = [canAddAssets(), canDelAsset({{ addedBy: u.id }}), c.folders.some(f => canEditFolder(c, f))]; u.role = r; u.admin = a; return v; }})()")
        check(fr == [False, False, False], f'freelancers only look: no adding, deleting or folder options {fr}')
        check(not errs2 and not errs3, f'no page errors {errs2} {errs3}')
        await b.close()
    srv.kill()
    print('ALL PASS' if not fails else f'FAILS {fails}')
asyncio.run(main())
