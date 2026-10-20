/* E11 Console — phone layout.
   On small screens (iPhone, narrow windows) the sidebar is replaced by a bottom tab bar and the
   lists become simple cards. Everything else — data, sync, permissions, the task page logic —
   is shared with the desktop app in app.js. The Mac app always keeps the desktop layout. */
const Phone = (() => {
  const mq = window.matchMedia('(max-width: 760px)');
  const OWN = new Set(['home', 'today', 'mytasks', 'inbox', 'reviews', 'review', 'me', 'projects', 'project', 'psearch']);
  const TITLES = { profile: 'My profile', team: 'Team members', updates: 'App updates', clients: 'Client Assets', client: 'Client Assets' };
  const st = { on: false, ibf: 'unread', q: '' };

  const isOn = () => st.on;
  function check() {
    const v = mq.matches && !(typeof Host !== 'undefined' && Host.isMacApp);
    if (v === st.on) return;
    st.on = v;
    document.body.classList.toggle('phone', v);
    document.documentElement.classList.toggle('phone', v);
    if (typeof db !== 'undefined' && db && currentUserId) render();
  }
  mq.addEventListener ? mq.addEventListener('change', check) : mq.addListener(check);

  // iPhone Home Screen apps can report a page shorter than the screen, which leaves a gap under
  // everything pinned to the bottom. Measure the real height and pin to the true bottom edge.
  function measure() {
    const root = document.documentElement;
    const standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
    let h = window.innerHeight;
    if (standalone) {
      const full = window.innerHeight > window.innerWidth ? Math.max(screen.height, screen.width) : Math.min(screen.height, screen.width);
      if (full > h && full - h < 140) h = full; // not when the keyboard is open (that shrinks it a lot more)
    }
    root.style.setProperty('--app-h', h + 'px');
    root.style.setProperty('--ph-shift', (window.innerHeight - h) + 'px');
  }
  measure();
  window.addEventListener('resize', measure);
  window.addEventListener('orientationchange', () => setTimeout(measure, 300));

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
    bar.innerHTML = tab('today', 'sun', 'My Day')
      + tab('mytasks', 'check-circle', 'My Tasks')
      + tab('inbox', 'inbox', 'Inbox', unread)
      + (cd ? tab('reviews', 'shield', 'Reviews', rv) : tab('projects', 'folder', 'Projects'))
      + tab('me', 'user', 'Me');
    bar.hidden = !!ui.taskId;
    document.body.classList.toggle('task-open', !!ui.taskId);
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
      <span class="pc-body"><span class="pc-title">${t.title ? esc(t.title) : '<i>Untitled task</i>'}</span>
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
    const open = db.tasks.filter((t) => onMyList(t) && myOpen(t));
    const sortP = (a, b) => byPrio(a, b) || (a.due || '').localeCompare(b.due || '') || a.createdAt.localeCompare(b.createdAt);
    const overdue = open.filter((t) => t.due && t.due < today).sort(sortP);
    const due = open.filter((t) => t.due === today).sort(sortP);
    const going = open.filter((t) => t.start && t.start <= today && t.due && t.due > today).sort(sortP);
    const done = db.tasks.filter((t) => isMine(t) && myDoneAt(t) && ymd(new Date(myDoneAt(t))) === today);
    const review = open.filter((t) => t.cdStatus === 'review').length;
    const d = new Date();
    return `<div class="ph-page">
      ${head('My Day', esc(d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })),
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
    const open = myTop().filter(myOpen);
    let body;
    if (tab === 'done') {
      const cutoff = Date.now() - AUTO_DELETE_DAYS * 86400000;
      const list = myTop().filter((t) => myDoneAt(t) && new Date(myDoneAt(t)).getTime() > cutoff).sort((a, b) => myDoneAt(b).localeCompare(myDoneAt(a)));
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
    list.forEach((n) => { const k = n.taskId || n.id; if (!byTask.has(k)) byTask.set(k, []); byTask.get(k).push(n); });
    const rows = [...byTask.values()].slice(0, 200).map((items) => {
      const n = items[0];
      const t = task(n.taskId);
      const unread = items.some((x) => !x.read);
      const target = items.find((x) => /^review/.test(x.kind) && !x.read) || items.find((x) => x.kind === 'mention') || n;
      return `<div class="ph-ib ${unread ? 'unread' : ''}" data-action="open-notif" data-id="${target.id}">
        ${avatarHTML(target.from, 40)}
        <span class="ph-ib-b"><span class="ph-ib-m">${notifMsg(target, t)}</span>
          <span class="ph-ib-t">${t ? esc(t.title || 'Untitled task') : '<i>Deleted task</i>'}</span>
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
        return `<div class="pc rv" data-ph="open-review" data-id="${r.id}">
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
    if (k === 'image') m = `<img src="${url}" alt="" loading="lazy">`;
    else if (k === 'video') m = `<video src="${url}" controls playsinline preload="metadata"></video>`;
    else m = `${a.thumb ? `<img src="${'/__file/' + a.thumb.split('/').map(encodeURIComponent).join('/')}" alt="">` : `<span class="ph-ext">${esc((fileExt(a.name) || 'file').slice(0, 5))}</span>`}`;
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
    const list = db.projects.slice().sort(byOrder);
    return `<div class="ph-page">
      ${head('Projects', plural(list.length, 'project'))}
      <div class="ph-list">${list.map((p) => {
        const open = db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done).length;
        return `<div class="pc pj" data-ph="open-project" data-id="${p.id}"><span class="ph-pj-ic" style="background:${p.color}">${esc(initials(p.name))}</span>
          <span class="pc-body"><span class="pc-title">${esc(p.name)}</span><span class="pc-meta">${plural(open, 'open task')}</span></span>${icon('chev-right')}</div>`;
      }).join('') || '<div class="ph-empty big">No projects yet</div>'}</div>
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
    const admin = u.role === 'admin';
    const row = (attrs, ic, label, sub = '') => `<button class="ph-row" ${attrs}>${icon(ic)}<span>${label}${sub ? `<small>${sub}</small>` : ''}</span>${icon('chev-right')}</button>`;
    const light = document.documentElement.dataset.theme === 'light';
    return `<div class="ph-page">
      <div class="ph-me-card">${avatarHTML(u.id, 64)}<div><b>${esc(fullName(u))}</b><span>${esc(designationOf(u))}</span><small>${esc(u.email)}</small></div></div>
      <div class="ph-rows">
        ${row('data-nav="profile"', 'user', 'My profile', 'Photo, office and notifications')}
        ${isCD() ? row('data-ph-tab="projects"', 'folder', 'Projects') : ''}
        ${row('data-nav="clients"', 'assets', 'Client Assets', 'Logos, guidelines and fonts')}
        ${row('data-nav="team"', 'users', 'Team members')}
        ${admin && Host.isServer ? row('data-nav="updates"', 'download', 'App updates') : ''}
      </div>
      <div class="ph-rows">
        ${typeof Push !== 'undefined' ? Push.row() : ''}
        <button class="ph-row" data-action="toggle-theme">${icon(light ? 'moon' : 'sun')}<span>${light ? 'Dark mode' : 'Light mode'}</span></button>
        ${Host.isServer ? '<button class="ph-row" data-action="whats-new">' + icon('info') + '<span>What’s new</span>' + icon('chev-right') + '</button>' : ''}
      </div>
      <div class="ph-rows"><button class="ph-row danger" data-ph="sign-out">${icon('logout')}<span>Sign out</span></button></div>
    </div>`;
  }

  function search() {
    return `<div class="ph-page">
      ${backHead('Search', 'data-ph-tab="today"')}
      <div class="ph-search">${icon('search')}<input id="ph-q" type="search" placeholder="Search tasks" value="${esc(st.q)}" autocomplete="off"></div>
      <div class="ph-list" id="ph-results">${results()}</div>
    </div>`;
  }
  function results() {
    const q = st.q.trim().toLowerCase();
    if (!q) return '<div class="ph-empty">Type a task name, project or tag</div>';
    const hits = db.tasks.filter((t) => {
      const p = proj(t.projectId);
      return (t.title || '').toLowerCase().includes(q) || (p && p.name.toLowerCase().includes(q)) || t.tags.some((g) => g.toLowerCase().includes(q));
    }).sort((a, b) => (a.done ? 1 : 0) - (b.done ? 1 : 0) || b.updatedAt.localeCompare(a.updatedAt)).slice(0, 60);
    return hits.map((t) => card(t)).join('') || '<div class="ph-empty">No tasks found</div>';
  }

  /* ---------- Hooks called from app.js ---------- */
  function renderContent(c) {
    if (!st.on || ui.search || !OWN.has(ui.view)) return false;
    const v = ui.view;
    c.innerHTML = v === 'home' || v === 'today' ? myDay() : v === 'mytasks' ? myTasks() : v === 'inbox' ? inbox()
      : v === 'reviews' ? reviews() : v === 'review' ? review() : v === 'projects' ? projects() : v === 'project' ? project()
      : v === 'psearch' ? search() : meScreen();
    if (ui.view === 'review') wireSlides(c);
    return true;
  }
  // Pages shared with the desktop (profile, team, Client Assets…) get a phone header with a back button
  function decorate(c) {
    if (!st.on || OWN.has(ui.view)) return;
    let title = TITLES[ui.view] || 'E11 Console', back = 'data-ph-tab="me"';
    if (ui.view === 'client') {
      const cl = clientById(ui.clientId);
      const f = cl && cl.folders.find((x) => x.id === ui.folderId);
      title = esc(f ? f.name : cl ? cl.name : 'Client Assets');
      back = f ? `data-action="open-client" data-id="${cl.id}"` : 'data-nav="clients"';
    }
    if (ui.search) { title = 'Search'; back = 'data-ph-tab="today"'; }
    c.insertAdjacentHTML('afterbegin', backHead(title, back));
    c.firstElementChild.classList.add('ph-sticky');
  }
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

  /* ---------- Sheets ---------- */
  function sheet(html, onWire) {
    const root = $('#overlay-root');
    root.innerHTML = `<div class="ph-scrim"><div class="ph-sheet" role="dialog"><i class="ph-grab"></i>${html}</div></div>`;
    const scrim = root.firstElementChild;
    const close = () => { if (root.firstElementChild === scrim) root.innerHTML = ''; };
    scrim.addEventListener('click', (e) => { if (e.target === scrim || e.target.closest('[data-sheet-close]')) close(); });
    requestAnimationFrame(() => scrim.classList.add('in'));
    onWire && onWire(scrim, close);
  }

  function quickAdd() {
    if (!can('createTask')) return denied();
    const inProject = ui.view === 'project' && proj(ui.projectId) ? ui.projectId : '';
    const mgr = me().role === 'admin' || me().role === 'am';
    const people = activeUsers();
    const projOpts = `<option value="">No project (My Tasks)</option>` + db.projects.slice().sort(byOrder).map((p) => `<option value="${p.id}" ${p.id === inProject ? 'selected' : ''}>${esc(p.name)}</option>`).join('');
    const userOpts = `<option value="${currentUserId}">Me</option>` + people.filter((u) => u.id !== currentUserId).map((u) => `<option value="${u.id}">${esc(fullName(u))}</option>`).join('') + '<option value="">Nobody yet</option>';
    sheet(`<div class="ph-sh-head"><h2>New task</h2><button class="ph-link" data-sheet-close>Cancel</button></div>
      <label class="ph-field"><span>Task name</span><input id="qa-title" placeholder="What needs doing?" autocomplete="off" enterkeyhint="done"></label>
      <div class="ph-form">
        <label><span>Project</span><select id="qa-proj">${projOpts}</select></label>
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
        const who = $('#qa-who', scrim) ? $('#qa-who', scrim).value : currentUserId;
        const t = createTask({ title, projectId: pj.value || null, due: $('#qa-due', scrim).value || null });
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
      ti.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); go(); } });
    });
  }

  function amendSheet(id) {
    const f = findReview(id);
    if (!f || !isCD()) return;
    sheet(`<div class="ph-sh-head"><h2>Request amendments</h2><button class="ph-link" data-sheet-close>Cancel</button></div>
      <p class="ph-sh-p">Tell ${esc(firstName(f.r.by))} what to change. It's posted as a comment on the task.</p>
      <textarea id="am-note" rows="5" placeholder="e.g. Use the new logo lockup and make the date bigger"></textarea>
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
    });
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
      ...(t.projectId ? [{ label: 'Open project', icon: 'folder', run: () => { closeDetail(); go('project', t.projectId); } }] : []),
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
      case 'ibf': st.ibf = el.dataset.k; renderContent(); break;
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
  return { get on() { return st.on; }, isOn, renderContent, decorate, chrome, taskHead, quickAdd, check };
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
  }
  function row(noRefresh) {
    if (!noRefresh) setTimeout(refresh, 0);
    if (st.state === 'none') return '';
    const label = { on: 'On', off: 'Off', denied: 'Blocked', install: 'Set up', unsupported: 'Not available', unknown: '' }[st.state];
    const sub = { on: 'Banners for mentions, reviews and assignments', off: 'Get a banner even when the app is closed', denied: 'Allow them in iPhone Settings → Notifications → E11 Console', install: 'Add E11 Console to your Home Screen first', unsupported: 'This browser can’t show notifications', unknown: '' }[st.state];
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
      toast('Notifications are on for this phone');
    } catch (e) { toast('Couldn’t turn on notifications: ' + e.message); } finally { st.busy = false; paint(); }
  }
  async function turnOff() {
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (sub) { await api('POST', '/api/push/unsubscribe', { endpoint: sub.endpoint }).catch(() => {}); await sub.unsubscribe(); }
      st.state = 'off'; paint();
      toast('Notifications are off for this phone');
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
  function openFrom(taskId, nid) {
    const go = () => {
      ui.sideTab = 'details';
      if (nid && db.notifications.some((n) => n.id === nid)) { openNotif(nid); return; }
      if (taskId && task(taskId)) openTask(taskId);
    };
    if (typeof db !== 'undefined' && db && currentUserId) return go();
    const iv = setInterval(() => { if (typeof db !== 'undefined' && db && currentUserId) { clearInterval(iv); setTimeout(go, 300); } }, 250);
    setTimeout(() => clearInterval(iv), 30000);
  }
  const q = new URLSearchParams(location.search);
  if (q.get('task')) { openFrom(q.get('task'), q.get('n')); history.replaceState(null, '', '/'); }
  if ('serviceWorker' in navigator) navigator.serviceWorker.addEventListener('message', (e) => { if (e.data && e.data.type === 'open-task') openFrom(e.data.taskId, e.data.nid); });

  return { row, refresh };
})();
