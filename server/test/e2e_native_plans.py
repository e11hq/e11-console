"""Content plans, the iPhone app's own (shell 35): the page hands the app each screen (Plans.native — list, plan, post,
the website's own rules) and does the SM's / CD's answers the website's way (act: a post marked, approve, send back)."""
import asyncio, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18301; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.5.4-test.1'}
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
        await pg.goto('/'); await pg.wait_for_timeout(3500)
        E = pg.evaluate
        mo = await E("Plans.native.list('').month")
        await E(f"""db.plans = db.plans || []; db.plans.push({{ id: 'pl-t', projectId: 'p-korea', month: '{mo}', status: 'review', round: 1,
          review: {{ to: 'both', by: 'someone', at: nowISO(), round: 1 }}, createdBy: 'someone', log: [],
          posts: [{{ id: 'pp1', day: '{mo}-05', title: 'Test post', format: 'reel', channels: [], refs: [{{ id: 'r1', url: 'https://example.com', label: 'A link' }}], desc: 'Hello', copyAr: 'مرحبا' }}] }})""")
        L = await E(f"Plans.native.list('{mo}')")
        check(L['rows'] and L['label'] and 'foot' in L, f"the list: the month, a row per client {L['label']} {len(L['rows'])}")
        withp = [r for r in L['rows'] if r['st']['k'] != 'none']
        check(withp, f"some clients have a skeleton {[ (r['name'], r['st']['t']) for r in withp]}")
        P = await E(f"Plans.native.plan('{withp[0]['pid']}', '{L['month']}')")
        check(P and P['id'] and P['banner'] and isinstance(P['days'], list) and P['approve'] is None, f"a skeleton: banner, days; no approve for an Admin {P and P['st']}")
        x = P['days'][0]['posts'][0] if P['days'] else None
        X = await E(f"Plans.native.post('{P['id']}', '{x['id']}')") if x else None
        check(X and X['title'] and 'refs' in X and X['review'] is False, f"a post: all of it, read only for an Admin {X and X['title']}")
        r = await E(f"Plans.native.act({{ ev: 'plApprove', plan: '{P['id']}' }})")
        check(isinstance(r, str) and r, f"an Admin can't approve: {r}")
        L2 = await E(f"Plans.native.list(Plans.native.shift('{L['month']}', 1))")
        check(L2['label'] != L['label'], f"another month {L2['label']}")
        S = await E(f"Plans.native.search('test post', '{mo}')")
        check(S and S[0]['month'] == mo and any(i.get('post') == 'pp1' for i in S[0]['items']), f"🔍 finds a post by its title, its month first {S and [(g['month'], len(g['items'])) for g in S]}")
        S2 = await E("Plans.native.search('korea', '')")
        check(S2 and all(any(not i.get('post') for i in g['items']) for g in S2[:1]), f"🔍 finds a client by its name {S2 and len(S2)}")
        check(await E("Plans.native.search('', '')") == [], 'nothing typed: nothing found')
        check(not errs, f"no page errors {errs}")
        await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'FAILS {len(fails)} {fails}')
asyncio.run(main())
