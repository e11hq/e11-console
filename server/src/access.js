// Who can see and change what. The interface already hides buttons people can't use; these
// checks make the server enforce the important rules too (especially for freelancers).
import { deepEqual } from './merge.js';

const SECRET_USER_FIELDS = ['hash', 'salt'];
// Fields only an Admin may change on a person's account
const PROTECTED_USER_FIELDS = ['role', 'active', 'email', 'projectIds'];

export function createAccess(store) {
  const users = () => store.list('users');
  const userByEmail = (email) => users().find((u) => u.active !== false && String(u.email || '').toLowerCase() === String(email || '').toLowerCase()) || null;
  const isFreelancer = (u) => u && u.role === 'freelancer';
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
    if (!isFreelancer(u)) return true;
    const parts = String(rel).split('/');
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
      default: return true;
    }
  }

  function shape(u, kind, data) {
    if (kind !== 'users' || !data) return data;
    const out = { ...data };
    SECRET_USER_FIELDS.forEach((k) => delete out[k]);
    return out;
  }

  function canWrite(u, ch, current) {
    const admin = u.role === 'admin';
    const manager = admin || u.role === 'am';
    const next = ch.del ? null : ch.data;
    switch (ch.kind) {
      case 'users':
        if (ch.del) return false;                                   // people are deactivated, never deleted
        if (admin) return true;
        if (String(ch.id) !== u.id || !current) return false;      // only your own account
        // you may edit your own profile, but not your role, email, access or projects
        return PROTECTED_USER_FIELDS.every((k) => deepEqual(next[k], ch.base ? ch.base[k] : current[k]) || deepEqual(next[k], current[k]));
      case 'meta':
      case 'statuses':
        return manager;
      case 'clients':
        if (isFreelancer(u)) return false;
        if (ch.del) return admin;                                   // only Admins delete a client
        return manager;                                             // Admins + Account Managers manage Client Assets
      case 'projects':
        if (isFreelancer(u)) return !ch.del && !!current && projectSet(u).has(current.id) && next.id === current.id;
        return true;
      case 'tasks':
        if (isFreelancer(u)) return (!current || taskVisible(u, current)) && (ch.del || taskVisible(u, next));
        return true;
      case 'notifications':
        if (ch.del) return !current || current.to === u.id;
        if (!current) return true;
        return current.to === u.id || current.from === u.id;
      default:
        return true;
    }
  }

  return { userByEmail, canSee, canWrite, shape, isFreelancer, canReadFile };
}
