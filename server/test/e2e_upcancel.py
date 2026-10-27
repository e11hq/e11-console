"""Uploads can be cancelled with the × on their progress row: the upload stops, nothing is attached, and what already
reached the server is deleted. Files deleted for good leave nothing behind (no hidden trash folder)."""
import asyncio, os, tempfile, time, subprocess, urllib.request, glob
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18245; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    data = tempfile.mkdtemp()
    env = {**os.environ, 'DATA_DIR': data, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.8.1-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(3000)
            # slow pieces, like a big file on a slow connection
            async def slow(route):
                await asyncio.sleep(1.2); await route.continue_()
            await pg.route('**/api/host/writeChunkBin*', slow)
            tid = await pg.evaluate("db.tasks.find(t => !t.parentId && !t.done).id")
            await pg.evaluate(f"(() => {{ window.__up = ServerHost.uploadMany([new File([new Uint8Array(30 * 1024 * 1024)], 'big-video.mp4')], {{ taskId: '{tid}' }}); }})()")
            await pg.wait_for_selector('.up-row .up-x'); await pg.wait_for_timeout(1800)
            check(await pg.locator('.up-row .up-x').count() == 1, 'the progress row has a × to cancel')
            await pg.click('.up-row .up-x'); await pg.wait_for_timeout(300)
            check((await pg.inner_text('.up-row small')) == 'Cancelled', 'the row says Cancelled')
            got = await pg.evaluate("window.__up.then(l => l.length)")
            check(got == 0, f'nothing is attached ({got})')
            await pg.wait_for_timeout(2500)
            left = [f for f in glob.glob(os.path.join(data, 'files', 'attachments', '**', 'big-video*'), recursive=True)]
            check(not left, f'the part already sent is deleted from the server {left}')
            hidden = glob.glob(os.path.join(data, 'files', 'trash', '**', 'big-video*'), recursive=True) + glob.glob(os.path.join(data, 'trash', '**', 'big-video*'), recursive=True)
            check(not hidden, f'nothing kept in a hidden trash folder {hidden}')
            # a second upload not cancelled still works
            await pg.unroute('**/api/host/writeChunkBin*')
            n = await pg.evaluate(f"ServerHost.uploadMany([new File([new Uint8Array(1024)], 'small.txt')], {{ taskId: '{tid}' }}).then(l => l.length)")
            check(n == 1, 'an upload left alone finishes')
            check(not errs, f'no page errors {errs}')
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
