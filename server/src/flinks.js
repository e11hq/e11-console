// File links (Haris 2026-11-03): "Copy link" on any file — Client Assets, a task's files, a comment's — gives one short
// link, files.e11hq.com/f/<token>, the same every time for that file. Pasted in the app it's still the file (a chip);
// opened by E11 staff it opens the iPhone or Mac app at the file (universal links: /.well-known/apple-app-site-
// association); for everyone else it's a branded E11 page with the file's preview and Download — no sign-in. A link
// works until its file is deleted; staff can turn it off (and on again). Never for expense claims or Finance files.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const KEY = 'flinks';
const PRIVATE = /^(Claims|Finance)\//;
const IMAGES = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'svg'];
const VIDEOS = ['mp4', 'mov', 'm4v', 'webm'];
const TOKEN = /^[A-Za-z0-9]{6,16}$/;

export function createFileLinks({ store, files, views, base, teamId, bundleId = 'ae.e11.console.ios', brandSvg = '' }) {
  const load = () => { try { return JSON.parse(store.kv.get(KEY) || '{}'); } catch { return {}; } };
  const save = (m) => store.kv.set(KEY, JSON.stringify(m));
  const newToken = () => { const a = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'; let s = ''; for (const b of crypto.randomBytes(8)) s += a[b % a.length]; return s; };
  let lastOrigin = '';
  const urlOf = (tok, origin) => `${String(base || origin || lastOrigin).replace(/\/+$/, '')}/f/${tok}`;

  // where a file is used now (a client's folder, a task's files, a comment) — nothing: it's been deleted
  function find(rel) {
    for (const c of store.list('clients')) {
      for (const f of c.folders || []) {
        const a = (f.files || []).find((x) => x && x.path === rel);
        if (a) return { att: a, where: { kind: 'asset', client: c.id, folder: f.id, file: a.id } };
      }
    }
    for (const t of store.list('tasks')) {
      if (t.deleted) continue;
      const a = (t.attachments || []).find((x) => x && x.path === rel);
      if (a) return { att: a, where: { kind: 'task', task: t.id, file: a.id } };
      for (const c of t.comments || []) {
        const b = (c.attachments || []).find((x) => x && x.path === rel);
        if (b && !c.deleted) return { att: b, where: { kind: 'comment', task: t.id, comment: c.id, file: b.id } };
      }
    }
    return null;
  }
  const onDisk = (rel) => { try { return fs.statSync(files.resolve(rel)).isFile(); } catch { return false; } };

  // the link page's pictures made ahead (Haris 2026-11-03: "the page with the picture missing"): when a link is made, and
  // for every link already out there once the server has started — a photo's two smaller copies (the soft background
  // 640, the big one 1280), else its thumbnail (PDF page, video frame, Office). One at a time, after the rest of the
  // NAS's work; each file once. (The page shows only that one small copy — a preview, as the website's and the app's; the
  // big 1280 one only when it's opened full screen — Haris 2026-11-03.)
  const warmed = new Set();
  let warmChain = Promise.resolve();
  function warm(a, rel) {
    rel = String(rel || (a && a.path) || '');
    if (!a || !rel || warmed.has(rel) || !files.makeSized) return;
    warmed.add(rel);
    const ext = extOf(a.name || rel);
    warmChain = warmChain.then(async () => {
      try {
        if (!onDisk(rel)) return;
        if (IMAGES.includes(ext) && ext !== 'svg') await files.makeSized(rel, 640);
        else if (!(a.thumb && onDisk(a.thumb))) await files.commands.thumb({ id: a.id, path: rel });
      } catch { /* the page makes it when asked, as before */ }
    });
  }
  const warmFolder = (c, f) => { for (const x of [f, ...tree(c, f)].slice(0, 40)) for (const a of (x.files || []).slice(0, 60)) if (a && a.path) warm(a, a.path); };
  function warmAll() {
    const m = load();
    for (const [, l] of Object.entries(m.links || {})) {
      if (!l || l.off) continue;
      if (l.kind === 'folder') { const hit = folderOf(l.client, l.folder); if (hit && !isFilesTop(hit.f)) warmFolder(hit.c, hit.f); }
      else { const hit = find(l.path); if (hit) warm(hit.att, l.path); }
    }
  }
  setTimeout(() => { try { warmAll(); } catch (e) { console.error('link pictures:', e.message); } }, 60_000).unref?.();

  // the link for a file (made once, then always the same)
  function linkFor(u, rel, origin) {
    if (origin) lastOrigin = origin;
    rel = String(rel || '');
    if (!rel || PRIVATE.test(rel) || rel.includes('..')) return { ok: false, error: 'This file can’t have a link' };
    const m = load();
    m.byPath = m.byPath || {}; m.links = m.links || {};
    let tok = m.byPath[rel];
    if (!tok || !m.links[tok]) {
      if (!find(rel)) return { ok: false, error: 'That file isn’t in E11 Console any more' };
      do { tok = newToken(); } while (m.links[tok]);
      m.byPath[rel] = tok; m.links[tok] = { path: rel, by: u.id, at: new Date().toISOString(), off: false };
      save(m);
    }
    { const h = find(rel); if (h) warm(h.att, rel); }
    return { ok: true, token: tok, url: urlOf(tok, origin), off: !!m.links[tok].off };
  }
  function setOff(u, rel, off, origin) {
    const r = linkFor(u, rel, origin);
    if (!r.ok) return r;
    const m = load();
    m.links[r.token].off = !!off; m.links[r.token].offBy = u.id; m.links[r.token].offAt = new Date().toISOString();
    save(m);
    return { ...r, off: !!off };
  }
  // what a link is (staff: where its file is, to open it in the app)
  function resolveToken(tok) {
    if (!TOKEN.test(String(tok || ''))) return null;
    const l = (load().links || {})[tok];
    if (!l) return null;
    const hit = find(l.path);
    return { ...l, hit, live: !!hit && !l.off && onDisk(l.path) };
  }
  const extOf = (n) => String(n || '').split('.').pop().toLowerCase();
  const size = (n) => (n >= 1e9 ? (n / 1e9).toFixed(1) + ' GB' : n >= 1e6 ? (n / 1e6).toFixed(1) + ' MB' : n >= 1e3 ? Math.round(n / 1e3) + ' KB' : (n || 0) + ' B');
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const year = () => new Date().getFullYear();

  const THUMBED = ['pdf', 'mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'];
  const hasPic = (a) => { const e = extOf(a.name || a.path); return IMAGES.includes(e) || !!a.thumb || THUMBED.includes(e); };
  // ---------- the page (Haris 2026-11-03: "a bit more interactive like WeTransfer"): the file's own picture big and soft
  // behind everything; the chosen file large on the right (a picture, a video that plays there, a PDF / Office first
  // page, or a tile with its type); a card on the left (at the bottom on a phone) with the name, type · size, who shared
  // it, and Download that fills as the file comes in, then ticks. A folder: its files in the card, each with its own
  // download ring; a tap shows that one. Copy link at the top right. Turned off: the card alone on E11's colour wash.
  const kindOf = (a) => { const e = extOf(a.name || a.path); return VIDEOS.includes(e) ? 'video' : IMAGES.includes(e) ? 'img' : hasPic(a) ? 'doc' : 'none'; };
  const sharer = (l) => { const u = l && l.by ? store.get('users', String(l.by)) : null; return u ? (u.name || String(u.email || '').split('@')[0]) : ''; };
  const ini = (n) => String(n || 'E').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join('');
  const item = (me, a) => ({ id: a.id || '', n: a.name || path.basename(a.path || '') || 'File', t: (extOf(a.name || a.path) || 'file').toUpperCase(), s: a.size || 0, z: size(a.size || 0), k: kindOf(a), u: me });
  const offCard = `<div class="offc"><span class="oi"><svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M6 18 18 6"/></svg></span><b>This link isn’t available</b><small>It was turned off, or it was removed. Ask the person who sent it for a new one.</small></div>`;
  const ogFor = (title, desc, url, img) => `<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}"><meta property="og:site_name" content="E11 Agency"><meta property="og:url" content="${esc(url)}">${img ? `<meta property="og:image" content="${esc(img)}"><meta name="twitter:card" content="summary_large_image">` : ''}`;
  const DL = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11M7 10l5 5 5-5M5 20h14"/></svg>';
  // v: { title, og, kind ('File' / 'Folder · …'), name, meta, by, back: {href, label}, folders: [{href, name, line}], items, pick, note } — or off
  function shell(title, og, v) {
    const off = !v;
    const data = off ? '[]' : JSON.stringify(v.items).replace(/</g, '\\u003c');
    const list = off ? '' : [
      ...(v.folders || []).map((x) => `<a class="f fo" href="${esc(x.href)}"><span class="th fold"><svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><path d="M3 6.5A2.5 2.5 0 0 1 5.5 4h4l2 2.2h7A2.5 2.5 0 0 1 21 8.7v8.8a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/></svg></span><span class="nm"><b>${esc(x.name)}</b><small>${esc(x.line)}</small></span><span class="chev">›</span></a>`),
      ...(v.folder ? v.items.map((it, i) => `<div class="f" data-i="${i}"><span class="th">${it.k === 'none' ? `<i>${esc(it.t)}</i>` : `<img src="${esc(it.u)}/thumb" alt="" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('i'),{textContent:'${esc(it.t)}'}))">`}${it.k === 'video' ? '<span class="pl">▶</span>' : ''}</span><span class="nm"><b>${esc(it.n)}</b><small>${esc(it.t)} · ${esc(it.z)}</small></span><a class="dl" href="${esc(it.u)}/file" data-i="${i}" title="Download" download><svg class="ring" viewBox="0 0 36 36"><circle class="tr" cx="18" cy="18" r="15"/><circle class="pg" cx="18" cy="18" r="15"/></svg>${DL}</a></div>`) : []),
    ].join('');
    const card = off ? offCard : `${v.back ? `<a class="back" href="${esc(v.back.href)}">‹ ${esc(v.back.label)}</a>` : ''}<div class="head"><div class="kind">${esc(v.kind)}</div><h1>${esc(v.name)}</h1><div class="meta">${esc(v.meta)}</div>${v.by ? `<div class="from"><i>${esc(ini(v.by))}</i><span>Shared by <b>${esc(v.by)}</b><small>E11 Agency</small></span></div>` : ''}</div>
${list ? `<div class="list">${list}</div>` : ''}${v.items.length ? `<div class="foot"><a class="big" id="big" href="${esc(v.items[v.pick || 0].u)}/file" download><span class="fill" id="fill"></span>${DL}<span id="bigt">${v.folder ? 'Download this file' : 'Download'}</span></a><div class="note">${esc(v.note)}</div></div>` : '<div class="none">No files here yet</div>'}`;
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${title ? esc(title) + ' · E11 Agency' : 'E11 Agency'}</title>${og || '<meta property="og:title" content="E11 Agency">'}<meta name="robots" content="noindex">
<meta name="color-scheme" content="light dark"><link rel="icon" href="data:,">
<style>
:root{--card:rgba(255,255,255,.94);--t:#17181b;--sub:#8a8a8e;--line:rgba(0,0,0,.08);--hov:rgba(0,0,0,.045);--btn:#17181b;--btnt:#fff;--blue:#0a84ff;--green:#30d158;
--wash:radial-gradient(circle at 25% 25%,#3d3a8f,transparent 55%),radial-gradient(circle at 80% 75%,#7b2d6b,transparent 55%),linear-gradient(135deg,#1b1c3a,#0b0b10)}
@media (prefers-color-scheme:dark){:root{--card:rgba(24,25,29,.92);--t:#eceef2;--sub:#8e8e93;--line:rgba(255,255,255,.09);--hov:rgba(255,255,255,.055);--btn:#fff;--btnt:#111}}
*{box-sizing:border-box;margin:0}
html,body{height:100%;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Inter",system-ui,sans-serif;-webkit-font-smoothing:antialiased;color:var(--t);background:#111;overflow:hidden}
a{color:inherit;text-decoration:none}button{font:inherit;color:inherit;background:none;border:0;cursor:pointer}
.bg{position:fixed;inset:0;background:var(--wash);overflow:hidden}
.bg img{position:absolute;inset:-8%;width:116%;height:116%;object-fit:cover;filter:blur(40px) saturate(1.3);opacity:0;transition:opacity .6s}.bg img.on{opacity:.95}
.bg::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,.22),rgba(0,0,0,.45))}
.top{position:fixed;top:22px;left:40px;right:40px;display:flex;justify-content:space-between;align-items:center;color:#fff;z-index:3}
.brand{display:flex;align-items:center;gap:12px}.brand svg{height:26px;width:auto}.brand svg path{fill:#fff}.brand span{font-size:10px;font-weight:700;letter-spacing:3px;opacity:.8}
.pill{height:38px;padding:0 16px;border-radius:19px;background:rgba(255,255,255,.16);-webkit-backdrop-filter:blur(20px);backdrop-filter:blur(20px);color:#fff;font-size:14px;font-weight:600;display:flex;align-items:center;gap:8px;transition:background .2s}.pill:hover{background:rgba(255,255,255,.26)}
.stage{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;padding:84px 56px 56px 520px}
.art{position:relative;display:flex;align-items:center;justify-content:center;max-width:100%;max-height:100%;width:100%;height:100%}
.art>img,.art>video{max-width:100%;max-height:100%;border-radius:18px;box-shadow:0 30px 80px rgba(0,0,0,.45);display:block;background:#000}
.art>img{cursor:zoom-in;background:transparent}.art.doc>img{background:#fff;cursor:zoom-in}
.nt{display:flex;flex-direction:column;align-items:center;gap:10px;color:#fff;text-align:center;padding:48px 40px;border-radius:24px;background:rgba(255,255,255,.1);-webkit-backdrop-filter:blur(30px);backdrop-filter:blur(30px);border:1px solid rgba(255,255,255,.15);max-width:520px}
.nt b{width:120px;height:140px;border-radius:18px;background:rgba(255,255,255,.18);display:flex;align-items:center;justify-content:center;font-size:28px;letter-spacing:1px}
.nt span{font-size:18px;font-weight:600;margin-top:8px;word-break:break-word}.nt small{font-size:13.5px;opacity:.75}
.card{position:fixed;left:40px;top:50%;transform:translateY(-50%);width:420px;max-height:calc(100vh - 150px);display:flex;flex-direction:column;background:var(--card);-webkit-backdrop-filter:blur(30px);backdrop-filter:blur(30px);border-radius:28px;box-shadow:0 24px 70px rgba(0,0,0,.35);overflow:hidden;z-index:2;animation:rise .6s cubic-bezier(.2,.8,.2,1)}
@keyframes rise{from{opacity:0;transform:translateY(calc(-50% + 24px))}}
.back{display:block;padding:18px 24px 0;font-size:14.5px;color:var(--blue);font-weight:500}
.head{padding:22px 24px 16px}.back+.head{padding-top:10px}
.kind{font-size:12px;font-weight:600;letter-spacing:.5px;text-transform:uppercase;color:var(--sub)}
.head h1{font-size:24px;font-weight:700;margin-top:6px;word-break:break-word;line-height:1.15}.head .meta{font-size:14px;color:var(--sub);margin-top:6px}
.from{display:flex;align-items:center;gap:10px;margin-top:14px;font-size:13.5px;color:var(--sub)}.from b{color:var(--t);font-weight:600}.from small{display:block;font-size:12.5px;margin-top:1px}.from span{line-height:1.3}
.from i{width:28px;height:28px;border-radius:14px;background:linear-gradient(135deg,#7b68ee,#4ea2ff);display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-style:normal;font-weight:700;flex:none}
.list{overflow:auto;border-top:1px solid var(--line);padding:6px}
.f{display:flex;align-items:center;gap:12px;padding:8px 10px;border-radius:14px;cursor:pointer;transition:background .15s}.f:hover,.f.on{background:var(--hov)}
.th{width:46px;height:46px;border-radius:10px;background:var(--line);flex:none;position:relative;display:flex;align-items:center;justify-content:center;overflow:hidden}
.th img{width:100%;height:100%;object-fit:cover;display:block}.th i{font-style:normal;font-size:10px;font-weight:800;color:var(--sub)}
.th.fold{background:#0a84ff;color:#fff}.th .pl{position:absolute;width:20px;height:20px;border-radius:10px;background:rgba(0,0,0,.5);color:#fff;display:flex;align-items:center;justify-content:center;font-size:8px}
.nm{flex:1;min-width:0}.nm b{display:block;font-size:14.5px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.nm small{font-size:12.5px;color:var(--sub)}
.chev{color:var(--sub);font-size:20px;padding:0 8px}
.dl{width:36px;height:36px;border-radius:18px;display:flex;align-items:center;justify-content:center;flex:none;position:relative;transition:background .15s}.dl:hover{background:var(--line)}
.dl .ring{position:absolute;inset:0;transform:rotate(-90deg)}.ring circle{fill:none;stroke-width:2.5}.ring .tr{stroke:var(--line)}.ring .pg{stroke:var(--blue);stroke-linecap:round;stroke-dasharray:94.2;stroke-dashoffset:94.2;transition:stroke-dashoffset .12s linear}
.dl.done{color:var(--green)}
.foot{padding:16px 20px 20px;border-top:1px solid var(--line)}
.big{position:relative;width:100%;height:54px;border-radius:16px;background:var(--btn);color:var(--btnt);font-weight:650;font-size:16.5px;overflow:hidden;display:flex;align-items:center;justify-content:center;gap:9px;transition:transform .15s,background .2s}
.big:hover{transform:translateY(-1px)}.big:active{transform:scale(.98)}.big .fill{position:absolute;left:0;top:0;bottom:0;width:0;background:var(--blue);transition:width .12s linear}
.big span,.big svg{position:relative}.big.going{background:color-mix(in srgb,var(--blue) 30%,var(--btn));color:#fff}.big.done{background:var(--green);color:#fff}
.note{font-size:12.5px;color:var(--sub);text-align:center;margin-top:10px}.none{color:var(--sub);font-size:14px;text-align:center;padding:24px}
.offc{display:flex;flex-direction:column;align-items:center;text-align:center;gap:10px;padding:40px 30px}.offc .oi{width:56px;height:56px;border-radius:28px;background:var(--line);display:flex;align-items:center;justify-content:center;color:var(--sub)}
.offc b{font-size:19px}.offc small{font-size:14px;color:var(--sub);line-height:1.45}
.lb{position:fixed;inset:0;background:rgba(0,0,0,.88);display:flex;align-items:center;justify-content:center;opacity:0;pointer-events:none;transition:opacity .25s;z-index:8}.lb.show{opacity:1;pointer-events:auto}
.lb img{max-width:90vw;max-height:86vh;border-radius:10px;transform:scale(.96);transition:transform .3s}.lb.show img{transform:none}
.lb .x,.lb .nv{position:absolute;width:44px;height:44px;border-radius:22px;background:rgba(255,255,255,.14);color:#fff;font-size:20px;display:flex;align-items:center;justify-content:center}
.lb .x{top:22px;right:22px}.lb .pv{left:22px;top:50%}.lb .nx{right:22px;top:50%}.lb .cap{position:absolute;bottom:22px;left:0;right:0;text-align:center;color:#fff;font-size:14px;opacity:.85}
.toast{position:fixed;left:50%;bottom:34px;transform:translate(-50%,20px);opacity:0;background:rgba(20,20,22,.9);color:#fff;font-size:14px;font-weight:600;padding:11px 18px;border-radius:22px;transition:.3s;z-index:9;pointer-events:none}.toast.show{opacity:1;transform:translate(-50%,0)}
@media (max-width:760px){html,body{overflow:auto}
 .stage{position:relative;padding:84px 16px 0;height:auto;min-height:0}.art{height:38vh}.art>img,.art>video{max-height:38vh}.nt{padding:26px 20px}.nt b{width:84px;height:96px;font-size:22px}
 .card{position:relative;left:auto;top:auto;transform:none;width:auto;margin:16px 16px calc(16px + env(safe-area-inset-bottom));max-height:none;animation:none}
 .top{position:fixed;top:0;left:0;right:0;padding:calc(12px + env(safe-area-inset-top)) 16px 12px;z-index:5;transition:background .25s,-webkit-backdrop-filter .25s,backdrop-filter .25s}
 .top.frost{background:rgba(16,16,22,.55);-webkit-backdrop-filter:blur(30px) saturate(1.6);backdrop-filter:blur(30px) saturate(1.6)}
 .pill .w{display:none}.pill{padding:0 11px}
 .list{overflow:visible}}
</style></head><body>
<div class="bg"><img id="bgi" alt=""></div>
<div class="top"><div class="brand">${brandSvg}<span>E11 AGENCY</span></div>${off ? '' : '<button class="pill" id="copy"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M10 14a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1"/><path d="M14 10a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"/></svg><span class="w">Copy link</span></button>'}</div>
<div class="stage"><div class="art" id="art"></div></div>
<div class="card">${card}</div>
<div class="lb" id="lb"><img id="lbi" alt=""><button class="x" id="lbx" aria-label="Close">✕</button><button class="nv pv" id="pv" aria-label="Previous">‹</button><button class="nv nx" id="nx" aria-label="Next">›</button><div class="cap" id="cap"></div></div>
<div class="toast" id="toast"></div>
<script>
(function(){var F=${data},cur=${off ? 0 : (v.pick || 0)},$=function(i){return document.getElementById(i)};
function e(s){return String(s).replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
function toast(t){var x=$('toast');x.textContent=t;x.classList.add('show');clearTimeout(x._t);x._t=setTimeout(function(){x.classList.remove('show')},1700)}
function show(i){cur=i;var f=F[i];if(!f)return;var a=$('art');a.className='art '+f.k;
 a.innerHTML=f.k==='video'?'<video controls playsinline preload="metadata" poster="'+e(f.u)+'/thumb" src="'+e(f.u)+'/view"></video>':f.k==='img'?'<img src="'+e(f.u)+'/thumb" alt="">':f.k==='doc'?'<img src="'+e(f.u)+'/thumb" alt="" onerror="this.parentNode.innerHTML=\\'<div class=nt><b>'+e(f.t)+'</b><span>'+e(f.n)+'</span><small>'+e(f.z)+'</small></div>\\'">':'<div class="nt"><b>'+e(f.t)+'</b><span>'+e(f.n)+'</span><small>'+e(f.z)+' · no preview — download to open</small></div>';
 var g=$('bgi');g.classList.remove('on');if(f.k!=='none'){g.onload=function(){g.classList.add('on')};g.src=f.u+'/thumb'}
 var im=a.querySelector('img');if(im&&(f.k==='img'||f.k==='doc'))im.onclick=open;
 document.querySelectorAll('.f[data-i]').forEach(function(r){r.classList.toggle('on',+r.dataset.i===i)});
 var b=$('big');if(b&&!b.classList.contains('going')){b.href=f.u+'/file'}}
// a download that shows how far it's come (small enough files; bigger ones go straight to the browser's download)
function get(f,step,end,fail){if(!window.fetch||!window.ReadableStream||f.s>400e6){location.href=f.u+'/file';end();return}
 fetch(f.u+'/file').then(function(r){if(!r.ok)throw 0;var t=+r.headers.get('content-length')||f.s||1,n=0,rd=r.body.getReader(),parts=[];
  function pump(){return rd.read().then(function(x){if(x.done){var u=URL.createObjectURL(new Blob(parts)),a=document.createElement('a');a.href=u;a.download=f.n;document.body.appendChild(a);a.click();a.remove();setTimeout(function(){URL.revokeObjectURL(u)},4e4);end();return}
   parts.push(x.value);n+=x.value.length;step(Math.min(1,n/t),n);return pump()})}return pump()}).catch(function(){fail()})}
function mb(n){return n>=1e9?(n/1e9).toFixed(1)+' GB':(n/1e6).toFixed(1)+' MB'}
function mark(i){var d=document.querySelector('.dl[data-i="'+i+'"]');if(!d)return;d.classList.add('done');d.querySelector('.pg').style.strokeDashoffset=0;var s=d.querySelector('svg:not(.ring)');if(s)s.innerHTML='<path d="M5 12.5l4.5 4.5L19 7.5"/>'}
var b=$('big');if(b)b.onclick=function(ev){ev.preventDefault();var f=F[cur],i=cur;if(!f||b.classList.contains('going'))return;b.classList.remove('done');b.classList.add('going');
 get(f,function(p,n){$('fill').style.width=(p*100)+'%';$('bigt').textContent=mb(n)+' of '+mb(f.s)},
 function(){b.classList.remove('going');b.classList.add('done');$('fill').style.width='0';$('bigt').textContent='Downloaded';mark(i);setTimeout(function(){b.classList.remove('done');$('bigt').textContent=F.length>1||document.querySelector('.f[data-i]')?'Download this file':'Download'},2600)},
 function(){b.classList.remove('going');$('fill').style.width='0';$('bigt').textContent='Download';toast('Download failed — try again')})};
document.querySelectorAll('.dl').forEach(function(d){d.onclick=function(ev){ev.preventDefault();ev.stopPropagation();var i=+d.dataset.i;if(d._go)return;d._go=1;var pg=d.querySelector('.pg');
 get(F[i],function(p){pg.style.strokeDashoffset=94.2*(1-p)},function(){d._go=0;mark(i)},function(){d._go=0;pg.style.strokeDashoffset=94.2;toast('Download failed — try again')})}});
document.querySelectorAll('.f[data-i]').forEach(function(r){r.onclick=function(){show(+r.dataset.i)}});
var lb=$('lb'),pics=function(){return F.map(function(f,i){return i}).filter(function(i){return F[i].k==='img'||F[i].k==='doc'})};
function open(){var f=F[cur];$('lbi').src=f.u+(f.k==='img'?'/view':'/thumb');$('cap').textContent=f.n;lb.classList.add('show');var p=pics();$('pv').style.display=$('nx').style.display=p.length>1?'':'none'}
function step(d){var p=pics(),k=p.indexOf(cur);if(k<0||p.length<2)return;show(p[(k+d+p.length)%p.length]);open()}
$('lbx').onclick=function(){lb.classList.remove('show')};lb.onclick=function(ev){if(ev.target===lb)lb.classList.remove('show')};
$('pv').onclick=function(ev){ev.stopPropagation();step(-1)};$('nx').onclick=function(ev){ev.stopPropagation();step(1)};
addEventListener('keydown',function(ev){if(!lb.classList.contains('show'))return;if(ev.key==='Escape')lb.classList.remove('show');if(ev.key==='ArrowRight')step(1);if(ev.key==='ArrowLeft')step(-1)});
var c=$('copy');if(c)c.onclick=function(){var u=location.href.replace(/\\/(file|view|thumb)$/,'');(navigator.clipboard?navigator.clipboard.writeText(u):Promise.reject()).then(function(){toast('Link copied')},function(){toast(u)})};
if(F.length)show(cur);
// (phone: the logo bar stays at the top; a frost comes in behind it once the page has scrolled — Haris 2026-11-04)
var tp=document.querySelector('.top'),fr=function(){var y=Math.max(window.scrollY||0,document.documentElement.scrollTop||0,document.body.scrollTop||0);tp.classList.toggle('frost',y>4)};
document.addEventListener('scroll',fr,true);fr();})();
</script></body></html>`;
  }
  // the file page (a file link)
  function page(tok, r) {
    if (!r || !r.live) return shell('', '', null);
    const a = r.hit.att, name = a.name || path.basename(r.path), ext = extOf(name);
    const it = item(`/f/${tok}`, a);
    return shell(name, ogFor(name, `${it.t} · ${it.z}`, urlOf(tok), hasPic(a) && ext !== 'svg' ? urlOf(tok) + '/thumb' : null),
      { kind: 'File', name, meta: `${it.t} · ${it.z}`, by: sharer(r), items: [it], pick: 0, note: 'Free to download · no sign-in' });
  }

  // ---------- folders (Haris 2026-11-03): a Client Assets folder's link — the folder as it is now, its folders and
  // files; a file opens on its own page (preview, Download) — no Download all. Not "Files" itself, only the folders in
  // it. Until the folder is deleted; Turn off link as for files.
  const isFilesTop = (f) => !!f && !f.parentId && f.name === 'Files';
  const kids = (c, f) => (c.folders || []).filter((x) => x.parentId === f.id);
  const tree = (c, f) => kids(c, f).flatMap((x) => [x, ...tree(c, x)]);
  const allFiles = (c, f) => [f, ...tree(c, f)].flatMap((x) => x.files || []);
  const folderOf = (cid, fid) => { const c = store.get('clients', cid); const f = c && (c.folders || []).find((x) => x.id === fid); return c && f ? { c, f } : null; };
  const furlOf = (tok, origin) => `${String(base || origin || lastOrigin).replace(/\/+$/, '')}/d/${tok}`;
  function folderLink(u, cid, fid, origin) {
    if (origin) lastOrigin = origin;
    const hit = folderOf(cid, fid);
    if (!hit) return { ok: false, error: 'That folder isn’t in Client Assets any more' };
    if (isFilesTop(hit.f)) return { ok: false, error: 'Files holds every job’s folder — share a folder inside it' };
    const m = load(); m.byFolder = m.byFolder || {}; m.links = m.links || {};
    const key = `${cid}/${fid}`;
    let tok = m.byFolder[key];
    if (!tok || !m.links[tok]) {
      do { tok = newToken(); } while (m.links[tok]);
      m.byFolder[key] = tok; m.links[tok] = { kind: 'folder', client: cid, folder: fid, by: u.id, at: new Date().toISOString(), off: false };
      save(m);
    }
    warmFolder(hit.c, hit.f);
    return { ok: true, token: tok, url: furlOf(tok, origin), off: !!m.links[tok].off };
  }
  function folderSetOff(u, cid, fid, off, origin) {
    const r = folderLink(u, cid, fid, origin);
    if (!r.ok) return r;
    const m = load(); Object.assign(m.links[r.token], { off: !!off, offBy: u.id, offAt: new Date().toISOString() }); save(m);
    return { ...r, off: !!off };
  }
  function resolveFolder(tok) {
    if (!TOKEN.test(String(tok || ''))) return null;
    const l = (load().links || {})[tok];
    if (!l || l.kind !== 'folder') return null;
    const hit = folderOf(l.client, l.folder);
    return { ...l, hit, live: !!hit && !l.off && !isFilesTop(hit.f) };
  }
  const COLORS = ['#ff9f0a', '#af52de', '#0a84ff', '#34c759', '#30b0c7', '#ff375f', '#5e5ce6'];
  function folderPage(tok, r, subId, pickId) {
    if (!r || !r.live) return shell('', '', null);
    const { c, f: root } = r.hit;
    const inside = [root, ...tree(c, root)];
    const f = subId ? inside.find((x) => x.id === subId) : root;
    if (!f) return shell('', '', null);
    const me = `/d/${tok}`;
    const subs = kids(c, f), fs_ = (f.files || []).filter((a) => a.path && onDisk(a.path));
    const all = allFiles(c, f);
    const line = [subs.length ? `${subs.length} folder${subs.length === 1 ? '' : 's'}` : '', `${all.length} file${all.length === 1 ? '' : 's'}`, size(all.reduce((n, a) => n + (a.size || 0), 0))].filter(Boolean).join(' · ');
    const parent = f !== root ? inside.find((x) => x.id === f.parentId) || root : null;
    const items = fs_.map((a) => item(`${me}/f/${a.id}`, a));
    const pick = Math.max(0, pickId ? fs_.findIndex((a) => a.id === pickId) : 0);
    const cover = all.find((a) => hasPic(a) && extOf(a.name) !== 'svg');
    return shell(f.name, ogFor(f.name, line, furlOf(tok), cover ? `${furlOf(tok)}/f/${cover.id}/thumb` : null), {
      kind: parent ? `Folder · ${root.name}` : `Folder · ${c.name || 'E11 Agency'}`, name: f.name, meta: line, by: sharer(r), folder: true,
      back: parent ? { href: parent === root ? me : `${me}/s/${parent.id}`, label: parent.name } : null,
      folders: subs.map((x) => ({ href: `${me}/s/${x.id}`, name: x.name, line: `${allFiles(c, x).length} file${allFiles(c, x).length === 1 ? '' : 's'}` })),
      items, pick, note: items.length ? 'Files download one by one — tap a file to look at it' : '',
    });
  }
  // a file inside a shared folder (any depth)
  function folderFile(r, fileId) {
    if (!r || !r.live) return null;
    const { c, f } = r.hit;
    for (const x of [f, ...tree(c, f)]) { const a = (x.files || []).find((y) => y.id === fileId); if (a && a.path && onDisk(a.path)) return { a, in: x }; }
    return null;
  }

  const HEAD = { 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'X-Robots-Tag': 'noindex' };
  const CSP = "default-src 'none'; img-src 'self'; media-src 'self'; connect-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'";
  const html = (req, res, ok, body) => { res.writeHead(ok ? 200 : 404, { ...HEAD, 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache', 'Content-Security-Policy': CSP }); res.end(req.method === 'HEAD' ? undefined : body); return true; };
  // a file's bytes: the download, its view (pictures, videos — ranges) or its picture
  async function sendAtt(req, res, what, a, rel) {
    const ext = extOf(a.name || rel);
    if (what === 'file') {
      const name = String(a.name || path.basename(rel)).replace(/[\r\n"]/g, '');
      const orig = res.writeHead.bind(res);
      res.writeHead = (st, h) => orig(st, { ...(h || {}), ...HEAD, 'Content-Disposition': `attachment; filename="${name.replace(/[^\x20-\x7e]/g, '_')}"; filename*=UTF-8''${encodeURIComponent(name)}`, 'Cache-Control': 'private, max-age=300' });
      files.serve(req, res, rel); return true;
    }
    if (what === 'view') {
      if (VIDEOS.includes(ext)) { files.serve(req, res, views ? views.viewPath(rel) : rel); return true; }
      if (ext === 'svg') { files.serve(req, res, rel); return true; }   // (served with its own no-script rules — files.serve)
      if (IMAGES.includes(ext)) { await files.serveSized(req, res, rel, 1280); return true; }
      res.writeHead(404, HEAD); res.end(); return true;
    }
    // its picture: a smaller copy of a photo, else the picture made for its thumbnail (PDF page, video frame, Office)
    if (IMAGES.includes(ext) && ext !== 'svg') { await files.serveSized(req, res, rel, 640); return true; }
    let t = a.thumb && onDisk(a.thumb) ? a.thumb : null;
    if (!t) { try { const x = await files.commands.thumb({ id: a.id, path: rel }); t = x && x.thumb; } catch { t = null; } }
    if (!t) { res.writeHead(404, HEAD); res.end(); return true; }
    files.serve(req, res, t); return true;
  }
  // the public part (no sign-in): file links /f/<token>[/file|view|thumb]; folder links /d/<token>, its folders
  // /d/<token>/s/<folder>, its files /d/<token>/f/<file>[/file|view|thumb]
  async function serve(req, res, p) {
    if (p === '/.well-known/apple-app-site-association' || p === '/apple-app-site-association') {
      const ids = teamId ? [`${teamId}.${bundleId}`] : [];
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' });
      res.end(JSON.stringify({ applinks: { details: [{ appIDs: ids, components: [{ '/': '/f/*', comment: 'File links open in the E11 Console app' }, { '/': '/d/*', comment: 'Folder links open in the E11 Console app' }, { '/': '/t/*', comment: 'Task links open in the E11 Console app' }] }] } }));
      return true;
    }
    let m = /^\/f\/([A-Za-z0-9]{6,16})(?:\/(file|view|thumb))?\/?$/.exec(p);
    if (m) {
      const [, tok, what] = m;
      const r = resolveToken(tok);
      if (!what) return html(req, res, r && r.live, page(tok, r));
      if (!r || !r.live) { res.writeHead(404, HEAD); res.end('Not available'); return true; }
      return sendAtt(req, res, what, r.hit.att, r.path);
    }
    m = /^\/d\/([A-Za-z0-9]{6,16})(?:\/s\/([\w-]{1,80}))?\/?$/.exec(p);
    if (m) { const r = resolveFolder(m[1]); const body = folderPage(m[1], r, m[2] || null); return html(req, res, r && r.live && !body.includes('This link isn’t available'), body); }
    m = /^\/d\/([A-Za-z0-9]{6,16})\/f\/([\w-]{1,80})(?:\/(file|view|thumb))?\/?$/.exec(p);
    if (m) {
      const [, tok, fid, what] = m;
      const r = resolveFolder(tok), hit = folderFile(r, fid);
      if (!what) {
        if (!hit) return html(req, res, false, shell('', '', null));
        // (the folder it's in, with this file chosen)
        return html(req, res, true, folderPage(tok, r, hit.in.id === r.hit.f.id ? null : hit.in.id, fid));
      }
      if (!hit) { res.writeHead(404, HEAD); res.end('Not available'); return true; }
      return sendAtt(req, res, what, hit.a, hit.a.path);
    }
    return false;
  }
  // for staff with the app: where the file is, so the app opens it there
  function where(u, tok, canRead) {
    const fr = resolveFolder(tok);
    if (fr) {
      if (!fr.hit) return { ok: false, error: 'That folder has been deleted' };
      if (!canRead(u, (fr.hit.f.dir || fr.hit.c.dir || 'Clients/x') + '/_')) return { ok: false, error: 'That folder is for the people working on it' };
      return { ok: true, off: !!fr.off, where: { kind: 'folder', client: fr.client, folder: fr.folder }, name: fr.hit.f.name };
    }
    const r = resolveToken(tok);
    if (!r) return { ok: false, error: 'That link isn’t in E11 Console' };
    if (!r.hit) return { ok: false, error: 'That file has been deleted' };
    if (!canRead(u, r.path)) return { ok: false, error: 'That file is for the people working on it' };
    const a = r.hit.att;
    return { ok: true, path: r.path, off: !!r.off, where: r.hit.where, att: { id: a.id, name: a.name, path: a.path, size: a.size || 0, ...(a.thumb ? { thumb: a.thumb } : {}), ...(a.type ? { type: a.type } : {}) } };
  }
  // (which of these are turned off: file paths, and folders as "d:<client>/<folder>")
  const offOf = (paths) => { const m = load(); return paths.filter((x) => { const t = /^d:/.test(x) ? (m.byFolder || {})[x.slice(2)] : (m.byPath || {})[x]; return t && m.links[t] && m.links[t].off; }); };
  return { linkFor, setOff, resolveToken, serve, where, urlOf, find, offOf, folderLink, folderSetOff, resolveFolder };
}
