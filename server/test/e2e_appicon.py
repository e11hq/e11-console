"""Mac app Dock icon: the owner uploads a new icon from My profile, every open Mac app swaps it live,
other people don't see the control, and Reset puts the default back."""
import asyncio, os, subprocess, sys, tempfile, time, urllib.request, struct, zlib
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18187; BASE = f'http://127.0.0.1:{PORT}'
OWNER = 'haris@e11-digital.com'; AM = 'areej@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def png(w, h):
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    raw = b''.join(b'\x00' + bytes([91, 75, 214]) * w for _ in range(h))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
BRIDGE = """
window.__icons = [];
window.webkit = { messageHandlers: { e11: { postMessage(raw) {
  const m = JSON.parse(raw); let res = { ok: true };
  if (m.cmd === 'setIcon') window.__icons.push(m.args.reset ? 'reset' : 'b64:' + m.args.b64.length);
  setTimeout(() => window.__e11NativeReply(m.id, res), 5);
} } } };
"""
def req(path, email, data=None):
    r = urllib.request.Request(BASE + path, method='POST' if data is not None else 'GET', data=data, headers={'X-Dev-Email': email, 'Content-Type': 'application/json'})
    return urllib.request.urlopen(r).read()
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': OWNER, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.1.3-test.50'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    req('/api/me', OWNER); req('/api/sample', OWNER, b'{}')
    img = os.path.join(tempfile.mkdtemp(), 'logo.png'); open(img, 'wb').write(png(900, 600))
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def open_as(email, mac=False):
            ctx = await b.new_context(viewport={'width': 1400, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': email, 'url': BASE}])
            if mac: await ctx.add_init_script(BRIDGE)
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(1390, 890); await pg.wait_for_timeout(1500)
            return pg, errs
        mac, mac_errs = await open_as(AM, mac=True)
        check(await mac.evaluate("window.__icons.length") == 0, 'Mac app with the default icon does nothing')
        owner, owner_errs = await open_as(OWNER)
        await owner.evaluate("go('profile')"); await owner.wait_for_timeout(500)
        check(await owner.locator('.ai-card').count() == 1, 'owner sees the Mac app icon card in My profile')
        await mac.evaluate("go('profile')"); await mac.wait_for_timeout(400)
        check(await mac.locator('.ai-card').count() == 0, 'an Account Manager does not see it')
        async with owner.expect_file_chooser() as fc_info:
            await owner.click('[data-action="appicon-upload"]')
        fc = await fc_info.value; await fc.set_files(img); await owner.wait_for_timeout(900)
        check(await owner.locator('.ai-dlg').count() == 1, 'preview dialog opens')
        check(await owner.locator('.ai-warn').count() == 1, 'warns that a non-square image is cropped to the middle')
        src = await owner.evaluate("document.querySelector('.ai-dockbar.dark img').src")
        check(src.startswith('data:image/png'), 'Dock preview drawn')
        await owner.screenshot(path=os.path.join(SHOTS, 'appicon_dialog.png'))
        await owner.click('.ai-round [data-r="round"]'); await owner.wait_for_timeout(200)
        check(await owner.locator('.ai-round .switch.on').count() == 0, 'rounded corners can be turned off')
        await owner.click('.ai-round [data-r="round"]'); await owner.wait_for_timeout(200)
        await owner.click('.ai-dlg [data-r="1"]'); await owner.wait_for_timeout(2500)
        info = await owner.evaluate("AppIcon.info()")
        check(info['custom'] is True, 'server now has a custom icon')
        icons = await mac.evaluate("window.__icons")
        check(len(icons) == 1 and icons[0].startswith('b64:') and int(icons[0][4:]) > 1000, f'open Mac app swapped its Dock icon live: {icons}')
        check(await owner.locator('.ai-card [data-action="appicon-reset"]').count() == 1, 'Reset button shows once an icon is set')
        # a Mac app opened later picks it up on start
        mac2, _ = await open_as('yousef@e11-digital.com', mac=True)
        n2 = await mac2.evaluate("window.__icons"); check(len(n2) == 1, f'a Mac app that starts later sets it once on launch: {n2}')
        await owner.click('[data-action="appicon-reset"]'); await owner.wait_for_timeout(300)
        await owner.click('.dialog [data-r="1"]'); await owner.wait_for_timeout(2000)
        icons = await mac.evaluate("window.__icons")
        check(icons[-1] == 'reset', f'reset reaches the open Mac app: {icons}')
        # a non-owner cannot change it through the server
        r = await mac.evaluate("fetch('/api/app-icon',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({png:'x'})}).then(r=>r.status)")
        check(r == 403, 'server refuses anyone else')
        check(not owner_errs and not mac_errs, f'no page errors {owner_errs + mac_errs}')
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
