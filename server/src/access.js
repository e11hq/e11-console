// Who can see and change what. The interface already hides buttons people can't use; these
// checks make the server enforce the important rules too (especially for freelancers).
import { deepEqual } from './merge.js';

const SECRET_USER_FIELDS = ['hash', 'salt'];
// Fields only an Admin may change on a person's account
const PROTECTED_USER_FIELDS = ['role', 'active', 'email', 'projectIds', 'admin', 'fin'];

export function createAccess(store, opts = {}) {
  // The owner (ADMIN_EMAIL): nobody else may change their role, rights, email or clients, or deactivate them —
  // whatever role they use the app with (they may work as Production and still own it)
  const ownerEmail = String(opts.ownerEmail || '').toLowerCase();
  const isOwnerUser = (x) => !!ownerEmail && !!x && String(x.email || '').toLowerCase() === ownerEmail;
  const users = () => store.list('users');
  const userByEmail = (email) => users().find((u) => u.active !== false && String(u.email || '').toLowerCase() === String(email || '').toLowerCase()) || null;
  const isFreelancer = (u) => u && u.role === 'freelancer';
  // Finance people (Finance Admin / Finance Viewer) only use the Finance pages: they see projects and a
  // slim copy of each task (name, project, status, dates, Finance status) — no comments, files or people's work.
  const isFinance = (u) => !!u && (u.role === 'finance_admin' || u.role === 'finance_viewer');
  const TASK_FOR_FINANCE = ['id', 'title', 'projectId', 'sectionId', 'parentId', 'done', 'completedAt', 'due', 'createdAt', 'updatedAt', 'finance', 'financeAt', 'financeBy', 'order'];
  // Admin rights: the Admin role, or another role given Admin rights on top. Finance access: Finance-only
  // people, or anyone given Finance Admin / Finance Viewer on top of their role (u.fin).
  const isAdm = (u) => !!u && (u.role === 'admin' || u.role === 'office_admin' || u.admin === true);
  // Office Admin: Admin rights (Team, Client Assets, App updates, Finance per their access) with a narrower view —
  // no tasks (only the slim job list Finance needs), no adding or editing clients, and in the Trash only Client Assets
  // items, which they can restore but not delete forever. Super Admin = the Admin role (or Admin rights on top).
  const isOffice = (u) => !!u && u.role === 'office_admin' && u.admin !== true;
  const isSuper = (u) => isAdm(u) && !isOffice(u);
  const CA_TRASH = new Set(['cafile', 'cafolder']);
  const finLevel = (u) => (!u ? null : u.role === 'finance_admin' ? 'admin' : u.role === 'finance_viewer' ? 'viewer' : u.fin === 'admin' || u.fin === 'viewer' ? u.fin : null);
  const projectSet = (u) => new Set(Array.isArray(u.projectIds) ? u.projectIds : []);

  // An inactive client (project.inactive) is hidden with everything in it — its tasks, their files and Inbox updates,
  // its Client Assets and its Finance history — from everyone, until an Admin switches it back on
  function inactiveIds() { return new Set(store.list('projects').filter((p) => p.inactive).map((p) => p.id)); }
  function taskProject(t) {
    if (!t) return null;
    if (t.projectId) return t.projectId;
    const parent = t.parentId ? store.get('tasks', String(t.parentId)) : null;
    return parent ? parent.projectId || null : null;
  }
  const inInactive = (t, off = inactiveIds()) => !!t && off.size > 0 && off.has(taskProject(t));
  // Client Assets of a client whose projects are all inactive
  function hiddenClient(c, off = inactiveIds()) {
    if (!c || !off.size) return false;
    const linked = store.list('projects').filter((p) => p.clientId === c.id);
    return linked.length > 0 && linked.every((p) => off.has(p.id));
  }
  // Production and Freelancers only see what they're part of: the tasks they're assigned to, created, guard, or are
  // @mentioned in (with the task such a task sits under, and its subtasks), the clients those tasks are in
  // and those clients' Client Assets. A freelancer's clients are also limited to the ones an Admin gave them.
  // (Not for someone with Admin rights or the Creative Director.)
  const cdId = () => (store.get('meta', 'main') || {}).cdUserId || null;
  const ownOnly = (u) => !!u && (u.role === 'production' || u.role === 'freelancer') && !isAdm(u) && u.id !== cdId();
  /* Content plans (a trial on the test copy): one plan per client per month, made by that client's Social Executives
     (project.socials) or a Social Manager (meta.socialMgrIds, Social people an Admin picks). Admins, Account Managers
     and the CD look at them; Production, Freelancers, Finance-only people and Office Admins don't see them. */
  const socialMgrs = () => new Set(((store.get('meta', 'main') || {}).socialMgrIds) || []);
  const isSocialMgr = (u) => !!u && u.role === 'social' && u.active !== false && socialMgrs().has(u.id);
  function planEditor(u, pid) {
    if (!u || u.role !== 'social' || u.active === false) return false;
    if (isSocialMgr(u)) return true;
    const p = pid && store.get('projects', String(pid));
    return !!p && (p.socials || []).includes(u.id);
  }
  // who makes tasks from an approved skeleton, exports it for the client and records the client's reply
  const planMaker = (u, pl) => !!u && !!pl && (planEditor(u, pl.projectId) || u.id === cdId() || isAdm(u) || ((store.get('projects', String(pl.projectId)) || {}).ams || []).some((a) => a.id === u.id));
  const planVisible = (u, pl) => !isFinance(u) && !isOffice(u) && !ownOnly(u) && !isFreelancer(u) && !(pl && pl.projectId && inactiveIds().has(pl.projectId));
  const mentioned = (html, id) => String(html || '').includes(`data-user="${id}"`);
  const partOf = (t, id) => (t.assignees || []).includes(id) || t.createdBy === id || t.guardian === id || mentioned(t.notesHtml, id)
    || (t.comments || []).some((c) => mentioned(c.html, id));
  // Tasks opened from a link someone sent (Production / Freelancers not on that task): they can read them and comment,
  // nothing else. Remembered per person (the last 100), so it holds after reloads.
  let peeks = null;
  const peekMap = () => { if (!peeks) { try { peeks = new Map(Object.entries(JSON.parse(store.kv.get('peeks') || '{}')).map(([k, v]) => [k, new Set(v)])); } catch { peeks = new Map(); } } return peeks; };
  const peekSet = (u) => peekMap().get(u.id) || new Set();
  function addPeek(u, id) {
    const t = store.get('tasks', String(id));
    if (!ownOnly(u) || !t || inInactive(t)) return null;
    const pid = taskProject(t);
    if (isFreelancer(u) && pid && !projectSet(u).has(pid)) return null;    // freelancers: only within their clients
    const set = new Set([...peekSet(u)].filter((x) => x !== t.id)); set.add(t.id);
    peekMap().set(u.id, new Set([...set].slice(-100)));
    store.kv.set('peeks', JSON.stringify(Object.fromEntries([...peekMap()].map(([k, v]) => [k, [...v]]))));
    seenCache = { rev: -1, map: new Map() };
    return t;
  }
  let seenCache = { rev: -1, map: new Map() };
  // what this person may see: { tasks, projects, clients } (sets of ids), worked out once per data revision
  function ownView(u) {
    const rev = store.rev();
    if (seenCache.rev !== rev) seenCache = { rev, map: new Map() };
    if (seenCache.map.has(u.id)) return seenCache.map.get(u.id);
    const all = store.list('tasks');
    const direct = new Set(all.filter((t) => partOf(t, u.id)).map((t) => t.id));
    const tasks = new Set(direct);
    all.forEach((t) => {
      if (!t.parentId) return;
      if (direct.has(t.id)) tasks.add(String(t.parentId));          // the task a subtask of theirs sits under
      if (direct.has(String(t.parentId))) tasks.add(t.id);          // the subtasks of a task of theirs
    });
    const byId = new Map(all.map((t) => [t.id, t]));
    const allowed = isFreelancer(u) ? projectSet(u) : null;
    const projects = new Set();
    for (const id of [...tasks]) {
      const pid = taskProject(byId.get(id));
      if (pid && allowed && !allowed.has(pid)) { tasks.delete(id); continue; }
      if (pid) projects.add(pid);
    }
    const clients = new Set(store.list('projects').filter((p) => projects.has(p.id) && p.clientId).map((p) => p.clientId));
    const linked = new Set(store.list('projects').filter((p) => p.clientId).map((p) => p.clientId));
    // opened from a link: the task and its client's name and statuses come along (not its Client Assets)
    const peek = new Set();
    for (const id of peekSet(u)) {
      const t = byId.get(id);
      if (!t || tasks.has(id)) continue;
      const pid = taskProject(t);
      if (isFreelancer(u) && pid && !projectSet(u).has(pid)) continue;
      peek.add(id); tasks.add(id); if (pid) projects.add(pid);
    }
    const out = { tasks, projects, clients, linked, peek };
    seenCache.map.set(u.id, out);
    return out;
  }
  function taskVisible(u, t) {
    if (inInactive(t)) return false;
    if (!ownOnly(u)) return true;
    if (!t) return false;
    // (or a change in flight: the task as it's being saved)
    if (!ownView(u).tasks.has(String(t.id)) && !partOf(t, u.id)) return false;
    const pid = taskProject(t);
    return !pid || !isFreelancer(u) || projectSet(u).has(pid);
  }
  const projectVisible = (u, p) => !ownOnly(u) || ownView(u).projects.has(p.id) || (isFreelancer(u) && projectSet(u).has(p.id));
  // Client Assets: their clients' folders; for Production also folders not linked to any client
  const clientVisible = (u, c) => !ownOnly(u) || ownView(u).clients.has(c.id) || (isFreelancer(u) ? clientSet(u).has(c.id) : !ownView(u).linked.has(c.id));

  // Freelancers see the Client Assets of the clients their projects belong to
  // Client Assets: anyone adds folders and files; people remove (or rename) only the folders and files they added,
  // Account Managers anyone's; the folders made with the client stay unless an Admin removes them.
  // Name and logo: Admins and Account Managers.
  const AUTO_FOLDERS = ['Logos', 'Brand Guidelines', 'Fonts', 'Files'];
  const isAutoFolder = (c, f) => !!f.auto || (AUTO_FOLDERS.includes(f.name) && (!f.createdBy || f.createdBy === c.createdBy) && Math.abs(Date.parse(f.createdAt || 0) - Date.parse(c.createdAt || 0)) < 60000);
  // the client's own Files folder: it holds sub-folders (one per job, and the final files), not loose files
  const isFilesTop = (f, c) => !!f && !f.parentId && f.name === 'Files' && (!!f.auto || (!!c && isAutoFolder(c, f)));
  // Folders inside Files go up to 5 levels deep (Files › 1 › 2 › 3 › 4 › 5); each holds files and folders, the 5th files
  // only; final-files folders hold no folders
  const MAX_DEPTH = 5;
  function folderChain(list, f) {                                  // [f, its parent, …, the top folder] (null: broken / a loop)
    const byId = new Map(list.map((x) => [x.id, x]));
    const out = [];
    for (let x = f; x; x = x.parentId ? byId.get(x.parentId) : null) {
      if (out.includes(x) || out.length > MAX_DEPTH + 1) return null;
      out.push(x);
      if (x.parentId && !byId.has(x.parentId)) return null;
    }
    return out;
  }
  function clientEditOk(u, manager, base, current, next) {
    if (!next) return false;
    // (anyone may fill in a missing logo — the first image in Logos — but only Admins and AMs change one)
    const firstLogo = !base.logo && !current.logo && !!next.logo && next.logoAuto === true;
    const changed = (k) => !deepEqual(next[k] ?? null, base[k] ?? null) && !deepEqual(next[k] ?? null, current[k] ?? null);
    if (changed('dir')) return false;
    if (changed('name') && current.createdBy !== u.id) return false;   // its name: Admins (checked before), or whoever created it
    if (!manager && !firstLogo && ['logo', 'logoAuto'].some((k) => !deepEqual(next[k] ?? null, base[k] ?? null) && !deepEqual(next[k] ?? null, current[k] ?? null))) return false;
    // judged against what this person's app last saw (base): what they removed or renamed; others' new folders and
    // files from the meantime are kept by the merge
    const was = new Map((base.folders || []).map((f) => [f.id, f]));
    const now = new Map((next.folders || []).map((f) => [f.id, f]));
    for (const [id, f] of was) {
      const n = now.get(id);
      // Account Managers look after anyone's folders and files; others only their own. Folders made with the client: Admins.
      const mine = !isAutoFolder(base, f) && (manager || f.createdBy === u.id);
      if (!n) {                                                     // folder removed
        if (!mine || (!manager && (f.files || []).some((a) => a.addedBy !== u.id))) return false;
        continue;
      }
      if (n.name !== f.name && !mine) return false;                 // renamed: only your own
      if (n.dir !== f.dir || !!n.auto !== !!f.auto || n.createdBy !== f.createdBy || (n.parentId || null) !== (f.parentId || null) || (n.finalOf || null) !== (f.finalOf || null)) return false;
      // final files are filed by the app: nobody adds or removes them by hand; Files holds folders, not loose files
      const curF = (current.folders || []).find((x) => x.id === id);
      const had = new Set([...(f.files || []), ...((curF && curF.files) || [])].map((a) => a.id));
      const added = (n.files || []).some((a) => !had.has(a.id));
      if (added && (f.finalOf || isFilesTop(f, base))) return false;
      if (f.finalOf && (f.files || []).some((a) => !(n.files || []).some((x) => x.id === a.id))) return false;
      const keep = new Set((n.files || []).map((a) => a.id));
      if (!manager && (f.files || []).some((a) => !keep.has(a.id) && a.addedBy !== u.id)) return false;   // only your own files go
    }
    const there = new Set((current.folders || []).map((f) => f.id));
    for (const [id, n] of now) {
      if (was.has(id) || there.has(id)) continue;
      if (n.createdBy !== u.id || n.auto || n.finalOf) return false; // a new folder is yours
      if (!n.parentId && !manager) return false;                    // a folder on the client's main page: Admins and AMs
      if (n.parentId) {                                             // a folder inside Files, up to 5 levels deep
        const chain = folderChain(next.folders || [], n);
        if (!chain || chain.length > MAX_DEPTH + 1 || !isFilesTop(chain[chain.length - 1], current)) return false;
        if (chain.slice(1).some((x) => x.finalOf)) return false;    // (nothing inside final files)
      }
    }
    return true;
  }
  function clientSet(u) {
    const ids = projectSet(u);
    return new Set(store.list('projects').filter((p) => ids.has(p.id) && p.clientId).map((p) => p.clientId));
  }
  // Can this person open this file? Freelancers only get files from their tasks and their clients.
  function canReadFile(u, rel) {
    const parts = String(rel).split('/');
    // Expense claims (receipts, signatures, claim PDFs): the person who claims, and Finance
    if (parts[0] === 'Claims') return parts[1] === u.id || !!finLevel(u);
    // Invoices and other finance records: Finance people and Admins only
    if (parts[0] === 'Finance') return !!finLevel(u);
    if (isFinance(u)) return (parts[0] === 'attachments' && parts[1] === '_avatars') || (parts[0] === 'Clients' && parts[1] === '_logos') || parts[0] === '.thumbs';
    // files of an inactive client: its tasks' attachments and its Client Assets
    if (parts[0] === 'attachments' && parts[1] && parts[1][0] !== '_') { const t = store.get('tasks', parts[1]); if (t && inInactive(t)) return false; }
    if (parts[0] === 'Clients' && parts[1] && parts[1] !== '_logos') {
      const dir = parts.slice(0, 2).join('/');
      const off = inactiveIds();
      if (off.size && store.list('clients').some((c) => (c.dir === dir || String(c.dir || '').startsWith(dir + '/')) && hiddenClient(c, off))) return false;
    }
    if (!ownOnly(u)) return true;
    if (parts[0] === 'attachments') {
      if (parts[1] === '_avatars') return true;
      if (parts[1] === '_uploads') return false;
      const t = store.get('tasks', parts[1]);
      // (also the files of your own scheduled comment, e.g. after its task was deleted)
      return (!!t && taskVisible(u, t)) || store.list('scheduled').some((s) => s.authorId === u.id && (s.attachments || []).some((a) => a.path === rel || a.thumb === rel));
    }
    if (parts[0] === 'Clients') {
      if (parts[1] === '_logos') return true;
      const dir = parts.slice(0, 2).join('/');
      return store.list('clients').some((c) => clientVisible(u, c) && (c.dir === dir || String(c.dir || '').startsWith(dir + '/')));
    }
    if (parts[0] === '.thumbs') return true; // previews are small and only reachable by id
    return false;
  }

  function canSee(u, kind, data) {
    if (!data) return true;
    switch (kind) {
      case 'notifications': return data.to === u.id && !(isOffice(u) && data.taskId) && !(data.taskId && inInactive(store.get('tasks', String(data.taskId)))) && !(data.clientId && hiddenClient(store.get('clients', String(data.clientId))));
      case 'projects': return projectVisible(u, data);
      case 'tasks': return isOffice(u) ? !!finLevel(u) && !inInactive(data) : taskVisible(u, data);
      case 'clients': return !hiddenClient(data) && clientVisible(u, data);
      case 'trash': return isOffice(u) ? CA_TRASH.has(data.type) : isAdm(u) || u.role === 'am';   // the Trash is for Admins and Account Managers (Office Admins: Client Assets items)
      case 'finance': return !!finLevel(u) || (data.type === 'reimb' && data.userId === u.id);   // (Admins too: only with Finance access)    // expense records (people see their own reimbursements)
      // expense claims: your own, and Finance sees everything except drafts and "submitted offline"
      case 'claims': return data.userId === u.id || (!!finLevel(u) && !['draft', 'offline'].includes(data.state));
      case 'plans': return planVisible(u, data);
      case 'scheduled': return data.authorId === u.id;   // a scheduled comment: only its author, until it's sent
      default: return true;
    }
  }

  function shape(u, kind, data) {
    if (kind === 'tasks' && data && (isFinance(u) || isOffice(u))) {
      const out = {};
      TASK_FOR_FINANCE.forEach((k) => { if (data[k] !== undefined) out[k] = data[k]; });
      return out;
    }
    if (kind === 'clients' && data && isFinance(u)) return { id: data.id, name: data.name, logo: data.logo || null };
    if (kind !== 'users' || !data) return data;
    const out = { ...data };
    SECRET_USER_FIELDS.forEach((k) => delete out[k]);
    if (!u || out.id !== u.id) delete out.bday;   // (a birthday is only in its owner's app; the server tells the team on the day)
    // Owner view (live site): the owner's own app sees them with Admin rights and Finance Admin; stored as it was, nobody else sees it
    if (u && u._ov && out.id === u.id) { out.admin = true; out.fin = 'admin'; }
    return out;
  }

  // ctx.restoring: the items this same save puts back (so a Trash entry may be cleared as it's restored)
  function canWrite(u, ch, current, ctx = {}) {
    const admin = isAdm(u);
    const manager = admin || u.role === 'am';
    const next = ch.del ? null : ch.data;
    if (ch.kind === 'finance') return finLevel(u) === 'admin';
    if (ch.kind === 'claims') return canWriteClaim(u, ch, current);
    if (isFinance(u)) {
      // Finance tells people their claim is approved or paid
      if (ch.kind === 'notifications' && !ch.del && !current && next && next.from === u.id && /^claim/.test(String(next.kind || ''))) return true;
      if (ch.kind === 'users') return !ch.del && String(ch.id) === u.id && !!current && PROTECTED_USER_FIELDS.every((k) => deepEqual(next[k], current[k]));
      if (ch.kind === 'notifications') return !ch.del ? !!current && current.to === u.id : !current || current.to === u.id;
      return false; // tasks (including their Finance status) are changed by Account Managers and Admins
    }
    switch (ch.kind) {
      case 'users':
        if (ch.del) return false;                                   // people are deactivated, never deleted
        // the owner's account: only the owner changes its role, rights, email, clients or active state
        if (current && isOwnerUser(current) && !isOwnerUser(u)) return PROTECTED_USER_FIELDS.every((k) => deepEqual(next[k] ?? null, (ch.base ? ch.base[k] : current[k]) ?? null) || deepEqual(next[k] ?? null, current[k] ?? null)) && admin;
        if (!current && isOwnerUser(next) && !isOwnerUser(u)) return false;    // nobody else makes an account with the owner's email
        if (current && next && isOwnerUser(next) && !isOwnerUser(current) && !isOwnerUser(u)) return false;   // ...or changes someone's email to it
        if (admin) return true;
        if (String(ch.id) !== u.id || !current) return false;      // only your own account
        // you may edit your own profile, but not your role, email, access or projects
        return PROTECTED_USER_FIELDS.every((k) => deepEqual(next[k], ch.base ? ch.base[k] : current[k]) || deepEqual(next[k], current[k]));
      case 'meta':
        // only Admins send a general announcement
        if (!admin && next && !deepEqual(next.announcement ?? null, (ch.base !== undefined ? (ch.base || {}).announcement : current && current.announcement) ?? null)) return false;
        // ...and pick the Social Manager
        if (!admin && next && !deepEqual(next.socialMgrIds ?? null, (ch.base !== undefined ? (ch.base || {}).socialMgrIds : current && current.socialMgrIds) ?? null) && !deepEqual(next.socialMgrIds ?? null, (current && current.socialMgrIds) ?? null)) return false;
        return manager;
      case 'statuses':
        return manager;
      case 'clients': {
        if (ch.del) return admin;                                   // only Admins delete a client's main folder
        if (!current) return manager;                               // a new client (Admins make them with a new client)
        if (admin) return true;
        if (isFreelancer(u)) return false;                          // freelancers only look at Client Assets
        if (!clientVisible(u, current)) return false;
        return clientEditOk(u, manager, ch.base !== undefined && ch.base ? ch.base : current, current, next);
      }
      case 'projects':
        if (isOffice(u)) return false;                              // Office Admins don't add or change clients
        if (isFreelancer(u)) return !ch.del && !!current && projectSet(u).has(current.id) && next.id === current.id;
        if (ch.del || !current || admin) return admin;              // only Admins add or remove a client
        if (!projectVisible(u, current)) return false;
        // and only Admins change one (name, colour, statuses, Client Assets link); others may switch List / Board
        return ['name', 'color', 'sections', 'clientId', 'ams', 'socials', 'inactive'].every((k) => deepEqual(next[k] ?? null, (ch.base !== undefined && ch.base ? ch.base[k] : current[k]) ?? null) || deepEqual(next[k] ?? null, current[k] ?? null));
      case 'tasks': {
        // a task's Finance status is set by Account Managers and Admins only
        const was = ch.base !== undefined ? ch.base : current;
        // Office Admins: only a job's Finance status (with Finance access), nothing else on tasks
        if (isOffice(u)) return !ch.del && !!current && !!next && finLevel(u) === 'admin' && Object.keys({ ...current, ...next }).every((k) => ['finance', 'financeAt', 'financeBy', 'updatedAt'].includes(k) || deepEqual(next[k] ?? null, (was || {})[k] ?? null) || deepEqual(next[k] ?? null, current[k] ?? null));
        if (!manager && next && !deepEqual(next.finance ?? null, (was && was.finance) ?? null)) return false;
        if ((current && inInactive(current)) || (next && inInactive(next))) return false;   // an inactive client's tasks are frozen
        if (current && next && !cdGateOk(current, next)) return false;
        if (current && next && !identityOk(current, next, ch.base)) return false;
        if (current && next && !editWindowOk(current, next, ch.base)) return false;
        if (isFreelancer(u)) return (!current || taskVisible(u, current)) && (ch.del || taskVisible(u, next));
        if (ownOnly(u) && current && !taskVisible(u, current)) return false;
        if (ownOnly(u) && current && ownView(u).peek.has(String(current.id))) return commentOnly(u, ch.base || current, current, next);
        return true;
      }
      case 'trash': {
        // Office Admins: Client Assets items only — put there when deleting, taken out when restoring (never deleted forever)
        if (isOffice(u)) {
          if (!ch.del) return !current && !!next && CA_TRASH.has(next.type) && next.deletedBy === u.id;
          return !!current && CA_TRASH.has(current.type) && !!current.key && !!(ctx.restoring && ctx.restoring.has(current.key));
        }
        // anyone's deletions land here; only Admins and Account Managers look after it
        if (!ch.del) return !current ? manager || (!!next && next.deletedBy === u.id) : manager;
        if (!current || admin) return true;                          // only Admins delete forever
        if (!manager) return false;
        const old = Date.now() - Date.parse(current.deletedAt || 0) > 30 * 86400000;
        return old || (!!current.key && !!(ctx.restoring && ctx.restoring.has(current.key)));
      }
      case 'plans': {
        if (!opts.plans || !planVisible(u, current || next)) return false;
        const pl = current || next || {};
        const pid = pl.projectId;
        if (current && next && (next.projectId !== current.projectId || next.month !== current.month)) return false;   // a plan stays with its client and month
        const editor = planEditor(u, pid);
        // approvers: the Creative Director, and the Social Manager for a skeleton they didn't make
        const approver = u.id === cdId() || (isSocialMgr(u) && pl.createdBy !== u.id);
        const editable = (st) => !st || st === 'draft' || st === 'changes';
        if (!current) {
          if (!editor || !next || !pid || !/^\d{4}-\d{2}$/.test(String(next.month || '')) || next.createdBy !== u.id || !editable(next.status)) return false;
          if (String(next.month) < new Date(Date.now() + 4 * 3600000).toISOString().slice(0, 7)) return false;   // (never for a month that's over: Dubai's month)
          // (what the steps and the server write later starts empty: exports, filing, the client round, approval, tasks)
          const blank = (v) => v == null || (Array.isArray(v) && !v.length);
          if (!['exports', 'filedDeck', 'clientApproved', 'sent', 'approval', 'tasksAt', 'review'].every((k) => blank(next[k]))) return false;
          if (!(Array.isArray(next.posts) || next.posts == null) || (next.posts || []).some((y) => !y || y.taskId || y.client || y.check)) return false;
          return !store.list('plans').some((x) => x.id !== String(ch.id) && x.projectId === pid && x.month === next.month);   // one plan per client per month
        }
        if (ch.del) return editor && editable(current.status);
        // tasks are made from an approved skeleton by Social, the CD, the client's Account Managers or Admins
        const maker = planMaker(u, pl);
        if (!editor && !approver && !maker) return false;
        const from = current.status || 'draft', to = next.status || 'draft';
        const base = ch.base && typeof ch.base === 'object' ? ch.base : null;
        // unchanged: the same as now, or as the copy this save was made from (the server writes exports, filing and the client's approval itself)
        const same = (f) => deepEqual(f(next), f(current)) || (!!base && deepEqual(f(next), f(base)));
        const tasksOf = (x) => (x.posts || []).filter((y) => y.taskId).map((y) => [y.id, y.taskId]);
        if (!same(tasksOf) || !same((x) => x.tasksAt ?? null)) {
          if (!maker || from !== 'approved' || to !== 'approved') return false;
        }
        // the client round: the client's reply per post and the whole plan's approval (the exports are written by the server)
        const clientOf = (x) => [x.clientApproved || null, x.sent || null, (x.posts || []).filter((y) => y.client).map((y) => [y.id, y.client])];
        if (!same(clientOf) && (!maker || from !== 'approved' || to !== 'approved')) return false;
        if (!same((x) => x.exports ?? null) || !same((x) => x.filedDeck ?? null)) return false;
        if (from === 'approved' && to === 'draft' && (current.posts || []).some((y) => y.taskId)) return false;   // (tasks made: it stays approved)
        // the steps: send (Social) · take back (Social) · approve or send back (approver) · reopen an approved one (either)
        if (from !== to) {
          const ok = (editable(from) && to === 'review' && editor) || (from === 'review' && to === 'draft' && editor)
            || (from === 'review' && (to === 'approved' || to === 'changes') && approver) || (from === 'approved' && to === 'draft' && (editor || approver));
          if (!ok) return false;
        }
        // the posts themselves: Social, while it's a draft or sent back
        const bare = (x) => ({ ...x, status: null, review: null, approval: null, log: null, round: null, updatedAt: null, tasksAt: null, clientApproved: null, exports: null, filedDeck: null, sent: null, posts: (x.posts || []).map(({ check, updatedAt, taskId, client, ...r }) => r) });
        if (!deepEqual(bare(next), bare(current)) && !(editor && editable(from))) return false;
        // the approver's marks on posts (Social may only clear them)
        const was = new Map((current.posts || []).map((x) => [x.id, x.check || null]));
        for (const x of next.posts || []) if (x.check && !deepEqual(x.check, was.get(x.id) || null) && !approver) return false;
        if (!same((x) => x.approval || null) && !approver && !(from === 'approved' && to === 'draft')) return false;
        // (making tasks only: nothing else changes)
        if (!editor && !approver && (from !== to || !same((x) => x.log || null) && !(next.log || []).slice((current.log || []).length).every((x) => ['tasks', 'client', 'client-approved', 'client-sent'].includes(x.act)))) return false;
        return true;
      }
      case 'scheduled': {
        // your own scheduled comments: made on a task you can comment on; changed while waiting; the server sends or cancels them
        const mine = (x) => !!x && x.authorId === u.id;
        if (ch.del) return mine(current);
        if (!mine(next) || (current && !mine(current))) return false;
        if (!current) {
          if (isOffice(u) || next.state !== 'waiting' || !Date.parse(next.sendAt)) return false;
          const t = store.get('tasks', String(next.taskId || ''));
          if (!t || t.done || inInactive(t)) return false;
          return canSee(u, 'tasks', t) || (ownOnly(u) && ownView(u).peek.has(String(t.id)));
        }
        if (current.state === 'waiting') return next.state === 'waiting' && next.taskId === current.taskId && !!Date.parse(next.sendAt);
        const rest = ({ drafted, ...r }) => r;   // a sent or cancelled one: only marked as taken back into a draft
        return deepEqual(rest(next), rest(current));
      }
      case 'notifications':
        if (ch.del) return !current || current.to === u.id;
        if (!current) return true;
        return current.to === u.id || current.from === u.id;
      default:
        return true;
    }
  }

  // Once a task first goes for CD review its name, description and client (and its subtasks' names) are locked for
  // everyone, so it can't be turned into another job; pinned brief updates (comments) can't be edited either
  function idLocked(t) {
    const root = t && t.parentId ? store.get('tasks', String(t.parentId)) || t : t;
    return !!root && (!!root.lockedAt || (root.reviews || []).length > 0);
  }
  function identityOk(current, next, base) {
    if (!idLocked(current)) return true;
    const was = base && typeof base === 'object' ? base : current;
    const changed = (a, b, k) => !deepEqual(a[k] ?? null, b[k] ?? null);
    const edited = (k) => changed(next, current, k) && changed(next, was, k);
    if (['title', 'notes', 'notesHtml'].some(edited)) return false;
    if (!current.parentId && edited('projectId')) return false;
    if (current.lockedAt && !next.lockedAt) return false;
    const pinned = new Set((current.briefPins || []).map((p) => p.cid));
    if (pinned.size) {
      const now = new Map((current.comments || []).map((c) => [c.id, c]));
      const old = new Map(((was.comments) || []).map((c) => [c.id, c]));
      for (const c of next.comments || []) {
        if (!pinned.has(c.id) || !now.has(c.id)) continue;
        const a = now.get(c.id), b = old.get(c.id) || a;
        if ((changed(c, a, 'text') && changed(c, b, 'text')) || (changed(c, a, 'html') && changed(c, b, 'html'))) return false;
      }
    }
    return true;
  }

  // A comment's words can be changed for 10 minutes after it was sent (everyone, Admins too; web/app.js EDIT_WINDOW).
  // A few minutes' grace covers a save that took a while to arrive. Only the words count: deleting it, reactions,
  // files' previews, link cards and "seen" marks aren't edits.
  const EDIT_WINDOW = 10 * 60000, EDIT_GRACE = 3 * 60000;
  function editWindowOk(current, next, base) {
    const was = base && typeof base === 'object' ? base : current;
    const now = new Map((current.comments || []).map((c) => [c.id, c]));
    const old = new Map((was.comments || []).map((c) => [c.id, c]));
    const changed = (a, b, k) => String(a[k] || '') !== String(b[k] || '');
    for (const c of next.comments || []) {
      const a = now.get(c.id);
      if (!a) continue;
      const b = old.get(c.id) || a;
      const edited = ['text', 'html'].some((k) => changed(c, a, k) && changed(c, b, k));
      if (edited && Date.now() - Date.parse(a.at) > EDIT_WINDOW + EDIT_GRACE) return false;
    }
    return true;
  }

  // CD review on and the files not approved: the task doesn't move past Review (CTR, Done or later) or get completed —
  // also with nobody assigned. Only a task done by the CD alone needs no approval. Switching CD review off is the way out.
  const isDoneName = (n) => /^(done|complete|completed)$/i.test(String(n || '').trim());
  function pastReview(t, sectionId) {
    const p = t.projectId && store.get('projects', String(t.projectId));
    const list = (p && p.sections) || store.list('statuses');
    const to = list.findIndex((x) => x.id === sectionId), sec = list[to];
    if (!sec) return false;
    if (/^ctr$/i.test(String(sec.name).trim()) || isDoneName(sec.name)) return true;
    const rv = list.findIndex((x) => /^(internal )?review$/i.test(String(x.name).trim()));
    return rv >= 0 && to > rv;
  }
  function cdGateOk(current, next) {
    if (next.parentId || !next.needsCD || next.cdStatus === 'approved') return true;
    const cd = (store.get('meta', 'main') || {}).cdUserId || null;
    const people = next.assignees || [];
    if (people.length && people.every((id) => id === cd)) return true;
    if (next.done && !current.done) return false;
    if (next.sectionId !== current.sectionId && pastReview(next, next.sectionId) && !pastReview(current, current.sectionId)) return false;
    return true;
  }

  // a view-only task: only comments change — your own added, edited or removed, and reactions on anyone's
  function commentOnly(u, base, current, next) {
    if (!next) return false;
    const FREE = ['comments', 'activity', 'updatedAt'];
    // (a preview image the app made for a file — e.g. a video's thumbnail — isn't a change to the task)
    const noThumbs = (v) => (Array.isArray(v) ? v.map((a) => { if (!a || typeof a !== 'object') return a; const { thumb, ...rest } = a; return rest; }) : v);
    const same = (k, a, b) => deepEqual(k === 'attachments' ? noThumbs(a ?? null) : a ?? null, k === 'attachments' ? noThumbs(b ?? null) : b ?? null);
    const keys = new Set([...Object.keys(next), ...Object.keys(current)]);
    for (const k of keys) if (!FREE.includes(k) && !same(k, next[k], base[k]) && !same(k, next[k], current[k])) return false;
    const was = new Map((base.comments || []).map((c) => [c.id, c]));
    const now = new Map((next.comments || []).map((c) => [c.id, c]));
    const strip = (c) => { const { reactions, ...rest } = c; return rest; };
    for (const [id, c] of was) {
      if (c.authorId === u.id) continue;
      const n = now.get(id);
      if (!n) { if ((current.comments || []).some((x) => x.id === id)) return false; continue; }
      if (!deepEqual(strip(n), strip(c))) return false;
    }
    for (const [id, n] of now) if (!was.has(id) && !(current.comments || []).some((x) => x.id === id) && n.authorId !== u.id) return false;
    return true;
  }

  // A month's claims close on the 28th (Dubai time): after that it can't be submitted or changed by the person
  const monthClosed = (m, now = new Date()) => { const today = now.toLocaleDateString('en-CA', { timeZone: 'Asia/Dubai' }); return today >= `${m}-28`; };
  const CLAIM_CONTENT = ['userId', 'month', 'groups', 'total', 'signature', 'submittedAt', 'createdAt'];
  const CLAIM_FINANCE = ['approvedAt', 'approvedBy', 'paidOn', 'paidBy', 'reimbId'];
  function canWriteClaim(u, ch, current) {
    const next = ch.del ? null : ch.data;
    const own = (current ? current.userId : next && next.userId) === u.id;
    // a Finance Admin marking their own claim HR approved / paid: the same Finance rules as anyone else's claim
    const financeMove = finLevel(u) === 'admin' && !ch.del && !!current && !!next && (next.state !== current.state || CLAIM_FINANCE.some((k) => !deepEqual(next[k] ?? null, current[k] ?? null)))
      && ['approved', 'paid'].includes(next.state);
    if (own && !financeMove) {
      if (ch.del) return !!current && current.state === 'draft';
      if (!next || next.userId !== u.id || !/^\d{4}-\d{2}$/.test(String(next.month || ''))) return false;
      if (!['draft', 'submitted', 'none', 'offline'].includes(next.state)) return !!current && current.state === next.state && CLAIM_CONTENT.every((k) => deepEqual(next[k], current[k])) && CLAIM_FINANCE.every((k) => deepEqual(next[k], current[k]));
      if (current && ['approved', 'paid'].includes(current.state)) return false;      // locked once HR approved
      if (monthClosed(next.month) && !(current && deepEqual(next, current))) return false;
      return CLAIM_FINANCE.every((k) => deepEqual(next[k] ?? null, current ? current[k] ?? null : null));
    }
    // Finance Admins mark claims HR approved / paid; nothing else changes
    if (finLevel(u) !== 'admin' || ch.del || !current || !next) return false;
    if (!['submitted', 'approved', 'paid'].includes(next.state) || ['draft', 'offline', 'none'].includes(current.state)) return false;
    return CLAIM_CONTENT.every((k) => deepEqual(next[k], current[k]));
  }

  return { isSocialMgr, planEditor, planMaker, userByEmail, isOwnerUser, isOffice, isSuper, canSee, canWrite, shape, ownOnly, ownView, addPeek, isFreelancer, isFinance, isAdm, finLevel, canReadFile, monthClosed };
}
