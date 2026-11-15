/* ================= Office Admin: Home =================
   An Office Admin (e.g. Arsal) has Admin rights without the task app. Their Home (agreed from the mockup "E11 Console —
   Office Admin Home"): four tiles, then three boxes of the same height down to the bottom of the window — the latest in
   Client Assets (search, client chips, a file picked: Open Folder · Download), the Inbox (opens on Unread, or All when
   nothing is unread) and, with Finance access, a month's expense claims (the last 12; Need HR approval / HR approved and paid,
   HR Approve / Paid On…, ••• for all of them) and expenses. Mac page by page, Home (Haris 2026-11-15): the iPhone's choices
   here too, and right-click on a claim or a file. */
const OfficeHome = (() => {
  const st = { q: '', client: 'all', sel: null, ibTab: null, finTab: 'claims', focus: null, month: null };   // (month: Finance's, the last 12)
  const KIND = { sub: 'Subscription', reimb: 'Reimbursement', expense: 'Office expense' };
  const CLAIM_PILL = { submitted: ['Submitted', 'oh-p-sub'], approved: ['HR approved', 'oh-p-ok'], paid: ['Paid', 'oh-p-paid'] };
  const fin = () => typeof finLevel === 'function' && !!finLevel(me());
  const finAdmin = () => typeof finLevel === 'function' && finLevel(me()) === 'admin';
  const monthName = (m) => { const [y, mo] = m.split('-').map(Number); return new Date(y, mo - 1, 1).toLocaleDateString('en-US', { month: 'long' }); };
  const short = (iso) => { const d = new Date(iso); const days = Math.floor((Date.now() - d) / 86400000); return days < 7 ? timeAgo(iso) : d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); };
  const extOf = (n) => (String(n).split('.').pop() || 'file').slice(0, 4).toUpperCase();

  function allFiles() {
    const out = [];
    clientsSorted().forEach((c) => (c.folders || []).forEach((f) => (f.files || []).forEach((a) => out.push({ c, f, a }))));
    return out.sort((x, y) => String(y.a.addedAt || '').localeCompare(String(x.a.addedAt || '')));
  }
  function filesHTML() {
    const q = st.q.trim();
    // the same search as the Client Assets page: every word counts, client / folder / file names, file types
    // ("ford logo png", "pdf", "font"), and small typos when nothing matches exactly
    let list, loose = false;
    if (q) {
      const scope = st.client === 'all' ? null : clientsSorted().find((c) => c.id === st.client);
      const r = caSearch(q, scope || null);
      loose = !!r.loose;
      list = r.files.sort((x, y) => String(y.a.addedAt || '').localeCompare(String(x.a.addedAt || '')));
    } else list = allFiles().filter(({ c }) => st.client === 'all' || c.id === st.client);
    const total = list.length;
    list = list.slice(0, 60);
    st.count = `${total} file${total === 1 ? '' : 's'}`;
    const n = $('#oh-fcount'); if (n) n.textContent = st.count;
    if (!list.length) return `<div class="oh-empty">${q ? 'No files match — try a client, a folder or a file type like “pdf”' : 'No files yet'}</div>`;
    const name = (a) => (q ? caMark(a.name, q) : esc(a.name));
    const where = (c, f) => (q ? caMark(`${c.name} › ${folderPath(c, f)}`, q) : `${esc(c.name)} › ${esc(folderPath(c, f))}`);
    const note = loose ? '<div class="oh-empty oh-close">Nothing matched exactly — close matches:</div>' : '';
    // a file picked: its size joins its line, and Open Folder · Download as two small round buttons where its time was
    // (no details box — Haris 2026-11-15 11:21); right-click has them too
    return note + list.map(({ c, f, a }) => {
      const open = st.sel === a.id;
      return `<div class="oh-fwrap" data-file="${a.id}" data-client="${c.id}" data-folder="${f.id}"><div class="oh-row ${open ? 'sel' : ''}" role="button" tabindex="0" data-oh="file" data-id="${a.id}">
          <span class="oh-ext" style="background:${esc(projColorOfClient(c))}">${esc(extOf(a.name))}</span>
          <span class="oh-t"><b>${name(a)}</b><small>${where(c, f)}${a.addedBy ? ' · ' + esc(firstName(a.addedBy)) : ''}${open && a.size ? ' · ' + esc(fmtSize(a.size)) : ''}</small></span>
          ${open ? `<span class="oh-fbtns"><button class="oh-ib" data-oh="open-folder" data-client="${c.id}" data-folder="${f.id}" title="Open Folder">${icon('folder')}</button><a class="oh-ib" href="${fileUrl(a)}" download="${esc(a.name)}" title="Download">${icon('download')}</a></span>`
            : `<span class="oh-w">${a.addedAt ? esc(short(a.addedAt)) : ''}</span>`}</div></div>`;
    }).join('');
  }
  function projColorOfClient(c) { const p = db.projects.find((x) => x.clientId === c.id); return (p && p.color) || '#6e717a'; }

  // the month's claims in two groups, each with See All (the iPhone's): Need HR approval (submitted), then HR approved and
  // paid. One thing at a row's right (Haris 2026-11-15 11:21): HR Approve / Paid On… for Finance Admins, else its state.
  function claimGroups(claims, money) {
    const row = (c) => {
      const act = finAdmin() && c.state === 'submitted' ? ['approve', 'HR Approve'] : finAdmin() && c.state === 'approved' ? ['paid', 'Paid On…'] : null;
      const [l, cls] = CLAIM_PILL[c.state];
      const n = Claims.itemsOf(c);
      return `<div class="oh-row static oh-claim" data-claim-row="${c.id}">
          ${avatarHTML(c.userId, 30)}<button class="oh-t oh-plain" data-oh="claim" data-id="${c.id}"><b>${esc(fullName(userById(c.userId)))}</b><small>${n} item${n === 1 ? '' : 's'}${c.state === 'paid' && c.paidOn ? ' · paid ' + esc(fmtDay(c.paidOn)) : ''} · ⃃${money(Claims.totalOf(c))}</small></button>
          ${act ? `<button class="oh-mini" data-oh="${act[0]}" data-id="${c.id}">${act[1]}</button>` : `<span class="oh-pill ${cls}">${l}</span>`}</div>`;
    };
    const grp = (title, list) => (list.length ? `<div class="oh-grp"><span>${title}</span><i>${list.length}</i><button class="oh-link" data-oh="see-all">See All</button></div>${list.map(row).join('')}` : '');
    return grp('Need HR approval', claims.filter((c) => c.state === 'submitted')) + grp('HR approved and paid', claims.filter((c) => c.state !== 'submitted'));
  }

  function view() {
    setTimeout(barSearch, 0);
    const u = me();
    const h = new Date().getHours();
    const part = Occasions.greeting(todayStr()) || (h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening');
    const clients = clientsSorted();
    const notes = myNotifs().slice().sort((a, b) => b.at.localeCompare(a.at));
    const unread = notes.filter((n) => !n.read).length;
    const ibTab = st.ibTab || (unread ? 'unread' : 'all');      // nothing unread: opens on All
    const shownNotes = notes.filter((n) => ibTab === 'all' || !n.read).slice(0, 50);
    const hasFin = fin();
    const m = st.month || Claims.claimMonth();
    const months = Array.from({ length: 12 }, (_, i) => Claims.addMonth(Claims.claimMonth(), -i));   // (the last 12, as the website's Claims)
    const claims = hasFin ? Claims.all().filter((c) => c.month === m && ['submitted', 'approved', 'paid'].includes(c.state)).sort((a, b) => fullName(userById(a.userId)).localeCompare(fullName(userById(b.userId)))) : [];
    const cnt = (s) => claims.filter((c) => c.state === s).length;
    const pct = (s) => (claims.length ? Math.round((cnt(s) / claims.length) * 100) : 0) + '%';
    const money = (n) => (Number(n) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const thisMonth = st.month || todayStr().slice(0, 7);
    const exp = hasFin ? Fin.transactions().filter((x) => String(x.date).startsWith(thisMonth)) : [];
    const team = db.users.filter((x) => x.active !== false).length;
    const ring = (k) => (st.focus === k ? 'focus' : '');
    const filesNow = filesHTML();
    const tile = (n, label, sub, act, tone) => `<button class="oh-stat" ${act}><span class="oh-num ${tone}">${n}</span><span class="oh-sl"><b>${esc(label)}</b><small>${esc(sub)}</small></span></button>`;
    const seg = (cur, list, key) => `<div class="oh-seg">${list.map(([k, l]) => `<button class="${cur === k ? 'on' : ''}" data-oh="seg" data-key="${key}" data-v="${k}">${esc(l)}</button>`).join('')}</div>`;
    return `<div class="oh ${hasFin ? '' : 'no-fin'}">
      <header class="oh-head">
        <div><div class="oh-date">${esc(new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' }))} · Office Admin</div>
          <h1>${esc(part)}, ${esc(firstName(u.id))}</h1></div>
        <label class="oh-search">${icon('search')}<span class="sr-only">Search Client Assets</span><input id="oh-q" value="${esc(st.q)}" placeholder="Search Client Assets — e.g. “ford logo png”" autocomplete="off" spellcheck="false"></label>
      </header>
      <div class="oh-stats">
        ${tile(clients.length, 'Clients', 'in Client Assets', 'data-oh="focus" data-v="assets"', 'violet')}
        ${tile(unread, 'Unread', 'in your Inbox', 'data-oh="focus" data-v="inbox"', unread ? 'red' : 'grey')}
        ${tile(team, 'Team members', 'Open Team page', 'data-oh="team"', 'blue')}
        ${hasFin ? tile(cnt('submitted'), 'Claims to approve', `${monthName(m)} · opens Claims`, 'data-oh="claims"', cnt('submitted') ? 'amber' : 'green') : ''}
      </div>
      <div class="oh-grid">
        <section class="oh-card ${ring('assets')}">
          <div class="oh-card-h"><h2>Latest in Client Assets</h2><span class="oh-dim" id="oh-fcount">${esc(st.count || '')}</span></div>
          <div class="oh-chips">${[['all', 'All clients', '#9aa0ab']].concat(clients.map((c) => [c.id, c.name, projColorOfClient(c)])).map(([id, l, col]) => `<button class="oh-chip ${st.client === id ? 'on' : ''}" data-oh="client" data-v="${id}"><i style="background:${esc(col)}"></i>${esc(l)}</button>`).join('')}</div>
          <div class="oh-scroll" id="oh-files">${filesNow}</div>
        </section>
        <section class="oh-card ${ring('inbox')}">
          <div class="oh-card-h"><h2>Inbox</h2>${seg(ibTab, [['unread', 'Unread'], ['all', 'All']], 'ibTab')}</div>
          <div class="oh-scroll">${shownNotes.length ? shownNotes.map((n) => `<button class="oh-row ${n.read ? '' : 'unread'}" data-action="open-notif" data-id="${n.id}">
              ${avatarHTML(n.from, 28)}<span class="oh-t"><b>${notifMsg(n, null)}</b><small>${n.kind === 'asset' ? 'Client Assets' : /^claim/.test(n.kind) ? 'Expense claim' : 'Update'} · ${esc(timeAgo(n.at))}</small></span>
              ${n.read ? '' : '<i class="oh-dot"></i>'}</button>`).join('') : '<div class="oh-empty center">All caught up</div>'}</div>
          <div class="oh-foot"><span>Open an update to see it</span>${unread ? '<button class="oh-link" data-action="mark-all-read">Mark all read</button>' : ''}</div>
        </section>
        ${hasFin ? `<section class="oh-card ${ring('fin')}">
          <div class="oh-card-h"><h2>Finance</h2><span class="oh-msel"><select data-oh-month aria-label="Month">${months.map((x) => `<option value="${x}" ${x === m ? 'selected' : ''}>${esc(monthName(x))}</option>`).join('')}</select>${icon('chev')}</span><span class="oh-ctl">${seg(st.finTab, [['claims', 'Claims'], ['expenses', 'Expenses']], 'finTab')}${finAdmin() && st.finTab === 'claims' && claims.some((c) => c.state !== 'paid') ? `<button class="oh-more" data-oh="more" title="More">${icon('more')}</button>` : ''}</span></div>
          ${st.finTab === 'claims' ? `<div class="oh-fin-top">
              <div class="oh-bar"><span class="sub" style="width:${pct('submitted')}"></span><span class="ok" style="width:${pct('approved')}"></span><span class="paid" style="width:${pct('paid')}"></span></div>
              <div class="oh-legend"><span><b class="sub">${cnt('submitted')}</b> submitted</span><span><b class="ok">${cnt('approved')}</b> HR approved</span><span><b class="paid">${cnt('paid')}</b> paid</span><span class="oh-amt">⃃${money(claims.reduce((a, c) => a + Claims.totalOf(c), 0))}</span></div></div>
            <div class="oh-scroll">${claims.length ? claimGroups(claims, money) : '<div class="oh-empty center">No claims submitted yet this month</div>'}</div>`
          : `<div class="oh-fin-top"><b class="oh-big">⃃${money(exp.reduce((a, x) => a + x.amount, 0))}</b><span class="oh-dim">spent in ${esc(monthName(thisMonth))} · ${exp.length} record${exp.length === 1 ? '' : 's'}</span></div>
            <div class="oh-scroll">${exp.length ? exp.map((x) => `<div class="oh-row static"><span class="oh-ext soft">${x.kind === 'sub' ? 'SUB' : x.kind === 'reimb' ? 'REIM' : 'EXP'}</span>
                <span class="oh-t"><b>${esc(x.name)}</b><small>${KIND[x.kind] || ''} · ${esc(fmtDay(x.date))}</small></span><span class="oh-amt">⃃${money(x.amount)}</span></div>`).join('') : '<div class="oh-empty center">No expenses this month yet</div>'}</div>`}
          <div class="oh-foot"><button class="btn sm" data-nav="fin-dash">Open Dashboard</button><button class="btn sm" data-nav="fin-reimb">All reimbursements</button></div>
        </section>` : ''}
      </div>
    </div>`;
  }
  const redraw = () => { if (ui.view === 'home' && isOffice()) renderContent(); };
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-oh]');
    if (!b || !b.closest('.oh')) return;
    e.stopPropagation();
    const k = b.dataset.oh, v = b.dataset.v;
    if (k === 'file') { if (e.target.closest('.oh-fbtns')) return; st.sel = st.sel === b.dataset.id ? null : b.dataset.id; $('#oh-files').innerHTML = filesHTML(); return; }
    if (k === 'open-folder') return openClient(b.dataset.client, b.dataset.folder);
    if (k === 'client') { st.client = v; st.sel = null; return redraw(); }
    if (k === 'seg') { st[b.dataset.key] = v; return redraw(); }
    if (k === 'focus') { st.focus = st.focus === v ? null : v; if (v === 'inbox') st.ibTab = null; if (v === 'fin') st.finTab = 'claims'; return redraw(); }
    if (k === 'team') return go('team');
    if (k === 'claims' || k === 'see-all') { Claims.st.finMonth = st.month || Claims.claimMonth(); return go('fin-reimb'); }
    if (k === 'more') {
      const m = st.month || Claims.claimMonth();
      const ofMonth = (s) => Claims.all().filter((c) => c.month === m && s.includes(c.state)).map((c) => c.id);
      return showMenu(b, [
        { label: 'Mark All HR Approved', icon: 'check', run: () => Claims.markApproved(ofMonth(['submitted'])) },
        { label: 'Set All Paid On…', icon: 'coin', run: () => Claims.markPaid(ofMonth(['submitted', 'approved'])) },
      ]);
    }
    if (k === 'claim') return Claims.open(b.dataset.id);
    if (k === 'approve') return Claims.markApproved([b.dataset.id]);
    if (k === 'paid') return Claims.markPaid([b.dataset.id]);
  }, true);
  document.addEventListener('change', (e) => {
    if (!e.target.matches || !e.target.matches('.oh [data-oh-month]')) return;
    st.month = e.target.value === Claims.claimMonth() ? null : e.target.value;
    redraw();
  });
  // right-click: a claim — Open Claim · HR Approved · Paid On… · Share PDF; a file — Open Folder · Download (the iPhone's)
  document.addEventListener('contextmenu', (e) => {
    if (!e.target.closest || !e.target.closest('.oh') || (typeof Phone !== 'undefined' && Phone.on)) return;
    const at = atPoint(e.clientX, e.clientY);
    const cr = e.target.closest('[data-claim-row]');
    if (cr) {
      const c = Claims.byId(cr.dataset.claimRow); if (!c) return;
      e.preventDefault();
      return showMenu(at, [
        { label: 'Open Claim', icon: 'open', run: () => Claims.open(c.id) },
        ...(finAdmin() && c.state !== 'paid' ? ['-',
          ...(c.state === 'submitted' ? [{ label: 'HR Approved', icon: 'check', run: () => Claims.markApproved([c.id]) }] : []),
          { label: 'Paid On…', icon: 'coin', run: () => Claims.markPaid([c.id]) }] : []),
        '-',
        { label: 'Share PDF', icon: 'download', run: () => Claims.downloadPdf(c.id) },
      ]);
    }
    const fr = e.target.closest('[data-file]');
    if (fr) {
      const a = allFiles().find((x) => x.a.id === fr.dataset.file); if (!a) return;
      e.preventDefault();
      return showMenu(at, [
        { label: 'Open Folder', icon: 'folder', run: () => openClient(fr.dataset.client, fr.dataset.folder) },
        { label: 'Download', icon: 'download', run: () => { const l = document.createElement('a'); l.href = fileUrl(a.a); l.download = a.a.name; document.body.appendChild(l); l.click(); l.remove(); } },
      ]);
    }
  });
  // the Mac app: their search is the bar's (Search Client Assets — Haris 2026-11-15 11:02), not the box on their Home
  const macBar = () => document.documentElement.classList.contains('mac-chrome');
  function barSearch() {
    const s = document.getElementById('search');
    if (!s || !macBar() || !isOffice()) return;
    s.placeholder = 'Search Client Assets';
    if (s.value !== st.q && document.activeElement !== s) s.value = st.q;
  }
  document.addEventListener('input', (e) => {
    if (e.target.id !== 'search' || !macBar() || typeof isOffice !== 'function' || !isOffice()) return;
    e.stopImmediatePropagation();
    st.q = e.target.value; st.sel = null;
    if (ui.view !== 'home') { go('home'); return; }
    const box = $('#oh-files'); if (box) box.innerHTML = filesHTML();
  }, true);
  document.addEventListener('input', (e) => {
    if (e.target.id !== 'oh-q') return;
    st.q = e.target.value; st.sel = null;
    const box = $('#oh-files'); if (box) box.innerHTML = filesHTML();
  });
  return { view, st };
})();
