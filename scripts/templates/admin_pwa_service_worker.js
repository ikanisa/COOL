'use strict';

const CACHE_NAME = __COLLECT_ADMIN_CACHE_NAME__;
const CACHE_URLS = __COLLECT_ADMIN_CACHE_URLS__;
const CACHE_HASHES = __COLLECT_ADMIN_CACHE_HASHES__;
const SHELL_URL = new URL('./', self.location.href).href;
const ASSET_URLS = new Set(CACHE_URLS.map((path) => new URL(path, self.location.href).href));
// Migrate caches from the retired generated Flutter worker on this Admin
// origin. Other applications may own caches with unrelated names.
const LEGACY_FLUTTER_CACHES = new Set([
  'flutter-app-cache',
  'flutter-temp-cache',
  'flutter-app-manifest',
]);

async function hasAdmittedBuildCache() {
  if (!(await caches.keys()).includes(CACHE_NAME)) return false;
  const cache = await caches.open(CACHE_NAME);
  const keys = await cache.keys();
  if (keys.length !== ASSET_URLS.size || keys.some((request) =>
    request.method !== 'GET' || !ASSET_URLS.has(request.url))) return false;
  for (const url of CACHE_URLS) {
    const expected = new URL(url, self.location.href);
    const response = await cache.match(expected.href);
    if (!response || !response.ok || response.type !== 'basic' || response.redirected ||
        new URL(response.url).href !== expected.href) return false;
    const digest = await crypto.subtle.digest('SHA-256', await response.clone().arrayBuffer());
    const actual = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
    if (actual !== CACHE_HASHES[url]) return false;
  }
  return true;
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    let preserveAdmittedCache = false;
    try {
      // Returning to this build while another update waits can reuse the active
      // cache. Preserve it only after verifying its complete static contents.
      preserveAdmittedCache = await hasAdmittedBuildCache();
      const cache = await caches.open(CACHE_NAME);
      // Wait for every write before cleanup if any resource fails. Otherwise
      // an in-flight successful fetch could recreate the rejected cache.
      const results = await Promise.allSettled(CACHE_URLS.map(async (url) => {
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
        const digest = await crypto.subtle.digest('SHA-256', await response.clone().arrayBuffer());
        const actual = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
        if (actual !== CACHE_HASHES[url]) {
          throw new Error(`Admin asset bytes differ from this build: ${url}`);
        }
        await cache.put(request, response);
      }));
      const failed = results.find((result) => result.status === 'rejected');
      if (failed) throw failed.reason;
      // Use the browser's waiting phase. Open operator tabs keep their entire
      // installed build until all controlled tabs/windows have been closed.
      // Do not activate an update over an unfinished operator action.
    } catch (error) {
      if (!preserveAdmittedCache) await caches.delete(CACHE_NAME);
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
    // Natural activation happens after previous controlled clients close.
    // Do not take over a page which loaded an earlier build from the network.
  })());
});

async function cacheFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  // Navigation and assets use the same installed shell version. No account
  // response is admitted to this static cache by a later runtime request.
  const key = request.mode === 'navigate' ? SHELL_URL : request;
  const cached = await cache.match(key, { ignoreSearch: true });
  if (cached) return cached;
  // An evicted static entry must not fetch newer, unversioned build bytes into
  // an old running app. Close all Admin tabs and reopen online to recover.
  return new Response('Admin static build is unavailable. Close all Admin tabs and reopen online.', {
    status: 503,
    headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  // Service documents and responses must use the browser's normal network
  // path. Never replace an Auth/CAPTCHA/privacy response or offline failure
  // with the installed static Admin shell, including iframe navigations.
  if (['/api', '/v1', '/functions', '/privacy', '/account-deletion', '/admin/auth/local-challenge'].some((path) =>
    url.pathname === path || url.pathname.startsWith(path + '/'))) return;
  url.search = '';
  if (event.request.mode !== 'navigate' && !ASSET_URLS.has(url.href)) return;
  event.respondWith(cacheFirst(event.request));
});
