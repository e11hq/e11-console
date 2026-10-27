"""Videos in comments show their thumbnail as a cover and load nothing until played; playing uses the 720p light copy
(starts at once), Download keeps the original; the phone review slides do the same."""
import asyncio, os, tempfile, time, subprocess, urllib.request, json
from playwright.async_api import async_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 18246; BASE = f'http://127.0.0.1:{PORT}'; ADMIN = 'haris@e11-digital.com'
OUT = tempfile.gettempdir()
fails = []
def check(c, m):
    print(('PASS ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
async def main():
    data = tempfile.mkdtemp()
    clip = os.path.join(tempfile.mkdtemp(), 'Ford-Ramadan.mp4')
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc=size=1920x1080:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '4', '-c:v', 'libx264', '-preset', 'ultrafast', '-b:v', '12M', '-c:a', 'aac', '-shortest', clip], check=True)
    env = {**os.environ, 'DATA_DIR': data, 'AUTH_DEV': '1', 'ADMIN_EMAIL': ADMIN, 'PORT': str(PORT), 'WEB_DIR': os.path.join(ROOT, 'web'), 'APP_VERSION': '1.8.1-test.1', 'VIEW_MIN_SIZE': '1000'}
    srv = subprocess.Popen(['node', os.path.join(ROOT, 'server/src/index.js')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + '/api/health'); break
        except Exception: time.sleep(0.1)
    urllib.request.urlopen(urllib.request.Request(BASE + '/api/sample', method='POST', data=b'{}', headers={'X-Dev-Email': ADMIN, 'Content-Type': 'application/json'}))
    try:
        async with async_playwright() as pw:
            b = await pw.chromium.launch()
            ctx = await b.new_context(viewport={'width': 1440, 'height': 900}, base_url=BASE)
            await ctx.add_cookies([{'name': 'e11_dev_email', 'value': ADMIN, 'url': BASE}])
            pg = await ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
            vid_requests = []
            pg.on('request', lambda r: vid_requests.append(r.url) if 'Ford-Ramadan' in r.url and '.thumbs' not in r.url else None)
            await pg.goto('/'); await pg.wait_for_timeout(3000)
            await pg.evaluate("document.querySelectorAll('.hello-wrap,.pa-card').forEach(e => e.remove())")
            tid = await pg.evaluate("db.tasks.find(t => !t.parentId && !t.done).id")
            # upload the clip and post it in a comment
            async with pg.expect_file_chooser() as fc:
                await pg.evaluate(f"(() => {{ window.__up = Host.call('pickAttachments', {{ taskId: '{tid}' }}); }})()")
            await (await fc.value).set_files(clip)
            n = await pg.evaluate(f"""window.__up.then(r => {{ const t = task('{tid}'); t.comments.push({{ id: 'c-vid', authorId: currentUserId, text: 'Ramadan cut', html: 'Ramadan cut', at: nowISO(), reactions: {{}}, attachments: r.files, parentId: null }}); commit(); return r.files.length; }})""")
            check(n == 1, 'the clip uploaded')
            vid_requests.clear()
            await pg.evaluate(f"ui.sideTab = ui.forceTab = 'comments'; openTask('{tid}')"); await pg.wait_for_timeout(2500)
            v = await pg.evaluate("(() => { const v = document.querySelector('#detail .cm[data-comment=\"c-vid\"] video'); return v && { src: v.getAttribute('src'), preload: v.preload, poster: v.poster, loaded: v.parentElement.classList.contains('loaded') }; })()")
            print('video', v)
            check(v and v['preload'] == 'none' and '?view=1' in v['src'], f'the player waits for play and points at the light copy {v}')
            check(v and '.thumbs/' in (v['poster'] or ''), 'the thumbnail is its cover')
            check(v and v['loaded'], 'the box shows (no endless shimmer)')
            check(not vid_requests, f'opening the task downloads none of the video {vid_requests[:3]}')
            await pg.screenshot(path=os.path.join(OUT, 'videos_cover.png'))
            # the light copy gets made; playing uses it
            path = await pg.evaluate("task(ui.taskId).comments.find(c => c.id === 'c-vid').attachments[0].path")
            ok = False
            for _ in range(60):
                info = await pg.evaluate(f"fetch('/__file/' + {json.dumps(path)}.split('/').map(encodeURIComponent).join('/') + '?view=1', {{ method: 'HEAD' }}).then(r => +r.headers.get('content-length'))")
                orig = os.path.getsize(clip)
                if info and info < orig: ok = True; break
                await pg.wait_for_timeout(1000)
            check(ok, f'the light copy is ready and smaller ({info} < {os.path.getsize(clip)})')
            dl = await pg.evaluate(f"fetch('/__file/' + {json.dumps(path)}.split('/').map(encodeURIComponent).join('/'), {{ method: 'HEAD' }}).then(r => +r.headers.get('content-length'))")
            check(dl == os.path.getsize(clip), 'Download is still the original')
            # (the test browser can't decode H.264, so playback itself is checked with ffprobe in viewcopy.test.js)
            check(not errs, f'no page errors {errs}')
            await b.close()
    finally:
        srv.terminate()
    print('ALL PASS' if not fails else f'{len(fails)} FAILED')
    raise SystemExit(1 if fails else 0)
asyncio.run(main())
