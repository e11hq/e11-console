"""Part B step 4: the app's Me pages without the page — My profile's edits on the server (server/src/appact-me.js pfSet)
and the questions / sheets worked out by the shared brain (web/appme-people.js: memberMenu, clientsMenu, cdAsk,
addMemberForm, trashAsk, trashEmptyAsk, places).
1. The brain against the website, in the page: for each person on the team (the owner, another Super Admin, the Office
   Admin, a freelancer, a Social person, the Social Manager, someone removed, the CD, Production, Finance only…), the
   sheet the page's memberMenu sends the app (NativeSheet.rows over what showMenu got) and the brain's are the same —
   sections, headers, labels, icons, ticks, red, greyed, role colours, which rows do something; the questions the page
   asks (Remove …?, Work as …?) word for word; seen by the owner, by another Super Admin (the owner's account locked)
   and by each one for their own row. The freelancer's clients sheet, the CD switch's question, Add team member's form,
   Delete forever / Empty the Trash, and the country / city lists likewise.
2. pfSet against the page's saveMe: the same starting data done twice — by the page's own handler (phone.js NativeMe
   __e11Me pfName, pfCountry, pfCity, pfBday, pfSound, pfNotif, digest, pfPhoto, pfPhotoOff) and by the server's
   handler over the same records; the person's record afterwards, the message and the file sent to the trash folder
   must be the same.
3. Through the server's route (POST /api/app/act): every field saved for people of each role (their own record passes
   access.canWrite), nobody else's record can be named, and kv 'app-act-profile' = 'off' sends the app back to the page."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json, sqlite3
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT = 18347; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
DATA = tempfile.mkdtemp(); DBFILE = os.path.join(DATA, 'db', 'e11.sqlite'); WORK = tempfile.mkdtemp()

DUMP = """import { openStore } from %s; const s = openStore(process.argv[2]); process.stdout.write(JSON.stringify(s.snapshot().data));""" % json.dumps(ROOT + '/server/src/store.js')
RUN = """import fs from 'node:fs'; import { createMeActs } from %s;
const [pre, who, ev] = [JSON.parse(fs.readFileSync(process.argv[2], 'utf8')), process.argv[3], JSON.parse(process.argv[4])];
const copy = (v) => (v == null ? null : JSON.parse(JSON.stringify(v)));
const store = { get: (k, id) => copy(k === 'meta' ? (id === 'main' ? pre.meta : null) : (pre[k] || []).find((x) => String(x.id) === String(id))), list: (k) => copy(k === 'meta' ? [pre.meta] : pre[k] || []) };
const acts = createMeActs({ store, now: () => Date.now() });
const u = pre.users.find((x) => x.email === who);
const { ev: name, ...body } = ev;
process.stdout.write(JSON.stringify(acts[name](u, body)));""" % json.dumps(ROOT + '/server/src/appact-me.js')
open(os.path.join(WORK, 'dump.mjs'), 'w').write(DUMP); open(os.path.join(WORK, 'run.mjs'), 'w').write(RUN)

def node(script, *args):
    r = subprocess.run(['node', '--no-warnings', os.path.join(WORK, script), *args], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr[-2000:])
    return json.loads(r.stdout)
def dump(): return node('dump.mjs', DBFILE)

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

# the brain and the page side by side, for one viewer: every person's menu, and the other questions
COMPARE = """(async (ids) => {
  if (!window.__amLoaded) { const src = await (await fetch('/appme-people.js', { cache: 'no-store' })).text(); (0, eval)(src); window.__amLoaded = true; }
  const snap = await (await fetch('/api/snapshot', { cache: 'no-store' })).json();
  const data = snap.data, me = currentUserId, now = Date.now();
  const env = { ownerId, host: location.host, testCopy: isTestCopy() };
  const clean = (x) => JSON.parse(JSON.stringify(x));
  // what the page would show: showMenu / dialogs caught, nothing changed (every question answered no)
  let cap = null, asked = [];
  const keep = { showMenu: window.showMenu, dialog: window.dialog, choiceDialog: window.choiceDialog, formDialog: window.formDialog, toast: window.toast, fits: NativeSheet.fits, asking: NativeMe.asking };
  window.showMenu = (a, items, opts) => { cap = { items, opts: opts || {} }; };
  window.dialog = async (a) => { asked.push({ kind: 'dialog', title: a.title, body: a.body, okText: a.okText, danger: !!a.danger }); return false; };
  window.choiceDialog = async (a) => { asked.push({ kind: 'choice' }); return null; };
  window.formDialog = async (a) => { const { validate, ...rest } = a; asked.push({ kind: 'form', ...clean(rest) }); return null; };
  window.toast = () => {};
  const out = { menus: [], clients: [], cd: [], trash: null, empty: null, form: null, places: null };
  const row = (r) => ({ label: r.label, icon: r.icon || '', checked: !!r.checked, danger: !!r.danger, disabled: !!r.disabled, dot: r.dot || null, does: r.i >= 0, ...(r.multi ? { multi: true } : {}), ...(r.sub ? { sub: r.sub } : {}) });
  try {
    for (const id of ids) {
      if (!userById(id)) continue;
      cap = null; asked = [];
      if (can('manageUsers')) memberMenu(document.body, id, true);   // (the page opens it only for people who manage the team)
      const app = E11AppMe.memberMenu(E11Rules, data, me, now, id, env);
      if (!cap) { out.menus.push({ id, page: null, app: app && clean(app) }); continue; }
      const secs = NativeSheet.rows(cap.items);
      const who = (cap.items[0] && cap.items[0].html && /pm-who/.test(cap.items[0].html)) ? (() => { const d = document.createElement('div'); d.innerHTML = cap.items[0].html; d.querySelectorAll('.av').forEach((x) => x.remove()); return d.textContent.replace(/\\s+/g, ' ').trim(); })() : null;
      const av = document.createElement('div'); av.innerHTML = avatarHTML(id, 30); const avEl = av.firstElementChild;
      const pagePerson = { initials: avEl.textContent.trim(), color: NativeSheet.colorRGB(avEl.style.background || '#000') };
      // the questions behind each row that has one in the app (run on the page, answered no)
      const asks = [];
      (app ? app.acts : []).forEach((a, i) => {
        if (!a.ask && a.act !== 'remove' && !(a.act === 'role' && id === me)) return;
        const r = app.sheet.sections.flatMap((s) => s.rows).find((x) => x.i === i);
        const it = cap.items.find((x) => x && x.run && ((x.label || '') === r.label || (x.html || '').replace(/<[^>]+>/g, '').trim() === r.label));
        asked = []; if (it) { try { it.run(); } catch (e) {} }
        const q = asked.filter((x) => x.kind === 'dialog')[0] || null; if (q) delete q.kind;
        asks.push({ label: r.label, page: q, app: a.ask || null });
      });
      out.menus.push({ id, who, pagePerson, hasPhoto: !!userById(id).avatar,
        page: secs.map((s) => ({ header: s.header || null, rows: s.rows.map(row) })),
        app: app && { first: app.sheet.sections[0], sections: app.sheet.sections.slice(1).map((s) => ({ header: s.header || null, rows: s.rows.map(row) })) }, asks });
    }
    // a freelancer's clients (the app's sheet: projectAccessDialog's native branch)
    NativeSheet.fits = () => true; NativeMe.asking = () => true;
    for (const id of ids.filter((x) => userById(x) && userById(x).role === 'freelancer')) {
      cap = null; projectAccessDialog(userById(id));
      if (!cap) { out.clients.push({ id, page: null, app: E11AppMe.clientsMenu(E11Rules, data, me, now, id, env), acts: true }); continue; }
      const secs = NativeSheet.rows(cap.items);
      secs.forEach((sec) => sec.rows.forEach((r) => { if (r.i >= 0 && cap.items[r.i] && cap.items[r.i].multi) r.multi = true; }));
      const pg = { sections: secs.map((s) => ({ header: s.header || null, rows: s.rows.map(row) })), search: cap.opts.search || null, empty: cap.opts.empty || null };
      const a = E11AppMe.clientsMenu(E11Rules, data, me, now, id, env);
      out.clients.push({ id, page: pg, app: { sections: a.sheet.sections.map((s) => ({ header: s.header || null, rows: s.rows.map(row) })), search: a.sheet.search || null, empty: a.sheet.empty || null },
        acts: a.acts.every((x, i) => x.project === db.projects.slice().sort(byOrder)[i].id) });
    }
    NativeSheet.fits = keep.fits; NativeMe.asking = keep.asking;
    // the CD switch, for each person
    for (const id of ids) {
      if (!userById(id) || userById(id).active === false) continue;
      asked = []; await cdToggleFlow(id);
      const q = asked[0] || null;
      out.cd.push({ id, page: q ? (q.kind === 'choice' ? { choice: true } : { title: q.title, body: q.body, okText: q.okText, danger: q.danger }) : null, app: clean(E11AppMe.cdAsk(E11Rules, data, me, now, id, env)) });
    }
    // Add team member, Delete forever, Empty the Trash
    asked = []; await addMemberFlow(); const f = asked[0] || null; if (f) delete f.kind;
    out.form = { page: f, app: clean(E11AppMe.addMemberForm(E11Rules, data, me, now, env)) };
    const t0 = trashList()[0];
    if (t0) { asked = []; await eraseTrashFlow(t0.id); out.trash = { page: asked[0] || null, app: E11AppMe.trashAsk(E11Rules, data, me, now, t0.id, env) }; if (out.trash.page) delete out.trash.page.kind; }
    asked = []; await emptyTrashFlow(); out.empty = { page: asked[0] || null, app: E11AppMe.trashEmptyAsk(E11Rules, data, me, now, env) }; if (out.empty.page) delete out.empty.page.kind;
    out.super = isSuper(userById(me)); out.manage = can('manageUsers'); out.nTrash = trashList().length;
    out.places = { country: JSON.stringify(E11AppMe.places(E11Rules, data, me, now, 'country').list) === JSON.stringify(E11_PLACES.COUNTRIES) && E11_PLACES.COUNTRIES.length > 100,
      city: JSON.stringify(E11AppMe.places(E11Rules, data, me, now, 'city', 'United Arab Emirates').list) === JSON.stringify(E11_PLACES.cities('United Arab Emirates')) && E11_PLACES.cities('United Arab Emirates').length > 0,
      none: E11AppMe.places(E11Rules, data, me, now, 'city', 'Nowhere').list.length === 0 };
  } finally { Object.assign(window, { showMenu: keep.showMenu, dialog: keep.dialog, choiceDialog: keep.choiceDialog, formDialog: keep.formDialog, toast: keep.toast }); }
  return out;
})"""

async def main():
    subprocess.run(['fuser', '-k', f'{PORT}/tcp'], stderr=subprocess.DEVNULL)
    env = {**os.environ, 'DATA_DIR': DATA, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': ROOT + '/web', 'APP_VERSION': '1.6.1-test.1'}
    srv = subprocess.Popen(['node', ROOT + '/server/src/index.js'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ok = []
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    def reset():
        H = {'X-Dev-Email': ADMIN}
        urllib.request.urlopen(urllib.request.Request(BASE + '/api/me', headers=H))
        urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample/reset', method='POST', data=b'{}', headers={**H, 'Content-Type': 'application/json'})).read()
    def act(who, ev):
        req = urllib.request.Request(BASE + '/api/app/act', method='POST', data=json.dumps({**ev, 'op': None}).encode(), headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
        return json.loads(urllib.request.urlopen(req).read())
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE + '/api/health'); break
            except Exception: time.sleep(0.1)
        reset()
        users = [u for u in dump()['users']]
        by = lambda f: next((u for u in users if f(u)), None)
        meta = dump()['meta']
        owner = by(lambda u: u['email'] == ADMIN)
        other_super = by(lambda u: u['id'] != owner['id'] and u.get('active') is not False and (u['role'] == 'admin' or (u.get('admin') and u['role'] != 'office_admin')))
        if not other_super:
            r = act(ADMIN, {'ev': 'member', 'id': 'u-sara', 'act': 'admin'}); check(r.get('ok'), 'setup: someone else given Super Admin rights', json.dumps(r)[:300])
            other_super = next(u for u in dump()['users'] if u['id'] == 'u-sara')
        # someone removed (Remove from team, through the route)
        r = act(ADMIN, {'ev': 'member', 'id': 'u-ali', 'act': 'remove'}); check(r.get('ok'), 'setup: Ali removed from the team', json.dumps(r)[:300])
        users = dump()['users']
        office = by(lambda u: u['role'] == 'office_admin')
        free = by(lambda u: u['role'] == 'freelancer')
        mgr = (meta.get('socialMgrIds') or [None])[0]
        social = by(lambda u: u['role'] == 'social' and u['id'] != mgr and u.get('active') is not False)
        fin_only = by(lambda u: u['role'] in ('finance_admin', 'finance_viewer'))
        ids = [x for x in [owner['id'], other_super['id'], office and office['id'], free and free['id'], social and social['id'], mgr, 'u-ali', meta.get('cdUserId'), 'u-joe', fin_only and fin_only['id'], 'u-lina'] if x]
        print('   people:', ids)
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            async def open_as(who):
                ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, base_url=BASE, timezone_id='Asia/Dubai')
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': who, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                trashed = []
                pg.on('request', lambda r: trashed.extend((lambda d: d.get('paths') or [d.get('path')])(json.loads(r.post_data or '{}'))) if '/api/host/trash' in r.url else None)
                await pg.goto('/'); await pg.wait_for_timeout(4500)
                return ctx, pg, errs, trashed

            # ---------- 1. the brain against the page ----------
            def menus_same(r, viewer):
                for m in r['menus']:
                    name = f'{viewer} → {m["id"]}'
                    if m['page'] is None:
                        check(m['app'] is None, f'{name}: no menu on either side', json.dumps(m['app'])[:200]); continue
                    if m['app'] is None: check(False, f'{name}: the brain has the menu', ''); continue
                    first = m['app']['first']
                    check(first.get('rows') == [] and first.get('header') == m['who'], f'{name}: the person on top “{first.get("header")}”', f'page: {m["who"]}')
                    pp = first.get('person') or {}
                    check(bool(pp.get('photo')) == m['hasPhoto'] and pp.get('initials') and (m['hasPhoto'] or (pp.get('initials') == m['pagePerson']['initials'] and pp.get('color') == m['pagePerson']['color'])), f'{name}: their picture', f'{pp} vs {m["pagePerson"]}')
                    d = diff(m['app']['sections'], m['page'])
                    check(not d, f'{name}: the same sheet ({sum(len(s["rows"]) for s in m["page"])} rows)', '\n   ' + '\n   '.join(d))
                    for a in m['asks']:
                        d = diff(a['app'], a['page'])
                        check(not d, f'{name}: “{a["label"]}” asks the same' + (f' — {a["app"]["title"]}' if a['app'] else ' (nothing)'), '\n   ' + '\n   '.join(d))
                for c in r['clients']:
                    if c['page'] is None: check(c['app'] is None, f'{viewer} → {c["id"]}: no clients sheet on either side', json.dumps(c['app'])[:200]); continue
                    d = diff(c['app'], c['page'])
                    check(not d and c['acts'], f'{viewer} → {c["id"]}: the clients sheet the same ({sum(len(s["rows"]) for s in c["page"]["sections"])} clients)', '\n   ' + '\n   '.join(d))
                for c in r['cd']:
                    d = diff(c['app'], c['page'])
                    check(not d, f'{viewer} → {c["id"]}: the CD switch asks the same {json.dumps(c["app"])[:70]}', '\n   ' + '\n   '.join(d))
                if r['manage']:
                    d = diff(r['form']['app'], r['form']['page']); check(not d, f'{viewer}: Add team member the same form', '\n   ' + '\n   '.join(d))
                else: check(r['form']['app'] is None and r['form']['page'] is None, f'{viewer}: no Add team member', json.dumps(r['form'])[:200])
                if r['trash'] is not None:
                    if r['super']: d = diff(r['trash']['app'], r['trash']['page']); check(not d, f'{viewer}: Delete forever asks the same', '\n   ' + '\n   '.join(d))
                    else: check(r['trash']['app'] is None, f'{viewer}: no Delete forever (not a Super Admin)', json.dumps(r['trash'])[:200])
                if r['super']: d = diff(r['empty']['app'], r['empty']['page']); check(not d, f'{viewer}: Empty the Trash asks the same', '\n   ' + '\n   '.join(d))
                else: check(r['empty']['app'] is None, f'{viewer}: no Empty the Trash (not a Super Admin)', json.dumps(r['empty'])[:200])
                print('   (Trash items:', r['nTrash'], ')')
                check(all(r['places'].values()), f'{viewer}: the country and city lists', json.dumps(r['places']))

            emails = {u['id']: u['email'] for u in dump()['users']}
            viewers = [ADMIN, other_super['email']] + [emails[x] for x in [office and office['id'], free and free['id'], 'u-joe'] if x]
            for who in viewers:
                ctx, pg, errs, _ = await open_as(who)
                r = await pg.evaluate(COMPARE, ids)
                menus_same(r, who.split('@')[0])
                check(not errs, f'{who}: no page errors', errs)
                await ctx.close()

            # (with no Creative Director: making someone CD is asked as a plain question)
            cdid = dump()['meta'].get('cdUserId')
            r = act(ADMIN, {'ev': 'cd', 'id': cdid}); check(r.get('ok'), 'setup: no Creative Director now', json.dumps(r)[:200])
            ctx, pg, errs, _ = await open_as(ADMIN)
            r = await pg.evaluate(COMPARE, ['u-joe', cdid])
            menus_same(r, 'haris (no CD)')
            check(any(c['app'] and c['app'].get('okText') == 'Make Creative Director' for c in r['cd']), 'haris (no CD): the make-CD question came up', json.dumps(r['cd'])[:300])
            await ctx.close()

            # ---------- 2. pfSet against the page's saveMe ----------
            for who in [ADMIN, emails['u-joe'], fin_only and fin_only['email']]:
                if not who: continue
                ctx, pg, errs, trashed = await open_as(who)
                await pg.evaluate("""(() => {
                  window.__said = []; window.__pick = null; window.__form = null; window.__date = null; window.__img = null;
                  const t0 = window.toast; window.toast = (m, ...r) => { window.__said.push(String(m)); try { return t0(m, ...r); } catch (e) {} };
                  const nc = NativeMac.call; NativeMac.call = (cmd, a) => cmd === 'pickDate' ? Promise.resolve(window.__date) : cmd === 'me' ? Promise.resolve({}) : nc(cmd, a);
                  const hc = Host.call; Host.call = (cmd, a) => cmd === 'pickImage' ? Promise.resolve({ path: window.__img }) : hc(cmd, a);
                  window.dialog = async () => true;
                  window.formDialog = async ({ validate }) => { const f = { ...window.__form }; const err = validate && validate(f); if (err) { window.__said.push(err); return null; } return f; };
                  window.showMenu = (anchor, items, opts) => { const want = window.__pick; if (want && want.custom != null) { opts.onCustom(want.custom); return; } const it = items.find((x) => x && x.run && x.label === (want && want.label)); if (it) it.run(); else window.__said.push('no such item: ' + (want && want.label)); };
                })()""")
                async def case(page_ev, srv_ev, what, setup=None, want_ok=True):
                    await pg.evaluate("persist(0)"); await pg.wait_for_timeout(1500)
                    pre = dump()
                    pre_path = os.path.join(WORK, 'pre.json'); open(pre_path, 'w').write(json.dumps(pre))
                    mine = node('run.mjs', pre_path, who, json.dumps({'ev': 'pfSet', **srv_ev}))
                    trashed.clear()
                    await pg.evaluate("(s) => { window.__said = []; Object.assign(window, s || {}); }", setup or {})
                    await pg.evaluate("(ev) => __e11Me(ev)", page_ev)
                    await pg.wait_for_timeout(2200)
                    post = dump(); said = await pg.evaluate("window.__said")
                    me0 = next(x for x in pre['users'] if x['email'] == who)
                    quiet = lambda x: {k: v for k, v in (x or {}).items() if k not in ('lastLoginAt', 'lastAlertAt', 'updatedAt')}
                    site = quiet(next(x for x in post['users'] if x['id'] == me0['id']))
                    srv_user = quiet(json.loads(json.dumps(mine['changes'][0]['data'])) if mine.get('ok') and mine['changes'] else me0)
                    d = diff(srv_user, site)
                    check(not d, f'{who.split("@")[0]}: {what} — the same record', '\n   ' + '\n   '.join(d))
                    others = [k for k in ('users', 'tasks', 'meta', 'projects', 'clients') if json.dumps([x for x in (pre[k] if k != 'meta' else [pre[k]]) if not (k == 'users' and x['id'] == me0['id'])], sort_keys=True) != json.dumps([x for x in (post[k] if k != 'meta' else [post[k]]) if not (k == 'users' and x['id'] == me0['id'])], sort_keys=True)]
                    check(not others, f'{who.split("@")[0]}: {what} — nothing else changed', others)
                    if mine.get('ok'): check(mine.get('messages', []) == [m for m in said if m != 'Some changes weren’t allowed'], f'{who.split("@")[0]}: {what} — the same message {mine.get("messages")}', f'page said {said}')
                    else: check(mine.get('error') in said, f'{who.split("@")[0]}: {what} — refused with the page\'s words “{mine.get("error")}”', f'page said {said}')
                    check(bool(mine.get('ok')) == want_ok, f'{who.split("@")[0]}: {what} — {"done" if want_ok else "refused"}', json.dumps(mine)[:300])
                    check(sorted(set(x for x in trashed if x)) == sorted(set(mine.get('filesGone') or [])), f'{who.split("@")[0]}: {what} — the same files to the trash folder', f'page {trashed} server {mine.get("filesGone")}')
                    check(not errs, f'{who.split("@")[0]}: {what} — no page errors', errs); errs.clear()
                    return mine
                cur = lambda: next(x for x in dump()['users'] if x['email'] == who)
                await case({'ev': 'pfName'}, {'field': 'name', 'value': 'Tess Tester'}, 'name', {'__form': {'name': 'Tess Tester'}})
                await case({'ev': 'pfName'}, {'field': 'name', 'value': '   '}, 'an empty name', {'__form': {'name': ''}}, want_ok=False)
                await case({'ev': 'pfCountry'}, {'field': 'country', 'value': 'United Arab Emirates'}, 'country', {'__pick': {'label': 'United Arab Emirates'}})
                await case({'ev': 'pfCity'}, {'field': 'city', 'value': 'Dubai'}, 'city from the list', {'__pick': {'label': 'Dubai'}})
                await case({'ev': 'pfCountry'}, {'field': 'country', 'value': 'Lebanon'}, 'another country (the city cleared)', {'__pick': {'label': 'Lebanon'}})
                await case({'ev': 'pfCity'}, {'field': 'city', 'value': 'Jounieh'}, 'a city typed in', {'__pick': {'custom': 'Jounieh'}})
                await case({'ev': 'pfCity'}, {'field': 'city', 'value': ''}, 'city Not set', {'__pick': {'label': 'Not set'}})
                await case({'ev': 'pfCountry'}, {'field': 'country', 'value': ''}, 'country Not set', {'__pick': {'label': 'Not set'}})
                await case({'ev': 'pfBday'}, {'field': 'bday', 'value': '03-14'}, 'birthday', {'__date': {'ok': True, 'date': '2026-03-14'}})
                await case({'ev': 'pfBday'}, {'field': 'bday', 'value': None}, 'birthday cleared', {'__date': {'ok': True, 'clear': True}})
                s0 = (cur().get('prefs') or {}).get('sound') is not False
                await case({'ev': 'pfSound'}, {'field': 'sound', 'value': not s0}, f'sound {"off" if s0 else "on"}')
                await case({'ev': 'pfSound'}, {'field': 'sound', 'value': s0}, f'sound {"on" if s0 else "off"} again')
                await case({'ev': 'pfNotif', 'k': 'comment'}, {'field': 'notif', 'k': 'comment', 'on': bool(((cur().get('prefs') or {}).get('notifOff') or {}).get('comment'))}, 'a notification type switched')
                await case({'ev': 'pfNotif', 'k': 'comment'}, {'field': 'notif', 'k': 'comment', 'on': bool(((cur().get('prefs') or {}).get('notifOff') or {}).get('comment'))}, 'and back')
                d0 = bool((cur().get('prefs') or {}).get('digestOff'))
                await case({'ev': 'digest'}, {'field': 'digest', 'on': d0}, f'morning summary {"on" if d0 else "off"}')
                await case({'ev': 'digest'}, {'field': 'digest', 'on': not d0}, 'morning summary back')
                uid = cur()['id']
                await case({'ev': 'pfPhoto'}, {'field': 'avatar', 'value': f'attachments/_avatars/{uid}-t1.jpg'}, 'a photo', {'__img': f'attachments/_avatars/{uid}-t1.jpg'})
                await case({'ev': 'pfPhoto'}, {'field': 'avatar', 'value': f'attachments/_avatars/{uid}-t2.jpg'}, 'another photo (the old one trashed)', {'__img': f'attachments/_avatars/{uid}-t2.jpg'})
                await case({'ev': 'pfPhotoOff'}, {'field': 'avatar', 'value': None}, 'the photo removed')
                await ctx.close()
            await b.close()

        # ---------- 3. through the route: each role's own record; nobody else's; the switch ----------
        reset()
        people = dump()['users']
        roles_seen = set()
        for u in people:
            if u.get('active') is False or u['role'] in roles_seen: continue
            roles_seen.add(u['role'])
            for ev in [{'field': 'name', 'value': (u.get('name') or 'X') + ' Q'}, {'field': 'country', 'value': 'Lebanon'}, {'field': 'city', 'value': 'Beirut'}, {'field': 'bday', 'value': '12-31'},
                       {'field': 'sound', 'value': False}, {'field': 'notif', 'k': 'due', 'on': False}, {'field': 'digest', 'on': False}, {'field': 'avatar', 'value': f'attachments/_avatars/{u["id"]}-r.jpg'}]:
                r = act(u['email'], {'ev': 'pfSet', **ev})
                check(r.get('ok') is True and len(r.get('changes') or []) == 1 and r['changes'][0]['id'] == u['id'], f'route: {u["role"]} sets their {ev["field"]}', json.dumps(r)[:300])
            x = next(y for y in dump()['users'] if y['id'] == u['id'])
            check(x.get('bday') == '12-31' and x.get('city') == 'Beirut' and x['prefs'].get('sound') is False and x['prefs']['notifOff'].get('due') and x['prefs'].get('digestOff') is True and x.get('avatar', '').endswith('-r.jpg'), f'route: {u["role"]}: all saved', json.dumps({k: x.get(k) for k in ('name', 'bday', 'city', 'prefs', 'avatar')})[:300])
        joe0 = next(y for y in dump()['users'] if y['id'] == 'u-joe')
        r = act(ADMIN, {'ev': 'pfSet', 'id': 'u-joe', 'userId': 'u-joe', 'field': 'name', 'value': 'Not Joe'})
        joe1 = next(y for y in dump()['users'] if y['id'] == 'u-joe')
        check(joe0 == joe1 and r.get('ok') and all(c['id'] != 'u-joe' for c in r.get('changes') or []), 'route: someone else\'s record can\'t be named (only your own changes)', json.dumps(r)[:300])
        r = act(ADMIN, {'ev': 'pfSet', 'field': 'bday', 'value': '13-40'}); check(r.get('ok') is False and r.get('status') == 400, 'route: a wrong birthday refused', json.dumps(r)[:200])
        r = act(ADMIN, {'ev': 'pfSet', 'field': 'avatar', 'value': 'Clients/secret/plan.pdf'}); check(r.get('ok') is False, 'route: a photo that isn\'t an uploaded photo refused', json.dumps(r)[:200])
        r = act(ADMIN, {'ev': 'pfSet', 'field': 'role', 'value': 'admin'}); check(r.get('ok') is False, 'route: no other field', json.dumps(r)[:200])
        con = sqlite3.connect(DBFILE, timeout=10); con.execute("insert or replace into kv (key, value) values ('app-act-profile', 'off')"); con.commit(); con.close()
        r = act(ADMIN, {'ev': 'pfSet', 'field': 'sound', 'value': True}); check(r.get('off') is True, 'route: kv app-act-profile off → back to the page', json.dumps(r)[:200])
    finally:
        srv.terminate()
        import shutil; shutil.rmtree(DATA, ignore_errors=True); shutil.rmtree(WORK, ignore_errors=True)   # (the data copies fill the disk)
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
