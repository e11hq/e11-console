"""The Me tab, the iPhone app's own (shell 33): the page hands the app what's on Me and its pages (the website's own
rules) and does each change the website's way — window.__e11Me; its questions (dialog, choiceDialog, formDialog) go to
the app as iPhone's own (meAsk) while the app's Me is showing."""
import asyncio, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18298; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
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
        exe = [os.path.join('/opt/pw-browsers', d, 'chrome-linux/chrome') for d in sorted(os.listdir('/opt/pw-browsers')) if d.startswith('chromium-')] if os.path.isdir('/opt/pw-browsers') else []
        b = await (pw.chromium.launch(executable_path=exe[-1]) if exe else pw.chromium.launch())
        ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
        await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
        pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto('/'); await pg.wait_for_timeout(3500)
        E = pg.evaluate
        # (the app's side: what the page sends it, and its answers to the page's questions)
        await E("""window.__got = []; window.__answers = [];
          NativeMac.call = (k, a) => { window.__got.push([k, a]); if (k === 'meAsk') return Promise.resolve(window.__answers.shift() || { ok: false }); return Promise.resolve({}); }""")
        m = await E("NativeMe.peek()")
        check(m['card']['name'] and m['card']['email'] == ADMIN and m['card']['role'], f"Me: your card {m['card']}")
        ks = [w['k'] for w in m['work']]
        check('clients' in ks and 'team' in ks and 'trash' in ks, f"Work: the website Me's rows for an Admin {ks}")
        check(m['theme'] in ('auto', 'light', 'dark') and m['times'].startswith('light from'), f"Appearance: the mode and today's times {m['theme']} {m['times']}")
        check(m['team'] is None, 'no team list until its page is open')
        await E("window.__e11Me({ ev: 'team', on: true })")
        t = (await E("NativeMe.peek()"))['team']
        names = [g['name'] for g in t['groups']]
        check(t['admin'] and t['active'] > 3 and names and names[0] == 'Super Admins' and len(t['guide']) >= 6, f"Team: by role, the role guide {names}")
        everyone = [p for g in t['groups'] for p in g['people']]
        you = [p for p in everyone if p['you']]
        check(len(you) == 1 and you[0]['email'] == ADMIN, 'you are marked')
        cd = [p for p in everyone if any(x['t'] in ('Creative Director', 'Acting CD') for x in p['pills'])]
        check(len(cd) <= 1 and all(p['cd'] for p in everyone), f"the Creative Director's pill, and the CD switch for an Admin {[p['name'] for p in cd]}")
        # theme
        await E("window.__e11Me({ ev: 'theme', mode: 'light' })")
        check((await E("Theme.mode()")) == 'light', 'Appearance: Light chosen')
        await E("window.__e11Me({ ev: 'theme', mode: 'auto' })")
        check((await E("Theme.mode()")) == 'auto', 'Automatic again')
        # the page's questions, as the app's own while Me shows
        await E("NativeMe.asking = () => true")
        await E("window.__answers = [{ ok: true, values: { name: 'Nadia Test', email: 'not-an-email', role: 'production', admin: '', fin: '' } }, { ok: true, values: { name: 'Nadia Test', email: 'nadia.test@e11-digital.com', role: 'production', admin: '', fin: '' } }]")
        await E("window.__e11Me({ ev: 'addMember' })")
        await pg.wait_for_timeout(400)
        forms = await E("window.__got.filter(x => x[0] === 'meAsk').map(x => x[1])")
        check(len(forms) == 2 and forms[0]['kind'] == 'form' and [f['key'] for f in forms[0]['fields']][:2] == ['name', 'email'] and 'valid email' in forms[1]['error'], f"Add member: iPhone's own form, a problem shown on it {[(f.get('kind'), f.get('error')) for f in forms]}")
        added = await E("db.users.some(u => u.email === 'nadia.test@e11-digital.com' && u.role === 'production')")
        check(added, 'the member added, the website way')
        nid = await E("db.users.find(u => u.email === 'nadia.test@e11-digital.com').id")
        await E("window.__got = []; window.__answers = [{ ok: true }]")
        await E(f"removeMemberFlow(userById('{nid}'))")
        await pg.wait_for_timeout(300)
        q = await E("window.__got.filter(x => x[0] === 'meAsk').map(x => x[1])")
        check(q and q[0]['kind'] == 'alert' and q[0]['danger'] and 'Remove' in q[0]['title'], f"Remove: iPhone's own question {q}")
        check(await E(f"userById('{nid}').active === false"), 'removed, the website way')
        t = (await E("NativeMe.peek()"))['team']
        check(any(p['id'] == nid for p in t['past']), 'now under Past')
        await E("window.__got = []; window.__answers = [{ ok: false }]")
        r = await E("choiceDialog({ title: 'Pick', choices: [{ label: 'Cancel', value: null }, { label: 'A', value: 'a', primary: true }] })")
        q = await E("window.__got.filter(x => x[0] === 'meAsk').map(x => x[1])")
        check(r is None and q and q[0]['kind'] == 'choice' and q[0]['choices'][0]['cancel'], f"a choice as iPhone's own sheet {q}")
        await E("window.__got = []; window.__answers = [{ ok: true, index: 1 }]")
        r = await E("choiceDialog({ title: 'Pick', choices: [{ label: 'Cancel', value: null }, { label: 'A', value: 'a', primary: true }] })")
        check(r == 'a', 'its answer')
        await E("window.__got = []")
        await E("NativeMe.toast('Hello')")
        tt = await E("window.__got.filter(x => x[0] === 'me' && x[1].toast).map(x => x[1].toast.t)")
        check(tt == ['Hello'], f"a toast goes to the app {tt}")
        await E("NativeMe.asking = () => false")
        ok = await E("(async () => { setTimeout(() => { const b = document.querySelector('#overlay-root [data-r=\"1\"]'); if (b) b.click(); }, 200); return await dialog({ title: 'Plain' }); })()")
        check(ok is True, "without the app's Me: the page's own dialog as before")
        check(not errs, f'no page errors {errs}')
        await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
