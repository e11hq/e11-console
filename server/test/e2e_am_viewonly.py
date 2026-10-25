"""An Account Manager on another client's task: view only (comments still work); their sidebar shows their clients."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18290; BASE=f'http://127.0.0.1:{PORT}'; ADMIN='haris@e11-digital.com'
async def main():
    env={**os.environ,'DATA_DIR':tempfile.mkdtemp(),'AUTH_DEV':'1','ADMIN_EMAIL':ADMIN,'PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.5.4-test.1'}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE+'/api/health'); break
            except Exception: time.sleep(0.1)
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/me',headers={'X-Dev-Email':ADMIN}))
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/sample/reset',method='POST',data=b'{}',headers={'X-Dev-Email':ADMIN,'Content-Type':'application/json'})).read()
        async with async_playwright() as pw:
            b=await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            ctx=await b.new_context(viewport={'width':1440,'height':900},base_url=BASE)
            await ctx.add_cookies([{'name':'e11_dev_email','value':'areej@e11-digital.com','url':BASE}])
            pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(4000); await pg.mouse.click(5,5); await pg.wait_for_timeout(400)
            sb = (await pg.evaluate("[...document.querySelectorAll('#project-list .nav-item .name')].map(e => e.textContent)"))
            other = await pg.evaluate("topTasks().find(t => t.projectId === 'p-alain' && t.createdBy !== currentUserId && !t.done).id")
            mine = await pg.evaluate("(topTasks().find(t => t.projectId === 'p-alain' && t.createdBy === currentUserId) || {}).id")
            await pg.evaluate(f"openTask('{other}')"); await pg.wait_for_timeout(700)
            r = await pg.evaluate(f"""(async () => {{ const t = task('{other}'); const due = t.due, sec = t.sectionId;
              const ro = document.querySelector('#detail').classList.contains('ro-task');
              const editable = [...document.querySelectorAll('#detail [contenteditable="true"]')].filter(e => !e.closest('.tm-feed, .tm-composer')).length;
              const enabled = [...document.querySelectorAll('#detail input:not([disabled]), #detail select:not([disabled])')].filter(e => !e.closest('.tm-feed, .tm-composer')).length;
              const other = task('{other}').projectId; const target = proj(other).sections.find(s => s.id !== sec).id;
              await changeStatus(t, target); setDone(t, true);
              const due0 = document.querySelector('#detail [data-action="due-today"], #detail [data-action="clear-due"]'); if (due0) due0.click();
              return {{ ro, editable, enabled, statusSame: t.sectionId === sec, notDone: !t.done, dueSame: t.due === due, note: !!document.querySelector('#detail .ro-note') }}; }})()""")
            ok = [sb == ['Ford & Lincoln', 'KOREA 360'], r == {'ro': True, 'editable': 0, 'enabled': 0, 'statusSame': True, 'notDone': True, 'dueSame': True, 'note': True}]
            n0 = await pg.evaluate(f"task('{other}').comments.length")
            await pg.locator('#d-comment').click(); await pg.keyboard.type('Looks good from my side'); await pg.locator('[data-action="add-comment"]').click(); await pg.wait_for_timeout(400)
            ok.append(await pg.evaluate(f"task('{other}').comments.length") == n0 + 1)
            if mine:
                await pg.evaluate("closeDetail()"); await pg.evaluate(f"openTask('{mine}')"); await pg.wait_for_timeout(500)
                ok.append(not await pg.evaluate("document.querySelector('#detail').classList.contains('ro-task')"))
            await pg.evaluate("closeDetail()")
            srch = await pg.evaluate("(() => { const r = taskSearch('ALAIN'); return { other: r.tasks.some(x => x.t.projectId === 'p-alain' && x.t.createdBy !== currentUserId), clients: r.projects.map(p => p.name) }; })()")
            ok.append(srch == {'other': False, 'clients': []})
            cal = await pg.evaluate("Cal && db.tasks.filter(t => Cal.isPost(t) && !amReadOnly(t)).every(t => ['p-ford', 'p-korea'].includes(t.projectId) || t.createdBy === currentUserId)")
            ok.append(cal is True)
            ca = await pg.evaluate("clientsSorted().map(c => c.name)")
            ok.append(sorted(ca) == ['Ford & Lincoln', 'KOREA 360'])
            # Production: no dates, no adding / removing checklist items (ticking is fine)
            c2 = await b.new_context(viewport={'width':1440,'height':900},base_url=BASE)
            await c2.add_cookies([{'name':'e11_dev_email','value':'yousef@e11-digital.com','url':BASE}])
            pp = await c2.new_page(); pp.on('pageerror', lambda e: errs.append(str(e)))
            await pp.goto('/'); await pp.wait_for_timeout(4000); await pp.mouse.click(5,5); await pp.wait_for_timeout(400)
            tid = await pp.evaluate("(() => { const t = topTasks().find(x => (x.assignees || []).includes(currentUserId) && !x.done && (x.checklist || []).length) || topTasks().find(x => (x.assignees || []).includes(currentUserId) && !x.done); if (!(t.checklist || []).length) t.checklist = [{ id: 'k1', text: 'Item', done: false }]; openTask(t.id); return t.id; })()")
            await pp.wait_for_timeout(600)
            pr = await pp.evaluate(f"""(() => {{ const t = task('{tid}'); const due = t.due, n = t.checklist.length;
              const r = {{ dueDisabled: !!document.querySelector('#d-due') && document.querySelector('#d-due').disabled, noClear: !document.querySelector('#detail [data-action="clear-due"], #detail [data-action="due-today"]'),
                noAdd: !document.querySelector('#d-cl-add'), noDel: !document.querySelector('#detail .cl-del') }};
              setDue(t, '2030-01-01'); r.dueSame = t.due === due;
              const was = !!t.checklist[0].done; document.querySelector('#detail [data-action="cl-toggle"]').click(); r.ticked = !!task('{tid}').checklist[0].done !== was; r.sameCount = t.checklist.length === n;
              return r; }})()""")
            ok.append(pr == {'dueDisabled': True, 'noClear': True, 'noAdd': True, 'noDel': True, 'dueSame': True, 'ticked': True, 'sameCount': True})
            if not ok[-1]: print('production:', pr)
            # Production and Freelancers: search shows only the tasks they're part of; Social still sees everything
            ps = await pp.evaluate("""(() => { const me0 = currentUserId; const as = (id, f) => { currentUserId = id; try { return f(); } finally { currentUserId = me0; } };
              const part = (t, id) => partOfTask(t, id);
              const run = (id) => as(id, () => { const r = taskSearch('Ford'); return { n: r.tasks.length, own: r.tasks.every(x => part(x.t, id)) }; });
              const others = (id) => db.tasks.filter(t => t.projectId === 'p-ford' && !part(t, id)).length;
              const prod = currentUserId, free = 'u-smp-free', soc = db.users.find(u => u.role === 'social' && u.active !== false).id;
              const p = run(prod), f = run(free), s = run(soc);
              return { prodOwn: p.own && p.n > 0, prodHides: others(prod) > 0, freeOwn: f.own && f.n > 0, socAll: s.n > p.n || !s.own }; })()""")
            ok.append(ps == {'prodOwn': True, 'prodHides': True, 'freeOwn': True, 'socAll': True})
            if not ok[-1]: print('search:', ps)
            # Social: same date / checklist limits, but they can write the description
            soc = await pp.evaluate("(() => { const me0 = currentUserId; const s = db.users.find(u => u.role === 'social' && u.active !== false); const p = db.users.find(u => u.role === 'production' && u.active !== false); const as = (id, f) => { currentUserId = id; try { return f(); } finally { currentUserId = me0; } }; return { socDesc: as(s.id, () => can('editDesc', {})), socDates: as(s.id, () => can('editDates', {})), socCl: as(s.id, () => can('editChecklist', {})), socAdd: as(s.id, () => can('addChecklist', {})), prodAdd: as(p.id, () => can('addChecklist', {})), prodDesc: as(p.id, () => can('editDesc', {})) }; })()")
            ok.append(soc == {'socDesc': True, 'socDates': False, 'socCl': False, 'socAdd': True, 'prodAdd': False, 'prodDesc': False})
            if not ok[-1]: print('social:', soc)
            ok.append(not errs)
            print('ALL PASS' if all(ok) else f'FAILS {ok} {sb} {r} {errs}')
            await b.close()
    finally:
        srv.kill()
asyncio.run(main())
