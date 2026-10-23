"""Finance → Expenses → Download report: Admin / Finance Admin / Finance Viewer pick 1–12 months; the PDF
lists subscriptions, reimbursements and extra expenses with each invoice's file name (or Missing); with
"Include invoices and receipts" a .zip holds the PDF plus Attachments/<YYYY-MM>/ files named as in the report."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json, zipfile
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18231; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
OUT = tempfile.mkdtemp()
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.9-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    snap = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/snapshot', headers={'X-Dev-Email': ADMIN})).read())['data']
    fa = next(u for u in snap['users'] if u.get('role') == 'finance_admin')['email']
    fv = next(u for u in snap['users'] if u.get('role') == 'finance_viewer')['email']
    am = next(u for u in snap['users'] if u.get('role') == 'am')['email']
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def login(email):
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE, accept_downloads=True)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(5, 5); await pg.wait_for_timeout(3000)
            await pg.evaluate("document.querySelectorAll('.an-scrim,.ec-remind').forEach(x=>x.remove())")
            return ctx, pg, errs
        ctx, pg, errs = await login(fa); E = pg.evaluate
        await E("go('fin-expenses')"); await pg.wait_for_timeout(400)
        await pg.click('[data-fin-rep]'); await pg.wait_for_timeout(200)
        check(await pg.is_visible('.fr-pop'), 'Download report opens the month picker')
        now = time.strftime('%Y-%m')
        check(await E("[...document.querySelectorAll('.fr-m.on')].map(x=>x.dataset.finRepm).join()") == now, 'this month is picked by default')
        check(await E("document.querySelectorAll('.fr-m:disabled').length") == 12 - int(now[5:]), 'future months cannot be picked')
        await pg.screenshot(path=os.path.join(OUT, 'pop.png'), clip={'x': 900, 'y': 0, 'width': 540, 'height': 560})
        # PDF only
        await pg.click('[data-fin-repf]'); await pg.wait_for_timeout(150)
        check('Download PDF' in await pg.inner_text('.fr-go'), 'unticked: Download PDF')
        async with pg.expect_download(timeout=30000) as d: await pg.click('.fr-go')
        dl = await d.value; p1 = os.path.join(OUT, dl.suggested_filename); await dl.save_as(p1)
        check(dl.suggested_filename.endswith('.pdf') and open(p1, 'rb').read(5) == b'%PDF-', f'a PDF downloads ({dl.suggested_filename})')
        # several months, with files
        await pg.wait_for_timeout(500); await pg.click('[data-fin-rep]'); await pg.wait_for_timeout(200)
        await pg.click('[data-fin-repf]'); await pg.wait_for_timeout(150)
        prev = [time.strftime('%Y-%m', time.localtime(time.time() - k * 30 * 86400)) for k in (1, 2, 3)]
        for m in prev:
            if int(m[:4]) < int(now[:4]): await pg.click('[data-fin-repy="-1"]'); await pg.wait_for_timeout(100)
            el = await pg.query_selector(f'[data-fin-repm="{m}"]')
            if el: await el.click(); await pg.wait_for_timeout(100)
        check('4 months' in await pg.inner_text('.fr-sel'), 'four months picked: ' + await pg.inner_text('.fr-sel'))
        check('Download .zip' in await pg.inner_text('.fr-go'), 'ticked: Download .zip')
        async with pg.expect_download(timeout=60000) as d: await pg.click('.fr-go')
        dl = await d.value; pz = os.path.join(OUT, dl.suggested_filename); await dl.save_as(pz)
        names = zipfile.ZipFile(pz).namelist()
        print('zip:', names[:12], len(names))
        check(dl.suggested_filename.endswith('.zip') and any(n.endswith('.pdf') and '/' not in n for n in names), 'the .zip has the report PDF at the top')
        att = [n for n in names if n.startswith('Attachments/')]
        check(len(att) > 0 and all(n.count('/') == 2 and n.split('/')[1][:4].isdigit() for n in att), 'attachments sit in Attachments/<YYYY-MM>/')
        check(all(n.split('/')[2][:4] in ('SUB-', 'REI-', 'EXT-') for n in att), 'files are named SUB-/REI-/EXT-nn_…')
        zipfile.ZipFile(pz).extract([n for n in names if '/' not in n][0], OUT)
        check(not errs, 'no page errors: ' + '; '.join(errs[:3]))
        await ctx.close()
        # Viewer sees it too; AM has no Finance pages
        ctx, pg, errs = await login(fv); await pg.evaluate("go('fin-expenses')"); await pg.wait_for_timeout(400)
        check(await pg.is_visible('[data-fin-rep]'), 'Finance Viewer has Download report'); await ctx.close()
        ctx, pg, errs = await login(ADMIN); await pg.evaluate("go('fin-expenses')"); await pg.wait_for_timeout(400)
        check(await pg.is_visible('[data-fin-rep]'), 'Admin has Download report'); await ctx.close()
        ctx, pg, errs = await login(am); await pg.evaluate("go('fin-expenses')"); await pg.wait_for_timeout(400)
        check(not await pg.is_visible('[data-fin-rep]'), 'Account Manager does not'); await ctx.close()
        await b.close()
    srv.terminate()
    print('OUT', OUT)
    print('\n' + ('ALL PASS' if not fails else f'{len(fails)} FAILED'))
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
