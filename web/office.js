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

  /* ---------- The Mac app: the Office Admin's Home in the team's Home style (Haris 2026-11-15 17:46, mock-up O1 A approved:
     "E11 Console for Mac") — Home's own pieces (.hm): the date and greeting with + Add claim, three cards on top (the third the
     right column's width), Claims as Team's tasks (its tabs and counts beside the title, See all, rows tinted in turn),
     Latest in Client Assets as pictures (one sliding row of clients fading at its right), and on the right the month's claims
     as Team goals achieved (its ring growing from 0 once the page shows — the rule), the Inbox and Team today. ---------- */
  const shownFor = () => (window.__e11ShownAt ? Date.now() - window.__e11ShownAt : 0);
  const sv = (k, d) => `<span class="hm-ic-s" data-i="oh-${k}"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${d}"/></svg></span>`;
  const MI = {
    claim: 'M2 4.5h12v7H2zM8 9.6a1.6 1.6 0 1 0 0-3.2 1.6 1.6 0 0 0 0 3.2zM4.2 8h.01M11.8 8h.01',
    sub: 'M3.5 8a4.5 4.5 0 0 1 7.8-3.1M12.5 8a4.5 4.5 0 0 1-7.8 3.1M11.6 2.6v2.5H9.1M4.4 13.4v-2.5h2.5',
    expense: 'M3 2.5h10v11l-1.7-1-1.6 1-1.7-1-1.6 1-1.7-1L3 13.5zM5.5 5.5h5M5.5 8h5M5.5 10.5h3',
    reimb: 'M5.5 7.4a2.2 2.2 0 1 0 0-4.4 2.2 2.2 0 0 0 0 4.4zM1.8 13c0-2.1 1.7-3.6 3.7-3.6 1 0 1.8.3 2.5.9M10 9.5h4.5M12.5 7.5l2 2-2 2',
    tray: 'M2.5 9.5 4.3 4h7.4l1.8 5.5V12a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1zM2.5 9.5h3l.8 1.6h3.4l.8-1.6h3',
    folder: 'M2.2 4.6c0-.7.5-1.2 1.2-1.2h2.8l1.4 1.5h4.9c.7 0 1.2.5 1.2 1.2v5.6c0 .7-.5 1.2-1.2 1.2H3.4c-.7 0-1.2-.5-1.2-1.2z',
    team: 'M6 7.4a2.2 2.2 0 1 0 0-4.4 2.2 2.2 0 0 0 0 4.4zM2 13c0-2.2 1.8-3.8 4-3.8s4 1.6 4 3.8M11 3.2a2 2 0 0 1 0 4M12.2 9.4c1.1.4 1.8 1.4 1.8 2.6',
  };
  const hello = () => {
    const h = new Date().getHours(), g = Occasions.greeting(todayStr()) || (h < 5 ? 'Good evening' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening');
    return Occasions.alone(g) ? g : `${g}, ${firstName(me().id)}`;
  };
  function macView() {
    const u = me();
    const today = todayStr();
    const hasFin = fin();
    // (the dirham sign everywhere, as the rest of the app — Haris 17:54)
    const AED = (n) => '\u20C3' + (Number(n) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const AED0 = (n) => '\u20C3' + Math.round(Number(n) || 0).toLocaleString('en-US');
    const m = Claims.claimMonth();
    const claims = hasFin ? Claims.all().filter((c) => c.month === m && ['submitted', 'approved', 'paid'].includes(c.state)).sort((a, b) => String(b.submittedAt || '').localeCompare(String(a.submittedAt || ''))) : [];
    const cnt = (s) => claims.filter((c) => c.state === s).length;
    const waiting = claims.filter((c) => c.state === 'submitted');
    const notes = myNotifs().slice().sort((a, b) => b.at.localeCompare(a.at));
    const unreadN = notes.filter((n) => !n.read);
    const nClaim = unreadN.filter((n) => /^claim/.test(n.kind)).length, nFile = unreadN.filter((n) => n.kind === 'asset').length, nOther = unreadN.length - nClaim - nFile;
    const unreadNote = unreadN.length ? [nClaim && `${nClaim} claim${nClaim === 1 ? '' : 's'}`, nFile && `${nFile} file${nFile === 1 ? '' : 's'}`, nOther && `${nOther} update${nOther === 1 ? '' : 's'}`].filter(Boolean).join(', ') : 'all caught up';
    const weekAgo = new Date(Date.now() - 7 * 86400000).toISOString();
    const files = allFiles();
    const fresh = files.filter(({ a }) => String(a.addedAt || '') >= weekAgo);
    const team = db.users.filter((x) => x.active !== false);
    const card = (cls, ic, l, n, note, noteCls, act) => `<button type="button" class="hm-stat" data-oh="${act}"><span class="hm-ic ${cls}">${sv(ic, MI[ic])}</span><span><span class="hm-sl">${esc(l)}</span><span class="hm-sn"><b>${n}</b><span class="${noteCls}">${esc(note)}</span></span></span></button>`;

    // Claims, as Team's tasks
    const TABS = [['submitted', 'Need HR approval'], ['approved', 'HR approved'], ['paid', 'Paid'], ['all', 'All']];
    if (!st.claimTab) st.claimTab = waiting.length ? 'submitted' : 'all';
    const inTab = claims.filter((c) => st.claimTab === 'all' || c.state === st.claimTab);
    const claimRows = inTab.slice(0, 6);
    const ago = (iso) => { if (!iso) return ''; const d = ymd(new Date(iso)); return d === today ? 'today' : d === addDays(today, -1) ? 'yesterday' : fmtDay(d); };
    const claimRow = (c) => {
      const n = Claims.itemsOf(c);
      const act = finAdmin() && c.state === 'submitted' ? ['approve', 'HR Approve'] : finAdmin() && c.state === 'approved' ? ['paid', 'Paid On…'] : null;
      const sub = c.state === 'paid' && c.paidOn ? `paid ${esc(fmtDay(c.paidOn))}` : c.state === 'approved' ? 'HR approved' : `submitted ${esc(ago(c.submittedAt))}`;
      return `<div class="hm-row ohm-claim" data-claim-row="${c.id}" data-oh="claim" data-id="${c.id}">${avatarHTML(c.userId, 30)}
          <span class="hm-main"><span class="hm-t">${esc(fullName(userById(c.userId)))}</span><span class="hm-sub">${n} item${n === 1 ? '' : 's'} · ${sub}</span></span>
          <span class="ohm-amt">${AED(Claims.totalOf(c))}</span>
          ${act ? `<button type="button" class="hm-btn ohm-act" data-oh="${act[0]}" data-id="${c.id}">${act[1]}</button>` : `<span class="ohm-state ${c.state}">${esc(CLAIM_PILL[c.state][0])}</span>`}</div>`;
    };
    const claimsCard = hasFin ? `<section class="hm-card">
        <div class="hm-h"><div class="hm-hl"><h2>Claims</h2><span class="hm-seg">${TABS.map(([k, l]) => { const n = k === 'all' ? claims.length : cnt(k); return `<button type="button" class="hm-tab ${st.claimTab === k ? 'on' : ''} ${k === 'submitted' && n ? 'amber' : ''}" data-oh="claim-tab" data-v="${k}">${l}<i>${n}</i></button>`; }).join('')}</span></div><a class="hm-a" data-oh="see-all">See all</a></div>
        ${claimRows.length ? claimRows.map(claimRow).join('') + (inTab.length > claimRows.length ? `<button type="button" class="hm-more-btn" data-oh="see-all">+${inTab.length - claimRows.length} more · See all</button>` : '')
          : `<div class="hm-empty">${st.claimTab === 'submitted' ? 'Nothing waiting for HR approval.' : st.claimTab === 'all' ? `No claims submitted yet for ${esc(monthName(m))}.` : `None ${st.claimTab === 'paid' ? 'paid' : 'HR approved'} yet this month.`}</div>`}
      </section>` : '';

    // Expenses this month, below Claims (Haris 17:54): Claims' card again — the kinds as tabs with counts, See all, rows
    // tinted in turn; a row with an invoice opens it in the preview
    const EK = [['all', 'All'], ['sub', 'Subscriptions'], ['expense', 'Office expenses'], ['reimb', 'Reimbursements']];
    const EKL = { sub: 'Subscription', expense: 'Office expense', reimb: 'Reimbursement' };
    const tm = todayStr().slice(0, 7);
    const exp = hasFin && typeof Fin !== 'undefined' ? Fin.transactions().filter((x) => String(x.date).startsWith(tm)) : [];
    if (!st.expTab) st.expTab = 'all';
    const expIn = exp.filter((x) => st.expTab === 'all' || x.kind === st.expTab), expRows = expIn.slice(0, 5);
    st.expRows = expIn;
    const expCard = hasFin ? `<section class="hm-card ohm-exp">
        <div class="hm-h"><div class="hm-hl"><h2>Expenses</h2><span class="hm-seg">${EK.map(([k, l]) => `<button type="button" class="hm-tab ${st.expTab === k ? 'on' : ''}" data-oh="exp-tab" data-v="${k}">${l}<i>${k === 'all' ? exp.length : exp.filter((x) => x.kind === k).length}</i></button>`).join('')}</span></div><span class="ohm-total">${AED(expIn.reduce((a, x) => a + x.amount, 0))}</span><a class="hm-a" data-oh="exp-all">See all</a></div>
        ${expRows.length ? expRows.map((x) => `<div class="hm-row ohm-claim ohm-x" ${x.invoice ? `data-oh="exp-inv" data-v="${esc(x.id)}"` : ''}><span class="hm-ic ohm-k ${x.kind}">${sv(x.kind, MI[x.kind])}</span>
            <span class="hm-main"><span class="hm-t">${esc(x.name)}</span><span class="hm-sub">${EKL[x.kind] || ''} · ${esc(fmtDay(x.date))}${x.invoice ? '' : ' · no invoice yet'}</span></span>
            <span class="ohm-amt">${AED(x.amount)}</span></div>`).join('') + (expIn.length > expRows.length ? `<button type="button" class="hm-more-btn" data-oh="exp-all">+${expIn.length - expRows.length} more · See all</button>` : '')
          : `<div class="hm-empty">No ${st.expTab === 'all' ? 'expenses' : EK.find(([k]) => k === st.expTab)[1].toLowerCase()} in ${esc(monthName(tm))} yet.</div>`}
      </section>` : '';

    // Latest in Client Assets: pictures; clients on one sliding row, newest first, each with its files this week
    const newest = new Map();
    files.forEach(({ c, a }) => { if (!newest.has(c.id)) newest.set(c.id, a.addedAt || ''); });
    const chipClients = clientsSorted().slice().sort((x, y) => String(newest.get(y.id) || '').localeCompare(String(newest.get(x.id) || '')));
    if (st.client !== 'all' && !chipClients.some((c) => c.id === st.client)) st.client = 'all';
    const q = st.q.trim();
    let shown;
    if (q) { const scope = st.client === 'all' ? null : chipClients.find((c) => c.id === st.client); shown = caSearch(q, scope || null).files.sort((x, y) => String(y.a.addedAt || '').localeCompare(String(x.a.addedAt || ''))).slice(0, 24); }
    else shown = files.filter(({ c }) => st.client === 'all' || c.id === st.client).slice(0, 8);
    st.thumbs = shown;
    const freshOf = (id) => fresh.filter(({ c }) => c.id === id).length;
    const thumb = ({ c, f, a }) => {
      const img = fileKind(a) === 'image' && Host.isNative ? `<img src="${imgUrl(a, 320)}" alt="" loading="lazy">` : '';
      return `<div class="hm-thumb" data-oh="thumb" data-v="${esc(a.id)}" data-file="${a.id}" data-client="${c.id}" data-folder="${f.id}" title="${esc(a.name)} · ${esc(c.name)} › ${esc(folderPath(c, f))}" style="--pc:${esc(projColorOfClient(c))}">${img}<span class="hm-kind">${esc(extOf(a.name))}</span><span class="hm-fname">${esc(a.name)}</span></div>`;
    };
    const assetsCard = `<section class="hm-card ohm-assets">
        <div class="hm-h"><h2>${q ? 'Found in Client Assets' : 'Latest in Client Assets'}</h2><a class="hm-a" data-nav="clients">Open Client Assets</a></div>
        <div class="ohm-chips" id="ohm-chips">${[['all', 'All clients', fresh.length]].concat(chipClients.map((c) => [c.id, c.name, freshOf(c.id)])).map(([id, l, n]) => `<button type="button" class="ohm-chip ${st.client === id ? 'on' : ''}" data-oh="client" data-v="${id}">${esc(l)}<i>${n}</i></button>`).join('')}</div>
        ${shown.length ? `<div class="hm-files ohm-grid">${shown.map(thumb).join('')}</div>` : `<div class="hm-empty">${q ? 'No files match — try a client, a folder or a file type like “pdf”.' : 'Files added to Client Assets show up here.'}</div>`}
      </section>`;

    // the month's claims, as Team goals achieved: paid so far of everything claimed, its ring growing from 0 once
    const total = claims.reduce((s, c) => s + Claims.totalOf(c), 0), paid = claims.filter((c) => c.state === 'paid').reduce((s, c) => s + Claims.totalOf(c), 0);
    const p = total ? paid / total : 0, R = 30, C = 2 * Math.PI * R, e = shownFor();
    const seg = (s) => (claims.length ? (cnt(s) / claims.length) * 100 : 0);
    const monthCard = hasFin ? `<section class="hm-card hm-goal ohm-month" data-oh="claims-open">
        <h2>${esc(monthName(m))}’s claims</h2>
        <div class="hm-gr"><svg viewBox="0 0 76 76" width="76" height="76" aria-hidden="true"><circle cx="38" cy="38" r="${R}" class="hm-ring-bg"/>${p > 0 ? `<circle cx="38" cy="38" r="${R}" class="hm-ring${e < 1200 ? ' hm-grow' : ''}" style="--c:${C.toFixed(1)};stroke-dasharray:${C.toFixed(1)};stroke-dashoffset:${(C * (1 - p)).toFixed(1)};${e > 0 && e < 1200 ? `animation-delay:-${e}ms` : ''}" transform="rotate(-90 38 38)"/>` : ''}<text x="38" y="43" text-anchor="middle">${claims.length ? Math.round(p * 100) + '%' : '–'}</text></svg>
          <div><b>Paid so far</b><span class="ohm-of">${AED0(paid)} of ${AED0(total)}</span>${waiting.length ? `<span class="warn">${waiting.length} waiting for HR approval</span>` : claims.length ? '<span class="ok">nothing waiting</span>' : '<span class="ohm-of">no claims yet</span>'}</div></div>
        <div class="ohm-bar"><i class="sub" style="width:${seg('submitted')}%"></i><i class="ok" style="width:${seg('approved')}%"></i><i class="paid" style="width:${seg('paid')}%"></i></div>
        <div class="ohm-legend"><span><b class="sub">${cnt('submitted')}</b> submitted</span><span><b class="ok">${cnt('approved')}</b> HR approved</span><span><b class="paid">${cnt('paid')}</b> paid</span></div>
      </section>` : '';

    // Inbox: the latest, unread first look (bold, the dot)
    const inboxRows = notes.slice(0, 6);
    const inboxCard = `<section class="hm-card ohm-inbox">
        <div class="hm-h"><h2>Inbox</h2><a class="hm-a" data-nav="inbox">Open Inbox</a></div>
        ${inboxRows.length ? inboxRows.map((n) => `<div class="hm-act ${n.read ? 'read' : 'unread'}" data-action="open-notif" data-id="${n.id}">${avatarHTML(n.from, 30)}<span class="hm-act-txt">${notifMsg(n, null)}</span><span class="hm-when">${esc(timeAgo(n.at))}</span>${n.read ? '' : '<i class="ohm-dot"></i>'}</div>`).join('') : '<div class="hm-empty">All caught up.</div>'}
      </section>`;

    // Team today: out of office, and birthdays today and this week
    const inDays = (md) => { if (!/^\d{2}-\d{2}$/.test(String(md || ''))) return null; for (let i = 0; i < 7; i++) { const d = addDays(today, i); if (d.slice(5) === md) return i; } return null; };
    const people = [];
    team.forEach((x) => { const a = awayDay(x); if (a) people.push({ x, k: 0, note: `Out of office · back ${awayLabel(a).split(' ')[0]}`, cls: 'away' }); });
    team.forEach((x) => { const i = inDays(x.bday); if (i != null) people.push({ x, k: 1 + i, note: i === 0 ? 'Birthday today 🎂' : `Birthday ${parseYmd(addDays(today, i)).toLocaleDateString('en-US', { weekday: 'short' })}`, cls: i === 0 ? 'bday' : '' }); });
    people.sort((a, b) => a.k - b.k);
    const teamCard = `<section class="hm-card ohm-team">
        <div class="hm-h"><h2>Team today</h2><a class="hm-a ohm-dim" data-oh="team">${team.length} people</a></div>
        ${people.length ? people.slice(0, 6).map(({ x, note, cls }) => `<div class="ohm-person" data-oh="team">${avatarHTML(x.id, 26)}<span class="ohm-pn">${esc(fullName(x))}</span><span class="ohm-pnote ${cls}">${esc(note)}</span></div>`).join('') : '<div class="hm-empty">Everyone’s in today.</div>'}
      </section>`;

    // + Add claim: a claim added by hand for someone (one PDF, a person, a month — Finance › Reimbursements' own form; Haris
    // 18:02) — not their own claim; only for a Finance Admin
    const canAdd = finAdmin();
    return `<div class="hm hm-lead ohm">
      <header class="hm-head"><div><div class="hm-date">${esc(new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' }))} · Office Admin</div><h1>${esc(hello())}</h1></div>
        <div class="hm-btns">${canAdd ? '<button type="button" class="hm-btn primary" data-oh="add-claim">+ Add claim</button>' : ''}</div></header>
      <section class="hm-stats">
        ${hasFin ? card('orange', 'claim', 'Claims to approve', waiting.length, waiting.length ? `${AED0(waiting.reduce((s, c) => s + Claims.totalOf(c), 0))} waiting` : 'none waiting', waiting.length ? 'orange' : 'ok', 'claims') : card('blue', 'team', 'Team members', team.length, 'Open Team page', 'ohm-n', 'team')}
        ${card('red', 'tray', 'Unread in your Inbox', unreadN.length, unreadNote, 'ohm-n', 'inbox')}
        ${card('blue', 'folder', 'New in Client Assets', fresh.length, 'this week', 'ok', 'assets')}
      </section>
      <div class="hm-grid">
        <div class="hm-col">${claimsCard}${expCard}${assetsCard}</div>
        <aside class="hm-col">${monthCard}${inboxCard}${teamCard}</aside>
      </div>
    </div>`;
  }

  function view() {
    setTimeout(barSearch, 0);
    if (Host.isMacApp) {
      // the clients' row stays where it was slid to, and the pictures load as Home's
      setTimeout(() => { const r = $('#ohm-chips'); if (r && st.chipX) r.scrollLeft = st.chipX; if (Host.isNative) hydrateThumbs($('#content')); }, 0);
      return macView();
    }
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
    if (!b || !b.closest('.oh, .ohm')) return;
    e.stopPropagation();
    const k = b.dataset.oh, v = b.dataset.v;
    // the Mac app's Home (macView)
    if (k === 'claim-tab') { st.claimTab = v; return redraw(); }
    if (k === 'exp-tab') { st.expTab = v; return redraw(); }
    if (k === 'exp-all') return go('fin-expenses');
    if (k === 'exp-inv') { const x = (st.expRows || []).find((y) => y.id === v); if (x && x.invoice) previewFile(x.invoice, (st.expRows || []).filter((y) => y.invoice).map((y) => y.invoice)); return; }
    if (k === 'add-claim') return Fin.add('reimb');
    if (k === 'inbox') return go('inbox');
    if (k === 'assets') { st.client = 'all'; return go('clients'); }
    if (k === 'claims-open') { Claims.st.finMonth = Claims.claimMonth(); return go('fin-reimb'); }
    if (k === 'thumb') { const list = (st.thumbs || []).map((x) => x.a), a = list.find((x) => x.id === v); if (a) previewFile(a, list); return; }
    if (k === 'claim' && e.target.closest('[data-oh="approve"], [data-oh="paid"]')) return;
    if (k === 'file') { if (e.target.closest('.oh-fbtns')) return; st.sel = st.sel === b.dataset.id ? null : b.dataset.id; $('#oh-files').innerHTML = filesHTML(); return; }
    if (k === 'open-folder') return openClient(b.dataset.client, b.dataset.folder);
    if (k === 'client') { st.client = v; st.sel = null; const r = $('#ohm-chips'); st.chipX = r ? r.scrollLeft : 0; return redraw(); }
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
    if (!e.target.closest || !e.target.closest('.oh, .ohm') || (typeof Phone !== 'undefined' && Phone.on)) return;
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
    if (Host.isMacApp) return redraw();
    const box = $('#oh-files'); if (box) box.innerHTML = filesHTML();
  }, true);
  document.addEventListener('input', (e) => {
    if (e.target.id !== 'oh-q') return;
    st.q = e.target.value; st.sel = null;
    const box = $('#oh-files'); if (box) box.innerHTML = filesHTML();
  });
  return { view, st };
})();
