"""The iPhone app on GitHub's Mac: runs it in an iPhone simulator against a local E11 Console server (sample data),
lets it do its self-test (home, Inbox via the native tab bar, a task, back), takes a screenshot at each stage and
checks its answers."""
import signal, glob, json, os, re, subprocess, sys, time, urllib.request
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
    # a film of the whole run (ios-run.mp4), so the moving parts — the shared top buttons, search, a page sliding in —
    # can be watched frame by frame from Claude's workspace; each stage's time in it is printed ('at 12.3s')
    # (simctl itself, in its own process group: Ctrl-C to the whole group lets it finish the file — sent to xcrun alone
    #  it never reached simctl and the film came out empty)
    simctl = sh('xcrun', '-f', 'simctl').stdout.strip() or 'simctl'
    # (a recorder left over from an earlier run holds the screen: this one would make no film)
    subprocess.run(['pkill', '-INT', '-f', 'recordVideo'], capture_output=True); time.sleep(1)
    rec = subprocess.Popen([simctl, 'io', udid, 'recordVideo', '--codec=h264', '--force', os.path.join(TMP, 'ios-run.mp4')], stdout=subprocess.DEVNULL, stderr=open(os.path.join(TMP, 'ios-rec.log'), 'w'), start_new_session=True)
    rec_t0 = time.time()
    r = subprocess.run(['xcrun', 'simctl', 'launch', udid, BUNDLE], env=lenv, capture_output=True, text=True); check(r.returncode == 0, 'launched ' + r.stdout + r.stderr[-300:])
    data = sh('xcrun', 'simctl', 'get_app_container', udid, BUNDLE, 'data').stdout.strip()
    out = os.path.join(data, 'Documents', 'selftest.json')
    seen, res, t0 = set(), {}, time.time()
    while time.time() - t0 < 720:   # (540 until 2026-11-08 — the slide-back checks made it longer, and the last stages were cut off)
        try: res = json.load(open(out))
        except Exception: res = {}
        st = res.get('stage')
        if st and st not in seen:
            seen.add(st); time.sleep(0.5)
            sh('xcrun', 'simctl', 'io', udid, 'screenshot', os.path.join(TMP, f'ios-{st}.png'))
            print('stage', st, f'at {time.time() - rec_t0:.1f}s')
            # (to another app and back, as a person does: Settings opened, then the app again)
            # (light / dark: the phone switched with the app open — the app must follow it by itself)
            if st == 'lookFlip': sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'light')
            if st == 'lookLight': sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')
            if st == 'away':
                sh('xcrun', 'simctl', 'launch', udid, 'com.apple.Preferences'); time.sleep(4)
                sh('xcrun', 'simctl', 'launch', udid, BUNDLE); time.sleep(1)
        if st == 'done': break
        time.sleep(0.5)
    try: os.killpg(rec.pid, signal.SIGINT); rec.wait(timeout=60)
    except Exception: rec.kill()
    try: print('film', os.path.getsize(os.path.join(TMP, 'ios-run.mp4')), 'bytes')
    except Exception as e: print('film: none', e)
    try: print('recorder said:', open(os.path.join(TMP, 'ios-rec.log')).read()[-600:])
    except Exception: pass
    print(json.dumps(res, indent=1)[:4000])
    p = res.get('home') or {}
    # 22: the startup screen is the app's own — there at once, the icon alone (Haris 2026-11-09: "Logo only, then go"), gone before Home
    sg = res.get('splashGeo') or {}
    check('splash' in seen and sg.get('logoOnly') is True and sg.get('iconLayers') == 14 and sg.get('subviews') == 1, f'the startup screen shows at once: the icon alone {sg}')
    hn = res.get('homeNative') or {}
    if hn.get('apple'):
      # (Haris 2026-11-07: Home opened under the small title — it must open with Apple's bar at its big title)
      check((hn.get('appleBarH') or 0) > 80, f"Home opens with the big title (Apple's bar {hn.get('appleBarH')} pt tall)")
    check(hn.get('shown') is True and (hn.get('cards') or 0) > 0 and len(hn.get('stats') or []) == 3 and hn.get('title') in ('E11 Day', 'My Day'), f'Home is the app\'s own, with its boxes and task cards {hn}')
    hsc0 = res.get('homeScrolledNative') or {}
    check(hsc0.get('server') is True, f'Home comes straight from the server (/api/home) {hsc0.get("server")}')
    hs = res.get('homeSwipeNative') or {}; hp = res.get('homePressNative') or {}
    hl = res.get('homeLeadNative') or {}
    # (Home in Apple's list — ios-nav: its swipe actions are Apple's, not driven from here; the cards are in Apple's cells)
    if hn.get('appleList'):
      check((hn.get('listCells') or 0) > 0, f"Home's cards are in Apple's list {hn.get('listCells')}")
    else:
      check(hs.get('open') is True and (hs.get('openShift') or 0) < -80 and (hs.get('actions') or 0) >= 1, f'a Home card swiped left shows Copy link / Delete {hs}')
      check(hl.get('open') is True and hl.get('lead') is True and (hl.get('openShift') or 0) > 80 and (hl.get('actions') or 0) >= 1, f'a Home card swiped right shows Done / Due {hl}')
    check(hp.get('sheet') == 'AttachSheetVC' and hp.get('open') is False, f'a Home card held opens Attach Files {hp}')
    hsc = res.get('homeScrolledNative') or {}; hf = res.get('homeFindNative') or {}; hfd = res.get('homeFindDoneNative') or {}
    if hsc.get('apple'):
      # (Apple's bar: its big title shrinks by itself; the list has scrolled)
      # (the bar holds Apple's search box under the title too, as E11 Talk's: scrolled, it's the big title's height less)
      check(0 < (hsc.get('appleBarH') or 0) < (hn.get('appleBarH') or 0) - 40, f"scrolled, Apple's big title gone up into its small bar ({hn.get('appleBarH')} → {hsc.get('appleBarH')} pt)")
      check(hf.get('searching') is True and (hf.get('results') or 0) > 0, f'Search finds "Ford" {hf}')
    else:
      check((hsc.get('shrink') or 0) >= 0.99 and (hsc.get('smallTitle') or 0) > 0.9, f'scrolled, Home\'s title shrinks into the small bar {hsc}')
      check(hf.get('searching') is True and (hf.get('searchBarW') or 0) > 250 and (hf.get('results') or 0) > 0, f'Search stretches into a bar with results for "Ford" {hf}')
    check(hfd.get('searching') is False, f'the ✕ closes the search {hfd}')
    hd = res.get('homeDateNative') or {}
    check(hd.get('sheet') == 'DateSheetVC', f'the date sheet opens (and the app is still running) {hd.get("sheet")}')
    tp, tps, tpc, tpb = res.get('tpageNative') or {}, res.get('tpageScrolledNative') or {}, res.get('tpageCommentsNative') or {}, res.get('tpageBackNative') or {}
    # (the rule "only what changed changes": to another app and back redraws nothing, and the task page keeps its bands)
    check(res.get('redrawsBefore') is not None and res.get('redrawsAfter') == res.get('redrawsBefore'), f"to another app and back: no screen drawn again {res.get('redrawsBefore')} → {res.get('redrawsAfter')}")
    # (a tab with its own Apple screen follows Home, locked: from a task, ‹ back — "+ New task" there through the slide, as
    #  at rest, on Home, My Tasks and the Inbox alike: Haris 2026-11-08)
    for k, name in (('home', 'Home'), ('mt', 'My Tasks'), ('ibx', 'the Inbox'), ('cl', 'Clients')):
      o, mid, end = res.get(f'slide_{k}_open'), res.get(f'slide_{k}_mid'), res.get(f'slide_{k}_end')
      check(o is True and mid is not None and mid == end, f'{name}: a task opened and ‹ back — "+ New task" as at rest all through the slide (open {o}, in the slide {mid}, after {end})')
    check((res.get('awayBands') or 0) > 0, f"the task page's grey bands still there after coming back {res.get('awayBands')}")
    check(tp.get('copy') is True and tp.get('copyTask') and tp.get('copyTask') == tp.get('title'), f"the app's own copy of the data is ready and gives the task page the server gives {({k: tp.get(k) for k in ('copy', 'copyTask', 'title')})}")
    tsd = res.get('tpageSwipeDetailsNative') or {}
    check(tsd.get('tab') == 'details' and tsd.get('compose') is False and tsd.get('pages') == 1, f"swiped from Comments: Details, no comment box {tsd}")
    check(tp.get('pages') == 1 and tp.get('drawn') is True and tp.get('x') == 0 and tp.get('tabBar') is False and (res.get('tpage') or {}).get('webTask') is False, f"a task opens as the app's own page, drawn from the server, nothing of the website's under it {tp} {res.get('tpage')}")
    # (the Inbox in Apple's navigation: Mark all read is Apple's bar button on its own screen, not the shared corner button)
    _ib = res.get('ibxInbox') or {}
    check(((_ib.get('corner') == 'read' and _ib.get('cornerA', 0) > 0.9) or _ib.get('appleMark') == 'read') and (res.get('homeNative') or {}).get('corner') == ('none' if (res.get('homeNative') or {}).get('apple') else 'search'), f"the corner button: Search on Home, Mark all read on the Inbox {(res.get('homeNative') or {}).get('corner')} {res.get('ibxInbox')}")
    if (res.get('homeNative') or {}).get('apple'):
      check(tp.get('corner') != 'more', f"a task page has Apple's own ‹ and •••, the shared ones stay out {tp.get('corner')}")
    else:
      check(tp.get('corner') == 'more' and tpb.get('corner') != 'more', f"the corner button is the task page's ••• and back again {tp.get('corner')} → {tpb.get('corner')}")
    check((res.get('tpageSheetNative') or {}).get('sheet') == 'NativeSheetVC', f"Assignees opens iPhone's own people sheet (changed by role again) {res.get('tpageSheetNative')}")
    check(tps.get('content', 0) > 300, f"the task page has its rows {tps}")
    check(tpc.get('feed', -1) > 0, f"the comments are the app's own (drawn from the server) {tpc}")
    check(tpc.get('tab') == 'comments' and tpc.get('compose') is True and tpc.get('box') is False, f"its Comments tab has the app's own comment box (not the old one) {tpc}")
    check(tpb.get('pages') == 0 and tpb.get('tabBar') is True and (res.get('tpageBack') or {}).get('webTask') is False, f"back: the page goes, the tab bar is back {tpb}")
    check((res.get('dailyNative') or {}).get('sheet') == 'DailySheetVC', f"the morning round-up opens as iPhone's own sheet {res.get('dailyNative')}")
    mt = res.get('mytasksMyTasks') or {}; mtd = res.get('mytasksDoneMyTasks') or {}; mta = res.get('mytasksAllMyTasks') or {}
    check(mt.get('shown') is True and mt.get('server') is True and mt.get('tab') == 'all' and 'filter-due' in (mt.get('filters') or []), f"My Tasks is the app's own, from the server, with All and its filter buttons {mt}")
    check(mtd.get('shown') is True and mtd.get('tab') == 'done' and 'tab=done' in (mtd.get('query') or ''), f"My Tasks' Done tab asks the server for completed tasks {mtd}")
    check(mta.get('tab') == 'all' and 'tab=all' in (mta.get('query') or ''), f"back to All {mta}")
    ms = res.get('mytasksScrolledMyTasks') or {}
    # (My Tasks under Apple's bar since 2026-11-08: All / Done is the first row of Apple's list, the filters in Apple's menu)
    check(ms.get('apple') is True and ms.get('scope') is True and ms.get('listOn') is True, f"My Tasks in Apple's navigation: All / Done in Apple's search bar's scope bar {ms}")
    check((res.get('mytasksScrolled') or {}).get('blank') is True, f"the page draws nothing under the app's My Tasks {res.get('mytasksScrolled')}")
    check((res.get('mytasksTopMyTasks') or {}).get('pinned') is False, f"back at the top they're with the list again {res.get('mytasksTopMyTasks')}")
    # (the empty-Inbox / empty-Done runs: what the server itself has for this person now, and who's who)
    try:
        hdr = {'X-Dev-Email': EMAIL}
        si = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/inbox?tab=all', headers=hdr), timeout=10).read()).get('home') or {}
        sd = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/mytasks?tab=done', headers=hdr), timeout=10).read()).get('home') or {}
        print('diag server: inbox rows', len(si.get('rows') or []), 'me', si.get('me'), '· done cards', sum(len(g.get('cards') or []) for g in sd.get('groups') or []), 'me', sd.get('me'))
    except Exception as e: print('diag server: failed', e)
    ib = res.get('ibxInbox') or {}; ibs = res.get('ibxSwipeInbox') or {}; ibu = res.get('ibxUnreadInbox') or {}; ibm = res.get('ibxMentionsInbox') or {}
    iba = res.get('ibxAllInbox') or {}
    check(ib.get('shown') is True and ib.get('server') is True and ib.get('tab') == 'unread' and len(ib.get('cats') or []) == 3, f"the Inbox is the app's own, from the server, opening on Unread {ib}")
    check((iba.get('rows') or 0) > 0 and iba.get('tab') == 'all', f"All: a row for each notification {iba}")
    check((res.get('ibx') or {}).get('blank') is True, f"the page draws nothing under the app's Inbox {res.get('ibx')}")
    check(ibs.get('open') is True, f"a row swiped right shows Read / Unread (Apple's own swipe in Apple's list) {ibs}")
    check(ib.get('apple') is True and ib.get('listOn') is True, f"the Inbox in Apple's navigation, its rows in Apple's list {ib}")
    check(ibu.get('tab') == 'unread' and (ibu.get('unreadRows') or 0) == (ibu.get('rows') or 0) and (ibu.get('rows') or 0) <= (iba.get('rows') or 0), f"Unread: only the unread ones, at once {ibu}")
    check(ibm.get('tab') == 'mentions' and (ibm.get('rows') or 0) <= (iba.get('rows') or 0), f"Mentions {ibm}")
    cw = ibu.get('cats') or []
    check(len(cw) == 3 and cw[0] == 49 and cw[1] > 49 and cw[2] == 49, f"the chosen button widens to its name, the others 49 wide {cw}")
    check((res.get('inboxMyTasks') or {}).get('shown') is not True, f"My Tasks isn't over the Inbox {res.get('inboxMyTasks')}")
    check((res.get('inboxNative') or {}).get('shown') is False, f"the app's Home goes on another tab {res.get('inboxNative')}")
    check(res.get('splashGone') is True, f"the startup screen went before Home {res.get('splashGone')}")
    check(set(seen) >= {'home', 'inbox', 'me', 'meTeam', 'meAbout', 'meProfile', 'meTrash', 'meBack', 'client', 'task', 'sheet', 'back', 'nsheet', 'nsheetEnd', 'nsheetChannel', 'nsheetTitled'}, f'all stages ran {sorted(seen)}')
    hf = res.get('homeFrame') or {}
    check(hf.get('web') == hf.get('screen') and hf.get('tabBar') is True, f'the page fills the screen under the floating tab bar {hf}')
    check(int(float(str((p.get('geo') or {}).get('tabsH') or '0').replace('px','') or 0)) > 40, f"the page knows the tab bar's height {p.get('geo')}")
    me = res.get('me') or {}
    mn, mt, ma, mb = res.get('meNative') or {}, res.get('meTeamNative') or {}, res.get('meAboutNative') or {}, res.get('meBackNative') or {}
    check(me.get('native') is True and me.get('blank') is True and me.get('lockRows') == 0, f"Me is the app's own, nothing drawn under it {me}")
    check(mn.get('open') is True and mn.get('kind') == 'me' and mn.get('card') is True and (mn.get('rows') or 0) >= 2 and mn.get('corner') == 'none,none,none', f"the app's Me: your card and its groups, no top buttons {mn}")
    check(mt.get('kind') == 'team' and mt.get('screens') == 2 and (mt.get('people') or 0) >= 1 and (str(mt.get('corner')).startswith('back,') or mt.get('apple') is True), f"Team members slides in over Me, the people in it, ‹ at the top {mt}")
    check(ma.get('kind') == 'about' and (ma.get('parts') or 0) >= 2, f"About: its cards and What's new {ma}")
    mp = res.get('meProfileNative') or {}
    check(mp.get('kind') == 'profile' and mp.get('profile') is True and (mp.get('rows') or 0) >= 4 and (str(mp.get('corner')).startswith('back,') or mp.get('apple') is True), f"My profile: the app's own, its groups, ‹ at the top {mp}")
    mtr = res.get('meTrashNative') or {}
    check(mtr.get('kind') == 'trash' and (mtr.get('parts') or 0) >= 3 and (str(mtr.get('corner')).startswith('back,') or mtr.get('apple') is True), f"Trash: the app's own, its search and categories, ‹ at the top {mtr}")
    check(mb.get('kind') == 'me' and mb.get('screens') == 1, f"‹ back to Me {mb}")
    # light / dark the Apple way (Haris 2026-11-09): every tab's screen follows the phone, none forced, nothing drawn again
    def lookOk(d, style, bright):
      if not isinstance(d, dict) or not d: return False
      scr = [d[k] for k in ('home', 'mytasks', 'inbox', 'clients', 'me') if isinstance(d.get(k), dict)]
      on = [x for x in scr if x.get('shown')]   # (a tab not on show hears the look when it shows again — iPhone's own way)
      return len(scr) >= 3 and len(on) >= 1 and all(x.get('forced') == 0 for x in scr) and all(x.get('style') == style and ((x.get('bg') or 0) > 0.5) == bright for x in on) and d.get('tabBar') == 0
    check(lookOk(res.get('lookAtLight'), 1, True), f"phone to light, app open: every tab's screen light, nothing forced {res.get('lookAtLight')}")
    check(lookOk(res.get('lookAtDark'), 2, False), f"phone back to dark: every tab's screen dark {res.get('lookAtDark')}")
    check(res.get('lookRedrawsAfter') is not None and res.get('lookRedrawsAfter') == res.get('lookRedrawsBefore'), f"the look switched by iPhone itself: no screen drawn again {res.get('lookRedrawsBefore')} → {res.get('lookRedrawsAfter')}")
    # (measurement only — Haris 2026-11-09: the frost on pushed pages at their top; the search bar going back to Client Assets)
    def barLine(b):
      if not isinstance(b, dict) or not b.get('bar'): return str(b)
      bar = b['bar']; l = b.get('list') or {}
      ss = ' '.join(f"[{x.get('ph','')[:18]} y{x.get('y',0):.0f} h{x.get('h',0):.0f} a{x.get('a',0):.2f}]" for x in (b.get('search') or []))
      return f"{b.get('top','')} bar y{bar.get('y',0):.0f}+{bar.get('h',0):.0f} list off{l.get('off','-')} adj{l.get('adj','-')} ins{l.get('ins','-')} cell{l.get('firstCell','-')} edge {l.get('edgeStyle','-')} hidden{l.get('edgeHidden','-')} {ss}"
    for k in ('frost_team', 'frost_assetsAll', 'frost_assetsClient'): print('measure', k, barLine(res.get(k)))
    print('measure snapOpened', res.get('snapOpened'))
    print('measure formNotes', json.dumps(res.get('formNotes')))
    tf = res.get('task_open') or []
    t1 = tf[0].get('t', 0) if tf else 0
    for f in tf:
      sg, ss, nb, tb = f.get('seg') or {}, f.get('segSuper') or {}, f.get('navBar') or {}, f.get('tabBar') or {}
      print('measure task_open', f"{(f.get('t',0) - t1) * 1000:5.0f}ms seg x{sg.get('x',0):.1f} y{sg.get('y',0):.1f} w{sg.get('w',0):.1f} h{sg.get('h',0):.1f} a{sg.get('a',0):.2f} | holder y{ss.get('y',0):.1f} h{ss.get('h',0):.1f} | bar y{nb.get('y',0):.1f} h{nb.get('h',0):.1f} | tabs hidden{f.get('tabHidden')} y{tb.get('y',0):.0f} a{tb.get('a',0):.2f} | safeB{f.get('safeBottom')} list off{f.get('listOff')} adj{f.get('listAdj')}")
    fr = res.get('snap_back') or []
    t0 = fr[0].get('t', 0) if fr else 0
    for f in fr: print('measure snap_back', f"{(f.get('t',0) - t0) * 1000:5.0f}ms", barLine(f))
    check(res.get('meRowsBefore') is not None and res.get('meRowsAfter') == res.get('meRowsBefore'), f"Me opened again: no row drawn again {res.get('meRowsBefore')} → {res.get('meRowsAfter')}")
    check((res.get('client') or {}).get('wide') is False, f"Client Assets folder fits the screen {res.get('client')}")
    ca = res.get('clientAssets') or {}
    # (opened from the page — a link, an Inbox update, a client's page — just that folder, so ‹ goes back where you came from:
    #  Haris 2026-11-04; it was the client's screen, then the folder, before)
    check(ca.get('open') is True and ca.get('kind') == 'folder' and (ca.get('screens') or 0) >= 1 and (ca.get('parts') or 0) >= 1 and ca.get('shown') is True, f"a Client Assets folder opens as the app's own screen, just the folder {ca}")
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
    # 20: the task's Comments on their own screen, scrolled by iOS: shown over the task, at the latest comment; with the
    # keyboard up still at the latest (the room under it the keyboard's and the box's); down again, at the latest
    w0, w1, w2 = res.get('cwebGeo') or {}, res.get('cwebKbGeo') or {}, res.get('cwebDownGeo') or {}
    check(w0.get('made') and w0.get('loaded') and w0.get('shown') and w0.get('atEnd'), f'the comments screen shows the task, at the latest comment {w0}')
    check(w1.get('shown') and w1.get('atEnd') and (w1.get('ty') or 0) < -300 and abs((w1.get('height') or 0) - (w0.get('height') or 0)) < 2, f'keyboard up: comments still at the latest, slid up above the keyboard, same size {w1}')
    check(w2.get('shown') and w2.get('atEnd') and abs(w2.get('ty') or 0) < 1, f'keyboard down: at the latest, back in place {w2}')
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
