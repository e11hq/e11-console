"""The iPhone app on GitHub's Mac: runs it in an iPhone simulator against a local E11 Console server (sample data),
lets it do its self-test (home, Inbox via the native tab bar, a task, back), takes a screenshot at each stage and
checks its answers."""
import glob, json, os, re, subprocess, sys, time, urllib.request
PORT = 18450
BASE = f'http://127.0.0.1:{PORT}'
TMP = os.environ.get('RUNNER_TEMP', '/tmp')
T_START = time.time()
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
    # (an ordinary numbered iPhone on the newest iOS: e.g. not the iPhone Duo, which sorts after them by name)
    rtv = lambda rt: [int(x) for x in re.findall(r'(\d+)', rt.split('iOS')[-1])[:2]]
    phones = [(rtv(rt), d) for rt, ds in devs.items() if 'iOS' in rt for d in ds if re.match(r'iPhone \d', d['name']) and 'Pro Max' not in d['name']]
    if not phones: phones = [(rtv(rt), d) for rt, ds in devs.items() if 'iOS' in rt for d in ds if d['name'].startswith('iPhone')]
    phones.sort(key=lambda x: (x[0], x[1]['name']))
    dev = phones[-1][1]; udid = dev['udid']
    print('simulator', dev['name'], udid)
    sh('xcrun', 'simctl', 'boot', udid); sh('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=300)
    sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')
    # (a fresh install: on our own Mac the simulator keeps the app's data between runs, and the last run's finished
    #  selftest.json made every later run stop at once — no stages, old screenshots, an old app's answers)
    sh('xcrun', 'simctl', 'terminate', udid, BUNDLE); sh('xcrun', 'simctl', 'uninstall', udid, BUNDLE)
    r = sh('xcrun', 'simctl', 'install', udid, APP); check(r.returncode == 0, 'installed ' + r.stderr[-300:])
    try: os.remove(os.path.join(sh('xcrun', 'simctl', 'get_app_container', udid, BUNDLE, 'data').stdout.strip(), 'Documents', 'selftest.json'))
    except Exception: pass
    lenv = dict(os.environ, SIMCTL_CHILD_E11_SERVER=BASE, SIMCTL_CHILD_E11_SELFTEST='1', SIMCTL_CHILD_E11_SELFTEST_EMAIL=EMAIL)
    r = subprocess.run(['xcrun', 'simctl', 'launch', udid, BUNDLE], env=lenv, capture_output=True, text=True); check(r.returncode == 0, 'launched ' + r.stdout + r.stderr[-300:])
    data = sh('xcrun', 'simctl', 'get_app_container', udid, BUNDLE, 'data').stdout.strip()
    out = os.path.join(data, 'Documents', 'selftest.json')
    seen, res, t0 = set(), {}, time.time()
    while time.time() - t0 < 480:
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
    p = res.get('home') or {}
    check(set(seen) >= {'home', 'inbox', 'me', 'client', 'task', 'sheet', 'back', 'nsheet', 'nsheetEnd', 'nsheetChannel', 'nsheetTitled'}, f'all stages ran {sorted(seen)}')
    hf = res.get('homeFrame') or {}
    check(hf.get('web') == hf.get('screen') and hf.get('tabBar') is True, f'the page fills the screen under the floating tab bar {hf}')
    check(int(float(str((p.get('geo') or {}).get('tabsH') or '0').replace('px','') or 0)) > 40, f"the page knows the tab bar's height {p.get('geo')}")
    me = res.get('me') or {}
    check(me.get('lockRows') == 1 and me.get('pushRows') == 1, f'one Face ID row after repaints {me}')
    check((res.get('client') or {}).get('wide') is False, f"Client Assets folder fits the screen {res.get('client')}")
    sh_ = res.get('sheet') or {}; g = sh_.get('geo') or {}
    check(sh_.get('menuBottom') is not None and sh_['menuBottom'] <= (g.get('innerH') or 0) + 1 and sh_['menuBottom'] - sh_.get('menuTop', 0) > 300, f'the comment sheet is fully on screen, all of it showing {sh_}')
    # native sheets: the same room above (TOP, 30) and below (as on the Channel sheet) everywhere; a long list's last
    # option clear of the bottom edge at the end of the scroll
    ch_ = res.get('nsheetChannelGeo') or {}; gap = ch_.get('endGap')
    for k in ('nsheet', 'nsheetEnd', 'nsheetChannel', 'nsheetTitled'):
        g_ = res.get(k + 'Geo') or {}
        check(abs((g_.get('topGap') or 0) - 30) <= 1, f'native sheet {k}: first thing 30 under the top edge {g_}')
    for k in ('nsheetEnd', 'nsheetTitled'):
        g_ = res.get(k + 'Geo') or {}
        check(gap is not None and g_.get('endGap') is not None and abs(g_['endGap'] - gap) <= 2, f'native sheet {k}: gap under the last option {g_.get("endGap")} = Channel\'s {gap}')
    check((res.get('nsheetGeo') or {}).get('scrolls') is True, 'the long native sheet scrolls')
    # 19: Comments with the keyboard (a pretend one): iOS moves the list itself, it stays at the latest comment, and once
    # the keyboard is up the page keeps the room (same picture); down again, the room goes and it's still at the latest
    f0, f1, f2 = res.get('cfeed') or {}, res.get('cfeedKb') or {}, res.get('cfeedDown') or {}
    g1 = res.get('cfeedKbGeo') or {}
    check(f0.get('on') is True and (f0.get('toEnd') or 0) <= 60, f'a task opened on Comments, at the latest comment {f0}')
    check(g1.get('found') is True, f'iOS found the comments list to move with the keyboard {g1}')
    check(f1.get('kbpad') == f"{round(g1.get('T') or 0)}px" and not f1.get('transform') and abs(f1.get('toEnd', 99)) <= 4 and (g1.get('inset') == 0), f'keyboard up: still at the latest comment, the page keeps the room {f1} {g1}')
    check(f2.get('kbpad') in ('0px', '') and abs(f2.get('toEnd', 99)) <= 4, f'keyboard down: room gone, still at the latest comment {f2} {res.get("cfeedDownGeo")}')
    fr = res.get('frame') or {}
    print('note ' + ('ok' if (fr.get('insetTop') or 0) >= 20 else 'CHECK SCREENSHOT') + f" the sign-in page clears the status bar {fr} {res.get('signin')}")   # (needs the internet: not a blocker)
    print('note ' + ('ok' if fr.get('reviewLink') is True or 'cloudflareaccess' not in str(fr.get('host')) else 'CHECK SCREENSHOT') + f" the App Review sign-in link shows under the sign-in page {fr.get('host')} {fr.get('reviewLink')}")   # (needs the internet)
    check(fr.get('privacy') is True, f"Apple's privacy manifest is in the app {fr.get('privacy')}")
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
    # if the app crashed: the newest crash report (on our own Mac, macOS keeps the simulator's apps' reports) goes with the results
    try:
        reps = [f for f in glob.glob(os.path.expanduser('~/Library/Logs/DiagnosticReports/E11Console*.ips')) if os.path.getmtime(f) > T_START]
        if reps:
            rep = max(reps, key=os.path.getmtime)
            open(os.path.join(TMP, 'ios-crash.txt'), 'w').write(open(rep, errors='replace').read()[:200000])
            print('CRASH report', os.path.basename(rep))
    except Exception as e: print('crash report not read', e)
    # (on our own Mac: the simulator is shut down again, so it doesn't stay running in the background)
    if os.environ.get('RUNNER_ENVIRONMENT') == 'self-hosted':
        try: subprocess.run(['xcrun', 'simctl', 'shutdown', 'all'], capture_output=True, timeout=60)
        except Exception: pass
print('FAILS', len(fails), fails)
sys.exit(1 if fails else 0)
