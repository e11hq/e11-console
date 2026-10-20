"""End-to-end check of the real web app against the real server, with two people at once.
Run:  python3 server/test/e2e_browser.py   (needs Playwright + Chromium; uses AUTH_DEV)"""
import asyncio, json, os, subprocess, sys, tempfile, time, urllib.request
from playwright.async_api import async_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18182
BASE = f'http://127.0.0.1:{PORT}'
fails = []
def check(c, msg):
    print(('PASS ' if c else 'FAIL ') + msg)
    if not c: fails.append(msg)

def req(method, path, who, body=None):
    r = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None, headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(r) as res: return json.loads(res.read())

async def main():
    data_dir = tempfile.mkdtemp(prefix='e11e2e-')
    env = {**os.environ, 'DATA_DIR': data_dir, 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'arsal@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '0.2.0'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    demo = json.load(open(os.environ.get('DEMO', '/home/claude/video/demo.json')))
    demo['meta'].pop('prefs', None)
    req('GET', '/api/me', 'arsal@e11-digital.com')            # creates nothing (users come from import)
    print('import', req('POST', '/api/import', 'arsal@e11-digital.com', {'data': demo})['count'])
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def person(email):
            ctx = await b.new_context(viewport={'width': 1500, 'height': 950}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
            pg = await ctx.new_page(); errs = []
            pg.on('pageerror', lambda e: errs.append(str(e)))
            pg.set_default_timeout(8000)
            await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(1490, 940); await pg.wait_for_timeout(1200)
            return pg, errs
        admin, e1 = await person('arsal@e11-digital.com')
        A = admin.evaluate
        # link Ford project to a client so the freelancer gets its assets
        await A("()=>{const c=createClient('Ford',null); db.projects.find(p=>p.name.startsWith('Ford')).clientId=c.id; createClient('ALAIN',null); persist(0)}")
        await admin.wait_for_timeout(1000)
        await A("go('team')"); await admin.wait_for_timeout(500)
        check('Freelancers with personal emails must be added in Cloudflare by hand' in await admin.locator('#cf-status').inner_text(), 'Team page explains Cloudflare sync is off')
        await admin.click('[data-action="add-member"]'); await admin.wait_for_timeout(200)
        check(await admin.locator('.form-dlg [name=pw]').count() == 0, 'no temporary password on the server')
        await admin.fill('.form-dlg [name=name]', 'Sam Freelance'); await admin.fill('.form-dlg [name=email]', 'sam.design@gmail.com')
        await admin.select_option('.form-dlg [name=role]', 'freelancer'); await admin.click('.form-dlg [type=submit]'); await admin.wait_for_timeout(300)
        check(await admin.locator('.pa-dlg').count() == 1, 'choosing Freelancer asks which projects they can see')
        await admin.click('.pa-row:has-text("Ford") input'); await admin.click('.pa-dlg [type=submit]'); await admin.wait_for_timeout(1500)
        await admin.screenshot(path=os.path.join(SHOTS, 'e2e_team.png'))
        check('1 project' in await admin.locator('.tt-row:has-text("Sam Freelance")').inner_text(), 'team table shows 1 project')
        free, e2 = await person('sam.design@gmail.com')
        F = free.evaluate
        check(await free.locator('.wl-title').count() == 1 and await free.locator('[name=pw]').count() == 0, 'freelancer gets the welcome screen without passwords')
        await free.fill('[name=name]', 'Sam Freelance'); await free.click('.auth-go'); await free.wait_for_timeout(1500)
        projs = await F("db.projects.map(p=>p.name)")
        check(len(projs) == 1 and projs[0].startswith('Ford'), f'freelancer sees only Ford: {projs}')
        check(await F("db.clients.map(c=>c.name).join()") == 'Ford', 'freelancer sees only Ford client assets')
        check(await F("db.tasks.every(t=>t.projectId===db.projects[0].id)"), 'freelancer sees only Ford tasks')
        # admin grants ALAIN live
        await A("()=>{const u=db.users.find(x=>x.email==='sam.design@gmail.com'); u.projectIds=[...u.projectIds, db.projects.find(p=>p.name==='ALAIN').id]; persist(0)}")
        await free.wait_for_timeout(2500)
        check(await F("db.projects.length") == 2 and await F("db.tasks.some(t=>db.projects.find(p=>p.name==='ALAIN').id===t.projectId)"), 'granting a project shows it (and its tasks) live')
        check(await F("can('createTask')") is False and await free.locator('[data-action="new-project"]').count() >= 0, 'freelancer has production-level rights')
        print('page errors', e1, e2); check(not e1 and not e2, 'no page errors')
        await b.close()
    srv.terminate()
    out = srv.communicate(timeout=5)[0].decode()
    if 'Error' in out: print(out[-2000:])
    print('FAILS', len(fails), fails)
    sys.exit(1 if fails else 0)

asyncio.run(main())
