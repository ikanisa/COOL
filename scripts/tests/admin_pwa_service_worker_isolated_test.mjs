#!/usr/bin/env node
/**
 * Dependency-free, read-only execution of the production Admin service-worker
 * template against a controlled CacheStorage, fetch and lifecycle environment.
 * This is NOT installed-browser, OS PWA or production acceptance.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash, webcrypto } from 'node:crypto';
import { Script, createContext } from 'node:vm';

const scope = 'https://platform-admin.collect.ikanisa.com/';
const paths = ['./', './_build/isolated/main.dart.js'];
const files = new Map([
  [new URL(paths[0], scope).href, 'Collect Admin synthetic offline shell'],
  [new URL(paths[1], scope).href, 'Synthetic compiled app content'],
]);
const sha256 = (v) => createHash('sha256').update(v).digest('hex');
const hashes = Object.fromEntries(paths.map((p) => [p, sha256(files.get(new URL(p, scope).href))]));
const template = readFileSync(new URL('../templates/admin_pwa_service_worker.js', import.meta.url), 'utf8');
const source = template
  .replace('__COLLECT_ADMIN_CACHE_NAME__', JSON.stringify('collect-admin-isolated'))
  .replace('__COLLECT_ADMIN_CACHE_URLS__', JSON.stringify(paths))
  .replace('__COLLECT_ADMIN_CACHE_HASHES__', JSON.stringify(hashes));
assert.ok(!source.includes('__COLLECT_ADMIN_'), 'unresolved service-worker template marker');

class MockRequest {
  constructor(input, init = {}) {
    this.url = new URL(typeof input === 'string' ? input : input.url, scope).href;
    this.method = init.method ?? 'GET';
    this.mode = init.mode ?? 'cors';
    this.credentials = init.credentials ?? 'same-origin';
    this.redirect = init.redirect ?? 'follow';
  }
}
class MockResponse {
  constructor(body, options = {}) {
    this.data = Buffer.from(body);
    this.status = options.status ?? 200;
    this.ok = this.status >= 200 && this.status < 300;
    this.type = options.type ?? 'basic';
    this.redirected = options.redirected ?? false;
    this.url = options.url ?? '';
    this.headers = options.headers ?? {};
  }
  clone() {
    return new MockResponse(this.data, {
      status: this.status, type: this.type, redirected: this.redirected,
      url: this.url, headers: this.headers,
    });
  }
  async arrayBuffer() {
    const buf = this.data;
    return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
  }
}
class MockCache {
  constructor() { this.entries = new Map(); }
  async keys() { return [...this.entries.keys()].map((url) => new MockRequest(url)); }
  async match(key, { ignoreSearch = false } = {}) {
    let url = new URL(typeof key === 'string' ? key : key.url, scope);
    if (ignoreSearch) url.search = '';
    return this.entries.get(url.href)?.clone();
  }
  async put(request, response) { this.entries.set(request.url, response.clone()); }
}
class MockCacheStorage {
  constructor() { this.stores = new Map(); }
  async keys() { return [...this.stores.keys()]; }
  async open(key) {
    if (!this.stores.has(key)) this.stores.set(key, new MockCache());
    return this.stores.get(key);
  }
  async delete(key) { return this.stores.delete(key); }
}

function harness({ tampered = false, redirected = false, wrongOrigin = false } = {}) {
  const caches = new MockCacheStorage();
  const hooks = new Map();
  const requests = [];
  const self = {
    location: { href: `${scope}custom-sw.js`, origin: new URL(scope).origin },
    addEventListener(type, handler) { hooks.set(type, handler); },
  };
  const fetch = async (request) => {
    requests.push(request);
    const original = files.get(request.url);
    if (original === undefined) throw new Error(`Unknown synthetic asset: ${request.url}`);
    const bytes = tampered && request.url.endsWith('main.dart.js') ? original + ' tampered' : original;
    const url = wrongOrigin ? new URL('/other', scope).href : request.url;
    return new MockResponse(bytes, { url, redirected });
  };
  const context = createContext({ self, caches, fetch, crypto: webcrypto,
    URL, Request: MockRequest, Response: MockResponse, Uint8Array, Promise });
  new Script(source, { filename: 'admin_pwa_service_worker.js' }).runInContext(context);
  return {
    caches, requests,
    setTampered(value) { tampered = value; },
    async dispatch(type, request) {
      const handler = hooks.get(type);
      assert.ok(handler, `Missing ${type} listener`);
      const waits = [];
      let intercepted = false;
      let response;
      const event = {
        request,
        waitUntil(p) { waits.push(p); },
        respondWith(p) { intercepted = true; response = Promise.resolve(p); },
      };
      handler(event);
      if (waits.length) await Promise.all(waits);
      return { intercepted, response: await response };
    },
  };
}

let passed = 0;
async function check(label, fn) {
  await fn();
  passed += 1;
  process.stdout.write(`PASS ${label}\n`);
}
await check('precache admits byte-bound credential-free resources', async () => {
  const h = harness();
  await h.dispatch('install');
  assert.equal(h.requests.length, paths.length);
  assert.ok(h.requests.every((request) => request.credentials === 'omit' && request.redirect === 'error'));
  const cache = await h.caches.open('collect-admin-isolated');
  assert.equal((await cache.keys()).length, paths.length);
});
await check('offline route navigation uses the verified shell only', async () => {
  const h = harness();
  await h.dispatch('install');
  const before = h.requests.length;
  const result = await h.dispatch('fetch', new MockRequest('/admin/sms-receipts?status=parsed', { mode: 'navigate' }));
  assert.ok(result.intercepted);
  assert.equal(result.response.data.toString(), files.get(new URL('./', scope).href));
  assert.equal(h.requests.length, before);
});
await check('private and unfamiliar assets never receive cached account content', async () => {
  const h = harness();
  await h.dispatch('install');
  for (const route of ['/api/admin/sms/receipts', '/v1/audit', '/admin/auth/local-challenge', '/privacy', '/account-deletion']) {
    const res = await h.dispatch('fetch', new MockRequest(route, { mode: 'navigate' }));
    assert.equal(res.intercepted, false, route);
  }
  for (const route of ['/outside-bundle.js', 'https://different.example.test/resource']) {
    const res = await h.dispatch('fetch', new MockRequest(route));
    assert.equal(res.intercepted, false, route);
  }
  const post = await h.dispatch('fetch', new MockRequest('/admin/', { method: 'POST', mode: 'navigate' }));
  assert.equal(post.intercepted, false);
});
await check('tampered static asset blocks install and discards incomplete cache', async () => {
  const h = harness({ tampered: true });
  await assert.rejects(() => h.dispatch('install'), /Admin asset bytes differ/);
  assert.equal((await h.caches.keys()).includes('collect-admin-isolated'), false);
});
await check('redirected and substituted responses block static install', async () => {
  for (const options of [{ redirected: true }, { wrongOrigin: true }]) {
    const h = harness(options);
    await assert.rejects(() => h.dispatch('install'), /Failed to cache static/);
    assert.equal((await h.caches.keys()).includes('collect-admin-isolated'), false);
  }
});
await check('failed reinstall preserves previously verified same-build cache', async () => {
  const h = harness();
  await h.dispatch('install');
  h.setTampered(true);
  await assert.rejects(() => h.dispatch('install'), /Admin asset bytes differ/);
  assert.equal((await h.caches.open('collect-admin-isolated')).entries.size, paths.length);
  const res = await h.dispatch('fetch', new MockRequest('/admin', { mode: 'navigate' }));
  assert.equal(res.response.data.toString(), files.get(new URL('./', scope).href));
});
await check('cache eviction fails closed without fetching new assets', async () => {
  const h = harness();
  await h.dispatch('install');
  const c = await h.caches.open('collect-admin-isolated');
  c.entries.delete(new URL(paths[1], scope).href);
  const before = h.requests.length;
  const response = await h.dispatch('fetch', new MockRequest(paths[1]));
  assert.equal(response.intercepted, true);
  assert.equal(response.response.status, 503);
  assert.equal(h.requests.length, before);
});
await check('activation removes only retired Collect and Flutter caches', async () => {
  const h = harness();
  await h.dispatch('install');
  await h.caches.open('collect-admin-retired');
  await h.caches.open('flutter-app-cache');
  await h.caches.open('unrelated-service-cache');
  await h.dispatch('activate');
  assert.deepEqual((await h.caches.keys()).sort(), ['collect-admin-isolated', 'unrelated-service-cache']);
});
console.log(`PASS ${passed}/${passed} isolated service-worker runtime checks`);
