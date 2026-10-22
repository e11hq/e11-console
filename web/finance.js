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
  const ADMIN_ONLY = ['fin-subs', 'fin-reimb', 'fin-extra'];
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
      np.innerHTML = `<div class="fp-card"><div class="fp-ic">${icon('coin')}</div><h2>Finance is on the computer</h2><p>Open ${esc(location.host)} on a computer, or the E11 Console Mac app, to see the Finance dashboard, projects and expenses.</p><button class="btn" data-fin-signout>Sign out</button></div>`;
      np.addEventListener('click', (e) => { if (e.target.closest('[data-fin-signout]')) signOut(); });
      document.body.appendChild(np);
    }
    if (fin) {
      const nav = document.createElement('nav');
      nav.className = 'nav fin-nav';
      nav.innerHTML = [['fin-dash', 'home', 'Dashboard'], ['fin-projects', 'folder', 'Projects'], ['fin-expenses', 'coin', 'Expenses']]
        .map(([v, ic, l]) => `<a class="nav-item" data-nav="${v}">${icon(ic)}${l}</a>`).join('');
      const head = $('#sidebar .sb-head');
      head.parentNode.insertBefore(nav, head);
    } else if (canLook()) {
      const a = document.createElement('a');
      a.className = 'nav-item fin-admin-nav';
      a.dataset.nav = 'fin-dash';
      a.title = 'Finance — task Finance status and expense records';
      a.innerHTML = `${icon('coin')}Finance`;
      const tr = $('#nav-trash');
      tr.parentNode.insertBefore(a, tr);
    }
  }
  function paintNav() {
    $$('.fin-nav .nav-item').forEach((a) => a.classList.toggle('active', ui.view === a.dataset.nav || (a.dataset.nav === 'fin-expenses' && ui.view === 'fin-list')));
    const an = $('.fin-admin-nav'); if (an) an.classList.toggle('active', owns(ui.view));
  }
  // The Finance Admin's pages, in the name menu (Finance-only people, and anyone given Finance Admin access)
  const addItems = () => (isFinAdmin() ? ['-',
    { label: 'Add subscriptions', icon: 'cal', run: () => go('fin-subs') },
    { label: 'Add Staff Reimbursements', icon: 'users', run: () => go('fin-reimb') },
    { label: 'Add Extra Expense', icon: 'coin', run: () => go('fin-extra') }] : []);
  function meMenu(anchor) {
    showMenu(anchor, [
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
    const t = { 'fin-dash': 'Dashboard', 'fin-projects': 'Projects', 'fin-expenses': 'Expenses', 'fin-list': 'All transactions', 'fin-subs': 'Subscriptions', 'fin-reimb': 'Staff reimbursements', 'fin-extra': 'Extra expenses' }[ui.view] || 'Finance';
    const tabs = !isFinUser() && ['fin-dash', 'fin-projects', 'fin-expenses'].includes(ui.view)
      ? `<div class="tabs">${[['fin-dash', 'Dashboard'], ['fin-projects', 'Projects'], ['fin-expenses', 'Expenses']].map(([v, l]) => `<button class="tab ${ui.view === v ? 'active' : ''}" data-fin-go="${v}">${l}</button>`).join('')}</div>` : '';
    return `<div class="page-icon" style="background:#173a2c;color:#3ddc97">${icon('coin')}</div><div class="page-title">${isFinUser() ? t : 'Finance'}</div>${tabs}`;
  }

  /* ---------- Pages ---------- */
  function render(c) {
    if (!canLook() || (ADMIN_ONLY.includes(ui.view) && !isFinAdmin())) { ui.view = isFinUser() ? 'fin-dash' : 'home'; renderAll(); return; }
    const v = ui.view;
    c.innerHTML = `<div class="fin">${v === 'fin-dash' ? dash() : v === 'fin-projects' ? projects() : v === 'fin-expenses' ? expenses() : v === 'fin-list' ? list() : v === 'fin-subs' ? subsPage() : v === 'fin-reimb' ? reimbPage() : extraPage()}</div>`;
  }
  const renderAll = () => { renderTitle(); renderSidebar(); renderContent(); };

  function dash() {
    const h = new Date().getHours();
    const greet = h < 5 ? 'Good evening' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    const ts = finTasks();
    const count = (s) => ts.filter((t) => t.finance === s).length;
    const months = lastMonths(6);
    const g = st.graph;
    const vals = months.map((m) => ts.filter((t) => t.finance === g && String(finAt(t)).slice(0, 7) === m).length);
    const max = Math.max(1, ...vals);
    const inv = (m) => ts.filter((t) => t.finance === 'Invoiced' && String(finAt(t)).slice(0, 7) === m).length;
    const now = inv(thisMonth()), prev = inv(addMonths(thisMonth(), -1));
    const pct = prev ? Math.round(((now - prev) / prev) * 100) : now ? 100 : 0;
    const up = now >= prev;
    return `<div class="home fin-home">
      <div class="home-date">${new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })}</div>
      <div class="home-greet">${greet}, ${esc(fullName(me()).split(' ')[0])}</div>
      <div class="fin-stats">${STATUSES.map((s) => `<button class="fin-stat" data-fin-status="${esc(s)}" style="--c:${FINANCE[s]}"><span class="n">${count(s)}</span><span class="l">${esc(s)}</span></button>`).join('')}</div>
      <div class="fin-grid">
        <div class="widget fin-graph">
          <h3>Monthly Graph<span class="spacer"></span></h3>
          <div class="fin-tabs">${STATUSES.map((s) => `<button class="${g === s ? 'on' : ''}" data-fin-graph="${esc(s)}" style="--c:${FINANCE[s]}">${esc(s)}</button>`).join('')}</div>
          <div class="fin-bars" style="--c:${FINANCE[g]}">${months.map((m, i) => `<div class="fin-bar" title="${esc(monthName(m, true))}: ${vals[i]} task${vals[i] === 1 ? '' : 's'}"><span class="v">${vals[i]}</span><i style="height:${Math.round((vals[i] / max) * 100)}%"></i><span class="m">${monthName(m)}</span></div>`).join('')}</div>
          <div class="fin-note">Tasks marked “${esc(g)}” in each of the last 6 months</div>
        </div>
        <div class="widget fin-over">
          <h3>Overview</h3>
          <div class="fo-n">${count('Invoiced')}</div>
          <div class="fo-l">invoiced tasks in total</div>
          <div class="fo-month"><b>${now}</b> invoiced in ${esc(monthName(thisMonth(), true).split(' ')[0])}</div>
          <div class="fo-chg ${up ? 'up' : 'down'}">${icon(up ? 'chev-up' : 'chev')}<b>${Math.abs(pct)}%</b> vs ${esc(monthName(addMonths(thisMonth(), -1), true).split(' ')[0])} (${prev})</div>
        </div>
      </div></div>`;
  }

  function projects() {
    const f = st.proj;
    const ts = finTasks().filter((t) => (f === 'all' ? true : f === 'none' ? !t.finance : t.finance === f));
    const can = isManager(); // only Account Managers and Admins change a task's Finance status
    const groups = db.projects.slice().sort(byOrder).map((p) => ({ p, list: ts.filter((t) => t.projectId === p.id) })).filter((g) => g.list.length);
    const none = ts.filter((t) => !t.projectId || !proj(t.projectId));
    if (none.length) groups.push({ p: { id: '_none', name: 'No project', color: '#666' }, list: none });
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
      <span class="fx-inv">${x.invoice ? `<button class="btn ghost xs" data-fin-inv="${esc(x.id)}">${icon('clip')}Invoice</button>` : '<span class="fl-empty">–</span>'}</span>
      ${admin ? `<span class="fx-x">${admin(x)}</span>` : ''}
    </div>`;
  function cashflow(months) {
    const tx = transactions();
    const tot = months.map((m) => tx.filter((x) => x.date.slice(0, 7) === m).reduce((a, x) => a + x.amount, 0));
    // the line is drawn in a 0–100 box that stretches to fit; dots, hover areas and labels are HTML on top
    const max = Math.max(1, ...tot) * 1.15, n = months.length;
    const X = (i) => 4 + (i * 92) / (n - 1), Y = (v) => 92 - (v / max) * 82;
    const line = tot.map((v, i) => `${i ? 'L' : 'M'}${X(i).toFixed(2)},${Y(v).toFixed(2)}`).join(' ');
    const area = `${line} L${X(n - 1).toFixed(2)},100 L${X(0).toFixed(2)},100 Z`;
    const step = 92 / (n - 1);
    return `<div class="fin-cash">
        <div class="fc-plot">
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" class="fc-svg">
            <defs><linearGradient id="fcg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--accent)" stop-opacity=".4"/><stop offset="1" stop-color="var(--accent)" stop-opacity="0"/></linearGradient></defs>
            <path d="${area}" fill="url(#fcg)"/><path d="${line}" fill="none" stroke="var(--accent)" stroke-width="2" vector-effect="non-scaling-stroke"/>
          </svg>
          ${tot.map((v, i) => `<div class="fc-hit" style="left:${Math.max(0, X(i) - step / 2)}%;width:${step}%">
              <i class="fc-guide" style="left:${((X(i) - Math.max(0, X(i) - step / 2)) / step) * 100}%;top:${Y(v)}%"></i>
              <i class="fc-dot" style="left:${((X(i) - Math.max(0, X(i) - step / 2)) / step) * 100}%;top:${Y(v)}%"></i>
              <div class="fc-tip ${i === 0 ? 'l' : i === n - 1 ? 'r' : ''}" style="left:${((X(i) - Math.max(0, X(i) - step / 2)) / step) * 100}%;top:${Y(v)}%"><b>${esc(monthName(months[i], true))}</b>${esc(aed(v))}</div>
            </div>`).join('')}
        </div>
        <div class="fc-months">${months.map((m, i) => `<span style="left:${X(i)}%">${monthName(m)}</span>`).join('')}</div>
      </div>`;
  }
  function expenses() {
    const m = thisMonth();
    const tx = transactions().filter((x) => x.date.slice(0, 7) === m);
    const sum = (k) => tx.filter((x) => !k || x.kind === k).reduce((a, x) => a + x.amount, 0);
    const total = sum();
    const parts = [['expense', 'Big expenses'], ['sub', 'Payments'], ['reimb', 'Reimbursements']];
    return `
      <div class="fin-grid">
        <div class="widget fe-over">
          <h3>${esc(monthName(m, true))} spending</h3>
          <div class="fo-n">${aed(total)}</div>
          <div class="fe-stack">${parts.map(([k]) => `<i style="width:${total ? (sum(k) / total) * 100 : 0}%;background:${KIND_C[k]}"></i>`).join('')}</div>
          <div class="fe-parts">${parts.map(([k, l]) => `<div class="fe-part"><span class="dot" style="background:${KIND_C[k]}"></span><span class="l">${l}<small>${tx.filter((x) => x.kind === k).length} this month</small></span><b>${aed(sum(k))}</b><span class="pc">${total ? Math.round((sum(k) / total) * 100) : 0}%</span><button class="btn ghost xs" data-fin-all="${k}">View all</button></div>`).join('')}</div>
        </div>
        <div class="widget fe-cash"><h3>Cash flow<span class="spacer"></span><small class="fin-note">Money spent, last 6 months</small></h3>${cashflow(lastMonths(6))}</div>
      </div>
      <div class="widget fe-recent">
        <h3>Recent transactions<span class="spacer"></span><button class="btn ghost" data-fin-all="all">View all ${icon('arrow')}</button></h3>
        ${transactions().slice(0, 5).map((x) => txRow(x)).join('') || '<div class="fin-empty">No transactions yet.</div>'}
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
          <span class="fa-name"><b>${esc(s.name)}</b><small>Every month on the ${ordinal(Number(s.day) || 1)} · next ${esc(fmtDay(nextDate(s)))}</small></span>
          <span class="fx-amt">${aed(s.amount)}</span>
          <span class="fa-inv">${(s.invoices || {})[m] ? `<button class="btn ghost xs" data-fin-subinv="${s.id}">${icon('clip')}${esc(monthName(m))} invoice</button>` : `<button class="btn ghost xs" data-fin-subadd="${s.id}">${icon('plus')}${esc(monthName(m))} invoice</button>`}</span>
          <button class="icon-btn sm" data-fin-del="${s.id}" title="Remove subscription (past months stay in the records)">${icon('trash')}</button>
        </div>`).join('') || '<div class="fin-empty">No subscriptions yet.</div>'}
      ${ended.length ? `<div class="fa-ended"><div class="fa-eh">Ended</div>${ended.map((s) => `<div class="fa-row ended"><span class="fa-name"><b>${esc(s.name)}</b><small>Ended ${esc(fmtDay(ymd(new Date(s.endedAt))))}</small></span><span class="fx-amt">${aed(s.amount)}</span></div>`).join('')}</div>` : ''}
    </div>`;
  }
  const ordinal = (n) => n + (n % 10 === 1 && n !== 11 ? 'st' : n % 10 === 2 && n !== 12 ? 'nd' : n % 10 === 3 && n !== 13 ? 'rd' : 'th');
  function monthRecords(type, label, btn) {
    const m = thisMonth();
    const list = recs(type).filter((r) => String(r.date || '').slice(0, 7) === m).sort((a, b) => b.date.localeCompare(a.date));
    const total = list.reduce((a, r) => a + (Number(r.amount) || 0), 0);
    return `<div class="widget fin-add">
      <h3>${label} — ${esc(monthName(m, true))}<span class="spacer"></span><button class="btn primary" data-fin-new="${type}">${icon('plus')}${btn}</button></h3>
      <p class="fin-note">${list.length ? `${list.length} this month · <b>${aed(total)}</b>. ` : ''}Earlier months are under Expenses → View all.</p>
      ${list.map((r) => `<div class="fa-row">
          <span class="fa-name"><b>${esc(type === 'reimb' ? personName(r) : r.name)}</b><small>Paid ${esc(fmtDay(r.date))}</small></span>
          <span class="fx-amt">${aed(r.amount)}</span>
          <span class="fa-inv">${r.invoice ? `<button class="btn ghost xs" data-fin-rinv="${r.id}">${icon('clip')}Invoice</button>` : '<span class="fl-empty">No invoice</span>'}</span>
          <button class="icon-btn sm" data-fin-del="${r.id}" title="Remove">${icon('trash')}</button>
        </div>`).join('') || '<div class="fin-empty">Nothing added this month.</div>'}
    </div>`;
  }
  const reimbPage = () => monthRecords('reimb', 'Staff reimbursements', 'Add reimbursement');
  const extraPage = () => monthRecords('expense', 'Extra expenses', 'Add expense');

  /* ---------- Add form (pop-up) ---------- */
  async function pickInvoice(folder) {
    const r = await Host.call('pickAttachments', { dest: 'Finance/' + folder + '/' + thisMonth() });
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
  async function subInvoice(id) {
    const s = recs('sub').find((x) => x.id === id);
    if (!s || !isFinAdmin()) return;
    try {
      const f = await pickInvoice('Subscriptions');
      if (!f) return;
      s.invoices = { ...(s.invoices || {}), [thisMonth()]: f };
      persist(0); renderContent();
    } catch (e) { toast('Could not attach the invoice: ' + e.message); }
  }
  const openFile = (f) => { if (f) previewFile(f); };

  /* ---------- Clicks ---------- */
  document.addEventListener('click', (e) => {
    if (!owns(ui.view) && !e.target.closest('[data-fin-go]')) return;
    const el = e.target.closest('[data-fin-go],[data-fin-status],[data-fin-graph],[data-fin-proj],[data-fin-toggle],[data-fin-set],[data-fin-all],[data-fin-back],[data-fin-type],[data-fin-page],[data-fin-inv],[data-fin-new],[data-fin-del],[data-fin-subinv],[data-fin-subadd],[data-fin-rinv]');
    if (!el) return;
    e.stopPropagation();
    const d = el.dataset;
    if (d.finGo) return go(d.finGo);
    if (d.finStatus) { st.proj = d.finStatus; return go('fin-projects'); }
    if (d.finGraph) { st.graph = d.finGraph; return renderContent(); }
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
    if (d.finSubadd) return subInvoice(d.finSubadd);
    if (d.finSubinv) { const s = recs('sub').find((x) => x.id === d.finSubinv); return openFile(s && (s.invoices || {})[thisMonth()]); }
    if (d.finRinv) { const r = (db.finance || []).find((x) => x.id === d.finRinv); return openFile(r && r.invoice); }
  }, true);
  document.addEventListener('change', (e) => {
    if (e.target.matches && e.target.matches('[data-fin-month]')) { st.list.month = e.target.value; st.list.page = 0; renderContent(); }
  });

  return { owns, init, paintNav, meMenu, addItems, canLook, title, render, transactions, subPayments, aed, st };
})();
