// A claim's PDF drawn by the server (Haris 2026-11-05: "Server draws it for all") — the expense claim sheet as the page
// drew it on its canvas (web/claims.js sheetPages: A4, the E11 tile, "Expense claim form", Name and Reimbursement month,
// the claim's lines by date with their receipts numbered, the total, the claimer and signature, the Finance strip), the
// same layout in the same 1240 × 1754 units (A4 at 150 dpi), written straight as a PDF — Helvetica for the words, the
// UAE dirham sign drawn from its official shape (tools/dirham-cbuae.svg, as the E11 Dirham font has it). No packages:
// the server has only Node, ffmpeg (the logo and the signature as JPEGs) and poppler (the receipts joined after it).
import zlib from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';

const WIDTHS = {"Helvetica": [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, 761, 556, 761, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 761, 611, 761, 761, 222, 222, 333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 761, 500, 667, 278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333, 400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611, 667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278, 722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, 556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278, 556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500], "Helvetica-Bold": [278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584, 761, 556, 761, 278, 556, 500, 1000, 556, 556, 333, 1000, 667, 333, 1000, 761, 611, 761, 761, 278, 278, 500, 500, 350, 556, 1000, 333, 1000, 556, 333, 944, 761, 500, 667, 278, 333, 556, 556, 556, 556, 280, 556, 333, 737, 370, 556, 584, 333, 737, 333, 400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365, 556, 834, 834, 834, 611, 722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278, 722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, 556, 556, 556, 556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278, 611, 611, 611, 611, 611, 611, 611, 584, 611, 611, 611, 611, 611, 556, 611, 556]};
// the dirham sign: its outline in the SVG's own units (1000 × 870, y down), as PDF path steps
const DIRHAM = "88.3 1.0 m 88.7 1.6 90.9 4.3 93.0 6.9 c 108.3 25.1 119.8 54.7 126.0 92.0 c 130.1 116.5 130.3 124.2 130.3 217.6 c 130.3 304.6 l 88.5 304.6 l 50.3 304.6 45.9 304.4 38.4 302.9 c 26.6 300.4 14.4 293.7 6.2 285.1 c -0.3 278.2 -0.1 277.8 0.3 298.7 c 0.8 316.0 1.0 317.9 3.5 327.3 c 7.5 342.2 13.0 353.3 21.3 363.2 c 32.6 376.8 44.1 384.4 60.5 389.5 c 64.0 390.5 71.4 390.9 97.6 391.1 c 130.3 391.6 l 130.3 434.9 l 130.3 478.3 l 84.2 478.0 l 37.9 477.7 l 29.9 474.5 l 20.4 470.7 16.1 467.9 6.8 459.6 c 0.0 453.5 l 0.4 472.6 l 0.9 490.3 1.0 492.3 3.5 501.3 c 12.2 533.1 33.2 555.8 60.9 563.2 c 67.8 565.1 70.5 565.2 99.4 565.6 c 130.3 566.0 l 130.3 655.6 l 130.3 709.7 130.0 749.6 129.5 756.4 c 129.0 762.6 127.4 774.2 126.0 782.3 c 119.5 819.6 107.8 847.7 91.0 865.9 c 87.6 869.6 l 256.7 869.6 l 357.8 869.6 433.4 869.2 444.5 868.7 c 464.0 867.7 507.5 863.4 517.3 861.3 c 520.4 860.7 526.2 859.8 530.0 859.2 c 538.1 858.0 551.5 855.2 570.8 850.3 c 598.0 843.5 622.8 835.0 647.1 824.2 c 654.7 820.8 676.5 809.7 682.3 806.2 c 685.4 804.4 689.1 802.2 690.5 801.5 c 694.4 799.4 700.9 795.2 710.4 788.4 c 715.1 785.0 719.8 781.7 720.8 781.0 c 725.0 778.2 739.5 766.1 746.1 760.0 c 771.2 736.9 792.2 711.2 808.5 683.7 c 810.8 679.7 813.8 674.7 815.1 672.6 c 818.4 667.0 832.0 639.0 833.3 634.8 c 833.9 632.9 834.7 630.9 835.1 630.5 c 837.7 627.1 852.7 579.9 854.5 569.6 c 855.1 566.3 855.4 565.8 857.9 565.3 c 859.5 565.0 882.8 565.0 909.7 565.2 c 963.5 565.6 963.5 565.6 975.4 571.1 c 982.1 574.2 984.1 575.6 991.5 582.3 c 1001.2 591.0 1000.3 592.4 999.7 570.6 c 999.3 557.8 998.8 549.9 997.9 546.7 c 994.5 534.4 993.7 531.8 990.7 525.6 c 980.9 504.2 964.5 488.9 943.5 481.6 c 935.3 478.6 l 901.9 478.2 l 868.6 477.7 l 869.0 466.0 l 869.4 450.6 869.4 420.1 868.9 404.4 c 868.5 391.8 l 913.1 391.6 l 951.3 391.4 958.4 391.6 962.6 392.7 c 975.2 396.2 983.7 401.0 994.1 410.5 c 999.9 415.9 l 999.9 401.1 l 999.9 383.5 999.0 375.7 995.4 364.1 c 988.3 340.6 974.3 323.1 954.3 312.3 c 941.3 305.3 940.5 305.1 895.8 304.8 c 869.6 304.6 855.9 304.2 855.2 303.6 c 854.6 303.0 854.1 302.0 854.1 301.2 c 854.1 300.4 852.6 294.1 850.6 287.3 c 827.2 204.6 783.5 138.9 719.6 90.2 c 710.9 83.5 689.6 69.4 681.0 64.6 c 677.7 62.7 674.1 60.7 673.2 60.1 c 669.0 57.8 644.9 46.0 638.9 43.5 c 635.3 41.9 630.6 39.9 628.5 39.1 c 593.2 23.8 534.0 9.3 488.8 4.8 c 481.4 4.1 471.6 3.0 467.1 2.6 c 446.7 0.3 418.4 0.0 257.7 0.0 c 121.9 0.0 87.8 0.3 88.3 1.0 c 88.3 1.0 l h 419.0 44.3 m 452.8 46.3 473.6 48.9 497.9 54.8 c 572.1 72.4 624.3 109.6 662.2 171.8 c 665.7 177.6 680.5 207.8 682.7 213.9 c 693.2 242.2 698.3 259.0 702.8 281.2 c 703.9 286.6 705.4 293.8 706.1 297.2 c 706.8 300.5 707.1 303.6 706.8 303.9 c 706.3 304.3 605.9 304.5 483.5 304.4 c 261.0 304.2 l 260.7 175.7 l 260.6 105.1 260.7 46.4 261.0 45.3 c 261.4 43.4 l 332.5 43.4 l 371.5 43.4 410.5 43.8 419.0 44.3 c h 716.5 394.6 m 717.2 398.9 717.2 471.9 716.5 475.5 c 715.9 478.2 l 488.4 478.0 l 261.0 477.7 l 260.8 435.3 l 260.6 412.0 260.8 392.6 261.0 392.2 c 261.3 391.7 358.2 391.4 488.7 391.4 c 715.9 391.4 l 716.5 394.6 l h 706.3 566.3 m 706.8 567.8 704.4 580.1 699.5 600.1 c 693.9 622.6 686.3 645.3 678.6 662.1 c 674.8 670.7 665.3 689.3 663.0 692.8 c 661.9 694.4 658.7 699.5 655.9 704.0 c 637.9 732.2 612.2 757.9 582.9 776.9 c 572.2 783.7 550.2 795.3 544.3 797.1 c 543.1 797.4 541.8 798.0 541.3 798.4 c 540.6 799.0 531.5 802.4 520.9 806.2 c 501.4 813.1 464.3 820.6 434.5 823.7 c 415.2 825.6 412.1 825.7 337.8 825.7 c 260.9 825.7 l 260.9 696.0 l 260.9 566.2 l 481.8 565.8 l 603.3 565.6 703.4 565.3 704.2 565.1 c 705.1 565.0 706.0 565.6 706.3 566.3 c h";
const W = 1240, H = 1754, P = 104, S = W / 794;
const PT = 595.28 / W;   // (a unit in points)

const WIN = { '…': 133, '·': 183, '—': 151, '–': 150, '‘': 145, '’': 146, '“': 147, '”': 148, '•': 149, '€': 128 };
const code = (ch) => { const c = ch.codePointAt(0); if (WIN[ch]) return WIN[ch]; return c >= 32 && c <= 255 && !(c >= 127 && c < 160) ? c : 63; };
const fontKey = (w) => (w >= 600 ? 'Helvetica-Bold' : 'Helvetica');
// a word's width in units: the letters, and the dirham sign as the E11 Dirham font has it (1.11 em, its gap built in)
function measure(s, w, px) {
  const tbl = WIDTHS[fontKey(w)];
  let n = 0;
  for (const ch of String(s)) n += ch === '⃃' ? 1110 : tbl[code(ch) - 32] || 556;
  return (n / 1000) * px;
}
const hex = (h) => { const x = String(h).replace('#', ''); return [0, 2, 4].map((i) => (parseInt(x.slice(i, i + 2), 16) / 255).toFixed(3)).join(' '); };
const pdfStr = (s) => '(' + Array.from(String(s)).map((ch) => { const c = code(ch); return c === 40 || c === 41 || c === 92 ? '\\' + String.fromCharCode(c) : c < 128 ? String.fromCharCode(c) : '\\' + c.toString(8).padStart(3, '0'); }).join('') + ')';

// pages: [{ ops: [] }]; images: { logo: { jpg, w, h }, sig: { jpg, w, h } }
export function claimSheetPdf(d, images = {}) {
  const pages = [];
  let ops = null, y = 0, pn = 0, cur = { w: 400, px: 12, fill: '#17181b' };
  const fill = (c) => { cur.fill = c; ops.push(hex(c) + ' rg'); };
  const font = (w, px) => { cur.w = w; cur.px = Math.round(px * S); };
  const rect = (x, yy, w, h) => ops.push(`${x.toFixed(2)} ${yy.toFixed(2)} ${w.toFixed(2)} ${h.toFixed(2)} re f`);
  // words at a baseline, left / right / centre, the dirham sign drawn between the words
  function text(s, x, base, align = 'left') {
    s = String(s == null ? '' : s);
    const wd = measure(s, cur.w, cur.px);
    let at = align === 'right' ? x - wd : align === 'center' ? x - wd / 2 : x;
    const parts = s.split('⃃');
    parts.forEach((part, i) => {
      if (part) { ops.push(`BT /${cur.w >= 600 ? 'F2' : 'F1'} ${cur.px} Tf 1 0 0 -1 ${at.toFixed(2)} ${base.toFixed(2)} Tm ${pdfStr(part)} Tj ET`); at += measure(part, cur.w, cur.px); }
      if (i < parts.length - 1) {
        // (the sign as the font draws it: 30 units in, 705 tall on the baseline, 1110 wide with its gap)
        const k = (cur.px * 0.705) / 870;
        ops.push(`q 1 0 0 1 ${(at + cur.px * 0.03).toFixed(2)} ${(base - cur.px * 0.705).toFixed(2)} cm ${k.toFixed(5)} 0 0 ${k.toFixed(5)} 0 0 cm ${DIRHAM} f Q`);
        at += cur.px * 1.11;
      }
    });
  }
  const fit = (s, max) => { let t = String(s); while (t.length > 1 && measure(t, cur.w, cur.px) > max) t = t.slice(0, -2); return t === s ? s : t + '…'; };
  const round = (x, yy, w, h, r) => { const k = 0.5523 * r; ops.push(`${x + r} ${yy} m ${x + w - r} ${yy} l ${x + w - r + k} ${yy} ${x + w} ${yy + r - k} ${x + w} ${yy + r} c ${x + w} ${yy + h - r} l ${x + w} ${yy + h - r + k} ${x + w - r + k} ${yy + h} ${x + w - r} ${yy + h} c ${x + r} ${yy + h} l ${x + r - k} ${yy + h} ${x} ${yy + h - r + k} ${x} ${yy + h - r} c ${x} ${yy + r} l ${x} ${yy + r - k} ${x + r - k} ${yy} ${x + r} ${yy} c h`); };
  const image = (name, x, yy, w, h) => ops.push(`q ${w.toFixed(2)} 0 0 ${(-h).toFixed(2)} ${x.toFixed(2)} ${(yy + h).toFixed(2)} cm /${name} Do Q`);
  const colX = [P, P + 130 * S, W - P - 12 * S];
  function newPage() {
    ops = []; pages.push({ ops }); pn++; y = P;
    fill('#ffffff'); rect(0, 0, W, H); fill('#17181b');
    if (images.logo) image('Im1', P, y, 56 * S, 56 * S);
    font(700, 11); fill('#6e717a'); text('E11 AGENCY', P + 70 * S, y + 20 * S);
    font(700, 26); fill('#17181b'); text('Expense claim form', P + 70 * S, y + 50 * S);
    font(400, 11); fill('#6e717a');
    text(pn > 1 ? `Page ${pn}` : `Claim ${d.month}-${d.initials || ''}`, W - P, y + 20 * S, 'right');
    if (d.submitted) text('Submitted ' + d.submitted, W - P, y + 38 * S, 'right');
    y += 74 * S; fill('#17181b'); rect(P, y, W - 2 * P, 2 * S); y += 22 * S;
    if (pn === 1) {
      const bw = (W - 2 * P - 12 * S) / 2;
      [['NAME', d.name], ['REIMBURSEMENT MONTH', d.monthName]].forEach(([l, v], k) => {
        const x = P + k * (bw + 12 * S);
        ops.push(`${hex('#e3e3e8')} RG 1.5 w`); round(x, y, bw, 58 * S, 8 * S); ops.push('S');
        font(600, 10.5); fill('#6e717a'); text(l, x + 14 * S, y + 22 * S);
        font(600, 14); fill('#17181b'); text(v, x + 14 * S, y + 44 * S);
      });
      y += 80 * S; font(700, 10.5); fill('#6e717a'); text('CLAIM DETAILS', P, y); y += 12 * S;
    }
    fill('#17181b'); rect(P, y, W - 2 * P, 34 * S);
    font(600, 10.5); fill('#ffffff');
    text('DATE', colX[0] + 12 * S, y + 22 * S); text('DESCRIPTION', colX[1], y + 22 * S); text('AMOUNT (⃃)', colX[2], y + 22 * S, 'right');
    y += 34 * S;
  }
  newPage();
  const RH = 34 * S, bottom = H - P - 40 * S;
  d.rows.forEach((r) => {
    if (y + RH > bottom) newPage();
    fill(r.t === 'g' ? '#f4f4f7' : '#ffffff'); rect(P, y, W - 2 * P, RH);
    fill('#ececf0'); rect(P, y, W - 2 * P, 1.5);
    fill('#17181b');
    if (r.t === 'g') { font(700, 12.5); text(r.date, colX[0] + 12 * S, y + 22 * S); text(fit(r.desc, colX[2] - colX[1] - 120 * S), colX[1], y + 22 * S); }
    else {
      font(400, 12.5); const t = fit(r.desc, colX[2] - colX[1] - 220 * S); text(t, colX[1] + 14 * S, y + 22 * S);
      if (r.rc) { const w = measure(t, 400, Math.round(12.5 * S)); font(500, 10); fill('#6e717a'); text(`receipt ${r.rc}`, colX[1] + 24 * S + w, y + 21 * S); fill('#17181b'); }
      font(500, 12.5); text(r.amt, colX[2], y + 22 * S, 'right');
    }
    y += RH;
  });
  if (y + 150 * S > bottom) newPage();
  fill('#efecff'); rect(P, y, W - 2 * P, 44 * S); fill('#5b4bd6'); rect(P, y, W - 2 * P, 2.5 * S);
  font(700, 14); fill('#17181b'); text('TOTAL', colX[0] + 12 * S, y + 28 * S);
  font(500, 12); fill('#4e5159'); text(d.summary, colX[1], y + 28 * S);
  font(700, 15); fill('#3b2fa0'); text('⃃' + d.total, colX[2], y + 28 * S, 'right');
  y += 80 * S;
  font(700, 10.5); fill('#6e717a'); text('CLAIMER DETAILS', P, y); text('SIGNATURE', W / 2, y);
  font(600, 14); fill('#17181b'); text(d.name, P, y + 26 * S);
  font(400, 12); fill('#6e717a'); text(d.role, P, y + 46 * S);
  if (images.sig) { const h = 54 * S, w = Math.min(220 * S, (images.sig.w / images.sig.h) * h); image('Im2', W / 2, y + 8 * S, w, h); }
  fill('#17181b'); rect(W / 2, y + 66 * S, 220 * S, 1.5);
  // the Finance strip at the foot of the last page
  const fy = H - P - 20 * S;
  ops.push(`${hex('#c9c9d1')} RG 1 w [6 6] 0 d ${P} ${fy - 34 * S} m ${W - P} ${fy - 34 * S} l S [] 0 d`);
  const cw = (W - 2 * P) / 3;
  [['For Finance use', d.received], ['HR approved', d.approved || '________________'], ['Paid on', d.paid || '____ / ____ / ________']].forEach(([l, v], k) => {
    font(700, 11.5); fill('#17181b'); text(l, P + k * cw, fy - 12 * S);
    font(400, 11); fill('#6e717a'); text(v || '', P + k * cw, fy + 6 * S);
  });
  font(400, 10); fill('#8a8d96');
  text(d.receipts ? 'Receipts follow on the next pages · Generated by E11 Console' : 'Generated by E11 Console', W / 2, H - P / 2, 'center');
  return writePdf(pages, images);
}

function writePdf(pages, images) {
  const objs = [];   // index → Buffer | string (object body)
  const add = (body) => { objs.push(body); return objs.length; };
  const catalog = add(null), pagesObj = add(null);
  const f1 = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  const f2 = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
  const imgRefs = [];
  [['Im1', images.logo], ['Im2', images.sig]].forEach(([n, im]) => {
    if (!im) return;
    const head = `<< /Type /XObject /Subtype /Image /Width ${im.w} /Height ${im.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${im.jpg.length} >>\nstream\n`;
    imgRefs.push(`/${n} ${add(Buffer.concat([Buffer.from(head, 'latin1'), im.jpg, Buffer.from('\nendstream', 'latin1')]))} 0 R`);
  });
  const kids = [];
  for (const pg of pages) {
    const content = zlib.deflateSync(Buffer.from(`${PT.toFixed(6)} 0 0 ${(-PT).toFixed(6)} 0 841.89 cm\n` + pg.ops.join('\n'), 'latin1'));
    const c = add(Buffer.concat([Buffer.from(`<< /Length ${content.length} /Filter /FlateDecode >>\nstream\n`, 'latin1'), content, Buffer.from('\nendstream', 'latin1')]));
    kids.push(add(`<< /Type /Page /Parent ${pagesObj} 0 R /MediaBox [0 0 595.28 841.89] /Resources << /Font << /F1 ${f1} 0 R /F2 ${f2} 0 R >> /XObject << ${imgRefs.join(' ')} >> >> /Contents ${c} 0 R >>`));
  }
  objs[catalog - 1] = `<< /Type /Catalog /Pages ${pagesObj} 0 R >>`;
  objs[pagesObj - 1] = `<< /Type /Pages /Kids [${kids.map((k) => k + ' 0 R').join(' ')}] /Count ${kids.length} >>`;
  const parts = [Buffer.from('%PDF-1.4\n%\xe2\xe3\xcf\xd3\n', 'latin1')];
  let off = parts[0].length;
  const xref = [];
  objs.forEach((o, i) => {
    xref.push(off);
    const b = Buffer.concat([Buffer.from(`${i + 1} 0 obj\n`, 'latin1'), Buffer.isBuffer(o) ? o : Buffer.from(o, 'latin1'), Buffer.from('\nendobj\n', 'latin1')]);
    parts.push(b); off += b.length;
  });
  const tail = `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${xref.map((x) => String(x).padStart(10, '0') + ' 00000 n \n').join('')}trailer\n<< /Size ${objs.length + 1} /Root ${catalog} 0 R >>\nstartxref\n${off}\n%%EOF\n`;
  parts.push(Buffer.from(tail, 'latin1'));
  return Buffer.concat(parts);
}

// ---------- a claim's data, as the page worked it out (claims.js sheetPages) ----------
const runOut = (cmd, args, timeout = 30000) => new Promise((ok) => execFile(cmd, args, { encoding: 'buffer', maxBuffer: 64 << 20, timeout }, (err, out) => ok(err ? null : out)));
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const ROLES = { admin: 'Super Admin', office_admin: 'Office Admin', am: 'Account Manager', production: 'Production', social: 'Social', freelancer: 'Freelancer', finance_admin: 'Finance only · Admin', finance_viewer: 'Finance only · Viewer' };
const dubaiDay = (ms) => new Date(ms + 4 * 3600000).toISOString().slice(0, 10);
const num = (v) => { const n = parseFloat(String(v == null ? '' : v).replace(/,/g, '')); return Number.isFinite(n) ? n : 0; };
const money = (n) => (Number(n) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const plural = (n, one, many) => `${n} ${n === 1 ? one : many || one + 's'}`;
// (a JPEG's size, from its header)
function jpegSize(b) {
  for (let i = 2; i < b.length - 9;) {
    if (b[i] !== 0xff) { i++; continue; }
    const m = b[i + 1], len = b.readUInt16BE(i + 2);
    if (m >= 0xc0 && m <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(m)) return { h: b.readUInt16BE(i + 5), w: b.readUInt16BE(i + 7) };
    i += 2 + len;
  }
  return null;
}
// a picture as a JPEG on white (the logo's and the signature's see-through parts), at most `max` tall
async function jpegOf(src, max) {
  const probe = await runOut('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'json', src], 20000);
  let w = 0, h = 0;
  try { const st = JSON.parse(String(probe)).streams[0]; w = +st.width || 0; h = +st.height || 0; } catch { return null; }
  if (!w || !h) return null;
  const k = Math.min(1, max / h), ow = Math.max(2, Math.round((w * k) / 2) * 2), oh = Math.max(2, Math.round((h * k) / 2) * 2);
  const jpg = await runOut('ffmpeg', ['-v', 'error', '-f', 'lavfi', '-i', `color=c=white:s=${ow}x${oh}`, '-i', src, '-filter_complex', `[1:v]scale=${ow}:${oh},format=rgba[a];[0:v][a]overlay=format=auto,format=yuvj444p[o]`, '-map', '[o]', '-frames:v', '1', '-q:v', '2', '-f', 'image2pipe', '-vcodec', 'mjpeg', '-'], 30000);
  if (!jpg || !jpg.length) return null;
  const sz = jpegSize(jpg);
  return sz ? { jpg, w: sz.w, h: sz.h } : null;
}
let logoJpg = null;
// c: the claim · u: its person (or null) · meta: the shared settings · resolve: a file's path on disk · webDir: the logo
export async function claimSheetFor(c, u, meta, { resolve, webDir, now = Date.now() } = {}) {
  const thisYear = dubaiDay(now).slice(0, 4);
  const fmtDay = (s) => { if (!s) return ''; const [y, m, d] = s.split('-').map(Number); return `${MON[m - 1]} ${d}${String(y) !== thisYear ? `, ${y}` : ''}`; };
  const dayOf = (iso) => (iso ? dubaiDay(Date.parse(iso)) : '');
  const fullName = (x) => (x ? x.name || String(x.email || '').split('@')[0] : c.personName || 'Someone');
  const initials = (n) => String(n).trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
  const cdId = meta && meta.cdUserId;
  const roleOf = (x) => (!x ? '' : x.id === cdId ? (meta.cdActing ? 'Acting CD' : 'Creative Director') : (meta.socialMgrIds || []).includes(x.id) && x.role === 'social' ? 'Social Manager' : ROLES[x.role] || x.role || '');
  const rows = [], rcpt = [];
  (c.groups || []).forEach((g) => {
    rows.push({ t: 'g', date: g.date ? fmtDay(g.date) : '', desc: g.title || '' });
    (g.items || []).forEach((i) => { if (i.receipt) rcpt.push(i.receipt); rows.push({ t: 'i', desc: i.desc || '', amt: i.amount !== '' && i.amount != null ? money(num(i.amount)) : '', rc: i.receipt ? rcpt.length : 0 }); });
  });
  const items = (c.groups || []).reduce((a, g) => a + (g.items || []).length, 0);
  const total = (c.groups || []).reduce((a, g) => a + (g.items || []).reduce((b, i) => b + num(i.amount), 0), 0);
  const [y, m] = String(c.month || '').split('-').map(Number);
  const name = fullName(u);
  const d = {
    month: c.month, initials: initials(name), submitted: c.submittedAt ? fmtDay(dayOf(c.submittedAt)) : '', name, monthName: m ? `${MONTHS[m - 1]} ${y}` : '',
    rows, summary: `${plural(items, 'item')} · ${plural(rcpt.length, 'receipt')} attached`, total: money(total), role: roleOf(u),
    received: c.submittedAt ? 'Received ' + fmtDay(dayOf(c.submittedAt)) : '', approved: c.approvedAt ? fmtDay(dayOf(c.approvedAt)) : '', paid: c.paidOn ? fmtDay(c.paidOn) : '', receipts: rcpt.length,
  };
  const images = {};
  try { logoJpg = logoJpg || (webDir ? await jpegOf(path.join(webDir, 'logo-tile.png'), 256) : null); } catch { logoJpg = null; }
  if (logoJpg) images.logo = logoJpg;
  const sigPath = c.signature && (c.signature.path || (typeof c.signature === 'string' ? c.signature : null));
  if (sigPath && resolve) { try { const f = resolve(sigPath); if (fs.existsSync(f)) { const j = await jpegOf(f, 220); if (j) images.sig = j; } } catch { /* no signature then */ } }
  return { pdf: claimSheetPdf(d, images), receipts: rcpt.map((r) => r.path), name: `Expense claim — ${name} — ${d.monthName}.pdf`.replace(/[\\/:*?"<>|]/g, '-') };
}
