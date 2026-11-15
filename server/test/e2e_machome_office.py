"""The Mac app: the Office Admin's Home in the team's Home style (Haris 2026-11-15 17:46, mock-up O1 A): Home's own pieces —
three cards on top (the third the right column's width), Claims as Team's tasks, Latest in Client Assets as pictures with
one sliding row of clients, the month's claims with its ring growing from 0 once, the Inbox and Team today. Browsers keep
the website's Office Admin Home."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18247; BASE = f'http://127.0.0.1:{PORT}'; OWNER = 'haris@e11-digital.com'; OA = 'arsal@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def api(who, p, body=None):
    r = urllib.request.Request(BASE + p, method='POST' if body is not None else 'GET', data=json.dumps(body).encode() if body is not None else None, headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
    return json.loads(urllib.request.urlopen(r).read())
BRIDGE = open(os.path.join(os.path.dirname(__file__), 'e2e_macbar.py')).read().split('BRIDGE = """')[1].split('"""')[0]
async def main():
    subprocess.run(['fuser', '-k', f'{PORT}/tcp'], stderr=subprocess.DEVNULL)
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': OWNER, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.8-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    api(OWNER, '/api/me'); api(OWNER, '/api/sample/reset', {})
    api(OWNER, '/api/push', {'changes': [{'kind': 'users', 'id': 'u-arsal', 'data': {'id': 'u-arsal', 'email': OA, 'name': 'Arsal Khan', 'role': 'office_admin', 'fin': 'admin', 'active': True, 'setup': True, 'prefs': {}}}]})
    shots = os.environ.get('SHOT_DIR', '/tmp')
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            for look in ('dark', 'light'):
                ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE, color_scheme=look)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': OA, 'url': BASE}])
                await ctx.add_init_script('window.__shell = 13;' + BRIDGE + 'window.__e11NativeSplash = true;')
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3500); E = pg.evaluate
                if look == 'light': await E("document.documentElement.dataset.theme = 'light'; document.documentElement.classList.remove('mac-sf')")
                await E("document.querySelectorAll('.oh-ask, .pa-card, [class*=profile-ask]').forEach((x) => x.remove())")
                await E("go('home')"); await pg.wait_for_timeout(600)
                if look == 'dark':
                    r = await E("""(() => { const q = (s) => document.querySelector(s); const st = [...document.querySelectorAll('.ohm .hm-stat')].map((x) => Math.round(x.getBoundingClientRect().width));
                      const aside = q('.ohm .hm-grid aside'); return { has: !!q('.hm.ohm') && !q('.oh'), stats: st, aside: Math.round(aside.getBoundingClientRect().width),
                      cards: [...document.querySelectorAll('.ohm .hm-card h2')].map((h) => h.textContent), tabs: [...document.querySelectorAll('.ohm [data-oh="claim-tab"]')].map((t) => t.textContent),
                      thumbs: document.querySelectorAll('.ohm .ohm-grid .hm-thumb').length, chipsOneRow: getComputedStyle(q('.ohm-chips')).flexWrap, ring: !!q('.ohm-month .hm-ring.hm-grow, .ohm-month .hm-ring'),
                      add: !!q('.ohm [data-oh="add-claim"]') }; })()""")
                    print(r)
                    check(r['has'], 'the Mac app shows the Office Admin Home in Home’s style')
                    check(len(r['stats']) == 3 and r['stats'][2] == r['aside'] == 330 and r['stats'][0] == r['stats'][1], f'three cards: two equal, the third the right column’s 330 {r["stats"]} {r["aside"]}')
                    check(r['cards'][:3] == ['Claims', 'Expenses', 'Latest in Client Assets'] and 'Inbox' in r['cards'] and 'Team today' in r['cards'] and any(c.endswith('’s claims') for c in r['cards']), f'the cards {r["cards"]}')
                    check([t.rstrip('0123456789') for t in r['tabs']] == ['Need HR approval', 'HR approved', 'Paid', 'All'], f'Claims’ tabs {r["tabs"]}')
                    check(r['chipsOneRow'] == 'nowrap', 'the clients on one sliding row')
                    check(r['add'], '+ Add claim')
                    # + Add claim: Finance › Reimbursements' own form — a claim added by hand for someone (Haris 18:02), not their own
                    await pg.locator('.ohm [data-oh="add-claim"]').click(); await pg.wait_for_timeout(500)
                    fm = await E("(() => { const m = [...document.querySelectorAll('.modal, .sheet, dialog[open], .fin-form, .overlay, .dlg')].pop(); return [ui.view, !!m && m.innerText.includes('Add staff reimbursement'), !!m]; })()")
                    check(fm[0] == 'home' and fm[1] and fm[2], f'+ Add claim opens the by-hand form (a person, a month, the PDF), not their own claim {fm}')
                    await pg.keyboard.press('Escape'); await pg.wait_for_timeout(300)
                    await E("closeMenus && closeMenus(); document.querySelectorAll('.modal-backdrop, .modal, .overlay').forEach((x) => x.remove())")
                    # the dirham sign everywhere (Haris 17:54); SF Pro and the Mac's own smoothing; the cards' symbols Apple's
                    t = await E("(() => { const x = document.querySelector('.ohm'); const cs = getComputedStyle(x); return [x.textContent.includes('AED'), x.textContent.includes('\u20C3'), cs.fontFamily, cs.webkitFontSmoothing || '', [...document.querySelectorAll('.ohm .hm-stat [data-i]')].map((i) => i.dataset.i)]; })()")
                    check(not t[0] and t[1], 'the dirham sign, no "AED"')
                    check('-apple-system' in t[2], f'SF Pro (the system font) {t[2]}')
                    check(t[4] == ['oh-claim', 'oh-tray', 'oh-folder'] and await E("['oh-claim','oh-tray','oh-folder','oh-sub','oh-expense','oh-reimb'].every((k) => MacSF.MAP[k])"), f'the symbols are Apple’s SF Symbols {t[4]}')
                    # the head steady whatever the total (Haris 18:06): the tabs and See all at the same place for every tab
                    spots = []
                    for k in ('all', 'sub', 'expense', 'reimb'):
                        await pg.locator(f'.ohm .ohm-exp [data-oh="exp-tab"][data-v="{k}"]').click(); await pg.wait_for_timeout(200)
                        spots.append(await E("(() => { const r = (s) => { const b = document.querySelector(s).getBoundingClientRect(); return [Math.round(b.left), Math.round(b.top)]; }; return [r('.ohm-exp .hm-seg'), r('.ohm-exp .hm-a'), document.querySelector('.ohm-exp .ohm-sum-t b').textContent]; })()"))
                    check(len({json.dumps(x[:2]) for x in spots}) == 1, f'Expenses: the tabs and See all never move with the total {spots}')
                    await E("document.querySelector('.ohm-exp .ohm-sum-t b').textContent = '\u20C31,250,000.00'"); await pg.wait_for_timeout(50)
                    big = await E("(() => { const b = document.querySelector('.ohm-exp .hm-a').getBoundingClientRect(), c = document.querySelector('.ohm-exp').getBoundingClientRect(), t = document.querySelector('.ohm-exp .ohm-sum-t').getBoundingClientRect(); return [Math.round(b.left), Math.round(b.top), t.right <= c.right]; })()")
                    check(big[:2] == spots[-1][1] and big[2], f'...the total at the foot: a seven-figure one fits, the head never moves {big}')
                    # ...and at every window width down to the Mac app's smallest (960): the head on one line inside its card
                    for w in (1440, 1280, 1180, 1100, 960):
                        await pg.set_viewport_size({'width': w, 'height': 900}); await pg.wait_for_timeout(250)
                        fit = await E("(() => { const c = document.querySelector('.ohm-exp'), h = c.querySelector('.hm-h'), a = c.querySelector('.hm-a').getBoundingClientRect(), s = c.querySelector('.hm-seg').getBoundingClientRect(), cb = c.getBoundingClientRect(); return [Math.round(cb.width), a.right <= cb.right - 10 && s.right <= cb.right - 10, h.scrollWidth <= h.clientWidth + 1]; })()")
                        check(fit[1] and fit[2], f'Expenses’ head on one line inside its card at {w} wide {fit}')
                    await pg.set_viewport_size({'width': 1440, 'height': 900}); await pg.wait_for_timeout(250)
                    await pg.locator('.ohm .ohm-exp .hm-tab', has_text='Subscriptions').click(); await pg.wait_for_timeout(300)
                    check(await E("document.querySelector('.ohm-exp .hm-tab.on').dataset.v") == 'sub', 'an Expenses tab picked')
                    # a tab picked; the ring rule (grows from 0 once the page shows)
                    await pg.locator('.ohm [data-oh="claim-tab"][data-v="all"]').click(); await pg.wait_for_timeout(300)
                    check(await E("document.querySelector('.ohm .hm-tab.on').dataset.v") == 'all', 'a Claims tab picked')
                    # the ring: grows from 0 once the page shows (Home's rule), drawn as the paid share
                    await E("(() => { const c = Claims.all().find((x) => x.state === 'approved'); if (c) { c.state = 'paid'; c.paidOn = todayStr(); } window.__e11ShownAt = Date.now(); renderContent(); })()"); await pg.wait_for_timeout(100)
                    check(await E("!!document.querySelector('.ohm-month .hm-ring.hm-grow')"), 'the month’s ring grows from 0 once the page shows')
                    # a picture opens the preview with its neighbours
                    if r['thumbs']:
                        await pg.locator('.ohm .ohm-grid .hm-thumb').first.click(); await pg.wait_for_timeout(500)
                        check(await E("!!(window.__native.preview || document.querySelector('.viewer, .vw, #viewer'))"), 'a picture opens in the preview')
                        await pg.keyboard.press('Escape'); await pg.wait_for_timeout(300)
                    # a client picked keeps the row where it was slid to
                    await E("document.getElementById('ohm-chips').scrollLeft = 80")
                    await pg.locator('.ohm .ohm-chip').nth(2).click(); await pg.wait_for_timeout(300)
                    check(await E("document.querySelector('.ohm-chip.on') === document.querySelectorAll('.ohm-chip')[2]"), 'a client picked')
                    await E("OfficeHome.st.client = 'all'; renderContent()"); await pg.wait_for_timeout(300)
                await pg.screenshot(path=f'{shots}/machome-office-{look}.png')
                check(not errs, f'no page errors ({look}) {errs[:2]}')
                await ctx.close()
            # a browser: the website's Office Admin Home stays
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': OA, 'url': BASE}])
            pg = await ctx.new_page(); await pg.goto('/'); await pg.wait_for_timeout(3500)
            await pg.evaluate("go('home')"); await pg.wait_for_timeout(400)
            check(await pg.evaluate("!!document.querySelector('.oh') && !document.querySelector('.ohm')"), 'a browser keeps the website’s Office Admin Home')
            await ctx.close()
    finally:
        srv.kill()
    print('ALL PASS' if not fails else f'{len(fails)} FAIL')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
