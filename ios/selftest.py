"""The iPhone app on GitHub's Mac: runs it in an iPhone simulator against a local E11 Console server (sample data),
lets it do its self-test (home, Inbox via the native tab bar, a task, back), takes a screenshot at each stage and
checks its answers."""
import json, os, subprocess, sys, time, urllib.request
PORT = 18450
BASE = f'http://127.0.0.1:{PORT}'
TMP = os.environ.get('RUNNER_TEMP', '/tmp')
EMAIL = 'haris@e11-digital.com'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = sys.argv[1]
BUNDLE = 'ae.e11.console.ios'
fails = []
def check(ok, what):
    print(('ok   ' if ok else 'FAIL ') + what); (None if ok else fails.append(what))
def sh(*a, **k): return subprocess.run(list(a), capture_output=True, text=True, **k)

env = dict(os.environ, AUTH_DEV='1', DATA_DIR=os.path.join(TMP, 'iosdata'), PORT=str(PORT), ADMIN_EMAIL=EMAIL, APP_VERSION='9.9.9-test.1', SHARE_DIR='')
srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=open(os.path.join(TMP, 'ios-server.log'), 'w'), stderr=subprocess.STDOUT)
try:
    for _ in range(60):
        try: urllib.request.urlopen(BASE + '/api/health', timeout=2); break
        except Exception: time.sleep(0.5)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': EMAIL, 'Content-Type': 'application/json'}), timeout=60)
    devs = json.loads(sh('xcrun', 'simctl', 'list', 'devices', 'available', '-j').stdout)['devices']
    phones = [d for rt, ds in devs.items() if 'iOS' in rt for d in ds if d['name'].startswith('iPhone') and 'Pro Max' not in d['name']]
    phones.sort(key=lambda d: d['name'])
    dev = phones[-1]; udid = dev['udid']
    print('simulator', dev['name'], udid)
    sh('xcrun', 'simctl', 'boot', udid); sh('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=300)
    sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')
    r = sh('xcrun', 'simctl', 'install', udid, APP); check(r.returncode == 0, 'installed ' + r.stderr[-300:])
    lenv = dict(os.environ, SIMCTL_CHILD_E11_SERVER=BASE, SIMCTL_CHILD_E11_SELFTEST='1', SIMCTL_CHILD_E11_SELFTEST_EMAIL=EMAIL)
    r = subprocess.run(['xcrun', 'simctl', 'launch', udid, BUNDLE], env=lenv, capture_output=True, text=True); check(r.returncode == 0, 'launched ' + r.stdout + r.stderr[-300:])
    data = sh('xcrun', 'simctl', 'get_app_container', udid, BUNDLE, 'data').stdout.strip()
    out = os.path.join(data, 'Documents', 'selftest.json')
    seen, res, t0 = set(), {}, time.time()
    while time.time() - t0 < 150:
        try: res = json.load(open(out))
        except Exception: res = {}
        st = res.get('stage')
        if st and st not in seen:
            seen.add(st); time.sleep(0.5)
            sh('xcrun', 'simctl', 'io', udid, 'screenshot', os.path.join(TMP, f'ios-{st}.png'))
            print('stage', st)
        if st == 'done': break
        time.sleep(0.5)
    print(json.dumps(res, indent=1)[:4000])
    p = res.get('page') or {}
    check(set(seen) >= {'home', 'inbox', 'task', 'done'}, f'all stages ran {sorted(seen)}')
    check(p.get('ios') is True and p.get('isIOSApp') is True and p.get('isMacApp') is False, 'the web app knows it is in the iPhone app (not the Mac app)')
    check(p.get('phone') is True, 'phone layout')
    check(p.get('webTabsShown') is False, "the page's own tab bar is hidden (the app draws a native one)")
    check((p.get('appInfo') or {}).get('native') == 'ios', f"appInfo {p.get('appInfo')}")
    check('Unknown command' in str(p.get('unknown')), 'unknown commands answered')
    check(len(res.get('tabs') or []) >= 4 and 'inbox' in (res.get('tabs') or []), f"native tab bar has the page's tabs {res.get('tabs')}")
    check((res.get('inbox') or {}).get('view') == 'inbox', f"tapping the native Inbox tab opens the Inbox {res.get('inbox')}")
    check((res.get('task') or {}).get('taskOpen') is True and (res.get('back') or {}).get('taskOpen') is False, 'a task opens and closes')
finally:
    srv.terminate()
print('FAILS', len(fails), fails)
sys.exit(1 if fails else 0)
