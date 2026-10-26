"""Content plans (trial, test copy): the list of clients for a month, starting a plan, the month calendar with occasions,
adding and editing posts with references, skipping an occasion, who can edit, the Social Manager and the client's Social
people, and the phone."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18331; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
EXEC, MGR, AM = 'amelia@e11-digital.com', 'aishwarya@e11-digital.com', 'areej@e11-digital.com'
OUT = os.environ.get('SHOTS') or tempfile.mkdtemp(); fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def api(who, p, body=None):
    req = urllib.request.Request(BASE + p, method='POST' if body is not None else 'GET', data=json.dumps(body).encode() if body is not None else None, headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
    return json.loads(urllib.request.urlopen(req).read())
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.6.5-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE + '/api/health'); break
            except Exception: time.sleep(0.1)
        api(ADMIN, '/api/me'); api(ADMIN, '/api/sample/reset', {})
        async with async_playwright() as pw:
            b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            async def login(email, vp=(1440, 900)):
                ctx = await b.new_context(viewport={'width': vp[0], 'height': vp[1]}, base_url=BASE, has_touch=vp[0] < 500)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3500); await pg.mouse.click(5, 5); await pg.wait_for_timeout(600)
                return ctx, pg, errs
            # ---------- the Social Executive ----------
            ctx, pg, errs = await login(EXEC)
            E = pg.evaluate
            check(await pg.locator('#nav-plans').is_visible(), 'Content plans in the sidebar (test site)')
            await pg.locator('#nav-plans').click(); await pg.wait_for_timeout(500)
            rows = await pg.locator('.pl-row:not(.tt-head)').count()
            check(rows == 6, f'Amelia sees the 6 clients she is Social for ({rows})')
            check('Trial' in await pg.locator('#title-area').inner_text(), 'marked as a trial')
            ford = pg.locator('.pl-row', has_text='Ford & Lincoln')
            check('Open' in await ford.inner_text() and await ford.locator('.pl-st.draft').count() == 1, 'Ford has a draft plan')
            await pg.screenshot(path=os.path.join(OUT, 'plans-list.png'))
            # start a plan for KIA
            await pg.locator('.pl-row', has_text='KIA').locator('[data-pl="start"]').click(); await pg.wait_for_timeout(600)
            check(await E("ui.view") == 'plan' and await pg.locator('.pl-who b').inner_text() == 'KIA', 'Start plan opens KIA’s new plan')
            check(await pg.locator('.pl-cell:not(.out)').count() >= 28, 'the month calendar')
            d = await E("Plans.planById(ui.planId).month + '-15'")
            await pg.locator(f'.pl-cell[data-day="{d}"]').hover()
            await pg.locator(f'.pl-cell[data-day="{d}"] [data-pl="new-post"]').click(); await pg.wait_for_timeout(300)
            check(await pg.locator('.pl-dlg').count() == 1, 'the + on a day opens a new post')
            await pg.fill('#pp-title', 'Sportage launch teaser')
            await pg.locator('[data-fmt="reel"]').click()
            await pg.locator('[data-ch="tt"]').click()
            await pg.fill('#pp-desc', 'Teaser for the new Sportage.')
            await pg.fill('#pp-en', 'Something new is coming.')
            await pg.fill('#pp-ar', 'شيء جديد قادم.')
            await pg.locator('[data-pp="link"]').click(); await pg.fill('#pp-link', 'www.instagram.com/kia'); await pg.keyboard.press('Enter'); await pg.wait_for_timeout(200)
            check(await pg.locator('.pl-ref-link').count() == 1, 'a reference link')
            async with pg.expect_file_chooser() as fc:
                await pg.locator('[data-pp="upload"]').click()
            await (await fc.value).set_files(os.path.join(ROOT, 'server/src/sample-files/clickup/cu09.jpg')); await pg.wait_for_timeout(2500)
            check(await pg.locator('.pl-ref-img img').count() == 1, 'an uploaded picture shows')
            bb = await pg.locator('.pl-dlg').bounding_box()
            check(bb and bb['y'] >= 0 and bb['y'] + bb['height'] <= 900, f'the pop-up fits the window {bb}')
            await pg.screenshot(path=os.path.join(OUT, 'plans-post.png'))
            await pg.locator('.pl-dlg [type="submit"]').click(); await pg.wait_for_timeout(800)
            chip = pg.locator(f'.pl-cell[data-day="{d}"] .pl-chip')
            check(await chip.count() == 1 and 'Reel' in await chip.inner_text(), 'the post is on its day, as a Reel')
            saved = await asyncio.to_thread(lambda: [p for p in api(ADMIN, '/api/snapshot')['data']['plans'] if p['projectId'] == 'p-kia'])
            check(len(saved) == 1 and saved[0]['posts'][0]['title'] == 'Sportage launch teaser' and saved[0]['posts'][0]['channels'] == ['ig', 'tt'] and len(saved[0]['posts'][0]['refs']) == 2, 'saved on the server with its channels and references')
            await chip.click(); await pg.wait_for_timeout(300)
            await pg.fill('#pp-title', 'Sportage teaser'); await pg.locator('.pl-dlg [type="submit"]').click(); await pg.wait_for_timeout(500)
            check('Sportage teaser' in await pg.locator(f'.pl-cell[data-day="{d}"]').inner_text(), 'editing a post')
            await pg.locator('[data-pl="tab"][data-v="list"]').click(); await pg.wait_for_timeout(300)
            check(await pg.locator('.pl-post').count() == 1 and await pg.locator('.pl-post .pl-thumb img').count() == 1, 'the list view with the picture')
            await pg.locator('[data-pl="tab"][data-v="calendar"]').click(); await pg.wait_for_timeout(200)
            # Ford: occasions this month and skipping one
            await pg.locator('#nav-plans').click(); await pg.wait_for_timeout(300)
            await pg.locator('.pl-row', has_text='Ford & Lincoln').click(); await pg.wait_for_timeout(500)
            n = await pg.locator('.pl-chip').count()
            check(n >= 6, f'Ford’s sample posts on the calendar ({n})')
            await pg.screenshot(path=os.path.join(OUT, 'plans-calendar.png'))
            miss = pg.locator('.pl-occ.miss').first
            if await miss.count():
                name = await miss.locator('b').inner_text()
                await miss.locator('[data-pl="skip"]').click(); await pg.wait_for_timeout(500)
                check(await pg.locator('.pl-occ.skip', has_text=name).count() == 1, f'skipping “{name}” for Ford')
                check(await E("(proj('p-ford').planSkips || []).length") == 1, 'remembered on the client (next year too)')
                await pg.locator('.pl-occ.skip', has_text=name).locator('[data-pl="unskip"]').click(); await pg.wait_for_timeout(400)
                check(await pg.locator('.pl-occ.miss', has_text=name).count() == 1, 'undo skip')
                await pg.locator('.pl-occ.miss', has_text=name).locator('[data-pl="occ-post"]').click(); await pg.wait_for_timeout(300)
                check(await pg.input_value('#pp-title') == name and await pg.input_value('#pp-occ') != '', 'Plan a post: the occasion is filled in')
                await pg.locator('.pl-dlg-top [data-pp="close"]').click(); await pg.wait_for_timeout(200)
            check(not errs, f'no page errors {errs}')
            await ctx.close()
            # ---------- the Account Manager: view only ----------
            ctx, pg, errs = await login(AM)
            E = pg.evaluate
            await E("go('plans')"); await pg.wait_for_timeout(400)
            check(await pg.locator('[data-pl="start"]').count() == 0, 'an AM can’t start plans')
            await E("ui.planId='pl-smp-p-korea'; go('plan')"); await pg.wait_for_timeout(400)
            check(await pg.locator('.pl-ro').count() == 1 and await pg.locator('[data-pl="new-post"]').count() == 0, 'an AM sees a plan view only')
            await pg.locator('.pl-chip').first.click(); await pg.wait_for_timeout(300)
            check(await pg.locator('#pp-title').get_attribute('readonly') is not None and await pg.locator('.pl-dlg [type="submit"]').count() == 0, 'a post opens read-only')
            check(not errs, f'no page errors {errs}')
            await ctx.close()
            # ---------- the Social Manager: every client ----------
            ctx, pg, errs = await login(MGR)
            E = pg.evaluate
            await E("go('plans')"); await pg.wait_for_timeout(400)
            n = await pg.locator('.pl-row:not(.tt-head)').count()
            check(n == await E("db.projects.filter(p => !p.inactive).length"), f'the Social Manager sees every client ({n})')
            check(await pg.locator('[data-pl="start"]').count() >= 5, 'and can start any of them')
            check(await E("designationOf(me())") == 'Social Manager', 'shown as Social Manager')
            check(not errs, f'no page errors {errs}')
            await ctx.close()
            # ---------- Admin: the Social Manager pick and a client's Social people ----------
            ctx, pg, errs = await login(ADMIN)
            E = pg.evaluate
            await E("go('team')"); await pg.wait_for_timeout(400)
            check('Social Manager' in await pg.locator('.tt-row', has_text='Aishwarya').inner_text(), 'the Team page shows the Social Manager')
            await pg.locator('.tt-row', has_text='Amelia').locator('[data-action="member-menu"]').click(); await pg.wait_for_timeout(200)
            check(await pg.locator('.menu .mi', has_text='Social Manager').count() == 1, 'Social people have a Social Manager option')
            await pg.mouse.click(700, 20); await pg.wait_for_timeout(200)
            await E("ClientList.dialog(proj('p-kia'))"); await pg.wait_for_timeout(300)
            check('Amelia' in await pg.locator('#cd-socials').inner_text(), 'the client pop-up lists its Social people')
            await pg.locator('[data-cd="add-social"]').click(); await pg.wait_for_timeout(200)
            check(await pg.locator('[data-cd-am]').count() >= 2, 'picking from the Social people')
            await pg.locator('[data-cd-am]', has_text='Aishwarya').click(); await pg.wait_for_timeout(200)
            await pg.keyboard.press('Escape'); await pg.wait_for_timeout(150)
            await pg.screenshot(path=os.path.join(OUT, 'plans-client-popup.png'))
            await pg.locator('.cd-dlg [type="submit"]').click(); await pg.wait_for_timeout(700)
            socials = await asyncio.to_thread(lambda: next(p for p in api(ADMIN, '/api/snapshot')['data']['projects'] if p['id'] == 'p-kia').get('socials'))
            check(socials == ['u-maya', 'u-aish'], f'saved: {socials}')
            check(not errs, f'no page errors {errs}')
            await ctx.close()
            # ---------- phone ----------
            ctx, pg, errs = await login(EXEC, (390, 844))
            await pg.click('[data-ph-tab="me"]'); await pg.wait_for_timeout(400)
            await pg.locator('.ph-row[data-nav="plans"]').click(); await pg.wait_for_timeout(500)
            check(await pg.locator('.pl-row:not(.tt-head)').count() == 6, 'phone: the list')
            await pg.screenshot(path=os.path.join(OUT, 'plans-phone-list.png'))
            await pg.locator('.pl-row', has_text='Ford & Lincoln').click(); await pg.wait_for_timeout(500)
            check(await pg.locator('.pl-post').count() >= 6, 'phone: the plan as a list by day')
            await pg.screenshot(path=os.path.join(OUT, 'plans-phone.png'))
            await pg.locator('.pl-post').first.click(); await pg.wait_for_timeout(400)
            bb = await pg.locator('.pl-dlg').bounding_box()
            check(bb and bb['width'] >= 389 and bb['height'] <= 845, f'phone: a post opens full screen {bb}')
            await pg.screenshot(path=os.path.join(OUT, 'plans-phone-post.png'))
            check(not errs, f'no page errors {errs}')
            await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
