"""Opening updates: a phone notification tapped before its update reaches the app still opens the right place (Review
Requests for the CD, the comment, the Client Assets folder); an Inbox row shows the newest update unless an unread one
needs action (files waiting for the CD, amendments); an Office Admin's task link stays on Home with a note."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18315; BASE=f'http://127.0.0.1:{PORT}'; OWNER='haris@e11-digital.com'
def api(who,p,body=None):
    r=urllib.request.Request(BASE+p,method='POST' if body is not None else 'GET',data=json.dumps(body).encode() if body is not None else None,headers={'X-Dev-Email':who,'Content-Type':'application/json'}); return json.loads(urllib.request.urlopen(r).read())
async def main():
    subprocess.run(['fuser','-k',f'{PORT}/tcp'],stderr=subprocess.DEVNULL)
    env={**os.environ,'DATA_DIR':tempfile.mkdtemp(),'AUTH_DEV':'1','ADMIN_EMAIL':OWNER,'PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.6.5-test.1'}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    ok=[]
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE+'/api/health'); break
            except Exception: time.sleep(0.1)
        api(OWNER,'/api/me'); api(OWNER,'/api/sample/reset',{})
        api(OWNER,'/api/push',{'changes':[{'kind':'users','id':'u-offa','data':{'id':'u-offa','email':'office@e11-digital.com','name':'Office','role':'office_admin','fin':'admin','active':True,'setup':True,'prefs':{}}}]})
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            c=await b.new_context(viewport={'width':390,'height':844},base_url=BASE,is_mobile=True,has_touch=True)
            await c.add_cookies([{'name':'e11_dev_email','value':'carine@e11-digital.com','url':BASE}])
            p=await c.new_page(); errs=[]; p.on('pageerror', lambda e: errs.append(str(e)))
            await p.goto('/'); await p.wait_for_timeout(3500)
            info=await p.evaluate("""(() => { const t = topTasks().find(x => !x.done && (x.comments || []).length && x.projectId), c0 = t.comments[t.comments.length - 1];
              const other = db.users.find(u => u.id !== currentUserId && u.active !== false && !isFinUser(u)).id; const cl = clientsSorted()[0];
              return { t: t.id, c: c0.id, other, cl: cl.id, f: cl.folders[0].id }; })()""")
            async def late(n, want, label):
                await p.evaluate("(() => { if (ui.taskId) closeDetail(); ui.focusComment = null; go('home'); })()"); await p.wait_for_timeout(300)
                nj=json.dumps(n); hint=json.dumps({'kind':n['kind'],'clientId':n.get('clientId'),'folderId':n.get('folderId'),'commentId':n.get('commentId')})
                await p.evaluate(f"(() => {{ navigator.serviceWorker.dispatchEvent(new MessageEvent('message', {{ data: {{ type: 'open-task', taskId: {json.dumps(n.get('taskId'))}, nid: '{n['id']}', hint: {hint} }} }})); setTimeout(() => {{ db.notifications.push({nj}); render(); }}, 1200); }})()")
                await p.wait_for_timeout(2400)
                got=await p.evaluate("({ view: ui.view, task: ui.taskId || null, tab: ui.sideTab, client: ui.clientId || null, folder: ui.folderId || null })")
                check(all(got.get(k)==v for k,v in want.items()), f'tapped before it arrived: {label}', got)
            base=lambda k, **x: {'id':'nt-'+k,'to':'u-karim','from':info['other'],'taskId':info['t'],'kind':k,'text':k,'at':'2030-01-01T00:00:00.000Z','read':False, **x}
            await late(base('review'), {'view':'reviews'}, 'files for review → Review Requests')
            await late(base('comment', commentId=info['c']), {'task':info['t'],'tab':'comments'}, 'a comment → the task on Comments')
            await late({**base('asset', clientId=info['cl'], folderId=info['f']), 'taskId': None}, {'view':'client','client':info['cl'],'folder':info['f']}, 'Client Assets → the folder')
            # Inbox row: the newest update, unless one needs action
            await p.evaluate(f"""(() => {{ myNotifs().forEach(n => n.read = true); const at = (m) => new Date(Date.now() - m * 60000).toISOString();
              db.notifications.push({{ id: 'ib-ok', to: currentUserId, from: '{info['other']}', taskId: '{info['t']}', kind: 'review-ok', text: 'approved your files for', at: at(30), read: false }});
              db.notifications.push({{ id: 'ib-men', to: currentUserId, from: '{info['other']}', taskId: '{info['t']}', kind: 'mention', text: 'mentioned you in a comment on', commentId: '{info['c']}', at: at(2), read: false }}); render(); }})()""")
            await p.locator('#ph-tabs [data-ph-tab="inbox"]').click(); await p.wait_for_timeout(400)
            check(await p.locator('.ph-ib[data-id="ib-men"]').count()==1, 'Inbox row shows the newer @mention, not the older “approved your files”')
            await p.evaluate(f"""(() => {{ db.notifications.push({{ id: 'ib-amend', to: currentUserId, from: '{info['other']}', taskId: '{info['t']}', kind: 'review-amend', text: 'requested amendments on your submission for', commentId: '{info['c']}', at: new Date(Date.now() - 3600000).toISOString(), read: false }}); render(); }})()""")
            await p.wait_for_timeout(300)
            check(await p.locator('.ph-ib[data-id="ib-amend"]').count()==1, 'an unread amendment request stays on top')
            check(not errs, 'no page errors', errs)
            await c.close()
            # an Office Admin opening a task link
            c=await b.new_context(viewport={'width':1440,'height':900},base_url=BASE)
            await c.add_cookies([{'name':'e11_dev_email','value':'office@e11-digital.com','url':BASE}])
            p=await c.new_page(); errs=[]; p.on('pageerror', lambda e: errs.append(str(e)))
            await p.goto(f"/?task={info['t']}"); await p.wait_for_timeout(4000)
            check(await p.evaluate("ui.view")=='home' and not await p.evaluate("ui.taskId") and not errs, 'Office Admin: a task link stays on Home, no error', errs)
            await b.close()
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
