"""Phone: every pop-up is a bottom sheet you can drag down to close; touching and holding a comment opens one
sheet with reactions, Reply, Edit comment, Copy text and Delete comment."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18233; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
OUT = tempfile.mkdtemp(); fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.3.3-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=3, is_mobile=True, has_touch=True, base_url=BASE)
        await ctx.add_cookies([{'name': 'e11_dev_email', 'value': 'areej@e11-digital.com', 'url': BASE}])
        pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto('/'); await pg.wait_for_timeout(2500); await pg.mouse.click(5, 5); await pg.wait_for_timeout(1500)
        cdp = await ctx.new_cdp_session(pg)
        async def touch(kind, x, y):
            await cdp.send('Input.dispatchTouchEvent', {'type': kind, 'touchPoints': [] if kind == 'touchEnd' else [{'x': x, 'y': y}]})
        E = pg.evaluate
        # a task with comments; post one of Areej's own so Edit / Delete show
        tid = await E("db.tasks.find(t=>!t.parentId && (t.comments||[]).length>1).id")
        await E(f"openTask('{tid}')"); await pg.wait_for_timeout(800)
        await E("(()=>{const t=task(ui.taskId); t.comments.push({id:'c-mine', authorId: currentUserId, text:'Looks good, sending to the client now.', html:'', at: nowISO(), reactions:{}}); commit();})()")
        await E("ui.sideTab='comments'; renderDetail()"); await pg.wait_for_timeout(600)
        check(await E("getComputedStyle(document.querySelector('.cm .cm-tools')).display") == 'none', 'the small buttons on each comment are hidden on the phone')
        # hold my comment
        await E("document.querySelector('.cm[data-comment=\"c-mine\"]').scrollIntoView({block:'center'})"); await pg.wait_for_timeout(300)
        bb = await pg.locator('.cm[data-comment="c-mine"] .cm-text').bounding_box()
        x, y = bb['x'] + 40, bb['y'] + bb['height'] / 2
        await touch('touchStart', x, y); await pg.wait_for_timeout(250); await touch('touchEnd', x, y); await pg.wait_for_timeout(300)
        check(await pg.locator('.menu.cm-sheet').count() == 0, 'a short tap does not open the sheet')
        await touch('touchStart', x, y); await pg.wait_for_timeout(650)
        check(await pg.locator('.menu.cm-sheet').count() == 1, 'touch and hold opens the comment sheet')
        await touch('touchEnd', x, y); await pg.wait_for_timeout(400)
        check(await pg.locator('.menu.cm-sheet').count() == 1, 'lifting the finger keeps the sheet open')
        items = await E("[...document.querySelectorAll('.menu.cm-sheet .mi')].map(m=>m.textContent.trim())")
        check(items == ['Reply', 'Edit comment', 'Copy text', 'Delete comment'], f'sheet items: {items}')
        check(await pg.locator('.menu.cm-sheet .react-pick button').count() >= 5, 'reactions across the top')
        box = await pg.locator('.menu.cm-sheet').bounding_box()
        check(abs(box['x']) < 1 and abs(box['width'] - 390) < 1 and abs(box['y'] + box['height'] - 844) < 2, f'sheet runs edge to edge along the bottom {box}')
        await pg.screenshot(path=os.path.join(OUT, 'cm-sheet.png'))
        await pg.locator('.menu.cm-sheet .react-pick button').nth(2).tap(); await pg.wait_for_timeout(500)
        r = await E("task(ui.taskId).comments.find(c=>c.id==='c-mine').reactions")
        check(len(r) == 1, f'tapping a reaction adds it: {r}')
        # holding low on the screen, where the sheet's items appear, and lifting late must not tap them
        await E("closeMenus()"); await pg.wait_for_timeout(300)
        bb = await pg.locator('.cm[data-comment="c-mine"] .cm-text').bounding_box()
        await E("(()=>{const c=document.querySelector('.cm[data-comment=\"c-mine\"]'); const s=document.querySelector('#detail .tm-activity, #detail .tm-scroll') ; c.scrollIntoView({block:'end'});})()"); await pg.wait_for_timeout(300)
        bb = await pg.locator('.cm[data-comment="c-mine"] .cm-text').bounding_box()
        hx, hy = bb['x'] + 40, bb['y'] + bb['height'] / 2
        await touch('touchStart', hx, hy); await pg.wait_for_timeout(1400)
        under = await E(f"(()=>{{const m=document.querySelector('.menu.cm-sheet'); m.style.pointerEvents='auto'; const el=document.elementFromPoint({hx},{hy}); m.style.pointerEvents='none'; return !!(el && el.closest('.menu.cm-sheet'))}})()")
        await touch('touchEnd', hx, hy); await pg.wait_for_timeout(500)
        check(await pg.locator('.menu.cm-sheet').count() == 1 and await E("!ui.editingComment"), f'lifting a long hold over the sheet taps nothing (finger over the sheet: {under})')
        await pg.locator('.menu.cm-sheet .mi').filter(has_text='Copy text').tap(); await pg.wait_for_timeout(400)
        check(await pg.locator('.menu.cm-sheet').count() == 0, 'the sheet works normally once the finger is up')
        # someone else's comment: no Edit / Delete
        other = await E("task(ui.taskId).comments.find(c=>c.authorId!==currentUserId && !c.parentId).id")
        await E(f"document.querySelector('.cm[data-comment=\"{other}\"]').scrollIntoView({{block:'center'}})"); await pg.wait_for_timeout(300)
        bb = await pg.locator(f'.cm[data-comment="{other}"] .cm-meta').bounding_box()
        await touch('touchStart', bb['x'] + 120, bb['y'] + 8); await pg.wait_for_timeout(650); await touch('touchEnd', bb['x'] + 120, bb['y'] + 8); await pg.wait_for_timeout(400)
        items = await E("[...document.querySelectorAll('.menu.cm-sheet .mi')].map(m=>m.textContent.trim())")
        check(items == ['Reply', 'Copy text'], f"someone else's comment: {items}")
        # drag the sheet down by its handle to close it
        box = await pg.locator('.menu.cm-sheet').bounding_box()
        hx, hy = 195, box['y'] + 12
        await touch('touchStart', hx, hy)
        for k in range(1, 9): await touch('touchMove', hx, hy + k * 22); await pg.wait_for_timeout(16)
        await touch('touchEnd', hx, hy + 176); await pg.wait_for_timeout(500)
        check(await pg.locator('.menu').count() == 0, 'dragging the handle down closes the sheet')
        # a short drag springs back
        await E("ui.sideTab='details'; renderDetail()"); await pg.wait_for_timeout(500)
        await pg.locator('[data-action="prio-menu"]').first.tap(); await pg.wait_for_timeout(500)
        check(await pg.locator('.menu').count() == 1, 'priority opens as a sheet')
        box = await pg.locator('.menu').bounding_box(); hy = box['y'] + 12
        await touch('touchStart', 195, hy); await touch('touchMove', 195, hy + 20); await touch('touchMove', 195, hy + 40); await pg.wait_for_timeout(300); await touch('touchEnd', 195, hy + 40); await pg.wait_for_timeout(400)
        box2 = await pg.locator('.menu').bounding_box()
        check(await pg.locator('.menu').count() == 1 and abs(box2['y'] - box['y']) < 2, 'a short drag springs back')
        await pg.screenshot(path=os.path.join(OUT, 'prio-sheet.png'))
        # drag from the middle of the sheet (not the handle) also closes it
        box = await pg.locator('.menu').bounding_box(); my = box['y'] + box['height'] / 2
        await touch('touchStart', 300, my)
        for k in range(1, 10): await touch('touchMove', 300, my + k * 20); await pg.wait_for_timeout(16)
        await touch('touchEnd', 300, my + 180); await pg.wait_for_timeout(450)
        check(await pg.locator('.menu').count() == 0, 'dragging from the middle of a sheet closes it too')
        # a plain tap on an item still picks it
        await pg.locator('[data-action="prio-menu"]').first.tap(); await pg.wait_for_timeout(500)
        await pg.locator('.prio-menu .mi').first.tap(); await pg.wait_for_timeout(500)
        check(await pg.locator('.menu').count() == 0 and 'urgent' in json.dumps(await E("task(ui.taskId).prio || {}")), 'a tap on an item still picks it')
        await E("closeMenus()")
        # assignee list: search on top, list scrolls, sheet sits on the bottom
        await pg.locator('.asg-add').first.tap(); await pg.wait_for_timeout(600)
        box = await pg.locator('.menu.asg-pop').bounding_box()
        check(box and abs(box['y'] + box['height'] - 844) < 2, f'the assignee list is a bottom sheet {box}')
        check(await E("document.activeElement.tagName") != 'INPUT', 'the keyboard does not open by itself')
        await pg.screenshot(path=os.path.join(OUT, 'asg-sheet.png'), clip={'x': 0, 'y': 150, 'width': 390, 'height': 120})
        # the comment box: slim bar, opens while writing, sends, tucks away by its handle
        await E("closeMenus(); ui.sideTab='comments'; renderDetail()"); await pg.wait_for_timeout(500)
        c = pg.locator('#detail .tm-composer')
        check('ph-open' not in (await c.get_attribute('class')), 'comment box starts as a slim bar')
        h0 = (await c.bounding_box())['height']
        await pg.locator('#d-comment').tap(); await pg.wait_for_timeout(300)
        check('ph-open' in (await c.get_attribute('class')), 'tapping it opens the box')
        await E("document.execCommand('insertText', false, 'Sent from the phone sheet')"); await pg.wait_for_timeout(200)
        h1 = (await c.bounding_box())['height']
        check(h1 > h0 + 40, f'open box is taller with the formatting row ({h0:.0f} → {h1:.0f})')
        await pg.screenshot(path=os.path.join(OUT, 'composer.png'))
        await pg.locator('#detail .tm-composer [data-action="add-comment"]').tap(); await pg.wait_for_timeout(600)
        check(await E("task(ui.taskId).comments.some(c=>c.text==='Sent from the phone sheet')"), 'the round send button posts the comment')
        await pg.locator('#d-comment').tap(); await pg.wait_for_timeout(300)
        bb = await c.bounding_box()
        await touch('touchStart', 195, bb['y'] + 12); await touch('touchMove', 195, bb['y'] + 60); await touch('touchEnd', 195, bb['y'] + 60); await pg.wait_for_timeout(400)
        check('ph-open' not in (await c.get_attribute('class')), 'pulling the handle down tucks the box away')
        check(not errs, f'no page errors {errs}')
        # Comments open at the newest one; scrolling up with a finger is not pulled back down while pictures load
        await E("closeMenus()"); await E("closeDetail()"); await pg.wait_for_timeout(300)
        tid2 = await E("db.tasks.filter(t=>(t.comments||[]).some(c=>(c.attachments||[]).length))[0].id")
        await E(f"(()=>{{const t=task('{tid2}'); const img=t.comments.find(c=>(c.attachments||[]).length).attachments[0]; for(let i=0;i<12;i++) t.comments.push({{id:'fill'+i, authorId: currentUserId, text:'Filler comment '+i+' with enough words to take up some room.', html:'', at: nowISO(), reactions:{{}}, attachments: i%4===0 ? [{{...img, id:'fa'+i}}] : []}}); }})()")
        await E(f"openTask('{tid2}')"); await pg.wait_for_timeout(300)
        await pg.locator('#detail button', has_text='Comments').first.tap(); await pg.wait_for_timeout(400)
        fe = "(()=>{const f=document.querySelector('#detail .tm-feed'); return [f.scrollTop, f.scrollHeight-f.clientHeight]})()"
        r = await E(fe); check(r[1] > 200 and r[0] >= r[1] - 30, f'comments open at the newest one {r}')
        fb = await pg.locator('#detail .tm-feed').bounding_box()
        fx, fy = fb['x'] + fb['width'] / 2, fb['y'] + 80
        await touch('touchStart', fx, fy)
        for k in range(1, 8): await touch('touchMove', fx, fy + k * 40); await pg.wait_for_timeout(16)
        await touch('touchEnd', fx, fy + 280)
        await E("document.querySelector('#detail .tm-feed').scrollTop = 0"); await pg.wait_for_timeout(3000)
        r = await E(fe); check(r[0] < 50, f'scrolling up stays put (not pulled back to the newest comment) {r}')
        await b.close()
    srv.terminate()
    print('OUT', OUT)
    print('\n' + ('ALL PASS' if not fails else f'{len(fails)} FAILED'))
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
