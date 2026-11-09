self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('push', event => {
  let payload = {};
  try { payload = event.data?.json() ?? {}; } catch { payload = { body: event.data?.text() ?? '' }; }
  if (!payload || typeof payload !== 'object') payload = {};
  const id = Number.isSafeInteger(payload.reminderId) && payload.reminderId > 0 ? payload.reminderId : null;
  const url = id ? `/?reminder=${id}` : '/';
  const tag = typeof payload.tag === 'string' && payload.tag ? payload.tag : undefined;
  event.waitUntil((async () => {
    await self.registration.showNotification(typeof payload.title === 'string' && payload.title.trim() ? payload.title : '下班王 · 到站提醒', {
      body: typeof payload.body === 'string' ? payload.body : '',
      icon: '/icons/xiabanwang-192.png?v=bell-forest-1', badge: '/icons/xiabanwang-192.png?v=bell-forest-1',
      tag, renotify: Boolean(tag), data: { url },
    });
    if (typeof payload.testId === 'string') {
      for (const client of await self.clients.matchAll({ type: 'window', includeUncontrolled: true })) {
        client.postMessage({ type: 'WEB_PUSH_RECEIVED', testId: payload.testId });
      }
    }
  })());
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const candidate = new URL(event.notification.data?.url ?? '/', self.location.origin);
  const target = candidate.origin === self.location.origin && candidate.pathname === '/' ? candidate.href : new URL('/', self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const existing = windows.find(c => new URL(c.url).origin === self.location.origin && !new URL(c.url).pathname.startsWith('/admin'));
    if (existing) { await existing.navigate(target); return existing.focus(); }
    return self.clients.openWindow(target);
  })());
});
