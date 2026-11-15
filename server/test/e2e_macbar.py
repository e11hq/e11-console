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
  if (m.cmd === 'appInfo') res = { ok: true, shell: window.__shell || 13, native: 'swift', preview: (window.__shell || 13) >= 13 };
  if (m.cmd === 'pageBar') window.__native.bar = m.args;
  if (m.cmd === 'menu') { window.__native.menu = m.args; res = window.__native.pick == null ? { ok: true } : { ok: true, i: window.__native.pick }; }
  if (m.cmd === 'openURL') window.__native.opened = m.args.url;
  if (m.cmd === 'splash') { (window.__native.splash = window.__native.splash || []).push(m.args); res = m.args.out ? { ok: true, shown: true, goneIn: 300 } : { ok: true, shown: true }; }
  if (m.cmd === 'preview') window.__native.preview = m.args;
  if (m.cmd === 'sidebar') res = { ok: true, overlay: true, room: 252, slim: 0 };
  if (m.cmd === 'symbols') res = { ok: true, images: Object.fromEntries(m.args.names.map((n) => [n, 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='])) };
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
                await ctx.add_init_script(f'window.__shell = {shell};' + BRIDGE + ("window.__e11NativeSplash = true;" if shell == 13 else ''))
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3500); E = pg.evaluate
                await E("go('home')"); await pg.wait_for_timeout(500)
                if shell == 12:
                    check(not await E("MacBar.on()") and await E("getComputedStyle(document.querySelector('#topbar .search')).visibility") == 'visible', 'an older Mac app keeps the page’s own search')
                    await pg.locator('.hm-lead .hm-row').first.click(button='right'); await pg.wait_for_timeout(200)
                    check(await pg.locator('.menu .mi').count() > 0 and await E("window.__native.menu") is None, '...and the page’s own menu')
                    check(not await E("document.documentElement.classList.contains('mac-sf')"), 'an older Mac app keeps the page\u2019s own icons')
                    check(not errs, f'no page errors (12) {errs[:2]}')
                    await ctx.close(); continue
                check(await E("getComputedStyle(document.querySelector('#topbar .search')).visibility") == 'visible' and await E("window.__native.bar") is None, 'the top bar stays the page\u2019s own (Talk and search)')
                # the Mac's own startup screen: the page's never shown, the page said hello and then out, the sidebar painted
                sp = await E("[!!document.getElementById('splash') || !document.documentElement.classList.contains('native-splash'), (window.__native.splash || []).map((a) => Object.keys(a)[0]).filter((k) => k !== 'status'), window.__native.calls.includes('sidebar')]")
                check(sp == [False, ['hello', 'out'], True], f'the startup screen is the Mac app\u2019s own; the page and sidebar ready behind it {sp}')
                # Home (Haris 2026-11-15 14:08–14:12): opens on Today; Team goals achieved above Schedule, its ring filling once;
                # the clients' lines growing once, their colour easing lighter to the right
                hm = await E("(() => { const a = document.querySelector('.hm-lead aside'); return [document.querySelector('.hm-tab.on').dataset.v, a.firstElementChild.classList.contains('hm-goal'), !!a.querySelector('.hm-goal + .hm-card .hm-h h2') && a.querySelector('.hm-goal + .hm-card .hm-h h2').textContent, !!document.querySelector('.hm-hero'), getComputedStyle(document.querySelector('.hm-pbar i')).backgroundImage.startsWith('linear-gradient')]; })()")
                check(hm == ['today', True, 'Schedule', False, True], f'Home: Today first, Team goals achieved above Schedule, the clients\u2019 lines a gradient {hm}')
                await pg.screenshot(path=os.environ.get('SHOT_DIR', '/tmp') + '/macbar-home.png')
                # hidden completely: the page the whole window wide — the app's slim 0 is 0, not the old 108 (Haris 14:39)
                await E("setSidebarCollapsed(true)"); await pg.wait_for_timeout(500)
                pl = await E("getComputedStyle(document.getElementById('app')).paddingLeft")
                await E("setSidebarCollapsed(false)"); await pg.wait_for_timeout(500)
                check(pl == '0px', f'the sidebar hidden: the page the whole window wide {pl}')
                await pg.hover('.hm-stat'); await pg.wait_for_timeout(100)
                hv = await E("getComputedStyle(document.querySelector('.hm-stat')).backgroundImage")
                check(hv.startswith('linear-gradient'), f'a top card pointed at: the Talk button\u2019s hover {hv[:40]}')
                w0 = await E("document.querySelector('#topbar .search').getBoundingClientRect().width")
                await pg.focus('#topbar .search input'); await pg.wait_for_timeout(400)
                w1 = await E("document.querySelector('#topbar .search').getBoundingClientRect().width")
                await E("document.activeElement.blur()"); await pg.wait_for_timeout(400)
                check(w0 == 220 and w1 == 300, f'the search: a little wider while typing {w0} → {w1}')
                # a file opened: the Mac app's own preview — the files of its group, which one, where its thumbnail was (16:06)
                await E("(() => { const t = db.tasks.find((x) => (x.attachments || []).length > 1); window.__pvT = t && t.id; if (t) previewFile(t.attachments[1], t.attachments); })()")
                await pg.wait_for_timeout(300)
                pv = await E("window.__native.preview && [window.__native.preview.files.length, window.__native.preview.at, !!window.__native.preview.files[0].kind, document.body.classList.contains('pv-open')]")
                check(pv is not None and pv[1] == 1 and pv[2] and pv[3] is False, f'a file opened: the Mac app\u2019s own preview, not the page\u2019s {pv}')
                await E("window.__e11Preview({ ev: 'closed' })")
                # scroll bars: WebKit's hidden, a thin overlay bar while a list scrolls, gone a moment after (17:19)
                await E("(() => { const l = document.querySelector('.hm-cl-list') || document.getElementById('content'); l.scrollTop = 40; l.dispatchEvent(new Event('scroll')); })()")
                await pg.wait_for_timeout(200)
                sb1 = await E("[...document.querySelectorAll('.mac-sb')].some((b) => b.classList.contains('on'))")
                await pg.wait_for_timeout(1500)
                sb2 = await E("[...document.querySelectorAll('.mac-sb')].some((b) => b.classList.contains('on'))")
                hid = await E("getComputedStyle(document.documentElement).scrollbarWidth")
                check(sb2 is False and hid == 'none', f'scroll bars: a thin one while scrolling, gone after {sb1, sb2, hid}')
                # Home fills the window: both columns end at its bottom (Haris 2026-11-15 15:28)
                fill = await E("(() => { const c = document.getElementById('content').getBoundingClientRect(), cols = [...document.querySelectorAll('.hm-grid > .hm-col')].map((x) => Math.round(x.getBoundingClientRect().bottom)); return [cols[0] === cols[1], cols[0] >= Math.round(c.bottom) - 30]; })()")
                check(fill == [True, True], f'Home fills the window, both columns ending together {fill}')
                st0 = await E("[!!window.__e11ShownAt, document.documentElement.classList.contains('e11-shown')]")
                check(st0 == [True, True], f'the page marked on show once the startup screen has gone {st0}')
                await pg.wait_for_timeout(1300); await E("render()"); await pg.wait_for_timeout(100)
                again = await E("[document.querySelectorAll('.hm-pbar i.hm-grow').length, document.querySelectorAll('.hm-ring.hm-grow').length]")
                check(again == [0, 0], f'drawn again later: the lines and the ring stay still {again}')
                # Apple's SF Symbols for Home's icons (and the top bar's), the page's drawings hidden under them (Haris 2026-11-15)
                await pg.wait_for_timeout(300)
                sf = await E("(() => { const e = document.querySelector('.hm [data-i=\"hm-chat\"]'); const t = document.querySelector('#topbar [data-i=\"search\"]'); const c = getComputedStyle(e); return [document.documentElement.classList.contains('mac-sf'), (c.webkitMaskImage || c.maskImage || '').startsWith('url('), getComputedStyle(e.firstElementChild).visibility, (getComputedStyle(t).webkitMaskImage || '').startsWith('url(')]; })()")
                check(sf == [True, True, 'hidden', True], f'Home and the top bar: SF Symbols in the Mac app 13 {sf}')
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
