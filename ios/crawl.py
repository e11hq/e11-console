"""The crawl (Haris 2026-11-05: "every single thing"): runs ios/UITests/CrawlTests.swift — Apple's UI testing tapping every
control on every screen — once for each role, the website off, against a local server with the sample data (the same
people as ios/walktest.py). Results: ios-crawl.txt (per role: every control tapped and what it did, the ones that did
nothing, crashes, lost screens), ios-crawl.json, ios-crawl-shots.zip — on the release ios-selftest.
Usage: python3 ios/crawl.py <derivedDataPath> [seconds per role]"""
import glob, json, os, re, subprocess, sys, time, urllib.request, zipfile
PORT = 18452
BASE = f'http://127.0.0.1:{PORT}'
TMP = os.environ.get('RUNNER_TEMP', '/tmp')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DD = sys.argv[1]
SECS = sys.argv[2] if len(sys.argv) > 2 else '900'
ONLY = [x.strip() for x in os.environ.get('CRAWL_ROLES', '').split(',') if x.strip()]
EMAIL = 'haris@e11-digital.com'
OUT = os.path.join(TMP, 'crawl-out'); os.makedirs(OUT, exist_ok=True)
T_START = time.time()
def sh(*a, **k): return subprocess.run(list(a), capture_output=True, text=True, **k)
def api(path, body=None, who=EMAIL):
    req = urllib.request.Request(BASE + path, method='POST' if body is not None else 'GET', data=json.dumps(body).encode() if body is not None else None,
                                 headers={'X-Dev-Email': who, 'Content-Type': 'application/json'})
    return json.loads(urllib.request.urlopen(req, timeout=60).read() or b'{}')

env = dict(os.environ, AUTH_DEV='1', DATA_DIR=os.path.join(TMP, 'crawldata'), PORT=str(PORT), ADMIN_EMAIL=EMAIL, APP_VERSION='9.9.9-test.1', SHARE_DIR='')
srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=open(os.path.join(TMP, 'crawl-server.log'), 'w'), stderr=subprocess.STDOUT)
report, allres = [], {}
try:
    for _ in range(60):
        try: urllib.request.urlopen(BASE + '/api/health', timeout=2); break
        except Exception: time.sleep(0.5)
    api('/api/sample', {})
    users = (api('/api/snapshot').get('data') or {}).get('users') or []
    def add(email, name, role, fin=''):
        api('/api/app/act', {'ev': 'addMember', 'email': email, 'name': name, 'role': role, 'fin': fin, 'op': email}); return email
    roles = [('Super Admin', EMAIL)]
    prod = [u for u in users if u.get('role') == 'production' and u.get('email') != EMAIL]
    if prod:
        api('/api/app/act', {'ev': 'cd', 'id': prod[0]['id'], 'choice': 'cd', 'op': 'cd1'}); roles.append(('Creative Director', prod[0]['email']))
    for label, role in (('Account Manager', 'am'), ('Production', 'production'), ('Social', 'social')):
        u = next((x for x in users if x.get('role') == role and x.get('email') not in [e for _, e in roles] + [EMAIL]), None)
        roles.append((label, u['email'] if u else add(f'crawl-{role}@test.e11', f'Crawl {label}', role)))
    roles.append(('Freelancer', add('crawl-free@test.e11', 'Crawl Freelancer', 'freelancer')))
    roles.append(('Office Admin', add('crawl-office@test.e11', 'Crawl Office', 'office_admin')))
    roles.append(('Office Admin + Finance', add('crawl-officefin@test.e11', 'Crawl Office Finance', 'office_admin', 'admin')))
    roles.append(('Finance only', add('crawl-fin@test.e11', 'Crawl Finance', 'finance_admin')))
    if ONLY: roles = [r for r in roles if any(o.lower() in r[0].lower() for o in ONLY)]
    print('crawling as', roles, flush=True)

    devs = json.loads(sh('xcrun', 'simctl', 'list', 'devices', 'available', '-j').stdout)['devices']
    rtv = lambda rt: [int(x) for x in re.findall(r'(\d+)', rt.split('iOS')[-1])[:2]]
    phones = sorted([(rtv(rt), d) for rt, ds in devs.items() if 'iOS' in rt for d in ds if re.match(r'iPhone \d', d['name']) and 'Pro Max' not in d['name']], key=lambda x: (x[0], x[1]['name']))
    udid = phones[-1][1]['udid']
    sh('xcrun', 'simctl', 'boot', udid); sh('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=300)
    sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')
    xctr = glob.glob(os.path.join(DD, 'Build', 'Products', '*.xctestrun'))
    print('xctestrun', xctr, flush=True)
    for n, (label, email) in enumerate(roles):
        tag = f"{n:02d}-" + re.sub(r'[^a-z]+', '-', label.lower()).strip('-')
        sh('xcrun', 'simctl', 'uninstall', udid, 'ae.e11.console.ios')
        renv = dict(os.environ, TEST_RUNNER_E11_EMAIL=email, TEST_RUNNER_E11_SERVER=BASE, TEST_RUNNER_E11_CRAWL_OUT=OUT, TEST_RUNNER_E11_TAG=tag, TEST_RUNNER_E11_CRAWL_SECS=SECS)
        t0 = time.time()
        args = ['xcodebuild', 'test-without-building', '-destination', f'id={udid}', '-only-testing:E11ConsoleUITests/CrawlTests/testCrawl', '-resultBundlePath', os.path.join(TMP, f'crawl-{tag}.xcresult')]
        args += ['-xctestrun', xctr[0]] if xctr else ['-project', os.path.join(ROOT, 'ios/E11Console.xcodeproj'), '-scheme', 'E11Console', '-derivedDataPath', DD]
        r = subprocess.run(args, env=renv, capture_output=True, text=True, timeout=int(SECS) + 900)
        open(os.path.join(TMP, f'crawl-{tag}.log'), 'w').write(r.stdout[-20000:] + r.stderr[-8000:])
        try: log = json.load(open(os.path.join(OUT, f'crawl-{tag}.json')))
        except Exception as e: log = []; print('no crawl log', tag, e, r.stdout[-3000:], r.stderr[-2000:], flush=True)
        allres[label] = {'email': email, 'secs': round(time.time() - t0), 'log': log, 'exit': r.returncode}
        taps = [x for x in log if x.get('kind') == 'tap']
        nothing = [x for x in taps if x.get('outcome') == 'nothing' and x.get('type') in ('button', 'row', 'switch')]
        lines = [f"== {label} ({email}) — {len(taps)} taps in {round(time.time() - t0)} s, exit {r.returncode}, tabs {next((x.get('tabs') for x in log if x.get('kind') == 'start'), None)}"]
        for x in log:
            if x.get('kind') in ('crash', 'lost', 'timeUp'): lines.append(f"   {x['kind'].upper()}: {' › '.join(x.get('path') or [])} › {x.get('label', '')} {x.get('screen', '')}")
        for x in nothing: lines.append(f"   NOTHING: {' › '.join(x.get('path') or [])} › [{x.get('type')}] {x.get('label')}")
        for x in taps:
            if x.get('outcome', '').startswith('alert'): lines.append(f"   alert: {' › '.join(x.get('path') or [])} › {x.get('label')} → {x['outcome'][:120]}")
        report += lines
        print('\n'.join(lines), flush=True)
        json.dump(allres, open(os.path.join(TMP, 'ios-crawl.json'), 'w'), indent=1)
        open(os.path.join(TMP, 'ios-crawl.txt'), 'w').write('\n'.join(report) + '\n')
finally:
    srv.terminate()
    reps = [f for f in glob.glob(os.path.expanduser('~/Library/Logs/DiagnosticReports/E11Console*.ips')) if os.path.getmtime(f) > T_START]
    for f in sorted(reps, key=os.path.getmtime)[-5:]:
        report.append('CRASH REPORT ' + os.path.basename(f))
        open(os.path.join(OUT, 'crashreport-' + os.path.basename(f) + '.txt'), 'w').write(open(f, errors='replace').read()[:200000])
    json.dump(allres, open(os.path.join(TMP, 'ios-crawl.json'), 'w'), indent=1)
    open(os.path.join(TMP, 'ios-crawl.txt'), 'w').write('\n'.join(report) + '\n')
    with zipfile.ZipFile(os.path.join(TMP, 'ios-crawl-shots.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
        for f in sorted(glob.glob(os.path.join(OUT, '*.png')) + glob.glob(os.path.join(OUT, '*.txt')) + glob.glob(os.path.join(TMP, 'crawl-*.log'))): z.write(f, os.path.basename(f))
    if os.environ.get('RUNNER_ENVIRONMENT') == 'self-hosted':
        try: subprocess.run(['xcrun', 'simctl', 'shutdown', 'all'], capture_output=True, timeout=60)
        except Exception: pass
print('CRAWL DONE', len(allres), 'roles')
