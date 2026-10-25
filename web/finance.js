/* ================= Finance =================
   Finance Admin / Finance Viewer have their own app: Dashboard, Projects and Expenses.
   Anyone else with Finance access (u.fin) and every Admin can look at the same pages (Finance in their
  sidebar); Finance Admins also get the add pages. A task's Finance status is only changed by Account
  Managers and Admins. Desktop only: on a phone-size screen
  Finance people see a note to use a computer. Only a Finance Admin changes things:
   a task's Finance status, monthly subscriptions, staff reimbursements and extra expenses.
   Records live in db.finance (server kind "finance"), one item each:
     { type: 'sub', name, amount, day, startMonth: 'YYYY-MM', endedAt, invoices: { 'YYYY-MM': file } }
     { type: 'reimb', userId | personId, amount, date, invoice }
     { type: 'expense', name, amount, date, invoice }
     { type: 'person', name }   — people outside the team who can be reimbursed
   Amounts are AED. Subscriptions are recorded automatically on their billing day each month. */
const Fin = (() => {
  const VIEWS = ['fin-dash', 'fin-projects', 'fin-expenses', 'fin-list', 'fin-subs', 'fin-reimb', 'fin-extra'];
  const ADMIN_ONLY = ['fin-subs', 'fin-extra'];   // Staff reimbursements: Viewers see the claims too (read only)
  const STATUSES = Object.keys(FINANCE);
  const st = { proj: 'all', graph: 'Invoiced', list: { type: 'all', month: '', page: 0 }, open: {} };
  const canLook = () => !!finLevel() || isAdmin();
  const owns = (v) => VIEWS.includes(v);
  const recs = (type) => (db.finance || []).filter((x) => x.type === type);
  const aed = (n) => 'AED ' + (Number(n) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const aedShort = (n) => { n = Number(n) || 0; return 'AED ' + (n >= 1e6 ? (n / 1e6).toFixed(1) + 'M' : n >= 1e4 ? Math.round(n / 1e3) + 'k' : n.toLocaleString('en-US', { maximumFractionDigits: 0 })); };
  const monthKey = (d) => ymd(d).slice(0, 7);
  const thisMonth = () => todayStr().slice(0, 7);
  const addMonths = (m, n) => { const [y, mo] = m.split('-').map(Number); const d = new Date(y, mo - 1 + n, 1); return monthKey(d); };
  const monthName = (m, long) => { const [y, mo] = m.split('-').map(Number); return new Date(y, mo - 1, 1).toLocaleDateString('en-US', long ? { month: 'long', year: 'numeric' } : { month: 'short' }); };
  const lastMonths = (n) => Array.from({ length: n }, (_, i) => addMonths(thisMonth(), i - n + 1));
  const daysIn = (m) => { const [y, mo] = m.split('-').map(Number); return new Date(y, mo, 0).getDate(); };
  const personName = (r) => (r.userId ? fullName(userById(r.userId)) : (recs('person').find((p) => p.id === r.personId) || {}).name || r.personName || 'Someone');

  /* ---------- Transactions (money going out) ---------- */
  function subPayments(s) {
    const out = [];
    const start = s.startMonth || String(s.createdAt || nowISO()).slice(0, 7);
    const endDate = s.endedAt ? ymd(new Date(s.endedAt)) : null;
    for (let m = start; m <= thisMonth(); m = addMonths(m, 1)) {
      const date = `${m}-${pad2(Math.min(Number(s.day) || 1, daysIn(m)))}`;
      if (date > todayStr()) break;
      if (endDate && date > endDate) break;
      out.push({ id: s.id + ':' + m, kind: 'sub', name: s.name, amount: Number(s.amount) || 0, date, invoice: (s.invoices || {})[m] || null, month: m, ref: s });
    }
    return out;
  }
  function transactions() {
    const out = [];
    recs('sub').forEach((s) => out.push(...subPayments(s)));
    recs('reimb').forEach((r) => out.push({ id: r.id, kind: 'reimb', name: personName(r), amount: Number(r.amount) || 0, date: r.date, invoice: r.invoice || null, ref: r }));
    recs('expense').forEach((r) => out.push({ id: r.id, kind: 'expense', name: r.name, amount: Number(r.amount) || 0, date: r.date, invoice: r.invoice || null, ref: r }));
    return out.sort((a, b) => b.date.localeCompare(a.date) || String(b.ref.createdAt || '').localeCompare(String(a.ref.createdAt || '')));
  }
  const KIND_L = { expense: 'Big expense', sub: 'Payment', reimb: 'Reimbursement' };
  const KIND_C = { expense: '#ff8a4c', sub: '#4c9aff', reimb: '#a875ff' };

  /* ---------- Download report (Expenses page: Admins, Finance Admins, Finance Viewers) ----------
     A PDF of the chosen months (1–12): subscriptions, staff reimbursements and extra expenses, no tasks.
     The pages are drawn here on A4 canvases and joined on the server. With "Include invoices and
     receipts" the download is a .zip: the PDF plus Attachments/<YYYY-MM>/<SUB|REI|EXT>-nn_<name>.<ext>,
     the names the report lists. A reimbursement from an expense claim gets its claim PDF (sheet + receipts). */
  const rep = { open: false, year: 0, sel: [], files: true, busy: false };
  const MS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const loadImg = (src) => new Promise((ok) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => ok(null); i.src = src; });
  const slug = (s) => String(s || '').normalize('NFKD').replace(/[^\w\s-]/g, '').trim().replace(/[\s_]+/g, '-').replace(/-+/g, '-').slice(0, 32).replace(/-$/, '') || 'file';
  const extOf = (p) => { const e = String(p || '').split('/').pop().split('.'); return e.length > 1 ? e.pop().toLowerCase() : 'pdf'; };
  const money = (n) => (Number(n) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  function repToggle() {
    rep.open = !rep.open;
    if (rep.open) { const m = st.exMonth === 'prev' ? addMonths(thisMonth(), -1) : thisMonth(); rep.sel = [m]; rep.year = Number(m.slice(0, 4)); }
    renderContent();
  }
  function repPop() {
    if (!rep.open) return '';
    const now = thisMonth(), sel = rep.sel.slice().sort();
    const grid = MS.map((l, i) => {
      const k = `${rep.year}-${pad2(i + 1)}`, on = sel.includes(k), off = k > now || (!on && sel.length >= 12);
      return `<button class="fr-m ${on ? 'on' : ''}" data-fin-repm="${k}" aria-pressed="${on}" ${off ? 'disabled' : ''} title="${esc(monthName(k, true))}">${l}</button>`;
    }).join('');
    const label = sel.length === 1 ? monthName(sel[0], true) : `${sel.length} months · ${monthName(sel[0], true)} – ${monthName(sel[sel.length - 1], true)}`;
    return `<div class="fr-pop" role="dialog" aria-label="Download expenses report">
      <div class="fr-h"><b>Expenses report (PDF)</b><span>Subscriptions, staff reimbursements and extra expenses. No tasks or clients.</span></div>
      <div class="fr-mh"><span>Months <small>· up to 12</small></span><span class="fr-y"><button class="icon-btn sm" data-fin-repy="-1" aria-label="Previous year">${icon('chev-left')}</button><b>${rep.year}</b><button class="icon-btn sm" data-fin-repy="1" aria-label="Next year" ${rep.year >= Number(now.slice(0, 4)) ? 'disabled' : ''}>${icon('chev-right')}</button></span></div>
      <div class="fr-grid">${grid}</div>
      <div class="fr-sel">${esc(label)}</div>
      <label class="fr-ck"><input type="checkbox" data-fin-repf ${rep.files ? 'checked' : ''}><span>Include invoices and receipts<small>Downloads a .zip: the report PDF + an Attachments folder, one folder per month. Unticked: just the PDF.</small></span></label>
      <button class="btn primary fr-go" data-fin-repgo ${rep.busy || !sel.length ? 'disabled' : ''}>${rep.busy ? 'Preparing…' : rep.files ? `${icon('download')}Download .zip` : `${icon('download')}Download PDF`}</button>
    </div>`;
  }
  function repPick(k) {
    const on = rep.sel.includes(k);
    if (on) { if (rep.sel.length > 1) rep.sel = rep.sel.filter((x) => x !== k); }
    else if (rep.sel.length < 12 && k <= thisMonth()) rep.sel = rep.sel.concat(k);
    renderContent();
  }
  // Each month's three lists, oldest first, with the file name the report refers to
  function repModel(months) {
    const all = transactions();
    return months.map((m) => {
      const of = (k) => all.filter((x) => x.date.slice(0, 7) === m && x.kind === k).sort((a, b) => a.date.localeCompare(b.date));
      const tag = (list, P) => list.map((x, i) => {
        const nn = `${P}-${pad2(i + 1)}`;
        let file = null, note = '';
        if (x.invoice && x.invoice.path) file = { path: x.invoice.path, as: `${m}/${nn}_${slug(x.name)}.${extOf(x.invoice.path)}` };
        else if (x.kind === 'reimb' && x.ref.claimId) {
          const c = typeof Claims !== 'undefined' && Claims.byId(x.ref.claimId);
          if (c) file = { claim: c, as: `${m}/${nn}_${slug(x.name)}.pdf` }; else note = 'Expense claim';
        }
        return { ...x, file, note, fname: file ? file.as.split('/')[1] : '' };
      });
      const subs = tag(of('sub'), 'SUB'), reimbs = tag(of('reimb'), 'REI'), extras = tag(of('expense'), 'EXT');
      const sum = (l) => l.reduce((a, x) => a + x.amount, 0);
      const missing = [...subs, ...reimbs, ...extras].filter((x) => !x.file && !x.note);
      return { m, subs, reimbs, extras, s: sum(subs), r: sum(reimbs), e: sum(extras), t: sum(subs) + sum(reimbs) + sum(extras), missing };
    });
  }
  async function repPages(model, withFiles) {
    const W = 1240, H = 1754, S = W / 794, P = 52 * S, CW = W - 2 * P, bottom = H - 62 * S;
    const F = '-apple-system, "SF Pro Text", "Segoe UI", Inter, Helvetica, Arial, sans-serif', MONO = '"SF Mono", Menlo, Consolas, "DejaVu Sans Mono", monospace';
    const logo = await loadImg('logo-tile.png');
    const multi = model.length > 1;
    const first = model[0].m, last = model[model.length - 1].m;
    const period = multi ? `${monthName(first, true)} – ${monthName(last, true)}` : monthName(first, true);
    const pages = [];
    let ctx = null, y = 0;
    const font = (w, px, mono) => { ctx.font = `${w} ${Math.round(px * S)}px ${mono ? MONO : F}`; };
    const text = (s, x, yy, al = 'left') => { ctx.textAlign = al; ctx.fillText(String(s), x, yy); };
    const fit = (s, max) => { s = String(s == null ? '' : s); let t = s; while (t.length > 1 && ctx.measureText(t).width > max) t = t.slice(0, -2); return t === s ? s : t + '…'; };
    const rrect = (x, yy, w, h, r) => { ctx.beginPath(); ctx.moveTo(x + r, yy); ctx.arcTo(x + w, yy, x + w, yy + h, r); ctx.arcTo(x + w, yy + h, x, yy + h, r); ctx.arcTo(x, yy + h, x, yy, r); ctx.arcTo(x, yy, x + w, yy, r); ctx.closePath(); };
    function newPage() {
      const c = document.createElement('canvas'); c.width = W; c.height = H;
      ctx = c.getContext('2d'); ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, W, H); ctx.textBaseline = 'alphabetic';
      pages.push(c);
      if (pages.length === 1) {
        if (logo) { ctx.save(); rrect(P, P - 6 * S, 48 * S, 48 * S, 11 * S); ctx.clip(); ctx.drawImage(logo, P, P - 6 * S, 48 * S, 48 * S); ctx.restore(); }
        font(700, 10.5); ctx.fillStyle = '#6e717a'; text('E11 AGENCY · FINANCE', P + 60 * S, P + 10 * S);
        font(700, 22); ctx.fillStyle = '#17181b'; text(multi ? 'Expenses report' : 'Monthly expenses report', P + 60 * S, P + 36 * S);
        font(700, 17); text(period, W - P, P + 14 * S, 'right');
        const d = new Date();
        font(400, 10.5); ctx.fillStyle = '#6e717a';
        text(`${multi ? model.length + ' months · ' : ''}Generated ${d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}, ${d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })} · by ${fullName(me())}`, W - P, P + 34 * S, 'right');
        ctx.fillStyle = '#17181b'; ctx.fillRect(P, P + 58 * S, CW, 2 * S);
        y = P + 78 * S;
      } else {
        font(600, 10); ctx.fillStyle = '#6e717a'; text(`E11 · Expenses report · ${period}`, P, P);
        ctx.fillStyle = '#e3e3e8'; ctx.fillRect(P, P + 10 * S, CW, 1);
        y = P + 30 * S;
      }
    }
    function cards(list) {   // [[label, value, note, dark]]
      const fr = list.map((c) => (c[3] ? 1.3 : 1)), tot = fr.reduce((a, b) => a + b, 0), gap = 10 * S, h = 66 * S;
      let x = P;
      list.forEach(([l, v, note, dark], i) => {
        const w = (CW - gap * (list.length - 1)) * (fr[i] / tot);
        rrect(x, y, w, h, 10 * S);
        if (dark) { ctx.fillStyle = '#17181b'; ctx.fill(); } else { ctx.strokeStyle = '#e3e3e8'; ctx.lineWidth = 1.5; ctx.stroke(); }
        font(700, 9.5); ctx.fillStyle = dark ? '#b5b6be' : '#6e717a'; text(fit(l.toUpperCase(), w - 24 * S), x + 13 * S, y + 19 * S);
        font(600, dark ? 17 : 14, true); ctx.fillStyle = dark ? '#ffffff' : '#17181b'; text(fit(v, w - 24 * S), x + 13 * S, y + 41 * S);
        font(400, 10); ctx.fillStyle = dark ? '#c9c9d1' : '#6e717a'; text(fit(note, w - 24 * S), x + 13 * S, y + 57 * S);
        x += w + gap;
      });
      y += h + 12 * S;
    }
    function split(s, r, e) {
      const t = s + r + e; if (!t) return;
      let x = P; const h = 8 * S;
      ctx.save(); rrect(P, y, CW, h, 4 * S); ctx.clip();
      [[s, KIND_C.sub], [r, KIND_C.reimb], [e, KIND_C.expense]].forEach(([v, c]) => { const w = (v / t) * CW; ctx.fillStyle = c; ctx.fillRect(x, y, w, h); x += w; });
      ctx.restore(); y += h + 18 * S;
    }
    function table(title, cols, rows, foot) {   // cols: [{ l, w (share of the width), r: right-aligned, mono }]
      const RH = 23 * S, HH = 23 * S;
      if (y + 20 * S + HH + RH * Math.min(Math.max(rows.length, 1), 3) > bottom) newPage();
      font(700, 10.5); ctx.fillStyle = '#6e717a'; text(title, P, y + 9 * S); y += 17 * S;
      const xs = []; let x = P; cols.forEach((c) => { xs.push(x); x += c.w * CW; });
      const cellX = (i) => (cols[i].r ? xs[i] + cols[i].w * CW - 10 * S : xs[i] + 10 * S);
      const head = () => { ctx.fillStyle = '#17181b'; ctx.fillRect(P, y, CW, HH); font(600, 9); ctx.fillStyle = '#ffffff'; cols.forEach((c, i) => text(c.l.toUpperCase(), cellX(i), y + 15 * S, c.r ? 'right' : 'left')); y += HH; };
      const row = (cells, isFoot) => {
        if (y + RH > bottom) { newPage(); head(); }
        if (isFoot) { ctx.fillStyle = '#f4f4f7'; ctx.fillRect(P, y, CW, RH); ctx.fillStyle = '#d9d9df'; ctx.fillRect(P, y, CW, 1.5); } else { ctx.fillStyle = '#ececf0'; ctx.fillRect(P, y, CW, 1); }
        cols.forEach((c, i) => {
          const v = cells[i], o = v && typeof v === 'object' ? v : { t: v == null ? '' : v };
          const mono = c.mono || o.mono;
          font(isFoot || o.b ? 700 : mono ? 500 : 400, o.sm ? 9.5 : mono && !c.r ? 10 : 11, mono);
          ctx.fillStyle = o.c || '#17181b';
          text(fit(o.t, c.w * CW - 20 * S), cellX(i), y + 15.5 * S, c.r ? 'right' : 'left');
        });
        y += RH;
      };
      head();
      if (!rows.length) row([{ t: 'None', c: '#8a8d96' }]);
      rows.forEach((r) => row(r));
      if (foot) row(foot, true);
      y += 16 * S;
    }
    const fileCell = (x) => (x.file ? (withFiles ? { t: x.fname, mono: true, c: '#4e5159' } : { t: 'Attached', c: '#4e5159' }) : x.note ? { t: x.note, c: '#6e717a' } : { t: 'Missing', c: '#c2410c', b: true });
    const day = (d) => new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
    const pct = (v, t) => (t ? Math.round((v / t) * 100) : 0);
    const plural = (n, one, many) => `${n} ${n === 1 ? one : many || one + 's'}`;
    function monthTables(mo, label) {
      const c3 = [{ l: 'Name', w: 0.33 }, { l: 'Paid on', w: 0.11 }, { l: withFiles ? 'Invoice file' : 'Invoice', w: 0.40 }, { l: 'AED', w: 0.16, r: true, mono: true }];
      table(`${label}SUBSCRIPTIONS`, c3.map((c, i) => (i === 1 ? { ...c, l: 'Billed on' } : c)), mo.subs.map((x) => [x.name, day(x.date), fileCell(x), money(x.amount)]), ['Subscriptions total', '', '', money(mo.s)]);
      table(`${label}STAFF REIMBURSEMENTS`, c3.map((c, i) => (i === 0 ? { ...c, l: 'Person' } : i === 2 ? { ...c, l: withFiles ? 'Receipt file' : 'Receipts' } : c)), mo.reimbs.map((x) => [x.name, day(x.date), fileCell(x), money(x.amount)]), ['Reimbursements total', '', '', money(mo.r)]);
      table(`${label}EXTRA EXPENSES`, c3, mo.extras.map((x) => [x.name, day(x.date), fileCell(x), money(x.amount)]), ['Extra expenses total', '', '', money(mo.e)]);
    }
    newPage();
    const S3 = model.reduce((a, x) => a + x.s, 0), R3 = model.reduce((a, x) => a + x.r, 0), E3 = model.reduce((a, x) => a + x.e, 0), T = S3 + R3 + E3;
    const nS = model.reduce((a, x) => a + x.subs.length, 0), nE = model.reduce((a, x) => a + x.extras.length, 0);
    const people = new Set(model.flatMap((x) => x.reimbs.map((r) => r.name))).size, nR = model.reduce((a, x) => a + x.reimbs.length, 0);
    let note;
    if (multi) note = `Avg AED ${money(T / model.length)} a month`;
    else {
      const pm = addMonths(first, -1), prev = transactions().filter((x) => x.date.slice(0, 7) === pm).reduce((a, x) => a + x.amount, 0);
      const p = pctChange(T, prev);
      note = `${p > 0 ? '↑' : p < 0 ? '↓' : '—'} ${Math.abs(p)}% vs ${monthName(pm, true).split(' ')[0]}`;
    }
    cards([['Total paid out', 'AED ' + money(T), note, true], ['Subscriptions', money(S3), `${plural(nS, 'payment')} · ${pct(S3, T)}%`], ['Reimbursements', money(R3), `${multi ? plural(nR, 'payment') : plural(people, 'person', 'people')} · ${pct(R3, T)}%`], ['Extra expenses', money(E3), `${plural(nE, 'purchase')} · ${pct(E3, T)}%`]]);
    split(S3, R3, E3);
    if (!multi) monthTables(model[0], '');
    else {
      const missing = model.flatMap((mo) => mo.missing.map((x) => ({ ...x, mo: mo.m })));
      table('MONTH BY MONTH', [{ l: 'Month', w: 0.2 }, { l: 'Subscriptions', w: 0.16, r: true, mono: true }, { l: 'Reimbursements', w: 0.17, r: true, mono: true }, { l: 'Extra', w: 0.15, r: true, mono: true }, { l: 'Total AED', w: 0.16, r: true, mono: true }, { l: 'Missing files', w: 0.16 }],
        model.map((mo) => [monthName(mo.m, true), money(mo.s), money(mo.r), money(mo.e), { t: money(mo.t), b: true }, mo.missing.length ? { t: `${mo.missing.length} missing`, c: '#c2410c' } : { t: 'All attached', c: '#15803d' }]),
        [plural(model.length, 'month'), money(S3), money(R3), money(E3), money(T), String(missing.length)]);
      if (missing.length) table('MISSING INVOICES AND RECEIPTS', [{ l: 'Month', w: 0.18 }, { l: 'Name', w: 0.44 }, { l: 'Type', w: 0.22 }, { l: 'AED', w: 0.16, r: true, mono: true }],
        missing.map((x) => [monthName(x.mo, true), x.name, { sub: 'Subscription', reimb: 'Reimbursement', expense: 'Extra expense' }[x.kind], money(x.amount)]));
      model.forEach((mo) => {
        if (y + 160 * S > bottom) newPage();
        ctx.fillStyle = '#efecff'; ctx.fillRect(P, y, CW, 34 * S); ctx.fillStyle = '#5b4bd6'; ctx.fillRect(P, y, 3 * S, 34 * S);
        font(700, 14); ctx.fillStyle = '#17181b'; text(monthName(mo.m, true), P + 14 * S, y + 22 * S);
        font(600, 12, true); ctx.fillStyle = '#3b2fa0'; text('AED ' + money(mo.t), W - P - 12 * S, y + 22 * S, 'right');
        y += 50 * S;
        monthTables(mo, '');
      });
    }
    // footers, now that the page count is known
    pages.forEach((c, i) => {
      ctx = c.getContext('2d');
      ctx.fillStyle = '#ececf0'; ctx.fillRect(P, H - 46 * S, CW, 1);
      font(400, 9.5); ctx.fillStyle = '#8a8d96';
      text(withFiles ? 'Files named in this report are in the .zip, under Attachments/<YYYY-MM>/. They are not included in this PDF.' : 'Generated by E11 Console', P, H - 30 * S);
      text(`E11 Console · Page ${i + 1} of ${pages.length}`, W - P, H - 30 * S, 'right');
    });
    return pages.map((c) => c.toDataURL('image/jpeg', 0.86).split(',')[1]);
  }
  async function repDownload() {
    const months = rep.sel.slice().sort();
    if (rep.busy || !months.length) return;
    rep.busy = true; renderContent();
    toast('Preparing the report…');
    try {
      const model = repModel(months);
      const files = [];
      if (rep.files) {
        for (const mo of model) for (const x of [...mo.subs, ...mo.reimbs, ...mo.extras]) {
          if (!x.file) continue;
          if (!x.file.claim) { files.push({ path: x.file.path, as: x.file.as }); continue; }
          try {   // the claim PDF (sheet + receipts), made the same way as on the claim itself
            const c = x.file.claim;
            const { pages, receipts } = await Claims.sheetPages(c);
            const r = await Host.call('claimPdf', { userId: c.userId, month: c.month, name: `Expense claim — ${fullName(userById(c.userId))} — ${monthName(c.month, true)}.pdf`.replace(/[\\/:*?"<>|]/g, '-'), pages, receipts });
            files.push({ path: r.path, as: x.file.as });
          } catch (e) { /* that claim is left out of the zip */ }
        }
      }
      const pages = await repPages(model, rep.files);
      const per = months.length === 1 ? monthName(months[0], true) : `${monthName(months[0], true)} to ${monthName(months[months.length - 1], true)}`;
      const r = await Host.call('expenseReport', { name: `E11 expenses — ${per}`, pages, zip: rep.files, files });
      rep.open = false;
      toast(Host.isMacApp ? `${r.name} saved to Downloads` : `Downloading ${r.name}`);
    } catch (e) { toast('Could not make the report: ' + e.message); }
    rep.busy = false; renderContent();
  }

  /* ---------- Tasks ---------- */
  const finTasks = () => db.tasks.filter((t) => !t.parentId);
  const finAt = (t) => t.financeAt || t.updatedAt || t.createdAt;

  /* ---------- Sidebar ---------- */
  function init() {
    const fin = isFinUser();
    document.body.classList.toggle('fin-mode', fin);
    $$('.fin-nav, .fin-admin-nav').forEach((el) => el.remove());
    const old = document.getElementById('fin-phone'); if (old) old.remove();
    if (fin) {
      const np = document.createElement('div');
      np.id = 'fin-phone';
      np.innerHTML = `<div class="fp-card"><div class="fp-ic">${icon('coin')}</div><h2>Finance is on the computer</h2><p>Open ${esc(location.host)} on a computer, or the E11 Console Mac app, to see the Finance dashboard, clients and expenses.</p><button class="btn" data-fin-signout>Sign out</button></div>`;
      np.addEventListener('click', (e) => { if (e.target.closest('[data-fin-signout]')) signOut(); });
      document.body.appendChild(np);
    }
    if (fin) {
      const nav = document.createElement('nav');
      nav.className = 'nav fin-nav';
      nav.innerHTML = [['fin-dash', 'home', 'Dashboard'], ['fin-projects', 'folder', 'Clients'], ['fin-expenses', 'coin', 'Expenses'], ['fin-reimb', 'users', 'Reimbursements']]
        .map(([v, ic, l]) => `<a class="nav-item" data-nav="${v}">${icon(ic)}${l}</a>`).join('');
      const head = $('#sidebar .sb-head');
      head.parentNode.insertBefore(nav, head);
    } else if (canLook()) {
      const a = document.createElement('a');
      a.className = 'nav-item ca-nav fin-admin-nav';
      a.dataset.nav = 'fin-dash';
      a.title = 'Finance — task Finance status and expense records';
      a.innerHTML = `<span class="ca-nav-ic">${icon('coin')}</span><span class="ca-nav-txt">Finance<small>Dashboard · Clients · Expenses</small></span>`;
      const tr = $('#nav-trash');
      tr.parentNode.insertBefore(a, tr);
    }
  }
  function paintNav() {
    $$('.fin-nav .nav-item').forEach((a) => a.classList.toggle('active', ui.view === a.dataset.nav || (a.dataset.nav === 'fin-expenses' && ui.view === 'fin-list')));
    // new expense claims: a count on Reimbursements; opening the page clears it
    const fresh = myNotifs().filter((n) => n.kind === 'claim' && !n.read);
    if (ui.view === 'fin-reimb' && fresh.length) { fresh.forEach((n) => { n.read = true; }); persist(); }
    const rn = $('.fin-nav .nav-item[data-nav="fin-reimb"]');
    if (rn) { let c = rn.querySelector('.count'); if (!c) { c = document.createElement('span'); c.className = 'count'; rn.appendChild(c); } const k = ui.view === 'fin-reimb' ? 0 : fresh.length; c.textContent = k ? String(k) : ''; c.classList.toggle('hot', !!k); }
    const an = $('.fin-admin-nav'); if (an) an.classList.toggle('active', owns(ui.view));
  }
  // The Finance Admin's pages, in the name menu (Finance-only people, and anyone given Finance Admin access)
  const addItems = () => (isFinAdmin() ? ['-',
    { label: 'Add subscriptions', icon: 'cal', run: () => go('fin-subs') },
    { label: 'Add Staff Reimbursements', icon: 'users', run: () => go('fin-reimb') },
    { label: 'Add Extra Expense', icon: 'coin', run: () => go('fin-extra') }] : finLevel() && !isFinUser() ? ['-', { label: 'Staff reimbursements', icon: 'users', run: () => go('fin-reimb') }] : []);
  function meMenu(anchor, extra = []) {
    showMenu(anchor, [
      ...extra,
      { label: 'My profile', icon: 'user', run: () => go('profile') },
      ...addItems(),
      ...(Host.isServer ? ['-', { label: 'What’s new', icon: 'info', run: () => whatsNewDialog(false) }] : []),
      ...(Host.isMacApp ? [{ label: 'Update Mac app', icon: 'download', run: () => MacUpdate.run() }] : []),
      '-',
      { label: 'Sign out', icon: 'logout', run: signOut },
    ]);
  }

  /* ---------- Titles ---------- */
  function title() {
    const t = { 'fin-dash': 'Dashboard', 'fin-projects': 'Clients', 'fin-expenses': 'Expenses', 'fin-list': 'All transactions', 'fin-subs': 'Subscriptions', 'fin-reimb': 'Staff reimbursements', 'fin-extra': 'Extra expenses' }[ui.view] || 'Finance';
    const tabs = !isFinUser() && ['fin-dash', 'fin-projects', 'fin-expenses'].includes(ui.view)
      ? `<div class="tabs">${[['fin-dash', 'Dashboard'], ['fin-projects', 'Clients'], ['fin-expenses', 'Expenses']].map(([v, l]) => `<button class="tab ${ui.view === v ? 'active' : ''}" data-fin-go="${v}">${l}</button>`).join('')}</div>` : '';
    return `<div class="page-icon" style="background:#173a2c;color:#3ddc97">${icon('coin')}</div><div class="page-title">${isFinUser() ? t : 'Finance'}</div>${tabs}`;
  }

  /* ---------- Pages ---------- */
  function render(c) {
    if (!canLook() || (ADMIN_ONLY.includes(ui.view) && !isFinAdmin())) { ui.view = isFinUser() ? 'fin-dash' : 'home'; renderAll(); return; }
    const v = ui.view;
    c.innerHTML = `<div class="fin">${v === 'fin-dash' ? dash() : v === 'fin-projects' ? projects() : v === 'fin-expenses' ? expenses() : v === 'fin-list' ? list() : v === 'fin-subs' ? subsPage() : v === 'fin-reimb' ? reimbPage() : extraPage()}</div>`;
    if (v === 'fin-reimb') Claims.afterFinanceRender();
  }
  const renderAll = () => { renderTitle(); renderSidebar(); renderContent(); };

  /* ---------- Small chart helpers ---------- */
  // Smooth line through points (0–100 box, stretched by the SVG)
  const smooth = (pts) => pts.reduce((d, [x, y], i) => { if (!i) return `M${x},${y}`; const [px, py] = pts[i - 1]; const mx = (px + x) / 2; return `${d} C${mx},${py} ${mx},${y} ${x},${y}`; }, '');
  const pctChange = (now, prev) => (prev ? Math.round(((now - prev) / prev) * 100) : now ? 100 : 0);
  const trend = (now, prev, goodUp = true) => {
    const p = pctChange(now, prev);
    if (!p) return `<span class="ft-trend flat">— 0%</span>`;
    const up = p > 0;
    return `<span class="ft-trend ${up === goodUp ? 'good' : 'bad'}">${up ? '↑' : '↓'} ${Math.abs(p)}%</span>`;
  };
  const ago = (iso) => { const d = (Date.now() - new Date(iso)) / 36e5; return d < 1 ? 'just now' : d < 24 ? `${Math.floor(d)}h ago` : d < 48 ? 'Yesterday' : fmtDay(ymd(new Date(iso))); };
  const statusIcon = `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M3 2.5h7l3 3v8H3z"/><path d="M5.5 8h5M5.5 10.5h3"/></svg>`;

  function dash() {
    const h = new Date().getHours();
    const greet = h < 5 ? 'Good evening' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    const ts = finTasks();
    const count = (s) => ts.filter((t) => t.finance === s).length;
    const inMonth = (s, m) => ts.filter((t) => t.finance === s && String(finAt(t)).slice(0, 7) === m).length;
    const cur = thisMonth(), prev = addMonths(cur, -1);
    const months = lastMonths(st.span === 12 ? 12 : 6);
    const g = st.graph;
    const vals = months.map((m) => inMonth(g, m));
    const max = Math.max(1, ...vals) * 1.25;
    const X = (i) => 4 + (i * 92) / (months.length - 1), Y = (v) => 92 - (v / max) * 82;
    const pts = vals.map((v, i) => [X(i), Y(v)]);
    const line = smooth(pts), area = `${line} L${X(months.length - 1)},100 L${X(0)},100 Z`;
    const total = ts.filter((t) => t.finance).length || 1;
    const waiting = count('LPO Pending') + count('To be invoiced');
    // invoiced by client (project's client, else the project) in the chosen period
    const since = months[0];
    const byClient = {};
    ts.filter((t) => t.finance === 'Invoiced' && String(finAt(t)).slice(0, 7) >= since).forEach((t) => {
      const p = proj(t.projectId); const c = p && p.clientId && clientById(p.clientId);
      const k = c ? c.name : p ? p.name : 'No client';
      byClient[k] = byClient[k] || { n: 0, color: p ? p.color : '#9aa4b2' }; byClient[k].n++;
    });
    const clients = Object.entries(byClient).sort((a, b) => b[1].n - a[1].n).slice(0, 5);
    const cmax = Math.max(1, ...clients.map(([, v]) => v.n));
    const invNow = inMonth('Invoiced', cur), invPrev = inMonth('Invoiced', prev);
    const invBy = [...new Set(ts.filter((t) => t.finance === 'Invoiced' && String(finAt(t)).slice(0, 7) === cur && t.financeBy && userById(t.financeBy)).map((t) => t.financeBy))];
    const recent = ts.filter((t) => t.finance && t.financeAt).sort((a, b) => b.financeAt.localeCompare(a.financeAt)).slice(0, 6);
    const mname = (m) => monthName(m, true).split(' ')[0];
    return `<div class="fa">
      <header class="fa-head">
        <div><h1>${greet}, ${esc(fullName(me()).split(' ')[0])}</h1><p>${esc(new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' }))} · where every job stands, from quote to invoice.</p></div>
        <div class="fa-seg">${[[6, 'Last 6 months'], [12, 'Last 12 months']].map(([n, l]) => `<button class="${(st.span || 6) === n ? 'on' : ''}" data-fin-span="${n}">${l}</button>`).join('')}</div>
      </header>
      <div class="fa-stats">${STATUSES.map((s) => `<button class="fa-stat ${g === s ? 'on' : ''}" data-fin-graph="${esc(s)}" style="--c:${FINANCE[s]}" title="Show “${esc(s)}” on the graph">
          <span class="fa-sl"><span class="fa-ic">${statusIcon}</span>${esc(s)}</span>
          <span class="fa-n">${count(s)}</span>
          <span class="fa-sf">${trend(inMonth(s, cur), inMonth(s, prev), s === 'Invoiced' || s === 'Retainer')}<span>vs ${esc(mname(prev))}</span></span>
        </button>`).join('')}</div>
      <div class="fa-grid">
        <div class="fa-main">
          <section class="fa-card">
            <div class="fa-ch"><h2>Monthly graph</h2><div class="fa-tabs">${STATUSES.map((s) => `<button class="${g === s ? 'on' : ''}" data-fin-graph="${esc(s)}" style="--c:${FINANCE[s]}">${esc(s)}</button>`).join('')}</div></div>
            <div class="fa-big"><b>${vals.reduce((a, b) => a + b, 0)}</b><span>tasks marked “${esc(g)}” in the last ${months.length} months</span></div>
            <div class="fa-plot" style="--c:${FINANCE[g]}">
              <svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id="fag" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${FINANCE[g]}" stop-opacity=".32"/><stop offset="1" stop-color="${FINANCE[g]}" stop-opacity="0"/></linearGradient></defs>
                <path d="M0 33H100M0 66H100" stroke="var(--border)" stroke-width="1" vector-effect="non-scaling-stroke"/><path d="${area}" fill="url(#fag)"/><path d="${line}" fill="none" stroke="${FINANCE[g]}" stroke-width="2.5" vector-effect="non-scaling-stroke"/></svg>
              ${pts.map(([x, y], i) => `<span class="fa-pt" style="left:${x}%;top:${y}%"><i></i><em>${esc(monthName(months[i], true))} · ${vals[i]} task${vals[i] === 1 ? '' : 's'}</em></span>`).join('')}
            </div>
            <div class="fa-months" style="grid-template-columns:repeat(${months.length},1fr)">${months.map((m) => `<span>${monthName(m)}</span>`).join('')}</div>
          </section>
          <div class="fa-two">
            <section class="fa-card">
              <div class="fa-ch"><h2>Status mix</h2><span class="fa-chip" style="--c:${FINANCE.Invoiced}">${Math.round((count('Invoiced') / total) * 100)}% invoiced</span></div>
              <div class="fa-mix">${STATUSES.map((s) => `<i style="width:${(count(s) / total) * 100}%;background:${FINANCE[s]}" title="${esc(s)}: ${count(s)}"></i>`).join('')}</div>
              <div class="fa-leg">${STATUSES.map((s) => `<span><i style="background:${FINANCE[s]}"></i>${esc(s)}<b>${Math.round((count(s) / total) * 100)}%</b></span>`).join('')}</div>
              <div class="fa-note"><b>${waiting} task${waiting === 1 ? '' : 's'}</b> waiting to be invoiced (LPO Pending + To be invoiced).</div>
            </section>
            <section class="fa-card">
              <div class="fa-ch"><h2>Invoiced by client</h2><span class="fa-muted">${months.length} months</span></div>
              <div class="fa-bars">${clients.map(([name, v]) => `<div><span><span><i style="background:${v.color}"></i>${esc(name)}</span><b>${v.n}</b></span><span class="fa-track"><i style="width:${(v.n / cmax) * 100}%;background:${v.color}"></i></span></div>`).join('') || '<div class="fin-empty">Nothing invoiced in this period yet.</div>'}</div>
            </section>
          </div>
        </div>
        <aside class="fa-side">
          <section class="fa-card fa-hero">
            <div class="fa-ch"><h2>Invoiced in ${esc(mname(cur))}</h2><span class="fa-muted">so far</span></div>
            <div class="fa-hero-n">${invNow}</div>
            <div class="fa-center">${(() => { const p = pctChange(invNow, invPrev); return `<span class="fa-chip ${p >= 0 ? 'good' : 'bad'}">${p >= 0 ? '↑' : '↓'} ${Math.abs(p)}% vs ${esc(mname(prev))} (${invPrev})</span>`; })()}</div>
            ${invBy.length ? `<div class="fa-avs">${invBy.slice(0, 5).map((u) => avatarHTML(u, 34)).join('')}</div><p class="fa-cap">${invBy.length === 1 ? esc(fullName(userById(invBy[0]))) + ' invoiced this month' : 'Account Managers who invoiced this month'}</p>` : '<p class="fa-cap">No invoices yet this month</p>'}
            <div class="fa-btns"><button class="btn" data-fin-go="fin-projects">Open Clients</button><button class="btn primary" data-fin-go="fin-expenses">Expenses</button></div>
          </section>
          <section class="fa-card">
            <div class="fa-ch"><h2>Recent changes</h2><button class="fa-link" data-fin-go="fin-projects">View all</button></div>
            <div class="fa-recent">${recent.map((t) => `<div class="fa-rrow" style="--c:${FINANCE[t.finance]}"><span class="fa-ric">${icon('check')}</span><span class="fa-rt"><b>${esc(t.title || 'Untitled task')}</b><small>${t.financeBy && userById(t.financeBy) ? esc(fullName(userById(t.financeBy))) + ' · ' : ''}${esc(ago(t.financeAt))}</small></span><span class="fa-rs">${esc(t.finance)}</span></div>`).join('') || '<div class="fin-empty">No Finance statuses yet.</div>'}</div>
          </section>
        </aside>
      </div>
    </div>`;
  }

  function projects() {
    const f = st.proj;
    const ts = finTasks().filter((t) => (f === 'all' ? true : f === 'none' ? !t.finance : t.finance === f));
    const can = isManager(); // only Account Managers and Admins change a task's Finance status
    const groups = db.projects.slice().sort(byOrder).map((p) => ({ p, list: ts.filter((t) => t.projectId === p.id) })).filter((g) => g.list.length);
    const none = ts.filter((t) => !t.projectId || !proj(t.projectId));
    if (none.length) groups.push({ p: { id: '_none', name: 'No client', color: '#666' }, list: none });
    const sec = (t) => (sectionOf(t) || {}).name || '';
    const chips = [['all', 'All'], ...STATUSES.map((s) => [s, s]), ['none', 'No Finance status']];
    return `
      <div class="fin-chips">${chips.map(([k, l]) => `<button class="${f === k ? 'on' : ''}" data-fin-proj="${esc(k)}">${esc(l)}<small>${k === 'all' ? finTasks().length : k === 'none' ? finTasks().filter((t) => !t.finance).length : finTasks().filter((t) => t.finance === k).length}</small></button>`).join('')}</div>
      ${groups.map(({ p, list }) => {
        const closed = !!st.open[p.id];
        return `<div class="fin-proj ${closed ? 'closed' : ''}">
          <button class="fp-head" data-fin-toggle="${esc(p.id)}">${icon('chev')}<i style="background:${p.color}"></i><b>${esc(p.name)}</b>${p.clientId && clientById(p.clientId) ? `<span class="fp-client">${esc(clientById(p.clientId).name)}</span>` : ''}<span class="fp-n">${list.length}</span></button>
          ${closed ? '' : `<div class="fp-rows">${list.map((t) => `<div class="fp-row ${t.done ? 'done' : ''}">
              <span class="fp-title">${t.done ? `<span class="fp-done">${icon('check')}</span>` : ''}${esc(t.title || 'Untitled task')}</span>
              <span class="fp-sec">${esc(sec(t))}</span>
              <span class="fp-due">${t.due ? esc(fmtDay(t.due)) : ''}</span>
              <span class="fp-fin">${can ? `<button class="fl-btn" data-fin-set="${t.id}">${t.finance ? fieldPill(t.finance, FINANCE[t.finance]) : '<span class="fl-empty">Set status</span>'}</button>` : t.finance ? fieldPill(t.finance, FINANCE[t.finance]).replace(icon('chev'), '') : '<span class="fl-empty">–</span>'}</span>
            </div>`).join('')}</div>`}
        </div>`;
      }).join('') || `<div class="fin-empty">No tasks ${f === 'all' ? 'yet' : 'with this status'}.</div>`}`;
  }
  function statusMenu(anchor, id) {
    const t = task(id);
    if (!t || !isManager()) return;
    const items = STATUSES.map((s) => ({ html: `<div class="mi">${fieldPill(s, FINANCE[s]).replace(icon('chev'), '')}${t.finance === s ? `<span class="wf-ck">${icon('check')}</span>` : ''}</div>`, run: () => { setField(t, 'finance', s); renderContent(); } }));
    if (t.finance) items.push({ html: '<div class="sep"></div>' }, { html: `<div class="mi fl-clear">${icon('x')}Clear</div>`, run: () => { setField(t, 'finance', null); renderContent(); } });
    const m = showMenu(anchor, items.map((it, i) => (it.run ? { ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) } : it)));
    m.classList.add('wf-menu', 'fl-menu');
  }

  /* ---------- Expenses ---------- */
  const txRow = (x, admin) => `<div class="fx-row">
      <span class="fx-date">${esc(fmtDay(x.date))}</span>
      <span class="fx-name">${esc(x.name)}</span>
      <span class="fx-kind" style="--c:${KIND_C[x.kind]}">${KIND_L[x.kind]}</span>
      <span class="fx-amt">${aed(x.amount)}</span>
      <span class="fx-inv">${x.invoice ? `<button class="btn ghost xs" data-fin-inv="${esc(x.id)}">${icon('clip')}Invoice</button>` : isFinAdmin() && !(x.kind === 'reimb' && x.ref.claimId) ? `<button class="btn ghost xs fx-miss" data-fin-txadd="${esc(x.id)}" title="No invoice yet — add it">${icon('plus')}Invoice</button>` : x.kind === 'reimb' && x.ref.claimId ? '<span class="fl-empty">Claim</span>' : '<span class="fl-empty">Missing</span>'}</span>
      ${admin ? `<span class="fx-x">${admin(x)}</span>` : ''}
    </div>`;
  function expenses() {
    const m = st.exMonth === 'prev' ? addMonths(thisMonth(), -1) : thisMonth();
    const pm = addMonths(m, -1);
    const all = transactions();
    const of = (mm, k) => all.filter((x) => x.date.slice(0, 7) === mm && (!k || x.kind === k));
    const sum = (mm, k) => of(mm, k).reduce((a, x) => a + x.amount, 0);
    const total = sum(m), prevTotal = sum(pm);
    const mname = (mm) => monthName(mm, true).split(' ')[0];
    const people = new Set(of(m, 'reimb').map((x) => x.name)).size;
    const cards = [
      ['Spent this month', total, sum(pm), `vs ${mname(pm)}`, 'var(--accent)'],
      ['Payments', sum(m, 'sub'), sum(pm, 'sub'), `${of(m, 'sub').length} subscription${of(m, 'sub').length === 1 ? '' : 's'}`, KIND_C.sub],
      ['Reimbursements', sum(m, 'reimb'), sum(pm, 'reimb'), `${people} ${people === 1 ? 'person' : 'people'}`, KIND_C.reimb],
      ['Big expenses', sum(m, 'expense'), sum(pm, 'expense'), `${of(m, 'expense').length} purchase${of(m, 'expense').length === 1 ? '' : 's'}`, KIND_C.expense],
    ];
    // Cash flow overview: one S-curve per kind, ending at its total
    const parts = [['sub', 'Payments'], ['reimb', 'Reimbursements'], ['expense', 'Big expenses']];
    // a round scale: 6 steps of 1 / 1.5 / 2 / 2.5 / 3 / 4 / 5 / 7.5 × 10ⁿ
    const raw = Math.max(1000, ...parts.map(([k]) => sum(m, k))) * 1.1 / 6;
    const mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const step = [1, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10].map((f) => f * mag).find((v) => v >= raw);
    const top = step * 6;
    const nice = (v) => (v >= 1000 ? +(v / 1000).toFixed(1) + 'k' : Math.round(v));
    // each curve ends right above its amount on the scale below (smallest first, each one starting where the last ended)
    let from = 0;
    // heights step up by size (smallest lowest) so the three curves never sit on each other; the scale gives the amount
    const LIFT = [24, 50, 78];
    const curves = parts.map(([k, l]) => ({ k, l, v: sum(m, k) })).sort((a, b) => a.v - b.v).map((c, i) => {
      const x1 = Math.max(0.5, (c.v / top) * 100), x0 = Math.min(from, Math.max(0, x1 - 4)), y = 92 - (c.v ? LIFT[i] : 0);
      from = x1;
      return { ...c, x1, y, d: `M${x0},92 C${(x0 + x1) / 2},92 ${(x0 + x1) / 2},${y} ${x1},${y}` };
    });
    // labels: flip to the left near the right edge; drop below the dot when the next label would sit on top of it
    curves.forEach((c, i) => { const n = curves[i + 1]; c.cls = c.x1 > 86 ? 'flip below' : n && n.x1 - c.x1 < 22 && Math.abs(n.y - c.y) < 22 ? 'below' : ''; });
    // half donut
    let a0 = Math.PI;
    const arcs = parts.slice().sort((a, b) => sum(m, b[0]) - sum(m, a[0])).map(([k, l]) => {
      const v = sum(m, k); const sweep = total ? Math.PI * (v / total) : 0; const a1 = a0 + sweep;
      const R = 130, r = 72, cx = 150, cy = 150, gap = sweep > 0.05 ? 0.012 : 0;
      const p = (ang, rad) => `${(cx + rad * Math.cos(ang)).toFixed(1)},${(cy + rad * Math.sin(ang)).toFixed(1)}`;
      const d = sweep ? `M${p(a0, R)} A${R},${R} 0 0 1 ${p(a1 - gap, R)} L${p(a1 - gap, r)} A${r},${r} 0 0 0 ${p(a0, r)} Z` : '';
      a0 = a1;
      return { k, l, v, d, pct: total ? Math.round((v / total) * 100) : 0 };
    });
    const biggest = of(m).slice().sort((a, b) => b.amount - a.amount)[0];
    const live = recs('sub').filter((x) => !x.endedAt);
    const monthly = live.reduce((a, x) => a + (Number(x.amount) || 0), 0);
    const today = todayStr();
    const upcoming = [];
    live.forEach((x) => { for (let k = 0; k < 2; k++) { const mm = addMonths(thisMonth(), k); const d = `${mm}-${pad2(Math.min(Number(x.day) || 1, daysIn(mm)))}`; if (d >= today && d <= addDays(today, 30)) upcoming.push({ x, d }); } });
    upcoming.sort((a, b) => a.d.localeCompare(b.d));
    const ini = (n) => String(n).replace(/[^A-Za-z0-9 ]/g, '').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || '?';
    const subColor = (i) => ['#e5484d', '#a875ff', '#4c9aff', '#4fd1c5', '#3ddc97', '#f9be33', '#ff8a4c', '#ff8fc7'][i % 8];
    const barMax = Math.max(total, prevTotal) * 1.25 || 1;
    const p = pctChange(total, prevTotal);
    return `<div class="fa">
      <header class="fa-head">
        <div><h1>Expenses</h1><p>Everything E11 paid out in ${esc(monthName(m, true))} — subscriptions, staff reimbursements and big purchases.</p></div>
        <div class="fr-wrap"><div class="fa-seg">${[['cur', 'This month'], ['prev', 'Last month']].map(([k, l]) => `<button class="${(st.exMonth || 'cur') === k ? 'on' : ''}" data-fin-exm="${k}">${l}</button>`).join('')}</div>
          <button class="btn primary fr-btn" data-fin-rep aria-expanded="${rep.open}">${icon('download')}Download report</button>${repPop()}</div>
      </header>
      <div class="fa-stats four">${cards.map(([l, v, pv, note, c], i) => `<div class="fa-stat static" style="--c:${c}"><span class="fa-sl"><span class="fa-ic">${icon('coin')}</span>${esc(l)}</span><span class="fa-n money">${aed(v)}</span><span class="fa-sf">${trend(v, pv, false)}<span>${esc(note)}</span></span></div>`).join('')}</div>
      <div class="fa-grid">
        <div class="fa-main">
          <section class="fa-card">
            <div class="fa-ch"><h2>Cash flow overview</h2><div class="fa-legend">${parts.map(([k, l]) => `<span><i style="background:${KIND_C[k]}"></i>${l}</span>`).join('')}</div></div>
            <div class="fa-flow">
              <svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><defs>${parts.map(([k]) => `<linearGradient id="fl-${k}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="${KIND_C[k]}" stop-opacity="0"/><stop offset=".65" stop-color="${KIND_C[k]}"/></linearGradient>`).join('')}</defs>
                ${curves.map((c) => `<path d="${c.d}" fill="none" stroke="url(#fl-${c.k})" stroke-width="2.5" vector-effect="non-scaling-stroke"/>`).join('')}</svg>
              ${curves.map((c) => `<span class="fa-end ${c.cls}" style="left:${c.x1}%;top:${c.y}%;--c:${KIND_C[c.k]}"><i></i><span><small>${c.l}</small><b>${aed(c.v)}</b></span></span>`).join('')}
            </div>
            <div class="fa-ruler"></div>
            <div class="fa-scale">${Array.from({ length: 7 }, (_, i) => `<span style="left:${(i / 6) * 100}%">${i ? nice(step * i) : 'AED 0'}</span>`).join('')}</div>
          </section>
          <div class="fa-two">
            <section class="fa-card">
              <div class="fa-ch"><h2>Compared with ${esc(mname(pm))}</h2><span class="fa-chip ${p > 0 ? 'bad' : 'good'}">${p > 0 ? '+' : ''}${p}%</span></div>
              <div class="fa-kv"><span>Spent</span><b>${aed(total)}</b></div>
              <div class="fa-slider"><i class="fill" style="width:${(total / barMax) * 100}%"></i><i class="knob" style="left:${(total / barMax) * 100}%"></i><i class="mark" style="left:${(prevTotal / barMax) * 100}%" title="${esc(mname(pm))}"></i></div>
              <div class="fa-kv sm"><span>AED 0</span><span class="acc">${esc(mname(pm))}: ${aed(prevTotal)}</span></div>
              ${biggest ? `<div class="fa-note"><div class="fa-kv"><span>Biggest item</span><b>${aed(biggest.amount)}</b></div><p>${esc(biggest.name)} · ${esc(KIND_L[biggest.kind])}, paid ${esc(fmtDay(biggest.date))}.</p></div>` : ''}
            </section>
            <section class="fa-card">
              <div class="fa-ch"><h2>All expenses</h2><span class="fa-muted">${esc(mname(m))}</span></div>
              <div class="fa-donut"><svg viewBox="0 0 300 160" aria-hidden="true">${arcs.map((a) => (a.d ? `<path d="${a.d}" fill="${KIND_C[a.k]}"><title>${a.l}: ${a.pct}%</title></path>` : '')).join('') || '<path d="M20,150 A130,130 0 0 1 280,150 L222,150 A72,72 0 0 0 78,150 Z" fill="var(--hover)"/>'}</svg><div><small>Total</small><b>${aed(total)}</b></div></div>
              <div class="fa-leg fa-leg-col">${arcs.map((a) => `<span><i style="background:${KIND_C[a.k]}"></i>${a.l}<b>${a.pct}%</b><button class="fa-link" data-fin-all="${a.k}">View all</button></span>`).join('')}</div>
            </section>
          </div>
        </div>
        <aside class="fa-side">
          <section class="fa-card">
            <div class="fa-ch"><h2>Subscriptions</h2>${isFinAdmin() ? `<button class="fa-link box" data-fin-go="fin-subs">+ Add</button>` : ''}</div>
            <div class="fa-subcard"><span class="fa-pill">Every month</span><b>${aed(monthly)}</b><div class="fa-subs">${live.slice(0, 7).map((x, i) => `<span style="background:${subColor(i)}" title="${esc(x.name)}">${esc(ini(x.name))}</span>`).join('')}</div><small>${live.length} subscription${live.length === 1 ? '' : 's'} · recorded on their billing day</small></div>
          </section>
          <section class="fa-card">
            <div class="fa-ch"><h2>Coming up</h2><span class="fa-muted">next 30 days</span></div>
            <div class="fa-up">${upcoming.slice(0, 5).map(({ x, d }) => `<div><span class="av" style="background:${subColor(live.indexOf(x))}">${esc(ini(x.name))}</span><span class="t"><b>${esc(x.name)}</b><small>${esc(fmtDay(d))}</small></span><b class="m">${aed(x.amount)}</b></div>`).join('') || '<div class="fin-empty">Nothing due in the next 30 days.</div>'}</div>
            <p class="fa-cap">Recorded automatically on each billing day</p>
          </section>
        </aside>
      </div>
      <section class="fa-card">
        <div class="fa-ch"><h2>Recent transactions</h2><button class="fa-link" data-fin-all="all">View all ${icon('arrow')}</button></div>
        ${all.slice(0, 5).map((x) => txRow(x)).join('') || '<div class="fin-empty">No transactions yet.</div>'}
      </section>
    </div>`;
  }
  function list() {
    const L = st.list;
    let tx = transactions();
    if (L.type !== 'all') tx = tx.filter((x) => x.kind === L.type);
    const months = [...new Set(transactions().map((x) => x.date.slice(0, 7)))].sort().reverse();
    if (L.month) tx = tx.filter((x) => x.date.slice(0, 7) === L.month);
    const pages = Math.max(1, Math.ceil(tx.length / 50));
    L.page = Math.min(L.page, pages - 1);
    const shown = tx.slice(L.page * 50, L.page * 50 + 50);
    const total = tx.reduce((a, x) => a + x.amount, 0);
    return `<div class="widget fin-list">
      <div class="fl-bar">
        <button class="btn ghost" data-fin-back>${icon('chev-left')}Expenses</button>
        <div class="fin-chips">${[['all', 'All'], ['expense', 'Big expenses'], ['sub', 'Payments'], ['reimb', 'Reimbursements']].map(([k, l]) => `<button class="${L.type === k ? 'on' : ''}" data-fin-type="${k}">${l}</button>`).join('')}</div>
        <span class="spacer"></span>
        <select class="field fin-month" data-fin-month>${['', ...months].map((m) => `<option value="${m}" ${m === L.month ? 'selected' : ''}>${m ? esc(monthName(m, true)) : 'All months'}</option>`).join('')}</select>
      </div>
      <div class="fl-sum">${tx.length} transaction${tx.length === 1 ? '' : 's'} · <b>${aed(total)}</b></div>
      ${shown.map((x) => txRow(x)).join('') || '<div class="fin-empty">Nothing here.</div>'}
      ${pages > 1 ? `<div class="fin-pages"><button class="btn ghost" data-fin-page="-1" ${L.page ? '' : 'disabled'}>${icon('chev-left')}Previous</button><span>Page ${L.page + 1} of ${pages}</span><button class="btn ghost" data-fin-page="1" ${L.page < pages - 1 ? '' : 'disabled'}>Next${icon('chev-right')}</button></div>` : ''}
    </div>`;
  }

  /* ---------- Finance Admin: add pages ---------- */
  function subsPage() {
    const live = recs('sub').filter((s) => !s.endedAt), ended = recs('sub').filter((s) => s.endedAt);
    const m = thisMonth();
    const nextDate = (s) => { const d = `${m}-${pad2(Math.min(Number(s.day) || 1, daysIn(m)))}`; return d >= todayStr() ? d : `${addMonths(m, 1)}-${pad2(Math.min(Number(s.day) || 1, daysIn(addMonths(m, 1))))}`; };
    const monthly = live.reduce((a, s) => a + (Number(s.amount) || 0), 0);
    return `<div class="widget fin-add">
      <h3>Monthly subscriptions<span class="spacer"></span><button class="btn primary" data-fin-new="sub">${icon('plus')}Add subscription</button></h3>
      <p class="fin-note">Each subscription is recorded as an expense on its billing day every month. ${live.length ? `Together: <b>${aed(monthly)}</b> a month.` : ''}</p>
      ${live.map((s) => `<div class="fa-row">
          <span class="fa-name"><b>${esc(s.name)}</b><small>Every month on the ${ordinal(Number(s.day) || 1)} · next ${esc(fmtDay(nextDate(s)))}</small>${missLine(s)}</span>
          <span class="fx-amt">${aed(s.amount)}</span>
          <span class="fa-inv">${(s.invoices || {})[m] ? `<button class="btn ghost xs" data-fin-subinv="${s.id}">${icon('clip')}${esc(monthName(m, true).split(' ')[0])} invoice</button>` : `<button class="btn ghost xs" data-fin-subadd="${s.id}">${icon('plus')}Add ${esc(monthName(m, true).split(' ')[0])} invoice</button>`}</span>
          <button class="icon-btn sm" data-fin-del="${s.id}" title="Remove subscription (past months stay in the records)">${icon('trash')}</button>
        </div>`).join('') || '<div class="fin-empty">No subscriptions yet.</div>'}
      ${ended.length ? `<div class="fa-ended"><div class="fa-eh">Ended</div>${ended.map((s) => `<div class="fa-row ended"><span class="fa-name"><b>${esc(s.name)}</b><small>Ended ${esc(fmtDay(ymd(new Date(s.endedAt))))}</small>${missLine(s)}</span><span class="fx-amt">${aed(s.amount)}</span></div>`).join('')}</div>` : ''}
    </div>`;
  }
  // earlier months still without an invoice (this month has its own button)
  const missLine = (s) => { const ms = subMissing(s).filter((m) => m !== thisMonth()); return ms.length ? `<span class="fa-miss">Missing invoices:${ms.map((m) => `<button data-fin-subadd="${s.id}" data-m="${m}" title="Add the ${esc(monthName(m, true))} invoice">${icon('plus')}${esc(monthName(m))}${m.slice(0, 4) !== thisMonth().slice(0, 4) ? ' ' + m.slice(2, 4) : ''}</button>`).join('')}</span>` : ''; };
  const ordinal = (n) => n + (n % 10 === 1 && n !== 11 ? 'st' : n % 10 === 2 && n !== 12 ? 'nd' : n % 10 === 3 && n !== 13 ? 'rd' : 'th');
  function monthRecords(type, label, btn) {
    const m = thisMonth();
    const list = recs(type).filter((r) => String(r.date || '').slice(0, 7) === m).sort((a, b) => b.date.localeCompare(a.date));
    const total = list.reduce((a, r) => a + (Number(r.amount) || 0), 0);
    const admin = isFinAdmin();
    return `<div class="widget fin-add">
      <h3>${type === 'reimb' ? 'Paid' : label} — ${esc(monthName(m, true))}<span class="spacer"></span>${admin ? `<button class="btn ${type === 'reimb' ? '' : 'primary'}" data-fin-new="${type}">${icon('plus')}${type === 'reimb' ? 'Add one by hand (PDF)' : btn}</button>` : ''}</h3>
      <p class="fin-note">${list.length ? `${list.length} this month · <b>${aed(total)}</b>. ` : ''}Earlier months are under Expenses → View all.</p>
      ${list.map((r) => `<div class="fa-row">
          <span class="fa-name"><b>${esc(type === 'reimb' ? personName(r) : r.name)}</b><small>Paid ${esc(fmtDay(r.date))}</small></span>
          <span class="fx-amt">${aed(r.amount)}</span>
          <span class="fa-inv">${r.claimId ? `<button class="btn ghost xs" data-cl="open" data-id="${esc(r.claimId)}">${icon('open')}Claim</button>` : r.invoice ? `<button class="btn ghost xs" data-fin-rinv="${r.id}">${icon('clip')}Invoice</button>` : admin ? `<button class="btn ghost xs fx-miss" data-fin-txadd="${esc(r.id)}" title="No invoice yet — add it">${icon('plus')}Add invoice</button>` : '<span class="fl-empty">No invoice</span>'}</span>
          ${admin && !r.claimId ? `<button class="icon-btn sm" data-fin-del="${r.id}" title="Remove">${icon('trash')}</button>` : '<span class="fa-sp"></span>'}
        </div>`).join('') || '<div class="fin-empty">Nothing added this month.</div>'}
    </div>`;
  }
  const reimbPage = () => Claims.financeSection() + monthRecords('reimb', 'Staff reimbursements', 'Add reimbursement');
  const extraPage = () => monthRecords('expense', 'Extra expenses', 'Add expense');

  /* ---------- Add form (pop-up) ---------- */
  async function pickInvoice(folder, month) {
    const r = await Host.call('pickAttachments', { dest: 'Finance/' + folder + '/' + (month || thisMonth()) });
    const f = (r.files || [])[0];
    return f ? { ...f, addedAt: nowISO(), addedBy: currentUserId } : null;
  }
  function form(kind) {
    return new Promise((resolve) => {
      const root = $('#overlay-root');
      const st2 = { invoice: null, busy: false };
      const T = { sub: 'Add subscription', reimb: 'Add staff reimbursement', expense: 'Add extra expense' }[kind];
      const peopleOpts = () => {
        const team = activeUsers().filter((u) => !isFinUser(u) || true);
        const extra = recs('person');
        return `<option value="">Choose a person…</option><optgroup label="Team members">${team.map((u) => `<option value="u:${u.id}">${esc(fullName(u))}</option>`).join('')}</optgroup>${extra.length ? `<optgroup label="Other people">${extra.map((p) => `<option value="p:${p.id}">${esc(p.name)}</option>`).join('')}</optgroup>` : ''}`;
      };
      const extraList = () => recs('person').map((p) => `<span class="fin-person">${esc(p.name)}<button type="button" data-xp="${p.id}" title="Remove from the list">${icon('x')}</button></span>`).join('');
      root.innerHTML = `<div class="scrim"><form class="dialog form-dlg fin-form" autocomplete="off">
        <h2>${T}</h2>
        ${kind === 'reimb' ? `<label class="dlg-label">Person</label><select class="field" name="who">${peopleOpts()}</select>
          <div class="fin-extra-people"><div class="fep-list">${extraList()}</div><div class="fep-add"><input class="field" name="newPerson" placeholder="Add someone who isn’t a team member"><button type="button" class="btn" data-addp>Add</button></div></div>`
          : `<label class="dlg-label">Name</label><input class="field" name="name" placeholder="${kind === 'sub' ? 'e.g. Adobe Creative Cloud' : 'e.g. Studio lights'}">`}
        <label class="dlg-label">Amount (AED)</label><input class="field" name="amount" type="number" min="0" step="0.01" inputmode="decimal" placeholder="0.00">
        ${kind === 'sub' ? `<label class="dlg-label">Billing day each month</label><select class="field" name="day">${Array.from({ length: 31 }, (_, i) => `<option value="${i + 1}" ${i + 1 === new Date().getDate() ? 'selected' : ''}>${ordinal(i + 1)}</option>`).join('')}</select><div class="dlg-hint">Months shorter than this use their last day.</div>`
          : `<label class="dlg-label">Payment date</label><span class="date-chip set fin-date">${icon('cal')}<span class="date-lbl">${esc(fmtDay(todayStr()))}</span><input type="date" class="date-in" name="date" value="${todayStr()}"></span>`}
        <label class="dlg-label">Invoice</label><div class="fin-inv-field"><button type="button" class="btn" data-pick>${icon('clip')}Attach invoice</button><span class="fin-inv-name"></span></div>
        <div class="dlg-err"></div>
        <div class="actions"><button type="button" class="btn" data-r="0">Cancel</button><button type="submit" class="btn primary">Save</button></div>
      </form></div>`;
      const formEl = $('form', root), err = $('.dlg-err', root);
      const close = (v) => { root.innerHTML = ''; document.removeEventListener('keydown', onKey, true); resolve(v); };
      const onKey = (e) => { if ($('.dp-pop')) return; if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(null); } };
      document.addEventListener('keydown', onKey, true);
      $('[data-r="0"]', root).addEventListener('click', () => close(null));
      const dateIn = formEl.elements.date;
      if (dateIn) dateIn.addEventListener('change', () => { $('.fin-date .date-lbl', root).textContent = dateIn.value ? fmtDay(dateIn.value) : 'Pick a date'; });
      $('.scrim', root).addEventListener('click', async (e) => {
        if (e.target.closest('[data-pick]')) {
          if (st2.busy) return;
          st2.busy = true;
          try { const f = await pickInvoice({ sub: 'Subscriptions', reimb: 'Reimbursements', expense: 'Expenses' }[kind]); if (f) { st2.invoice = f; $('.fin-inv-name', root).innerHTML = `${esc(f.name)} <button type="button" class="icon-btn xs" data-unpick>${icon('x')}</button>`; } }
          catch (x) { err.textContent = 'Could not attach the invoice: ' + x.message; }
          st2.busy = false;
        }
        if (e.target.closest('[data-unpick]')) { st2.invoice = null; $('.fin-inv-name', root).innerHTML = ''; }
        if (e.target.closest('[data-addp]')) {
          const n = (formEl.elements.newPerson.value || '').trim();
          if (!n) return;
          const p = { id: uid(), type: 'person', name: n, createdAt: nowISO(), createdBy: currentUserId };
          db.finance.push(p); persist(0);
          formEl.elements.newPerson.value = '';
          formEl.elements.who.innerHTML = peopleOpts(); formEl.elements.who.value = 'p:' + p.id;
          $('.fep-list', root).innerHTML = extraList();
        }
        const xp = e.target.closest('[data-xp]');
        if (xp) {
          const i = db.finance.findIndex((x) => x.id === xp.dataset.xp);
          if (i >= 0) { db.finance.splice(i, 1); persist(0); }
          const keep = formEl.elements.who.value;
          formEl.elements.who.innerHTML = peopleOpts(); formEl.elements.who.value = keep;
          $('.fep-list', root).innerHTML = extraList();
        }
      });
      formEl.addEventListener('submit', (e) => {
        e.preventDefault();
        const el = formEl.elements;
        const amount = Math.round(parseFloat(el.amount.value) * 100) / 100;
        if (kind === 'reimb' && !el.who.value) { err.textContent = 'Choose who is being reimbursed'; return; }
        if (kind !== 'reimb' && !(el.name.value || '').trim()) { err.textContent = 'Enter a name'; el.name.focus(); return; }
        if (!(amount > 0)) { err.textContent = 'Enter the amount in AED (numbers only)'; el.amount.focus(); return; }
        if (dateIn && !dateIn.value) { err.textContent = 'Choose the payment date'; return; }
        const rec = { id: uid(), type: kind, amount, createdAt: nowISO(), createdBy: currentUserId };
        if (kind === 'sub') { rec.name = el.name.value.trim(); rec.day = Number(el.day.value); rec.startMonth = thisMonth(); rec.invoices = st2.invoice ? { [thisMonth()]: st2.invoice } : {}; rec.endedAt = null; }
        else {
          rec.date = dateIn.value; rec.invoice = st2.invoice;
          if (kind === 'expense') rec.name = el.name.value.trim();
          else { const [t, id] = el.who.value.split(':'); if (t === 'u') rec.userId = id; else { rec.personId = id; rec.personName = (recs('person').find((p) => p.id === id) || {}).name || ''; } }
        }
        close(rec);
      });
      setTimeout(() => { const f = $('input.field, select.field', formEl); if (f) f.focus(); }, 20);
    });
  }
  async function add(kind) {
    if (!isFinAdmin()) return;
    const rec = await form(kind);
    if (!rec) return;
    db.finance.push(rec); persist(0); renderContent();
    toast(kind === 'sub' ? `${rec.name} added — recorded every month on the ${ordinal(rec.day)}` : 'Saved');
  }
  async function remove(id) {
    const r = (db.finance || []).find((x) => x.id === id);
    if (!r || !isFinAdmin()) return;
    if (r.type === 'sub') {
      const ok = await dialog({ title: `Remove ${r.name}?`, body: 'It won’t be recorded from now on. Months already recorded stay in the records.', okText: 'Remove', danger: true });
      if (!ok) return;
      r.endedAt = nowISO();
    } else {
      const ok = await dialog({ title: 'Remove this record?', body: 'It will no longer count in the expenses.', okText: 'Remove', danger: true });
      if (!ok) return;
      db.finance.splice(db.finance.indexOf(r), 1);
    }
    persist(0); renderContent();
  }
  async function subInvoice(id, month) {
    const s = recs('sub').find((x) => x.id === id);
    if (!s || !isFinAdmin()) return;
    const m = month || thisMonth();
    try {
      const f = await pickInvoice('Subscriptions', m);
      if (!f) return;
      s.invoices = { ...(s.invoices || {}), [m]: f };
      persist(0); renderContent();
      toast(`${monthName(m, true)} invoice added to ${s.name}`);
    } catch (e) { toast('Could not attach the invoice: ' + e.message); }
  }
  const openFile = (f) => { if (f) previewFile(f); };
  // A Finance Admin adds a missing invoice afterwards, for any month (Expenses lists, report gaps)
  async function txInvoice(id) {
    const x = transactions().find((y) => y.id === id);
    if (!x || !isFinAdmin() || x.invoice || (x.kind === 'reimb' && x.ref.claimId)) return;
    if (x.kind === 'sub') return subInvoice(x.ref.id, x.month);
    try {
      const f = await pickInvoice(x.kind === 'reimb' ? 'Reimbursements' : 'Expenses', x.date.slice(0, 7));
      if (!f) return;
      x.ref.invoice = f;
      persist(0); renderContent();
      toast(`Invoice added to ${x.name}`);
    } catch (e) { toast('Could not attach the invoice: ' + e.message); }
  }
  // Paid months (up to the last 12) of a subscription that still have no invoice, oldest first
  const subMissing = (s) => subPayments(s).filter((p) => !p.invoice && p.month >= addMonths(thisMonth(), -11)).map((p) => p.month);

  /* ---------- Clicks ---------- */
  document.addEventListener('click', (e) => {
    if (!owns(ui.view) && !e.target.closest('[data-fin-go]')) return;
    if (rep.open && !e.target.closest('.fr-pop,[data-fin-rep]')) { rep.open = false; const pop = $('.fr-pop'); if (pop) pop.remove(); const b = $('[data-fin-rep]'); if (b) b.setAttribute('aria-expanded', 'false'); }
    if (e.target.closest('[data-fin-repf]')) return;   // the checkbox: handled on change
    const el = e.target.closest('[data-fin-rep],[data-fin-repm],[data-fin-repy],[data-fin-repgo],[data-fin-go],[data-fin-span],[data-fin-exm],[data-fin-status],[data-fin-graph],[data-fin-proj],[data-fin-toggle],[data-fin-set],[data-fin-all],[data-fin-back],[data-fin-type],[data-fin-page],[data-fin-inv],[data-fin-new],[data-fin-del],[data-fin-subinv],[data-fin-subadd],[data-fin-rinv],[data-fin-txadd]');
    if (!el) return;
    e.stopPropagation();
    const d = el.dataset;
    if (el.hasAttribute('data-fin-rep')) return repToggle();
    if (d.finRepm) return repPick(d.finRepm);
    if (d.finRepy) { rep.year += Number(d.finRepy); return renderContent(); }
    if (el.hasAttribute('data-fin-repgo')) return repDownload();
    if (d.finGo) return go(d.finGo);
    if (d.finStatus) { st.proj = d.finStatus; return go('fin-projects'); }
    if (d.finGraph) { st.graph = d.finGraph; return renderContent(); }
    if (d.finSpan) { st.span = Number(d.finSpan); return renderContent(); }
    if (d.finExm) { st.exMonth = d.finExm; return renderContent(); }
    if (d.finProj) { st.proj = d.finProj; return renderContent(); }
    if (d.finToggle) { st.open[d.finToggle] = !st.open[d.finToggle]; return renderContent(); }
    if (d.finSet) return statusMenu(el, d.finSet);
    if (d.finAll) { st.list = { type: d.finAll, month: '', page: 0 }; return go('fin-list'); }
    if (el.hasAttribute('data-fin-back')) return go('fin-expenses');
    if (d.finType) { st.list.type = d.finType; st.list.page = 0; return renderContent(); }
    if (d.finPage) { st.list.page += Number(d.finPage); $('#content').scrollTop = 0; return renderContent(); }
    if (d.finInv) { const x = transactions().find((y) => y.id === d.finInv); return openFile(x && x.invoice); }
    if (d.finNew) return add(d.finNew);
    if (d.finDel) return remove(d.finDel);
    if (d.finSubadd) return subInvoice(d.finSubadd, d.m);
    if (d.finTxadd) return txInvoice(d.finTxadd);
    if (d.finSubinv) { const s = recs('sub').find((x) => x.id === d.finSubinv); return openFile(s && (s.invoices || {})[thisMonth()]); }
    if (d.finRinv) { const r = (db.finance || []).find((x) => x.id === d.finRinv); return openFile(r && r.invoice); }
  }, true);
  document.addEventListener('change', (e) => {
    if (e.target.matches && e.target.matches('[data-fin-repf]')) { rep.files = e.target.checked; renderContent(); return; }
    if (e.target.matches && e.target.matches('[data-fin-month]')) { st.list.month = e.target.value; st.list.page = 0; renderContent(); }
  });

  /* ---------- Subscription invoice reminder ----------
     Finance Admins: from the 25th to the end of the month, once a day from 11:30 AM, a pop-up lists this
     month's subscriptions (already billed) that have no invoice yet. */
  function invoiceTick() {
    if (!db || !currentUserId || !isFinAdmin() || !Host.isServer || (typeof Phone !== 'undefined' && Phone.on)) return;
    if ($('#overlay-root').children.length || $('.ec-remind') || $('.an-pop')) return;
    try { if (navigator.webdriver && localStorage.getItem('e11-inv-remind') !== '1') return; } catch (e) { /* storage blocked */ }
    const now = new Date();
    if (now.getDate() < 25 || now.getHours() * 60 + now.getMinutes() < 11 * 60 + 30) return;
    const u = me(); u.prefs = u.prefs || {};
    if (u.prefs.invNag === todayStr()) return;
    const m = thisMonth();
    const miss = recs('sub').map((s) => subPayments(s).find((p) => p.month === m && !p.invoice)).filter(Boolean);
    if (!miss.length) return;
    u.prefs.invNag = todayStr(); persist(0);
    if (!document.hasFocus()) Host.call('notify', { title: 'Subscription invoices', body: `${miss.length} subscription${miss.length === 1 ? ' has' : 's have'} no ${monthName(m, true)} invoice`, sound: 'Glass' }).catch(() => {});
    const el = document.createElement('div');
    el.className = 'ec-remind fin-remind';
    el.innerHTML = `<div class="ec-rbox" role="dialog" aria-labelledby="fi-rt">
      <div class="ec-rtop"><img src="logo-tile.png" alt="E11"><div><small>SUBSCRIPTION INVOICES · ${esc(monthName(m, true).toUpperCase())}</small><h2 id="fi-rt">${miss.length === 1 ? '1 subscription has' : miss.length + ' subscriptions have'} no ${esc(monthName(m, true).split(' ')[0])} invoice</h2>
        <p>Attach them before the month ends, so the expenses report is complete.</p></div></div>
      <div class="fi-list">${miss.map((p) => `<div><b>${esc(p.name)}</b><span>Billed ${esc(fmtDay(p.date))}</span><em>${aed(p.amount)}</em></div>`).join('')}</div>
      <div class="ec-rbtns"><button class="btn primary" data-r="go">Attach invoices</button></div>
      <button class="ec-rlater" data-r="later">Remind me tomorrow</button>
    </div>`;
    document.body.appendChild(el);
    el.addEventListener('click', (e) => {
      const b = e.target.closest('[data-r]'); if (!b) return;
      el.remove();
      if (b.dataset.r === 'go') go('fin-subs');
    });
  }

  return { owns, init, paintNav, invoiceTick, meMenu, addItems, canLook, title, render, transactions, subPayments, aed, st };
})();
