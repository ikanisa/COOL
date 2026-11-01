import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {readFile} from 'node:fs/promises';
import {build, version} from 'esbuild';
import {harness, FRONT, QA, PATH} from '../../../test/fixtures/local-challenge-parent-harness.mjs';
import {renderLocalChallengeDocument} from '../../platform-supabase-free/local-challenge.mjs';
import {STATIC_RECOVERY_SCRIPT} from '../src/static-recovery.js';
import {recoveryDom} from './fixtures/static-handoff-harness.mjs';

// Mirror the actual Wrangler 4.151.0 deployment transform that exposed the
// Function.toString closure defect. A source-only import cannot detect it.
assert.equal(version, '0.28.2', 'Use the exact locked hosting compiler');
const compiled = await build({
  entryPoints: [fileURLToPath(new URL('../src/index.js', import.meta.url))],
  bundle: true, format: 'esm', target: 'es2024', keepNames: true,
  supported: {'import-source': true, using: true},
  loader: {'.js': 'jsx', '.mjs': 'jsx', '.cjs': 'jsx'},
  conditions: ['workerd', 'worker', 'browser'],
  sourcemap: 'inline', minify: false, write: false, logLevel: 'silent',
});


const code = compiled.outputFiles[0].text;
const {default: worker} = await import('data:text/javascript;base64,' + Buffer.from(code).toString('base64'));
// Use the reviewed managed deployment profile without duplicating its host.
const managedSupabaseOrigin = JSON.parse(await readFile(new URL('../wrangler.supabase.jsonc', import.meta.url))).vars.SUPABASE_URL;
const bundleSha = createHash('sha256').update(code).digest('hex');
const presentation = html => html.replace(/<script nonce="[a-f0-9]+">[\s\S]*?<\/script>/, '')
  .replaceAll(/nonce="[a-f0-9]+"/g, 'nonce="RENDER_NONCE"');

for (const origin of [FRONT, QA]) test(`actual kept-name Admin bundle executes its isolated ${origin} inline parent`, async t => {
  t.diagnostic(`esbuild ${version}; keepNames=true; format=esm; target=es2024; bundle_sha256=${bundleSha}`);
  let staticDispatches = 0;
  const env = {ADMIN_ORIGIN: origin, COLLECT_BACKEND: 'supabase',
    SUPABASE_URL: managedSupabaseOrigin,
    ASSETS: {fetch() { staticDispatches++; throw Error('Parent must not fall back to assets'); }}};
  let parent;
  const f = await harness({origin, render: async request => {
    parent = await worker.fetch(request, env);
    assert.equal(parent.status, 200);
    assert.equal(parent.headers.get('Cache-Control'), 'private, no-store, max-age=0, no-transform');
    assert.equal(parent.headers.get('Permissions-Policy'), 'loopback-network=(self), local-network=(), camera=(), microphone=(), geolocation=()');
    assert.equal(parent.headers.has('Set-Cookie'), false);
    return parent;
  }});
  // The harness VM intentionally has no esbuild helper globals. Bootstrap must
  // actually register listeners before any human interaction or fixture fetch.
  assert.equal(f.elements['pairing-form'].listeners.has('submit'), true);
  assert.equal(f.calls.length, 0); assert.equal(f.frame(), undefined);
  const plain = renderLocalChallengeDocument(new Request(origin + PATH), {origin});
  assert.equal(presentation(f.html), presentation(await plain.text()));
  const nonce = f.html.match(/<script nonce="([a-f0-9]{48})">/)[1];
  assert.equal(parent.headers.get('Content-Security-Policy'), `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self' http://127.0.0.1:*; frame-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; object-src 'none'`);
  await f.connect(); assert.equal(f.calls.length, 1);
  const frame = f.frame(); assert.ok(frame);
  assert.equal(new URL(frame.src).origin, origin);
  assert.equal(new URL(frame.src).searchParams.get('parent_origin'), origin);
  assert.equal(f.elements.status.dataset.state, 'verifying');
  const candidate = {type: 'collect.turnstile.v1', attempt_id: f.descriptor.attempt_id,
    token: 'SYNTHETIC_BUNDLED_PARENT_NOT_PROVIDER_VERIFIED'};
  // A valid token-shaped fixture from the other approved origin is still foreign.
  await f.candidate(candidate, {origin: origin === QA ? FRONT : QA});
  assert.equal(f.calls.length, 1);
  await f.candidate(candidate);
  await f.window.emit('message', {origin, source: frame.contentWindow, data: candidate});
  await f.connect();
  assert.equal(f.calls.length, 2);
  assert.equal(f.calls[1].options.method, 'POST');
  assert.equal(f.calls[1].body.token, candidate.token);
  assert.equal(f.calls[1].body.operation, f.descriptor.operation);
  assert.equal(f.calls[1].options.credentials, 'omit');
  assert.equal(f.calls[1].url.includes(candidate.token), false);
  assert.equal(f.frame(), undefined); assert.equal(f.timers.size, 0);
  assert.equal(f.elements.status.dataset.state, 'complete');
  assert.match(f.elements.status.textContent, /terminal for the sign-in result/);
  assert.equal(staticDispatches, 0);
});

// Exercise the same kept-name bundle used above, not only the unbundled worker.
test('actual kept-name Admin bundle serves manual predecessor recovery instead of SPA HTML', async () => {
  const path = '/_build/7f23b213325ba63698284d8d31dcb67e3487cf6b4d279e5ff50506950b206198/main.dart.js';
  let calls = 0;
  const env = {ADMIN_ORIGIN: QA, COLLECT_BACKEND: 'supabase',
    SUPABASE_URL: managedSupabaseOrigin,
    ASSETS: {async fetch() { calls++; return new Response('<html>old fallback</html>', {headers: {
      'Content-Type': 'text/html', 'Cache-Control': 'public, max-age=31536000, immutable'}}); }}};
  const response = await worker.fetch(new Request(QA + path), env);
  assert.equal(calls, 1); assert.equal(response.status, 200);
  assert.match(response.headers.get('Content-Type'), /^text\/javascript/);
  assert.match(response.headers.get('Cache-Control'), /no-store/);
  assert.equal(response.headers.get('X-Collect-Static-Recovery'), '1');
  const body = await response.text(); assert.equal(body, STATIC_RECOVERY_SCRIPT);
  const dom = recoveryDom(); dom.run(body);
  assert.equal(dom.panel().children[2].textContent, 'Reopen Collect');
  assert.equal(dom.reloads, 0); assert.equal(dom.forbiddenEffects, 0);
  dom.panel().children[2].listeners.click();
  assert.equal(dom.reloads, 1); assert.equal(dom.forbiddenEffects, 0);
});
