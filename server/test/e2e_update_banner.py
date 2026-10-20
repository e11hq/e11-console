"""Open app on 1.0.0, restart the server as 1.1.0: the app should reconnect, show the Reload banner,
and after reloading load the new files."""
import asyncio, json, os, subprocess, sys, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18183; BASE = f'http://127.0.0.1:{PORT}'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def start(v, data):
    env = {**os.environ, 'DATA_DIR': data, 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'arsal@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': v}
    p = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); return p
        except Exception: time.sleep(0.1)
    return p
async def main():
    data = tempfile.mkdtemp()
    srv = start('1.0.0', data)
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        ctx = await b.new_context(viewport={'width': 1400, 'height': 900}, base_url=BASE)
        await ctx.add_cookies([{'name': 'e11_dev_email', 'value': 'arsal@e11-digital.com', 'url': BASE}])
        pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto('/'); await pg.wait_for_timeout(700); await pg.mouse.click(1390, 890); await pg.wait_for_timeout(1500)
        check(await pg.evaluate("Sync.version") == '1.0.0', 'running 1.0.0')
        check(await pg.evaluate("[...document.scripts].some(s=>/app\\.js\\?v=1\\.0\\.0/.test(s.src))"), 'app files requested with ?v=1.0.0')
        srv.terminate(); srv.wait()
        await pg.wait_for_timeout(1500)
        check('Reconnecting' in await pg.locator('#save-label').inner_text(), 'shows Reconnecting while the server restarts')
        srv = start('1.1.0', data)
        await pg.wait_for_timeout(5000)
        check(await pg.locator('#update-banner.on').count() == 1, 'Reload banner appears after the update')
        check('1.1.0' in await pg.locator('#update-banner').inner_text(), 'banner names the new version')
        check('Synced' in await pg.locator('#save-label').inner_text(), 'back to Synced')
        await pg.screenshot(path=os.path.join(SHOTS, 'e2e_banner.png'))
        await pg.click('#update-banner [data-action="reload-app"]'); await pg.wait_for_timeout(1500); await pg.mouse.click(1390, 890); await pg.wait_for_timeout(1200)
        check(await pg.evaluate("Sync.version") == '1.1.0' and await pg.evaluate("[...document.scripts].some(s=>/app\\.js\\?v=1\\.1\\.0/.test(s.src))"), 'after Reload the new version is loaded')
        check(await pg.locator('#update-banner.on').count() == 0, 'banner gone after reload')
        # the Admin page without a launcher explains it is not managed
        await pg.evaluate("go('updates')"); await pg.wait_for_timeout(800)
        check('isn’t managed by the updater' in await pg.locator('#upd-body').inner_text(), 'App updates page loads')
        check(not errs, 'no page errors ' + str(errs))
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails); sys.exit(1 if fails else 0)
asyncio.run(main())
