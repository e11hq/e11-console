// E11 Console service worker: lets the browser install the app. It does not cache data —
// everything comes live from the office server. If the server can't be reached, a short notice
// is shown instead of the browser's error page.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', (e) => {
  if (e.request.mode !== 'navigate') return;
  e.respondWith(fetch(e.request).catch(() => new Response(
    '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>E11 Console — offline</title>' +
    '<body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#0b0b0d;color:#ececf1;font:15px/1.5 -apple-system,Segoe UI,sans-serif;text-align:center">' +
    '<div><div style="font-size:20px;font-weight:700;margin-bottom:6px">You’re offline</div><div style="color:#9d9da8">E11 Console can’t reach the office server right now.<br>Check your internet connection, then try again.</div>' +
    '<button onclick="location.reload()" style="margin-top:18px;padding:9px 18px;border-radius:8px;border:0;background:#6a56e6;color:#fff;font-size:14px">Try again</button></div>',
    { headers: { 'Content-Type': 'text/html; charset=utf-8' } })));
});
