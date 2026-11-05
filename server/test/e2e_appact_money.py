"""Part B step 3: the app's Claims and Expenses actions done on the server (server/src/appact-money.js createMoneyActs) —
the same changes and answers as the hidden website page's (web/phone.js NativeMe __e11Me: clApprove, clPaid, clAdd,
clPerson, exAdd, exEnd) for the same starting data, generated ids and timestamps aside. For each action: the page's own
changes to its copy (claims, finance, notifications) and its answer; what the server then took (its snapshot); and the
server handlers' changes, worked out over a store made from the same starting snapshot."""
import asyncio, os, re, subprocess, tempfile, time, urllib.request, json
from playwright.async_api import async_playwright
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))); PORT=18343; BASE=f'http://127.0.0.1:{PORT}'; ADMIN='haris@e11-digital.com'
KINDS = ['claims', 'finance', 'notifications']
# the server side: the handlers over a store made from the starting snapshot; steps run in turn (each one's changes kept)
NODE = r"""
import(process.argv[1]).then(({ createMoneyActs }) => {
let inp = ''; process.stdin.on('data', (d) => { inp += d; }).on('end', () => {
  const { data, me, steps } = JSON.parse(inp);
  const db = {}; for (const k of Object.keys(data)) if (Array.isArray(data[k])) db[k] = data[k].map((x) => JSON.parse(JSON.stringify(x)));
  const store = { get: (k, id) => { const r = (db[k] || []).find((x) => String(x.id) === String(id)); return r ? JSON.parse(JSON.stringify(r)) : null; }, list: (k) => JSON.parse(JSON.stringify(db[k] || [])) };
  const acts = createMoneyActs({ store, now: () => Date.now() });
  const u = db.users.find((x) => x.id === me);
  const out = []; let prev = null;
  for (const s of steps) {
    const body = JSON.parse(JSON.stringify(s).replace(/"@prev"/g, JSON.stringify(prev && prev.answer ? prev.answer.id : null)));
    const r = acts[body.ev](u, body); out.push(r); prev = r;
    if (r.ok) for (const ch of r.changes) {
      db[ch.kind] = db[ch.kind] || [];
      const i = db[ch.kind].findIndex((x) => String(x.id) === String(ch.id));
      if (ch.del) { if (i >= 0) db[ch.kind].splice(i, 1); } else if (i >= 0) db[ch.kind][i] = ch.data; else db[ch.kind].push(ch.data);
    }
  }
  process.stdout.write(JSON.stringify(out));
});
});
"""
TS = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$')
UID = re.compile(r'^(clh-|p:)?([0-9a-z]{13,16})$')
def norm(x, known):
    if isinstance(x, dict): return {k: norm(v, known) for k, v in x.items()}
    if isinstance(x, list): return [norm(v, known) for v in x]
    if isinstance(x, str):
        if TS.match(x): return '<time>'
        m = UID.match(x)
        if m and m.group(2) not in known: return (m.group(1) or '') + '<new id>'
    return x
def changes_of(before, after):
    """{kind: [records]} before / after → the changed records, as the handlers give them"""
    out = []
    for k in KINDS:
        b = {str(r['id']): r for r in before.get(k, [])}; a = {str(r['id']): r for r in after.get(k, [])}
        for i, r in a.items():
            if i not in b: out.append({'kind': k, 'data': r})
            elif r != b[i]: out.append({'kind': k, 'base': b[i], 'data': r})
        for i in b:
            if i not in a: out.append({'kind': k, 'id': i, 'del': True})
    return out
def canon(chs, known):
    rows = []
    for c in chs:
        c = {k: v for k, v in c.items() if k != 'id' or c.get('del')}
        rows.append(json.dumps(norm(c, known), sort_keys=True, ensure_ascii=False))
    return sorted(rows)
def server_side(data, me, steps):
    p = subprocess.run(['node', '-e', NODE, 'file://' + ROOT + '/server/src/appact-money.js'], input=json.dumps({'data': data, 'me': me, 'steps': steps}), capture_output=True, text=True, timeout=30)
    if p.returncode: raise RuntimeError(p.stderr)
    return json.loads(p.stdout)

PAGE_COPY = "(() => { const o = {}; for (const k of %s) o[k] = JSON.parse(JSON.stringify(db[k] || [])); return o; })()" % json.dumps(KINDS)
RUN = """async (ev) => {
  window.__ans = window.__ans || [];
  if (!window.__stubbed) { NativeMac.call = (cmd, a) => { if (cmd === 'me' && a && a.rid) window.__ans.push(a); return Promise.resolve({}); }; window.__stubbed = true; }
  const rid = 'x' + Math.random().toString(36).slice(2);
  __e11Me({ ...ev, rid });
  for (let i = 0; i < 50 && !window.__ans.find((a) => a.rid === rid); i++) await new Promise((ok) => setTimeout(ok, 20));
  const a = window.__ans.find((x) => x.rid === rid) || null;
  if (a) delete a.rid;
  return a;
}"""

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
        H={'X-Dev-Email':ADMIN}
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/me',headers=H))
        urllib.request.urlopen(urllib.request.Request(BASE+'/api/sample/reset',method='POST',data=b'{}',headers={**H,'Content-Type':'application/json'})).read()
        async with async_playwright() as pw:
            b=await pw.chromium.launch()
            async def open_as(who):
                ctx=await b.new_context(viewport={'width':390,'height':844},device_scale_factor=2,is_mobile=True,has_touch=True,base_url=BASE,timezone_id='Asia/Dubai',locale='en-US')
                await ctx.add_cookies([{'name':'e11_dev_email','value':who,'url':BASE}])
                pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto('/')
                await pg.wait_for_function("typeof db !== 'undefined' && db && db.users && db.users.length > 0 && typeof __e11Me === 'function' && !!currentUserId", timeout=30000)
                await pg.wait_for_timeout(2500)
                return ctx, pg, errs
            async def snapshot(pg):
                return (await pg.evaluate("(async () => (await (await fetch('/api/snapshot', { cache: 'no-store' })).json()).data)()"))

            async def case(pg, me, name, steps, expect_ok=True, server_refuses=False):
                """steps: page events, in turn ("@prev": the previous answer's id)"""
                snap = await snapshot(pg)
                page0 = await pg.evaluate(PAGE_COPY)
                known = set(re.findall(r'[0-9a-z]{13,16}', json.dumps(snap) + json.dumps(page0)))
                for k in ('claims', 'finance'):
                    check(page0[k] == snap.get(k, []), f'{name}: the page and the server start the same ({k})')
                answers, prev = [], None
                for s in steps:
                    ev = json.loads(json.dumps(s).replace('"@prev"', json.dumps(prev.get('id') if prev else None)))
                    a = await pg.evaluate(RUN, ev); answers.append(a); prev = a
                page1 = await pg.evaluate(PAGE_COPY)          # the page's own changes, before the server answers
                page_ch = changes_of(page0, page1)
                await pg.wait_for_timeout(2500)
                snap1 = await snapshot(pg)                    # what the server took
                took = changes_of({k: snap.get(k, []) for k in ('claims', 'finance')}, {k: snap1.get(k, []) for k in ('claims', 'finance')})
                res = server_side(snap, me, steps)
                srv_ch = [c for r in res if r.get('ok') for c in r['changes']]
                # answers: ok / error the same; the extra fields the same (ids aside)
                for i, (a, r) in enumerate(zip(answers, res)):
                    if server_refuses:
                        check(a and a.get('ok') and not r['ok'] and r.get('status'), f'{name} [{steps[i]["ev"]}]: the page answers ok but the server refuses its change; the handler refuses first', f'\n   page: {a}\n   handler: {r}')
                        continue
                    pa = {k: v for k, v in (a or {}).items() if k not in ('ok', 'error')}
                    check(a is not None and bool(a.get('ok')) == bool(r['ok']) and (a.get('error') == r.get('error')), f'{name} [{steps[i]["ev"]}]: the same answer ({"ok" if r["ok"] else r.get("error")})', f'\n   page: {a}\n   handler: {r}')
                    if r['ok']: check(norm(pa, known) == norm(r.get('answer', {}), known), f'{name} [{steps[i]["ev"]}]: the same answer fields', f'\n   page: {pa}\n   handler: {r.get("answer")}')
                    else: check(isinstance(r.get('status'), int) and r['status'] >= 400, f'{name}: a refusal has a status', r)
                if server_refuses:
                    check(not took, f'{name}: the server took nothing from the page', took)
                    check(not srv_ch, f'{name}: the handler changes nothing', srv_ch)
                    return res
                pc, sc = canon(page_ch, known), canon(srv_ch, known)
                check(pc == sc, f'{name}: the same changes ({len(sc)})', '\n   page:\n     ' + '\n     '.join(pc) + '\n   handler:\n     ' + '\n     '.join(sc))
                if expect_ok:
                    tc = canon(took, known)
                    want = canon([c for c in page_ch if c['kind'] in ('claims', 'finance')], known)
                    check(tc == want, f'{name}: the server took the page\'s changes', '\n   took:\n     ' + '\n     '.join(tc) + '\n   page:\n     ' + '\n     '.join(want))
                    check(bool(sc) or not any(r['ok'] for r in res) or name.endswith('nothing to do'), f'{name}: something changed', sc)
                return res

            # ---------- the Office Admin with Finance Admin ----------
            ctx, pg, errs = await open_as('arsal@e11-digital.com')
            snap = await snapshot(pg)
            today = await pg.evaluate('todayStr()'); cm = await pg.evaluate('Claims.claimMonth()')
            this_m = today[:7]
            y, mo = map(int, this_m.split('-')); lm = f'{y if mo > 1 else y - 1}-{(mo - 2) % 12 + 1:02d}'
            old_m = f'{y - 1}-{mo:02d}'
            claims = snap['claims']
            sub = [c for c in claims if c['state'] == 'submitted' and c.get('userId') and c['userId'] != 'u-arsal']
            appr = [c for c in claims if c['state'] == 'approved']
            paid = [c for c in claims if c['state'] == 'paid']
            print('     claim month', cm, '· submitted', len(sub), '· approved', len(appr), '· paid', len(paid))
            check(len(sub) >= 2 and appr and paid, 'sample: submitted, approved and paid claims to work on', (len(sub), len(appr), len(paid)))
            member = next(x for x in snap['users'] if x.get('active') is not False and x['id'] not in ('u-arsal',) and x.get('role') not in ('finance_admin', 'finance_viewer'))
            pdf = {'path': 'Finance/Reimbursements/test-claim.pdf', 'name': 'Test claim.pdf', 'size': 12345}
            inv = {'path': 'Finance/Subscriptions/test-inv.pdf', 'name': 'Invoice Nov.pdf', 'size': 999}
            ME = 'u-arsal'
            await case(pg, ME, 'HR approve a submitted claim', [{'ev': 'clApprove', 'id': sub[0]['id']}])
            await case(pg, ME, 'HR approve a paid claim: nothing to do', [{'ev': 'clApprove', 'id': paid[0]['id']}])
            await case(pg, ME, 'Paid on: an HR approved claim', [{'ev': 'clPaid', 'id': appr[0]['id'], 'date': today}])
            await case(pg, ME, 'Paid on: a submitted claim', [{'ev': 'clPaid', 'id': sub[1]['id'], 'date': f'{lm}-15'}])
            await case(pg, ME, 'Paid on: a paid claim is refused', [{'ev': 'clPaid', 'id': paid[0]['id'], 'date': today}])
            await case(pg, ME, 'Paid on: no date is refused', [{'ev': 'clPaid', 'id': sub[0]['id'], 'date': ''}])
            await case(pg, ME, 'Claim by hand for a team member', [{'ev': 'clAdd', 'who': 'u:' + member['id'], 'month': this_m, 'amount': '1234.567', 'pdf': pdf}])
            await case(pg, ME, 'Claim by hand for a new person (clPerson, then clAdd)', [{'ev': 'clPerson', 'name': '  Sami (courier)  '}, {'ev': 'clAdd', 'who': '@prev', 'month': lm, 'amount': 80, 'pdf': {'path': pdf['path']}}])
            await case(pg, ME, 'Claim by hand: no month given (this month)', [{'ev': 'clAdd', 'who': 'u:' + member['id'], 'amount': '50', 'pdf': pdf}])
            await case(pg, ME, 'Claim by hand: no one chosen', [{'ev': 'clAdd', 'who': '', 'amount': '50', 'pdf': pdf}])
            await case(pg, ME, 'Claim by hand: no amount', [{'ev': 'clAdd', 'who': 'u:' + member['id'], 'amount': 'abc', 'pdf': pdf}])
            await case(pg, ME, 'Claim by hand: no PDF', [{'ev': 'clAdd', 'who': 'u:' + member['id'], 'amount': '50'}])
            await case(pg, ME, 'Claim by hand: a month not allowed (a year ago)', [{'ev': 'clAdd', 'who': 'u:' + member['id'], 'month': old_m, 'amount': '50', 'pdf': pdf}], server_refuses=True)
            await case(pg, ME, 'A person with no name', [{'ev': 'clPerson', 'name': '   '}])
            await case(pg, ME, 'Subscription with an invoice', [{'ev': 'exAdd', 'kind': 'sub', 'name': ' Figma ', 'amount': '55.5', 'day': 15, 'invoice': inv}])
            await case(pg, ME, 'Subscription without an invoice (day 0 → 1)', [{'ev': 'exAdd', 'kind': 'sub', 'name': 'Notion', 'amount': 40, 'day': 0}])
            await case(pg, ME, 'Office expense with an invoice and a date', [{'ev': 'exAdd', 'kind': 'expense', 'name': 'Printer ink', 'amount': '87.499', 'date': f'{this_m}-02', 'invoice': {'path': 'Finance/Expenses/ink.pdf'}}])
            await case(pg, ME, 'Office expense without an invoice or date (today)', [{'ev': 'exAdd', 'name': 'Water', 'amount': '12'}])
            await case(pg, ME, 'Expense with no name', [{'ev': 'exAdd', 'name': ' ', 'amount': '12'}])
            await case(pg, ME, 'Expense with no amount', [{'ev': 'exAdd', 'name': 'Water', 'amount': '0'}])
            snap = await snapshot(pg)
            live = [x for x in snap['finance'] if x['type'] == 'sub' and not x.get('endedAt')]
            check(live, 'a live subscription to end')
            await case(pg, ME, 'End a subscription', [{'ev': 'exEnd', 'id': live[0]['id']}])
            await case(pg, ME, 'End a subscription that isn\'t there', [{'ev': 'exEnd', 'id': 'nope'}])
            await case(pg, ME, 'End an office expense (not a subscription)', [{'ev': 'exEnd', 'id': next(x['id'] for x in snap['finance'] if x['type'] == 'expense')}])
            check(not errs, 'arsal: no page errors', errs)
            await ctx.close()

            # ---------- not a Finance Admin ----------
            for who, uid in (('carine@e11-digital.com', None), ('ali@e11-digital.com', None)):
                ctx, pg, errs = await open_as(who)
                me = await pg.evaluate('currentUserId')
                s2 = await snapshot(pg)
                anyc = (s2.get('claims') or [{'id': 'cl-x'}])[0]['id']
                for st in ([{'ev': 'clApprove', 'id': anyc}], [{'ev': 'clPaid', 'id': anyc, 'date': today}], [{'ev': 'clAdd', 'who': 'u:' + me, 'amount': '5', 'pdf': pdf}],
                           [{'ev': 'clPerson', 'name': 'X'}], [{'ev': 'exAdd', 'name': 'X', 'amount': '5'}], [{'ev': 'exEnd', 'id': 'x'}]):
                    await case(pg, me, f'{who.split("@")[0]} (not a Finance Admin): {st[0]["ev"]} refused', st, expect_ok=False)
                check(not errs, f'{who}: no page errors', errs)
                await ctx.close()
            await b.close()
    finally:
        srv.terminate()
    print('ALL OK' if all(ok) else 'SOME FAILED'); raise SystemExit(0 if all(ok) else 1)
asyncio.run(main())
