"""The App Store screenshots that need a finger (Haris 2026-11-14): ios/UITests/ShotsTests.swift run by Apple's UI testing
in the 6.9" simulator, dark, 9:41 and full bars, against a local server holding only the App Review copy's made-up demo data
(ios/shots-demo.mjs) — as the person whose Inbox has comments to peek at and today's birthday. The screenshots go to
ios-hold-shots.zip on the release ios-selftest. Nothing is signed or sent.
Usage: python3 ios/shots_ui.py <derivedDataPath>"""
import glob, json, os, re, shutil, subprocess, sys, time, urllib.request, zipfile
PORT = 18452
BASE = f'http://127.0.0.1:{PORT}'
TMP = os.environ.get('RUNNER_TEMP', '/tmp')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DD = sys.argv[1]
EMAIL = 'review@e11hq.com'
WHO = os.environ.get('SHOTS_WHO', 'leila.aziz@example.com')
OUT = os.path.join(TMP, 'hold-out'); shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
DATA = os.path.join(TMP, 'holddata'); shutil.rmtree(DATA, ignore_errors=True)
def sh(*a, **k): return subprocess.run(list(a), capture_output=True, text=True, **k)
made = json.loads(sh('node', os.path.join(ROOT, 'ios', 'shots-demo.mjs'), DATA, EMAIL).stdout.strip().splitlines()[-1])
print('demo data', made, flush=True)
env = dict(os.environ, AUTH_DEV='1', DATA_DIR=DATA, PORT=str(PORT), ADMIN_EMAIL=EMAIL, APP_VERSION='9.9.9-test.1', SHARE_DIR='')
srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=open(os.path.join(TMP, 'hold-server.log'), 'w'), stderr=subprocess.STDOUT)
try:
    for _ in range(60):
        try: urllib.request.urlopen(BASE + '/api/health', timeout=2); break
        except Exception: time.sleep(0.5)
    devs = json.loads(sh('xcrun', 'simctl', 'list', 'devices', 'available', '-j').stdout)['devices']
    rtv = lambda rt: [int(x) for x in re.findall(r'(\d+)', rt.split('iOS')[-1])[:2]]
    ph = sorted([(rtv(rt), d) for rt, ds in devs.items() if 'iOS' in rt for d in ds if re.match(r'iPhone \d+ Pro Max$', d['name'])], key=lambda x: (x[0], x[1]['name']))
    udid = ph[-1][1]['udid']; print('simulator', ph[-1][1]['name'], flush=True)
    sh('xcrun', 'simctl', 'boot', udid); sh('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=300)
    sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')
    sh('xcrun', 'simctl', 'status_bar', udid, 'clear')
    sh('xcrun', 'simctl', 'status_bar', udid, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularMode', 'active', '--cellularBars', '4', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3')
    sh('xcrun', 'simctl', 'uninstall', udid, 'ae.e11.console.ios')
    xctr = glob.glob(os.path.join(DD, 'Build', 'Products', '*.xctestrun'))
    renv = dict(os.environ, TEST_RUNNER_E11_EMAIL=WHO, TEST_RUNNER_E11_SERVER=BASE, TEST_RUNNER_E11_CRAWL_OUT=OUT)
    args = ['xcodebuild', 'test-without-building', '-destination', f'id={udid}', '-only-testing:E11ConsoleUITests/ShotsTests/testHold', '-resultBundlePath', os.path.join(TMP, 'hold.xcresult')]
    args += ['-xctestrun', xctr[0]] if xctr else ['-project', os.path.join(ROOT, 'ios/E11Console.xcodeproj'), '-scheme', 'E11Console', '-derivedDataPath', DD]
    r = subprocess.run(args, env=renv, capture_output=True, text=True, timeout=1200)
    print('exit', r.returncode, r.stdout[-2500:], r.stderr[-1500:], flush=True)
    sh('xcrun', 'simctl', 'status_bar', udid, 'clear')
finally:
    srv.terminate()
    with zipfile.ZipFile(os.path.join(TMP, 'ios-hold-shots.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
        for f in sorted(glob.glob(os.path.join(OUT, '*.png'))): z.write(f, os.path.basename(f))
    print('shots', len(glob.glob(os.path.join(OUT, '*.png'))), flush=True)
