"""Part B step 5: the app's Client Assets actions on the server (server/src/appact-assets.js) — for each one, the same
starting data done twice: once by the website's own handler in the page (phone.js NativeAssets __e11Assets, as the
iPhone app sends it, signed in as the right person; what it saved read back from the server's database), once by the
server's handler (a Node run over the same records, before anything was saved). The records changed (clients, projects,
Trash entries, Inbox updates), the answer (ok / error, a new id, gone), the NAS folders made (Host makeDir) and the files
sent to the trash folder must be the same (generated ids and times aside) — for the owner (Super Admin), an Office Admin,
an Account Manager, Production, a freelancer with and one without the client, and Finance. Then through the route
(POST /api/app/act): the person's rights, the folders on disk, kv 'app-act-assets' = 'off', and the logo made from a
file put in a new client's Logos folder (transparent PNG, JPEG, SVG) next to the one the website's canvas makes."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json, re, base64, io, shutil, sqlite3
from playwright.async_api import async_playwright
from PIL import Image, ImageDraw
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT = 18347; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
AREEJ, YOUSEF, SAM, RANIA = 'areej@e11-digital.com', 'yousef@e11-digital.com', 'sam.rivera.design@gmail.com', 'rania.finance@e11-digital.com'
OA, FREE2 = 'office@e11-digital.com', 'free.two@gmail.com'   # (added below: an Office Admin without Super Admin rights; a freelancer with no clients)
DATA = tempfile.mkdtemp(); DBFILE = os.path.join(DATA, 'db', 'e11.sqlite'); WORK = tempfile.mkdtemp(); FILES = os.path.join(DATA, 'files')

DUMP = """import { openStore } from %s; const s = openStore(process.argv[2]); process.stdout.write(JSON.stringify(s.snapshot().data));""" % json.dumps(ROOT + '/server/src/store.js')
RUN = """import fs from 'node:fs'; import { createAssetActs } from %s;
const [pre, who, ev] = [JSON.parse(fs.readFileSync(process.argv[2], 'utf8')), process.argv[3], JSON.parse(process.argv[4])];
const copy = (v) => (v == null ? null : JSON.parse(JSON.stringify(v)));
const store = { get: (k, id) => copy(k === 'meta' ? (id === 'main' ? pre.meta : null) : (pre[k] || []).find((x) => String(x.id) === String(id))), list: (k) => copy(pre[k] || []), rev: () => 1, kv: { get: () => null, set: () => {} } };
const acts = createAssetActs({ store, now: () => Date.now() });
const u = pre.users.find((x) => x.email === who);
const { ev: name, ...body } = ev;
const r = acts['ca' + name[0].toUpperCase() + name.slice(1)](u, body);
process.stdout.write(JSON.stringify({ ...r, later: undefined }));""" % json.dumps(ROOT + '/server/src/appact-assets.js')
open(os.path.join(WORK, 'dump.mjs'), 'w').write(DUMP); open(os.path.join(WORK, 'run.mjs'), 'w').write(RUN)

def node(script, *args):
    r = subprocess.run(['node', '--no-warnings', os.path.join(WORK, script), *args], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr[-2000:])
    return json.loads(r.stdout)

def dump(): return node('dump.mjs', DBFILE)

ISO = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$')
IDISH = re.compile(r'^(cl|cf|tr)-[0-9a-z]{8,}$')
def norm(v, new_ids):
    if isinstance(v, str):
        if ISO.match(v): return '<time>'
        return '<new>' if v in new_ids else v
    if isinstance(v, list): return [norm(x, new_ids) for x in v]
    if isinstance(v, dict):
        out = {}
        for k, x in v.items():
            if k in ('at', 'addedAt', 'createdAt', 'deletedAt') and isinstance(x, str) and ISO.match(x): out[k] = '<time>'; continue
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

def new_ids_of(a, b):
    """every id made by the action: new records', and new folders' / files' inside a client"""
    ids = {i for (k, i) in b if (k, i) not in a}
    inner = lambda recs: {x['id'] for (k, i), c in recs.items() if k == 'clients' for f in c.get('folders', []) for x in [f] + f.get('files', [])}
    return ids | (inner(b) - inner(a))

def diff(pre, post):
    a, b = index(pre), index(post)
    new_ids = new_ids_of(a, b)
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

# logo sources: a dark logo on a transparent background, a photo-like JPEG with its own background, an SVG
def sources():
    t = Image.new('RGBA', (480, 240), (0, 0, 0, 0)); d = ImageDraw.Draw(t)
    d.rounded_rectangle((40, 50, 440, 190), 30, fill=(20, 30, 90, 255)); d.ellipse((70, 80, 150, 160), fill=(240, 180, 20, 255))
    b1 = io.BytesIO(); t.save(b1, 'PNG')
    j = Image.new('RGB', (360, 300), (230, 110, 40)); d = ImageDraw.Draw(j); d.ellipse((90, 60, 270, 240), fill=(255, 255, 255)); d.rectangle((150, 120, 210, 180), fill=(30, 30, 30))
    b2 = io.BytesIO(); j.save(b2, 'JPEG', quality=95)
    svg = b'<svg xmlns="http://www.w3.org/2000/svg" width="300" height="120" viewBox="0 0 300 120"><rect x="10" y="10" width="280" height="100" rx="18" fill="#e8e8e8"/><circle cx="60" cy="60" r="32" fill="#ffffff"/></svg>'
    return [('Brand mark.png', b1.getvalue()), ('Photo logo.jpg', b2.getvalue()), ('Vector logo.svg', svg)]

async def main():
    subprocess.run(['fuser', '-k', f'{PORT}/tcp'], stderr=subprocess.DEVNULL)
    env = {**os.environ, 'DATA_DIR': DATA, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': ROOT + '/web', 'APP_VERSION': '1.6.1-test.1'}
    srv = subprocess.Popen(['node', ROOT + '/server/src/index.js'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ok = []
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    def post(path, who, body):
        req = urllib.request.Request(BASE + path, method='POST', data=json.dumps(body).encode(), headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
        return json.loads(urllib.request.urlopen(req).read())
    def reset():
        urllib.request.urlopen(urllib.request.Request(BASE + '/api/me', headers={'X-Dev-Email': ADMIN}))
        post('/api/sample/reset', ADMIN, {})
        # the two extra people (as an Admin adds them)
        post('/api/push', ADMIN, {'client': 't', 'changes': [
            {'kind': 'users', 'id': 'u-t-oa', 'data': {'id': 'u-t-oa', 'email': OA, 'name': 'Olivia Office', 'role': 'office_admin', 'active': True, 'setup': True, 'prefs': {}}},
            {'kind': 'users', 'id': 'u-t-free2', 'data': {'id': 'u-t-free2', 'email': FREE2, 'name': 'Fred Free', 'role': 'freelancer', 'projectIds': [], 'active': True, 'setup': True, 'prefs': {}}}]})
    def act(who, ev): return post('/api/app/act', who, {**ev, 'op': None})
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
                await close_all()
                ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, base_url=BASE, timezone_id='Asia/Dubai')
                await ctx.add_cookies([{'name': 'e11_dev_email', 'value': who, 'url': BASE}])
                pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
                host = {'trashMany': [], 'makeDir': []}
                def on_req(r):
                    for k in host:
                        if r.url.endswith('/api/host/' + k):
                            body = json.loads(r.post_data or '{}')
                            host[k].extend(body.get('paths', []) if k == 'trashMany' else [body.get('path')])
                pg.on('request', on_req)
                await pg.goto('/'); await pg.wait_for_timeout(4500)
                await pg.evaluate("""(() => {
                  window.__answers = {};
                  const n0 = NativeMac.call;
                  NativeMac.call = (cmd, a) => { if (cmd === 'assets' && a && a.rid) { window.__answers[a.rid] = a; return Promise.resolve({}); } if (cmd === 'assets') return Promise.resolve({}); return n0 ? n0(cmd, a) : Promise.resolve({}); };
                })()""")
                pages[who] = (ctx, pg, errs, host)
                return pages[who]
            async def case(who, ev, what, want_ok=True, page_crash=False):
                ctx, pg, errs, host = await page_of(who)
                await pg.evaluate("persist(0)"); await pg.wait_for_timeout(1500)
                pre = dump()
                pre_path = os.path.join(WORK, 'pre.json'); open(pre_path, 'w').write(json.dumps(pre))
                mine = node('run.mjs', pre_path, who, json.dumps(ev))
                for v in host.values(): v.clear()
                await pg.evaluate("() => { window.__answers = {}; }")
                await pg.evaluate("(ev) => __e11Assets({ ...ev, rid: 'x' })", ev)
                await pg.wait_for_timeout(2600)
                after = dump()
                page_ans = await pg.evaluate("window.__answers.x || null") or {}
                site = diff(pre, after)
                # (the person's own page saving their own things meanwhile — a pref, the last sign-in — isn't the action)
                me = next(x for x in pre['users'] if x['email'] == who)
                site = [r for r in site if not r.startswith(json.dumps(['users', me['id']])[:-1])]
                srv_rows = diff(pre, applied(pre, mine['changes'])) if mine.get('ok') else []
                only_site = [r for r in site if r not in srv_rows]; only_srv = [r for r in srv_rows if r not in site]
                check(site == srv_rows, f'{what}: the same records changed ({len(site)})', '\n   only on the website: ' + '\n            '.join(only_site) + '\n   only on the server:  ' + '\n            '.join(only_srv))
                want = {'ok': page_ans.get('ok'), 'error': page_ans.get('error'), 'id': bool(page_ans.get('id')), 'gone': bool(page_ans.get('gone'))}
                ans = mine.get('answer') or {}
                got = {'ok': mine.get('ok'), 'error': mine.get('error') if not mine.get('ok') else None, 'id': bool(ans.get('id')), 'gone': bool(ans.get('gone'))}
                if page_crash:
                    # (the page itself fails here — its answer is a script error — so only the refusal is compared)
                    check(want['ok'] is False and got['ok'] is False and got['error'] == 'Your role can’t do this', f'{what}: refused (the page: “{want["error"]}”; the server: “{got["error"]}”)')
                else: check(want == got, f'{what}: the same answer {want}', f'server: {got}')
                if ans.get('id'):
                    # (the new client's / folder's id is the one the page answered with on its side: both new, both saved)
                    check(page_ans.get('id') in json.dumps(after) and ans['id'] not in json.dumps(after), f'{what}: answer.id is the new record', f"page {page_ans.get('id')} server {ans.get('id')}")
                check(sorted(host['makeDir']) == sorted(mine.get('dirs') or []), f'{what}: the same NAS folders made {sorted(mine.get("dirs") or [])}', f'website: {sorted(host["makeDir"])}')
                check(sorted(set(host['trashMany'])) == sorted(set(mine.get('filesGone') or [])), f'{what}: the same files to the trash folder ({len(host["trashMany"])})', f'\n   website: {sorted(set(host["trashMany"]))}\n   server:  {sorted(set(mine.get("filesGone") or []))}')
                check(bool(mine.get('ok')) == want_ok, f'{what}: {"done" if want_ok else "refused"} as expected', json.dumps(mine)[:300])
                check(not errs, f'{what}: no page errors', errs); errs.clear()
                return mine

            snap = dump()
            cl = lambda cid: next(c for c in dump()['clients'] if c['id'] == cid)
            fo = lambda cid, name: next(f for f in cl(cid)['folders'] if f['name'] == name)
            # ---------- the owner (Super Admin) ----------
            await case(ADMIN, {'ev': 'addClient', 'name': 'ford AND lincoln.'}, 'owner: a client that\'s already there', want_ok=False)
            await case(ADMIN, {'ev': 'addClient', 'name': '   '}, 'owner: a client with no name', want_ok=False)
            await case(ADMIN, {'ev': 'addClient', 'name': '  Emaar   Properties '}, 'owner: + New client (four folders)')
            await case(ADMIN, {'ev': 'newFolder', 'client': 'cl-p-kia', 'name': 'Campaign 2027'}, 'owner: a folder on the client\'s page')
            await case(ADMIN, {'ev': 'newFolder', 'client': 'cl-p-kia', 'parent': 'cf-p-kia-files', 'name': ' Ramadan '}, 'owner: a folder inside Files')
            await case(ADMIN, {'ev': 'newFolder', 'client': 'cl-p-kia', 'parent': 'cf-p-kia-files', 'name': 'q4 family cars campaign'}, 'owner: a folder named as another', want_ok=False)
            await case(ADMIN, {'ev': 'newFolder', 'client': 'cl-p-kia', 'parent': 'cf-p-kia-logos', 'name': 'x'}, 'owner: a folder inside Logos', want_ok=False)
            await case(ADMIN, {'ev': 'newFolder', 'client': 'cl-p-deepal', 'parent': 'cf-final-smp-cu-86eyw0wru', 'name': 'x'}, 'owner: a folder inside final files', want_ok=False)
            await case(ADMIN, {'ev': 'newFolder', 'client': 'cl-p-kia', 'parent': 'cf-p-kia-files', 'name': ''}, 'owner: a folder with no name', want_ok=False)
            # (five levels inside Files, then no more)
            parent = 'cf-p-kia-q4familycarscampaign'
            for lv in ['Level 2', 'Level 3', 'Level 4']:
                r = await case(ADMIN, {'ev': 'newFolder', 'client': 'cl-p-kia', 'parent': parent, 'name': lv}, f'owner: {lv} inside Files')
                parent = fo('cl-p-kia', lv)['id']
            await case(ADMIN, {'ev': 'newFolder', 'client': 'cl-p-kia', 'parent': parent, 'name': 'Level 5'}, 'owner: the 5th level inside Files')
            await case(ADMIN, {'ev': 'newFolder', 'client': 'cl-p-kia', 'parent': fo('cl-p-kia', 'Level 5')['id'], 'name': 'Level 6'}, 'owner: a 6th level', want_ok=False)
            await case(ADMIN, {'ev': 'renameFolder', 'client': 'cl-p-kia', 'folder': 'cf-p-kia-q4familycarscampaign', 'name': 'Q4 Family Cars 2026'}, 'owner: a folder renamed')
            await case(ADMIN, {'ev': 'renameFolder', 'client': 'cl-p-kia', 'folder': 'cf-p-kia-q4familycarscampaign', 'name': 'ramadan'}, 'owner: renamed as another', want_ok=False)
            await case(ADMIN, {'ev': 'renameFolder', 'client': 'cl-p-deepal', 'folder': 'cf-final-smp-cu-86eyw0wru', 'name': 'x'}, 'owner: final files renamed', want_ok=False)
            await case(ADMIN, {'ev': 'uploaded', 'client': 'cl-p-kia', 'folder': 'cf-p-kia-q4familycarscampaign', 'files': [{'name': 'Hero.jpg', 'path': 'Clients/KIA/Files/Q4 Family Cars Campaign/Hero.jpg', 'size': 1234}, {'name': 'Cut.mp4', 'path': 'Clients/KIA/Files/Q4 Family Cars Campaign/Cut.mp4', 'size': 99}, {'name': 'no path'}]}, 'owner: files uploaded (Inbox updates)')
            await case(ADMIN, {'ev': 'uploaded', 'client': 'cl-p-kia', 'folder': 'cf-p-kia-files', 'files': [{'name': 'a.jpg', 'path': 'Clients/KIA/Files/a.jpg'}]}, 'owner: files into Files itself', want_ok=False)
            await case(ADMIN, {'ev': 'uploaded', 'client': 'cl-p-kia', 'folder': 'cf-p-kia-fonts', 'files': []}, 'owner: nothing uploaded', want_ok=False)
            await case(ADMIN, {'ev': 'uploaded', 'client': 'cl-p-deepal', 'folder': 'cf-final-smp-cu-86eyw0wru', 'files': [{'name': 'a.jpg', 'path': 'x/a.jpg'}]}, 'owner: files into final files', want_ok=False)
            await case(ADMIN, {'ev': 'deleteFile', 'client': 'cl-p-kia', 'folder': 'cf-p-kia-brandguidelines', 'file': cl('cl-p-kia')['folders'][1]['files'][0]['id']}, 'owner: a file deleted (Trash, Inbox)')
            fin = fo('cl-p-deepal', 'DEEPAL | G318 Staff Emailer')
            await case(ADMIN, {'ev': 'deleteFile', 'client': 'cl-p-deepal', 'folder': fin['id'], 'file': fin['files'][0]['id']}, 'owner: a final file deleted', want_ok=False)
            tac = fo('cl-p-ford', 'Tactical Always On')
            await case(ADMIN, {'ev': 'deleteFiles', 'client': 'cl-p-ford', 'folder': tac['id'], 'files': [x['id'] for x in tac['files']] + ['nope']}, 'owner: Select › Delete (2 files)')
            await case(ADMIN, {'ev': 'deleteFiles', 'client': 'cl-p-ford', 'folder': tac['id'], 'files': ['nope']}, 'owner: Select › Delete, files gone', want_ok=False)
            await case(ADMIN, {'ev': 'deleteFolder', 'client': 'cl-p-gm', 'folder': 'cf-p-gm-automechanika'}, 'owner: a folder deleted (its files: Inbox)')
            await case(ADMIN, {'ev': 'deleteFolder', 'client': 'cl-p-kia', 'folder': 'cf-p-kia-q4familycarscampaign'}, 'owner: a folder with 4 folders inside deleted')
            await case(ADMIN, {'ev': 'deleteFolder', 'client': 'cl-p-korea', 'folder': 'cf-p-korea-fonts'}, 'owner: a folder made with the client deleted')
            await case(ADMIN, {'ev': 'renameClient', 'client': 'cl-p-kia', 'name': '  KIA   Motors '}, 'owner: a client renamed')
            await case(ADMIN, {'ev': 'renameClient', 'client': 'cl-p-kia', 'name': 'Déepal'}, 'owner: renamed as another client', want_ok=False)
            await case(ADMIN, {'ev': 'renameClient', 'client': 'cl-nope', 'name': 'x'}, 'owner: a client that\'s gone', want_ok=False)
            await case(ADMIN, {'ev': 'deleteClient', 'client': 'cl-p-atm'}, 'owner: a client deleted (its projects unlinked, its files)')
            await case(ADMIN, {'ev': 'deleteClient', 'client': 'cl-p-kia'}, 'owner: a client deleted with a file of it in the Trash')
            # ---------- an Account Manager (KIA's, DEEPAL's…) ----------
            await case(AREEJ, {'ev': 'addClient', 'name': 'Nissan'}, 'AM: + New client')
            nissan = next(c for c in dump()['clients'] if c['name'] == 'Nissan')['id']
            await case(AREEJ, {'ev': 'renameClient', 'client': nissan, 'name': 'Nissan Gulf'}, 'AM: their own client renamed')
            await case(AREEJ, {'ev': 'renameClient', 'client': 'cl-p-deepal', 'name': 'Deepal UAE'}, 'AM: someone else\'s client renamed', want_ok=False)
            await case(AREEJ, {'ev': 'newFolder', 'client': 'cl-p-deepal', 'name': 'Events'}, 'AM: a folder on the client\'s page')
            s09 = fo('cl-p-deepal', 'S09 Pre-Book Campaign')
            await case(AREEJ, {'ev': 'deleteFile', 'client': 'cl-p-deepal', 'folder': s09['id'], 'file': s09['files'][0]['id']}, 'AM: someone else\'s file deleted')
            await case(AREEJ, {'ev': 'renameFolder', 'client': 'cl-p-deepal', 'folder': s09['id'], 'name': 'S09 Pre-Book'}, 'AM: someone else\'s folder renamed')
            await case(AREEJ, {'ev': 'renameFolder', 'client': 'cl-p-deepal', 'folder': 'cf-p-deepal-logos', 'name': 'Logo files'}, 'AM: Logos renamed', want_ok=False)
            await case(AREEJ, {'ev': 'deleteFolder', 'client': 'cl-p-deepal', 'folder': 'cf-p-deepal-fonts'}, 'AM: Fonts deleted', want_ok=False)
            await case(AREEJ, {'ev': 'deleteFolder', 'client': 'cl-p-deepal', 'folder': s09['id']}, 'AM: someone else\'s folder deleted')
            await case(AREEJ, {'ev': 'deleteClient', 'client': nissan}, 'AM: a client deleted', want_ok=False)
            # ---------- Production (Yousef: KIA's Q4 folder is his) — fresh sample ----------
            await close_all(); reset()
            await case(YOUSEF, {'ev': 'addClient', 'name': 'Toyota'}, 'Production: + New client', want_ok=False)
            await case(YOUSEF, {'ev': 'newFolder', 'client': 'cl-p-kia', 'name': 'Mine'}, 'Production: a folder on the client\'s page', want_ok=False)
            await case(YOUSEF, {'ev': 'newFolder', 'client': 'cl-p-kia', 'parent': 'cf-p-kia-q4familycarscampaign', 'name': 'Retouched'}, 'Production: a folder inside Files')
            await case(YOUSEF, {'ev': 'uploaded', 'client': 'cl-p-kia', 'folder': 'cf-p-kia-q4familycarscampaign', 'files': [{'name': f'Shot {i}.jpg', 'path': f'Clients/KIA/Files/Q4 Family Cars Campaign/Shot {i}.jpg', 'size': i} for i in range(6)]}, 'Production: 6 files uploaded')
            await case(YOUSEF, {'ev': 'uploaded', 'client': 'cl-p-kia', 'folder': 'cf-p-kia-logos', 'files': [{'name': 'kia.png', 'path': 'Clients/KIA/Logos/kia.png', 'size': 5}]}, 'Production: a file into Logos (the client has a logo)')
            q4 = fo('cl-p-kia', 'Q4 Family Cars Campaign')
            await case(YOUSEF, {'ev': 'deleteFile', 'client': 'cl-p-kia', 'folder': q4['id'], 'file': q4['files'][0]['id']}, 'Production: their own file deleted')
            lg = fo('cl-p-kia', 'Logos')
            await case(YOUSEF, {'ev': 'deleteFile', 'client': 'cl-p-kia', 'folder': lg['id'], 'file': lg['files'][0]['id']}, 'Production: someone else\'s file deleted', want_ok=False)
            await case(YOUSEF, {'ev': 'deleteFiles', 'client': 'cl-p-kia', 'folder': lg['id'], 'files': [x['id'] for x in lg['files']]}, 'Production: Select › Delete with someone else\'s', want_ok=False)
            await case(YOUSEF, {'ev': 'renameFolder', 'client': 'cl-p-kia', 'folder': q4['id'], 'name': 'Q4 Cars'}, 'Production: their own folder renamed')
            await case(YOUSEF, {'ev': 'renameFolder', 'client': 'cl-p-kia', 'folder': 'cf-p-kia-fonts', 'name': 'Type'}, 'Production: Fonts renamed', want_ok=False)
            await case(YOUSEF, {'ev': 'renameClient', 'client': 'cl-p-kia', 'name': 'KIA 2'}, 'Production: the client renamed', want_ok=False)
            await case(YOUSEF, {'ev': 'deleteFolder', 'client': 'cl-p-kia', 'folder': q4['id']}, 'Production: their own folder (with theirs inside) deleted')
            await case(YOUSEF, {'ev': 'deleteClient', 'client': 'cl-p-kia'}, 'Production: a client deleted', want_ok=False)
            seen = {c['id'] for c in json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/snapshot', headers={'X-Dev-Email': YOUSEF})).read())['data']['clients']}
            hid = next(c for c in dump()['clients'] if c['id'] not in seen)
            await case(YOUSEF, {'ev': 'uploaded', 'client': hid['id'], 'folder': hid['folders'][2]['id'], 'files': [{'name': 'a.otf', 'path': hid['dir'] + '/Fonts/a.otf'}]}, f'Production: a client they\'re not on ({hid["name"]})', want_ok=False)
            # ---------- freelancers, Finance ----------
            await case(SAM, {'ev': 'uploaded', 'client': 'cl-p-ford', 'folder': 'cf-p-ford-fonts', 'files': [{'name': 'a.otf', 'path': 'Clients/Ford & Lincoln/Fonts/a.otf'}]}, 'freelancer (Ford): files uploaded', want_ok=False)
            await case(SAM, {'ev': 'newFolder', 'client': 'cl-p-ford', 'parent': 'cf-p-ford-files', 'name': 'Mine'}, 'freelancer (Ford): a folder', want_ok=False)
            tac = fo('cl-p-ford', 'Tactical Always On')
            await case(SAM, {'ev': 'deleteFile', 'client': 'cl-p-ford', 'folder': tac['id'], 'file': tac['files'][0]['id']}, 'freelancer (Ford): a file deleted', want_ok=False)
            await case(SAM, {'ev': 'renameClient', 'client': 'cl-p-ford', 'name': 'Ford'}, 'freelancer (Ford): the client renamed', want_ok=False)
            await case(FREE2, {'ev': 'uploaded', 'client': 'cl-p-ford', 'folder': 'cf-p-ford-fonts', 'files': [{'name': 'a.otf', 'path': 'x'}]}, 'freelancer (no clients): Ford', want_ok=False)
            await case(FREE2, {'ev': 'addClient', 'name': 'Mine'}, 'freelancer (no clients): + New client', want_ok=False)
            await case(RANIA, {'ev': 'addClient', 'name': 'Mine'}, 'Finance: + New client', want_ok=False, page_crash=True)
            # ---------- an Office Admin (no Super Admin rights) ----------
            await case(OA, {'ev': 'addClient', 'name': 'Office Client'}, 'Office Admin: + New client')
            await case(OA, {'ev': 'newFolder', 'client': 'cl-p-hre', 'name': 'Contracts'}, 'Office Admin: a folder')
            await case(OA, {'ev': 'renameFolder', 'client': 'cl-p-hre', 'folder': 'cf-p-hre-brandguidelines', 'name': 'Brand book'}, 'Office Admin: a folder made with the client renamed')
            await case(OA, {'ev': 'renameClient', 'client': 'cl-p-hre', 'name': 'HRE Wheels'}, 'Office Admin: a client renamed')
            await case(OA, {'ev': 'deleteFolder', 'client': 'cl-p-hre', 'folder': 'cf-p-hre-logos'}, 'Office Admin: Logos deleted')
            await case(OA, {'ev': 'deleteClient', 'client': 'cl-p-bizreh'}, 'Office Admin: a client deleted (its project can\'t be changed — stays linked)')
            await close_all()

            # ---------- the logo from Logos: the website's canvas and the server, from the same file ----------
            reset()
            ctx, pg, errs, host = await page_of(ADMIN)
            def upload(who, dest, name, data):
                return post('/api/host/writeChunk', who, {'dest': dest, 'name': name, 'b64': base64.b64encode(data).decode()})
            def logo_of(cid, wait=15):
                for _ in range(wait * 4):
                    c = next((x for x in dump()['clients'] if x['id'] == cid), None)
                    if c and c.get('logo'): return c
                    time.sleep(0.25)
                return c
            for i, (name, data) in enumerate(sources()):
                await pg.evaluate("(n) => __e11Assets({ ev: 'addClient', name: n, rid: 'w' })", f'Web logo {i}')
                await pg.wait_for_timeout(1500)
                wc = next(c for c in dump()['clients'] if c['name'] == f'Web logo {i}')
                wl = next(f for f in wc['folders'] if f['name'] == 'Logos')
                up = upload(ADMIN, wl['dir'], name, data)
                await pg.evaluate("([c, f, x]) => __e11Assets({ ev: 'uploaded', client: c, folder: f, files: [x], rid: 'u' })", [wc['id'], wl['id'], {'name': up['name'], 'path': up['path'], 'size': up['size']}])
                web = logo_of(wc['id'])
                r = act(ADMIN, {'ev': 'caAddClient', 'name': f'Server logo {i}'})
                sc = next(c for c in dump()['clients'] if c['id'] == r.get('id'))
                sl = next(f for f in sc['folders'] if f['name'] == 'Logos')
                check(all(os.path.isdir(os.path.join(FILES, f['dir'])) for f in sc['folders']), f'logo {name}: the new client\'s four folders made on disk')
                up = upload(ADMIN, sl['dir'], name, data)
                r = act(ADMIN, {'ev': 'caUploaded', 'client': sc['id'], 'folder': sl['id'], 'files': [{'name': up['name'], 'path': up['path'], 'size': up['size']}]})
                check(r.get('ok') is True, f'logo {name}: uploaded through the route', json.dumps(r)[:300])
                mine = logo_of(sc['id'])
                good = bool(web.get('logo')) and bool(mine.get('logo')) and mine.get('logoAuto') is True and web.get('logoAuto') is True and re.match(r'^Clients/_logos/client-sq-[0-9a-z]+\.png$', mine['logo'] or '')
                check(good, f'logo {name}: the client\'s logo made from Logos (website {web.get("logo")}, server {mine.get("logo")})', json.dumps([web.get('logo'), mine.get('logo'), mine.get('logoAuto')]))
                if good:
                    a = Image.open(os.path.join(FILES, web['logo'])).convert('RGB'); m = Image.open(os.path.join(FILES, mine['logo'])).convert('RGB')
                    same_size = a.size == m.size == (600, 600)
                    pa, pm = list(a.resize((60, 60)).tobytes()), list(m.resize((60, 60)).tobytes())
                    dif = sum(abs(x - y) for x, y in zip(pa, pm)) / (60 * 60 * 3)
                    corner = lambda im: im.getpixel((3, 3))
                    check(same_size and dif < 6 and max(abs(x - y) for x, y in zip(corner(a), corner(m))) <= 3, f'logo {name}: the same square (600 px, background {corner(m)} vs {corner(a)}, mean difference {dif:.2f})', f'sizes {a.size} {m.size}')
            # (a second image into Logos once it has a logo: no change; a client with a logo already: none made)
            sc = next(c for c in dump()['clients'] if c['name'] == 'Server logo 0'); sl = next(f for f in sc['folders'] if f['name'] == 'Logos')
            up = upload(ADMIN, sl['dir'], 'Other.png', sources()[0][1])
            act(ADMIN, {'ev': 'caUploaded', 'client': sc['id'], 'folder': sl['id'], 'files': [{'name': up['name'], 'path': up['path'], 'size': up['size']}]}); time.sleep(3)
            check(next(c for c in dump()['clients'] if c['id'] == sc['id'])['logo'] == sc['logo'], 'logo: a second image doesn\'t change it')
            # (Production puts the first image into a new client's Logos: theirs too — access.js lets anyone fill in a missing one)
            r = act(ADMIN, {'ev': 'caAddClient', 'name': 'Prod logo'}); pc = next(c for c in dump()['clients'] if c['id'] == r['id']); pl = next(f for f in pc['folders'] if f['name'] == 'Logos')
            up = upload(ADMIN, pl['dir'], 'p.png', sources()[0][1])
            r = act(AREEJ, {'ev': 'caUploaded', 'client': pc['id'], 'folder': pl['id'], 'files': [{'name': up['name'], 'path': up['path'], 'size': up['size']}]})
            check(r.get('ok') is True and bool(logo_of(pc['id']).get('logo')), 'logo: an Account Manager\'s upload makes it too', json.dumps(r)[:300])
            # (into a folder named Logos someone else made — not the client's own: no logo)
            r = act(AREEJ, {'ev': 'caAddClient', 'name': 'No logo'}); nc = next(c for c in dump()['clients'] if c['id'] == r['id'])
            act(ADMIN, {'ev': 'caDeleteFolder', 'client': nc['id'], 'folder': next(f for f in nc['folders'] if f['name'] == 'Logos')['id']})
            r = act(ADMIN, {'ev': 'caNewFolder', 'client': nc['id'], 'name': 'Logos'})
            up = upload(ADMIN, nc['dir'] + '/Logos', 'n.png', sources()[0][1])
            r2 = act(ADMIN, {'ev': 'caUploaded', 'client': nc['id'], 'folder': r['id'], 'files': [{'name': up['name'], 'path': up['path'], 'size': up['size']}]}); time.sleep(4)
            check(r2.get('ok') is True and not next(c for c in dump()['clients'] if c['id'] == nc['id']).get('logo'), 'logo: not from a Logos folder someone made later', json.dumps(r2)[:200])
            check(not errs, 'logo: no page errors', errs)
            await close_all()
            await b.close()

        # ---------- through the route: the person's rights, the answers, the folders on disk, the switch ----------
        reset()
        r = act(YOUSEF, {'ev': 'caNewFolder', 'client': 'cl-p-kia', 'parent': 'cf-p-kia-q4familycarscampaign', 'name': 'Route folder'})
        check(r.get('ok') is True and r.get('id') and any(c['kind'] == 'clients' for c in r.get('changes', [])) and os.path.isdir(os.path.join(FILES, 'Clients/KIA/Files/Q4 Family Cars Campaign/Route folder')), 'route: Production makes a folder (answer.id, the client record, the folder on disk)', json.dumps(r)[:400])
        r = act(YOUSEF, {'ev': 'caUploaded', 'client': 'cl-p-kia', 'folder': r['id'], 'files': [{'name': 'x.jpg', 'path': 'Clients/KIA/Files/Q4 Family Cars Campaign/Route folder/x.jpg', 'size': 1}]})
        check(r.get('ok') is True and len(r.get('changes', [])) == 1, 'route: Production uploads (the client back; others\' Inbox updates not sent to them)', json.dumps(r)[:400])
        r = act(SAM, {'ev': 'caDeleteClient', 'client': 'cl-p-ford'}); check(r.get('ok') is False and r.get('error') == 'Only Admins delete clients', 'route: a freelancer can\'t delete a client', json.dumps(r)[:300])
        r = act(OA, {'ev': 'caDeleteClient', 'client': 'cl-p-forta'})
        check(r.get('ok') is True and r.get('gone') is True and not any(c['id'] == 'cl-p-forta' for c in dump()['clients']) and next(p for p in dump()['projects'] if p['id'] == 'p-forta').get('clientId') == 'cl-p-forta', 'route: an Office Admin deletes a client (gone; the project they can\'t change stays as it was)', json.dumps(r)[:300])
        os.makedirs(os.path.join(FILES, 'Clients/CPT/Logos'), exist_ok=True); open(os.path.join(FILES, 'Clients/CPT/Logos/CPT logo.svg'), 'w').write('<svg/>')
        r = act(ADMIN, {'ev': 'caDeleteClient', 'client': 'cl-p-cpt'})
        check(r.get('ok') is True and not os.path.exists(os.path.join(FILES, 'Clients/CPT')) and next(p for p in dump()['projects'] if p['id'] == 'p-cpt').get('clientId') is None, 'route: the owner deletes a client (its NAS folder gone, its project unlinked)', json.dumps(r)[:300])
        r = act(ADMIN, {'ev': 'caAddClient', 'name': 'Route client'})
        check(r.get('ok') is True and r.get('id', '').startswith('cl-') and all(os.path.isdir(os.path.join(FILES, 'Clients/Route client', n)) for n in ['Logos', 'Brand Guidelines', 'Fonts', 'Files']), 'route: + New client (answer.id, four folders on disk)', json.dumps(r)[:300])
        con = sqlite3.connect(DBFILE, timeout=10); con.execute("insert or replace into kv (key, value) values ('app-act-assets', 'off')"); con.commit(); con.close()
        r = act(ADMIN, {'ev': 'caAddClient', 'name': 'Off'}); check(r.get('off') is True, 'route: kv app-act-assets off → back to the page', json.dumps(r)[:200])
        r = act(ADMIN, {'ev': 'trEmpty'}); check(r.get('off') is not True, 'route: the other groups stay on', json.dumps(r)[:200])
    finally:
        srv.terminate()
        shutil.rmtree(DATA, ignore_errors=True); shutil.rmtree(WORK, ignore_errors=True)
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
