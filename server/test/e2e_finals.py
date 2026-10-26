"""Part A: Files holds folders (no Upload at its top; New folder there), other folders hold files; completing a CD-reviewed
task asks about client approval once, then files its approved files in Files › <task> (Final); Info pop-ups; the
Client approved button; phone back buttons."""
import asyncio, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18295; BASE=f'http://127.0.0.1:{PORT}'; ADMIN='haris@e11-digital.com'
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
            info = await pg.evaluate("""(() => { const c = clientsSorted().find(c => db.projects.some(p => p.clientId === c.id) && c.folders.some(f => isFilesTop(c, f)));
              const files = c.folders.find(f => isFilesTop(c, f)); return { c: c.id, files: files.id, loose: files.files.length }; })()""")
            await pg.evaluate(f"openClient('{info['c']}', '{info['files']}')"); await pg.wait_for_timeout(600)
            check(await pg.locator('[data-action="ca-upload"]').count() == 0 and await pg.locator('.cfo-head [data-action="add-cfolder"]').count() == 1 and await pg.locator('.cf-grid .cf-card.add[data-action="add-cfolder"]').count() == 1, 'Files: New folder button and a New folder card, no Upload files')
            await pg.locator('.cfo-head [data-action="add-cfolder"]').click(); await pg.wait_for_timeout(300)
            await pg.locator('#overlay-root input').first.fill('Summer shoot'); await pg.keyboard.press('Enter'); await pg.wait_for_timeout(500)
            sub = await pg.evaluate(f"(() => {{ const c = clientById('{info['c']}'); const f = c.folders.find(f => f.name === 'Summer shoot'); return f && {{ id: f.id, parent: f.parentId, dir: f.dir }}; }})()")
            check(sub and sub['parent'] == info['files'] and '/Files/Summer shoot' in sub['dir'], 'a folder made inside Files', sub)
            await pg.locator(f'.cf-card[data-id="{sub["id"]}"]').click(); await pg.wait_for_timeout(500)
            check(await pg.locator('[data-action="ca-upload"]').count() == 1 and await pg.locator('.cfo-head [data-action="add-cfolder"]').count() == 1, 'inside it: Upload files and New folder')
            check(await pg.evaluate("document.querySelector('.cf-grid > .cf-card').matches('.add')"), 'the New folder card comes first')
            # down to the 5th level: Files › Summer shoot › L2 › L3 › L4 › L5
            ids = [sub['id']]
            for n in ('L2', 'L3', 'L4', 'L5'):
                await pg.locator('.cf-grid .cf-card.add').click(); await pg.wait_for_timeout(300)
                await pg.locator('#overlay-root input').first.fill(n); await pg.keyboard.press('Enter'); await pg.wait_for_timeout(400)
                fid = await pg.evaluate(f"clientById('{info['c']}').folders.find(f => f.name === '{n}').id"); ids.append(fid)
                await pg.locator(f'.cf-card[data-id="{fid}"]').click(); await pg.wait_for_timeout(400)
            check(await pg.locator('[data-action="add-cfolder"]').count() == 0 and await pg.locator('[data-action="ca-upload"]').count() == 1, '5th level: files only (no New folder)')
            crumbs = await pg.locator('.cfo-crumbs').inner_text()
            check('Files › Summer shoot › L2 › L3 › L4' in crumbs, 'the header shows the whole path', crumbs)
            await pg.locator('.cfo-crumbs a', has_text='L2').click(); await pg.wait_for_timeout(400)
            check(await pg.evaluate("ui.folderId") == ids[1], 'a part of the path opens that folder')
            await pg.wait_for_timeout(1500)
            # delete L2 with everything inside; restore it in one go
            await pg.evaluate(f"(() => {{ const c = clientById('{info['c']}'); openClient(c.id, '{sub['id']}'); }})()"); await pg.wait_for_timeout(400)
            await pg.locator(f'.cf-card[data-id="{ids[1]}"]').hover(); await pg.locator(f'.cf-card[data-id="{ids[1]}"] [data-action="cfolder-menu"]').click(); await pg.wait_for_timeout(200)
            await pg.locator('.menu .mi', has_text='Delete folder').click(); await pg.wait_for_timeout(300)
            body = await pg.locator('#overlay-root').inner_text()
            check('3 folders' in body, 'the delete warning counts the folders inside', body)
            await pg.locator('#overlay-root .btn.danger').click(); await pg.wait_for_timeout(1200)
            gone = await pg.evaluate(f"[{','.join(repr(i) for i in ids[1:])}].filter(id => clientById('{info['c']}').folders.some(f => f.id === id)).length")
            tr = await pg.evaluate("trashList().find(t => t.type === 'cafolder' && t.data.folder.name === 'L2')")
            check(gone == 0 and tr and len(tr['data']['inner']) == 3, 'L2 and the 3 folders in it are in the Trash as one item')
            await pg.evaluate(f"restoreTrash('{tr['id']}')"); await pg.wait_for_timeout(1500)
            back = await pg.evaluate(f"[{','.join(repr(i) for i in ids[1:])}].filter(id => clientById('{info['c']}').folders.some(f => f.id === id)).length")
            check(back == 4, 'restored in one go: L2 › L3 › L4 › L5', back)
            await pg.evaluate(f"openClient('{info['c']}', '{sub['id']}')"); await pg.wait_for_timeout(400)
            await pg.wait_for_timeout(1500)
            ref = await pg.evaluate(f"(() => {{ const c = clientById('{info['c']}'); return !!c.folders.find(f => f.id === '{sub['id']}'); }})()")
            check(ref, 'the server kept the new folder')
            # a CD-reviewed task, with an approved file on disk
            tid = await pg.evaluate("""async (cid) => {
              const p = db.projects.find(p => p.clientId === cid); const done = statusList({ projectId: p.id }).find(s => isDoneName(s.name));
              const prod = db.users.find(u => u.role === 'production' && u.active !== false);
              const t = createTask({ projectId: p.id, sectionId: done.id, title: 'Eid greeting reel' });
              const up = await Host.call('writeChunk', { taskId: t.id, name: 'eid-reel.png', b64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' });
              t.needsCD = true; t.assignees = [prod.id]; t.cdStatus = 'approved';
              t.attachments.push({ id: 'att-eid', name: up.name, path: up.path, size: up.size, reviewId: 'rv-eid', addedAt: nowISO() });
              t.reviews = [{ id: 'rv-eid', by: prod.id, at: nowISO(), files: ['att-eid'], state: 'approved', decidedAt: nowISO(), decidedBy: cdUserId() || currentUserId, epoch: 0, round: 1 }];
              persist(0); await Sync.push(); return t.id; }""", info['c'])
            await pg.evaluate(f"openTask('{tid}')"); await pg.wait_for_timeout(700)
            check(await pg.locator('#detail [data-action="client-approved"]').count() == 1, 'Client approved button for the Admin')
            # the row follows the task's CD Status for the current round
            rows = await pg.evaluate("""(() => { const p = db.projects[0]; const s = statusList({ projectId: p.id })[1];
              const a = createTask({ projectId: p.id, sectionId: s.id, title: 'Approved without a submission' }); a.needsCD = true; a.cdStatus = 'approved'; a.assignees = [];
              const b = createTask({ projectId: p.id, sectionId: s.id, title: 'Sent back for a new round' }); b.needsCD = true; b.cdStatus = ''; b.reviewEpoch = 1;
              b.reviews = [{ id: 'old-r', by: currentUserId, at: nowISO(), files: [], state: 'approved', decidedAt: nowISO(), epoch: 0, round: 1 }];
              return [!!clientApprovalRow(a), !!clientApprovalRow(b)]; })()""")
            check(rows == [True, False], 'Client approval row: shown when CD Approved (even without a submission), hidden while a new round waits', rows)
            await pg.locator('#detail .done-btn[data-action="toggle"]').first.click(); await pg.wait_for_timeout(400)
            check(await pg.locator('.choice-dlg h2', has_text='Did the client approve?').count() == 1, 'completing asks: Did the client approve?')
            await pg.locator('.choice-dlg button', has_text='Yes, today').click(); await pg.wait_for_timeout(2500)
            fin = await pg.evaluate(f"(() => {{ const c = clientById('{info['c']}'); const f = c.folders.find(f => f.finalOf === '{tid}'); return f && {{ id: f.id, name: f.name, parent: f.parentId, files: f.files.map(a => a.final && a.final.srcId), client: f.files[0] && f.files[0].final.clientBy }}; }})()")
            check(fin and fin['name'] == 'Eid greeting reel' and fin['parent'] == info['files'] and fin['files'] == ['att-eid'] and fin['client'], 'filed in Files › Eid greeting reel with the client approval', fin)
            await pg.evaluate("closeDetail()"); await pg.evaluate(f"openClient('{info['c']}', '{info['files']}')"); await pg.wait_for_timeout(600)
            check(await pg.locator(f'.cf-card.final[data-id="{fin["id"]}"]').count() == 1, 'shown as a Final folder in Files')
            await pg.locator(f'.cf-card[data-id="{fin["id"]}"]').click(); await pg.wait_for_timeout(500)
            check(await pg.locator('[data-action="ca-upload"]').count() == 0 and await pg.locator('[data-action="ca-remove"]').count() == 0, 'final folder: no Upload, no Delete on its files')
            check(await pg.locator('.cfo-title [data-action="open-task"]').count() == 1, 'Open task link while the task exists')
            await pg.locator('.ca-tile').first.hover(); await pg.locator('.ca-tile [data-action="ca-info"]').first.click(); await pg.wait_for_timeout(300)
            txt = await pg.locator('.ci-dlg').inner_text()
            check(all(k in txt for k in ('Completed', 'Task created by', 'Assignee', 'Approved by', 'CD approved', 'Client approval')) and 'Round' not in txt, 'file Info: completed, created by, assignee, approved by CD & client, dates', txt)
            check(await pg.locator('.ci-dlg [data-ci-task]').count() == 1, 'file Info: Open task')
            await pg.keyboard.press('Escape'); await pg.wait_for_timeout(200)
            await pg.locator('.cfo-head [data-action="ca-info-folder"]').click(); await pg.wait_for_timeout(300)
            txt = await pg.locator('.ci-dlg').inner_text()
            check('Created by' in txt and 'Files' in txt and 'Size' in txt and 'Approved' not in txt, 'folder Info: created by, date, files, size — no approvals', txt)
            await pg.keyboard.press('Escape'); await pg.wait_for_timeout(200)
            # a normal file
            await pg.evaluate(f"(() => {{ const c = clientById('{info['c']}'); const lf = c.folders.find(f => f.name === 'Logos'); openClient(c.id, lf.id); }})()"); await pg.wait_for_timeout(500)
            if await pg.locator('.ca-tile').count():
                await pg.locator('.ca-tile').first.hover(); await pg.locator('.ca-tile [data-action="ca-info"]').first.click(); await pg.wait_for_timeout(300)
                txt = await pg.locator('.ci-dlg').inner_text()
                check('Added by' in txt and 'Date added' in txt and 'Type' in txt, 'normal file Info: added by, date, size, type', txt)
                await pg.keyboard.press('Escape')
            check(not errs, 'no page errors (desktop)', errs)
            # phone: inside a Files folder, back goes to Files
            ph=await b.new_context(viewport={'width':390,'height':844},base_url=BASE)
            await ph.add_cookies([{'name':'e11_dev_email','value':ADMIN,'url':BASE}])
            pp=await ph.new_page(); perrs=[]; pp.on('pageerror', lambda e: perrs.append(str(e)))
            await pp.goto('/'); await pp.wait_for_timeout(4000)
            await pp.evaluate(f"openClient('{info['c']}', '{sub['id']}')"); await pp.wait_for_timeout(700)
            back = await pp.evaluate("(() => { const b = document.querySelector('#ph-top [data-action], #ph-top [data-nav], #ph-top [data-ph-tab]'); return b && [b.dataset.action, b.dataset.id]; })()")
            check(back == ['open-cfolder', info['files']], 'phone: back from a Files folder goes to Files', back)
            check(not perrs, 'no page errors (phone)', perrs)
            await b.close()
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
