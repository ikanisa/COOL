#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const origin = 'https://admin.example.test/';
const template = readFileSync('scripts/templates/admin_pwa_service_worker.js', 'utf8');

function worker({ name = 'collect-admin-current', redirectAsset = null } = {}) {
  const listeners = new Map();
  const stores = new Map();
  const requests = [];
  let actor = 'account-a';
  let skipped = false;
  let claimed = false;

  class StaticRequest {
    constructor(path, options = {}) {
      this.url = new URL(path, origin).href;
      this.method = options.method ?? 'GET';
      this.mode = options.mode ?? 'same-origin';
      this.cache = options.cache;
      this.credentials = options.credentials;
      this.redirect = options.redirect;
    }
  }

  class StaticCache {
    #entries = new Map();

    async put(request, response) {
      this.#entries.set(request.url, response);
    }

    async match(request, { ignoreSearch = false } = {}) {
      const url = typeof request === 'string' ? request : request.url;
      const key = ignoreSearch ? new URL(url).origin + new URL(url).pathname : url;
      for (const [stored, response] of this.#entries) {
        const storedKey = ignoreSearch
          ? new URL(stored).origin + new URL(stored).pathname
          : stored;
        if (storedKey === key) return response;
      }
      return undefined;
    }

    async keys() {
      return [...this.#entries.keys()];
    }
  }

  const caches = {
    async open(key) {
      if (!stores.has(key)) stores.set(key, new StaticCache());
      return stores.get(key);
    },
    async keys() { return [...stores.keys()]; },
    async delete(key) { return stores.delete(key); },
  };

  const fetch = async (request) => {
    requests.push(request);
    const url = typeof request === 'string' ? request : request.url;
    if (new URL(url).pathname === '/__private/account') {
      return { actor, url, ok: true, type: 'basic', redirected: false };
    }
    const redirected = url === redirectAsset;
    return {
      url: redirected ? origin + 'admin/login' : url,
      ok: true,
      status: 200,
      type: 'basic',
      redirected,
      body: new URL(url).pathname === '/' ? '<title>Collect Admin</title>' : 'bundle',
    };
  };

  const source = template
    .replace('__COLLECT_ADMIN_CACHE_NAME__', JSON.stringify(name))
    .replace('__COLLECT_ADMIN_CACHE_URLS__', JSON.stringify(['./', './main.dart.js']));
  runInNewContext(source, {
    URL,
    Set,
    Promise,
    Error,
    Request: StaticRequest,
    fetch,
    caches,
    self: {
      location: new URL(origin),
      clients: { async claim() { claimed = true; } },
      async skipWaiting() { skipped = true; },
      addEventListener(type, callback) { listeners.set(type, callback); },
    },
  });

  async function lifecycle(type) {
    let pending;
    listeners.get(type)({ waitUntil(promise) { pending = promise; } });
    await pending;
  }

  async function request(path, { method = 'GET', mode = 'same-origin' } = {}) {
    const input = { url: new URL(path, origin).href, method, mode };
    let pending;
    listeners.get('fetch')({
      request: input,
      respondWith(promise) { pending = promise; },
    });
    return pending ? await pending : null;
  }

  return {
    caches, stores, requests, lifecycle, request,
    network: fetch,
    setActor(value) { actor = value; },
    get skipped() { return skipped; },
    get claimed() { return claimed; },
  };
}

const normal = worker();
await normal.lifecycle('install');
assert.equal(normal.skipped, true);
assert.equal(normal.requests.length, 2);
for (const request of normal.requests) {
  assert.equal(request.cache, 'reload');
  assert.equal(request.credentials, 'omit');
  assert.equal(request.redirect, 'error');
}
const cache = await normal.caches.open('collect-admin-current');
assert.deepEqual(await cache.keys(), [origin, origin + 'main.dart.js']);
assert.equal((await normal.request('/admin/transactions', { mode: 'navigate' })).body,
  '<title>Collect Admin</title>');
assert.equal((await normal.request('/main.dart.js?v=new')).body, 'bundle');
assert.equal(await normal.request('/__private/account'), null);
assert.equal((await normal.request('/__private/account', { mode: 'navigate' })).body,
  '<title>Collect Admin</title>');
assert.equal(await normal.request('/__private/account', { method: 'POST' }), null);
const directA = await normal.network(origin + '__private/account');
normal.setActor('account-b');
assert.equal(await normal.request('/__private/account'), null);
const directB = await normal.network(origin + '__private/account');
assert.equal(directA.actor, 'account-a');
assert.equal(directB.actor, 'account-b');
assert.deepEqual(await cache.keys(), [origin, origin + 'main.dart.js']);
await normal.caches.open('collect-admin-previous');
for (const name of ['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']) {
  await normal.caches.open(name);
}
await normal.caches.open('other-app-cache');
await normal.caches.open('flutter-unrelated-application');
await normal.lifecycle('activate');
assert.equal(normal.claimed, true);
assert.deepEqual(await normal.caches.keys(), [
  'collect-admin-current', 'other-app-cache', 'flutter-unrelated-application',
]);

const redirect = worker({ name: 'collect-admin-rejected', redirectAsset: origin + 'main.dart.js' });
await assert.rejects(redirect.lifecycle('install'), /Failed to cache static Admin asset/);
assert.deepEqual(await redirect.caches.keys(), []);
assert.equal(redirect.skipped, false);

console.log('Admin PWA worker cache boundary: PASS');
