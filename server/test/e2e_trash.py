"""Trash end to end: delete → Trash → search → restore → delete forever. Run: python3 server/test/e2e_trash.py"""
import asyncio, base64, json, os, subprocess, tempfile, time, urllib.request, urllib.error
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18204; BASE = f'http://127.0.0.1:{PORT}'
fails = []
def check(c, msg):
    print(('PASS ' if c else 'FAIL ') + msg)
    if not c: fails.append(msg)
def status(path, who):
    try: return urllib.request.urlopen(urllib.request.Request(BASE + path, headers={'X-Dev-Email': who})).status
    except urllib.error.HTTPError as e: return e.code
PNG = base64.b64encode(bytes.fromhex('89504e470d0a1a0a0000000d4948445200000010000000100802000000909168360000001c49444154789c63f8cfc0f09f8114c0c4c0c0f09f81a1c10106001ac40cf4df5b8a3c0000000049454e44ae426082')).decode()
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'haris@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.1.3-test.31'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/me', headers={'X-Dev-Email': 'haris@e11-digital.com'}))
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': 'haris@e11-digital.com', 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as p:
            b = await p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            async def person(email, phone=False):
                ctx = await b.new_context(viewport={'width': 390, 'height': 844} if phone else {'width': 1400, 'height': 900}, is_mobile=phone, has_touch=phone, base_url=BASE)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(500); await pg.mouse.click(10, 10); await pg.keyboard.press('Escape'); await pg.wait_for_timeout(1500)
                return pg, errs
            am, e1 = await person('areej@e11-digital.com')
            pr, e2 = await person('yousef@e11-digital.com')
            ad, e3 = await person('haris@e11-digital.com')
            A, P, D = am.evaluate, pr.evaluate, ad.evaluate
            check(await A("getComputedStyle(document.getElementById('nav-trash')).display") != 'none', 'Account Manager sees Trash in the sidebar')
            check(await P("getComputedStyle(document.getElementById('nav-trash')).display") == 'none', 'Production does not')
            # a task with a file, assigned to Yousef
            tid = await A("""async ()=>{ const t=db.tasks.find(t=>!t.parentId && t.projectId && !t.done); t.assignees=['u-sara'];
              const r=await Host.call('writeChunk',{taskId:t.id,name:'Brief_v2.pdf',path:null,b64:'%s'}); t.attachments.push({id:uid(),name:'Brief_v2.pdf',path:r.path,size:r.size,addedAt:nowISO()}); commit({delay:0}); return t.id; }""" % PNG)
            await am.wait_for_timeout(800)
            title = await A(f"task('{tid}').title"); fpath = await A(f"task('{tid}').attachments.at(-1).path")
            await A(f"()=>deleteTaskFlow('{tid}')"); await am.wait_for_timeout(1500)
            check(await A(f"!task('{tid}') && trashList().some(x=>x.key==='tasks:{tid}')"), 'deleting a task moves it to the Trash')
            check(status('/__file/' + fpath, 'areej@e11-digital.com') == 200, 'its file is kept while it’s in the Trash')
            check(await P(f"!task('{tid}') && myNotifs().some(n=>n.kind==='trash' && n.taskId==='{tid}')"), 'the assignee is told it went to the Trash')
            check(await P("(db.trash||[]).length") == 0, 'Production never receives Trash items')
            # Trash page + smart search
            await A("()=>go('trash')"); await am.wait_for_timeout(300)
            check(await am.locator('.tr-row').count() >= 1, 'Trash page lists it')
            first = title.split('|')[0].strip().split(' ')[0]
            typo = first[1] + first[0] + first[2:] if len(first) > 3 else first
            await am.fill('#tr-q', typo.lower() + ' pdf'); await am.wait_for_timeout(300)
            check(await am.locator('.tr-row').count() >= 1, f'Trash search finds it with a typo ("{typo.lower()} pdf")')
            await am.screenshot(path=os.path.join(SHOTS, 'trash-desktop.png'))
            check(await am.locator('[data-action="tr-forever"]').count() == 0 and await am.locator('[data-action="tr-empty"]').count() == 0, 'Account Managers can’t delete forever')
            await am.locator('[data-action="tr-restore"]').first.click(); await am.wait_for_timeout(1500)
            check(await A(f"!!task('{tid}') && task('{tid}').attachments.some(a=>a.name==='Brief_v2.pdf') && !trashList().some(x=>x.key==='tasks:{tid}')"), 'Restore puts the task back with its file')
            check(await P(f"!!task('{tid}') && myNotifs().some(n=>n.kind==='restore' && n.taskId==='{tid}')"), 'the assignee sees it again and is told')
            # Production deletes his own comment → lands in the Trash for the AM
            await P(f"""()=>{{ const t=task('{tid}'); t.comments.push({{id:'yc1',text:'My note to remove',html:'My note to remove',at:nowISO(),attachments:[],parentId:null,reactions:{{}},authorId:'u-sara'}}); commit({{delay:0}}); }}""")
            await pr.wait_for_timeout(800)
            await P(f"()=>{{ ui.taskId='{tid}'; deleteComment('yc1') }}"); await pr.wait_for_timeout(400)
            check(await pr.locator('.dialog').count() == 1 and 'Account Manager' in await pr.locator('.dialog').inner_text(), 'Production gets a clear confirmation first')
            await pr.locator('.dialog [data-r="1"]').click(); await pr.wait_for_timeout(1500)
            check(await A("trashList().some(x=>x.type==='comment' && x.deletedBy==='u-sara')"), 'his deleted comment is in the Trash for Account Managers')
            # Admin: delete forever removes the file
            await D(f"()=>deleteTaskFlow('{tid}')"); await ad.wait_for_timeout(1500)
            await D("()=>go('trash')"); await ad.wait_for_timeout(300)
            check(await ad.locator('[data-action="tr-empty"]').count() == 1, 'Admins see Empty Trash')
            iid = await D(f"trashList().find(x=>x.type==='task' && x.key==='tasks:{tid}').id")
            await D(f"()=>{{ eraseTrashFlow('{iid}') }}"); await ad.wait_for_timeout(300)
            await ad.locator('.dialog [data-r="1"]').click(); await ad.wait_for_timeout(1500)
            gone = not await D(f"trashList().some(x=>x.id==='{iid}')"); st = status('/__file/' + fpath, 'haris@e11-digital.com')
            check(gone and st == 404, 'Delete forever removes it and its file')
            # 30 days in the Trash, and finished tasks after 30 days
            await A("()=>{ const it=toTrash('cafile',{clientId:'x',folderId:'y',file:{id:'f9',name:'old.png',path:'nowhere'}}); it.deletedAt=new Date(Date.now()-31*86400000).toISOString(); purgeTrash(); commit({delay:0}); }")
            check(not await A("trashList().some(x=>x.data.file && x.data.file.id==='f9')"), 'items older than 30 days leave the Trash')
            done_id = await A("()=>{ const t=db.tasks.find(t=>!t.parentId && !t.done); t.done=true; t.completedAt=new Date(Date.now()-31*86400000).toISOString(); purgeOldCompleted(); return t.id }")
            check(await A(f"!task('{done_id}') && trashList().some(x=>x.key==='tasks:{done_id}' && x.auto)"), 'tasks finished 30+ days ago move to the Trash (not gone)')
            # phone
            ph, e4 = await person('areej@e11-digital.com', phone=True)
            await ph.locator('#ph-tabs [data-ph-tab="me"]').click(); await ph.wait_for_timeout(300)
            await ph.locator('.ph-row[data-nav="trash"]').click(); await ph.wait_for_timeout(400)
            check(await ph.locator('#ph-top .ph-bar b').inner_text() == 'Trash' and await ph.locator('.tr-row').count() >= 1, 'phone: Trash from Me, with a back header')
            await ph.screenshot(path=os.path.join(SHOTS, 'trash-phone.png'))
            errs = e1 + e2 + e3 + e4
            check(not errs, f'no errors {errs[:2]}')
            await b.close()
    finally:
        srv.terminate()
    print('\n' + ('ALL PASS' if not fails else f'{len(fails)} FAILED'))
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
