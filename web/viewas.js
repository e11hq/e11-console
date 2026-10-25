/* ================= View as (TEST SITE ONLY) =================
   A testing aid for the owner on the test copy: use the app as any team member, within their role, to check what
   they see. The server does the switching (it treats the owner's requests as that person) and remembers the choice,
   so it holds after reloads and on every device until "Back to me". Never offered on the live site — the server
   refuses it there and /api/me sends nothing. Keep this on the test copy in future updates. */
const ViewAs = (() => {
  let info = null;   // { real: { id, name }, as: { id, name, role } | null }
  const available = () => !!info;
  const viewing = () => !!(info && info.as);
  function init(v) {
    info = v || null;
    document.documentElement.classList.toggle('viewas-on', viewing());
    let bar = document.getElementById('viewas-bar');
    if (!viewing()) { if (bar) bar.remove(); return; }
    if (!bar) { bar = document.createElement('div'); bar.id = 'viewas-bar'; document.body.appendChild(bar); }
    bar.innerHTML = `${icon('users')}<span>Viewing as <b>${esc(info.as.name)}</b> · ${esc(roleOf(userById(info.as.id)) || ROLES[info.as.role] || info.as.role)}<small>Test site only</small></span>
      <button class="btn sm" data-va="pick">Switch</button><button class="btn primary sm" data-va="me">Back to me</button>`;
  }
  async function set(userId) {
    try { await Sync.push(); } catch (e) { /* offline: fine */ }
    try { await api('POST', '/api/view-as', { userId: userId || null }); } catch (e) { toast(e.message); return; }
    location.reload();
  }
  // the team, with a search on top; pick one to use the app as them
  function pick() {
    if (!available()) return;
    const root = $('#overlay-root');
    const people = db.users.filter((u) => u.active !== false && u.id !== info.real.id).sort((a, b) => fullName(a).localeCompare(fullName(b)));
    root.innerHTML = `<div class="scrim"><div class="dialog va-dlg" role="dialog" aria-label="View as">
      <div class="cd-top"><h2>View as…</h2><button class="icon-btn" data-va="close" title="Close">${icon('x')}</button></div>
      <p class="va-note">Test site only. Use the app as this person, with their role — what they see and what they can do. It stays until you choose <b>Back to me</b>.</p>
      <div class="ap-search va-search">${icon('search')}<input placeholder="Search the team…" autocomplete="off" spellcheck="false"></div>
      <div class="va-list"></div>
      ${viewing() ? '<div class="actions"><button class="btn primary" data-va="me">Back to me (Admin)</button></div>' : ''}
    </div></div>`;
    const input = $('.va-search input', root), list = $('.va-list', root);
    const draw = () => {
      const q = input.value.trim().toLowerCase();
      const rows = people.filter((u) => !q || fullName(u).toLowerCase().includes(q) || u.email.toLowerCase().includes(q) || String(roleOf(u)).toLowerCase().includes(q));
      list.innerHTML = rows.length ? rows.map((u) => `<button class="va-row ${info.as && info.as.id === u.id ? 'on' : ''}" data-va-id="${u.id}">${avatarHTML(u.id, 30)}<span><b>${esc(fullName(u))}</b><small>${esc(u.email)}</small></span><span class="role-pill r-${roleCls(u)}">${esc(roleOf(u))}</span></button>`).join('')
        : `<div class="ap-none">No one matches “${esc(input.value.trim())}”</div>`;
    };
    input.addEventListener('input', draw);
    $('.scrim', root).addEventListener('click', (e) => {
      if (e.target.classList.contains('scrim') || e.target.closest('[data-va="close"]')) { root.innerHTML = ''; return; }
      const r = e.target.closest('[data-va-id]'); if (r) set(r.dataset.vaId);
    });
    draw(); setTimeout(() => input.focus(), 20);
  }
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-va]'); if (!b) return;
    if (b.dataset.va === 'me') { e.preventDefault(); set(null); }
    else if (b.dataset.va === 'pick') { e.preventDefault(); pick(); }
  });
  return { init, available, viewing, pick, back: () => set(null) };
})();
