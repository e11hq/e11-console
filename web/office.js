/* ================= Office Admin: Home =================
   An Office Admin (e.g. Arsal) has Admin rights without the task app. Their Home (agreed from the mockup "E11 Console —
   Office Admin Home"): four tiles, then three boxes of the same height down to the bottom of the window — the latest in
   Client Assets (search, client chips, a file's details), the Inbox (opens on Unread, or All when nothing is unread) and,
   with Finance access, this month's expense claims (HR approve / mark paid) and expenses. */
const OfficeHome = (() => {
  const st = { q: '', client: 'all', sel: null, ibTab: null, finTab: 'claims', focus: null };
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
    return note + list.map(({ c, f, a }) => {
      const open = st.sel === a.id;
      return `<div class="oh-fwrap"><button class="oh-row ${open ? 'sel' : ''}" data-oh="file" data-id="${a.id}">
          <span class="oh-ext" style="background:${esc(projColorOfClient(c))}">${esc(extOf(a.name))}</span>
          <span class="oh-t"><b>${name(a)}</b><small>${where(c, f)}${a.addedBy ? ' · ' + esc(firstName(a.addedBy)) : ''}</small></span>
          <span class="oh-w">${a.addedAt ? esc(short(a.addedAt)) : ''}</span></button>
        ${open ? `<div class="oh-detail">
          <div class="oh-kv"><span>Added by</span><span>${a.addedBy ? esc(fullName(userById(a.addedBy))) : '—'}</span>
            <span>Added</span><span>${a.addedAt ? esc(new Date(a.addedAt).toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' })) : '—'}</span>
            <span>Size</span><span>${esc(fmtSize(a.size))}</span><span>Folder</span><span>${esc(c.name)} › ${esc(folderPath(c, f))}</span></div>
          <div class="oh-acts"><button class="btn sm" data-oh="open-folder" data-client="${c.id}" data-folder="${f.id}">Open folder</button><a class="btn sm" href="${fileUrl(a)}" download="${esc(a.name)}">Download</a></div>
        </div>` : ''}</div>`;
    }).join('');
  }
  function projColorOfClient(c) { const p = db.projects.find((x) => x.clientId === c.id); return (p && p.color) || '#6e717a'; }

  function view() {
    const u = me();
    const h = new Date().getHours();
    const part = Occasions.greeting(todayStr()) || (h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening');
    const clients = clientsSorted();
    const notes = myNotifs().slice().sort((a, b) => b.at.localeCompare(a.at));
    const unread = notes.filter((n) => !n.read).length;
    const ibTab = st.ibTab || (unread ? 'unread' : 'all');      // nothing unread: opens on All
    const shownNotes = notes.filter((n) => ibTab === 'all' || !n.read).slice(0, 50);
    const hasFin = fin();
    const m = Claims.claimMonth();
    const claims = hasFin ? Claims.all().filter((c) => c.month === m && ['submitted', 'approved', 'paid'].includes(c.state)).sort((a, b) => fullName(userById(a.userId)).localeCompare(fullName(userById(b.userId)))) : [];
    const cnt = (s) => claims.filter((c) => c.state === s).length;
    const pct = (s) => (claims.length ? Math.round((cnt(s) / claims.length) * 100) : 0) + '%';
    const money = (n) => (Number(n) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const thisMonth = todayStr().slice(0, 7);
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
        ${hasFin ? tile(cnt('submitted'), 'Claims to approve', monthName(m), 'data-oh="focus" data-v="fin"', cnt('submitted') ? 'amber' : 'green') : ''}
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
          <div class="oh-card-h"><h2>Finance · ${esc(monthName(m))}</h2>${seg(st.finTab, [['claims', 'Claims'], ['expenses', 'Expenses']], 'finTab')}</div>
          ${st.finTab === 'claims' ? `<div class="oh-fin-top">
              <div class="oh-bar"><span class="sub" style="width:${pct('submitted')}"></span><span class="ok" style="width:${pct('approved')}"></span><span class="paid" style="width:${pct('paid')}"></span></div>
              <div class="oh-legend"><span><b class="sub">${cnt('submitted')}</b> submitted</span><span><b class="ok">${cnt('approved')}</b> HR approved</span><span><b class="paid">${cnt('paid')}</b> paid</span><span class="oh-amt">AED ${money(claims.reduce((a, c) => a + Claims.totalOf(c), 0))}</span></div></div>
            <div class="oh-scroll">${claims.length ? claims.map((c) => { const [l, cls] = CLAIM_PILL[c.state]; return `<div class="oh-row static">
                ${avatarHTML(c.userId, 28)}<button class="oh-t oh-plain" data-oh="claim" data-id="${c.id}"><b>${esc(fullName(userById(c.userId)))}</b><small>${Claims.itemsOf(c)} item${Claims.itemsOf(c) === 1 ? '' : 's'} · AED ${money(Claims.totalOf(c))}</small></button>
                <span class="oh-pill ${cls}">${l}</span>
                ${finAdmin() && c.state !== 'paid' ? `<button class="oh-mini" data-oh="${c.state === 'submitted' ? 'approve' : 'paid'}" data-id="${c.id}">${c.state === 'submitted' ? 'HR approve' : 'Mark paid'}</button>` : ''}</div>`; }).join('') : '<div class="oh-empty center">No claims submitted yet this month</div>'}</div>`
          : `<div class="oh-fin-top"><b class="oh-big">AED ${money(exp.reduce((a, x) => a + x.amount, 0))}</b><span class="oh-dim">spent this month · ${exp.length} record${exp.length === 1 ? '' : 's'}</span></div>
            <div class="oh-scroll">${exp.length ? exp.map((x) => `<div class="oh-row static"><span class="oh-ext soft">${x.kind === 'sub' ? 'SUB' : x.kind === 'reimb' ? 'REIM' : 'EXP'}</span>
                <span class="oh-t"><b>${esc(x.name)}</b><small>${KIND[x.kind] || ''} · ${esc(fmtDay(x.date))}</small></span><span class="oh-amt">AED ${money(x.amount)}</span></div>`).join('') : '<div class="oh-empty center">No expenses this month yet</div>'}</div>`}
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
    if (k === 'file') { st.sel = st.sel === b.dataset.id ? null : b.dataset.id; $('#oh-files').innerHTML = filesHTML(); return; }
    if (k === 'open-folder') return openClient(b.dataset.client, b.dataset.folder);
    if (k === 'client') { st.client = v; st.sel = null; return redraw(); }
    if (k === 'seg') { st[b.dataset.key] = v; return redraw(); }
    if (k === 'focus') { st.focus = st.focus === v ? null : v; if (v === 'inbox') st.ibTab = null; if (v === 'fin') st.finTab = 'claims'; return redraw(); }
    if (k === 'team') return go('team');
    if (k === 'claim') return Claims.open(b.dataset.id);
    if (k === 'approve') return Claims.markApproved([b.dataset.id]);
    if (k === 'paid') return Claims.markPaid([b.dataset.id]);
  }, true);
  document.addEventListener('input', (e) => {
    if (e.target.id !== 'oh-q') return;
    st.q = e.target.value; st.sel = null;
    const box = $('#oh-files'); if (box) box.innerHTML = filesHTML();
  });
  return { view, st };
})();
