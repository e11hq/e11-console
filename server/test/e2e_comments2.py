"""Comments: Edit comment only for the first 10 minutes (with the minutes left); read receipts on @mentions (Seen);
link preview cards (WeTransfer details, removable by the writer); and the morning round-up card for Account Managers."""
import asyncio, os, tempfile, time, subprocess, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18241; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'; AM = 'areej@e11-digital.com'; PROD = 'yousef@e11-digital.com'
OUT = tempfile.gettempdir()
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def page_as(b, email, w=1440, h=900):
    ctx = await b.new_context(viewport={'width': w, 'height': h}, base_url=BASE)
    await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
    pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
    await pg.goto('/'); await pg.wait_for_timeout(3000)
    await pg.evaluate("document.querySelectorAll('.hello-wrap,.pa-card').forEach(e => e.remove())")
    return pg, errs
async def menu_items(pg, cid):
    await pg.evaluate(f"commentMenu(document.querySelector('#detail [data-comment=\"{cid}\"]'), '{cid}')"); await pg.wait_for_timeout(200)
    items = await pg.eval_on_selector_all('.menu .mi', "els => els.map(e => { const c = e.cloneNode(true); const h = c.querySelector('small'); const hint = h ? h.textContent : ''; if (h) h.remove(); return [c.textContent.trim(), hint]; })")
    await pg.evaluate("closeMenus()")
    return items
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
            am, aerr = await page_as(b, AM)
            tid = await am.evaluate("(Work.leadSet([currentUserId]).find(t => !t.done && (t.assignees || []).includes('u-sara') && !idLocked(t)) || Work.leadSet([currentUserId]).find(t => !t.done && (t.assignees || []).includes('u-sara'))).id")
            check(bool(tid), f'a task of Areej’s with Yousef on it {tid}')
            nm = await am.evaluate("firstName('u-sara')")
            WT = 'https://wetransfer.com/downloads/0123456789abcdef0123456789abcdef/abcdef1234'
            await am.evaluate("""(wt) => {
              Cmx._cache.set(wt, { ok: true, url: wt, site: 'WeTransfer', key: 'wetransfer', title: 'KIA final videos', wt: { files: 2, size: 2400000000, expires: new Date(Date.now() + 1.5 * 86400000).toISOString(), names: ['KIA_final.mp4', 'KIA_cutdown.mp4'] } });
              Cmx._cache.set('https://example.com/brief', { ok: true, url: 'https://example.com/brief', site: 'example.com', title: 'Summer brief', desc: 'The campaign in one page', image: null, icon: null });
            }""", WT)
            await am.evaluate(f"""(() => {{ const t = task('{tid}'); const now = Date.now();
              t.comments.push({{ id: 'c-old', authorId: currentUserId, text: 'Sent yesterday', html: 'Sent yesterday', at: new Date(now - 20 * 60000).toISOString(), reactions: {{}}, attachments: [], parentId: null }});
              t.comments.push({{ id: 'c-men', authorId: currentUserId, text: '@Ali please check {WT} and https://example.com/brief', html: '<span class="mention" data-user="u-sara" contenteditable="false">@Ali</span> please check {WT} and https://example.com/brief', at: new Date(now - 60000).toISOString(), reactions: {{}}, attachments: [], parentId: null }});
              commit(); }})()""")
            await am.wait_for_timeout(800)
            await am.evaluate(f"ui.sideTab = ui.forceTab = 'comments'; openTask('{tid}')"); await am.wait_for_timeout(800)
            # 1. edit window
            fresh = await menu_items(am, 'c-men')
            ed = [h for (l, h) in fresh if l == 'Edit comment']
            check(bool(ed) and 'min left' in ed[0], f'a new comment: Edit comment with the minutes left {fresh}')
            old = await menu_items(am, 'c-old')
            check('Edit comment' not in [l for (l, h) in old] and 'Delete comment' in [l for (l, h) in old], f'after 10 minutes: no Edit comment, Delete still there {old}')
            # 2. link cards
            await am.wait_for_timeout(300)
            cards = await am.eval_on_selector_all('#detail .cm[data-comment="c-men"] .lk-card', 'els => els.map(e => e.innerText.replace(/\\s+/g, " ").trim())')
            check(len(cards) == 2, f'two link cards under the comment {cards}')
            check(any('WeTransfer' in c and '2 files' in c and '2.4 GB' in c and 'Expires in 2 days' in c for c in cards), f'the WeTransfer card: files, size, expiry {cards}')
            check(await am.evaluate("!!document.querySelector('#detail .lk-card.wt .lk-wt.soon')"), 'expiring soon is highlighted')
            check(any('Summer brief' in c and 'The campaign' in c for c in cards), 'a normal page: title and description')
            await am.screenshot(path=os.path.join(OUT, 'cm2_cards.png'))
            # 3. Seen: not yet, then Ali opens the task and it comes into view
            seen0 = await am.inner_text('#detail .cm[data-comment="c-men"] .cm-seen')
            check(f'Not seen by {nm} yet' in seen0, f'before: {seen0!r}')
            ali, alerr = await page_as(b, PROD)
            await ali.evaluate(f"ui.sideTab = ui.forceTab = 'comments'; ui.focusComment = 'c-men'; openTask('{tid}')"); await ali.wait_for_timeout(4500)
            check(await ali.evaluate(f"!!(task('{tid}').comments.find(c => c.id === 'c-men').seen || {{}})['u-sara']"), 'Ali’s app marked it seen')
            await am.wait_for_timeout(1500)
            seen1 = await am.inner_text('#detail .cm[data-comment="c-men"] .cm-seen')
            check(seen1.startswith(f'Seen by {nm}'), f'Areej sees it: {seen1!r}')
            check(await am.evaluate("!!document.querySelector('#detail .cm[data-comment=\"c-men\"] .cm-seen.on .cm-seen-avs .avatar, #detail .cm[data-comment=\"c-men\"] .cm-seen.on .cm-seen-avs > *')"), 'with Ali’s face')
            # someone else on the task (the admin) sees it too
            ad, aderr = await page_as(b, ADMIN)
            await ad.evaluate(f"ui.sideTab = ui.forceTab = 'comments'; openTask('{tid}')"); await ad.wait_for_timeout(800)
            check((await ad.inner_text('#detail .cm[data-comment="c-men"] .cm-seen')).startswith(f'Seen by {nm}'), 'everyone on the task sees it')
            check(not (await ad.evaluate(f"task('{tid}').comments.find(c => c.id === 'c-men').seen || {{}}")).get(await ad.evaluate('currentUserId')), 'someone not mentioned doesn’t mark it')
            await am.screenshot(path=os.path.join(OUT, 'cm2_seen.png'))
            # remove a card (the writer only): the link stays in the words
            check(await ali.evaluate("!document.querySelector('#detail .cm[data-comment=\"c-men\"] .lk-x')"), 'others can’t remove the cards')
            await am.hover('#detail .cm[data-comment="c-men"] .lk-card.wt'); await am.click('#detail .cm[data-comment="c-men"] .lk-card.wt .lk-x'); await am.wait_for_timeout(500)
            check(await am.locator('#detail .cm[data-comment="c-men"] .lk-card').count() == 1 and 'wetransfer.com' in await am.inner_text('#detail .cm[data-comment="c-men"] .cm-text'), 'the card is gone, the link stays')
            # 4. morning round-up
            await am.evaluate("api('POST', '/api/daily/test', {})"); await am.wait_for_timeout(1500)
            n = await am.evaluate("db.notifications.filter(n => n.kind === 'daily' && n.to === currentUserId).length")
            check(n == 1, f'the summary arrives in the Inbox ({n})')
            await am.evaluate("closeDetail(); go('inbox')"); await am.wait_for_timeout(600)
            row = am.locator('.ib-row', has_text='Morning round-up').first
            check(await row.count() == 1, 'an Inbox row called Morning round-up')
            txt = await row.inner_text()
            check('Your day' in txt, f'with the numbers {txt[:140]!r}')
            await row.click(); await am.wait_for_timeout(500)
            check(await am.locator('.dy-card').count() == 1, 'opening it shows the summary card')
            head = await am.inner_text('.dy-card .dy-top')
            check('Good morning' in head, f'card head {head!r}')
            secs = await am.eval_on_selector_all('.dy-card .dy-h', 'els => els.map(e => e.innerText.replace(/\\s+/g, " ").trim())')
            check(len(secs) == 6 and secs[0].startswith('Overdue'), f'six lines {secs}')
            counts = await am.evaluate("Daily.sections().map(s => [s.k, s.sched ? s.sched.length : s.tasks.length])")
            print('counts', counts)
            await am.screenshot(path=os.path.join(OUT, 'cm2_daily.png'))
            first = [k for k, c in counts if c][:1]
            if first:
                rows = await am.locator('.dy-card .dy-sec.open .dy-row').count()
                check(rows >= 1, f'the first line with tasks is open ({rows} rows)')
            ov = dict(counts).get('overdue', 0)
            if ov:
                if not await am.evaluate("!!document.querySelector('.dy-sec.open [data-dy-all=\"overdue\"]')"):
                    await am.click('.dy-card [data-dy-sec="overdue"]'); await am.wait_for_timeout(200)
                await am.click('.dy-card [data-dy-all="overdue"]'); await am.wait_for_timeout(500)
                check(await am.evaluate("ui.view") == 'mytasks' and await am.evaluate("Work.f().due") == 'late' and await am.locator('.dy-card').count() == 0, 'See them in My Tasks opens My Tasks filtered to Overdue')
            # the profile switch
            await am.evaluate("go('profile')"); await am.wait_for_timeout(600)
            check('Morning round-up' in await am.inner_text('#content') if await am.query_selector('#content') else False, 'My profile has the Morning round-up switch')
            pr, prerr = ali, alerr
            await pr.evaluate("closeDetail(); go('profile')"); await pr.wait_for_timeout(600)
            check(not await pr.query_selector('[data-action="daily-try"]'), 'not for Production')
            check(not aerr and not alerr and not aderr, f'no page errors {aerr} {alerr} {aderr}')
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
