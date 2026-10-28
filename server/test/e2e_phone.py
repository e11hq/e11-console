"""Phone layout check on an iPhone-sized screen. Run: python3 server/test/e2e_phone.py"""
import asyncio, base64, io, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18193; BASE = f'http://127.0.0.1:{PORT}'
fails = []
def check(c, msg):
    print(('PASS ' if c else 'FAIL ') + msg)
    if not c: fails.append(msg)
def req(method, path, who, body=None):
    r = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None, headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(r) as res: return json.loads(res.read())
# a small red PNG for the review file
PNG = base64.b64encode(bytes.fromhex('89504e470d0a1a0a0000000d4948445200000010000000100802000000909168360000001c49444154789c63f8cfc0f09f8114c0c4c0c0f09f81a1c10106001ac40cf4df5b8a3c0000000049454e44ae426082')).decode()

async def main():
    data_dir = tempfile.mkdtemp(prefix='e11ph-')
    env = {**os.environ, 'DATA_DIR': data_dir, 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'arsal@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.0-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    demo = json.load(open(os.environ.get('DEMO', '/home/claude/video/demo.json')))
    demo['meta'].pop('prefs', None); demo['meta']['cdUserId'] = 'u-karim'
    req('GET', '/api/me', 'arsal@e11-digital.com')
    req('POST', '/api/import', 'arsal@e11-digital.com', {'data': demo})
    try:
        async with async_playwright() as p:
            b = await p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            async def phone(email):
                ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, base_url=BASE)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
                pg = await ctx.new_page(); errs = []
                pg.on('pageerror', lambda e: errs.append(str(e)))
                pg.set_default_timeout(8000)
                await pg.goto('/'); await pg.wait_for_timeout(500); await pg.mouse.click(200, 400); await pg.wait_for_timeout(1500)
                return pg, errs
            shot = lambda pg, n: pg.screenshot(path=os.path.join(SHOTS, f'ph-{n}.png'))
            hr, e1 = await phone('areej@e11-digital.com')
            E = hr.evaluate
            check(await E("document.body.classList.contains('phone')"), 'phone layout is on at iPhone width')
            check(await E("getComputedStyle(document.getElementById('sidebar')).display") == 'none', 'sidebar hidden')
            check(await hr.locator('#ph-tabs .ph-tab').count() == 5, 'bottom tab bar with 5 tabs')
            check(await hr.locator('.ph-head h1').inner_text() == 'My Day', 'opens on My Day')
            await shot(hr, '1-myday')
            # Areej submits a file for CD review on one of his tasks (setup)
            tid = await E("""async ()=>{ const t=db.tasks.find(t=>!t.parentId&&t.projectId&&!t.done); t.assignees=['u-lina']; t.needsCD=true; t.due=todayStr();
               const r=await Host.call('writeChunk',{taskId:t.id,name:'Poster_A1.png',path:null,b64:'%s'}); submitReview(t,[{id:uid(),name:'Poster_A1.png',path:r.path,size:r.size}]); commit({delay:0}); return t.id; }""" % PNG)
            await hr.wait_for_timeout(800)
            # My Tasks
            await hr.locator('[data-ph-tab="mytasks"]').click(); await hr.wait_for_timeout(300)
            check(await hr.locator('#ph-top .ph-head h1').inner_text() == 'My Tasks' and await hr.locator('.pc').count() > 0, 'My Tasks shows task cards')
            await shot(hr, '2-mytasks')
            # open a task
            await hr.locator(f'.pc[data-task="{tid}"]').click(); await hr.wait_for_timeout(500)
            check(await hr.locator('#detail .ph-task-head').is_visible(), 'task page opens full screen with phone header')
            check(await E("document.getElementById('ph-tabs').hidden"), 'tab bar hidden on the task page')
            check(await hr.locator('#detail .tm-main').is_visible() and not await hr.locator('#detail .tm-activity').is_visible(), 'Details tab shown first')
            await shot(hr, '3-task')
            await E("document.querySelectorAll('#notif-root > *').forEach((n) => n.remove())")   # (a pop-up update at the top can cover the tabs, e.g. the content plan reminder late in the month)
            await hr.locator('#detail .ph-task-head [data-tab="comments"]').click(); await hr.wait_for_timeout(300)
            check(await hr.locator('#detail .tm-activity').is_visible() and not await hr.locator('#detail .tm-main').is_visible(), 'Comments tab switches')
            ed = hr.locator('#d-comment'); await ed.click(); await hr.keyboard.type('Posted from my phone')
            await hr.locator('#detail [data-action="add-comment"]').first.click(); await hr.wait_for_timeout(500)
            check(await E(f"task('{tid}').comments.some(c=>c.text.includes('Posted from my phone'))"), 'comment posted from the phone')
            await shot(hr, '4-comments')
            await hr.locator('#detail .ph-back').click(); await hr.wait_for_timeout(300)
            check(not await E("document.getElementById('ph-tabs').hidden") and not await hr.locator('#detail .tm').count(), 'back closes the task, tab bar returns')
            # quick add
            await hr.locator('[data-ph-tab="today"]').click(); await hr.wait_for_timeout(200)
            await hr.locator('.ph-fab').click(); await hr.wait_for_timeout(400)
            DRAG = """async ([dy, steps]) => { const box = document.querySelector('.ph-sheet'); const top = box.getBoundingClientRect().top + 10;
              const fire = (type, y) => { const t = new Touch({ identifier: 2, target: box, clientX: 195, clientY: y });
                box.querySelector('.ph-grab').dispatchEvent(new TouchEvent(type, { touches: type === 'touchend' ? [] : [t], changedTouches: [t], bubbles: true, cancelable: true })); };
              fire('touchstart', top); for (let i = 1; i <= steps; i++) { fire('touchmove', top + dy * i / steps); await new Promise(r => setTimeout(r, 30)); }
              fire('touchend', top + dy); await new Promise(r => setTimeout(r, 500)); }"""
            await E(DRAG, [30, 6])
            check(await hr.locator('.ph-sheet').count() == 1, 'a small pull on the sheet springs back')
            await E(DRAG, [260, 10])
            check(await hr.locator('.ph-sheet').count() == 0, 'pulling the sheet down by its top cancels it')
            await hr.locator('.ph-fab').click(); await hr.wait_for_timeout(400)
            await hr.locator('#qa-desc').fill('only notes so far'); await E(DRAG, [260, 10])
            check(await hr.locator('.ph-scrim.docked').count() == 1, 'a description alone is enough to keep the draft')
            await hr.locator('.ph-scrim.docked .ph-sheet').click(); await hr.wait_for_timeout(300)
            await hr.locator('#qa-desc').fill('')
            await hr.locator('#qa-title').fill('Half typed draft')
            await E(DRAG, [260, 10])
            check(await hr.locator('.ph-scrim.docked').count() == 1, 'pulling down a sheet with typing tucks it away instead of cancelling')
            await shot(hr, '5a-docked')
            await hr.locator('#ph-tabs [data-ph-tab="inbox"]').click(); await hr.wait_for_timeout(200)
            check(await E("ui.view") == 'inbox' and await hr.locator('.ph-scrim.docked').count() == 1, 'the rest of the app works while the draft is tucked away')
            await hr.locator('.ph-scrim.docked .ph-sheet').click(); await hr.wait_for_timeout(300)
            check(await hr.locator('.ph-scrim.docked').count() == 0 and await hr.locator('#qa-title').input_value() == 'Half typed draft', 'tapping the bar brings the draft back as it was')
            await E(DRAG, [260, 10])
            await E(DRAG, [120, 6])
            check(await hr.locator('.ph-sheet').count() == 0 and not await E("db.tasks.some(t=>t.title==='Half typed draft')"), 'pulling the tucked bar down again throws the draft away')
            await hr.locator('#ph-tabs [data-ph-tab="today"]').click(); await hr.wait_for_timeout(200)
            await hr.locator('.ph-fab').click(); await hr.wait_for_timeout(400)
            await hr.locator('#qa-title').fill('Phone made task'); await hr.locator('#qa-desc').fill('Brief from the client call'); await shot(hr, '5-quickadd')
            await hr.locator('#qa-go').click(); await hr.wait_for_timeout(400)
            check(await E("db.tasks.some(t=>t.title==='Phone made task' && t.due===todayStr() && !t.assignees.includes('u-lina') && t.notes==='Brief from the client call')"), 'quick add creates a task with its description, due today (an Account Manager isn’t assigned)')
            check(await hr.locator('.pc', has_text='Phone made task').count() == 1, 'new task appears on My Day')
            # Me + profile page with back
            await hr.locator('#ph-tabs [data-ph-tab="me"]').click(); await hr.wait_for_timeout(200)
            await shot(hr, '6-me')
            await hr.locator('.ph-row[data-nav="profile"]').click(); await hr.wait_for_timeout(300)
            check(await hr.locator('#ph-top .ph-bar b').inner_text() == 'My profile', 'profile page has a phone back header')
            await shot(hr, '7-profile')
            await hr.locator('#ph-top .ph-bar .ph-back').click(); await hr.wait_for_timeout(200)
            check(await E("ui.view") == 'me', 'back returns to Me')
            # search
            await hr.locator('[data-ph-tab="today"]').click(); await hr.locator('[data-ph="search"]').click(); await hr.wait_for_timeout(200)
            await hr.locator('#ph-q').fill('phone made'); await hr.wait_for_timeout(200)
            check(await hr.locator('#ph-results .pc').count() == 1, 'search finds the task')
            # projects tab (not CD)
            await hr.locator('#ph-tabs [data-ph-tab="projects"]').click(); await hr.wait_for_timeout(200)
            await hr.locator('.pc.pj').first.click(); await hr.wait_for_timeout(300)
            check(await E("ui.view") == 'project', 'project opens from Projects')
            await shot(hr, '8-project')
            # menus become action sheets
            await hr.locator('.pc[data-task]').first.click(); await hr.wait_for_timeout(300)
            await hr.locator('[data-ph="task-more"]').click(); await hr.wait_for_timeout(200)
            box = await hr.locator('.menu').bounding_box()
            check(box and box['width'] > 350 and box['y'] + box['height'] > 800, 'menus open as a bottom action sheet')
            await shot(hr, '9-menu')
            check(not e1, f'no errors for Areej {e1[:2]}')

            # Carine (CD) reviews on her phone
            cd, e2 = await phone('carine@e11-digital.com')
            check(await cd.locator('[data-ph-tab="reviews"] .ph-badge').inner_text() == '1', 'CD sees Reviews tab with a badge')
            await cd.locator('#ph-tabs [data-ph-tab="inbox"]').click(); await cd.wait_for_timeout(200)
            check(await cd.locator('.ph-ib.unread').count() >= 1, 'CD inbox shows the review notification')
            await shot(cd, '10-inbox')
            await cd.locator('#ph-tabs [data-ph-tab="reviews"]').click(); await cd.wait_for_timeout(200)
            await cd.locator('.pc.rv').first.click(); await cd.wait_for_timeout(600)
            check(await cd.locator('.ph-slide img').count() == 1, 'review screen shows the file')
            await shot(cd, '11-review')
            await cd.locator('[data-ph="amend"]').click(); await cd.wait_for_timeout(400)
            await cd.locator('#am-note').fill('Make the date bigger'); await shot(cd, '12-amend')
            await cd.locator('#am-go').click(); await cd.wait_for_timeout(600)
            check(await cd.evaluate(f"task('{tid}').reviews.at(-1).state") == 'amend', 'amendments sent from the phone')
            check(await cd.evaluate("ui.view") == 'reviews', 'back on the (now empty) review list')
            await hr.wait_for_timeout(1200)
            check(await E(f"task('{tid}').comments.some(c=>c.text.includes('Make the date bigger'))"), 'Areej sees the amendment comment live')
            check(not e2, f'no errors for Carine {e2[:2]}')
            await E("()=>{closeMenus(); closeDetail()}")
            # swipe sideways to switch tabs
            HSWIPE = """async ([x0, x1]) => { const el = document.elementFromPoint(200, 500) || document.body;
              const fire = (type, x) => { const t = new Touch({ identifier: 3, target: el, clientX: x, clientY: 500 });
                el.dispatchEvent(new TouchEvent(type, { touches: type === 'touchend' ? [] : [t], changedTouches: [t], bubbles: true, cancelable: true })); };
              fire('touchstart', x0); for (let i = 1; i <= 8; i++) { fire('touchmove', x0 + (x1 - x0) * i / 8); await new Promise(r => setTimeout(r, 16)); }
              fire('touchend', x1); await new Promise(r => setTimeout(r, 350)); }"""
            await hr.locator('#ph-tabs [data-ph-tab="mytasks"]').click(); await hr.wait_for_timeout(200)
            await E(HSWIPE, [300, 120])
            check(await E("ui.myTasksTab") == 'done', 'swiping left on My Tasks shows Done')
            await E(HSWIPE, [120, 300])
            check(await E("ui.myTasksTab") == 'todo', 'swiping right goes back to To Do')
            await hr.locator('#ph-tabs [data-ph-tab="inbox"]').click(); await hr.wait_for_timeout(200)
            await E(HSWIPE, [300, 120])
            check(await hr.locator('.ph-chips button.on').get_attribute('data-k') == 'all', 'swiping on Inbox moves Unread → All')
            await hr.locator('#ph-tabs [data-ph-tab="mytasks"]').click(); await hr.wait_for_timeout(200)
            await hr.locator('.pc[data-task]').first.click(); await hr.wait_for_timeout(400)
            await E(HSWIPE, [300, 120])
            check(await E("document.getElementById('detail').dataset.tab") == 'comments', 'swiping left on a task shows Comments')
            await E(HSWIPE, [120, 300])
            check(await E("document.getElementById('detail').dataset.tab") == 'details', 'swiping right shows Details again')
            await E("()=>{closeDetail()}")
            # swipe from the left edge goes back
            SWIPE = """async ([x1, steps]) => { window.__phSwipeAlways = true;
              // like iOS: every event goes to the element first touched, even after going back removes it from the page
              let el0 = null;
              const fire = (type, x) => { if (type === 'touchstart') el0 = document.elementFromPoint(x, 400) || document.body; const t = new Touch({ identifier: 1, target: el0, clientX: x, clientY: 400 });
                el0.dispatchEvent(new TouchEvent(type, { touches: type === 'touchend' ? [] : [t], changedTouches: [t], bubbles: true, cancelable: true })); };
              fire('touchstart', 8); for (let i = 1; i <= steps; i++) { fire('touchmove', 8 + (x1 - 8) * i / steps); await new Promise(r => setTimeout(r, 16)); }
              fire('touchend', x1); await new Promise(r => setTimeout(r, 400)); }"""
            await hr.locator('.pc[data-task]').first.click(); await hr.wait_for_timeout(400)
            await E(SWIPE, [45, 6])
            check(await E("ui.taskId") is not None, 'a short swipe springs back and keeps the task open')
            await E(SWIPE, [300, 12])
            check(await E("ui.taskId") is None, 'swiping from the left edge closes the task')
            await hr.locator('.pc.pj').first.click() if await hr.locator('.pc.pj').count() else None
            await E("()=>go('project', db.projects[0].id)"); await hr.wait_for_timeout(200)
            await E(SWIPE, [300, 12])
            check(await E("ui.view") == 'projects', 'swiping back from a project returns to Projects')
            check(await E("document.getElementById('content').style.transform") == '', 'page is back in place after the swipe')
            check(await E("!document.querySelector('.ph-swipe-fg, .ph-swipe-dim') && document.getElementById('app').style.transform === ''"), 'nothing left over from the swipe')
            # notifications switch on Me, and opening a task from a tapped notification
            await hr.locator('#ph-tabs [data-ph-tab="me"]').click(); await hr.wait_for_timeout(600)
            check(await hr.locator('#ph-push').count() == 1, 'Me shows the phone notifications switch')
            await shot(hr, '14-push-row')
            await E(f"navigator.serviceWorker.dispatchEvent(new MessageEvent('message', {{ data: {{ type: 'open-task', taskId: '{tid}' }} }}))")
            await hr.wait_for_timeout(500)
            check(await E("ui.taskId") == tid, 'tapping a notification opens its task')
            await E("()=>{closeDetail()}")
            pg2 = await hr.context.new_page(); await pg2.goto(f'/?task={tid}'); await pg2.wait_for_timeout(500); await pg2.mouse.click(200, 400); await pg2.wait_for_timeout(2000)
            check(await pg2.evaluate("ui.taskId") == tid and await pg2.evaluate("location.search") == '', 'opening the app from a notification link lands on the task')
            await pg2.close()
            # light theme sanity
            await hr.locator('#ph-tabs [data-ph-tab="me"]').click(); await hr.locator('.ph-theme [data-mode="light"]').click(); await hr.wait_for_timeout(200)
            await hr.locator('#ph-tabs [data-ph-tab="today"]').click(); await hr.wait_for_timeout(200)
            await shot(hr, '13-light')
            await b.close()
    finally:
        srv.terminate()
    print('\n' + ('ALL PASS' if not fails else f'{len(fails)} FAILED'))
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
