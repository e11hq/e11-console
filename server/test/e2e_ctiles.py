"""A comment's files: 1 shows full size as before; 2 side by side; 3+ up to 3 a row; more than 6 → 6 tiles, the 6th "+N".
Tapping a tile opens the preview with every file of that comment; the ⋯ on a tile has Copy / Preview / Download."""
import asyncio, base64, io, os, subprocess, tempfile, time, urllib.request
from PIL import Image
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18231; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
SHOTS = os.environ.get('SHOTS', tempfile.mkdtemp())
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def png(i):
    im = Image.new('RGB', (1600, 1000), ((60 + i * 40) % 255, (120 + i * 70) % 255, (200 + i * 30) % 255))
    b = io.BytesIO(); im.save(b, 'PNG'); return base64.b64encode(b.getvalue()).decode()
FILE = "(b64, name, type) => { const bin = atob(b64); const a = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i); return new File([a], name, { type }); }"
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.7-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
            ctx = await b.new_context(viewport={'width': 1400, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(5, 5); await pg.wait_for_timeout(3000)
            E = pg.evaluate
            tid = await E("(db.tasks.find(t=>/Offroad Campaign/.test(t.title)) || db.tasks[0]).id")
            await E(f"""async ([imgs, tid]) => {{ const mk = {FILE};
              const files = imgs.map((b, i) => mk(b, `shot-${{i + 1}}.png`, 'image/png'));
              files.push(new File([new Uint8Array(2000)], 'brief.pdf', {{ type: 'application/pdf' }}));
              const up = await ServerHost.uploadMany(files, {{ taskId: tid }});
              const t = task(tid); const who = t.comments[0] ? t.comments[0].authorId : currentUserId;
              const add = (id, txt, l) => t.comments.push({{ id, text: txt, html: txt, authorId: who, at: nowISO(), parentId: null, reactions: {{}}, attachments: l.map(a => ({{ ...a, addedAt: nowISO() }})) }});
              add('ct1', 'One file', [up[0]]); add('ct2', 'Two files', [up[1], up[2]]); add('ct3', 'Three files', [up[3], up[8], up[4]]);
              add('ct5', 'Five files', up.slice(0, 5)); add('ct8', 'Eight files', up.slice(0, 8)); commit(); }}""", [[png(i) for i in range(8)], tid])
            await E(f"openTask('{tid}')"); await pg.wait_for_timeout(1500)
            L = lambda cid: E(f"""(() => {{ const c = document.querySelector('[data-comment-id="{cid}"], [data-id="{cid}"].cm, #c-{cid}') || [...document.querySelectorAll('.cm, .comment')].find(x => x.textContent.includes(''));
              return null; }})()""")
            info = await E("""(() => { const out = {}; for (const g of document.querySelectorAll('.c-files')) { const cm = g.closest('[class*="cm"], .comment'); const txt = (cm ? cm.textContent : '').match(/(One|Two|Three|Five|Eight) files?/); if (!txt) continue;
                const tiles = [...g.querySelectorAll(':scope > .ct')]; const ys = new Set(tiles.map(t => Math.round(t.getBoundingClientRect().top)));
                out[txt[1]] = { grid: g.classList.contains('ct-grid'), ap: g.querySelectorAll('.ap').length, tiles: tiles.length, rows: ys.size, more: (g.querySelector('.ct-more') || {}).textContent || '', w: tiles.map(t => Math.round(t.getBoundingClientRect().width)) }; } return out; })()""")
            print(info)
            check(info.get('One', {}).get('ap') == 1 and not info['One']['grid'], '1 file: full size as before')
            check(info.get('Two', {}).get('tiles') == 2 and info['Two']['rows'] == 1, '2 files: side by side')
            check(info.get('Three', {}).get('tiles') == 3 and info['Three']['rows'] == 1 and max(info['Three']['w']) < min(info['Two']['w']), '3 files: one row of 3, smaller')
            check(info.get('Five', {}).get('tiles') == 5 and info['Five']['rows'] == 2 and not info['Five']['more'], '5 files: 3 + 2')
            check(info.get('Eight', {}).get('tiles') == 6 and info['Eight']['rows'] == 2 and info['Eight']['more'] == '+2', '8 files: 6 tiles, the last says +2')
            g8 = pg.locator('.c-files.ct-grid').last
            await g8.scroll_into_view_if_needed(); await pg.wait_for_timeout(800)
            await pg.screenshot(path=os.path.join(SHOTS, 'ctiles_desktop.png'), full_page=False)
            await g8.locator('.ct').nth(5).locator('.ct-media').click(); await pg.wait_for_timeout(1000)
            n = await E("document.querySelectorAll('.fpv-th').length || document.querySelectorAll('.fpv-slide').length")
            check(await pg.locator('.fpv').count() > 0, 'tapping the +2 tile opens the preview')
            check(await E("Viewer.isOpen()") and n >= 8 or n == 8, f'the preview has all 8 files of the comment ({n})')
            await E("Viewer.close()"); await pg.wait_for_timeout(500)
            await g8.locator('.ct').first.locator('[data-action="ct-menu"]').click(); await pg.wait_for_timeout(300)
            mt = await E("(document.querySelector('.menu') || {}).textContent || ''")
            check('Copy' in mt and 'Preview' in mt and 'Download' in mt, f'⋯ on a tile: Copy / Preview / Download')
            await pg.keyboard.press('Escape')
            check(not errs, f'no page errors {errs}')
            # the phone
            pctx = await b.new_context(viewport={'width': 390, 'height': 844}, base_url=BASE, has_touch=True, is_mobile=True, device_scale_factor=2)
            await pctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
            pp = await pctx.new_page(); perr = []; pp.on('pageerror', lambda e: perr.append(str(e)))
            await pp.goto('/'); await pp.wait_for_timeout(3500)
            await pp.evaluate(f"ui.sideTab = ui.forceTab = 'comments'; openTask('{tid}')"); await pp.wait_for_timeout(1500)
            w = await pp.evaluate("[...document.querySelectorAll('.c-files.ct-grid')].map(g => [g.querySelectorAll('.ct').length, Math.round(g.getBoundingClientRect().width), Math.round(g.scrollWidth)])")
            check(len(w) == 4 and all(x[2] <= x[1] + 1 for x in w), f'phone: tiles fit the width {w}')
            await pp.locator('.c-files.ct-grid').nth(2).scroll_into_view_if_needed(); await pp.wait_for_timeout(800)
            await pp.screenshot(path=os.path.join(SHOTS, 'ctiles_phone.png'))
            check(not perr, f'phone: no page errors {perr}')
            await b.close()
    finally:
        srv.terminate()
    print('SHOTS', SHOTS)
    print('FAILED' if fails else 'ALL PASS', len(fails))
asyncio.run(main())
