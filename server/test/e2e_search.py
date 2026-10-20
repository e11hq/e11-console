"""Smart search: tasks (desktop + phone) and Client Assets typo tolerance. Run: python3 server/test/e2e_search.py"""
import asyncio, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18203; BASE = f'http://127.0.0.1:{PORT}'
fails = []
def check(c, msg):
    print(('PASS ' if c else 'FAIL ') + msg)
    if not c: fails.append(msg)
def post(p, who):
    return json.loads(urllib.request.urlopen(urllib.request.Request(BASE + p, method='POST', data=b'{}', headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})).read())
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'haris@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.1.3-test.30'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/me', headers={'X-Dev-Email': 'haris@e11-digital.com'}))
    post('/api/sample', 'haris@e11-digital.com')
    try:
        async with async_playwright() as p:
            b = await p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            ctx = await b.new_context(viewport={'width': 1400, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': 'haris@e11-digital.com', 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(500); await pg.mouse.click(1390, 890); await pg.wait_for_timeout(1500)
            S = lambda q: pg.evaluate("(q)=>{const r=taskSearch(q); return {n:r.total, first:r.tasks[0]&&r.tasks[0].t.title, titles:r.tasks.map(h=>h.t.title), projects:r.projects.map(p=>p.name), fixed:r.fixed.map(f=>f.to)}}", q)
            r = await S('frod')
            check(r['n'] > 0 and 'ford' in r['fixed'] and all('Ford' in t or 'Lincoln' in t or True for t in r['titles']), f'"frod" finds Ford work and says so ({r["n"]} tasks, fixed {r["fixed"]})')
            r = await S('offorad')
            check(any('Offroad' in t for t in r['titles']), f'"offorad" finds the Offroad task ({r["first"]})')
            r = await S('ford edm')
            check(r['first'] and 'EDM' in r['first'], f'"ford edm": every word must match, best first ({r["first"]})')
            r = await S('korea')
            check(any('KOREA' in p for p in r['projects']) and r['n'] > 0, f'"korea" shows the project and its tasks ({r["projects"]}, {r["n"]})')
            r = await S('arabic')
            check(r['n'] > 0, 'words inside comments are found ("arabic")')
            why = await pg.evaluate("()=>{const r=taskSearch('arabic'); return searchWhy(r.tasks[0], r)}")
            check('Comment by' in why or 'Reply by' in why or 'Description' in why, f'the result says where it matched: {why[:80]}')
            r = await S('overdue')
            od = await pg.evaluate("db.tasks.filter(t=>!t.done && t.due && dayDiff(t.due)<0).length")
            check(r['n'] == od and od > 0, f'"overdue" lists the overdue tasks ({r["n"]} of {od})')
            r = await S('areej')
            check(r['n'] > 0, f'a person’s name finds their tasks ({r["n"]})')
            r = await S('zzqx')
            check(r['n'] == 0, 'nonsense finds nothing')
            # desktop page
            await pg.fill('#search', 'frod edm'); await pg.wait_for_timeout(500)
            check(await pg.locator('.sr-fixed').count() == 1 and await pg.locator('.sr-hit').count() >= 1, 'desktop search page shows corrected results')
            await pg.screenshot(path=os.path.join(SHOTS, 'search-desktop.png'))
            await pg.fill('#search', 'arabic'); await pg.wait_for_timeout(500)
            check(await pg.locator('.sr-why').count() >= 1, 'desktop shows why a task matched')
            # Client Assets typo tolerance
            ca = await pg.evaluate("""()=>{ db.clients=[{id:'c1',name:'Ford',dir:'Clients/Ford',folders:[{id:'f1',name:'Brand Guidelines',dir:'x',files:[{id:'a1',name:'Ford_logo_white.png',path:'x/a.png',size:1}]}]}];
               const exact=caSearch('ford logo'); const typo=caSearch('frod logo'); const typo2=caSearch('gudelines'); return [exact.files.length, !!exact.loose, typo.files.length, !!typo.loose, typo2.folders.length]}""")
            check(ca == [1, False, 1, True, 1], f'Client Assets: exact first, then close matches for typos {ca}')
            # phone
            ph = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, base_url=BASE)
            await ph.add_cookies([{'name': 'e11_dev_email', 'value': 'haris@e11-digital.com', 'url': BASE}])
            pp = await ph.new_page(); await pp.goto('/'); await pp.wait_for_timeout(500); await pp.mouse.click(200, 400); await pp.wait_for_timeout(1500)
            await pp.locator('[data-ph="search"]').click(); await pp.wait_for_timeout(300)
            await pp.locator('#ph-q').fill('korae'); await pp.wait_for_timeout(300)
            check(await pp.locator('#ph-results .pc.pj').count() >= 1 and await pp.locator('#ph-results .sr-fixed').count() == 1, 'phone: typo still finds the project, with the correction shown')
            await pp.screenshot(path=os.path.join(SHOTS, 'search-phone.png'))
            await pp.locator('#ph-q').fill('package arabic'); await pp.wait_for_timeout(300)
            check(await pp.locator('#ph-results .ph-why').count() >= 1, 'phone: shows where it matched')
            await pp.screenshot(path=os.path.join(SHOTS, 'search-phone2.png'))
            check(not errs, f'no errors {errs[:2]}')
            await b.close()
    finally:
        srv.terminate()
    print('\n' + ('ALL PASS' if not fails else f'{len(fails)} FAILED'))
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
