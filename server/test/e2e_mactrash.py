"""The Mac app's Trash (web/mactrash.js — canvas "Trash — Mac" T1–T8): the list as the boards, the filters, the search with its
typo note, a file chip opening the Mac's preview with the row's files, right-click (Apple's menu), Restore, Delete Forever and
Empty Trash asking with Apple's alert, a deleted task in its own Mac window (and the page's own box on an older Mac app), an
Account Manager's rights, empty and nothing found. The Mac Inbox opening on All with nothing unread. Browsers keep the
website's own Trash. Run: python3 server/test/e2e_mactrash.py (SHOTS=dir for pictures)"""
import asyncio, base64, json, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18263; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'; AM = 'areej@e11-digital.com'
CHROME = os.environ.get('CHROME', '/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
PNG = base64.b64encode(bytes.fromhex('89504e470d0a1a0a0000000d4948445200000010000000100802000000909168360000001c49444154789c63f8cfc0f09f8114c0c4c0c0f09f81a1c10106001ac40cf4df5b8a3c0000000049454e44ae426082')).decode()
# the Mac app, as the page sees it: its bridge answers (alert → window.__alertPress, menu → window.__menuPick, trashWindow →
# window.__winOK), every call kept in window.__calls
MAC = """try { localStorage.setItem('e11-mac-shell', '13'); } catch (e) {}
window.__calls = []; window.__alertPress = true; window.__menuPick = null; window.__winOK = true;
window.webkit = { messageHandlers: { e11: { postMessage: (s) => { const m = JSON.parse(s); window.__calls.push(m);
  const R = { appInfo: { ok: true, shell: 13, preview: true, info: true }, alert: { ok: true, pressed: window.__alertPress }, preview: { ok: true },
    menu: { ok: true, i: window.__menuPick }, trashWindow: window.__winOK ? { ok: true } : { ok: false, error: 'Unknown command trashWindow' }, trashClose: { ok: true } };
  const r = R[m.cmd] || { ok: false, error: 'Unknown command ' + m.cmd };
  setTimeout(() => window.__e11NativeReply && window.__e11NativeReply(m.id, r), 20); } } } };"""
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
            async def mac(email, dark=True):
                ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, extra_http_headers={'X-Dev-Email': email}, color_scheme='dark' if dark else 'light')
                await ctx.add_init_script(MAC)
                p = await ctx.new_page(); p.on('pageerror', lambda e: errs.append(str(e)))
                await p.goto(BASE + '/'); await p.wait_for_function('typeof db !== "undefined" && db && db.tasks && db.tasks.length > 0', timeout=20000)
                await p.wait_for_timeout(1500)
                return ctx, p
            ctx, p = await mac(ADMIN)
            E = p.evaluate
            # three tasks to the Trash, one with a picture and a PDF
            tids = await E("""async () => { const ts = db.tasks.filter((t) => !t.parentId && t.projectId && !t.done).slice(0, 3);
              const t = ts[0];
              for (const [n, ext] of [['menu-hero-01', 'png'], ['retouch-notes', 'pdf']]) { const r = await Host.call('writeChunk', { taskId: t.id, name: n + '.' + ext, path: null, b64: '%s' });
                t.attachments.push({ id: uid(), name: n + '.' + ext, path: r.path, size: r.size, addedAt: nowISO() }); }
              commit({ delay: 0 }); return ts.map((x) => x.id); }""" % PNG)
            await p.wait_for_timeout(600)
            for t in tids: await E(f"()=>deleteTaskFlow('{t}')"); await p.wait_for_timeout(500)
            await p.wait_for_timeout(1200)
            n = await E("trashList().length")
            check(n >= 3, f'three tasks in the Trash ({n})')
            await E("()=>go('trash')"); await p.wait_for_timeout(500)
            check(await p.locator('#content > .mtr').count() == 1 and await p.locator('.tr-row').count() == 0, 'the Mac: its own Trash (T1), not the website’s')
            check(await p.locator('.mtr-seg button').all_inner_texts() == ['All', 'Tasks', 'Clients', 'Files', 'Comments', 'Deleted by me'], 'the six filters as a segmented control')
            check(await p.locator('.mtr-danger').count() == 1, 'Empty Trash for a Super Admin')
            g1 = await p.locator('.mtr-grp').first.inner_text()
            check(await p.locator('.mtr-row').count() == n and g1.split()[0] == 'Today' and g1.split()[-1] == str(n), f'every item, grouped ({g1!r})')
            check(await p.locator('.mtr-row .mtr-rnd').count() == n and await p.locator('.mtr-row .mtr-pill.pri').count() == n, 'Restore and Delete Forever on each row')
            ok = await E("""() => [...document.querySelectorAll('.mtr-row')].every((r) => { const it = trashList().find((x) => x.id === r.dataset.tr), fs = trashFiles(it);
              const chips = [...r.querySelectorAll('.mtr-fch')]; return chips.length === Math.min(4, fs.length) && chips.every((c, i) => isImage(fs[i]) ? !!c.querySelector('img.mib-tpic') : c.querySelector('i.mib-tpic').textContent === fileExt(fs[i].name).toUpperCase().slice(0, 4))
                && (fs.length > 4) === !!r.querySelector('.mtr-more'); })""")
            check(ok, 'file chips: up to 4, a picture its own, anything else its badge, +N more')
            check(await p.locator('.mtr-left').first.inner_text() == '30 days left', 'days left')
            await p.screenshot(path=os.path.join(SHOTS, 'mactrash-T1.png'))
            # the PDF chip: the Mac's preview, flying from the badge, with the row's files
            await E("window.__calls = []")
            chip = p.locator('.mtr-fch:has(i.mib-tpic)').first
            cname = await chip.locator('span').inner_text()
            rowfiles = await chip.evaluate("(c) => trashFiles(trashList().find((x) => x.id === c.closest('.mtr-row').dataset.tr)).length")
            await chip.click(); await p.wait_for_timeout(400)
            pv = await E("window.__calls.find((m) => m.cmd === 'preview')")
            box = await chip.locator('i.mib-tpic').bounding_box()
            fr = (pv or {}).get('args', {}).get('from') or {}
            check(bool(pv) and len(pv['args']['files']) == rowfiles and pv['args']['files'][pv['args']['at']]['name'] == cname, f'a chip opens the Mac’s preview with the row’s files, ← → ({rowfiles})')
            check(all(f.get('noLink') is True for f in (pv or {}).get('args', {}).get('files', [])), 'a file in the Trash: no Copy Link in the preview')
            check(abs(fr.get('w', 0) - box['width']) < 1 and abs(fr.get('x', 0) - box['x']) < 1, f'it flies out of the badge only, not the whole chip {fr}')
            # the filters and the search with a typo
            await p.locator('.mtr-seg button', has_text='Comments').click(); await p.wait_for_timeout(300)
            check(await p.locator('.mtr-row').count() == 0 and await p.locator('.mtr-empty b').inner_text() == 'The Trash Is Empty', 'a filter with nothing: the empty words')
            await p.locator('.mtr-seg button', has_text='All').click(); await p.wait_for_timeout(300)
            title = await E(f"trashTitle(trashList()[0])")
            w = [x for x in title.split() if len(x) >= 5]
            w = (w[0] if w else title.split()[0]).lower()
            typo = w[1] + w[0] + w[2:]
            await p.fill('#mtr-q', typo); await p.wait_for_timeout(400)
            check((await p.locator('.mtr-grp').first.inner_text()).startswith('Results') and await p.locator('.mtr-row mark').count() >= 1, f'searching: one Results group, the words marked ("{typo}")')
            check(await p.locator('.mtr-fix b').count() == 1, 'the typo noted (Showing results for …)')
            await p.screenshot(path=os.path.join(SHOTS, 'mactrash-T3.png'))
            await p.fill('#mtr-q', 'zzqqxx'); await p.wait_for_timeout(300)
            check('Nothing in the Trash matches' in await p.locator('.mtr-empty b').inner_text(), 'nothing found: the website’s words')
            await p.locator('.mtr-x').click(); await p.wait_for_timeout(300)
            check(await p.input_value('#mtr-q') == '' and await p.locator('.mtr-row').count() == n, 'the field’s ✕ clears it')
            # a deleted task opens in its own Mac window
            await E("window.__calls = []")
            await p.locator('.mtr-row.opens .mtr-main').first.click(); await p.wait_for_timeout(400)
            w1 = await E("window.__calls.find((m) => m.cmd === 'trashWindow')")
            check(bool(w1) and w1['args']['title'] and 'In the Trash' in w1['args']['bar'] and w1['args']['canRestore'] is True and isinstance(w1['args']['files'], list), 'a task’s row: its own Mac window, with everything it had (T4)')
            check(await p.locator('.tv-dlg').count() == 0, '… not the page’s box')
            # the Mac window's Restore
            key = w1['args']['key']
            await E(f"window.__e11Trash({{ key: '{key}', act: 'restore' }})"); await p.wait_for_timeout(800)
            check(not await E(f"trashList().some((x) => x.id === '{key}')") and await p.locator('.mtr-row').count() == n - 1, 'Restore in the window puts it back; the row goes')
            # an older Mac app (no window of its own): the page's own box
            await E("window.__winOK = false")
            await p.locator('.mtr-row.opens .mtr-main').first.click(); await p.wait_for_timeout(500)
            check(await p.locator('.tv-dlg').count() == 1, 'an older Mac app: the page’s own box, as the website')
            await p.keyboard.press('Escape'); await E("document.getElementById('tv-root') && (document.getElementById('tv-root').innerHTML = '')")
            # right-click: Apple's menu with the board's choices; Restore picked
            await E("window.__calls = []; window.__menuPick = 1")
            r = await p.locator('.mtr-row').first.bounding_box()
            await p.mouse.click(r['x'] + 300, r['y'] + 20, button='right'); await p.wait_for_timeout(500)
            mm = await E("window.__calls.find((m) => m.cmd === 'menu')")
            labels = [x.get('label') for x in (mm or {}).get('args', {}).get('list', []) if 'label' in x]
            check(labels[:2] == ['Open', 'Restore'] and labels[-1] == 'Delete Forever…', f'right-click: Apple’s menu {labels}')
            await p.wait_for_timeout(600)
            left = await p.locator('.mtr-row').count()
            check(left == n - 2, 'the menu’s Restore restores it')
            # Delete Forever: Apple's alert — Cancel keeps it, Delete Forever deletes
            await E("window.__calls = []; window.__alertPress = false")
            await p.locator('.mtr-rnd').first.click(); await p.wait_for_timeout(500)
            al = await E("window.__calls.find((m) => m.cmd === 'alert')")
            check(bool(al) and al['args']['ok'] == 'Delete Forever' and al['args']['destructive'] is True and 'can’t be restored' in al['args']['body'], 'Delete Forever asks with Apple’s alert (T7)')
            check(await p.locator('.mtr-row').count() == left, 'Cancel keeps it')
            await E("window.__alertPress = true")
            await p.locator('.mtr-rnd').first.click(); await p.wait_for_timeout(800)
            check(await p.locator('.mtr-row').count() == left - 1, 'Delete Forever deletes it')
            await p.screenshot(path=os.path.join(SHOTS, 'mactrash-after.png'))
            # an Account Manager: no Empty Trash, no Delete Forever (light)
            ctx2, q = await mac(AM, dark=False)
            await q.evaluate("()=>go('trash')"); await q.wait_for_timeout(500)
            check(await q.locator('.mtr').count() == 1 and await q.locator('.mtr-danger').count() == 0 and await q.locator('.mtr-rnd').count() == 0, 'an Account Manager: Restore only (T2)')
            await q.screenshot(path=os.path.join(SHOTS, 'mactrash-T2.png'))
            await ctx2.close()
            # Empty Trash (one more task in the Trash first)
            t4 = await E("db.tasks.find((t) => !t.parentId && t.projectId && !t.done).id")
            await E(f"()=>deleteTaskFlow('{t4}')"); await p.wait_for_timeout(1200)
            await E("window.__calls = []")
            if await p.locator('.mtr-danger').count():
                await p.locator('.mtr-danger').click(); await p.wait_for_timeout(800)
                al = await E("window.__calls.find((m) => m.cmd === 'alert')")
                check(bool(al) and al['args']['title'] == 'Empty the Trash?' and al['args']['ok'] == 'Empty Trash', 'Empty Trash asks with Apple’s alert')
                check(await p.locator('.mtr-row').count() == 0 and await p.locator('.mtr-danger').count() == 0, 'emptied: the empty words, no Empty Trash (T6)')
            await p.screenshot(path=os.path.join(SHOTS, 'mactrash-T6.png'))
            # the Mac Inbox with nothing unread opens on All
            await E("()=>{ myNotifs().forEach((n) => { n.read = true; }); go('inbox'); }"); await p.wait_for_timeout(500)
            check(await E("ui.inboxTab") == 'all', 'the Mac Inbox with nothing unread opens on All')
            # Update Ready: Apple's alert (Reload · What's New · Later), no bar; Later → again when the app comes back to the front
            await E("window.__calls = []; window.__alertPress = false; showUpdateBanner('9.9.9')"); await p.wait_for_timeout(400)
            ua = [m for m in await E("window.__calls") if m['cmd'] == 'alert']
            check(len(ua) == 1 and ua[0]['args']['title'] == 'Update Ready' and [ua[0]['args'][k] for k in ('ok', 'other', 'cancel')] == ['Reload', 'What’s New', 'Later'] and ua[0]['args']['whenFront'] is True, 'Update Ready: Apple’s alert, Reload · What’s New · Later')
            check(await p.locator('#update-banner.on').count() == 0 and not [m for m in await E("window.__calls") if m['cmd'] == 'updateReady'], '… no bar and no notification')
            await E("showUpdateBanner('9.9.9')"); await p.wait_for_timeout(300)
            check(len([m for m in await E("window.__calls") if m['cmd'] == 'alert']) == 1, 'asked once, not again on every check')
            await p.wait_for_timeout(1600)
            await E("window.dispatchEvent(new Event('blur')); window.dispatchEvent(new Event('focus'))"); await p.wait_for_timeout(300)
            check(len([m for m in await E("window.__calls") if m['cmd'] == 'alert']) == 2, 'Later: asked again when E11 Console comes back to the front')
            await ctx.close()
            # a browser: the website's own Trash
            ctx3 = await b.new_context(viewport={'width': 1440, 'height': 900}, extra_http_headers={'X-Dev-Email': ADMIN})
            r3 = await ctx3.new_page(); r3.on('pageerror', lambda e: errs.append(str(e)))
            await r3.goto(BASE + '/'); await r3.wait_for_function('typeof db !== "undefined" && db && db.tasks && db.tasks.length > 0', timeout=20000)
            await r3.wait_for_timeout(800)
            await r3.evaluate("()=>{ myNotifs().forEach((n) => { n.read = true; }); go('inbox'); }"); await r3.wait_for_timeout(300)
            check(await r3.evaluate("ui.inboxTab") == 'primary', 'browsers: the Inbox opens on its unread tab as before')
            await r3.evaluate("()=>go('trash')"); await r3.wait_for_timeout(300)
            check(await r3.locator('.mtr').count() == 0 and await r3.locator('.trash').count() == 1, 'browsers: the website’s own Trash')
            check(not errs, f'no page errors {errs}')
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'FAILS {fails}')
asyncio.run(main())
