"""The iPhone app's Home from the server (/api/home, web/rules.js) is exactly what the page used to send the app
(phone.js NativeHome before the rules moved): for every person in the sample data, the old page code's groups and
cards are compared with the server's. The page itself (now on the shared rules) loads without errors."""
import asyncio, json, os, shutil, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18291; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
OLD = os.environ.get('OLD_REF', 'HEAD')
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)

def old_web():
    """the web folder with the page as it was (OLD_REF) — the server's homeview still reads the new rules.js"""
    d = tempfile.mkdtemp()
    shutil.copytree(os.path.join(ROOT, 'web'), os.path.join(d, 'web'))
    for f in ('phone.js', 'index.html'):
        src = subprocess.run(['git', '-C', ROOT, 'show', f'{OLD}:web/{f}'], capture_output=True, text=True, check=True).stdout
        open(os.path.join(d, 'web', f), 'w').write(src)
    return os.path.join(d, 'web')

def old_cardof():
    src = subprocess.run(['git', '-C', ROOT, 'show', f'{OLD}:web/phone.js'], capture_output=True, text=True, check=True).stdout
    a = src.index('  function cardOf(t, o = {}) {'); b = src.index('  function model() {', a)
    return src[a:b]

async def main():
    web = old_web()
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': web, 'APP_VERSION': '1.2.8-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    card_src = old_cardof()
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            async def login(email, w=1440, h=900):
                ctx = await b.new_context(viewport={'width': w, 'height': h}, base_url=BASE, timezone_id='Asia/Dubai')
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3000)
                return ctx, pg, errs
            ctx, pg, errs = await login(ADMIN)
            people = await pg.evaluate("db.users.filter(u=>u.active!==false).map(u=>({email:u.email, role:u.role, id:u.id}))")
            await ctx.close()
            checked = 0
            for p in people:
                ctx, pg, errs = await login(p['email'])
                old = await pg.evaluate("""(src) => {
                  if (typeof Phone === 'undefined' || !Phone.myDayData) return null;
                  const person = () => {}, rgbOfCss = (css) => { try { return NativeSheet.colorRGB(css); } catch (e) { return null; } };
                  const cardOf = eval('(' + src.trim().replace(/^function cardOf/, 'function') + ')');
                  if (isOffice() || isFinUser()) return 'none';
                  const { overdue, due, going, done, review } = Phone.myDayData();
                  const grp = (name, tasks, o = {}) => (tasks.length || o.empty ? { name, n: tasks.length, empty: tasks.length ? '' : o.empty || '', cards: tasks.map((t) => cardOf(t, o)) } : null);
                  return { title: Work.dayTitle(), date: new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' }), me: currentUserId,
                    stats: [due.length, overdue.length, review],
                    groups: [grp('Today', due, { empty: 'Nothing due today 🎉' }), grp('In progress', going), grp('Overdue', overdue), grp('Completed today', done, { status: false })].filter(Boolean),
                    add: can('createTask'), canDelete: can('deleteTask') };
                }""", card_src)
                srvm = await pg.evaluate("fetch('/api/home').then(r=>r.json())")
                home = srvm.get('home')
                if old in (None,):
                    check(False, f"{p['email']}: the old page had no Home to compare"); await ctx.close(); continue
                if old == 'none':
                    check(home is None, f"{p['role']} {p['email']}: no Home from the server either")
                    await ctx.close(); continue
                got = {k: home.get(k) for k in ('title', 'date', 'me', 'stats', 'groups', 'add', 'canDelete')} if home else None
                if got:
                    for g in got['groups']:
                        for c in g['cards']:
                            c.pop('why', None); c.pop('canDelete', None)
                same = json.dumps(got, sort_keys=True) == json.dumps(old, sort_keys=True)
                if not same and got:
                    for k in old:
                        if json.dumps(old[k], sort_keys=True) != json.dumps(got.get(k), sort_keys=True):
                            print('   differs:', k)
                            if k == 'groups':
                                for go, gn in zip(old['groups'], got['groups']):
                                    for co, cn in zip(go['cards'], gn['cards']):
                                        for kk in co:
                                            if json.dumps(co[kk], sort_keys=True) != json.dumps(cn.get(kk), sort_keys=True): print('     card', co['id'], kk, co[kk], '≠', cn.get(kk))
                                    if len(go['cards']) != len(gn['cards']): print('     group', go['name'], len(go['cards']), '≠', len(gn['cards']))
                            else: print('     ', old[k], '≠', got.get(k))
                n = sum(len(g['cards']) for g in old['groups'])
                check(same, f"{p['role']} {p['email']}: the server's Home is the old page's ({n} cards, boxes {old['stats']})")
                check(bool(home) and isinstance(home.get('people'), dict) and p['id'] in home['people'], f"{p['email']}: the people on it come with it")
                check(not errs, f"{p['email']}: no page errors {errs[:2]}")
                checked += 1
                await ctx.close()
            check(checked >= 4, f'{checked} people compared')
            # the switch: 'home-server' off → the app is told to use the page
            await b.close()
    finally:
        srv.terminate()
    print('FAILS', len(fails), fails)
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
