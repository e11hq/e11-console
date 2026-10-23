// Expense claims: who sees and changes them, receipts and signatures, the claim PDF
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createServer } from '../src/server.js';

let app, base, dir;
const now = new Date();
const ym = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
// an open month (claims for it close on the 28th) and a closed one
const OPEN = now.getDate() >= 28 ? ym(new Date(now.getFullYear(), now.getMonth() + 1, 1)) : ym(now);
const CLOSED = ym(new Date(now.getFullYear(), now.getMonth() - 1, 1));
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11cl-'));
  app = createServer({ dataDir: dir, dev: true });
  app.cfSync = null;
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    users: [
      { id: 'u-prod', email: 'ali@e11-digital.com', role: 'production', active: true },
      { id: 'u-free', email: 'free@gmail.com', role: 'freelancer', active: true },
      { id: 'u-am', email: 'areej@e11-digital.com', role: 'am', active: true },
      { id: 'u-admin', email: 'arsal@e11-digital.com', role: 'admin', active: true },
      { id: 'u-fa', email: 'fin@e11-digital.com', role: 'finance_admin', active: true },
      { id: 'u-fv', email: 'view@e11-digital.com', role: 'finance_viewer', active: true },
    ],
    claims: [
      { id: `cl-u-am-${OPEN}`, userId: 'u-am', month: OPEN, state: 'submitted', groups: [{ id: 'g', date: `${OPEN}-03`, title: 'Shoot', items: [{ id: 'i', desc: 'Taxi', amount: 50, receipt: null }] }], total: 50, submittedAt: now.toISOString() },
      { id: `cl-u-free-${OPEN}`, userId: 'u-free', month: OPEN, state: 'offline', groups: [], total: 0 },
      { id: `cl-u-prod-${CLOSED}`, userId: 'u-prod', month: CLOSED, state: 'draft', groups: [], total: 0 },
    ],
  }, 'test');
  fs.mkdirSync(path.join(dir, 'files', 'Claims', 'u-am', OPEN), { recursive: true });
  fs.copyFileSync(new URL('../src/sample-files/receipt-reimbursement.pdf', import.meta.url), path.join(dir, 'files', 'Claims', 'u-am', OPEN, 'receipt.pdf'));
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const call = async (who, p, body) => {
  const res = await fetch(base + p, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const push = (who, id, data, base0) => call(who, '/api/push', { changes: [{ kind: 'claims', id, data, ...(base0 ? { base: base0 } : {}) }] }).then((r) => r.body.results[0].refused);
const snap = (who) => call(who, '/api/snapshot').then((r) => r.body.data.claims.map((c) => c.id));
const cur = (id) => app.store.get('claims', id);
const PROD = 'ali@e11-digital.com', FREE = 'free@gmail.com', AM = 'areej@e11-digital.com', ADMIN = 'arsal@e11-digital.com', FA = 'fin@e11-digital.com', FV = 'view@e11-digital.com';

test('people see their own claims; Finance sees submitted ones but not drafts or "submitted offline"', async () => {
  assert.deepEqual(await snap(AM), [`cl-u-am-${OPEN}`]);
  assert.deepEqual(await snap(PROD), [`cl-u-prod-${CLOSED}`]);
  assert.deepEqual((await snap(FA)).sort(), [`cl-u-am-${OPEN}`]);
  assert.deepEqual(await snap(FV), [`cl-u-am-${OPEN}`], 'Finance Viewers see claims too');
  assert.deepEqual(await snap(ADMIN), [], 'Admins without Finance access don’t');
});

test('anyone (freelancers too) can submit their own claim for an open month, never someone else’s', async () => {
  const mk = (uid, state = 'submitted') => ({ id: `cl-${uid}-${OPEN}`, userId: uid, month: OPEN, state, groups: [{ id: 'g', date: `${OPEN}-05`, title: 'Scout', items: [{ id: 'i', desc: 'Petrol', amount: 80, receipt: null }] }], total: 80 });
  assert.equal(await push(PROD, `cl-u-prod-${OPEN}`, mk('u-prod')), false);
  assert.equal(await push(FREE, `cl-u-free-${OPEN}`, mk('u-free')), false, 'freelancer');
  assert.equal(await push(PROD, `cl-u-am-${OPEN}`, { ...cur(`cl-u-am-${OPEN}`), total: 1 }), true, 'not someone else’s');
  assert.equal(await push(PROD, `cl-u-prod-${OPEN}`, { ...mk('u-prod'), state: 'approved' }), true, 'can’t approve your own');
  assert.equal(await push(PROD, `cl-u-prod-${OPEN}`, { ...mk('u-prod'), paidOn: '2026-01-01' }), true, 'can’t set paid');
});

test('a month closes on the 28th: no submitting or changing it afterwards', async () => {
  const c = cur(`cl-u-prod-${CLOSED}`);
  assert.equal(await push(PROD, c.id, { ...c, state: 'submitted', total: 10 }), true);
  assert.equal(await push(PROD, `cl-u-prod-${CLOSED}x`, { id: `cl-u-prod-${CLOSED}x`, userId: 'u-prod', month: CLOSED, state: 'none', groups: [] }), true);
});

test('Finance Admins mark HR approved and paid; they can’t change what was claimed; Viewers only look', async () => {
  const id = `cl-u-am-${OPEN}`;
  const c = cur(id);
  assert.equal(await push(FV, id, { ...c, state: 'approved', approvedAt: now.toISOString() }), true, 'viewer');
  assert.equal(await push(FA, id, { ...c, total: 5000 }), true, 'no changing amounts');
  assert.equal(await push(FA, id, { ...c, state: 'approved', approvedAt: now.toISOString(), approvedBy: 'u-fa' }), false);
  assert.equal(await push(FA, id, { ...cur(id), state: 'paid', paidOn: `${OPEN}-27`, paidBy: 'u-fa' }), false);
  assert.equal(await push(AM, id, { ...cur(id), groups: [] }), true, 'locked for the person once approved');
});

test('Finance-only people can tell someone their claim is paid (but no other notifications)', async () => {
  const n = (kind) => call(FA, '/api/push', { changes: [{ kind: 'notifications', id: 'n-' + kind, data: { id: 'n-' + kind, to: 'u-am', from: 'u-fa', kind, text: 'x', at: now.toISOString(), read: false } }] }).then((r) => r.body.results[0].refused);
  assert.equal(await n('claim-paid'), false);
  assert.equal(await n('comment'), true);
});

test('receipts and signatures go to your own Claims folder; only you and Finance can open them', async () => {
  const up = (who, dest) => call(who, '/api/host/writeChunk', { dest, name: 'r.txt', b64: Buffer.from('hi').toString('base64') });
  assert.equal((await up(AM, `Claims/u-am/${OPEN}`)).status, 200);
  assert.equal((await up(PROD, `Claims/u-am/${OPEN}`)).status, 403);
  const file = (who) => fetch(`${base}/__file/Claims/u-am/${OPEN}/receipt.pdf`, { headers: { 'X-Dev-Email': who } }).then((r) => r.status);
  assert.equal(await file(AM), 200);
  assert.equal(await file(FV), 200);
  assert.equal(await file(PROD), 403);
  assert.equal(await file(ADMIN), 403);
});

test('claim PDF: the sheet pages plus the receipts, for the person or Finance only', async () => {
  // a tiny white JPEG as the drawn sheet
  const jpg = path.join(dir, 's.jpg');
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 'lavfi', '-i', 'color=c=white:s=124x175', '-frames:v', '1', jpg]);
  const b64 = fs.readFileSync(jpg).toString('base64');
  const body = { userId: 'u-am', month: OPEN, name: 'Expense claim.pdf', pages: [b64], receipts: [`Claims/u-am/${OPEN}/receipt.pdf`] };
  const r = await call(FA, '/api/host/claimPdf', body);
  assert.equal(r.status, 200);
  const pdf = path.join(dir, 'files', r.body.path);
  assert.ok(fs.readFileSync(pdf).subarray(0, 5).toString() === '%PDF-', 'a PDF file');
  // page count needs poppler (on the NAS image; CI may not have it when its package mirror is down)
  let hasPoppler = true; try { execFileSync('pdfinfo', ['-v'], { stdio: 'ignore' }); } catch { hasPoppler = false; }
  if (hasPoppler) {
    const pages = Number(/Pages:\s+(\d+)/.exec(execFileSync('pdfinfo', [pdf]).toString())[1]);
    assert.ok(pages >= 2, `sheet + receipt (${pages} pages)`);
  }
  assert.equal((await call(PROD, '/api/host/claimPdf', body)).status, 403);
  assert.equal((await call(AM, '/api/host/claimPdf', { ...body, receipts: ['attachments/x/secret.pdf'] })).status, 403);
});

test('expenses report: PDF for Admin and Finance; with files a .zip with Attachments/<month>/ folders', async () => {
  const jpg = path.join(dir, 'r.jpg');
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 'lavfi', '-i', 'color=c=white:s=124x175', '-frames:v', '1', jpg]);
  const b64 = fs.readFileSync(jpg).toString('base64');
  fs.mkdirSync(path.join(dir, 'files', 'Finance', 'Subscriptions', OPEN), { recursive: true });
  fs.writeFileSync(path.join(dir, 'files', 'Finance', 'Subscriptions', OPEN, 'inv.pdf'), '%PDF-1.4 test');
  const pdfOnly = await call(FV, '/api/host/expenseReport', { name: 'E11 expenses — test', pages: [b64, b64] });
  assert.equal(pdfOnly.status, 200);
  assert.ok(!pdfOnly.body.zip && pdfOnly.body.path.startsWith('Finance/_reports/'));
  assert.equal(fs.readFileSync(path.join(dir, 'files', pdfOnly.body.path)).subarray(0, 5).toString(), '%PDF-');
  const files = [{ path: `Finance/Subscriptions/${OPEN}/inv.pdf`, as: `${OPEN}/SUB-01_Google.pdf` }, { path: `Claims/u-am/${OPEN}/receipt.pdf`, as: `${OPEN}/REI-01_Areej.pdf` }];
  const z = await call(FA, '/api/host/expenseReport', { name: 'E11 expenses — test', pages: [b64], zip: true, files });
  assert.equal(z.status, 200);
  assert.equal(z.body.count, 3);
  const zr = await fetch(base + z.body.url, { headers: { 'X-Dev-Email': FA } });
  const buf = Buffer.from(await zr.arrayBuffer());
  const utf = buf.toString('utf8');
  assert.ok(utf.includes(`Attachments/${OPEN}/SUB-01_Google.pdf`) && utf.includes(`Attachments/${OPEN}/REI-01_Areej.pdf`) && utf.includes('E11 expenses — test.pdf'), 'zip entries in folders');
  // Admins (no Finance access) can make the PDF, but not with claim receipts; others can't at all
  assert.equal((await call(ADMIN, '/api/host/expenseReport', { name: 'x', pages: [b64] })).status, 200);
  assert.equal((await call(ADMIN, '/api/host/expenseReport', { name: 'x', pages: [b64], zip: true, files })).status, 403);
  assert.equal((await call(AM, '/api/host/expenseReport', { name: 'x', pages: [b64] })).status, 403);
  assert.equal((await call(FA, '/api/host/expenseReport', { name: 'x', pages: [b64], zip: true, files: [{ path: 'attachments/t/x.pdf', as: 'a.pdf' }] })).status, 403);
});
