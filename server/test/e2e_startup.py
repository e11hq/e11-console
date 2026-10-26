"""Opening the app on a weak connection (phone Home Screen app): no blank screen.
- slow or failing server at startup: the startup screen says "Connecting…" with Try again and opens by itself once it answers
- a crash while opening: "Something went wrong · Reload", reported to the server
- the server unreachable for the first page: the service worker's "Connecting…" page, which reloads into the app once it's back"""
import asyncio, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18297; BASE=f'http://127.0.0.1:{PORT}'; A='haris@e11-digital.com'
fails=[]
def check(c, m): print(('ok  ' if c else 'FAIL'), m); (None if c else fails.append(m))
DATA=tempfile.mkdtemp()
def start():
    subprocess.run(['fuser','-k',f'{PORT}/tcp'],stderr=subprocess.DEVNULL)
    env={**os.environ,'DATA_DIR':DATA,'AUTH_DEV':'1','ADMIN_EMAIL':A,'PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.6.5-test.1'}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    for _ in range(80):
        try: urllib.request.urlopen(BASE+'/api/health'); return srv
        except Exception: time.sleep(0.1)
    return srv
async def main():
    srv=start()
    try:
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/me',headers={'X-Dev-Email':A}))
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            ctx=await b.new_context(viewport={'width':390,'height':844}, base_url=BASE, service_workers='allow')
            await ctx.add_cookies([{'name':'e11_dev_email','value':A,'url':BASE}])
            pg=await ctx.new_page()
            # 1) the server doesn't answer /api/me twice (slow, then failing): Connecting… on the startup screen, then it opens
            n={'me':0}
            async def me_route(route):
                n['me']+=1
                if n['me']==1: await asyncio.sleep(13); await route.abort()       # longer than the 12 s limit
                elif n['me']==2: await route.abort()
                else: await route.continue_()
            await pg.route('**/api/me', me_route)
            await pg.goto('/'); await pg.wait_for_timeout(14000)
            hint = await pg.locator('#sp-hint').inner_text()
            check('Connecting' in hint or 'connecting' in hint, f'the startup screen says it is connecting ({hint!r})')
            check(await pg.locator('#sp-hint .sp-retry').count() == 1, '...with Try again')
            await pg.locator('#sp-hint .sp-retry').click()
            for _ in range(40):
                await pg.wait_for_timeout(500)
                if await pg.evaluate("!!((typeof currentUserId !== 'undefined' && currentUserId) && document.getElementById('app') && !document.getElementById('splash'))"): break
            check(await pg.evaluate("!!currentUserId") and n['me'] >= 3, f'it opens once the server answers (tries: {n["me"]})')
            await pg.unroute('**/api/me')
            # 2) a crash while opening: Something went wrong, reported
            pg2=await ctx.new_page()
            async def slow_snap(route): await asyncio.sleep(2); await route.continue_()
            await pg2.route('**/api/snapshot', slow_snap)
            await pg2.goto('/'); await pg2.wait_for_timeout(600)
            await pg2.evaluate("setTimeout(() => { throw new Error('boom while opening'); }, 0)")
            await pg2.wait_for_timeout(1500)
            check('Something went wrong' in await pg2.locator('body').inner_text(), 'a crash while opening shows Something went wrong · Reload')
            errs=json.loads(urllib.request.urlopen(urllib.request.Request(BASE+'/api/client-errors',headers={'X-Dev-Email':A})).read())['errors']
            check(any('boom while opening' in e['message'] and e['where']=='opening' for e in errs), 'and it was reported to the server')
            await pg2.close()
            # 3) the server is down when the app is opened: the service worker shows Connecting…, then reloads into the app
            await pg.reload(); await pg.wait_for_timeout(4000)
            check(await pg.evaluate("navigator.serviceWorker && navigator.serviceWorker.controller ? true : false"), 'the service worker is in charge')
            srv.kill(); srv.wait(); subprocess.run(['fuser','-k',f'{PORT}/tcp'],stderr=subprocess.DEVNULL)
            try: await pg.goto('/', timeout=15000)
            except Exception as e: print('  goto:', str(e)[:80])
            await pg.wait_for_timeout(1000)
            body = await pg.locator('body').inner_text()
            check('Connecting' in body or 'offline' in body, f'server down: the Connecting screen, not a blank page ({body[:40]!r})')
            srv=start()
            for _ in range(40):
                await pg.wait_for_timeout(500)
                try:
                    if await pg.evaluate("!!(typeof currentUserId !== 'undefined' && currentUserId)"): break
                except Exception: pass
            ok3 = await pg.evaluate("!!(typeof currentUserId !== 'undefined' && currentUserId)")
            if not ok3: print('  debug', (await pg.locator('body').inner_text())[:200].replace('\n',' | '))
            check(ok3, 'back up: it reloads into the app by itself')
            await b.close()
    finally:
        srv.kill()
    print('ALL PASS' if not fails else f'FAILS {fails}')
asyncio.run(main())
