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
        await pr.evaluate(f"(() => {{ const c = clientById('{cid}'); newFolder(c, 'Mood boards'); const f = c.folders.find(x => x.name === 'Logos'); f.files.push({{ id: 'pf1', name: 'mine.png', path: f.dir + '/mine.png', addedBy: currentUserId }}); persist(0); render(); }})()")
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
        # deleting the client keeps its Client Assets
        await E("(() => { const p = db.projects.find(x => x.name === 'Nissan Test'); db.projects = db.projects.filter(x => x.id !== p.id); persist(0); })()")
        await E("Sync.push()"); await pg.wait_for_timeout(600)
        check(await E(f"!!clientById('{cid}')"), 'deleting the client keeps its Client Assets folder')
        check(not errs2 and not errs3, f'no page errors {errs2} {errs3}')
        await b.close()
    srv.kill()
    print('ALL PASS' if not fails else f'FAILS {fails}')
asyncio.run(main())
