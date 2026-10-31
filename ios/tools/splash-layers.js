// Renders the startup screen's icon (web/index.html #splash .sp-mark) as separate transparent layers for the iPhone
// app's native startup screen (ios/App/Splash.swift), which animates them as the page does (styles.css spCard…).
// Each layer is the whole picture area — the icon's 824-unit square plus 100 units all round for the shadows
// (viewBox 0 0 1024 1024) — at 492 px, i.e. 3× the 164 pt the app draws it at (the icon itself: 132 pt, as on the page).
// Run (from the repo): NODE_PATH=$(npm root -g) node ios/tools/splash-layers.js
const { chromium } = require('playwright');
const path = require('path'), fs = require('fs');
const repo = path.resolve(__dirname, '../..');
const out = path.join(repo, 'ios/App/Assets.xcassets');
const layers = {
  SplTile: ['.sp-bg'],
  SplGreen: ['.sp-green'],
  SplYellow: ['.sp-yellow'],
  SplFront: ['.sp-front', ['.sp-e11', '.sp-ln', '.sp-check']],
  SplE11: ['.sp-e11'],
  SplLine1: ['.sp-l1'],
  SplLine2: ['.sp-l2'],
  SplCheck: ['.sp-check'],
};
// the five files that fly in (PNG, MP4, PDF, DOCX, AI), each in the dark and the light look
for (let i = 1; i <= 5; i++) { layers[`SplFile${i}Dark`] = [`.sp-files > .spf:nth-child(${i})`, [], 'dark']; layers[`SplFile${i}Light`] = [`.sp-files > .spf:nth-child(${i})`, [], 'light']; }
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ javaScriptEnabled: false, viewport: { width: 600, height: 600 }, deviceScaleFactor: 1 });
  const p = await ctx.newPage();
  await p.goto('file://' + path.join(repo, 'web/index.html'));
  for (const [name, [sel, hide = [], theme = 'dark']] of Object.entries(layers)) {
    await p.evaluate(({ sel, hide, theme }) => {
      const sp = document.getElementById('splash');
      document.body.innerHTML = ''; document.body.appendChild(sp);
      document.documentElement.style.background = 'transparent'; document.body.style.background = 'transparent';
      sp.className = theme === 'light' ? 'light' : '';
      sp.style.cssText = 'position:static;display:block;background:transparent;box-shadow:none;width:492px;height:492px';
      [...sp.children].forEach((c) => { if (!c.classList.contains('sp-center')) c.style.display = 'none'; });
      const c = sp.querySelector('.sp-center'); [...c.children].forEach((x) => { if (!x.classList.contains('sp-mark')) x.style.display = 'none'; });
      c.style.cssText = 'padding:0;max-width:none;width:492px';
      const svg = sp.querySelector('.sp-mark');
      svg.setAttribute('viewBox', '0 0 1024 1024'); svg.style.width = '492px'; svg.style.height = '492px';
      let st = document.getElementById('lay'); if (!st) { st = document.createElement('style'); st.id = 'lay'; document.head.appendChild(st); }
      st.textContent = `#splash *, #splash { animation: none !important; transition: none !important; }
        .sp-mark * { visibility: hidden; }
        .sp-mark defs, .sp-mark defs * { visibility: visible; }
        .sp-mark ${sel}, .sp-mark ${sel} * { visibility: visible; }
        ${hide.map((h) => `.sp-mark ${h}, .sp-mark ${h} *`).join(', ')}${hide.length ? ' { visibility: hidden !important; }' : ''}`;
    }, { sel, hide, theme });
    const dir = path.join(out, name + '.imageset'); fs.mkdirSync(dir, { recursive: true });
    await p.locator('#splash .sp-mark').screenshot({ path: path.join(dir, name + '.png'), omitBackground: true });
    fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify({ images: [{ idiom: 'universal', filename: name + '.png', scale: '3x' }], info: { author: 'xcode', version: 1 } }, null, 2));
    console.log(name);
  }
  await b.close();
})();
