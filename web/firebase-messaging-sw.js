importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBZKeyhvuYUlBcdqylVIexJOZdQ7-S4lFI',
  authDomain: 'eacc-mobile-app.firebaseapp.com',
  projectId: 'eacc-mobile-app',
  storageBucket: 'eacc-mobile-app.firebasestorage.app',
  messagingSenderId: '492936842220',
  appId: '1:492936842220:web:de1c69381e413074c34ec9',
  measurementId: 'G-S9GL3J0R9H',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || payload.data?.senderName || 'EACC Chat';
  const body = payload.notification?.body || 'New message';

  self.registration.showNotification(title, {
    body,
    data: payload.data || {},
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification.data || {};
  const courseId = data.courseId || '';
  const threadId = data.threadId || '';
  const targetUrl = threadId
    ? `/?courseId=${encodeURIComponent(courseId)}&threadId=${encodeURIComponent(threadId)}`
    : '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          client.postMessage({
            type: 'chat_notification_click',
            courseId,
            threadId,
          });
          return client.focus();
        }
      }

      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }

      return undefined;
    }),
  );
});
