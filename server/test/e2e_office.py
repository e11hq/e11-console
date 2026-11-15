"""Office Admin in the browser: no task app (sidebar, guard, shortcuts), their own Home, Team page labels, the Trash with
Client Assets items only (restore, no delete forever), the phone tabs; and a deleted Client Assets folder goes to the
Trash and comes back."""
import asyncio, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18299; BASE=f'http://127.0.0.1:{PORT}'; OWNER='haris@e11-digital.com'; ARSAL='arsal.office@e11-digital.com'
fails=[]
def check(c, m): print(('ok  ' if c else 'FAIL'), m); (None if c else fails.append(m))
def api(who, p, body=None):
    r=urllib.request.Request(BASE+p, method='POST' if body is not None else 'GET', data=json.dumps(body).encode() if body is not None else None, headers={'X-Dev-Email':who,'Content-Type':'application/json'})
    return json.loads(urllib.request.urlopen(r).read())
async def page_for(b, email, w=1440, h=900):
    ctx=await b.new_context(viewport={'width':w,'height':h}, base_url=BASE)
    await ctx.add_cookies([{'name':'e11_dev_email','value':email,'url':BASE}])
    pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
    await pg.goto('/'); await pg.wait_for_timeout(3500); await pg.keyboard.press('Shift'); await pg.wait_for_timeout(600)
    return ctx, pg, errs
async def main():
    subprocess.run(['fuser','-k',f'{PORT}/tcp'],stderr=subprocess.DEVNULL)
    env={**os.environ,'DATA_DIR':tempfile.mkdtemp(),'AUTH_DEV':'1','ADMIN_EMAIL':OWNER,'PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.6.5-test.1'}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE+'/api/health'); break
            except Exception: time.sleep(0.1)
        api(OWNER,'/api/me'); api(OWNER,'/api/sample/reset',{})
        api(OWNER,'/api/push',{'changes':[{'kind':'users','id':'u-arsal','data':{'id':'u-arsal','email':ARSAL,'name':'Muhammad Arsal','role':'office_admin','fin':'admin','active':True,'setup':True,'prefs':{}}}]})
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            # --- the owner deletes a Client Assets folder: it goes to the Trash
            c0, op, e0 = await page_for(b, OWNER)
            fid = await op.evaluate("""(async () => { const c = db.clients[0]; const f = c.folders.find(x => !x.auto) || c.folders[c.folders.length - 1]; openClient(c.id); return [c.id, f.id, f.name, f.files.length, f.parentId || null]; })()""")
            await op.wait_for_timeout(500)
            if fid[4]: await op.locator(f'.cf-card[data-id="{fid[4]}"]').click(); await op.wait_for_timeout(500)   # (it sits in a folder: open that first)
            # (the folder card's own ••• button: a menu anchored to the whole page would open below the window)
            card = op.locator(f'.cf-card[data-id="{fid[1]}"]')
            await card.hover(); await card.locator('[data-action="cfolder-menu"]').click(); await op.wait_for_timeout(300)
            await op.locator('.menu .mi', has_text='Trash folder').click(); await op.wait_for_timeout(300)
            await op.click('.dialog [data-r="1"]'); await op.wait_for_timeout(1500)
            check(await op.evaluate(f"!clientById('{fid[0]}').folders.some(x => x.id === '{fid[1]}') && trashList().some(t => t.type === 'cafolder' && t.data.folder.id === '{fid[1]}')"), f'a deleted folder ({fid[2]}, {fid[3]} files) goes to the Trash')
            check(not e0, f'no page errors (owner) {e0[:2]}')
            # --- the Office Admin
            ctx, pg, errs = await page_for(b, ARSAL); E=pg.evaluate
            vis = await E("""(() => { const v = (sel) => { const el = document.querySelector(sel); return !!el && el.offsetParent !== null; };
              return { home: v('.nav [data-nav="home"]'), inbox: v('.nav [data-nav="inbox"]'), assets: v('[data-nav="clients"]'), fin: v('.fin-office .nav-item[data-nav="fin-dash"]') && v('.fin-office .nav-item[data-nav="fin-projects"]') && v('.fin-office .nav-item[data-nav="fin-reimb"]') && v('.fin-office .nav-item[data-nav="fin-expenses"]'), trash: v('#nav-trash'),
                myday: v('.nav [data-nav="today"]'), mytasks: v('.nav [data-nav="mytasks"]'), clients: v('#project-list'), search: v('.search'), newtask: v('[data-action="new-task"]') }; })()""")
            check(vis == {'home': True, 'inbox': True, 'assets': True, 'fin': True, 'trash': True, 'myday': False, 'mytasks': False, 'clients': False, 'search': False, 'newtask': False}, f'sidebar: Home, Inbox, Client Assets, Finance (Dashboard, Clients, Reimbursements, Expenses), Trash only {vis}')
            await pg.locator('.fin-office .nav-item[data-nav="fin-reimb"]').click(); await pg.wait_for_timeout(500)
            check(await E("ui.view") == 'fin-reimb' and await pg.locator('.fin-office .nav-item.active[data-nav="fin-reimb"]').count() == 1, 'Reimbursements opens from the Finance heading')
            await E("go('home')"); await pg.wait_for_timeout(300)
            check(await pg.locator('.oh').count() == 1 and 'Office Admin' in await pg.locator('.oh-date').inner_text(), 'their own Home')
            if os.environ.get('SHOT'): await pg.screenshot(path=os.environ['SHOT'])
            # Home: three boxes of the same height reaching the bottom; Inbox opens on Unread (or All when nothing is unread)
            hs = await E("[...document.querySelectorAll('.oh-card')].map(c => Math.round(c.getBoundingClientRect().height))")
            bottom = await E("Math.round(document.querySelector('.oh-card').getBoundingClientRect().bottom)")
            check(len(hs) == 3 and max(hs) - min(hs) <= 1 and bottom > 820, f'three boxes, same height, down to the bottom {hs} {bottom}')
            check(await E("document.querySelectorAll('.oh-card')[1].querySelector('.oh-seg .on').textContent") == ('Unread' if await E("myNotifs().some(n => !n.read)") else 'All'), 'Inbox opens on Unread when there are unread updates')
            await E("myNotifs().forEach(n => { n.read = true; }); OfficeHome.st.ibTab = null; renderContent()"); await pg.wait_for_timeout(300)
            check(await E("document.querySelectorAll('.oh-card')[1].querySelector('.oh-seg .on').textContent") == 'All', '...and on All when nothing is unread')
            # client chips and search filter the files; a file shows its details
            await pg.locator('.oh-chip').nth(1).click(); await pg.wait_for_timeout(300)
            one = await E("(() => { const n = document.querySelector('.oh-chip.on').textContent; return [...document.querySelectorAll('#oh-files .oh-t small')].every(s => s.textContent.startsWith(n)); })()")
            check(one, 'a client chip shows only that client')
            await pg.locator('.oh-chip').first.click(); await pg.wait_for_timeout(300)
            await pg.fill('#oh-q', 'logo'); await pg.wait_for_timeout(300)
            check(await E("[...document.querySelectorAll('#oh-files .oh-t b')].every(b => /logo/i.test(b.textContent + b.nextElementSibling.textContent))"), 'search filters the files')
            await pg.fill('#oh-q', 'pdf'); await pg.wait_for_timeout(300)
            names = await E("[...document.querySelectorAll('#oh-files .oh-t b')].map(b => b.textContent)")
            check(names and all(n.lower().endswith('.pdf') for n in names), f'a file type finds those files, like the Client Assets page ({names[:3]})')
            await pg.fill('#oh-q', 'logo'); await pg.wait_for_timeout(300)
            await pg.locator('#oh-files .oh-row').first.click(); await pg.wait_for_timeout(200)
            # a file picked: no details box — its size in its line, Open Folder · Download as two round buttons (Haris 2026-11-15)
            check(await pg.locator('#oh-files .oh-detail').count() == 0 and await pg.locator('#oh-files .oh-row.sel .oh-fbtns .oh-ib').count() == 2, 'a file picked shows Open Folder · Download, no details box')
            await pg.locator('#oh-files .oh-row').first.click(button='right'); await pg.wait_for_timeout(200)
            check(await E("[...document.querySelectorAll('.menu .mi')].map(m => m.textContent.trim())") == ['Open Folder', 'Download'], 'a file right-clicked: Open Folder · Download')
            await pg.keyboard.press('Escape'); await E("closeMenus()")
            await pg.fill('#oh-q', '')
            # Finance: the month (the last 12), claims in two groups with See All, one thing at a row's right, •••, right-click
            m = await E("Claims.claimMonth()")
            us = [u for u in api(OWNER,'/api/snapshot')['data']['users'] if u.get('active') is not False and u.get('email') and u['email'] not in (OWNER, ARSAL)][:3]
            ids = []
            for i, u in enumerate(us):
                cid = f"cl-{u['id']}-{m}"; ids.append(cid)
                d = {'id': cid, 'userId': u['id'], 'month': m, 'state': 'submitted', 'groups': [{'id': 'g', 'date': f'{m}-05', 'title': 'Scout', 'items': [{'id': 'i', 'desc': 'Petrol', 'amount': 80 + i, 'receipt': None}]}], 'total': 80 + i, 'submittedAt': '2026-11-01T08:00:00.000Z'}
                r = api(u['email'], '/api/push', {'changes': [{'kind': 'claims', 'id': cid, 'data': d}]})
                check(not r['results'][0].get('refused'), f'claim {i} submitted')
            snapc = {c['id']: c for c in api(ARSAL, '/api/snapshot')['data']['claims']}
            api(ARSAL, '/api/push', {'changes': [{'kind': 'claims', 'id': ids[1], 'data': {**snapc[ids[1]], 'state': 'approved', 'approvedAt': '2026-11-02T08:00:00.000Z', 'approvedBy': 'u-arsal'}}]})
            api(ARSAL, '/api/push', {'changes': [{'kind': 'claims', 'id': ids[2], 'data': {**snapc[ids[2]], 'state': 'paid', 'approvedAt': '2026-11-02T08:00:00.000Z', 'approvedBy': 'u-arsal', 'paidOn': f'{m}-03', 'paidBy': 'u-arsal'}}]})
            await pg.wait_for_timeout(2500); await E("OfficeHome.st.finTab = 'claims'; renderContent()")
            await pg.wait_for_timeout(300)
            fin = pg.locator('.oh-card').nth(2)
            check(await fin.locator('[data-oh-month] option').count() == 12, 'Finance: the month menu holds the last 12')
            grps = await fin.locator('.oh-grp > span').all_inner_texts()
            check(grps == ['Need HR approval', 'HR approved and paid'] and await fin.locator('.oh-grp [data-oh="see-all"]').count() == 2, f'two groups with See All {grps}')
            sub = fin.locator('[data-claim-row="'+ids[0]+'"]')
            check(await sub.locator('.oh-mini').inner_text() == 'HR Approve' and await sub.locator('.oh-pill').count() == 0, 'a submitted claim: HR Approve only, no pill beside it')
            check(await fin.locator('[data-claim-row="'+ids[1]+'"] .oh-mini').inner_text() == 'Paid On…', 'an HR approved claim: Paid On…')
            check(await fin.locator('[data-claim-row="'+ids[2]+'"] .oh-pill').inner_text() == 'Paid' and 'paid ' in await fin.locator('[data-claim-row="'+ids[2]+'"] small').inner_text(), 'a paid claim: Paid, and when')
            await fin.locator('[data-oh="more"]').click(); await pg.wait_for_timeout(200)
            check(await E("[...document.querySelectorAll('.menu .mi')].map(m => m.textContent.trim())") == ['Mark All HR Approved', 'Set All Paid On…'], '••• Mark All HR Approved · Set All Paid On…')
            await E("closeMenus()")
            await sub.click(button='right', position={'x': 60, 'y': 10}); await pg.wait_for_timeout(200)
            check(await E("[...document.querySelectorAll('.menu .mi')].map(m => m.textContent.trim())") == ['Open Claim', 'HR Approved', 'Paid On…', 'Share PDF'], 'a claim right-clicked: Open Claim · HR Approved · Paid On… · Share PDF')
            await E("closeMenus()")
            await sub.locator('.oh-mini').click(); await pg.wait_for_timeout(300)
            check(await E(f"Claims.byId('{ids[0]}').state") == 'approved', 'HR Approve marks it HR approved')
            prev = await E("Claims.addMonth(Claims.claimMonth(), -1)")
            await fin.locator('[data-oh-month]').select_option(prev); await pg.wait_for_timeout(300)
            check(await E("OfficeHome.st.month") == prev and not any([await pg.locator(f'[data-claim-row="{i}"]').count() for i in ids]), 'another month shows that month')
            await pg.locator('.oh-stat').nth(3).click(); await pg.wait_for_timeout(400)
            check(await E("ui.view") == 'fin-reimb' and await E("Claims.st.finMonth") == prev, 'Claims to approve opens Claims on that month')
            await E("OfficeHome.st.month = null; go('home')"); await pg.wait_for_timeout(300)
            await E("go('mytasks')"); await pg.wait_for_timeout(300)
            check(await E("ui.view") == 'home', 'task pages lead back to Home')
            await E("go('team')"); await pg.wait_for_timeout(400)
            t = await pg.locator('#content').inner_text()
            check('Office Admin' in t and 'Super Admin' in t, 'Team page shows Super Admin / Office Admin')
            await E("go('updates')"); await pg.wait_for_timeout(400)
            check(await E("ui.view") == 'updates', 'App updates opens')
            await E("go('trash')"); await pg.wait_for_timeout(500)
            types = await E("trashList().map(t => t.type)")
            check(len(types) > 0 and all(x in ('cafile','cafolder') for x in types), f'Trash: Client Assets items only {types}')
            check(await pg.locator('[data-action="tr-forever"], [data-action="tr-empty"]').count() == 0, 'no Delete forever / Empty Trash')
            tid = await E(f"trashList().find(t => t.type === 'cafolder').id")
            await pg.locator(f'[data-action="tr-restore"][data-id="{tid}"]').click(); await pg.wait_for_timeout(1500)
            snap = api(OWNER,'/api/snapshot')['data']
            back = [c for c in snap['clients'] if c['id']==fid[0]][0]
            check(any(f['id']==fid[1] and len(f['files'])==fid[3] for f in back['folders']) and not any(t['id']==tid for t in snap['trash']), 'the Office Admin restores the folder with its files')
            # (the app fills in empty lists on every task it loads, so: nothing in them — and the server sends none of it)
            check(await E("db.tasks.every(t => !t.notes && !(t.comments || []).length && !(t.attachments || []).length && !(t.activity || []).length)"), 'no task detail in their app')
            slim = api(ARSAL,'/api/snapshot')['data']['tasks']
            check(slim and not any(k in t for t in slim for k in ('comments', 'notes', 'notesHtml', 'attachments', 'activity', 'assignees')), 'the server sends them only the slim job list')
            check(not errs, f'no page errors (Office Admin) {errs[:2]}')
            # --- phone
            c2, ph, e2 = await page_for(b, ARSAL, 390, 844)
            tabs = await ph.evaluate("[...document.querySelectorAll('#ph-tabs .ph-tab > span:last-child')].map(s => s.textContent)")
            # (Haris 2026-11-04: an Office Admin with Finance access gets Overview · Inbox · Claims · Expenses · Me)
            check(tabs == ['Overview', 'Inbox', 'Claims', 'Expenses', 'Me'], f'phone tabs {tabs}')
            check(await ph.locator('.oh').count() == 1, 'phone Home')
            check(not e2, f'no page errors (phone) {e2[:2]}')
            await b.close()
    finally: srv.kill()
    print('ALL PASS' if not fails else f'FAILS {fails}')
asyncio.run(main())
