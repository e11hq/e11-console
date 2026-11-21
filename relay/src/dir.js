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
  const store = {
    get(kind, id) { if (kind === 'meta') return id === 'main' ? d.meta || {} : null; return (idx[kind] && idx[kind].get(String(id))) || null; },
    list(kind) { return kind === 'users' ? d.users || [] : kind === 'projects' ? d.projects || [] : kind === 'clients' ? d.clients || [] : []; },
  };
  const access = {
    isFreelancer: (u) => flag(u, 'free'), isSuper: (u) => flag(u, 'super'), isOffice: (u) => flag(u, 'office'),
    canSee: (u, kind, x) => kind === 'projects' && !!u && !!x && ((d.see && d.see[u.id]) || []).includes(String(x.id)),
    userByEmail: (e) => idx.email.get(String(e || '').toLowerCase()) || null,
  };
  return { store, access, set(s) { d = s; index(); }, get snapshot() { return d; } };
}
