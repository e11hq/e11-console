/* ================= Content plans =================
   One plan per client per month (db.plans):
     { id, projectId, month: 'YYYY-MM', status: 'draft', createdBy, createdAt, updatedAt, posts: [post] }
     post = { id, day: 'YYYY-MM-DD', title, desc, format, channels: [], occasion, shots, copyEn, copyAr, refs: [ref],
              createdBy, createdAt, updatedAt }
     ref  = a file { id, name, path, size, w?, h? } (uploaded to attachments/<plan id>/) or a link { id, url, label }
   Who: a client's Social Executives (project.socials, set in the client pop-up) and the Social Manager (Social people an
   Admin picks on the Team page: db.meta.socialMgrIds) make and edit a client's plans; Admins, Account Managers and the CD
   look at them. An occasion skipped for a client stays skipped every year (project.planSkips: occasion keys).
   Approval of the content skeleton (stage 2):
     status: 'draft' → 'review' (sent to the Social Manager, the CD or both: pl.review = { to, by, at, round }) →
             'approved' (pl.approval = { by, at, round }) or 'changes' (back to Social, with a note) → sent again …
     post.check = { state: 'ok' | 'changes', note, by, at } — the approver's look at each post
     pl.log = [{ act: 'sent' | 'approved' | 'changes' | 'withdrawn' | 'reopened', by, at, to?, note?, round }]
   One approval is enough (also with "Both"); the SM or the CD may step in on any skeleton waiting; a skeleton the
   Social Manager made goes to the CD (nobody approves their own). Next stages: creating tasks, the finished work coming
   back into the plan, the client export (then it's the "content plan") and the client's approval. */
const Plans = (() => {
  const on = () => true;   // (a trial on the test copy until 2026-10-28; now on everywhere)
  const owns = (v) => on() && (v === 'plans' || v === 'plan');
  const FORMATS = [['post', 'Post', '#8b8b96'], ['carousel', 'Carousel', '#7b68ee'], ['reel', 'Reel', '#e5484d'], ['story', 'Story', '#f2b23e'], ['video', 'Video', '#3ddc97']];
  const FMT = Object.fromEntries(FORMATS.map(([k, name, color]) => [k, { k, name, color }]));
  const fmtOf = (k) => FMT[k] || FMT.post;
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const WD = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const phone = () => typeof Phone !== 'undefined' && Phone.on;
  const list = () => db.plans || (db.plans = []);
  const planById = (id) => list().find((p) => p.id === id) || null;
  const planOf = (pid, month) => list().find((p) => p.projectId === pid && p.month === month) || null;

  /* ---------- who ---------- */
  const isMgr = (u = me()) => !!u && u.role === 'social' && socialMgrIds().includes(u.id);
  const canSee = (u = me()) => on() && !!u && u.active !== false && !isFinUser(u) && !isOffice(u) && (isAdm(u) || u.role === 'am' || u.role === 'social' || isCD(u.id));
  const socialsOf = (p) => ((p && p.socials) || []).filter((id) => { const u = userById(id); return u && u.active !== false; });
  const canEditClient = (pid, u = me()) => on() && !!u && u.role === 'social' && u.active !== false && (isMgr(u) || socialsOf(proj(pid)).includes(u.id));
  const editable = (pl) => !pl.status || pl.status === 'draft' || pl.status === 'changes';
  const canEdit = (pl) => !!pl && canEditClient(pl.projectId) && editable(pl);      // the posts: while a draft, or sent back
  const isEditor = (pl) => !!pl && canEditClient(pl.projectId);                       // (the client's Social people + SM)
  // who approves: the Social Manager (not a skeleton they made) and the Creative Director
  const canApprove = (pl, u = me()) => !!pl && on() && !!u && ((u.id === cdUserId()) || (isMgr(u) && pl.createdBy !== u.id));
  const approverIds = (pl, to) => {
    const cd = cdUserId(), sm = socialMgrIds().filter((id) => id !== pl.createdBy);
    return [...new Set(to === 'cd' ? [cd] : to === 'sm' ? sm : [cd, ...sm])].filter(Boolean);
  };
  // who makes tasks from an approved skeleton: Social, the CD, the client's Account Managers, Admins
  const canMakeTasks = (pl, u = me()) => !!pl && pl.status === 'approved' && !!u && (isEditor(pl) || u.id === cdUserId() || isAdm(u) || ((proj(pl.projectId) || {}).ams || []).some((a) => a.id === u.id));
  // on tasks made from a plan, its Social people (and the Social Manager) do what an Account Manager can
  const socialManages = (t) => { const pl = t && t.planId && planById(t.planId); return !!pl && canEditClient(pl.projectId); };
  /* a post's progress, from its task: the finished work is each person's latest CD-approved files
     (a newer version replaces the old one as soon as the CD approves it) */
  function finishedFiles(t) {
    const latest = new Map();
    (t.reviews || []).forEach((r) => { if (r.state !== 'approved') return; const p = latest.get(r.by); if (!p || String(r.decidedAt || r.at) >= String(p.decidedAt || p.at)) latest.set(r.by, r); });
    const files = [];
    latest.forEach((r) => (r.files || []).forEach((id) => { const a = (t.attachments || []).find((x) => x.id === id); if (a) files.push(a); }));
    return files;
  }
  const PROG = { none: ['Not created', '#8b8b96'], prod: ['In production', '#a875ff'], cd: ['With the CD', '#f2b23e'], ready: ['Finished', '#3ddc97'], changes: ['Client changes', '#ff8a4c'], done: ['Client approved', '#5b9bff'] };
  function progress(x) {
    const t = x.taskId && task(x.taskId);
    if (!x.taskId) return { k: 'none', t: null, files: [] };
    if (!t) return { k: 'none', t: null, files: [], gone: true };
    const files = finishedFiles(t);
    // finished: the work is CD approved (for the client changes too, once the CD approved the new version)
    const fin = files.length && (t.cdStatus === 'approved' || !t.needsCD);
    const k = t.done ? 'done' : reviewPending(t) ? 'cd' : fin ? 'ready' : x.client && x.client.state === 'changes' ? 'changes' : files.length ? 'prod' : 'prod';
    return { k, t, files, fin: !!fin || t.done };
  }
  const SHORT = { none: '', prod: 'In production', cd: 'With the CD', ready: 'Finished', changes: 'Changes', done: 'Approved' };   // (on the calendar)
  const progPill = (g) => `<span class="pl-prog" style="--c:${PROG[g.k][1]}">${esc(PROG[g.k][0])}</span>`;
  const hasTasks = (pl) => (pl.posts || []).some((x) => x.taskId);
  const toLabel = (to) => (to === 'cd' ? (userById(cdUserId()) ? firstName(cdUserId()) : 'the CD') : to === 'sm' ? 'the Social Manager' : `${userById(cdUserId()) ? firstName(cdUserId()) : 'the CD'} & the Social Manager`);
  // the clients on the list: a Social Executive's own; an AM's own; everyone else (Social Manager, Admins, CD) all
  function clientsInScope() {
    const u = me();
    const active = db.projects.filter((p) => !p.inactive).sort(byOrder);
    if (u.role === 'social' && !isMgr(u)) return active.filter((p) => socialsOf(p).includes(u.id));
    if (u.role === 'am' && !isAdm(u) && !isCD(u.id)) return active.filter((p) => amSidebarOk(p));
    return active;
  }

  /* ---------- months ---------- */
  const monthKey = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
  const nextMonth = () => { const d = new Date(); return monthKey(new Date(d.getFullYear(), d.getMonth() + 1, 1)); };
  const thisMonth = () => monthKey(new Date());   // (plans are never for a month that's over: the list starts here)
  const st = () => (ui.plans = ui.plans || { month: nextMonth(), tab: 'calendar' });
  const monthLabel = (m) => { const [y, mm] = m.split('-').map(Number); return `${MONTHS[mm - 1]} ${y}`; };
  const shiftMonth = (m, n) => { const [y, mm] = m.split('-').map(Number); return monthKey(new Date(y, mm - 1 + n, 1)); };
  const firstDay = (m) => `${m}-01`;
  const lastDay = (m) => { const [y, mm] = m.split('-').map(Number); return ymd(new Date(y, mm, 0)); };
  const monday = (s) => { const d = parseYmd(s); d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); return ymd(d); };
  const dayLong = (s) => parseYmd(s).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
  const dayGap = (a, b) => Math.round((parseYmd(b) - parseYmd(a)) / 86400000);

  /* ---------- small pieces ---------- */
  const clientDot = (p, size = 18) => { const c = clientOfProject(p); return c && c.logo ? `<span class="pl-logo">${clientLogoHTML(c, size)}</span>` : `<span class="dot" style="background:${p.color}"></span>`; };
  const people = (ids, none) => (ids.length ? `<span class="pl-people">${ids.map((id) => `<span class="pl-person" title="${esc(fullName(userById(id)))}">${avatarHTML(id, 22)}<span>${esc(firstName(id))}</span></span>`).join('')}</span>` : `<span class="pl-none">${esc(none)}</span>`);
  const fmtPill = (k) => `<span class="pl-fmt" style="--c:${fmtOf(k).color}">${esc(fmtOf(k).name)}</span>`;
  const CH = () => Object.fromEntries(Cal.CHANNELS.map(([k, name, short, color]) => [k, { k, name, short, color }]));
  const chChips = (ks) => { const ch = CH(); return (ks || []).filter((k) => ch[k]).map((k) => `<span class="cal-ch" style="--c:${ch[k].color}" title="${esc(ch[k].name)}">${ch[k].short}</span>`).join(''); };
  // (the version made for the SM / CD to approve is the content skeleton; with the finished videos and graphics, from
  // Round 1 for the client, it's the content plan)
  const ST = { draft: ['draft', 'Skeleton · draft'], review: ['review', 'Waiting for approval'], changes: ['changes', 'Changes asked'], approved: ['approved', 'Skeleton approved'] };
  const statusPill = (pl) => {
    if (!pl) return '<span class="pl-st none">Not started</span>';
    if (pl.status === 'approved' && pl.clientApproved) return '<span class="pl-st approved">Client approved</span>';
    if (pl.status === 'approved' && pl.sent && (pl.exports || []).length && pl.sent.round === pl.exports[pl.exports.length - 1].round) return `<span class="pl-st client">With the client · Round ${pl.sent.round}</span>`;
    if (pl.status === 'approved' && (pl.posts || []).some((x) => x.taskId)) { const n = (pl.posts || []).length, r = (pl.posts || []).filter((x) => ['ready', 'done'].includes(progress(x).k)).length; return `<span class="pl-st prod">In production · ${r}/${n} finished</span>`; }
    const [c, l] = ST[pl.status] || ST.draft; return `<span class="pl-st ${c}">${l}</span>`;
  };
  const occKey = (o) => o.key || o.id;
  const skipped = (p, o) => ((p && p.planSkips) || []).includes(occKey(o));
  const postsSorted = (pl) => (pl.posts || []).slice().sort((a, b) => String(a.day).localeCompare(String(b.day)) || String(a.createdAt).localeCompare(String(b.createdAt)));

  /* ---------- the list of plans ---------- */
  function title() {
    if (ui.view === 'plan') {
      const pl = planById(ui.planId), p = pl && proj(pl.projectId);
      if (pl && p) return `<div class="page-icon pl-icon">${icon('cal')}</div><a class="page-title crumb-link" data-nav="plans">Content plans</a><span class="crumb-sep">/</span><div class="page-title">${esc(p.name)} · ${esc(monthLabel(pl.month))}</div>`;
    }
    return `<div class="page-icon pl-icon">${icon('cal')}</div><div class="page-title">Content plans</div>`;
  }
  function render(c) {
    if (!canSee()) { ui.view = 'home'; return renderContent(); }
    if (ui.view === 'plan') return renderPlan(c);
    const m = st().month;
    const rows = clientsInScope();
    const mine = me().role === 'social';
    const made = rows.filter((p) => planOf(p.id, m)).length;
    c.innerHTML = `<div class="pl-page">
      <div class="pl-bar">
        <div class="cal-nav">
          <button class="icon-btn" data-pl="prev" title="Previous month" ${m <= thisMonth() ? 'disabled' : ''}>${icon('chev-left')}</button>
          <b class="cal-label">${esc(monthLabel(m))}</b>
          <button class="icon-btn" data-pl="next" title="Next month">${icon('chev-right')}</button>
          ${m !== nextMonth() ? `<button class="btn ghost sm" data-pl="reset" title="Back to the month being planned">Back to ${esc(monthLabel(nextMonth()).split(' ')[0])}</button>` : ''}
        </div>
        <span class="pl-count">${made} of ${rows.length} client${rows.length === 1 ? '' : 's'} planned</span>
      </div>
      <p class="pl-intro">${mine ? (isMgr() ? 'As Social Manager you can start or edit any client’s content skeleton.' : 'The clients you’re the Social person for. Start the month’s content skeleton, then add posts on the calendar.') : 'Each client’s plan for the month. Social Executives and the Social Manager make them; you can open and read them.'}</p>
      ${rows.length ? `<div class="team-table pl-table">
        <div class="tt-row tt-head pl-row"><div>Client</div><div>Social</div><div>Account Manager</div><div>Posts</div><div>Status</div><div></div></div>
        ${rows.map((p) => {
          const pl = planOf(p.id, m);
          const ams = (p.ams || []).filter((a) => !a.onLeave && userById(a.id)).map((a) => a.id);
          const act = pl ? `<button class="btn ghost sm" data-pl="open" data-id="${pl.id}">Open</button>` : canEditClient(p.id) ? `<button class="btn primary sm" data-pl="start" data-p="${p.id}">${icon('plus')}Start skeleton</button>` : '';
          return `<div class="tt-row pl-row ${pl ? 'has' : ''}" ${pl ? `data-pl="open" data-id="${pl.id}"` : ''}>
            <div class="tt-name">${clientDot(p)}<span>${esc(p.name)}</span></div>
            <div>${people(socialsOf(p), 'No Social set')}</div>
            <div>${people(ams, 'None')}</div>
            <div class="pl-n">${pl ? (pl.posts || []).length : '–'}</div>
            <div>${statusPill(pl)}</div>
            <div class="pl-act">${act}</div>
          </div>`;
        }).join('')}
      </div>` : `<div class="empty"><div class="big">No clients here yet</div>${mine ? 'Ask an Admin to add you as the Social person in a client’s pop-up.' : 'No active clients.'}</div>`}
    </div>`;
  }

  /* ---------- one plan ---------- */
  function renderPlan(c) {
    const pl = planById(ui.planId), p = pl && proj(pl.projectId);
    if (!pl || !p) { ui.view = 'plans'; return render(c); }
    const ed = canEdit(pl);
    const tab = phone() ? 'list' : st().tab;
    const by = pl.createdBy && userById(pl.createdBy);
    const n = (pl.posts || []).length;
    c.innerHTML = `<div class="pl-page pl-one">
      <div class="pl-head">
        <div class="pl-who">${clientDot(p, 30)}<div><b>${esc(p.name)}</b><span>${esc(monthLabel(pl.month))} · ${n} post${n === 1 ? '' : 's'}${by ? ` · started by ${esc(fullName(by))}` : ''}</span></div>${statusPill(pl)}</div>
        <span class="spacer"></span>
        ${phone() ? '' : `<div class="cal-seg"><button class="${tab === 'calendar' ? 'on' : ''}" data-pl="tab" data-v="calendar">Calendar</button><button class="${tab === 'list' ? 'on' : ''}" data-pl="tab" data-v="list">List</button></div>`}
        ${headActions(pl)}
      </div>
      ${banner(pl)}
      <div class="pl-body">
        <div class="pl-main">${tab === 'calendar' ? calendar(pl, ed) : listView(pl, ed)}</div>
        ${side(pl, p, ed)}
      </div>
    </div>`;
  }
  function calendar(pl, ed) {
    const m = pl.month, from = monday(firstDay(m)), to = addDays(monday(lastDay(m)), 6);
    const today = todayStr();
    const posts = postsSorted(pl);
    let cells = '';
    for (let d = from; d <= to; d = addDays(d, 1)) {
      const inMonth = d.slice(0, 7) === m;
      const day = inMonth ? posts.filter((x) => x.day === d) : [];
      const all = inMonth ? Occasions.on(d) : [];
      // a long occasion (Ramadan, DSF) is named on its first day and on Mondays
      const occ = all.filter((o) => !o.end || o.date === d || dayGap(o.date, o.end) <= 3 || parseYmd(d).getDay() === 1);
      cells += `<div class="cal-cell pl-cell ${inMonth ? '' : 'out'} ${d === today ? 'today' : ''} ${all.length ? 'occ' : ''}" data-day="${d}">
        <div class="cal-dh"><span class="cal-num">${parseYmd(d).getDate()}</span>${occ.length ? `<span class="cal-occ" title="${esc(occ.map((o) => o.name).join(', '))}">${esc(occ.map((o) => o.name).join(' · '))}</span>` : ''}${ed && inMonth ? `<button class="cal-add" data-pl="new-post" data-d="${d}" title="Add a post on this day">${icon('plus')}</button>` : ''}</div>
        ${day.map((x) => `<button class="pl-chip ${checkCls(pl, x)}" data-pl="post" data-id="${x.id}" style="--c:${fmtOf(x.format).color}" title="${esc((x.title || 'Untitled post') + ' · ' + fmtOf(x.format).name + checkTip(pl, x))}"><span class="pl-chip-t">${checkMark(pl, x)}${esc(x.title || 'Untitled post')}</span><span class="pl-chip-f">${esc(fmtOf(x.format).name)}${x.taskId ? ` · <i style="color:${PROG[progress(x).k][1]}">${esc(SHORT[progress(x).k])}</i>` : ''}</span></button>`).join('')}
      </div>`;
    }
    return `<div class="cal-month pl-month"><div class="cal-wd">${WD.map((w) => `<span>${w}</span>`).join('')}</div><div class="cal-grid">${cells}</div></div>`;
  }
  function listView(pl, ed) {
    const posts = postsSorted(pl);
    if (!posts.length) return `<div class="empty pl-empty"><div class="big">No posts yet</div>${ed ? 'Use <b>Add post</b>, or the + on a day of the calendar.' : 'The Social team hasn’t added any posts yet.'}</div>`;
    const days = [...new Set(posts.map((x) => x.day))];
    return `<div class="pl-list">${days.map((d) => `<section class="pl-lday"><h3>${esc(dayLong(d))}${Occasions.on(d).length ? `<span class="pl-locc">${esc(Occasions.on(d).map((o) => o.name).join(' · '))}</span>` : ''}</h3>
      ${posts.filter((x) => x.day === d).map((x) => postRow(x, pl)).join('')}</section>`).join('')}</div>`;
  }
  function postRow(x, pl) {
    const o = x.occasion && Occasions.byId(x.occasion);
    const n = (x.refs || []).length;
    const g = progress(x);
    const img = g.files.find((r) => fileKind(r) === 'image') || (x.refs || []).find((r) => r.path && fileKind(r) === 'image');
    return `<button class="pl-post ${checkCls(pl, x)}" data-pl="post" data-id="${x.id}">
      <span class="pl-thumb">${img ? `<img src="${imgUrl(img, 160)}" alt="" loading="lazy">` : `<span class="pl-thumb-f" style="--c:${fmtOf(x.format).color}">${esc(fmtOf(x.format).name.slice(0, 1))}</span>`}</span>
      <span class="pl-post-txt"><b>${checkMark(pl, x)}${esc(x.title || 'Untitled post')}</b><span>${x.check && x.check.state === 'changes' && x.check.note && pl.status !== 'approved' ? `<i class="pl-chg-note">${esc(x.check.note)}</i>` : esc(String(x.desc || x.copyEn || '').replace(/\s+/g, ' ').slice(0, 140))}</span></span>
      <span class="pl-post-meta">${x.taskId ? progPill(g) : ''}${fmtPill(x.format)}${chChips(x.channels)}${o ? `<span class="cal-occ-pill">${esc(o.name)}</span>` : ''}${n ? `<span class="pl-refs">${icon('clip')}${n}</span>` : ''}</span>
    </button>`;
  }
  function side(pl, p, ed) {
    const occs = Occasions.between(firstDay(pl.month), lastDay(pl.month));
    const posts = pl.posts || [];
    const row = (o) => {
      const n = posts.filter((x) => x.occasion === o.id).length;
      const sk = !n && skipped(p, o);
      const stt = n ? 'ok' : sk ? 'skip' : 'miss';
      return `<div class="pl-occ ${stt}">
        <span class="pl-occ-ic">${n ? icon('check') : sk ? '–' : '!'}</span>
        <div class="pl-occ-txt"><b>${esc(o.name)}</b><span>${o.est ? 'Expected · ' : ''}${esc(Occasions.fmt(o))} · ${n ? `${n} post${n === 1 ? '' : 's'} planned` : sk ? 'Skipped for this client' : 'Not planned yet'}</span></div>
        ${ed && !n ? `<div class="pl-occ-acts">${sk ? `<button class="btn ghost xs" data-pl="unskip" data-o="${esc(o.id)}">Undo skip</button>` : `<button class="btn ghost xs" data-pl="occ-post" data-o="${esc(o.id)}">Plan a post</button><button class="btn ghost xs" data-pl="skip" data-o="${esc(o.id)}">Skip for this client</button>`}</div>` : ''}
      </div>`;
    };
    const next = Occasions.between(firstDay(shiftMonth(pl.month, 1)), lastDay(shiftMonth(pl.month, 3))).filter((o) => o.date > lastDay(pl.month)).slice(0, 6);
    const todo = occs.filter((o) => !posts.some((x) => x.occasion === o.id) && !skipped(p, o)).length;
    return `<aside class="cal-side pl-side">
      <section class="cal-box"><div class="cal-box-h"><h3>Occasions this month</h3>${occs.length ? `<span class="pl-occ-sum ${todo ? 'warn' : 'ok'}">${todo ? `${todo} to plan` : 'All covered'}</span>` : ''}</div>
        ${occs.length ? occs.map(row).join('') : '<div class="cal-muted">No occasions this month</div>'}
      </section>
      <section class="cal-box"><h3>Coming next</h3>
        ${next.length ? next.map((o) => `<div class="pl-next"><b>${esc(o.name)}</b><span>${o.est ? 'Expected · ' : ''}${esc(Occasions.fmt(o))}</span></div>`).join('') : '<div class="cal-muted">Nothing in the next months</div>'}
        <p class="cal-muted pl-next-note">Plan shoots early for these.</p>
      </section>
    </aside>`;
  }

  /* ---------- approval: the head, the banner, the marks ---------- */
  const showChecks = (pl) => pl.status === 'review' || pl.status === 'changes';
  const checkCls = (pl, x) => (!showChecks(pl) || !x.check ? '' : x.check.state === 'ok' ? 'ok' : 'chg');
  const checkMark = (pl, x) => (!showChecks(pl) || !x.check ? '' : x.check.state === 'ok' ? `<span class="pl-mk ok" title="Looks good">${icon('check')}</span>` : '<span class="pl-mk chg" title="Changes asked">!</span>');
  const checkTip = (pl, x) => (!showChecks(pl) || !x.check ? '' : x.check.state === 'ok' ? ' · Looks good' : ` · Changes asked${x.check.note ? ': ' + x.check.note : ''}`);
  function headActions(pl) {
    const out = [];
    const ed = canEdit(pl), editor = isEditor(pl), appr = canApprove(pl);
    if (ed) out.push(`<button class="btn sm" data-pl="new-post">${icon('plus')}Add post</button>`, `<button class="btn primary sm" data-pl="send">${icon('send')}${pl.status === 'changes' ? 'Send again' : 'Send for approval'}</button>`);
    if (canMakeTasks(pl) && (pl.posts || []).some((x) => !x.taskId || !task(x.taskId))) out.push(`<button class="btn primary sm" data-pl="make-tasks">${icon('plus')}Create tasks</button>`);
    if (canMakeTasks(pl) && hasTasks(pl) && !pl.clientApproved) {
      if ((pl.exports || []).length) out.push(`<button class="btn sm" data-pl="reply">${icon('reply')}Client’s reply</button>`);
      if ((pl.posts || []).some((x) => progress(x).fin && !progress(x).t.done)) out.push(`<button class="btn ${(pl.exports || []).length ? '' : 'primary '}sm" data-pl="export">${icon('download')}Export for client</button>`);
      if (allFinished(pl) && (pl.exports || []).length) out.push(`<button class="btn primary sm" data-pl="client-all">${icon('check')}Client approved</button>`);
    }
    if (pl.status === 'review' && appr) out.push(`<button class="btn sm" data-pl="send-back">${icon('edit')}Send back for changes</button>`, `<button class="btn primary sm" data-pl="approve">${icon('check')}Approve skeleton</button>`);
    if (editor || appr) out.push(`<button class="icon-btn" data-pl="plan-menu" title="Skeleton options">${icon('more')}</button>`);
    return out.length ? out.join('') : '<span class="pl-ro">View only</span>';
  }
  function banner(pl) {
    const who = (id) => (id === currentUserId ? 'You' : userById(id) ? fullName(userById(id)) : 'Someone');
    const last = (act) => (pl.log || []).filter((x) => x.act === act).pop();
    if (pl.status === 'review' && pl.review) {
      const r = pl.review;
      return `<div class="pl-banner review">${icon('clock')}<div><b>${esc(who(r.by))} sent this content skeleton to ${esc(toLabel(r.to))} for approval${r.round > 1 ? ` · Round ${r.round}` : ''}</b><span>${esc(timeAgo(r.at))}${canApprove(pl) ? ' · Open each post to mark it Looks good or Ask for changes, then approve the skeleton or send it back.' : isEditor(pl) ? ' · It can’t be changed while it waits. Take it back from ••• to change something.' : ''}</span></div></div>`;
    }
    if (pl.status === 'changes') {
      const l = last('changes'), n = (pl.posts || []).filter((x) => x.check && x.check.state === 'changes').length;
      return `<div class="pl-banner changes">${icon('edit')}<div><b>${esc(l ? who(l.by) : 'The approver')} asked for changes${n ? ` on ${n} post${n === 1 ? '' : 's'}` : ''}</b>${l && l.note ? `<p>${esc(l.note)}</p>` : ''}<span>${l ? esc(timeAgo(l.at)) : ''}${isEditor(pl) ? ' · Make the changes, then Send again.' : ''}</span></div></div>`;
    }
    if (pl.status === 'approved' && pl.clientApproved) {
      const ca = pl.clientApproved;
      return `<div class="pl-banner approved">${icon('check-circle')}<div><b>The client approved the content plan</b><span>${esc(fmtDateTime(ca.at))}${ca.auto ? ' · every post was approved' : ca.by ? ` · recorded by ${esc(who(ca.by))}` : ''}${pl.filedDeck ? ' · The approved PowerPoint and each post’s final files are in Client Assets › Files.' : ''}</span>${exportLinks(pl)}</div></div>`;
    }
    if (pl.status === 'approved' && (pl.exports || []).length) {
      const ex = pl.exports[pl.exports.length - 1];
      const sent = pl.sent && pl.sent.round === ex.round;
      const posts = pl.posts || [];
      const ap = posts.filter((x) => progress(x).k === 'done').length, ch = posts.filter((x) => progress(x).k === 'changes' || (x.client && x.client.state === 'changes' && x.client.round === ex.round && progress(x).k !== 'done')).length;
      return `<div class="pl-banner client">${icon('send')}<div><b>${sent ? `Content plan with the client · Round ${ex.round}` : `Round ${ex.round} exported — not marked as sent yet`}</b><span>${sent ? `Sent ${esc(fmtDay(pl.sent.at.slice(0, 10)))}` : `Exported ${esc(timeAgo(ex.at))}`} · ${ex.posts.length} post${ex.posts.length === 1 ? '' : 's'} in it${ap ? ` · ${ap} client approved` : ''}${ch ? ` · ${ch} with client changes` : ''}${allFinished(pl) ? ' · Every post is finished: mark it Client approved when the client says yes.' : ''}</span>
        ${exportLinks(pl)}${!sent && canMakeTasks(pl) ? '<button class="btn ghost xs pl-sent" data-pl="mark-sent">Mark as sent to the client</button>' : ''}</div></div>`;
    }
    if (pl.status === 'approved' && pl.approval) {
      const posts = pl.posts || [], made = posts.filter((x) => x.taskId).length;
      if (made) {
        const gs = posts.map(progress), ready = gs.filter((g) => g.k === 'ready' || g.k === 'done').length;
        const left = posts.length - made;
        return `<div class="pl-banner approved">${icon('check-circle')}<div><b>${ready} of ${posts.length} post${posts.length === 1 ? '' : 's'} finished (CD approved)</b><span>Skeleton approved by ${esc(who(pl.approval.by))} · ${made} task${made === 1 ? '' : 's'} made${left ? ` · ${left} post${left === 1 ? '' : 's'} without a task yet` : ''} · The CD-approved video or graphic comes into each post by itself.</span></div></div>`;
      }
      return `<div class="pl-banner approved">${icon('check-circle')}<div><b>Content skeleton approved by ${esc(who(pl.approval.by))}</b><span>${esc(fmtDateTime(pl.approval.at))} · Next: ${canMakeTasks(pl) ? 'Create tasks from it.' : 'Social, the CD or the Account Manager creates the tasks.'}</span></div></div>`;
    }
    return '';
  }
  function notify(ids, pl, kind, text, snippet = '') {
    [...new Set(ids)].forEach((to) => {
      const u = to && userById(to);
      if (!u || to === currentUserId || u.active === false) return;
      db.notifications.push({ id: uid(), to, from: currentUserId, kind, planId: pl.id, text, snippet: String(snippet || '').slice(0, 300), at: nowISO(), read: false });
    });
  }
  const logIt = (pl, act, extra = {}) => { pl.log = (pl.log || []).concat({ act, by: currentUserId, at: nowISO(), round: pl.round || 1, ...extra }); pl.updatedAt = nowISO(); };
  function sendFlow(pl) {
    if (!canEdit(pl)) return denied();
    if (!(pl.posts || []).length) { toast('Add at least one post first'); return; }
    const p = proj(pl.projectId);
    const cd = cdUserId(), sms = socialMgrIds().filter((id) => id !== pl.createdBy);
    const opts = [sms.length && ['sm', `Social Manager${sms.length === 1 ? ` (${firstName(sms[0])})` : ''}`], cd && ['cd', `${fullName(userById(cd))} (CD)`], sms.length && cd && ['both', 'Both']].filter(Boolean);
    if (!opts.length) { toast('There’s no Social Manager or Creative Director to send it to'); return; }
    const missing = Occasions.between(firstDay(pl.month), lastDay(pl.month)).filter((o) => !(pl.posts || []).some((x) => x.occasion === o.id) && !skipped(p, o));
    let to = (pl.review && opts.some(([k]) => k === pl.review.to) && pl.review.to) || opts[0][0];
    const root = $('#overlay-root');
    root.innerHTML = `<div class="scrim"><div class="dialog pl-send-dlg" role="dialog" aria-label="Send for approval">
      <h2>${pl.status === 'changes' ? 'Send the skeleton again' : 'Send for approval'}</h2>
      <p>${esc(p.name)}’s content skeleton for ${esc(monthLabel(pl.month))} · ${(pl.posts || []).length} post${(pl.posts || []).length === 1 ? '' : 's'}. One approval is enough.</p>
      <label class="dlg-label">Send to</label>
      <div class="pl-pick" id="ps-to">${opts.map(([k, l]) => `<button type="button" class="pl-opt ${k === to ? 'on' : ''}" data-to="${k}" style="--c:var(--accent)">${esc(l)}</button>`).join('')}</div>
      ${pl.createdBy && isMgr(userById(pl.createdBy)) ? '<div class="dlg-hint">Made by the Social Manager, so it goes to the Creative Director.</div>' : ''}
      ${missing.length ? `<div class="pl-warn">${icon('info')}<div><b>Not planned yet: ${esc(missing.map((o) => o.name).join(', '))}</b><span>Plan a post for ${missing.length === 1 ? 'it' : 'them'}, or Skip for this client from the occasions list, or send anyway.</span></div></div>` : ''}
      <div class="actions"><button class="btn" data-r="0">Cancel</button><button class="btn primary" data-r="1">${missing.length ? 'Send anyway' : 'Send'}</button></div>
    </div></div>`;
    const close = () => { root.innerHTML = ''; };
    $('.scrim', root).addEventListener('click', (e) => {
      if (e.target.classList.contains('scrim')) return close();
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.to) { to = b.dataset.to; $$('#ps-to .pl-opt', root).forEach((x) => x.classList.toggle('on', x === b)); return; }
      if (b.dataset.r === '0') return close();
      if (b.dataset.r !== '1') return;
      close();
      pl.round = (pl.round || 0) + 1;
      (pl.posts || []).forEach((x) => { if (x.check && x.check.state === 'changes') delete x.check; });   // (the changes were made)
      pl.status = 'review';
      pl.review = { to, by: currentUserId, at: nowISO(), round: pl.round };
      logIt(pl, 'sent', { to });
      notify(approverIds(pl, to), pl, 'plan', `sent the content skeleton for <b>${esc(nameOf(pl))}</b> for your approval${pl.round > 1 ? ` (Round ${pl.round})` : ''}`);
      persist(0); render2();
      toast(`Sent to ${toLabel(to)} for approval`);
    });
  }
  function withdraw(pl) {
    if (!isEditor(pl) || pl.status !== 'review') return denied();
    pl.status = 'draft';
    logIt(pl, 'withdrawn');
    persist(0); render2(); toast('Taken back — you can change it and send it again');
  }
  async function approve(pl) {
    if (!canApprove(pl) || pl.status !== 'review') return denied();
    const flagged = (pl.posts || []).filter((x) => x.check && x.check.state === 'changes').length;
    if (flagged) { toast(`${flagged} post${flagged === 1 ? ' is' : 's are'} marked Ask for changes — send it back instead`); return; }
    const n = (pl.posts || []).length;
    const ok = await dialog({ title: 'Approve this content skeleton?', body: `${nameOf(pl)} · ${n} post${n === 1 ? '' : 's'}. After this, tasks can be created from it.`, okText: 'Approve skeleton' });
    if (!ok) return;
    const now = nowISO();
    (pl.posts || []).forEach((x) => { if (!x.check || x.check.state !== 'ok') x.check = { state: 'ok', by: currentUserId, at: now }; });
    pl.status = 'approved';
    pl.approval = { by: currentUserId, at: now, round: pl.round || 1 };
    logIt(pl, 'approved');
    notify([pl.createdBy, pl.review && pl.review.by, ...approverIds(pl, 'both')], pl, 'plan-ok', `approved the content skeleton for <b>${esc(nameOf(pl))}</b>`);
    persist(0); render2(); toast('Content skeleton approved');
  }
  function sendBack(pl) {
    if (!canApprove(pl) || pl.status !== 'review') return denied();
    const flagged = (pl.posts || []).filter((x) => x.check && x.check.state === 'changes');
    const root = $('#overlay-root');
    root.innerHTML = `<div class="scrim"><div class="dialog pl-send-dlg" role="dialog" aria-label="Send back for changes">
      <h2>Send back for changes</h2>
      <p>${flagged.length ? `${flagged.length} post${flagged.length === 1 ? ' is' : 's are'} marked with your notes. Add anything else here.` : 'Say what should change. You can also open posts and mark them Ask for changes with a note.'}</p>
      <textarea class="field" id="sb-note" rows="4" placeholder="${flagged.length ? 'A note for the whole skeleton (optional)' : 'What should change?'}"></textarea>
      <div class="actions"><button class="btn" data-r="0">Cancel</button><button class="btn primary" data-r="1">Send back</button></div>
    </div></div>`;
    const close = () => { root.innerHTML = ''; };
    setTimeout(() => $('#sb-note', root).focus(), 20);
    $('.scrim', root).addEventListener('click', (e) => {
      if (e.target.classList.contains('scrim')) return close();
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.r === '0') return close();
      if (b.dataset.r !== '1') return;
      const note = $('#sb-note', root).value.trim();
      if (!note && !flagged.length) { $('#sb-note', root).focus(); toast('Say what should change'); return; }
      close();
      pl.status = 'changes';
      logIt(pl, 'changes', { note });
      notify([pl.createdBy, pl.review && pl.review.by], pl, 'plan-changes', `asked for changes on the content skeleton for <b>${esc(nameOf(pl))}</b>`, note || flagged.map((x) => `${x.title}: ${x.check.note || 'changes'}`).join(' · '));
      persist(0); render2(); toast('Sent back to Social');
    });
  }
  async function reopen(pl) {
    if (!(isEditor(pl) || canApprove(pl)) || pl.status !== 'approved') return denied();
    const ok = await dialog({ title: 'Reopen this content skeleton?', body: 'It goes back to draft so it can be changed, and needs approving again.', okText: 'Reopen' });
    if (!ok) return;
    pl.status = 'draft'; pl.approval = null;
    logIt(pl, 'reopened');
    persist(0); render2(); toast('Reopened as a draft');
  }
  const render2 = () => { renderContent(); renderSidebar(); };

  /* ---------- stage 3: tasks from an approved skeleton ---------- */
  const workers = () => db.users.filter((u) => u.active !== false && (['production', 'social', 'freelancer'].includes(u.role)) && u.id !== cdUserId()).sort((a, b) => fullName(a).localeCompare(fullName(b)));
  const ROLE_H = { production: 'Production', social: 'Social', freelancer: 'Freelancers' };
  function taskNotes(pl, x) {
    const p = proj(pl.projectId), o = x.occasion && Occasions.byId(x.occasion);
    const ch = CH(), chs = (x.channels || []).filter((k) => ch[k]).map((k) => ch[k].name).join(', ');
    const para = (label, v, rtl) => (v ? `<p${rtl ? ' dir="rtl"' : ''}><b>${esc(label)}</b><br>${esc(v).replace(/\n/g, '<br>')}</p>` : '');
    const links = (x.refs || []).filter((r) => r.url);
    return `<p><b>From the content plan:</b> ${esc(p ? p.name : '')} · ${esc(monthLabel(pl.month))}</p>`
      + `<p><b>Go-live:</b> ${esc(dayLong(x.day))} · <b>Format:</b> ${esc(fmtOf(x.format).name)}${chs ? ` · <b>Channels:</b> ${esc(chs)}` : ''}${o ? ` · <b>Occasion:</b> ${esc(o.name)}` : ''}</p>`
      + para('Description', x.desc) + para('Type of shots / shot list', x.shots) + para('Copy · English', x.copyEn) + para('Copy · Arabic', x.copyAr, true)
      + (links.length ? `<p><b>Reference links</b><br>${links.map((r) => `<a href="${esc(r.url)}" target="_blank" rel="noopener">${esc(r.label || r.url)}</a>`).join('<br>')}</p>` : '');
  }
  function makeTasksDialog(pl) {
    if (!canMakeTasks(pl)) return denied();
    const posts = postsSorted(pl).filter((x) => !x.taskId || !task(x.taskId));   // (a task deleted since can be made again)
    if (!posts.length) { toast('Every post already has its task'); return; }
    const today = todayStr();
    const defDue = (d) => { const x = addDays(d, -3); return x < today ? today : x; };
    const rows = posts.map((x) => ({ x, on: true, who: [], due: defDue(x.day) }));
    const root = $('#overlay-root');
    const draw = () => {
      const n = rows.filter((r) => r.on).length;
      $('#mt-rows', root).innerHTML = rows.map((r, i) => `<div class="mt-row ${r.on ? '' : 'off'}">
        <button type="button" class="mt-ck ${r.on ? 'on' : ''}" data-mt="ck" data-i="${i}" aria-label="Include">${r.on ? icon('check') : ''}</button>
        <div class="mt-t"><b>${esc(r.x.title || 'Untitled post')}</b><span>${esc(dayLong(r.x.day))} · ${esc(fmtOf(r.x.format).name)}</span></div>
        <button type="button" class="mt-who" data-mt="who" data-i="${i}">${r.who.length ? `${avatarStack(r.who, 20, 3)}<span>${esc(r.who.map((id) => firstName(id)).join(', '))}</span>` : `<span class="mt-none">${icon('user')}Pick people</span>`}</button>
        <span class="date-chip pl-date mt-due set">${icon('cal')}<span class="date-lbl">${esc(fmtDay(r.due))}</span><input type="date" class="date-in" data-mt="due" data-i="${i}" value="${r.due}"></span>
      </div>`).join('');
      $('[data-r="1"]', root).textContent = n ? `Create ${n} task${n === 1 ? '' : 's'}` : 'Create tasks';
      $('[data-r="1"]', root).disabled = !n;
    };
    root.innerHTML = `<div class="scrim pl-scrim"><div class="dialog pl-dlg mt-dlg" role="dialog" aria-label="Create tasks">
      <div class="pl-dlg-top"><h2>Create tasks</h2><span class="pl-dlg-sub">${esc(nameOf(pl))} · one task per post, with everything from the skeleton</span><button type="button" class="icon-btn" data-r="0" title="Close">${icon('x')}</button></div>
      <div class="pl-dlg-body">
        <div class="mt-bulk"><span>For all</span>
          <select class="field" id="mt-fmt"><option value="">posts</option>${FORMATS.map(([k, name]) => `<option value="${k}">${esc(name)}s</option>`).join('')}</select>
          <button type="button" class="btn ghost sm" data-mt="bulk-who">${icon('user')}People</button>
          <span class="date-chip pl-date mt-due">${icon('cal')}<span class="date-lbl">Due date</span><input type="date" class="date-in" id="mt-bulk-due"></span>
        </div>
        <div id="mt-rows"></div>
      </div>
      <div class="actions"><span class="mt-hint">Due dates are up to you (today is fine). The CD reviews each one as usual.</span><span class="spacer"></span><button class="btn" data-r="0">Cancel</button><button class="btn primary" data-r="1">Create tasks</button></div>
    </div></div>`;
    const close = () => { root.innerHTML = ''; };
    // people: a list with ticks that stays open to pick several
    const pick = (anchor, cur, done) => {
      const ck = (on) => (on ? `<span class="wf-ck">${icon('check')}</span>` : '');
      const items = [];
      ['production', 'social', 'freelancer'].forEach((r) => {
        const us = workers().filter((u) => u.role === r);
        if (!us.length) return;
        items.push({ html: `<div class="wf-mh">${ROLE_H[r]}</div>` });
        us.forEach((u) => items.push({ html: `<div class="mi wf-person">${avatarHTML(u.id, 20)}<span>${esc(fullName(u))}</span>${ck(cur.includes(u.id))}</div>`, run: () => { const next = cur.includes(u.id) ? cur.filter((x) => x !== u.id) : cur.concat(u.id); done(next); setTimeout(() => pick(anchor, next, done), 0); } }));
      });
      const m = showMenu(anchor, items.map((it, i) => (it.run ? { ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) } : it)));
      m.classList.add('wf-menu', 'mt-menu');
    };
    const box = $('.scrim', root);
    box.addEventListener('change', (e) => {
      const el = e.target;
      if (el.dataset.mt === 'due' && el.value) { rows[+el.dataset.i].due = el.value; draw(); }
      if (el.id === 'mt-bulk-due' && el.value) { const f = $('#mt-fmt', root).value; rows.forEach((r) => { if (!f || r.x.format === f) r.due = el.value; }); el.value = ''; draw(); toast('Due date set'); }
    });
    box.addEventListener('click', async (e) => {
      if (e.target.classList.contains('scrim')) return;
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.r === '0') return close();
      if (b.dataset.mt === 'ck') { const r = rows[+b.dataset.i]; r.on = !r.on; draw(); return; }
      if (b.dataset.mt === 'who') { e.stopPropagation(); const r = rows[+b.dataset.i]; pick(b, r.who, (v) => { r.who = v; draw(); }); return; }
      if (b.dataset.mt === 'bulk-who') {
        e.stopPropagation();
        const f = $('#mt-fmt', root).value, targets = rows.filter((r) => !f || r.x.format === f);
        pick(b, [], (v) => { targets.forEach((r) => { r.who = v.slice(); }); draw(); });
        return;
      }
      if (b.dataset.r !== '1') return;
      const go_ = rows.filter((r) => r.on);
      if (!go_.length) return;
      b.disabled = true; b.textContent = 'Creating…';
      const p = proj(pl.projectId);
      const made = [];
      for (const r of go_) {
        const x = (pl.posts || []).find((y) => y.id === r.x.id);
        if (!x || (x.taskId && task(x.taskId))) continue;
        const id = uid();
        let atts = [];
        const files = (x.refs || []).filter((y) => y.path);
        if (files.length) { try { atts = ((await api('POST', '/api/plan-refs', { planId: pl.id, taskId: id, files: files.map((y) => ({ path: y.path, name: y.name, w: y.w, h: y.h })) })).files || []).map((a) => ({ id: uid(), ...a, addedAt: nowISO(), addedBy: currentUserId })); } catch (err) { /* the files stay on the plan */ } }
        const html = taskNotes(pl, x);
        const t = createTask({ id, title: x.title || 'Untitled post', projectId: pl.projectId, assignees: r.who.slice(), due: r.due, golive: x.day, channels: (x.channels || []).slice(), occasion: x.occasion || null,
          notesHtml: html, notes: (() => { const d = document.createElement('div'); d.innerHTML = html; return d.textContent; })(), attachments: atts, planId: pl.id, planPostId: x.id });
        x.taskId = t.id;
        r.who.forEach((u) => pushNotif(u, t, 'assigned', 'assigned you to'));
        made.push(t);
      }
      if (!made.length) { close(); return; }
      pl.tasksAt = nowISO();
      logIt(pl, 'tasks', { n: made.length });
      // the client's Account Managers always hear about it (unless they made them)
      const ams = ((p && p.ams) || []).filter((a) => !a.onLeave).map((a) => a.id);
      notify(ams, pl, 'plan-tasks', `created ${made.length} task${made.length === 1 ? '' : 's'} from the content skeleton for <b>${esc(nameOf(pl))}</b>`);
      close(); persist(0); render2();
      toast(`Created ${made.length} task${made.length === 1 ? '' : 's'} in ${p ? p.name : 'the client'}`);
    });
    draw();
  }

  /* ---------- stage 4: the client round ---------- */
  const allFinished = (pl) => (pl.posts || []).length > 0 && (pl.posts || []).every((x) => { const g = progress(x); return g.t && (g.t.done || g.fin); });
  const fileLink = (f, label) => `<a class="pl-dl" href="${fileUrl(f)}" download="${esc(f.name)}" data-pl="dl">${icon('download')}${esc(label)}</a>`;
  function exportLinks(pl) {
    const ex = (pl.exports || [])[(pl.exports || []).length - 1];
    if (!ex) return '';
    return `<div class="pl-dls">${fileLink(ex.pptx, `PowerPoint · Round ${ex.round}`)}${ex.pdf ? fileLink(ex.pdf, 'PDF') : ''}${pl.exports.length > 1 ? `<button class="btn ghost xs" data-pl="rounds">Earlier rounds</button>` : ''}</div>`;
  }
  function roundsMenu(anchor, pl) {
    showMenu(anchor, (pl.exports || []).slice().reverse().map((ex) => ({ html: `<div class="mi pl-hist"><span>Round ${ex.round} · ${esc(fmtDay(ex.at.slice(0, 10)))}<small><a href="${fileUrl(ex.pptx)}" download="${esc(ex.pptx.name)}">PowerPoint</a>${ex.pdf ? ` · <a href="${fileUrl(ex.pdf)}" download="${esc(ex.pdf.name)}">PDF</a>` : ''}</small></span></div>` })));
  }
  // the client's logo, from Client Assets › Logos: picked the first time, used every time after
  const logosFolder = (p) => { const c = p && clientOfProject(p); return c ? c.folders.find((f) => !f.parentId && /^logos?$/i.test(f.name)) || null : null; };
  const logoFiles = (p) => { const f = logosFolder(p); return f ? (f.files || []).filter((a) => fileKind(a) === 'image') : []; };
  function exportDialog(pl) {
    if (!canMakeTasks(pl)) return denied();
    const p = proj(pl.projectId);
    const posts = postsSorted(pl);
    const ready = posts.filter((x) => { const g = progress(x); return g.fin && g.t && !g.t.done; }).concat(posts.filter((x) => progress(x).k === 'done'));
    const notReady = posts.filter((x) => !ready.includes(x));
    const round = (pl.exports || []).length + 1;
    let logo = (p.planLogo && logoFiles(p).find((a) => a.path === p.planLogo)) || null;
    let picking = !logo && !!clientOfProject(p);
    const root = $('#overlay-root');
    const paint = () => {
      const lf = logoFiles(p);
      root.innerHTML = `<div class="scrim pl-scrim"><div class="dialog pl-dlg ex-dlg" role="dialog" aria-label="Export for client">
        <div class="pl-dlg-top"><h2>Export for client</h2><span class="pl-dlg-sub">${esc(nameOf(pl))} · Round ${round}</span><button type="button" class="icon-btn" data-r="0" title="Close">${icon('x')}</button></div>
        <div class="pl-dlg-body">
          <label class="dlg-label">Client logo</label>
          ${!clientOfProject(p) ? '<div class="pl-none">This client has no Client Assets, so the cover shows its name.</div>'
            : picking ? `<div class="ex-logos">${lf.map((a) => `<button type="button" class="ex-logo ${logo && logo.id === a.id ? 'on' : ''}" data-logo="${a.id}" title="${esc(a.name)}"><img src="${imgUrl(a, 320)}" alt=""><span>${esc(a.name)}</span></button>`).join('')}
                <button type="button" class="ex-logo up" data-x="upload-logo">${icon('upload')}<span>Upload a logo</span></button></div>
                <div class="dlg-hint">${lf.length ? 'Pick the logo for the cover. It’s used every time after; change it here when needed.' : 'There’s no logo in this client’s Client Assets › Logos yet. Upload one: it’s saved there too.'}</div>`
            : `<div class="ex-cur">${logo ? `<img src="${imgUrl(logo, 320)}" alt="">` : ''}<span>${logo ? esc(logo.name) : 'No logo'}</span><button type="button" class="btn ghost xs" data-x="change-logo">Change logo</button></div>`}
          <label class="dlg-label">What goes in</label>
          <div class="ex-sum"><b>${ready.length} finished post${ready.length === 1 ? '' : 's'}</b> (CD approved)${notReady.length ? ` · not in this round: ${esc(notReady.map((x) => x.title).join(', '))}` : ''}</div>
          <div class="ex-list">${ready.map((x, i) => { const g = progress(x); const img = g.files.find((r) => fileKind(r) === 'image'); return `<div class="ex-row"><span class="ex-n">${String(i + 1).padStart(2, '0')}</span><span class="pl-thumb sm">${img ? `<img src="${imgUrl(img, 160)}" alt="">` : `<span class="pl-thumb-f" style="--c:${fmtOf(x.format).color}">${esc(fmtOf(x.format).name.slice(0, 1))}</span>`}</span><span class="ex-t">${esc(x.title)}<small>${esc(dayLong(x.day))} · ${esc(fmtOf(x.format).name)}${g.k === 'done' ? ' · client approved' : ''}</small></span></div>`; }).join('')}</div>
          <label class="ex-send"><input type="checkbox" id="ex-send" checked> Mark it as sent to the client (you email the file yourself)</label>
          <div class="ex-busy" id="ex-busy" hidden><span class="spin"></span>Making the PowerPoint and the PDF… this can take a minute with videos.</div>
          <div id="ex-done"></div>
        </div>
        <div class="actions"><button class="btn" data-r="0">Close</button><button class="btn primary" data-r="1" ${ready.length && (logo || !clientOfProject(p) || !picking) ? '' : 'disabled'}>${icon('download')}Export Round ${round}</button></div>
      </div></div>`;
    };
    paint();
    const close = () => { root.innerHTML = ''; };
    root.onclick = async (e) => {
      const box = $('.ex-dlg', root); if (!box) return;
      const b = e.target.closest('button'); if (!b || !box.contains(b)) return;
      if (b.dataset.r === '0') { root.onclick = null; return close(); }
      if (b.dataset.logo) { logo = logoFiles(p).find((a) => a.id === b.dataset.logo) || null; picking = false; return paint(); }
      if (b.dataset.x === 'change-logo') { picking = true; return paint(); }
      if (b.dataset.x === 'upload-logo') {
        const c = clientOfProject(p); let f = logosFolder(p);
        if (!c) return;
        if (!f) { toast('This client has no Logos folder in Client Assets'); return; }
        const picked = await ServerHost.pickFiles({ multiple: false, accept: 'image/*,.svg' });
        if (!picked.length) return;
        const up = await ServerHost.uploadMany(picked, { dest: f.dir });
        if (!up.length) return;
        const a = { ...up[0], id: uid(), addedAt: nowISO(), addedBy: currentUserId };
        f = logosFolder(p); f.files = (f.files || []).concat(a);
        persist(0);
        logo = a; picking = false; paint();
        toast('Saved in Client Assets › Logos');
        return;
      }
      if (b.dataset.r !== '1') return;
      const send = $('#ex-send', root).checked;
      b.disabled = true; $('#ex-busy', root).hidden = false;
      try {
        const occ = Occasions.between(firstDay(pl.month), lastDay(pl.month)).map((o) => ({ id: o.id, name: o.name, date: o.date, end: o.end || null }));
        const st = await api('POST', '/api/plan-export', { planId: pl.id, logo: logo ? logo.path : null, occasions: occ });
        let r = null;
        for (let i = 0; i < 400 && !r; i++) {
          await new Promise((ok) => setTimeout(ok, 2000));
          const j = await api('GET', '/api/plan-export?job=' + encodeURIComponent(st.job)).catch(() => null);
          if (j && j.state === 'error') throw new Error(j.error);
          if (j && j.state === 'done') r = j;
        }
        if (!r) throw new Error('It’s taking too long — please try again');
        const ex = r.export;
        // (the server saved the export on the plan; add it here at once so the links show)
        if (!(pl.exports || []).some((x) => x.id === ex.id)) pl.exports = (pl.exports || []).concat(ex);
        if (send) { pl.sent = { round: ex.round, at: nowISO(), by: currentUserId }; logIt(pl, 'client-sent', { round: ex.round }); persist(0); }
        $('#ex-busy', root).hidden = true;
        $('#ex-done', root).innerHTML = `<div class="ex-ok">${icon('check-circle')}<div><b>Round ${ex.round} is ready</b><span>Download it and email it to the client.${send ? ' The plan shows it’s with the client.' : ''}</span><div class="pl-dls">${fileLink(ex.pptx, 'PowerPoint')}${ex.pdf ? fileLink(ex.pdf, 'PDF') : '<span class="pl-none">The PDF couldn’t be made</span>'}</div></div></div>`;
        b.remove();
        render2();
      } catch (err) { $('#ex-busy', root).hidden = true; b.disabled = false; toast('Couldn’t export: ' + err.message); }
    };
  }
  function markSent(pl) {
    const ex = (pl.exports || [])[(pl.exports || []).length - 1];
    if (!ex || !canMakeTasks(pl)) return;
    pl.sent = { round: ex.round, at: nowISO(), by: currentUserId };
    logIt(pl, 'client-sent', { round: ex.round });
    persist(0); render2(); toast(`Round ${ex.round} marked as sent to the client`);
  }
  // the client asked for changes on a post: its task goes back to In progress, with the client's words as a comment, and
  // the new version needs the CD's approval again
  function sendBackTask(t, note, links, round) {
    if (!t) return;
    if (t.done) setDone(t, false);
    t.partsDone = {};
    t.needsCD = true; t.reviewEpoch = epochOf(t) + 1;
    if (t.cdStatus) logChange(t, 'the <b>CD Status</b>', CD[t.cdStatus] ? CD[t.cdStatus].label : '', '');
    t.cdStatus = '';
    delete t.clientApproval;
    logActivity(t, `sent it back for the client’s changes (content plan Round ${round}) — <b>needs CD review again</b>`);
    const prog = statusList(t).find((x) => /^in ?-?progress$/i.test(String(x.name).trim()));
    if (prog && t.sectionId !== prog.id) moveTask(t.id, prog.id);
    const text = `Client’s changes (content plan, Round ${round}): ${note || 'see the links'}${(links || []).length ? '\n' + links.join('\n') : ''}`;
    const html = `<b>Client’s changes</b> (content plan, Round ${round}):<br>${esc(note || 'See the links').replace(/\n/g, '<br>')}${(links || []).length ? '<br>' + links.map((u) => `<a href="${esc(u)}" target="_blank" rel="noopener">${esc(u)}</a>`).join('<br>') : ''}`;
    const cid = uid();
    t.comments.push({ id: cid, text, html, at: nowISO(), attachments: [], parentId: null, reactions: {}, authorId: currentUserId });
    notifyWatchers(t, 'comment', 'added the client’s changes on', { snippet: trunc(text, 160), commentId: cid });
    t.updatedAt = nowISO();
  }
  function approveTask(t) {
    if (!t || t.done) return true;
    if (!cdApprovedNow(t) && t.needsCD) return false;
    setClientApproval(t, {});
    setDone(t, true);
    return true;
  }
  // The client's comment on a post, read from their PowerPoint: does it just say "approved"?
  //  'auto'    — this client's usual way of saying it (remembered on the client: project.approvalWords)
  //  'ask'     — no comment, or sounds like approval and asks for nothing: the person asks themselves (never approved by a guess)
  //  'changes' — anything else, including "approved, but…"
  const normWords = (t) => String(t || '').toLowerCase().replace(/[\u064B-\u0652\u0640]/g, '').replace(/[أإآ]/g, 'ا').replace(/[.!,;:،؛\s]+/g, ' ').trim();
  const YES = /\b(approved?|approval|ok|okay|okey|okk+|good to go|go ahead|go for it|looks? (good|great|perfect|fine|amazing)|all good|perfect|great|love (it|this|this one)|loved it|fine|confirmed?|agreed?|yes|yep|nice|well done|amazing|excellent|superb|brilliant|good job|great job|thank you|thanks|noted)\b|👍|✅|👌|💯|🙌|👏|❤️|♥|موافق|موافقين|موافقه|تمام|ممتاز|ممتازه|حلو|جميل|رائع|معتمد|اعتماد|اوكي|اوك|يعطيكم العافيه|شكرا/i;
  const ASK_CHANGE = /\b(but|however|except|although|though|change|changes|changed|replace|remove|delete|add|adding|update|fix|instead|can you|could you|can we|could we|would you|should|shouldn't|make it|make the|more|less|bigger|smaller|larger|too|not|don't|dont|no|revise|revision|amend|edit|adjust|move|swap|use the|increase|decrease|reduce|correct|typo|wrong|missing|resize|align|font|colour|color|logo|size|text|copy|caption|date|price)\b|\?|لكن|بس |تغيير|غير|غيروا|عدل|عدلوا|تعديل|ممكن|يرجى|الرجاء|بدل|اضف|اضافه|احذف|حذف|شيل|لا |ليس|بدون|اكبر|اصغر|كبر|صغر|الخط|اللون|الشعار|السعر|التاريخ/i;
  function readApproval(text, learned) {
    const n = normWords(text);
    if (!n) return 'ask';   // no comment is a question too: never taken as approval by itself
    if ((learned || []).includes(n)) return 'auto';
    return YES.test(n) && !ASK_CHANGE.test(' ' + n + ' ') && n.length <= 160 ? 'ask' : 'changes';
  }
  function replyDialog(pl) {
    if (!canMakeTasks(pl)) return denied();
    const ex = (pl.exports || [])[(pl.exports || []).length - 1];
    if (!ex) return;
    const posts = postsSorted(pl).filter((x) => ex.posts.includes(x.id));
    const rows = posts.map((x) => { const g = progress(x); return { x, g, locked: g.k === 'done', state: g.k === 'done' ? 'approved' : null, note: '', links: [], comment: '', ask: false, auto: false, remember: false, confirmed: false }; });
    const client = proj(pl.projectId);
    const learned = () => (client && client.approvalWords) || [];
    const asking = () => rows.filter((r) => !r.locked && r.ask).length;
    const root = $('#overlay-root');
    let hint = '';
    const paint = () => {
      root.innerHTML = `<div class="scrim pl-scrim"><div class="dialog pl-dlg rp-dlg" role="dialog" aria-label="Client's reply">
        <div class="pl-dlg-top"><h2>Client’s reply</h2><span class="pl-dlg-sub">${esc(nameOf(pl))} · Round ${ex.round}</span><button type="button" class="icon-btn" data-r="0" title="Close">${icon('x')}</button></div>
        <div class="pl-dlg-body">
          <div class="rp-up"><button type="button" class="btn sm" data-x="upload">${icon('upload')}Upload the client’s PowerPoint</button><span>Their comments and links go on each post by themselves. Or mark each post below.</span></div>
          ${hint ? `<div class="rp-hint">${hint}</div>` : ''}
          ${rows.map((r, i) => { const img = r.g.files.find((f) => fileKind(f) === 'image'); return `<div class="rp-row ${r.state || ''}">
            <span class="pl-thumb sm">${img ? `<img src="${imgUrl(img, 160)}" alt="">` : `<span class="pl-thumb-f" style="--c:${fmtOf(r.x.format).color}">${esc(fmtOf(r.x.format).name.slice(0, 1))}</span>`}</span>
            <div class="rp-main"><b>${esc(r.x.title)}</b><small>${esc(dayLong(r.x.day))} · ${esc(fmtOf(r.x.format).name)}</small>
              ${!r.locked && r.comment && (r.state !== 'changes' || r.ask) ? `<div class="rp-quote"><i>Client comment</i>${esc(r.comment).replace(/\n/g, '<br>')}</div>` : ''}
              ${r.locked ? '<span class="pl-prog" style="--c:#5b9bff">Client approved</span>' : r.ask ? `<div class="rp-ask"><span>${r.comment ? 'This looks approved. Is it?' : 'No comment from the client. Approved?'}</span><button type="button" class="btn sm rp-yes" data-ask="yes" data-i="${i}">${icon('check')}Yes, approved</button><button type="button" class="btn sm rp-no" data-ask="no" data-i="${i}">${icon('edit')}No, changes</button></div>` : `<div class="pl-pick rp-pick"><button type="button" class="pl-opt ${r.state === 'approved' ? 'on' : ''}" style="--c:var(--green)" data-st="approved" data-i="${i}">${icon('check')}Approved</button><button type="button" class="pl-opt ${r.state === 'changes' ? 'on' : ''}" style="--c:#ff8a4c" data-st="changes" data-i="${i}">${icon('edit')}Changes</button><button type="button" class="pl-opt ${!r.state ? 'on' : ''}" style="--c:var(--text-3)" data-st="" data-i="${i}">No reply yet</button></div>
              ${r.state === 'approved' && r.auto ? `<div class="rp-learn">Approved: ${esc(nameOf(pl))}’s usual wording</div>` : ''}
              ${r.state === 'approved' && r.comment && !r.auto ? `<label class="rp-learn"><input type="checkbox" class="rp-rem" data-i="${i}" ${r.remember ? 'checked' : ''}>Remember “${esc(trunc(normWords(r.comment), 60))}” as approval for ${esc(nameOf(pl))}</label>` : ''}
              ${r.state === 'changes' ? `<textarea class="field rp-note" data-i="${i}" rows="2" placeholder="What the client wants changed">${esc(r.note)}</textarea>${r.links.length ? `<div class="rp-links">${r.links.map((u) => `<a href="${esc(u)}" target="_blank" rel="noopener">${esc(u)}</a>`).join('')}</div>` : ''}` : ''}`}
            </div></div>`; }).join('')}
        </div>
        <div class="actions"><span class="mt-hint">${asking() ? `Answer the ${asking() === 1 ? 'post' : asking() + ' posts'} in yellow first. ` : ''}Approved posts are completed (their final files go to Client Assets). Changes send the task back to In progress, and the new version goes to the CD again.</span><span class="spacer"></span><button class="btn" data-r="0">Cancel</button><button class="btn primary" data-r="1" ${asking() ? 'disabled' : ''}>Save the reply</button></div>
      </div></div>`;
    };
    paint();
    const close = () => { root.innerHTML = ''; root.onclick = null; root.oninput = null; root.onchange = null; };
    root.oninput = (e) => { const t = e.target; if (t.classList.contains('rp-note')) rows[+t.dataset.i].note = t.value; };
    root.onchange = (e) => { const t = e.target; if (t.classList.contains('rp-rem')) rows[+t.dataset.i].remember = t.checked; };
    root.onclick = async (e) => {
      const box = $('.rp-dlg', root); if (!box) return;
      const b = e.target.closest('button'); if (!b || !box.contains(b)) return;
      if (b.dataset.r === '0') return close();
      if (b.dataset.st !== undefined && b.dataset.i !== undefined) { const r = rows[+b.dataset.i]; r.state = b.dataset.st || null; r.auto = false; if (r.state !== 'approved') r.remember = false; if (r.state === 'changes' && !r.note && r.comment) r.note = r.comment; return paint(); }
      if (b.dataset.ask) {
        const r = rows[+b.dataset.i]; r.ask = false; r.confirmed = b.dataset.ask === 'yes';
        r.state = r.confirmed ? 'approved' : 'changes'; r.remember = r.confirmed;
        if (!r.confirmed && !r.note) r.note = r.comment;
        return paint();
      }
      if (b.dataset.x === 'upload') {
        const picked = await ServerHost.pickFiles({ multiple: false, accept: '.pptx' });
        if (!picked.length) return;
        b.disabled = true; b.textContent = 'Reading…';
        try {
          const up = await ServerHost.uploadMany(picked, { taskId: pl.id });
          const r = await api('POST', '/api/plan-return', { planId: pl.id, path: up[0].path });
          const n = { none: 0, auto: 0, ask: 0, ch: 0 };
          rows.forEach((row) => {
            if (row.locked) return;
            const got = r.posts[row.x.id];
            if (!got) return;
            row.comment = got.comments.join('\n').trim(); row.links = got.links; row.ask = false; row.auto = false; row.remember = false;
            const k = got.links.length ? 'changes' : readApproval(row.comment, learned());
            if (k === 'changes') { row.state = 'changes'; row.note = row.comment; n.ch++; }
            else if (k === 'ask') { row.state = null; row.ask = true; row.note = ''; n[row.comment ? 'ask' : 'none']++; }
            else { row.state = 'approved'; row.note = ''; row.auto = true; n.auto++; }
          });
          const pl2 = (c, one, many) => `${c} ${c === 1 ? one : many}`;
          const bits = [];
          if (n.none) bits.push(`<b>${pl2(n.none, 'post', 'posts')}</b> with no comment (please check)`);
          if (n.auto) bits.push(`<b>${pl2(n.auto, 'post', 'posts')}</b> approved in ${esc(nameOf(pl))}’s usual wording`);
          if (n.ask) bits.push(`<b>${pl2(n.ask, 'post', 'posts')}</b> ${n.ask === 1 ? 'looks' : 'look'} approved (please check)`);
          if (n.ch) bits.push(`<b>${pl2(n.ch, 'post', 'posts')}</b> with changes`);
          hint = `Read “${esc(picked[0].name)}”: ${bits.join(', ') || 'no posts found in it'}. Check them before saving.`;
        } catch (err) { toast(err.message); }
        return paint();
      }
      if (b.dataset.r !== '1') return;
      if (asking()) { toast('Answer the posts in yellow first'); return; }
      const todo = rows.filter((r) => !r.locked && r.state);
      if (!todo.length) { toast('Mark at least one post'); return; }
      if (todo.some((r) => r.state === 'changes' && !r.note.trim() && !r.links.length)) { toast('Say what the client wants changed'); return; }
      let ok = 0, ch = 0, skipped = 0;
      const now = nowISO();
      todo.forEach((r) => {
        const x = (pl.posts || []).find((y) => y.id === r.x.id), t = x && x.taskId && task(x.taskId);
        if (!x || !t) return;
        if (r.state === 'approved') { if (approveTask(t)) { x.client = { state: 'approved', round: ex.round, at: now, by: currentUserId, ...(r.comment ? { note: r.comment } : {}) }; ok++; } else skipped++; }
        else { sendBackTask(t, r.note.trim(), r.links, ex.round); x.client = { state: 'changes', note: r.note.trim(), links: r.links, round: ex.round, at: now, by: currentUserId }; ch++; }
      });
      // this client's ways of saying "approved", for the next rounds
      const words = rows.filter((r) => r.state === 'approved' && r.remember && r.comment).map((r) => normWords(r.comment)).filter((w) => w && w.length <= 160);
      if (client && words.length) client.approvalWords = [...new Set([...words, ...learned()])].slice(0, 60);
      logIt(pl, 'client', { round: ex.round, approved: ok, changes: ch });
      close(); persist(0); render2();
      toast(`Saved: ${ok} approved${ch ? `, ${ch} sent back for changes` : ''}${skipped ? ` · ${skipped} not finished yet` : ''}`);
    };
  }
  async function clientApproveAll(pl) {
    if (!canMakeTasks(pl) || !allFinished(pl)) return denied();
    const p = proj(pl.projectId);
    const ok = await dialog({ title: 'Did the client approve the content plan?', body: `All of ${p.name}’s ${monthLabel(pl.month)} posts are marked client approved and completed. Their final files and the approved PowerPoint go to Client Assets › Files › Content plan – ${monthLabel(pl.month)}.`, okText: 'Yes, client approved' });
    if (!ok) return;
    const now = nowISO();
    let n = 0;
    (pl.posts || []).forEach((x) => { const t = x.taskId && task(x.taskId); if (t && !t.done && approveTask(t)) { n++; } if (t && t.done && !(x.client && x.client.state === 'approved')) x.client = { state: 'approved', round: (pl.exports || []).length, at: now, by: currentUserId }; });
    pl.clientApproved = { at: now, by: currentUserId };
    logIt(pl, 'client-approved');
    notify([pl.createdBy, ...socialsOf(p), ...socialMgrIds(), ...((p.ams || []).filter((x) => !x.onLeave).map((x) => x.id))], pl, 'plan-client', `recorded the client’s approval of the content plan for <b>${esc(nameOf(pl))}</b>`);
    persist(0); render2();
    toast(`Client approved — ${n} task${n === 1 ? '' : 's'} completed`);
  }

  /* ---------- making and changing ---------- */
  function open(id) { ui.planId = id; go('plan'); }
  function startPlan(pid, month) {
    if (!canEditClient(pid)) return denied();
    const had = planOf(pid, month);
    if (had) return open(had.id);
    const pl = { id: 'pl-' + uid(), projectId: pid, month, status: 'draft', createdBy: currentUserId, createdAt: nowISO(), updatedAt: nowISO(), posts: [] };
    list().push(pl);
    persist(0);
    open(pl.id);
    toast(`Started ${proj(pid).name}’s content skeleton for ${monthLabel(month)}`);
  }
  function setSkip(pl, oid, skip) {
    const p = proj(pl.projectId), o = Occasions.byId(oid);
    if (!p || !o || !canEdit(pl)) return denied();
    const k = occKey(o);
    p.planSkips = (p.planSkips || []).filter((x) => x !== k);
    if (skip) p.planSkips.push(k);
    if (!p.planSkips.length) delete p.planSkips;
    persist(0); renderContent();
    toast(skip ? `${o.name} skipped for ${p.name} — it stays skipped next year too` : `${o.name} is back on ${p.name}’s list`);
  }
  function planMenu(anchor, pl) {
    const items = [];
    if (pl.status === 'review' && isEditor(pl)) items.push({ label: 'Take it back to change it', icon: 'reply', run: () => withdraw(pl) });
    if (pl.status === 'approved' && !hasTasks(pl) && (isEditor(pl) || canApprove(pl))) items.push({ label: 'Reopen as a draft', icon: 'edit', run: () => reopen(pl) });
    items.push({ html: `<div class="menu-label">History</div>` });
    const acts = { sent: 'sent it for approval', 'client-sent': 'sent it to the client', approved: 'approved it', changes: 'asked for changes', withdrawn: 'took it back', reopened: 'reopened it', tasks: 'created tasks', export: 'exported it for the client', client: 'saved the client’s reply', 'client-approved': 'recorded the client’s approval' };
    (pl.log || []).slice(-6).reverse().forEach((x) => items.push({ html: `<div class="mi pl-hist">${avatarHTML(x.by, 18)}<span>${esc(firstName(x.by))} ${acts[x.act] || x.act}<small>${esc(timeAgo(x.at))}</small></span></div>` }));
    if (!(pl.log || []).length) items.push({ html: '<div class="mi-note">Not sent yet</div>' });
    if (isEditor(pl) && editable(pl)) items.push('-', { label: 'Delete this skeleton', icon: 'trash', danger: true, run: () => delPlan(pl) });
    showMenu(anchor, items);
  }
  async function delPlan(pl) {
    const n = (pl.posts || []).length, name = proj(pl.projectId).name;
    const ok = await dialog({ title: 'Delete this content skeleton?', body: `${name}’s ${monthLabel(pl.month)} skeleton${n ? ` and its ${n} post${n === 1 ? '' : 's'}` : ''} will be deleted.`, okText: 'Delete', danger: true });
    if (!ok) return;
    db.plans = list().filter((x) => x.id !== pl.id);
    persist(0); go('plans'); toast('Deleted');
  }

  /* ---------- a post: the pop-up ---------- */
  function postDialog(pl, x, preset = {}) {
    const ed = canEdit(pl);
    const isNew = !x;
    const m = pl.month;
    // the approver's look at this post while the skeleton waits for approval
    const appr = !isNew && pl.status === 'review' && canApprove(pl);
    const ck = { state: x && x.check ? x.check.state : null, note: x && x.check ? x.check.note || '' : '' };
    const checkBox = () => {
      if (appr) return `<div class="pl-check" id="pp-check"><div class="pl-check-btns"><button type="button" class="pl-opt ${ck.state === 'ok' ? 'on' : ''}" data-ck="ok" style="--c:var(--green)">${icon('check')}Looks good</button><button type="button" class="pl-opt ${ck.state === 'changes' ? 'on' : ''}" data-ck="changes" style="--c:var(--amber)">${icon('edit')}Ask for changes</button></div>
        <textarea class="field" id="pp-cknote" rows="2" placeholder="What should change in this post?" ${ck.state === 'changes' ? '' : 'hidden'}>${esc(ck.note)}</textarea></div>`;
      if (x && x.check && x.check.state === 'changes' && showChecks(pl)) return `<div class="pl-check chg">${icon('edit')}<div><b>${esc(firstName(x.check.by))} asked for changes</b>${x.check.note ? `<p>${esc(x.check.note)}</p>` : ''}</div></div>`;
      if (x && x.check && x.check.state === 'ok' && showChecks(pl)) return `<div class="pl-check ok">${icon('check')}<div><b>${esc(firstName(x.check.by))}: looks good</b></div></div>`;
      return '';
    };
    const pd = preset.day || null;
    const d0 = !pd ? firstDay(m) : pd.slice(0, 7) === m ? pd : pd < firstDay(m) ? firstDay(m) : lastDay(m);
    const s = {
      day: x ? x.day : d0, title: x ? x.title || '' : preset.title || '', format: x ? x.format || 'post' : 'post', channels: x ? (x.channels || []).slice() : ['ig'],
      occasion: x ? x.occasion || null : preset.occasion || null, desc: x ? x.desc || '' : '', shots: x ? x.shots || '' : '', copyEn: x ? x.copyEn || '' : '', copyAr: x ? x.copyAr || '' : '',
      refs: x ? (x.refs || []).map((r) => ({ ...r })) : [],
    };
    if (isNew && !s.occasion) { const sug = Occasions.suggest(s.day)[0]; if (sug) s.occasion = sug.id; }
    const ch = CH();
    const occs = Occasions.between(addDays(firstDay(m), -7), addDays(lastDay(m), 7));
    const root = $('#overlay-root');
    const ro = ed ? '' : 'readonly';
    root.innerHTML = `<div class="scrim pl-scrim"><form class="dialog pl-dlg" autocomplete="off" role="dialog" aria-label="${isNew ? 'New post' : 'Post'}">
      <div class="pl-dlg-top"><h2>${isNew ? 'New post' : ed ? 'Edit post' : 'Post'}</h2><span class="pl-dlg-sub">${esc(proj(pl.projectId).name)} · ${esc(monthLabel(m))}</span><button type="button" class="icon-btn" data-pp="close" title="Close">${icon('x')}</button></div>
      <div class="pl-dlg-body">
        ${checkBox()}
        ${x && x.client && x.client.state === 'changes' && progress(x).k !== 'done' ? `<div class="pl-check chg">${icon('edit')}<div><b>Client’s changes · Round ${x.client.round}</b>${x.client.note ? `<p>${esc(x.client.note)}</p>` : ''}${(x.client.links || []).map((u) => `<p><a href="${esc(u)}" target="_blank" rel="noopener">${esc(u)}</a></p>`).join('')}</div></div>` : ''}
        ${x && x.taskId ? (() => { const g = progress(x); return `<div class="pl-task-box"><div class="pl-task-h">${progPill(g)}${g.t ? `<a class="pl-task-l" data-pp="task" data-id="${g.t.id}">${icon('open')}Open the task</a><span class="pl-task-who">${avatarStack(g.t.assignees || [], 20, 4)}${g.t.due ? `<small>Due ${esc(fmtDay(g.t.due))}</small>` : ''}</span>` : '<small>The task was deleted</small>'}</div>
          ${g.files.length ? `<div class="pl-dlg-sub2">Finished work (CD approved)</div><div class="pl-ref-grid">${g.files.map((r) => `<div class="pl-ref" title="${esc(r.name)}"><button type="button" class="pl-ref-img" data-pp="viewf" data-id="${r.id}">${fileKind(r) === 'image' ? `<img src="${imgUrl(r, 320)}" alt="">` : `<span class="pl-ref-ext">${esc(fileExt(r.name) || 'file')}</span>`}${fileKind(r) === 'video' ? `<span class="tile-play">${icon('play')}</span>` : ''}</button><span class="pl-ref-n">${esc(r.name)}</span></div>`).join('')}</div>` : g.t ? '<div class="pl-none">The video or graphic shows here once the CD approves it.</div>' : ''}</div>`; })() : ''}
        <label class="dlg-label" for="pp-title">Title</label>
        <input class="field" id="pp-title" maxlength="120" placeholder="e.g. Territory 2026 offer" value="${esc(s.title)}" ${ro}>
        <div class="pl-grid2">
          <div><label class="dlg-label">Go-live</label><span class="date-chip pl-date set">${icon('cal')}<span class="date-lbl">${esc(dayLong(s.day))}</span>${ed ? `<input type="date" class="date-in" id="pp-day" value="${s.day}" min="${firstDay(m)}" max="${lastDay(m)}">` : ''}</span></div>
          <div><label class="dlg-label" for="pp-occ">Occasion</label><select class="field" id="pp-occ" ${ed ? '' : 'disabled'}><option value="">None</option>${occs.map((o) => `<option value="${esc(o.id)}" ${o.id === s.occasion ? 'selected' : ''}>${esc(o.name)} · ${esc(Occasions.fmt(o))}</option>`).join('')}</select></div>
        </div>
        <label class="dlg-label">Format</label>
        <div class="pl-pick" id="pp-fmt">${FORMATS.map(([k, name, color]) => `<button type="button" class="pl-opt ${s.format === k ? 'on' : ''}" data-fmt="${k}" style="--c:${color}" ${ed ? '' : 'disabled'}>${esc(name)}</button>`).join('')}</div>
        <label class="dlg-label">Channels</label>
        <div class="pl-pick" id="pp-ch">${Cal.CHANNELS.map(([k, name]) => `<button type="button" class="pl-opt ${s.channels.includes(k) ? 'on' : ''}" data-ch="${k}" style="--c:${ch[k].color}" ${ed ? '' : 'disabled'}>${esc(name)}</button>`).join('')}</div>
        <label class="dlg-label" for="pp-desc">Description</label>
        <textarea class="field" id="pp-desc" rows="3" placeholder="The idea: what the post says and shows" ${ro}>${esc(s.desc)}</textarea>
        <label class="dlg-label" for="pp-shots">Type of shots / shot list</label>
        <textarea class="field" id="pp-shots" rows="3" placeholder="e.g. 1. Drone, car on a desert road at sunrise (3s)…" ${ro}>${esc(s.shots)}</textarea>
        <div class="pl-grid2">
          <div><label class="dlg-label" for="pp-en">Copy · English</label><textarea class="field" id="pp-en" rows="4" ${ro}>${esc(s.copyEn)}</textarea></div>
          <div><label class="dlg-label" for="pp-ar">Copy · Arabic</label><textarea class="field pl-ar" id="pp-ar" rows="4" dir="rtl" lang="ar" ${ro}>${esc(s.copyAr)}</textarea></div>
        </div>
        <div class="pl-refs-h"><label class="dlg-label">References</label>${ed ? `<span class="spacer"></span><button type="button" class="btn ghost sm" data-pp="upload">${icon('upload')}Add files</button><button type="button" class="btn ghost sm" data-pp="link">${icon('link')}Add link</button>` : ''}</div>
        <div class="pl-link-add" id="pp-link-add" hidden><input class="field" id="pp-link" placeholder="Paste a link (Instagram, TikTok, Pinterest, Drive…)"><button type="button" class="btn primary sm" data-pp="link-ok">Add</button></div>
        <div class="pl-refs-list" id="pp-refs"></div>
      </div>
      <div class="actions">${ed && !isNew ? `<button type="button" class="btn ghost danger" data-pp="del">${icon('trash')}Delete</button><span class="spacer"></span>` : ''}<button type="button" class="btn" data-pp="close">${ed || appr ? 'Cancel' : 'Close'}</button>${ed ? `<button type="submit" class="btn primary">${isNew ? 'Add post' : 'Save'}</button>` : appr ? '<button type="submit" class="btn primary">Save</button>' : ''}</div>
    </form></div>`;
    const form = $('form', root);
    const paintRefs = () => {
      const files = s.refs.filter((r) => r.path), links = s.refs.filter((r) => r.url);
      $('#pp-refs', root).innerHTML = (files.length || links.length) ? `${files.length ? `<div class="pl-ref-grid">${files.map((r) => { const k = fileKind(r); return `<div class="pl-ref" title="${esc(r.name)}"><button type="button" class="pl-ref-img" data-pp="view" data-id="${r.id}">${k === 'image' ? `<img src="${imgUrl(r, 320)}" alt="">` : `<span class="pl-ref-ext">${esc(fileExt(r.name) || 'file')}</span>`}${k === 'video' ? `<span class="tile-play">${icon('play')}</span>` : ''}</button><span class="pl-ref-n">${esc(r.name)}</span>${ed ? `<button type="button" class="icon-btn xs pl-ref-x" data-pp="rm" data-id="${r.id}" title="Remove">${icon('x')}</button>` : ''}</div>`; }).join('')}</div>` : ''}
        ${links.map((r) => `<div class="pl-ref-link">${icon('link')}<a href="${esc(r.url)}" target="_blank" rel="noopener">${esc(r.label || r.url)}</a>${ed ? `<button type="button" class="icon-btn xs" data-pp="rm" data-id="${r.id}" title="Remove">${icon('x')}</button>` : ''}</div>`).join('')}`
        : `<div class="pl-none">${ed ? 'Photos, videos, PDFs or links that show what you have in mind' : 'No references'}</div>`;
    };
    const close = () => { root.innerHTML = ''; document.removeEventListener('keydown', onKey, true); };
    const onKey = (e) => { if (e.key === 'Escape' && !$('.fv, .file-viewer, .fpv')) { e.preventDefault(); e.stopPropagation(); close(); } };
    document.addEventListener('keydown', onKey, true);
    $('.scrim', root).addEventListener('mousedown', (e) => { if (e.target.classList.contains('scrim') && !ed) close(); });
    if (ed) $('#pp-day', root).addEventListener('change', (e) => { if (e.target.value) { s.day = e.target.value; $('.date-lbl', e.target.closest('.date-chip')).textContent = dayLong(s.day); } });
    const addLink = () => {
      const v = $('#pp-link', root).value.trim();
      if (!v) return;
      const url = /^[a-z]+:\/\//i.test(v) ? v : 'https://' + v;
      let label;
      try { const u = new URL(url); label = u.hostname.replace(/^www\./, '') + (u.pathname.length > 1 ? u.pathname.slice(0, 40) : ''); } catch (e) { toast('That doesn’t look like a link'); return; }
      s.refs.push({ id: 'pr-' + uid(), url, label });
      $('#pp-link', root).value = ''; $('#pp-link-add', root).hidden = true;
      paintRefs();
    };
    $('#pp-link', root).addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addLink(); } });
    form.addEventListener('click', async (e) => {
      const tl = e.target.closest('[data-pp="task"]');
      if (tl) { e.preventDefault(); close(); openTask(tl.dataset.id); return; }
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.pp === 'close') return close();
      if (b.dataset.pp === 'view') { const r = s.refs.find((y) => y.id === b.dataset.id); if (r) previewFile(r); return; }
      if (b.dataset.pp === 'viewf') { const g = progress(x); const r = g.files.find((y) => y.id === b.dataset.id); if (r) previewFile(r); return; }
      if (b.dataset.ck && appr) {
        ck.state = ck.state === b.dataset.ck ? null : b.dataset.ck;
        $$('#pp-check [data-ck]', root).forEach((y) => y.classList.toggle('on', y.dataset.ck === ck.state));
        const nt = $('#pp-cknote', root); nt.hidden = ck.state !== 'changes'; if (!nt.hidden) nt.focus();
        return;
      }
      if (!ed) return;
      if (b.dataset.fmt) { s.format = b.dataset.fmt; $$('#pp-fmt .pl-opt', root).forEach((y) => y.classList.toggle('on', y === b)); return; }
      if (b.dataset.ch) { const k = b.dataset.ch; s.channels = s.channels.includes(k) ? s.channels.filter((y) => y !== k) : s.channels.concat(k); b.classList.toggle('on', s.channels.includes(k)); return; }
      if (b.dataset.pp === 'rm') { s.refs = s.refs.filter((y) => y.id !== b.dataset.id); paintRefs(); return; }
      if (b.dataset.pp === 'link') { const box = $('#pp-link-add', root); box.hidden = !box.hidden; if (!box.hidden) $('#pp-link', root).focus(); return; }
      if (b.dataset.pp === 'link-ok') return addLink();
      if (b.dataset.pp === 'upload') {
        const files = await ServerHost.pickFiles({ multiple: true, accept: 'image/*,video/*,.pdf,.ppt,.pptx,.key,.doc,.docx' });
        if (!files.length) return;
        b.disabled = true;
        try { const up = await ServerHost.uploadMany(files, { taskId: pl.id }); up.forEach((a) => s.refs.push({ ...a, id: 'pr-' + uid() })); } finally { b.disabled = false; }
        if (document.body.contains(form)) paintRefs();
        return;
      }
      if (b.dataset.pp === 'del') {
        close();
        const ok = await dialog({ title: 'Delete this post?', body: `“${x.title || 'Untitled post'}” will be removed from the plan.`, okText: 'Delete', danger: true });
        if (!ok) return;
        pl.posts = (pl.posts || []).filter((y) => y.id !== x.id); pl.updatedAt = nowISO();
        persist(0); renderContent(); toast('Post deleted');
      }
    });
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      if (appr && !ed) {
        const cur = (pl.posts || []).find((y) => y.id === x.id);
        if (!cur || pl.status !== 'review') { close(); return; }
        const note = ($('#pp-cknote', root).value || '').trim();
        if (ck.state === 'changes' && !note) { $('#pp-cknote', root).focus(); toast('Say what should change'); return; }
        if (ck.state) cur.check = { state: ck.state, note: ck.state === 'changes' ? note : '', by: currentUserId, at: nowISO() }; else delete cur.check;
        pl.updatedAt = nowISO();
        close(); persist(0); renderContent();
        toast(ck.state === 'ok' ? 'Marked Looks good' : ck.state === 'changes' ? 'Marked Ask for changes' : 'Saved');
        return;
      }
      if (!ed) return close();
      const t = $('#pp-title', root).value.trim();
      if (!t) { $('#pp-title', root).focus(); toast('Give the post a title'); return; }
      if (!planById(pl.id)) { close(); toast('This plan was deleted'); return; }
      const v = { day: s.day, title: t, format: s.format, channels: s.channels, occasion: $('#pp-occ', root).value || null,
        desc: $('#pp-desc', root).value.trim(), shots: $('#pp-shots', root).value.trim(), copyEn: $('#pp-en', root).value.trim(), copyAr: $('#pp-ar', root).value.trim(), refs: s.refs };
      if (isNew) pl.posts = (pl.posts || []).concat({ id: 'pp-' + uid(), ...v, createdBy: currentUserId, createdAt: nowISO(), updatedAt: nowISO() });
      else {
        const cur = (pl.posts || []).find((y) => y.id === x.id); if (!cur) { close(); toast('This post was deleted'); return; }
        Object.assign(cur, v, { updatedAt: nowISO() });
        if (cur.check && cur.check.state === 'ok') delete cur.check;   // (changed after it was looked at: it needs another look)
      }
      pl.updatedAt = nowISO();
      close(); persist(0); renderContent();
      toast(isNew ? `Added “${t}” on ${dayLong(s.day)}` : 'Saved');
    });
    paintRefs();
    if (ed && isNew) setTimeout(() => $('#pp-title', root).focus(), 30);
  }

  /* ---------- clicks ---------- */
  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-pl]');
    if (!el || !db || !owns(ui.view)) return;
    const a = el.dataset.pl, s = st();
    e.preventDefault();
    const pl = planById(ui.planId);
    switch (a) {
      case 'prev': if (s.month > thisMonth()) s.month = shiftMonth(s.month, -1); return renderContent();
      case 'next': s.month = shiftMonth(s.month, 1); return renderContent();
      case 'reset': s.month = nextMonth(); return renderContent();
      case 'open': e.stopPropagation(); return open(el.dataset.id);
      case 'start': e.stopPropagation(); return startPlan(el.dataset.p, s.month);
      case 'tab': s.tab = el.dataset.v; return renderContent();
      case 'new-post': if (pl) postDialog(pl, null, { day: el.dataset.d || null }); return;
      case 'post': { const x = pl && (pl.posts || []).find((y) => y.id === el.dataset.id); if (x) postDialog(pl, x); return; }
      case 'occ-post': { const o = Occasions.byId(el.dataset.o); if (pl && o) postDialog(pl, null, { day: o.date, occasion: o.id, title: o.name }); return; }
      case 'skip': if (pl) setSkip(pl, el.dataset.o, true); return;
      case 'unskip': if (pl) setSkip(pl, el.dataset.o, false); return;
      case 'plan-menu': e.stopImmediatePropagation(); if (pl) planMenu(el, pl); return;   // (the app's own click handler would close it at once)
      case 'send': if (pl) sendFlow(pl); return;
      case 'make-tasks': if (pl) makeTasksDialog(pl); return;
      case 'export': if (pl) exportDialog(pl); return;
      case 'reply': if (pl) replyDialog(pl); return;
      case 'client-all': if (pl) clientApproveAll(pl); return;
      case 'mark-sent': if (pl) markSent(pl); return;
      case 'rounds': e.stopImmediatePropagation(); if (pl) roundsMenu(el, pl); return;
      case 'dl': { const a = el; ServerHost.download(a.getAttribute('href'), a.getAttribute('download')); return; }
      case 'approve': if (pl) approve(pl); return;
      case 'send-back': if (pl) sendBack(pl); return;
    }
  });

  // skeletons waiting for this person's approval (the sidebar count)
  const waiting = () => (canSee() ? list().filter((pl) => pl.status === 'review' && canApprove(pl) && proj(pl.projectId) && !proj(pl.projectId).inactive).length : 0);
  const nameOf = (pl) => { const p = proj(pl.projectId); return `${p ? p.name : 'A client'} · ${monthLabel(pl.month)}`; };
  return { on, owns, canSee, render, title, isMgr, socialsOf, planById, monthLabel, FORMATS, waiting, nameOf, open, socialManages, progress };
})();
