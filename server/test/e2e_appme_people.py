"""Part B step 2: Me's own screens from the app's own copy of the data (web/appme-people.js, E11AppMe) — Me's card and
Work rows, Team members, the Trash (with searches and categories) and My profile — the same JSON as the page's own
models (phone.js NativeMe), for the owner, the CD, a Social Executive, Production, an Account Manager and the Office
Admin; and again after a task is deleted to the Trash (a fresh snapshot)."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18333; BASE=f'http://127.0.0.1:{PORT}'; ADMIN='haris@e11-digital.com'
PEOPLE = [ADMIN, 'carine@e11-digital.com', 'aishwarya@e11-digital.com', 'ali@e11-digital.com', 'areej@e11-digital.com', 'arsal@e11-digital.com']

# both sides, on the page: the page's models (NativeMe) and E11AppMe's from a fresh snapshot
COMPARE = """(async () => {
  if (typeof E11AppMe === 'undefined' || window.__amFresh) { const src = await (await fetch('/appme-people.js', { cache: 'no-store' })).text(); (0, eval)(src); window.__amFresh = false; }
  const snap = await (await fetch('/api/snapshot', { cache: 'no-store' })).json();
  const data = snap.data, me = currentUserId, now = Date.now();
  // (what the data doesn't hold: the owner, the server's address, the app's shell — the page's own NativeMe has 0 here)
  const env = { ownerId, host: Host.isServer ? location.host : '', shell: 0 };
  const clean = (x) => JSON.parse(JSON.stringify(x));
  const out = { page: {}, app: {} };
  const pm = NativeMe.peek();
  out.page.me = clean({ card: pm.card, work: pm.work });
  out.app.me = clean(E11AppMe.me(E11Rules, data, me, now, env));
  out.page.team = clean(NativeMe.teamModel());
  out.app.team = clean(E11AppMe.team(E11Rules, data, me, now, env));
  const pf = clean(NativeMe.profileModel()); delete pf.photoBusy; delete pf.owner;
  out.page.profile = pf;
  out.app.profile = clean(E11AppMe.profile(E11Rules, data, me, now, env));
  // (md: the raw 'MM-DD' birthday, the app's date picker's — the page's model has only the day as shown)
  if (!('md' in pf) && out.app.profile) { out.mdOk = out.app.profile.md === (userById(me).bday || ''); delete out.app.profile.md; } else out.mdOk = true;
  // the Trash: every category, a word from an item's title, a typo of it, and nothing found
  const t0 = (trashList()[0] || null);
  const word = t0 ? (sWords(trashTitle(t0))[0] || '') : '';
  const typo = word.length >= 5 ? word.slice(0, 2) + word[3] + word[2] + word.slice(4) : word;
  const qs = [['', 'all'], ['', 'task'], ['', 'project'], ['', 'file'], ['', 'comment'], ['', 'mine'], [word, 'all'], [typo, 'all'], ['zzqqxx', 'all'], [word, 'mine']];
  const q0 = ui.trashQ, f0 = ui.trashFilter;
  out.page.trash = []; out.app.trash = [];
  for (const [q, f] of qs) {
    ui.trashQ = q; ui.trashFilter = f;
    out.page.trash.push({ q, f, m: clean(NativeMe.trashModel()) });
    out.app.trash.push({ q, f, m: clean(E11AppMe.trash(E11Rules, data, me, now, q, f, env)) });
  }
  ui.trashQ = q0; ui.trashFilter = f0;
  out.nTrash = trashList().length; out.word = word;
  return out;
})()"""

def diff(a, b, path=''):
    """the first places two JSON values differ"""
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
    subprocess.run(['fuser','-k',f'{PORT}/tcp'],stderr=subprocess.DEVNULL)
    env={**os.environ,'DATA_DIR':tempfile.mkdtemp(),'AUTH_DEV':'1','ADMIN_EMAIL':ADMIN,'PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.6.1-test.1'}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    ok=[]
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    def same(r, who):
        check(r.get('mdOk'), f'{who}: profile md is the raw birthday')
        for k in ('me', 'team', 'profile', 'trash'):
            d = diff(r['app'][k], r['page'][k], k)
            check(not d, f'{who}: {k} the same' + (f' ({r["nTrash"]} in the Trash, word “{r["word"]}”)' if k == 'trash' else ''), '\n   ' + '\n   '.join(d))
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE+'/api/health'); break
            except Exception: time.sleep(0.1)
        H={'X-Dev-Email':ADMIN}
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/me',headers=H))
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/sample/reset',method='POST',data=b'{}',headers={**H,'Content-Type':'application/json'})).read()
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            async def open_as(who):
                ctx=await b.new_context(viewport={'width':390,'height':844},device_scale_factor=2,is_mobile=True,has_touch=True,base_url=BASE)
                await ctx.add_cookies([{'name':'e11_dev_email','value':who,'url':BASE}])
                pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/'); await pg.wait_for_timeout(4500)
                return ctx, pg, errs
            for who in PEOPLE:
                ctx, pg, errs = await open_as(who)
                same(await pg.evaluate(COMPARE), who)
                check(not errs, f'{who}: no page errors', errs)
                await ctx.close()
            # a change: the owner deletes two tasks and a comment to the Trash; the owner and an AM see it the same way
            ctx, pg, errs = await open_as(ADMIN)
            gone = await pg.evaluate("""(() => {
              const ts = db.tasks.filter((t) => !t.parentId && !t.done && t.projectId);
              const a = ts[0], b2 = ts.find((t) => t.projectId !== a.projectId) || ts[1];
              deleteTaskFlow(a.id); deleteTaskFlow(b2.id);
              const t = db.tasks.find((x) => (x.comments || []).length);
              if (t) { const c = t.comments[0]; t.comments = t.comments.filter((x) => x.id !== c.id); toTrash('comment', { taskId: t.id, comments: [c] }, { taskTitle: t.title }); commit({ delay: 0 }); }
              return [a.title, b2.title];
            })()""")
            await pg.wait_for_timeout(2500)
            r = await pg.evaluate(COMPARE)
            check(r['nTrash'] >= 3, f'owner: the Trash holds what was deleted ({r["nTrash"]}: {gone})')
            same(r, ADMIN + ' after deleting')
            check(not errs, 'owner after deleting: no page errors', errs)
            # and a change to someone's profile (sound off, a notification type off, a birthday, a city)
            await pg.evaluate("(() => { const u = me(); u.prefs = u.prefs || {}; u.prefs.sound = false; u.prefs.notifOff = { ...(u.prefs.notifOff || {}), comment: true }; u.bday = '03-14'; u.country = 'United Arab Emirates'; u.city = 'Dubai'; persist(0); })()")
            await pg.wait_for_timeout(2500)
            same(await pg.evaluate(COMPARE), ADMIN + ' after a profile change')
            await ctx.close()
            ctx, pg, errs = await open_as('areej@e11-digital.com')
            same(await pg.evaluate(COMPARE), 'areej (AM) after the owner deleted')
            check(not errs, 'areej after: no page errors', errs)
            await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
