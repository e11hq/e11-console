"""Light / dark: Automatic by default (sunrise–sunset in Dubai), Light or Dark chosen in My profile or the
phone's Me tab; the sun/moon button picks one too. Finance link is a card like Client Assets."""
import asyncio, os, subprocess, tempfile, time, urllib.request, datetime
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18205; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
DUBAI = datetime.timezone(datetime.timedelta(hours=4))
async def E_ws(pg):
    return await pg.evaluate("[...document.querySelectorAll('.profile > .pf-card')].map(c=>Math.round(c.getBoundingClientRect().width))")
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.7-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def at(hour, vp=(1300, 800)):
            ctx = await b.new_context(viewport={'width': vp[0], 'height': vp[1]}, base_url=BASE, timezone_id='Asia/Dubai', has_touch=vp[0] < 500)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.clock.install(time=datetime.datetime(2026, 10, 22, hour, 0, tzinfo=DUBAI))
            await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(5, 5); await pg.wait_for_timeout(3500)
            return ctx, pg, errs
        ctx, pg, errs = await at(10)
        check(await pg.evaluate("Theme.mode()") == 'auto' and await pg.evaluate("document.documentElement.dataset.theme") == 'light', 'Automatic by default: light at 10 am')
        await pg.clock.fast_forward('09:00:00'); await pg.wait_for_timeout(500)
        check(await pg.evaluate("document.documentElement.dataset.theme") == 'dark', 'turns dark after sunset (7 pm) by itself')
        await pg.evaluate("go('profile')"); await pg.wait_for_timeout(300)
        txt = await pg.locator('.pf-appearance').inner_text()
        check('Auto' in txt and 'sunrise and sunset' in txt and await pg.locator('.pf-appearance .tp-card').count() == 3, 'My profile → Appearance with Light / Dark / Auto previews')
        widths = await E_ws(pg)
        check(len(set(widths)) == 1, f'every profile card is the same full width {widths}')
        await pg.click('.pf-appearance [data-mode="light"]'); await pg.wait_for_timeout(300)
        check(await pg.evaluate("document.documentElement.dataset.theme") == 'light' and await pg.evaluate("Theme.mode()") == 'light', 'choosing Light keeps it light after sunset')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'theme_profile.png'))
        await pg.click('.pf-appearance [data-mode="auto"]'); await pg.wait_for_timeout(300)
        await pg.locator('.pf-appearance').screenshot(path=os.path.join(tempfile.gettempdir(), 'theme_cards.png'))
        check(await pg.evaluate("document.documentElement.dataset.theme") == 'dark', 'back to Automatic: dark again')
        await pg.click('.brand-btns .theme-toggle, #mac-bar .theme-toggle'); await pg.wait_for_timeout(300)
        check(await pg.evaluate("Theme.mode()") == 'light', 'the sun/moon button picks a fixed theme')
        # Finance card
        fin = await pg.locator('.fin-admin-nav').bounding_box(); ca = await pg.locator('.ca-nav-wrap .ca-nav[data-nav="clients"]').bounding_box(); tr = await pg.locator('#nav-trash').bounding_box()
        g1 = round(fin['y'] - (ca['y'] + ca['height'])); g2 = round(tr['y'] - (fin['y'] + fin['height']))
        check(abs(g1 - g2) <= 1 and await pg.locator('.fin-admin-nav .ca-nav-ic').count() == 1, f'Finance is a card like Client Assets, same gap above and below ({g1}px / {g2}px)')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'theme_sidebar.png'))
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        ctx, pg, errs = await at(21, (390, 844))
        check(await pg.evaluate("document.documentElement.dataset.theme") == 'dark', 'phone: dark at 9 pm on Automatic')
        await pg.click('[data-ph-tab="me"]'); await pg.wait_for_timeout(400)
        await pg.click('.ph-theme [data-mode="light"]'); await pg.wait_for_timeout(300)
        check(await pg.evaluate("document.documentElement.dataset.theme") == 'light', 'phone: Me → Appearance → Light')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'theme_phone.png'))
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
