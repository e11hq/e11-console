"""Scheduled comments (desktop): Send / Reply with a ⌄ that opens the scheduler (typed time, quick picks, calendar
and times, office-hours note); a scheduled comment shows only for its author with Edit / Send now / Cancel; the server
posts it at its time; a task completed first cancels it (Inbox → back as a draft); a deleted one shows its text."""
import asyncio, os, tempfile, time, subprocess, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18233; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
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
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE, permissions=['clipboard-read', 'clipboard-write'])
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(3000)
            await pg.evaluate("document.querySelectorAll('.hello-wrap,.pa-card').forEach(e => e.remove())")
            ids = await pg.evaluate("db.tasks.filter(t => !t.done && !t.parentId && !(t.needsCD && t.cdStatus !== 'approved')).slice(0, 4).map(t => t.id)")
            a, b2, c3, d4 = ids
            async def write(tid, text):
                await pg.evaluate(f"ui.forceTab = 'comments'; openTask('{tid}')"); await pg.wait_for_timeout(500)
                await pg.click('#detail #d-comment'); await pg.keyboard.type(text); await pg.wait_for_timeout(150)
            # --- the button
            await write(a, 'Hi Amelia, the carousel is ready')
            btn = await pg.inner_text('#detail .send-split [data-action="add-comment"]')
            check(btn.strip() == 'Send', f'the comment button says Send {btn!r}')
            await pg.click('#detail .sc-chev'); await pg.wait_for_timeout(300)
            check(await pg.evaluate("!!document.getElementById('sc-pop')"), 'the ⌄ opens the scheduler')
            labels = await pg.eval_on_selector_all('#sc-pop .sc-q .sc-ql', 'els => els.map(e => e.textContent)')
            check(labels == ['In 20 minutes', 'In 2 hours', 'Tomorrow', 'In 2 days', 'Next week'], f'quick picks {labels}')
            times = await pg.eval_on_selector_all('#sc-pop .sc-q .sc-qt', 'els => els.map(e => e.textContent)')
            check(all('9:00 AM' in x for x in times[2:]), f'day picks at 9:00 AM {times}')
            check(await pg.evaluate("document.querySelectorAll('#sc-pop .sc-d').length") == 42, 'a month calendar')
            await pg.screenshot(path=os.path.join(OUT, 'sched_pop.png'))
            # typing a time
            await pg.fill('#sc-q', 'thu 2pm'); await pg.wait_for_timeout(200)
            hit = await pg.inner_text('#sc-pop .sc-hit')
            check('2:00 PM' in hit and 'Schedule' in hit, f'a typed time is understood {hit!r}')
            await pg.fill('#sc-q', 'saturday 10am'); await pg.wait_for_timeout(200)
            check('Outside office hours' in await pg.inner_text('#sc-pop'), 'a weekend time shows the office-hours note')
            await pg.fill('#sc-q', 'blah'); await pg.wait_for_timeout(150)
            check('Try “tomorrow 10am”' in await pg.inner_text('#sc-pop'), 'an unreadable time gives examples')
            await pg.fill('#sc-q', ''); await pg.wait_for_timeout(150)
            # a day on the calendar, then a time
            await pg.click('#sc-pop .sc-d:not(.out):not(:disabled):not(.today) >> nth=3'); await pg.wait_for_timeout(200)
            check(await pg.evaluate("document.querySelectorAll('#sc-pop .sc-t').length") >= 1 and 'Schedule for' in await pg.inner_text('#sc-pop .sc-go'), 'picking a day shows times and a Schedule button')
            await pg.fill('#sc-other', '7:30 pm'); await pg.wait_for_timeout(200)
            check('7:30 PM' in await pg.inner_text('#sc-pop .sc-go') and 'Outside office hours' in await pg.inner_text('#sc-pop'), 'another time after 6 PM shows the note')
            await pg.screenshot(path=os.path.join(OUT, 'sched_day.png'))
            await pg.click('#sc-pop [data-sc-back]'); await pg.wait_for_timeout(150)
            # schedule for tomorrow
            await pg.click('#sc-pop .sc-q >> nth=2'); await pg.wait_for_timeout(500)
            s = await pg.evaluate(f"db.scheduled.find(s => s.taskId === '{a}' && s.state === 'waiting')")
            check(s is not None and 'carousel' in s['text'], 'Tomorrow schedules the comment')
            check(not await pg.evaluate(f"ui.commentDraft['{a}']") and await pg.inner_text('#detail #d-comment') == '', 'and clears the comment box')
            card = await pg.inner_text('#detail .sc-card')
            check('Scheduled ·' in card and '9:00 AM' in card and 'Send now' in card, f'it shows in the task {card[:80]!r}')
            await pg.screenshot(path=os.path.join(OUT, 'sched_card.png'))
            await pg.wait_for_timeout(800)
            # nobody else receives it
            other = await pg.evaluate("db.users.find(u => u.role === 'am' && u.active !== false).email")
            req = urllib.request.Request(BASE + '/api/snapshot', headers={'X-Dev-Email': other})
            import json
            check(len(json.loads(urllib.request.urlopen(req).read())['data'].get('scheduled', [])) == 0, 'other people don’t receive it')
            # Edit → back in the comment box
            await pg.click('#detail .sc-card [data-sc-act="edit"]'); await pg.wait_for_timeout(400)
            check('carousel' in await pg.inner_text('#detail #d-comment') and not await pg.evaluate(f"db.scheduled.some(s => s.taskId === '{a}' && s.state === 'waiting')"), 'Edit puts it back in the comment box')
            # schedule again, then Send now
            await pg.click('#detail .sc-chev'); await pg.wait_for_timeout(200)
            await pg.click('#sc-pop .sc-q >> nth=3'); await pg.wait_for_timeout(400)
            n0 = await pg.evaluate(f"task('{a}').comments.length")
            await pg.click('#detail .sc-card [data-sc-act="now"]'); await pg.wait_for_timeout(400)
            check(await pg.evaluate(f"task('{a}').comments.length") == n0 + 1 and not await pg.query_selector('#detail .sc-card'), 'Send now posts it')
            # Cancel
            await write(a, 'never mind')
            await pg.click('#detail .sc-chev'); await pg.wait_for_timeout(200)
            await pg.click('#sc-pop .sc-q >> nth=4'); await pg.wait_for_timeout(400)
            await pg.click('#detail .sc-card [data-sc-act="cancel"]'); await pg.wait_for_timeout(400)
            check(not await pg.evaluate(f"db.scheduled.some(s => s.taskId === '{a}' && s.state === 'waiting')"), 'Cancel removes it')
            # a reply: the button says Reply
            cid = await pg.evaluate(f"task('{a}').comments.find(c => !c.parentId).id")
            await pg.evaluate(f"ui.replyTo = '{cid}'; renderDetail()"); await pg.wait_for_timeout(300)
            check((await pg.inner_text('#detail .send-split [data-action="add-comment"]')).strip() == 'Reply', 'a reply’s button says Reply')
            await pg.evaluate("ui.replyTo = null; renderDetail()")
            # --- the server sends it at its time
            await pg.evaluate(f"""(() => {{ db.scheduled.push({{ id: 's-e2e', taskId: '{b2}', taskTitle: task('{b2}').title, authorId: currentUserId, replyTo: null, text: 'Timed hello', html: 'Timed hello', attachments: [], sendAt: new Date(Date.now() + 32000).toISOString(), createdAt: nowISO(), state: 'waiting' }}); commit(); }})()""")
            ok = False
            for _ in range(30):
                await pg.wait_for_timeout(2000)
                if await pg.evaluate(f"task('{b2}').comments.some(c => c.text === 'Timed hello')"): ok = True; break
            check(ok, 'the server posts it at its time')
            # --- completed first: cancelled, Inbox, back as a draft
            await pg.evaluate(f"""(() => {{ db.scheduled.push({{ id: 's-done', taskId: '{c3}', taskTitle: task('{c3}').title, authorId: currentUserId, replyTo: null, text: 'Done already?', html: 'Done already?', attachments: [], sendAt: new Date(Date.now() + 86400000).toISOString(), createdAt: nowISO(), state: 'waiting' }}); commit(); }})()""")
            await pg.wait_for_timeout(800)
            await pg.evaluate(f"(() => {{ const t = task('{c3}'); setDone(t, true); commit(); }})()")
            n = None
            for _ in range(20):
                await pg.wait_for_timeout(500)
                n = await pg.evaluate("db.notifications.find(n => n.kind === 'sched-cancel' && n.schedId === 's-done')")
                if n: break
            check(n is not None and 'was completed before' in n['text'], 'completing the task cancels it and tells you')
            await pg.evaluate("closeDetail(); go('inbox')"); await pg.wait_for_timeout(500)
            row = await pg.inner_text('#content')
            check('Scheduled comment' in row and 'wasn’t sent' in row, 'the Inbox shows it')
            await pg.screenshot(path=os.path.join(OUT, 'sched_inbox.png'))
            await pg.evaluate(f"openNotif('{n['id']}')"); await pg.wait_for_timeout(700)
            check(await pg.evaluate('ui.taskId') == c3 and 'Done already?' in await pg.inner_text('#detail #d-comment'), 'tapping it opens the task with the comment back as a draft')
            # --- deleted first: its text and files (for someone without the Trash)
            await pg.evaluate(f"""(() => {{ db.scheduled.push({{ id: 's-del', taskId: '{d4}', taskTitle: task('{d4}').title, authorId: currentUserId, replyTo: null, text: 'Lost words', html: 'Lost words', attachments: [{{ id: 'f', name: 'cut.mp4', path: 'attachments/{d4}/cut.mp4', size: 3 }}], sendAt: new Date(Date.now() + 86400000).toISOString(), createdAt: nowISO(), state: 'waiting' }}); commit(); }})()""")
            await pg.wait_for_timeout(800)
            await pg.evaluate(f"closeDetail(); deleteTask(task('{d4}'))") if await pg.evaluate("typeof deleteTask === 'function'") else await pg.evaluate(f"(() => {{ db.tasks = db.tasks.filter(t => t.id !== '{d4}'); commit(); }})()")
            n = None
            for _ in range(20):
                await pg.wait_for_timeout(500)
                n = await pg.evaluate("db.notifications.find(n => n.kind === 'sched-cancel' && n.schedId === 's-del')")
                if n: break
            check(n is not None and 'was deleted before' in n['text'], 'deleting the task cancels it and tells you')
            await pg.evaluate("db.trash = []")   # (as someone who can't see the Trash)
            await pg.evaluate(f"openNotif('{n['id']}')"); await pg.wait_for_timeout(400)
            txt = await pg.inner_text('#sc-lost') if await pg.query_selector('#sc-lost') else ''
            check('Lost words' in txt and 'Copy text' in txt and 'cut.mp4' in txt and 'comes back as a draft' in txt, 'without the Trash: its text, Copy text and files')
            await pg.screenshot(path=os.path.join(OUT, 'sched_lost.png'))
            check(not errs, f'no page errors {errs}')
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
