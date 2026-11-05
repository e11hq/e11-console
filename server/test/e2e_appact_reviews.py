"""Part B step 3: the CD's review decisions on the server (server/src/appact-reviews.js: rvApprove, rvAmend) do exactly
what the website does (phone.js NativeMe 'rvApprove' / 'rvAmend' → app.js decideReview).

How it's compared:
  1. A baseline: a server on its own data folder, the sample reset (deterministic ids), then stopped; a few records are
     added straight into its store so every case exists: a second pending request on a two-person task (Ali on
     "KIA | Year End Sale"), and Areej (the KIA client's Account Manager and creator) has "CD review results" switched off
     in her notification settings.
  2. For each run (approvals, amendments) the baseline folder is copied twice, A and B.
     A: a server on A; the website as the CD (carine@, Playwright) — each decision through the page's own handler
        window.__e11Me({ ev, id, rid, ... }) (NativeMac.call stubbed to catch the page's answers), waiting for it to sync.
     B: no server — Node opens B's store, runs the module's handlers as the CD with the same inputs in the same order,
        and saves their `changes` with store.apply (as the route will).
     (4.5 s between decisions on the page and a clock moved on 5 s on the server side, so pushNotif's "one update per
     change" 4-second merge never joins two decisions on either side.)
  3. Both stores against the baseline: every task that changed and every notification made or changed must be the same,
     with generated ids (named in order of first appearance, so a notification's commentId must still point at the same
     comment) and new timestamps blanked out. The page's answers ({ ok, next } or the error) must equal the handler's.
"""
import asyncio, json, os, shutil, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18341; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'; CD = 'carine@e11-digital.com'
STORE = os.path.join(ROOT, 'server/src/store.js'); MOD = os.path.join(ROOT, 'server/src/appact-reviews.js')
ok = []
def check(good, what, extra=''):
    ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)

def node(code, *args):
    r = subprocess.run(['node', '--no-warnings', '--input-type=module', '-e', code, '--', *args], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr)
    return json.loads(r.stdout) if r.stdout.strip() else None

def start(data_dir):
    subprocess.run(['fuser', '-k', f'{PORT}/tcp'], stderr=subprocess.DEVNULL)
    env = {**os.environ, 'DATA_DIR': data_dir, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': ROOT + '/web', 'APP_VERSION': '1.6.1-test.1'}
    srv = subprocess.Popen(['node', ROOT + '/server/src/index.js'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(80):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    return srv

def stop(srv):
    srv.terminate()
    try: srv.wait(10)
    except Exception: srv.kill()

# the baseline's extra records (the server is stopped)
TWEAK = r"""
const { openStore } = await import(process.argv[1]);
const s = openStore(process.argv[2] + '/db/e11.sqlite');
const t = s.get('tasks', 'smp-cu-86eyw61b0');
const sara = t.reviews[0];
const at = new Date(Date.parse(sara.at) + 3600000).toISOString();
t.attachments.push({ id: 'tw-ali-f0', name: 'KIA_YearEnd_Ali.jpg', size: 1000, path: 'attachments/smp-cu-86eyw61b0/KIA_YearEnd_Ali.jpg', type: 'image/jpeg', addedAt: at, addedBy: 'u-ali', reviewId: 'tw-ali-rv1' });
t.reviews.push({ id: 'tw-ali-rv1', by: 'u-ali', at, files: ['tw-ali-f0'], state: 'pending', epoch: 0, round: 1 });
const lina = s.get('users', 'u-lina');
lina.prefs = { ...(lina.prefs || {}), notifOff: { ...((lina.prefs || {}).notifOff || {}), result: true } };
s.apply([{ kind: 'tasks', id: t.id, data: t }, { kind: 'users', id: lina.id, data: lina }], 'test');
s.close();
"""

# B: the handlers on B's store; then both stores against the baseline, normalised
RUN_B_AND_COMPARE = r"""
const [storeJs, modJs, baseDir, aDir, bDir, actsJson] = process.argv.slice(1);
const { openStore } = await import(storeJs);
const { createReviewActs } = await import(modJs);
const acts = JSON.parse(actsJson);
const B = openStore(bDir + '/db/e11.sqlite');
let offset = 0;
const R = createReviewActs({ store: B, now: () => Date.now() + offset });
const byEmail = (s, e) => s.list('users').find((u) => u.email === e);
const answers = {};
for (const a of acts) {
  const u = byEmail(B, a.as || 'carine@e11-digital.com');
  const { ev, rid, as, ...body } = a;
  const r = R[ev](u, body);
  if (r.ok) { B.apply(r.changes, u.id); answers[rid] = { ok: true, next: r.answer.next }; }
  else answers[rid] = { ok: false, error: r.error, status: r.status };
  offset += 5000;
}
B.close();
const snap = (dir) => { const s = openStore(dir + '/db/e11.sqlite'); const d = s.snapshot().data; s.close(); return d; };
const base = snap(baseDir), A = snap(aDir), Bd = snap(bDir);
const baseStrings = new Set();
const walkS = (v) => { if (typeof v === 'string') baseStrings.add(v); else if (v && typeof v === 'object') Object.values(v).forEach(walkS); };
walkS(base.tasks); walkS(base.notifications);
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;
function norm(records) {
  const ids = new Map();
  const nm = (v, key) => {
    if (typeof v === 'string') {
      if (baseStrings.has(v)) return v;
      if (ISO.test(v)) return '<now>';
      if (['id', 'commentId'].includes(key)) { if (!ids.has(v)) ids.set(v, `<id${ids.size + 1}>`); return ids.get(v); }
      return v;
    }
    if (Array.isArray(v)) return v.map((x) => nm(x, key));
    if (v && typeof v === 'object') {
      const o = {};
      // (partsDone: a person → when; new keys of r.need are file ids from the baseline)
      for (const k of Object.keys(v).sort()) o[ids.has(k) ? ids.get(k) : k] = nm(v[k], k);
      return o;
    }
    return v;
  };
  return records.map((r) => nm(r));
}
// (the website, on opening, fills in the empty defaults an older or sample task lacks — access.js fillsOnly — and pushes
//  them; that's not part of a decision, so such fields are left out on both sides)
const FILL = { tags: [], comments: [], attachments: [], activity: [], checklist: [], reviews: [], start: null, notes: '', title: '', cdStatus: '', prio: {} };
const canon = (v) => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map((y) => [y, x[y]])) : x));
function unfill(t, b) {
  const o = { ...t };
  for (const k of Object.keys(o)) {
    if (b && b[k] !== undefined) continue;
    if ((k in FILL && canon(o[k]) === canon(FILL[k])) || (k === 'needsCD' && typeof o[k] === 'boolean')) delete o[k];
  }
  if (b && b.priority !== undefined && o.priority === undefined) o.priority = b.priority;
  return o;
}
function diff(d) {
  const bt0 = new Map(base.tasks.map((t) => [t.id, t]));
  const bt = new Map(base.tasks.map((t) => [t.id, canon(t)]));
  const bn = new Map(base.notifications.map((n) => [n.id, JSON.stringify(n)]));
  const tasks = d.tasks.map((t) => unfill(t, bt0.get(t.id))).filter((t) => bt.get(t.id) !== canon(t)).sort((a, b) => a.id.localeCompare(b.id));
  const key = (n) => [n.to, n.taskId, n.kind, n.text, n.from, n.snippet].join('|');
  const notes = d.notifications.filter((n) => bn.get(n.id) !== JSON.stringify(n)).sort((a, b) => key(a).localeCompare(key(b)));
  const all = norm([...tasks, ...notes]);
  return { tasks: all.slice(0, tasks.length), notifications: all.slice(tasks.length) };
}
console.log(JSON.stringify({ answers, A: diff(A), B: diff(Bd) }));
"""

RUNS = {
    'approvals': [
        {'ev': 'rvApprove', 'rid': 'a1', 'id': 'smp-cu-z8xb3urtb5-rv1'},     # round 1, one person, 3 files → CTR
        {'ev': 'rvApprove', 'rid': 'a2', 'id': 'smp-cu-86eyw61b0-rv1'},      # two people: Yousef's (Ali's still waiting)
        {'ev': 'rvApprove', 'rid': 'a3', 'id': 'tw-ali-rv1'},                # ...then Ali's: all approved → CTR
        {'ev': 'rvApprove', 'rid': 'a4', 'id': 'smp-cu-z8xb3uu8q1-rv2'},     # round 2: the file approved in round 1 carried
        {'ev': 'rvApprove', 'rid': 'a5', 'id': 'smp-cu-z8xb3uu8q1-rv2'},     # already decided → refused
        {'ev': 'rvApprove', 'rid': 'a6', 'id': 'smp-cu-z8xb3uty40-rv1', 'as': ADMIN},   # not the CD → refused
    ],
    'amendments': [
        # per-file ticks with notes (one empty) + a general note with characters to escape → the third file approved
        {'ev': 'rvAmend', 'rid': 'm1', 'id': 'smp-cu-z8xb3urtb5-rv1', 'need': {'smp-cu-z8xb3urtb5-f0': 'Bigger logo\nplease', 'smp-cu-z8xb3urtb5-f2': ''}, 'note': 'General: <check> & \'fix\' the "end"'},
        {'ev': 'rvAmend', 'rid': 'm2', 'id': 'smp-cu-z8xb3utbyv-rv1', 'note': 'Redo the colours\nand the type'},   # no ticks: every file
        {'ev': 'rvAmend', 'rid': 'm3', 'id': 'smp-cu-z8xb3uty40-rv1', 'need': {}},                # nothing ticked → refused
        {'ev': 'rvAmend', 'rid': 'm4', 'id': 'smp-cu-z8xb3uty40-rv1', 'note': '   '},            # no note → refused
        {'ev': 'rvAmend', 'rid': 'm5', 'id': 'smp-cu-z8xb3uu8q1-rv2', 'need': {'not-a-file': 'x'}},   # none of its files → approved
        {'ev': 'rvAmend', 'rid': 'm6', 'id': 'smp-cu-86eyw61b0-rv1', 'need': {'smp-cu-86eyw61b0-fr': 'Wrong size'}},   # Ali still waiting
        {'ev': 'rvAmend', 'rid': 'm7', 'id': 'tw-ali-rv1', 'note': 'All of it'},                  # nobody waiting → In progress
        {'ev': 'rvAmend', 'rid': 'm8', 'id': 'tw-ali-rv1', 'note': 'Again'},                      # already decided → refused
    ],
}

async def website(acts):
    async with async_playwright() as pw:
        exe = [os.path.join('/opt/pw-browsers', d, 'chrome-linux/chrome') for d in sorted(os.listdir('/opt/pw-browsers')) if d.startswith('chromium-')] if os.path.isdir('/opt/pw-browsers') else []
        b = await (pw.chromium.launch(executable_path=exe[-1]) if exe else pw.chromium.launch())
        pages = {}
        async def page_for(who):
            if who in pages: return pages[who]
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': who, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(3500)
            await pg.evaluate("window.__got = []; NativeMac.call = (k, a) => { window.__got.push([k, a]); return Promise.resolve({}); }")
            pages[who] = (pg, errs); return pages[who]
        answers = {}
        for a in acts:
            pg, errs = await page_for(a.get('as', CD))
            ev = {k: v for k, v in a.items() if k != 'as'}
            await pg.evaluate("(ev) => window.__e11Me(ev)", ev)
            await pg.wait_for_timeout(4500)
            got = await pg.evaluate("(rid) => (window.__got.find(([k, x]) => k === 'me' && x && x.rid === rid) || [])[1] || null", a['rid'])
            answers[a['rid']] = {k: v for k, v in (got or {}).items() if k != 'rid'}
        for who, (pg, errs) in pages.items():
            for _ in range(40):
                if await pg.evaluate("window.__e11SyncState") == 'saved': break
                await pg.wait_for_timeout(250)
            check(await pg.evaluate("window.__e11SyncState") == 'saved', f'{who}: the website synced')
            check(not errs, f'{who}: no page errors', errs)
        await b.close()
        return answers

def show(x): return json.dumps(x, ensure_ascii=False, indent=1)[:4000]

async def main():
    tmp = tempfile.mkdtemp()
    base = os.path.join(tmp, 'base')
    srv = start(base)
    try:
        H = {'X-Dev-Email': ADMIN}
        urllib.request.urlopen(urllib.request.Request(BASE + '/api/me', headers=H))
        r = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample/reset', method='POST', data=b'{}', headers={**H, 'Content-Type': 'application/json'})).read())
        check(r.get('ok'), 'sample reset', r)
    finally:
        stop(srv)
    node(TWEAK, STORE, base)
    for name, acts in RUNS.items():
        a_dir, b_dir = os.path.join(tmp, name + '-A'), os.path.join(tmp, name + '-B')
        shutil.copytree(base, a_dir); shutil.copytree(base, b_dir)
        srv = start(a_dir)
        try: page_answers = await website(acts)
        finally: stop(srv)
        out = node(RUN_B_AND_COMPARE, STORE, MOD, base, a_dir, b_dir, json.dumps(acts))
        for a in acts:
            pa, sa = page_answers.get(a['rid']), out['answers'].get(a['rid'])
            sa_cmp = {k: v for k, v in sa.items() if k != 'status'}
            check(pa == sa_cmp, f"{name} {a['rid']} {a['ev']} {a['id']}{' as ' + a['as'] if 'as' in a else ''}: the same answer {sa}", f'\n   page:   {pa}\n   server: {sa}')
        A, B = out['A'], out['B']
        check(len(A['tasks']) > 0 and len(A['notifications']) > 0, f"{name}: the website changed {len(A['tasks'])} tasks, {len(A['notifications'])} notifications")
        ta, tb = {t['id']: t for t in A['tasks']}, {t['id']: t for t in B['tasks']}
        check(sorted(ta) == sorted(tb), f'{name}: the same tasks changed {sorted(ta)}', f'\n   page:   {sorted(ta)}\n   server: {sorted(tb)}')
        for tid in sorted(set(ta) | set(tb)):
            x, y = ta.get(tid), tb.get(tid)
            if x == y: check(True, f'{name}: task {tid} the same (status, CD status, reviews, comments, activity, parts)'); continue
            keys = sorted(set((x or {}).keys()) | set((y or {}).keys()))
            bad = [k for k in keys if (x or {}).get(k) != (y or {}).get(k)]
            check(False, f'{name}: task {tid} the same', '\n' + '\n'.join(f'   {k}:\n    page:   {show((x or {}).get(k))}\n    server: {show((y or {}).get(k))}' for k in bad))
        na, nb = A['notifications'], B['notifications']
        check(na == nb, f'{name}: the same {len(na)} notifications (who, kind, text, snippet, comment)', f'\n   page:   {show(na)}\n   server: {show(nb)}')
        if name == 'approvals':
            t = ta.get('smp-cu-z8xb3uu8q1') or {}
            rv2 = next((r for r in t.get('reviews', []) if r['id'] == 'smp-cu-z8xb3uu8q1-rv2'), {})
            check(rv2.get('set') == ['smp-cu-z8xb3uu8q1-f0', 'smp-cu-z8xb3uu8q1-f1-v2'], f"round 2: the carried file is in the approved set {rv2.get('set')}")
            check(not any(n['to'] == 'u-lina' and n['kind'] == 'review-ok' for n in na), 'Areej (results switched off) got no "approved" update')
            check(any(n['to'] == 'u-lina' and n['kind'] == 'mention' for n in na), 'Areej (the creator) still got the final-files comment')
    shutil.rmtree(tmp, ignore_errors=True)
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
