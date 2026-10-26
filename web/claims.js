/* ================= Expense claims =================
   Everyone except Finance-only people fills in a monthly expense claim (computers only, like Finance):
   My profile → My reimbursements. A claim is one record in db.claims (server kind "claims"):
     { id: 'cl-<userId>-<YYYY-MM>', userId, month, state, groups: [{ id, date, title, items: [{ id, desc, amount, receipt }] }],
       total, signature, submittedAt, approvedAt, approvedBy, paidOn, paidBy, reimbId, createdAt, updatedAt }
   state: draft | submitted | approved (HR) | paid | none ("I don't have claims") | offline ("Submitted offline").
   Finance sees every claim except drafts and "offline". A month's claims close on the 28th; from then on
   new claims are for the next month. From the 20th to the 27th a reminder pop-up shows once a day from
   11:30 AM until the person submits, says they have no claims, or that they submitted offline. */
const Claims = (() => {
  const VIEWS = ['claims', 'claim'];
  const st = { draft: null, key: '', finMonth: null, flash: null, sel: new Set() };
  const owns = (v) => VIEWS.includes(v);
  const all = () => db.claims || [];
  const idFor = (uid, m) => `cl-${uid}-${m}`;
  const byId = (id) => all().find((c) => c.id === id) || null;
  const mineFor = (m) => byId(idFor(currentUserId, m));
  const phone = () => typeof Phone !== 'undefined' && Phone.on;
  const addMonth = (m, n) => { const [y, mo] = m.split('-').map(Number); const d = new Date(y, mo - 1 + n, 1); return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`; };
  const monthName = (m, short) => { const [y, mo] = m.split('-').map(Number); return new Date(y, mo - 1, 1).toLocaleDateString('en-US', short ? { month: 'long' } : { month: 'long', year: 'numeric' }); };
  // From the 28th, claims are for the next month
  const claimMonth = (d = todayStr()) => (Number(d.slice(8, 10)) >= 28 ? addMonth(d.slice(0, 7), 1) : d.slice(0, 7));
  const closed = (m) => todayStr() >= `${m}-28`;
  const canClaim = (u = me()) => !!u && !isFinUser(u) && u.active !== false;
  const plural = (n, one, many) => `${n} ${n === 1 ? one : many || one + 's'}`;
  const num = (v) => { const n = parseFloat(String(v == null ? '' : v).replace(/,/g, '')); return Number.isFinite(n) ? n : 0; };
  const money = (n) => (Number(n) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const totalOf = (c) => (c.groups || []).reduce((a, g) => a + (g.items || []).reduce((b, i) => b + num(i.amount), 0), 0);
  const itemsOf = (c) => (c.groups || []).reduce((a, g) => a + (g.items || []).length, 0);
  const receiptsOf = (c) => (c.groups || []).flatMap((g) => (g.items || []).filter((i) => i.receipt).map((i) => i.receipt));
  const STATE = {
    draft: ['Draft', '#f3f3f6', '#6e717a'], submitted: ['Submitted', 'rgba(123,104,238,.16)', '#7b68ee'], approved: ['HR approved', 'rgba(79,209,197,.16)', '#1f9e93'],
    paid: ['Paid', 'rgba(61,220,151,.16)', '#18a565'], none: ['No claims', '#f3f3f6', '#6e717a'], offline: ['Submitted offline', '#f3f3f6', '#6e717a'],
  };
  const pill = (c) => { const s = STATE[c.state] || STATE.draft; return `<span class="ec-pill" style="background:${s[1]};color:${s[2]}">${s[0]}${c.state === 'paid' && c.paidOn ? ' · ' + esc(fmtDay(c.paidOn)) : ''}</span>`; };
  const editable = (c) => !!c && c.userId === currentUserId && !['approved', 'paid'].includes(c.state) && !closed(c.month);
  const finUsers = () => db.users.filter((u) => u.active !== false && finLevel(u));
  const fileUrlOf = (f) => '/__file/' + String(f.path).split('/').map(encodeURIComponent).join('/');

  function save(c) {
    c.updatedAt = nowISO();
    c.total = Math.round(totalOf(c) * 100) / 100;
    const i = db.claims.findIndex((x) => x.id === c.id);
    if (i >= 0) db.claims[i] = c; else db.claims.push(c);
    persist(0);
  }
  function notify(to, c, kind, text) {
    if (!to || to === currentUserId) return;
    db.notifications.push({ id: uid(), to, from: currentUserId, taskId: null, claimId: c.id, month: c.month, kind, text, snippet: c.total ? 'AED ' + money(c.total) : '', commentId: null, at: nowISO(), read: false });
  }

  /* ---------- My reimbursements ---------- */
  function viewList() {
    const u = me();
    const m = claimMonth();
    const cur = mineFor(m);
    const rows = all().filter((c) => c.userId === currentUserId && c.state !== 'offline').sort((a, b) => b.month.localeCompare(a.month));
    // reimbursements Finance recorded by hand (PDF uploads) for this person
    const manual = (db.finance || []).filter((r) => r.type === 'reimb' && r.userId === currentUserId && !r.claimId).sort((a, b) => b.date.localeCompare(a.date));
    const btn = !canClaim(u) ? '' : cur && cur.state !== 'draft'
      ? `<button class="btn" data-cl="open" data-id="${cur.id}">${icon('open')}Open your ${esc(monthName(m, true))} claim</button>`
      : `<button class="btn primary" data-cl="new" data-m="${m}">${icon('plus')}${cur ? 'Continue' : 'New'} claim for ${esc(monthName(m, true))}</button>`;
    return `<div class="ec-page">
      <div class="ec-top"><div><h1>My reimbursements</h1><p>Claims for ${esc(monthName(m))} can be submitted until the 27th${m !== todayStr().slice(0, 7) ? '' : ''}.</p></div>${btn}</div>
      <div class="ec-card">
        ${rows.length || manual.length ? rows.map((c) => `<div class="ec-row" data-cl-row="${c.id}">
            <span class="ec-rm"><b>${esc(monthName(c.month))}</b><small>${c.state === 'none' ? 'You told Finance you had no claims' : c.state === 'draft' ? 'Draft — not submitted yet' : `${plural(itemsOf(c), 'item')} · ${plural(receiptsOf(c).length, 'receipt')}${c.submittedAt ? ' · submitted ' + esc(fmtDay(ymd(new Date(c.submittedAt)))) : ''}`}</small></span>
            <span class="ec-amt">${c.state === 'none' ? '' : 'AED ' + money(c.total || totalOf(c))}</span>
            ${pill(c)}
            <span class="ec-acts">${c.state === 'none' ? '' : `<button class="btn ghost sm" data-cl="open" data-id="${c.id}">Open</button><button class="icon-btn sm" data-cl="pdf" data-id="${c.id}" title="Download PDF">${icon('download')}</button>`}</span>
          </div>`).join('') + manual.map((r) => `<div class="ec-row">
            <span class="ec-rm"><b>${esc(monthName(r.date.slice(0, 7)))}</b><small>Added by Finance${r.invoice ? ' (PDF)' : ''}</small></span>
            <span class="ec-amt">AED ${money(r.amount)}</span>
            <span class="ec-pill" style="background:${STATE.paid[1]};color:${STATE.paid[2]}">Paid · ${esc(fmtDay(r.date))}</span>
            <span class="ec-acts">${r.invoice ? `<button class="btn ghost sm" data-cl="inv" data-id="${r.id}">Open</button>` : ''}</span>
          </div>`).join('') : `<div class="ec-empty">Your claims show up here, with their status: Submitted, HR approved and Paid.</div>`}
      </div>
    </div>`;
  }

  /* ---------- The claim form ---------- */
  const newGroup = () => ({ id: uid(), date: todayStr(), title: '', items: [{ id: uid(), desc: '', amount: '', receipt: null }] });
  function startDraft(c) {
    st.draft = JSON.parse(JSON.stringify(c));
    st.key = c.id + ':' + Date.now();
  }
  function openClaim(id) { const c = byId(id); if (!c) return; ui.claimId = id; startDraft(c); go('claim'); }
  function newClaim(m) {
    if (!canClaim()) return;
    if (closed(m)) { toast(`${monthName(m)} claims closed on the 28th`); return; }
    const ex = mineFor(m);
    if (ex) return openClaim(ex.id);
    const c = { id: idFor(currentUserId, m), userId: currentUserId, month: m, state: 'draft', groups: [newGroup()], total: 0, signature: (me() || {}).signature || null, createdAt: nowISO() };
    ui.claimId = c.id; startDraft(c); st.draft._new = true; go('claim');
  }
  function viewClaim() {
    let c = st.draft && st.draft.id === ui.claimId ? st.draft : null;
    if (!c) { const rec = byId(ui.claimId); if (!rec) return `<div class="ec-page"><div class="ec-empty">This claim isn’t available.</div></div>`; startDraft(rec); c = st.draft; }
    const rec = byId(c.id) || c;
    const edit = c.userId === currentUserId && (c._new || editable(rec));
    const u = userById(c.userId);
    const mine = c.userId === currentUserId;
    const fin = finLevel() === 'admin';   // (a Finance Admin marks their own claim too, like anyone else's)
    const months = [claimMonth(), addMonth(claimMonth(), 1)];
    const groups = c.groups || [];
    const sig = c.signature;
    const saved = (me() || {}).signature;
    return `<div class="ec-page ec-editor" data-key="${esc(st.key)}">
      <div class="ec-crumbs"><button class="btn ghost sm" data-cl="back">${icon('chev-left')}${mine ? 'My reimbursements' : 'Staff reimbursements'}</button>${!edit ? pill(rec) : ''}</div>
      <section class="ec-sheet">
        <header class="ec-head">
          <div class="ec-brand"><img src="logo-tile.png" alt="E11"><div><small>E11 AGENCY</small><h1>Expense claim form</h1></div></div>
          <div class="ec-meta">
            <span>Name</span><b>${esc(fullName(u))}</b>
            <label for="ec-month">Reimbursement month</label>
            ${edit && c._new ? `<span class="ec-selw"><select id="ec-month" class="ec-sel" data-k="month">${months.map((m) => `<option value="${m}" ${m === c.month ? 'selected' : ''}>${esc(monthName(m))}</option>`).join('')}</select>${icon('chev')}</span>` : `<b>${esc(monthName(c.month))}</b>`}
          </div>
        </header>
        <div class="ec-table">
          <div class="ec-th"><span>Date</span><span>Description</span><span class="r">AED</span><span></span></div>
          ${groups.map((g, gi) => `<div class="ec-group">
            <div class="ec-tr title">
              <span>${edit ? `<span class="date-chip set ec-date">${icon('cal')}<span class="date-lbl">${g.date ? esc(fmtDay(g.date)) : 'Pick a date'}</span><input type="date" class="date-in" value="${esc(g.date || '')}" data-k="date" data-g="${g.id}"></span>` : `<b class="ec-d">${g.date ? esc(fmtDay(g.date)) : ''}</b>`}</span>
              <span>${edit ? `<input class="ec-in strong" value="${esc(g.title || '')}" placeholder="Title, e.g. Address Shoot" data-k="title" data-g="${g.id}" aria-label="Title">` : `<b>${esc(g.title || '')}</b>`}</span>
              <span class="r ec-sub" data-sub="${g.id}">${(g.items || []).length > 1 ? money((g.items || []).reduce((a, i) => a + num(i.amount), 0)) : ''}</span>
              <span class="ec-x">${edit && groups.length > 1 ? `<button class="icon-btn sm" data-cl="del-group" data-g="${g.id}" title="Remove this title and its items">${icon('trash')}</button>` : ''}</span>
            </div>
            ${(g.items || []).map((it) => `<div class="ec-tr item">
              <span></span>
              <span class="ec-desc">${edit ? `<input class="ec-in" value="${esc(it.desc || '')}" placeholder="Item, e.g. Salik" data-k="desc" data-g="${g.id}" data-i="${it.id}" aria-label="Item">` : `<span>${esc(it.desc || '')}</span>`}
                ${it.receipt ? `<button type="button" class="ec-rc" data-cl="receipt-open" data-g="${g.id}" data-i="${it.id}" title="${esc(it.receipt.name)}">${icon('clip')}<span>${esc(it.receipt.name)}</span></button>` : ''}</span>
              <span class="r">${edit ? `<input class="ec-in num" value="${esc(it.amount == null ? '' : String(it.amount))}" placeholder="0.00" inputmode="decimal" data-k="amount" data-g="${g.id}" data-i="${it.id}" aria-label="Amount in AED">` : `<span class="ec-num">${it.amount !== '' && it.amount != null ? money(num(it.amount)) : ''}</span>`}</span>
              <span class="ec-x">${edit ? `<button class="icon-btn sm ${it.receipt ? 'on' : ''}" data-cl="${it.receipt ? 'receipt-del' : 'receipt'}" data-g="${g.id}" data-i="${it.id}" title="${it.receipt ? 'Remove receipt' : 'Attach receipt (optional)'}">${icon('clip')}</button>${(g.items || []).length > 1 ? `<button class="icon-btn sm" data-cl="del-item" data-g="${g.id}" data-i="${it.id}" title="Remove item">${icon('x')}</button>` : ''}` : ''}</span>
            </div>`).join('')}
            ${edit ? `<div class="ec-tr add"><span></span><span><button class="btn ghost sm" data-cl="add-item" data-g="${g.id}">${icon('plus')}Add item</button></span></div>` : ''}
          </div>`).join('')}
          ${edit ? `<div class="ec-addg"><button class="btn" data-cl="add-group">${icon('plus')}Add title (new date)</button></div>` : ''}
          <div class="ec-total"><b>TOTAL</b><span class="ec-count">${plural(itemsOf(c), 'item')} · ${plural(receiptsOf(c).length, 'receipt')}</span><b class="r" id="ec-total">${money(totalOf(c))}</b><span>AED</span></div>
        </div>
        <div class="ec-claimer">
          <div><small>CLAIMER DETAILS</small><b>${esc(fullName(u))}</b><span>${esc(roleOf(u))}${c.submittedAt ? ' · submitted ' + esc(fmtDay(ymd(new Date(c.submittedAt)))) : ''}</span></div>
          <div class="ec-sigs"><small>SIGNATURE</small>
            ${edit ? `<div class="ec-sigrow">
              ${saved ? `<button type="button" class="ec-sig ${sig && sig.path === saved.path ? 'on' : ''}" data-cl="sig-saved"><img src="${fileUrlOf(saved)}" alt="Your saved signature" onerror="this.closest('.ec-sig').hidden = true"><span><b>Saved signature</b><small>Used again on each claim</small></span></button>` : ''}
              <button type="button" class="ec-sig" data-cl="sig-upload"><span class="ec-sig-ic">${icon('upload')}</span><span><b>Upload ${saved ? 'a new one' : 'your signature'}</b><small>PNG or JPG</small></span></button>
              <button type="button" class="ec-sig" data-cl="sig-draw"><span class="ec-sig-ic">${icon('edit')}</span><span><b>Draw it</b><small>With the mouse or trackpad</small></span></button>
            </div>` : sig ? `<img class="ec-sig-img" src="${fileUrlOf(sig)}" alt="Signature">` : '<span class="ec-dim">No signature</span>'}
          </div>
        </div>
        ${rec.state === 'approved' || rec.state === 'paid' ? `<div class="ec-finbar">${rec.approvedAt ? `<span>${icon('check')}HR approved ${esc(fmtDay(ymd(new Date(rec.approvedAt))))}${rec.approvedBy ? ' · marked by ' + esc(fullName(userById(rec.approvedBy))) : ''}</span>` : ''}${rec.paidOn ? `<span>${icon('coin')}Paid on ${esc(fmtDay(rec.paidOn))}</span>` : ''}</div>` : ''}
        <footer class="ec-foot">
          <span>${edit ? `Finance is notified when you submit. You can change it until it’s marked HR approved, or until the 27th.` : mine && closed(c.month) && !['approved', 'paid'].includes(rec.state) ? `${esc(monthName(c.month))} claims closed on the 28th.` : ''}</span>
          <span class="ec-btns">
            ${!c._new ? `<button class="btn" data-cl="pdf" data-id="${c.id}">${icon('download')}Download PDF</button>` : ''}
            ${fin && rec.state === 'submitted' ? `<button class="btn" data-cl="approve" data-id="${c.id}">${icon('check')}Mark HR approved</button>` : ''}
            ${fin && ['submitted', 'approved'].includes(rec.state) ? `<button class="btn primary" data-cl="paid" data-id="${c.id}">${icon('coin')}Set paid on…</button>` : ''}
            ${edit ? `<button class="btn" data-cl="save-draft">Save draft</button><button class="btn primary" data-cl="submit">${rec.state === 'submitted' ? 'Save & resubmit' : 'Save & submit'}</button>` : ''}
          </span>
        </footer>
      </section>
    </div>`;
  }

  /* ---------- Finance: claims for a month ---------- */
  function financeSection() {
    if (!finLevel()) return '';
    const m = st.finMonth || claimMonth();
    const admin = finLevel() === 'admin';
    const list = all().filter((c) => c.month === m && ['submitted', 'approved', 'paid'].includes(c.state)).sort((a, b) => String(b.submittedAt || '').localeCompare(String(a.submittedAt || '')));
    const none = all().filter((c) => c.month === m && c.state === 'none');
    const answered = new Set(all().filter((c) => c.month === m).map((c) => c.userId));
    const waiting = db.users.filter((u) => canClaim(u) && !answered.has(u.id)).sort((a, b) => fullName(a).localeCompare(fullName(b)));
    const total = list.reduce((a, c) => a + (c.total || totalOf(c)), 0);
    const months = Array.from({ length: 12 }, (_, i) => addMonth(claimMonth(), -i));
    const open = list.filter((c) => c.state !== 'paid');
    return `<div class="widget fin-add ec-fin">
      <h3>Expense claims — <span class="ec-selw"><select class="ec-sel" data-cl-finmonth>${months.map((x) => `<option value="${x}" ${x === m ? 'selected' : ''}>${esc(monthName(x))}</option>`).join('')}</select>${icon('chev')}</span><span class="spacer"></span>
        ${admin && open.length ? `<button class="btn" data-cl="approve-all">${icon('check')}Mark all HR approved</button><button class="btn primary" data-cl="paid-all">${icon('coin')}Set all paid on…</button>` : ''}</h3>
      <p class="fin-note">${list.length ? `${plural(list.length, 'claim')} · <b>AED ${money(total)}</b>. ` : ''}Submitted from the app by the 27th. ${closed(m) ? 'This month is closed.' : `Open until 27 ${esc(monthName(m, true))}.`}</p>
      ${list.map((c) => { const u = userById(c.userId); return `<div class="fa-row ec-frow" data-claim="${c.id}">
          <span class="fa-name ec-who">${avatarHTML(c.userId, 28)}<span><b>${esc(fullName(u))}</b><small>${plural(itemsOf(c), 'item')} · ${plural(receiptsOf(c).length, 'receipt')} · submitted ${esc(fmtDay(ymd(new Date(c.submittedAt || c.updatedAt))))}</small></span>${c.state === 'submitted' ? `<i class="ec-new" data-tip="Submitted by @${esc(fullName(u))}"></i>` : ''}</span>
          <span class="fx-amt">AED ${money(c.total || totalOf(c))}</span>
          ${pill(c)}
          <span class="ec-acts"><button class="btn ghost xs" data-cl="open" data-id="${c.id}">Open</button><button class="icon-btn sm" data-cl="pdf" data-id="${c.id}" title="Download PDF">${icon('download')}</button>
            ${admin && c.state === 'submitted' ? `<button class="btn xs" data-cl="approve" data-id="${c.id}">HR approved</button>` : ''}
            ${admin && c.state !== 'paid' ? `<button class="btn xs" data-cl="paid" data-id="${c.id}">Paid on…</button>` : ''}</span>
        </div>`; }).join('') || '<div class="fin-empty">No claims submitted for this month yet.</div>'}
      ${none.length ? `<div class="ec-fgroup"><span>No claims</span>${none.map((c) => `<span class="ec-chip">${avatarHTML(c.userId, 18)}${esc(fullName(userById(c.userId)))}</span>`).join('')}</div>` : ''}
      ${waiting.length && !closed(m) ? `<div class="ec-fgroup"><span>Not answered yet</span>${waiting.map((u) => `<span class="ec-chip dim">${avatarHTML(u.id, 18)}${esc(fullName(u))}</span>`).join('')}</div>` : ''}
    </div>`;
  }
  function afterFinanceRender() {
    if (!st.flash) return;
    const id = st.flash; st.flash = null;
    setTimeout(() => {
      const el = document.querySelector(`#content [data-claim="${id}"], #content [data-cl-row="${id}"]`);
      if (!el) return;
      el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      el.classList.remove('flash'); void el.offsetWidth; el.classList.add('flash');
      setTimeout(() => el.classList.remove('flash'), 2600);
    }, 80);
  }
  async function markApproved(ids) {
    const list = ids.map(byId).filter((c) => c && c.state === 'submitted');
    if (!list.length || finLevel() !== 'admin') return;
    list.forEach((c) => { c.state = 'approved'; c.approvedAt = nowISO(); c.approvedBy = currentUserId; save(c); notify(c.userId, c, 'claim-ok', `marked your ${monthName(c.month, true)} expense claim <b>HR approved</b>`); });
    persist(0); renderContent();
    toast(list.length === 1 ? 'Marked HR approved' : `${list.length} claims marked HR approved`);
  }
  async function markPaid(ids) {
    const list = ids.map(byId).filter((c) => c && ['submitted', 'approved'].includes(c.state));
    if (!list.length || finLevel() !== 'admin') return;
    const date = await pickDate(list.length === 1 ? `Paid on — ${fullName(userById(list[0].userId))}` : `Paid on — ${list.length} claims`);
    if (!date) return;
    list.forEach((c) => {
      if (!c.approvedAt) { c.approvedAt = nowISO(); c.approvedBy = currentUserId; }
      c.state = 'paid'; c.paidOn = date; c.paidBy = currentUserId;
      // the payment counts in Finance → Expenses as a staff reimbursement
      let r = (db.finance || []).find((x) => x.id === c.reimbId);
      if (!r) { r = { id: uid(), type: 'reimb', userId: c.userId, claimId: c.id, createdAt: nowISO(), createdBy: currentUserId, invoice: null }; db.finance.push(r); c.reimbId = r.id; }
      r.amount = Math.round(totalOf(c) * 100) / 100; r.date = date;
      save(c);
      notify(c.userId, c, 'claim-paid', `marked your ${monthName(c.month, true)} expense claim <b>paid</b> on ${fmtDay(date)}`);
    });
    persist(0); renderContent();
    toast(list.length === 1 ? 'Marked paid' : `${list.length} claims marked paid`);
  }
  function pickDate(title) {
    return new Promise((resolve) => {
      const root = $('#overlay-root');
      root.innerHTML = `<div class="scrim"><form class="dialog form-dlg" autocomplete="off"><h2>${esc(title)}</h2>
        <label class="dlg-label">Paid on</label><span class="date-chip set fin-date">${icon('cal')}<span class="date-lbl">${esc(fmtDay(todayStr()))}</span><input type="date" class="date-in" name="date" value="${todayStr()}"></span>
        <div class="actions"><button type="button" class="btn" data-r="0">Cancel</button><button type="submit" class="btn primary">Save</button></div></form></div>`;
      const f = $('form', root), d = f.elements.date;
      const close = (v) => { root.innerHTML = ''; resolve(v); };
      d.addEventListener('change', () => { $('.date-lbl', root).textContent = d.value ? fmtDay(d.value) : 'Pick a date'; });
      $('[data-r="0"]', root).addEventListener('click', () => close(null));
      f.addEventListener('submit', (e) => { e.preventDefault(); close(d.value || null); });
    });
  }

  /* ---------- PDF: the sheet drawn on A4 canvases, then joined with the receipts on the server ---------- */
  const loadImg = (src) => new Promise((ok) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => ok(null); i.src = src; });
  async function sheetPages(c) {
    const W = 1240, H = 1754, P = 104, S = W / 794;   // A4 at 150 dpi; S = scale from the 794px design
    const F = '-apple-system, "SF Pro Text", "Segoe UI", Inter, Helvetica, Arial, sans-serif';
    const logo = await loadImg('logo-tile.png');
    const sig = c.signature ? await loadImg(fileUrlOf(c.signature)) : null;
    const u = userById(c.userId);
    const rows = [];
    const rcpt = [];
    (c.groups || []).forEach((g) => {
      rows.push({ t: 'g', date: g.date ? fmtDay(g.date) : '', desc: g.title || '' });
      (g.items || []).forEach((i) => { if (i.receipt) rcpt.push(i.receipt); rows.push({ t: 'i', desc: i.desc || '', amt: i.amount !== '' && i.amount != null ? money(num(i.amount)) : '', rc: i.receipt ? rcpt.length : 0 }); });
    });
    const pages = [];
    let page = null, ctx = null, y = 0, pn = 0;
    const font = (w, px) => { ctx.font = `${w} ${Math.round(px * S)}px ${F}`; };
    const text = (s, x, yy, align = 'left') => { ctx.textAlign = align; ctx.fillText(s, x, yy); };
    const fit = (s, max) => { let t = s; while (t.length > 1 && ctx.measureText(t).width > max) t = t.slice(0, -2); return t === s ? s : t + '…'; };
    const colX = [P, P + 130 * S, W - P - 12 * S];
    function newPage() {
      page = document.createElement('canvas'); page.width = W; page.height = H; ctx = page.getContext('2d');
      ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H); ctx.fillStyle = '#17181b'; ctx.textBaseline = 'alphabetic';
      pn++; y = P;
      if (logo) ctx.drawImage(logo, P, y, 56 * S, 56 * S);
      font(700, 11); ctx.fillStyle = '#6e717a'; text('E11 AGENCY', P + 70 * S, y + 20 * S);
      font(700, 26); ctx.fillStyle = '#17181b'; text('Expense claim form', P + 70 * S, y + 50 * S);
      font(400, 11); ctx.fillStyle = '#6e717a';
      text(pn > 1 ? `Page ${pn}` : `Claim ${c.month}-${(u && initials(fullName(u))) || ''}`, W - P, y + 20 * S, 'right');
      if (c.submittedAt) text('Submitted ' + fmtDay(ymd(new Date(c.submittedAt))), W - P, y + 38 * S, 'right');
      y += 74 * S; ctx.fillStyle = '#17181b'; ctx.fillRect(P, y, W - 2 * P, 2 * S); y += 22 * S;
      if (pn === 1) {
        const bw = (W - 2 * P - 12 * S) / 2;
        [['NAME', fullName(u)], ['REIMBURSEMENT MONTH', monthName(c.month)]].forEach(([l, v], k) => {
          const x = P + k * (bw + 12 * S);
          ctx.strokeStyle = '#e3e3e8'; ctx.lineWidth = 1.5; roundRect(x, y, bw, 58 * S, 8 * S); ctx.stroke();
          font(600, 10.5); ctx.fillStyle = '#6e717a'; text(l, x + 14 * S, y + 22 * S);
          font(600, 14); ctx.fillStyle = '#17181b'; text(v, x + 14 * S, y + 44 * S);
        });
        y += 80 * S; font(700, 10.5); ctx.fillStyle = '#6e717a'; text('CLAIM DETAILS', P, y); y += 12 * S;
      }
      ctx.fillStyle = '#17181b'; ctx.fillRect(P, y, W - 2 * P, 34 * S);
      font(600, 10.5); ctx.fillStyle = '#fff';
      text('DATE', colX[0] + 12 * S, y + 22 * S); text('DESCRIPTION', colX[1], y + 22 * S); text('AED', colX[2], y + 22 * S, 'right');
      y += 34 * S;
      pages.push(page);
    }
    function roundRect(x, yy, w, h, r) { ctx.beginPath(); ctx.moveTo(x + r, yy); ctx.arcTo(x + w, yy, x + w, yy + h, r); ctx.arcTo(x + w, yy + h, x, yy + h, r); ctx.arcTo(x, yy + h, x, yy, r); ctx.arcTo(x, yy, x + w, yy, r); ctx.closePath(); }
    newPage();
    const RH = 34 * S, bottom = H - P - 40 * S;
    rows.forEach((r) => {
      if (y + RH > bottom) newPage();
      ctx.fillStyle = r.t === 'g' ? '#f4f4f7' : '#fff'; ctx.fillRect(P, y, W - 2 * P, RH);
      ctx.fillStyle = '#ececf0'; ctx.fillRect(P, y, W - 2 * P, 1.5);
      ctx.fillStyle = '#17181b';
      if (r.t === 'g') { font(700, 12.5); text(r.date, colX[0] + 12 * S, y + 22 * S); text(fit(r.desc, colX[2] - colX[1] - 120 * S), colX[1], y + 22 * S); }
      else {
        font(400, 12.5); const d = fit(r.desc, colX[2] - colX[1] - 220 * S); text(d, colX[1] + 14 * S, y + 22 * S);
        if (r.rc) { const w = ctx.measureText(d).width; font(500, 10); ctx.fillStyle = '#6e717a'; text(`receipt ${r.rc}`, colX[1] + 24 * S + w, y + 21 * S); ctx.fillStyle = '#17181b'; }
        font(500, 12.5); text(r.amt, colX[2], y + 22 * S, 'right');
      }
      y += RH;
    });
    if (y + 150 * S > bottom) newPage();
    ctx.fillStyle = '#efecff'; ctx.fillRect(P, y, W - 2 * P, 44 * S); ctx.fillStyle = '#5b4bd6'; ctx.fillRect(P, y, W - 2 * P, 2.5 * S);
    font(700, 14); ctx.fillStyle = '#17181b'; text('TOTAL', colX[0] + 12 * S, y + 28 * S);
    font(500, 12); ctx.fillStyle = '#4e5159'; text(`${plural(itemsOf(c), 'item')} · ${plural(rcpt.length, 'receipt')} attached`, colX[1], y + 28 * S);
    font(700, 15); ctx.fillStyle = '#3b2fa0'; text('AED ' + money(totalOf(c)), colX[2], y + 28 * S, 'right');
    y += 80 * S;
    font(700, 10.5); ctx.fillStyle = '#6e717a'; text('CLAIMER DETAILS', P, y); text('SIGNATURE', W / 2, y);
    font(600, 14); ctx.fillStyle = '#17181b'; text(fullName(u), P, y + 26 * S);
    font(400, 12); ctx.fillStyle = '#6e717a'; text(roleOf(u), P, y + 46 * S);
    if (sig) { const h = 54 * S, w = Math.min(220 * S, (sig.width / sig.height) * h); ctx.drawImage(sig, W / 2, y + 8 * S, w, h); }
    ctx.fillStyle = '#17181b'; ctx.fillRect(W / 2, y + 66 * S, 220 * S, 1.5);
    // Finance strip at the foot of the last page
    const fy = H - P - 20 * S;
    ctx.strokeStyle = '#c9c9d1'; ctx.setLineDash([6, 6]); ctx.beginPath(); ctx.moveTo(P, fy - 34 * S); ctx.lineTo(W - P, fy - 34 * S); ctx.stroke(); ctx.setLineDash([]);
    const cw = (W - 2 * P) / 3;
    [['For Finance use', c.submittedAt ? 'Received ' + fmtDay(ymd(new Date(c.submittedAt))) : ''], ['HR approved', c.approvedAt ? fmtDay(ymd(new Date(c.approvedAt))) : '________________'], ['Paid on', c.paidOn ? fmtDay(c.paidOn) : '____ / ____ / ________']].forEach(([l, v], k) => {
      font(700, 11.5); ctx.fillStyle = '#17181b'; text(l, P + k * cw, fy - 12 * S);
      font(400, 11); ctx.fillStyle = '#6e717a'; text(v, P + k * cw, fy + 6 * S);
    });
    font(400, 10); ctx.fillStyle = '#8a8d96';
    text(rcpt.length ? `Receipts follow on the next pages · Generated by E11 Console` : 'Generated by E11 Console', W / 2, H - P / 2, 'center');
    return { pages: pages.map((p) => p.toDataURL('image/jpeg', 0.92).split(',')[1]), receipts: rcpt.map((r) => r.path) };
  }
  async function downloadPdf(id) {
    const c = id === (st.draft && st.draft.id) && !byId(id) ? st.draft : byId(id);
    if (!c) return;
    toast('Preparing the PDF…');
    try {
      const { pages, receipts } = await sheetPages(c);
      const name = `Expense claim — ${fullName(userById(c.userId))} — ${monthName(c.month)}.pdf`.replace(/[\\/:*?"<>|]/g, '-');
      const r = await Host.call('claimPdf', { userId: c.userId, month: c.month, name, pages, receipts });
      await Host.call('revealPath', { path: r.path });
    } catch (e) { toast('Could not make the PDF: ' + e.message); }
  }

  /* ---------- Saving the form ---------- */
  function readDraft() { return st.draft; }
  function validate(c) {
    const items = (c.groups || []).flatMap((g) => g.items || []);
    if (!items.some((i) => num(i.amount) > 0)) return 'Add at least one item with an amount';
    for (const g of c.groups || []) {
      if (!g.date) return 'Pick a date for every title';
      if (!(g.title || '').trim()) return 'Give every date a title, e.g. Address Shoot';
      for (const i of g.items || []) {
        if (!(i.desc || '').trim() && num(i.amount)) return `Describe the AED ${money(num(i.amount))} item under “${g.title}”`;
        if (String(i.amount || '').trim() && !(num(i.amount) >= 0)) return 'Amounts are numbers only';
      }
    }
    if (!c.signature) return 'Add your signature';
    return null;
  }
  function clean(c) {
    const out = { ...c }; delete out._new;
    out.groups = (c.groups || []).map((g) => ({ ...g, title: (g.title || '').trim(), items: (g.items || []).filter((i) => (i.desc || '').trim() || num(i.amount) || i.receipt).map((i) => ({ ...i, desc: (i.desc || '').trim(), amount: String(i.amount || '').trim() ? Math.round(num(i.amount) * 100) / 100 : '' })) })).filter((g) => g.items.length || g.title);
    return out;
  }
  function submit(asDraft) {
    const d = readDraft();
    if (!d) return;
    if (closed(d.month)) { toast(`${monthName(d.month)} claims closed on the 28th`); return; }
    const c = clean(d);
    if (!asDraft) { const err = validate(c); if (err) { toast(err); return; } }
    const prev = byId(c.id);
    const was = prev ? prev.state : null;
    if (!asDraft) { c.state = 'submitted'; c.submittedAt = nowISO(); }
    else if (!prev || prev.state === 'draft' || prev.state === 'none') c.state = 'draft';
    save(c);
    if (!asDraft) {
      finUsers().forEach((u) => notify(u.id, c, 'claim', `${was === 'submitted' ? 'updated' : 'submitted'} their ${monthName(c.month, true)} expense claim`));
      persist(0);
    }
    st.draft = null; st.flash = c.id;
    go('claims');
    toast(asDraft ? 'Draft saved — submit it by the 27th' : `Submitted — Finance has been told (AED ${money(c.total)})`);
  }

  /* ---------- Signature ---------- */
  async function uploadSig(blobOrPick) {
    const u = me();
    let f = null;
    if (blobOrPick) f = (await Host.call('uploadBlob', { blob: blobOrPick, name: 'signature.png', dest: `Claims/${u.id}/signature` })).file;
    else { const r = await Host.call('pickAttachments', { dest: `Claims/${u.id}/signature`, accept: 'image/*', single: true }); f = (r.files || [])[0] || null; }
    if (!f) return;
    u.signature = { id: f.id, name: f.name, path: f.path, size: f.size };
    st.draft.signature = u.signature;
    persist(0); redraw();
  }
  function drawSig() {
    const root = $('#overlay-root');
    root.innerHTML = `<div class="scrim"><div class="dialog ec-draw"><h2>Draw your signature</h2><p class="ec-dim">Use the mouse or trackpad. It’s saved for your next claims.</p>
      <canvas width="1000" height="320" aria-label="Signature pad"></canvas>
      <div class="actions"><button type="button" class="btn" data-x="clear">Clear</button><span class="spacer"></span><button type="button" class="btn" data-x="cancel">Cancel</button><button type="button" class="btn primary" data-x="use">Use this signature</button></div></div></div>`;
    const cv = $('canvas', root), ctx = cv.getContext('2d');
    ctx.lineWidth = 5; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = '#1b2a6b';
    let drawing = false, any = false;
    const pos = (e) => { const r = cv.getBoundingClientRect(); return [(e.clientX - r.left) * (cv.width / r.width), (e.clientY - r.top) * (cv.height / r.height)]; };
    cv.addEventListener('pointerdown', (e) => { drawing = true; any = true; cv.setPointerCapture(e.pointerId); ctx.beginPath(); ctx.moveTo(...pos(e)); });
    cv.addEventListener('pointermove', (e) => { if (!drawing) return; ctx.lineTo(...pos(e)); ctx.stroke(); });
    cv.addEventListener('pointerup', () => { drawing = false; });
    $('.ec-draw', root).addEventListener('click', async (e) => {
      const x = e.target.closest('[data-x]'); if (!x) return;
      if (x.dataset.x === 'clear') { ctx.clearRect(0, 0, cv.width, cv.height); any = false; return; }
      if (x.dataset.x === 'cancel') { root.innerHTML = ''; return; }
      if (!any) { toast('Draw your signature first'); return; }
      const blob = await new Promise((ok) => cv.toBlob(ok, 'image/png'));
      root.innerHTML = '';
      try { await uploadSig(blob); } catch (err) { toast('Could not save the signature: ' + err.message); }
    });
  }

  /* ---------- Reminder pop-up (20th–27th, from 11:30 AM, once a day) ---------- */
  function reminderDue() {
    const u = me();
    if (!canClaim(u) || phone() || !Host.isServer) return false;
    // automated browser tests don't get the pop-up unless they ask for it
    try { if (navigator.webdriver && localStorage.getItem('e11-claim-remind') !== '1') return false; } catch (e) { /* storage blocked */ }
    const now = new Date(), d = now.getDate();
    if (d < 20 || d > 27 || now.getHours() * 60 + now.getMinutes() < 11 * 60 + 30) return false;
    const m = todayStr().slice(0, 7);
    const c = mineFor(m);
    if (c && c.state !== 'draft') return false;
    return (u.prefs || {}).claimNag !== todayStr();
  }
  function tick() {
    if (!db || !currentUserId || !reminderDue() || $('#overlay-root').children.length || $('.ec-remind') || $('.an-pop')) return;
    const u = me(), m = todayStr().slice(0, 7), left = 27 - new Date().getDate();
    u.prefs = u.prefs || {}; u.prefs.claimNag = todayStr(); persist(0);
    if (!document.hasFocus()) Host.call('notify', { title: 'Expense claims', body: `Your ${monthName(m, true)} claim is due by the 27th`, sound: 'Glass' }).catch(() => {});
    const el = document.createElement('div');
    el.className = 'ec-remind';
    el.innerHTML = `<div class="ec-rbox" role="dialog" aria-labelledby="ec-rt">
      <div class="ec-rtop"><img src="logo-tile.png" alt="E11"><div><small>EXPENSE CLAIMS · ${esc(monthName(m).toUpperCase())}</small><h2 id="ec-rt">Any expenses to claim this month?</h2>
        <p>Submit your ${esc(monthName(m, true))} claim by <b>27 ${esc(monthName(m, true))}</b>. Claims can’t be submitted from the 28th.</p></div></div>
      <div class="ec-rdays">${[20, 21, 22, 23, 24, 25, 26, 27].map((n) => `<i class="${n < new Date().getDate() ? 'past' : n === new Date().getDate() ? 'today' : ''}">${n}</i>`).join('')}<span>Daily reminder · ${left ? `${plural(left, 'more day')} to submit` : 'last day to submit'}</span></div>
      <div class="ec-rbtns"><button class="btn primary" data-r="submit">Submit now</button><button class="btn" data-r="offline">Submitted offline</button><button class="btn" data-r="none">I don’t have claims</button></div>
      <button class="ec-rlater" data-r="later">Remind me tomorrow</button>
    </div>`;
    document.body.appendChild(el);
    el.addEventListener('click', (e) => {
      const b = e.target.closest('[data-r]'); if (!b) return;
      el.remove();
      const r = b.dataset.r;
      if (r === 'submit') return newClaim(m);
      if (r === 'later') return;
      const c = mineFor(m) || { id: idFor(currentUserId, m), userId: currentUserId, month: m, groups: [], total: 0, signature: null, createdAt: nowISO() };
      c.state = r === 'none' ? 'none' : 'offline';
      save(c);
      if (r === 'none') toast(`Got it — no claims for ${monthName(m, true)}. No more reminders this month.`);
      else toast('Got it — no more reminders this month.');
      if (ui.view === 'claims') renderContent();
    });
  }

  /* ---------- Pages ---------- */
  function title() {
    return `<div class="page-icon" style="background:#2b2650;color:#c9c0ff">${icon('coin')}</div><div class="page-title">${ui.view === 'claim' ? 'Expense claim' : 'My reimbursements'}</div>`;
  }
  function render(c) {
    if (phone()) { c.innerHTML = `<div class="ec-page"><div class="ec-empty big">${icon('coin')}<b>Expense claims are on the computer</b>Open E11 Console on a computer or the Mac app to fill in your claim.</div></div>`; return; }
    if (ui.view === 'claim') {
      // keep the form as it is while typing (other people's changes don't redraw it)
      const ed = c.querySelector('.ec-editor');
      if (ed && st.draft && ed.dataset.key === st.key && !st.redraw) return;
      st.redraw = false;
      c.innerHTML = viewClaim();
      return;
    }
    c.innerHTML = viewList();
    afterFinanceRender();
  }
  function redraw() { st.redraw = true; const c = $('#content'); const top = c.scrollTop; renderContent(); c.scrollTop = top; }

  /* ---------- Inbox ---------- */
  function openNotif(n) {
    if (phone()) { toast('Expense claims open on the computer'); return; }
    if (n.kind === 'claim') {
      if (!finLevel()) return;
      st.finMonth = n.month || claimMonth(); st.flash = n.claimId;
      return go('fin-reimb');
    }
    st.flash = n.claimId;
    go('claims');
  }

  /* ---------- Clicks and typing ---------- */
  function group(gid) { return (st.draft.groups || []).find((g) => g.id === gid); }
  function item(gid, iid) { const g = group(gid); return g && (g.items || []).find((i) => i.id === iid); }
  function updateTotals() {
    const d = st.draft; if (!d) return;
    const t = $('#ec-total'); if (t) t.textContent = money(totalOf(d));
    (d.groups || []).forEach((g) => { const s = document.querySelector(`[data-sub="${g.id}"]`); if (s) s.textContent = (g.items || []).length > 1 ? money((g.items || []).reduce((a, i) => a + num(i.amount), 0)) : ''; });
    const n = $('.ec-count'); if (n) n.textContent = `${plural(itemsOf(d), 'item')} · ${plural(receiptsOf(d).length, 'receipt')}`;
  }
  document.addEventListener('input', (e) => {
    const el = e.target;
    if (!el.dataset || !el.dataset.k || !el.closest('.ec-editor') || !st.draft) return;
    const k = el.dataset.k;
    if (k === 'title') { const g = group(el.dataset.g); if (g) g.title = el.value; }
    else if (k === 'desc' || k === 'amount') { const i = item(el.dataset.g, el.dataset.i); if (i) i[k === 'desc' ? 'desc' : 'amount'] = el.value; if (k === 'amount') updateTotals(); }
  });
  document.addEventListener('change', (e) => {
    const el = e.target;
    if (el.matches && el.matches('[data-cl-finmonth]')) { st.finMonth = el.value; renderContent(); return; }
    if (!el.dataset || !el.dataset.k || !el.closest('.ec-editor') || !st.draft) return;
    if (el.dataset.k === 'date') { const g = group(el.dataset.g); if (g) g.date = el.value; const l = el.parentElement.querySelector('.date-lbl'); if (l) l.textContent = el.value ? fmtDay(el.value) : 'Pick a date'; }
    if (el.dataset.k === 'month') {
      const m = el.value;
      if (mineFor(m)) { openClaim(mineFor(m).id); return; }
      st.draft.month = m; st.draft.id = idFor(currentUserId, m); ui.claimId = st.draft.id;
    }
  });
  document.addEventListener('click', async (e) => {
    const el = e.target.closest('[data-cl]');
    if (!el || !db) return;
    const a = el.dataset.cl, d = st.draft;
    e.preventDefault();
    switch (a) {
      case 'new': return newClaim(el.dataset.m || claimMonth());
      case 'open': return openClaim(el.dataset.id);
      case 'back': st.draft = null; return go(byId(ui.claimId) && byId(ui.claimId).userId !== currentUserId ? 'fin-reimb' : 'claims');
      case 'pdf': return downloadPdf(el.dataset.id);
      case 'inv': { const r = (db.finance || []).find((x) => x.id === el.dataset.id); if (r && r.invoice) previewFile(r.invoice); return; }
      case 'approve': return markApproved([el.dataset.id]);
      case 'paid': return markPaid([el.dataset.id]);
      case 'approve-all': { const m = st.finMonth || claimMonth(); return markApproved(all().filter((c) => c.month === m && c.state === 'submitted').map((c) => c.id)); }
      case 'paid-all': { const m = st.finMonth || claimMonth(); return markPaid(all().filter((c) => c.month === m && ['submitted', 'approved'].includes(c.state)).map((c) => c.id)); }
      case 'save-draft': return submit(true);
      case 'submit': return submit(false);
      case 'sig-saved': if (d) { d.signature = me().signature; redraw(); } return;
      case 'sig-upload': try { await uploadSig(null); } catch (err) { toast('Could not upload: ' + err.message); } return;
      case 'sig-draw': return drawSig();
      default: break;
    }
    if (!d) return;
    if (a === 'add-group') { d.groups.push(newGroup()); redraw(); setTimeout(() => { const ins = $$('.ec-editor input[data-k="title"]'); const last = ins[ins.length - 1]; if (last) last.focus(); }, 30); return; }
    if (a === 'del-group') { d.groups = d.groups.filter((g) => g.id !== el.dataset.g); return redraw(); }
    const g = group(el.dataset.g);
    if (!g) return;
    if (a === 'add-item') { const it = { id: uid(), desc: '', amount: '', receipt: null }; g.items.push(it); redraw(); setTimeout(() => { const x = $(`.ec-editor input[data-i="${it.id}"][data-k="desc"]`); if (x) x.focus(); }, 30); return; }
    const it = item(el.dataset.g, el.dataset.i);
    if (!it) return;
    if (a === 'del-item') { g.items = g.items.filter((x) => x.id !== it.id); return redraw(); }
    if (a === 'receipt-del') { it.receipt = null; return redraw(); }
    if (a === 'receipt-open') { if (it.receipt) previewFile(it.receipt); return; }
    if (a === 'receipt') {
      try {
        const r = await Host.call('pickAttachments', { dest: `Claims/${d.userId}/${d.month}`, accept: 'image/*,.pdf,.heic', single: true });
        const f = (r.files || [])[0];
        if (f) { it.receipt = { id: f.id, name: f.name, path: f.path, size: f.size, addedAt: nowISO() }; redraw(); }
      } catch (err) { toast('Could not attach the receipt: ' + err.message); }
    }
  });

  return { owns, render, title, financeSection, afterFinanceRender, openNotif, tick, claimMonth, newClaim, st, byId, sheetPages, all, totalOf, itemsOf, markApproved, markPaid, open: openClaim };
})();
