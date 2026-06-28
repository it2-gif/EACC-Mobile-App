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

function appBasePath() {
  const scope = self.registration?.scope || self.location.href;
  const pathname = new URL(scope).pathname;
  return pathname.endsWith('/') ? pathname : `${pathname}/`;
}

function appUrl(query) {
  const base = appBasePath();
  return `${self.location.origin}${base}${query ? `?${query}` : ''}`;
}

messaging.onBackgroundMessage((payload) => {
  const base = appBasePath();
  const title = payload.notification?.title || payload.data?.senderName || 'EACC Connection';
  const body =
    payload.notification?.body || payload.data?.previewText || 'New message';

  self.registration.showNotification(title, {
    body,
    data: payload.data || {},
    icon: `${base}icons/Icon-192.png`,
    badge: `${base}icons/Icon-192.png`,
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification.data || {};
  const courseId = data.courseId || '';
  const threadId = data.threadId || '';
  const studentName = data.studentName || '';
  const senderName = data.senderName || '';
  const query = threadId
    ? `courseId=${encodeURIComponent(courseId)}&threadId=${encodeURIComponent(threadId)}&studentName=${encodeURIComponent(studentName)}&senderName=${encodeURIComponent(senderName)}`
    : '';
  const targetUrl = appUrl(query);

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          if ('navigate' in client) {
            return client.navigate(targetUrl).then((navigatedClient) => navigatedClient.focus());
          }

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
