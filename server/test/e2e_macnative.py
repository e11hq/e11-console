"""The Mac app's parts outside its window (web/macnative.js — canvases "Menu bar item — Mac" B5, "Spotlight — Mac" S1–S3,
"Drag out to Finder — Mac" D1–D4): what the menu bar item is sent (the unread count, the newest 3 unread, what's due today,
New Task by right) and kept live, its panel's picks; Spotlight's items (only what this person sees), a result opened,
signing out; a Client Assets file or folder, a task's file and a Trash file dragged — the files the drag carries, the page's
own drops never taking it as an upload. Older Mac apps and browsers: nothing. Run: python3 server/test/e2e_macnative.py"""
import asyncio, base64, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18271; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'; AM = 'areej@e11-digital.com'
CHROME = os.environ.get('CHROME', '/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
PNG = base64.b64encode(bytes.fromhex('89504e470d0a1a0a0000000d4948445200000010000000100802000000909168360000001c49444154789c63f8cfc0f09f8114c0c4c0c0f09f81a1c10106001ac40cf4df5b8a3c0000000049454e44ae426082')).decode()
MAC = """try { localStorage.setItem('e11-mac-shell', '13'); } catch (e) {}
window.__calls = []; window.__new = %s;
window.webkit = { messageHandlers: { e11: { postMessage: (s) => { const m = JSON.parse(s); window.__calls.push(m);
  const R = { appInfo: { ok: true, shell: 13, preview: true, info: true, trashWindow: true, ...(window.__new ? { bar: true, spotlight: true, dragOut: true } : {}) },
    preview: { ok: true }, bar: { ok: true, shown: true }, spotlight: { ok: true }, signedOut: { ok: true }, dragOut: { ok: true }, trashWindow: { ok: true } };
  const r = R[m.cmd] || { ok: false, error: 'Unknown command ' + m.cmd };
  setTimeout(() => window.__e11NativeReply && window.__e11NativeReply(m.id, r), 10); } } } };"""
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.8-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(60):
            try: urllib.request.urlopen(BASE + '/api/health'); break
            except Exception: time.sleep(0.1)
        urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
        async with async_playwright() as pw:
            b = await pw.chromium.launch(executable_path=CHROME)
            errs = []
            async def mac(email, new=True, bridge=True):
                ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, extra_http_headers={'X-Dev-Email': email}, color_scheme='dark')
                if bridge: await ctx.add_init_script(MAC % ('true' if new else 'false'))
                p = await ctx.new_page(); p.on('pageerror', lambda e: errs.append(str(e)))
                await p.goto(BASE + '/'); await p.wait_for_function('typeof db !== "undefined" && db && db.tasks && db.tasks.length > 0', timeout=20000)
                await p.wait_for_timeout(1500)
                return ctx, p
            ctx, p = await mac(ADMIN)
            E = p.evaluate
            last = lambda cmd: E(f"(() => {{ const l = window.__calls.filter((m) => m.cmd === '{cmd}'); return l.length ? l[l.length - 1].args : null; }})()")
            # some unread updates and tasks due today, a file on a task, files in a client's folder
            setup = await E("""async () => {
              const ts = db.tasks.filter((t) => !t.parentId && t.projectId && !t.done);
              ts.slice(0, 4).forEach((t) => { t.due = todayStr(); });
              const others = db.users.filter((u) => u.id !== currentUserId);
              for (let i = 0; i < 5; i++) db.notifications.push({ id: 'nt-' + i, to: currentUserId, from: others[i % others.length].id, kind: 'comment', taskId: ts[i].id, text: 'commented on', snippet: 'Looks good ' + i, at: new Date(Date.now() - (5 - i) * 60000).toISOString(), read: false });
              const r = await Host.call('writeChunk', { taskId: ts[0].id, name: 'hero.png', path: null, b64: 'PNGDATA' });
              ts[0].attachments.push({ id: 'att-hero', name: 'hero.png', path: r.path, size: r.size, addedAt: nowISO() });
              if (!clientsSorted().length) createClient('Kestrel Foods');
              const c = clientsSorted()[0], f = c.folders[0];
              const sub = newFolder(c, 'Selects', false, f);
              f.files.push({ id: 'caf-1', name: 'menu-final.png', path: r.path, size: r.size, addedAt: nowISO(), addedBy: currentUserId });
              sub.files.push({ id: 'caf-2', name: 'menu-alt.png', path: r.path, size: r.size, addedAt: nowISO(), addedBy: currentUserId });
              commit({ delay: 0 }); render();
              return { t0: ts[0].id, cid: c.id, fid: f.id, sid: sub.id };
            }""".replace('PNGDATA', PNG))
            await p.wait_for_timeout(900)
            # ---------- the menu bar item ----------
            bar = await last('bar')
            unread = await E("myNotifs().filter((n) => !n.read).length")
            check(bool(bar) and bar['on'] is True and bar['count'] == unread, f"the menu bar item: on, the unread count ({(bar or {}).get('count')} = {unread})")
            newest = await E("myNotifs().filter((n) => !n.read).sort((a, b) => b.at.localeCompare(a.at)).slice(0, 3).map((n) => n.id)")
            rows = (bar or {}).get('inbox', {}).get('rows', [])
            check([r['id'] for r in rows] == newest, 'its panel: the newest 3 unread, newest first (B5)')
            r0 = rows[0] if rows else {}
            check(bool(r0.get('who')) and r0.get('what', '').startswith('commented') and 'Looks good 4' in r0.get('what', '') and r0.get('sub', '').endswith('m') and r0.get('ini') and r0.get('color'), f"a row: who, what they did, which task · when, their face ({r0})")
            due = await E("(() => { const D = Work.day(); return D.tasks.filter((t) => D.open(t) && t.due && dayDiff(t.due) === 0).length; })()")
            day = (bar or {}).get('day', {})
            check(day.get('n') == due and len(day.get('rows', [])) == min(3, due) and day.get('title') == await E("Work.dayTitle()"), f"E11 Day: what's due today ({day.get('n')}), up to 3 rows")
            d0 = (day.get('rows') or [{}])[0]
            check(d0.get('sub', '').endswith('due today') and d0.get('pill', {}).get('t') and d0.get('pill', {}).get('c', '').startswith('#') and d0.get('dot'), f'a task row: its client · due today, its status as a pill ({d0})')
            check(bar.get('canNew') is True, 'New Task for those who can make tasks')
            # live: one read → the count and rows change; nothing changed → nothing sent again
            n0 = len([c for c in await E("window.__calls") if c['cmd'] == 'bar'])
            await E("() => { render(); }"); await p.wait_for_timeout(400)
            n1 = len([c for c in await E("window.__calls") if c['cmd'] == 'bar'])
            check(n1 == n0, 'drawn again with nothing changed: nothing sent again')
            await E(f"() => {{ const n = db.notifications.find((x) => x.id === '{newest[0]}'); n.read = true; commit({{ delay: 0 }}); renderSidebar(); }}"); await p.wait_for_timeout(400)
            bar2 = await last('bar')
            check(bar2['count'] == unread - 1 and newest[0] not in [r['id'] for r in bar2['inbox']['rows']], 'live: an update read — the count and the rows follow')
            # the panel's picks
            await E("window.__e11Bar({ k: 'inbox' })"); await p.wait_for_timeout(300)
            check(await E("ui.view") == 'inbox', 'Open Inbox: the Inbox')
            await E("window.__e11Bar({ k: 'day' })"); await p.wait_for_timeout(300)
            check(await E("ui.view") == 'today', 'Open E11 Day: E11 Day')
            await E(f"window.__e11Bar({{ k: 'notif', id: '{newest[1]}' }})"); await p.wait_for_timeout(600)
            check(await E(f"db.notifications.find((x) => x.id === '{newest[1]}').read") is True and await E("ui.taskId") is not None, 'an update: read, its task opened')
            await E("closeDetail && closeDetail()"); await p.wait_for_timeout(300)
            await E(f"window.__e11Bar({{ k: 'task', id: '{setup['t0']}' }})"); await p.wait_for_timeout(600)
            check(await E("ui.taskId") == setup['t0'], 'a task due today: its task')
            await E("closeDetail && closeDetail()"); await p.wait_for_timeout(300)
            # ---------- Spotlight ----------
            await p.wait_for_timeout(4500)
            sp = await last('spotlight')
            items = (sp or {}).get('items', [])
            kinds = {i['id'].split(':')[0] for i in items}
            check(bool(sp) and sp['who'].endswith('|' + await E("currentUserId")) and kinds >= {'task', 'client', 'assets', 'folder', 'file'}, f'Spotlight: tasks, clients, Client Assets, folders and files ({len(items)}, {sorted(kinds)})')
            ftask = next((i for i in items if i['id'] == 'task:' + setup['t0']), {})
            check(ftask.get('kind') == 'Task' and 'due today' in ftask.get('desc', '') and ftask.get('title'), f'a task: its name, status · client · due ({ftask.get("desc")})')
            ff = next((i for i in items if i['id'] == f"file:{setup['cid']}:{setup['fid']}:caf-1"), {})
            check(ff.get('ext') == 'png' and ff.get('thumb', '').startswith('http') and '›' in ff.get('desc', ''), f"a file: client › folder, size, its picture ({ff.get('desc')})")
            fs = next((i for i in items if i['id'] == f"folder:{setup['cid']}:{setup['sid']}"), {})
            check(fs.get('desc', '').endswith('› Selects') and '›' in fs.get('desc', ''), f"a folder inside a folder: its whole path ({fs.get('desc')})")
            seen = await E("topTasks().filter((t) => Work.seen().has(t.id)).length")
            check(len([i for i in items if i['id'].startswith('task:')]) == seen, 'only the tasks this person sees')
            nsp = len([c for c in await E("window.__calls") if c['cmd'] == 'spotlight'])
            await E("render()"); await p.wait_for_timeout(4500)
            check(len([c for c in await E("window.__calls") if c['cmd'] == 'spotlight']) == nsp, 'nothing changed: Spotlight isn’t sent again')
            # a result opened
            await E(f"window.__e11Spot('folder:{setup['cid']}:{setup['sid']}')"); await p.wait_for_timeout(500)
            check(await E("[ui.view, ui.clientId, ui.folderId]") == ['client', setup['cid'], setup['sid']], 'a folder from Spotlight: Client Assets at that folder')
            await E("window.__calls = []")
            await E(f"window.__e11Spot('file:{setup['cid']}:{setup['fid']}:caf-1')"); await p.wait_for_timeout(1200)
            pv = await last('preview')
            check(bool(pv) and pv['files'][pv['at']]['id'] == 'caf-1' and pv['files'][pv['at']].get('dl', '').startswith('http'), 'a file from Spotlight: its folder, the file in the preview (with the file itself for dragging out)')
            await E(f"window.__e11Spot('client:' + db.projects.find((p) => !p.inactive && clientListOk(p)).id)"); await p.wait_for_timeout(400)
            check(await E("ui.view") == 'project', 'a client from Spotlight: its page')
            # ---------- dragging out ----------
            async def drag(sel):
                await E("window.__calls = []")
                return await p.evaluate("""(sel) => { const el = document.querySelector(sel); if (!el) return 'none';
                  el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, button: 0 }));
                  const dt = new DataTransfer(); const ev = new DragEvent('dragstart', { bubbles: true, cancelable: true, dataTransfer: dt });
                  el.dispatchEvent(ev); const m = window.__calls.find((c) => c.cmd === 'dragOut');
                  el.dispatchEvent(new DragEvent('dragend', { bubbles: true, dataTransfer: dt }));
                  return { items: m ? m.args.items : null, types: [...dt.types], draggable: el.getAttribute('draggable') }; }""", sel)
            await E(f"openClient('{setup['cid']}', '{setup['fid']}')"); await p.wait_for_timeout(600)
            d = await drag('.mca-t[data-mca-file="caf-1"]')
            it = ((d or {}).get('items') or [{}])[0]
            check(it.get('name') == 'menu-final.png' and it.get('url', '').startswith(BASE + '/__file/') and it.get('size', 0) > 0 and 'application/x-e11-out' in d['types'], f'a Client Assets file dragged: the file itself goes with the drag (D1) ({it})')
            check('application/x-e11-file' in d['types'], 'and Client Assets’ own move inside the window is as before')
            await E(f"openClient('{setup['cid']}')"); await p.wait_for_timeout(600)
            d = await drag(f'.mca-fc[data-mca-folder="{setup["fid"]}"]')
            fo = ((d or {}).get('items') or [{}])[0]
            check(fo.get('folder') is True and any(x['name'] == 'menu-final.png' for x in fo.get('files', [])) and any(x['name'] == 'Selects' and x['files'][0]['name'] == 'menu-alt.png' for x in fo.get('folders', [])), 'a folder dragged: a folder with its files and its folders in it')
            check(d.get('draggable') is None, 'a folder card made draggable only for that drag')
            await E(f"TaskLink.show('{setup['t0']}')"); await p.wait_for_timeout(900)
            d = await drag('#detail [data-action="quicklook"][data-id="att-hero"]')
            ta = ((d or {}).get('items') or [{}])[0] if isinstance(d, dict) else {}
            check(ta.get('name') == 'hero.png' and ta.get('url', '').startswith(BASE), f'a task’s file dragged: the file ({d if not isinstance(d, dict) else ta})')
            await E("closeDetail && closeDetail()"); await p.wait_for_timeout(300)
            # the page's own drops never take one of these as an upload; files from Finder still upload
            g = await E("""() => { let hits = 0; const f = () => { hits++; }; document.addEventListener('dragover', f);
              const a = new DataTransfer(); a.setData('application/x-e11-out', '1');
              document.body.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: a }));
              const h1 = hits; const b = new DataTransfer(); b.items.add(new File(['x'], 'x.txt'));
              document.body.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: b }));
              document.removeEventListener('dragover', f); return [h1, hits]; }""")
            check(g == [0, 1], f'one of ours over the page: no page drop takes it; files from Finder do ({g})')
            # signing out
            await E("window.__calls = []")
            await E("signOut()"); await p.wait_for_timeout(100)
            check(any(c['cmd'] == 'signedOut' for c in await E("window.__calls")), 'signing out: the menu bar item and Spotlight’s items go')
            await ctx.close()
            # an Account Manager: their own tasks only, no Empty Trash etc — Spotlight only what they see
            ctx, p = await mac(AM)
            await p.wait_for_timeout(4500)
            sp = await p.evaluate("(() => { const l = window.__calls.filter((m) => m.cmd === 'spotlight'); return l.length ? l[l.length - 1].args : null; })()")
            seen = await p.evaluate("topTasks().filter((t) => Work.seen().has(t.id)).length")
            allt = await p.evaluate("topTasks().length")
            check(bool(sp) and len([i for i in sp['items'] if i['id'].startswith('task:')]) == seen and seen < allt, f'an Account Manager: Spotlight has only their tasks ({seen} of {allt})')
            await ctx.close()
            # an older Mac app: nothing sent
            ctx, p = await mac(ADMIN, new=False)
            await p.wait_for_timeout(4500)
            cmds = {c['cmd'] for c in await p.evaluate("window.__calls")}
            check(not (cmds & {'bar', 'spotlight', 'dragOut'}), f'an older Mac app: nothing of these ({sorted(cmds)})')
            await ctx.close()
            # a browser
            ctx, p = await mac(ADMIN, bridge=False)
            check(await p.evaluate("typeof MacNative !== 'undefined' && !MacNative.on()"), 'a browser: nothing here')
            await ctx.close()
            check(not errs, f'no page errors {errs[:3]}')
            await b.close()
    finally:
        srv.terminate()
    print('\n%d failed' % len(fails) if fails else '\nall passed')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
