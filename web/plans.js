/* ================= Content plans (a trial on the test copy) =================
   One plan per client per month (db.plans):
     { id, projectId, month: 'YYYY-MM', status: 'draft', createdBy, createdAt, updatedAt, posts: [post] }
     post = { id, day: 'YYYY-MM-DD', title, desc, format, channels: [], occasion, shots, copyEn, copyAr, refs: [ref],
              createdBy, createdAt, updatedAt }
     ref  = a file { id, name, path, size, w?, h? } (uploaded to attachments/<plan id>/) or a link { id, url, label }
   Who: a client's Social Executives (project.socials, set in the client pop-up) and the Social Manager (Social people an
   Admin picks on the Team page: db.meta.socialMgrIds) make and edit a client's plans; Admins, Account Managers and the CD
   look at them. An occasion skipped for a client stays skipped every year (project.planSkips: occasion keys).
   Stage 1: plans, the month calendar and occasions. Next: approval by the Social Manager / CD, creating tasks, the
   finished work coming back into the plan, the client export and the client's approval. */
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
  const canEdit = (pl) => !!pl && canEditClient(pl.projectId);
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
  const statusPill = (pl) => (pl ? '<span class="pl-st draft" title="The content skeleton, being written">Skeleton · draft</span>' : '<span class="pl-st none">Not started</span>');
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
        ${ed ? `<button class="btn primary sm" data-pl="new-post">${icon('plus')}Add post</button><button class="icon-btn" data-pl="plan-menu" title="Plan options">${icon('more')}</button>` : '<span class="pl-ro">View only</span>'}
      </div>
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
        ${day.map((x) => `<button class="pl-chip" data-pl="post" data-id="${x.id}" style="--c:${fmtOf(x.format).color}" title="${esc((x.title || 'Untitled post') + ' · ' + fmtOf(x.format).name)}"><span class="pl-chip-t">${esc(x.title || 'Untitled post')}</span><span class="pl-chip-f">${esc(fmtOf(x.format).name)}</span></button>`).join('')}
      </div>`;
    }
    return `<div class="cal-month pl-month"><div class="cal-wd">${WD.map((w) => `<span>${w}</span>`).join('')}</div><div class="cal-grid">${cells}</div></div>`;
  }
  function listView(pl, ed) {
    const posts = postsSorted(pl);
    if (!posts.length) return `<div class="empty pl-empty"><div class="big">No posts yet</div>${ed ? 'Use <b>Add post</b>, or the + on a day of the calendar.' : 'The Social team hasn’t added any posts yet.'}</div>`;
    const days = [...new Set(posts.map((x) => x.day))];
    return `<div class="pl-list">${days.map((d) => `<section class="pl-lday"><h3>${esc(dayLong(d))}${Occasions.on(d).length ? `<span class="pl-locc">${esc(Occasions.on(d).map((o) => o.name).join(' · '))}</span>` : ''}</h3>
      ${posts.filter((x) => x.day === d).map(postRow).join('')}</section>`).join('')}</div>`;
  }
  function postRow(x) {
    const o = x.occasion && Occasions.byId(x.occasion);
    const n = (x.refs || []).length;
    const img = (x.refs || []).find((r) => r.path && fileKind(r) === 'image');
    return `<button class="pl-post" data-pl="post" data-id="${x.id}">
      <span class="pl-thumb">${img ? `<img src="${imgUrl(img, 160)}" alt="" loading="lazy">` : `<span class="pl-thumb-f" style="--c:${fmtOf(x.format).color}">${esc(fmtOf(x.format).name.slice(0, 1))}</span>`}</span>
      <span class="pl-post-txt"><b>${esc(x.title || 'Untitled post')}</b><span>${esc(String(x.desc || x.copyEn || '').replace(/\s+/g, ' ').slice(0, 140))}</span></span>
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
    showMenu(anchor, [{ label: 'Delete this plan', icon: 'trash', danger: true, run: async () => {
      const n = (pl.posts || []).length, name = proj(pl.projectId).name;
      const ok = await dialog({ title: 'Delete this plan?', body: `${name}’s ${monthLabel(pl.month)} plan${n ? ` and its ${n} post${n === 1 ? '' : 's'}` : ''} will be deleted.`, okText: 'Delete', danger: true });
      if (!ok) return;
      db.plans = list().filter((x) => x.id !== pl.id);
      persist(0); go('plans'); toast('Plan deleted');
    } }]);
  }

  /* ---------- a post: the pop-up ---------- */
  function postDialog(pl, x, preset = {}) {
    const ed = canEdit(pl);
    const isNew = !x;
    const m = pl.month;
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
      <div class="actions">${ed && !isNew ? `<button type="button" class="btn ghost danger" data-pp="del">${icon('trash')}Delete</button><span class="spacer"></span>` : ''}<button type="button" class="btn" data-pp="close">${ed ? 'Cancel' : 'Close'}</button>${ed ? `<button type="submit" class="btn primary">${isNew ? 'Add post' : 'Save'}</button>` : ''}</div>
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
      if (!ed) return close();
      const t = $('#pp-title', root).value.trim();
      if (!t) { $('#pp-title', root).focus(); toast('Give the post a title'); return; }
      if (!planById(pl.id)) { close(); toast('This plan was deleted'); return; }
      const v = { day: s.day, title: t, format: s.format, channels: s.channels, occasion: $('#pp-occ', root).value || null,
        desc: $('#pp-desc', root).value.trim(), shots: $('#pp-shots', root).value.trim(), copyEn: $('#pp-en', root).value.trim(), copyAr: $('#pp-ar', root).value.trim(), refs: s.refs };
      if (isNew) pl.posts = (pl.posts || []).concat({ id: 'pp-' + uid(), ...v, createdBy: currentUserId, createdAt: nowISO(), updatedAt: nowISO() });
      else { const cur = (pl.posts || []).find((y) => y.id === x.id); if (!cur) { close(); toast('This post was deleted'); return; } Object.assign(cur, v, { updatedAt: nowISO() }); }
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
    }
  });

  return { on, owns, canSee, render, title, isMgr, socialsOf, planById, monthLabel, FORMATS };
})();
