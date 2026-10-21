"""Required Mac app update: an older Mac app (no or lower `shell` in appInfo) shows a banner that can't be
dismissed; Update now saves and opens a .terminal file that runs the installer for this server.
An up-to-date Mac app and a normal browser show nothing."""
import asyncio, base64, os, plistlib, re, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18190; BASE = f'http://127.0.0.1:{PORT}'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
SHELL = int(re.search(r'var SHELL_VERSION = (\d+);', open(os.path.join(ROOT, 'mac/main.js')).read()).group(1))
def bridge(shell):
    info = '{ ok: true, server: location.origin, version: "2.0.0"' + (f', shell: {shell}' if shell else '') + ' }'
    return """
window.__saved = [];
window.webkit = { messageHandlers: { e11: { postMessage(raw) {
  const m = JSON.parse(raw); let res = { ok: true };
  if (m.cmd === 'appInfo') res = %s;
  if (m.cmd === 'saveFile') window.__saved.push(m.args);
  setTimeout(() => window.__e11NativeReply(m.id, res), 5);
} } } };""" % info
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'haris@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.5'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        async def open_app(init):
            ctx = await b.new_context(viewport={'width': 1300, 'height': 800}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': 'haris@e11-digital.com', 'url': BASE}])
            if init: await ctx.add_init_script(init)
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(600, 400); await pg.wait_for_timeout(2500)
            return ctx, pg, errs
        # old Mac app (no shell number)
        ctx, pg, errs = await open_app(bridge(None))
        check(await pg.locator('#mac-update').count() == 1, 'older Mac app shows the required-update banner')
        check(await pg.locator('#mac-update [aria-label*="lose"], #mac-update .x, #mac-update [data-action*="dismiss"]').count() == 0, 'banner has no close button')
        await pg.screenshot(path=os.path.join(tempfile.gettempdir(), 'macupdate_banner.png'))
        await pg.click('#mac-update [data-action="mac-update"]'); await pg.wait_for_timeout(500)
        saved = await pg.evaluate('window.__saved')
        check(len(saved) == 1 and saved[0]['name'].endswith('.terminal') and saved[0]['open'] and saved[0]['done'], 'Update now saves and opens a .terminal file')
        pl = plistlib.loads(base64.b64decode(saved[0]['b64']))
        cmd = pl['CommandString']
        check(f'curl -fsSL {BASE}/install | bash' in cmd, f'it runs this server’s installer: {cmd[:90]}…')
        check(pl['RunCommandAsShell'] is False and pl['shellExitAction'] == 1, 'runs inside a shell and the window closes when it finishes cleanly')
        syn = subprocess.run(['bash', '-n', '-c', cmd], capture_output=True, text=True)
        check(syn.returncode == 0, f'the command is valid shell {syn.stderr}')
        fake = tempfile.mkdtemp(); open(os.path.join(fake, 'osascript'), 'w').write('#!/bin/sh\nfor a in "$@"; do printf "[%s]" "$a"; done\n'); os.chmod(os.path.join(fake, 'osascript'), 0o755)
        inner = re.search(r'(/bin/sh -c ".*?") </dev/null', cmd).group(1).replace('sleep 2; ', '')
        check("perl -MPOSIX -e 'setsid(); exec @ARGV'" in cmd and '&); exit 0;' in cmd, 'the helper runs in its own session, not as a job of the window’s shell')
        ran = subprocess.run(['bash', '-c', inner], capture_output=True, text=True, env={**os.environ, 'PATH': fake + ':' + os.environ['PATH']}).stdout
        check('[close (every window whose name contains "E11 Console update")]' in ran and '[if (count of windows) is 0 then quit]' in ran, f'afterwards it closes the update window by its title, then quits Terminal if nothing else is open: {ran}')
        check("\\033]0;E11 Console update" in cmd, 'the update window is titled so it can be found')
        check('Terminal is updating' in await pg.locator('#mac-update').inner_text(), 'banner says the update is under way')
        check(not errs, f'no page errors {errs}')
        await ctx.close()
        # up-to-date Mac app and plain browser: no banner
        ctx, pg, errs = await open_app(bridge(SHELL))
        check(await pg.locator('#mac-update').count() == 0, f'up-to-date Mac app (shell {SHELL}) shows nothing')
        await pg.click('#me-chip'); await pg.wait_for_timeout(300)
        await pg.locator('.menu .mi', has_text='Update Mac app').click(); await pg.wait_for_timeout(500)
        check(len(await pg.evaluate('window.__saved')) == 1, 'profile menu → Update Mac app runs the update any time'); await ctx.close()
        ctx, pg, errs = await open_app(None)
        check(await pg.locator('#mac-update').count() == 0, 'a normal browser shows nothing'); await ctx.close()
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
