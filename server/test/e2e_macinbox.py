"""The Mac app's Inbox, Mail's way (Haris 2026-11-15 21:40, canvas I1 B – I17): the list on the left, the picked row read on
the right with only the website's own buttons; picking reads it; ↑ ↓ and Esc; a comment answered right there (a thread
under a main comment, or into its thread), or reacted to from the ☺︎; the row keeps "You replied / You reacted". Browsers
keep the website's Inbox."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18249; BASE = f'http://127.0.0.1:{PORT}'; OWNER = 'haris@e11-digital.com'
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
    shots = os.environ.get('SHOT_DIR', '/tmp')
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            for look in ('dark', 'light'):
                ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE, color_scheme=look)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': OWNER, 'url': BASE}])
                await ctx.add_init_script('window.__shell = 13;' + BRIDGE + 'window.__e11NativeSplash = true;')
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3500); E = pg.evaluate
                if look == 'light': await E("document.documentElement.dataset.theme = 'light'")
                await E("document.querySelectorAll('.oh-ask, .pa-card').forEach((x) => x.remove())")
                await E("ui.inboxTab = 'all'; go('inbox')"); await pg.wait_for_timeout(700)
                r = await E("""(() => ({ mib: !!document.querySelector('#content > .mib'), rows: document.querySelectorAll('.mib-row').length, sel: document.querySelectorAll('.mib-row.sel').length,
                   pane: !!document.querySelector('.mib-pane .mib-ph, .mib-pane .mib-greet'), old: !!document.querySelector('.inbox .ib-row') }))()""")
                print(look, r)
                check(r['mib'] and not r['old'], f'{look}: the Mac app shows the Inbox Mail’s way')
                check(r['rows'] > 3 and r['sel'] == 1 and r['pane'], f'{look}: rows, the newest picked and read on the right')
                await pg.screenshot(path=f'{shots}/macinbox-{look}.png')
                if look == 'dark':
                    # a row picked: read on the right and marked read (as Mail)
                    k = await E("""(() => { const rows = [...document.querySelectorAll('.mib-row')]; const r = rows.find((x) => x.classList.contains('unread') && !x.classList.contains('sel')) || rows[1]; r.click(); return r.dataset.k; })()""")
                    await pg.wait_for_timeout(400)
                    st = await E(f"""(() => {{ const r = document.querySelector('.mib-row[data-k="{k}"]'); return [!!r && r.classList.contains('sel'), !!r && !r.classList.contains('unread'), myNotifs().filter((n) => notifKey(n) === '{k}').every((n) => n.read)]; }})()""")
                    check(all(st), f'clicking a row picks it, reads it and marks it read {st}')
                    # ↓ moves, Esc picks none (Apple's empty view)
                    await E("document.activeElement && document.activeElement.blur()")
                    before = await E("document.querySelector('.mib-row.sel').dataset.k")
                    await pg.keyboard.press('ArrowDown'); await pg.wait_for_timeout(300)
                    after = await E("document.querySelector('.mib-row.sel').dataset.k")
                    check(before != after, '↓ picks the next row')
                    await pg.keyboard.press('Escape'); await pg.wait_for_timeout(300)
                    check(await E("!document.querySelector('.mib-row.sel') && !!document.querySelector('.mib-empty')"), 'Esc: nothing picked, the empty view')
                    # a comment answered from here: into its thread, or a new thread under a main comment
                    ck = await E("""(() => { const g = [...document.querySelectorAll('.mib-row')].map((r) => r.dataset.k).find((k) => myNotifs().some((n) => notifKey(n) === k && ['comment', 'mention'].includes(n.kind) && n.commentId && task(n.taskId) && task(n.taskId).comments.some((c) => c.id === n.commentId))); return g || null; })()""")
                    check(bool(ck), 'a row with a comment to answer')
                    if ck:
                        await pg.locator(f'.mib-row[data-k="{ck}"]').click(); await pg.wait_for_timeout(400)
                        info = await E("(() => { const ta = document.querySelector('.mib-in'); return ta ? [ta.dataset.tid, ta.dataset.root, document.querySelector('.mib-where').textContent] : null; })()")
                        check(bool(info), f'the reply box is there {info}')
                        await pg.locator('.mib-in').fill('Monday works — I’ll move the call.')
                        check(await E("!document.querySelector('.mib-send').disabled"), 'the send button lights up once something is typed')
                        await pg.keyboard.press('Enter'); await pg.wait_for_timeout(500)
                        res = await E(f"""(() => {{ const t = task('{info[0]}'); const c = t.comments[t.comments.length - 1]; return [c.text, c.parentId === '{info[1]}', c.authorId === currentUserId,
                            (document.querySelector('.mib-row[data-k="{ck}"] .mib-mine') || {{}}).textContent || '', !!document.querySelector('.mib-yours')]; }})()""")
                        check(res[0].startswith('Monday works') and res[1] and res[2], f'the reply goes under that comment’s thread {res[:3]}')
                        check('You replied' in res[3] and res[4], f'the row keeps “You replied”, the reply shown on the right {res[3:]}')
                        # react from the ☺︎
                        await pg.hover('.mib-u:has(.mib-smile)'); await pg.locator('.mib-smile').last.click(); await pg.wait_for_timeout(300)
                        n6 = await E("document.querySelectorAll('.mib-pop button').length")
                        check(n6 == 6, f'the ☺︎ pops up the website’s six reactions ({n6})')
                        await pg.locator('.mib-pop button[data-e="👍"]').click(); await pg.wait_for_timeout(400)
                        rx = await E(f"""[(document.querySelector('.mib-row[data-k="{ck}"] .mib-mine') || {{}}).textContent || '', !!document.querySelector('.mib-pill.mine')]""")
                        check('You reacted' in rx[0] and rx[1], f'the row keeps “You reacted 👍”, the pill under the comment {rx}')
                        await pg.screenshot(path=f'{shots}/macinbox-replied.png')
                    # Clear on the one being read in Primary: the next is picked
                    await E("ui.inboxTab = 'primary'; myNotifs().slice(0, 6).forEach((n) => { n.read = false; }); go('home'); go('inbox')"); await pg.wait_for_timeout(500)
                    k1 = await E("(document.querySelector('.mib-row.sel') || {}).dataset ? document.querySelector('.mib-row.sel').dataset.k : null")
                    await E("clearTaskNotifs(document.querySelector('.mib-row.sel').dataset.k, true)"); await pg.wait_for_timeout(400)
                    k2 = await E("(document.querySelector('.mib-row.sel') || {}).dataset ? document.querySelector('.mib-row.sel').dataset.k : null")
                    check(k1 and k2 and k1 != k2, f'Clear on the one being read picks the next ({k1} → {k2})')
                check(not errs, f'{look}: no page errors {errs[:2]}')
                await ctx.close()
            # a browser: the website's Inbox, untouched
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': OWNER, 'url': BASE}])
            pg = await ctx.new_page(); await pg.goto('/'); await pg.wait_for_timeout(3000)
            await pg.evaluate("ui.inboxTab = 'all'; go('inbox')"); await pg.wait_for_timeout(500)
            check(await pg.evaluate("!!document.querySelector('.inbox .ib-row') && !document.querySelector('.mib')"), 'a browser keeps the website’s Inbox')
            await b.close()
    finally:
        srv.kill()
    print('FAILS:', fails) if fails else print('ALL PASS')
asyncio.run(main())
