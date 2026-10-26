"""CD review on and not approved: statuses past Review are locked in the menu, choosing one is refused, completing is
refused — with or without assignees, Admin included. Approved (or CD review off): free again."""
import asyncio, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18293; BASE=f'http://127.0.0.1:{PORT}'; ADMIN='haris@e11-digital.com'
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
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/me',headers={'X-Dev-Email':ADMIN}))
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/sample/reset',method='POST',data=b'{}',headers={'X-Dev-Email':ADMIN,'Content-Type':'application/json'})).read()
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            ctx=await b.new_context(viewport={'width':1440,'height':900},base_url=BASE)
            await ctx.add_cookies([{'name':'e11_dev_email','value':ADMIN,'url':BASE}])
            pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(4000)
            tid = await pg.evaluate("""(() => { const p = db.projects.find(p => statusList({ projectId: p.id }).some(s => /^review$/i.test(s.name)));
              const s0 = statusList({ projectId: p.id }).find(s => !/^to ?do$/i.test(s.name));
              const t = createTask({ projectId: p.id, sectionId: s0.id, title: 'CD gate check' }); t.needsCD = true; t.assignees = []; t.cdStatus = null; persist(0); return t.id; })()""")
            await pg.evaluate(f"openTask('{tid}')"); await pg.wait_for_timeout(700)
            T = f"db.tasks.find(t => t.id === '{tid}')"
            async def menu():
                await pg.locator('#detail [data-action="status-menu"]').first.click(); await pg.wait_for_timeout(300)
                r = await pg.evaluate("[...document.querySelectorAll('.menu .mi')].map(m => [m.textContent.trim(), m.classList.contains('mi-locked')])")
                await pg.keyboard.press('Escape'); await pg.wait_for_timeout(200); return r
            for who in ('nobody assigned', 'assigned'):
                if who == 'assigned':
                    await pg.evaluate(f"{T}.assignees = [db.users.find(u => u.role === 'production').id]; persist(0); render({{ keepDetail: true }})"); await pg.wait_for_timeout(300)
                m = await menu()
                names = [n for n, _ in m]; ri = next(i for i, n in enumerate(names) if n.lower() == 'review')
                check(all(l for _, l in m[ri+1:]) and not any(l for _, l in m[:ri+1]), f'{who}: statuses after Review are locked, the rest are open', m)
                later = await pg.evaluate(f"(() => {{ const l = statusList({T}); const i = l.findIndex(s => /^review$/i.test(s.name)); return l.slice(i + 1).map(s => s.id); }})()")
                for sid in later:
                    await pg.evaluate(f"changeStatus({T}, '{sid}')"); await pg.wait_for_timeout(200)
                check(await pg.evaluate(f"!later_ok_placeholder" .replace('later_ok_placeholder', f"{T}.done || {later}.includes({T}.sectionId)")), f'{who}: choosing CTR / Done is refused')
                msg = await pg.evaluate(f"completeBlockedMsg({T})")
                check(not await pg.evaluate(f"canComplete({T})") and ('Creative Director' in msg), f'{who}: completing is refused — "{msg}"')
            await pg.evaluate(f"{T}.cdStatus = 'approved'; persist(0); render({{ keepDetail: true }})"); await pg.wait_for_timeout(300)
            m = await menu(); check(not any(l for _, l in m), 'approved: nothing locked', m)
            done = await pg.evaluate(f"(() => statusList({T}).find(s => isDoneName(s.name)).id)()")
            await pg.evaluate(f"changeStatus({T}, '{done}')"); await pg.wait_for_timeout(1200)
            check(await pg.evaluate(f"{T}.sectionId === '{done}' && canComplete({T})"), 'approved: moves to Done and can be completed')
            check(not errs, 'no page errors', errs)
            await b.close()
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
