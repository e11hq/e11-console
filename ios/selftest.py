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
# (a quick build — Haris 2026-11-09: these groups of the app's steps are left out, and the checks that need them)
QUICK = ['me', 'look', 'form', 'nsheet', 'daily', 'snap', 'storage', 'slide', 'titles', 'first', 'client']
SKIP = QUICK if os.environ.get('E11_QUICK') == 'yes' else []
def check(ok, what, need=()):
    if any(n.startswith(g) for n in need for g in SKIP): print('skip ' + what); return
    print(('ok   ' if ok else 'FAIL ') + what); (None if ok else fails.append(what))
def sh(*a, **k): return subprocess.run(list(a), capture_output=True, text=True, **k)

env = dict(os.environ, AUTH_DEV='1', DATA_DIR=os.path.join(TMP, 'iosdata'), PORT=str(PORT), ADMIN_EMAIL=EMAIL, APP_VERSION='9.9.9-test.1', SHARE_DIR='')
srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=open(os.path.join(TMP, 'ios-server.log'), 'w'), stderr=subprocess.STDOUT)
try:
    for _ in range(60):
        try: urllib.request.urlopen(BASE + '/api/health', timeout=2); break
        except Exception: time.sleep(0.5)
    # (the full sample, with Client Assets clients — the plain one has none; else the plain one)
    try: fresh = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample/reset', method='POST', data=b'{}', headers={'X-Dev-Email': EMAIL, 'Content-Type': 'application/json'}), timeout=120).read() or b'{}').get('ok')
    except Exception as e: print('sample reset failed', e); fresh = False
    if not fresh: urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': EMAIL, 'Content-Type': 'application/json'}), timeout=60)
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
    # (the app runs without the website — Haris 2026-11-11: what to open is picked here from the server's own data, as the
    #  page used to pick it: a task with comments and a checklist, not locked or in review; one in CD review with subtasks or a
    #  checklist; a client's folder with more than one file)
    pick = {}
    try:
        snap = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + '/api/snapshot', headers={'X-Dev-Email': EMAIL}), timeout=30).read())
        db = snap.get('data') or {}
        tasks = db.get('tasks') or []
        free = lambda x: not x.get('parentId') and not x.get('done') and not x.get('lockedAt') and not (x.get('reviews') or [])
        t = next((x for x in tasks if free(x) and x.get('comments') and x.get('checklist')), None) or next((x for x in tasks if free(x) and x.get('comments')), None) or next((x for x in tasks if free(x)), None) or next((x for x in tasks if not x.get('parentId') and not x.get('done')), None)
        rv = lambda x: not x.get('parentId') and not x.get('done') and any(r.get('state') == 'pending' for r in (x.get('reviews') or []))
        subs = lambda x: any(y.get('parentId') == x.get('id') for y in tasks)
        r = next((x for x in tasks if rv(x) and subs(x) and x.get('checklist')), None) or next((x for x in tasks if rv(x) and (subs(x) or x.get('checklist'))), None) or next((x for x in tasks if rv(x)), None)
        cls = db.get('clients') or []
        c = next((x for x in cls if any(len(f.get('files') or []) > 1 for f in (x.get('folders') or []))), None) or (cls[0] if cls else None)
        f = next((y for y in ((c or {}).get('folders') or []) if len(y.get('files') or []) > 1), None) or (((c or {}).get('folders') or [None])[0])
        pick = {'task': (t or {}).get('id', ''), 'review': (r or {}).get('id', ''), 'client': (c or {}).get('id', ''), 'folder': (f or {}).get('id', '')}
    except Exception as e: print('pick failed', e)
    print('pick', json.dumps(pick))
    check(bool(pick.get('task')), f"the server's data gives a task to open {pick}")
    lenv = dict(os.environ, SIMCTL_CHILD_E11_SELFTEST_PICK=json.dumps(pick), SIMCTL_CHILD_E11_SERVER=BASE, SIMCTL_CHILD_E11_SELFTEST='1', SIMCTL_CHILD_E11_SELFTEST_SKIP=','.join(SKIP), SIMCTL_CHILD_E11_SELFTEST_EMAIL=EMAIL)
    # a film of the whole run (ios-run.mp4), so the moving parts — the shared top buttons, search, a page sliding in —
    # can be watched frame by frame from Claude's workspace; each stage's time in it is printed ('at 12.3s')
    # (simctl itself, in its own process group: Ctrl-C to the whole group lets it finish the file — sent to xcrun alone
    #  it never reached simctl and the film came out empty)
    simctl = sh('xcrun', '-f', 'simctl').stdout.strip() or 'simctl'
    # (a recorder left over from an earlier run holds the screen: this one would make no film)
    subprocess.run(['pkill', '-INT', '-f', 'recordVideo'], capture_output=True); time.sleep(1)
    rec = subprocess.Popen([simctl, 'io', udid, 'recordVideo', '--codec=h264', '--force', os.path.join(TMP, 'ios-run.mp4')], stdout=subprocess.DEVNULL, stderr=open(os.path.join(TMP, 'ios-rec.log'), 'w'), start_new_session=True)
    rec_t0 = time.time()
    r = subprocess.run(['xcrun', 'simctl', 'launch', '--stderr=/tmp/e11-app-stderr.txt', udid, BUNDLE], env=lenv, capture_output=True, text=True); check(r.returncode == 0, 'launched ' + r.stdout + r.stderr[-300:])
    data = sh('xcrun', 'simctl', 'get_app_container', udid, BUNDLE, 'data').stdout.strip()
    out = os.path.join(data, 'Documents', 'selftest.json')
    seen, res, t0 = set(), {}, time.time()
    while time.time() - t0 < 1200:   # (540 until 2026-11-08, 720 then 900 until 2026-11-09 — GitHub's slower Mac needs more; — the light / dark and measurement steps made it longer: 1600 was cut off before its last stages)
        try: res = json.load(open(out))
        except Exception: res = {}
        st = res.get('stage')
        if st and st not in seen:
            seen.add(st); time.sleep(0.5)
            sh('xcrun', 'simctl', 'io', udid, 'screenshot', os.path.join(TMP, f'ios-{st}.png'))
            print('stage', st, f'at {time.time() - rec_t0:.1f}s')
            # (to another app and back, as a person does: Settings opened, then the app again)
            # (light / dark: the phone switched with the app open — the app must follow it by itself)
            if st in ('lookFlip', 'tlookFlip'): sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'light')
            if st in ('lookLight', 'tlookLight'): sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')
            if st in ('away', 'titlesAway', 'titlesAway2'):
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
    # 22: the startup screen is the app's own — there at once, the icon alone (Haris 2026-11-09: "Logo only, then go"), gone before Home
    sg = res.get('splashGeo') or {}
    check('splash' in seen and sg.get('logoOnly') is True and sg.get('iconLayers') == 14 and not sg.get('offline') and sg.get('files') == 5, f'the startup screen shows at once: the icon alone {sg}')
    # the startup screen in the phone's look, nothing forced (Haris 2026-11-09: page 1, fully Apple)
    check(sg.get('forced') == 0 and sg.get('style') in (1, 2) and ((sg.get('bg') or 0) > 0.5) == (sg.get('style') == 1), f"the startup screen in the phone's look, not forced {sg}")
    # the first start (a fresh install — nothing on the phone): once the logo has assembled and the copy isn't in yet,
    # Apple's spinner and "Setting up your account" under it
    se = res.get('splashEnd') or {}
    check(bool(se) and (se.get('setupSeen') is True or (se.get('age') or 0) < 2.6), f"a first start: setting up shown under the logo while it waited {se}")
    hn = res.get('homeNative') or {}
    if hn.get('apple'):
      # (Haris 2026-11-07: Home opened under the small title — it must open with Apple's bar at its big title)
      check((hn.get('appleBarH') or 0) > 80, f"Home opens with the big title (Apple's bar {hn.get('appleBarH')} pt tall)")
    check(hn.get('shown') is True and (hn.get('cards') or 0) > 0 and len(hn.get('stats') or []) == 3 and hn.get('title') in ('E11 Day', 'My Day'), f'Home is the app\'s own, with its boxes and task cards {hn}')
    hsc0 = res.get('homeScrolledNative') or {}
    check(hsc0.get('server') is True, f'Home comes straight from the server (/api/home) {hsc0.get("server")}')
    hp = res.get('homePressNative') or {}
    # (Home fully Apple — Haris 2026-11-09: each task Apple's own cell in Apple's inset groups; its swipes Apple's actions —
    #  Copy link (and Trash) on the left, Done / Due on the right; held: Apple's menu with its lift)
    check((hn.get('listCells') or 0) > 0 and (hn.get('groupsApple') or 0) >= 1, f"Home's tasks are Apple's cells in Apple's inset groups {hn.get('listCells')} cells, {hn.get('groupsApple')} groups")
    row = (hp.get('row') or {})
    check('Copy link' in (row.get('trailing') or []), f"a Home task swiped left: Apple's Copy link {row.get('trailing')}")
    check(any(t in (row.get('leading') or []) for t in ('Done', 'Not Done', 'Review', 'Due')), f"a Home task swiped right: Apple's Done / Due {row.get('leading')}")
    check(bool(row.get('menu')) and row.get('cell') is True, f"a Home task held: Apple's menu; the row is Apple's own cell {row}")
    hg = hn.get('headGap'); hg = -1 if hg is None else hg
    check(-1 < hg <= 14, f"Home: each group's heading just over its rows, as locked (gap {hn.get('headGap')} pt)")
    wa = res.get('washAt') or {}
    check(wa.get('title') is True and wa.get('washed') is False, f"search cleared with the bar's own x, searched again, cleared, closed: Home's task title without search's wash ({res.get('washWord')}) {wa}")
    hsc = res.get('homeScrolledNative') or {}; hf = res.get('homeFindNative') or {}; hfd = res.get('homeFindDoneNative') or {}
    if hsc.get('apple'):
      # (Apple's bar: its big title shrinks by itself; the list has scrolled)
      # (the bar holds Apple's search box under the title too, as E11 Talk's: scrolled, it's the big title's height less)
      check(0 < (hsc.get('appleBarH') or 0) < (hn.get('appleBarH') or 0) - 40, f"scrolled, Apple's big title gone up into its small bar ({hn.get('appleBarH')} → {hsc.get('appleBarH')} pt)")
      check(hf.get('searching') is True and (hf.get('results') or 0) > 0, f'Search finds "Ford" {hf}')
    check(hfd.get('searching') is False, f'the ✕ closes the search {hfd}')
    fv = res.get('focusView') or {}
    check(fv.get('none') is True or fv.get('inView') is True, f"a comment opened as from the Inbox stays in view once everything has come {fv}")
    check(res.get('reviewCd') is True and res.get('reviewTab') == 'mytasks', f"Home's In review box: My Tasks with Waiting for CD review on (cd {res.get('reviewCd')}, tab {res.get('reviewTab')})")
    # (the Clients pages fully Apple — Haris 2026-11-10)
    cl, cp, cs, cf, cw = res.get('clList') or {}, res.get('clPage') or {}, res.get('clStrikeAt') or {}, res.get('clFind') or {}, res.get('clWashAt') or {}
    check((cl.get('rows') or 0) > 0 and cl.get('appleCell') is True, f"the Clients list: each client Apple's own cell {cl}")
    check(cp.get('openDone') is True and (cp.get('cards') or 0) > 0 and cp.get('appleCell') is True, f"a client's page ({res.get('clOpened')}): Apple's Open · Done, its tasks Apple's cells {cp}")
    check((cp.get('folders') or 0) == 0 or (cp.get('strip') is True and cp.get('seeAll') is True), f"a client's page: its folders in Apple's sideways row with See All {cp}")
    check((cs.get('titles') or 0) > 0 and cs.get('struckOpen') == 0, f"a client's page, Done then Open again: no open task struck through {cs} (Done showed {res.get('clDoneShown')})")
    ca, cs2, ct = res.get('clHoldArrived') or {}, res.get('clHoldScrolled') or {}, res.get('clHoldTop') or {}
    cmoved = {k: (ca.get(k), cs2.get(k), ct.get(k)) for k in set(ca) | set(cs2) | set(ct) if len({round(x) for x in (ca.get(k), cs2.get(k), ct.get(k)) if x is not None}) > 1}
    print('measure clientRowHeights', json.dumps({'arrived': ca, 'scrolled': cs2, 'top': ct}))
    check(bool(ca) and not cmoved, f"a client's page: each row keeps its height — arrived, scrolled, back at the top (moved: {cmoved})")
    print('measure clAgainNotes', json.dumps(res.get('clAgainNotes')))
    check(res.get('clRowsBefore') is not None and res.get('clRowsAfter') == res.get('clRowsBefore'), f"the Clients tab left and opened again: no row set again {res.get('clRowsBefore')} → {res.get('clRowsAfter')}")
    check(cf.get('searching') is True and (cf.get('tasks') or 0) > 0 and cf.get('clients') == 0, f"a client's page searched for \"{res.get('clFindWord')}\": its tasks found {cf}")
    check(cw.get('title') is True and cw.get('washed') is False, f"a client's page, search closed: its task title without search's wash {cw}")
    hd = res.get('homeDateNative') or {}
    check(hd.get('sheet') == 'DateSheetVC', f'the date sheet opens (and the app is still running) {hd.get("sheet")}')
    tp, tps, tpc, tpb = res.get('tpageNative') or {}, res.get('tpageScrolledNative') or {}, res.get('tpageCommentsNative') or {}, res.get('tpageBackNative') or {}
    # (the rule "only what changed changes": to another app and back redraws nothing, and the task page keeps its Details)
    check(res.get('redrawsBefore') is not None and res.get('redrawsAfter') == res.get('redrawsBefore'), f"to another app and back: no screen drawn again {res.get('redrawsBefore')} → {res.get('redrawsAfter')}")
    # (a tab with its own Apple screen follows Home, locked: from a task, ‹ back — "+ New task" there through the slide, as
    #  at rest, on Home, My Tasks and the Inbox alike: Haris 2026-11-08)
    for k, name in (('home', 'Home'), ('mt', 'My Tasks'), ('ibx', 'the Inbox'), ('cl', 'Clients')):
      o, mid, end = res.get(f'slide_{k}_open'), res.get(f'slide_{k}_mid'), res.get(f'slide_{k}_end')
      check(o is True and mid is not None and mid == end, f'{name}: a task opened and ‹ back — "+ New task" as at rest all through the slide (open {o}, in the slide {mid}, after {end})', need=('slide',))
    # (Haris 2026-11-09: rows changing height as the tab bar went, growing as they scrolled in — each row keeps its height)
    ha, hs, ht = res.get('holdArrived') or {}, res.get('holdScrolled') or {}, res.get('holdTop') or {}
    moved = {k: (ha.get(k), hs.get(k), ht.get(k)) for k in set(ha) | set(hs) | set(ht) if len({round(x) for x in (ha.get(k), hs.get(k), ht.get(k)) if x is not None}) > 1}
    print('measure atRoles', json.dumps(res.get('atRoles')))
    print('measure rowHeights', json.dumps({'arrived': ha, 'scrolled': hs, 'top': ht}))
    # (and none taller than its words need: 1621's checklist rows came out 170 tall, steady but wrong — Haris 2026-11-09)
    tall = {k: v for r in (ha, hs, ht) for k, v in r.items() if v and v > 110 and k not in ('desc', 'title', 'files', 'done', 'trash', 'lock', 'parent', 'based')}
    check(not tall, f"the task page's rows are no taller than their words — none over 110 but the description, title and files (too tall: {tall})")
    ra, re_, rt = res.get('rHoldArrived') or {}, res.get('rHoldEnd') or {}, res.get('rHoldTop') or {}
    rmoved = {k: (ra.get(k), re_.get(k), rt.get(k)) for k in set(ra) | set(re_) | set(rt) if len({round(x) for x in (ra.get(k), re_.get(k), rt.get(k)) if x is not None}) > 1}
    print('measure reviewRowHeights', json.dumps({'arrived': ra, 'end': re_, 'top': rt}))
    print('measure reviewRows', sorted(set(ra) | set(re_) | set(rt)))
    check(len(ra) >= 4 and len(re_) >= 2 and not rmoved, f"a task in CD review: rows keep their heights to the very end and back (changed: {rmoved})")
    check(len(ha) >= 4 and len(ht) >= 4 and not moved, f"the task page's rows keep their heights — arrived, scrolled, back at the top (changed: {moved})")
    # (the comments in Apple's list — Haris 2026-11-09, mock-up approved: rows steady, a swipe on a comment its Reply only)
    fa, ft = res.get('feedAt') or {}, res.get('feedTop') or {}
    fra, frt = fa.get('rows') or {}, ft.get('rows') or {}
    fmoved = {k: (fra.get(k), frt.get(k)) for k in set(fra) & set(frt) if fra.get(k) != frt.get(k)}
    print('measure commentRows', json.dumps({'end': fra, 'top': frt}))
    check(fa.get('list') == 'UITableView' and (fa.get('count') or 0) >= 1 and not fmoved, f"the comments in Apple's list, each row keeping its height at the latest and back at the top (changed: {fmoved}) {({k: fa.get(k) for k in ('list', 'count')})}")
    check(fa.get('swipeOn') is not False and fa.get('swipeBeside') is not True, f"a swipe on a comment is its Reply, never Details; beside it, Details (on {fa.get('swipeOn')}, beside {fa.get('swipeBeside')})")
    check(ft.get('topRoom') is not None and ft.get('topRoom') == res.get('feedBar'), f"the comments' list starts under the bar — its day pills never under Details · Comments (list {ft.get('topRoom')}, bar {res.get('feedBar')})")
    fd = res.get('feedDays') or {}
    check(fd.get('sections') == 4 and fd.get('items') == 4, f"comments out of date order drawn without stopping the app — each day its own section (Haris 2026-11-10's crash) {fd}")
    check((fa.get('menu') or 0) >= 2, f"holding a comment: Apple's menu with the reactions and its actions {fa.get('menu')}")
    tl, td = res.get('tlookAtLight') or {}, res.get('tlookAtDark') or {}
    check(tl.get('style') == 1 and tl.get('forced') == 0 and (tl.get('bg') or 0) > 0.5 and td.get('style') == 2 and td.get('forced') == 0 and td.get('bg', 1) < 0.5, f"the task page follows the phone light / dark, nothing forcing it (light {tl}, dark {td})", need=('tlook',))
    check((res.get('awayCells') or 0) > 0, f"the task page's Details still on the page after coming back {res.get('awayCells')}")
    # (Haris 2026-11-09, "Task page Details — fully Apple": Apple's own list cells in Apple's boxes, the creator as Apple's
    #  grey footer at the very end)
    _td = tp.get('details') or {}
    check((_td.get('appleRows') or 0) >= 3 and (_td.get('sections') or 0) >= 2 and (_td.get('listCells') or 0) >= 3, f"the task page's Details: Apple's own list cells in Apple's boxes {_td}")
    check(not _td.get('hasCreator') or (_td.get('foot') or '').startswith('Created by'), f"the task's creator as Apple's grey footer at the end of Details {_td.get('foot')}")
    check(tp.get('copy') is True and tp.get('copyTask') and tp.get('copyTask') == tp.get('title'), f"the app's own copy of the data is ready and gives the task page the server gives {({k: tp.get(k) for k in ('copy', 'copyTask', 'title')})}")
    tsd = res.get('tpageSwipeDetailsNative') or {}
    check(tsd.get('tab') == 'details' and tsd.get('compose') is False and tsd.get('pages') == 1, f"swiped from Comments: Details, no comment box {tsd}")
    check(tp.get('pages') == 1 and tp.get('drawn') is True and tp.get('x') == 0 and tp.get('tabBar') is False, f"a task opens as the app's own page, drawn from the server {tp}")
    # (the Inbox in Apple's navigation: Mark all read is Apple's bar button on its own screen, not the shared corner button)
    _ib = res.get('ibxInbox') or {}
    check(_ib.get('appleMark') == 'read', f"Mark all read is Apple's bar button on the Inbox {res.get('ibxInbox')}")
    check((res.get('tpageSheetNative') or {}).get('sheet') == 'NativeSheetVC', f"Assignees opens iPhone's own people sheet (changed by role again) {res.get('tpageSheetNative')}")
    check(tps.get('content', 0) > 300, f"the task page has its rows {tps}")
    check(tpc.get('feed', -1) > 0, f"the comments are the app's own (drawn from the server) {tpc}")
    check(tpc.get('tab') == 'comments' and tpc.get('compose') is True, f"its Comments tab has the app's own comment box {tpc}")
    check(tpb.get('pages') == 0 and tpb.get('tabBar') is True, f"back: the page goes, the tab bar is back {tpb}")
    check((res.get('dailyNative') or {}).get('sheet') == 'DailySheetVC', f"the morning round-up opens as iPhone's own sheet {res.get('dailyNative')}", need=('daily',))
    mt = res.get('mytasksMyTasks') or {}; mtd = res.get('mytasksDoneMyTasks') or {}; mta = res.get('mytasksAllMyTasks') or {}
    # (Haris 2026-11-09, My Tasks fully Apple: Apple's unavailable view exactly when there's nothing to show; Home the same)
    for k in ('mytasksMyTasks', 'mytasksDoneMyTasks', 'mytasksAllMyTasks'):
      g = res.get(k) or {}
      if g.get('shown'): check(g.get('unavailable') is ((g.get('modelCards') or 0) == 0), f"{k}: Apple's 'No Tasks' view only when there are no tasks ({g.get('modelCards')} tasks, view {g.get('unavailable')})")
    check((res.get('homeNative') or {}).get('unavailable') is not True, f"Home with tasks: no 'No Tasks' view {(res.get('homeNative') or {}).get('unavailable')}")
    # (Haris 2026-11-09: "I open search and close it, title disappears" — after search opened and closed, My Tasks' big title
    #  is on screen as before it: checked when the first reading found it)
    def bigOn(k):
      t = ((res.get(k) or {}).get('bigTitle') or {}).get('titles') or []
      return any((x.get('alpha') or 0) > 0.9 and (x.get('size') or 0) >= 28 for x in t)
    # (the reading now finds it wherever Apple draws it — in 1608 it never found the big title, so this check never ran)
    check(bigOn('mytasksMyTasks'), f"My Tasks opens with its big title on screen {(res.get('mytasksMyTasks') or {}).get('bigTitle')}")
    check(bigOn('mytasksFindDoneMyTasks'), f"My Tasks: search opened and closed, its big title still there {(res.get('mytasksFindDoneMyTasks') or {}).get('bigTitle')}")
    # (Haris 2026-11-09 14:45: My Tasks, Home, the Inbox, back to My Tasks — the big title gone, its room left)
    check(bigOn('mytasksTabBackMyTasks'), f"My Tasks: to Home, the Inbox and back by the tab bar, its big title still there {(res.get('mytasksTabBackMyTasks') or {}).get('bigTitle')}")
    # (Haris 2026-11-09 14:52: back from another app — My Tasks' and the Inbox's big titles still there, with My Tasks on
    #  while away and with Home on)
    # (measurement — the line under My Tasks' title changed as its tab is tapped, and while another tab is on: is that what
    #  takes the big title away on the second visit? Haris 2026-11-09 16:17)
    for k in ('titleMtLineSet', 'titleMtLineHidden'): print('measure bigTitle', k, json.dumps(res.get(k)))
    # (Haris 2026-11-09 16:56: from the start, E11 Day → My Tasks → another tab → My Tasks — the title gone for good)
    for k, name in (('titleFirstMt', 'My Tasks, first visit'), ('titleFirstIbx', 'the Inbox, first visit'), ('titleSecondMt', 'My Tasks, second visit'), ('titleSecondIbx', 'the Inbox, second visit')):
      print('measure bigTitle', k, json.dumps(res.get(k)))
      check(((res.get(k) or {}).get('alpha') or 0) > 0.9 and not (res.get(k) or {}).get('over'), f"{name}: its big title on screen, nothing over it {res.get(k)}", need=('first',))
    for x in (res.get('lineSets') or [])[-30:]: print('measure lineSet', json.dumps(x))
    for k, name in (('titleMtAway', 'My Tasks, back from another app'), ('titleIbxAway', 'the Inbox after that'), ('titleIbxAway2', 'the Inbox, Home on while away'), ('titleMtAway2', 'My Tasks after that')):
      print('measure bigTitle', k, json.dumps(res.get(k)))
      check(((res.get(k) or {}).get('alpha') or 0) > 0.9, f"{name}: its big title on screen {res.get(k)}", need=('titles',))
    # (measurement — the big title as on screen at each My Tasks step: Haris's 12:53 screenshot had its room empty)
    for k in ('mytasksMyTasks', 'mytasksDoneMyTasks', 'mytasksScrolledMyTasks', 'mytasksTopMyTasks', 'mytasksAllMyTasks', 'mytasksFindMyTasks', 'mytasksFindDoneMyTasks', 'mytasksTabHomeMyTasks', 'mytasksTabInboxMyTasks', 'mytasksTabBackMyTasks', 'slideMtBackMyTasks'):
      print('measure bigTitle', k, json.dumps((res.get(k) or {}).get('bigTitle')))
    check(mt.get('shown') is True and mt.get('server') is True and mt.get('tab') == 'all', f"My Tasks is the app's own, from the server, on All {mt}")
    check(mtd.get('shown') is True and mtd.get('tab') == 'done' and 'tab=done' in (mtd.get('query') or ''), f"My Tasks' Done tab asks the server for completed tasks {mtd}")
    check(mta.get('tab') == 'all' and 'tab=all' in (mta.get('query') or ''), f"back to All {mta}")
    ms = res.get('mytasksScrolledMyTasks') or {}
    # (My Tasks under Apple's bar since 2026-11-08: All / Done is the first row of Apple's list, the filters in Apple's menu)
    check(ms.get('apple') is True and ms.get('scope') is True and ms.get('listOn') is True, f"My Tasks in Apple's navigation: All / Done in Apple's search bar's scope bar {ms}")
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
    check(ib.get('shown') is True and ib.get('server') is True and (ib.get('tab') == 'unread' if (ib.get('unread') or 0) > 0 else ib.get('tab') == 'all') and len(ib.get('cats') or []) == 3, f"the Inbox is the app's own, from the server, opening on Unread — on All when nothing is unread {ib}")
    check((iba.get('rows') or 0) > 0 and iba.get('tab') == 'all', f"All: a row for each notification {iba}")
    check(ibs.get('open') is True, f"a row swiped right shows Read / Unread (Apple's own swipe in Apple's list) {ibs}")
    # (the Inbox fully Apple — Haris 2026-11-10: each row Apple's own cell; holding a task's update, Apple's peek of it from the
    #  phone's copy, with Apple's menu: Open Task · Mark as Read · Copy Text / Copy Link)
    check((ibs.get('cells') or 0) >= 1 and (ibs.get('cells') or 0) <= (ibs.get('rows') or 0), f"the Inbox's rows are Apple's own list cells {({k: ibs.get(k) for k in ('cells', 'rows')})}")
    check(res.get('notifCategories') == ['e11.comment:reply,read,open', 'e11.task:read,open'], f"a notification held: Reply · Mark as Read · Open Task on a comment's, Mark as Read · Open Task on a task's {res.get('notifCategories')}")
    _pk = ibs.get('peek') or {}
    check(not _pk or ((_pk.get('h') or 0) > 60 and _pk.get('menu') == 3), f"holding an update about a task: Apple's peek of it and its menu {_pk}")
    check(ib.get('apple') is True and ib.get('listOn') is True, f"the Inbox in Apple's navigation, its rows in Apple's list {ib}")
    check(ibu.get('tab') == 'unread' and (ibu.get('unreadRows') or 0) == (ibu.get('rows') or 0) and (ibu.get('rows') or 0) <= (iba.get('rows') or 0), f"Unread: only the unread ones, at once {ibu}")
    check(ibm.get('tab') == 'mentions' and (ibm.get('rows') or 0) <= (iba.get('rows') or 0), f"Mentions {ibm}")
    cw = ibu.get('cats') or []
    check(len(cw) == 3 and cw[0] == 49 and cw[1] > 49 and cw[2] == 49, f"the chosen button widens to its name, the others 49 wide {cw}")
    check((res.get('inboxMyTasks') or {}).get('shown') is not True, f"My Tasks isn't over the Inbox {res.get('inboxMyTasks')}")
    check((res.get('inboxNative') or {}).get('shown') is False, f"the app's Home goes on another tab {res.get('inboxNative')}")
    check(res.get('splashGone') is True, f"the startup screen went before Home {res.get('splashGone')}")
    check(set(seen) >= {x for x in {'home', 'inbox', 'me', 'meTeam', 'meAbout', 'meProfile', 'meTrash', 'meBack', 'client', 'tpage', 'rpage', 'nsheet', 'nsheetEnd', 'nsheetChannel', 'nsheetTitled'} if not any(x.startswith(g) for g in SKIP)}, f'all stages ran {sorted(seen)}')
    mn, mt, ma, mb = res.get('meNative') or {}, res.get('meTeamNative') or {}, res.get('meAboutNative') or {}, res.get('meBackNative') or {}
    check(mn.get('open') is True and mn.get('kind') == 'me' and mn.get('card') is True and (mn.get('rows') or 0) >= 2, f"the app's Me: your card and its groups, no top buttons {mn}", need=('me',))
    check(mt.get('kind') == 'team' and mt.get('screens') == 2 and (mt.get('people') or 0) >= 1 and mt.get('apple') is True, f"Team members slides in over Me, the people in it, ‹ at the top {mt}", need=('me',))
    check(ma.get('kind') == 'about' and (ma.get('parts') or 0) >= 2, f"About: its cards and What's new {ma}", need=('me',))
    mp = res.get('meProfileNative') or {}
    check(mp.get('kind') == 'profile' and mp.get('profile') is True and (mp.get('rows') or 0) >= 4 and mp.get('apple') is True, f"My profile: the app's own, its groups, ‹ at the top {mp}", need=('me',))
    mtr = res.get('meTrashNative') or {}
    check(mtr.get('kind') == 'trash' and (mtr.get('parts') or 0) >= 3 and mtr.get('apple') is True, f"Trash: the app's own, its search and categories, ‹ at the top {mtr}", need=('me',))
    check(mb.get('kind') == 'me' and mb.get('screens') == 1, f"‹ back to Me {mb}", need=('me',))
    # light / dark the Apple way (Haris 2026-11-09): every tab's screen follows the phone, none forced, nothing drawn again
    def lookOk(d, style, bright):
      if not isinstance(d, dict) or not d: return False
      scr = [d[k] for k in ('home', 'mytasks', 'inbox', 'clients', 'me') if isinstance(d.get(k), dict)]
      on = [x for x in scr if x.get('shown')]   # (a tab not on show hears the look when it shows again — iPhone's own way)
      return len(scr) >= 3 and len(on) >= 1 and all(x.get('forced') == 0 for x in scr) and all(x.get('style') == style and ((x.get('bg') or 0) > 0.5) == bright for x in on) and d.get('tabBar') == 0
    check(lookOk(res.get('lookAtLight'), 1, True), f"phone to light, app open: every tab's screen light, nothing forced {res.get('lookAtLight')}", need=('look',))
    check(lookOk(res.get('lookAtDark'), 2, False), f"phone back to dark: every tab's screen dark {res.get('lookAtDark')}", need=('look',))
    check(res.get('lookRedrawsAfter') is not None and res.get('lookRedrawsAfter') == res.get('lookRedrawsBefore'), f"the look switched by iPhone itself: no screen drawn again {res.get('lookRedrawsBefore')} → {res.get('lookRedrawsAfter')}", need=('look',))
    # (measurement only — Haris 2026-11-09: the frost on pushed pages at their top; the search bar going back to Client Assets)
    def barLine(b):
      if not isinstance(b, dict) or not b.get('bar'): return str(b)
      bar = b['bar']; l = b.get('list') or {}
      ss = ' '.join(f"[{x.get('ph','')[:18]} y{x.get('y',0):.0f} h{x.get('h',0):.0f} a{x.get('a',0):.2f}]" for x in (b.get('search') or []))
      return f"{b.get('top','')} bar y{bar.get('y',0):.0f}+{bar.get('h',0):.0f} list off{l.get('off','-')} adj{l.get('adj','-')} ins{l.get('ins','-')} cell{l.get('firstCell','-')} edge {l.get('edgeStyle','-')} hidden{l.get('edgeHidden','-')} {ss}"
    for k in ('frost_team', 'frost_assetsAll', 'frost_assetsClient'): print('measure', k, barLine(res.get(k)))
    print('measure snapOpened', res.get('snapOpened'))
    print('measure formNotes', json.dumps(res.get('formNotes')))
    st = res.get('storageAt') or {}
    print('measure storage', f"total {st.get('total',0)/1e6:.2f} MB in {st.get('files')} files; copies {st.get('copies')} ({st.get('copyBytes',0)/1e6:.2f} MB)")
    for k, b in sorted((st.get('parts') or {}).items(), key=lambda x: -x[1]): print('measure storage part', f"{b/1e6:8.2f} MB  {k}")
    for x in st.get('top') or []: print('measure storage file', f"{x.get('b',0)/1e6:8.2f} MB  {x.get('f')}")
    tf = res.get('task_open') or []
    t1 = tf[0].get('t', 0) if tf else 0
    for f in tf:
      sg, ss, nb, tb = f.get('seg') or {}, f.get('segSuper') or {}, f.get('navBar') or {}, f.get('tabBar') or {}
      print('measure task_open', f"{(f.get('t',0) - t1) * 1000:5.0f}ms seg x{sg.get('x',0):.1f} y{sg.get('y',0):.1f} w{sg.get('w',0):.1f} h{sg.get('h',0):.1f} a{sg.get('a',0):.2f} | holder y{ss.get('y',0):.1f} h{ss.get('h',0):.1f} | bar y{nb.get('y',0):.1f} h{nb.get('h',0):.1f} | tabs hidden{f.get('tabHidden')} y{tb.get('y',0):.0f} a{tb.get('a',0):.2f} | safeB{f.get('safeBottom')} list off{f.get('listOff')} adj{f.get('listAdj')}")
    fr = res.get('snap_back') or []
    t0 = fr[0].get('t', 0) if fr else 0
    for f in fr: print('measure snap_back', f"{(f.get('t',0) - t0) * 1000:5.0f}ms", barLine(f))
    check(res.get('meRowsBefore') is not None and res.get('meRowsAfter') == res.get('meRowsBefore'), f"Me opened again: no row drawn again {res.get('meRowsBefore')} → {res.get('meRowsAfter')}", need=('me',))
    ca = res.get('clientAssets') or {}
    # (opened from the page — a link, an Inbox update, a client's page — just that folder, so ‹ goes back where you came from:
    #  Haris 2026-11-04; it was the client's screen, then the folder, before)
    check(ca.get('open') is True and ca.get('kind') == 'folder' and (ca.get('screens') or 0) >= 1 and (ca.get('parts') or 0) >= 1 and ca.get('shown') is True, f"a Client Assets folder opens as the app's own screen, just the folder {ca}", need=('client',))
    # native sheets: the same room above (TOP, 30) and below (as on the Channel sheet) everywhere; a long list's last
    # option clear of the bottom edge at the end of the scroll
    ch_ = res.get('nsheetChannelGeo') or {}; gap = ch_.get('endGap')
    for k in ('nsheet', 'nsheetEnd', 'nsheetChannel', 'nsheetTitled'):
        g_ = res.get(k + 'Geo') or {}
        check(abs((g_.get('topGap') or 0) - 30) <= 1, f'native sheet {k}: first thing 30 under the top edge {g_}', need=('nsheet',))
    for k in ('nsheetEnd', 'nsheetTitled'):
        g_ = res.get(k + 'Geo') or {}
        check(gap is not None and g_.get('endGap') is not None and abs(g_['endGap'] - gap) <= 2, f'native sheet {k}: gap under the last option {g_.get("endGap")} = Channel\'s {gap}', need=('nsheet',))
    check((res.get('nsheetGeo') or {}).get('scrolls') is True, 'the long native sheet scrolls', need=('nsheet',))
    fr = res.get('frame') or {}
    print('note ' + ('ok' if (fr.get('insetTop') or 0) >= 20 else 'CHECK SCREENSHOT') + f" the sign-in page clears the status bar {fr} {res.get('signin')}")   # (needs the internet: not a blocker)
    print('note ' + ('ok' if fr.get('reviewLink') is True or 'cloudflareaccess' not in str(fr.get('host')) else 'CHECK SCREENSHOT') + f" the App Review sign-in link shows under the sign-in page {fr.get('host')} {fr.get('reviewLink')}")   # (needs the internet)
    check(fr.get('privacy') is True, f"Apple's privacy manifest is in the app {fr.get('privacy')}")
    check((res.get('appInfo') or {}).get('native') == 'ios', f"appInfo {res.get('appInfo')}")
    check(len(res.get('tabs') or []) >= 4 and 'inbox' in (res.get('tabs') or []), f"native tab bar has the page's tabs {res.get('tabs')}")
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
# (Apple's layout-loop records, printed by UIKit before it stops the app — what loops, cell by cell)
try:
    err = open('/tmp/e11-app-stderr.txt', errors='replace').read()
    i = err.find('feedback loop'); i = i if i >= 0 else err.find('FeedbackLoop')
    if i >= 0: print('LOOP RECORDS', err[max(0, i - 2000):i + 6000])
except Exception:
    pass
print('FAILS', len(fails), fails)
sys.exit(1 if fails else 0)
