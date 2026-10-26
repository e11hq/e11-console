/* ================= Office Admin: Home =================
   An Office Admin (e.g. Arsal) has Admin rights without the task app. Their Home shows what they look after: recent
   Client Assets activity across clients, their latest Inbox updates, the team, and Finance when they have Finance access. */
const OfficeHome = (() => {
  function recentFiles(limit) {
    const out = [];
    (db.clients || []).filter(caVisible).forEach((c) => (c.folders || []).forEach((f) => (f.files || []).forEach((a) => out.push({ c, f, a }))));
    return out.filter((x) => x.a.addedAt).sort((x, y) => String(y.a.addedAt).localeCompare(String(x.a.addedAt))).slice(0, limit);
  }
  function view() {
    const u = me();
    const h = new Date().getHours();
    const part = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    const files = recentFiles(8);
    const notes = myNotifs().slice().sort((a, b) => b.at.localeCompare(a.at)).slice(0, 6);
    const unread = myNotifs().filter((n) => !n.read).length;
    const team = db.users.filter((x) => x.active !== false);
    const clients = clientsSorted();
    const fin = typeof finLevel === 'function' ? finLevel(u) : null;
    const claimsNew = myNotifs().filter((n) => n.kind === 'claim' && !n.read).length;
    return `<div class="oh">
      <div class="oh-head">
        <div class="oh-date">${esc(new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' }))} · Office Admin</div>
        <h1>${esc(part)}, ${esc(firstName(u.id))}</h1>
      </div>
      <div class="oh-stats">
        <button class="oh-stat" data-nav="clients"><b>${clients.length}</b><span>Clients in Client Assets</span></button>
        <button class="oh-stat" data-nav="inbox"><b>${unread}</b><span>Unread in your Inbox</span></button>
        <button class="oh-stat" data-action="oh-team"><b>${team.length}</b><span>Team members</span></button>
        ${fin ? `<button class="oh-stat" data-nav="fin-dash"><b>${claimsNew}</b><span>New expense claims</span></button>` : ''}
      </div>
      <div class="oh-grid">
        <section class="oh-card">
          <div class="oh-card-h"><h3>${icon('assets')}Latest in Client Assets</h3><button class="btn ghost sm" data-nav="clients">Open Client Assets</button></div>
          ${files.length ? files.map(({ c, f, a }) => `<button class="oh-row" data-action="oh-folder" data-client="${c.id}" data-folder="${f.id}">
              <span class="oh-ic">${icon('clip')}</span>
              <span class="oh-t"><b>${esc(a.name)}</b><small>${esc(c.name)} › ${esc(f.name)}${a.addedBy ? ' · ' + esc(firstName(a.addedBy)) : ''}</small></span>
              <span class="oh-w">${esc(timeAgo(a.addedAt))}</span></button>`).join('')
            : '<div class="oh-empty">No files yet</div>'}
        </section>
        <section class="oh-card">
          <div class="oh-card-h"><h3>${icon('inbox')}Inbox</h3><button class="btn ghost sm" data-nav="inbox">Open Inbox</button></div>
          ${notes.length ? notes.map((n) => `<button class="oh-row ${n.read ? '' : 'unread'}" data-action="open-notif" data-id="${n.id}">
              ${avatarHTML(n.from, 26)}
              <span class="oh-t"><b>${notifMsg(n, null)}</b><small>${esc(timeAgo(n.at))}</small></span>
              ${n.read ? '' : '<i class="oh-dot"></i>'}</button>`).join('')
            : '<div class="oh-empty">Nothing here yet — Client Assets and Finance updates land here.</div>'}
        </section>
        ${fin ? `<section class="oh-card">
          <div class="oh-card-h"><h3>${icon('coin')}Finance</h3></div>
          <div class="oh-links">
            <button class="btn" data-nav="fin-dash">Dashboard</button>
            <button class="btn" data-nav="fin-expenses">Expenses</button>
            <button class="btn" data-action="oh-reimb">Staff reimbursements${claimsNew ? ` · ${claimsNew} new` : ''}</button>
          </div>
        </section>` : ''}
      </div>
    </div>`;
  }
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-action="oh-folder"], [data-action="oh-team"], [data-action="oh-reimb"]');
    if (!b) return;
    e.stopPropagation();
    if (b.dataset.action === 'oh-folder') openClient(b.dataset.client, b.dataset.folder);
    else if (b.dataset.action === 'oh-team') go('team');
    else go('fin-reimb');
  }, true);
  return { view };
})();
