"""The App Store screenshots (Haris 2026-11-11: the approved Style F Dark frames get real screens from the app): the iPhone app
in the 6.9" simulator (the newest iPhone Pro Max — the App Store's 1320 x 2868), dark, 9:41 and full bars, against a local
server holding only the App Review copy's made-up demo data (ios/shots-demo.mjs). It walks the app's own self-test steps as
the people each screenshot needs, taking a screenshot at every step, and keeps them all: ios-appstore-shots.zip (on the
release ios-selftest), picked and framed afterwards. Nothing is signed or sent — a simulator run only.
  A  the reviewer (Alex Morgan, Super Admin + Finance): the main self-test steps — E11 Day, the morning round-up, the Inbox and
     its peek, a task, a client's Client Assets folder (E11_SELFTEST=1)
  B  the Creative Director, the Social Manager, an Office Admin with Finance, the reviewer: the Apple pages — Review Requests,
     Content plans, Claims, Expenses (E11_SELFTEST=apple)
  C  the person whose birthday it is today: the app as it opens (their greeting)
  D  the reviewer with no signal in the status bar: E11 Day from the phone's own copy (Works offline)"""
import json, os, re, shutil, subprocess, sys, time, urllib.request, zipfile
PORT = 18452
BASE = f'http://127.0.0.1:{PORT}'
TMP = os.environ.get('RUNNER_TEMP', '/tmp')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = sys.argv[1]
BUNDLE = 'ae.e11.console.ios'
EMAIL = 'review@e11hq.com'
OUT = os.path.join(TMP, 'appstore-shots'); shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
DATA = os.path.join(TMP, 'shotsdata'); shutil.rmtree(DATA, ignore_errors=True)
def sh(*a, **k): return subprocess.run(list(a), capture_output=True, text=True, **k)
def api(path, body=None, who=EMAIL):
    req = urllib.request.Request(BASE + path, method='POST' if body is not None else 'GET', data=json.dumps(body).encode() if body is not None else None,
                                 headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
    return json.loads(urllib.request.urlopen(req, timeout=60).read() or b'{}')

made = json.loads(sh('node', os.path.join(ROOT, 'ios', 'shots-demo.mjs'), DATA, EMAIL).stdout.strip().splitlines()[-1])
print('demo data', made, flush=True)
env = dict(os.environ, AUTH_DEV='1', DATA_DIR=DATA, PORT=str(PORT), ADMIN_EMAIL=EMAIL, APP_VERSION='9.9.9-test.1', SHARE_DIR='')
srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=open(os.path.join(TMP, 'shots-server.log'), 'w'), stderr=subprocess.STDOUT)
try:
    for _ in range(60):
        try: urllib.request.urlopen(BASE + '/api/health', timeout=2); break
        except Exception: time.sleep(0.5)
    snap = api('/api/snapshot'); db = snap.get('data') or snap
    users, meta = db.get('users') or [], db.get('meta') or {}
    email_of = lambda uid: next((u.get('email') for u in users if u.get('id') == uid), None)
    cd = email_of(meta.get('cdUserId'))
    sm = email_of(((meta.get('socialMgrIds') or [None])[0]))
    of = next((u.get('email') for u in users if u.get('role') == 'office_admin' and u.get('fin') == 'admin' and u.get('active') is not False), None)
    if not of:
        api('/api/app/act', {'ev': 'addMember', 'email': 'sara.khan@example.com', 'name': 'Sara Khan', 'role': 'office_admin', 'fin': 'admin', 'op': 'of1'}); of = 'sara.khan@example.com'
    print('people', {'cd': cd, 'sm': sm, 'office': of, 'birthday': (made.get('birthday') or {}).get('email')}, flush=True)
    # (the main self-test's pick, as selftest.py: a task with comments, one in review, a client's folder with files)
    tasks, cls = db.get('tasks') or [], db.get('clients') or []
    free = lambda x: not x.get('parentId') and not x.get('done') and not x.get('lockedAt') and not (x.get('reviews') or [])
    t = next((x for x in tasks if free(x) and x.get('comments') and x.get('checklist')), None) or next((x for x in tasks if free(x) and x.get('comments')), None) or next((x for x in tasks if free(x)), None)
    rv = next((x for x in tasks if not x.get('parentId') and not x.get('done') and any(r.get('state') == 'pending' for r in (x.get('reviews') or []))), None)
    c = next((x for x in cls if any(len(f.get('files') or []) > 2 for f in (x.get('folders') or []))), None) or (cls[0] if cls else None)
    f = next((y for y in ((c or {}).get('folders') or []) if len(y.get('files') or []) > 2), None)
    pick = {'task': (t or {}).get('id', ''), 'review': (rv or {}).get('id', ''), 'client': (c or {}).get('id', ''), 'folder': (f or {}).get('id', '')}
    print('pick', pick, flush=True)

    # the 6.9" iPhone: the newest Pro Max
    devs = json.loads(sh('xcrun', 'simctl', 'list', 'devices', 'available', '-j').stdout)['devices']
    rtv = lambda rt: [int(x) for x in re.findall(r'(\d+)', rt.split('iOS')[-1])[:2]]
    def newest(pat):
        ph = [(rtv(rt), d) for rt, ds in devs.items() if 'iOS' in rt for d in ds if re.match(pat, d['name'])]
        ph.sort(key=lambda x: (x[0], x[1]['name'])); return ph[-1][1] if ph else None
    def boot(d):
        sh('xcrun', 'simctl', 'boot', d['udid']); sh('xcrun', 'simctl', 'bootstatus', d['udid'], '-b', timeout=300)
        sh('xcrun', 'simctl', 'ui', d['udid'], 'appearance', 'dark')
        print('simulator', d['name'], flush=True); return d['udid']
    # (SHOTS: all — every screen as before; home — only E11 Day's first steps, on the 6.9" Pro Max and the 6.3" Pro side by
    #  side: E11 Day came out empty in the 2026-11-14 run, fine on Haris's phone — Haris 2026-11-14)
    SHOTS = os.environ.get('SHOTS', 'all') or 'all'
    dev = newest(r'iPhone \d+ Pro Max$'); udid = boot(dev)
    full = ['--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularMode', 'active', '--cellularBars', '4', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3']
    def bars(*a): sh('xcrun', 'simctl', 'status_bar', udid, 'clear'); sh('xcrun', 'simctl', 'status_bar', udid, 'override', *a)
    def shot(name): sh('xcrun', 'simctl', 'io', udid, 'screenshot', os.path.join(OUT, name + '.png'))
    def run(tag, email, mode, secs=420, every=True, extra=None, quick=None, until=None):
        sh('xcrun', 'simctl', 'terminate', udid, BUNDLE); sh('xcrun', 'simctl', 'uninstall', udid, BUNDLE)
        sh('xcrun', 'simctl', 'install', udid, APP)
        lenv = dict(os.environ, SIMCTL_CHILD_E11_SERVER=BASE, SIMCTL_CHILD_E11_SELFTEST=mode, SIMCTL_CHILD_E11_SELFTEST_EMAIL=email, **(extra or {}))
        subprocess.run(['xcrun', 'simctl', 'launch', udid, BUNDLE], env=lenv, capture_output=True, text=True)
        data = sh('xcrun', 'simctl', 'get_app_container', udid, BUNDLE, 'data').stdout.strip()
        if quick:   # (just the app as it opens: a few pictures, then on)
            for s in quick: time.sleep(s); shot(f'{tag}-{int(time.time()) % 10000}')
            return
        seen, t0, last, n = set(), time.time(), time.time(), 0
        while time.time() - t0 < secs:
            try: res = json.load(open(os.path.join(data, 'Documents', 'selftest.json')))
            except Exception: res = {}
            st = res.get('stage')
            if st and st not in seen:
                seen.add(st); last = time.time(); n += 1; time.sleep(0.6)
                shot(f'{tag}-{n:03d}-{st}')
                if st in ('lookFlip', 'tlookFlip'): sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'light')
                if st in ('lookLight', 'tlookLight'): sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')
            if st == 'done' or st == until or time.time() - last > 100: break
            time.sleep(0.4)
        sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')
        print(tag, email, len(seen), 'steps', flush=True)

    bars(*full)
    if SHOTS == 'home':
        run('H-promax', EMAIL, '1', secs=240, until='homeFind', extra={'SIMCTL_CHILD_E11_SELFTEST_PICK': json.dumps(pick)})
        time.sleep(4); shot('H-promax-zz-after')
        sh('xcrun', 'simctl', 'shutdown', udid)
        small = newest(r'iPhone \d+ Pro$')
        if small:
            udid = boot(small); bars(*full)
            run('H-pro', EMAIL, '1', secs=240, until='homeFind', extra={'SIMCTL_CHILD_E11_SELFTEST_PICK': json.dumps(pick)})
            time.sleep(4); shot('H-pro-zz-after')
        raise SystemExit
    run('A-reviewer', EMAIL, '1', secs=1200, extra={'SIMCTL_CHILD_E11_SELFTEST_PICK': json.dumps(pick)})
    for tag, who in (('B-cd', cd), ('B-social', sm), ('B-office', of), ('B-reviewer', EMAIL)):
        if who: run(tag, who, 'apple')
    b = (made.get('birthday') or {}).get('email')
    if b: run('C-birthday', b, 'apple', quick=[6, 4, 4])
    bars('--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularMode', 'notSupported', '--wifiMode', 'failed', '--wifiBars', '0')
    run('D-offline', EMAIL, 'apple', quick=[8, 5])
    sh('xcrun', 'simctl', 'status_bar', udid, 'clear')
finally:
    srv.terminate()
    with zipfile.ZipFile(os.path.join(TMP, 'ios-appstore-shots.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
        for fn in sorted(os.listdir(OUT)): z.write(os.path.join(OUT, fn), fn)
    print('shots', len(os.listdir(OUT)), flush=True)
