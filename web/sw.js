// E11 Console service worker: lets the browser install the app. It does not cache data —
// everything comes live from the office server. If the server can't be reached, or the first page takes too long
// on a weak connection (the iPhone otherwise sits on a blank screen), a "Connecting…" screen shows instead: it keeps
// trying on its own and opens the app as soon as the connection answers.
const OPEN_TIMEOUT = 8000;
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
const connectingPage = (offline) => new Response(
  '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#0c0d0f"><title>E11 Console — connecting</title>' +
  '<body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#0c0d0f;color:#e9eaee;font:15px/1.5 -apple-system,Segoe UI,sans-serif;text-align:center;padding:0 24px">' +
  '<div><div style="width:46px;height:46px;margin:0 auto 18px;border-radius:50%;border:3px solid #2c2f37;border-top-color:#7c6cff;animation:s 1s linear infinite"></div>' +
  '<div style="font-size:20px;font-weight:700;margin-bottom:6px" id="t">' + (offline ? 'You’re offline' : 'Connecting to E11 Console…') + '</div>' +
  '<div style="color:#9d9da8" id="d">' + (offline ? 'Waiting for the internet connection.' : 'The connection is slow right now.') + '<br>It opens by itself as soon as it can.</div>' +
  '<button onclick="location.reload()" style="margin-top:20px;padding:10px 20px;border-radius:999px;border:0;background:#5b4bd6;color:#fff;font-size:15px;font-weight:600">Try again</button></div>' +
  '<style>@keyframes s{to{transform:rotate(360deg)}}</style>' +
  '<script>let n=0;async function tryIt(){n++;try{await fetch("/api/health",{cache:"no-store",credentials:"same-origin",redirect:"manual"});location.reload();}catch(e){setTimeout(tryIt,Math.min(15000,2000*n));}}' +
  'window.addEventListener("online",()=>location.reload());setTimeout(tryIt,1500);</script>',
  { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
self.addEventListener('fetch', (e) => {
  if (e.request.mode !== 'navigate') return;
  e.respondWith(new Promise((resolve) => {
    let done = false;
    const timer = setTimeout(() => { if (!done) { done = true; resolve(connectingPage(false)); } }, OPEN_TIMEOUT);
    fetch(e.request).then((res) => { if (!done) { done = true; clearTimeout(timer); resolve(res); } })
      .catch(() => { if (!done) { done = true; clearTimeout(timer); resolve(connectingPage(!self.navigator || self.navigator.onLine === false)); } });
  }));
});

// Phone notifications (Web Push). The server sends { title, body, taskId, nid, tag, badge }.
self.addEventListener('push', (e) => {
  let m = {};
  try { m = e.data ? e.data.json() : {}; } catch (err) { m = { body: e.data ? e.data.text() : '' }; }
  const show = self.registration.showNotification(m.title || 'E11 Console', {
    body: m.body || 'You have a new update',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    tag: m.tag || undefined,
    renotify: !!m.tag,
    data: { taskId: m.taskId || null, nid: m.nid || null, view: m.view || null },
  });
  const badge = typeof m.badge === 'number' && self.navigator.setAppBadge ? self.navigator.setAppBadge(m.badge).catch(() => {}) : null;
  e.waitUntil(Promise.all([show, badge]));
});

// Tapping a notification opens the app on that task
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const d = e.notification.data || {};
  const qs = d.view ? `/?view=${encodeURIComponent(d.view)}` : d.taskId ? `/?task=${encodeURIComponent(d.taskId)}${d.nid ? '&n=' + encodeURIComponent(d.nid) : ''}` : d.nid ? `/?n=${encodeURIComponent(d.nid)}` : '/';
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    const c = list.find((x) => new URL(x.url).origin === self.location.origin);
    if (c) { c.postMessage(d.view ? { type: 'open-view', view: d.view } : { type: 'open-task', taskId: d.taskId, nid: d.nid }); return c.focus(); }
    return self.clients.openWindow(qs);
  }));
});
