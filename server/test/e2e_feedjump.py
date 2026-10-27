"""Mac app: a task's comments get a round "jump to the latest" button once scrolled up, or a "N new comments" pill
when comments arrive meanwhile, in the app's normal solid style (no glass anywhere). A browser has no jump button."""
import asyncio, os, re, tempfile, time, subprocess, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18238; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
OUT = tempfile.gettempdir()
SHELL = int(re.search(r'let SHELL_VERSION = (\d+)', open(os.path.join(ROOT, 'mac/swift/main.swift')).read()).group(1))
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
BRIDGE = """
window.webkit = { messageHandlers: { e11: { postMessage(raw) {
  const m = JSON.parse(raw); let res = { ok: true };
  if (m.cmd === 'appInfo') res = { ok: true, server: location.origin, version: '2.0.0', shell: %d };
  setTimeout(() => window.__e11NativeReply(m.id, res), 5);
} } } };""" % SHELL
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.7.1-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            async def open_app(mac, theme):
                ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
                if mac: await ctx.add_init_script(BRIDGE)
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3200)
                await pg.evaluate(f"document.querySelectorAll('.hello-wrap,.pa-card').forEach(e => e.remove()); document.documentElement.dataset.theme = '{theme}'")
                return ctx, pg, errs
            for theme in ['dark', 'light']:
                ctx, pg, errs = await open_app(True, theme)
                check(await pg.evaluate("document.documentElement.classList.contains('mac-chrome')"), f'{theme}: the Mac app')
                tid = await pg.evaluate("db.tasks.filter(t => !t.parentId).sort((a, b) => (b.comments || []).length - (a.comments || []).length)[0].id")
                await pg.evaluate(f"ui.detailMode = 'side'; ui.forceTab = 'comments'; openTask('{tid}')"); await pg.wait_for_timeout(900)
                check(not await pg.query_selector('#detail .jl'), f'{theme}: no jump button at the latest comment')
                box = await pg.eval_on_selector('#detail .tm-feed', 'f => { const r = f.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; }'); await pg.mouse.move(box[0], box[1]); await pg.mouse.wheel(0, -3000); await pg.wait_for_timeout(500)
                jl = await pg.query_selector('#detail .jl.jl-round')
                check(jl is not None, f'{theme}: scrolled up, the round jump button shows')
                bf = await pg.evaluate("getComputedStyle(document.querySelector('#detail .jl')).backdropFilter || getComputedStyle(document.querySelector('#detail .jl')).webkitBackdropFilter")
                check('blur' not in str(bf), f'{theme}: in the normal solid style, no glass ({bf})')
                await pg.screenshot(path=os.path.join(OUT, f'jump_jump_{theme}.png'))
                # a new comment from someone else arrives while scrolled up
                await pg.evaluate(f"""(() => {{ const t = task('{tid}'); const who = db.users.find(u => u.id !== currentUserId && u.active !== false).id;
                  t.comments.push({{ id: 'c-new-{theme}', text: 'Updated the end card', html: 'Updated the end card', authorId: who, at: nowISO(), parentId: null, reactions: {{}}, attachments: [] }}); renderDetail(); }})()""")
                await pg.wait_for_timeout(300)
                pill = await pg.inner_text('#detail .jl.jl-new') if await pg.query_selector('#detail .jl.jl-new') else ''
                check('1 new comment' in pill, f'{theme}: a new comment shows the "1 new comment" pill {pill!r}')
                check(await pg.evaluate("(() => { const f = document.querySelector('#detail .tm-feed'); return f.scrollTop < 50; })()"), f'{theme}: and doesn’t yank you down')
                await pg.screenshot(path=os.path.join(OUT, f'jump_new_{theme}.png'))
                await pg.click('#detail .jl'); await pg.wait_for_timeout(900)
                check(await pg.evaluate("(() => { const f = document.querySelector('#detail .tm-feed'); return f.scrollHeight - f.scrollTop - f.clientHeight < 80; })()") and not await pg.query_selector('#detail .jl'), f'{theme}: clicking it goes to the latest and it goes away')
                # at the latest, a new comment stays in view
                await pg.evaluate(f"""(() => {{ const t = task('{tid}'); t.comments.push({{ id: 'c-new2-{theme}', text: 'One more', html: 'One more', authorId: t.comments[0].authorId, at: nowISO(), parentId: null, reactions: {{}}, attachments: [] }}); renderDetail(); }})()""")
                await pg.wait_for_timeout(300)
                check(await pg.evaluate("(() => { const f = document.querySelector('#detail .tm-feed'); return f.scrollHeight - f.scrollTop - f.clientHeight < 80; })()"), f'{theme}: at the latest, new comments stay in view')
                # toast, alert, date picker, scheduler
                await pg.evaluate("toast('Comment scheduled for Wed, Oct 28 · 9:00 AM', { label: 'Undo', run: () => {} }, 20000)")
                await pg.evaluate("alertUser({ title: 'Areej Masri', body: 'mentioned you on “Ford | Bronco Reel 15s” — Can you check the end card before 4?', open: () => {} }, true)")
                await pg.wait_for_timeout(500)
                for sel, name in [('#toast-root .toast', 'toast'), ('#notif-root .notif-card', 'alert')]:
                    el = await pg.query_selector(sel)
                    bf = await pg.evaluate("(el) => getComputedStyle(el).backdropFilter || getComputedStyle(el).webkitBackdropFilter", el) if el else ''
                    check('blur' not in str(bf), f'{theme}: the {name} keeps the normal look')
                await pg.screenshot(path=os.path.join(OUT, f'jump_toasts_{theme}.png'))
                await pg.evaluate("document.querySelectorAll('#notif-root .notif-card, #toast-root .toast').forEach(e => e.remove())")
                await pg.evaluate("ui.sideTab = 'details'; renderDetail()"); await pg.wait_for_timeout(300)
                await pg.click('#detail .date-chip:has(#d-due)'); await pg.wait_for_timeout(300)
                dp = await pg.query_selector('.dp-pop')
                check(dp is not None and 'blur' not in str(await pg.evaluate("(el) => getComputedStyle(el).backdropFilter || getComputedStyle(el).webkitBackdropFilter", dp)), f'{theme}: the date picker keeps the normal look')
                await pg.screenshot(path=os.path.join(OUT, f'jump_dp_{theme}.png'))
                await pg.keyboard.press('Escape'); await pg.wait_for_timeout(200)
                await pg.evaluate("ui.sideTab = 'comments'; renderDetail()"); await pg.wait_for_timeout(300)
                await pg.click('#detail #d-comment'); await pg.keyboard.type('Hello'); await pg.click('#detail .sc-chev'); await pg.wait_for_timeout(300)
                check('blur' not in str(await pg.evaluate("getComputedStyle(document.getElementById('sc-pop')).backdropFilter || getComputedStyle(document.getElementById('sc-pop')).webkitBackdropFilter")), f'{theme}: the scheduler keeps the normal look')
                await pg.screenshot(path=os.path.join(OUT, f'jump_sched_{theme}.png'))
                check(not errs, f'{theme}: no page errors {errs}')
                await ctx.close()
            # a browser: the normal look
            ctx, pg, errs = await open_app(False, 'dark')
            tid = await pg.evaluate("db.tasks.filter(t => !t.parentId).sort((a, b) => (b.comments || []).length - (a.comments || []).length)[0].id")
            await pg.evaluate(f"ui.detailMode = 'side'; ui.forceTab = 'comments'; openTask('{tid}')"); await pg.wait_for_timeout(800)
            box = await pg.eval_on_selector('#detail .tm-feed', 'f => { const r = f.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; }'); await pg.mouse.move(box[0], box[1]); await pg.mouse.wheel(0, -3000); await pg.wait_for_timeout(500)
            await pg.evaluate("toast('Hello')"); await pg.wait_for_timeout(200)
            bf = await pg.evaluate("getComputedStyle(document.querySelector('#toast-root .toast')).backdropFilter")
            check(not await pg.query_selector('#detail .jl') and 'blur' not in str(bf), 'a browser keeps the normal look (no glass, no jump button)')
            check(not errs, f'browser: no page errors {errs}')
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
