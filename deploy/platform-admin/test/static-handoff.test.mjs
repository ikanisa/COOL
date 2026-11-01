import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile, mkdtemp, mkdir, writeFile, rm, realpath} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import worker, {createAdminWorker} from '../src/index.js';
import {STATIC_RECOVERY_SCRIPT, versionedStatic} from '../src/static-recovery.js';
import {recoveryDom, installedWorker} from './fixtures/static-handoff-harness.mjs';
import {createWebApplication} from '../../self-hosted/web-server.mjs';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';

const origin = 'https://admin-supabase-qa.collect.ikanisa.com';
// Keep the managed fixture bound to the reviewed deployment profile.
const managedSupabaseOrigin = JSON.parse(await readFile(new URL('../wrangler.supabase.jsonc', import.meta.url))).vars.SUPABASE_URL;
const prior = '/_build/7f23b213325ba63698284d8d31dcb67e3487cf6b4d279e5ff50506950b206198/main.dart.js';
const current = '/_build/1ea54bebc61ec3e3833ded3175575b770be751cf902961803c3611dd35a7a391/main.dart.js';
const environment = assets => ({ADMIN_ORIGIN: origin, COLLECT_BACKEND: 'supabase',
  SUPABASE_URL: managedSupabaseOrigin, ASSETS: assets});
const request = (path = prior, init) => new Request(origin + path, init);
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const html = () => new Response('<html>current fixture</html>', {headers: {
  'Content-Type': 'text/html', 'Cache-Control': 'public, max-age=31536000, immutable'}});

test('Supabase production and QA route namespaced assets through the guard without changing managed routes', async () => {
  for (const name of ['wrangler.supabase.jsonc', 'wrangler.supabase-qa.jsonc']) {
    const profile = JSON.parse(await readFile(new URL('../' + name, import.meta.url)));
    assert.equal(profile.assets.run_worker_first.filter(path => path === '/_build/*').length, 1, name);
    assert.equal(profile.assets.not_found_handling, 'single-page-application', name);
    for (const path of ['/api', '/api/*', '/v1', '/v1/*', '/functions', '/functions/*',
      '/privacy/account-deletion', '/privacy/account-deletion/*']) {
      assert.ok(profile.assets.run_worker_first.includes(path), name + ': ' + path);
    }
  }
});

test('missing predecessor main becomes explicit noncacheable recovery without provider dispatch', async () => {
  let calls = 0, upstream = 0;
  const entry = createAdminWorker({fetchImpl: async () => {upstream++; throw Error('No provider call');}});
  const response = await entry.fetch(request(), environment({fetch: async received => {
    calls++; assert.equal(received.url, origin + prior); assert.equal(received.redirect, 'manual'); return html();
  }}));
  assert.equal(response.status, 200); assert.match(response.headers.get('Content-Type'), /^text\/javascript/);
  assert.match(response.headers.get('Cache-Control'), /no-store/); assert.doesNotMatch(response.headers.get('Cache-Control'), /immutable/);
  assert.equal(response.headers.get('X-Collect-Static-Recovery'), '1');
  assert.equal(await response.text(), STATIC_RECOVERY_SCRIPT); assert.equal(calls, 1); assert.equal(upstream, 0);
});

test('self-hosted Admin serves exact existing build and safe recovery for missing predecessor assets', async () => {
  const directory = await realpath(await mkdtemp(join(tmpdir(), 'collect-admin-static-handoff-')));
  try {
    const profile = {format:'collect.deployment.v1', id:'collect-static-test', mode:'self_hosted', environment:'production',
      supabase_origin:'https://supabase.example.test', member_api_origin:'https://api.example.test',
      admin_origin:'https://admin.example.test', public_origin:'https://collect.example.test',
      google_callback_origin:'https://admin.example.test'};
    const encoded = canonicalProfile(profile);
    await writeFile(join(directory, 'index.html'), '<main>synthetic Admin shell</main>');
    await mkdir(join(directory, '_build', '1ea54bebc61ec3e3833ded3175575b770be751cf902961803c3611dd35a7a391'), {recursive:true});
    await writeFile(join(directory, current.slice(1)), 'synthetic verified main');
    const app = await createWebApplication({COLLECT_BACKEND:'supabase', ADMIN_ORIGIN:profile.admin_origin,
      SUPABASE_URL:profile.supabase_origin, APP_ENVIRONMENT:profile.environment,
      COLLECT_DEPLOYMENT_PROFILE:encoded, COLLECT_DEPLOYMENT_PROFILE_SHA256:sha(encoded),
      COLLECT_ADMIN_ASSET_DIR:directory, COLLECT_PUBLIC_ASSET_DIR:directory});
    const get = path => app(new Request(profile.admin_origin + path, {headers:{Accept:'text/html'}}));
    const missing = await get(prior);
    assert.equal(missing.status, 200);
    assert.match(missing.headers.get('Content-Type'), /^text\/javascript/);
    assert.match(missing.headers.get('Cache-Control'), /no-store/);
    assert.equal(await missing.text(), STATIC_RECOVERY_SCRIPT);
    const live = await get(current);
    assert.equal(live.status, 200); assert.equal(await live.text(), 'synthetic verified main');
    const nonmain = await get(prior.replace('main.dart.js', 'assets/missing.woff2'));
    assert.equal(nonmain.status, 404); assert.doesNotMatch(await nonmain.text(), /synthetic Admin shell/);
  } finally {
    await rm(directory, {recursive:true, force:true});
  }
});

test('genuine current main and ranged assets retain their exact bytes/status/immutable headers', async () => {
  for (const status of [200, 206]) {
    const original = new Response('real fixture JavaScript bytes', {status, headers: {
      'Content-Type': 'text/javascript', 'Cache-Control': 'public, max-age=31536000, immutable', ETag: '"fixture"'}});
    const result = await versionedStatic(request(current), {fetch: async () => original});
    assert.equal(result, original); assert.equal(await result.text(), 'real fixture JavaScript bytes');
    assert.equal(result.status, status); assert.equal(result.headers.get('ETag'), '"fixture"');
  }
});

test('missing nonmain asset is404/no-store and never an HTML shell or recovery script', async () => {
  const response = await versionedStatic(request(prior.replace('main.dart.js', 'assets/missing.woff2')), {fetch: async () => html()});
  assert.equal(response.status, 404); assert.match(response.headers.get('Content-Type'), /^text\/plain/);
  assert.match(response.headers.get('Cache-Control'), /no-store/); assert.doesNotMatch(await response.text(), /<html>|collectStaticRecovery/);
});

test('redirects and cookie-bearing asset responses cannot become executable application authority', async () => {
  for (const make of [() => new Response(null, {status: 302, headers: {Location: 'https://other.invalid/main.js'}}),
    () => new Response('unqualified fixture JS', {headers: {'Content-Type': 'text/javascript', 'Set-Cookie': 'fixture=private'}})]) {
    const response = await versionedStatic(request(), {fetch: async received => {
      assert.equal(received.redirect, 'manual'); return make();}});
    assert.equal(response.headers.get('Set-Cookie'), null); assert.equal(response.headers.get('Location'), null);
    assert.equal(response.headers.get('X-Collect-Static-Recovery'), '1'); assert.equal(await response.text(), STATIC_RECOVERY_SCRIPT);
  }
});

test('conditional304 is revalidated once so a cached HTML fallback cannot authorize an asset', async () => {
  let calls = 0;
  const response = await versionedStatic(request(prior, {headers: {'If-None-Match': '"cached-html"', Range: 'bytes=0-10'}}), {
    fetch: async received => {calls++; if (calls === 1) return new Response(null, {status: 304});
      assert.equal(received.headers.get('If-None-Match'), null); assert.equal(received.headers.get('Range'), null); return html();}});
  assert.equal(calls, 2); assert.equal(response.headers.get('X-Collect-Static-Recovery'), '1');
});

test('conditional current304 revalidation preserves the genuine representation', async () => {
  let calls = 0;
  const expected = new Response('verified fixture JS', {headers: {'Content-Type': 'application/javascript'}});
  const response = await versionedStatic(request(current), {fetch: async () => ++calls === 1 ? new Response(null, {status: 304}) : expected});
  assert.equal(calls, 2); assert.equal(response, expected);
});

test('HEAD recovery has no body; mutations and wrong host cannot dispatch static/provider work', async () => {
  const head = await versionedStatic(request(prior, {method: 'HEAD'}), {fetch: async () => html()});
  assert.equal(head.status, 200); assert.equal(await head.text(), '');
  let calls = 0;
  const assets = {fetch: async () => {calls++; throw Error('Must not dispatch');}};
  const post = await versionedStatic(request(prior, {method: 'POST', body: '{}'}), assets);
  assert.equal(post.status, 405); assert.match(post.headers.get('Cache-Control'), /no-store/);
  const foreign = await worker.fetch(new Request('https://other.invalid' + prior), environment(assets));
  assert.equal(foreign.status, 403); assert.equal(calls, 0);
});

test('uncontrolled first-visit recovery is named/manual/idempotent and touches no private state', () => {
  const dom = recoveryDom(); dom.run(STATIC_RECOVERY_SCRIPT);
  const panel = dom.panel(); assert.ok(panel); assert.equal(panel.attributes.role, 'alert');
  assert.equal(panel.children[0].textContent, "Collect couldn't load this page");
  const reopen = panel.children[2]; assert.equal(reopen.textContent, 'Reopen Collect');
  assert.equal(dom.reloads, 0); assert.equal(dom.forbiddenEffects, 0);
  dom.run(STATIC_RECOVERY_SCRIPT); assert.equal(dom.document.body.children.length, 1);
  reopen.listeners.click(); assert.equal(dom.reloads, 1); assert.equal(dom.forbiddenEffects, 0);
});

test('recovery waits for DOM and never replaces a running Flutter view or unsaved editor', () => {
  const waiting = recoveryDom({loading: true}); waiting.run(STATIC_RECOVERY_SCRIPT); assert.equal(waiting.panel(), null);
  waiting.events.get('DOMContentLoaded')(); assert.ok(waiting.panel()); assert.equal(waiting.reloads, 0);
  for (const mode of [{running: true}, {editing: true}]) {
    const dom = recoveryDom(mode); dom.run(STATIC_RECOVERY_SCRIPT);
    assert.equal(dom.panel(), null); assert.equal(dom.document.body.children.length, 0);
    assert.equal(dom.reloads, 0); assert.equal(dom.forbiddenEffects, 0);
  }
});

test('fully installed worker keeps predecessor bytes after server switch; evicted entry503 never reaches server', async () => {
  const template = await readFile(new URL('../../../scripts/templates/admin_pwa_service_worker.js', import.meta.url), 'utf8');
  const main = new TextEncoder().encode('explicit synthetic VM-control predecessor');
  const shell = new TextEncoder().encode('<html>synthetic VM-control shell</html>');
  const source = template.replace('__COLLECT_ADMIN_CACHE_NAME__', JSON.stringify('collect-admin-handoff-fixture'))
    .replace('__COLLECT_ADMIN_CACHE_URLS__', JSON.stringify(['./', '.' + prior]))
    .replace('__COLLECT_ADMIN_CACHE_HASHES__', JSON.stringify({'./': sha(shell), ['.' + prior]: sha(main)}));
  const sw = await installedWorker(source, origin, new Map([[origin + '/', shell], [origin + prior, main]]));
  const before = sw.fetches, cached = await sw.read(origin + prior);
  assert.equal(sha(new Uint8Array(await cached.arrayBuffer())), sha(main)); assert.equal(sw.fetches, before);
  await sw.evict(origin + prior); assert.equal(await sw.admitted(), false);
  const evicted = await sw.read(origin + prior); assert.equal(evicted.status, 503);
  assert.match(evicted.headers.get('Cache-Control'), /no-store/); assert.equal(sw.fetches, before);
  assert.match(await evicted.text(), /Close all Admin tabs and reopen online/);
});

test('an explicit recovery script cannot pass the installed bundle hash check', async () => {
  const template = await readFile(new URL('../../../scripts/templates/admin_pwa_service_worker.js', import.meta.url), 'utf8');
  const main = new TextEncoder().encode('explicit synthetic expected application');
  const shell = new TextEncoder().encode('<html>synthetic VM-control shell</html>');
  const source = template.replace('__COLLECT_ADMIN_CACHE_NAME__', JSON.stringify('collect-admin-refusal-fixture'))
    .replace('__COLLECT_ADMIN_CACHE_URLS__', JSON.stringify(['./', '.' + prior]))
    .replace('__COLLECT_ADMIN_CACHE_HASHES__', JSON.stringify({'./': sha(shell), ['.' + prior]: sha(main)}));
  await assert.rejects(installedWorker(source, origin, new Map([[origin + '/', shell],
    [origin + prior, new TextEncoder().encode(STATIC_RECOVERY_SCRIPT)]])), /Admin asset bytes differ/);
});
