"""Part B step 8: the iPhone app starting without the page.
- GET /api/app/start: signed in → who, and the startup screen's memo; the same as the page sends the app (app.js Splash
  toAppMemo: the first name, the CD's row, three weeks of greetings — occasions — and Dubai's sunrise / sunset) for the
  owner, an Account Manager and the CD; nobody signed in → 401 (JSON — the app reads that as "sign in first").
- The startup screen's four rows from the shared brain (web/appme-tasks.js startRows) — the same as the page ticks them
  (app.js Splash values()), and the fourth row's name."""
import asyncio, os, subprocess, tempfile, time, urllib.request, urllib.error, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT = 18373; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
AREEJ, CARINE, YOUSEF = 'areej@e11-digital.com', 'carine@e11-digital.com', 'yousef@e11-digital.com'
DATA = tempfile.mkdtemp()

BRIDGE = """window.__cap = { memo: null, ticks: [], label4: null };
window.webkit = { messageHandlers: { e11ios: { postMessage(raw) {
  const m = JSON.parse(raw), a = m.args || {};
  let r = { ok: true };
  if (m.cmd === 'appInfo') r = { ok: true, shell: 30 };
  else if (m.cmd === 'splash') { if (a.memo) window.__cap.memo = a.memo; if (a.tick != null) window.__cap.ticks[a.tick] = a.value; if (a.label4) window.__cap.label4 = a.label4; }
  setTimeout(() => window.__e11NativeReply && window.__e11NativeReply(m.id, r), 1);
} } } };"""

async def main():
    subprocess.run(['fuser', '-k', f'{PORT}/tcp'], stderr=subprocess.DEVNULL)
    env = {**os.environ, 'DATA_DIR': DATA, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': ROOT + '/web', 'APP_VERSION': '1.6.1-test.1'}
    srv = subprocess.Popen(['node', ROOT + '/server/src/index.js'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ok = []
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    def req(path, who=None, body=None):
        h = {'Content-Type': 'application/json', 'Accept': 'application/json'}
        if who: h['X-Dev-Email'] = who
        r = urllib.request.Request(BASE + path, method='POST' if body is not None else 'GET', data=json.dumps(body).encode() if body is not None else None, headers=h)
        try: return 200, json.loads(urllib.request.urlopen(r).read())
        except urllib.error.HTTPError as e: return e.code, json.loads(e.read() or b'{}')
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE + '/api/health'); break
            except Exception: time.sleep(0.1)
        req('/api/me', ADMIN); req('/api/sample/reset', ADMIN, {})
        st, j = req('/api/app/start')
        check(st == 401 and j.get('ok') is False, f'nobody signed in: 401 ({st})', j)
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            for who, role in [(ADMIN, 'owner'), (AREEJ, 'an AM'), (CARINE, 'the CD'), (YOUSEF, 'Production')]:
                st, s = req('/api/app/start', who)
                check(st == 200 and s.get('ok') and s.get('me'), f'{role}: signed in — who', s)
                ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, base_url=BASE, timezone_id='Asia/Dubai')
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': who, 'url': BASE}])
                await ctx.add_init_script(BRIDGE)
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(6000)
                cap = await pg.evaluate("""async () => {
                  const src = await (await fetch('/appme-tasks.js', { cache: 'no-store' })).text(); (0, eval)(src);
                  return { cap: __cap, me: currentUserId, rows: E11AppMe.startRows(E11Rules, JSON.parse(JSON.stringify(db)), currentUserId, Date.now()) };
                }""")
                memo = cap['cap']['memo'] or {}
                check(s['me'] == cap['me'], f'{role}: the same person as the page', (s['me'], cap['me']))
                check(s['name'] == memo.get('name') and s['cd'] == memo.get('cd'), f'{role}: first name "{s["name"]}" and the CD\'s row ({s["cd"]}) as the page', (s['name'], s['cd'], memo.get('name'), memo.get('cd')))
                days, pdays = s.get('days') or {}, memo.get('days') or {}
                check(len(days) == 21 and sorted(days) == sorted(pdays), f'{role}: three weeks of days', (len(days), len(pdays)))
                bad = [d for d in days if days[d] != pdays.get(d)]
                check(not bad, f'{role}: each day\'s greeting, sunrise and sunset as the page\'s', [(d, days[d], pdays.get(d)) for d in bad[:3]])
                rows = cap['rows'] or {}
                check(rows.get('list') == cap['cap']['ticks'], f'{role}: the four rows as the page ticks them ({rows.get("list")})', (rows.get('list'), cap['cap']['ticks']))
                check(rows.get('label4') == cap['cap']['label4'] == s['label4'], f'{role}: the fourth row "{s["label4"]}"', (rows.get('label4'), cap['cap']['label4'], s['label4']))
                check(not errs, f'{role}: no page errors', errs)
                await ctx.close()
            await b.close()
        # an occasion with its greeting, from the shared settings (an AM's own occasion): on the day, as the page has it
        st, me = req('/api/snapshot', ADMIN)
        day = time.strftime('%Y-%m-%d', time.gmtime(time.time() + 4 * 3600 + 2 * 86400))
        st, s = req('/api/app/start', ADMIN)
        check(day in s['days'], 'the day after tomorrow is in it', list(s['days'])[:3])
    finally:
        srv.kill()
    print(f'\n{sum(ok)}/{len(ok)} passed')
    raise SystemExit(0 if all(ok) else 1)

asyncio.run(main())
