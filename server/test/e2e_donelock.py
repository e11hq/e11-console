"""A completed task is locked (Haris, 2026-11-01): its page is read only with "Completed on … — read only", no comment box,
"New task from this"; only Admins see Reopen; the one who completed it may Undo for a few seconds, not later."""
import asyncio, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18297; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.8-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            async def login(email):
                ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE, timezone_id='Asia/Dubai')
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3500)
                return ctx, pg, errs
            ctx, pg, errs = await login(ADMIN); E = pg.evaluate
            am = await E("(()=>{const t=topTasks().find(t=>t.done && (t.assignees||[]).some(id=>{const u=userById(id); return u && !isAdm(u);}))||topTasks().find(t=>t.done); const id=(t.assignees||[]).find(id=>{const u=userById(id); return u && !isAdm(u);}); return {tid:t.id, am:id?userById(id).email:null}})()")   # (someone on it who isn't an Admin)
            tid = am['tid']
            # an Admin: the page is read only, with Reopen and New task from this; no comment box
            await E(f"(()=>{{ui.detailMode='modal';openTask('{tid}')}})()"); await pg.wait_for_timeout(700)
            check(await E("document.querySelector('#detail').classList.contains('done-lock')"), 'a completed task opens locked')
            note = await E("(document.querySelector('#detail .done-note')||{}).textContent||''")
            check('read only' in note and 'Completed' in note, f'the note says so: {note!r}')
            check(await pg.locator('#detail [data-action="reopen-done"]').count() == 1, 'an Admin sees Reopen')
            check(await E("getComputedStyle(document.querySelector('#detail .tm-composer')||document.body).display") in ('none',) or await pg.locator('#detail .tm-composer').count() == 0, 'no comment box')
            r = await E(f"changeStatus(task('{tid}'), (statusList(task('{tid}'))[0]||{{}}).id)")
            check(r is False and await E(f"task('{tid}').done"), 'the status can’t be changed')
            await ctx.close()
            # an AM: no Reopen; reopening is refused (page and server)
            if am['am']:
                ctx, pg, errs = await login(am['am']); E = pg.evaluate
                await E(f"(()=>{{ui.detailMode='modal';openTask('{tid}')}})()"); await pg.wait_for_timeout(700)
                check(await pg.locator('#detail [data-action="reopen-done"]').count() == 0, 'someone else on it doesn’t see Reopen')
                await E(f"setDone(task('{tid}'), false); commit({{delay:0}})"); await pg.wait_for_timeout(1500)
                check(await E(f"task('{tid}').done"), 'they can’t reopen it')
                # Undo right after completing an open task: allowed
                oid = await E("(()=>{const r=E11Rules.make(db,currentUserId,todayStr()); const t=topTasks().find(t=>!t.done && canComplete(t) && !r.amReadOnly(t) && !(t.cdStatus==='approved')); return t&&t.id})()")
                if oid:
                    await E(f"setDone(task('{oid}'), true); commit({{delay:0}})"); await pg.wait_for_timeout(1200)
                    await E(f"setDone(task('{oid}'), false); commit({{delay:0}})"); await pg.wait_for_timeout(1500)
                    check(await E(f"!task('{oid}').done"), 'Undo right after completing works')
                check(not errs, f'no page errors {errs[:2]}')
                await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('FAILS', len(fails), fails)
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
