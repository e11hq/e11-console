"""Part B step 8: the morning round-up without the page. The shared brain (web/appme-tasks.js, E11AppMe.daily) against
the page's own (web/daily.js nativeShow — what it sends the iPhone app's sheet), in a page that is the iPhone app (its
bridge faked, shell 30), for the owner (the whole team's), an Account Manager (their clients'), the CD, Production and
the Office Admin (no round-up): the title, the line under it, the sections, their counts and rows (at most 7, "See … in
My Tasks"), which one is open; with a comment of theirs scheduled for today and one for tomorrow. Then "See … in My
Tasks": the filter the brain gives is the one the page puts on My Tasks."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT = 18371; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
AREEJ, CARINE, YOUSEF, ARSAL = 'areej@e11-digital.com', 'carine@e11-digital.com', 'yousef@e11-digital.com', 'arsal@e11-digital.com'
DATA = tempfile.mkdtemp()

BRIDGE = """window.__cap = { daily: [] };
window.webkit = { messageHandlers: { e11ios: { postMessage(raw) {
  const m = JSON.parse(raw), a = m.args || {};
  let r = { ok: true };
  if (m.cmd === 'appInfo') r = { ok: true, shell: 30 };
  else if (m.cmd === 'dailySheet') window.__cap.daily.push(a);
  else if (m.cmd === 'nativeSheet') r = { ok: true, index: -1 };
  setTimeout(() => window.__e11NativeReply && window.__e11NativeReply(m.id, r), 1);
} } } };"""

SETUP = """(async () => {
  const src = await (await fetch('/appme-tasks.js', { cache: 'no-store' })).text(); (0, eval)(src);
  window.__sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  window.persist = () => {};
  for (let i = 0; i < 30; i++) await __sleep(100);
  // a comment of theirs for later today, one for tomorrow, one already sent
  const me = currentUserId, t = db.tasks.find((x) => !x.parentId && !x.done);
  const at = (h) => new Date(Date.now() + h * 3600000).toISOString();
  const today = (h) => { const d = new Date(Date.now() + 4 * 3600000); d.setUTCHours(h, 0, 0, 0); return new Date(d.getTime() - 4 * 3600000).toISOString(); };
  db.scheduled = (db.scheduled || []).concat([
    { id: 'sc-a', authorId: me, taskId: t.id, text: 'Send the final files to the client please, with the logo', sendAt: today(23), state: 'waiting' },
    { id: 'sc-b', authorId: me, taskId: t.id, text: '', sendAt: today(22), state: 'waiting' },
    { id: 'sc-c', authorId: me, taskId: t.id, text: 'tomorrow', sendAt: at(30), state: 'waiting' },
    { id: 'sc-d', authorId: me, taskId: t.id, text: 'sent', sendAt: today(1), state: 'sent' },
  ]);
  return { me, wants: Daily.wants() };
})()"""

CASE = """async () => {
  __cap.daily = [];
  Daily.show(); await __sleep(80);
  const clean = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
  const app = E11AppMe.daily(E11Rules, clean(db), currentUserId, Date.now());
  // "See … in My Tasks" as the page does it, for each section that has it
  const all = [];
  for (const s of (app ? app.sections : [])) {
    if (!s.more) continue;
    go('home'); await __sleep(30);
    window.__e11Daily({ ev: 'all', k: s.k }); await __sleep(60);
    const F = Work.f();
    all.push({ k: s.k, page: { view: ui.view, tab: ui.myTasksTab, due: F.due, cd: F.cd, team: F.team, people: F.people, ams: F.ams, assigned: F.assigned },
      app: Object.assign({ view: 'mytasks', tab: 'todo', due: null, cd: false, team: false, people: [], ams: [], assigned: false }, app.team ? { team: true } : {}, s.filter) });
  }
  return { page: clean(__cap.daily[0] || null), app: clean(app), all };
}"""

def diff(a, b, path=''):
    out = []
    if type(a) != type(b): return [f'{path}: {json.dumps(a)[:200]} != {json.dumps(b)[:200]}']
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b: out.append(f'{path}.{k}: only in {"app" if k in a else "page"}')
            else: out += diff(a[k], b[k], f'{path}.{k}')
    elif isinstance(a, list):
        if len(a) != len(b): out.append(f'{path}: {len(a)} items != {len(b)}')
        for i, (x, y) in enumerate(zip(a, b)): out += diff(x, y, f'{path}[{i}]')
    elif a != b: out.append(f'{path}: {json.dumps(a)[:200]} != {json.dumps(b)[:200]}')
    return out[:12]

async def main():
    subprocess.run(['fuser', '-k', f'{PORT}/tcp'], stderr=subprocess.DEVNULL)
    env = {**os.environ, 'DATA_DIR': DATA, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': ROOT + '/web', 'APP_VERSION': '1.6.1-test.1'}
    srv = subprocess.Popen(['node', ROOT + '/server/src/index.js'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ok = []
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    def same(a, b, what):
        d = diff(a, b); check(not d, what, '\n   ' + '\n   '.join(d))
    def req(path, who, body=None):
        r = urllib.request.Request(BASE + path, method='POST' if body is not None else 'GET', data=json.dumps(body).encode() if body is not None else None, headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
        return json.loads(urllib.request.urlopen(r).read())
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE + '/api/health'); break
            except Exception: time.sleep(0.1)
        req('/api/me', ADMIN); req('/api/sample/reset', ADMIN, {})
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            for who, role, gets in [(ADMIN, 'owner', True), (AREEJ, 'an AM', True), (CARINE, 'the CD', None), (YOUSEF, 'Production', False), (ARSAL, 'the Office Admin', False)]:
                ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, base_url=BASE, timezone_id='Asia/Dubai')
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': who, 'url': BASE}])
                await ctx.add_init_script(BRIDGE)
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(4500)
                s = await pg.evaluate(SETUP)
                r = await pg.evaluate(CASE)
                if gets is not None: check(bool(s['wants']) == gets, f'{role}: {"gets" if gets else "no"} round-up on the page')
                if not s['wants']:
                    check(r['app'] is None, f'{role}: no round-up from the brain either', json.dumps(r['app'])[:200])
                else:
                    app = dict(r['app'] or {}); page = dict(r['page'] or {})
                    page.pop('light', None)
                    team = app.pop('team', None)
                    app['sections'] = [{k: v for k, v in x.items() if k != 'filter'} for x in app.get('sections', [])]
                    # (the clock in the foot: the same minute, or the next)
                    fa, fp = app.pop('foot', ''), page.pop('foot', '')
                    check(fa[:17] == fp[:17] == 'Up to date as of ', f'{role}: the foot', (fa, fp))
                    same(app, page, f'{role}: the round-up ({sum(x["n"] for x in app["sections"])} lines, open: {app.get("open")})')
                    check(team == (who == ADMIN), f'{role}: the whole team\'s: {team}')
                    sch = next((x for x in app['sections'] if x['k'] == 'sched'), {})
                    check(sch.get('n') == 2, f'{role}: their 2 comments scheduled for today, not tomorrow\'s or the sent one', sch)
                    for a in r['all']: same(a['app'], a['page'], f'{role}: "See … in My Tasks" for {a["k"]}')
                check(not errs, f'{role}: no page errors', errs)
                await ctx.close()
            await b.close()
    finally:
        srv.kill()
    print(f'\n{sum(ok)}/{len(ok)} passed')
    raise SystemExit(0 if all(ok) else 1)

asyncio.run(main())
