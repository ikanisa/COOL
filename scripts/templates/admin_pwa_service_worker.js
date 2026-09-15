'use strict';

const CACHE_NAME = __COLLECT_ADMIN_CACHE_NAME__;
const CACHE_URLS = __COLLECT_ADMIN_CACHE_URLS__;
const SHELL_URL = new URL('./', self.location.href).href;
const ASSET_URLS = new Set(CACHE_URLS.map((path) => new URL(path, self.location.href).href));

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    try {
      const cache = await caches.open(CACHE_NAME);
      await Promise.all(CACHE_URLS.map(async (url) => {
        const request = new Request(url, { cache: 'reload' });
        const response = await fetch(request);
        if (!response.ok) {
          throw new Error(`Failed to refresh ${url}: HTTP ${response.status}`);
        }
        await cache.put(request, response);
      }));
      await self.skipWaiting();
    } catch (error) {
      await caches.delete(CACHE_NAME);
      throw error;
    }
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key.startsWith('collect-admin-') && key !== CACHE_NAME)
      .map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

async function cacheFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  // Navigation and assets use the same installed shell version. No account
  // response is admitted to this static cache by a later runtime request.
  const key = request.mode === 'navigate' ? SHELL_URL : request;
  const cached = await cache.match(key, { ignoreSearch: true });
  if (cached) return cached;
  return fetch(request);
}

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  url.search = '';
  if (event.request.mode !== 'navigate' && !ASSET_URLS.has(url.href)) return;
  event.respondWith(cacheFirst(event.request));
});
