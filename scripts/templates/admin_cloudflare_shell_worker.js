'use strict';

// Public build bytes only. Account reads and every mutation remain network-only.
const CACHE_NAME = __COLLECT_SHELL_CACHE_NAME__;
const ASSET_HASHES = __COLLECT_SHELL_ASSET_HASHES__;
const ROOT = new URL('./', self.location.href);
const ASSETS = new Map(Object.entries(ASSET_HASHES).map(([path, hash]) => [new URL(path, ROOT).href, hash]));
const LEGACY = new Set(['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']);

async function verified(response, url, expectedHash) {
  if (!response.ok || response.type !== 'basic' || response.redirected || response.url !== url) {
    throw new Error('Public Admin shell resource unavailable.');
  }
  const digest = await crypto.subtle.digest('SHA-256', await response.clone().arrayBuffer());
  const actual = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
  if (actual !== expectedHash) throw new Error('Public Admin shell build does not match.');
  return response;
}

async function fetchPublic(url, expectedHash) {
  const request = new Request(url, { cache: 'reload', credentials: 'omit', redirect: 'error' });
  return verified(await fetch(request), url, expectedHash);
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    try {
      const cache = await caches.open(CACHE_NAME);
      const results = await Promise.allSettled([...ASSETS].map(async ([url, expectedHash]) => {
        const request = new Request(url, { cache: 'reload', credentials: 'omit', redirect: 'error' });
        const response = await fetchPublic(url, expectedHash);
        await cache.put(request, response);
      }));
      const failed = results.find((result) => result.status === 'rejected');
      if (failed) throw failed.reason;
      // Natural waiting protects open tabs and their unfinished operator work.
    } catch (error) {
      await caches.delete(CACHE_NAME);
      throw error;
    }
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter((name) => name !== CACHE_NAME && (
      /^collect-admin-shell-[a-f0-9]{64}$/.test(name) ||
      /^collect-admin-[a-f0-9]{16}$/.test(name) || LEGACY.has(name)
    )).map((name) => caches.delete(name)));
    // Do not claim a network-loaded earlier build; use a normal navigation.
  })());
});

async function staticResponse(url) {
  const cache = await caches.open(CACHE_NAME);
  const response = await cache.match(url);
  const expectedHash = ASSETS.get(url);
  if (response) {
    try { return await verified(response, url, expectedHash); } catch { /* Repair only this known public resource. */ }
  }
  try {
    // A partial cache eviction must not strand the same installed build. Only
    // its original bytes may repair it; a newer release must wait normally.
    const repaired = await fetchPublic(url, expectedHash);
    try { await cache.put(new Request(url, { credentials: 'omit' }), repaired.clone()); } catch {
      // Verified online bytes remain usable; rejected storage is not durability.
    }
    return repaired;
  } catch { /* Offline or changed bytes stay unavailable; preserve all user state. */ }
  return new Response('The public offline Admin shell is unavailable. Reconnect. If this persists, repair only the public shell cache or service worker. Keep original request references; do not clear cookies or session data.', {
    status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== ROOT.origin) return;
  if (request.mode === 'navigate') {
    // Collect uses hash routes; private/API/unknown navigations never fall back.
    if (url.search || ![ROOT.pathname, ROOT.pathname + 'index.html'].includes(url.pathname)) return;
    event.respondWith(staticResponse(ROOT.href));
    return;
  }
  url.search = '';
  if (!ASSETS.has(url.href)) return;
  event.respondWith(staticResponse(url.href));
});
