/* ================= Clients: the Admin's client pop-up and the "Edit client list" page =================
   A client (stored as a project) has a name, a colour, its Account Managers and whether it's active:
     p.ams = [{ id, onLeave? }]   the AMs who look after it; one on leave stays listed but another covers
     p.inactive = true            an inactive client is hidden from everyone with its tasks, Client Assets and Finance
                                  history (the server stops sending them) until an Admin switches it back on
   Only Admins add or change clients (the server checks the same). A new client gets its Client Assets folder;
   renaming a client renames its Client Assets folder too (the folder on disk keeps its name). */
const ClientList = (() => {
  const amList = () => db.users.filter((u) => u.active !== false && u.role === 'am').sort((a, b) => fullName(a).localeCompare(fullName(b)));
  const amsOf = (p) => (p.ams || []).filter((a) => userById(a.id));
  const isActive = (p) => !p.inactive;

  /* ---------- the pop-up: new client, or edit one ---------- */
  function dialog(p) {
    if (!isAdmin()) { toast('Only Admins add or change clients'); return; }
    const isNew = !p;
    const used = new Set(db.projects.map((x) => x.color));
    const st = {
      name: p ? p.name : '',
      color: p ? p.color : (COLORS.find((c) => !used.has(c)) || COLORS[0]),
      ams: p ? amsOf(p).map((a) => ({ ...a })) : [],
      active: p ? isActive(p) : true,
    };
    const root = $('#overlay-root');
    root.innerHTML = `<div class="scrim"><form class="dialog cd-dlg" autocomplete="off" role="dialog" aria-label="${isNew ? 'New client' : 'Edit client'}">
      <div class="cd-top"><h2>${isNew ? 'New client' : 'Edit client'}</h2><button type="button" class="icon-btn cd-x" data-cd="close" title="Close">${icon('x')}</button></div>
      <label class="dlg-label">Client name</label>
      <input class="field" name="name" maxlength="80" placeholder="e.g. Ford & Lincoln" value="${esc(st.name)}">
      <div class="dlg-err" id="cd-err"></div>
      <label class="dlg-label">Colour</label>
      <div class="swatches cd-sw">${COLORS.map((c) => `<button type="button" class="swatch ${c === st.color ? 'on' : ''}" data-cd-color="${c}" style="background:${c}" title="${c}"></button>`).join('')}</div>
      <div class="cd-amh"><label class="dlg-label">Account Managers</label><button type="button" class="btn ghost sm" data-cd="add-am">${icon('plus')}Add</button></div>
      <div class="cd-ams" id="cd-ams"></div>
      <div class="cd-state"><div><b>Active client</b><span id="cd-state-txt"></span></div><button type="button" class="switch ${st.active ? 'on' : ''}" data-cd="active" aria-label="Active client"><i></i></button></div>
      ${isNew ? `<div class="dlg-hint">${icon('folder')}Its Client Assets folder (${DEFAULT_FOLDERS.join(', ')}) is made too.</div>` : ''}
      <div class="actions"><button type="button" class="btn" data-cd="close">Cancel</button><button type="submit" class="btn primary">${isNew ? 'Add client' : 'Save'}</button></div>
    </form></div>`;
    const form = $('form', root), inp = form.elements.name, err = $('#cd-err', root);
    const paintAms = () => {
      $('#cd-ams', root).innerHTML = st.ams.length ? st.ams.map((a) => `<div class="cd-am ${a.onLeave ? 'leave' : ''}">
          ${avatarHTML(a.id, 28)}<span class="cd-am-n">${esc(fullName(userById(a.id)))}${a.onLeave ? '<small>On leave</small>' : ''}</span>
          <button type="button" class="cd-leave ${a.onLeave ? '' : 'on'}" data-cd-leave="${a.id}" title="${a.onLeave ? 'Back from leave' : 'Mark as on leave'}">${a.onLeave ? 'On leave' : 'Active'}</button>
          <button type="button" class="icon-btn sm" data-cd-rm="${a.id}" title="Remove">${icon('x')}</button></div>`).join('')
        : '<div class="cd-none">No Account Manager yet</div>';
      const cover = st.ams.filter((a) => !a.onLeave).length;
      if (st.ams.length && !cover) $('#cd-ams', root).insertAdjacentHTML('beforeend', '<div class="cd-warn">Everyone here is on leave — add or switch on another Account Manager to cover.</div>');
    };
    const paintState = () => { $('#cd-state-txt', root).textContent = st.active ? 'Shows in the sidebar and the client lists' : 'Hidden from everyone with its tasks, Client Assets and Finance history until switched back on'; };
    const check = () => {
      const n = inp.value.trim();
      const d = n && db.projects.find((x) => x !== p && clientKey(x.name) === clientKey(n));
      err.textContent = d ? `There is already a client named “${d.name}”.` : '';
      $('[type="submit"]', root).disabled = !n || !!d;
    };
    const close = () => { root.innerHTML = ''; document.removeEventListener('keydown', onKey, true); };
    const onKey = (e) => { if (e.key === 'Escape' && !$('.cd-pick')) { e.preventDefault(); e.stopPropagation(); close(); } };
    document.addEventListener('keydown', onKey, true);
    inp.addEventListener('input', check);
    $('.scrim', root).addEventListener('mousedown', (e) => { if (e.target.classList.contains('scrim') && !$('.cd-pick')) close(); });   // (with the list open, a click outside only closes the list)
    form.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.cd === 'close') return close();
      if (b.dataset.cdColor) { st.color = b.dataset.cdColor; $$('.cd-sw .swatch', root).forEach((s) => s.classList.toggle('on', s === b)); return; }
      if (b.dataset.cd === 'active') { st.active = !st.active; b.classList.toggle('on', st.active); paintState(); return; }
      if (b.dataset.cdLeave) { const a = st.ams.find((x) => x.id === b.dataset.cdLeave); a.onLeave = !a.onLeave; if (!a.onLeave) delete a.onLeave; paintAms(); return; }
      if (b.dataset.cdRm) { st.ams = st.ams.filter((x) => x.id !== b.dataset.cdRm); paintAms(); return; }
      if (b.dataset.cd === 'add-am') { e.stopPropagation(); pickAms(b, st, paintAms); }
    });
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      check();
      if ($('[type="submit"]', root).disabled) { if (!inp.value.trim()) err.textContent = 'Enter the client’s name'; return; }
      save(p, { ...st, name: inp.value.trim().replace(/\s+/g, ' ') });
      close();
    });
    paintAms(); paintState(); check();
    setTimeout(() => inp.focus(), 20);
  }

  // the list of Account Managers, with a search on top (like a task's assignees); tick several
  function pickAms(anchor, st, done) {
    closeMenus();
    const pop = document.createElement('div');
    pop.className = 'menu asg-pop cd-pick';
    pop.innerHTML = `<div class="ap-search">${icon('search')}<input placeholder="Search Account Managers…" autocomplete="off" spellcheck="false"></div><div class="ap-list"></div>`;
    document.body.appendChild(pop);
    const input = $('input', pop), list = $('.ap-list', pop);
    const place = () => {
      const r = anchor.getBoundingClientRect(), w = pop.offsetWidth, h = pop.offsetHeight;
      let x = r.right - w, y = r.bottom + 6;
      if (y + h > innerHeight - 10) y = Math.max(10, r.top - h - 6);
      pop.style.left = Math.max(10, x) + 'px'; pop.style.top = y + 'px';
    };
    const draw = () => {
      const q = input.value.trim().toLowerCase();
      const people = amList().filter((u) => !q || fullName(u).toLowerCase().includes(q) || u.email.toLowerCase().includes(q));
      list.innerHTML = people.length ? people.map((u) => { const on = st.ams.some((a) => a.id === u.id); return `<div class="ap-item ${on ? 'on' : ''}" data-cd-am="${u.id}">
          <span class="ap-av">${avatarHTML(u.id, 30)}</span><span class="ap-name">${esc(fullName(u))}</span>${on ? `<span class="cd-tick">${icon('check')}</span>` : ''}</div>`; }).join('')
        : `<div class="ap-none">${amList().length ? `No Account Manager matches “${esc(input.value.trim())}”` : 'No Account Managers in the team yet'}</div>`;
      place();
    };
    const off = (e) => { if (!pop.contains(e.target)) { pop.remove(); document.removeEventListener('mousedown', off, true); document.removeEventListener('keydown', esc_, true); } };
    const esc_ = (e) => { if (e.key === 'Escape') { e.stopPropagation(); e.preventDefault(); off({ target: document.body }); } };
    pop.addEventListener('click', (e) => {
      e.stopPropagation();
      const it = e.target.closest('[data-cd-am]'); if (!it) return;
      const id = it.dataset.cdAm;
      st.ams = st.ams.some((a) => a.id === id) ? st.ams.filter((a) => a.id !== id) : st.ams.concat({ id });
      draw(); done(); input.focus();
    });
    input.addEventListener('input', draw);
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); const first = $('[data-cd-am]', pop); if (first) first.click(); } });
    setTimeout(() => { document.addEventListener('mousedown', off, true); document.addEventListener('keydown', esc_, true); }, 0);
    draw(); input.focus();
  }

  function save(p, st) {
    const ams = st.ams.map((a) => (a.onLeave ? { id: a.id, onLeave: true } : { id: a.id }));
    if (!p) {
      const np = createProject(st.name, st.color);
      np.ams = ams;
      if (!st.active) np.inactive = true;
      // its Client Assets folder (Logos, Brand Guidelines, Fonts, Files), linked; an existing one of that name is reused
      const c = dupClient(np.name) || createClient(np.name);
      np.clientId = c.id;
      persist(0);
      renderSidebar();
      if (st.active) go('project', np.id); else renderContent();
      toast(`Added ${np.name}${st.active ? ' — its Client Assets folder is ready' : ' (inactive)'}`);
      return;
    }
    const was = p.name;
    p.name = st.name; p.color = st.color; p.ams = ams;
    if (st.active) delete p.inactive; else p.inactive = true;
    // the linked Client Assets folder takes the new name (unless another Client Assets folder already has it)
    const c = clientOfProject(p);
    if (c && was !== p.name) {
      const clash = dupClient(p.name, c.id);
      if (clash) toast(`Renamed. Client Assets already has “${clash.name}”, so its folder keeps the name “${c.name}”.`);
      else c.name = p.name;
    }
    persist(0);
    renderSidebar(); renderTitle(); renderContent();
    toast(`Saved ${p.name}`);
  }

  function setActive(p, on) {
    if (!isAdmin()) return denied();
    if (on) delete p.inactive; else p.inactive = true;
    persist(0);
    renderSidebar(); renderContent();
    toast(on ? `${p.name} is active again — its tasks and Client Assets are back` : `${p.name} is inactive — hidden from everyone with its tasks, Client Assets and Finance history`);
  }

  /* ---------- the "Edit client list" page (Admins) ---------- */
  const owns = (v) => v === 'clientlist';
  const title = () => `<div class="page-icon" style="background:#2a2350;color:#b6a6ff">${icon('folder')}</div><div class="page-title">Edit client list</div>`;
  function render(c) {
    if (!isAdmin()) { ui.view = 'home'; return renderContent(); }
    const all = db.projects.slice().sort(byOrder);
    const act = all.filter(isActive), inact = all.filter((p) => !isActive(p));
    const tab = ui.clTab === 'inactive' ? 'inactive' : 'active';
    const list = tab === 'inactive' ? inact : act;
    const open = (p) => db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done).length;
    c.innerHTML = `<div class="team cl-list">
      <div class="team-head">
        <div><div class="team-title">${act.length} active client${act.length === 1 ? '' : 's'}</div><div class="team-sub">Only Admins add and change clients. An inactive client is hidden from everyone — with its tasks, Client Assets and Finance history — until you switch it back on. Nothing is deleted.</div></div>
        <span class="spacer"></span>
        <button class="btn primary" data-cl="new">${icon('plus')}New client</button>
      </div>
      <div class="mt-tabs team-tabs" role="tablist">
        <button class="mt-tab ${tab === 'active' ? 'on' : ''}" role="tab" data-cl="tab" data-tab="active">Active clients <span>${act.length}</span></button>
        <button class="mt-tab ${tab === 'inactive' ? 'on' : ''}" role="tab" data-cl="tab" data-tab="inactive">Inactive clients <span>${inact.length}</span></button>
      </div>
      ${!list.length ? `<div class="empty"><div class="big">${tab === 'inactive' ? 'No inactive clients' : 'No active clients'}</div>${tab === 'inactive' ? 'Clients you switch off show here, and you can switch them back on.' : 'Add a client with New client.'}</div>`
        : `<div class="team-table">
        <div class="tt-row tt-head cl-row"><div>Client</div><div>Account Managers</div><div>Open tasks</div><div>Client Assets</div><div>Active</div><div></div></div>
        ${list.map((p) => { const ams = amsOf(p), ca = clientOfProject(p); return `<div class="tt-row cl-row ${isActive(p) ? '' : 'inactive'}">
          <div class="tt-name"><span class="cl-dot" style="background:${p.color}"></span><span>${esc(p.name)}</span></div>
          <div class="cl-ams">${ams.length ? ams.map((a) => `<span class="cl-am ${a.onLeave ? 'leave' : ''}" title="${esc(fullName(userById(a.id)))}${a.onLeave ? ' (on leave)' : ''}">${avatarHTML(a.id, 24)}<span>${esc(firstName(a.id))}${a.onLeave ? ' <small>on leave</small>' : ''}</span></span>`).join('') : '<span class="cl-none">None yet</span>'}</div>
          <div>${isActive(p) ? open(p) : '<span class="cl-none" title="Hidden while the client is inactive">Hidden</span>'}</div>
          <div>${ca ? `<a class="cl-ca" data-action="open-client" data-id="${ca.id}">${clientLogoHTML(ca, 18)}${esc(ca.name)}</a>` : !isActive(p) && p.clientId ? '<span class="cl-none">Hidden</span>' : '<span class="cl-none">Not linked</span>'}</div>
          <div><button class="switch ${isActive(p) ? 'on' : ''}" data-cl="active" data-id="${p.id}" aria-label="Active" title="${isActive(p) ? 'Make inactive' : 'Make active'}"><i></i></button></div>
          <div><button class="btn ghost sm" data-cl="edit" data-id="${p.id}">${icon('edit')}Edit</button></div>
        </div>`; }).join('')}
      </div>`}
    </div>`;
  }
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-cl]'); if (!b) return;
    const k = b.dataset.cl, p = b.dataset.id ? proj(b.dataset.id) : null;
    if (k === 'tab') { ui.clTab = b.dataset.tab; renderContent(); }
    else if (k === 'new') dialog(null);
    else if (k === 'edit' && p) dialog(p);
    else if (k === 'active' && p) setActive(p, !isActive(p));
  });
  return { dialog, owns, title, render, isActive, amsOf };
})();
