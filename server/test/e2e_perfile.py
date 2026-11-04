"""Per-file CD decisions: Request amendments with ticked files approves the rest, posts one comment grouped by file;
the approved files are kept across rounds; the next round's approval makes the whole set (r.set) the final files."""
import asyncio, os, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18297; BASE=f'http://127.0.0.1:{PORT}'; ADMIN='haris@e11-digital.com'
async def main():
    subprocess.run(['fuser','-k',f'{PORT}/tcp'],stderr=subprocess.DEVNULL)
    env={**os.environ,'DATA_DIR':tempfile.mkdtemp(),'AUTH_DEV':'1','ADMIN_EMAIL':ADMIN,'PORT':str(PORT),'WEB_DIR':ROOT+'/web','APP_VERSION':'1.6.1-test.1'}
    srv=subprocess.Popen(['node',ROOT+'/server/src/index.js'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    ok=[]
    def check(good, what, extra=''):
        ok.append(bool(good)); print(('ok  ' if good else 'FAIL'), what, '' if good else extra)
    try:
        for _ in range(50):
            try: urllib.request.urlopen(BASE+'/api/health'); break
            except Exception: time.sleep(0.1)
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/me',headers={'X-Dev-Email':ADMIN}))
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/sample/reset',method='POST',data=b'{}',headers={'X-Dev-Email':ADMIN,'Content-Type':'application/json'})).read()
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            ctx=await b.new_context(viewport={'width':1440,'height':900},base_url=BASE)
            await ctx.add_cookies([{'name':'e11_dev_email','value':ADMIN,'url':BASE}])
            pg=await ctx.new_page(); errs=[]; toasts=[]
            pg.on('pageerror', lambda e: errs.append(str(e)))
            await pg.goto('/'); await pg.wait_for_timeout(4000)
            await pg.evaluate("window.__t = []; const _t = toast; window.toast = (m, ...a) => { window.__t.push(String(m)); return _t(m, ...a); }")
            tid = await pg.evaluate("""(() => {
              db.meta.cdUserId = currentUserId;
              const p = db.projects.find(p => !p.inactive && statusList({ projectId: p.id }).some(s => /^review$/i.test(s.name)));
              const s0 = statusList({ projectId: p.id }).find(s => /progress/i.test(s.name));
              const pr = db.users.find(u => u.role === 'production' && u.active !== false);
              const t = createTask({ projectId: p.id, sectionId: s0.id, title: 'Per-file check', assignees: [pr.id] }); t.needsCD = true;
              const f = (n) => ({ id: uid(), name: n, path: `attachments/${t.id}/${n}`, size: 10, addedAt: nowISO() });
              const A = f('A.png'), B = f('B.png'), C = f('C.png');
              const r = { id: uid(), by: pr.id, at: nowISO(), files: [A.id, B.id, C.id], state: 'pending', epoch: 0, round: 1 };
              t.reviews = [r]; [A, B, C].forEach(a => t.attachments.push({ ...a, reviewId: r.id })); t.lockedAt = r.at; syncCD(t);
              window.__ids = { A: A.id, B: B.id, C: C.id, pr: pr.id }; persist(0); return t.id; })()""")
            T = f"db.tasks.find(t => t.id === '{tid}')"
            await pg.wait_for_timeout(800)
            # round 1: C needs changes, A and B approved
            await pg.evaluate(f"decideReview({T}, {T}.reviews[0], 'amend', 'Overall nice', {{ [__ids.C]: 'Make the logo bigger' }})")
            await pg.wait_for_timeout(1200)
            r1 = await pg.evaluate(f"{T}.reviews[0]")
            ids = await pg.evaluate("__ids")
            check(r1['state'] == 'amend' and sorted(r1['ok']) == sorted([ids['A'], ids['B']]) and list(r1['need'].keys()) == [ids['C']], 'round 1: A, B approved — C needs changes', r1)
            c = await pg.evaluate(f"{T}.comments[{T}.comments.length - 1]")
            check('C.png' in c['html'] and 'Make the logo bigger' in c['html'] and 'Overall nice' in c['html'] and 'mention' in c['html'] and len(c['attachments']) == 1, 'one comment: the mention, the general note, C with its note, C attached', c['html'])
            shown = await pg.evaluate(f"shownAtts({T}).map(a => a.name).sort()")
            check(shown == ['A.png', 'B.png'], 'A and B show in the task files at once', shown)
            res = await pg.evaluate(f"resultOf({T}.reviews[0])")
            check(res['k'] == 'mix' and res['long'] == '2 approved · 1 needs changes', 'the result reads "2 approved · 1 needs changes"', res)
            # what the person sees when resubmitting
            need = await pg.evaluate(f"stillNeeded({T}, __ids.pr).map(x => x.a.name)")
            check(need == ['C.png'], 'Still needed: C', need)
            check(await pg.evaluate(f"{T}.cdStatus !== 'approved' && !cdOK({T})"), 'the task is not CD approved yet')
            # round 2: only C (a new version, same name)
            await pg.evaluate(f"""(() => {{ const t = {T}; const C2 = {{ id: uid(), name: 'C.png', path: `attachments/${{t.id}}/C2.png`, size: 11, addedAt: nowISO() }};
              const r = {{ id: uid(), by: __ids.pr, at: nowISO(), files: [C2.id], state: 'pending', epoch: 0, round: 2 }}; t.reviews.push(r); t.attachments.push({{ ...C2, reviewId: r.id }}); syncCD(t); __ids.C2 = C2.id; persist(0); }})()""")
            car = await pg.evaluate(f"carriedOf({T}, {T}.reviews[1]).map(a => a.name).sort()")
            check(car == ['A.png', 'B.png'], 'round 2 carries A and B (already approved)', car)
            await pg.evaluate(f"decideReview({T}, {T}.reviews[1], 'approve')"); await pg.wait_for_timeout(1500)
            r2 = await pg.evaluate(f"{T}.reviews[1]"); ids = await pg.evaluate("__ids")
            check(r2['state'] == 'approved' and sorted(r2['set']) == sorted([ids['A'], ids['B'], ids['C2']]), 'round 2 approved: the whole set is A, B and the new C', r2)
            check(await pg.evaluate(f"{T}.cdStatus === 'approved'"), 'CD Status Approved once every file is approved')
            fin = await pg.evaluate(f"{T}.comments.filter(c => c.auto).pop()")
            check(fin and sorted(a['name'] for a in fin['attachments']) == ['A.png', 'B.png', 'C.png'] and len(fin['attachments']) == 3, 'the final files comment carries A, B and the new C', fin and [a['name'] for a in fin['attachments']])
            # the server took every change (nothing refused)
            snap = json.loads(urllib.request.urlopen(urllib.request.Request(BASE+'/api/snapshot',headers={'X-Dev-Email':ADMIN})).read())
            st = next(t for t in snap['data']['tasks'] if t['id'] == tid)
            check(len(st['reviews']) == 2 and st['reviews'][1].get('set') and st['reviews'][0].get('need'), 'the server has both rounds with their per-file results')
            toasts = await pg.evaluate("__t")
            check(not any('allowed' in t for t in toasts), 'nothing refused', toasts)
            # the web dialog: ticks + notes
            await pg.evaluate(f"""(() => {{ const t = {T}; const f = (n) => ({{ id: uid(), name: n, path: `attachments/${{t.id}}/${{n}}`, size: 10, addedAt: nowISO() }}); t.reviewEpoch = 1; const X = f('X.mp4'), Y = f('Y.mp4');
              const r = {{ id: uid(), by: __ids.pr, at: nowISO(), files: [X.id, Y.id], state: 'pending', epoch: 1, round: 1 }}; t.reviews.push(r); [X, Y].forEach(a => t.attachments.push({{ ...a, reviewId: r.id }})); t.cdStatus = ''; syncCD(t); __ids.r3 = r.id; __ids.Y = Y.id; persist(0); }})()""")
            await pg.evaluate("decisionDialog(__ids.r3)"); await pg.wait_for_timeout(300)
            await pg.click('[data-d="amend"]'); await pg.wait_for_timeout(200)
            check(await pg.locator('.rd-file').count() == 2, 'the dialog lists both files to tick')
            await pg.locator(f'[data-tick="{await pg.evaluate("__ids.Y")}"]').check(); await pg.wait_for_timeout(150)
            await pg.locator('.rd-file.on textarea').fill('Shorter intro'); await pg.click('[data-d="send"]'); await pg.wait_for_timeout(600)
            r3 = await pg.evaluate(f"{T}.reviews[2]")
            check(r3['state'] == 'amend' and len(r3['ok']) == 1 and list(r3['need'].values()) == ['Shorter intro'], 'dialog: X approved, Y sent back with its note', r3)
            # the iPhone's Reviews (shell 38): the model the app draws, and its decisions
            await pg.evaluate(f"""(() => {{ const t = {T}; const f = (n) => ({{ id: uid(), name: n, path: `attachments/${{t.id}}/${{n}}`, size: 10, addedAt: nowISO() }}); const P = f('P.png'), Q = f('Q.png');
              const r = {{ id: uid(), by: __ids.pr, at: nowISO(), files: [P.id, Q.id], state: 'pending', epoch: 1, round: 2 }}; t.reviews.push(r); [P, Q].forEach(a => t.attachments.push({{ ...a, reviewId: r.id }})); syncCD(t); __ids.r4 = r.id; __ids.Q = Q.id; persist(0); }})()""")
            m = await pg.evaluate("NativeMe.reviewsModel()")
            w = next((x for x in m['waiting'] if x['id'] == ids_r4), None) if (ids_r4 := await pg.evaluate("__ids.r4")) else None
            check(w and w['round'] == 2 and w['carried'] == 1 and len(w['files']) == 2 and w['last'] and 'Shorter intro' in w['last'] and w['task'] == 'Per-file check', 'app model: the request with round 2, 1 carried (X), last round\'s note', w)
            d = next((x for x in m['reviewed'] if x['id'] == r3['id']), None)
            check(d and d['res']['k'] == 'mix' and [f['mark'] for f in d['files']].count('ok') == 1, 'app model: the decided one shows its mixed result and marks', d)
            await pg.evaluate("window.NativeMac = window.NativeMac || { call: () => Promise.resolve() }")
            await pg.evaluate("__e11Me({ ev: 'rvAmend', id: __ids.r4, rid: 'x1', note: '', need: { [__ids.Q]: 'Crop tighter' } })"); await pg.wait_for_timeout(500)
            r4 = await pg.evaluate(f"{T}.reviews[3]")
            check(r4['state'] == 'amend' and len(r4['ok']) == 1 and list(r4['need'].values()) == ['Crop tighter'], 'app: Request amendments with one file ticked', r4)
            check(not errs, 'no page errors', errs)
            await b.close()
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
