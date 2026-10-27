/* E11 Console — phone layout.
   On small screens (iPhone, narrow windows) the sidebar is replaced by a bottom tab bar and the
   lists become simple cards. Everything else — data, sync, permissions, the task page logic —
   is shared with the desktop app in app.js. The Mac app always keeps the desktop layout. */
const Phone = (() => {
  const mq = window.matchMedia('(max-width: 760px)');
  const OWN = new Set(['home', 'today', 'mytasks', 'inbox', 'reviews', 'review', 'me', 'projects', 'project', 'psearch']);
  const TITLES = { calendar: 'Content calendar', plans: 'Content plans', trash: 'Trash', profile: 'My profile', team: 'Team members', updates: 'App updates', clients: 'Client Assets', client: 'Client Assets' };
  const st = { on: false, ibf: 'unread', q: '' };

  const isOn = () => st.on;
  function check() {
    // Finance people use the Finance pages, which are built for every screen size (no phone tabs)
    const v = mq.matches && !(typeof Host !== 'undefined' && Host.isMacApp) && !(typeof db !== 'undefined' && db && currentUserId && typeof isFinUser === 'function' && isFinUser());
    if (v === st.on) return;
    st.on = v;
    document.body.classList.toggle('phone', v);
    document.documentElement.classList.toggle('phone', v);
    noZoom(v);
    if (!v && typeof unpin === 'function') unpin();
    if (typeof db !== 'undefined' && db && currentUserId) render();
  }
  mq.addEventListener ? mq.addEventListener('change', check) : mq.addListener(check);

  // No pinch or double-tap zoom in the phone layout: it should feel like an app, not a web page.
  // iPhone Safari ignores user-scalable=no on its own, so the pinch gesture itself is stopped too.
  const VP_APP = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
  const VP_WEB = 'width=device-width, initial-scale=1, viewport-fit=cover';
  function noZoom(on) {
    const m = document.querySelector('meta[name="viewport"]');
    if (m) m.setAttribute('content', on ? VP_APP : VP_WEB);
  }
  const stopPinch = (e) => { if (st.on) e.preventDefault(); };
  ['gesturestart', 'gesturechange', 'gestureend'].forEach((ev) => document.addEventListener(ev, stopPinch, { passive: false }));
  document.addEventListener('touchmove', (e) => { if (st.on && e.touches && e.touches.length > 1) e.preventDefault(); }, { passive: false });

  // iPhone Home Screen apps can report a page shorter than the screen, which leaves a gap under
  // everything pinned to the bottom. Measure the real height and pin to the true bottom edge.
  // Where does "the bottom" (bottom: 0) really land? A tiny probe pinned there tells us, so the
  // correction is always based on what the phone is doing right now, not on a number it reported once.
  let probe = null, lastKey = '';
  function measure() {
    const root = document.documentElement;
    if (!probe && document.body) { probe = document.createElement('i'); probe.style.cssText = 'position:fixed;left:0;bottom:0;width:0;height:0;padding-top:env(safe-area-inset-top);box-sizing:content-box;pointer-events:none;visibility:hidden'; document.body.appendChild(probe); }
    const standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
    const bottom = probe ? probe.getBoundingClientRect().bottom : window.innerHeight; // where bottom:0 sits now
    let h = Math.max(bottom, window.innerHeight);
    // only an app that draws under the status bar (no space reserved at the top) can come up short
    const underBar = probe && parseFloat(getComputedStyle(probe).paddingTop) > 0;
    root.classList.toggle('ph-underbar', !!(standalone && underBar)); // headers move down past iOS's blurred band
    if (standalone && underBar) {
      const full = window.innerHeight > window.innerWidth ? Math.max(screen.height, screen.width) : Math.min(screen.height, screen.width);
      if (full > h && full - h < 140) h = full; // not when the keyboard is open (that shrinks it a lot more)
    }
    const shift = Math.min(0, Math.round(bottom - h));
    const key = h + '/' + shift;
    if (key === lastKey) return;
    lastKey = key;
    root.style.setProperty('--app-h', h + 'px');
    root.style.setProperty('--ph-shift', shift + 'px');
  }
  measure();
  window.addEventListener('resize', measure);
  window.addEventListener('orientationchange', () => setTimeout(measure, 300));
  window.addEventListener('pageshow', () => { measure(); setTimeout(measure, 300); });
  document.addEventListener('visibilitychange', () => { if (!document.hidden) { measure(); setTimeout(measure, 300); setTimeout(measure, 1000); } });
  if (window.visualViewport) window.visualViewport.addEventListener('resize', measure);
  // the phone can settle on its real size a moment after opening without telling the page: keep checking
  setInterval(() => { if (st.on && !document.hidden) measure(); }, 1000);

  const tabOf = (v) => (v === 'home' ? 'today' : v === 'review' ? 'reviews' : v === 'project' ? 'projects' : v);
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;

  /* ---------- Bottom tab bar ---------- */
  function chrome() {
    if (!st.on) return;
    let bar = document.getElementById('ph-tabs');
    if (!bar) { bar = document.createElement('nav'); bar.id = 'ph-tabs'; document.body.appendChild(bar); }
    const unread = myNotifs().filter((n) => !n.read).length;
    const cd = isCD();
    const rv = cd ? activeReviews().length : 0;
    const cur = tabOf(ui.view);
    const tab = (v, ic, label, badge) => `<button class="ph-tab ${cur === v ? 'on' : ''}" data-ph-tab="${v}">${icon(ic)}${badge ? `<i class="ph-badge">${badge > 99 ? '99+' : badge}</i>` : ''}<span>${label}</span></button>`;
    bar.innerHTML = isOffice()      // an Office Admin: no task pages
      ? tab('today', 'home', 'Home') + tab('inbox', 'inbox', 'Inbox', unread) + tab('clients', 'assets', 'Client Assets') + tab('me', 'user', 'Me')
      : tab('today', 'sun', Work.dayTitle())
      + tab('mytasks', 'check-circle', 'My Tasks')
      + tab('inbox', 'inbox', 'Inbox', unread)
      + (cd ? tab('reviews', 'shield', 'Reviews', rv) : tab('projects', 'folder', 'Clients'))
      + tab('me', 'user', 'Me');
    bar.hidden = !!ui.taskId;
    document.body.classList.toggle('task-open', !!ui.taskId);
    const top = document.getElementById('ph-top'); if (top) { top.hidden = !top.firstElementChild; if (!ui.taskId && top.firstElementChild) document.documentElement.style.setProperty('--ph-head-h', top.offsetHeight + 'px'); }
  }

  /* ---------- Pieces ---------- */
  function card(t, o = {}) {
    const p = proj(t.projectId);
    const s = statusInfo(t);
    const open = !t.done && !partDone(t);
    const late = open && t.due && dayDiff(t.due) < 0;
    const bits = [];
    bits.push(p ? `<i class="ph-dot" style="background:${p.color}"></i>${esc(p.name)}` : 'My Tasks');
    if (o.status !== false) bits.push(esc(s.name));
    if (t.due && o.due !== false) bits.push(`<b class="${late ? 'late' : dayDiff(t.due) === 0 && open ? 'today' : ''}">${esc(mwDue(t))}</b>`);
    if (t.comments.length) bits.push(plural(t.comments.length, 'comment'));
    const pr = prioOf(t);
    const badge = isUrgent(t) && !t.done ? '<span class="ph-tag urgent">Urgent</span>'
      : typeof normPrio(pr) === 'number' ? `<span class="ph-tag">${normPrio(pr)}</span>` : '';
    return `<div class="pc ${late ? 'late' : ''} ${t.done ? 'done' : ''}" data-task="${t.id}">
      <span class="pc-ic">${statusIcon(t, 22)}</span>
      <span class="pc-body"><span class="pc-title">${t.title ? (o.mark ? sMark(t.title, o.mark) : esc(t.title)) : '<i>Untitled task</i>'}</span>
        <span class="pc-meta">${bits.join('<em>·</em>')}</span>
        ${t.cdStatus && !t.done ? `<span class="pc-cd">${cdChip(t)}</span>` : ''}</span>
      <span class="pc-side">${badge}${avatarStack(t.assignees, 22, 2, t)}</span>
    </div>`;
  }
  const group = (name, tasks, o = {}) => (tasks.length || o.empty
    ? `<div class="ph-gh">${esc(name)}${tasks.length ? `<span>${tasks.length}</span>` : ''}</div>${tasks.map((t) => card(t, o)).join('') || `<div class="ph-empty">${o.empty}</div>`}`
    : '');
  const fab = () => (can('createTask') ? `<button class="ph-fab" data-ph="quick-add" aria-label="New task">${icon('plus')}</button>` : '');
  function head(title, sub, right = '') {
    return `<header class="ph-head"><div class="ph-hl">${sub ? `<div class="ph-sub">${sub}</div>` : ''}<h1>${title}</h1></div>${right}</header>`;
  }
  const backHead = (title, back, right = '') => `<header class="ph-bar"><button class="ph-back" ${back} aria-label="Back">${icon('chev-left')}</button><b>${title}</b>${right || '<span class="ph-bar-sp"></span>'}</header>`;

  /* ---------- Screens ---------- */
  function myDay() {
    const today = todayStr();
    const D = Work.day();
    const open = D.tasks.filter(D.open);
    const sortP = (a, b) => byPrio(a, b) || (a.due || '').localeCompare(b.due || '') || a.createdAt.localeCompare(b.createdAt);
    const overdue = open.filter((t) => t.due && t.due < today).sort(sortP);
    const due = open.filter((t) => t.due === today).sort(sortP);
    const going = open.filter((t) => t.start && t.start <= today && t.due && t.due > today).sort(sortP);
    const done = D.doneTasks.filter((t) => D.doneAt(t) && ymd(new Date(D.doneAt(t))) === today);
    const review = open.filter((t) => t.cdStatus === 'review').length;
    const d = new Date();
    return `<div class="ph-page">
      ${head(Work.dayTitle(), esc(d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })),
        `<button class="ph-round" data-ph="search" aria-label="Search">${icon('search')}</button><button class="ph-me" data-ph-tab="me" aria-label="Me">${avatarHTML(currentUserId, 40)}</button>`)}
      <div class="ph-stats">
        <div><b class="g">${due.length}</b><span>Due today</span></div>
        <div><b class="r">${overdue.length}</b><span>Overdue</span></div>
        <div><b class="a">${review}</b><span>In review</span></div>
      </div>
      <div class="ph-list">
        ${group('Overdue', overdue)}
        ${group('Today', due, { empty: overdue.length ? 'Nothing else due today' : 'Nothing due today 🎉' })}
        ${group('In progress', going)}
        ${group('Completed today', done, { status: false })}
      </div>
      ${fab()}
    </div>`;
  }

  function myTasks() {
    const tab = ui.myTasksTab === 'done' ? 'done' : 'todo';
    const L = Work.list(), doneAt = Work.doneAtOf;
    const open = L.filter(Work.openOf);
    let body;
    if (tab === 'done') {
      const cutoff = Date.now() - AUTO_DELETE_DAYS * 86400000;
      const list = L.filter((t) => doneAt(t) && new Date(doneAt(t)).getTime() > cutoff).sort((a, b) => doneAt(b).localeCompare(doneAt(a)));
      body = group('Last 30 days', list, { empty: 'Tasks you complete show here.', status: false });
    } else {
      body = group('Overdue', open.filter((t) => t.due && dayDiff(t.due) < 0).sort(byDayThenPrio))
        + group('Today', open.filter((t) => t.due && dayDiff(t.due) === 0).sort(byDayThenPrio), { empty: 'Nothing due today 🎉' })
        + group('Next', open.filter((t) => t.due && dayDiff(t.due) > 0).sort(byDayThenPrio))
        + group('No due date', open.filter((t) => !t.due).sort((a, b) => byPrio(a, b) || a.createdAt.localeCompare(b.createdAt)));
    }
    return `<div class="ph-page">
      ${head('My Tasks', plural(open.length, 'open task'))}
      <div class="ph-seg"><button class="${tab === 'todo' ? 'on' : ''}" data-action="mt-tab" data-tab="todo">To Do</button><button class="${tab === 'done' ? 'on' : ''}" data-action="mt-tab" data-tab="done">Done</button></div>
      ${workFilterBar()}
      <div class="ph-list">${body}</div>
      ${fab()}
    </div>`;
  }

  function inbox() {
    const all = myNotifs();
    const unreadN = all.filter((n) => !n.read).length;
    const f = st.ibf;
    const list = all.filter((n) => (f === 'unread' ? !n.read : f === 'mentions' ? n.kind === 'mention' : true)).sort((a, b) => b.at.localeCompare(a.at));
    const byTask = new Map();
    list.forEach((n) => { const k = notifKey(n); if (!byTask.has(k)) byTask.set(k, []); byTask.get(k).push(n); });
    const rows = [...byTask.values()].slice(0, 200).map((items) => {
      const n = items[0];
      const t = task(n.taskId);
      const unread = items.some((x) => !x.read);
      const target = ibTarget(items);   // (opens what the row shows: the newest, or an unread one needing action)
      return `<div class="ph-ib ${unread ? 'unread' : ''}" data-action="open-notif" data-id="${target.id}">
        ${avatarHTML(target.from, 40)}
        <span class="ph-ib-b"><span class="ph-ib-m">${notifMsg(target, t)}</span>
          <span class="ph-ib-t">${n.kind === 'sched-cancel' ? `Scheduled ${/scheduled reply/.test(n.text || '') ? 'reply' : 'comment'}` : t ? esc(t.title || 'Untitled task') : n.kind === 'birthday' ? 'Birthday' : /^claim/.test(n.kind) ? 'Expense claims' : n.kind === 'asset' ? esc(assetTitle(n)) : n.planId ? esc(planTitle(n)) : '<i>Deleted task</i>'}</span>
          <span class="ph-ib-w">${esc(timeAgo(n.at))}${items.length > 1 ? ` · ${items.length} updates` : ''}</span></span>
        ${unread ? '<i class="ph-ib-dot"></i>' : ''}
      </div>`;
    }).join('');
    const chip = (k, l) => `<button class="${f === k ? 'on' : ''}" data-ph="ibf" data-k="${k}">${l}</button>`;
    return `<div class="ph-page">
      ${head('Inbox', unreadN ? plural(unreadN, 'unread update') : 'All caught up', unreadN ? '<button class="ph-pill" data-action="mark-all-read">Mark all read</button>' : '')}
      <div class="ph-chips">${chip('unread', `Unread${unreadN ? ' ' + unreadN : ''}`)}${chip('all', 'All')}${chip('mentions', 'Mentions')}</div>
      <div class="ph-ibl">${rows || `<div class="ph-empty big">${f === 'unread' ? 'Inbox zero 🎉<small>New updates and @mentions land here.</small>' : 'Nothing here yet'}</div>`}</div>
    </div>`;
  }

  function reviews() {
    if (!isCD()) return `<div class="ph-page">${head('Reviews')}<div class="ph-empty big">Only the Creative Director sees review requests</div></div>`;
    const list = activeReviews();
    return `<div class="ph-page">
      ${head('Reviews', list.length ? plural(list.length, 'request') + ' waiting' : 'Nothing waiting')}
      <div class="ph-list">${list.map(({ t, r }) => {
        const p = proj(t.projectId);
        const n = (r.files || []).length;
        return `<div class="pc rv" data-ph="open-review" data-id="${r.id}" data-review="${r.id}">
          ${avatarHTML(r.by, 40)}
          <span class="pc-body"><span class="pc-title">${esc(t.title || 'Untitled task')}</span>
            <span class="pc-meta">${p ? `<i class="ph-dot" style="background:${p.color}"></i>${esc(p.name)}<em>·</em>` : ''}${esc(firstName(r.by))} sent ${plural(n, 'file')} · ${esc(timeAgo(r.at))}</span></span>
          ${r.round > 1 ? `<span class="ph-tag amber">Round ${r.round}</span>` : ''}
        </div>`;
      }).join('') || '<div class="ph-empty big">All caught up 🎉<small>New submissions appear here, and you get a notification.</small></div>'}</div>
    </div>`;
  }

  function fileSlide(t, a) {
    const k = fileKind(a), url = fileUrl(a);
    let m;
    if (k === 'image') m = `<img src="${imgUrl(a, 1280)}" alt="" loading="lazy">`;
    else if (k === 'video') m = `<video src="${url}" controls playsinline preload="metadata"></video>`;
    else m = a.thumb ? `<img src="${'/__file/' + a.thumb.split('/').map(encodeURIComponent).join('/')}" alt="">`
      : `<span class="ph-ext" ${Host.isNative ? `data-thumb-for="${a.id}" data-thumb-task="${t.id}" data-mode="slide"` : ''}>${esc((fileExt(a.name) || 'file').slice(0, 5))}</span>`;
    return `<div class="ph-slide"><div class="ph-media" ${k === 'video' ? '' : `data-ph="preview" data-tid="${t.id}" data-id="${a.id}"`}>${m}</div><div class="ph-fname">${esc(a.name)}<small>${fmtSize(a.size)}</small></div></div>`;
  }
  function review() {
    const list = activeReviews();
    const i = list.findIndex((x) => x.r.id === ui.reviewId);
    const f = i >= 0 ? list[i] : findReview(ui.reviewId);
    if (!f || f.r.state !== 'pending') { ui.view = 'reviews'; return reviews(); }
    const { t, r } = f;
    const files = (r.files || []).map((id) => t.attachments.find((a) => a.id === id)).filter(Boolean);
    const desc = t.notesHtml ? notifPlainHTML(t.notesHtml) : t.notes;
    return `<div class="ph-page ph-rv">
      ${backHead(`<span class="ph-kick">Review request${i >= 0 ? ` · ${i + 1} of ${list.length}` : ''}</span>${esc(t.title || 'Untitled task')}`, 'data-ph-tab="reviews"', `<button class="ph-round sm" data-action="rr-open" data-id="${t.id}" aria-label="Open task">${icon('open')}</button>`)}
      <div class="ph-rv-by">${avatarHTML(r.by, 32)}<span><b>${esc(fullName(userById(r.by)))}</b> sent ${plural(files.length, 'file')} · ${esc(timeAgo(r.at))}</span>${r.round > 1 ? `<span class="ph-tag amber">Round ${r.round}</span>` : ''}</div>
      <div class="ph-slides" id="ph-slides">${files.map((a) => fileSlide(t, a)).join('') || '<div class="ph-slide"><div class="ph-media"><span class="ph-ext">No files</span></div></div>'}</div>
      ${files.length > 1 ? `<div class="ph-dots" id="ph-dots">${files.map((_, k) => `<i class="${k ? '' : 'on'}"></i>`).join('')}</div>` : ''}
      ${desc ? `<div class="ph-rv-desc">${esc(desc)}</div>` : ''}
      <div class="ph-rv-note">Swipe through the files. Your notes are posted on the task for ${esc(firstName(r.by))}.</div>
      <div class="ph-rv-acts"><button class="ph-btn amber" data-ph="amend" data-id="${r.id}">Request amendments</button><button class="ph-btn green" data-ph="approve" data-id="${r.id}">${icon('check')}Approve</button></div>
    </div>`;
  }

  function projects() {
    const list = db.projects.filter((p) => !p.inactive && amSidebarOk(p)).sort(byOrder);   // active clients (an AM: their own)
    return `<div class="ph-page">
      ${head('Clients', plural(list.length, 'client'))}
      <div class="ph-list">${list.map((p) => {
        const open = db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done).length;
        return `<div class="pc pj" data-ph="open-project" data-id="${p.id}"><span class="ph-pj-ic" style="background:${p.color}">${esc(initials(p.name))}</span>
          <span class="pc-body"><span class="pc-title">${esc(p.name)}</span><span class="pc-meta">${plural(open, 'open task')}</span></span>${icon('chev-right')}</div>`;
      }).join('') || '<div class="ph-empty big">No clients yet</div>'}</div>
    </div>`;
  }
  function project() {
    const p = proj(ui.projectId);
    if (!p) { ui.view = 'projects'; return projects(); }
    const showDone = !!ui.showDone[p.id];
    const body = p.sections.map((s) => {
      const all = db.tasks.filter((t) => t.projectId === p.id && t.sectionId === s.id && !t.parentId).sort((a, b) => urgentFirst(a, b) || byOrder(a, b));
      const ts = showDone ? all : all.filter((t) => !t.done);
      if (!ts.length) return '';
      return `<div class="ph-gh"><i class="ph-dot" style="background:${s.color}"></i>${esc(s.name)}<span>${ts.length}</span></div>${ts.map((t) => card(t, { status: false })).join('')}`;
    }).join('');
    const cl = clientOfProject(p);
    return `<div class="ph-page">
      ${backHead(esc(p.name), 'data-ph-tab="projects"', `<button class="ph-round sm" data-action="toggle-show-done" aria-label="${showDone ? 'Hide' : 'Show'} completed">${icon(showDone ? 'check-circle' : 'check')}</button>`)}
      ${cl ? `<button class="ph-client" data-action="open-client" data-id="${cl.id}">${clientLogoHTML(cl, 22)}<span>${esc(cl.name)} brand assets</span>${icon('chev-right')}</button>` : ''}
      <div class="ph-list">${body || `<div class="ph-empty big">No open tasks${showDone ? '' : '<small>Tap ✓ above to show completed tasks.</small>'}</div>`}</div>
      ${fab()}
    </div>`;
  }

  function meScreen() {
    const u = me();
    const admin = isAdm(u);
    const row = (attrs, ic, label, sub = '') => `<button class="ph-row" ${attrs}>${icon(ic)}<span>${label}${sub ? `<small>${sub}</small>` : ''}</span>${icon('chev-right')}</button>`;
    const light = document.documentElement.dataset.theme === 'light';
    return `<div class="ph-page">
      <div class="ph-me-card">${avatarHTML(u.id, 64)}<div><b>${esc(fullName(u))}</b><span>${esc(designationOf(u))}</span><small>${esc(u.email)}</small></div></div>
      <div class="ph-rows">
        ${row('data-nav="profile"', 'user', 'My profile', 'Photo, office and notifications')}
        ${isCD() ? row('data-ph-tab="projects"', 'folder', 'Clients') : ''}
        ${Cal.canSee() && !calendarRetired() ? row('data-nav="calendar"', 'cal', 'Content calendar', 'Posts by day, channel and occasion') : ''}
        ${Plans.canSee() ? row('data-nav="plans"', 'cal', 'Content plans', 'Each client’s month · trial') : ''}
        ${row('data-nav="clients"', 'assets', 'Client Assets', 'Logos, guidelines and fonts')}
        ${row('data-nav="team"', 'users', 'Team members')}
        ${isManager() ? row('data-nav="trash"', 'trash', 'Trash', trashList().length ? `${trashList().length} item${trashList().length === 1 ? '' : 's'} · restore within ${TRASH_DAYS} days` : `Deleted items wait here ${TRASH_DAYS} days`) : ''}
        ${admin && Host.isServer ? row('data-nav="updates"', 'download', 'App updates') : ''}
        ${isTestCopy() && AppIcon.isOwner() && !(typeof ViewAs !== 'undefined' && ViewAs.viewing()) ? row('data-ph="sample"', 'trash', 'Start fresh with sample data', 'Test site only: wipes everything except you') : ''}
      </div>
      <div class="ph-rows">
        ${typeof Push !== 'undefined' ? Push.row() : ''}
        ${Host.isServer && Digest.wants({ ...u, prefs: {} }) ? `<button class="ph-row" data-action="toggle-digest">${icon('sun')}<span>Morning summary<small>10:30 am, Monday to Friday · switch off for holidays</small></span><i class="ph-state ${(u.prefs || {}).digestOff ? '' : 'on'}">${(u.prefs || {}).digestOff ? 'Off' : 'On'}</i></button>` : ''}
        <div class="ph-row ph-theme"><div class="pt-top">${icon(light ? 'sun' : 'moon')}<span>Appearance<small>${Theme.mode() === 'auto' ? 'Follows sunrise and sunset' : 'Always ' + Theme.mode()}</small></span></div>${Theme.picker('ph-seg-sm')}</div>
        ${Host.isServer ? '<button class="ph-row" data-action="whats-new">' + icon('info') + '<span>What’s new</span>' + icon('chev-right') + '</button>' : ''}
      </div>
      ${typeof ViewAs !== 'undefined' && ViewAs.available() ? `<div class="ph-rows"><button class="ph-row" data-va="pick">${icon('users')}<span>View as…<small>Test site only — use the app as a team member</small></span></button>${ViewAs.viewing() ? `<button class="ph-row" data-va="me">${icon('reply')}<span>Back to me</span></button>` : ''}</div>` : ''}
      <div class="ph-rows"><button class="ph-row danger" data-ph="sign-out">${icon('logout')}<span>Sign out</span></button></div>
      ${Host.isServer && Sync.version ? `<div class="ph-ver">E11 Console ${esc(Sync.version)}</div>` : ''}
    </div>`;
  }

  function search() {
    return `<div class="ph-page">
      ${backHead('Search', 'data-ph-tab="today"')}
      <div class="ph-search">${icon('search')}<input id="ph-q" type="search" name="e11-search" aria-autocomplete="none" data-form-type="other" placeholder="Search tasks" value="${esc(st.q)}" autocomplete="off"></div>
      <div class="ph-list" id="ph-results">${results()}</div>
    </div>`;
  }
  function results() {
    const q = st.q.trim();
    if (!q) return '<div class="ph-empty">Search titles, clients, people, tags, descriptions and comments. Try “overdue”, “urgent” or “mine” too.</div>';
    const r = taskSearch(q, { limit: 80 });
    const projects = r.projects.map((p) => `<div class="pc pj" data-ph="open-project" data-id="${p.id}"><span class="ph-pj-ic" style="background:${p.color}">${esc(initials(p.name))}</span>
      <span class="pc-body"><span class="pc-title">${sMark(p.name, r)}</span><span class="pc-meta">Client · ${plural(db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done).length, 'open task')}</span></span>${icon('chev-right')}</div>`).join('');
    const tasks = r.tasks.map((h) => { const why = searchWhy(h, r); return card(h.t, { mark: r }) + (why ? `<div class="ph-why">${why}</div>` : ''); }).join('');
    return (r.fixed.length ? searchFixedNote(r) : '')
      + (projects ? `<div class="ph-gh">Clients<span>${r.projects.length}</span></div>${projects}` : '')
      + (tasks ? `<div class="ph-gh">Tasks<span>${r.total}</span></div>${tasks}` : (projects ? '' : '<div class="ph-empty">No tasks found. Try a client or person’s name.</div>'));
  }

  /* ---------- Hooks called from app.js ---------- */
  function renderContent(c) {
    if (!st.on || ui.search || !OWN.has(ui.view)) return false;
    const v = ui.view;
    c.innerHTML = v === 'home' || v === 'today' ? (isOffice() ? OfficeHome.view() : myDay()) : v === 'mytasks' ? myTasks() : v === 'inbox' ? inbox()
      : v === 'reviews' ? reviews() : v === 'review' ? review() : v === 'projects' ? projects() : v === 'project' ? project()
      : v === 'psearch' ? search() : meScreen();
    if (ui.view === 'review') { wireSlides(c); hydrateThumbs(c); }
    if (v === 'inbox' && typeof fitWords === 'function') c.querySelectorAll('.ph-ib-t').forEach(fitWords);   // (task names cut at a whole word)
    pinHead(c);
    document.body.classList.toggle('ph-fab-on', !!document.querySelector('#ph-fabslot .ph-fab'));
    document.body.classList.toggle('ph-strip', !c.querySelector('.ph-bar'));
    return true;
  }
  // Pages shared with the desktop (profile, team, Client Assets…) get a phone header with a back button
  function decorate(c) {
    if (!st.on || OWN.has(ui.view)) return;
    document.body.classList.remove('ph-fab-on', 'ph-strip');
    let title = TITLES[ui.view] || 'E11 Console', back = 'data-ph-tab="me"';
    if (ui.view === 'client') {
      const cl = clientById(ui.clientId);
      const f = cl && cl.folders.find((x) => x.id === ui.folderId);
      title = esc(f ? f.name : cl ? cl.name : 'Client Assets');
      const up = f && f.parentId ? cl.folders.find((x) => x.id === f.parentId) : null;
      back = up ? `data-action="open-cfolder" data-id="${up.id}"` : f ? `data-action="open-client" data-id="${cl.id}"` : 'data-nav="clients"';
    }
    if (ui.view === 'plan') { const pl = Plans.planById(ui.planId), p = pl && proj(pl.projectId); title = p ? `${esc(p.name)} · ${esc(Plans.monthLabel(pl.month))}` : 'Content plan'; back = 'data-nav="plans"'; }
    if (ui.search) { title = 'Search'; back = 'data-ph-tab="today"'; }
    c.insertAdjacentHTML('afterbegin', backHead(title, back));
    pinHead(c);
  }
  // iOS 26 softens the top edge of anything that scrolls, so page headers live in a fixed layer
  // above the scrolling content (like the task page header, which stays sharp).
  function pinHead(c) {
    let top = document.getElementById('ph-top');
    if (!top) { top = document.createElement('div'); top.id = 'ph-top'; document.body.appendChild(top); }
    top.innerHTML = '';
    const h = c.querySelector(':scope > .ph-bar, :scope > .ph-page > .ph-bar, :scope > .ph-page > .ph-head, :scope > .ph-page > .ph-me-card');
    if (h) top.appendChild(h);
    top.hidden = !h; // while a task is open it's only made invisible (CSS), so it can still be measured
    let slot = document.getElementById('ph-fabslot');
    if (!slot) { slot = document.createElement('div'); slot.id = 'ph-fabslot'; document.body.appendChild(slot); }
    slot.innerHTML = '';
    const fabEl = c.querySelector('.ph-fab');
    if (fabEl) slot.appendChild(fabEl);
    const set = () => document.documentElement.style.setProperty('--ph-head-h', (top.firstElementChild ? top.offsetHeight : 0) + 'px');
    set(); requestAnimationFrame(set);
    if (!top._ro && window.ResizeObserver) { top._ro = new ResizeObserver(set); top._ro.observe(top); }
  }
  function unpin() { const top = document.getElementById('ph-top'); if (top) { top.innerHTML = ''; top.hidden = true; } const sl = document.getElementById('ph-fabslot'); if (sl) sl.innerHTML = ''; document.documentElement.style.setProperty('--ph-head-h', '0px'); }
  // The task page header on the phone: back, title and the Details / Comments switch
  function taskHead(t, tab, n) {
    if (!st.on) return '';
    return `<div class="ph-task-head">
      <div class="ph-bar"><button class="ph-back" data-action="close-detail" aria-label="Back">${icon('chev-left')}</button><b>${esc(t.title || 'Untitled task')}</b>
        <button class="ph-round sm" data-ph="task-more" aria-label="More">${icon('more')}</button></div>
      <div class="ph-seg in-task"><button class="${tab === 'details' ? 'on' : ''}" data-action="side-tab" data-tab="details">Details</button><button class="${tab === 'comments' ? 'on' : ''}" data-action="side-tab" data-tab="comments">Comments${n ? ` <i>${n}</i>` : ''}</button></div>
    </div>`;
  }

  function wireSlides(c) {
    const s = c.querySelector('#ph-slides'), dots = c.querySelector('#ph-dots');
    if (!s || !dots) return;
    s.addEventListener('scroll', () => {
      const k = Math.round(s.scrollLeft / Math.max(1, s.clientWidth));
      [...dots.children].forEach((d, i) => d.classList.toggle('on', i === k));
    }, { passive: true });
  }

  /* ---------- Sheets ----------
     A sheet slides up from the bottom. Pulled down by its top:
     - nothing typed yet → it closes
     - something typed   → it tucks into a small bar above the tab bar; the rest of the app stays usable.
       Tap or pull the bar up to carry on; pull the tucked bar down again to throw it away. */
  const sheetRoot = () => {
    let r = document.getElementById('ph-sheet-root');
    if (!r) { r = document.createElement('div'); r.id = 'ph-sheet-root'; document.body.appendChild(r); }
    return r;
  };
  const docked = () => $('#ph-sheet-root .ph-scrim.docked');
  function sheet(html, onWire, o = {}) {
    const root = sheetRoot();
    const old = root.firstElementChild;
    if (old && old.dataset.kind === o.kind && old._expand) { old._expand(); return; } // carry on with the tucked one
    root.innerHTML = `<div class="ph-scrim" data-kind="${o.kind || ''}"><div class="ph-sheet" role="dialog"><div class="ph-handle"><i class="ph-grab"></i></div>${html}<div class="ph-dock-hint">${esc(o.dockLabel || 'Draft')} · <b>Tap to continue</b></div></div></div>`;
    const scrim = root.firstElementChild;
    const box = scrim.firstElementChild;
    let closing = false;
    const setDockClass = () => document.body.classList.toggle('ph-docked', !!docked());
    const close = (discarded) => {
      if (closing || root.firstElementChild !== scrim) return;
      closing = true;
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      box.style.transition = ''; box.style.transform = '';
      scrim.classList.remove('in', 'docked');
      setDockClass();
      setTimeout(() => { if (root.firstElementChild === scrim) root.innerHTML = ''; }, 260);
      if (discarded === true) toast(o.discardedMsg || 'Draft discarded');
    };
    const dock = (instant) => {
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      // instant: the sheet has already slid down to where the bar sits, so swap without animating
      box.style.transition = instant ? 'none' : ''; box.style.transform = '';
      const t = box.querySelector('input:not([type]), input[type="text"], textarea');
      const hint = box.querySelector('.ph-dock-hint');
      hint.innerHTML = `${esc(o.dockLabel || 'Draft')}${t && t.value.trim() ? ` · <span>${esc(t.value.trim())}</span>` : ''} · <b>Tap to continue</b>`;
      scrim.classList.add('docked');
      setDockClass();
    };
    const expand = () => { box.style.transition = ''; box.style.transform = ''; scrim.classList.remove('docked'); scrim.classList.add('in'); setDockClass(); };
    scrim._expand = expand;
    const dirty = () => [...box.querySelectorAll('input:not([type]), input[type="text"], input[type="search"], textarea')].some((x) => x.value.trim());
    scrim.addEventListener('click', (e) => {
      if (scrim.classList.contains('docked')) { if (!e.target.closest('[data-sheet-close]')) { expand(); return; } }
      if (e.target.closest('[data-sheet-close]')) return close();
      if (e.target === scrim) { if (dirty()) dock(); else close(); }
    });
    requestAnimationFrame(() => scrim.classList.add('in'));
    dragSheet(scrim, box, { close, dock, expand, dirty });
    onWire && onWire(scrim, close);
  }
  function dragSheet(scrim, box, f) {
    let d = null;
    box.addEventListener('touchstart', (e) => {
      const t = e.touches[0];
      const isDocked = scrim.classList.contains('docked');
      const top = box.getBoundingClientRect().top;
      const onHandle = e.target.closest('.ph-handle, .ph-sh-head') && !e.target.closest('button');
      if (e.touches.length !== 1 || (!isDocked && !onHandle && (e.target.closest('button, input, select, textarea, label') || t.clientY - top > 64))) { d = null; return; }
      d = { y0: t.clientY, t0: Date.now(), dy: 0, h: box.offsetHeight, docked: isDocked, moved: false };
    }, { passive: true });
    box.addEventListener('touchmove', (e) => {
      if (!d) return;
      const raw = e.touches[0].clientY - d.y0;
      if (Math.abs(raw) > 6) d.moved = true;
      e.preventDefault();
      box.style.transition = 'none';
      if (d.docked) { d.dy = raw; box.style.transform = `translateY(${raw > 0 ? raw : raw / 3}px)`; return; }
      d.dy = Math.max(0, raw);
      box.style.transform = `translateY(${d.dy}px)`;
      scrim.style.background = `rgba(0,0,0,${0.55 * (1 - Math.min(1, d.dy / d.h))})`;
    }, { passive: false });
    const end = () => {
      if (!d) return;
      const cur = d; d = null;
      scrim.style.background = '';
      const fast = Math.abs(cur.dy) > 30 && Math.abs(cur.dy) / Math.max(1, Date.now() - cur.t0) > 0.5;
      const spring = () => { box.style.transition = 'transform .22s cubic-bezier(.2,.8,.2,1)'; box.style.transform = ''; };
      if (cur.docked) {
        if (cur.dy > 40 || (fast && cur.dy > 0)) { box.style.transition = 'transform .2s ease-in'; box.style.transform = 'translateY(140%)'; setTimeout(() => f.close(true), 180); }
        else if (cur.dy < -20 || (fast && cur.dy < 0)) f.expand();
        else spring(); // a tap is handled by the click
        if (cur.moved) scrim._skipClick = true;
        return;
      }
      if (cur.dy > Math.min(140, cur.h * 0.3) || fast) {
        if (f.dirty()) {
          // slide on down until only the top strip shows, then become the tucked bar in that same spot
          // where the tucked bar will sit: measure it without showing it (class on and off in the same frame)
          const now = box.getBoundingClientRect().top - cur.dy;
          scrim.classList.add('docked'); const barTop = box.getBoundingClientRect().top - cur.dy; scrim.classList.remove('docked');
          box.style.transition = 'transform .22s cubic-bezier(.2,.8,.2,1)';
          box.style.transform = `translateY(${Math.max(0, barTop - now)}px)`;
          setTimeout(() => { f.dock(true); requestAnimationFrame(() => requestAnimationFrame(() => { box.style.transition = ''; })); }, 220);
        }
        else { box.style.transition = 'transform .22s ease-in'; box.style.transform = 'translateY(100%)'; scrim.classList.remove('in'); setTimeout(f.close, 200); }
      } else spring();
    };
    box.addEventListener('touchend', end);
    box.addEventListener('touchcancel', end);
    // a drag on the tucked bar shouldn't also count as a tap
    scrim.addEventListener('click', (e) => { if (scrim._skipClick) { scrim._skipClick = false; e.stopImmediatePropagation(); } }, true);
  }

  function quickAdd() {
    if (!can('createTask')) return denied();
    const inProject = ui.view === 'project' && proj(ui.projectId) ? ui.projectId : '';
    const mgr = isAdm(me()) || me().role === 'am' || isCD();
    const people = activeUsers();
    const projOpts = `<option value="">No client (My Tasks)</option>` + db.projects.filter((p) => (!p.inactive && amClientOk(p)) || p.id === inProject).sort(byOrder).map((p) => `<option value="${p.id}" ${p.id === inProject ? 'selected' : ''}>${esc(p.name)}</option>`).join('');
    // (only Production, Social, Freelancers and the Creative Director can be assigned)
    const meOk = assignable(me());
    const userOpts = (meOk ? `<option value="${currentUserId}">Me</option>` : '<option value="">Nobody yet</option>') + people.filter((u) => u.id !== currentUserId && assignable(u)).map((u) => `<option value="${u.id}">${esc(fullName(u))}</option>`).join('') + (meOk ? '<option value="">Nobody yet</option>' : '');
    sheet(`<div class="ph-sh-head"><h2>New task</h2><button class="ph-link" data-sheet-close>Cancel</button></div>
      <label class="ph-field"><span>Title</span><input id="qa-title" name="e11-task-title" type="text" placeholder="What needs doing?" autocomplete="off" aria-autocomplete="none" data-1p-ignore data-lpignore="true" data-form-type="other" enterkeyhint="next"></label>
      <label class="ph-field"><span>Description <i>(optional)</i></span><textarea id="qa-desc" name="e11-task-notes" autocomplete="off" aria-autocomplete="none" data-form-type="other" rows="3" placeholder="Details, links or notes for the team"></textarea></label>
      <div class="ph-form">
        <label><span>Client</span><select id="qa-proj">${projOpts}</select></label>
        ${can('assign') ? `<label><span>Assign to</span><select id="qa-who">${userOpts}</select></label>` : ''}
        <label><span>Due</span><input type="date" id="qa-due" value="${ui.view === 'today' || ui.view === 'home' || ui.view === 'mytasks' ? todayStr() : ''}"></label>
        ${mgr ? `<label class="ph-sw"><span>CD review</span><em>Needs CD review</em><input type="checkbox" id="qa-cd" ${inProject ? 'checked' : ''}><i></i></label>` : ''}
      </div>
      <button class="ph-btn primary wide" id="qa-go">Create task</button>`, (scrim, close) => {
      const ti = $('#qa-title', scrim), pj = $('#qa-proj', scrim), cd = $('#qa-cd', scrim);
      setTimeout(() => ti.focus(), 250);
      if (cd) pj.addEventListener('change', () => { cd.checked = !!pj.value; });
      const go = () => {
        const title = ti.value.trim();
        if (!title) { ti.focus(); toast('Give the task a name'); return; }
        const who = $('#qa-who', scrim) ? $('#qa-who', scrim).value : assignable(me()) ? currentUserId : '';
        if (cd && cd.checked && who && who === cdUserId()) { toast('A task that needs CD review can’t be assigned to the Creative Director. Turn off CD review or choose someone else.'); return; }
        const desc = $('#qa-desc', scrim).value.trim();
        const t = createTask({ title, projectId: pj.value || null, due: $('#qa-due', scrim).value || null, notes: desc, ...(desc ? { notesHtml: linkify(esc(desc)).replace(/\n/g, '<br>') } : {}) });
        if (cd) t.needsCD = !!(cd.checked && t.projectId);
        if (who) {
          t.assignees = [who];
          if (who !== currentUserId) { logActivity(t, `assigned <b>${esc(fullName(userById(who)))}</b>`); pushNotif(who, t, 'assigned', 'assigned you to'); }
        }
        commit({ delay: 0 });
        close();
        toast(`Created “${title}”`, { label: 'Open', run: () => openTask(t.id) });
      };
      $('#qa-go', scrim).addEventListener('click', go);
      ti.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); $('#qa-desc', scrim).focus(); } });
    }, { kind: 'new-task', dockLabel: 'New task', discardedMsg: 'New task discarded' });
  }

  function amendSheet(id) {
    const f = findReview(id);
    if (!f || !isCD()) return;
    sheet(`<div class="ph-sh-head"><h2>Request amendments</h2><button class="ph-link" data-sheet-close>Cancel</button></div>
      <p class="ph-sh-p">Tell ${esc(firstName(f.r.by))} what to change. It's posted as a comment on the task.</p>
      <textarea id="am-note" name="e11-amend-notes" autocomplete="off" aria-autocomplete="none" data-form-type="other" rows="5" placeholder="e.g. Use the new logo lockup and make the date bigger"></textarea>
      <button class="ph-btn amber wide" id="am-go">Send back</button>`, (scrim, close) => {
      const ta = $('#am-note', scrim);
      setTimeout(() => ta.focus(), 250);
      $('#am-go', scrim).addEventListener('click', () => {
        const v = ta.value.trim();
        if (!v) { ta.focus(); toast('Describe the changes required'); return; }
        close();
        decideReview(f.t, f.r, 'amend', esc(v).replace(/\n/g, '<br>'));
        toast(`Sent back to ${firstName(f.r.by)} with your notes`);
        nextReview();
      });
    }, { kind: 'amend-' + id, dockLabel: 'Amendments for ' + firstName(f.r.by), discardedMsg: 'Amendment notes discarded' });
  }
  function nextReview() {
    const left = activeReviews();
    if (left.length) { ui.reviewId = left[0].r.id; ui.view = 'review'; } else ui.view = 'reviews';
    $('#content').scrollTop = 0;
    render();
  }

  function taskMore() {
    const t = task(ui.taskId);
    if (!t) return;
    const items = [
      { label: 'Attach files', icon: 'clip', run: () => attachFiles('task') },
      ...(t.projectId ? [{ label: 'Open client', icon: 'folder', run: () => { closeDetail(); go('project', t.projectId); } }] : []),
      ...(can('deleteTask') ? ['-', { label: 'Delete task', icon: 'trash', danger: true, run: () => deleteTaskFlow(t.id) }] : []),
    ];
    showMenu(document.body, items);
  }

  /* ---------- Taps ---------- */
  document.addEventListener('click', (e) => {
    if (!st.on || !db || !currentUserId) return;
    // a task tapped in a list always opens on Details
    const pc = e.target.closest('.pc[data-task]');
    if ((pc && !e.target.closest('button')) || e.target.closest('.ph-ib')) { ui.sideTab = 'details'; ui.activityFilter = 'comments'; }
    const tab = e.target.closest('[data-ph-tab]');
    if (tab) {
      e.stopPropagation();
      if (ui.taskId) closeDetail();
      closeMenus();
      const v = tab.dataset.phTab;
      if (v === 'reviews') ui.rrTab = 'active';
      if (v === 'mytasks') { ui.workF = null; ui.myTasksTab = 'todo'; }
      go(v);
      return;
    }
    const el = e.target.closest('[data-ph]');
    if (!el) return;
    e.stopPropagation();
    const id = el.dataset.id;
    switch (el.dataset.ph) {
      case 'quick-add': quickAdd(); break;
      case 'search': go('psearch'); setTimeout(() => { const q = $('#ph-q'); if (q) q.focus(); }, 50); break;
      case 'ibf': st.ibf = el.dataset.k; render(); break;
      case 'open-review': ui.reviewId = id; go('review'); break;
      case 'approve': {
        const f = findReview(id);
        if (!f) return;
        decideReview(f.t, f.r, 'approve');
        toast(`Approved — ${firstName(f.r.by)} has been notified`);
        nextReview();
        break;
      }
      case 'amend': amendSheet(id); break;
      case 'preview': { const t = task(el.dataset.tid); const a = t && findAttachment(t, id); if (a) previewFile(a); break; }
      case 'open-project': go('project', id); break;
      case 'task-more': taskMore(); break;
      case 'sample': resetSampleData(); break;
      case 'sign-out': dialog({ title: 'Sign out?', body: 'You’ll need the code from your email to sign in again.', okText: 'Sign out' }).then((ok) => { if (ok) signOut(); }); break;
      default: break;
    }
  }, true);
  document.addEventListener('input', (e) => {
    if (e.target.id !== 'ph-q') return;
    st.q = e.target.value;
    const r = $('#ph-results');
    if (r) r.innerHTML = results();
  });

  check();
  return { get on() { return st.on; }, isOn, renderContent, decorate, chrome, taskHead, quickAdd, check, resetInbox: () => { st.ibf = 'unread'; } };
})();

/* Phone notifications (Web Push): the switch on the Me page, and opening a task from a notification */
const Push = (() => {
  const st = { state: 'unknown', busy: false };
  const ios = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const standalone = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const supported = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  const keyBytes = (k) => { const s = atob(k.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((k.length + 3) % 4)); return Uint8Array.from(s, (c) => c.charCodeAt(0)); };

  async function refresh() {
    if (!Host.isServer) { st.state = 'none'; return paint(); }
    if (!supported()) { st.state = ios && !standalone() ? 'install' : 'unsupported'; return paint(); }
    if (Notification.permission === 'denied') { st.state = 'denied'; return paint(); }
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (!sub) st.state = 'off';
      else {
        const r = await api('POST', '/api/push/status', { endpoint: sub.endpoint });
        if (!r.on) await api('POST', '/api/push/subscribe', { subscription: sub.toJSON() }); // the server forgot it: tell it again
        st.state = 'on';
      }
    } catch (e) { st.state = 'off'; }
    paint();
  }
  function paint() {
    const el = document.getElementById('ph-push');
    if (el) el.outerHTML = row(true);
    const pf = document.getElementById('pf-push');
    if (pf) pf.outerHTML = profileRow(true);
  }
  // My profile on a computer: the same notifications, for this browser (the Mac app shows its own while it's open)
  function profileRow(noRefresh) {
    if (Host.isMacApp) return `<div class="pf-opt" id="pf-push"><div><b>Notifications</b><span>The Mac app shows a banner for every Inbox update while it’s running — closing its window keeps it running (⌘Q quits), and <b>Open at Login</b> in its app menu starts it with your Mac.</span></div></div>`;
    if (!noRefresh) setTimeout(refresh, 0);
    if (st.state === 'none') return '';
    const sub = { on: 'A banner for every Inbox update, even when this tab is closed', off: 'Get a banner for every Inbox update, even when this tab is closed', denied: 'Blocked in this browser — allow notifications for this site in the browser’s settings', unsupported: 'This browser can’t show notifications', unknown: '' }[st.state] || '';
    const ctl = st.state === 'on' || st.state === 'off'
      ? `<div class="pf-opt-btns">${st.state === 'on' ? '<button class="btn sm" data-pf-push="test">Send test</button>' : ''}<button class="switch ${st.state === 'on' ? 'on' : ''}" data-pf-push="toggle" aria-label="Notifications on this computer" ${st.busy ? 'disabled' : ''}><i></i></button></div>` : '';
    return `<div class="pf-opt" id="pf-push"><div><b>Notifications on this computer</b><span>${sub}</span></div>${ctl}</div>`;
  }
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-pf-push]'); if (!b || st.busy) return;
    if (b.dataset.pfPush === 'test') api('POST', '/api/push/test', {}).then((r) => toast(r.sent ? 'Sent — it may take a few seconds' : 'Couldn’t reach this computer — switch it off and on again')).catch((er) => toast(er.message));
    else if (st.state === 'on') turnOff(); else if (st.state === 'off') turnOn();
  });
  function row(noRefresh) {
    if (!noRefresh) setTimeout(refresh, 0);
    if (st.state === 'none') return '';
    const label = { on: 'On', off: 'Off', denied: 'Blocked', install: 'Set up', unsupported: 'Not available', unknown: '' }[st.state];
    const sub = { on: 'A banner for every Inbox update', off: 'Get a banner even when the app is closed', denied: 'Allow them in iPhone Settings → Notifications → E11 Console', install: 'Add E11 Console to your Home Screen first', unsupported: 'This browser can’t show notifications', unknown: '' }[st.state];
    return `<button class="ph-row" id="ph-push" data-ph-push>${icon('bell')}<span>Notifications on this phone<small>${sub}</small></span><i class="ph-state ${st.state === 'on' ? 'on' : ''}">${st.busy ? '…' : label}</i></button>`;
  }

  async function turnOn() {
    st.busy = true; paint();
    try {
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') { st.state = perm === 'denied' ? 'denied' : 'off'; return; }
      const reg = await navigator.serviceWorker.ready;
      const { key } = await api('GET', '/api/push/key');
      const sub = (await reg.pushManager.getSubscription()) || await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(key) });
      await api('POST', '/api/push/subscribe', { subscription: sub.toJSON() });
      st.state = 'on';
      toast(`Notifications are on for this ${Phone.on ? 'phone' : 'computer'}`);
    } catch (e) { toast('Couldn’t turn on notifications: ' + e.message); } finally { st.busy = false; paint(); }
  }
  async function turnOff() {
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (sub) { await api('POST', '/api/push/unsubscribe', { endpoint: sub.endpoint }).catch(() => {}); await sub.unsubscribe(); }
      st.state = 'off'; paint();
      toast(`Notifications are off for this ${Phone.on ? 'phone' : 'computer'}`);
    } catch (e) { toast(e.message); }
  }
  function installHelp() {
    dialog({
      title: 'Add E11 Console to your Home Screen',
      body: 'iPhone only sends notifications to apps on the Home Screen. In Safari, tap the Share button (the square with an arrow), choose “Add to Home Screen”, then open E11 Console from its new icon and come back here.',
      okText: 'Got it', cancelText: null,
    });
  }

  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-ph-push]');
    if (!el || st.busy) return;
    e.stopPropagation();
    if (st.state === 'install') return installHelp();
    if (st.state === 'denied') return dialog({ title: 'Notifications are blocked', body: 'Open iPhone Settings → Notifications → E11 Console and turn on Allow Notifications. Then come back here.', okText: 'OK', cancelText: null });
    if (st.state === 'off') return turnOn();
    if (st.state === 'on') {
      showMenu(el, [
        { label: 'Send a test notification', icon: 'bell', run: () => api('POST', '/api/push/test', {}).then((r) => toast(r.sent ? 'Sent — it may take a few seconds' : 'Couldn’t reach this phone — try turning it off and on')).catch((err) => toast(err.message)) },
        { label: 'Turn off on this phone', icon: 'x', danger: true, run: turnOff },
      ]);
    }
  }, true);

  // Opening the app from a notification
  // The update a notification is about may not have reached the app yet (it was asleep, or is still catching up):
  // go to the right kind of page straight away, then open the update itself as soon as it arrives (up to ~8 s).
  function openFrom(taskId, nid, hint = {}) {
    const has = () => nid && db.notifications.some((n) => n.id === nid);
    const byKind = () => {
      const k = hint.kind || '';
      if ((k === 'review' || k === 'review-wd') && isCD()) { if (ui.taskId) closeDetail(); go('reviews'); return true; }
      if (k === 'asset' && hint.clientId && clientById(hint.clientId)) { const c = clientById(hint.clientId); openClient(c.id, c.folders.some((x) => x.id === hint.folderId) ? hint.folderId : null); return true; }
      if (/^claim/.test(k)) { Claims.openNotif({ kind: k }); return true; }
      if (/^plan/.test(k) && hint.planId && Plans.planById(hint.planId)) { Plans.open(hint.planId); return true; }
      return false;
    };
    const start = () => {
      ui.sideTab = 'details';
      if (has()) { openNotif(nid); return; }
      if (taskId && !nid) return TaskLink.open(taskId); // a shared link: may hand over to the Mac app
      // meanwhile: the right page for its kind, or the task (on Comments for a comment, @mention or amendments)
      if (!byKind() && taskId && task(taskId)) {
        if (['comment', 'mention', 'review-amend'].includes(hint.kind) && hint.commentId) ui.sideTab = ui.forceTab = 'comments';
        openTask(taskId);
      }
      if (!nid) return;
      const t0 = Date.now(), here = () => `${ui.view}|${ui.taskId || ''}`, was = here();
      const wait = setInterval(() => {
        if (here() !== was || Date.now() - t0 > 8000) clearInterval(wait);   // (they moved on themselves, or it never came)
        else if (has()) { clearInterval(wait); openNotif(nid); }
      }, 250);
    };
    if (typeof db !== 'undefined' && db && currentUserId) return start();
    const iv = setInterval(() => { if (typeof db !== 'undefined' && db && currentUserId) { clearInterval(iv); setTimeout(start, 300); } }, 250);
    setTimeout(() => clearInterval(iv), 30000);
  }
  // a notification that opens a page (occasion reminders open the Content calendar)
  function openView(view) {
    const ok = { calendar: 1 };
    if (!ok[view]) return;
    const run = () => go(view);
    if (typeof db !== 'undefined' && db && currentUserId) return run();
    const iv = setInterval(() => { if (typeof db !== 'undefined' && db && currentUserId) { clearInterval(iv); setTimeout(run, 300); } }, 250);
    setTimeout(() => clearInterval(iv), 30000);
  }
  const q = new URLSearchParams(location.search);
  if (q.get('task') || q.get('n')) { openFrom(q.get('task'), q.get('n'), { kind: q.get('k'), clientId: q.get('c'), folderId: q.get('f'), planId: q.get('pl') }); history.replaceState(null, '', '/'); }   // (an update without a task, e.g. Client Assets, has only n)
  else if (q.get('view')) { openView(q.get('view')); history.replaceState(null, '', '/'); }
  if ('serviceWorker' in navigator) navigator.serviceWorker.addEventListener('message', (e) => { if (e.data && e.data.type === 'open-task') openFrom(e.data.taskId, e.data.nid, e.data.hint || {}); if (e.data && e.data.type === 'open-view') openView(e.data.view); });

  return { row, refresh, profileRow };
})();

/* Swipe from the left edge to go back, like a native iPhone app (only in the Home Screen app —
   in Safari the browser's own edge swipe would fight it). The page you're going back to is already there
   underneath, a little to the left and dimmed, and slides in more slowly than your finger (parallax).
   - an open task: the list behind it is live, so it simply moves with the swipe
   - a page: a still copy of this page slides away while the real previous page is drawn underneath
     straight away (so what comes into view is exactly where you land); letting go early puts it all back
   - a comment thread: the thread slides away to the comments */
(() => {
  const EDGE = 28, DONE = 0.33, PAR = 0.3, DIM = 0.22;
  let g = null;
  const standalone = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true || window.__phSwipeAlways;
  function target() {
    if ($('#overlay-root').firstElementChild || $('.menu') || $('#ph-sheet-root .ph-scrim:not(.docked)')) return null; // a sheet or menu is open
    if (ui.taskId) {
      const pane = $('#detail');
      if (ui.thread && pane.dataset.tab === 'comments') return { kind: 'thread', btn: $('.th-back', pane), layer: $('.tm-activity', pane) };
      return { kind: 'task', btn: $('.ph-task-head .ph-back', pane), layer: $('.tm', pane) };
    }
    const btn = $('#ph-top .ph-back') || $('#content .ph-back');
    return btn ? { kind: 'page', btn, layer: $('#content') } : null;
  }
  const move = (el, x, anim) => {
    if (!el) return;
    el.style.transition = anim ? 'transform .22s cubic-bezier(.2,.8,.2,1)' : 'none';
    el.style.transform = x ? `translate3d(${x}px,0,0)` : '';
  };
  const fade = (el, o, anim) => { if (!el) return; el.style.transition = anim ? 'opacity .22s cubic-bezier(.2,.8,.2,1)' : 'none'; el.style.opacity = String(o); };
  const dimLayer = (parent, before, z) => {
    const d = document.createElement('div');
    d.className = 'ph-swipe-dim';
    d.style.cssText = `position:${parent === document.body ? 'fixed' : 'absolute'};left:0;right:0;top:0;bottom:0;background:#000;opacity:${DIM};pointer-events:none;${z != null ? 'z-index:' + z + ';' : ''}`;
    parent.insertBefore(d, before || null);
    return d;
  };
  // set up what sits underneath, the first time the finger really moves
  function begin(c) {
    const w = window.innerWidth;
    c.w = w;
    if (c.kind === 'task') {
      // the task pane lives inside #main, so move the list itself (not its parents); the page header sits
      // above the pane in the stacking order, so it is cut off where the pane starts and dimmed with a filter
      c.under = [$('#content')].filter(Boolean);
      const top = $('#ph-top'); if (top) { top.style.visibility = 'visible'; c.top = top; }
      c.dim = dimLayer($('#detail'), c.layer);
    } else if (c.kind === 'page') {
      // a still copy of this page (and its header) on top, then the real previous page drawn underneath
      const app = $('#app'), top = $('#ph-top'), content = $('#content');
      const scroll = content ? content.scrollTop : 0;
      const fg = document.createElement('div');
      fg.className = 'ph-swipe-fg';
      fg.style.cssText = 'position:fixed;left:0;right:0;top:0;height:var(--app-h,100%);z-index:22;pointer-events:none;background:var(--ph-bg)';
      fg.appendChild(app.cloneNode(true));
      if (top && !top.hidden) fg.appendChild(top.cloneNode(true));
      document.body.appendChild(fg);                       // after the originals, so their ids still find the real ones
      const cc = fg.querySelector('#content'); if (cc) cc.scrollTop = scroll;
      c.fg = fg; c.layer = fg;
      c.saved = { ui: { ...ui }, scroll };
      c.btn.click();                                       // draw the page we're going back to, underneath
      c.under = [$('#app'), $('#ph-top')].filter(Boolean);
      c.dim = dimLayer(document.body, fg, 21);          // above the real header (z 20), below the copy
    } else c.under = [];
    c.under.forEach((el) => move(el, -w * PAR, false));
    if (c.top) track(c, 0);
  }
  function track(c, dx) {
    move(c.layer, dx, false);
    const p = Math.min(1, dx / c.w);
    c.under.forEach((el) => move(el, -c.w * PAR * (1 - p), false));
    fade(c.dim, DIM * (1 - p), false);
    if (c.top) {
      const tx = -c.w * PAR * (1 - p);
      move(c.top, tx, false);
      c.top.style.clipPath = `inset(0 ${Math.max(0, c.w - (dx - tx))}px 0 0)`;
      c.top.style.filter = `brightness(${1 - DIM * (1 - p)})`;
    }
  }
  function cleanup(c) {
    [...c.under, c.top].forEach((el) => { if (el) { el.style.transition = 'none'; el.style.transform = ''; } });
    const top = $('#ph-top'); if (top) { top.style.visibility = ''; top.style.clipPath = ''; top.style.filter = ''; }
    if (c.dim) c.dim.remove();
    if (c.fg) c.fg.remove();
  }
  // iOS stops sending a touch's events to the page once the element under the finger is removed (going back
  // redraws the page), so listen on that element too; each event is handled once
  let held = null;
  const hold = (el) => { release(); held = el; if (el) { el.addEventListener('touchmove', onMove, { passive: false }); el.addEventListener('touchend', end); el.addEventListener('touchcancel', end); } };
  const release = () => { if (held) { held.removeEventListener('touchmove', onMove); held.removeEventListener('touchend', end); held.removeEventListener('touchcancel', end); held = null; } };
  // leftovers from a swipe that never got its end (shouldn't happen, but never leave the page stuck)
  const sweep = () => {
    document.querySelectorAll('.ph-swipe-fg, .ph-swipe-dim').forEach((n) => n.remove());
    [$('#app'), $('#content'), $('#ph-top')].forEach((el) => { if (el) { el.style.transition = ''; el.style.transform = ''; el.style.clipPath = ''; el.style.filter = ''; } });
    const top = $('#ph-top'); if (top) top.style.visibility = '';
  };
  document.addEventListener('touchstart', (e) => {
    if (!g && document.querySelector('.ph-swipe-fg, .ph-swipe-dim')) sweep();
    g = null;
    if (!Phone.on || !standalone() || e.touches.length !== 1) return;
    const t = e.touches[0];
    if (t.clientX > EDGE) return;
    const tg = target();
    if (!tg || !tg.btn || !tg.layer) return;
    g = { x0: t.clientX, y0: t.clientY, t0: Date.now(), dx: 0, on: false, under: [], ...tg };
    hold(e.target);
  }, { passive: true });
  function onMove(e) {
    if (!g || e.__phSwipe) return;
    e.__phSwipe = true;
    const t = e.touches[0];
    const dx = t.clientX - g.x0, dy = t.clientY - g.y0;
    if (!g.on) {
      if (Math.abs(dy) > 12 && Math.abs(dy) > Math.abs(dx)) { g = null; return; } // scrolling, not swiping
      if (dx < 10) return;
      g.on = true;
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      begin(g);
    }
    e.preventDefault();
    g.dx = Math.max(0, dx);
    track(g, g.dx);
    clearTimeout(g.idle); const me = g;
    g.idle = setTimeout(() => { if (g === me) end(); }, 4000); // no word from the finger for a while: settle
  }
  document.addEventListener('touchmove', onMove, { passive: false });
  function end(e) {
    if (e) { if (e.__phSwipe) return; e.__phSwipe = true; }
    release();
    if (g) clearTimeout(g.idle);
    if (!g || !g.on) { g = null; return; }
    const c = g; g = null;
    const w = c.w;
    const fast = c.dx > 50 && c.dx / Math.max(1, Date.now() - c.t0) > 0.5;
    const glide = (to) => { // the header has no transform-only path, so walk it along with the release
      if (!c.top) return;
      const from = c.dx, t0 = performance.now();
      const step = (now) => { const k = Math.min(1, (now - t0) / 220), e = 1 - Math.pow(1 - k, 3);
        if (c.top.style.visibility !== 'visible') return;
        const dx = from + (to - from) * e, p = dx / w, tx = -w * PAR * (1 - p);
        c.top.style.transition = 'none'; c.top.style.transform = `translate3d(${tx}px,0,0)`;
        c.top.style.clipPath = `inset(0 ${Math.max(0, w - (dx - tx))}px 0 0)`; c.top.style.filter = `brightness(${1 - DIM * (1 - p)})`;
        if (k < 1) requestAnimationFrame(step); };
      requestAnimationFrame(step);
    };
    if (c.dx > w * DONE || fast) {
      glide(w);
      move(c.layer, w, true); c.under.forEach((el) => move(el, 0, true)); fade(c.dim, 0, true);
      setTimeout(() => {
        if (c.kind !== 'page') { c.btn.click(); move(c.layer, 0, false); } // (a page already went back underneath)
        cleanup(c);
      }, 220);
    } else {
      glide(0);
      move(c.layer, 0, true); c.under.forEach((el) => move(el, -w * PAR, true)); fade(c.dim, DIM, true);
      setTimeout(() => {
        if (c.kind === 'page' && c.saved) {
          // let go early: put the page we were on back (still hidden under its copy), then lift the copy
          Object.assign(ui, c.saved.ui); render();
          const content = $('#content'); if (content) content.scrollTop = c.saved.scroll;
        }
        cleanup(c);
      }, 220);
    }
  }
  document.addEventListener('touchend', end);
  document.addEventListener('touchcancel', end);
})();

/* Swipe left / right on a page to move between its tabs: To Do ↔ Done, Details ↔ Comments,
   Unread ↔ All ↔ Mentions. (A swipe that starts at the very left edge is "back" instead.) */
(() => {
  let g = null;
  const SKIP = 'input, textarea, select, [contenteditable="true"], .ph-slides, .ph-chips, .wf-bar, .tr-chips, .fin-chips, .fin-tabs, .fa-tabs, .tile-grid, .menu, .ph-sheet, .ap-video, video, .board';
  function tabsHere() {
    if ($('#overlay-root').firstElementChild || $('#ph-sheet-root .ph-scrim:not(.docked)') || $('.menu')) return null;
    if (ui.taskId) {
      if (ui.thread) return null;
      const btns = $$('#detail .ph-task-head .ph-seg button');
      return btns.length > 1 ? { btns, area: () => [$('#detail .tm-body')].filter(Boolean) } : null;
    }
    const btns = $$('#content .ph-seg button').length ? $$('#content .ph-seg button') : $$('#content .ph-chips button');
    return btns.length > 1 ? { btns, area: () => below($$('#content .ph-seg button, #content .ph-chips button')[0], $('#content > .ph-page')) } : null;
  }
  // What moves with the swipe: only the content under the tabs (the tabs and the heading stay put)
  function below(btn, root) {
    if (!root) return [];
    if (!btn || !root.contains(btn)) return [root];
    let h = btn;
    while (h.parentElement && h.parentElement !== root) h = h.parentElement;
    const out = [];
    for (let n = h.nextElementSibling; n; n = n.nextElementSibling) if (!n.classList.contains('wf-bar')) out.push(n);
    return out.length ? out : [root];
  }
  const each = (els, fn) => (Array.isArray(els) ? els : els ? [els] : []).forEach(fn);
  document.addEventListener('touchstart', (e) => {
    g = null;
    if (!Phone.on || e.touches.length !== 1) return;
    const t = e.touches[0];
    if (t.clientX <= 28 || e.target.closest(SKIP)) return;
    const tabs = tabsHere();
    if (!tabs) return;
    g = { x0: t.clientX, y0: t.clientY, dx: 0, on: false, tabs, el: tabs.area() };
  }, { passive: true });
  document.addEventListener('touchmove', (e) => {
    if (!g) return;
    const t = e.touches[0];
    const dx = t.clientX - g.x0, dy = t.clientY - g.y0;
    if (!g.on) {
      if (Math.abs(dy) > 10 && Math.abs(dy) > Math.abs(dx)) { g = null; return; } // scrolling
      if (Math.abs(dx) < 14 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
      g.on = true;
    }
    e.preventDefault();
    g.dx = dx;
    each(g.el, (el) => { el.style.transition = 'none'; el.style.transform = `translateX(${dx * 0.25}px)`; el.style.opacity = String(1 - Math.min(0.35, Math.abs(dx) / 900)); });
  }, { passive: false });
  const end = () => {
    if (!g || !g.on) { g = null; return; }
    const cur = g; g = null;
    const reset = (els) => each(els, (el) => { el.style.transition = 'transform .2s ease, opacity .2s ease'; el.style.transform = ''; el.style.opacity = ''; });
    const btns = cur.tabs.btns;
    const i = btns.findIndex((b) => b.classList.contains('on'));
    const j = cur.dx < -60 ? i + 1 : cur.dx > 60 ? i - 1 : i;
    if (j === i || j < 0 || j >= btns.length) { reset(cur.el); return; }
    btns[j].click();
    const now = cur.tabs.area();
    each(now, (el) => { el.classList.remove('ph-in-l', 'ph-in-r'); void el.offsetWidth; el.classList.add(cur.dx < 0 ? 'ph-in-r' : 'ph-in-l'); el.style.transform = ''; el.style.opacity = ''; });
    reset((cur.el || []).filter((el) => !now.includes(el)));
  };
  document.addEventListener('touchend', end);
  document.addEventListener('touchcancel', end);
})();


/* Phone pop-up menus (reactions, ••• menus, priority, people…): darken everything behind and stop the
   page scrolling underneath. Tapping the dark area closes the menu. (The @mention list while typing is left alone.) */
(() => {
  let scrim = null;
  const open = () => !!document.querySelector('body > .menu:not(.mention-pop)');
  const sync = () => {
    const on = Phone.on && open();
    document.body.classList.toggle('ph-menu-open', on);
    if (on && !scrim) {
      scrim = document.createElement('div');
      scrim.id = 'ph-menu-scrim';
      const shut = (e) => { e.preventDefault(); e.stopPropagation(); closeMenus(); sync(); };
      scrim.addEventListener('touchstart', shut, { passive: false });
      scrim.addEventListener('click', shut);
      document.body.appendChild(scrim);
    } else if (!on && scrim) { scrim.remove(); scrim = null; }
  };
  // iPhone only registers a newly shown scrolling area after it next lays the page out, so the first swipe
  // in a fresh menu did nothing. Show each new menu's scrolling parts as not scrollable for a moment,
  // then switch scrolling on: that change makes iPhone register them straight away.
  const wake = (m) => {
    const els = [m, ...m.querySelectorAll('.ap-list')];
    els.forEach((el) => { el.style.overflowY = 'hidden'; });
    setTimeout(() => requestAnimationFrame(() => els.forEach((el) => { el.style.overflowY = ''; })), 60);
  };
  new MutationObserver((recs) => {
    recs.forEach((r) => r.addedNodes.forEach((n) => { if (Phone.on && n.nodeType === 1 && n.classList.contains('menu')) wake(n); }));
    sync();
  }).observe(document.body, { childList: true });
  document.addEventListener('touchmove', (e) => {
    if (!document.body.classList.contains('ph-menu-open')) return;
    const inMenu = e.target.closest && e.target.closest('.menu');
    if (!inMenu) { e.preventDefault(); return; }
    // inside the menu: allow scrolling only where there is something to scroll
    let el = e.target;
    while (el && el !== inMenu.parentElement) { if (el.scrollHeight > el.clientHeight + 1 && /(auto|scroll)/.test(getComputedStyle(el).overflowY)) return; el = el.parentElement; }
    e.preventDefault();
  }, { passive: false });
})();

/* Phone pop-ups as bottom sheets: drag down by the handle (or from the top of a scrolled-up list) to close,
   and keep the sheet above the keyboard when a search box in it is being typed in. */
(() => {
  const root = document.documentElement;
  const fit = () => {
    const v = window.visualViewport;
    if (!v) return;
    const kb = Math.max(0, Math.round(window.innerHeight - v.height - v.offsetTop));
    root.style.setProperty('--ph-kb', kb + 'px');
    // (an iPhone Home Screen app shrinks the whole page for the keyboard, so this number can stay 0 there;
    //  the comment box uses the typing check below instead)
    root.style.setProperty('--ph-vh', Math.round(v.height) + 'px');
  };
  if (window.visualViewport) { visualViewport.addEventListener('resize', fit); visualViewport.addEventListener('scroll', fit); }
  fit();
  // typing on a phone means the on-screen keyboard is up: drop the home-bar spacing under the comment box then
  const typing = () => { const a = document.activeElement; root.classList.toggle('ph-typing', !!(Phone.on && a && a.closest && a.closest('#detail .tm-composer') && (a.isContentEditable || /^(INPUT|TEXTAREA)$/.test(a.tagName)))); };
  document.addEventListener('focusin', typing); document.addEventListener('focusout', () => setTimeout(typing, 50));
  // Same feel as the review / New task sheets: the sheet follows the finger from its first movement
  // (taking over before iPhone starts scrolling or bouncing the list), and springs or slides on release.
  let drag = null;
  const scroller = (el, menu) => { while (el && el !== menu.parentElement) { if (el.scrollHeight > el.clientHeight + 1 && /(auto|scroll)/.test(getComputedStyle(el).overflowY)) return el; el = el.parentElement; } return null; };
  const scrimEl = () => document.getElementById('ph-menu-scrim');
  document.addEventListener('touchstart', (e) => {
    drag = null;
    if (!Phone.on || e.touches.length !== 1) return;
    const m = e.target.closest && e.target.closest('body > .menu:not(.mention-pop)');
    if (!m) return;
    const y = e.touches[0].clientY, top = m.getBoundingClientRect().top;
    const handle = y - top <= 44 && !e.target.closest('input, textarea, [contenteditable="true"]');
    const sc = scroller(e.target, m);
    if (!handle && sc && sc.scrollTop > 0) return;          // a scrolled list scrolls; it never drags the sheet
    if (!handle && e.target.closest('input, textarea, [contenteditable="true"], .react-pick')) return;
    drag = { m, y0: y, t0: Date.now(), dy: 0, h: m.offsetHeight, handle, decided: handle, live: handle };
  }, { passive: true });
  document.addEventListener('touchmove', (e) => {
    if (!drag) return;
    const raw = e.touches[0].clientY - drag.y0;
    if (!drag.decided) {                                     // from the middle: a clear move down drags, up scrolls, a tap stays a tap
      if (Math.abs(raw) < 8) return;
      drag.decided = true;
      if (raw < 0) { drag = null; return; }
      drag.live = true; drag.y0 += 8;
    }
    if (!drag.live) return;
    e.preventDefault();
    if (!drag.started) {
      drag.started = true;
      drag.m.style.animation = 'none'; drag.m.style.transition = 'none';
      const s = scrimEl(); if (s) s.style.transition = 'none';
      const inp = drag.m.querySelector('input:focus'); if (inp) inp.blur();
    }
    drag.dy = Math.max(0, e.touches[0].clientY - drag.y0);
    drag.m.style.transform = `translate3d(0, ${drag.dy}px, 0)`;
    const s = scrimEl(); if (s) s.style.opacity = String(1 - Math.min(1, drag.dy / drag.h));
  }, { passive: false });
  const end = () => {
    if (!drag) return;
    const d = drag; drag = null;
    if (!d.started) return;                                  // a tap on the handle does nothing special
    const s = scrimEl();
    const fast = d.dy > 30 && d.dy / Math.max(1, Date.now() - d.t0) > 0.5;
    if (d.dy > Math.min(140, d.h * 0.3) || fast) {
      d.m.style.transition = 'transform .22s ease-in'; d.m.style.transform = 'translate3d(0, 100%, 0)';
      if (s) { s.style.transition = 'opacity .22s ease-in'; s.style.opacity = '0'; }
      setTimeout(() => { if (d.m.isConnected) closeMenus(); }, 200);
    } else {
      d.m.style.transition = 'transform .22s cubic-bezier(.2,.8,.2,1)'; d.m.style.transform = '';
      if (s) { s.style.transition = 'opacity .22s ease'; s.style.opacity = ''; }
    }
  };
  document.addEventListener('touchend', end, { passive: true });
  document.addEventListener('touchcancel', end, { passive: true });
})();

/* Phone: touch and hold a comment for one sheet with reactions, Reply, Edit comment, Copy text and
   Delete comment (instead of the small buttons on each comment). A short buzz confirms the hold:
   phones that support vibration vibrate; on iPhone (iOS 18 and later) a hidden switch gives a haptic tap. */
(() => {
  const HOLD = 450;
  let timer = null, el = null, x0 = 0, y0 = 0, swallow = 0, lifted = true, held = null;
  const buzz = () => {
    try { if (navigator.vibrate && navigator.vibrate(12)) return; } catch (e) { /* no vibration */ }
    try {
      const l = document.createElement('label');
      l.style.cssText = 'position:fixed;left:-200px;top:0;opacity:0;pointer-events:none';
      l.innerHTML = '<input type="checkbox" switch>';
      document.body.appendChild(l); l.click();
      setTimeout(() => l.remove(), 400);
    } catch (e) { /* no haptics */ }
  };
  const cancel = () => { clearTimeout(timer); timer = null; if (el) el.classList.remove('ph-pressing'); el = null; };
  function sheet(id) {
    const t = task(ui.taskId);
    const c = t && (t.comments || []).find((x) => x.id === id);
    if (!c) return;
    const mine = c.authorId === currentUserId || isAdm(me());
    const isReply = !!c.parentId;
    const on = c.reactions || {};
    const items = [{ html: `<div class="react-pick">${REACTIONS.map((e) => `<button data-swatch="${e}" class="${on[e] ? 'on' : ''}" aria-label="React ${e}">${e}</button>`).join('')}</div>` }];
    if (!isReply && ui.thread !== id) items.push({ label: 'Reply', icon: 'reply', run: () => { const b = document.querySelector(`.cm[data-comment="${id}"] [data-action="reply"]`); if (b) b.click(); } });
    if (mine) items.push({ label: 'Edit comment', icon: 'edit', run: () => { ui.editingComment = id; renderDetail(); setTimeout(() => { const e2 = document.getElementById('edit-comment'); if (e2) { e2.focus(); placeCaretAtEnd(e2); } }, 0); } });
    items.push({ label: 'Copy text', icon: 'copy', run: () => { try { navigator.clipboard.writeText(c.text || ''); toast('Copied'); } catch (e) { toast('Could not copy'); } } });
    if (mine) items.push('-', { label: 'Delete comment', icon: 'trash', danger: true, run: () => deleteComment(id) });
    const m = showMenu(document.body, items);
    m.classList.add('cm-sheet');
    m._onSwatch = (emoji) => toggleReaction(id, emoji);
  }
  document.addEventListener('touchstart', (e) => {
    if (!Phone.on || e.touches.length !== 1) return;
    const cm = e.target.closest && e.target.closest('.cm[data-comment]');
    if (!cm || e.target.closest('a, button, [contenteditable="true"], .c-files, .composer')) return;
    cancel();
    el = cm; x0 = e.touches[0].clientX; y0 = e.touches[0].clientY;
    cm.classList.add('ph-pressing');
    timer = setTimeout(() => {
      const id = cm.dataset.comment;
      cancel(); buzz();
      cm.classList.add('ph-held'); setTimeout(() => cm.classList.remove('ph-held'), 450);
      // the finger is still down where the sheet now appears: lifting it mustn't tap (or highlight) what's under it.
      // The sheet ignores touches until the finger is up, and taps are swallowed for a moment after.
      swallow = Infinity; lifted = false;
      sheet(id);
      const m = document.querySelector('.menu.cm-sheet');
      if (m) { m.style.pointerEvents = 'none'; held = m; }
    }, HOLD);
  }, { passive: true });
  document.addEventListener('touchmove', (e) => { if (timer && Math.hypot(e.touches[0].clientX - x0, e.touches[0].clientY - y0) > 10) cancel(); }, { passive: true });
  const lift = (e) => {
    if (swallow === Infinity && !lifted) {
      e.preventDefault(); lifted = true;
      swallow = Date.now() + 400;
      const m = held; held = null;
      setTimeout(() => { if (m) m.style.pointerEvents = ''; }, 350);
    }
    cancel();
  };
  document.addEventListener('touchend', lift, { passive: false });
  document.addEventListener('touchcancel', lift, { passive: false });
  document.addEventListener('click', (e) => { if (Date.now() < swallow) { e.preventDefault(); e.stopPropagation(); } }, true);
  document.addEventListener('contextmenu', (e) => { if (Phone.on && e.target.closest && e.target.closest('.cm[data-comment]')) e.preventDefault(); });
})();

/* Phone comment box: open while typing, or while it holds a draft, files or a reply; the handle tucks it away */
(() => {
  let raf = 0;
  const sync = () => {
    raf = 0;
    if (!Phone.on) return;
    document.querySelectorAll('#detail .tm-composer').forEach((c) => {
      const ed = c.querySelector('.rt-editor');
      const has = ed && (ed.textContent.trim() || ed.querySelector('img, .mention'));
      const busy = c.contains(document.activeElement) || has || c.querySelector('.cb-files, .cb-replying');
      c.classList.toggle('ph-open', !!busy && !c.classList.contains('ph-min'));
    });
  };
  const soon = () => { if (!raf) raf = requestAnimationFrame(sync); };
  document.addEventListener('focusin', (e) => { const c = e.target.closest && e.target.closest('#detail .tm-composer'); if (c) c.classList.remove('ph-min'); soon(); });
  document.addEventListener('focusout', () => setTimeout(soon, 150));
  document.addEventListener('input', (e) => { if (e.target.closest && e.target.closest('#detail .tm-composer')) soon(); });
  new MutationObserver(soon).observe(document.documentElement, { childList: true, subtree: true });
  // the handle: tap it or pull it down to tuck the box away (the draft is kept)
  let y0 = null, box = null;
  document.addEventListener('touchstart', (e) => {
    const c = e.target.closest && e.target.closest('#detail .tm-composer.ph-open');
    if (!c || e.touches[0].clientY - c.getBoundingClientRect().top > 26) return;
    y0 = e.touches[0].clientY; box = c;
  }, { passive: true });
  document.addEventListener('touchend', (e) => {
    if (box === null) return;
    const dy = (e.changedTouches[0] || {}).clientY - y0, c = box; box = null;
    if (dy > 24 || Math.abs(dy) < 6) {
      c.classList.add('ph-min');
      const ed = c.querySelector('.rt-editor'); if (ed) ed.blur();
      if (document.activeElement && c.contains(document.activeElement)) document.activeElement.blur();
      sync();
    }
  }, { passive: true });
})();

