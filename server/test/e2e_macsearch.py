"""The Mac app's Search (web/macsearch.js — canvas "Search — Mac" S1–S5): the quick list under the field while typing (the page
stays), ↑ ↓ ↩, See all results, people / clients / tasks as Home's rows, a person's tasks and back, the typo note and filter chips,
Apple's right-click menu, Esc and clearing going back. Browsers keep the website's own search page."""
import asyncio, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18251; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
MAC = "try { localStorage.setItem('e11-mac-shell', '13'); } catch (e) {} window.webkit = { messageHandlers: { e11: { postMessage: () => {} } } };"
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.8-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(60):
            try: urllib.request.urlopen(BASE + '/api/health'); break
            except Exception: time.sleep(0.1)
        urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
        async with async_playwright() as pw:
            b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            errs = []
            # ---- the Mac app ----
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, extra_http_headers={'X-Dev-Email': ADMIN})
            await ctx.add_init_script(MAC)
            p = await ctx.new_page(); p.on('pageerror', lambda e: errs.append(str(e)))
            await p.goto(BASE + '/'); await p.wait_for_function('typeof db !== "undefined" && db && db.tasks && db.tasks.length > 0', timeout=20000)
            await p.wait_for_timeout(1500)
            name = await p.evaluate('''() => { const u = db.users.find((x) => x.id !== currentUserId && db.tasks.some((t) => (t.assignees || []).includes(x.id))); return fullName(u).split(' ')[0].toLowerCase(); }''')
            await p.click('#search'); await p.keyboard.type(name); await p.wait_for_timeout(400)
            check(await p.evaluate('ui.view') == 'home' and await p.evaluate('ui.search') == '', 'typing: the page stays where it is')
            check(await p.locator('.mcs-pop.shown').count() == 1, 'typing: the quick list shows under the field')
            check(await p.locator('.mcs-pop [data-key^="q-person-"]').count() >= 1 and await p.locator('.mcs-pop [data-key^="q-task-"]').count() <= 5, 'quick list: people, up to 5 tasks')
            g = await p.evaluate('''() => { const f = document.querySelector('#topbar .search').getBoundingClientRect(), q = document.querySelector('.mcs-pop').getBoundingClientRect(); return [f.width, Math.abs(f.right - q.right), Math.abs(f.bottom - q.top), q.width]; }''')
            check(g[0] == 400 and g[1] < 0.01 and g[2] < 0.01 and g[3] == 400, f'one piece: the field 400 wide, the list hanging from it to the pixel {g}')
            first = await p.locator('.mcs-pop [data-qi]').first.get_attribute('data-key')
            await p.keyboard.type('x'); await p.wait_for_timeout(200); await p.keyboard.press('Backspace'); await p.wait_for_timeout(300)
            check(await p.locator('.mcs-pop.shown').count() == 1, 'typing on: the list stays shown (drawn again in place)')
            await p.keyboard.press('ArrowDown'); await p.wait_for_timeout(100)
            check(await p.locator('.mcs-pop .mcs-qi.on').first.get_attribute('data-key') == first, '↓ picks the first')
            await p.keyboard.press('Escape'); await p.wait_for_timeout(300)
            check(await p.locator('.mcs-pop').count() == 0 and await p.input_value('#search') == '', 'Esc closes the list and clears the field')
            await p.click('#search'); await p.keyboard.type(name); await p.wait_for_timeout(300); await p.keyboard.press('Enter'); await p.wait_for_timeout(500)
            check(await p.evaluate('ui.search') == name and await p.locator('.mcs').count() == 1, '↩ with nothing picked: the Search page (See all results)')
            rows = await p.locator('.mcs .hm-row[data-task]').count()
            check(rows > 0 and await p.locator('.mcs .hm-row .status-pill').count() == rows, 'tasks as Home\'s rows, each with its status pill')
            check(await p.locator('.mcs [data-mcs="person"]').count() >= 1, 'people found on the page')
            check('task' in (await p.inner_text('.mcs-head')), 'the head counts what was found')
            k = await p.locator('.mcs .hm-row').first.get_attribute('data-key')
            await p.keyboard.type(' '); await p.wait_for_timeout(400)
            check(await p.locator(f'.mcs [data-key="{k}"]').count() == 1, 'typing on the page: the rows stay (drawn again in place)')
            await p.locator('.mcs [data-mcs="person"]').first.click(); await p.wait_for_timeout(400)
            check(await p.locator('.mcs-who').count() == 1 and await p.locator('.mcs .hm-row').count() >= 1, 'a person clicked: their tasks on the same page')
            await p.click('[data-mcs="back"]'); await p.wait_for_timeout(300)
            check(await p.locator('.mcs-who').count() == 0 and await p.locator('.mcs [data-mcs="person"]').count() >= 1, '‹ back to all results')
            r = await p.locator('.mcs .hm-row').first.bounding_box()
            await p.mouse.click(r['x'] + 200, r['y'] + 20, button='right'); await p.wait_for_timeout(300)
            check(await p.locator('.menu').count() >= 1, 'right-click a task: its menu')
            await p.keyboard.press('Escape'); await p.wait_for_timeout(200)
            await p.fill('#search', 'campain overdue'); await p.wait_for_timeout(400)
            check(await p.locator('.mcs-fix b').count() >= 1 and await p.locator('.mcs-fc').all_inner_texts() == ['Overdue'], 'a typo noted, the filter word as a chip')
            await p.fill('#search', ''); await p.wait_for_timeout(300); await p.click('#search'); await p.keyboard.type('zzqqx'); await p.wait_for_timeout(300)
            check(await p.locator('.mcs-pop .mcs-none').count() == 1 and await p.locator('.mcs-pop [data-key="q-all"]').count() == 0, 'quick list, nothing found: said in it, no See all results')
            await p.keyboard.press('Enter'); await p.wait_for_timeout(300)
            check(await p.evaluate('ui.search') == '', '↩ with nothing found: nothing happens')
            await p.locator('.mcs-x').click(); await p.wait_for_timeout(300)
            check(await p.input_value('#search') == '' and await p.locator('.mcs-pop').count() == 0, 'the field\'s ✕ clears it and closes the list')
            await p.keyboard.type(name); await p.keyboard.press('Enter'); await p.wait_for_timeout(400)
            await p.fill('#search', 'zzqqx'); await p.wait_for_timeout(300)
            check(await p.locator('.mcs-empty').count() == 1, 'nothing found: the website\'s words')
            await p.fill('#search', ''); await p.wait_for_timeout(300)
            check(await p.evaluate('ui.search') == '' and await p.evaluate('ui.view') == 'home', 'cleared: back to the page before')
            await ctx.close()
            # ---- a browser: the website's own search, unchanged ----
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, extra_http_headers={'X-Dev-Email': ADMIN})
            p = await ctx.new_page(); p.on('pageerror', lambda e: errs.append(str(e)))
            await p.goto(BASE + '/'); await p.wait_for_function('typeof db !== "undefined" && db && db.tasks && db.tasks.length > 0', timeout=20000)
            await p.wait_for_timeout(1000)
            await p.fill('#search', name); await p.wait_for_timeout(400)
            check(await p.locator('.mcs-pop').count() == 0 and await p.locator('.mcs').count() == 0 and await p.locator('.search-results-head').count() == 1, 'browsers: the website\'s own search page')
            check(not errs, f'no page errors {errs}')
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'FAILS {fails}')
asyncio.run(main())
