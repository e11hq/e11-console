"""Finance for Admins: Super Admin and Office Admin see Finance only with + Finance (Super Admin: the Finance button; Office
Admin: a Finance heading with Dashboard, Clients, Reimbursements, Expenses — with data). Both can add it to themselves."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18299; BASE=f'http://127.0.0.1:{PORT}'; OWNER='haris@e11-digital.com'
SA='sami@e11-digital.com'; OA='arsal@e11-digital.com'
def api(who,p,body=None):
    r=urllib.request.Request(BASE+p,method='POST' if body is not None else 'GET',data=json.dumps(body).encode() if body is not None else None,headers={'X-Dev-Email':who,'Content-Type':'application/json'}); return json.loads(urllib.request.urlopen(r).read())
async def main():
    subprocess.run(['fuser','-k',f'{PORT}/tcp'],stderr=subprocess.DEVNULL)
    env={**os.environ,'DATA_DIR':tempfile.mkdtemp(),'AUTH_DEV':'1','ADMIN_EMAIL':OWNER,'PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.6.1-test.1'}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    ok=[]
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE+'/api/health'); break
            except Exception: time.sleep(0.1)
        api(OWNER,'/api/me'); api(OWNER,'/api/sample/reset',{})
        mk=lambda i,e,r: {'kind':'users','id':i,'data':{'id':i,'email':e,'name':i,'role':r,'active':True,'setup':True,'prefs':{}}}
        api(OWNER,'/api/push',{'changes':[mk('u-sami',SA,'admin'), mk('u-arsal',OA,'office_admin')]})
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            for who,tag in ((SA,'Super Admin'),(OA,'Office Admin')):
                ctx=await b.new_context(viewport={'width':1440,'height':900},base_url=BASE)
                await ctx.add_cookies([{'name':'e11_dev_email','value':who,'url':BASE}])
                pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(4000)
                seen = lambda: pg.evaluate("[...document.querySelectorAll('#sidebar [data-nav^=\"fin-\"]')].filter(e => e.offsetParent).map(e => e.dataset.nav)")
                check(await seen() == [], f'{tag} without + Finance: no Finance in the sidebar', await seen())
                await pg.evaluate("go('fin-dash')"); await pg.wait_for_timeout(500)
                check(await pg.evaluate("ui.view") != 'fin-dash', f'{tag} without + Finance: Finance pages don’t open')
                if tag == 'Office Admin':
                    check(await pg.locator('.oh .oh-card h2', has_text='Finance').count() == 0, 'Office Admin without + Finance: no Finance box on Home')
                # give themselves Finance Admin from their own row on the Team page
                await pg.evaluate("go('team')"); await pg.wait_for_timeout(600)
                await pg.evaluate("memberMenu(document.body, currentUserId)"); await pg.wait_for_timeout(300)
                await pg.locator('.menu .mi', has_text='Finance Admin').first.click(); await pg.wait_for_timeout(2500)
                nav = await seen()
                want = ['fin-dash'] if tag == 'Super Admin' else ['fin-dash', 'fin-projects', 'fin-reimb', 'fin-expenses']
                check(nav == want, f'{tag} gives themselves + Finance Admin: {"the Finance button" if tag == "Super Admin" else "Finance heading with Dashboard, Clients, Reimbursements, Expenses"}', nav)
                for v in ('fin-dash', 'fin-projects'):
                    await pg.evaluate(f"go('{v}')"); await pg.wait_for_timeout(900)
                    n = await pg.evaluate("db.tasks.filter(t => !t.parentId).length")
                    txt = await pg.locator('#content').inner_text()
                    check(n > 10 and 'Invoiced' in txt, f'{tag} with + Finance: {v} shows the jobs ({n} tasks)')
                if tag == 'Office Admin':
                    await pg.evaluate("go('home')"); await pg.wait_for_timeout(600)
                    check(await pg.locator('.oh .oh-card h2', has_text='Finance').count() == 1, 'Office Admin with + Finance: Finance box on Home')
                    check(await pg.evaluate("db.tasks.every(t => t.notesHtml === undefined && !(t.comments || []).length)"), 'Office Admin still gets no task details (Finance view only)')
                check(not errs, f'{tag}: no page errors', errs)
                await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
