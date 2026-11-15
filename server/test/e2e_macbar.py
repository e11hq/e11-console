"""The Mac app 13+: a right-click's options go to the Mac as Apple's menu (command menu); the top bar stays the page's own;
older Mac apps keep the page's own menu (Mac page by page, part 2 — Haris 2026-11-15)."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18241; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
BRIDGE = """
window.__native = { calls: [], bar: null, menu: null, pick: null };
window.webkit = { messageHandlers: { e11: { postMessage(raw) {
  const m = JSON.parse(raw); window.__native.calls.push(m.cmd);
  let res = { ok: true };
  if (m.cmd === 'appInfo') res = { ok: true, shell: window.__shell || 13, native: 'swift' };
  if (m.cmd === 'pageBar') window.__native.bar = m.args;
  if (m.cmd === 'menu') { window.__native.menu = m.args; res = window.__native.pick == null ? { ok: true } : { ok: true, i: window.__native.pick }; }
  if (m.cmd === 'openURL') window.__native.opened = m.args.url;
  setTimeout(() => window.__e11NativeReply(m.id, res), 5);
} } } };
"""
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.8-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            for shell in (13, 12):
                ctx = await b.new_context(viewport={'width': 1400, 'height': 900}, base_url=BASE)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
                await ctx.add_init_script(f'window.__shell = {shell};' + BRIDGE)
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3500); E = pg.evaluate
                await E("go('home')"); await pg.wait_for_timeout(500)
                if shell == 12:
                    check(not await E("MacBar.on()") and await E("getComputedStyle(document.querySelector('#topbar .search')).visibility") == 'visible', 'an older Mac app keeps the page’s own search')
                    await pg.locator('.hm-lead .hm-row').first.click(button='right'); await pg.wait_for_timeout(200)
                    check(await pg.locator('.menu .mi').count() > 0 and await E("window.__native.menu") is None, '...and the page’s own menu')
                    check(not errs, f'no page errors (12) {errs[:2]}')
                    await ctx.close(); continue
                check(await E("getComputedStyle(document.querySelector('#topbar .search')).visibility") == 'visible' and await E("window.__native.bar") is None, 'the top bar stays the page\u2019s own (Talk and search)')
                # a task opened full covers the strip: Apple's controls go
                tid = await E("document.querySelector('.hm-lead .hm-row').dataset.task")
                await E("window.__native.menu = null; window.__native.pick = null")
                r = pg.locator('.hm-lead .hm-row').first
                await r.click(button='right'); await pg.wait_for_timeout(300)
                m = await E("window.__native.menu")
                labels = [x.get('label') for x in (m or {}).get('list', []) if 'label' in x]
                check(labels[:2] == ['Open Task', 'Status ›'] and await pg.locator('.menu').count() == 0, f'a right-click: Apple’s menu, not the page’s {labels}')
                await E("window.__native.pick = 0")
                await r.click(button='right'); await pg.wait_for_timeout(500)
                check(await E("ui.taskId") == tid, 'the one picked runs (Open Task)')
                await pg.wait_for_timeout(400)
                check(not errs, f'no page errors (13) {errs[:2]}')
                await ctx.close()
            await b.close()
    finally: srv.kill()
    print('ALL PASS' if not fails else f'FAILS {fails}')
asyncio.run(main())
