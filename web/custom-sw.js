'use strict';

const OFFLINE_CACHE = 'cool-offline-v2';
const OFFLINE_URL = '/offline.html';
const FLUTTER_SW_QUERY = self.location.search || '';

importScripts(`flutter_service_worker.js${FLUTTER_SW_QUERY}`);

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(OFFLINE_CACHE).then((cache) => {
      return cache.add(new Request(OFFLINE_URL, { cache: 'reload' }));
    }),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => name.startsWith('cool-offline-') && name !== OFFLINE_CACHE)
          .map((name) => caches.delete(name)),
      );
    }),
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET' || event.request.mode !== 'navigate') {
    return;
  }

  const requestUrl = new URL(event.request.url);
  if (requestUrl.origin !== self.location.origin) {
    return;
  }

  const path = requestUrl.pathname;
  if (path === '/' || path === '/index.html' || path === OFFLINE_URL) {
    return;
  }

  event.respondWith(
    fetch(event.request).catch(() => {
      return caches.match(OFFLINE_URL).then((cachedResponse) => {
        if (cachedResponse) {
          return cachedResponse;
        }
        return new Response(
          '<html><body><h1>Offline</h1><p>Please check your connection.</p></body></html>',
          { headers: { 'Content-Type': 'text/html' } },
        );
      });
    }),
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting' || event.data?.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});
