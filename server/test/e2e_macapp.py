"""The web app inside the E11 Console Mac app: a pretend native bridge answers file-picker,
read, save and badge calls. Also checks the installer is served without sign-in."""
import asyncio, base64, json, os, subprocess, sys, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18184; BASE = f'http://127.0.0.1:{PORT}'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
RAW = b'MAC FILE ' * 300000                          # 2.7 MB -> two pieces
FAKE_FILE = base64.b64encode(RAW).decode()
BRIDGE = """
window.__native = { calls: [], saved: {} };
const FILE = atob('%s');
window.webkit = { messageHandlers: { e11: { postMessage(raw) {
  const m = JSON.parse(raw); window.__native.calls.push(m.cmd);
  let res = { ok: true };
  if (m.cmd === 'pickLocalFiles') res = { ok: true, files: [{ token: 'tok1', name: 'Brief from Finder.txt', size: FILE.length }] };
  if (m.cmd === 'readLocalChunk') res = { ok: true, b64: btoa(FILE.slice(m.args.offset, m.args.offset + m.args.length)) };
  if (m.cmd === 'saveFile') { const s = window.__native.saved[m.args.token] = window.__native.saved[m.args.token] || { name: m.args.name, size: 0, open: m.args.open }; s.size += atob(m.args.b64).length; s.done = m.args.done; }
  if (m.cmd === 'badge') window.__native.badge = m.args.n;
  setTimeout(() => window.__e11NativeReply(m.id, res), 5);
} } } };
""" % FAKE_FILE
async def main():
    data = tempfile.mkdtemp()
    env = {**os.environ, 'DATA_DIR': data, 'AUTH_DEV': '1', 'ADMIN_EMAIL': 'arsal@e11-digital.com', 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.1.0'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    # installer: no sign-in, server address filled in
    sh = urllib.request.urlopen(BASE + '/install').read().decode()
    check('SERVER="${E11_SERVER:-http://127.0.0.1:%d}"' % PORT in sh, 'installer served without sign-in, with this server address')
    check(urllib.request.urlopen(BASE + '/install/main.js').read().startswith(b'// E11 Console for Mac'), 'Mac app source served')
    check(len(urllib.request.urlopen(BASE + '/install/AppIcon.png').read()) > 1000, 'app icon served')
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        ctx = await b.new_context(viewport={'width': 1400, 'height': 900}, base_url=BASE)
        await ctx.add_cookies([{'name': 'e11_dev_email', 'value': 'arsal@e11-digital.com', 'url': BASE}])
        await ctx.add_init_script(BRIDGE)
        pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto('/'); await pg.wait_for_timeout(700); await pg.mouse.click(1390, 890); await pg.wait_for_timeout(1500)
        E = pg.evaluate
        check(await E("Host.isMacApp && Host.isServer"), 'page knows it is inside the Mac app')
        await E("()=>{const p=createProject('Ford',COLORS[0]); createTask({projectId:p.id, sectionId:p.sections[0].id, title:'Mac upload'}); commit()}")
        await pg.wait_for_timeout(500)
        tid = await E("db.tasks.find(t=>t.title==='Mac upload').id")
        await E("(id)=>openTask(id)", tid); await pg.wait_for_timeout(300)
        await pg.click('.tm-actions [data-action="attach"]'); await pg.wait_for_timeout(3000)
        att = await E("(id)=>task(id).attachments.map(a=>[a.name,a.size,a.path])", tid)
        check(len(att) == 1 and att[0][1] == len(RAW), f'file chosen in the Mac picker uploaded in pieces: {att}')
        calls = await E("window.__native.calls")
        check(calls.count('readLocalChunk') == 2 and 'pickLocalFiles' in calls, 'read through the Mac app in 2 pieces')
        # download all -> saved to Downloads via the app
        await E("(p)=>Host.call('revealPath',{path:p})", att[0][2]); await pg.wait_for_timeout(1500)
        saved = list((await E("window.__native.saved")).values())
        check(len(saved) == 1 and saved[0]['size'] == len(RAW) and saved[0]['done'] and not saved[0]['open'], f'download saved through the app: {saved}')
        await E("(p)=>Host.call('openPath',{path:p})", att[0][2]); await pg.wait_for_timeout(1500)
        saved = list((await E("window.__native.saved")).values())
        check(any(s['open'] for s in saved), 'opening a file saves a temporary copy and opens it')
        # a download link (a content plan's PowerPoint / PDF) is saved to Downloads, the window stays on the app
        before = len(await E("Object.keys(window.__native.saved)")); url0 = pg.url
        await E("(p)=>{const a=document.createElement('a'); a.href='/__file/'+p.split('/').map(encodeURIComponent).join('/'); a.download='Plan - Round 1.pptx'; a.textContent='dl'; document.body.appendChild(a); a.click(); a.remove();}", att[0][2]); await pg.wait_for_timeout(1500)
        saved = list((await E("window.__native.saved")).values())
        check(pg.url == url0 and len(saved) == before + 1 and any(x['name'] == 'Plan - Round 1.pptx' and x['done'] and not x['open'] for x in saved), f'a download link is saved through the app, not opened in its window: {[x["name"] for x in saved]}')
        # badge for unread notifications
        await E("()=>{db.notifications.push({id:'nx',to:currentUserId,from:currentUserId,taskId:db.tasks[0].id,kind:'mention',text:'x',at:nowISO(),read:false}); renderSidebar()}"); await pg.wait_for_timeout(300)
        check(await E("window.__native.badge") == 1, 'Dock badge shows unread notifications')
        check(await pg.locator('[data-action="allow-notifs"]').count() == 0, 'no browser notification prompt inside the app')
        await pg.screenshot(path=os.path.join(SHOTS, 'e2e_macapp.png'))
        # browser (not the Mac app): menu offers the Mac app with the command
        ctx2 = await b.new_context(viewport={'width': 1400, 'height': 900}, base_url=BASE)
        await ctx2.add_cookies([{'name': 'e11_dev_email', 'value': 'arsal@e11-digital.com', 'url': BASE}])
        p2 = await ctx2.new_page(); await p2.goto('/'); await p2.wait_for_timeout(700); await p2.mouse.click(1390, 890); await p2.wait_for_timeout(1200)
        await p2.click('#me-chip'); await p2.wait_for_timeout(200)
        await p2.click('.menu :text("Get the Mac app")'); await p2.wait_for_timeout(300)
        check(f'curl -fsSL {BASE}/install | bash' in await p2.locator('.mac-cmd code').inner_text(), 'Get the Mac app shows the one-line install command')
        await p2.screenshot(path=os.path.join(SHOTS, 'e2e_macdialog.png'))
        check(not errs, 'no page errors ' + str(errs))
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails); sys.exit(1 if fails else 0)
asyncio.run(main())
