"""Seasonal decorations: Santa hat and snow from 16 to 31 December, Mac app / website only, switch in My profile."""
import asyncio, os, subprocess, tempfile, time, urllib.request, datetime
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18276; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
OUT = os.environ.get('SHOTS') or tempfile.mkdtemp(); fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.5.1-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def open_at(when, w=1440, h=900):
            ctx = await b.new_context(viewport={'width': w, 'height': h}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.clock.install(time=when)
            await pg.goto('/'); await pg.clock.run_for(1800)
            return ctx, pg, errs
        dec = datetime.datetime(2026, 12, 20, 10, 0)
        # the startup screen on the computer
        ctx, pg, errs = await open_at(dec)
        check(await pg.locator('#splash .xm-hat').count() == 1, 'the startup icon wears the hat on 20 December')
        await pg.screenshot(path=os.path.join(OUT, 'season-startup.png'))
        await pg.clock.run_for(4000); await pg.mouse.click(5, 5); await pg.clock.run_for(800)
        E = pg.evaluate
        check(await pg.locator('.brand-logo .xm-hat-s').is_visible(), 'the sidebar logo wears the hat')
        check(await pg.locator('.xm-drift').is_visible() and await pg.locator('.xm-flakes i').count() > 20, 'snow bank and falling snow')
        cap = await E("getComputedStyle(document.querySelector('.brand-acts .create-btn'), '::before').content")
        check(cap not in ('none', 'normal', ''), 'the purple + button has a snow cap')
        grey = await E("getComputedStyle(document.querySelector('.brand-acts .icon-btn'), '::before').content")
        check(grey in ('none', 'normal'), 'grey buttons stay plain')
        check(await E("getComputedStyle(document.querySelector('.xm-drift')).pointerEvents") == 'none', 'the snow never blocks clicks')
        await pg.screenshot(path=os.path.join(OUT, 'season-desktop.png'))
        # the switch in My profile
        await E("go('profile')"); await pg.clock.run_for(400)
        await pg.locator('[data-action="toggle-season"]').click(); await pg.clock.run_for(400)
        check(await pg.locator('.xm-drift').count() == 0 and await pg.locator('.xm-hat-s').count() == 0, 'switching it off removes hat and snow')
        check(await E("localStorage.getItem('e11-season-off')") == '1', 'the choice is kept on the device for the startup screen')
        await pg.locator('[data-action="toggle-season"]').click(); await pg.clock.run_for(400)
        check(await pg.locator('.xm-drift').count() == 1, 'and back on')
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        # out of season: nothing
        ctx, pg, errs = await open_at(datetime.datetime(2026, 12, 15, 10, 0))
        check(await pg.locator('.xm-hat, .xm-drift').count() == 0, 'nothing on 15 December')
        r = await pg.evaluate("[Season.inSeason(new Date(2027,11,16)), Season.inSeason(new Date(2027,11,31)), Season.inSeason(new Date(2028,0,1))]")
        check(r == [True, True, False], f'16 to 31 December, every year {r}')
        await ctx.close()
        # the phone: nothing, not even the hat
        ctx, pg, errs = await open_at(dec, 390, 844)
        check(await pg.locator('#splash .xm-hat').count() == 0, 'no hat on the phone startup screen')
        await pg.clock.run_for(4000); await pg.mouse.click(5, 5); await pg.clock.run_for(800)
        check(await pg.locator('.xm-drift:visible, .xm-flakes:visible, .xm-hat-s:visible').count() == 0, 'no snow or hat on the phone')
        check(not errs, f'no page errors on the phone {errs}')
        await ctx.close()
        await b.close()
    srv.kill()
    print('ALL PASS' if not fails else f'FAILS {fails}')
asyncio.run(main())
