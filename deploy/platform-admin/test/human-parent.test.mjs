import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createAdminWorker} from '../src/index.js';
import {renderLocalChallengeDocument} from '../../platform-supabase-free/local-challenge.mjs';

const QA = 'https://admin-supabase-qa.collect.ikanisa.com';
const PROD = 'https://platform-admin.collect.ikanisa.com';
const PATH = '/admin/auth/local-challenge';
const PROJECT = 'https://rrlduytparvsjfmegalh.supabase.co';
function fixture(origin = QA) {
  const calls = {backend: 0, legacy: 0, assets: 0};
  const worker = createAdminWorker({fetchImpl: async () => { calls.backend++; throw Error('No backend on parent route'); }});
  const env = {ADMIN_ORIGIN: origin, COLLECT_BACKEND: 'supabase', SUPABASE_URL: PROJECT,
    PLATFORM_API: {fetch: async () => { calls.legacy++; throw Error('No legacy fallback'); }},
    ASSETS: {fetch: async () => { calls.assets++; return new Response('OLD_SPA_FALLBACK', {headers: {'Content-Type': 'text/html'}}); }}};
  return {calls, env, async handle(path = PATH, options = {}) { return worker.fetch(new Request(origin + path, options), env); }, worker};
}

test('actual QA Admin host serves the human parent before SPA or backend dispatch', async () => {
  const f = fixture(); const response = await f.handle();
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /<title>Security verification · Collect<\/title>/);
  assert.doesNotMatch(html, /OLD_SPA_FALLBACK/);
  assert.equal(response.headers.get('Content-Type'), 'text/html; charset=utf-8');
  assert.deepEqual(f.calls, {backend: 0, legacy: 0, assets: 0});
});

test('existing renderer accepts QA only from explicit bounded configured origin', async () => {
  assert.equal(renderLocalChallengeDocument(new Request(QA + PATH)).status, 421);
  const reply = renderLocalChallengeDocument(new Request(QA + PATH), {origin: QA});
  assert.equal(reply.status, 200);
  assert.match(await reply.text(), new RegExp(JSON.stringify(QA).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  for (const options of [{origin: 'https://evil.invalid'}, {origin: QA + '/'}, {origin: 'http://admin-supabase-qa.collect.ikanisa.com'},
    {origin: 'https://admin-supabase-qa2.collect.ikanisa.com'}, {origin: undefined}, {origin: QA, extra: true}, null]) {
    assert.equal(renderLocalChallengeDocument(new Request(QA + PATH), options).status, 503);
  }
});

test('parent security headers permit only nonce scripts/styles and explicit loopback human handoff', async () => {
  for (const origin of [QA, PROD]) {
    const f = fixture(origin), response = await f.handle(); const html = await response.text();
    const nonce = html.match(/<script nonce="([a-f0-9]{48})">/)[1];
    assert.equal(response.headers.get('Cache-Control'), 'private, no-store, max-age=0, no-transform');
    for (const name of ['CDN-Cache-Control', 'Netlify-CDN-Cache-Control', 'Surrogate-Control']) assert.equal(response.headers.get(name), 'no-store');
    assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
    assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer');
    assert.equal(response.headers.get('Cross-Origin-Resource-Policy'), 'same-origin');
    assert.equal(response.headers.get('Cross-Origin-Opener-Policy'), 'same-origin');
    assert.equal(response.headers.get('X-Frame-Options'), 'DENY');
    assert.equal(response.headers.get('Permissions-Policy'), 'loopback-network=(self), local-network=(), camera=(), microphone=(), geolocation=()');
    assert.equal(response.headers.get('Content-Security-Policy'), `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self' http://127.0.0.1:*; frame-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; object-src 'none'`);
    assert.equal(response.headers.has('Set-Cookie'), false);
    assert.deepEqual(f.calls, {backend: 0, legacy: 0, assets: 0});
  }
});

test('current Admin host refuses retained suspicious parent forms without SPA fallback', async () => {
  const f = fixture();
  for (const path of [PATH + '/', PATH + '/extra', PATH + '-other', PATH + '.html', PATH + '%2fextra',
    '/admin/auth/%6cocal-challenge', '/admin/auth/local%2dchallenge', '/admin//auth/local-challenge',
    '/ADMIN/AUTH/LOCAL-CHALLENGE', PATH + '%252fextra', PATH + '%zz']) {
    const response = await f.handle(path); assert.equal(response.status, 404, path);
    assert.equal(response.headers.get('Content-Type'), 'application/json; charset=utf-8');
  }
  for (const suffix of ['?port=45123', '?', '#token', '#']) assert.equal((await f.handle(PATH + suffix)).status, 400);
  assert.deepEqual(f.calls, {backend: 0, legacy: 0, assets: 0});
});

test('host parent method, Host and origin checks cannot acquire another authority', async () => {
  const f = fixture();
  for (const method of ['HEAD', 'POST', 'PUT', 'DELETE', 'OPTIONS']) {
    const response = await f.handle(PATH, {method}); assert.equal(response.status, 405); assert.equal(response.headers.get('Allow'), 'GET');
  }
  for (const [headers, status] of [[{Host: 'other.example'}, 421], [{Origin: PROD}, 403],
    [{Origin: 'null'}, 403], [{'Sec-Fetch-Site': 'cross-site'}, 403]]) assert.equal((await f.handle(PATH, {headers})).status, status);
  assert.equal((await f.worker.fetch(new Request(PROD + PATH), f.env)).status, 403);
  const invalid = fixture('https://admin-supabase-qa2.collect.ikanisa.com');
  assert.equal((await invalid.handle()).status, 503); assert.deepEqual(invalid.calls, {backend: 0, legacy: 0, assets: 0});
  assert.deepEqual(f.calls, {backend: 0, legacy: 0, assets: 0});
});

test('unrelated Admin app pages and explicit legacy mode preserve their existing routing', async () => {
  const f = fixture(); const response = await f.handle('/admin/login');
  assert.equal(await response.text(), 'OLD_SPA_FALLBACK');
  assert.equal(response.headers.get('Cache-Control'), 'no-store, no-transform');
  assert.equal(response.headers.has('Permissions-Policy'), false); assert.equal(response.headers.has('Content-Security-Policy'), false);
  assert.deepEqual(f.calls, {backend: 0, legacy: 0, assets: 1});
  const legacy = fixture(PROD); legacy.env.COLLECT_BACKEND = 'cloudflare';
  assert.equal(await (await legacy.handle()).text(), 'OLD_SPA_FALLBACK');
  assert.deepEqual(legacy.calls, {backend: 0, legacy: 0, assets: 1});
});

test('undeployed Supabase template adds only bounded parent-first selector', async () => {
  const configuration = JSON.parse(await readFile(new URL('../wrangler.supabase.jsonc', import.meta.url), 'utf8'));
  assert.ok(configuration.assets.run_worker_first.includes('/admin/auth/local-challenge*'));
  assert.equal(configuration.assets.run_worker_first.some(path => path === '/admin/*' || path === '/admin/auth/*'), false);
  assert.equal(configuration.vars.ADMIN_ORIGIN, PROD);
  assert.equal(configuration.vars.COLLECT_BACKEND, 'supabase');
  assert.equal(configuration.vars.SUPABASE_URL, PROJECT);
});
