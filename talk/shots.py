"""E11 Talk's App Store screenshots (Haris 2026-11-14): talk/UITests/TalkShotsTests.swift run by Apple's UI testing in the
6.9" simulator, light, 9:41 and full bars, against a local server holding only the App Review copy's made-up demo data
(E11 Console's — ios/shots-demo.mjs — and Talk's chats — talk/shots-demo.mjs), signed in as the reviewer through the
simulator test build's own sign-in (Net.swift, #if DEBUG). Screenshots: talk-shots.zip on the release talk-selftest.
Nothing is signed or sent. Usage: python3 talk/shots.py <derivedDataPath>"""
import glob, json, os, re, shutil, subprocess, sys, time, urllib.request, zipfile
PORT = 18462
BASE = f'http://127.0.0.1:{PORT}'
TMP = os.environ.get('RUNNER_TEMP', '/tmp')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DD = sys.argv[1]
EMAIL = 'review@e11hq.com'
OUT = os.path.join(TMP, 'talk-shots-out'); shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
DATA = os.path.join(TMP, 'talkshotsdata'); shutil.rmtree(DATA, ignore_errors=True)
def sh(*a, **k): return subprocess.run(list(a), capture_output=True, text=True, **k)
r1 = sh('node', os.path.join(ROOT, 'ios', 'shots-demo.mjs'), DATA, EMAIL); print('console demo', r1.stdout[-400:], r1.stderr[-600:], flush=True)
r2 = sh('node', os.path.join(ROOT, 'talk', 'shots-demo.mjs'), DATA, EMAIL); print('talk demo', r2.stdout[-400:], r2.stderr[-1200:], flush=True)
env = dict(os.environ, AUTH_DEV='1', DATA_DIR=DATA, PORT=str(PORT), ADMIN_EMAIL=EMAIL, APP_VERSION='9.9.9-test.1', SHARE_DIR='')
srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=open(os.path.join(TMP, 'talk-shots-server.log'), 'w'), stderr=subprocess.STDOUT)
try:
    for _ in range(60):
        try: urllib.request.urlopen(BASE + '/api/health', timeout=2); break
        except Exception: time.sleep(0.5)
    try:
        req = urllib.request.Request(BASE + '/api/talk/state', headers={'X-Dev-Email': EMAIL})
        st = json.loads(urllib.request.urlopen(req, timeout=20).read()); print('talk state groups', len(st.get('groups') or []), flush=True)
    except Exception as e: print('talk state failed', e, flush=True)
    devs = json.loads(sh('xcrun', 'simctl', 'list', 'devices', 'available', '-j').stdout)['devices']
    rtv = lambda rt: [int(x) for x in re.findall(r'(\d+)', rt.split('iOS')[-1])[:2]]
    ph = sorted([(rtv(rt), d) for rt, ds in devs.items() if 'iOS' in rt for d in ds if re.match(r'iPhone \d+ Pro Max$', d['name'])], key=lambda x: (x[0], x[1]['name']))
    udid = ph[-1][1]['udid']; print('simulator', ph[-1][1]['name'], flush=True)
    sh('xcrun', 'simctl', 'boot', udid); sh('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=300)
    sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'light')
    sh('xcrun', 'simctl', 'status_bar', udid, 'clear')
    sh('xcrun', 'simctl', 'status_bar', udid, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularMode', 'active', '--cellularBars', '4', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3')
    sh('xcrun', 'simctl', 'uninstall', udid, 'ae.e11.talk.ios')
    xctr = glob.glob(os.path.join(DD, 'Build', 'Products', '*.xctestrun'))
    renv = dict(os.environ, TEST_RUNNER_E11_EMAIL=EMAIL, TEST_RUNNER_E11_SERVER=BASE, TEST_RUNNER_E11_SHOTS_OUT=OUT)
    args = ['xcodebuild', 'test-without-building', '-destination', f'id={udid}', '-only-testing:E11TalkUITests/TalkShotsTests', '-resultBundlePath', os.path.join(TMP, 'talkshots.xcresult')]
    args += ['-xctestrun', xctr[0]] if xctr else ['-project', os.path.join(ROOT, 'talk/E11Talk.xcodeproj'), '-scheme', 'E11Talk', '-derivedDataPath', DD]
    r = subprocess.run(args, env=renv, capture_output=True, text=True, timeout=1800)
    print('exit', r.returncode, r.stdout[-3000:], r.stderr[-1500:], flush=True)
    sh('xcrun', 'simctl', 'status_bar', udid, 'clear')
finally:
    srv.terminate()
    with zipfile.ZipFile(os.path.join(TMP, 'talk-shots.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
        for f in sorted(glob.glob(os.path.join(OUT, '*.png'))): z.write(f, os.path.basename(f))
        lg = os.path.join(TMP, 'talk-shots-server.log')
        if os.path.exists(lg): z.write(lg, 'server.log')
    print('shots', len(glob.glob(os.path.join(OUT, '*.png'))), flush=True)
