// Part B step 3 (2026-11-05): the iPhone app's Claims and Expenses actions, done on the server — what the hidden
// website page does today for the same input (web/phone.js NativeMe `__e11Me`: clApprove, clPaid, clAdd, clPerson,
// exAdd, exEnd), with the same rules (web/claims.js Claims.markApproved / paidOn / addByHand / notify, web/finance.js
// subscriptions and expenses, app.js finLevel / uid / nowISO / todayStr) and the same answers and error texts.
// "Today" and every month are Dubai's (the page runs on a phone in Dubai).
//
//   const acts = createMoneyActs({ store, now });   // store: get(kind, id) / list(kind); now: () => ms (or a number)
//   acts.clApprove(u, body) → { ok: true, changes: [{ kind, id, base?, data } | { kind, id, del: true }], messages: [], answer: {} }
//                          | { ok: false, status, error }
// `u` is the signed-in user's record. Changes are whole records: `base` the record before (absent for a new one).
// What the server would refuse anyway (access.js canWriteClaim) is refused here first, with an answer the app can show.
const DUBAI = 4 * 3600000;   // Dubai is UTC+4 all year
const pad2 = (n) => String(n).padStart(2, '0');
const clone = (x) => (x == null ? x : JSON.parse(JSON.stringify(x)));
const finLevel = (u) => (!u ? null : u.role === 'finance_admin' ? 'admin' : u.role === 'finance_viewer' ? 'viewer' : u.fin === 'admin' || u.fin === 'viewer' ? u.fin : null);
const num = (v) => { const n = parseFloat(String(v == null ? '' : v).replace(/,/g, '')); return Number.isFinite(n) ? n : 0; };
const money = (n) => (Number(n) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const totalOf = (c) => (c.groups || []).reduce((a, g) => a + (g.items || []).reduce((b, i) => b + num(i.amount), 0), 0);
const parseYmd = (s) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); };
// claims.js monthName: (m, true) → "November"; (m) → "November 2026"
const monthName = (m, short) => { const [y, mo] = m.split('-').map(Number); return new Date(y, mo - 1, 1).toLocaleDateString('en-US', short ? { month: 'long' } : { month: 'long', year: 'numeric' }); };
const addMonth = (m, n) => { const [y, mo] = m.split('-').map(Number); const d = new Date(y, mo - 1 + n, 1); return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`; };

const ONLY_ADMIN = 'Only a Finance Admin can do this';

export function createMoneyActs({ store, now } = {}) {
  const clock = () => (typeof now === 'function' ? Number(now()) : now == null ? Date.now() : Number(now));
  const nowISO = () => new Date(clock()).toISOString();
  const todayStr = () => { const d = new Date(clock() + DUBAI); return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`; };
  let seq = 0;
  // app.js uid(): base-36 time + 6 random characters (+ a counter so two made in the same moment never meet)
  const uid = () => clock().toString(36) + (Math.random().toString(36).slice(2, 8) + '000000').slice(0, 6) + (seq++ % 36).toString(36);
  // app.js fmtDay: "Nov 5", with the year when it isn't this year (Dubai's)
  const fmtDay = (s) => { if (!s) return ''; const d = parseYmd(s); const o = { month: 'short', day: 'numeric' }; if (d.getFullYear() !== Number(todayStr().slice(0, 4))) o.year = 'numeric'; return d.toLocaleDateString('en-US', o); };
  const monthClosed = (m) => todayStr() >= `${m}-28`;

  const fail = (status, error) => ({ ok: false, status, error });
  const done = (changes, answer = {}) => ({ ok: true, changes, messages: [], answer });
  const isFinAdm = (u) => !!u && finLevel(u) === 'admin';

  // Claims.save: updatedAt, the total again from its items
  function saved(c) { c.updatedAt = nowISO(); c.total = Math.round(totalOf(c) * 100) / 100; return c; }
  // Claims.notify: the person told (never yourself)
  function notice(u, to, c, kind, text) {
    if (!to || to === u.id) return null;
    const n = { id: uid(), to, from: u.id, taskId: null, claimId: c.id, month: c.month, kind, text, snippet: c.total ? 'AED ' + money(c.total) : '', commentId: null, at: nowISO(), read: false };
    return { kind: 'notifications', id: n.id, data: n };
  }

  // ---------- Claims ----------
  // HR approved (a Submitted claim; anything else: nothing happens, and the page still answers ok)
  function clApprove(u, body = {}) {
    if (!isFinAdm(u)) return fail(403, ONLY_ADMIN);
    const before = store.get('claims', String(body.id));
    const changes = [];
    if (before && before.state === 'submitted') {
      const c = clone(before);
      c.state = 'approved'; c.approvedAt = nowISO(); c.approvedBy = u.id;
      saved(c);
      changes.push({ kind: 'claims', id: c.id, base: before, data: c });
      const n = notice(u, c.userId, c, 'claim-ok', `marked your ${monthName(c.month, true)} expense claim <b>HR approved</b>`);
      if (n) changes.push(n);
    }
    return done(changes);
  }

  // Paid on a date (a Submitted or HR approved claim): HR approved too if it wasn't, and the payment as a staff
  // reimbursement in Finance → Expenses (its record made once, then kept up to date)
  function clPaid(u, body = {}) {
    if (!isFinAdm(u)) return fail(403, ONLY_ADMIN);
    const date = String(body.date || '');
    const before = store.get('claims', String(body.id));
    if (!before || !['submitted', 'approved'].includes(before.state) || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return fail(400, 'That claim can’t be marked paid');
    const c = clone(before), changes = [];
    if (!c.approvedAt) { c.approvedAt = nowISO(); c.approvedBy = u.id; }
    c.state = 'paid'; c.paidOn = date; c.paidBy = u.id;
    const rBefore = c.reimbId != null ? store.get('finance', String(c.reimbId)) : null;
    let r = clone(rBefore);
    if (!r) {
      r = { id: uid(), type: 'reimb', userId: c.userId, claimId: c.id, createdAt: nowISO(), createdBy: u.id, invoice: null };
      if (!c.userId) { r.personId = c.personId; r.personName = c.personName; }
      c.reimbId = r.id;
    }
    r.amount = Math.round(totalOf(c) * 100) / 100; r.date = date;
    changes.push(rBefore ? { kind: 'finance', id: r.id, base: rBefore, data: r } : { kind: 'finance', id: r.id, data: r });
    saved(c);
    changes.push({ kind: 'claims', id: c.id, base: before, data: c });
    const n = notice(u, c.userId, c, 'claim-paid', `marked your ${monthName(c.month, true)} expense claim <b>paid</b> on ${fmtDay(date)}`);
    if (n) changes.push(n);
    return done(changes);
  }

  // A claim added by hand: one PDF for a team member ("u:<id>") or someone who isn't one ("p:<finance person id>"),
  // Submitted, for this month or last (the server takes no other month; your own: a month that isn't closed)
  function clAdd(u, body = {}) {
    if (!isFinAdm(u)) return fail(403, ONLY_ADMIN);
    const [t, id] = String(body.who || '').split(':');
    const amount = Math.round(parseFloat(body.amount) * 100) / 100;
    if (!id) return fail(400, 'Choose who is being reimbursed');
    if (!(amount > 0)) return fail(400, 'Enter the amount in AED (numbers only)');
    if (!body.pdf || !body.pdf.path) return fail(400, 'Attach the claim’s PDF');
    const person = t === 'p' ? store.get('finance', id) : null;
    const month = /^\d{4}-\d{2}$/.test(body.month || '') ? String(body.month) : todayStr().slice(0, 7);
    const userId = t === 'u' ? id : null;
    // (access.js canWriteClaim: your own claim — not once its month is closed; anyone else's — this month or last)
    if (userId === u.id) { if (monthClosed(month)) return fail(403, `${monthName(month)} claims closed on the 28th`); }
    else { const cur = todayStr().slice(0, 7); if (month !== cur && month !== addMonth(cur, -1)) return fail(403, 'A claim by hand is for this month or last month'); }
    const at = nowISO();
    const c = { id: 'clh-' + uid(), byHand: true, userId, personId: t === 'p' ? id : null, personName: person ? person.name : '', month, state: 'submitted',
      groups: [{ id: uid(), date: `${month}-01`, title: 'Added by hand', items: [{ id: uid(), desc: 'Claim (PDF)', amount: Math.round(num(amount) * 100) / 100,
        receipt: { id: uid(), path: String(body.pdf.path), name: String(body.pdf.name || 'Claim.pdf'), size: Number(body.pdf.size) || 0 } }] }],
      submittedAt: at, createdAt: at, createdBy: u.id };
    saved(c);
    const changes = [{ kind: 'claims', id: c.id, data: c }];
    if (c.userId) { const n = notice(u, c.userId, c, 'claim-hand', `added an expense claim for you for <b>${monthName(c.month, true)}</b> by hand`); if (n) changes.push(n); }
    return done(changes);
  }

  // Someone who isn't a team member, to add a claim for by hand (answer: their "p:<id>" and name)
  function clPerson(u, body = {}) {
    if (!isFinAdm(u)) return fail(403, ONLY_ADMIN);
    const n = String(body.name || '').trim();
    if (!n) return fail(400, 'Enter a name');
    const pr = { id: uid(), type: 'person', name: n, createdAt: nowISO(), createdBy: u.id };
    return done([{ kind: 'finance', id: pr.id, data: pr }], { id: 'p:' + pr.id, name: n });
  }

  // ---------- Expenses ----------
  // A monthly subscription (from this month, on its billing day; an invoice: this month's) or an office expense
  function exAdd(u, body = {}) {
    if (!isFinAdm(u)) return fail(403, ONLY_ADMIN);
    const name = String(body.name || '').trim(), amount = Math.round(parseFloat(body.amount) * 100) / 100;
    if (!name) return fail(400, 'Enter a name');
    if (!(amount > 0)) return fail(400, 'Enter the amount in AED (numbers only)');
    const inv = body.invoice && body.invoice.path ? { path: String(body.invoice.path), name: String(body.invoice.name || 'Invoice'), size: Number(body.invoice.size) || 0 } : null;
    const rec = { id: uid(), type: body.kind === 'sub' ? 'sub' : 'expense', name, amount, createdAt: nowISO(), createdBy: u.id };
    const m = todayStr().slice(0, 7);
    if (rec.type === 'sub') { rec.day = Math.min(31, Math.max(1, Number(body.day) || 1)); rec.startMonth = m; rec.invoices = inv ? { [m]: inv } : {}; rec.endedAt = null; }
    else { rec.date = /^\d{4}-\d{2}-\d{2}$/.test(body.date || '') ? body.date : todayStr(); rec.invoice = inv; }
    return done([{ kind: 'finance', id: rec.id, data: rec }]);
  }

  // A subscription ended now: not recorded from now on (months already recorded stay)
  function exEnd(u, body = {}) {
    if (!isFinAdm(u)) return fail(403, ONLY_ADMIN);
    const before = typeof body.id === 'string' ? store.get('finance', body.id) : null;
    if (!before || before.type !== 'sub') return fail(404, 'That subscription isn’t here any more');
    const x = clone(before);
    x.endedAt = nowISO();
    return done([{ kind: 'finance', id: x.id, base: before, data: x }]);
  }

  return { clApprove, clPaid, clAdd, clPerson, exAdd, exEnd };
}

