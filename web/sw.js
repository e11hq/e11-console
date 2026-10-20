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
    data: { taskId: m.taskId || null, nid: m.nid || null },
  });
  const badge = typeof m.badge === 'number' && self.navigator.setAppBadge ? self.navigator.setAppBadge(m.badge).catch(() => {}) : null;
  e.waitUntil(Promise.all([show, badge]));
});

// Tapping a notification opens the app on that task
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const d = e.notification.data || {};
  const qs = d.taskId ? `/?task=${encodeURIComponent(d.taskId)}${d.nid ? '&n=' + encodeURIComponent(d.nid) : ''}` : '/';
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    const c = list.find((x) => new URL(x.url).origin === self.location.origin);
    if (c) { c.postMessage({ type: 'open-task', taskId: d.taskId, nid: d.nid }); return c.focus(); }
    return self.clients.openWindow(qs);
  }));
});
