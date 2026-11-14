// Our sign-in page (Haris 2026-11-11, the approved mock-up "Sign-in — fully Apple"): the E11 wordmark, then email →
// password, or a sign-in code (an admin's, or the owner's own) → set a password → in. One page, its steps drawn by a
// little script; everything checked by the server (signin.js). Light and dark follow the phone. No outside files.

// (E11 Talk: "Use your email." — its client contacts sign in with the email E11 set up for them, not a work email; Console
//  keeps "work email": only the team uses it — Haris 2026-11-14)
export function signinPage({ mark = '', req = {}, app = 'console' }) {
  // (inside a <script> block nothing is HTML-decoded: only what could close the block is escaped)
  const reqJson = JSON.stringify(req).replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/&/g, '\\u0026');
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<meta name="color-scheme" content="light dark">
<title>Sign in · ${app === 'talk' ? 'E11 Talk' : 'E11 Console'}</title>
<style>
:root{--bg:#F2F2F7;--card:#fff;--ink:#000;--sub:#6C6C70;--btn:#000;--btnInk:#fff;--line:#E5E5EA;--blue:#007AFF;--bad:#D70015}
@media (prefers-color-scheme: dark){:root{--bg:#000;--card:#1C1C1E;--ink:#fff;--sub:#98989F;--btn:#fff;--btnInk:#000;--line:#38383A;--blue:#0A84FF;--bad:#FF6961}}${app === 'talk' ? `
/* E11 Talk (mock-up "Talk — Sign-in, in Talk's colours", Haris 2026-11-14): Talk's white page, grey boxes, Talk's blue */
:root{--bg:#fff;--card:#F2F2F7;--btn:#2F6FE4;--btnInk:#fff;--blue:#2F6FE4}
@media (prefers-color-scheme: dark){:root{--bg:#000;--card:#1C1C1E;--btn:#2F6FE4;--btnInk:#fff;--blue:#5A9BFF}}` : ''}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--ink);font-family:-apple-system,"SF Pro Text",Inter,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
main{min-height:100svh;max-width:420px;margin:0 auto;padding:max(env(safe-area-inset-top),24px) 24px max(env(safe-area-inset-bottom),28px);display:flex;flex-direction:column;align-items:center}
.top{align-self:stretch;height:44px;margin-top:16px}
.back{width:44px;height:44px;border-radius:22px;border:0;background:var(--card);display:none;align-items:center;justify-content:center;color:var(--ink)}
.mark{width:84px;height:auto;margin-top:60px;color:var(--ink)}
.mark svg{width:84px;height:auto;display:block}.mark svg path{fill:currentColor}
.mark span{opacity:0;display:inline-block;animation:tilt .75s cubic-bezier(.3,1.4,.5,1) forwards}
h1{margin:36px 0 0;font-size:34px;font-weight:700;text-align:center;letter-spacing:.2px}
p.sub{margin:8px 0 0;font-size:15px;color:var(--sub);text-align:center;line-height:20px}
form{width:100%;margin-top:30px;display:flex;flex-direction:column;gap:14px}
.box{background:var(--card);border-radius:14px;overflow:hidden}
.box input+input{border-top:.5px solid var(--line)}
input{display:block;width:100%;height:52px;border:0;border-radius:0;background:var(--card);padding:0 16px;font:inherit;font-size:17px;color:var(--ink);outline:none}
.single{border-radius:14px}
button.go{height:52px;border:0;border-radius:26px;background:var(--btn);color:var(--btnInk);font:inherit;font-size:17px;font-weight:600}
button.go:disabled{opacity:.5}
button.link{align-self:center;border:0;background:none;color:var(--blue);font:inherit;font-size:15px;font-weight:500;padding:8px}
.digits{display:flex;gap:12px;justify-content:center}
.digits input{width:60px;height:68px;border-radius:14px;text-align:center;font-size:30px;font-weight:600;padding:0}
.err{min-height:20px;margin:-4px 0 0;font-size:14px;color:var(--bad);text-align:center}  /* under the button, its room kept: nothing moves when it shows (Haris 2026-11-14) */
.foot{margin-top:auto;padding-top:24px;font-size:13px;color:var(--sub);text-align:center;line-height:18px}
.fade{animation:up .45s ease-out both}
@keyframes tilt{from{opacity:0;transform:scale(.6) rotate(-12deg)}to{opacity:1;transform:none}}
@keyframes up{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
@media (prefers-reduced-motion: reduce){.mark span,.fade{animation:none;opacity:1}}
</style>
</head>
<body>
<main>
<div class="top"><button class="back" type="button" aria-label="Back" id="back"><svg width="12" height="20" viewBox="0 0 12 20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 2 2 10l8 8"/></svg></button></div>
<div class="mark" role="img" aria-label="E11">${mark}</div>
<section id="step" class="fade" style="width:100%;display:flex;flex-direction:column;align-items:center"></section>
</main>
<script id="req" type="application/json">${reqJson}</script>
<script>
(function(){
var req = JSON.parse(document.getElementById('req').textContent || '{}');
var step = document.getElementById('step'), back = document.getElementById('back');
var st = { email: '', ticket: '', owner: false };
function el(h){ var d = document.createElement('div'); d.innerHTML = h; return d; }
function esc(s){ return String(s).replace(/[&<>"']/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }
function api(path, body){
  return fetch('/oidc/api/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(Object.assign({ req: req }, body)) })
    .then(function(r){ return r.json(); }).catch(function(){ return { ok: false, error: 'No connection — try again.' }; });
}
function show(html, onBack){
  step.className = ''; void step.offsetWidth; step.className = 'fade';
  step.innerHTML = html; back.style.display = onBack ? 'flex' : 'none'; back.onclick = onBack || null;
  var f = step.querySelector('input'); if (f) setTimeout(function(){ f.focus(); }, 50);
}
function busy(form, on){ var b = form.querySelector('button.go'); if (b) b.disabled = on; }
function fail(msg){ var e = step.querySelector('.err'); if (e) e.textContent = msg || 'That didn’t work — try again.'; }
function done(r){ if (r && r.redirect) location.replace(r.redirect); else fail(r && r.error); }

function emailStep(){
  show('<h1>Sign in</h1><p class="sub">${app === 'talk' ? 'Use your email.' : 'Use your work email.'}</p>'
    + '<form id="f" novalidate><label for="em" hidden>Email</label><input class="single" id="em" type="email" inputmode="email" autocomplete="username" autocapitalize="none" spellcheck="false" placeholder="Email" value="' + esc(st.email) + '" required>'
    + '<button class="go" type="submit">Continue</button><p class="err" role="alert"></p></form>'
    + '<p class="foot">New here, or forgot your password? Ask your admin for a sign-in code.</p>');
  step.querySelector('#f').onsubmit = function(e){
    e.preventDefault(); var f = e.target, v = f.querySelector('#em').value.trim();
    if (!v) return fail('${app === 'talk' ? 'Enter your email.' : 'Enter your work email.'}');
    busy(f, true);
    api('start', { email: v }).then(function(r){
      busy(f, false);
      if (!r.ok) return fail(r.error);
      st.email = r.email; st.owner = !!r.owner;
      if (r.password) passwordStep(); else codeStep(st.owner);
    });
  };
}
function passwordStep(){
  show('<h1>Welcome back</h1><p class="sub">' + esc(st.email) + '</p>'
    + '<form id="f"><input type="email" autocomplete="username" value="' + esc(st.email) + '" hidden>'
    + '<label for="pw" hidden>Password</label><input class="single" id="pw" type="password" autocomplete="current-password" placeholder="Password" required>'
    + '<button class="go" type="submit">Sign In</button><p class="err" role="alert"></p>'
    + '<button class="link" type="button" id="use">' + (st.owner ? 'Use Owner Code' : 'Use a Sign-in Code') + '</button></form>', emailStep);
  step.querySelector('#use').onclick = function(){ codeStep(st.owner); };
  step.querySelector('#f').onsubmit = function(e){
    e.preventDefault(); var f = e.target; busy(f, true);
    api('password', { email: st.email, password: f.querySelector('#pw').value }).then(function(r){ busy(f, false); done(r); });
  };
}
function codeStep(owner){
  show('<h1>' + (owner ? 'Enter your owner code' : 'Enter your code') + '</h1><p class="sub">'
    + (owner ? 'Your own 4 digits, for ' + esc(st.email) + ' — always the same, never runs out' : 'The 4-digit sign-in code your admin gave you for ' + esc(st.email)) + '</p>'
    + '<form id="f"><div class="digits">' + [0,1,2,3].map(function(i){ return '<input inputmode="numeric" pattern="[0-9]*" maxlength="1" autocomplete="' + (i ? 'off' : 'one-time-code') + '" aria-label="Digit ' + (i + 1) + '">'; }).join('') + '</div>'
    + '<button class="go" type="submit">Continue</button><p class="err" role="alert"></p></form>'
    + '<p class="foot">' + (owner ? 'Then set a password, and add the team from the owner’s view.<br>5 wrong tries lock it for an hour — never for good.' : 'A code works once, only for this email, for 24 hours.<br>After 5 wrong tries it stops — ask for a new one.') + '</p>', function(){ emailStep(); });
  var boxes = [].slice.call(step.querySelectorAll('.digits input'));
  boxes.forEach(function(b, i){
    b.oninput = function(){
      var v = b.value.replace(/\\D/g, '');
      if (v.length > 1) { v.split('').slice(0, 4 - i).forEach(function(d, j){ boxes[i + j].value = d; }); (boxes[Math.min(3, i + v.length)] || b).focus(); }
      else { b.value = v; if (v && boxes[i + 1]) boxes[i + 1].focus(); }
      if (boxes.every(function(x){ return x.value; })) step.querySelector('#f').requestSubmit();
    };
    b.onkeydown = function(e){ if (e.key === 'Backspace' && !b.value && boxes[i - 1]) boxes[i - 1].focus(); };
  });
  step.querySelector('#f').onsubmit = function(e){
    e.preventDefault(); var f = e.target, code = boxes.map(function(x){ return x.value; }).join('');
    if (code.length !== 4) return fail('Enter all 4 digits.');
    busy(f, true);
    api(owner ? 'owner' : 'code', { email: st.email, code: code }).then(function(r){
      busy(f, false);
      if (!r.ok) { boxes.forEach(function(x){ x.value = ''; }); boxes[0].focus(); return fail(r.error); }
      st.ticket = r.ticket; setStep();
    });
  };
}
function setStep(){
  show('<h1>Set your password</h1><p class="sub">The app opens once it’s set. Next time, sign in with your email and this password.</p>'
    + '<form id="f"><input type="email" autocomplete="username" value="' + esc(st.email) + '" hidden>'
    + '<div class="box"><label for="p1" hidden>New password</label><input id="p1" type="password" autocomplete="new-password" placeholder="New password" minlength="8" required>'
    + '<label for="p2" hidden>Confirm password</label><input id="p2" type="password" autocomplete="new-password" placeholder="Confirm password" minlength="8" required></div>'
    + '<button class="go" type="submit">Set Password</button><p class="err" role="alert"></p></form>'
    + '<p class="foot">At least 8 characters. Your old password stops working, and you’re signed out everywhere else.</p>');
  step.querySelector('#f').onsubmit = function(e){
    e.preventDefault(); var f = e.target, a = f.querySelector('#p1').value, b = f.querySelector('#p2').value;
    if (a.length < 8) return fail('At least 8 characters.');
    if (a !== b) return fail('The two passwords aren’t the same.');
    busy(f, true);
    api('setpw', { ticket: st.ticket, password: a }).then(function(r){ busy(f, false); done(r); });
  };
}
var spans = document.querySelectorAll('.mark span'); [].forEach.call(spans, function(s, i){ s.style.animationDelay = (i * 0.12) + 's'; });
emailStep();
})();
</script>
</body>
</html>`;
}
