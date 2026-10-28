"""Mac app downloads (fake Mac bridge): a message shows straight away; over the office network a Mac app 11 shows how
much has arrived and can cancel; a Mac app 10 still downloads the old way; outside the office, the usual way with %."""
import asyncio, os, tempfile, time, subprocess, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18251; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
BRIDGE = """
window.__calls = []; window.__dl = { state: 'receiving', done: 0, size: 1000 }; window.__cancelled = false;
window.webkit = { messageHandlers: { e11: { postMessage(raw) {
  const m = JSON.parse(raw); let res = { ok: true }; window.__calls.push(m.cmd + (m.args && m.args.job === true ? ':job' : ''));
  if (m.cmd === 'appInfo') res = { ok: true, shell: %d, native: 'swift', server: location.origin };
  if (m.cmd === 'downloadLocal') res = m.args.job ? { ok: true, job: 'j1' } : { ok: true, path: '/Users/x/Downloads/a' };
  if (m.cmd === 'downloadStatus') { res = { ...window.__dl, ok: true }; }
  if (m.cmd === 'downloadCancel') { window.__cancelled = true; window.__dl = { state: 'cancelled', done: 0, size: 0 }; }
  setTimeout(() => window.__e11NativeReply(m.id, res), 5);
} } } };"""
async def main():
    data_dir = tempfile.mkdtemp()
    env = {**os.environ, 'DATA_DIR': data_dir, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.9.4-test.1',
           'OFFICE_IP': '127.0.0.1', 'LOCAL_URL': 'https://127.0.0.1:18252'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            async def open_app(shell):
                ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
                await ctx.add_init_script(BRIDGE % shell)
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3000)
                return pg, errs
            pg, errs = await open_app(11)
            check(await pg.evaluate("!!(ServerHost.office() && ServerHost.office().local)"), 'in the office')
            path = await pg.evaluate("(() => { const t = db.tasks.find(t => (t.attachments || []).length); return t.attachments[0].path; })()")
            # Mac app 11: progress, then done
            await pg.evaluate(f"void (window.__p = Host.call('revealPath', {{ path: {json.dumps(path)} }}).then(() => 'ok', (e) => 'err:' + e.message))")
            await pg.wait_for_timeout(500)
            await pg.evaluate("window.__dl = { state: 'receiving', done: 450, size: 1000 }")
            await pg.wait_for_timeout(700)
            msg = await pg.evaluate("(document.querySelector('.toast.busy span') || {}).textContent || ''")
            check('over the office network' in msg and '45%' in msg, f'the message shows how much has arrived ({msg!r})')
            check(await pg.evaluate("!document.querySelector('.toast.busy button').hidden"), 'with a Cancel button')
            await pg.evaluate("window.__dl = { state: 'done', done: 1000, size: 1000, path: '/x' }")
            check(await pg.evaluate("window.__p") == 'ok', 'finishes')
            await pg.wait_for_timeout(300)
            check(await pg.evaluate("!document.querySelector('.toast.busy')"), 'the message goes away when it’s saved')
            check('downloadLocal:job' in await pg.evaluate("window.__calls"), 'asked the Mac app for a download it reports on')
            # Cancel
            await pg.evaluate("window.__dl = { state: 'receiving', done: 10, size: 1000 }")
            await pg.evaluate(f"void (window.__p = Host.call('revealPath', {{ path: {json.dumps(path)} }}).then(() => 'ok', (e) => (e.cancelled ? 'cancelled' : 'err:' + e.message)))")
            await pg.wait_for_timeout(900)
            await pg.click('.toast.busy button')
            check(await pg.evaluate("window.__p") == 'cancelled' and await pg.evaluate("window.__cancelled"), 'Cancel stops it')
            check(not errs, f'no page errors {errs}')
            # Mac app 10: the old call (no job)
            pg2, errs2 = await open_app(10)
            r = await pg2.evaluate(f"Host.call('revealPath', {{ path: {json.dumps(path)} }}).then(() => 'ok')")
            calls = await pg2.evaluate("window.__calls")
            check(r == 'ok' and 'downloadLocal' in calls and 'downloadLocal:job' not in calls, f'a Mac app 10 downloads the old way {calls[-3:]}')
            check(not errs2, f'no page errors {errs2}')
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
