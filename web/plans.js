/* ================= Content plans (a trial on the test copy) =================
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
  const on = () => typeof isTestCopy === 'function' && isTestCopy();
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
  const statusPill = (pl) => { if (!pl) return '<span class="pl-st none">Not started</span>'; const [c, l] = ST[pl.status] || ST.draft; return `<span class="pl-st ${c}">${l}</span>`; };
  const occKey = (o) => o.key || o.id;
  const skipped = (p, o) => ((p && p.planSkips) || []).includes(occKey(o));
  const postsSorted = (pl) => (pl.posts || []).slice().sort((a, b) => String(a.day).localeCompare(String(b.day)) || String(a.createdAt).localeCompare(String(b.createdAt)));

  /* ---------- the list of plans ---------- */
  function title() {
    if (ui.view === 'plan') {
      const pl = planById(ui.planId), p = pl && proj(pl.projectId);
      if (pl && p) return `<div class="page-icon pl-icon">${icon('cal')}</div><a class="page-title crumb-link" data-nav="plans">Content plans</a><span class="crumb-sep">/</span><div class="page-title">${esc(p.name)} · ${esc(monthLabel(pl.month))}</div><span class="pl-trial">Trial · test site</span>`;
    }
    return `<div class="page-icon pl-icon">${icon('cal')}</div><div class="page-title">Content plans</div><span class="pl-trial">Trial · test site</span>`;
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
          <button class="icon-btn" data-pl="prev" title="Previous month">${icon('chev-left')}</button>
          <b class="cal-label">${esc(monthLabel(m))}</b>
          <button class="icon-btn" data-pl="next" title="Next month">${icon('chev-right')}</button>
          ${m !== nextMonth() ? '<button class="btn ghost sm" data-pl="reset">Next month</button>' : ''}
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
        ${day.map((x) => `<button class="pl-chip ${checkCls(pl, x)}" data-pl="post" data-id="${x.id}" style="--c:${fmtOf(x.format).color}" title="${esc((x.title || 'Untitled post') + ' · ' + fmtOf(x.format).name + checkTip(pl, x))}"><span class="pl-chip-t">${checkMark(pl, x)}${esc(x.title || 'Untitled post')}</span><span class="pl-chip-f">${esc(fmtOf(x.format).name)}</span></button>`).join('')}
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
    const img = (x.refs || []).find((r) => r.path && fileKind(r) === 'image');
    return `<button class="pl-post ${checkCls(pl, x)}" data-pl="post" data-id="${x.id}">
      <span class="pl-thumb">${img ? `<img src="${imgUrl(img, 160)}" alt="" loading="lazy">` : `<span class="pl-thumb-f" style="--c:${fmtOf(x.format).color}">${esc(fmtOf(x.format).name.slice(0, 1))}</span>`}</span>
      <span class="pl-post-txt"><b>${checkMark(pl, x)}${esc(x.title || 'Untitled post')}</b><span>${x.check && x.check.state === 'changes' && x.check.note && pl.status !== 'approved' ? `<i class="pl-chg-note">${esc(x.check.note)}</i>` : esc(String(x.desc || x.copyEn || '').replace(/\s+/g, ' ').slice(0, 140))}</span></span>
      <span class="pl-post-meta">${fmtPill(x.format)}${chChips(x.channels)}${o ? `<span class="cal-occ-pill">${esc(o.name)}</span>` : ''}${n ? `<span class="pl-refs">${icon('clip')}${n}</span>` : ''}</span>
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
    if (pl.status === 'approved' && pl.approval) {
      return `<div class="pl-banner approved">${icon('check-circle')}<div><b>Content skeleton approved by ${esc(who(pl.approval.by))}</b><span>${esc(fmtDateTime(pl.approval.at))} · Next: creating the tasks from it (coming in the next stage of the trial).</span></div></div>`;
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
    if (pl.status === 'approved' && (isEditor(pl) || canApprove(pl))) items.push({ label: 'Reopen as a draft', icon: 'edit', run: () => reopen(pl) });
    items.push({ html: `<div class="menu-label">History</div>` });
    const acts = { sent: 'sent it for approval', approved: 'approved it', changes: 'asked for changes', withdrawn: 'took it back', reopened: 'reopened it' };
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
    const onKey = (e) => { if (e.key === 'Escape' && !$('.fv, .file-viewer')) { e.preventDefault(); e.stopPropagation(); close(); } };
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
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.pp === 'close') return close();
      if (b.dataset.pp === 'view') { const r = s.refs.find((y) => y.id === b.dataset.id); if (r) previewFile(r); return; }
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
      case 'prev': s.month = shiftMonth(s.month, -1); return renderContent();
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
      case 'plan-menu': e.stopPropagation(); if (pl) planMenu(el, pl); return;
      case 'send': if (pl) sendFlow(pl); return;
      case 'approve': if (pl) approve(pl); return;
      case 'send-back': if (pl) sendBack(pl); return;
    }
  });

  // skeletons waiting for this person's approval (the sidebar count)
  const waiting = () => (canSee() ? list().filter((pl) => pl.status === 'review' && canApprove(pl) && proj(pl.projectId) && !proj(pl.projectId).inactive).length : 0);
  const nameOf = (pl) => { const p = proj(pl.projectId); return `${p ? p.name : 'A client'} · ${monthLabel(pl.month)}`; };
  return { on, owns, canSee, render, title, isMgr, socialsOf, planById, monthLabel, FORMATS, waiting, nameOf, open };
})();
