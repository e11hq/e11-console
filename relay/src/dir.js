// E11 Console's people and clients, as the office sends them (signed): what E11 Talk's own code asks E11 Console for
// (store.get / store.list, access.*). Console's tasks stay in the office — task cards and picking a task wait for it.
export function makeDir(snap) {
  let d = snap || { users: [], projects: [], clients: [], meta: {}, flags: {}, see: {} };
  const by = (list) => new Map((list || []).map((x) => [String(x.id), x]));
  let idx = {};
  const index = () => { idx = { users: by(d.users), projects: by(d.projects), clients: by(d.clients) };
    idx.email = new Map((d.users || []).filter((u) => u.email).map((u) => [String(u.email).toLowerCase(), u])); };
  index();
  const flag = (u, k) => !!(u && d.flags && d.flags[u.id] && d.flags[u.id][k]);
  // E11 Console's tasks never live here (Haris 2026-11-22 02:58 "keep it only local"): for one call that shares a task, the
  // office lends that task (only what its card needs) and its client's sections — checked by the office for that person —
  // and they're let go as soon as the call is done
  let lent = { tasks: new Map(), projects: new Map() };
  const store = {
    get(kind, id) {
      if (kind === 'meta') return id === 'main' ? d.meta || {} : null;
      if (lent[kind] && lent[kind].has(String(id))) return lent[kind].get(String(id));
      return (idx[kind] && idx[kind].get(String(id))) || null;
    },
    list(kind) { return kind === 'users' ? d.users || [] : kind === 'projects' ? d.projects || [] : kind === 'clients' ? d.clients || [] : []; },
  };
  const access = {
    isFreelancer: (u) => flag(u, 'free'), isSuper: (u) => flag(u, 'super'), isOffice: (u) => flag(u, 'office'),
    canSee: (u, kind, x) => kind === 'tasks' ? !!x && lent.tasks.get(String(x.id)) === x
      : kind === 'projects' && !!u && !!x && ((d.see && d.see[u.id]) || []).includes(String(x.id)),
    userByEmail: (e) => idx.email.get(String(e || '').toLowerCase()) || null,
  };
  const lend = (tasks = [], projects = []) => { lent = { tasks: new Map(tasks.map((t) => [String(t.id), t])), projects: new Map(projects.map((p) => [String(p.id), p])) }; };
  return { store, access, lend, set(s) { d = s; index(); }, get snapshot() { return d; } };
}
