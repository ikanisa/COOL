'use strict';

const VERSION = 'cool-pwa-v5';
// Cache-busting: bump VERSION whenever the precache manifest changes
// (added/removed files, route changes). On activate, old caches are deleted.
// See docs/pwa-rollback-runbook.md for the full rollback procedure.
const PRECACHE = `${VERSION}-precache`;
const RUNTIME = `${VERSION}-runtime`;
const DATA = `${VERSION}-data`;
const DB_NAME = 'cool-pwa-db';
const DB_VERSION = 1;
const QUEUE_STORE = 'queue';

const SHELL_ROUTES = [
  '/',
  '/index.html',
  '/admin/',
  '/admin/index.html',
  '/admin/platform/',
  '/admin/platform/index.html',
  '/admin/users/',
  '/admin/users/index.html',
  '/admin/app-config/',
  '/admin/app-config/index.html',
  '/admin/operations/',
  '/admin/operations/index.html',
  '/admin/roles/',
  '/admin/roles/index.html',
  '/admin/analytics/',
  '/admin/analytics/index.html',
  '/admin/audit-log/',
  '/admin/audit-log/index.html',
  '/admin/groups/',
  '/admin/groups/index.html',
  '/admin/offline/',
  '/admin/offline/index.html',
];

const CORE_ASSETS = [
  '/manifest.webmanifest',
  '/robots.txt',
  '/sitemap.xml',
  '/assets/css/app.css',
  '/assets/js/app.js',
  '/assets/js/app_install.js',
  '/assets/js/app_notifications.js',
  '/assets/js/app_page.js',
  '/assets/js/admin_api.js',
  '/assets/js/admin_views.js',
  '/assets/js/idb.js',
  '/assets/icons/Icon-192.png',
  '/assets/icons/Icon-256.png',
  '/assets/icons/Icon-384.png',
  '/assets/icons/Icon-512.png',
  '/assets/icons/Icon-1024.png',
  '/assets/icons/Icon-maskable-192.png',
  '/assets/icons/Icon-maskable-512.png',
  '/assets/img/cool_logo_mark.webp',
  '/assets/fonts/SpaceGrotesk-Variable.woff2',
  '/assets/fonts/Manrope-Variable.woff2',
  '/assets/screenshots/home.png',
  '/assets/screenshots/shop.png',
  '/assets/screenshots/settings.png',
  '/data/platform.json',
  '/data/groups.json',
  '/data/admin.json',
  '/data/users.json',
  '/data/app-config.json',
  '/data/operations.json',
  '/data/roles.json',
  '/data/analytics.json',
  '/data/audit-log.json',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(PRECACHE).then((cache) => cache.addAll([...SHELL_ROUTES, ...CORE_ASSETS])).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter((name) => ![PRECACHE, RUNTIME, DATA].includes(name)).map((name) => caches.delete(name)));
    await self.clients.claim();
    if (self.registration.navigationPreload) {
      await self.registration.navigationPreload.enable();
    }
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') {
    return;
  }

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) {
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(handleNavigation(event));
    return;
  }

  if (url.pathname.startsWith('/data/')) {
    event.respondWith(networkFirst(request, DATA));
    return;
  }

  if (/\.(?:css|js|png|webp|jpg|jpeg|svg|ttf|woff2?|json|webmanifest)$/.test(url.pathname)) {
    event.respondWith(staleWhileRevalidate(request, RUNTIME));
  }
});

self.addEventListener('message', (event) => {
  const data = event.data;
  if (!data || typeof data !== 'object') {
    return;
  }

  if (data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }

  if (data.type === 'DOWNLOAD_OFFLINE') {
    event.waitUntil(caches.open(PRECACHE).then((cache) => cache.addAll([...SHELL_ROUTES, ...CORE_ASSETS])));
  }
});

self.addEventListener('sync', (event) => {
  if (event.tag === 'cool-sync') {
    event.waitUntil(flushQueue('background_sync'));
  }
});

self.addEventListener('periodicsync', (event) => {
  if (event.tag === 'cool-content-refresh') {
    event.waitUntil(refreshContentCaches());
  }
});

self.addEventListener('push', (event) => {
  const payload = safeJson(event.data?.text());
  const title = payload.title || 'COOL admin update';
  const options = {
    body: payload.body || 'Fresh operational activity is ready in the admin console.',
    icon: payload.icon || '/assets/icons/Icon-192.png',
    badge: payload.badge || '/assets/icons/Icon-192.png',
    tag: payload.tag || 'cool-push',
    data: {
      route: payload.route || '/admin/operations/',
    },
    actions: payload.actions || [
      { action: 'open-command', title: 'Open command' },
      { action: 'open-operations', title: 'Open operations' },
    ],
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const route = event.action === 'open-command'
      ? '/admin/platform/'
      : event.action === 'open-operations'
        ? '/admin/operations/'
        : event.notification.data?.route || '/admin/operations/';

  event.waitUntil((async () => {
    const allClients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const existing = allClients.find((client) => 'focus' in client);
    if (existing) {
      await existing.focus();
      existing.navigate(route);
      return;
    }
    await self.clients.openWindow(route);
  })());
});

async function handleNavigation(event) {
  const preload = await event.preloadResponse;
  if (preload) {
    return preload;
  }

  try {
    const network = await fetch(event.request);
    const cache = await caches.open(RUNTIME);
    cache.put(event.request, network.clone());
    return network;
  } catch (_) {
    const cache = await caches.open(PRECACHE);
    const exact = await cache.match(event.request.url);
    if (exact) {
      return exact;
    }

    const path = new URL(event.request.url).pathname;
    const candidates = [path, `${path.replace(/\/$/, '')}/`, `${path.replace(/\/$/, '')}/index.html`, '/admin/offline/', '/admin/offline/index.html'];
    for (const candidate of candidates) {
      const match = await cache.match(candidate);
      if (match) {
        return match;
      }
    }

    return new Response('Offline', { status: 503, headers: { 'Content-Type': 'text/plain' } });
  }
}

async function staleWhileRevalidate(request, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  const networkPromise = fetch(request).then((response) => {
    cache.put(request, response.clone());
    return response;
  }).catch(() => cached);
  return cached || networkPromise;
}

async function networkFirst(request, cacheName) {
  const cache = await caches.open(cacheName);
  try {
    const response = await fetch(request);
    cache.put(request, response.clone());
    return response;
  } catch (_) {
    const cached = await cache.match(request);
    if (cached) {
      return cached;
    }
    return new Response(JSON.stringify({ offline: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

async function refreshContentCaches() {
  const cache = await caches.open(DATA);
  await Promise.all(
    CORE_ASSETS.filter((asset) => asset.startsWith('/data/')).map(async (asset) => {
      try {
        const response = await fetch(asset, { cache: 'no-store' });
        if (response.ok) {
          await cache.put(asset, response.clone());
        }
      } catch (_) {
        // Background refresh is best-effort only.
      }
    }),
  );
}

function openDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(QUEUE_STORE)) {
        db.createObjectStore(QUEUE_STORE, { keyPath: 'id' });
      }
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function getAllQueueItems() {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(QUEUE_STORE, 'readonly');
    const store = tx.objectStore(QUEUE_STORE);
    const request = store.getAll();
    request.onsuccess = () => resolve(request.result || []);
    request.onerror = () => reject(request.error);
  });
}

async function putQueueItem(item) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(QUEUE_STORE, 'readwrite');
    tx.objectStore(QUEUE_STORE).put(item);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function flushQueue(reason) {
  const queue = await getAllQueueItems();
  const pending = queue.filter((item) => item.status === 'pending');
  let synced = 0;
  let failed = 0;

  for (const item of pending) {
    try {
      if (!item.endpoint.startsWith('demo://')) {
        const response = await fetch(item.endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(item.payload),
        });
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
      }

      item.status = 'synced';
      item.syncedAt = new Date().toISOString();
      item.syncReason = reason;
      await putQueueItem(item);
      synced++;
    } catch (error) {
      item.lastError = String(error);
      item.lastAttemptAt = new Date().toISOString();
      await putQueueItem(item);
      failed++;
    }
  }

  const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  await Promise.all(clients.map((client) => client.postMessage({
    type: 'SYNC_COMPLETE',
    detail: { synced, failed, reason },
  })));
}

function safeJson(payload) {
  try {
    return payload ? JSON.parse(payload) : {};
  } catch {
    return {};
  }
}
