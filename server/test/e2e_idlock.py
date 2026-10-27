"""After CD review a task's name, description and client (and its subtasks' names) are locked in the app; the task
offers New task from this (linked both ways); comments can be pinned to the brief, show under the description and
jump to the comment; a pinned comment can't be edited."""
import asyncio, os, tempfile, time, subprocess, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18235; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
OUT = tempfile.gettempdir()
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.7.1-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(3000)
            await pg.evaluate("document.querySelectorAll('.hello-wrap,.pa-card').forEach(e => e.remove())")
            locked = await pg.evaluate("db.tasks.find(t => !t.parentId && (t.reviews || []).length && (t.comments || []).length > 1 && db.tasks.some(s => s.parentId === t.id)) || db.tasks.find(t => !t.parentId && (t.reviews || []).length && (t.comments || []).length > 1)")
            free = await pg.evaluate("db.tasks.find(t => !t.parentId && !(t.reviews || []).length && !t.lockedAt).id")
            lid = locked['id']
            check(await pg.evaluate(f"idLocked(task('{lid}'))") and not await pg.evaluate(f"idLocked(task('{free}'))"), 'tasks already sent for CD review are locked; others aren’t')
            # an open task: editable as before
            await pg.evaluate(f"openTask('{free}')"); await pg.wait_for_timeout(400)
            check(await pg.get_attribute('#d-title', 'readonly') is None and not await pg.query_selector('#detail .id-lock'), 'a task never sent for review is editable')
            # the locked task
            await pg.evaluate(f"openTask('{lid}')"); await pg.wait_for_timeout(500)
            check(await pg.get_attribute('#d-title', 'readonly') is not None, 'the name is read only')
            note = await pg.inner_text('#detail .id-lock')
            check('locked' in note and 'CD review' in note and 'New task from this' in note, f'a lock note with New task from this {note[:90]!r}')
            check(await pg.get_attribute('#d-project', 'disabled') is not None, 'the client can’t be changed')
            await pg.click('#detail .desc-view') if await pg.query_selector('#detail .desc-view') else None
            await pg.wait_for_timeout(200)
            check(not await pg.query_selector('#detail #d-notes'), 'the description doesn’t open for editing')
            subs = await pg.eval_on_selector_all('#detail .sub-title', 'els => els.map(e => e.readOnly)')
            check(all(subs), f'subtask names are read only {subs}')
            # typing into the name is ignored even if forced
            title0 = locked['title']
            await pg.evaluate("(() => { const el = document.getElementById('d-title'); el.removeAttribute('readonly'); el.value = 'Another job'; el.dispatchEvent(new Event('input', { bubbles: true })); })()")
            await pg.wait_for_timeout(300)
            check(await pg.evaluate(f"task('{lid}').title") == title0, 'a forced edit of the name is undone')
            await pg.screenshot(path=os.path.join(OUT, 'idlock_task.png'))
            # Pin to brief
            cid = await pg.evaluate(f"task('{lid}').comments.find(c => !c.parentId).id")
            await pg.evaluate(f"(() => {{ ui.sideTab = 'comments'; renderDetail(); }})()"); await pg.wait_for_timeout(300)
            await pg.evaluate(f"commentMenu(document.querySelector('#detail [data-comment=\"{cid}\"]'), '{cid}')"); await pg.wait_for_timeout(200)
            items = await pg.eval_on_selector_all('.menu .mi', 'els => els.map(e => e.textContent.trim())')
            check('Pin to brief' in items, f'the comment menu offers Pin to brief {items}')
            await pg.click('.menu .mi:has-text("Pin to brief")'); await pg.wait_for_timeout(400)
            await pg.evaluate("ui.sideTab = 'details'; renderDetail()"); await pg.wait_for_timeout(300)
            strip = await pg.inner_text('#detail .brief-pins') if await pg.query_selector('#detail .brief-pins') else ''
            check('brief updates' in strip.lower(), f'the pinned comment shows under the description {strip[:80]!r}')
            await pg.screenshot(path=os.path.join(OUT, 'idlock_pins.png'))
            await pg.click('#detail .bp-row'); await pg.wait_for_timeout(500)
            check(await pg.evaluate(f"!!document.querySelector('#detail [data-comment=\"{cid}\"].flash')") and await pg.evaluate("ui.sideTab") == 'comments', 'clicking it jumps to the comment')
            await pg.evaluate(f"commentMenu(document.querySelector('#detail [data-comment=\"{cid}\"]'), '{cid}')"); await pg.wait_for_timeout(200)
            items = await pg.eval_on_selector_all('.menu .mi', 'els => els.map(e => e.textContent.trim())')
            check('Edit comment' not in items and 'Unpin from brief' in items, f'a pinned comment can’t be edited; it can be unpinned {items}')
            await pg.evaluate("closeMenus()")
            # a long field list (Task Update) opens next to its button, not at the top of the window
            await pg.evaluate("ui.sideTab = 'details'; renderDetail()"); await pg.wait_for_timeout(200)
            fb = await pg.query_selector('#detail .fl-btn[data-k="update"]')
            if fb:
                await fb.scroll_into_view_if_needed(); await fb.click(); await pg.wait_for_timeout(300)
                gap = await pg.evaluate("(() => { const m = document.querySelector('.menu'), b = document.querySelector('#detail .fl-btn[data-k=\"update\"]').getBoundingClientRect(), r = m.getBoundingClientRect(); return Math.min(Math.abs(r.top - b.bottom), Math.abs(b.top - r.bottom)); })()")
                check(gap < 12, f'the Task Update list opens right next to its button (gap {gap}px)')
                await pg.evaluate("closeMenus()")
            # New task from this, closed without changes: it goes away again
            await pg.click('#detail [data-action="task-from"]'); await pg.wait_for_timeout(600)
            tmp = await pg.evaluate('ui.taskId')
            await pg.evaluate("closeDetail()"); await pg.wait_for_timeout(400)
            check(tmp != lid and not await pg.evaluate(f"!!task('{tmp}')"), 'an untouched New task from this disappears when closed')
            await pg.evaluate(f"openTask('{lid}')"); await pg.wait_for_timeout(400)
            # New task from this
            await pg.click('#detail [data-action="task-from"]'); await pg.wait_for_timeout(600)
            nid = await pg.evaluate('ui.taskId')
            n = await pg.evaluate(f"task('{nid}')")
            check(nid != lid and n['basedOn'] == lid and n['projectId'] == locked['projectId'] and n['title'] == '' and n['assignees'] == locked['assignees'], 'New task from this makes a fresh task with the same client and people')
            check(await pg.get_attribute('#d-title', 'readonly') is None and await pg.evaluate("document.activeElement && document.activeElement.id") == 'd-title', 'its name is empty, editable and focused')
            check('New task from' in await pg.inner_text('#detail .id-from'), 'it links back to the old task')
            await pg.fill('#d-title', 'KIA follow-up'); await pg.wait_for_timeout(600)
            await pg.evaluate(f"openTask('{lid}')"); await pg.wait_for_timeout(400)
            check('KIA follow-up' in await pg.inner_text('#detail .id-lock'), 'and the old task lists it')
            check(not errs, f'no page errors {errs}')
            # phone: the same lock
            ph = await b.new_context(viewport={'width': 390, 'height': 844}, base_url=BASE)
            await ph.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
            pp = await ph.new_page(); perrs = []; pp.on('pageerror', lambda e: perrs.append(str(e)))
            await pp.goto('/'); await pp.wait_for_timeout(3000)
            await pp.evaluate("document.querySelectorAll('.hello-wrap,.pa-card').forEach(e => e.remove())")
            await pp.evaluate(f"openTask('{lid}')"); await pp.wait_for_timeout(600)
            check(await pp.get_attribute('#d-title', 'readonly') is not None and await pp.query_selector('#detail .id-lock') is not None, 'the phone shows the lock too')
            await pp.screenshot(path=os.path.join(OUT, 'idlock_phone.png'))
            check(not perrs, f'no page errors on the phone {perrs}')
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
