#!/usr/bin/env node
// Real Chromium lifecycle with production postprocessing and tiny static fixtures.
// These pages model pending work; they do not certify the Admin business workflow.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { spawn, spawnSync } from 'node:child_process';
import { cp, mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, join, relative, resolve, sep } from 'node:path';
import { observeWaitingAdminUpdate, reopenAfterAllAdminTabsLeave } from '../qa/admin_pwa_update_policy.mjs';

const root = resolve('.');
const output = resolve(process.argv[2] || '');
if (!process.argv[2] || !output.startsWith(join(root, '.cache') + sep) || existsSync(output)) throw Error('A new task-owned cache output is required');
await mkdir(output, { recursive: true });
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
const inputPaths = ['scripts/tests/admin_pwa_update_browser_test.mjs', 'scripts/qa/admin_pwa_update_policy.mjs',
  'scripts/templates/admin_pwa_service_worker.js', 'scripts/admin_pwa_release_build.sh', 'scripts/admin_pwa_manifest_gate.sh',
  'scripts/admin_pwa_hosting_gate.sh', 'scripts/admin_pwa_live_gate.sh', 'web/flutter_bootstrap.js', 'web/_headers',
  'web/index.html', 'web/robots.txt', 'web/icons/collect-web-512.png', 'lib/app/theme/collect_colors.dart'];
const snapshot = async () => Object.fromEntries(await Promise.all(inputPaths.map(async (path) => [path, sha(await readFile(path))])));
const report = { started_at: new Date().toISOString(), status: 'running', final_acceptance: false,
  scope: 'real_chromium_loopback_tiny_static_fixtures_current_production_postprocessor',
  source_before: await snapshot(), checks: [], requests: [], commands: [], errors: [], hosted: false,
  actual_admin_workflow: false, provider_calls: 0 };
function check(id, condition, observed) {
  report.checks.push({ id, pass: Boolean(condition), observed });
  console.log(id + ': ' + (condition ? 'PASS' : 'FAIL'));
  assert.ok(condition, id);
}
async function inventory(directory) {
  const values = {};
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      for (const [child, hash] of Object.entries(await inventory(path))) values[join(entry.name, child)] = hash;
    } else if (entry.isFile()) values[entry.name] = sha(await readFile(path));
  }
  return values;
}
const builder = await readFile('scripts/admin_pwa_release_build.sh', 'utf8');
const marker = "ruby -r digest -r json -r open3 <<'RUBY'\n";
assert.equal(builder.split(marker).length, 2);
await writeFile(join(output, 'postprocessor.rb'), builder.split(marker)[1].split('\nRUBY\n')[0]);
const sourceBootstrap = await readFile('web/flutter_bootstrap.js', 'utf8');
async function stage(name, existingArtifact) {
  const stageRoot = join(output, name), directory = join(stageRoot, 'build/web');
  await mkdir(directory, { recursive: true });
  if (existingArtifact) await cp(existingArtifact, directory, { recursive: true });
  else {
    await mkdir(join(directory, 'assets'), { recursive: true });
    await mkdir(join(directory, 'icons'), { recursive: true });
    const index = (await readFile('web/index.html', 'utf8')).replace('$FLUTTER_BASE_HREF', '/').replace(/<style>[^]*?<\/style>/, '')
      .replace('<body>', '<body><input id="pending" aria-label="Pending fixture work"><span id="version"></span>');
    await writeFile(join(directory, 'index.html'), index);
    await writeFile(join(directory, 'manifest.json'), '{}');
    await writeFile(join(directory, 'version.json'), '{}');
    await writeFile(join(directory, 'assets/lazy.txt'), 'lazy-' + name);
    await writeFile(join(directory, 'main.dart.js'), `window.fixtureVersion=${JSON.stringify(name)};document.querySelector('#version').textContent=window.fixtureVersion;window.fixtureReady=true;`);
    await cp('web/icons/collect-web-512.png', join(directory, 'icons/collect-web-512.png'));
  }
  let flutterPrefix;
  if (existingArtifact) {
    const priorBootstrap = await readFile(join(directory, 'flutter_bootstrap.js'), 'utf8');
    const boundary = priorBootstrap.indexOf("window.addEventListener('load',");
    assert.ok(boundary > 0, 'Known compiled Flutter loader boundary');
    flutterPrefix = priorBootstrap.slice(0, boundary);
    report.compatibility_artifact = { path: relative(root, existingArtifact), files: await inventory(existingArtifact),
      qualification: 'dated compiled app bytes adapted only through current bootstrap and postprocessor; not a current-source app build' };
  } else {
    flutterPrefix = `window._flutter={loader:{load:function(options){window.fixtureConfig=options.config;var script=document.createElement('script');script.src=options.config.entrypointBaseUrl+'main.dart.js';document.head.appendChild(script);}}};`;
  }
  await writeFile(join(directory, 'flutter_bootstrap.js'), sourceBootstrap.replace('{{flutter_js}}\n{{flutter_build_config}}', flutterPrefix));
  await cp('web/_headers', join(directory, '_headers'));
  await cp('web/robots.txt', join(directory, 'robots.txt'));
  for (const path of ['lib/app/theme/collect_colors.dart', 'scripts/templates/admin_pwa_service_worker.js']) {
    await mkdir(dirname(join(stageRoot, path)), { recursive: true }); await cp(path, join(stageRoot, path));
  }
  const result = spawnSync('ruby', ['-r', 'digest', '-r', 'json', '-r', 'open3', join(output, 'postprocessor.rb')], { cwd: stageRoot, encoding: 'utf8' });
  await writeFile(join(output, name + '.postprocess.log'), result.stdout + result.stderr);
  assert.equal(result.status, 0, name + ' production postprocessing');
  for (const gate of ['admin_pwa_manifest_gate.sh', 'admin_pwa_hosting_gate.sh']) {
    const validated = spawnSync('bash', [join(root, 'scripts', gate)], { env: { ...process.env, ADMIN_PWA_BUILD_DIR: directory }, encoding: 'utf8' });
    report.commands.push({ command: gate, stage: name, exit: validated.status });
    await writeFile(join(output, name + '.' + gate + '.log'), validated.stdout + validated.stderr);
    assert.equal(validated.status, 0, name + ' ' + gate);
  }
  const bootstrap = await readFile(join(directory, 'flutter_bootstrap.js'), 'utf8');
  const worker = await readFile(join(directory, 'custom-sw.js'), 'utf8');
  return { directory, name, assetBase: bootstrap.match(/var adminAssetBase = '([^']+)'/)[1],
    cache: worker.match(/const CACHE_NAME = "([^"]+)"/)[1], files: await inventory(directory) };
}
const a = await stage('a'), b = await stage('b'), bad = await stage('bad');
report.artifacts = { a, b, bad };
let active = a, legacy = false, corrupt = false, interrupted = false, unsafeHeaders = false, browser, server;
const contexts = [];
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.wasm': 'application/wasm', '.txt': 'text/plain' };
function policy(text, path) {
  const result = {}; let applies = false;
  for (const line of text.split('\n')) {
    if (line.startsWith('/')) applies = new RegExp('^' + line.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replaceAll('*', '.*') + '$').test(path);
    else if (applies && /^\s+[^:]+:/.test(line)) { const split = line.indexOf(':'); result[line.slice(0, split).trim()] = line.slice(split + 1).trim(); }
  }
  return result;
}
try {
  server = createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://127.0.0.1');
      report.requests.push({ path: url.pathname, stage: active.name, legacy, cookie_present: Boolean(request.headers.cookie) });
      if (url.pathname === '/__private/account') { response.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); response.end(JSON.stringify({ cookie_present: Boolean(request.headers.cookie) })); return; }
      if (url.pathname === '/legacy-seed.html') { response.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' }); response.end('<script src="main.dart.js"></script>'); return; }
      if (legacy && url.pathname === '/main.dart.js') { response.writeHead(200, { 'Content-Type': 'text/javascript', 'Cache-Control': 'public, max-age=31536000, immutable' }); response.end("window.legacyBundle='old-immutable';"); return; }
      if (legacy && url.pathname === '/assets/lazy.txt') { response.writeHead(200, { 'Content-Type': 'text/plain', 'Cache-Control': 'public, max-age=31536000, immutable' }); response.end('old-immutable-asset'); return; }
      if (interrupted && url.pathname === '/manifest.json') { response.writeHead(503); response.end('Interrupted synthetic installation'); return; }
      let path = resolve(active.directory, '.' + decodeURIComponent(url.pathname));
      if (!path.startsWith(active.directory + sep) && path !== active.directory) { response.writeHead(404); response.end(); return; }
      if (url.pathname === '/') path = join(active.directory, 'index.html');
      try { if (!(await stat(path)).isFile()) throw Error('missing'); } catch { response.writeHead(404); response.end('Not found'); return; }
      let bytes = await readFile(path);
      if (corrupt && url.pathname.endsWith('/assets/lazy.txt')) bytes = Buffer.from('mixed-deployment-bytes');
      const headers = policy(await readFile(join(active.directory, '_headers'), 'utf8'), url.pathname);
      if (unsafeHeaders && url.pathname === '/main.dart.js') headers['Cache-Control'] = 'public, max-age=31536000, immutable';
      response.writeHead(200, { 'Content-Type': mime[extname(path)] || 'application/octet-stream', ...headers }); response.end(bytes);
    } catch (error) { response.writeHead(500); response.end('Fixture failure'); report.errors.push(error.stack); }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`; report.origin = origin;
  const liveGate = async (name, expectedStatus) => {
    const command = spawn('bash', [join(root, 'scripts/admin_pwa_live_gate.sh'), '--json'], { env: { ...process.env, ADMIN_PWA_LIVE_URL: origin, ADMIN_PWA_LIVE_FIXTURE: '1' } });
    const out = [], err = []; command.stdout.on('data', (bytes) => out.push(bytes)); command.stderr.on('data', (bytes) => err.push(bytes));
    const exit = await new Promise((resolve) => command.once('exit', resolve));
    const result = JSON.parse(Buffer.concat(out)); await writeFile(join(output, name + '.live-gate.json'), JSON.stringify(result, null, 2) + '\n');
    await writeFile(join(output, name + '.live-gate.stderr.log'), Buffer.concat(err));
    check(name, result.status === expectedStatus && exit === (expectedStatus === 'pass' ? 0 : 1), { exit, failures: result.failures });
    return result;
  };
  await liveGate('loopback-live-contract-positive', 'pass');
  corrupt = true; const mixedGate = await liveGate('loopback-live-contract-rejects-mixed-runtime-bytes', 'fail'); corrupt = false;
  check('loopback-byte-rejection-identifies-content-binding', mixedGate.failures.some((failure) => failure.includes('served runtime bytes differ')));
  unsafeHeaders = true; const headerGate = await liveGate('loopback-live-contract-rejects-immutable-stable-bundle', 'fail'); unsafeHeaders = false;
  check('loopback-header-rejection-identifies-mutable-bundle', headerGate.failures.some((failure) => failure.includes('mutable main.dart.js')));
  const loaded = await import(process.env.PLAYWRIGHT_CORE_PATH || '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js');
  const { chromium } = loaded.default || loaded;
  const executablePath = process.env.ADMIN_PWA_CHROME || '/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  browser = await chromium.launch({ executablePath, headless: true, args: ['--disable-background-networking', '--disable-component-update', '--disable-sync'] });
  report.browser = { version: browser.version(), executable: executablePath, executable_sha256: sha(await readFile(executablePath)) };
  const warm = await browser.newContext({ serviceWorkers: 'block' }); contexts.push(warm);
  const old = await warm.newPage(); legacy = true;
  await old.goto(origin + '/legacy-seed.html'); await old.waitForFunction(() => window.legacyBundle === 'old-immutable');
  await old.evaluate(() => fetch('/assets/lazy.txt').then((response) => response.text()));
  legacy = false; active = b;
  await old.goto(origin + '/'); await old.waitForFunction(() => window.fixtureReady);
  check('legacy-immutable-http-cache-cannot-supply-versioned-main', await old.evaluate(() => window.fixtureVersion) === 'b');
  check('legacy-immutable-http-cache-cannot-supply-versioned-assets', await old.evaluate(() => fetch(window.fixtureConfig.assetBase + 'assets/lazy.txt').then((response) => response.text())) === 'lazy-b');
  check('legacy-immutable-cache-still-exists-without-clearing-user-state', await old.evaluate(() => fetch('/assets/lazy.txt').then((response) => response.text())) === 'old-immutable-asset');
  await warm.close();
  const context = await browser.newContext({ serviceWorkers: 'allow' }); contexts.push(context); active = a;
  await context.addCookies([{ name: 'synthetic-operator', value: 'fixture-only', url: origin }]);
  const page = await context.newPage(); await page.goto(origin + '/'); await page.waitForFunction(() => window.fixtureReady);
  await page.evaluate(() => navigator.serviceWorker.ready);
  check('first-visit-worker-does-not-claim-loaded-network-page', await page.evaluate(() => navigator.serviceWorker.controller === null));
  await page.reload(); await page.waitForFunction(() => window.fixtureReady && navigator.serviceWorker.controller);
  const sibling = await context.newPage(); await sibling.goto(origin + '/'); await sibling.waitForFunction(() => window.fixtureReady);
  await page.locator('#pending').fill('unfinished-fixture-a'); await sibling.locator('#pending').fill('unfinished-fixture-b');
  active = b;
  const update = await observeWaitingAdminUpdate(page);
  check('new-worker-waits-for-open-tabs', update.state === 'installed' && update.sameController, update);
  check('pending-work-in-both-tabs-is-preserved', await page.locator('#pending').inputValue() === 'unfinished-fixture-a' && await sibling.locator('#pending').inputValue() === 'unfinished-fixture-b');
  check('open-tabs-retain-old-main-and-lazy-assets', await page.evaluate(() => window.fixtureVersion) === 'a' && await sibling.evaluate(() => fetch(window.fixtureConfig.assetBase + 'assets/lazy.txt').then((response) => response.text())) === 'lazy-a');
  const waiting = await page.evaluate(() => caches.keys());
  check('old-and-waiting-static-caches-coexist', waiting.includes(a.cache) && waiting.includes(b.cache), waiting);
  await page.reload(); await page.waitForFunction(() => window.fixtureReady);
  check('reload-while-another-old-tab-is-open-stays-on-old-build', await page.evaluate(() => window.fixtureVersion) === 'a');
  await page.evaluate(async () => { await caches.open('unrelated-fixture'); });
  await reopenAfterAllAdminTabsLeave(context, origin); await page.waitForFunction(() => window.fixtureReady);
  check('all-tabs-closed-then-reopened-use-new-main-and-assets', await page.evaluate(() => window.fixtureVersion) === 'b' && await page.evaluate(() => fetch(window.fixtureConfig.assetBase + 'assets/lazy.txt').then((response) => response.text())) === 'lazy-b');
  const after = await page.evaluate(() => caches.keys());
  check('safe-activation-retires-only-old-admin-cache', !after.includes(a.cache) && after.includes(b.cache) && after.includes('unrelated-fixture'), after);
  const failInstall = async (id) => {
    active = bad;
    const outcome = await page.evaluate(async () => {
      const registration = await navigator.serviceWorker.ready, old = navigator.serviceWorker.controller;
      const done = new Promise((resolve, reject) => { const timer = setTimeout(() => reject(Error('Install terminal state absent')), 30000);
        registration.addEventListener('updatefound', () => { const worker = registration.installing; worker.addEventListener('statechange', () => { if (['redundant', 'installed', 'activated'].includes(worker.state)) { clearTimeout(timer); resolve(worker.state); } }); }, { once: true }); });
      await registration.update(); return { state: await done, same: navigator.serviceWorker.controller === old };
    });
    check(id + '-does-not-replace-active-worker', outcome.state === 'redundant' && outcome.same, outcome);
    check(id + '-removes-partial-cache', !(await page.evaluate(() => caches.keys())).includes(bad.cache));
  };
  corrupt = true; await failInstall('mixed-byte-install'); corrupt = false;
  interrupted = true; await failInstall('interrupted-install'); interrupted = false; active = b;
  await context.setOffline(true); await page.reload(); await page.waitForFunction(() => window.fixtureReady);
  check('offline-reload-retains-complete-current-static-build', await page.evaluate(() => window.fixtureVersion) === 'b' && await page.evaluate(() => fetch(window.fixtureConfig.assetBase + 'assets/lazy.txt').then((response) => response.text())) === 'lazy-b');
  check('offline-private-response-is-unavailable', await page.evaluate(() => fetch('/__private/account').then(() => false, () => true)));
  await context.setOffline(false);
  const privateBefore = await page.evaluate(() => fetch('/__private/account').then((response) => response.json()));
  await context.clearCookies();
  const privateAfter = await page.evaluate(() => fetch('/__private/account').then((response) => response.json()));
  check('private-account-state-remains-fresh-and-uncached', privateBefore.cookie_present && !privateAfter.cookie_present && !await page.evaluate(() => caches.match('/__private/account').then(Boolean)));
  active = a;
  check('rollback-also-waits-for-open-new-version-tabs', (await observeWaitingAdminUpdate(page)).sameController && await page.evaluate(() => window.fixtureVersion) === 'b');
  await reopenAfterAllAdminTabsLeave(context, origin); await page.waitForFunction(() => window.fixtureReady);
  check('rollback-after-tabs-close-restores-matching-old-main-and-assets', await page.evaluate(() => window.fixtureVersion) === 'a' && await page.evaluate(() => fetch(window.fixtureConfig.assetBase + 'assets/lazy.txt').then((response) => response.text())) === 'lazy-a');
  const workerCache = await page.evaluate(async () => { const keys = await caches.keys(); const result = []; for (const key of keys) { const cache = await caches.open(key); result.push({ key, paths: (await cache.keys()).map((request) => new URL(request.url).pathname) }); } return result; });
  check('cache-contains-only-installed-static-inventory', workerCache.every((cache) => !cache.paths.some((path) => path.startsWith('/__private'))), workerCache);
  await context.close();
  if (process.env.ADMIN_PWA_COMPAT_BUILD) {
    const existing = resolve(process.env.ADMIN_PWA_COMPAT_BUILD); active = await stage('dated-flutter-compatibility', existing);
    report.artifacts.compatibility = active;
    const compatibility = await browser.newContext(); contexts.push(compatibility);
    const real = await compatibility.newPage(); const session = await compatibility.newCDPSession(real);
    await session.send('Network.enable'); await session.send('Network.setBlockedURLs', { urls: ['https://*'] });
    await real.goto(origin + '/#/admin/login');
    await real.waitForFunction(() => document.querySelector('flt-semantics-placeholder') || document.querySelectorAll('flt-semantics').length > 5, null, { timeout: 60000 });
    await real.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await real.waitForFunction(() => document.body.innerText.includes('Collect admin login'), null, { timeout: 30000 });
    check('dated-actual-flutter-loader-and-admin-login-render-from-versioned-assets', true);
    await real.screenshot({ path: join(output, 'dated-flutter-login-compatibility.png') });
    await compatibility.close();
  }
  const badPrecache = report.requests.filter((request) => request.path.startsWith('/_build/') && request.stage === 'bad');
  check('precache-never-sends-operator-cookies', badPrecache.length > 0 && badPrecache.every((request) => !request.cookie_present));
  report.status = 'pass';
} catch (error) { report.status = 'fail'; report.errors.push(error.stack); console.error(error.stack); }
finally {
  report.source_after = await snapshot(); report.source_stable = JSON.stringify(report.source_before) === JSON.stringify(report.source_after);
  if (!report.source_stable) report.status = 'fail'; report.completed_at = new Date().toISOString();
  for (const context of contexts) await context.close().catch(() => {});
  await browser?.close(); await new Promise((resolve) => server ? server.close(resolve) : resolve());
  await writeFile(join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
}
process.exitCode = report.status === 'pass' ? 0 : 1;
