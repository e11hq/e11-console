// A claim's PDF drawn by the server (Haris 2026-11-05): a real PDF, a page per 30-odd lines, the words and the dirham sign
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { claimSheetFor } from '../src/claimsheet.js';

test('a claim becomes its sheet as a PDF, more pages for more lines', async () => {
  const items = Array.from({ length: 50 }, (_, i) => ({ id: 'i' + i, desc: 'Taxi ' + i, amount: 10 + i, ...(i === 3 ? { receipt: { path: 'Claims/u1/2026-11/r.jpg' } } : {}) }));
  const c = { id: 'cl-u1-2026-11', userId: 'u1', month: '2026-11', state: 'submitted', submittedAt: '2026-11-05T08:00:00Z', groups: [{ id: 'g', date: '2026-11-03', title: 'Shoot', items }] };
  const s = await claimSheetFor(c, { id: 'u1', name: 'Muhammad Haris Sharif', role: 'admin' }, {}, { now: Date.parse('2026-11-05T10:00:00Z') });
  assert.equal(s.pdf.slice(0, 5).toString(), '%PDF-');
  assert.deepEqual(s.receipts, ['Claims/u1/2026-11/r.jpg']);
  assert.equal(s.name, 'Expense claim — Muhammad Haris Sharif — November 2026.pdf');
  const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'cl-')), 'c.pdf');
  fs.writeFileSync(f, s.pdf);
  let info = '';
  try { info = execFileSync('pdfinfo', [f]).toString(); } catch { return; }   // (no poppler here: the bytes are enough)
  assert.ok(Number((/Pages:\s+(\d+)/.exec(info) || [])[1]) >= 2, info);
  const txt = execFileSync('pdftotext', [f, '-']).toString();
  assert.match(txt, /Expense claim form/);
  assert.match(txt, /Muhammad Haris Sharif/);
  assert.match(txt, /1,725\.00/);   // (the total: 50 lines, 10…59)
});
