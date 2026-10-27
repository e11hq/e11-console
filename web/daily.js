/* Morning round-up for Account Managers and Super Admins (server/src/amdaily.js sends it at 9:00 Dubai, Monday to
   Friday, not on UAE public holidays). Opening the Inbox update shows this card, worked out again with the latest
   data: Overdue, Due today, Waiting for CD review, Amendments sent back, Client approval missing, and your comments
   scheduled for today. An AM's card covers their own work (the same tasks as their Home page); a Super Admin's the
   whole team's. Each line lists its tasks; Overdue, Due today and Waiting for CD open My Tasks with that filter. */
const Daily = (() => {
  const wants = (u = me()) => !!u && (u.role === 'am' || isSuper(u));
  const team = (u = me()) => isSuper(u);
  function tasksFor(u = me()) {
    const ids = team(u) ? db.users.filter((x) => x.active !== false && (x.role === 'am' || isAdm(x))).map((x) => x.id) : [u.id];
    return Work.leadSet(ids).filter((t) => !t.done && !(proj(t.projectId) || {}).inactive);
  }
  const amend = (t) => needsCD(t) && reviewersOf(t).some((u) => reviewState(t, u) === 'amend');
  const clientMissing = (t) => hasApproved(t) && !clientApprovalFresh(t);
  const dubaiDay = (iso) => new Date(Date.parse(iso) + 4 * 3600000).toISOString().slice(0, 10);
  function sections(u = me()) {
    const open = tasksFor(u), today = todayStr();
    const byDue = (a, b) => (a.due || '9999').localeCompare(b.due || '9999');
    const sched = (db.scheduled || []).filter((s) => s.authorId === u.id && s.state === 'waiting' && dubaiDay(s.sendAt) === dubaiDay(new Date().toISOString()))
      .sort((a, b) => String(a.sendAt).localeCompare(String(b.sendAt)));
    return [
      { k: 'overdue', l: 'Overdue', ic: 'flag', tone: 'red', tasks: open.filter((t) => t.due && t.due < today).sort(byDue), filter: { due: 'late' } },
      { k: 'today', l: 'Due today', ic: 'cal', tone: 'amber', tasks: open.filter((t) => t.due === today), filter: { due: 'today' } },
      { k: 'cd', l: 'Waiting for CD review', ic: 'shield', tone: 'accent', tasks: open.filter(reviewPending), filter: { cd: true } },
      { k: 'amend', l: 'Amendments sent back', ic: 'edit', tone: 'red', tasks: open.filter(amend) },
      { k: 'client', l: 'Client approval missing', ic: 'check-circle', tone: 'amber', tasks: open.filter(clientMissing) },
      { k: 'sched', l: 'Your comments scheduled today', ic: 'clock', tone: 'accent', sched },
    ];
  }
  const fmtClock = (iso) => new Date(iso).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Dubai' });
  function rowHTML(t) {
    const p = proj(t.projectId);
    const late = t.due && t.due < todayStr();
    return `<button type="button" class="dy-row" data-dy-open="${esc(t.id)}"><span class="dy-rt">${esc(t.title || 'Untitled task')}</span><span class="dy-rm">${p ? esc(p.name) : ''}${t.due ? `<i class="${late ? 'late' : ''}">${esc(fmtDay(t.due))}</i>` : ''}</span></button>`;
  }
  const open = { k: null };
  function cardHTML(u = me()) {
    const S = sections(u);
    const n = (s) => (s.sched ? s.sched.length : s.tasks.length);
    const any = S.some((s) => n(s));
    if (!open.k) { const f = S.find((s) => n(s)); open.k = f ? f.k : null; }
    const when = new Date().toLocaleDateString('en-US', { weekday: 'long', day: 'numeric', month: 'long' });
    const body = !any ? `<div class="dy-clear">${icon('check-circle')}<b>All clear today</b><span>Nothing overdue, due today or waiting on anyone.</span></div>`
      : S.map((s) => {
        const c = n(s), on = open.k === s.k && c;
        const list = !on ? '' : s.sched
          ? s.sched.map((x) => { const t = task(x.taskId); return `<button type="button" class="dy-row" data-dy-open="${esc(x.taskId)}"><span class="dy-rt">${esc(trunc(x.text || 'Files', 70))}</span><span class="dy-rm">${t ? esc(t.title || 'Untitled task') : ''}<i>${esc(fmtClock(x.sendAt))}</i></span></button>`; }).join('')
          : s.tasks.slice(0, 6).map(rowHTML).join('') + (s.tasks.length > 6 || s.filter ? `<button type="button" class="dy-more" data-dy-all="${s.k}">${s.filter ? `See ${s.tasks.length > 6 ? 'all ' + s.tasks.length : 'them'} in My Tasks` : `+${s.tasks.length - 6} more`}</button>` : '');
        return `<div class="dy-sec ${c ? '' : 'none'} ${on ? 'open' : ''} t-${s.tone}">
          <button type="button" class="dy-h" data-dy-sec="${s.k}" ${c ? '' : 'disabled'}><span class="dy-ic">${icon(s.ic)}</span><span class="dy-l">${esc(s.l)}</span><b class="dy-n">${c}</b>${c ? icon('chev') : ''}</button>
          ${on ? `<div class="dy-list">${list}</div>` : ''}</div>`;
      }).join('');
    return `<div class="scrim dy-scrim"><div class="dialog dy-card" role="dialog" aria-label="Morning round-up">
      <div class="dy-top"><span class="dy-sun">${icon('sun')}</span><div><h2>Good morning, ${esc(firstName(u.id))}</h2><span>${esc(when)} · ${team(u) ? 'the whole team’s tasks' : Work.hasClients(u.id) ? 'your clients’ tasks' : 'your tasks'}</span></div>
        <button type="button" class="icon-btn dy-x" data-dy-close title="Close">${icon('x')}</button></div>
      <div class="dy-body">${body}</div>
      <div class="dy-foot"><span>Up to date as of ${esc(new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }))}</span><button type="button" class="btn primary sm" data-dy-close>Done</button></div>
    </div></div>`;
  }
  let shown = false;
  function paint() { const root = document.getElementById('overlay-root'); if (root && shown) root.innerHTML = cardHTML(); }
  function show() {
    if (!wants()) return;
    open.k = null; shown = true;
    paint();
  }
  function close() { shown = false; const root = document.getElementById('overlay-root'); if (root && root.querySelector('.dy-scrim')) root.innerHTML = ''; }
  document.addEventListener('click', (e) => {
    if (!shown || !e.target.closest) return;
    const root = document.getElementById('overlay-root');
    if (!root || !root.contains(e.target)) return;
    if (e.target.classList && e.target.classList.contains('dy-scrim')) return close();
    if (e.target.closest('[data-dy-close]')) return close();
    const sec = e.target.closest('[data-dy-sec]');
    if (sec) { open.k = open.k === sec.dataset.dySec ? '' : sec.dataset.dySec; return paint(); }
    const o = e.target.closest('[data-dy-open]');
    if (o) { close(); if (task(o.dataset.dyOpen)) openTask(o.dataset.dyOpen); else toast('That task isn’t there anymore'); return; }
    const all = e.target.closest('[data-dy-all]');
    if (all) {
      const s = sections().find((x) => x.k === all.dataset.dyAll);
      if (s && s.filter) {
        close();
        ui.workF = null; ui.myTasksTab = 'todo';
        const F = Work.f();
        if (team()) F.team = true;
        Object.assign(F, s.filter);
        go('mytasks');
      } else if (s) { all.remove(); const list = root.querySelector('.dy-sec.open .dy-list'); if (list) list.innerHTML = s.tasks.map(rowHTML).join(''); }
    }
  });
  document.addEventListener('keydown', (e) => { if (shown && e.key === 'Escape') { e.preventDefault(); close(); } }, true);
  // a try-out from My profile: one now, in the Inbox and on the phone
  async function tryNow() {
    try { await api('POST', '/api/daily/test', {}); toast('Sent — it’s in your Inbox'); } catch (e) { toast('Couldn’t send it: ' + e.message); }
  }
  return { wants, show, close, sections, tryNow, isOpen: () => shown };
})();
