"""Checks the Swift Mac app on GitHub's Mac: install it with the real installer from a local server, start it
in self-test mode (it loads the web app and calls every bridge command), then check its answers."""
import json, os, subprocess, sys, time, urllib.request
PORT = 18440
BASE = f'http://127.0.0.1:{PORT}'
TMP = os.environ.get('RUNNER_TEMP', '/tmp')
OUT = os.path.join(TMP, 'selftest.json')
EMAIL = 'haris@e11-digital.com'
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
fails = []
def check(ok, what):
    print(('ok   ' if ok else 'FAIL ') + what); (None if ok else fails.append(what))

env = dict(os.environ, AUTH_DEV='1', DATA_DIR=os.path.join(TMP, 'data'), PORT=str(PORT), ADMIN_EMAIL=EMAIL, APP_VERSION='9.9.9-test.1',
           OFFICE_IP='127.0.0.1', LOCAL_PORT='18443', LOCAL_URL='https://127.0.0.1:18443', SHARE_DIR='')   # (this Mac is "the office")
srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=open(os.path.join(TMP, 'server.log'), 'w'), stderr=subprocess.STDOUT)
try:
    for _ in range(60):
        try: urllib.request.urlopen(BASE + '/api/health', timeout=2); break
        except Exception: time.sleep(0.5)
    sh = urllib.request.urlopen(BASE + '/install').read().decode()
    check('LEGACY="${E11_LEGACY:-0}"' in sh, 'installer served, Swift app chosen')
    check('LEGACY="${E11_LEGACY:-1}"' in urllib.request.urlopen(BASE + '/install/legacy').read().decode(), 'legacy installer served')
    check(len(urllib.request.urlopen(BASE + '/install/E11Console.zip').read()) > 100000, 'Swift build served')
    # first the earlier app (as on the team's Macs today), then the Swift app over it, as Update now does
    r = subprocess.run(['bash', '-c', f'curl -fsSL {BASE}/install/legacy | bash'], capture_output=True, text=True, timeout=300)
    legacy = [d for d in ['/Applications/E11 Console Test.app', os.path.expanduser('~/Applications/E11 Console Test.app')] if os.path.isdir(d)]
    check(r.returncode == 0 and legacy and os.path.isfile(os.path.join(legacy[0], 'Contents/MacOS/applet')), 'the earlier app installs from /install/legacy ' + r.stdout[-300:])
    time.sleep(4)
    r = subprocess.run(['bash', '-c', f'curl -fsSL {BASE}/install | bash'], capture_output=True, text=True, timeout=300)
    print(r.stdout[-1500:], r.stderr[-1500:])
    check(r.returncode == 0 and 'Done!' in r.stdout, 'installer finished')
    app = '/Applications/E11 Console Test.app'
    if not os.path.isdir(app): app = os.path.expanduser('~/Applications/E11 Console Test.app')
    exe = os.path.join(app, 'Contents/MacOS/E11 Console Test')
    check(os.path.isfile(exe) and not os.path.exists(os.path.join(app, 'Contents/MacOS/applet')), 'the Swift app replaced the earlier one')
    lipo = subprocess.run(['lipo', '-archs', exe], capture_output=True, text=True).stdout
    check('arm64' in lipo and 'x86_64' in lipo, f'runs on Apple silicon and Intel ({lipo.strip()})')
    v = subprocess.run(['codesign', '--verify', '--deep', '--strict', app], capture_output=True, text=True)
    check(v.returncode == 0, 'signed for this Mac ' + v.stderr.strip())
    pl = subprocess.run(['plutil', '-convert', 'json', '-o', '-', os.path.join(app, 'Contents/Info.plist')], capture_output=True, text=True).stdout
    pl = json.loads(pl)
    check(pl.get('E11ServerURL') == BASE and pl.get('CFBundleIdentifier') == 'ae.e11.console.client.test', 'server and app id in the app')
    check(pl['CFBundleURLTypes'][0]['CFBundleURLSchemes'] == ['e11console-test'], 'task links scheme')
    check(pl.get('CFBundleIconName') == 'AppIcon' and os.path.isfile(os.path.join(app, 'Contents/Resources/Assets.car')), 'the glass everyday icon is in the app')
    subprocess.run(['swift', os.path.join(ROOT, 'mac/swift/icon-preview.swift'), app, os.path.join(TMP, 'icon')], capture_output=True, text=True, timeout=300)
    check(os.path.exists(os.path.join(TMP, 'icon-light.png')), 'a picture of the icon as macOS draws it')
    time.sleep(3)
    subprocess.run(['osascript', '-e', 'tell application id "ae.e11.console.client.test" to quit'], capture_output=True)
    time.sleep(2)
    subprocess.run(['pkill', '-f', 'E11 Console Test.app/Contents/MacOS'], capture_output=True)
    time.sleep(1)
    if os.path.exists(OUT): os.remove(OUT)
    st = subprocess.run([exe], env=dict(os.environ, E11_SELFTEST=OUT, E11_SELFTEST_EMAIL=EMAIL), capture_output=True, text=True, timeout=150)
    print('app exit', st.returncode, st.stderr[-2000:])
    check(os.path.exists(OUT), 'self-test finished and wrote its answers')
    res = json.load(open(OUT)) if os.path.exists(OUT) else {}
    try:
        errs = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/client-errors', headers={'X-Dev-Email': EMAIL})).read())
        for e in (errs.get('errors') or errs.get('list') or []): print('PAGE ERROR', e.get('message'), '\n', (e.get('stack') or '')[:1500])
    except Exception as e: print('no error list', e)
    print(json.dumps(res, indent=1)[:4000])
    c = res.get('calls', {})
    check(not res.get('error'), 'no self-test error: ' + str(res.get('error')))
    check(res.get('page') == 'mac', 'the web app loaded and sees the Mac app')
    ai = c.get('appInfo', {})
    check(res.get('closedVisible') is False and res.get('reopenedVisible') is True, 'closing the window keeps the app running; the Dock icon brings it back')
    check(res.get('loginOn') is True and res.get('loginOff') is True, 'Open at Login turns on and off')
    check(ai.get('shell') == 11 and ai.get('glass') is True and ai.get('native') == 'swift' and ai.get('server') == BASE, f'appInfo {ai}')
    for k in ['badge', 'badgeOff', 'notify', 'light', 'dark', 'save1', 'save2']:
        check((c.get(k) or {}).get('ok') is True, f'{k} answered ok: {c.get(k)}')
    check(res.get('saved') == 'hello mac', 'a download saved in pieces into Downloads: ' + repr(res.get('saved')))
    check('error' in (c.get('badURL') or {}), 'only web links open')
    check('Unknown command' in str((c.get('unknown') or {}).get('error')), 'unknown command answered')
    check('error' in (c.get('chunkGone') or {}), 'reading a file not picked is refused')
    check((c.get('share') or {}).get('onShare') is False, f"a file on this Mac isn't on the shared folder {c.get('share')}")
    up = c.get('upLocal') or {}
    check(up.get('state') == 'done' and (up.get('file') or {}).get('size') == 20000000, f'office-network upload with the pinned certificate {up}')
    check((c.get('upBadPin') or {}).get('state') == 'error', f"a server with another certificate gets nothing {c.get('upBadPin')}")
    dl = os.path.expanduser('~/Downloads/e11-office-dl.bin')
    check((c.get('dlLocal') or {}).get('ok') is True and os.path.exists(dl) and os.path.getsize(dl) == 20000000, f"office-network download {c.get('dlLocal')}")
    dl2 = os.path.expanduser('~/Downloads/e11-office-dl2.bin'); j = c.get('dlJob') or {}
    check(j.get('job') and j.get('state') == 'done' and j.get('size') == 20000000 and os.path.exists(dl2) and os.path.getsize(dl2) == 20000000, f'office-network download with progress (Mac app 11) {j}')
    check(c.get('macChrome') is True and c.get('macBar') is True, 'the page draws its own title bar (Mac app 4+)')
    check(c.get('updateBar') is False, 'no update bar for the newest Mac app')
    check(c.get('notifClick') == 'function' and c.get('openTask') == 'function', 'notification click and task links wired')
    lights = res.get('lights') or {}
    check(abs(lights.get('x', 0) - 20) < 1, f'window buttons placed in the page’s top row {lights}')
    check(os.path.exists(OUT[:-5] + '.png') and os.path.getsize(OUT[:-5] + '.png') > 20000, 'a picture of the window')
finally:
    srv.terminate()
print('FAILS', len(fails), fails)
sys.exit(1 if fails else 0)
