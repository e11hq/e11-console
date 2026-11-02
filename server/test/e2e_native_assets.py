"""Client Assets, the iPhone app's own (shell 32): the page hands the app each screen's contents (who may do what by the
website's own rules) and does each change the website's way — window.__e11Assets answers through NativeMac.call('assets')."""
import asyncio, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18297; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
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
        async def as_user(email):
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(3500)
            # (the app's side: what the page sends it)
            await pg.evaluate("window.__got = []; NativeMac.call = (k, a) => { window.__got.push([k, a]); return Promise.resolve({}); }")
            return ctx, pg, errs
        ctx, pg, errs = await as_user(ADMIN)
        E = pg.evaluate
        async def ask(ev):
            await E("window.__got = []")
            await E(f"window.__e11Assets({json.dumps({**ev, 'rid': 'r1'})})")
            await pg.wait_for_timeout(150)
            got = await E("window.__got.filter(x => x[0] === 'assets' && x[1].rid === 'r1').map(x => x[1])")
            return got[-1] if got else None
        r = await ask({'ev': 'addClient', 'name': 'Northwind Motors'})
        check(r and r['ok'], f"a client to work with {r}")
        r = await ask({'ev': 'want'})
        check(r and r['ok'] and r['model']['kind'] == 'all' and len(r['model']['clients']) > 0, f"all: the clients {r and r['model'].get('sub')}")
        cid = next(c['id'] for c in r['model']['clients'] if c['name'] == 'Northwind Motors')
        r = await ask({'ev': 'want', 'client': cid})
        m = r['model']
        check(m['kind'] == 'client' and len(m['folders']) >= 4 and all('dir' in f and 'canUpload' in f for f in m['folders']), f"a client: its folders with who may do what {[f['name'] for f in m['folders']][:6]}")
        logos = next(f for f in m['folders'] if f['name'] == 'Logos')
        files_top = next(f for f in m['folders'] if f['name'] == 'Files')
        check(logos['canUpload'] and not files_top['canUpload'] and files_top['canSub'], 'Logos takes files; Files only folders')
        # new folder inside Files, rename, then a file uploaded into it, deleted, the folder deleted
        r = await ask({'ev': 'newFolder', 'client': cid, 'parent': files_top['id'], 'name': 'Summer shoot'})
        check(r['ok'] and r.get('id') and any(f['name'] == 'Summer shoot' and f['parent'] == files_top['id'] for f in r['model']['folders']), f"a folder made inside Files {r.get('error')}")
        fid = r['id']
        r = await ask({'ev': 'newFolder', 'client': cid, 'parent': files_top['id'], 'name': 'summer shoot'})
        check(not r['ok'] and 'already' in (r['error'] or ''), f"the same name again: refused ({r['error']})")
        r = await ask({'ev': 'renameFolder', 'client': cid, 'folder': fid, 'name': 'Summer shoot 2026'})
        check(r['ok'] and any(f['name'] == 'Summer shoot 2026' for f in r['model']['folders']), 'renamed')
        r = await ask({'ev': 'uploaded', 'client': cid, 'folder': fid, 'files': [{'name': 'hero.jpg', 'path': 'Clients/x/hero.jpg', 'size': 2048}]})
        f1 = [f for f in r['model']['files'] if f['folder'] == fid]
        check(r['ok'] and len(f1) == 1 and f1[0]['name'] == 'hero.jpg' and f1[0]['canDel'] and f1[0]['url'] and f1[0]['where'].endswith('Summer shoot 2026'), f"an uploaded file filed in the folder {f1}")
        check(f1 and f1[0]['id'] in r['model']['recent'], 'and it is under Recently added')
        r = await ask({'ev': 'uploaded', 'client': cid, 'folder': files_top['id'], 'files': [{'name': 'x.jpg', 'path': 'p', 'size': 1}]})
        check(not r['ok'] and 'Files holds folders' in (r['error'] or ''), 'not into Files itself')
        r = await ask({'ev': 'deleteFile', 'client': cid, 'folder': fid, 'file': f1[0]['id']})
        check(r['ok'] and not [f for f in r['model']['files'] if f['folder'] == fid], 'the file deleted')
        trash = await E("db.trash.filter(x => x.type === 'cafile').length")
        check(trash >= 1, 'into the Trash')
        r = await ask({'ev': 'deleteFolder', 'client': cid, 'folder': fid})
        check(r['ok'] and not any(f['id'] == fid for f in r['model']['folders']), 'the folder deleted')
        # clients: add, rename, delete
        r = await ask({'ev': 'addClient', 'name': 'Zephyr Labs'})
        check(r['ok'] and r.get('id') and any(c['name'] == 'Zephyr Labs' for c in r['model']['clients']), f"a client added {r.get('error')}")
        nid = r['id']
        r = await ask({'ev': 'want', 'client': nid})
        check([f['name'] for f in r['model']['folders']] == ['Logos', 'Brand Guidelines', 'Fonts', 'Files'], 'with its four folders')
        r = await ask({'ev': 'addClient', 'name': 'zephyr labs'})
        check(not r['ok'], 'the same client again: refused')
        r = await ask({'ev': 'renameClient', 'client': nid, 'name': 'Zephyr Studio'})
        check(r['ok'] and r['model']['name'] == 'Zephyr Studio', 'renamed')
        r = await ask({'ev': 'deleteClient', 'client': nid})
        check(r['ok'] and r.get('gone') and not any(c['id'] == nid for c in r['model']['clients']), 'deleted')
        check(not errs, f'no page errors {errs}')
        # a freelancer only looks
        FL = await E("(db.users.find(u => u.role === 'freelancer' && u.active !== false) || {}).email")
        if FL:
            ctx2, fl, errs2 = await as_user(FL)
            pg = fl; E = fl.evaluate
            r = await ask({'ev': 'want'})
            if r and r['ok'] and r['model']['clients']:
                c2 = r['model']['clients'][0]['id']
                r = await ask({'ev': 'want', 'client': c2})
                check(r['ok'] and not any(f['canUpload'] or f['canDel'] for f in r['model']['folders']), 'a freelancer: no upload or delete')
                r = await ask({'ev': 'newFolder', 'client': c2, 'name': 'Nope'})
                check(not r['ok'], 'and no new folders')
            check(not r or not r['model'].get('canAdd'), 'and no Add client')
    finally:
        srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
