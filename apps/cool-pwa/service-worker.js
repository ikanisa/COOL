'use strict';

const VERSION = 'cool-pwa-v1';
const PRECACHE = `${VERSION}-precache`;
const RUNTIME = `${VERSION}-runtime`;
const DATA = `${VERSION}-data`;
const DB_NAME = 'cool-pwa-db';
const DB_VERSION = 1;
const QUEUE_STORE = 'queue';

const SHELL_ROUTES = [
  '/',
  '/index.html',
  '/home/',
  '/home/index.html',
  '/groups/',
  '/groups/index.html',
  '/momo/',
  '/momo/index.html',
  '/profile/',
  '/profile/index.html',
  '/admin/',
  '/admin/index.html',
  '/notifications/',
  '/notifications/index.html',
  '/install/',
  '/install/index.html',
  '/share/',
  '/share/index.html',
  '/offline/',
  '/offline/index.html',
];

const CORE_ASSETS = [
  '/manifest.webmanifest',
  '/robots.txt',
  '/sitemap.xml',
  '/assets/css/app.css',
  '/assets/js/app.js',
  '/assets/js/idb.js',
  '/assets/icons/Icon-192.png',
  '/assets/icons/Icon-256.png',
  '/assets/icons/Icon-384.png',
  '/assets/icons/Icon-512.png',
  '/assets/icons/Icon-1024.png',
  '/assets/icons/Icon-maskable-192.png',
  '/assets/icons/Icon-maskable-512.png',
  '/assets/img/cool_logo_mark.png',
  '/assets/img/hero_match_bg.png',
  '/assets/img/hero_match_bg.webp',
  '/assets/fonts/Manrope-Regular.ttf',
  '/assets/fonts/Barlow-SemiBold.ttf',
  '/assets/fonts/Barlow-ExtraBold.ttf',
  '/assets/fonts/DMMono-Regular.ttf',
  '/assets/screenshots/home.png',
  '/assets/screenshots/shop.png',
  '/assets/screenshots/settings.png',
  '/data/home.json',
  '/data/groups.json',
  '/data/momo.json',
  '/data/profile.json',
  '/data/admin.json',
  '/data/notifications.json',
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
  const title = payload.title || 'COOL update';
  const options = {
    body: payload.body || 'Fresh activity is ready in your PWA workspace.',
    icon: payload.icon || '/assets/icons/Icon-192.png',
    badge: payload.badge || '/assets/icons/Icon-192.png',
    tag: payload.tag || 'cool-push',
    data: {
      route: payload.route || '/notifications/',
    },
    actions: payload.actions || [
      { action: 'open-home', title: 'Open home' },
      { action: 'open-notifications', title: 'Open alerts' },
    ],
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const route = event.action === 'open-home'
    ? '/home/'
    : event.action === 'open-notifications'
      ? '/notifications/'
      : event.notification.data?.route || '/notifications/';

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
    const candidates = [path, `${path.replace(/\/$/, '')}/`, `${path.replace(/\/$/, '')}/index.html`, '/offline/', '/offline/index.html'];
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
