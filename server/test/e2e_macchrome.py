"""Mac app 4+: page runs under the title bar. Sidebar / theme / back / forward buttons sit in the top row
next to the window buttons; empty parts of that row drag the window; back / forward walk page history.
Older Mac apps and browsers keep the normal layout."""
import asyncio, os, re, tempfile, time, subprocess, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18191; BASE = f'http://127.0.0.1:{PORT}'
fails = []
SHELL = int(re.search(r'var SHELL_VERSION = (\d+);', open(os.path.join(ROOT, 'mac/main.js')).read()).group(1))
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def bridge(shell):
    return """
window.__calls = [];
window.webkit = { messageHandlers: { e11: { postMessage(raw) {
  const m = JSON.parse(raw); let res = { ok: true };
  window.__calls.push(m.cmd);
  if (m.cmd === 'appInfo') res = { ok: true, server: location.origin, version: '2.0.0', shell: %d };
  setTimeout(() => window.__e11NativeReply(m.id, res), 5);
} } } };""" % shell
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'haris@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.5-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': 'haris@e11-digital.com', 'Content-Type': 'application/json'}))
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def open_app(init, theme=None):
            ctx = await b.new_context(viewport={'width': 1300, 'height': 800}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': 'haris@e11-digital.com', 'url': BASE}])
            if init: await ctx.add_init_script(init)
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(600, 400); await pg.wait_for_timeout(2500)
            return ctx, pg, errs
        shots = tempfile.gettempdir()
        ctx, pg, errs = await open_app(bridge(SHELL))
        check(await pg.evaluate("document.documentElement.classList.contains('mac-chrome')"), 'Mac app 4 gets the full-height layout')
        bar = await pg.locator('#mac-bar').bounding_box()
        check(bar and bar['y'] == 0 and bar['x'] == 84 and bar['height'] == 48, f'controls sit in the top row next to the window buttons {bar}')
        check(await pg.locator('#mac-bar .icon-btn').count() == 4, 'sidebar, theme, back and forward buttons')
        check(not await pg.locator('#sidebar .brand-btns').is_visible(), 'sidebar no longer has its own copies')
        tb = await pg.locator('#topbar').bounding_box()
        check(tb['y'] == 0 and tb['height'] == 48, f'page title and search are in the top row {tb}')
        brand = await pg.locator('#sidebar .brand').bounding_box()
        check(brand['y'] >= 48, f'sidebar logo starts below the top row {brand}')
        await pg.screenshot(path=os.path.join(shots, 'macchrome_dark.png'))
        # drag + zoom from empty parts of the top row, not from buttons
        await pg.evaluate('window.__calls = []')
        await pg.mouse.click(700, 20); await pg.wait_for_timeout(100)
        check('dragWindow' in await pg.evaluate('window.__calls'), 'empty top row drags the window')
        await pg.evaluate('window.__calls = []')
        await pg.mouse.dblclick(700, 20); await pg.wait_for_timeout(100)
        check('zoomWindow' in await pg.evaluate('window.__calls'), 'double-click on it zooms the window')
        await pg.evaluate('window.__calls = []')
        await pg.click('#search'); await pg.wait_for_timeout(100)
        check('dragWindow' not in await pg.evaluate('window.__calls'), 'search box does not drag')
        await pg.keyboard.press('Escape'); await pg.evaluate('ui.taskId && closeDetail()'); await pg.wait_for_timeout(300)
        # history
        check(await pg.locator('#nav-back').is_disabled(), 'back starts disabled')
        await pg.click('[data-nav="inbox"]'); await pg.wait_for_timeout(200)
        await pg.click('[data-nav="mytasks"]'); await pg.wait_for_timeout(200)
        await pg.click('#nav-back'); await pg.wait_for_timeout(200)
        check(await pg.evaluate('ui.view') == 'inbox', 'back goes to the previous page')
        await pg.click('#nav-back'); await pg.wait_for_timeout(200)
        check(await pg.evaluate('ui.view') == 'home' and await pg.locator('#nav-back').is_disabled(), 'back again reaches the first page')
        await pg.click('#nav-fwd'); await pg.wait_for_timeout(200)
        check(await pg.evaluate('ui.view') == 'inbox', 'forward goes ahead again')
        await pg.keyboard.press('Meta+]'); await pg.wait_for_timeout(200)
        check(await pg.evaluate('ui.view') == 'mytasks' and await pg.locator('#nav-fwd').is_disabled(), '⌘] goes forward')
        await pg.keyboard.press('Meta+['); await pg.wait_for_timeout(200)
        check(await pg.evaluate('ui.view') == 'inbox', '⌘[ goes back')
        await pg.click('[data-nav="clients"]'); await pg.wait_for_timeout(200)
        check(await pg.locator('#nav-fwd').is_disabled(), 'a new page clears forward history')
        # sidebar collapse: topbar title clears the controls
        await pg.click('#mac-bar .sb-toggle'); await pg.wait_for_timeout(300)
        check(await pg.evaluate("document.getElementById('app').classList.contains('sb-collapsed')"), 'sidebar button collapses the sidebar')
        title = await pg.locator('#title-area').bounding_box()
        check(title['x'] >= 84 + 4 * 30, f'page title stays clear of the controls {title}')
        await pg.screenshot(path=os.path.join(shots, 'macchrome_collapsed.png'))
        await pg.click('#mac-bar .sb-toggle'); await pg.wait_for_timeout(200)
        await pg.evaluate("Theme.setMode('dark')"); await pg.wait_for_timeout(200)   # Auto is light during the day
        await pg.click('#mac-bar .theme-toggle'); await pg.wait_for_timeout(300)
        check(await pg.evaluate("document.documentElement.dataset.theme") == 'light', 'theme button switches to light')
        await pg.screenshot(path=os.path.join(shots, 'macchrome_light.png'))
        # full-screen task: its top row (with task title) sits in the title bar
        await pg.click('[data-nav="mytasks"]'); await pg.wait_for_timeout(200)
        await pg.evaluate("(() => { ui.detailMode = 'full'; openTask(db.tasks.find(x => !x.deletedAt).id); })()")
        await pg.wait_for_timeout(600)
        await pg.evaluate("(() => { ui.detailMode = 'modal'; renderDetail(); })()"); await pg.wait_for_timeout(400)
        box = await pg.locator('#detail .tm').bounding_box(); bar = await pg.locator('#mac-bar').bounding_box()
        check(box['y'] >= bar['y'] + bar['height'] + 4, f'task pop-up opens below the title-bar row {box}')
        await pg.screenshot(path=os.path.join(shots, 'macchrome_modal.png'))
        await pg.evaluate("(() => { ui.detailMode = 'full'; renderDetail(); })()"); await pg.wait_for_timeout(400)
        check('full' in await pg.evaluate("document.getElementById('detail').className"), 'task opened full screen')
        top = await pg.locator('#detail .tm-top').bounding_box()
        check(top and top['y'] == 0, f'full-screen task top row is in the title bar {top}')
        check(await pg.locator('#detail .crumb.tm-tt').is_visible(), 'task title shows in that row')
        await pg.screenshot(path=os.path.join(shots, 'macchrome_task.png'))
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        for sh, label in ((3, 'older Mac app (3)'), (None, 'browser')):
            ctx, pg, errs = await open_app(bridge(sh) if sh else None)
            check(not await pg.evaluate("document.documentElement.classList.contains('mac-chrome')") and await pg.locator('#mac-bar').count() == 0, f'{label} keeps the normal layout')
            check(await pg.locator('#sidebar .brand-btns').is_visible(), f'{label} keeps the sidebar buttons')
            await ctx.close()
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
