"""App updates page: opening it asks the updater for a fresh check, so a new release shows
without pressing "Check now" (the updater itself only checks once an hour)."""
import asyncio, json, os, subprocess, tempfile, threading, time, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18188; LPORT = 18189; BASE = f'http://127.0.0.1:{PORT}'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
calls = {'check': 0}
class Fake(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self): self.reply()
    def do_POST(self):
        if self.path == '/check': calls['check'] += 1
        self.reply()
    def reply(self):
        found = calls['check'] > 0
        body = json.dumps({'ok': True, 'channel': 'stable', 'running': '1.2.0', 'current': '1.2.0', 'previous': None, 'lastCheck': '2026-10-21T05:00:00Z', 'lastError': None, 'busy': False, 'updateHour': 2, 'history': [],
                           'available': {'version': '1.2.1', 'name': 'E11 Console 1.2.1', 'notes': '## Fixes\n- New logo'} if found else None}).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
async def main():
    lsrv = HTTPServer(('127.0.0.1', LPORT), Fake); threading.Thread(target=lsrv.serve_forever, daemon=True).start()
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'haris@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.0', 'LAUNCHER_URL': f'http://127.0.0.1:{LPORT}'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        for name, kw in [('desktop', dict(viewport={'width': 1300, 'height': 850})), ('phone', dict(viewport={'width': 390, 'height': 844}, is_mobile=True, has_touch=True))]:
            calls['check'] = 0
            ctx = await b.new_context(base_url=BASE, **kw)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': 'haris@e11-digital.com', 'url': BASE}])
            pg = await ctx.new_page(); await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(200, 300); await pg.wait_for_timeout(2500)
            await pg.evaluate("go('updates')"); await pg.wait_for_timeout(1500)
            txt = await pg.locator('#upd-body').inner_text()
            check(calls['check'] == 1, f'{name}: opening the page asked for a fresh check ({calls["check"]})')
            check('update available' in txt.lower() and '1.2.1' in txt, f'{name}: the new version shows without pressing Check now')
            await ctx.close()
        await b.close()
    srv.terminate(); lsrv.shutdown()
    print('FAILS', len(fails), fails)
asyncio.run(main())
