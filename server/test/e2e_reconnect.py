import asyncio, os, subprocess, tempfile, time, urllib.request
from playwright.async_api import async_playwright
ROOT='/home/claude/e11-console'; PORT=18206; BASE=f'http://127.0.0.1:{PORT}'
D=tempfile.mkdtemp()
env={**os.environ,'DATA_DIR':D,'AUTH_DEV':'1','ADMIN_EMAIL':'haris@e11-digital.com','PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.1.3-test.32'}
def start():
    p=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: urllib.request.urlopen(BASE+'/api/health'); break
        except Exception: time.sleep(0.1)
    return p
async def main():
    srv=start(); ok=True
    async with async_playwright() as p:
        b=await p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
        ctx=await b.new_context(viewport={'width':1300,'height':800},base_url=BASE)
        await ctx.add_cookies([{'name':'e11_dev_email','value':'haris@e11-digital.com','url':BASE}])
        pg=await ctx.new_page(); await pg.goto('/'); await pg.wait_for_timeout(500); await pg.mouse.click(10,10); await pg.wait_for_timeout(1500)
        L=lambda: pg.evaluate("document.getElementById('save-label').textContent")
        print('start:', await L())
        srv.terminate(); srv.wait(); await pg.wait_for_timeout(4000)
        a=await L(); print('server down 4s:', a); ok &= a=='Reconnecting…'
        await pg.wait_for_timeout(17000)
        a=await L(); print('server down 21s:', a); ok &= a.startswith('Offline')
        await pg.evaluate("()=>{ const t=createTask({title:'Made while offline'}); commit({delay:0}); }")
        srv=start()
        await pg.evaluate("window.dispatchEvent(new Event('focus'))"); await pg.wait_for_timeout(2500)
        a=await L(); print('back + focus:', a); ok &= a.startswith('Synced')
        n=urllib.request.urlopen(urllib.request.Request(BASE+'/api/snapshot',headers={'X-Dev-Email':'haris@e11-digital.com'})).read().decode().count('Made while offline')
        print('offline change reached the server:', n==1); ok &= n==1
        await b.close()
    srv.terminate()
    print('ALL PASS' if ok else 'FAILED')
asyncio.run(main())
