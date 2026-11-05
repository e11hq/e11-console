"""Part B step 3: the app's Content plans, Trash and Team actions on the server (server/src/appact-other.js) — for each
one, the same starting data done twice: once by the website's own handler in the page (phone.js NativeMe __e11Me, as
the iPhone app sends it, signed in as the right person; what it saved read back from the server's database), once by
the server's handler (a Node run over the same records, before anything was saved). The records changed, the
notifications, activity lines, logs, the answer / error and the message must be the same (generated ids and times
aside); a file deleted for good: the same files sent to the server's trash folder."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json, re
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT = 18345; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
AMELIA, CARINE, AREEJ = 'amelia@e11-digital.com', 'carine@e11-digital.com', 'areej@e11-digital.com'
DATA = tempfile.mkdtemp(); DBFILE = os.path.join(DATA, 'db', 'e11.sqlite'); WORK = tempfile.mkdtemp()

# the database as it is now (every record), and the server's handler run over a copy of it
DUMP = """import { openStore } from %s; const s = openStore(process.argv[2]); process.stdout.write(JSON.stringify(s.snapshot().data));""" % json.dumps(ROOT + '/server/src/store.js')
RUN = """import fs from 'node:fs'; import { createOtherActs } from %s;
const [pre, who, ev] = [JSON.parse(fs.readFileSync(process.argv[2], 'utf8')), process.argv[3], JSON.parse(process.argv[4])];
const copy = (v) => (v == null ? null : JSON.parse(JSON.stringify(v)));
const store = { get: (k, id) => copy(k === 'meta' ? (id === 'main' ? pre.meta : null) : (pre[k] || []).find((x) => String(x.id) === String(id))), list: (k) => copy(pre[k] || []) };
const acts = createOtherActs({ store, now: () => Date.now(), ownerEmail: %s });
const u = pre.users.find((x) => x.email === who);
const { ev: name, ...body } = ev;
process.stdout.write(JSON.stringify(acts[name](u, body)));""" % (json.dumps(ROOT + '/server/src/appact-other.js'), json.dumps(ADMIN))
open(os.path.join(WORK, 'dump.mjs'), 'w').write(DUMP); open(os.path.join(WORK, 'run.mjs'), 'w').write(RUN)

def node(script, *args):
    r = subprocess.run(['node', '--no-warnings', os.path.join(WORK, script), *args], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr[-2000:])
    return json.loads(r.stdout)

def dump(): return node('dump.mjs', DBFILE)

ISO = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$')
def norm(v, new_ids):
    if isinstance(v, str):
        if ISO.match(v): return '<time>'
        return '<new>' if v in new_ids else v
    if isinstance(v, list): return [norm(x, new_ids) for x in v]
    if isinstance(v, dict):
        out = {}
        for k, x in v.items():
            if k == 'id' and 'actor' in v: continue                 # an activity line's own id
            if k == 'at' and isinstance(x, str) and ISO.match(x): out[k] = '<time>'; continue
            out[k] = norm(x, new_ids)
        return out
    return v

def index(data):
    out = {}
    for k, v in data.items():
        if k == 'meta': out[('meta', 'main')] = v
        else:
            for x in v: out[(k, str(x['id']))] = x
    return out

def diff(pre, post):
    a, b = index(pre), index(post)
    new_ids = {i for (k, i) in b if (k, i) not in a}
    rows = []
    for key in sorted(set(a) | set(b)):
        x, y = a.get(key), b.get(key)
        if json.dumps(x, sort_keys=True) == json.dumps(y, sort_keys=True): continue
        rows.append(json.dumps([key[0], '<new>' if key[1] in new_ids else key[1], None if y is None else norm(y, new_ids)], sort_keys=True))
    return sorted(rows)

def applied(pre, changes):
    post = json.loads(json.dumps(pre))
    for ch in changes:
        k, i = ch['kind'], str(ch['id'])
        if k == 'meta': post['meta'] = ch['data']; continue
        lst = post.setdefault(k, [])
        j = next((n for n, x in enumerate(lst) if str(x['id']) == i), None)
        if ch.get('del'):
            if j is not None: lst.pop(j)
        elif j is None: lst.append(ch['data'])
        else: lst[j] = ch['data']
    return post

def drop_undefined(v):
    return json.loads(json.dumps(v))

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
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE + '/api/health'); break
            except Exception: time.sleep(0.1)
        reset()
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            pages = {}
            async def close_all():
                for ctx, *_ in pages.values(): await ctx.close()
                pages.clear()
            async def page_of(who):
                if who in pages: return pages[who]
                # (one person's page at a time: another's open page saves its own things — their prefs — meanwhile)
                await close_all()
                ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, base_url=BASE, timezone_id='Asia/Dubai')
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': who, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                trashed = []
                pg.on('request', lambda r: trashed.extend(json.loads(r.post_data or '{}').get('paths', [])) if r.url.endswith('/api/host/trashMany') else None)
                await pg.goto('/'); await pg.wait_for_timeout(4500)
                # the app's bridge answered; the page's questions answered yes (the app asks them before it sends the action)
                await pg.evaluate("""(() => {
                  window.__said = []; window.__answers = {}; window.__pick = null; window.__menu = null;
                  NativeMac.call = (cmd, a) => { if (cmd === 'me' && a && a.rid) window.__answers[a.rid] = a; if (cmd === 'me' && a && a.toast) window.__said.push(a.toast.t); return Promise.resolve({}); };
                  const t0 = window.toast; window.toast = (m, ...r) => { window.__said.push(String(m)); try { return t0(m, ...r); } catch (e) {} };
                  window.dialog = async () => true;
                  window.choiceDialog = async ({ choices }) => { const c = choices.find((x) => x.value === window.__pick); return c ? c.value : null; };
                  window.showMenu = (anchor, items) => { window.__menu = items; };
                  window.formDialog = async ({ validate }) => { const f = { ...window.__form }; const err = validate && validate(f); if (err) { window.__said.push(err); return null; } return f; };
                })()""")
                pages[who] = (ctx, pg, errs, trashed)
                return pages[who]
            async def settle(pg):
                await pg.evaluate("persist(0)"); await pg.wait_for_timeout(1800)
            async def case(who, ev, what, pick=None, menu=None, want_ok=True, form=None):
                ctx, pg, errs, trashed = await page_of(who)
                await settle(pg)
                pre = dump()
                pre_path = os.path.join(WORK, 'pre.json'); open(pre_path, 'w').write(json.dumps(pre))
                mine = node('run.mjs', pre_path, who, json.dumps(ev))
                trashed.clear()
                await pg.evaluate("([p, f]) => { window.__said = []; window.__answers = {}; window.__pick = p; window.__form = f; }", [pick, form])
                if menu is None:
                    await pg.evaluate("(ev) => __e11Me({ ...ev, rid: 'x' })", ev)
                else:
                    # touch and hold the person: the page's own menu, then its item
                    res = await pg.evaluate("""([id, re]) => { __e11Me({ ev: 'member', id }); const items = window.__menu || []; window.__menu = null;
                      const it = items.find((x) => x && x.run && new RegExp(re).test((x.html || x.label || '').replace(/<[^>]+>/g, ''))); if (!it) return 'no such item: ' + re + ' in ' + items.map((x) => x && (x.label || (x.html || '').replace(/<[^>]+>/g, ''))).join(' | ');
                      Promise.resolve(it.run()); return 'ran'; }""", [ev['id'], menu])
                    if res != 'ran': check(False, f'{what}: the page\'s menu item', res); return
                await pg.wait_for_timeout(2600)
                post = dump()
                page_ans = await pg.evaluate("window.__answers.x || null")
                said = await pg.evaluate("window.__said")
                site = diff(pre, post)
                # (the person's own page saving their own things meanwhile — a pref, the last sign-in — isn't the action)
                me = next(x for x in pre['users'] if x['email'] == who)
                me2 = next((x for x in post['users'] if x['id'] == me['id']), None)
                quiet = lambda x: {k: v for k, v in (x or {}).items() if k not in ('prefs', 'lastLoginAt', 'lastAlertAt')}
                if me2 and quiet(me) == quiet(me2): site = [r for r in site if not r.startswith(json.dumps(['users', me['id']])[:-1])]
                # (Remove from team: the website also changes completed tasks, which the server refuses — they're locked —
                #  yet its Inbox updates about them are saved; the server's handler leaves both out)
                if ev.get('act') == 'remove':
                    changed_tasks = {json.loads(r)[1] for r in site if r.startswith('["tasks"')}
                    site = [r for r in site if not (r.startswith('["notifications"') and json.loads(r)[2].get('taskId') not in changed_tasks)]
                if mine.get('ok'):
                    srv_rows = diff(pre, drop_undefined(applied(pre, mine['changes'])))
                else: srv_rows = []
                same_changes = site == srv_rows
                only_site = [r for r in site if r not in srv_rows]; only_srv = [r for r in srv_rows if r not in site]
                check(same_changes, f'{what}: the same records changed ({len(site)})', '\n   only on the website: ' + '\n            '.join(only_site) + '\n   only on the server:  ' + '\n            '.join(only_srv))
                # the answer (plans: the page answers ok / error) or, for the others, the toast
                if page_ans is not None:
                    want = {'ok': page_ans.get('ok'), 'error': page_ans.get('error')}
                    got = {'ok': mine.get('ok'), 'error': mine.get('error')}
                    check(want == got, f'{what}: the same answer {want}', f'server: {got}')
                said = [m for m in said if m != 'Some changes weren’t allowed']
                if mine.get('ok'):
                    check(mine.get('messages', []) == said, f'{what}: the same message {mine.get("messages")}', f'page said {said}')
                elif page_ans is None:
                    check(mine.get('error') in said, f'{what}: refused with the page\'s words “{mine.get("error")}”', f'page said {said}')
                check(bool(mine.get('ok')) == want_ok, f'{what}: {"done" if want_ok else "refused"} as expected', json.dumps(mine)[:300])
                if 'filesGone' in mine or trashed:
                    check(sorted(set(trashed)) == sorted(set(mine.get('filesGone') or [])), f'{what}: the same files to the trash folder ({len(trashed)})', f'\n   website: {sorted(set(trashed))}\n   server:  {sorted(set(mine.get("filesGone") or []))}')
                check(not errs, f'{what}: no page errors', errs); errs.clear()
                return mine

            # ---------- content plans: KOREA 360 waits for the Social Manager (amelia); HRE for both, with 2 posts flagged
            await case(AMELIA, {'ev': 'plApprove', 'plan': 'pl-smp-p-hre'}, 'SM approves HRE while 2 posts are marked changes', want_ok=False)
            await case(AMELIA, {'ev': 'plReview', 'plan': 'pl-smp-p-korea', 'post': None, 'state': 'ok'}, 'a post that isn\'t there', want_ok=False)
            snap = dump(); korea = next(p for p in snap['plans'] if p['id'] == 'pl-smp-p-korea'); posts = [x['id'] for x in korea['posts']]
            await case(AMELIA, {'ev': 'plReview', 'plan': 'pl-smp-p-korea', 'post': posts[0], 'state': 'ok'}, 'SM: a post Looks good')
            await case(AMELIA, {'ev': 'plReview', 'plan': 'pl-smp-p-korea', 'post': posts[1], 'state': 'changes', 'note': '  '}, 'SM: Ask for changes without a note', want_ok=False)
            await case(AMELIA, {'ev': 'plReview', 'plan': 'pl-smp-p-korea', 'post': posts[1], 'state': 'changes', 'note': 'Make the logo bigger'}, 'SM: a post Ask for changes with a note')
            await case(AMELIA, {'ev': 'plApprove', 'plan': 'pl-smp-p-korea'}, 'SM approves while a post is marked changes', want_ok=False)
            await case(AMELIA, {'ev': 'plReview', 'plan': 'pl-smp-p-korea', 'post': posts[1], 'state': ''}, 'SM: the mark taken off')
            await case(CARINE, {'ev': 'plApprove', 'plan': 'pl-smp-p-korea'}, 'the CD approves one sent only to the SM', want_ok=False)
            await case(AMELIA, {'ev': 'plApprove', 'plan': 'pl-smp-p-korea'}, 'SM approves the skeleton')
            await case(AMELIA, {'ev': 'plBack', 'plan': 'pl-smp-p-korea', 'note': 'x'}, 'sent back once approved', want_ok=False)
            await case(CARINE, {'ev': 'plReview', 'plan': 'pl-smp-p-hre', 'post': next(p for p in snap['plans'] if p['id'] == 'pl-smp-p-hre')['posts'][0]['id'], 'state': 'changes', 'note': 'Shorter copy'}, 'CD: a post Ask for changes on HRE')
            await case(CARINE, {'ev': 'plBack', 'plan': 'pl-smp-p-hre', 'note': ''}, 'CD sends HRE back with only its flagged posts')
            # ---------- the Trash (the owner) ----------
            await case(ADMIN, {'ev': 'trRestore', 'id': 'tr-smp-task'}, 'Trash: a task restored')
            await case(ADMIN, {'ev': 'trRestore', 'id': 'tr-smp-comment'}, 'Trash: a comment restored')
            await case(ADMIN, {'ev': 'trRestore', 'id': 'tr-smp-file'}, 'Trash: a Client Assets file restored')
            # ---------- the Team (the owner): the CD switch, a person's menu, Add member ----------
            await case(ADMIN, {'ev': 'cd', 'id': 'u-karim'}, 'CD switched off (no CD now)')
            await case(ADMIN, {'ev': 'cd', 'id': 'u-maya'}, 'someone made CD (no CD before)')
            await case(ADMIN, {'ev': 'cd', 'id': 'u-karim', 'choice': 'acting'}, 'Acting CD while the CD is away', pick='acting')
            await case(ADMIN, {'ev': 'cd', 'id': 'u-karim'}, 'the Acting CD switched off (the CD is back)')
            await case(ADMIN, {'ev': 'cd', 'id': 'u-karim', 'choice': 'cd'}, 'the CD replaced', pick='cd')
            await case(ADMIN, {'ev': 'member', 'id': 'u-joe', 'act': 'role', 'role': 'social'}, 'a role changed', menu='^Social$')
            await case(ADMIN, {'ev': 'member', 'id': 'u-joe', 'act': 'socialMgr'}, 'made Social Manager', menu='^Social Manager')
            await case(ADMIN, {'ev': 'member', 'id': 'u-sara', 'act': 'admin'}, 'Super Admin rights on', menu='^Super Admin rights')
            await case(ADMIN, {'ev': 'member', 'id': 'u-sara', 'act': 'fin', 'fin': 'viewer'}, 'Finance access', menu='^Finance Viewer')
            await case(ADMIN, {'ev': 'member', 'id': 'u-ali', 'act': 'remove'}, 'removed from the team (unassigned)', menu='^Remove from team')
            await case(ADMIN, {'ev': 'member', 'id': 'u-ali', 'act': 'restore'}, 'access restored', menu='^Restore access')
            nm = {'name': 'Sara Khan', 'email': 'Sara.Khan@e11-digital.com', 'role': 'am', 'admin': 'yes', 'fin': 'viewer'}
            await case(ADMIN, {'ev': 'addMember', **nm}, 'Add team member', form=nm)
            await case(ADMIN, {'ev': 'addMember', **nm}, 'Add team member: already on the team', form=nm, want_ok=False)
            await close_all()

            # ---------- fresh sample: send back with a note; an Account Manager restores; delete forever; empty ----------
            reset()
            await case(AMELIA, {'ev': 'plBack', 'plan': 'pl-smp-p-korea', 'note': ''}, 'sent back with no note and nothing flagged', want_ok=False)
            await case(AMELIA, {'ev': 'plBack', 'plan': 'pl-smp-p-korea', 'note': 'Week 2 needs a reel\nand a story'}, 'SM sends back with a note')
            await case(AREEJ, {'ev': 'trRestore', 'id': 'tr-smp-file'}, 'Trash: an Account Manager restores a Client Assets file')
            await case(AREEJ, {'ev': 'trForever', 'id': 'tr-smp-task'}, 'Trash: an Account Manager can\'t delete forever', want_ok=False)
            await case(ADMIN, {'ev': 'trForever', 'id': 'tr-smp-task'}, 'Trash: a task deleted forever (its files)')
            await case(ADMIN, {'ev': 'trEmpty'}, 'Trash: emptied')
            await close_all()
            await b.close()

        # ---------- through the server's own route (POST /api/app/act): every change passes the person's rights ----------
        reset()
        def act(who, ev):
            req = urllib.request.Request(BASE + '/api/app/act', method='POST', data=json.dumps({**ev, 'op': None}).encode(), headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
            return json.loads(urllib.request.urlopen(req).read())
        snap = dump(); korea = next(p for p in snap['plans'] if p['id'] == 'pl-smp-p-korea')
        for who, ev, what in [
            (AMELIA, {'ev': 'plReview', 'plan': 'pl-smp-p-korea', 'post': korea['posts'][0]['id'], 'state': 'changes', 'note': 'Brighter'}, 'SM marks a post'),
            (AMELIA, {'ev': 'plBack', 'plan': 'pl-smp-p-korea', 'note': ''}, 'SM sends it back'),
            (CARINE, {'ev': 'plReview', 'plan': 'pl-smp-p-hre', 'post': next(p for p in snap['plans'] if p['id'] == 'pl-smp-p-hre')['posts'][1]['id'], 'state': ''}, 'the CD takes a mark off'),
            (CARINE, {'ev': 'plReview', 'plan': 'pl-smp-p-hre', 'post': next(p for p in snap['plans'] if p['id'] == 'pl-smp-p-hre')['posts'][3]['id'], 'state': 'ok'}, 'the CD marks one Looks good'),
            (CARINE, {'ev': 'plApprove', 'plan': 'pl-smp-p-hre'}, 'the CD approves'),
            (AREEJ, {'ev': 'trRestore', 'id': 'tr-smp-task'}, 'an Account Manager restores a task'),
            (AREEJ, {'ev': 'trRestore', 'id': 'tr-smp-comment'}, 'an Account Manager restores a comment'),
            (AREEJ, {'ev': 'trRestore', 'id': 'tr-smp-file'}, 'an Account Manager restores a file'),
            (ADMIN, {'ev': 'cd', 'id': 'u-maya', 'choice': 'acting'}, 'the owner: an Acting CD'),
            (ADMIN, {'ev': 'member', 'id': 'u-ali', 'act': 'remove'}, 'the owner removes someone'),
            (ADMIN, {'ev': 'member', 'id': 'u-joe', 'act': 'role', 'role': 'freelancer'}, 'the owner makes someone a freelancer'),
            (ADMIN, {'ev': 'member', 'id': 'u-joe', 'act': 'clients', 'projectIds': ['p-kia', 'p-gm']}, 'the clients a freelancer sees'),
            (ADMIN, {'ev': 'addMember', 'email': 'new.person@e11-digital.com', 'role': 'production'}, 'the owner adds someone'),
        ]:
            r = act(who, ev)
            check(r.get('ok') is True and len(r.get('changes') or []) > 0, f'route: {what} — saved ({len(r.get("changes") or [])} records)', json.dumps(r)[:400])
        # (the Trash is emptied: something to delete forever first)
        urllib.request.urlopen(urllib.request.Request(BASE + '/api/push', method='POST', data=json.dumps({'client': 't', 'changes': [{'kind': 'trash', 'id': 'tr-test-1', 'data': {'id': 'tr-test-1', 'type': 'comment', 'deletedAt': '2026-11-01T00:00:00.000Z', 'deletedBy': 'u-lina', 'data': {'taskId': 'nope', 'comments': []}}}]}).encode(), headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'})).read()
        r = act(AREEJ, {'ev': 'trEmpty'}); check(r.get('ok') is False, 'route: an Account Manager can\'t empty the Trash', json.dumps(r)[:300])
        r = act(ADMIN, {'ev': 'trEmpty'}); check(r.get('ok') is True and dump()['trash'] == [], 'route: the owner empties the Trash', json.dumps(r)[:300])
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
