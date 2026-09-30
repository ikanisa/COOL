'use strict';

const CACHE_NAME = __COLLECT_ADMIN_CACHE_NAME__;
const CACHE_URLS = __COLLECT_ADMIN_CACHE_URLS__;
const SHELL_URL = new URL('./', self.location.href).href;
const ASSET_URLS = new Set(CACHE_URLS.map((path) => new URL(path, self.location.href).href));
// Migrate caches from the retired generated Flutter worker on this Admin
// origin. Other applications may own caches with unrelated names.
const LEGACY_FLUTTER_CACHES = new Set([
  'flutter-app-cache',
  'flutter-temp-cache',
  'flutter-app-manifest',
]);

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    try {
      const cache = await caches.open(CACHE_NAME);
      await Promise.all(CACHE_URLS.map(async (url) => {
        // A static shell must be identical for every operator. Never let an
        // authenticated cookie or a redirect to an account page enter it.
        const request = new Request(url, {
          cache: 'reload',
          credentials: 'omit',
          redirect: 'error',
        });
        const response = await fetch(request);
        const expected = new URL(url, self.location.href);
        if (!response.ok || response.type !== 'basic' || response.redirected ||
            new URL(response.url).href !== expected.href) {
          throw new Error(`Failed to cache static Admin asset ${url}`);
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
    await Promise.all(keys.filter((key) =>
      (key.startsWith('collect-admin-') && key !== CACHE_NAME) ||
      LEGACY_FLUTTER_CACHES.has(key))
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
