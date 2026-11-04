"""Part B step 2: the app's own Overview, Claims, Expenses and Reviews (web/appme-money.js E11AppMe) — the same models as
the page's own (phone.js NativeMe overview / claimsModel / expensesModel / reviewsModel, Reviews without `focus`), from
the person's /api/snapshot data, for the Office Admin with Finance, the CD and the owner — and again after a change
(a claim approved; reviews decided: amendments with a per-file note, an approval)."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18331; BASE=f'http://127.0.0.1:{PORT}'; ADMIN='haris@e11-digital.com'
PEOPLE = ['arsal@e11-digital.com', 'carine@e11-digital.com', ADMIN]
COMPARE = """(async () => {
  if (typeof E11AppMe === 'undefined') { const src = await (await fetch('/appme-money.js', { cache: 'no-store' })).text(); (0, eval)(src); }
  const snap = await (await fetch('/api/snapshot', { cache: 'no-store' })).json();
  const now = () => Date.now();
  const page = { claims: NativeMe.claimsModel(), expenses: NativeMe.expensesModel(), overview: NativeMe.overview(), reviews: NativeMe.reviewsModel() };
  delete page.reviews.focus;
  const app = { claims: E11AppMe.claims(E11Rules, snap.data, currentUserId, now), expenses: E11AppMe.expenses(E11Rules, snap.data, currentUserId, now),
    overview: E11AppMe.overview(E11Rules, snap.data, currentUserId, now), reviews: E11AppMe.reviews(E11Rules, snap.data, currentUserId, now) };
  const out = {};
  for (const k of Object.keys(page)) out[k] = { page: JSON.stringify(page[k]), app: JSON.stringify(app[k]) };
  out.sizes = { claims: page.claims.all.length, need: page.claims.need.length, office: page.expenses.office.length, subs: page.expenses.subs.length,
    assets: page.overview.assets.length, ovClaims: (page.overview.claims || []).length, waiting: page.reviews.waiting.length, reviewed: page.reviews.reviewed.length };
  return out;
})()"""
def diff(a, b):
    i = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
    return f'\n   at {i}:\n   page: …{a[max(0,i-120):i+160]}\n   app:  …{b[max(0,i-120):i+160]}'
async def main():
    subprocess.run(['fuser','-k',f'{PORT}/tcp'],stderr=subprocess.DEVNULL)
    env={**os.environ,'DATA_DIR':tempfile.mkdtemp(),'AUTH_DEV':'1','ADMIN_EMAIL':ADMIN,'PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.6.1-test.1'}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    ok=[]
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE+'/api/health'); break
            except Exception: time.sleep(0.1)
        H={'X-Dev-Email':ADMIN}
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/me',headers=H))
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/sample/reset',method='POST',data=b'{}',headers={**H,'Content-Type':'application/json'})).read()
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            async def compare(pg, who, when, need=None):
                # (the page's change reaches the server, then the snapshot: a few tries)
                for i in range(12):
                    r = await pg.evaluate(COMPARE)
                    same = all(r[k]['page'] == r[k]['app'] for k in ('claims', 'expenses', 'overview', 'reviews'))
                    if same and (need is None or need(r['sizes'])): break
                    await pg.wait_for_timeout(500)
                for k in ('claims', 'expenses', 'overview', 'reviews'):
                    check(r[k]['page'] == r[k]['app'], f'{who} {when}: {k} the same', diff(r[k]['page'], r[k]['app']))
                if need is not None: check(need(r['sizes']), f'{who} {when}: the change shows', r['sizes'])
                return r['sizes']
            for who in PEOPLE:
                ctx=await b.new_context(viewport={'width':390,'height':844},device_scale_factor=2,is_mobile=True,has_touch=True,base_url=BASE,timezone_id='Asia/Dubai',locale='en-US')
                await ctx.add_cookies([{'name':'e11_dev_email','value':who,'url':BASE}])
                pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/')
                await pg.wait_for_function("typeof db !== 'undefined' && db && db.users && db.users.length > 0 && typeof NativeMe !== 'undefined'", timeout=30000)
                await pg.wait_for_timeout(2500)
                s = await compare(pg, who, 'at first')
                print('    ', s)
                if who.startswith('arsal'):
                    check(s['claims'] > 0 and s['office'] > 0 and s['subs'] > 0 and s['ovClaims'] > 0, f'{who}: there is something to compare', s)
                    n0 = s['need']
                    cid = await pg.evaluate("(() => { const m = Claims.claimMonth(); const c = Claims.all().find((x) => x.month === m && x.state === 'submitted'); return c ? c.id : null; })()")
                    check(bool(cid), f'{who}: a submitted claim to approve')
                    if cid:
                        await pg.evaluate(f"Claims.markApproved([{json.dumps(cid)}])")
                        await compare(pg, who, 'after approving a claim', lambda z: z['need'] == n0 - 1)
                    # (an office expense added on the page)
                    await pg.evaluate("""(() => { const d = todayStr(); db.finance.push({ id: 'e2e-ex-' + Date.now(), type: 'expense', name: 'Printer paper & ink', amount: 87.5, date: d, invoice: null, createdAt: nowISO(), createdBy: currentUserId }); persist(0); })()""")
                    o0 = s['office']
                    await compare(pg, who, 'after adding an office expense', lambda z: z['office'] == o0 + 1)
                if who.startswith('carine'):
                    check(s['waiting'] > 0 or s['reviewed'] > 0, f'{who}: there are reviews to compare', s)
                    w0, d0 = s['waiting'], s['reviewed']
                    if w0:
                        await pg.evaluate("""(() => { const { t, r } = activeReviews()[0]; const f = (r.files || [])[0]; decideReview(t, r, 'amend', '<p>Please fix the logo &amp; the <b>colours</b> &lt;soon&gt;</p>', f && (r.files || []).length > 1 ? { [f]: 'Bigger logo' } : null); })()""")
                        await compare(pg, who, 'after requesting amendments', lambda z: z['waiting'] == w0 - 1 and z['reviewed'] == d0 + 1)
                    if w0 > 1:
                        await pg.evaluate("(() => { const { t, r } = activeReviews()[0]; decideReview(t, r, 'approve'); })()")
                        await compare(pg, who, 'after approving a review', lambda z: z['waiting'] == w0 - 2 and z['reviewed'] == d0 + 2)
                check(not errs, f'{who}: no page errors', errs)
                await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
