"""General announcement: only Admins have the card on My profile (title, description, live preview, confirm);
everyone else — Finance-only people too, computer and phone — sees it once as a pop-up until they close it,
with the 'contact Muhammad Arsal' line; the sender doesn't; a new one replaces the last; non-Admins can't send."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18245; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.9-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            async def login(email, vp=(1440, 900)):
                ctx = await b.new_context(viewport={'width': vp[0], 'height': vp[1]}, base_url=BASE, has_touch=vp[0] < 500)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3800)
                return ctx, pg, errs
            # ---- an Account Manager has no card and the server refuses a sneaky one
            ctx, pg, errs = await login('areej@e11-digital.com' if False else ADMIN); E = pg.evaluate
            am = await E("db.users.find(u=>u.role==='am').email"); prod = await E("userById('u-maab').email")
            await ctx.close()
            ctx, pg, errs = await login(am); E = pg.evaluate
            await E("go('profile')"); await pg.wait_for_timeout(300)
            check(await pg.locator('.pf-ann').count() == 0, 'Account Managers have no announcement card')
            await E("db.meta.announcement={id:'x1',title:'Not allowed',body:'',by:currentUserId,at:nowISO()}; persist(0)"); await pg.wait_for_timeout(1500)
            snap = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/snapshot', headers={'X-Dev-Email': ADMIN})).read())['data']['meta']
            check(not (snap.get('announcement') or {}).get('title') == 'Not allowed', 'the server refuses an announcement from a non-Admin')
            await ctx.close()
            # ---- Admin writes and sends it
            ctx, pg, errs = await login(ADMIN); E = pg.evaluate
            await E("go('profile')"); await pg.wait_for_timeout(300)
            check(await pg.locator('.pf-ann').count() == 1, 'Admin has the Announcement card on My profile')
            await pg.fill('#an-title', 'Office closed on Monday'); await pg.fill('#an-body', 'Public holiday.\nDeadlines move to Tuesday.')
            check(await pg.locator('#an-pt').inner_text() == 'Office closed on Monday', 'live preview')
            await pg.click('[data-action="ann-send"]'); await pg.wait_for_timeout(300)
            check(await pg.locator('.dialog').count() == 1, 'asks before sending')
            await pg.click('.dialog .btn.primary'); await pg.wait_for_timeout(1500)
            check(await E("db.meta.announcement && db.meta.announcement.title") == 'Office closed on Monday', 'sent')
            await E("Announce.check()"); await pg.wait_for_timeout(200)
            check(await pg.locator('.an-pop').count() == 0, 'the sender doesn’t get the pop-up')
            check(not errs, f'no page errors {errs}')
            await ctx.close()
            # ---- everyone else sees it once
            for who, vp, label in [(prod, (1440, 900), 'computer'), ('rania.finance@e11-digital.com', (1440, 900), 'Finance-only'), (prod, (390, 844), 'phone')]:
                ctx, pg, errs = await login(who, vp); E = pg.evaluate
                if label == 'phone': await E("me().prefs.annSeen=null; persist(0); Announce.check()"); await pg.wait_for_timeout(300)
                pop = pg.locator('.an-pop')
                check(await pop.count() == 1, f'{label}: pop-up shows')
                if await pop.count():
                    txt = await pop.inner_text()
                    check('ANNOUNCEMENT' in txt and 'Office closed on Monday' in txt and 'Deadlines move to Tuesday' in txt and 'contact Muhammad Arsal' in txt, f'{label}: title, description and the contact line')
                    if label == 'phone':
                        bb = await pg.locator('.an-box').bounding_box(); check(bb['width'] <= 390, f'phone: fits the screen ({bb["width"]:.0f}px)')
                    await pg.wait_for_timeout(1200)
                    check(await pop.count() == 1, f'{label}: doesn’t go away by itself')
                    await pg.click('.an-pop [data-an="close"] >> nth=-1'); await pg.wait_for_timeout(1200)
                    check(await pop.count() == 0, f'{label}: Close closes it')
                    await pg.reload(); await pg.wait_for_timeout(3800)
                    check(await pg.locator('.an-pop').count() == 0, f'{label}: shows only once')
                check(not errs, f'{label}: no page errors {errs}')
                await ctx.close()
            # ---- a new one replaces the last
            ctx, pg, errs = await login(ADMIN); E = pg.evaluate
            await E("db.meta.announcement={id:uid(),title:'Team lunch Thursday',body:'',by:currentUserId,at:nowISO()}; persist(0)"); await pg.wait_for_timeout(1500)
            await ctx.close()
            ctx, pg, errs = await login(prod); E = pg.evaluate
            txt = await pg.locator('.an-pop').inner_text() if await pg.locator('.an-pop').count() else ''
            check('Team lunch Thursday' in txt and 'Office closed' not in txt, 'a new announcement replaces the last and shows again')
            await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
