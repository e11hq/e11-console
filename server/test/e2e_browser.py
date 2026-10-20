"""End-to-end check of the real web app against the real server, with two people at once.
Run:  python3 server/test/e2e_browser.py   (needs Playwright + Chromium; uses AUTH_DEV)"""
import asyncio, json, os, subprocess, sys, tempfile, time, urllib.request
from playwright.async_api import async_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18181
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
        areej, e1 = await person('areej@e11-digital.com')
        haris, e2 = await person('haris@e11-digital.com')
        E1, E2 = areej.evaluate, haris.evaluate
        check(await E1('currentUserId') == 'u-lina' and await E2('currentUserId') == 'u-haris', 'both signed in by Cloudflare identity (no login screen)')
        check(await E1('db.tasks.length') == 15, 'tasks loaded from the server')
        check('Synced' in await areej.locator('#save-label').inner_text(), 'status shows Synced')
        # Areej creates a task -> Haris sees it live
        await E1("()=>{const t=createTask({title:'Live from Areej', projectId:db.projects[0].id, sectionId:db.projects[0].sections[0].id, assignees:['u-haris']}); commit();}")
        await haris.wait_for_timeout(1500)
        check(await E2("!!db.tasks.find(t=>t.title==='Live from Areej')"), 'new task appears live for Haris')
        # both comment on the same task at the same moment
        tid = await E1("db.tasks.find(t=>t.title==='Live from Areej').id")
        await E1("(id)=>{task(id).comments.push({id:'cA',text:'Areej comment',at:nowISO(),attachments:[],parentId:null,reactions:{},authorId:'u-lina'}); persist(0)}", tid)
        await E2("(id)=>{task(id).comments.push({id:'cH',text:'Haris comment',at:nowISO(),attachments:[],parentId:null,reactions:{},authorId:'u-haris'}); persist(0)}", tid)
        await areej.wait_for_timeout(2000)
        c1 = await E1("(id)=>task(id).comments.map(c=>c.id).sort().join()", tid)
        c2 = await E2("(id)=>task(id).comments.map(c=>c.id).sort().join()", tid)
        check(c1 == 'cA,cH' and c2 == 'cA,cH', f'simultaneous comments both kept on both screens ({c1} / {c2})')
        # Haris gets a notification live when Areej mentions him
        await E1("(id)=>{pushNotif('u-haris', task(id), 'mention', 'mentioned you in a comment on', {snippet:'hi'}); persist(0)}", tid)
        await haris.wait_for_timeout(1500)
        check(await E2("myNotifs().some(n=>n.kind==='mention' && n.from==='u-lina')"), 'mention notification delivered live')
        check(await E1("db.notifications.some(n=>n.to==='u-haris')") is False, "Areej's app does not keep Haris's notifications")
        # typing protection: Haris is typing a comment when Areej edits the task title
        await E2("(id)=>openTask(id)", tid); await haris.wait_for_timeout(400)
        await haris.click('#d-comment'); await haris.keyboard.type('Half-typed reply')
        await E1("(id)=>{task(id).title='Renamed by Areej'; commit()}", tid)
        await haris.wait_for_timeout(1500)
        check(await E2("document.querySelector('#d-comment').innerText") == 'Half-typed reply', 'Haris keeps his half-typed comment while the task updates')
        check(await E2("(id)=>task(id).title", tid) == 'Renamed by Areej', 'title change arrived for Haris')
        await haris.keyboard.press('Meta+Enter'); await haris.wait_for_timeout(1500)
        check(await E1("(id)=>task(id).comments.some(c=>c.text==='Half-typed reply')", tid), "Haris's comment reaches Areej")
        # preferences stay per person/device
        await E2("setTheme('light')"); await haris.wait_for_timeout(800)
        check(await E1("document.documentElement.dataset.theme") == 'dark', "Haris's light mode doesn't change Areej's theme")
        # permissions: Haris (Production) can't create a client
        await E2("()=>{createClient('Sneaky', null); persist(0)}"); await haris.wait_for_timeout(1500)
        check(await E2("!db.clients.some(c=>c.name==='Sneaky')"), 'refused change is rolled back in the app')
        # upload through the browser picker
        await E1("(id)=>openTask(id)", tid); await areej.wait_for_timeout(300)
        async with areej.expect_file_chooser() as fc:
            await areej.click('.tm-actions [data-action="attach"]')
        chooser = await fc.value
        pdf = os.path.join(data_dir, 'brief.txt'); open(pdf, 'w').write('hello from the browser ' * 200000)
        await chooser.set_files(pdf); await areej.wait_for_timeout(2500)
        att = await E1("(id)=>task(id).attachments.map(a=>[a.name,a.size,a.path])", tid)
        check(len(att) == 1 and att[0][1] == os.path.getsize(pdf), f'file uploaded from the browser in pieces: {att}')
        await haris.wait_for_timeout(1000)
        check(await E2("(id)=>task(id).attachments.length", tid) == 1, 'attachment appears for Haris')
        body = urllib.request.urlopen(urllib.request.Request(BASE + '/__file/' + att[0][2], headers={'X-Dev-Email': 'haris@e11-digital.com', 'Range': 'bytes=0-4'})).read()
        check(body == b'hello', 'file downloadable from the server')
        # offline then back online: change is kept and sent
        await haris.context.set_offline(True)
        await E2("(id)=>{task(id).tags.push('offline-tag'); commit()}", tid); await haris.wait_for_timeout(1500)
        check(await haris.locator('#save-label').inner_text() in ('Reconnecting…',) or 'Offline' in await haris.locator('#save-label').inner_text(), 'shows Reconnecting when the server is unreachable')
        await haris.context.set_offline(False); await haris.wait_for_timeout(7000)
        check(await E1("(id)=>task(id).tags.includes('offline-tag')", tid), 'offline change synced after reconnecting')
        await areej.screenshot(path=os.path.join(SHOTS, 'e2e_areej.png'))
        await haris.screenshot(path=os.path.join(SHOTS, 'e2e_haris.png'))
        # reload: everything persisted on the server
        await areej.reload(); await areej.wait_for_timeout(600); await areej.mouse.click(1490, 940); await areej.wait_for_timeout(1200)
        check(await E1("(id)=>task(id) && task(id).title", tid) == 'Renamed by Areej' and await E1("(id)=>task(id).comments.length", tid) == 3, 'data still there after reload')
        print('page errors', e1, e2); check(not e1 and not e2, 'no page errors')
        await b.close()
    srv.terminate()
    out = srv.communicate(timeout=5)[0].decode()
    if 'Error' in out: print(out[-2000:])
    print('FAILS', len(fails), fails)
    sys.exit(1 if fails else 0)

asyncio.run(main())
