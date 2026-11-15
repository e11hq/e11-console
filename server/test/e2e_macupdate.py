"""Required Mac app update: an older Mac app (no or lower `shell` in appInfo) shows a banner that can't be
dismissed; since 2026-11-15 it sends them to the Mac App Store (the Terminal-installed app is discontinued).
An up-to-date Mac app and a normal browser show nothing."""
import asyncio, base64, os, plistlib, re, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18190; BASE = f'http://127.0.0.1:{PORT}'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
SHELL = int(re.search(r'var SHELL_VERSION = (\d+);', open(os.path.join(ROOT, 'mac/main.js')).read()).group(1))
def bridge(shell):
    info = '{ ok: true, server: location.origin, version: "2.0.0"' + (f', shell: {shell}' if shell else '') + ' }'
    return """
window.__saved = [];
window.webkit = { messageHandlers: { e11: { postMessage(raw) {
  const m = JSON.parse(raw); let res = { ok: true };
  if (m.cmd === 'appInfo') res = %s;
  if (m.cmd === 'saveFile') window.__saved.push(m.args);
  setTimeout(() => window.__e11NativeReply(m.id, res), 5);
} } } };""" % info
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'haris@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.5'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def open_app(init):
            ctx = await b.new_context(viewport={'width': 1300, 'height': 800}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': 'haris@e11-digital.com', 'url': BASE}])
            if init: await ctx.add_init_script(init)
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(600, 400); await pg.wait_for_timeout(2500)
            return ctx, pg, errs
        # old Mac app (no shell number)
        ctx, pg, errs = await open_app(bridge(None))
        check(await pg.locator('#mac-update').count() == 1, 'older Mac app shows the required-update banner')
        check(await pg.locator('#mac-update [aria-label*="lose"], #mac-update .x, #mac-update [data-action*="dismiss"]').count() == 0, 'banner has no close button')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'macupdate_banner.png'))
        check('Mac App Store' in await pg.locator('#mac-update').inner_text(), 'the banner says the Mac app is now on the Mac App Store (the Terminal app is discontinued — Haris 2026-11-15)')
        await pg.click('#mac-update [data-action="mac-update"]'); await pg.wait_for_timeout(500)
        check(await pg.locator('.mac-dlg a[href*="apps.apple.com/app/e11-console"]').count() == 1 and not await pg.evaluate('window.__saved'), 'Get it opens the App Store dialog — no Terminal update')
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        # up-to-date Mac app and plain browser: no banner
        ctx, pg, errs = await open_app(bridge(SHELL))
        check(await pg.locator('#mac-update').count() == 0, f'up-to-date Mac app (shell {SHELL}) shows nothing')
        await pg.click('#me-chip'); await pg.wait_for_timeout(300)
        await pg.locator('.menu .mi', has_text='Get the App Store app').click(); await pg.wait_for_timeout(500)
        check(await pg.locator('.mac-dlg').count() == 1, 'profile menu → Get the App Store app'); await ctx.close()
        ctx, pg, errs = await open_app(None)
        check(await pg.locator('#mac-update').count() == 0, 'a normal browser shows nothing'); await ctx.close()
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
