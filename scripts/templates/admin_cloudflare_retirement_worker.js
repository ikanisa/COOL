'use strict';

// A Cloudflare Admin cutover must also retire previously installed workers.
// This worker never fetches or stores assets, account responses or credentials.
const LEGACY_ADMIN_CACHES = new Set([
  'flutter-app-cache',
  'flutter-temp-cache',
  'flutter-app-manifest',
]);
self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    for (const name of names) {
      if (/^collect-admin-[a-f0-9]{16}$/.test(name) || LEGACY_ADMIN_CACHES.has(name)) {
        await caches.delete(name);
      }
    }
    await self.clients.claim();
    await self.registration.unregister();
  })());
});
