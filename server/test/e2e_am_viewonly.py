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
            ok.append(not errs)
            print('ALL PASS' if all(ok) else f'FAILS {ok} {sb} {r} {errs}')
            await b.close()
    finally:
        srv.kill()
asyncio.run(main())
