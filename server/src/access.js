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

  function taskVisible(u, t) {
    if (!isFreelancer(u)) return true;
    if (!t) return false;
    if (t.projectId) return projectSet(u).has(t.projectId);
    return (t.assignees || []).includes(u.id) || t.createdBy === u.id;
  }

  // Freelancers see the Client Assets of the clients their projects belong to
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
      case 'notifications': return data.to === u.id;
      case 'projects': return !isFreelancer(u) || projectSet(u).has(data.id);
      case 'tasks': return taskVisible(u, data);
      case 'clients': return !isFreelancer(u) || clientSet(u).has(data.id);
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
      case 'clients':
        if (isFreelancer(u)) return false;
        if (ch.del) return admin;                                   // only Admins delete a client
        return manager;                                             // Admins + Account Managers manage Client Assets
      case 'projects':
        if (isFreelancer(u)) return !ch.del && !!current && projectSet(u).has(current.id) && next.id === current.id;
        if (ch.del || !current || admin) return admin;              // only Admins add or remove a client
        // and only Admins change one (name, colour, statuses, Client Assets link); others may switch List / Board
        return ['name', 'color', 'sections', 'clientId'].every((k) => deepEqual(next[k] ?? null, (ch.base !== undefined && ch.base ? ch.base[k] : current[k]) ?? null) || deepEqual(next[k] ?? null, current[k] ?? null));
      case 'tasks': {
        // a task's Finance status is set by Account Managers and Admins only
        const was = ch.base !== undefined ? ch.base : current;
        if (!manager && next && !deepEqual(next.finance ?? null, (was && was.finance) ?? null)) return false;
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
