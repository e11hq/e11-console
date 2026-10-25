// Who can see and change what. The interface already hides buttons people can't use; these
// checks make the server enforce the important rules too (especially for freelancers).
import { deepEqual } from './merge.js';

const SECRET_USER_FIELDS = ['hash', 'salt'];
// Fields only an Admin may change on a person's account
const PROTECTED_USER_FIELDS = ['role', 'active', 'email', 'projectIds', 'admin', 'fin'];

export function createAccess(store) {
  const users = () => store.list('users');
  const userByEmail = (email) => users().find((u) => u.active !== false && String(u.email || '').toLowerCase() === String(email || '').toLowerCase()) || null;
  const isFreelancer = (u) => u && u.role === 'freelancer';
  // Finance people (Finance Admin / Finance Viewer) only use the Finance pages: they see projects and a
  // slim copy of each task (name, project, status, dates, Finance status) — no comments, files or people's work.
  const isFinance = (u) => !!u && (u.role === 'finance_admin' || u.role === 'finance_viewer');
  const TASK_FOR_FINANCE = ['id', 'title', 'projectId', 'sectionId', 'parentId', 'done', 'completedAt', 'due', 'createdAt', 'updatedAt', 'finance', 'financeAt', 'financeBy', 'order'];
  // Admin rights: the Admin role, or another role given Admin rights on top. Finance access: Finance-only
  // people, or anyone given Finance Admin / Finance Viewer on top of their role (u.fin).
  const isAdm = (u) => !!u && (u.role === 'admin' || u.admin === true);
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
  function taskVisible(u, t) {
    if (inInactive(t)) return false;
    if (!isFreelancer(u)) return true;
    if (!t) return false;
    if (t.projectId) return projectSet(u).has(t.projectId);
    return (t.assignees || []).includes(u.id) || t.createdBy === u.id;
  }

  // Freelancers see the Client Assets of the clients their projects belong to
  // Client Assets: anyone adds folders and files; people remove (or rename) only the folders and files they added,
  // Account Managers anyone's; the folders made with the client stay unless an Admin removes them.
  // Name and logo: Admins and Account Managers.
  const AUTO_FOLDERS = ['Logos', 'Brand Guidelines', 'Fonts', 'Files'];
  const isAutoFolder = (c, f) => !!f.auto || (AUTO_FOLDERS.includes(f.name) && (!f.createdBy || f.createdBy === c.createdBy) && Math.abs(Date.parse(f.createdAt || 0) - Date.parse(c.createdAt || 0)) < 60000);
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
      if (n.dir !== f.dir || !!n.auto !== !!f.auto || n.createdBy !== f.createdBy) return false;
      const keep = new Set((n.files || []).map((a) => a.id));
      if (!manager && (f.files || []).some((a) => !keep.has(a.id) && a.addedBy !== u.id)) return false;   // only your own files go
    }
    const there = new Set((current.folders || []).map((f) => f.id));
    for (const [id, n] of now) {
      if (was.has(id) || there.has(id)) continue;
      if (n.createdBy !== u.id || n.auto) return false;             // a new folder is yours
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
    if (parts[0] === 'Finance') return !!finLevel(u) || isAdm(u);
    if (isFinance(u)) return (parts[0] === 'attachments' && parts[1] === '_avatars') || (parts[0] === 'Clients' && parts[1] === '_logos') || parts[0] === '.thumbs';
    // files of an inactive client: its tasks' attachments and its Client Assets
    if (parts[0] === 'attachments' && parts[1] && parts[1][0] !== '_') { const t = store.get('tasks', parts[1]); if (t && inInactive(t)) return false; }
    if (parts[0] === 'Clients' && parts[1] && parts[1] !== '_logos') {
      const dir = parts.slice(0, 2).join('/');
      const off = inactiveIds();
      if (off.size && store.list('clients').some((c) => (c.dir === dir || String(c.dir || '').startsWith(dir + '/')) && hiddenClient(c, off))) return false;
    }
    if (!isFreelancer(u)) return true;
    if (parts[0] === 'attachments') {
      if (parts[1] === '_avatars') return true;
      if (parts[1] === '_uploads') return false;
      const t = store.get('tasks', parts[1]);
      return !!t && taskVisible(u, t);
    }
    if (parts[0] === 'Clients') {
      if (parts[1] === '_logos') return true;
      const dir = parts.slice(0, 2).join('/');
      const allowed = clientSet(u);
      return store.list('clients').some((c) => allowed.has(c.id) && (c.dir === dir || String(c.dir || '').startsWith(dir + '/')));
    }
    if (parts[0] === '.thumbs') return true; // previews are small and only reachable by id
    return false;
  }

  function canSee(u, kind, data) {
    if (!data) return true;
    switch (kind) {
      case 'notifications': return data.to === u.id && !(data.taskId && inInactive(store.get('tasks', String(data.taskId)))) && !(data.clientId && hiddenClient(store.get('clients', String(data.clientId))));
      case 'projects': return !isFreelancer(u) || projectSet(u).has(data.id);
      case 'tasks': return taskVisible(u, data);
      case 'clients': return !hiddenClient(data) && (!isFreelancer(u) || clientSet(u).has(data.id));
      case 'trash': return isAdm(u) || u.role === 'am';   // the Trash is for Admins and Account Managers
      case 'finance': return !!finLevel(u) || isAdm(u) || (data.type === 'reimb' && data.userId === u.id);    // expense records (people see their own reimbursements)
      // expense claims: your own, and Finance sees everything except drafts and "submitted offline"
      case 'claims': return data.userId === u.id || (!!finLevel(u) && !['draft', 'offline'].includes(data.state));
      default: return true;
    }
  }

  function shape(u, kind, data) {
    if (kind === 'tasks' && data && isFinance(u)) {
      const out = {};
      TASK_FOR_FINANCE.forEach((k) => { if (data[k] !== undefined) out[k] = data[k]; });
      return out;
    }
    if (kind === 'clients' && data && isFinance(u)) return { id: data.id, name: data.name, logo: data.logo || null };
    if (kind !== 'users' || !data) return data;
    const out = { ...data };
    SECRET_USER_FIELDS.forEach((k) => delete out[k]);
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
        if (admin) return true;
        if (String(ch.id) !== u.id || !current) return false;      // only your own account
        // you may edit your own profile, but not your role, email, access or projects
        return PROTECTED_USER_FIELDS.every((k) => deepEqual(next[k], ch.base ? ch.base[k] : current[k]) || deepEqual(next[k], current[k]));
      case 'meta':
        // only Admins send a general announcement
        if (!admin && next && !deepEqual(next.announcement ?? null, (ch.base !== undefined ? (ch.base || {}).announcement : current && current.announcement) ?? null)) return false;
        return manager;
      case 'statuses':
        return manager;
      case 'clients': {
        if (ch.del) return admin;                                   // only Admins delete a client's main folder
        if (!current) return manager;                               // a new client (Admins make them with a new client)
        if (admin) return true;
        if (isFreelancer(u)) return false;                          // freelancers only look at Client Assets
        return clientEditOk(u, manager, ch.base !== undefined && ch.base ? ch.base : current, current, next);
      }
      case 'projects':
        if (isFreelancer(u)) return !ch.del && !!current && projectSet(u).has(current.id) && next.id === current.id;
        if (ch.del || !current || admin) return admin;              // only Admins add or remove a client
        // and only Admins change one (name, colour, statuses, Client Assets link); others may switch List / Board
        return ['name', 'color', 'sections', 'clientId', 'ams', 'inactive'].every((k) => deepEqual(next[k] ?? null, (ch.base !== undefined && ch.base ? ch.base[k] : current[k]) ?? null) || deepEqual(next[k] ?? null, current[k] ?? null));
      case 'tasks': {
        // a task's Finance status is set by Account Managers and Admins only
        const was = ch.base !== undefined ? ch.base : current;
        if (!manager && next && !deepEqual(next.finance ?? null, (was && was.finance) ?? null)) return false;
        if ((current && inInactive(current)) || (next && inInactive(next))) return false;   // an inactive client's tasks are frozen
        if (isFreelancer(u)) return (!current || taskVisible(u, current)) && (ch.del || taskVisible(u, next));
        return true;
      }
      case 'trash': {
        // anyone's deletions land here; only Admins and Account Managers look after it
        if (!ch.del) return !current ? manager || (!!next && next.deletedBy === u.id) : manager;
        if (!current || admin) return true;                          // only Admins delete forever
        if (!manager) return false;
        const old = Date.now() - Date.parse(current.deletedAt || 0) > 30 * 86400000;
        return old || (!!current.key && !!(ctx.restoring && ctx.restoring.has(current.key)));
      }
      case 'notifications':
        if (ch.del) return !current || current.to === u.id;
        if (!current) return true;
        return current.to === u.id || current.from === u.id;
      default:
        return true;
    }
  }

  // A month's claims close on the 28th (Dubai time): after that it can't be submitted or changed by the person
  const monthClosed = (m, now = new Date()) => { const today = now.toLocaleDateString('en-CA', { timeZone: 'Asia/Dubai' }); return today >= `${m}-28`; };
  const CLAIM_CONTENT = ['userId', 'month', 'groups', 'total', 'signature', 'submittedAt', 'createdAt'];
  const CLAIM_FINANCE = ['approvedAt', 'approvedBy', 'paidOn', 'paidBy', 'reimbId'];
  function canWriteClaim(u, ch, current) {
    const next = ch.del ? null : ch.data;
    const own = (current ? current.userId : next && next.userId) === u.id;
    if (own) {
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

  return { userByEmail, canSee, canWrite, shape, isFreelancer, isFinance, isAdm, finLevel, canReadFile, monthClosed };
}
