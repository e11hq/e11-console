"""Files: square client logos (light logo → dark square, dark logo → light square, older logos converted),
smaller image copies for lists, Office previews (Word/PowerPoint/Excel → PDF), and the task panel opening
on Details, wide and without a shadow."""
import asyncio, base64, io, json, os, shutil, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.environ.get('SHOTS', tempfile.gettempdir())
PORT = 18191; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def png_logo(color, transparent=True, w=900, h=300):
    from PIL import Image, ImageDraw
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0) if transparent else (200, 30, 40, 255)); d = ImageDraw.Draw(im)
    d.rectangle((60, 60, w - 60, h - 60), fill=color)
    b = io.BytesIO(); im.save(b, 'PNG'); return base64.b64encode(b.getvalue()).decode()
def big_photo():
    from PIL import Image
    im = Image.effect_noise((3000, 2000), 80).convert('RGB'); b = io.BytesIO(); im.save(b, 'PNG'); return base64.b64encode(b.getvalue()).decode()
async def main():
    env = {**os.environ, 'DATA_DIR': tempfile.mkdtemp(), 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.2.5-test.1'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/me', headers={'X-Dev-Email': ADMIN}))
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    office = {n: base64.b64encode(open('/tmp/' + n, 'rb').read()).decode() for n in ['brief.docx', 'recap.pptx', 'plan.xlsx'] if os.path.exists('/tmp/' + n)}
    async with async_playwright() as pw:
        b = await pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
        await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
        pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto('/'); await pg.wait_for_timeout(600); await pg.mouse.click(5, 300); await pg.wait_for_timeout(2500)
        E = pg.evaluate
        FILE = "(b64, name, type) => { const bin = atob(b64); const a = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i); return new File([a], name, { type }); }"
        # --- square logos
        bg = await E(f"""async ([w, k]) => {{ const mk = {FILE};
            const px = async (b64) => {{ const f = await squareLogo(mk(b64, 'l.png', 'image/png')); const im = await loadImage(f); const c = document.createElement('canvas'); c.width = im.naturalWidth; c.height = im.naturalHeight; const g = c.getContext('2d'); g.drawImage(im, 0, 0); return [im.naturalWidth, im.naturalHeight, Array.from(g.getImageData(5, 5, 1, 1).data)]; }};
            return [await px(w), await px(k)]; }}""", [png_logo((255, 255, 255, 255)), png_logo((20, 20, 30, 255))])
        check(bg[0][0] == bg[0][1] == 800, f'logo becomes an 800×800 square {bg[0][:2]}')
        check(sum(bg[0][2][:3]) < 120, f'white logo gets a dark background {bg[0][2]}')
        check(sum(bg[1][2][:3]) > 600, f'dark logo gets a light background {bg[1][2]}')
        opaque = await E(f"""async (b64) => {{ const mk = {FILE}; const f = await squareLogo(mk(b64, 'o.png', 'image/png')); const im = await loadImage(f); const c = document.createElement('canvas'); c.width = 800; c.height = 800; const g = c.getContext('2d'); g.drawImage(im, 0, 0); return Array.from(g.getImageData(3, 3, 1, 1).data); }}""", png_logo((255, 255, 255, 255), transparent=False))
        check(abs(opaque[0] - 200) < 25 and opaque[1] < 60, f'a logo with its own background gets a square of its edge colour {opaque}')
        # older (non-square) logo is converted when an Admin opens Client Assets
        await E(f"""async (b64) => {{ const mk = {FILE}; const up = await ServerHost.uploadMany([mk(b64, 'old.png', 'image/png')], {{ dest: 'Clients/_logos' }}); const c = createClient('Oldco'); c.logo = up[0].path; commit(); }}""", png_logo((255, 255, 255, 255)))
        await pg.wait_for_timeout(800)
        check(not await E("isSquareLogo(db.clients.find(c=>c.name==='Oldco').logo)"), 'older logo starts as not square')
        await E("go('clients')"); await pg.wait_for_timeout(4000)
        check(await E("isSquareLogo(db.clients.find(c=>c.name==='Oldco').logo)"), 'opening Client Assets converts it to a square')
        check(await pg.locator('.ca-card .cl-logo.sq').count() >= 1, 'it shows edge to edge')
        await pg.screenshot(path=os.path.join(SHOTS, 'files_assets.png'))
        # --- smaller copies of images
        tid = await E("db.tasks.find(t=>/Offroad Campaign/.test(t.title)).id")
        path = await E(f"""async ([b64, tid]) => {{ const mk = {FILE}; const up = await ServerHost.uploadMany([mk(b64, 'photo.png', 'image/png')], {{ taskId: tid }}); const t = task(tid); t.attachments.push({{ ...up[0], addedAt: nowISO() }}); commit(); return up[0].path; }}""", [big_photo(), tid])
        full = await E("(p) => fetch('/__file/' + p.split('/').map(encodeURIComponent).join('/')).then(r => r.blob()).then(b => b.size)", path)
        small = await E("(p) => fetch('/__file/' + p.split('/').map(encodeURIComponent).join('/') + '?w=640').then(r => r.blob()).then(b => [b.size, b.type])", path)
        check(small[0] < full / 5, f'list copy of a big photo is much smaller: {small[0]//1024} KB vs {full//1024} KB ({small[1]})')
        await E(f"openTask('{tid}')"); await pg.wait_for_timeout(1200)
        srcs = await E("[...document.querySelectorAll('#detail img')].map(i=>i.getAttribute('src')).filter(s=>s.includes('photo'))")
        check(srcs and all('?w=' in s for s in srcs), f'task page shows the smaller copy: {srcs}')
        # --- Office previews
        for name, b64 in office.items():
            att = await E(f"""async ([b64, name, tid]) => {{ const mk = {FILE}; const up = await ServerHost.uploadMany([mk(b64, name, 'application/octet-stream')], {{ taskId: tid }}); const a = {{ ...up[0], addedAt: nowISO() }}; task(tid).attachments.push(a); commit(); return a; }}""", [b64, name, tid])
            t0 = time.time(); r = await E("(a) => Host.call('docPreview', { id: a.id, path: a.path })", att)
            check(bool(r.get('pdf')), f'{name} → PDF preview in {time.time()-t0:.1f}s')
            th = await E("(a) => Host.call('thumb', { id: a.id, path: a.path })", att)
            check(bool(th.get('thumb')), f'{name} gets a first-page thumbnail')
        await E("(n) => previewFile(task(ui.taskId).attachments.find(a => a.name === n))", 'recap.pptx'); await pg.wait_for_timeout(1500)
        check(await pg.locator('.fpv-slide iframe.fv-pdf').count() == 1, 'PowerPoint opens as a full preview in the viewer')
        await pg.screenshot(path=os.path.join(SHOTS, 'files_pptx.png'))
        await E("document.getElementById('overlay-root').innerHTML=''")
        # --- task panel: Details first, wide, no shadow
        await E(f"()=>{{ ui.detailMode='side'; ui.sideTab='comments'; renderDetail(); }}"); await pg.wait_for_timeout(300)
        await E("closeDetail()"); await E(f"openTask('{tid}')"); await pg.wait_for_timeout(700)
        check(await E("document.querySelector('#detail .tm').dataset.tab || ui.sideTab") == 'details', 'a task opened again starts on Details')
        st = await E("(()=>{ const s=getComputedStyle(document.querySelector('#detail .tm')); return [s.boxShadow, Math.round(parseFloat(s.width))]; })()")
        check(st[0] == 'none' and st[1] >= 700, f'side panel is wide and has no shadow: {st}')
        await pg.screenshot(path=os.path.join(SHOTS, 'files_side.png'))
        check(not errs, f'no page errors {errs}')
        await b.close()
    srv.terminate()
    print('FAILS', len(fails), fails)
asyncio.run(main())
