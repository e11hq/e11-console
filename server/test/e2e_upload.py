"""Uploads: big files go up in raw pieces, a few at a time, and carry on through dropped connections."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18251; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
OUT = tempfile.mkdtemp(); fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.3.3-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=3, is_mobile=True, has_touch=True, base_url=BASE)
        await ctx.add_cookies([{'name': 'e11_dev_email', 'value': 'areej@e11-digital.com', 'url': BASE}])
        pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto('/'); await pg.wait_for_timeout(2500); await pg.mouse.click(5, 5); await pg.wait_for_timeout(1000)
        E = pg.evaluate
        data = os.urandom(10 * 1024 * 1024 + 12345)
        src = os.path.join(OUT, 'clip.mp4'); open(src, 'wb').write(data)
        seen = {'n': 0, 'dropped': 0, 'max_body': 0}
        async def flaky(route):
            seen['n'] += 1
            body = route.request.post_data_buffer or b''
            seen['max_body'] = max(seen['max_body'], len(body))
            if seen['n'] in (2, 4):            # two pieces lose their connection (like switching apps)
                seen['dropped'] += 1; await route.abort('connectionreset'); return
            await route.continue_()
        await pg.route('**/api/host/writeChunkBin*', flaky)
        tid = await E("db.tasks.find(t=>!t.parentId).id")
        async with pg.expect_file_chooser() as fc:
            await E(f"(window.__up = Host.call('pickAttachments', {{ taskId: '{tid}' }}), 1)")
        await (await fc.value).set_files(src)
        r = await E("window.__up")
        files = r.get('files') or []
        check(len(files) == 1, f'the upload finished despite two dropped pieces: {files}')
        check(seen['dropped'] == 2 and seen['n'] >= 5, f'pieces were retried ({seen})')
        check(seen['max_body'] <= 4 * 1024 * 1024, f"pieces are raw bytes, at most 4 MB ({seen['max_body']})")
        if files:
            f = files[0]
            check(f['size'] == len(data), f"size matches: {f['size']} vs {len(data)}")
            import hashlib
            got = await E(f"fetch('/__file/' + {json.dumps(files[0]['path'])}.split('/').map(encodeURIComponent).join('/')).then(r=>r.arrayBuffer()).then(b=>crypto.subtle.digest('SHA-256', b)).then(h=>[...new Uint8Array(h)].map(x=>x.toString(16).padStart(2,'0')).join(''))")
            check(got == hashlib.sha256(data).hexdigest(), 'the stored file is byte-for-byte the original')
        await b.close()
    srv.kill()
    print('OUT', OUT)
    print('ALL PASS' if not fails else f'FAILS {fails}')
asyncio.run(main())
