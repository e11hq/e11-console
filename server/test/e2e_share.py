"""Share button on the task page: copies <server>/?task=<id>. Opening that link shows the task; for someone
who uses the Mac app, a Mac browser first hands it to the app (e11console://task/<id>) and shows the task
itself if the app doesn't answer. Not on the phone."""
import asyncio, os, re, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18193; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
SHELL = int(re.search(r'var SHELL_VERSION = (\d+);', open(os.path.join(ROOT, 'mac/main.js')).read()).group(1))
MACUA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
BRIDGE = """window.__calls=[]; window.webkit={messageHandlers:{e11:{postMessage(raw){const m=JSON.parse(raw);window.__calls.push(m.cmd);let r={ok:true};if(m.cmd==='appInfo')r={ok:true,shell:%d};setTimeout(()=>window.__e11NativeReply(m.id,r),5);}}}};""" % SHELL
# pretend this is the live site so the app link scheme is used
HOSTFAKE = "Object.defineProperty(window, '__fakeHost', {value: true});"
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.6-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def open_app(path='/', init=None, ua=None, vp=(1300, 800), wait=2500):
            ctx = await b.new_context(viewport={'width': vp[0], 'height': vp[1]}, base_url=BASE, user_agent=ua, permissions=['clipboard-read', 'clipboard-write'])
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
            if init: await ctx.add_init_script(init)
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto(path); await pg.wait_for_timeout(wait)
            return ctx, pg, errs
        # --- Mac app: marks the person as a Mac app user; links handed over by the app open the task
        ctx, pg, errs = await open_app(init=BRIDGE)
        await pg.mouse.click(600, 400); await pg.wait_for_timeout(2500)
        check(await pg.evaluate('!!me().macApp'), 'using the Mac app remembers this person has it')
        tid = await pg.evaluate("db.tasks.find(t => /Offroad Campaign/.test(t.title)).id")
        await pg.evaluate(f"window.__e11OpenTask('{tid}')"); await pg.wait_for_timeout(600)
        check(await pg.evaluate('ui.taskId') == tid, 'a link handed over by the Mac app opens the task')
        await ctx.close()
        # --- desktop browser: share button copies the link
        ctx, pg, errs = await open_app()
        await pg.mouse.click(600, 400); await pg.wait_for_timeout(2500)
        await pg.evaluate("ui.taskId && closeDetail()")
        await pg.evaluate(f"openTask('{tid}')"); await pg.wait_for_timeout(600)
        btns = await pg.eval_on_selector_all('#detail .tm-actions .icon-btn', 'els => els.map(e => e.dataset.action)')
        check('share-task' in btns and btns.index('share-task') == btns.index('attach') - 1, f'Share sits next to Attach / Delete / Layout {btns}')
        await pg.click('#detail [data-action="share-task"]'); await pg.wait_for_timeout(400)
        link = await pg.evaluate('navigator.clipboard.readText()')
        check(link == f'{BASE}/?task={tid}', f'Share copies the task link: {link}')
        check('Link copied' in await pg.locator('#toast-root').inner_text(), 'and says so')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'share_button.png'))
        # a task link inside the app opens straight away
        await pg.evaluate("closeDetail()")
        await pg.evaluate(f"(() => {{ const a = document.createElement('a'); a.href = '/?task={tid}'; a.target = '_blank'; a.id = 'tl'; a.textContent = 'x'; document.getElementById('content').prepend(a); }})()")
        await pg.click('#tl'); await pg.wait_for_timeout(500)
        check(await pg.evaluate('ui.taskId') == tid and len(ctx.pages) == 1, 'a task link in a comment opens the task in place')
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        # --- link opened in a browser (local server: no app hand-over) shows the task
        ctx, pg, errs = await open_app(f'/?task={tid}', wait=4500)
        check(await pg.evaluate('ui.taskId') == tid, 'opening the link in a browser shows the task')
        await ctx.close()
        # --- hand-over logic on a Mac browser for a Mac app user (scheme forced by pretending to be live)
        force = "window.__forceScheme = 'e11console';"
        ctx, pg, errs = await open_app(f'/?task={tid}', init=force, ua=MACUA, wait=600)
        await pg.wait_for_timeout(3500)
        tried = await pg.evaluate("window.__triedScheme || null")
        check(tried == f'e11console://task/{tid}', f'a Mac browser first offers the link to the Mac app: {tried}')
        await pg.wait_for_timeout(6000)
        check(await pg.evaluate('ui.taskId') == tid and await pg.locator('#open-app').count() == 0, 'no app answered: the task shows in the browser')
        await ctx.close()
        ctx, pg, errs = await open_app(f'/?task={tid}', init=force + "window.__fakeLeave = true;", ua=MACUA, wait=600)
        await pg.wait_for_timeout(5000)
        txt = await pg.locator('#open-app').inner_text() if await pg.locator('#open-app').count() else ''
        check('Opened in the E11 Console app' in txt, f'when the app takes it, the tab says so: {txt!r}')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'share_opened.png'))
        await pg.click('#open-app [data-oa="here"]'); await pg.wait_for_timeout(500)
        check(await pg.evaluate('ui.taskId') == tid, '"Show it here instead" opens it in the browser')
        await ctx.close()
        # --- phone: no share button
        ctx, pg, errs = await open_app(vp=(390, 844))
        await pg.evaluate(f"openTask('{tid}')"); await pg.wait_for_timeout(600)
        check(await pg.locator('#detail [data-action="share-task"]:visible').count() == 0, 'no Share button on the phone')
        await ctx.close()
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
