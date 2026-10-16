import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash, webcrypto } from 'node:crypto';
import vm from 'node:vm';

const template = await readFile(new URL('../templates/admin_cloudflare_shell_worker.js', import.meta.url), 'utf8');
const origin = 'https://admin.example.test/';
const name = 'collect-admin-shell-' + 'a'.repeat(64);
const bodies = { './': '<title>Collect Admin</title>', './main.dart.js': 'public build', './assets/FontManifest.json': '[]' };

function fixture({ mismatch = null, redirect = null, failure = null, delayed = null } = {}) {
  const handlers = new Map(), stores = new Map(), requests = [], calls = [];
  const responseBodies = { ...bodies };
  let offline = false;
  let refusedWrites = false;
  class Request {
    constructor(url, options = {}) { Object.assign(this, options, { url: new URL(url, origin).href }); }
  }
  const caches = {
    async open(key) {
      if (!stores.has(key)) stores.set(key, new Map());
      const entries = stores.get(key);
      return {
        async put(request, response) {
          if (refusedWrites) throw new Error('storage quota refused');
          entries.set(request.url, response);
        },
        async match(url) { return entries.get(typeof url === 'string' ? url : url.url); },
      };
    },
    async keys() { return [...stores.keys()]; },
    async delete(key) { calls.push(['delete', key]); return stores.delete(key); },
  };
  const source = template.replace('__COLLECT_SHELL_CACHE_NAME__', JSON.stringify(name))
    .replace('__COLLECT_SHELL_ASSET_HASHES__', JSON.stringify(Object.fromEntries(
      Object.entries(bodies).map(([url, body]) => [url, createHash('sha256').update(body).digest('hex')]))));
  vm.runInNewContext(source, {
    URL, Request, Response, crypto: webcrypto, Uint8Array,
    caches,
    fetch: async (request) => {
      requests.push(request);
      if (offline) throw new Error('network unavailable');
      const path = './' + new URL(request.url).pathname.slice(1);
      if (path === delayed) await new Promise((resolve) => setTimeout(resolve, 15));
      if (path === failure) throw new Error('network unavailable');
      const body = path === mismatch ? 'different build' : responseBodies[path];
      return {
        ok: true, type: 'basic', redirected: path === redirect,
        url: path === redirect ? origin + 'api/admin/auth/session' : request.url,
        body,
        clone() { return { ...this, async arrayBuffer() { return new TextEncoder().encode(body).buffer; } }; },
      };
    },
    self: {
      location: new URL(origin + 'admin-shell-sw.js'),
      addEventListener: (event, handler) => handlers.set(event, handler),
      skipWaiting: () => calls.push('skipWaiting'),
      clients: { claim: () => calls.push('claim') },
    },
  });
  return {
    stores, requests, calls,
    setOffline(value) { offline = value; },
    setRefuseWrites(value) { refusedWrites = value; },
    setBody(path, body) { responseBodies[path] = body; },
    async lifecycle(event) {
      let pending;
      handlers.get(event)({ waitUntil: (value) => { pending = value; } });
      return pending;
    },
    async request(path, { method = 'GET', mode = 'same-origin' } = {}) {
      let pending;
      handlers.get('fetch')({ request: { url: new URL(path, origin).href, method, mode }, respondWith: (value) => { pending = value; } });
      return pending ? pending : null;
    },
  };
}

test('only sealed public bytes are fetched without credentials or redirects', async () => {
  const f = fixture(); await f.lifecycle('install');
  assert.equal(f.requests.length, 3);
  for (const request of f.requests) {
    assert.equal(request.credentials, 'omit');
    assert.equal(request.redirect, 'error');
    assert.equal(request.cache, 'reload');
  }
  assert.deepEqual([...f.stores.get(name).keys()].sort(), Object.keys(bodies).map((path) => new URL(path, origin).href).sort());
  assert.equal((await f.request('/main.dart.js?v=new')).body, 'public build');
  assert.equal(f.requests.length, 3, 'runtime requests do not fetch/cache newer assets');
});

test('API/private/cross-origin/unknown navigation and every non-GET bypass the cache', async () => {
  const f = fixture(); await f.lifecycle('install');
  for (const path of ['/api/admin/auth/session', '/api/admin/team', '/api/gateway', '/private/receipt', '/unknown']) {
    assert.equal(await f.request(path), null);
    assert.equal(await f.request(path, { mode: 'navigate' }), null);
    assert.equal(await f.request(path, { method: 'POST' }), null);
  }
  assert.equal(await f.request('/main.dart.js', { method: 'PATCH' }), null);
  assert.equal(await f.request('/?token=private', { mode: 'navigate' }), null);
  assert.equal(await f.request('https://other.example/main.dart.js'), null);
  assert.equal(f.stores.get(name).size, 3);
  assert.equal(f.requests.length, 3);
});

test('only hash-router shell navigations receive the public offline shell', async () => {
  const f = fixture(); await f.lifecycle('install');
  for (const path of ['/', '/index.html', '/#/admin/users']) {
    assert.equal((await f.request(path, { mode: 'navigate' })).body, bodies['./']);
  }
});

test('new install waits without skipping or claiming and preserves old running cache until activation', async () => {
  const f = fixture();
  const old = 'collect-admin-shell-' + 'b'.repeat(64);
  f.stores.set(old, new Map());
  f.stores.set('collect-admin-0123456789abcdef', new Map());
  f.stores.set('flutter-app-cache', new Map());
  f.stores.set('collect-admin-unrelated', new Map());
  f.stores.set('other-app', new Map());
  await f.lifecycle('install');
  assert.ok(f.stores.has(old));
  assert.deepEqual(f.calls, []);
  await f.lifecycle('activate');
  assert.deepEqual([...f.stores.keys()], ['collect-admin-unrelated', 'other-app', name]);
  assert.ok(!f.calls.includes('skipWaiting'));
  assert.ok(!f.calls.includes('claim'));
});

for (const reason of ['mismatch', 'redirect', 'failure']) {
  test(`failed ${reason} install removes partial cache after all writes settle`, async () => {
    const f = fixture({ [reason]: './', delayed: './main.dart.js' });
    await assert.rejects(f.lifecycle('install'));
    assert.equal(f.stores.has(name), false);
    await new Promise((resolve) => setTimeout(resolve, 25));
    assert.equal(f.stores.has(name), false, 'late writes cannot recreate rejected cache');
  });
}

test('evicted shell asset can repair only its exact same-build bytes without credentials', async () => {
  const f = fixture(); await f.lifecycle('install');
  f.stores.get(name).delete(origin + 'main.dart.js');
  const response = await f.request('/main.dart.js');
  assert.equal(response.body, 'public build');
  assert.equal(f.stores.get(name).get(origin + 'main.dart.js').body, 'public build');
  assert.equal(f.requests.length, 4);
  assert.equal(f.requests.at(-1).credentials, 'omit');
  assert.equal(f.requests.at(-1).redirect, 'error');
});

test('corrupt cached public bytes are checked and replaced with the original build only', async () => {
  const f = fixture(); await f.lifecycle('install');
  const previous = f.stores.get(name).get(origin + 'main.dart.js');
  f.stores.get(name).set(origin + 'main.dart.js', { ...previous,
    clone() { return { async arrayBuffer() { return new TextEncoder().encode('corrupted bytes').buffer; } }; },
  });
  assert.equal((await f.request('/main.dart.js')).body, 'public build');
  assert.equal(f.requests.length, 4);
});

test('evicted asset refuses newer network build bytes and preserves request/session state', async () => {
  const f = fixture(); await f.lifecycle('install');
  f.stores.get(name).delete(origin + 'main.dart.js');
  f.setBody('./main.dart.js', 'newer incompatible build');
  const response = await f.request('/main.dart.js');
  assert.equal(response.status, 503);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.match(await response.text(), /Keep original request references; do not clear cookies or session data/);
  assert.equal(f.stores.get(name).has(origin + 'main.dart.js'), false);
  assert.equal(f.requests.length, 4);
});

test('offline partial eviction shows an honest failure and reconnect repairs without site-data clearing', async () => {
  const f = fixture(); await f.lifecycle('install');
  f.stores.get(name).delete(origin + 'main.dart.js');
  f.setOffline(true);
  const response = await f.request('/main.dart.js');
  assert.equal(response.status, 503);
  assert.equal(f.stores.get(name).has(origin + 'main.dart.js'), false);
  f.setOffline(false);
  assert.equal((await f.request('/main.dart.js')).body, 'public build');
  assert.equal(f.stores.get(name).has(origin + 'main.dart.js'), true);
});

test('refused repair storage serves only verified online bytes without claiming a durable cache entry', async () => {
  const f = fixture(); await f.lifecycle('install');
  f.stores.get(name).delete(origin + 'main.dart.js');
  f.setRefuseWrites(true);
  assert.equal((await f.request('/main.dart.js')).body, 'public build');
  assert.equal(f.stores.get(name).has(origin + 'main.dart.js'), false);
  assert.equal(f.requests.length, 4);
});
