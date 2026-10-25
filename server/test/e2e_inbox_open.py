"""Inbox: a row opens the update it shows. A Task Update change with an older unread @mention on the same task opens the
task on Details, not the comment (Primary and All alike); an unread review still comes first."""
import asyncio, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18291; BASE=f'http://127.0.0.1:{PORT}'; ADMIN='haris@e11-digital.com'
async def main():
    subprocess.run(['fuser','-k',f'{PORT}/tcp'],stderr=subprocess.DEVNULL)
    env={**os.environ,'DATA_DIR':tempfile.mkdtemp(),'AUTH_DEV':'1','ADMIN_EMAIL':ADMIN,'PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.6.1-test.1'}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    ok=[]
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE+'/api/health'); break
            except Exception: time.sleep(0.1)
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/me',headers={'X-Dev-Email':ADMIN}))
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/sample/reset',method='POST',data=b'{}',headers={'X-Dev-Email':ADMIN,'Content-Type':'application/json'})).read()
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            for phone in (False, True):
                ctx=await b.new_context(viewport={'width':390,'height':844} if phone else {'width':1440,'height':900},base_url=BASE)
                await ctx.add_cookies([{'name':'e11_dev_email','value':ADMIN,'url':BASE}])
                pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(4000); await pg.keyboard.press('Shift'); await pg.wait_for_timeout(500)
                tid = await pg.evaluate("""(() => {
                  myNotifs().forEach(n => { n.read = true; });
                  const t = topTasks().find(x => !x.done && (x.comments || []).length);
                  const c = t.comments[0]; const now = Date.now();
                  db.notifications.push({ id: 'ib-m', to: currentUserId, from: c.authorId, taskId: t.id, kind: 'mention', text: 'mentioned you in', snippet: 'hi', commentId: c.id, at: new Date(now - 3600000).toISOString(), read: false });
                  db.notifications.push({ id: 'ib-u', to: currentUserId, from: c.authorId, taskId: t.id, kind: 'update', text: 'changed the Task Update on', snippet: 'Edit Video', at: new Date(now - 60000).toISOString(), read: false });
                  persist(0); return t.id; })()""")
                sel = '.ph-ib' if phone else '.ib-row'
                for tab in ('primary', 'all'):
                    await pg.evaluate("closeDetail(); myNotifs().forEach(n => { if (n.id === 'ib-m' || n.id === 'ib-u') n.read = false; })")
                    if phone:
                        await pg.locator('#ph-tabs [data-ph-tab="inbox"]').click(); await pg.wait_for_timeout(300)
                        await pg.evaluate(f"ui.inboxTab = '{tab}'; render()")
                    else:
                        await pg.evaluate(f"ui.inboxTab = '{tab}'; go('inbox')")
                    await pg.wait_for_timeout(400)
                    await pg.locator(f'{sel}[data-id="ib-u"]').first.click(); await pg.wait_for_timeout(700)
                    r = await pg.evaluate("({ task: ui.taskId, tab: ui.sideTab, focus: ui.focusComment || null })")
                    good = r['task'] == tid and r['tab'] == 'details' and not r['focus']
                    ok.append(good)
                    print(('ok  ' if good else 'FAIL'), 'phone' if phone else 'desktop', tab, 'opens the Task Update on Details', '' if good else r)
                ok.append(not errs)
                if errs: print('FAIL errors', errs[:2])
                await ctx.close()
            await b.close()
    finally:
        srv.kill()
    print('ALL PASS' if all(ok) else 'FAILS')
asyncio.run(main())
