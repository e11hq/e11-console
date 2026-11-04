"""Part B step 2: the app's own Content plans and Client Assets (web/appme-plans.js, E11AppMe) — exactly the models the
page builds today (Plans.native list / plan / post / search / waiting; NativeAssets modelFor), from the person's own
data (/api/snapshot), for Social Executives, the Social Manager, the CD, the owner, an Account Manager and the Office
Admin. Then after changes (a post marked Ask for changes by the Social Manager, a folder added) with a fresh snapshot."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT = 18335; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
PEOPLE = ['aishwarya@e11-digital.com', 'maria@e11-digital.com', 'amelia@e11-digital.com', 'carine@e11-digital.com', ADMIN, 'areej@e11-digital.com', 'arsal@e11-digital.com']

# both models worked out in the page, at the same moment, as JSON (what the app gets)
COMPARE = """(async () => {
  const src = await (await fetch('/appme-plans.js', { cache: 'no-store' })).text(); (0, eval)(src);
  const snap = await (await fetch('/api/snapshot', { cache: 'no-store' })).json();
  const data = snap.data, me = currentUserId, now = Date.now(), A = E11AppMe;
  const J = (f) => { try { const v = f(); return JSON.stringify(v === undefined ? null : v); } catch (e) { return JSON.stringify({ threw: String(e && e.message || e) }); } };
  const out = [];
  const pair = (what, page, mine) => out.push([what, J(page), J(mine)]);
  const month = Plans.native.list('').month;
  const months = [month, Plans.native.shift(month, -1), Plans.native.shift(month, 1), Plans.native.shift(month, 6)];
  months.forEach((m) => pair('list ' + m, () => Plans.native.list(m), () => A.plansList(E11Rules, data, me, now, m)));
  pair('list (no month)', () => Plans.native.list(''), () => A.plansList(E11Rules, data, me, now, ''));
  const pids = new Set((db.projects || []).map((p) => p.id));
  (db.plans || []).forEach((pl) => pids.add(pl.projectId));
  const pms = new Set(months); (db.plans || []).forEach((pl) => pms.add(pl.month));
  pids.forEach((pid) => pms.forEach((m) => pair(`plan ${pid} ${m}`, () => Plans.native.plan(pid, m), () => A.plan(E11Rules, data, me, now, pid, m))));
  (db.plans || []).forEach((pl) => (pl.posts || []).forEach((x) => pair(`post ${pl.id} ${x.id}`, () => Plans.native.post(pl.id, x.id), () => A.plansPost(E11Rules, data, me, now, pl.id, x.id))));
  ['korea', 'post', 'a', 'week offer', 'zzz', ''].forEach((q) => [month, ''].forEach((cur) => pair(`search "${q}" ${cur}`, () => Plans.native.search(q, cur), () => A.plansSearch(E11Rules, data, me, now, q, cur))));
  pair('waiting', () => Plans.waiting(), () => A.plansWaiting(E11Rules, data, me, now));
  pair('assets (all)', () => NativeAssets.modelFor(null), () => A.assets(E11Rules, data, me, now, null));
  (db.clients || []).forEach((c) => pair('assets ' + c.id, () => NativeAssets.modelFor(c.id), () => A.assets(E11Rules, data, me, now, c.id)));
  ((snap.data && snap.data.clients) || []).forEach((c) => { if (!(db.clients || []).some((x) => x.id === c.id)) pair('assets ' + c.id, () => NativeAssets.modelFor(c.id), () => A.assets(E11Rules, data, me, now, c.id)); });
  pair('assets (gone)', () => NativeAssets.modelFor('cl-nope'), () => A.assets(E11Rules, data, me, now, 'cl-nope'));
  return { month, rows: out };
})()"""

def first_diff(a, b, path=''):
    if type(a) != type(b): return f'{path}: {json.dumps(a)[:200]} != {json.dumps(b)[:200]}'
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b: return f'{path}.{k}: missing on {"page" if k not in a else "app"} ({json.dumps(a.get(k, b.get(k)))[:200]})'
            d = first_diff(a[k], b[k], f'{path}.{k}')
            if d: return d
        return None
    if isinstance(a, list):
        if len(a) != len(b): return f'{path}: length {len(a)} != {len(b)}'
        for i, (x, y) in enumerate(zip(a, b)):
            d = first_diff(x, y, f'{path}[{i}]')
            if d: return d
        return None
    return None if a == b else f'{path}: {json.dumps(a)[:200]} != {json.dumps(b)[:200]}'

async def main():
    subprocess.run(['fuser', '-k', f'{PORT}/tcp'], stderr=subprocess.DEVNULL)
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': ROOT + '/web', 'APP_VERSION': '1.6.1-test.1'}
    srv = subprocess.Popen(['node', ROOT + '/server/src/index.js'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ok = []
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE + '/api/health'); break
            except Exception: time.sleep(0.1)
        H = {'X-Dev-Email': ADMIN}
        urllib.request.urlopen(urllib.request.Request(BASE + '/api/me', headers=H))
        urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample/reset', method='POST', data=b'{}', headers={**H, 'Content-Type': 'application/json'})).read()
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            async def open_as(who):
                # (Dubai's clock, as the iPhone's: the page's days and times are the device's own)
                ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, base_url=BASE, timezone_id='Asia/Dubai')
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': who, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(4500)
                return ctx, pg, errs
            async def compare(who, tag):
                ctx, pg, errs = await open_as(who)
                r = await pg.evaluate(COMPARE)
                bad = []
                n_data = 0
                for what, page, mine in r['rows']:
                    a, m = json.loads(page), json.loads(mine)
                    if a is not None: n_data += 1
                    if a != m: bad.append(f'{what}: {first_diff(a, m)}')
                check(not bad, f'{tag} {who}: {len(r["rows"])} models the same ({n_data} with something in them, month {r["month"]})', '\n   ' + '\n   '.join(bad[:12]) + (f'\n   … {len(bad) - 12} more' if len(bad) > 12 else ''))
                check(not errs, f'{tag} {who}: no page errors', errs)
                await ctx.close()
                return r
            for who in PEOPLE: await compare(who, 'before')

            # changes, made the page's own way (they reach the server): the Social Manager asks for changes on a post of
            # a skeleton waiting for her; the Office Admin adds a folder inside a client's Files; the owner a top folder
            ctx, pg, errs = await open_as('amelia@e11-digital.com')
            done = await pg.evaluate("""(() => {
              const pl = (db.plans || []).find((p) => p.status === 'review' && (p.posts || []).length && !Plans.native.act({ ev: 'x', plan: p.id }).startsWith('Only'));
              if (!pl) return 'no skeleton waiting for the Social Manager';
              const x = pl.posts.find((y) => !y.check || y.check.state !== 'changes') || pl.posts[0];
              const err = Plans.native.act({ ev: 'plReview', plan: pl.id, post: x.id, state: 'changes', note: 'A test note' });
              return err || ('ok ' + pl.id + ' ' + x.id);
            })()""")
            check(done.startswith('ok'), f'the Social Manager marks a post Ask for changes ({done})')
            await pg.wait_for_timeout(2500); await ctx.close()
            ctx, pg, errs = await open_as('arsal@e11-digital.com')
            done = await pg.evaluate("""(() => {
              const c = (db.clients || []).find((c) => c.folders.some((f) => !f.parentId && f.name === 'Files'));
              if (!c) return 'no client with Files';
              const files = c.folders.find((f) => !f.parentId && f.name === 'Files');
              const f = newFolder(c, 'Test job folder', false, files); persist(0);
              return 'ok ' + c.id + ' ' + f.id;
            })()""")
            check(done.startswith('ok'), f'the Office Admin adds a folder inside Files ({done})')
            await pg.wait_for_timeout(2500); await ctx.close()
            ctx, pg, errs = await open_as(ADMIN)
            done = await pg.evaluate("""(() => {
              const c = (db.clients || [])[0]; if (!c) return 'no client';
              const f = newFolder(c, 'Owner folder', false, null); persist(0);
              const pl = (db.plans || []).find((p) => p.status === 'draft'); if (pl) { pl.status = 'approved'; pl.approval = { by: currentUserId, at: nowISO(), round: 1 }; persist(0); }
              return 'ok ' + c.id + ' ' + f.id + ' ' + (pl ? pl.id : '');
            })()""")
            check(done.startswith('ok'), f'the owner adds a top folder and approves a draft ({done})')
            await pg.wait_for_timeout(2500); await ctx.close()
            for who in PEOPLE:
                r = await compare(who, 'after ')
                if who in (ADMIN, 'amelia@e11-digital.com', 'carine@e11-digital.com'):
                    blob = ''.join(m for _, _, m in r['rows'])
                    check('A test note' in blob and 'Test job folder' in blob and 'Owner folder' in blob, f'after  {who}: the changes are in the app\'s models (the note, both new folders)')
            await b.close()
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
