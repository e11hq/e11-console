"""Part B step 1: the app's own tab bar (web/appview.js tabs) — the same tabs, labels and counts as the page's own phone
tab bar, for every kind of person: the owner, the CD, a Social Executive, Production, an Account Manager, the Office Admin."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18321; BASE=f'http://127.0.0.1:{PORT}'; ADMIN='haris@e11-digital.com'
PEOPLE = [ADMIN, 'carine@e11-digital.com', 'aishwarya@e11-digital.com', 'ali@e11-digital.com', 'areej@e11-digital.com', 'arsal@e11-digital.com', 'maria@e11-digital.com']
async def main():
    subprocess.run(['fuser','-k',f'{PORT}/tcp'],stderr=subprocess.DEVNULL)
    env={**os.environ,'DATA_DIR':tempfile.mkdtemp(),'AUTH_DEV':'1','ADMIN_EMAIL':ADMIN,'PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.6.1-test.1'}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    ok=[]
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE+'/api/health'); break
            except Exception: time.sleep(0.1)
        H={'X-Dev-Email':ADMIN}
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/me',headers=H))
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/sample/reset',method='POST',data=b'{}',headers={**H,'Content-Type':'application/json'})).read()
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            for who in PEOPLE:
                ctx=await b.new_context(viewport={'width':390,'height':844},device_scale_factor=2,is_mobile=True,has_touch=True,base_url=BASE)
                await ctx.add_cookies([{'name':'e11_dev_email','value':who,'url':BASE}])
                pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(4500)
                page_tabs = await pg.evaluate("[...document.querySelectorAll('#ph-tabs [data-ph-tab]')].map(b => ({ v: b.dataset.phTab, label: ([...b.querySelectorAll('span')].pop() || {}).textContent || '', badge: (b.querySelector('.ph-badge') || {}).textContent || '' }))")
                app = await pg.evaluate("""(async () => {
                  const src = await (await fetch('/appview.js')).text(); (0, eval)(src);
                  const snap = await (await fetch('/api/snapshot')).json();
                  return E11AppView.tabs(E11Rules, snap.data, currentUserId, () => Date.now());
                })()""")
                # the page adds the due-today count to its first tab (phone.js nativeTabs) — as the app's tab bar shows it
                due = await pg.evaluate("(() => { try { return isOffice() ? 0 : R().myDayData().due.length; } catch (e) { return 0; } })()")
                want = [dict(t) for t in page_tabs]
                if want and want[0]['v'] == 'today' and not want[0]['badge'] and due: want[0]['badge'] = str(due)
                got = [dict(t) for t in (app or {}).get('tabs', [])]
                for t in got + want:
                    if t['v'] == 'plans': t['badge'] = ''   # (Plans' count: still the page's)
                check(got == want, f'{who}: the same tabs, labels and counts', f'\n   app:  {got}\n   page: {want}')
                check(not errs, f'{who}: no page errors', errs)
                await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
