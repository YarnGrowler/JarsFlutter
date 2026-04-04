// Jars Web Push (no Firebase).
self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  const title = data.title || 'Jars';
  const body = data.body || '';
  // tag must differ per message or the OS replaces earlier notifications with the same tag.
  const tag =
    (typeof data.tag === 'string' && data.tag.length > 0)
      ? data.tag
      : `jars-${Date.now()}`;
  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: data.icon || '/icons/jars-notification.svg',
      badge: '/icons/jars-notification.svg',
      tag,
      data: data.data || {},
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification.data?.url || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (c.url.includes(self.location.origin) && 'focus' in c) return c.focus();
      }
      if (clients.openWindow) return clients.openWindow(url);
    }),
  );
});
