import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import entry from '../../deploy/admin-entry/src/index.mjs';

const old = 'https://admin.collect.ikanisa.com';
const preview = 'https://admin-preview.collect.ikanisa.com';
const target = 'https://platform-admin.collect.ikanisa.com';
const securityStage = 'https://admin16-security-stage.collect.ikanisa.com';
const qualification = 'https://admin-supabase-qa.collect.ikanisa.com';
const destinationFor = origin => origin === securityStage ? qualification : target;
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

async function visit(origin, path, options = {}) {
  const original = new URL(path, origin);
  const target = destinationFor(origin);
  const browserScript = await entry.fetch(new Request(origin + '/admin-entry-handoff.js')).text();
  const elements = Object.fromEntries(['primary', 'alternative', 'guidance'].map(name =>
    [name, {href: target + '/#/admin', hidden: name === 'alternative'}]));
  const redirects = [];
  const state = length => ({
    get length() {
      if (options.storageDenied) throw new Error('Storage unavailable');
      return length ?? 0;
    },
    getItem() { throw new Error('Stored values must remain unopened'); },
    setItem() { throw new Error('Old state must remain intact'); },
    removeItem() { throw new Error('Old state must remain intact'); },
  });
  await vm.runInNewContext(browserScript, {
    URL,
    document: {
      getElementById: id => elements[id],
      querySelector: selector => selector === 'main[data-preserve]' && options.cookie ? {} : null,
    },
    window: {
      location: {href: original.href, replace: destination => redirects.push(destination)},
      history: {state: options.history ?? null},
      navigator: {serviceWorker: {controller: options.controlled ? {} : null}},
      caches: {keys: async () => options.cached ? ['old-cache'] : []},
      indexedDB: {databases: async () => options.database ? [{name: 'old-store'}] : []},
      localStorage: state(options.local), sessionStorage: state(options.session),
    },
  });
  return {redirects, elements};
}

test('clean path and hash bookmarks reach the React hash router with their encoded task and query', async () => {
  for (const origin of [old, preview, securityStage]) {
    const target = destinationFor(origin);
    for (const [path, expected] of [
      ['/', '/admin'], ['/index.html', '/admin'], ['/admin', '/admin'],
      ['/#/admin/settings?section=staff', '/admin/settings?section=staff'],
      ['/admin/users/abc?sort=name&sort=id', '/admin/users/abc?sort=name&sort=id'],
      ['/index.html#/admin/transactions?view=momo', '/admin/transactions?view=momo'],
      ['/admin/users?search=a%2Bb%23c', '/admin/users?search=a%2Bb%23c'],
      ['/admin/users#/admin/users', '/admin/users'],
      ['/admin/transactions/321258000000001?returnTo=%2Fadmin%2Ftransactions', '/admin/transactions/321258000000001?returnTo=%2Fadmin%2Ftransactions'],
    ]) {
      for (const method of ['GET', 'HEAD']) {
        const url = new URL(path, origin);
        url.hash = '';
        const response = entry.fetch(new Request(url, {method, headers: {Accept: 'text/html'}}), unavailable);
        assert.equal(response.status, 200);
        assert.equal(response.headers.get('Location'), null);
        privateHeaders(response);
        const body = await response.text();
        if (method === 'HEAD') assert.equal(body, '');
        else {
          assert.match(body, /src="\/admin-entry-handoff\.js"/);
          assert.match(body, /target="_blank" rel="noopener noreferrer"/);
          assert.doesNotMatch(body, /sort=name|returnTo=|321258000000001/);
        }
      }
      assert.deepEqual((await visit(origin, path)).redirects, [target + '/#' + expected]);
    }
  }
});

test('a mixed bookmark preserves its original address and offers only compatible React routes in new tabs', async () => {
  for (const origin of [old, preview, securityStage]) {
    const target = destinationFor(origin);
    const both = await visit(origin, '/admin/settings?section=staff#/admin/transactions?view=momo');
    assert.equal(both.redirects.length, 0);
    assert.equal(both.elements.primary.href, target + '/#/admin/transactions?view=momo');
    assert.equal(both.elements.alternative.href, target + '/#/admin/settings?section=staff');
    assert.equal(both.elements.alternative.hidden, false);
    for (const [path, restored] of [
      ['/admin/users?sort=name#section', '/admin/users?sort=name'],
      ['/?q=old#/admin/groups', '/admin/groups'], ['/#old-anchor', '/admin'],
      ['/admin//unexpected', '/admin'], ['/#/admin/%2Fother', '/admin'],
      ['/#/admin/auth/token', '/admin'], ['/#/admin/users?sort=name#section', '/admin/users?sort=name'],
      ['/#/admin/setup?token=fixture-only', '/admin'],
      ['/admin/login?returnTo=%2Fadmin%2Fsetup%3Ftoken%3Dfixture-only', '/admin'],
      ['/admin/requests?key=synthetic-old-operation', '/admin'],
    ]) {
      const held = await visit(origin, path);
      assert.equal(held.redirects.length, 0, path);
      assert.equal(held.elements.primary.href, target + '/#' + restored, path);
      assert.equal(held.elements.alternative.hidden, true);
    }
  }
});

test('existing cookie, local data, same-tab drafts, unavailable storage or History state preserve the original tab', async () => {
  for (const origin of [old, preview, securityStage]) {
    const target = destinationFor(origin);
    const request = new Request(origin + '/admin/users', {headers: {Accept: 'text/html', Cookie: 'prior=synthetic-only'}});
    const html = await entry.fetch(request, unavailable).text();
    assert.match(html, /<main data-preserve>/);
    assert.ok(html.includes('href="' + target + '/#/admin"'));
    assert.ok(!html.includes(origin === securityStage ? 'https://platform-admin.' : 'https://admin-supabase-qa.'));
    assert.doesNotMatch(html, /synthetic-only|prior=/);
    for (const options of [{cookie: true}, {local: 1}, {session: 1}, {storageDenied: true}, {history: {old: 'draft'}},
      {cached: true}, {database: true}, {controlled: true}]) {
      const held = await visit(origin, '/admin/users', options);
      assert.equal(held.redirects.length, 0);
      assert.equal(held.elements.primary.href, target + '/#/admin/users');
    }
  }
});

test('the former preview retires all retained worker URLs and denies stale resources locally', async () => {
  const read = (path, init = {}) => entry.fetch(new Request(preview + path, {
    ...init, headers: {Accept: 'text/html', Cookie: 'old=fixture', ...init.headers},
  }), unavailable);
  for (const path of ['/custom-sw.js', '/flutter_service_worker.js?v=old', '/admin-shell-sw.js?v=old']) {
    const response = read(path, {headers: {'Sec-Fetch-Dest': 'serviceworker', 'Sec-Fetch-Mode': 'same-origin'}});
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Service-Worker-Allowed'), '/');
    assert.equal(response.headers.get('Content-Type'), 'text/javascript; charset=utf-8');
    assert.equal(response.headers.get('Location'), null);
    assert.equal(await response.text(), RETIREMENT_WORKER);
    privateHeaders(response);
  }
  for (const [path, init, status] of [
    ['/manifest.json', {}, 410], ['/version.json', {}, 410], ['/flutter_bootstrap.js', {}, 410],
    ['/api/admin/auth/session', {}, 410], ['/admin/settings', {headers: {Accept: 'application/json'}}, 410],
    ['/admin', {headers: {Authorization: 'Bearer fixture-only'}}, 403], ['/', {method: 'POST'}, 405],
  ]) {
    const response = read(path, init);
    assert.equal(response.status, status);
    assert.equal(response.headers.has('Location'), false);
    privateHeaders(response);
  }
});

test('destination and alias origins cannot loop or become an open redirect', async () => {
  for (const origin of [target, 'http://admin.collect.ikanisa.com', 'https://admin.collect.ikanisa.com.evil.example',
    'https://admin.collect.ikanisa.com:444', 'https://collect-admin.example.workers.dev',
    'https://admin-supabase-qa.collect.ikanisa.com', 'http://admin-preview.collect.ikanisa.com',
    'https://admin-preview.collect.ikanisa.com:444', 'https://admin-preview.collect.ikanisa.com.evil.example']) {
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
    assert.equal(respond('/admin/users', {headers: {Accept: accept}}).status, 200);
  }
  for (const accept of ['', '*/*', 'application/json', 'text/html;q=0', 'text/html;q=invalid', 'text/html;q=2']) {
    assert.equal(respond('/admin/users', {headers: {Accept: accept}}).status, 410);
  }
  for (const accept of ['', '*/*', 'text/html']) {
    assert.equal(respond('/admin/users', {method: 'HEAD', headers: {Accept: accept}}).status, 200);
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
    '/flutter_service_worker.js?v=old', '/admin-shell-sw.js', '/admin-shell-sw.js?v=prior']) {
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
  for (const path of ['/admin/custom-sw.js', '/custom-sw.js/other', '/%63ustom-sw.js', '/admin-shell-sw.js/other', '/%61dmin-shell-sw.js']) {
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
  // Version 41 serves its old Flutter application on its immutable preview URL.
  assert.equal(config.preview_urls, false);
  assert.equal(config.observability.enabled, false);
  assert.deepEqual(config.routes, [
    {pattern: 'admin.collect.ikanisa.com', custom_domain: true, enabled: true, previews_enabled: false},
    {pattern: 'admin-preview.collect.ikanisa.com/*', zone_name: 'ikanisa.com'},
    {pattern: 'admin16-security-stage.collect.ikanisa.com/*', zone_name: 'ikanisa.com'},
  ]);
  for (const key of ['assets', 'services', 'vars', 'd1_databases', 'r2_buckets', 'send_email', 'triggers',
    'kv_namespaces', 'durable_objects', 'queues']) assert.equal(config[key], undefined, key);
});

test('preview and security-stage routing preserve their scoped backend owners', async () => {
  const manifest = JSON.parse(await readFile(new URL('../../deploy/admin-entry/preview-backend-routes.json', import.meta.url)));
  assert.equal(manifest.zone, 'ikanisa.com');
  assert.deepEqual(manifest.custom_domain_owners, {'admin-preview.collect.ikanisa.com':'collect-admin-cloudflare',
    'admin16-security-stage.collect.ikanisa.com':'collect-admin16-security-stage-20261016'});
  assert.deepEqual(manifest.routes, [
    {pattern: 'admin-preview.collect.ikanisa.com/api/admin/*', script: null},
    {pattern: 'admin-preview.collect.ikanisa.com/api/gateway', script: null},
    {pattern: 'admin-preview.collect.ikanisa.com/api/gateway/*', script: null},
    {pattern: 'admin16-security-stage.collect.ikanisa.com/api/admin/*', script: null},
  ]);
});
