// Compatibility bridge for previously installed EACC Connect web apps.
// No messages are sent and no browser data is deleted.
const destination = 'https://eacc-mobile-app.web.app/';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('fetch', event => {
  if (event.request.mode === 'navigate') event.respondWith(Response.redirect(destination, 302));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(self.clients.openWindow(destination));
});
