"""Expense claims: the daily reminder pop-up (20th–27th from 11:30, three answers), the claim form (titles with
dates, items with AED, receipts, signature, live total), submitting notifies Finance, the PDF (sheet + receipts),
Finance Viewers look, Finance Admins mark HR approved / paid (a reimbursement record appears), from the 28th
claims are for the next month, and claims are computer-only."""
import asyncio, datetime, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18244; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
now = datetime.datetime.now()
# the month the server takes claims for (from the 28th it's the next one)
first = now.replace(day=1)
M = (first + datetime.timedelta(days=32)).replace(day=1) if now.day >= 28 else first
def notifs(email):
    r = urllib.request.urlopen(urllib.request.Request(BASE + '/api/snapshot', headers={'X-Dev-Email': email}))
    return json.loads(r.read())['data']['notifications']
def at(day, h, mi=0): return M.replace(day=day, hour=h, minute=mi, second=0, microsecond=0)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.9-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            async def login(email, when=None, vp=(1440, 1000), remind=True):
                ctx = await b.new_context(viewport={'width': vp[0], 'height': vp[1]}, base_url=BASE, accept_downloads=True, has_touch=vp[0] < 500)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
                if remind: await ctx.add_init_script("try{localStorage.setItem('e11-claim-remind','1')}catch(e){}")
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                if when: await pg.clock.set_fixed_time(when)
                await pg.goto('/'); await pg.wait_for_timeout(4000)
                return ctx, pg, errs
            ctx, pg, errs = await login(ADMIN, remind=False)
            maab = await pg.evaluate("userById('u-maab').email"); aish = await pg.evaluate("userById('u-aish').email")
            await ctx.close()

            # ---- reminder: before 11:30 nothing, after 11:30 the pop-up; "I don't have claims" stops it
            ctx, pg, errs = await login(maab, at(22, 11, 10)); E = pg.evaluate
            check(await pg.locator('.ec-remind').count() == 0, 'no reminder before 11:30')
            await pg.clock.set_fixed_time(at(22, 11, 40)); await E("Claims.tick()"); await pg.wait_for_timeout(300)
            check(await pg.locator('.ec-remind').count() == 1, 'reminder pop-up after 11:30 on the 22nd')
            check(await pg.locator('.ec-remind [data-r="submit"]').count() == 1 and await pg.locator('.ec-remind [data-r="offline"]').count() == 1 and await pg.locator('.ec-remind [data-r="none"]').count() == 1, 'Submit now / Submitted offline / I don’t have claims')
            await pg.click('.ec-remind [data-r="none"]'); await pg.wait_for_timeout(500)
            check(await E(f"Claims.byId('cl-u-maab-{M:%Y-%m}').state") == 'none', 'I don’t have claims is recorded')
            await pg.clock.set_fixed_time(at(23, 12, 0)); await E("Claims.tick()"); await pg.wait_for_timeout(300)
            check(await pg.locator('.ec-remind').count() == 0, 'no more reminders that month')
            check(not errs, f'no page errors {errs}')
            await ctx.close()

            # ---- outside 20th–27th: nothing
            ctx, pg, errs = await login(aish, at(19, 12, 0)); E = pg.evaluate
            check(await pg.locator('.ec-remind').count() == 0, 'no reminder on the 19th')
            # the new-claim button opens a claim, never the New client pop-up (they once shared a button name)
            await E("go('claims')"); await pg.wait_for_timeout(400)
            await pg.locator('[data-cl="new"]').first.click(); await pg.wait_for_timeout(500)
            check(await pg.locator('.cd-dlg').count() == 0 and await E("ui.view") == 'claim', 'New claim opens the claim form, not New client')
            await ctx.close()

            # ---- Submit now → the form
            ctx, pg, errs = await login(aish, at(24, 12, 0)); E = pg.evaluate
            check(await pg.locator('.ec-remind').count() == 1, 'reminder shows when the app opens after 11:30')
            await pg.click('.ec-remind [data-r="submit"]'); await pg.wait_for_timeout(500)
            check(await E("ui.view") == 'claim' and await pg.locator('.ec-editor').count() == 1, 'Submit now opens the claim form')
            await pg.fill('input[data-k="title"]', 'Address Shoot')
            await pg.fill('input[data-k="desc"]', 'Salik'); await pg.fill('input[data-k="amount"]', '24')
            await pg.click('[data-cl="add-item"]'); await pg.wait_for_timeout(150)
            await pg.locator('input[data-k="desc"]').nth(1).fill('Petrol'); await pg.locator('input[data-k="amount"]').nth(1).fill('180.50')
            async with pg.expect_file_chooser() as fc:
                await pg.locator('[data-cl="receipt"]').nth(1).click()
            await (await fc.value).set_files(os.path.join(ROOT, 'server/src/sample-files/receipt-reimbursement.pdf')); await pg.wait_for_timeout(1500)
            check(await pg.locator('.ec-rc').count() == 1, 'receipt attached to the Petrol item')
            await pg.click('[data-cl="add-group"]'); await pg.wait_for_timeout(150)
            await pg.locator('input[data-k="title"]').nth(1).fill('Client meeting')
            await pg.locator('input[data-k="desc"]').nth(2).fill('Taxi'); await pg.locator('input[data-k="amount"]').nth(2).fill('68')
            check((await pg.locator('#ec-total').inner_text()).strip() == '272.50', 'total adds up live')
            # submitting without a signature is refused
            await pg.click('[data-cl="submit"]'); await pg.wait_for_timeout(300)
            check(await E("ui.view") == 'claim', 'needs a signature first')
            await pg.click('[data-cl="sig-draw"]'); await pg.wait_for_timeout(200)
            cv = pg.locator('.ec-draw canvas'); bb = await cv.bounding_box()
            await pg.mouse.move(bb['x'] + 40, bb['y'] + 100); await pg.mouse.down()
            for k in range(25): await pg.mouse.move(bb['x'] + 40 + k * 16, bb['y'] + 100 + ((-1) ** k) * 30)
            await pg.mouse.up(); await pg.click('.ec-draw [data-x="use"]'); await pg.wait_for_timeout(1500)
            check(await E("!!me().signature"), 'drawn signature is saved for next time')
            await pg.click('[data-cl="submit"]'); await pg.wait_for_timeout(800)
            cid = f'cl-u-aish-{M:%Y-%m}'
            c = await E(f"(()=>{{const c=Claims.byId('{cid}'); return c && [c.state, c.total, c.groups.length]}})()")
            check(c == ['submitted', 272.5, 2], f'claim submitted {c}')
            check(await E("ui.view") == 'claims', 'back on My reimbursements')
            # the new-claim button opens a claim, never the New client pop-up (they once shared a button name)
            if await pg.locator('[data-cl="new"]').count():
                await pg.locator('[data-cl="new"]').first.click(); await pg.wait_for_timeout(500)
                check(await pg.locator('.cd-dlg').count() == 0, 'Add reimbursement doesn’t open New client')
                if await pg.locator('[data-cl="sig-saved"] img').count():
                    check(await E("document.querySelector('[data-cl=\"sig-saved\"] img').naturalWidth > 0"), 'the saved signature shows')
                await E("go('claims')"); await pg.wait_for_timeout(400)
            await pg.wait_for_timeout(800)
            fa = [n for n in notifs('rania.finance@e11-digital.com') if n.get('claimId') == cid]; fv = [n for n in notifs('omar.accounts@e11-digital.com') if n.get('claimId') == cid]
            check(len(fa) == 1 and len(fv) == 1, f'Finance Admin and Viewer are notified ({len(fa)}, {len(fv)})')
            async with pg.expect_download() as dl:
                await pg.locator(f'[data-cl-row="{cid}"] [data-cl="pdf"]').click()
            p = os.path.join(tempfile.gettempdir(), 'claim_test.pdf'); await (await dl.value).save_as(p)
            pages = int(subprocess.check_output(['pdfinfo', p]).decode().split('Pages:')[1].split()[0])
            check(pages >= 2, f'PDF has the sheet and the receipt ({pages} pages)')
            check(not errs, f'no page errors {errs}')
            # from the 28th, claims are for the next month
            await pg.clock.set_fixed_time(at(28, 10, 0)); await E("go('claims')"); await pg.wait_for_timeout(300)
            nxt = (M + datetime.timedelta(days=32)).replace(day=1)
            check(await E("Claims.claimMonth()") == f'{nxt:%Y-%m}' and nxt.strftime('%B') in await pg.locator('.ec-top').inner_text(), 'from the 28th new claims are for the next month')
            await ctx.close()

            # ---- Finance Viewer looks only
            ctx, pg, errs = await login('omar.accounts@e11-digital.com', at(24, 12, 30)); E = pg.evaluate
            await E("go('fin-reimb')"); await pg.wait_for_timeout(500)
            check(await pg.locator(f'[data-claim="{cid}"]').count() == 1, 'Finance Viewer sees the claim')
            check(await pg.locator('[data-cl="approve"], [data-cl="paid"]').count() == 0, 'but can’t mark it')
            await ctx.close()

            # ---- Finance Admin: opens from the notification (highlighted), marks HR approved and paid
            ctx, pg, errs = await login('rania.finance@e11-digital.com', at(24, 12, 30)); E = pg.evaluate
            n = await E(f"db.notifications.find(n=>n.to===currentUserId&&n.claimId==='{cid}').id")
            await E(f"openNotif('{n}')"); await pg.wait_for_timeout(400)
            check(await E("ui.view") == 'fin-reimb' and await E(f"!!document.querySelector('[data-claim=\"{cid}\"].flash')"), 'notification opens Reimbursements with that claim highlighted')
            check(await pg.locator(f'[data-claim="{cid}"] .ec-new').count() == 1, 'submitted mark on the claim')
            await pg.click(f'[data-claim="{cid}"] [data-cl="approve"]'); await pg.wait_for_timeout(400)
            check(await E(f"Claims.byId('{cid}').state") == 'approved', 'marked HR approved')
            await pg.click(f'[data-claim="{cid}"] [data-cl="paid"]'); await pg.wait_for_timeout(300)
            await pg.click('.dialog button[type="submit"]'); await pg.wait_for_timeout(600)
            st = await E(f"(()=>{{const c=Claims.byId('{cid}'); const r=db.finance.find(x=>x.claimId===c.id); return [c.state, !!c.paidOn, r && r.amount]}})()")
            check(st == ['paid', True, 272.5], f'marked paid and recorded as a reimbursement {st}')
            await pg.wait_for_timeout(800)
            told = sorted(n['kind'] for n in notifs(aish) if n.get('claimId') == cid)
            check(told == ['claim-ok', 'claim-paid'], f'claimant told at each step {told}')
            check(not errs, f'no page errors {errs}')
            await ctx.close()

            # ---- computers only
            ctx, pg, errs = await login(aish, at(24, 12, 0), vp=(390, 844)); E = pg.evaluate
            check(await pg.locator('.ec-remind').count() == 0, 'no pop-up on the phone')
            await E("go('claims')"); await pg.wait_for_timeout(300)
            check('on the computer' in await pg.locator('#content').inner_text(), 'phone shows the use-a-computer note')
            await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
