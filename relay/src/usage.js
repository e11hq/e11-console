// How much of Cloudflare's free daily limits E11 Talk has used today — for the owner, in Talk's About (TALK-CF-A,
// Haris 2026-11-22 02:14 "A"). Cloudflare's own figures, from its analytics (GraphQL), with a read-only token Haris
// made ("Account Analytics: Read", the Worker secret CF_ANALYTICS_TOKEN). The day is Cloudflare's: UTC — 4 AM here.
// One number: the highest of the daily limits — requests, running time, rows written (and rows read).
export const FREE = { requests: 100_000, gbs: 13_000, rowsWritten: 100_000, rowsRead: 5_000_000 };
const API = 'https://api.cloudflare.com/client/v4/graphql';

// (each part asked on its own: one Cloudflare doesn't answer doesn't lose the others)
const PARTS = {
  worker: { q: 'workersInvocationsAdaptive(limit: 10000, filter: { date: $d }) { sum { requests } }', pick: (r) => ({ workerRequests: sum(r, 'requests') }) },
  calls: { q: 'durableObjectsInvocationsAdaptiveGroups(limit: 10000, filter: { date: $d }) { sum { requests } }', pick: (r) => ({ hubRequests: sum(r, 'requests') }) },
  hub: { q: 'durableObjectsPeriodicGroups(limit: 10000, filter: { date: $d }) { sum { activeTime inboundWebsocketMsgCount rowsRead rowsWritten } }',
    pick: (r) => ({ activeUs: sum(r, 'activeTime'), wsIn: sum(r, 'inboundWebsocketMsgCount'), rowsRead: sum(r, 'rowsRead'), rowsWritten: sum(r, 'rowsWritten') }) },
};
const sum = (rows, k) => (rows || []).reduce((n, x) => n + Number((x.sum || {})[k] || 0), 0);

export async function usage({ token, account, now = Date.now(), go = (...a) => fetch(...a) }) {
  if (!token) return { ok: false, error: 'No analytics token in Cloudflare yet' };
  if (!account) return { ok: false, error: 'No account' };
  const d = new Date(now).toISOString().slice(0, 10);
  const got = {}, errors = {};
  await Promise.all(Object.entries(PARTS).map(async ([name, part]) => {
    try {
      const r = await go(API, { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
        body: JSON.stringify({ query: `query ($a: String!, $d: Date!) { viewer { accounts(filter: { accountTag: $a }) { x: ${part.q} } } }`, variables: { a: account, d } }) });
      const j = await r.json();
      if (j.errors && j.errors.length) throw new Error(j.errors.map((e) => e.message).join('; '));
      Object.assign(got, part.pick(((((j.data || {}).viewer || {}).accounts || [])[0] || {}).x));
    } catch (e) { errors[name] = String(e.message || e).slice(0, 300); }
  }));
  if (Object.keys(got).length === 0) return { ok: false, error: 'Cloudflare didn’t answer', errors };
  // (requests: the front door's and the hub's, a WebSocket message counting as 1/20 of one; running time: 128 MB while active)
  const requests = (got.workerRequests || 0) + (got.hubRequests || 0) + (got.wsIn || 0) / 20;
  const gbs = ((got.activeUs || 0) / 1e6) * 0.125;
  const pct = {
    requests: requests / FREE.requests * 100, time: gbs / FREE.gbs * 100,
    rowsWritten: (got.rowsWritten || 0) / FREE.rowsWritten * 100, rowsRead: (got.rowsRead || 0) / FREE.rowsRead * 100,
  };
  const top = Object.entries(pct).sort((a, b) => b[1] - a[1])[0];
  return { ok: true, day: d, percent: Math.round(top[1] * 10) / 10, highest: top[0], pct, figures: { ...got, requests, gbs }, errors: Object.keys(errors).length ? errors : undefined };
}
