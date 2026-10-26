// The content plan for the client: an E11-branded PowerPoint (and a PDF of it) with each finished post's CD-approved
// video or graphic, and the client's PowerPoint read back (their comments and links per post).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { createDeck } from './pptx.js';
import { unzip } from './zip.js';

const ASSET = (n) => new URL(n, import.meta.url);
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const WD = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const FMT = { post: ['Post', '8B8B96'], carousel: ['Carousel', '7B68EE'], reel: ['Reel', 'E5484D'], story: ['Story', 'F2B23E'], video: ['Video', '3DDC97'] };
const CH = { ig: 'Instagram', tt: 'TikTok', li: 'LinkedIn', x: 'X', fb: 'Facebook', yt: 'YouTube', sc: 'Snapchat', edm: 'EDM' };
const ACCENT = '7B68EE', INK = '111111', GREY = '5F5F5F', MUTED = '6B6B6B', LINE = 'E3E3E3', BOX = 'F7F7F7', OCC = 'B8410F';
// a different line on the Thank you slide each time (Haris approved these)
export const LINES = [
  '{Month}, planned. Now let’s make it unforgettable.', 'Here’s to a month your audience won’t scroll past.', 'Good things are coming to your feed.',
  'Your brand, our craft, one great month ahead.', 'Every post here started with you in mind.', 'We bring the ideas. You bring the magic.',
  'Here’s to the posts people stop for.', 'Thirty days, one story, told beautifully.', 'Ready when you are. Let’s make some noise.',
  'Great ideas are better shared. Thanks for building this one with us.', 'Thanks for trusting us with your story, again.', 'The best content starts with a great partner.',
];
const IMG = new Set(['png', 'jpg', 'jpeg', 'gif']);
const VID = new Set(['mp4', 'm4v', 'mov']);
const extOf = (n) => (String(n).split('.').pop() || '').toLowerCase();
const run = (cmd, args, ms = 120000) => new Promise((ok, no) => execFile(cmd, args, { timeout: ms, maxBuffer: 8 << 20 }, (err) => (err ? no(err) : ok())));
const parseYmd = (s) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); };
const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const dayLong = (s) => parseYmd(s).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });

// width and height of a PNG, JPEG or GIF
export function imageSize(buf) {
  try {
    if (buf[0] === 0x89 && buf[1] === 0x50) return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
    if (buf[0] === 0x47 && buf[1] === 0x49) return { w: buf.readUInt16LE(6), h: buf.readUInt16LE(8) };
    if (buf[0] === 0xff && buf[1] === 0xd8) {
      let p = 2;
      while (p < buf.length) {
        if (buf[p] !== 0xff) { p++; continue; }
        const m = buf[p + 1], len = buf.readUInt16BE(p + 2);
        if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) return { w: buf.readUInt16BE(p + 7), h: buf.readUInt16BE(p + 5) };
        p += 2 + len;
      }
    }
  } catch { /* unknown */ }
  return null;
}

export function createPlanDeck({ filesRoot }) {
  // a stored path inside the files folder (task files and Client Assets only; never out with "..")
  const abs = (rel) => {
    const s = String(rel || '');
    if (!/^(attachments|Clients)\//.test(s) || s.split('/').some((x) => x === '..' || x === '.' || x === '') || s.includes('\\')) throw new Error('bad path');
    const f = path.resolve(filesRoot, ...s.split('/'));
    if (!f.startsWith(path.resolve(filesRoot) + path.sep)) throw new Error('bad path');
    return f;
  };
  const tmpDir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'e11-deck-'));

  // a picture the slide can hold: PNG / JPEG / GIF as they are; anything else (HEIC, WebP, SVG…) turned into PNG / JPEG
  async function picture(rel) {
    const ext = extOf(rel);
    let file;
    try { file = abs(rel); } catch { return null; }
    if (!fs.existsSync(file)) return null;
    if (IMG.has(ext)) { const data = fs.readFileSync(file); const d = imageSize(data); return { data, ext: ext === 'jpg' ? 'jpeg' : ext, w: d && d.w, h: d && d.h }; }
    const tmp = tmpDir();
    try {
      if (ext === 'svg') {
        await run('soffice', ['-env:UserInstallation=file:///tmp/e11-libreoffice', '--headless', '--norestore', '--convert-to', 'png', '--outdir', tmp, file], 90000);
        const out = path.join(tmp, path.basename(file).replace(/\.svg$/i, '.png'));
        if (fs.existsSync(out)) { const data = fs.readFileSync(out); const d = imageSize(data); return { data, ext: 'png', w: d && d.w, h: d && d.h }; }
        return null;
      }
      const out = path.join(tmp, 'p.png');
      await run('ffmpeg', ['-y', '-loglevel', 'error', '-i', file, '-frames:v', '1', out], 60000);
      const data = fs.readFileSync(out); const d = imageSize(data); return { data, ext: 'png', w: d && d.w, h: d && d.h };
    } catch { return null; } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }
  // a still from a video, for its slide (and the PDF)
  async function poster(rel) {
    const tmp = tmpDir();
    try {
      const out = path.join(tmp, 'f.jpg');
      await run('ffmpeg', ['-y', '-loglevel', 'error', '-ss', '0.8', '-i', abs(rel), '-frames:v', '1', '-vf', 'scale=1280:-2', out], 60000).catch(() => run('ffmpeg', ['-y', '-loglevel', 'error', '-i', abs(rel), '-frames:v', '1', '-vf', 'scale=1280:-2', out], 60000));
      const data = fs.readFileSync(out); const d = imageSize(data); return { data, ext: 'jpeg', w: d && d.w, h: d && d.h };
    } catch { return null; } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }

  /* d = { plan, clientName, month, round, posts: [{ post, files: [{ name, path, w, h }] }], occasions: [{ name, date, end }],
           preparedBy, amNames, logoRel, line, sentAt } → { pptx: Buffer } */
  async function build(d) {
    const deck = createDeck({ title: `${d.clientName} · Content plan · ${d.monthLabel}`, author: 'E11' });
    const W = 13.333;
    const total = d.posts.length + 4;
    const mark = { white: fs.readFileSync(ASSET('e11-mark-white.png')), black: fs.readFileSync(ASSET('e11-mark-black.png')) };
    const footer = (s, n, dark) => {
      s.box({ x: 0.58, y: 7.02, w: W - 1.16, h: 0.006, fill: dark ? '333333' : LINE });
      if (!dark) s.image({ x: 0.58, y: 7.14, w: 0.3, h: 0.155, data: mark.black, ext: 'png', iw: 656, ih: 338, name: 'E11' });
      s.text({ x: dark ? 0.58 : 0.98, y: 7.1, w: 7, h: 0.25, paras: [{ t: `${d.clientName} · Content plan · ${d.monthLabel}`, size: 9, color: dark ? 'BDBDBD' : MUTED }] });
      s.text({ x: W - 3.58, y: 7.1, w: 3, h: 0.25, paras: [{ t: `Round ${d.round} · ${String(n).padStart(2, '0')} / ${total}`, size: 9, color: dark ? 'BDBDBD' : MUTED, align: 'right' }] });
    };
    const label = (s, x, y, w, t, color = MUTED) => s.text({ x, y, w, h: 0.22, paras: [{ t: t.toUpperCase(), size: 8.5, bold: true, color }] });

    // 1 · cover
    {
      const s = deck.slide({ bg: 'FFFFFF', name: 'Cover' });
      s.box({ x: 0, y: 0, w: 5.42, h: 7.5, fill: INK });
      s.image({ x: 0.58, y: 0.58, w: 1.25, h: 0.65, data: mark.white, ext: 'png', iw: 656, ih: 338, name: 'E11' });
      s.box({ x: 0.58, y: 4.3, w: 0.5, h: 0.06, fill: ACCENT });
      s.text({ x: 0.58, y: 4.55, w: 4.4, h: 1.7, paras: [{ t: 'Content\nplan', size: 54, bold: true, color: 'FFFFFF', line: 0.95 }] });
      s.text({ x: 0.58, y: 6.3, w: 4.4, h: 0.4, paras: [{ t: `For your review · Round ${d.round}`, size: 13.5, color: 'BDBDBD' }] });
      if (d.logo) s.image({ x: W - 0.67 - 2.3, y: 0.58, w: 2.3, h: 1.15, data: d.logo.data, ext: d.logo.ext, iw: d.logo.w, ih: d.logo.h, name: 'Client logo' });
      s.text({ x: 6.08, y: 3.0, w: 6.6, h: 0.4, paras: [{ t: d.clientName, size: 15, color: GREY }] });
      s.text({ x: 6.08, y: 3.4, w: 6.8, h: 1.1, paras: [{ t: d.monthLabel, size: 60, bold: true, color: INK, line: 1 }] });
      const chans = [...new Set(d.posts.flatMap((x) => x.post.channels || []))].map((k) => CH[k]).filter(Boolean);
      s.text({ x: 6.08, y: 4.55, w: 6.8, h: 0.4, paras: [{ t: `${d.posts.length} post${d.posts.length === 1 ? '' : 's'}${d.occasions.length ? ` · ${d.occasions.length} occasion${d.occasions.length === 1 ? '' : 's'}` : ''}${chans.length ? ` · ${chans.slice(0, 4).join(', ')}` : ''}`, size: 15, color: GREY }] });
      s.box({ x: 6.08, y: 6.05, w: 6.6, h: 0.006, fill: LINE });
      [['Prepared by', d.preparedBy || '—'], ['Account manager', d.amNames || '—'], ['Sent', d.sentLabel], ['Version', `Round ${d.round}`]].forEach(([k, v], i) => {
        label(s, 6.08 + i * 1.68, 6.25, 1.6, k);
        s.text({ x: 6.08 + i * 1.68, y: 6.5, w: 1.62, h: 0.5, paras: [{ t: v, size: 12, color: INK }] });
      });
    }

    // 2 · month at a glance (the posts in this round)
    {
      const s = deck.slide({ bg: 'FFFFFF', name: 'Month at a glance' });
      label(s, 0.58, 0.42, 5, 'Month at a glance');
      s.text({ x: 0.58, y: 0.65, w: 6, h: 0.55, paras: [{ t: d.monthLabel, size: 28, bold: true, color: INK }] });
      const [y0, m0] = d.month.split('-').map(Number);
      const first = new Date(y0, m0 - 1, 1), last = new Date(y0, m0, 0);
      const start = new Date(first); start.setDate(1 - ((first.getDay() + 6) % 7));
      const weeks = Math.ceil(((first.getDay() + 6) % 7 + last.getDate()) / 7);
      const gx = 0.58, gy = 1.55, gw = 9.05, cw = gw / 7, ch = (6.75 - gy - 0.25) / weeks;
      WD.forEach((w, i) => s.text({ x: gx + i * cw + 0.06, y: gy - 0.3, w: cw, h: 0.25, paras: [{ t: w.toUpperCase(), size: 8.5, bold: true, color: MUTED }] }));
      for (let i = 0; i < weeks * 7; i++) {
        const day = new Date(start); day.setDate(start.getDate() + i);
        const key = ymd(day), inM = day.getMonth() === m0 - 1;
        const cx = gx + (i % 7) * cw, cy = gy + Math.floor(i / 7) * ch;
        s.box({ x: cx, y: cy, w: cw, h: ch, fill: inM ? 'FFFFFF' : 'FAFAFA', line: { color: 'EEEEEE', w: 0.75 } });
        if (!inM) continue;
        const occ = d.occasions.filter((o) => o.date <= key && (o.end || o.date) >= key && (o.date === key || !o.end));
        const paras = [{ t: String(day.getDate()), size: 9.5, bold: true, color: '3F3F3F', after: 1 }];
        occ.slice(0, 1).forEach((o) => paras.push({ t: o.name, size: 7.5, bold: true, color: OCC, after: 1 }));
        s.text({ x: cx + 0.05, y: cy + 0.04, w: cw - 0.1, h: 0.45, paras });
        d.posts.filter((x) => x.post.day === key).slice(0, 2).forEach((x, j) => {
          const f = FMT[x.post.format] || FMT.post;
          const by = cy + 0.42 + j * 0.34;
          if (by + 0.3 > cy + ch) return;
          s.box({ x: cx + 0.05, y: by, w: 0.04, h: 0.3, fill: f[1] });
          s.box({ x: cx + 0.09, y: by, w: cw - 0.14, h: 0.3, fill: 'F1F1F1', inset: 0.04, anchor: 'middle', paras: [{ t: `${String(x.n).padStart(2, '0')} · ${x.post.title || 'Post'}`, size: 7, color: INK }] });
        });
      }
      // occasions and counts
      const sx = 9.95;
      label(s, sx, 1.25, 2.8, 'Occasions');
      let oy = 1.5;
      (d.occasions.length ? d.occasions : [{ name: 'None this month', date: '' }]).slice(0, 6).forEach((o) => {
        const posts = d.posts.filter((x) => x.post.occasion === o.id);
        s.text({ x: sx, y: oy, w: 2.8, h: 0.5, paras: [{ runs: [{ t: o.date ? `${parseYmd(o.date).getDate()} ${MONTHS[parseYmd(o.date).getMonth()].slice(0, 3)}  ` : '', bold: true, size: 10.5 }, { t: o.name, size: 10.5 }], after: 0 }, ...(posts.length ? [{ t: posts.map((x) => `Post ${String(x.n).padStart(2, '0')}`).join(', '), size: 9, color: GREY }] : [])] });
        oy += 0.55;
      });
      label(s, sx, Math.max(oy + 0.1, 4.7), 2.8, 'In this round');
      const by = Math.max(oy + 0.35, 4.95);
      Object.entries(FMT).map(([k, [nm]]) => [nm, d.posts.filter((x) => (x.post.format || 'post') === k).length]).filter(([, n]) => n).slice(0, 3).forEach(([nm, n], i) => {
        s.box({ x: sx + i * 0.95, y: by, w: 0.88, h: 0.8, fill: 'F4F4F4', radius: 0.08, inset: 0.1, paras: [{ t: String(n), size: 20, bold: true, color: INK, after: 0 }, { t: `${nm}${n === 1 ? '' : 's'}`, size: 9, color: '4F4F4F' }] });
      });
      footer(s, 2);
    }

    // 3… · one slide per finished post
    let vidBytes = 0;
    for (const x of d.posts) {
      const p = x.post, f = FMT[p.format] || FMT.post;
      const s = deck.slide({ bg: 'FFFFFF', name: `E11 post ${p.id}` });
      s.text({ x: 0.58, y: 0.36, w: 1.2, h: 0.85, paras: [{ t: String(x.n).padStart(2, '0'), size: 46, bold: true, color: ACCENT }] });
      label(s, 1.75, 0.42, 6, `${dayLong(p.day)} · Go-live`);
      s.text({ x: 1.75, y: 0.66, w: 6.4, h: 0.5, paras: [{ t: p.title || 'Post', size: 24, bold: true, color: INK }] });
      const chips = [f[0], ...(p.channels || []).map((k) => CH[k]).filter(Boolean), ...(x.occasionName ? [x.occasionName] : [])];
      s.text({ x: 8.3, y: 0.62, w: W - 8.88, h: 0.5, paras: [{ t: chips.join('  ·  '), size: 10, color: '3F3F3F', align: 'right' }] });
      // the finished work
      const ax = 0.58, ay = 1.45, aw = 4.6, ah = 4.05;
      const media = [];
      for (const fl of x.files.slice(0, 4)) {
        const ext = extOf(fl.name || fl.path);
        if (VID.has(ext)) {
          const size = fs.existsSync(abs(fl.path)) ? fs.statSync(abs(fl.path)).size : 0;
          const ps = await poster(fl.path);
          media.push({ kind: 'video', fl, ps, size, ext: ext === 'mov' ? 'mov' : 'mp4' });
        } else {
          const pic = await picture(fl.path);
          if (pic) media.push({ kind: 'image', pic, fl });
        }
      }
      if (!media.length) s.box({ x: ax, y: ay, w: aw, h: ah, fill: 'F4F4F4', radius: 0.08, anchor: 'middle', paras: [{ t: 'Finished work', size: 11, color: MUTED, align: 'center' }] });
      const place = (m, bx, by, bw, bh, fit) => {
        if (m.kind === 'image') return s.image({ x: bx, y: by, w: bw, h: bh, data: m.pic.data, ext: m.pic.ext, iw: m.pic.w, ih: m.pic.h, fit, name: m.fl.name, alt: m.fl.name });
        if (m.ps && m.size && m.size < 200e6 && vidBytes + m.size < 450e6) { vidBytes += m.size; return s.video({ x: bx, y: by, w: bw, h: bh, data: fs.readFileSync(abs(m.fl.path)), ext: m.ext, poster: m.ps, iw: m.ps.w, ih: m.ps.h, name: m.fl.name }); }
        if (m.ps) s.image({ x: bx, y: by, w: bw, h: bh, data: m.ps.data, ext: m.ps.ext, iw: m.ps.w, ih: m.ps.h, fit, name: m.fl.name });
        s.text({ x: bx, y: by + bh - 0.3, w: bw, h: 0.3, paras: [{ t: `Video: ${m.fl.name}${m.size >= 200e6 ? ' (sent separately)' : ''}`, size: 8.5, color: MUTED }] });
      };
      if (media.length === 1) place(media[0], ax, ay, aw, ah, 'fit');
      else if (media.length > 1) {
        const cols = 2, rows = Math.ceil(media.length / 2), gap = 0.1, cw = (aw - gap) / cols, chh = (ah - gap * (rows - 1)) / rows;
        media.forEach((m, i) => place(m, ax + (i % 2) * (cw + gap), ay + Math.floor(i / 2) * (chh + gap), cw, chh, 'cover'));
      }
      if (x.files.length > 4) s.text({ x: ax, y: ay + ah + 0.02, w: aw, h: 0.22, paras: [{ t: `+ ${x.files.length - 4} more`, size: 8.5, color: MUTED }] });
      // the words
      const rx = 5.55, rw = W - rx - 0.58;
      label(s, rx, 1.45, rw / 2 - 0.15, 'Copy · English');
      s.text({ x: rx, y: 1.7, w: rw / 2 - 0.15, h: 1.9, paras: [{ t: p.copyEn || '—', size: 11.5, color: INK, line: 1.3 }] });
      label(s, rx + rw / 2 + 0.15, 1.45, rw / 2 - 0.15, 'Copy · Arabic');
      s.text({ x: rx + rw / 2 + 0.15, y: 1.7, w: rw / 2 - 0.15, h: 1.9, paras: [{ t: p.copyAr || '—', size: 12.5, color: INK, rtl: !!p.copyAr, line: 1.4 }] });
      s.box({ x: rx, y: 3.75, w: rw, h: 0.006, fill: 'EEEEEE' });
      label(s, rx, 3.9, rw, 'The idea');
      s.text({ x: rx, y: 4.15, w: rw, h: 1.3, paras: [{ t: p.desc || '—', size: 11, color: '2B2B2B', line: 1.3 }] });
      // for the client to fill in
      label(s, 0.58, 5.68, 6, 'Client comments', INK);
      s.box({ x: 0.58, y: 5.92, w: 8.1, h: 1.0, fill: BOX, line: { color: 'BDBDBD', dash: true }, radius: 0.08, inset: 0.12, name: `E11 client comments ${p.id}`, style: { size: 11, color: INK } });
      label(s, 8.88, 5.68, 3.8, 'Reference links', INK);
      s.box({ x: 8.88, y: 5.92, w: W - 8.88 - 0.58, h: 1.0, fill: BOX, line: { color: 'BDBDBD', dash: true }, radius: 0.08, inset: 0.12, name: `E11 reference links ${p.id}`, style: { size: 10, color: INK } });
      footer(s, x.n + 2);
    }

    // how to review
    {
      const s = deck.slide({ bg: INK, name: 'How to review' });
      s.box({ x: 0.58, y: 0.6, w: 0.5, h: 0.06, fill: ACCENT });
      s.text({ x: 0.58, y: 0.8, w: 7, h: 0.8, paras: [{ t: 'How to review', size: 38, bold: true, color: 'FFFFFF' }] });
      [['Comment on each post', 'Type in the grey Client comments box on the post’s slide. PowerPoint comments work too.'], ['Add references', 'Paste any links you’d like us to look at in the Reference links box.'], ['Send it back', `Save the file and reply to our email with it attached. We’ll come back with Round ${d.round + 1} if anything changes.`]].forEach(([t, b], i) => {
        const y = 2.0 + i * 1.05;
        s.box({ x: 0.58, y, w: 0.4, h: 0.4, fill: '111111', line: { color: '6B6B6B', w: 1.25 }, radius: 0.2, anchor: 'middle', inset: 0, paras: [{ t: String(i + 1), size: 11, bold: true, color: 'FFFFFF', align: 'center' }] });
        s.text({ x: 1.2, y: y - 0.02, w: 6.3, h: 1, paras: [{ t, size: 14.5, bold: true, color: 'FFFFFF', after: 2 }, { t: b, size: 12, color: 'BDBDBD', line: 1.3 }] });
      });
      const bx = W - 0.58 - 4.6;
      s.box({ x: bx, y: 0.75, w: 4.6, h: 4.9, fill: 'FFFFFF', radius: 0.1 });
      label(s, bx + 0.3, 0.98, 4, 'Client approval');
      s.text({ x: bx + 0.3, y: 1.25, w: 4, h: 0.6, paras: [{ t: 'Happy with the whole month? Fill this in and send the file back.', size: 12, color: INK, line: 1.3 }] });
      [['Approved by', 0.45], ['Date', 0.45], ['Overall comments', 0.85]].reduce((y, [k, h]) => {
        s.text({ x: bx + 0.3, y, w: 4, h: 0.25, paras: [{ t: k, size: 10, bold: true, color: INK }] });
        s.box({ x: bx + 0.3, y: y + 0.27, w: 4, h, fill: BOX, line: { color: 'BDBDBD', dash: true }, radius: 0.06, inset: 0.08, name: `E11 approval ${k}`, style: { size: 11, color: INK } });
        return y + h + 0.5;
      }, 2.05);
      s.image({ x: 0.58, y: 6.8, w: 0.75, h: 0.39, data: mark.white, ext: 'png', iw: 656, ih: 338, name: 'E11' });
      s.text({ x: 4.5, y: 6.88, w: W - 5.08, h: 0.3, paras: [{ t: `Questions? ${d.amNames || 'Your account manager'}   ·   Round ${d.round} · ${String(total - 1).padStart(2, '0')} / ${total}`, size: 10, color: 'BDBDBD', align: 'right' }] });
    }

    // thank you
    {
      const s = deck.slide({ bg: INK, name: 'Thank you' });
      s.image({ x: W / 2 - 1.25, y: 1.7, w: 2.5, h: 1.3, data: mark.white, ext: 'png', iw: 656, ih: 338, name: 'E11' });
      s.text({ x: 1.5, y: 3.55, w: W - 3, h: 0.9, paras: [{ t: d.line, size: 22, color: 'D9D9D9', align: 'center', line: 1.3 }] });
      s.box({ x: W / 2 - 0.25, y: 4.6, w: 0.5, h: 0.06, fill: ACCENT });
      s.text({ x: 1.5, y: 4.85, w: W - 3, h: 0.9, paras: [{ t: 'Thank you', size: 46, bold: true, color: 'FFFFFF', align: 'center' }] });
    }
    return deck.build();
  }

  // the PDF of a PowerPoint (LibreOffice); null when it can't be made
  async function toPdf(pptxBuf, name) {
    const tmp = tmpDir();
    try {
      const src = path.join(tmp, 'deck.pptx');
      fs.writeFileSync(src, pptxBuf);
      await run('soffice', ['-env:UserInstallation=file:///tmp/e11-libreoffice', '--headless', '--norestore', '--convert-to', 'pdf', '--outdir', tmp, src], 240000);
      const out = path.join(tmp, 'deck.pdf');
      return fs.existsSync(out) ? fs.readFileSync(out) : null;
    } catch { return null; } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }
  return { build, toPdf, picture };
}

/* The client's PowerPoint back: per post (found by the slide's name / its comment box), what they typed in the Client
   comments and Reference links boxes, PowerPoint comments on that slide (old and new kinds) and links on it.
   → { posts: { [postId]: { comments: [text], links: [url] } }, approval: { by, date, comments } } */
export function readReturnedDeck(buf) {
  const z = unzip(buf, (n) => /^ppt\/(slides\/(_rels\/)?slide\d+\.xml(\.rels)?|comments\/.*\.xml)$/.test(n));
  const dec = (s) => String(s).replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n)).replace(/&amp;/g, '&');
  const texts = (xml) => {
    const paras = String(xml).split(/<\/a:p>/).map((p) => [...p.matchAll(/<a:t>([^<]*)<\/a:t>/g)].map((m) => dec(m[1])).join('')).filter((t) => t.trim());
    return paras.join('\n').trim();
  };
  const out = { posts: {}, approval: {} };
  const urlRe = /\bhttps?:\/\/[^\s<>"')]+|\bwww\.[^\s<>"')]+/gi;
  for (const [name, data] of z) {
    const m = /^ppt\/slides\/slide(\d+)\.xml$/.exec(name);
    if (!m) continue;
    const xml = data.toString('utf8');
    const shapes = xml.split('<p:sp>').slice(1).map((sp) => ({ name: dec((/<p:cNvPr [^>]*name="([^"]*)"/.exec(sp) || [])[1] || ''), sp }));
    const id = (/name="E11 post ([^"]+)"/.exec(xml) || [])[1] || ((shapes.find((s) => /^E11 client comments /.test(s.name)) || {}).name || '').replace(/^E11 client comments /, '');
    shapes.filter((s) => /^E11 approval /.test(s.name)).forEach((s) => { const t = texts(s.sp); if (t) out.approval[s.name.replace(/^E11 approval /, '').toLowerCase()] = t; });
    if (!id) continue;
    const box = shapes.find((s) => s.name === `E11 client comments ${id}`);
    const lnk = shapes.find((s) => s.name === `E11 reference links ${id}`);
    const comments = [];
    const links = [];
    if (box) { const t = texts(box.sp); if (t) comments.push(t); }
    if (lnk) { const t = texts(lnk.sp); if (t) { (t.match(urlRe) || []).forEach((u) => links.push(u)); const rest = t.replace(urlRe, '').trim(); if (rest && !(t.match(urlRe) || []).length) comments.push(rest); } }
    // links and comments attached to the slide
    const rels = (z.get(`ppt/slides/_rels/slide${m[1]}.xml.rels`) || Buffer.from('')).toString('utf8');
    for (const r of rels.matchAll(/<Relationship [^>]*>/g)) {
      const tag = r[0], target = dec((/Target="([^"]*)"/.exec(tag) || [])[1] || ''), type = (/Type="([^"]*)"/.exec(tag) || [])[1] || '';
      if (/\/hyperlink$/.test(type) && /^https?:/i.test(target)) links.push(target);
      if (/comments$/i.test(type)) {
        const file = path.posix.normalize(path.posix.join('ppt/slides', target));
        const cx = z.get(file);
        if (!cx) continue;
        const cxml = cx.toString('utf8');
        // old comments: <p:text>…</p:text>; new ones: paragraphs in each comment and reply
        const old = [...cxml.matchAll(/<p:text>([^<]*)<\/p:text>/g)].map((x) => dec(x[1]).trim()).filter(Boolean);
        const neu = cxml.split(/<\/p188:(?:cm|reply)>/).map((c) => texts(c)).filter(Boolean);
        (old.length ? old : neu).forEach((t) => { comments.push(t); (t.match(urlRe) || []).forEach((u) => links.push(u)); });
      }
    }
    const fix = (u) => (/^www\./i.test(u) ? 'https://' + u : u);
    out.posts[id] = { comments: [...new Set(comments)], links: [...new Set(links.map(fix))] };
  }
  return out;
}
