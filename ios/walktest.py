"""The walk-through (Haris 2026-11-05: "test each and everything for every role, a complete test without the website"):
the iPhone app in the simulator, the website off (E11_SELFTEST=walk — ios/App/WalkTest.swift), once for each role —
Super Admin, the Creative Director, Account Manager, Production, Social, Freelancer, Office Admin (with and without
Finance), Finance only (Admin, Viewer). At each step the app writes what's on screen; this takes a screenshot (every step
for the first person, only steps with something wrong for the rest), and at the end lists for each role: taps that went
to the website (so nothing happened), words like "Loading…" or an error showing, and crashes. Results: ios-walk.json,
ios-walk.txt, ios-walk-shots.zip (on the release ios-selftest)."""
import glob, json, os, re, subprocess, sys, time, urllib.request, zipfile
PORT = 18451
BASE = f'http://127.0.0.1:{PORT}'
TMP = os.environ.get('RUNNER_TEMP', '/tmp')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = sys.argv[1]
# (--apple: only the Super Admin, only the Apple pages' checks — the phone's way, no website; any failed check fails this
#  run, and the build signs and sends nothing — Haris 2026-11-10)
APPLE = '--apple' in sys.argv[2:]
BUNDLE = 'ae.e11.console.ios'
EMAIL = 'haris@e11-digital.com'
SHOTS = os.path.join(TMP, 'walk-shots'); os.makedirs(SHOTS, exist_ok=True)
T_START = time.time()
def sh(*a, **k): return subprocess.run(list(a), capture_output=True, text=True, **k)
def api(path, body=None, who=EMAIL):
    req = urllib.request.Request(BASE + path, method='POST' if body is not None else 'GET', data=json.dumps(body).encode() if body is not None else None,
                                 headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
    return json.loads(urllib.request.urlopen(req, timeout=60).read() or b'{}')

env = dict(os.environ, AUTH_DEV='1', DATA_DIR=os.path.join(TMP, 'walkdata'), PORT=str(PORT), ADMIN_EMAIL=EMAIL, APP_VERSION='9.9.9-test.1', SHARE_DIR='')
srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=open(os.path.join(TMP, 'walk-server.log'), 'w'), stderr=subprocess.STDOUT)
report, out = [], {}
try:
    for _ in range(60):
        try: urllib.request.urlopen(BASE + '/api/health', timeout=2); break
        except Exception: time.sleep(0.5)
    api('/api/sample', {})
    snap = api('/api/snapshot')
    users = (snap.get('data') or snap).get('users') or []
    by = lambda r: next((u for u in users if u.get('role') == r and u.get('active') is not False and u.get('email') != EMAIL), None)
    # the people to walk as: one of each role, the missing ones added by the Super Admin; a production person made CD
    def add(email, name, role, fin=''):
        r = api('/api/app/act', {'ev': 'addMember', 'email': email, 'name': name, 'role': role, 'fin': fin, 'op': email})
        print('added', email, role, fin, r.get('ok'), r.get('error', ''))
        return email
    roles = [('Super Admin', EMAIL)]
    prod = [u for u in users if u.get('role') == 'production' and u.get('email') != EMAIL]
    if prod and not APPLE:
        r = api('/api/app/act', {'ev': 'cd', 'id': prod[0]['id'], 'choice': 'cd', 'op': 'cd1'})
        print('CD', prod[0]['email'], r.get('ok'), r.get('error', ''))
        roles.append(('Creative Director', prod[0]['email']))
    for label, role in ((('Social', 'social'),) if APPLE else (('Account Manager', 'am'), ('Production', 'production'), ('Social', 'social'))):   # (--apple: Social too, for its own Plans tab)
        u = next((x for x in users if x.get('role') == role and x.get('email') not in [e for _, e in roles] + [EMAIL]), None)
        roles.append((label, u['email'] if u else add(f'walk-{role}@test.e11', f'Walk {label}', role)))
    if not APPLE:
        roles.append(('Freelancer', add('walk-free@test.e11', 'Walk Freelancer', 'freelancer')))
        roles.append(('Office Admin', add('walk-office@test.e11', 'Walk Office', 'office_admin')))
        roles.append(('Office Admin + Finance', add('walk-officefin@test.e11', 'Walk Office Finance', 'office_admin', 'admin')))
        roles.append(('Finance only · Admin', add('walk-finadmin@test.e11', 'Walk Finance Admin', 'finance_admin')))
        roles.append(('Finance only · Viewer', add('walk-finview@test.e11', 'Walk Finance Viewer', 'finance_viewer')))
    print('walking as', roles)

    devs = json.loads(sh('xcrun', 'simctl', 'list', 'devices', 'available', '-j').stdout)['devices']
    rtv = lambda rt: [int(x) for x in re.findall(r'(\d+)', rt.split('iOS')[-1])[:2]]
    phones = [(rtv(rt), d) for rt, ds in devs.items() if 'iOS' in rt for d in ds if re.match(r'iPhone \d', d['name']) and 'Pro Max' not in d['name']]
    phones.sort(key=lambda x: (x[0], x[1]['name']))
    udid = phones[-1][1]['udid']
    sh('xcrun', 'simctl', 'boot', udid); sh('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=300)
    sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')
    for n, (label, email) in enumerate(roles):
        tag = re.sub(r'[^a-z]+', '-', label.lower()).strip('-')
        sh('xcrun', 'simctl', 'terminate', udid, BUNDLE); sh('xcrun', 'simctl', 'uninstall', udid, BUNDLE)
        sh('xcrun', 'simctl', 'install', udid, APP)
        lenv = dict(os.environ, SIMCTL_CHILD_E11_SERVER=BASE, SIMCTL_CHILD_E11_SELFTEST='apple' if APPLE else 'walk', SIMCTL_CHILD_E11_SELFTEST_EMAIL=email)
        t_role = time.time()
        r = subprocess.run(['xcrun', 'simctl', 'launch', udid, BUNDLE], env=lenv, capture_output=True, text=True)
        data = sh('xcrun', 'simctl', 'get_app_container', udid, BUNDLE, 'data').stdout.strip()
        res, seen, t0, last = {}, set(), time.time(), time.time()
        while time.time() - t0 < 420:
            try: res = json.load(open(os.path.join(data, 'Documents', 'selftest.json')))
            except Exception: pass
            st = res.get('stage')
            if st and st not in seen:
                seen.add(st); last = time.time()
                w = (res.get('walk') or [{}])[-1]
                bad = w.get('lost') or w.get('issues')
                if n == 0 or bad or st == 'done':
                    sh('xcrun', 'simctl', 'io', udid, 'screenshot', os.path.join(SHOTS, f'{n:02d}-{tag}-{st}.png'))
            if st == 'done': break
            # (the app gone — crashed — or stuck: no new step for 60 s)
            if time.time() - last > 100:
                res["stuck"] = st or "never started"; sh("xcrun", "simctl", "io", udid, "screenshot", os.path.join(SHOTS, f"{n:02d}-{tag}-STUCK.png")); break
            time.sleep(0.4)
        res['email'] = email; res['secs'] = round(time.time() - t_role)
        out[label] = res
        steps = res.get('walk') or []
        lines = [f'== {label} ({email}) — {len(steps)} steps, {res["secs"]} s, booted {res.get("walkBooted")}, tabs {res.get("tabs")}']
        if res.get('stuck'): lines.append(f'   STUCK after {res["stuck"]} (crashed or frozen)')
        # every search: results, and what a tap on the first task / client result opened
        for w in steps:
            st_ = w.get('step', '')
            if st_.startswith('find_') or st_.startswith('findTask_') or st_.startswith('findClient_'):
                k = st_.split('_', 1)[1]
                tap = res.get(('walkTap_' if st_.startswith('findTask_') else 'walkTapC_') + k, '') if not st_.startswith('find_') else ''
                lines.append(f"   search {st_:24} results={w.get('results')} screen={w.get('screen')} task={str(w.get('task', ''))[:30]} pages={w.get('pages')} {tap}")
        for w in steps:
            probs = []
            if w.get('lost'): probs.append('went to the website: ' + ' | '.join(w['lost']))
            if w.get('issues'): probs.append('showing: ' + ' | '.join(w['issues']))
            if probs: lines.append(f"   {w.get('step')}: [{w.get('screen')}/{w.get('sheet') or '-'}] " + ' ;; '.join(probs))
        report += lines
        print('\n'.join(lines), flush=True)
finally:
    srv.terminate()
    reps = [f for f in glob.glob(os.path.expanduser('~/Library/Logs/DiagnosticReports/E11Console*.ips')) if os.path.getmtime(f) > T_START]
    for f in sorted(reps, key=os.path.getmtime)[-3:]:
        report.append('CRASH ' + os.path.basename(f))
        open(os.path.join(TMP, 'walk-crash-' + os.path.basename(f) + '.txt'), 'w').write(open(f, errors='replace').read()[:200000])
    json.dump(out, open(os.path.join(TMP, 'ios-walk.json'), 'w'), indent=1)
    open(os.path.join(TMP, 'ios-walk.txt'), 'w').write('\n'.join(report) + '\n')
    with zipfile.ZipFile(os.path.join(TMP, 'ios-walk-shots.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
        for f in sorted(glob.glob(os.path.join(SHOTS, '*.png'))): z.write(f, os.path.basename(f))
        for f in glob.glob(os.path.join(TMP, 'walk-crash-*.txt')): z.write(f, os.path.basename(f))
    if os.environ.get('RUNNER_ENVIRONMENT') == 'self-hosted':
        try: subprocess.run(['xcrun', 'simctl', 'shutdown', 'all'], capture_output=True, timeout=60)
        except Exception: pass
print('WALK DONE', len(out), 'roles')
if APPLE:
    a = (out.get('Super Admin') or {}).get('apple') or {}
    fails = []
    def check(ok, what):
        print(('ok   ' if ok else 'FAIL ') + what, flush=True)
        if not ok: fails.append(what)
    st, rv, rl, fc = a.get('start') or {}, a.get('review') or {}, a.get('roles') or {}, a.get('focus') or {}
    print('measure apple', json.dumps(a))
    check(st.get('pageReady') is False, f"the Apple pages ran without the website {st}")
    check(rv.get('cd') is True and rv.get('tab') == 'mytasks', f"Home's In review box: My Tasks with Waiting for CD review on {rv}")
    rows = rl.get('rows') or []
    check(bool(rows) and all(r != '<none>' for r in rows), f"the @ list: each person's role under the name {rl}")
    drawn = rl.get('drawn') or []
    check(bool(drawn) and all(r != '<none>' for r in drawn), f"the @ list as drawn: each role's words on screen in its row {drawn}")
    check(fc.get('none') is True or fc.get('inView') is True, f"a comment opened as from the Inbox stays in view once everything has come {fc}")
    bf = a.get('barFrames') or {}
    print('measure barLog', json.dumps(bf.get('log')))
    print('measure barVariants', json.dumps(a.get('barVariants')))
    for fr in (bf.get('frames') or [])[::2]: print('measure barFrame', json.dumps(fr))
    pl, pp = a.get('plans') or {}, a.get('plan') or {}
    check(pl.get('kind') == 'plans' and pl.get('apple') is True and not pl.get('loading') and isinstance(pl.get('rows'), int) and pl.get('rows', -1) >= 0 and (pl.get('rows', 0) > 0 or pl.get('empty') == 'No Clients'), f"Content plans: the list from the phone's copy, in Apple's navigation {pl}")
    check(pl.get('rows', 0) == 0 or (pp.get('kind') == 'plan' and not pp.get('loading') and (pp.get('status') is True or pp.get('empty') == 'Not Started Yet')), f"Content plans: a client's month — its status cell or Apple's Not Started Yet {pp}")
    tm, tmm = a.get('team') or {}, a.get('teamMember') or {}
    menu = tm.get('menu') or []
    check(tm.get('kind') == 'team' and tm.get('people', 0) > 0 and all(not r.endswith(': ') for r in tm.get('roles') or []), f"Team members: each person with their role, from the phone's copy {tm.get('roles')}")
    check(not tm.get('admin') or ('Change Role ›' in menu and 'Remove from Team' in menu and 'Social Manager' in (tm.get('roleMenu') or [])), f"Team members: a person held — Apple's menu with Change Role (Social Manager in it) and Remove from Team {menu} {tm.get('roleMenu')}")
    rows = tmm.get('rows') or []
    check(tmm.get('kind') == 'member' and (not tm.get('admin') or ('Role ⌄' in rows and 'Finance Access ⌄' in rows)), f"Team members: a member's page — Role and Finance Access as Apple's pull-down menus {rows}")
    so = (out.get('Social') or {}).get('apple') or {}
    t0, t1, t2 = so.get('plansTab') or {}, so.get('plansTabPlan') or {}, so.get('plansTabBack') or {}
    print('measure apple social', json.dumps(so))
    check(t0.get('shown') is True and t0.get('kind') == 'plans' and t0.get('barHidden') is False and not t0.get('loading'), f"Social's Plans tab: its own Apple screen, the list from the phone's copy {t0}")
    check(t0.get('rows', 0) == 0 or (t1.get('kind') == 'plan' and t1.get('barHidden') is True and not t1.get('loading')), f"Social's Plans tab: a skeleton opened — the tab bar gone once it's there {t1}")
    check(t0.get('rows', 0) == 0 or (t2.get('kind') == 'plans' and t2.get('barHidden') is False), f"Social's Plans tab: back — the tab bar there again, the list as it was {t2}")
    for who in ('Super Admin', 'Social'):
        check(not (out.get(who) or {}).get('stuck'), f"the app ran to the end as {who} (no crash, not stuck)")
    open(os.path.join(TMP, 'ios-apple.txt'), 'w').write('\n'.join(fails) + '\n')
    sys.exit(1 if fails else 0)
