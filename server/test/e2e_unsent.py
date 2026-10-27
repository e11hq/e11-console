"""Unsent comments: leaving a task (closing it or opening another) with a comment, a reply or files not sent
shows a pop-up — Send comment / Keep as draft / Go back. Keep as draft doesn't ask again until the draft changes;
drafts survive a reload; Send while files upload sends once they finish; the phone shows a bottom sheet."""
import asyncio, os, tempfile, time, subprocess, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18231; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
OUT = tempfile.gettempdir()
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.7.0-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            async def open_app(vp=(1440, 900)):
                ctx = await b.new_context(viewport={'width': vp[0], 'height': vp[1]}, base_url=BASE)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3000)
                await pg.evaluate("document.querySelectorAll('.hello-wrap,.pa-card').forEach(e => e.remove())")
                return ctx, pg, errs
            ctx, pg, errs = await open_app()
            ids = await pg.evaluate("db.tasks.filter(t => !t.done && !t.parentId).slice(0, 2).map(t => t.id)")
            a, b2 = ids
            async def type_comment(tid, text):
                await pg.evaluate(f"ui.forceTab = 'comments'; openTask('{tid}')"); await pg.wait_for_timeout(500)
                await pg.click('#detail #d-comment'); await pg.keyboard.type(text); await pg.wait_for_timeout(200)
            shown = lambda: pg.evaluate("!!document.getElementById('unsent-root')")
            # --- close with a typed comment → pop-up
            await type_comment(a, 'Hi Amelia, I updated the carousel')
            await pg.click('#detail button[data-action="close-detail"]'); await pg.wait_for_timeout(400)
            check(await shown(), 'closing a task with an unsent comment shows the pop-up')
            txt = await pg.inner_text('#unsent-root')
            check('hasn’t been sent' in txt and 'Hi Amelia' in txt and 'Send comment' in txt and 'Keep as draft' in txt and 'Go back' in txt, 'it shows the comment and the three choices')
            await pg.screenshot(path=os.path.join(OUT, 'unsent_desktop.png'))
            # Keep as draft → no pop-up next time until it changes
            await pg.click('[data-us="keep"]'); await pg.wait_for_timeout(200)
            check(not await shown(), 'Keep as draft closes it')
            await pg.evaluate(f"ui.forceTab = 'comments'; openTask('{a}')"); await pg.wait_for_timeout(500)
            check('Hi Amelia' in await pg.inner_text('#detail #d-comment'), 'the draft is still in the task')
            await pg.evaluate("closeDetail()"); await pg.wait_for_timeout(300)
            check(not await shown(), 'a kept draft doesn’t ask again')
            # change it, then open another task → asks again; Go back returns to it
            await type_comment(a, ' — can you check?')
            await pg.evaluate(f"openTask('{b2}')"); await pg.wait_for_timeout(400)
            check(await shown(), 'opening another task asks again after the draft changed')
            await pg.click('[data-us="back"]'); await pg.wait_for_timeout(500)
            check(await pg.evaluate('ui.taskId') == a and 'can you check' in await pg.inner_text('#detail #d-comment'), 'Go back reopens the task with the comment')
            # Send comment from the pop-up
            n0 = await pg.evaluate(f"task('{a}').comments.length")
            await pg.evaluate("closeDetail()"); await pg.wait_for_timeout(300)
            await pg.click('[data-us="send"]'); await pg.wait_for_timeout(400)
            c = await pg.evaluate(f"task('{a}').comments.slice(-1)[0]")
            check(await pg.evaluate(f"task('{a}').comments.length") == n0 + 1 and 'can you check' in c['text'], 'Send comment posts it')
            check(not await pg.evaluate(f"ui.commentDraft['{a}']"), 'and clears the draft')
            # a reply: names who it's for
            cid = await pg.evaluate(f"(task('{a}').comments.find(c => !c.parentId && c.authorId !== currentUserId) || task('{a}').comments[0]).id")
            await pg.evaluate(f"ui.forceTab = 'comments'; openTask('{a}'); ui.replyTo = '{cid}'; renderDetail()"); await pg.wait_for_timeout(400)
            await pg.click('#detail #d-comment'); await pg.keyboard.type('Noted, new cut by 4 PM'); await pg.wait_for_timeout(200)
            await pg.evaluate("closeDetail()"); await pg.wait_for_timeout(300)
            txt = await pg.inner_text('#unsent-root') if await shown() else ''
            check('Your reply hasn’t been sent' in txt and 'Reply to' in txt and 'Send reply' in txt, 'a reply says reply and who it is for')
            await pg.click('[data-us="keep"]')
            # drafts survive a reload
            await pg.wait_for_timeout(500)
            await pg.reload(); await pg.wait_for_timeout(3000)
            check('Noted' in (await pg.evaluate(f"ui.commentDraft['{a}:{cid}'] || ''")), 'drafts survive a reload')
            # files still uploading: Send waits for them, then sends by itself
            await pg.evaluate("document.querySelectorAll('.hello-wrap,.pa-card').forEach(e => e.remove())")
            await pg.evaluate(f"ui.forceTab = 'comments'; openTask('{b2}'); ui.commentUp['{b2}'] = {{ tid: '{b2}', replyTo: null, total: 1, frac: 0.4 }}"); await pg.wait_for_timeout(300)
            await pg.evaluate("closeDetail()"); await pg.wait_for_timeout(300)
            check(await shown() and 'Uploading 1 file' in await pg.inner_text('#unsent-root'), 'uploading files count as unsent')
            await pg.click('[data-us="send"]'); await pg.wait_for_timeout(200)
            check('Sending once your files finish' in await pg.inner_text('#unsent-root'), 'Send while uploading waits for the files')
            await pg.screenshot(path=os.path.join(OUT, 'unsent_uploading.png'))
            m0 = await pg.evaluate(f"task('{b2}').comments.length")
            await pg.evaluate(f"""(() => {{ ui.commentUp['{b2}'].frac = 0.9; Unsent.progress('{b2}'); delete ui.commentUp['{b2}'];
                ui.commentFiles['{b2}'] = [{{ id: 'f1', name: 'carousel-v3.mp4', path: 'x/carousel-v3.mp4', size: 10 }}]; Unsent.uploaded('{b2}', true); }})()""")
            await pg.wait_for_timeout(300)
            check(await pg.evaluate(f"task('{b2}').comments.length") == m0 + 1 and not await shown(), 'once uploaded it sends by itself')
            check(not errs, f'no page errors {errs}')
            await ctx.close()
            # --- phone: bottom sheet
            ctx, pg, errs = await open_app((390, 844))
            await pg.evaluate(f"ui.forceTab = 'comments'; openTask('{a}')"); await pg.wait_for_timeout(600)
            await pg.evaluate(f"ui.commentDraft['{a}'] = 'Hi Amelia, I updated the carousel with the new Arabic copy'")
            await pg.evaluate("closeDetail()"); await pg.wait_for_timeout(400)
            box = await pg.evaluate("(() => { const c = document.querySelector('#unsent-root .us-card'); if (!c) return null; const r = c.getBoundingClientRect(); return [r.left, r.bottom, r.width]; })()")
            check(box is not None and box[0] == 0 and abs(box[1] - 844) < 2 and box[2] == 390, f'the phone shows a bottom sheet {box}')
            order = await pg.evaluate("[...document.querySelectorAll('#unsent-root .us-acts .btn')].map(b => [b.dataset.us, Math.round(b.getBoundingClientRect().top)]).sort((x, y) => x[1] - y[1]).map(x => x[0])")
            check(order == ['send', 'keep', 'back'], f'Send comes first on the phone {order}')
            await pg.screenshot(path=os.path.join(OUT, 'unsent_phone.png'))
            check(not errs, f'no page errors on the phone {errs}')
            await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
