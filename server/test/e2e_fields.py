"""Task Fields under the description: Task Update (everyone; logged + notifies everyone on the task),
Finance (Account Managers / Admins only), Guardian (Production / Social / Freelancers by role)."""
import asyncio, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18200; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.7-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def login(email, vp=(1300, 800)):
            ctx = await b.new_context(viewport={'width': vp[0], 'height': vp[1]}, base_url=BASE, has_touch=vp[0] < 500)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(4000)
            return ctx, pg, errs
        ctx, pg, errs = await login(ADMIN); E = pg.evaluate
        tid = await E("db.tasks.find(t=>/Offroad Campaign/.test(t.title)).id")
        await E(f"(()=>{{ui.detailMode='modal';openTask('{tid}')}})()"); await pg.wait_for_timeout(600)
        labels = await E("[...document.querySelectorAll('#detail .fl-row .fl-l')].map(e=>e.textContent.trim())")
        check(labels == ['Task Update', 'Finance', 'Guardian'], f'Fields under the description for an Admin: {labels}')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'fields_empty.png'))
        await E("db.tasks.slice(0,3).forEach(t=>t.update='Shoot')")
        await pg.click('#detail [data-action="field-pick"][data-k="update"]'); await pg.wait_for_timeout(300)
        opts = await E("[...document.querySelectorAll('.fl-menu .mi:not(.fl-clear)')].map(e=>e.textContent.trim())")
        check(opts[0] == 'Shoot' and len(opts) == 26, f'Task Update options, most used first: {opts[:3]}… ({len(opts)})')
        await E("window.__sent=[]; const _p=pushNotif; pushNotif=(to,t,kind,...a)=>{ if(kind==='update') window.__sent.push(to); return _p(to,t,kind,...a); }")
        await pg.locator('.fl-menu .mi', has_text='WIP').first.click(); await pg.wait_for_timeout(400)
        t = await E(f"(()=>{{const t=task('{tid}');return [t.update, t.activity.slice(-1)[0].text, window.__sent]}})()")
        w = await E(f"watchersOf(task('{tid}')).filter(u=>u!==currentUserId)")
        check(t[0] == 'WIP' and 'Task Update' in t[1], f'choosing WIP saves it and logs it: {t[1]}')
        check(set(t[2]) == set(w) and len(w) > 0, f'everyone on the task gets an Inbox notification {t[2]}')
        await pg.click('#detail [data-action="field-pick"][data-k="finance"]'); await pg.wait_for_timeout(300)
        await pg.locator('.fl-menu .mi', has_text='LPO Pending').click(); await pg.wait_for_timeout(300)
        check(await E(f"task('{tid}').finance") == 'LPO Pending', 'Admin sets Finance')
        await pg.click('#detail [data-action="field-pick"][data-k="guardian"]'); await pg.wait_for_timeout(300)
        heads = await E("[...document.querySelectorAll('.fl-menu .wf-mh')].map(e=>e.textContent)")
        check(heads[0] == 'Production' and set(heads) <= {'Production', 'Social', 'Freelancers'}, f'Guardian list grouped by role {heads}')
        await pg.locator('.fl-menu .wf-person').first.click(); await pg.wait_for_timeout(300)
        g = await E(f"task('{tid}').guardian")
        check(bool(g) and await E(f"userById('{g}').role") == 'production', 'Guardian set')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'fields_set.png'))
        await E("ui.fieldsHideEmpty=true; renderDetail()")
        check(await pg.locator('#detail .fl-row').count() == 3, 'nothing empty to hide now')
        check(not errs, f'no page errors {errs}')
        prod = await E("db.users.find(u=>u.role==='production').email")
        await pg.wait_for_timeout(1200)
        await ctx.close()
        ctx, pg, errs = await login(prod); E = pg.evaluate
        await E(f"openTask('{tid}')"); await pg.wait_for_timeout(600)
        labels = await E("[...document.querySelectorAll('#detail .fl-row .fl-l')].map(e=>e.textContent.trim())")
        check(labels == ['Task Update', 'Guardian'], f'Production does not see Finance: {labels}')
        check(await E(f"task('{tid}').update") == 'WIP', 'the Task Update reached the others')
        await ctx.close()
        ctx, pg, errs = await login(ADMIN, (390, 844)); E = pg.evaluate
        await E(f"openTask('{tid}')"); await pg.wait_for_timeout(700)
        await pg.locator('#detail .fl-sec').scroll_into_view_if_needed(); await pg.wait_for_timeout(200)
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'fields_phone.png'))
        check(await pg.locator('#detail .fl-row').count() == 3, 'Fields show on the phone')
        await ctx.close()
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
