import {test} from 'node:test';
import assert from 'node:assert/strict';
import {fixture, PASSWORD, ORIGIN} from './admin_support/fixture.mjs';
const {default: proxy} = await import(process.env.COLLECT_ADMIN_PROXY_MODULE ?? '../../platform-admin/src/index.js');

test('same-origin service forwarding preserves the real origin-bound account cookie and never serves API failures as HTML', async t => {
  const f = await fixture(t), owner = await f.seedAccount();
  let assetReads = 0;
  const env = {ADMIN_ORIGIN: ORIGIN,
    PLATFORM_API: {fetch: async request => f.mf.dispatchFetch(request.url, {method: request.method, headers: request.headers, ...(request.method === 'GET' || request.method === 'HEAD' ? {} : {body: await request.text()})})},
    ASSETS: {fetch: () => {assetReads++; return new Response('static shell');}},
  };
  const login = await proxy.fetch(new Request(ORIGIN + '/api/admin/auth/login', {
    method: 'POST', headers: {Origin: ORIGIN, 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.10'},
    body: JSON.stringify({email: owner.email, password: PASSWORD}),
  }), env);
  assert.equal(login.status, 200);
  const cookie = login.headers.get('set-cookie').split(';')[0];
  assert.ok(login.headers.get('set-cookie').includes('HttpOnly'));
  assert.equal(login.headers.get('cache-control'), 'no-store');
  const read = await proxy.fetch(new Request(ORIGIN + '/api/admin/auth/session', {headers: {Cookie: cookie}}), env);
  const result = await read.json();
  assert.equal(result.user.email, owner.email);
  assert.equal(result.user.principalId, owner.userId);
  const wrong = await proxy.fetch(new Request('https://wrong.example/api/admin/auth/session', {headers: {Cookie: cookie}}), env);
  assert.equal(wrong.status, 403);
  const unknown = await proxy.fetch(new Request(ORIGIN + '/api/unknown'), env);
  assert.equal(unknown.status, 404);
  const missing = await proxy.fetch(new Request(ORIGIN + '/api/admin/auth/session'), {...env, PLATFORM_API: null});
  assert.equal(missing.status, 503);
  assert.equal(missing.headers.get('cache-control'), 'no-store');
  assert.equal(assetReads, 0);
  const shell = await proxy.fetch(new Request(ORIGIN + '/'), env);
  assert.equal(await shell.text(), 'static shell');
  assert.equal(assetReads, 1);
});

test('HTML asset responses retain exact bytes and security headers with no-store and no-transform', async () => {
  const body = '<!doctype html><title>Collect Admin</title>';
  for (const contentType of ['text/html; charset=utf-8', 'Text/HTML']) {
    const response = await proxy.fetch(new Request(ORIGIN + '/admin/privacy-requests'), {
      ADMIN_ORIGIN: ORIGIN,
      ASSETS: {fetch: async () => new Response(body, {headers: {
        'Content-Type': contentType, 'Cache-Control': 'no-store',
        'Content-Security-Policy': "default-src 'self'; object-src 'none'",
        'X-Content-Type-Options': 'nosniff', 'X-Asset-Version': 'original',
      }})},
    });
    assert.equal(response.status, 200);
    assert.equal(await response.text(), body);
    assert.equal(response.headers.get('Cache-Control'), 'no-store, no-transform');
    assert.equal(response.headers.get('Content-Security-Policy'), "default-src 'self'; object-src 'none'");
    assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
    assert.equal(response.headers.get('X-Asset-Version'), 'original');
  }
});

test('non-HTML asset cache policies and exact payloads remain unchanged', async () => {
  const bytes = Uint8Array.from([0, 1, 2, 127, 255]);
  const response = await proxy.fetch(new Request(ORIGIN + '/_build/current/engine.wasm'), {
    ADMIN_ORIGIN: ORIGIN,
    ASSETS: {fetch: async () => new Response(bytes, {headers: {
      'Content-Type': 'application/wasm',
      'Cache-Control': 'public, max-age=31536000, immutable', 'ETag': 'original',
    }})},
  });
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes);
  assert.equal(response.headers.get('Cache-Control'), 'public, max-age=31536000, immutable');
  assert.equal(response.headers.get('ETag'), 'original');
});
