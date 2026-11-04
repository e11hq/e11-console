"""File links (flinks.js): Copy link gives one short public link per file; the branded page, the file and its picture
open without signing in; a link can be turned off; the files address shows nothing else; pasting our link in the app
is the file."""
import asyncio, json, os, subprocess, tempfile, time, urllib.request, urllib.error
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18299; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def req(path, body=None, who=ADMIN, host=None, method=None):
    h = {'Content-Type': 'application/json'}
    if who: h['X-Dev-Email'] = who
    if host: h['Host'] = host
    r = urllib.request.Request(BASE + path, data=json.dumps(body).encode() if body is not None else None, headers=h, method=method or ('POST' if body is not None else 'GET'))
    try:
        with urllib.request.urlopen(r) as x: return x.status, x.read(), dict(x.headers)
    except urllib.error.HTTPError as e: return e.code, e.read(), dict(e.headers)
async def main():
    data = tempfile.mkdtemp()
    env = {**os.environ, 'DATA_DIR': data, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.5.4-test.1', 'FILES_URL': 'https://files-test.example.com', 'APPLE_TEAM_ID': 'ABCDE12345'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    req('/api/sample', {})
    try:
      async with async_playwright() as pw:
        exe = [os.path.join('/opt/pw-browsers', d, 'chrome-linux/chrome') for d in sorted(os.listdir('/opt/pw-browsers')) if d.startswith('chromium-')] if os.path.isdir('/opt/pw-browsers') else []
        b = await (pw.chromium.launch(executable_path=exe[-1]) if exe else pw.chromium.launch())
        ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
        await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
        pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto('/'); await pg.wait_for_timeout(3500)
        E = pg.evaluate
        # a real file in a client's Logos folder
        import base64
        os.makedirs(os.path.join(data, 'files', 'Clients', 'flink-test'), exist_ok=True)
        png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
        open(os.path.join(data, 'files', 'Clients', 'flink-test', 'logo.png'), 'wb').write(png)
        info = await E("""(async () => {
          const c = db.clients.find((x) => x.folders && x.folders.length) || createClient('Northwind');
          const f = c.folders.find((x) => x.name === 'Logos') || c.folders[0];
          f.files.push({ id: 'fl-1', name: 'Northwind logo.png', path: 'Clients/flink-test/logo.png', size: 70, addedAt: nowISO(), addedBy: currentUserId });
          persist(0); await Sync.push();
          return { path: 'Clients/flink-test/logo.png' };
        })()""")
        path = info['path']
        st, body, _ = req('/api/flink', {'path': path})
        r = json.loads(body) if st == 200 else {}
        check(st == 200 and r.get('ok') and r['url'].startswith('https://files-test.example.com/f/'), f"a file's link {st} {r} {info}")
        tok = r.get('token', '')
        st2, body2, _ = req('/api/flink', {'path': path})
        check(json.loads(body2).get('token') == tok, 'the same link every time')
        st, body, h = req(f'/f/{tok}', who=None)
        html = body.decode('utf8', 'replace')
        check(st == 200 and 'Northwind logo.png' in html and 'E11 AGENCY' in html and 'og:title' in html and '/file' in html, f"the branded page, no sign-in {st}")
        check('<svg' in html and 'currentColor' in html, 'with the E11 word mark')
        for sch in ('light', 'dark'):
            sp = await b.new_page(viewport={'width': 390, 'height': 760}, device_scale_factor=2, color_scheme=sch)
            await sp.goto(BASE + f'/f/{tok}'); await sp.wait_for_timeout(400)
            await sp.screenshot(path=os.environ.get('SHOT_DIR', tempfile.gettempdir()) + f'/flink-{sch}.png'); await sp.close()
        st, body, h = req(f'/f/{tok}', who=None)
        check('noindex' in h.get('X-Robots-Tag', '') and 'nofollow' in h.get('X-Robots-Tag', '') and 'noindex' in body.decode('utf8'), f"private: not for search engines {h.get('X-Robots-Tag')}")
        st, body, _ = req('/robots.txt', who=None, host='files-test.example.com')
        check(st == 200 and b'Disallow: /' in body, 'robots.txt on the files address')
        st, body, h = req(f'/f/{tok}/file', who=None)
        check(st == 200 and 'attachment' in h.get('Content-Disposition', '') and len(body) > 10, f"Download: the file itself {st} {h.get('Content-Disposition')}")
        st, body, h = req(f'/f/{tok}/view', who=None)
        check(st == 200 and h.get('Content-Type', '').startswith('image/'), f"its picture to show {st}")
        st, body, _ = req('/.well-known/apple-app-site-association', who=None)
        aasa = json.loads(body) if st == 200 else {}
        check(aasa.get('applinks', {}).get('details', [{}])[0].get('appIDs') == ['ABCDE12345.ae.e11.console.ios'], f"universal links for the iPhone and Mac app {aasa}")
        st, body, _ = req(f'/api/flink?token={tok}')
        w = json.loads(body)
        check(w.get('ok') and w['where']['kind'] == 'asset' and w['att']['name'] == 'Northwind logo.png', f"staff: where the file is {w}")
        st, body, _ = req('/', who=None, host='files-test.example.com')
        check(st == 404, f"the files address shows nothing else {st}")
        st, body, _ = req('/api/flink', {'path': 'Claims/u-1/receipt.pdf'})
        check(st in (200, 403) and not (json.loads(body) or {}).get('ok'), 'never for claims')
        prod = await E("(db.users.find((u) => u.role === 'production' && u.active !== false) || {}).email")
        if prod:
            st, body, _ = req('/api/flink', {'path': path, 'off': True}, who=prod)
            check(st == 403, f"only Admins turn a link off {st}")
        # turned off: the page says so, the file doesn't come
        st, body, _ = req('/api/flink', {'path': path, 'off': True})
        check(json.loads(body).get('off') is True, 'turned off')
        st, body, _ = req('/api/flink', {'paths': [path, 'Clients/x/none.png']})
        check(json.loads(body).get('off') == [path], f"the files whose links are off (the app's sheets) {body[:120]}")
        st, body, _ = req(f'/f/{tok}', who=None)
        check(st == 404 and 'isn’t available' in body.decode('utf8'), 'the page: not available')
        st, _, _ = req(f'/f/{tok}/file', who=None)
        check(st == 404, 'and no download')
        req('/api/flink', {'path': path, 'off': False})
        st, _, _ = req(f'/f/{tok}/file', who=None)
        check(st == 200, 'on again: the same link works')
        # folder links: the folder as it is now, its files on their own pages, no Download all; not "Files" itself
        fo = await E("(() => { const c = db.clients.find((x) => x.folders.some((f) => f.files.some((a) => a.id === 'fl-1'))); const f = c.folders.find((x) => x.files.some((a) => a.id === 'fl-1')); const top = c.folders.find((x) => !x.parentId && x.name === 'Files'); return { c: c.id, f: f.id, name: f.name, top: top && top.id }; })()")
        st, body, _ = req('/api/flink', {'client': fo['c'], 'folder': fo['f']})
        fr = json.loads(body)
        check(fr.get('ok') and '/d/' in fr['url'], f"a folder's link {fr}")
        ftok = fr.get('token', '')
        st, body, _ = req(f'/d/{ftok}', who=None)
        h2 = body.decode('utf8', 'replace')
        check(st == 200 and fo['name'] in h2 and 'Northwind logo.png' in h2 and f'/d/{ftok}/f/fl-1' in h2 and 'Download all' not in h2, f"the folder page: its files, no Download all {st}")
        for sch in ('light', 'dark'):
            sp = await b.new_page(viewport={'width': 390, 'height': 700}, device_scale_factor=2, color_scheme=sch)
            await sp.goto(BASE + f'/d/{ftok}'); await sp.wait_for_timeout(400)
            await sp.screenshot(path=os.environ.get('SHOT_DIR', tempfile.gettempdir()) + f'/folder-{sch}.png'); await sp.close()
        # (Haris 2026-11-04) each person their own link, saying who shared it; one switch for all of an item's links
        if prod:
            pname = await E(f"(() => {{ const u = db.users.find((x) => x.email === {json.dumps(prod)}); return u.name || u.email.split('@')[0]; }})()")
            st, body, _ = req('/api/flink', {'client': fo['c'], 'folder': fo['f']}, who=prod); pr = json.loads(body)
            check(pr.get('ok') and pr.get('token') and pr['token'] != ftok, f"someone else copying the folder gets their own link {pr}")
            st, body, _ = req('/api/flink', {'client': fo['c'], 'folder': fo['f']}, who=prod)
            check(json.loads(body).get('token') == pr.get('token'), 'and the same one every time')
            st, body, _ = req(f"/d/{pr.get('token')}", who=None); h3 = body.decode('utf8', 'replace')
            check(st == 200 and f'Shared by <b>{pname}' in h3, f'their link says they shared it ({pname})')
            check(f'Shared by <b>{pname}' not in h2, 'the first link still says the first person')
            am = await E("(db.users.find((u) => u.role === 'am' && u.active !== false) || {}).email")
            st, body, _ = req('/api/flink', {'path': path}, who=am or prod); pf = json.loads(body)
            check(pf.get('ok') and pf.get('token') != tok, f'a file: their own link too {pf} {tok}')
            req('/api/flink', {'client': fo['c'], 'folder': fo['f'], 'off': True})
            st, _, _ = req(f"/d/{pr.get('token')}", who=None); st2, _, _ = req(f'/d/{ftok}', who=None)
            st3, b3, _ = req('/api/flink', {'client': fo['c'], 'folder': fo['f']}, who=prod)
            check(st != 200 and st2 != 200 and json.loads(b3).get('off') is True, f'turned off: every link to it is off {st} {st2}')
            req('/api/flink', {'client': fo['c'], 'folder': fo['f'], 'off': False})
            st, _, _ = req(f"/d/{pr.get('token')}", who=None)
            check(st == 200, 'on again: theirs works again')
        st, body, _ = req(f'/d/{ftok}/f/fl-1', who=None)
        check(st == 200 and 'Northwind logo.png' in body.decode('utf8') and f'/d/{ftok}/f/fl-1/file' in body.decode('utf8'), 'a file opened from it: the folder, with that file chosen')
        st, _, h = req(f'/d/{ftok}/f/fl-1/file', who=None)
        check(st == 200 and 'attachment' in h.get('Content-Disposition', ''), 'its Download')
        st, _, _ = req(f'/d/{ftok}/f/not-in-it/file', who=None)
        check(st == 404, 'nothing from outside the folder')
        if fo.get('top'):
            st, body, _ = req('/api/flink', {'client': fo['c'], 'folder': fo['top']})
            check(not json.loads(body).get('ok'), 'not "Files" itself')
        req('/api/flink', {'client': fo['c'], 'folder': fo['f'], 'off': True})
        st, _, _ = req(f'/d/{ftok}', who=None)
        check(st == 404, 'a folder link turned off')
        st, body, _ = req('/api/flink', {'paths': ['d:' + fo['c'] + '/' + fo['f']]})
        check(len(json.loads(body).get('off') or []) == 1, "the app's sheets know it's off")
        st, _, _ = req(f'/f/{tok}/file', who=None)
        check(st == 200, "the file's own link stays as it is")
        req('/api/flink', {'client': fo['c'], 'folder': fo['f'], 'off': False})
        st, body, _ = req(f'/api/flink?token={ftok}')
        check(json.loads(body).get('where', {}).get('kind') == 'folder', 'staff: the app opens the folder')
        # pasting our link in a comment: the file as a chip
        await E(f"window.__clipUrl = 'https://files-test.example.com/f/{tok}'")
        att = await E("FileLinks.fileOf(window.__clipUrl)")
        check(att and att.get('name') == 'Northwind logo.png', f"our link pasted here is the file {att}")
        # deleted: gone
        await E("(async () => { const c = db.clients.find((x) => x.folders.some((f) => f.files.some((a) => a.id === 'fl-1'))); c.folders.forEach((f) => { f.files = f.files.filter((a) => a.id !== 'fl-1'); }); persist(0); await Sync.push(); })()")
        await pg.wait_for_timeout(500)
        st, _, _ = req(f'/f/{tok}', who=None)
        check(st == 404, 'the file deleted: the link stops')
        check(not errs, f'no page errors {errs}')
        await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
