"""Fast office use in the Mac app (fake Mac bridge): a picked file on the NAS shared folder is copied on the NAS
(the progress row says so); one that isn't goes the normal way; with an older Mac app nothing changes."""
import asyncio, os, tempfile, time, subprocess, urllib.request, hashlib, base64, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18247; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def fp(data):
    n = min(1 << 20, len(data))
    return hashlib.sha256(data[:n] + data[len(data) - n:]).hexdigest()
async def main():
    data_dir = tempfile.mkdtemp(); share = os.path.join(tempfile.mkdtemp(), 'E11 Share')
    os.makedirs(os.path.join(share, 'KIA', 'Final'))
    big = os.urandom(3 * 1024 * 1024 + 7)
    open(os.path.join(share, 'KIA', 'Final', 'hero.mov'), 'wb').write(big)
    local = os.urandom(5000)
    env = {**os.environ, 'DATA_DIR': data_dir, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.8.1-test.1', 'SHARE_DIR': share}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    def bridge(shell):
        files = {'tok-share': {'name': 'hero.mov', 'size': len(big), 'share': {'ok': True, 'onShare': True, 'rel': 'KIA/Final/hero.mov', 'size': len(big), 'fp': fp(big)}},
                 'tok-local': {'name': 'notes.bin', 'size': len(local), 'share': {'ok': True, 'onShare': False}, 'b64': base64.b64encode(local).decode()}}
        return """
window.__calls = []; window.__pick = 'tok-share';
const F = %s;
window.webkit = { messageHandlers: { e11: { postMessage(raw) {
  const m = JSON.parse(raw); let res = { ok: true }; window.__calls.push(m.cmd);
  if (m.cmd === 'appInfo') res = { ok: true, shell: %d, native: 'swift', server: location.origin };
  if (m.cmd === 'pickLocalFiles') res = { ok: true, files: [{ token: window.__pick, name: F[window.__pick].name, size: F[window.__pick].size }] };
  if (m.cmd === 'shareInfo') res = F[m.args.token].share;
  if (m.cmd === 'readLocalChunk') { const b = atob(F[m.args.token].b64); res = { ok: true, b64: btoa(b.slice(m.args.offset, m.args.offset + m.args.length)) }; }
  setTimeout(() => window.__e11NativeReply(m.id, res), 5);
} } } };""" % (json.dumps(files), shell)
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            async def open_app(shell):
                ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
                await ctx.add_init_script(bridge(shell))
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(3000)
                return pg, errs
            pg, errs = await open_app(10)
            check(await pg.evaluate("Host.isMacApp && ServerHost.office() && ServerHost.office().share"), 'the Mac app knows the shared folder is connected')
            tid = await pg.evaluate("db.tasks.find(t => !t.parentId && !t.done).id")
            # a file on the shared folder: copied on the NAS
            got = await pg.evaluate(f"""(async () => {{ const p = Host.call('pickAttachments', {{ taskId: '{tid}' }}); let via = '';
              for (let i = 0; i < 40 && !via; i++) {{ await new Promise(r => setTimeout(r, 25)); const v = document.querySelector('.up-via'); if (v) via = v.textContent; }}
              const r = await p; return {{ files: r.files, via }}; }})()""")
            f = (got['files'] or [None])[0]
            print('share copy', got)
            check(f and f['path'].startswith(f'attachments/{tid}/') and f['size'] == len(big), 'the file from the shared folder was added to the task')
            copied = os.path.join(data_dir, 'files', f['path']) if f else ''
            check(f and open(copied, 'rb').read() == big, 'copied on the NAS, byte for byte')
            check(got['via'] == 'Copying on the NAS', f"the progress row says how ({got['via']!r})")
            calls = await pg.evaluate("window.__calls")
            check('readLocalChunk' not in calls, 'nothing was read from the Mac and sent')
            # a file not on the shared folder: the normal upload
            await pg.evaluate("window.__pick = 'tok-local'; window.__calls = []")
            r2 = await pg.evaluate(f"Host.call('pickAttachments', {{ taskId: '{tid}' }}).then(r => r.files)")
            check(r2 and r2[0]['size'] == len(local) and 'readLocalChunk' in await pg.evaluate("window.__calls"), 'a file on the Mac uploads the usual way')
            check(not errs, f'no page errors {errs}')
            # an older Mac app: the usual upload even for a shared-folder file
            pg2, errs2 = await open_app(9)
            await pg2.evaluate("window.__pick = 'tok-local'")
            await pg2.evaluate(f"Host.call('pickAttachments', {{ taskId: '{tid}' }})")
            check('shareInfo' not in await pg2.evaluate("window.__calls"), 'an older Mac app doesn’t try (until it’s updated)')
            check(not errs2, f'no page errors {errs2}')
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
