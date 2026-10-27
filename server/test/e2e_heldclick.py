"""A held click on a button right after typing in a field (an update arrived meanwhile) works the first time:
the page waits until the mouse is released before catching up, so the button is not redrawn under the pointer."""
import asyncio, os, tempfile, time, subprocess, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18247; BASE=f"http://127.0.0.1:{PORT}"; ADMIN="haris@e11-digital.com"
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': ROOT + '/web', 'APP_VERSION': '1.7.1-test.1'}
    srv = subprocess.Popen(['node', ROOT + '/server/src/index.js'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    async with async_playwright() as pw:
        b = await pw.chromium.launch()
        ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
        await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
        pg = await ctx.new_page(); await pg.goto('/'); await pg.wait_for_timeout(3200)
        await pg.evaluate("document.querySelectorAll('.hello-wrap,.pa-card,#notif-root').forEach(e => e.remove())")
        ok = 0
        for i in range(3):
            lid = await pg.evaluate("db.tasks.find(t => !t.parentId && (t.reviews||[]).length).id")
            await pg.evaluate(f"ui.detailMode = 'side'; openTask('{lid}')"); await pg.wait_for_timeout(500)
            await pg.click('#detail [data-action="task-from"]'); await pg.wait_for_timeout(1500)
            nid = await pg.evaluate('ui.taskId')
            # someone else changes something meanwhile (an update arrives while the name box has focus)
            other = await pg.evaluate("db.tasks.find(t => !t.parentId && t.id !== ui.taskId && !t.done).id")
            req = urllib.request.Request(BASE + '/api/snapshot', headers={'X-Dev-Email': ADMIN})
            t = [x for x in json.loads(urllib.request.urlopen(req).read())['data']['tasks'] if x['id'] == other][0]
            t2 = dict(t, tags=(t.get('tags') or []) + ['x%d' % i])
            urllib.request.urlopen(urllib.request.Request(BASE + '/api/push', method='POST', data=json.dumps({'changes': [{'kind': 'tasks', 'id': other, 'base': t, 'data': t2}]}).encode(), headers={'X-Dev-Email': 'areej@e11-digital.com', 'Content-Type': 'application/json'}))
            await pg.wait_for_timeout(800)
            r = await pg.eval_on_selector('#detail [data-action="delete-task"]', 'e => { const r = e.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; }')
            await pg.mouse.move(r[0], r[1]); await pg.mouse.down(); await pg.wait_for_timeout(250); await pg.mouse.up(); await pg.wait_for_timeout(600)
            gone = not await pg.evaluate(f"!!task('{nid}')")
            print('try', i, 'deleted with one held click:', gone)
            ok += gone
            if not gone: await pg.evaluate(f"deleteTaskFlow('{nid}')")
        print('RESULT', ok, '/ 3'); raise SystemExit(0 if ok == 3 else 1)
        await b.close()
    srv.terminate()
asyncio.run(main())
