import asyncio, sys, json
from playwright.async_api import async_playwright
import os; SP=os.environ.get('OUT', 'appstore-out')
UA='Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'
CLEAN = "document.querySelectorAll('#notif-root > *, .toast').forEach(x=>x.remove()); for (const e of [...document.querySelectorAll('body *')]) { if (e.isConnected && /Black Friday/.test(e.textContent) && e.textContent.length < 300 && !(e.parentElement && /Black Friday/.test(e.parentElement.textContent) && e.parentElement.textContent.length < 300)) e.remove(); }"
async def shot(b, email, name, js, wait=3500, dark=False):
    c = await b.new_context(viewport={'width':440,'height':956}, device_scale_factor=3, is_mobile=True, has_touch=True, user_agent=UA, color_scheme='dark' if dark else 'light')
    await c.add_cookies([{'name':'e11_dev_email','value':email,'url':'http://localhost:8772'}])
    pg = await c.new_page()
    await pg.goto('http://localhost:8772/'); await pg.wait_for_timeout(3500)
    await pg.evaluate(CLEAN)
    if js: r = await pg.evaluate("async () => {" + js + "}"); print(name, r)
    await pg.wait_for_timeout(wait); await pg.evaluate(CLEAN)
    if name == 'comments': await pg.evaluate("(() => { const f=document.querySelector('.tm-feed'); f.scrollTop=f.scrollHeight;  })()"); await pg.wait_for_timeout(600)
    await pg.screenshot(path=f'{SP}/shots/{name}.png')
    await c.close()
S = {
 'home': ('lena.farouk@example.com', ''),
 'task': ('leila.aziz@example.com', "const t=db.tasks.find(x=>/Winter Drive/.test(x.title)); openTask(t.id); return t.title"),
 'comments': ('leila.aziz@example.com', "const t=db.tasks.find(x=>/Winter Drive/.test(x.title)); openTask(t.id); await new Promise(r=>setTimeout(r,800)); document.querySelector('[data-action=side-tab][data-tab=comments]').click(); await new Promise(r=>setTimeout(r,3000)); const c=[...document.querySelectorAll('*')].filter(e=>/^Two directions/.test(e.textContent.trim())).pop(); c&&c.scrollIntoView({block:'start'}); const sc=c&&(function f(e){return !e?null:(e.scrollHeight>e.clientHeight+5&&getComputedStyle(e).overflowY!='visible'?e:f(e.parentElement))})(c.parentElement); if(sc) sc.scrollTop-=70; return !!c"),
 'reviews': ('claire.dubois@example.com', "go('reviews'); return 1"),
 'clients': ('leila.aziz@example.com', "go('clients'); return 1"),
 'review': ('claire.dubois@example.com', "go('reviews'); await new Promise(r=>setTimeout(r,800)); const el=[...document.querySelectorAll('[data-ph=open-review]')].find(e=>/Winter Drive/.test(e.textContent)); el && el.click(); return !!el"),
 'inbox': ('leila.aziz@example.com', "go('inbox'); return 1"),
}
async def main():
    which = sys.argv[1:]
    async with async_playwright() as p:
        b = await p.chromium.launch()
        for k in (which or S): await shot(b, S[k][0], k, S[k][1])
        await b.close()
asyncio.run(main())
