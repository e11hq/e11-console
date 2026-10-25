"""Owner view (live site only) and the owner's protected account, in the browser.
A copy set up like the live site: the owner works as Production, Lana is the Admin."""
import asyncio, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OWNER='haris@e11-digital.com'; LANA='lana@e11-digital.com'
fails=[]
def check(c, m): print(('ok  ' if c else 'FAIL'), m); (None if c else fails.append(m))
def start(port, version):
    subprocess.run(['fuser','-k',f'{port}/tcp'],stderr=subprocess.DEVNULL)
    env={**os.environ,'DATA_DIR':tempfile.mkdtemp(),'AUTH_DEV':'1','ADMIN_EMAIL':OWNER,'PORT':str(port),'WEB_DIR':ROOT+'/web','APP_VERSION':version}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    base=f'http://127.0.0.1:{port}'
    for _ in range(50):
        try: urllib.request.urlopen(base+'/api/health'); break
        except Exception: time.sleep(0.1)
    return srv, base
def api(base, who, path, body=None):
    req=urllib.request.Request(base+path, method='POST' if body is not None else 'GET', data=json.dumps(body).encode() if body is not None else None, headers={'X-Dev-Email':who,'Content-Type':'application/json'})
    return json.loads(urllib.request.urlopen(req).read())
def seed(base):
    me=api(base, OWNER, '/api/me')['user']
    ch=[{'kind':'users','id':'u-lana','data':{'id':'u-lana','email':LANA,'name':'Lana Al Ramli','role':'admin','active':True,'setup':True,'prefs':{}}},
        {'kind':'users','id':'u-ali','data':{'id':'u-ali','email':'ali@e11-digital.com','name':'Ali Raza','role':'production','active':True,'setup':True,'prefs':{}}},
        {'kind':'projects','id':'p-ford','data':{'id':'p-ford','name':'Ford','color':'#3b82f6','sections':[{'id':'s1','name':'To do'}]}},
        {'kind':'projects','id':'p-alain','data':{'id':'p-alain','name':'ALAIN','color':'#7c3aed','sections':[{'id':'s2','name':'To do'}]}},
        {'kind':'tasks','id':'t-mine','data':{'id':'t-mine','title':'My Ford task','projectId':'p-ford','sectionId':'s1','assignees':[me['id']],'createdBy':'u-lana','comments':[],'tags':[],'attachments':[],'activity':[],'checklist':[],'createdAt':'2026-10-20T08:00:00Z','updatedAt':'2026-10-20T08:00:00Z'}},
        {'kind':'tasks','id':'t-other','data':{'id':'t-other','title':'Ali ALAIN task','projectId':'p-alain','sectionId':'s2','assignees':['u-ali'],'createdBy':'u-lana','comments':[],'tags':[],'attachments':[],'activity':[],'checklist':[],'createdAt':'2026-10-20T08:00:00Z','updatedAt':'2026-10-20T08:00:00Z'}}]
    api(base, OWNER, '/api/push', {'changes': ch})
    u=api(base, OWNER, '/api/snapshot')['data']['users']; mine=[x for x in u if x['id']==me['id']][0]
    api(base, OWNER, '/api/push', {'changes':[{'kind':'users','id':me['id'],'base':mine,'data':{**mine,'name':'Muhammad Haris Sharif','setup':True,'role':'production'}}]})
    return me['id']
async def page_for(b, base, email, w=1440, h=900):
    ctx=await b.new_context(viewport={'width':w,'height':h}, base_url=base)
    await ctx.add_cookies([{'name':'e11_dev_email','value':email,'url':base}])
    pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
    await pg.goto('/'); await pg.wait_for_timeout(3500); await pg.keyboard.press('Shift'); await pg.wait_for_timeout(500)
    return ctx, pg, errs
async def main():
    srv, base = start(18293, '1.6.2')
    srv2, tbase = start(18294, '1.6.2-test.200')
    try:
        hid = seed(base); seed(tbase)
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            ctx, pg, errs = await page_for(b, base, OWNER)
            E=pg.evaluate
            check(await E("me().role") == 'production' and not await E("isAdm(me())"), 'the owner works as Production')
            check(await E("db.tasks.map(t => t.id).join()") == 't-mine', 'and sees only their own tasks')
            await E("go('profile')"); await pg.wait_for_timeout(400)
            cards = await E("[...document.querySelectorAll('.profile > .pf-card')].map(c => c.classList.contains('ov-card'))")
            check(cards and cards[-1] is True and cards.count(True) == 1, 'Owner view is the last card on My profile')
            await pg.click('[data-ov="look"]'); await pg.wait_for_timeout(1500)
            check(await E("isAdm(me()) && me().role === 'production'"), 'stepped in: Admin rights, role still Production')
            check(await E("finLevel() === 'admin'"), 'and Finance Admin')
            check(await E("/Finance/.test(document.querySelector('#sidebar, .sidebar, nav').innerText)"), 'Finance shows in the sidebar')
            check(await E("db.tasks.some(t => t.id === 't-other')"), 'sees every task')
            check(await pg.locator('#ov-bar').is_visible() and 'Look only' in await pg.locator('#ov-bar').inner_text(), 'the bar says Look only')
            await pg.wait_for_timeout(3500); await pg.screenshot(path='/tmp/claude-0/-home-claude/cbe383c5-0a7d-5e51-824e-d5c89984d379/scratchpad/ov-look.png')
            # look only: a change is put back, the server keeps the old title
            await E("(() => { const t = task('t-other'); t.title = 'Changed while looking'; persist(0); })()"); await pg.wait_for_timeout(1200)
            check(await E("task('t-other').title") == 'Ali ALAIN task', 'look only: the change is put back in the app')
            check(api(base, LANA, '/api/snapshot')['data']['tasks'][1]['title'] if False else [t for t in api(base, LANA, '/api/snapshot')['data']['tasks'] if t['id']=='t-other'][0]['title'] == 'Ali ALAIN task', '...and nothing reached the server')
            # Lana sees nothing different
            lana_h=[u for u in api(base, LANA, '/api/snapshot')['data']['users'] if u['id']==hid][0]
            check(lana_h['role'] == 'production' and not lana_h.get('admin'), 'Lana still sees Production, no Admin rights')
            # allow changes
            await pg.click('#ov-bar [data-ov="edit"]'); await pg.wait_for_timeout(300)
            await pg.click('.dialog [data-r="1"]'); await pg.wait_for_timeout(800)
            check('Changes ON' in await pg.locator('#ov-bar').inner_text(), 'the bar says Changes ON')
            await E("(() => { const t = task('t-other'); t.title = 'Renamed by owner'; persist(0); })()"); await pg.wait_for_timeout(1500)
            check([t for t in api(base, LANA, '/api/snapshot')['data']['tasks'] if t['id']=='t-other'][0]['title'] == 'Renamed by owner', 'with changes allowed, the change is saved')
            # the owner can change their own role from their Team row (nobody else can)
            await E("go('team')"); await pg.wait_for_timeout(300)
            await E(f"memberMenu(document.body, '{hid}')"); await pg.wait_for_timeout(300)
            check('your role (owner)' in (await pg.locator('.menu').last.inner_text()).lower(), 'the owner’s own row offers Your role')
            await pg.keyboard.press('Escape'); await E("closeMenus()")
            # the profile save in Owner view doesn't store Admin rights
            await E("go('profile')"); await pg.wait_for_timeout(300)
            await pg.click('[data-action="save-profile"]'); await pg.wait_for_timeout(1200)
            lana_h=[u for u in api(base, LANA, '/api/snapshot')['data']['users'] if u['id']==hid][0]
            check(lana_h['role'] == 'production' and not lana_h.get('admin') and not lana_h.get('fin'), 'saving the profile in Owner view keeps the stored role and access')
            # back to Production
            await pg.click('#ov-bar [data-ov="off"]'); await pg.wait_for_timeout(1500)
            check(not await E("isAdm(me())") and not await E("finLevel()") and await E("db.tasks.map(t => t.id).join()") == 't-mine' and await pg.locator('#ov-bar').count() == 0, 'Back to Production: own tasks only, no Finance, no bar')
            # a reload ends it
            await E("go('profile')"); await pg.wait_for_timeout(300)
            await pg.click('[data-ov="look"]'); await pg.wait_for_timeout(1500)
            await pg.reload(); await pg.wait_for_timeout(3500); await pg.keyboard.press('Shift'); await pg.wait_for_timeout(500)
            check(not await E("isAdm(me())") and await pg.locator('#ov-bar').count() == 0, 'a reload ends Owner view')
            check(not errs, f'no page errors {errs[:2]}')
            # Lana: the owner's row is locked on the Team page; the server refuses anyway
            c2, lp, errs2 = await page_for(b, base, LANA)
            await lp.evaluate("go('team')"); await lp.wait_for_timeout(500)
            await lp.evaluate(f"memberMenu(document.body, '{hid}')"); await lp.wait_for_timeout(300)
            txt = await lp.locator('.menu').last.inner_text()
            check('only the owner can change this account' in txt.lower() and await lp.locator('.menu .mi.disabled').count() == 4, 'Team page: the owner’s row is locked for Lana')
            await lp.keyboard.press('Escape'); await lp.evaluate("closeMenus()")
            await lp.evaluate("memberMenu(document.body, currentUserId)"); await lp.wait_for_timeout(300)
            check('your role' not in (await lp.locator('.menu').last.inner_text()).lower(), 'other Admins can’t change their own role')
            await lp.evaluate("closeMenus()")
            await lp.evaluate(f"(() => {{ const u = userById('{hid}'); u.active = false; u.role = 'social'; persist(0); }})()"); await lp.wait_for_timeout(1500)
            st=[u for u in api(base, OWNER, '/api/snapshot')['data']['users'] if u['id']==hid][0]
            check(st['active'] is True and st['role'] == 'production', 'even forced, the owner is not deactivated or changed')
            check(not errs2, f'no page errors (Lana) {errs2[:2]}')
            # the test site: no Owner view
            c3, tp, errs3 = await page_for(b, tbase, OWNER)
            await tp.evaluate("go('profile')"); await tp.wait_for_timeout(400)
            check(await tp.locator('.ov-card').count() == 0, 'not on the test site')
            # phone: the card is at the bottom of My profile
            c4, ph, errs4 = await page_for(b, base, OWNER, 390, 844)
            await ph.evaluate("go('profile')"); await ph.wait_for_timeout(500)
            last = await ph.evaluate("(() => { const cs = [...document.querySelectorAll('.profile > .pf-card')]; return cs.length && cs[cs.length - 1].classList.contains('ov-card'); })()")
            check(last, 'phone: Owner view is the last card on My profile')
            await ph.click('[data-ov="look"]'); await ph.wait_for_timeout(1500)
            check(await ph.locator('#ov-bar').is_visible(), 'phone: the bar shows')
            await ph.wait_for_timeout(3500); await ph.screenshot(path='/tmp/claude-0/-home-claude/cbe383c5-0a7d-5e51-824e-d5c89984d379/scratchpad/ov-phone.png')
            check(not errs4, f'no page errors (phone) {errs4[:2]}')
            await b.close()
    finally:
        srv.kill(); srv2.kill()
    print('ALL PASS' if not fails else f'FAILS {fails}')
asyncio.run(main())
