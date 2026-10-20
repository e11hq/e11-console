// Keeps Cloudflare Access in step with the Team page.
// Staff with @e11-digital.com emails are let in by the domain rule on the Access application.
// Everyone else on the team (freelancers with Gmail/Outlook addresses) is kept in one Cloudflare
// Access group, "E11 Console — Freelancers". Adding a person on the Team page adds them here;
// removing them (or making them inactive) takes them out.
const API = 'https://api.cloudflare.com/client/v4';
const PLACEHOLDER = 'nobody@invalid.e11hq.com'; // a group can't be empty

export function createCfSync({ accountId, token, groupId, groupName = 'E11 Console — Freelancers', staffDomain = 'e11-digital.com', listUsers, fetchImpl = fetch, log = console, delayMs = 3000 }) {
  const configured = !!(accountId && token);
  let timer = null, running = false, again = false;
  let state = { configured, ok: null, at: null, error: null, emails: [] , groupId: groupId || null };

  const wanted = () => [...new Set(listUsers()
    .filter((u) => u.active !== false && u.email && !String(u.email).toLowerCase().endsWith('@' + staffDomain))
    .map((u) => String(u.email).toLowerCase()))].sort();

  async function cf(method, path, body) {
    const res = await fetchImpl(API + path, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data.success === false) throw new Error((data.errors && data.errors[0] && data.errors[0].message) || `Cloudflare error ${res.status}`);
    return data.result;
  }

  async function findOrCreateGroup(include) {
    if (state.groupId) return state.groupId;
    const groups = await cf('GET', `/accounts/${accountId}/access/groups?per_page=100`);
    const g = (groups || []).find((x) => x.name === groupName);
    if (g) { state.groupId = g.id; return g.id; }
    const created = await cf('POST', `/accounts/${accountId}/access/groups`, { name: groupName, include });
    state.groupId = created.id;
    return created.id;
  }

  async function syncNow() {
    if (!configured) return state;
    if (running) { again = true; return state; }
    running = true;
    try {
      const emails = wanted();
      const include = (emails.length ? emails : [PLACEHOLDER]).map((email) => ({ email: { email } }));
      const id = await findOrCreateGroup(include);
      await cf('PUT', `/accounts/${accountId}/access/groups/${id}`, { name: groupName, include });
      state = { ...state, ok: true, at: new Date().toISOString(), error: null, emails };
    } catch (e) {
      state = { ...state, ok: false, at: new Date().toISOString(), error: e.message };
      log.error('Cloudflare sync failed:', e.message);
    } finally {
      running = false;
      if (again) { again = false; schedule(); }
    }
    return state;
  }

  function schedule() {
    if (!configured) return;
    clearTimeout(timer);
    timer = setTimeout(syncNow, delayMs);
  }
  return { schedule, syncNow, status: () => ({ ...state }) };
}
