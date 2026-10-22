/* ================= Home page =================
   Account Managers and Admins: the tasks they created and how their team is doing (layout A).
   Production, Social and everyone else: what to work on next, their pipeline and week (layout C).
   Everything comes from task data the app already keeps. The phone has its own Home. */
const Home = (() => {
  const st = { range: 'week', metric: 'done', day: null, next: 0, lane: null };
  const DAY = 86400000;
  const WD = ['Mo', 'Tu', 'We', 'Th', 'Fr'];
  const first = (u) => fullName(u).split(' ')[0];
  const greeting = () => { const h = new Date().getHours(); return h < 5 ? 'Good evening' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening'; };
  const dateLine = () => new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
  const ymdOf = (iso) => (iso ? ymd(new Date(iso)) : null);
  const pColor = (t) => (proj(t.projectId) || {}).color || 'var(--text-3)';
  const pName = (t) => (proj(t.projectId) || {}).name || 'No project';
  const title = (t) => (t.title ? esc(t.title) : '<span class="ph">Untitled task</span>');
  const nComments = (t) => (t.comments || []).length;
  const nFiles = (t) => shownAtts(t).length;
  const svg = (d, w = 1.5) => `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${d}"/></svg>`;
  const IC = {
    clock: 'M8 2.2a5.8 5.8 0 1 0 0 11.6A5.8 5.8 0 0 0 8 2.2zM8 4.8V8l2.2 1.4',
    check: 'M8 2.2a5.8 5.8 0 1 0 0 11.6A5.8 5.8 0 0 0 8 2.2zM5.6 8.1l1.7 1.7 3.2-3.4',
    shield: 'M8 1.8 13 4v4c0 3-2.2 5.2-5 6.2C5.2 13.2 3 11 3 8V4z',
    chat: 'M3.2 2.9h9.6c.6 0 1 .4 1 1v6.6c0 .6-.4 1-1 1H7.4l-3 2.4v-2.4H3.2c-.6 0-1-.4-1-1V3.9c0-.6.4-1 1-1z',
    clip: 'M10.5 4.5 5.6 9.4a1.4 1.4 0 0 0 2 2l5-5a2.8 2.8 0 0 0-4-4l-5 5a4.2 4.2 0 0 0 6 6l4.4-4.4',
    flag: 'M3.5 13.5V3h7l-1.5 2.5 1.5 2.5h-7',
    tick: 'm3.5 8.4 3 3 6-6.6',
  };
  const tick = `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.6" aria-hidden="true"><path d="${IC.tick}"/></svg>`;
  const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);
  const delta = (now, before) => {
    if (!before) return now ? { t: 'New', up: true } : null;
    const d = Math.round(((now - before) / before) * 100);
    return { t: `${d >= 0 ? '+' : ''}${d}%`, up: d >= 0 };
  };
  const chip = (d, goodUp = true) => (d ? `<span class="hm-delta ${d.up === goodUp ? 'good' : 'bad'}">${d.t}</span>` : '');
  const onTime = (t, doneAt) => !t.due || ymdOf(doneAt) <= t.due;

  // ---- this week (Monday to Friday) ----
  function week() {
    const now = new Date();
    const wd = (now.getDay() + 6) % 7; // 0 = Monday
    const mon = addDays(todayStr(), wd > 4 ? 7 - wd : -wd); // at the weekend, show next week
    return WD.map((w, i) => ({ w, d: addDays(mon, i) }));
  }
  function pickedDay(days) {
    if (st.day && days.some((x) => x.d === st.day)) return st.day;
    const t = todayStr();
    return days.some((x) => x.d === t) ? t : days[0].d;
  }
  const dayStrip = (days, sel, dot) => `<div class="hm-days">${days.map((x) => `<button type="button" class="hm-day ${x.d === sel ? 'on' : ''} ${x.d === todayStr() ? 'today' : ''}" data-hm="day" data-v="${x.d}">${x.w}<b>${parseYmd(x.d).getDate()}</b>${dot && dot(x.d) ? '<i class="hm-dot"></i>' : ''}</button>`).join('')}</div>`;

  // ---- activity ----
  function actRow(a) {
    const t = task(a.taskId);
    return `<div class="hm-act" ${t ? `data-task="${t.id}"` : ''}>${avatarHTML(a.from, 32)}
      <span class="hm-act-txt"><b>${esc(fullName(userById(a.from)))}</b> <span class="hm-mute">${a.html}</span> ${t ? `<span class="hm-link">${title(t)}</span>` : ''}
        ${a.quote ? `<span class="hm-quote">“${esc(a.quote)}”</span>` : ''}
        ${a.file ? `<span class="hm-file">${svg('M4 1.8h5l3 3v9.4H4z', 1.4)}<span><b>${esc(a.file.name)}</b><small>${fmtSize(a.file.size)}</small></span></span>` : ''}</span>
      <span class="hm-when">${esc(timeAgo(a.at))}</span></div>`;
  }
  const actCard = (list, empty, extra = '') => `<section class="hm-card hm-acts ${extra}">
      <div class="hm-h"><h2>Recent activity</h2><a class="hm-a" data-nav="inbox">Open Inbox</a></div>
      ${list.length ? list.map(actRow).join('') : `<div class="hm-empty">${empty}</div>`}
    </section>`;

  /* ================= A · Account Manager / Admin ================= */
  function viewLead() {
    // An Admin sees every Account Manager's and Admin's created tasks (same as E11 Day); an AM sees their own
    const admin = isAdmin();
    const who = new Set(admin ? db.users.filter((x) => x.role === 'am' || isAdm(x)).map((x) => x.id) : [currentUserId]);
    const mine = topTasks().filter((t) => who.has(t.createdBy));
    const open = mine.filter((t) => !t.done);
    const today = todayStr();
    const due0 = open.filter((t) => t.due === today);
    const overdue = open.filter((t) => t.due && t.due < today);
    const weekAgo = Date.now() - 7 * DAY, twoWeeks = Date.now() - 14 * DAY;
    const doneIn = (a, b) => mine.filter((t) => t.done && t.completedAt && +new Date(t.completedAt) > a && +new Date(t.completedAt) <= b).length;
    const doneWeek = doneIn(weekAgo, Date.now()), donePrev = doneIn(twoWeeks, weekAgo);
    const inReview = open.filter(reviewPending);
    const since = inReview.length ? inReview.map((t) => (t.reviews || []).filter((r) => r.state === 'pending').map((r) => r.at).sort()[0]).sort()[0] : null;

    // created tasks list
    const wkEnd = addDays(today, 7);
    const inRange = (t) => (st.range === 'today' ? t.due && t.due <= today : st.range === 'week' ? t.due && t.due <= wkEnd : true);
    const rows = open.filter(inRange).sort((a, b) => (a.due || '9999').localeCompare(b.due || '9999') || byPrio(a, b)).slice(0, 6);
    const rangeTabs = [['today', 'Today'], ['week', 'This week'], ['all', 'All open']].map(([k, l]) => `<button type="button" class="hm-tab ${st.range === k ? 'on' : ''}" data-hm="range" data-v="${k}">${l}</button>`).join('');

    // this month chart
    const now = new Date(), y = now.getFullYear(), m = now.getMonth();
    const nDays = new Date(y, m + 1, 0).getDate(), todayN = now.getDate();
    const inMonth = (iso, yy = y, mm = m) => { if (!iso) return false; const d = new Date(iso); return d.getFullYear() === yy && d.getMonth() === mm; };
    const ly = m ? y : y - 1, lm = m ? m - 1 : 11;
    const doneM = mine.filter((t) => t.done && inMonth(t.completedAt)), doneL = mine.filter((t) => t.done && inMonth(t.completedAt, ly, lm));
    const onT = pct(doneM.filter((t) => onTime(t, t.completedAt)).length, doneM.length);
    const onTL = pct(doneL.filter((t) => onTime(t, t.completedAt)).length, doneL.length);
    const reviewsOn = mine.flatMap((t) => (t.reviews || []).filter((r) => r.state !== 'withdrawn'));
    const M = {
      done: { l: 'Completed by the team', big: 'tasks completed', at: doneM.map((t) => t.completedAt) },
      created: { l: 'Tasks created', big: 'tasks created', at: mine.filter((t) => inMonth(t.createdAt)).map((t) => t.createdAt) },
      reviews: { l: 'Sent for CD review', big: 'sent for CD review', at: reviewsOn.filter((r) => inMonth(r.at)).map((r) => r.at) },
    };
    const cur = M[st.metric] || M.done;
    const vals = Array.from({ length: nDays }, () => 0);
    cur.at.forEach((iso) => { vals[new Date(iso).getDate() - 1]++; });
    const max = Math.max(1, ...vals);
    const X = (i) => ((i + 0.5) / nDays) * 100, Y = (v) => 100 - (v / max) * 88;
    const avg = vals.slice(0, todayN).map((_, i) => { const w = vals.slice(Math.max(0, i - 2), Math.min(todayN, i + 3)); return w.reduce((a, b) => a + b, 0) / w.length; });
    let line = avg.length ? `M${X(0)},${Y(avg[0])}` : '';
    for (let i = 1; i < avg.length; i++) { const mx = (X(i - 1) + X(i)) / 2; line += ` C${mx},${Y(avg[i - 1])} ${mx},${Y(avg[i])} ${X(i)},${Y(avg[i])}`; }
    const past = vals.slice(0, todayN), pk = past.indexOf(Math.max(...past));
    const mName = now.toLocaleDateString('en-US', { month: 'short' });
    const bars = vals.map((v, i) => `<div class="hm-bar ${i < todayN ? '' : 'future'}" style="height:${Math.max(3, (v / max) * 100)}%"><span class="hm-tip">${mName} ${i + 1} · ${v} ${esc(cur.l.toLowerCase())}</span></div>`).join('');
    const ticks = [1, 8, 15, 22, nDays].map((d) => `<span>${mName} ${d}</span>`).join('');
    const metricTabs = Object.entries(M).map(([k, v]) => `<button type="button" class="hm-tab ${st.metric === k ? 'on' : ''}" data-hm="metric" data-v="${k}">${v.l}</button>`).join('');

    // activity on tasks I created, by other people
    const acts = mine.flatMap((t) => (t.activity || []).filter((a) => a.actor && a.actor !== currentUserId).map((a) => ({ from: a.actor, html: a.text, taskId: t.id, at: a.at })))
      .concat(mine.flatMap((t) => (t.comments || []).filter((c) => c.authorId !== currentUserId).map((c) => ({ from: c.authorId, html: 'commented on', quote: c.text, taskId: t.id, at: c.at }))))
      .sort((a, b) => String(b.at).localeCompare(String(a.at))).slice(0, 7);

    // schedule
    const days = week(), sel = pickedDay(days);
    const agenda = mine.filter((t) => t.due === sel).sort((a, b) => Number(a.done) - Number(b.done) || byPrio(a, b));
    const lateOn = (d) => d < today && mine.some((t) => !t.done && t.due === d);

    // checklist items still to do on tasks I created
    const items = open.flatMap((t) => (t.checklist || []).map((c) => ({ t, c }))).sort((a, b) => Number(a.c.done) - Number(b.c.done)).slice(0, 5);
    const itemsDone = items.filter((x) => x.c.done).length;

    // projects: an AM sees the projects their tasks are in, an Admin sees them all
    const pSet = admin ? null : new Set(mine.map((t) => t.projectId));
    const projects = db.projects.slice().sort(byOrder).filter((p) => !pSet || pSet.has(p.id)).map((p) => {
      const ts = topTasks().filter((t) => t.projectId === p.id);
      const d = ts.filter((t) => t.done).length;
      return { p, open: ts.length - d, pc: pct(d, ts.length) };
    });
    const projCard = `<section class="hm-card">
        <div class="hm-h"><h2>${admin ? 'Projects' : 'My projects'}</h2><span class="hm-mute">${projects.length}</span></div>
        ${projects.length ? `<div class="hm-projs">${projects.map(({ p, open: o, pc }) => `<div class="hm-proj" data-project="${p.id}"><span class="hm-pi" style="background:${p.color}">${esc(initials(p.name))}</span><span class="hm-main"><b>${esc(p.name)}</b><span class="hm-sub">${o} open · ${pc}% done</span><span class="hm-pbar"><i style="width:${pc}%;background:${p.color}"></i></span></span></div>`).join('')}</div>` : '<div class="hm-empty">Projects with your tasks show up here.</div>'}
      </section>`;

    // team on time this month
    const team = [...new Set(doneM.flatMap((t) => t.assignees || []))].filter((u) => userById(u));

    const statCard = (cls, ic, l, n, note, noteCls, nav = 'mytasks') => `<button type="button" class="hm-stat" data-hm="all" data-nav-x="${nav}"><span class="hm-ic ${cls}">${svg(ic, 1.5)}</span><span><span class="hm-sl">${l}</span><span class="hm-sn"><b>${n}</b><span class="${noteCls}">${note}</span></span></span></button>`;

    return `<div class="hm hm-lead">
      <header class="hm-head"><div><div class="hm-date">${dateLine()}</div><h1>${greeting()}, ${esc(first(me()))}</h1></div>
        <div class="hm-btns"><button type="button" class="hm-btn" data-nav="today">${esc(Work.dayTitle())}</button><button type="button" class="hm-btn primary" data-action="new-task">+ New task</button></div></header>
      <section class="hm-stats">
        ${statCard('blue', IC.clock, admin ? 'Team tasks due today' : 'Your tasks due today', due0.length, overdue.length ? `${overdue.length} overdue` : 'none overdue', overdue.length ? 'warn' : 'ok')}
        ${statCard('green', IC.check, 'Finished by your team', doneWeek, doneWeek - donePrev >= 0 ? `↑ ${doneWeek - donePrev} vs last week` : `↓ ${donePrev - doneWeek} vs last week`, doneWeek >= donePrev ? 'ok' : 'warn')}
        ${statCard('orange', IC.shield, 'Waiting for CD review', inReview.length, since ? `oldest ${timeAgo(since)}` : 'nothing waiting', 'orange')}
      </section>
      <div class="hm-grid">
        <div class="hm-col">
          <section class="hm-card">
            <div class="hm-h"><div class="hm-hl"><h2>${admin ? 'Team’s created tasks' : 'Your created tasks'}</h2><span class="hm-seg">${rangeTabs}</span></div><a class="hm-a" data-action="home-view-all">See all</a></div>
            ${rows.length ? rows.map((t) => `<div class="hm-row" data-task="${t.id}">
                <i class="hm-pc" style="background:${pColor(t)}"></i>
                <span class="hm-main"><span class="hm-t">${title(t)}</span><span class="hm-sub">${esc(pName(t))}${admin && t.createdBy !== currentUserId && userById(t.createdBy) ? ` · by ${esc(fullName(userById(t.createdBy)))}` : ''}${t.due ? ` · due <span class="due ${dueClass(t)}">${esc(fmtDue(t.due))}</span>` : ''}</span></span>
                <span class="hm-counts"><span title="Comments">${svg(IC.chat, 1.4)}${nComments(t)}</span><span title="Files">${svg(IC.clip, 1.4)}${nFiles(t)}</span></span>
                <span class="hm-who">${(t.assignees || []).length ? avatarStack(t.assignees, 26, 3, t) : '<span class="hm-mute">Unassigned</span>'}</span>
                <span class="hm-st">${statusPill(t)}</span>
              </div>`).join('') : `<div class="hm-empty">${st.range === 'all' ? (admin ? 'Tasks your team creates will show up here.' : 'Tasks you create will show up here.') : 'Nothing due ' + (st.range === 'today' ? 'today' : 'this week') + (admin ? ' on the team’s tasks.' : ' on the tasks you created.')}</div>`}
          </section>
          <section class="hm-card">
            <div class="hm-kpis">
              <div class="hm-kpi-row">
                <div><div class="hm-sl">Completed</div><div class="hm-kv"><b>${doneM.length}</b>${chip(delta(doneM.length, doneL.length))}</div></div>
                <div><div class="hm-sl">On time</div><div class="hm-kv"><b>${doneM.length ? onT + '%' : '–'}</b>${doneM.length && doneL.length ? chip(delta(onT, onTL)) : ''}</div></div>
                <div><div class="hm-sl">Overdue</div><div class="hm-kv"><b>${overdue.length}</b></div></div>
              </div>
              <div class="hm-big"><b>${cur.at.length}</b><span>${esc(cur.big)} · ${now.toLocaleDateString('en-US', { month: 'long' })}</span></div>
            </div>
            <div class="hm-tabs">${metricTabs}</div>
            <div class="hm-chart">
              <div class="hm-bars">${bars}</div>
              <svg viewBox="0 0 100 100" preserveAspectRatio="none" class="hm-line" aria-hidden="true"><path d="${line}" vector-effect="non-scaling-stroke"/></svg>
              ${past[pk] ? `<div class="hm-peak" style="left:${X(pk)}%;top:${44 + Y(past[pk]) * 1.48}px"><span>${svg(IC.flag, 1.6)}</span><em>Busiest day</em></div>` : ''}
              <div class="hm-ticks">${ticks}</div>
            </div>
          </section>
          ${actCard(acts, admin ? 'When people work on the team’s tasks, it shows up here.' : 'When your team works on the tasks you created, it shows up here.', 'grow')}
        </div>
        <aside class="hm-col">
          <section class="hm-card">
            <div class="hm-h"><h2>Schedule</h2><span class="hm-mute">${sel === today ? 'Today' : parseYmd(sel).toLocaleDateString('en-US', { weekday: 'long' })}</span></div>
            ${dayStrip(days, sel, lateOn)}
            <div class="hm-agenda">${agenda.length ? agenda.slice(0, 5).map((t) => `<div class="hm-ag ${t.done ? 'done' : ''}" data-task="${t.id}"><i style="background:${pColor(t)}"></i><span class="hm-main"><b>${title(t)}</b><span class="hm-sub">${t.done ? 'Done' : statusInfo(t).name}${t.update ? ' · ' + esc(t.update) : ''}</span></span>${avatarStack(t.assignees || [], 22, 2, t)}</div>`).join('') : '<div class="hm-empty">Nothing due this day</div>'}${agenda.length > 5 ? `<div class="hm-mute">+${agenda.length - 5} more due this day</div>` : ''}</div>
          </section>
          ${projCard}
          <section class="hm-card">
            <div class="hm-h"><h2>Checklist</h2><span class="hm-mute">${items.length ? `${itemsDone} of ${items.length} done` : ''}</span></div>
            ${items.length ? items.map(({ t, c }) => `<div class="hm-cl"><button type="button" class="hm-chk ${c.done ? 'on' : ''}" data-hm="cl" data-task-id="${t.id}" data-v="${c.id}" aria-label="Done">${tick}</button><span class="hm-main" data-task="${t.id}"><b class="${c.done ? 'struck' : ''}">${esc(c.text)}</b><span class="hm-sub">${title(t)}</span></span></div>`).join('') : `<div class="hm-empty">Checklist items on ${admin ? 'the team’s tasks' : 'the tasks you created'} show up here.</div>`}
          </section>
          <section class="hm-hero">
            <h2>Team on time</h2>
            <div class="hm-hn"><b>${doneM.length ? onT + '%' : '–'}</b><span>${doneM.length && doneL.length ? `${onT - onTL >= 0 ? '+' : ''}${onT - onTL}% vs<br>${new Date(ly, lm, 1).toLocaleDateString('en-US', { month: 'long' })}` : 'this month'}</span></div>
            ${team.length ? `<div class="hm-avs">${avatarStack(team, 32, 5)}</div>` : ''}
            <p>${admin ? 'Team tasks' : 'Tasks you created'} that were finished by their due date this month</p>
          </section>
        </aside>
      </div>
    </div>`;
  }

  /* ================= C · Production / Social ================= */
  function viewMember() {
    const u = me();
    const today = todayStr();
    const mineAll = topTasks().filter(isMine);
    const open = myTop().filter(myOpen).sort((a, b) => (a.due || '9999').localeCompare(b.due || '9999') || byPrio(a, b));

    // Up next
    const h = open.length ? open[st.next % open.length] : null;
    let hero = `<section class="hm-next empty"><div><span class="hm-pill acc">All caught up</span><h2>Nothing open on your list</h2><div class="hm-nsub">New tasks assigned to you will show up here.</div></div></section>`;
    if (h) {
      const pr = prioOf(h), rs = reviewState(h);
      const main = iReview(h) ? (rs === 'pending' ? '<button type="button" class="hm-btn primary" disabled>With the CD for review</button>' : `<button type="button" class="hm-btn primary" data-hm="submit" data-v="${h.id}">${rs === 'amend' ? 'Submit amended files' : 'Submit files for review'}</button>`)
        : `<button type="button" class="hm-btn primary" data-hm="part" data-v="${h.id}">Mark my part done</button>`;
      const cl = h.checklist || [];
      const cd = cl.filter((c) => c.done).length;
      hero = `<section class="hm-next">
        <div class="hm-nl">
          <div class="hm-chips"><span class="hm-pill acc">Up next</span>${pr !== 'none' ? `<span class="hm-pill ${pr === 'urgent' ? 'red' : ''}">${esc(prioLabel(pr))}</span>` : ''}${h.due ? `<span class="hm-pill amber">${h.due < today ? 'Overdue · ' : 'Due '}${esc(fmtDue(h.due))}</span>` : ''}${h.update ? `<span class="hm-pill" style="color:${UPDATE_COLOR(h.update)}">${esc(h.update)}</span>` : ''}<span class="hm-pill">${esc(statusInfo(h).name)}</span></div>
          <h2>${title(h)}</h2>
          <div class="hm-nsub">${esc(pName(h))}${h.createdBy && userById(h.createdBy) ? ` · Created by ${esc(fullName(userById(h.createdBy)))}` : ''} · ${nFiles(h)} files · ${nComments(h)} comments${needsCD(h) ? ' · needs CD review' : ''}</div>
          <div class="hm-nbtns">${main}<button type="button" class="hm-btn ghost" data-hm="open" data-v="${h.id}">Open task</button>${open.length > 1 ? `<button type="button" class="hm-btn text" data-hm="next">Next task → <small>${(st.next % open.length) + 1} of ${open.length}</small></button>` : ''}</div>
        </div>
        <div class="hm-ncl">
          <div class="hm-ncl-h"><span>Checklist</span><span class="mono">${cd}/${cl.length}</span></div>
          <div class="hm-prog"><i style="width:${pct(cd, cl.length)}%"></i></div>
          ${cl.length ? cl.slice(0, 5).map((c) => `<button type="button" class="hm-sub-i ${c.done ? 'on' : ''}" data-hm="cl" data-task-id="${h.id}" data-v="${c.id}"><span class="hm-box">${tick}</span><span>${esc(c.text)}</span></button>`).join('') + (cl.length > 5 ? `<div class="hm-ncl-more">+${cl.length - 5} more in the task</div>` : '') : '<div class="hm-ncl-more">No checklist on this task</div>'}
        </div>
      </section>`;
    }

    // Pipeline: my open tasks by Task Update, most used first
    const groups = new Map();
    open.forEach((t) => { const k = t.update || ''; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(t); });
    const lanes = [...groups.entries()].sort((a, b) => (a[0] === '') - (b[0] === '') || b[1].length - a[1].length).slice(0, 5);
    const laneK = lanes.some(([k]) => k === st.lane) ? st.lane : lanes.length ? lanes[0][0] : null;
    const laneC = (k) => (k ? UPDATE_COLOR(k) : 'var(--text-3)');
    const sel = laneK != null ? groups.get(laneK) : [];
    const pipeline = `<section class="hm-card">
      <div class="hm-h"><div><h2>My pipeline</h2><p class="hm-note">Your open tasks grouped by their Task Update · click one</p></div><span class="hm-mute mono">${open.length} open</span></div>
      ${lanes.length ? `<div class="hm-lanes" style="grid-template-columns:repeat(${Math.max(lanes.length, 3)},minmax(0,1fr))">${lanes.map(([k, ts]) => `<button type="button" class="hm-lane ${k === laneK ? 'on' : ''}" data-hm="lane" data-v="${esc(k)}">
          <span class="hm-lh"><span><i style="background:${laneC(k)}"></i>${esc(k || 'No Task Update')}</span><b class="mono">${ts.length}</b></span>
          ${ts.slice(0, 2).map((t) => `<span class="hm-mini" style="border-left-color:${pColor(t)}">${title(t)}</span>`).join('')}${ts.length > 2 ? `<span class="hm-more">+${ts.length - 2} more</span>` : ''}
        </button>`).join('')}</div>
        <div class="hm-lane-list">${sel.map((t) => `<div class="hm-lrow" data-task="${t.id}"><i style="background:${pColor(t)}"></i><span class="hm-t">${title(t)}</span><span class="hm-sub">${esc(pName(t))}</span><span class="due ${dueClass(t)}">${esc(fmtDue(t.due))}</span></div>`).join('')}</div>`
        : '<div class="hm-empty">No open tasks right now.</div>'}
    </section>`;

    // My week
    const days = week();
    const cal = `<section class="hm-card">
      <div class="hm-h"><div><h2>My week</h2><p class="hm-note">Your tasks on their due date (and start date) · grey = already done</p></div><span class="hm-mute">${esc(parseYmd(days[0].d).toLocaleDateString('en-US', { day: 'numeric', month: 'short' }))} – ${esc(parseYmd(days[4].d).toLocaleDateString('en-US', { day: 'numeric', month: 'short' }))}</span></div>
      <div class="hm-cal">${days.map((x) => {
        const due = mineAll.filter((t) => t.due === x.d).map((t) => ({ t, k: 'Due' }));
        const start = mineAll.filter((t) => t.start === x.d && t.due !== x.d).map((t) => ({ t, k: 'Starts' }));
        const list = due.concat(start).sort((a, b) => Number(myDoneAt(a.t) != null) - Number(myDoneAt(b.t) != null));
        return `<div><div class="hm-cal-d ${x.d === today ? 'today' : ''}">${x.d === today ? 'Today · ' : ''}${parseYmd(x.d).toLocaleDateString('en-US', { weekday: 'short', day: 'numeric' })}</div>
          <div class="hm-slot ${x.d === today ? 'today' : ''}">${list.map(({ t, k }) => { const dn = myDoneAt(t) != null; return `<div class="hm-post ${dn ? 'done' : ''} ${!dn && k === 'Due' && x.d < today ? 'late' : ''}" data-task="${t.id}" style="border-left-color:${pColor(t)}"><span>${dn ? 'Done' : k}${t.update ? ' · ' + esc(t.update) : ''}</span>${title(t)}</div>`; }).join('')}</div></div>`;
      }).join('')}</div>
    </section>`;

    // Recent activity: my Inbox
    const acts = (db.notifications || []).filter((n) => n.to === currentUserId && n.from).sort((a, b) => String(b.at).localeCompare(String(a.at))).slice(0, 4)
      .map((n) => ({ from: n.from, html: esc(n.text), quote: n.snippet, taskId: n.taskId, at: n.at }));

    // CD reviews this month
    const now = new Date();
    const thisMonth = (iso) => { if (!iso) return false; const d = new Date(iso); return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth(); };
    const myRev = db.tasks.flatMap((t) => (t.reviews || []).filter((r) => r.by === currentUserId && r.state !== 'withdrawn').map((r) => ({ t, r })));
    const monthRev = myRev.filter(({ r }) => thisMonth(r.decidedAt || r.at));
    const approved = monthRev.filter(({ r }) => r.state === 'approved').length;
    const amended = monthRev.filter(({ r }) => r.state === 'amend').length;
    const waiting = myRev.filter(({ t, r }) => r.state === 'pending' && !t.done).length;
    const firstTime = monthRev.filter(({ r }) => r.state === 'approved' && (r.round || 1) === 1).length;
    const decidedTasks = new Set(monthRev.filter(({ r }) => r.state === 'approved' || r.state === 'amend').map(({ t }) => t.id)).size;
    const ft = pct(firstTime, decidedTasks);
    const ring = 2 * Math.PI * 15.9;

    // Amendments to fix
    const amends = open.filter((t) => needsCD(t) && reviewState(t) === 'amend').map((t) => ({ t, r: lastReview(t, currentUserId) }));

    // Latest files on my tasks
    const files = mineAll.flatMap((t) => shownAtts(t).map((a) => ({ t, a }))).sort((x, y) => String(y.a.addedAt || '').localeCompare(String(x.a.addedAt || ''))).slice(0, 4);
    const thumb = ({ t, a }) => {
      const img = fileKind(a) === 'image' && Host.isNative ? `<img src="${imgUrl(a, 320)}" alt="" loading="lazy">` : '';
      return `<div class="hm-thumb" data-task="${t.id}" title="${esc(a.name)} · ${esc(t.title || '')}" style="--pc:${pColor(t)}">${img}<span class="hm-kind">${esc((fileExt(a.name) || 'file').toUpperCase().slice(0, 4))}</span><span class="hm-fname">${esc(a.name)}</span></div>`;
    };

    // On-time streak: my finished tasks, newest first, until one was late
    const finished = mineAll.filter((t) => myDoneAt(t) && t.due).sort((a, b) => String(myDoneAt(b)).localeCompare(String(myDoneAt(a))));
    let streak = 0;
    for (const t of finished) { if (onTime(t, myDoneAt(t))) streak++; else break; }

    const roleL = { production: 'Production', social: 'Social', freelancer: 'Freelancer' }[u.role] || ROLES[u.role] || '';
    return `<div class="hm hm-member">
      <header class="hm-head"><div><div class="hm-date">${dateLine()}${roleL ? ' · ' + esc(roleL) : ''}</div><h1>${greeting()}, ${esc(first(u))}</h1></div>
        <div class="hm-btns"><button type="button" class="hm-btn" data-nav="today">My Day</button>${can('createTask') ? '<button type="button" class="hm-btn primary" data-action="new-task">+ New task</button>' : ''}</div></header>
      <div class="hm-grid">
        <div class="hm-col">
          ${hero}
          ${pipeline}
          ${cal}
          ${actCard(acts, 'Mentions, approvals and new assignments show up here.', 'grow')}
        </div>
        <aside class="hm-col">
          <section class="hm-card">
            <h2>My CD reviews</h2>
            <div class="hm-rev">
              <svg viewBox="0 0 36 36" aria-hidden="true"><circle cx="18" cy="18" r="15.9" class="trk"/><circle cx="18" cy="18" r="15.9" class="val" stroke-dasharray="${(ft / 100) * ring} ${ring}" transform="rotate(-90 18 18)"/><text x="18" y="20.6" text-anchor="middle">${decidedTasks ? ft + '%' : '–'}</text></svg>
              <div><b>Approved first time</b><br><span class="mono">${approved}</span> approved · <span class="mono">${amended}</span> amended<br><span class="mono">${waiting}</span> waiting with the CD<br><small>Your submissions in ${now.toLocaleDateString('en-US', { month: 'long' })}</small></div>
            </div>
          </section>
          <section class="hm-card">
            <div class="hm-h"><h2>Amendments to fix</h2>${amends.length ? `<span class="hm-pill red solid">${amends.length}</span>` : ''}</div>
            ${amends.length ? amends.map(({ t, r }) => `<div class="hm-am" data-task="${t.id}"><b>${title(t)}</b>${r && r.noteHtml ? `<div class="hm-am-n">${avatarHTML(r.decidedBy || cdUserId(), 26)}<span>“${esc(notifPlainHTML(r.noteHtml))}”</span></div>` : ''}</div>`).join('') : '<div class="hm-empty">Nothing to fix — the CD hasn’t asked for changes.</div>'}
          </section>
          <section class="hm-card">
            <div class="hm-h"><h2>Latest files</h2><span class="hm-mute">on your tasks</span></div>
            ${files.length ? `<div class="hm-files">${files.map(thumb).join('')}</div>` : '<div class="hm-empty">Files on your tasks show up here.</div>'}
          </section>
          <section class="hm-hero">
            <h2>On-time streak</h2>
            <div class="hm-hn"><b>${streak}</b><span>task${streak === 1 ? '' : 's'} in a row finished by their due date</span></div>
          </section>
        </aside>
      </div>
    </div>`;
  }

  function view() {
    if (Host.isNative) setTimeout(() => hydrateThumbs($('#content')), 0);
    return Work.lead() ? viewLead() : viewMember();
  }

  document.addEventListener('click', (e) => {
    if (ui.view !== 'home') return;
    const el = e.target.closest('[data-hm]');
    if (!el) return;
    e.stopPropagation();
    const k = el.dataset.hm, v = el.dataset.v;
    if (k === 'range') st.range = v;
    else if (k === 'metric') st.metric = v;
    else if (k === 'day') st.day = v;
    else if (k === 'lane') st.lane = v;
    else if (k === 'next') st.next++;
    else if (k === 'all') { ui.workF = null; ui.myTasksTab = 'todo'; return go('mytasks'); }
    else if (k === 'open') return openTask(v);
    else if (k === 'submit') { const t = task(v); if (t) submitDialog(t); return; }
    else if (k === 'part') { const t = task(v); if (t) setMyPart(t, true); return; }
    else if (k === 'cl') {
      const t = task(el.dataset.taskId); const c = t && (t.checklist || []).find((x) => x.id === v);
      if (!c) return;
      c.done = !c.done; logActivity(t, `${c.done ? 'checked' : 'unchecked'} <b>${esc(c.text)}</b>`); t.updatedAt = nowISO(); commit(); return;
    }
    renderContent();
  });

  return { view, st };
})();
