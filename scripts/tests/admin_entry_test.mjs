import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import entry from '../../deploy/admin-entry/src/index.mjs';

const old = 'https://admin.collect.ikanisa.com';
const target = 'https://platform-admin.collect.ikanisa.com';
const unavailable = new Proxy({}, {get() { throw new Error('No binding may be used'); }});
const respond = (path, init = {}) => entry.fetch(new Request(old + path, {
  ...init, headers: {Accept: 'text/html', ...init.headers},
}), unavailable);
const RETIREMENT_WORKER = await respond('/custom-sw.js').text();
function privateHeaders(response) {
  assert.equal(response.headers.get('Cache-Control'), 'no-store, no-transform');
  assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer');
  assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
  assert.equal(response.headers.get('Cross-Origin-Resource-Policy'), 'same-origin');
  assert.match(response.headers.get('Content-Security-Policy'), /frame-ancestors 'none'/);
  for (const name of ['Set-Cookie', 'Access-Control-Allow-Origin', 'Access-Control-Allow-Credentials',
    'Clear-Site-Data', 'Refresh']) assert.equal(response.headers.get(name), null, name);
}

test('document aliases inherit hashes and path entries normalize their exact task/query to canonical fragments', async () => {
  for (const [path, expected] of [
    ['/', '/'], ['/index.html', '/index.html'], ['/index.html?x=1', '/index.html?x=1'],
    ['/?q=a%2Bb&next=https%3A%2F%2Fevil.example', '/?q=a%2Bb&next=https%3A%2F%2Fevil.example'],
    ['/admin', '/admin'], ['/admin/users/abc?sort=name&sort=id', '/admin/users/abc?sort=name&sort=id'],
    ['/admin/transactions/321258000000001?returnTo=%2Fadmin%2Ftransactions', '/admin/transactions/321258000000001?returnTo=%2Fadmin%2Ftransactions'],
    ['/admin/users?search=a%2Bb%23c&returnTo=https%3A%2F%2Fevil.example', '/admin/users?search=a%2Bb%23c&returnTo=https%3A%2F%2Fevil.example'],
    ['/admin//evil.example?redirect=//evil.example', '/admin//evil.example?redirect=//evil.example'],
  ]) {
    for (const method of ['GET', 'HEAD']) {
      const response = respond(path, {method, headers: {'Sec-Fetch-Dest': 'document', 'Sec-Fetch-Mode': 'navigate'}});
      assert.equal(response.status, 302, path);
      const pathEntry = path.startsWith('/admin');
      assert.equal(response.headers.get('Location'), target + (pathEntry ? '/#' : '') + expected);
      assert.equal(new URL(response.headers.get('Location')).origin, target);
      assert.equal(new URL(response.headers.get('Location')).hash, pathEntry ? '#' + expected : '');
      if (pathEntry) {
        assert.equal(new URL(response.headers.get('Location')).pathname, '/');
        assert.equal(new URL(response.headers.get('Location')).search, '');
      }
      assert.equal(await response.text(), '');
      privateHeaders(response);
    }
  }
});

test('destination and alias origins cannot loop or become an open redirect', async () => {
  for (const origin of [target, 'http://admin.collect.ikanisa.com', 'https://admin.collect.ikanisa.com.evil.example',
    'https://admin.collect.ikanisa.com:444', 'https://collect-admin.example.workers.dev']) {
    const response = entry.fetch(new Request(origin + '/admin?target=' + target), unavailable);
    assert.equal(response.status, 403, origin);
    assert.equal(response.headers.get('Location'), null);
    privateHeaders(response);
  }
});

test('unsafe methods deny locally without reading or forwarding a request body or credentials', async () => {
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']) {
    for (const path of ['/', '/admin/groups', '/api/admin/auth/login', '/custom-sw.js']) {
      const request = new Request(old + path, {method, body: 'private-fixture-only', headers: {
        Cookie: 'legacy=synthetic', Authorization: 'Bearer synthetic', Origin: old,
      }});
      for (const key of ['text', 'json', 'arrayBuffer', 'formData', 'blob']) {
        request[key] = () => { throw new Error('Body must remain unread'); };
      }
      const response = entry.fetch(request, unavailable);
      assert.equal(response.status, 405);
      assert.equal(response.headers.get('Allow'), 'GET, HEAD');
      assert.equal(request.bodyUsed, false);
      assert.equal(response.headers.get('Location'), null);
      assert.doesNotMatch(await response.text(), /synthetic|private-fixture/);
      privateHeaders(response);
    }
  }
});

test('service, auth and stale asset aliases never redirect or return an application shell', async () => {
  for (const path of ['/api', '/api/admin/auth/session', '/API/admin/auth/session', '/%61pi/admin/auth/session',
    '/auth/v1/token', '/functions/v1/admin', '/rest/v1/users', '/main.dart.js', '/flutter_bootstrap.js',
    '/manifest.json', '/assets/AssetManifest.bin', '/_build/old/main.dart.js', '//evil.example/path',
    '/admin/../api/admin/auth/session', '/admin/%2e%2e/api/admin/auth/session']) {
    for (const method of ['GET', 'HEAD']) {
      const response = respond(path, {method});
      assert.equal(response.status, 410, path);
      assert.equal(response.headers.get('Location'), null);
      assert.match(response.headers.get('Content-Type'), /^application\/json/);
      assert.doesNotMatch(await response.text(), /<!doctype|<script|private|synthetic/i);
      privateHeaders(response);
    }
  }
});

test('malformed, double encoded, control and encoded separator paths fail closed', () => {
  for (const path of ['/admin/%', '/admin/%ff', '/admin/%2Fapi', '/admin/%5capi',
    '/admin/%2500', '/admin/%00', '/admin/%0a', '/admin/%7f', '/admin/%20']) {
    const response = respond(path);
    assert.equal(response.status, 400, path);
    assert.equal(response.headers.get('Location'), null);
    privateHeaders(response);
  }
});

test('fetch/XHR and subresource requests cannot follow the UI entry redirect', () => {
  for (const headers of [
    {'Sec-Fetch-Dest': 'empty', 'Sec-Fetch-Mode': 'same-origin'},
    {'Sec-Fetch-Dest': 'script', 'Sec-Fetch-Mode': 'no-cors'},
    {'Sec-Fetch-Dest': 'iframe', 'Sec-Fetch-Mode': 'navigate'},
    {'Sec-Fetch-Dest': 'document', 'Sec-Fetch-Mode': 'cors'},
    {'Sec-Fetch-Dest': 'document'}, {'Sec-Fetch-Mode': 'navigate'},
  ]) {
    const response = respond('/admin/users', {headers});
    assert.equal(response.status, 410);
    assert.equal(response.headers.get('Location'), null);
    privateHeaders(response);
  }
});

test('metadata-free legacy documents require a positive HTML Accept; ordinary HEAD remains available', () => {
  for (const accept of ['text/html', 'text/html;q=0.5', 'application/xhtml+xml', 'text/plain, text/html;q=1.000']) {
    assert.equal(respond('/admin/users', {headers: {Accept: accept}}).status, 302);
  }
  for (const accept of ['', '*/*', 'application/json', 'text/html;q=0', 'text/html;q=invalid', 'text/html;q=2']) {
    assert.equal(respond('/admin/users', {headers: {Accept: accept}}).status, 410);
  }
  for (const accept of ['', '*/*', 'text/html']) {
    assert.equal(respond('/admin/users', {method: 'HEAD', headers: {Accept: accept}}).status, 302);
  }
  assert.equal(respond('/admin/users', {method: 'HEAD', headers: {Accept: 'application/json'}}).status, 410);
});

test('credential-bearing requests and nested service or static aliases never redirect', () => {
  for (const name of ['Authorization', 'Proxy-Authorization']) {
    const response = respond('/admin', {headers: {[name]: 'Bearer synthetic'}});
    assert.equal(response.status, 403);
    assert.equal(response.headers.get('Location'), null);
  }
  for (const path of ['/admin/api/admin/auth/session', '/admin/%61uth/token', '/admin/functions/anything',
    '/admin/graphql', '/admin/rest/users', '/admin/main.dart.js', '/admin/assets/a.css', '/admin/index.html']) {
    assert.equal(respond(path).status, 410, path);
    assert.equal(respond(path).headers.get('Location'), null);
  }
});

test('exact historical service worker names serve same-origin JS even with bootstrap version queries', async () => {
  for (const path of ['/custom-sw.js', '/flutter_service_worker.js', '/custom-sw.js?v=old',
    '/flutter_service_worker.js?v=old']) {
    for (const method of ['GET', 'HEAD']) {
      const response = respond(path, {method, headers: {'Sec-Fetch-Dest': 'serviceworker', 'Sec-Fetch-Mode': 'same-origin'}});
      assert.equal(response.status, 200);
      assert.equal(response.headers.get('Location'), null);
      assert.equal(response.headers.get('Content-Type'), 'text/javascript; charset=utf-8');
      assert.equal(response.headers.get('Service-Worker-Allowed'), '/');
      assert.equal(await response.text(), method === 'HEAD' ? '' : RETIREMENT_WORKER);
      privateHeaders(response);
    }
  }
  for (const path of ['/admin/custom-sw.js', '/custom-sw.js/other', '/%63ustom-sw.js']) {
    assert.notEqual(respond(path).status, 200);
  }
});

test('retirement has only natural activation/unregister, without authority over active clients or storage', async () => {
  const handlers = new Map(), calls = [];
  vm.runInNewContext(RETIREMENT_WORKER, {
    self: {
      addEventListener: (name, handler) => handlers.set(name, handler),
      registration: {unregister: async () => { calls.push('unregister'); return true; }},
    },
  });
  assert.deepEqual([...handlers.keys()], ['activate']);
  assert.deepEqual(calls, []);
  let pending;
  handlers.get('activate')({waitUntil: value => { pending = value; }});
  await pending;
  assert.deepEqual(calls, ['unregister']);
  assert.doesNotMatch(RETIREMENT_WORKER, /skipWaiting|clients|caches|fetch|indexedDB|localStorage|sessionStorage|navigate|postMessage/);
});

test('candidate config is a separate binding-free replacement preserving observed domain/compatibility settings', async () => {
  const config = JSON.parse(await readFile(new URL('../../deploy/admin-entry/wrangler.jsonc', import.meta.url), 'utf8'));
  assert.equal(config.name, 'collect-admin');
  assert.equal(config.main, 'src/index.mjs');
  assert.equal(config.compatibility_date, '2026-08-20');
  assert.equal(config.workers_dev, true);
  assert.equal(config.preview_urls, true);
  assert.equal(config.observability.enabled, false);
  assert.deepEqual(config.routes, [{pattern: 'admin.collect.ikanisa.com', custom_domain: true, enabled: true, previews_enabled: false}]);
  for (const key of ['assets', 'services', 'vars', 'd1_databases', 'r2_buckets', 'send_email', 'triggers',
    'kv_namespaces', 'durable_objects', 'queues']) assert.equal(config[key], undefined, key);
});
