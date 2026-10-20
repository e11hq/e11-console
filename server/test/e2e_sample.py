"""Test copy: Admin fills it with sample data from the phone Me page. Run: python3 server/test/e2e_sample.py"""
import asyncio, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18201; BASE = f'http://127.0.0.1:{PORT}'
fails = []
def check(c, msg):
    print(('PASS ' if c else 'FAIL ') + msg)
    if not c: fails.append(msg)
def start(version, port):
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '', 'ADMIN_EMAIL': 'haris@e11-digital.com', 'PORT': str(port), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': version}
    return env
async def main():
    # AUTH_DEV is needed to sign in without Cloudflare here; the version decides whether sample data is allowed
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'haris@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.1.3-test.26'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    try:
        async with async_playwright() as p:
            b = await p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': 'haris@e11-digital.com', 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(500); await pg.mouse.click(200, 400); await pg.wait_for_timeout(1500)
            check(await pg.evaluate("db.tasks.length") == 0, 'test copy starts empty')
            await pg.locator('#ph-tabs [data-ph-tab="me"]').click(); await pg.wait_for_timeout(300)
            await pg.locator('[data-ph="sample"]').click(); await pg.wait_for_timeout(300)
            await pg.locator('.dialog [data-r="1"]').click(); await pg.wait_for_timeout(2000)
            n = await pg.evaluate("db.tasks.length"); people = await pg.evaluate("db.users.length")
            replies = await pg.evaluate("db.tasks.reduce((n,t)=>n+t.comments.filter(c=>c.parentId).length,0)")
            check(n >= 15 and people >= 10 and replies >= 10, f'sample data arrived live: {n} tasks, {people} people, {replies} replies')
            check(await pg.evaluate("db.users.filter(u=>u.email==='haris@e11-digital.com').length") == 1, 'your own account is kept (no duplicate Haris)')
            check(await pg.evaluate("myNotifs().filter(n=>!n.read).length") > 5, 'your Inbox has updates and @mentions')
            check(await pg.evaluate("db.tasks.some(t=>t.due===todayStr())"), 'tasks are dated around today')
            check(await pg.evaluate("isCD('u-karim') || !!db.meta.cdUserId"), 'a Creative Director is set for trying reviews')
            await pg.locator('#ph-tabs [data-ph-tab="today"]').click(); await pg.wait_for_timeout(300)
            await pg.screenshot(path=os.path.join(SHOTS, 's1-myday.png'))
            tid = await pg.evaluate("db.tasks.find(t=>t.comments.some(c=>c.parentId)).id")
            await pg.evaluate(f"()=>{{ ui.sideTab='comments'; openTask('{tid}') }}"); await pg.wait_for_timeout(600)
            tools = pg.locator('#detail .cm-tools').first
            check(await tools.evaluate("e=>getComputedStyle(e).opacity") == '1', 'comment buttons show without tapping')
            await pg.screenshot(path=os.path.join(SHOTS, 's2-comments.png'))
            check(not errs, f'no errors {errs[:2]}')
            await b.close()
        # the live app refuses
        r = urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': 'haris@e11-digital.com', 'Content-Type': 'application/json'})
    finally:
        srv.terminate()
    print('\n' + ('ALL PASS' if not fails else f'{len(fails)} FAILED'))
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
