#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { createHash, webcrypto } from 'node:crypto';

const origin = 'https://admin.example.test/';
const template = readFileSync('scripts/templates/admin_pwa_service_worker.js', 'utf8');

function worker({ name = 'collect-admin-current', redirectAsset = null, mismatchAsset = null, delayedAsset = null, rejectedAsset = null, assets = ['./', './main.dart.js'] } = {}) {
  const listeners = new Map();
  const stores = new Map();
  const requests = [];
  const networkResponses = new Map();
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
      return [...this.#entries.keys()].map((url) => new StaticRequest(url));
    }

    async delete(url) { return this.#entries.delete(url); }
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
    if (url === rejectedAsset) throw Error('Interrupted synthetic static fetch');
    if (networkResponses.has(url)) return networkResponses.get(url);
    if (new URL(url).pathname === '/__private/account') {
      return { actor, url, ok: true, type: 'basic', redirected: false };
    }
    if (url === delayedAsset) await new Promise((yes) => setTimeout(yes, 30));
    const redirected = url === redirectAsset;
    const body = url === mismatchAsset ? 'wrong-build' : new URL(url).pathname === '/' ? '<title>Collect Admin</title>' : 'bundle';
    return {
      url: redirected ? origin + 'admin/login' : url,
      ok: true,
      status: 200,
      type: 'basic',
      redirected,
      body,
      clone() { return { async arrayBuffer() { return new TextEncoder().encode(body).buffer; } }; },
    };
  };

  const source = template
    .replace('__COLLECT_ADMIN_CACHE_NAME__', JSON.stringify(name))
    .replace('__COLLECT_ADMIN_CACHE_URLS__', JSON.stringify(assets))
    .replace('__COLLECT_ADMIN_CACHE_HASHES__', JSON.stringify(Object.fromEntries(assets.map((path) => [
      path, createHash('sha256').update(new URL(path, origin).pathname === '/' ? '<title>Collect Admin</title>' : 'bundle').digest('hex'),
    ]))));
  runInNewContext(source, {
    URL,
    Set,
    Promise,
    Error,
    Request: StaticRequest,
    Response,
    crypto: webcrypto,
    Uint8Array,
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

  // Model browser default handling after dispatching the actual installed
  // fetch listener. No real network or provider is used by this VM fixture.
  async function browserRequest(path, options = {}) {
    const input = new StaticRequest(path, options);
    let intercepted = false;
    let pending;
    listeners.get('fetch')({
      request: input,
      respondWith(promise) {
        assert.equal(intercepted, false);
        intercepted = true;
        pending = promise;
      },
    });
    const response = intercepted ? await pending : await fetch(input);
    return { response, intercepted, input };
  }

  return {
    caches, stores, requests, lifecycle, request, browserRequest,
    network: fetch,
    setActor(value) { actor = value; },
    setMismatchAsset(value) { mismatchAsset = value; },
    setRejectedAsset(value) { rejectedAsset = value; },
    setNetworkResponse(path, response) { networkResponses.set(new URL(path, origin).href, response); },
    get skipped() { return skipped; },
    get claimed() { return claimed; },
  };
}

const normal = worker();
await normal.lifecycle('install');
assert.equal(normal.skipped, false);
assert.equal(normal.requests.length, 2);
for (const request of normal.requests) {
  assert.equal(request.cache, 'reload');
  assert.equal(request.credentials, 'omit');
  assert.equal(request.redirect, 'error');
}
const cache = await normal.caches.open('collect-admin-current');
assert.deepEqual((await cache.keys()).map((request) => request.url), [origin, origin + 'main.dart.js']);
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
assert.deepEqual((await cache.keys()).map((request) => request.url), [origin, origin + 'main.dart.js']);
// Reserved service families include both exact roots and slash-delimited
// descendants. Navigation must not convert live service failures into shell200.
const serviceFamilies = ['/api', '/v1', '/functions', '/privacy', '/account-deletion', '/admin/auth/local-challenge'];
const servicePaths = [
  ...serviceFamilies.flatMap((path) => [path, path + '/child']),
  '/api/admin/auth/session',
  '/v1/security/challenge?context=synthetic-memory-only',
  '/functions/v1/collect-api/v1/security/challenge',
  '/privacy/email/verify',
  '/account-deletion/status',
  '/admin/auth/local-challenge?pairing=synthetic-memory-only&nonce=synthetic-memory-only',
];
for (const path of servicePaths) {
  for (const mode of ['navigate', 'same-origin']) {
    const before = normal.requests.length;
    assert.equal(await normal.request(path, { mode }), null, path + ': leave default browser handling');
    assert.equal(normal.requests.length, before, 'SW must not start its own service fetch');
    for (const status of [200, 401, 404, 503]) {
      const body = 'synthetic service response ' + status + ' ' + path;
      normal.setNetworkResponse(path, new Response(body, { status, headers: { 'Cache-Control': 'no-store' } }));
      const actual = await normal.browserRequest(path, { mode, credentials: 'include', cache: 'no-store', redirect: 'follow' });
      assert.equal(actual.intercepted, false, path + ': no respondWith for service documents');
      assert.equal(normal.requests.at(-1), actual.input, 'Default handling retains original request identity');
      assert.equal(actual.input.credentials, 'include');
      assert.equal(actual.input.cache, 'no-store');
      assert.equal(actual.input.redirect, 'follow');
      assert.equal(actual.response.status, status, path + ': preserve upstream failure status');
      assert.equal(await actual.response.text(), body);
      assert.equal(actual.response.headers.get('Cache-Control'), 'no-store');
      assert.equal(await cache.match(new URL(path, origin).href, { ignoreSearch: true }), undefined);
    }
    normal.setRejectedAsset(new URL(path, origin).href);
    await assert.rejects(normal.browserRequest(path, { mode }), /Interrupted synthetic static fetch/,
      path + ': offline service request fails instead of returning the Admin shell');
    normal.setRejectedAsset(null);
    assert.deepEqual((await cache.keys()).map((request) => request.url), [origin, origin + 'main.dart.js']);
  }
  assert.equal(await normal.request(path, { method: 'POST', mode: 'navigate' }), null,
    'Existing non-GET pass-through is preserved');
}
for (const family of serviceFamilies) {
  const lookalike = family + '-admin-view';
  assert.equal((await normal.request(lookalike, { mode: 'navigate' })).body, '<title>Collect Admin</title>',
    'A service family must end at a path-segment boundary');
}
assert.equal(await normal.request('https://other.example.test/v1/security/challenge', { mode: 'navigate' }), null,
  'Cross-origin requests remain untouched');
for (const path of ['/admin', '/admin/auth', '/admin/auth/sign-in', '/admin/transactions']) {
  assert.equal((await normal.request(path, { mode: 'navigate' })).body, '<title>Collect Admin</title>',
    'Other Admin routes retain the installed shell');
}
assert.equal((await normal.request('/main.dart.js?v=still-installed')).body, 'bundle');

// Actual immutable/versioned static URLs retain cache-first offline behavior.
const versionedPath = '/_build/' + 'a'.repeat(64) + '/main.dart.js';
const versioned = worker({ name: 'collect-admin-versioned', assets: ['./', '.' + versionedPath] });
await versioned.lifecycle('install');
versioned.setRejectedAsset(origin + versionedPath.slice(1));
const beforeVersionedFetch = versioned.requests.length;
assert.equal((await versioned.request(versionedPath + '?v=current')).body, 'bundle');
assert.equal((await versioned.request('/admin/team', { mode: 'navigate' })).body, '<title>Collect Admin</title>');
assert.equal(versioned.requests.length, beforeVersionedFetch);

await normal.caches.open('collect-admin-previous');
for (const name of ['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']) {
  await normal.caches.open(name);
}
await normal.caches.open('other-app-cache');
await normal.caches.open('flutter-unrelated-application');
await normal.lifecycle('activate');
assert.equal(normal.claimed, false);
assert.deepEqual(await normal.caches.keys(), [
  'collect-admin-current', 'other-app-cache', 'flutter-unrelated-application',
]);

const redirect = worker({ name: 'collect-admin-rejected', redirectAsset: origin + 'main.dart.js' });
await assert.rejects(redirect.lifecycle('install'), /Failed to cache static Admin asset/);
assert.deepEqual(await redirect.caches.keys(), []);
assert.equal(redirect.skipped, false);

const mismatch = worker({ name: 'collect-admin-mixed', mismatchAsset: origin + 'main.dart.js' });
await assert.rejects(mismatch.lifecycle('install'), /bytes differ from this build/);
assert.deepEqual(await mismatch.caches.keys(), []);

const interrupted = worker({ name: 'collect-admin-interrupted', rejectedAsset: origin + 'main.dart.js', delayedAsset: origin });
await assert.rejects(interrupted.lifecycle('install'), /Interrupted synthetic static fetch/);
assert.deepEqual(await interrupted.caches.keys(), []);

const returning = worker({ name: 'collect-admin-returning' });
await returning.lifecycle('install');
const admittedCache = await returning.caches.open('collect-admin-returning');
const admittedKeys = (await admittedCache.keys()).map((request) => request.url);
const admittedBodies = await Promise.all(admittedKeys.map(async (url) =>
  (await admittedCache.match(url)).body));
returning.setMismatchAsset(origin + 'main.dart.js');
await assert.rejects(returning.lifecycle('install'), /bytes differ from this build/);
assert.deepEqual(await returning.caches.keys(), ['collect-admin-returning']);
assert.deepEqual((await admittedCache.keys()).map((request) => request.url), admittedKeys);
assert.deepEqual(await Promise.all(admittedKeys.map(async (url) =>
  (await admittedCache.match(url)).body)), admittedBodies);
assert.equal((await returning.request('/main.dart.js')).body, 'bundle');
returning.setMismatchAsset(null);
returning.setRejectedAsset(origin + 'main.dart.js');
await assert.rejects(returning.lifecycle('install'), /Interrupted synthetic static fetch/);
assert.deepEqual(await returning.caches.keys(), ['collect-admin-returning']);
assert.deepEqual((await admittedCache.keys()).map((request) => request.url), admittedKeys);
assert.deepEqual(await Promise.all(admittedKeys.map(async (url) =>
  (await admittedCache.match(url)).body)), admittedBodies);
assert.equal((await returning.request('/main.dart.js')).body, 'bundle');
returning.setRejectedAsset(null);
await returning.lifecycle('install');
assert.deepEqual((await admittedCache.keys()).map((request) => request.url), admittedKeys);

for (const previousState of ['partial', 'corrupt', 'unexpected-private-entry']) {
  const invalid = worker({ name: 'collect-admin-invalid-' + previousState });
  await invalid.lifecycle('install');
  const invalidCache = await invalid.caches.open('collect-admin-invalid-' + previousState);
  if (previousState === 'partial') {
    await invalidCache.delete(origin + 'main.dart.js');
  } else if (previousState === 'corrupt') {
    invalid.setMismatchAsset(origin + 'main.dart.js');
    await invalidCache.put({ url: origin + 'main.dart.js' }, await invalid.network(origin + 'main.dart.js'));
  } else {
    await invalidCache.put({ url: origin + '__private/account' }, await invalid.network(origin + '__private/account'));
  }
  invalid.setMismatchAsset(origin + 'main.dart.js');
  await assert.rejects(invalid.lifecycle('install'), /bytes differ from this build/);
  assert.deepEqual(await invalid.caches.keys(), [], previousState + ' must not be treated as an admitted build');
}

const concurrent = worker({ name: 'collect-admin-partial', redirectAsset: origin, delayedAsset: origin + 'main.dart.js' });
await assert.rejects(concurrent.lifecycle('install'), /Failed to cache static Admin asset/);
assert.deepEqual(await concurrent.caches.keys(), []);
await new Promise((yes) => setTimeout(yes, 40));
assert.deepEqual(await concurrent.caches.keys(), []);

await cache.delete(origin + 'main.dart.js');
const networkBefore = normal.requests.length;
const evicted = await normal.request('/main.dart.js');
assert.equal(evicted.status, 503);
assert.equal(normal.requests.length, networkBefore);
assert.equal(evicted.headers.get('Cache-Control'), 'no-store');
console.log('Admin PWA worker service-document pass-through, cache boundary, integrity and failed-cache cleanup: PASS');
