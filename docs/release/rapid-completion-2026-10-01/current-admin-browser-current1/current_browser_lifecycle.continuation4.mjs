#!/usr/bin/env node
// Current production entrypoint and service worker; synthetic loopback transport.
import { createServer } from 'node:http';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { cp, mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createLocalBrowserFixture } from './local_browser_api_fixture.mjs';

const workspaceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
// Read immutable candidate inputs while keeping mutable builds outside checkout.
const root = resolve(process.env.COLLECT_BROWSER_SOURCE_ROOT || workspaceRoot);
const output = resolve(process.argv[2] || '');
const buildRoot = resolve(process.env.COLLECT_BROWSER_BUILD_ROOT || '');
const retainedReportPath = process.env.COLLECT_BROWSER_RESUME_REPORT;
const retainedReport = retainedReportPath ? JSON.parse(await readFile(retainedReportPath, 'utf8')) : null;
if (!process.argv[2] || !output.startsWith(join(root, '.cache') + sep) || existsSync(output)) {
  throw Error('A new task-owned cache output directory is required');
}
if (!process.env.COLLECT_BROWSER_BUILD_ROOT || buildRoot === workspaceRoot || !existsSync(buildRoot)) {
  throw Error('A preserved isolated source export is required for the Admin build');
}
await mkdir(output, { recursive: true });
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
async function files(directory) {
  const values = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) values.push(...await files(path));
    else if (entry.isFile()) values.push(path);
  }
  return values.sort();
}
async function hashes(directory) {
  return Object.fromEntries(await Promise.all((await files(directory)).map(async path =>
    [relative(directory, path), hash(await readFile(path))])));
}
const sourceFiles = ['pubspec.yaml', 'pubspec.lock', '.fvmrc', 'scripts/qa/current_browser_lifecycle.mjs',
  'scripts/qa/local_browser_api_fixture.mjs', 'scripts/admin_pwa_release_build.sh',
  'scripts/templates/admin_pwa_service_worker.js', 'scripts/public_static_site_build.rb',
  'scripts/public_app_media.rb', 'scripts/public_photography.rb', 'scripts/tests/local_browser_email_fixture_test.mjs'].map(name => join(root, name));
async function snapshot() {
  const sourcePaths = (await Promise.all(['lib', 'web', 'assets', 'third_party', 'content/legal'].map(name => files(join(root, name))))).flat();
  sourcePaths.push(...sourceFiles);
  // Upstream package QA fixtures are not compiled by the normal Admin or
  // Public entrypoints. Preserve runtime/native/assets/licence metadata;
  // exclude only these explicitly named package QA/documentation roots.
  const executed = sourcePaths.filter(path => !/^third_party\/[^/]+\/(?:test|tests|example|examples|benchmark|benchmarks|doc|docs)\//.test(relative(root, path)));
  return Object.fromEntries(await Promise.all(executed.sort().map(async path =>
    [relative(root, path), hash(await readFile(path))])));
}
const report = { status: 'running', started_at_utc: new Date().toISOString(),
  scope: 'Normal current Admin email sign-in and tab-local memory sessions, actual service-worker lifecycle and separate Public artifact. Synthetic loopback transport; current database semantics, physical devices and design fidelity remain separate.',
  source_scope: 'Current lib/web/assets/legal and complete local fork runtime/metadata; explicit upstream package QA/documentation roots excluded because neither entrypoint compiles them. Exact executing build/fixture/regression scripts retained.',
  sources_before: await snapshot(), source_root: root, build_root: buildRoot,
  executing_harness_sha256: hash(await readFile(fileURLToPath(import.meta.url))),
  executing_fixture_sha256: hash(await readFile(join(workspaceRoot, 'scripts/qa/local_browser_api_fixture.mjs'))),
  commands: [], checks: [], route_states: [], errors: [], blocked_outbound_requests: [],
  database_calls: 0, hosted_calls: 0, provider_calls: 0,
  coverage: { email_sign_in: false, reference_only_storage: false, reload_requires_sign_in: false,
    tabs_do_not_adopt_sign_in: false, legacy_broadcast_refused: false, mismatched_departure_refused: false,
    exact_departure_denies: false, private_logout: false, account_switch: false,
    public_admin_separation: false, static_cache_privacy: false, warm_update: false,
    failed_update: false, legacy_cache_migration: false, offline_signed_out: false,
    installed_pwa: false, signed_out_all_routes: false, authenticated_all_routes: false },
};
const fixture = createLocalBrowserFixture();
let server, publicServer, context, browser, active, failedAsset = false, pwaSession, installedId;
function check(id, condition, observed = null) {
  report.checks.push({ id, status: condition ? 'pass' : 'fail', observed });
  console.log(JSON.stringify({ id, status: condition ? 'pass' : 'fail' }));
  if (!condition) throw Error(id);
}
async function run(name, command, args, environment = {}, cwd = root) {
  const stdout = [], stderr = [];
  const child = spawn(command, args, { cwd, env: { ...process.env, ...environment }, stdio: ['ignore', 'pipe', 'pipe'] });
  child.stdout.on('data', bytes => stdout.push(bytes)); child.stderr.on('data', bytes => stderr.push(bytes));
  const code = await new Promise((yes, no) => { child.once('error', no); child.once('exit', yes); });
  const out = Buffer.concat(stdout), err = Buffer.concat(stderr);
  await writeFile(join(output, name + '.stdout'), out); await writeFile(join(output, name + '.stderr'), err);
  report.commands.push({ name, command, args, cwd, exit_code: code, stdout_sha256: hash(out), stderr_sha256: hash(err) });
  if (code !== 0) throw Error(name + ' exit ' + code);
}
const mimes = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.webp': 'image/webp', '.ttf': 'font/ttf' };
function headers(text, path) {
  const result = {}; let pattern;
  for (const line of text.split('\n')) {
    if (!line.trim() || line.trim().startsWith('#')) continue;
    if (!line.startsWith(' ')) pattern = line.trim();
    else {
      const index = line.indexOf(':'); if (index < 0 || !pattern) continue;
      const regex = new RegExp('^' + pattern.split('*').map(part => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*') + '$');
      if (regex.test(path)) result[line.slice(0, index).trim()] = line.slice(index + 1).trim();
    }
  }
  return result;
}
async function serve(request, response, directory, fallback) {
  const pathname = new URL(request.url, 'http://127.0.0.1').pathname;
  let path = resolve(directory, '.' + decodeURIComponent(pathname));
  if (path !== directory && !path.startsWith(directory + sep)) { response.writeHead(404); response.end(); return; }
  const policy = headers(await readFile(join(directory, '_headers'), 'utf8'), pathname);
  try { if (!(await stat(path)).isFile()) path = join(path, 'index.html'); await stat(path); }
  catch {
    if (!fallback) { response.writeHead(404, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store', ...policy }); response.end('Not found'); return; }
    path = join(directory, 'index.html');
  }
  response.writeHead(200, { 'Content-Type': mimes[extname(path)] || 'application/octet-stream', 'Cache-Control': 'no-store', ...policy });
  response.end(await readFile(path));
}
async function semantics(page) {
  await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder') || document.querySelectorAll('flt-semantics').length > 5, null, { timeout: 90000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
}
async function visible(page, text) {
  await page.waitForFunction(value => [...document.querySelectorAll('flt-semantics')]
    .some(element => ((element.getAttribute('aria-label') || '') + ' ' + (element.textContent || '')).includes(value)), text, { timeout: 30000 });
}
async function enter(page, label, value) {
  const field = page.getByRole('textbox', { name: label, exact: true });
  // Flutter creates a focused native editor after the semantics tap. Its
  // overlay has a different accessibility node; bind focus to this geometry.
  const bounds = await field.boundingBox();
  if (!bounds) throw Error('Synthetic browser editor has no bounds: ' + label);
  await field.click();
  await page.waitForFunction(({ bounds, multiline }) => {
    const active = document.activeElement;
    if (!active || !['INPUT', 'TEXTAREA'].includes(active.tagName)
      || (multiline && active.tagName !== 'TEXTAREA')) return false;
    const rect = active.getBoundingClientRect();
    const x = rect.x + rect.width / 2, y = rect.y + rect.height / 2;
    return x >= bounds.x && x <= bounds.x + bounds.width
      && y >= bounds.y && y <= bounds.y + bounds.height;
  }, { bounds, multiline: value.includes('\n') });
  await page.keyboard.press('Meta+A');
  await page.keyboard.insertText(value);
  await page.waitForFunction(value => document.activeElement?.value === value, value);

}
async function activate(page, role, name) {
  const parent = page.getByRole(role, { name, exact: typeof name === 'string' });
  const nested = parent.locator('[flt-tappable]').first(); const action = await nested.count() ? nested : parent;
  await action.focus(); await action.press('Enter');
}
async function login(page, which = 'a') {
  await semantics(page); await enter(page, 'Operator email', `operator-${which}@example.invalid`);
  await activate(page, 'button', 'Send admin email code');
  await visible(page, 'Email code requested. Check your approved operator inbox.');
  await page.waitForFunction(() => [...document.querySelectorAll('[role="button"]')]
    .some(element => element.getAttribute('aria-label') === 'Verify admin email code'
      && element.getAttribute('aria-disabled') !== 'true'));
  await enter(page, '6-digit code', '123456');
  await activate(page, 'button', 'Verify admin email code'); await visible(page, 'Local Operator ' + which.toUpperCase());
}
async function storage(page) {
  return page.evaluate(async () => ({ local: { ...localStorage }, session: { ...sessionStorage },
    indexed: (await indexedDB.databases()).map(value => value.name), cookie: document.cookie }));
}
function noCredentials(value) {
  const bytes = JSON.stringify(value);
  return !bytes.includes('access_token') && !bytes.includes('refresh_token') && !bytes.includes('synthetic-refresh-')
    && !bytes.includes('Alice Current') && !bytes.includes('Private Current');
}
async function publish(page, message) {
  await page.evaluate(value => { const channel = new BroadcastChannel('sb-127-auth-token'); channel.postMessage(value); channel.close(); }, message);
}
async function cachePrivacy(page) {
  return page.evaluate(async () => {
    for (const name of await caches.keys()) {
      const cache = await caches.open(name);
      for (const request of await cache.keys()) {
        if (['/rest/', '/auth/', '/functions/'].some(prefix => new URL(request.url).pathname.startsWith(prefix))) return false;
        const bytes = await (await cache.match(request)).text();
        if (['Alice Current', 'Private Current', 'synthetic-refresh-'].some(value => bytes.includes(value))) return false;
      }
    }
    return true;
  });
}
try {
  server = createServer(async (request, response) => {
    try {
      const path = new URL(request.url, 'http://127.0.0.1').pathname;
      let bytes = ''; for await (const chunk of request) bytes += chunk;
      if (await fixture.handle(request, response, path, bytes ? JSON.parse(bytes) : {})) return;
      if (failedAsset && path === '/manifest.json') { response.writeHead(503); response.end('Synthetic failed update'); return; }
      if (!active) { response.writeHead(503); response.end(); return; }
      await serve(request, response, active, true);
    } catch (error) { report.errors.push('Loopback server: ' + error.message); response.writeHead(500); response.end('Local fixture error'); }
  });
  const retainedPort = retainedReport ? Number(new URL(retainedReport.admin_origin).port) : 0;
  await new Promise((yes, no) => { server.once('error', no); server.listen(retainedPort, '127.0.0.1', yes); });
  const origin = `http://127.0.0.1:${server.address().port}`; report.admin_origin = origin;
  const flutter = process.env.COLLECT_BROWSER_FLUTTER || '/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter';
  if (retainedReport) {
    const compiledInput = name => /^(?:lib|web|assets|third_party)\//.test(name)
      || ['pubspec.yaml', 'pubspec.lock', '.fvmrc', 'scripts/admin_pwa_release_build.sh',
        'scripts/templates/admin_pwa_service_worker.js'].includes(name);
    const now = await snapshot();
    check('retained-build-compiler-inputs-unchanged', Object.entries(retainedReport.sources_before)
      .filter(([name]) => compiledInput(name)).every(([name, digest]) => now[name] === digest)
      && retainedReport.source_inputs_stable === true && retainedReport.admin_origin === origin);
    const priorOutput = dirname(resolve(retainedReportPath));
    for (const name of ['flutter-runtime', 'email-fixture-boundaries', 'worker-cache-regression', 'bundle-gate-regression', 'admin-build']) {
      const command = retainedReport.commands.find(value => value.name === name && value.exit_code === 0);
      if (!command || hash(await readFile(join(priorOutput, name + '.stdout'))) !== command.stdout_sha256
        || hash(await readFile(join(priorOutput, name + '.stderr'))) !== command.stderr_sha256) {
        throw Error('Retained zero-exit command receipt missing: ' + name);
      }
      report.commands.push({ ...command, reused_from: retainedReportPath });
    }
    report.retained_admin_bundle = { path: join(priorOutput, 'admin-build'),
      files: await hashes(join(priorOutput, 'admin-build')), compiled_inputs: Object.fromEntries(
        Object.entries(retainedReport.sources_before).filter(([name]) => compiledInput(name))) };
    active = join(output, 'admin-build'); await cp(join(priorOutput, 'admin-build'), active, { recursive: true });
    check('retained-admin-bundle-byte-identical', JSON.stringify(await hashes(active)) === JSON.stringify(report.retained_admin_bundle.files));
  } else {
  await run('flutter-runtime', flutter, ['--version', '--machine']);
  const version = JSON.parse(await readFile(join(output, 'flutter-runtime.stdout'), 'utf8'));
  check('pinned-flutter-runtime', version.frameworkVersion === JSON.parse(await readFile(join(root, '.fvmrc'), 'utf8')).flutter, version.frameworkVersion);
  await run('email-fixture-boundaries', process.execPath, ['scripts/tests/local_browser_email_fixture_test.mjs']);
  await run('worker-cache-regression', process.execPath, ['scripts/tests/admin_pwa_worker_cache_test.mjs']);
  await run('bundle-gate-regression', 'ruby', ['scripts/tests/admin_pwa_bundle_gate_test.rb']);
  await run('admin-build', '/bin/bash', [join(buildRoot, 'scripts/admin_pwa_release_build.sh')], {
    FLUTTER: flutter, COLLECT_SKIP_DOTENV: '1', SUPABASE_PRODUCTION_URL: origin,
    SUPABASE_PRODUCTION_ANON_KEY: 'sb_publishable_synthetic_local_only', APP_PUBLIC_URL: 'http://127.0.0.1', ADMIN_APP_URL: origin,
  }, buildRoot);
  active = join(output, 'admin-build'); await cp(join(buildRoot, 'build/web'), active, { recursive: true });
  }
  await run('public-build', 'ruby', ['scripts/public_static_site_build.rb'], { PUBLIC_BUILD_DIR: join(output, 'public-build') });
  const publicBuild = join(output, 'public-build');
  publicServer = createServer((request, response) => serve(request, response, publicBuild, false).catch(error => {
    report.errors.push('Public server: ' + error.message); response.writeHead(500); response.end();
  }));
  await new Promise(yes => publicServer.listen(0, '127.0.0.1', yes));
  const publicOrigin = `http://127.0.0.1:${publicServer.address().port}`; report.public_origin = publicOrigin;
  report.artifacts = { admin: await hashes(active), public: await hashes(publicBuild) };
  const loaded = await import(process.env.PLAYWRIGHT_CORE_PATH || '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js');
  const { chromium } = loaded.default || loaded;
  const executable = process.env.ADMIN_PWA_CHROME || '/Users/jeanbosco/.cache/selenium/chrome/mac-arm64/151.0.7922.34/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
  report.browser_executable = { path: executable, sha256: hash(await readFile(executable)) };
  context = await chromium.launchPersistentContext(join(output, 'isolated-browser-profile'), { executablePath: executable,
    headless: false, viewport: { width: 1440, height: 1000 }, serviceWorkers: 'allow',
    args: ['--disable-background-networking', '--disable-component-update', '--disable-sync'] });
  browser = context.browser(); report.browser_version = browser.version();
  const observe = page => page.on('pageerror', error => report.errors.push(error.stack || error.message));
  context.pages().forEach(observe); context.on('page', observe);
  await context.route('**/*', route => {
    const url = new URL(route.request().url());
    if ([origin, publicOrigin].includes(url.origin)) return route.continue();
    report.blocked_outbound_requests.push({ origin: url.origin, path: url.pathname }); return route.abort();
  });
  const page = await context.newPage(); const navigation = await page.goto(origin + '/#/admin/groups');
  check('shipped-security-headers', !!navigation.headers()['content-security-policy'] && navigation.headers()['x-frame-options'] === 'DENY');
  await semantics(page);
  const routerSource = await readFile(join(root, 'lib/admin/admin_router.dart'), 'utf8');
  const declaredBlock = routerSource.match(/const adminRoutePaths = <String>\[([\s\S]*?)\];/);
  if (!declaredBlock) throw Error('Current Admin route declaration missing');
  const declaredRoutes = [...declaredBlock[1].matchAll(/'([^']+)'/g)].map(value => value[1]);
  const recordId = '99690000-0000-4000-8000-000000090001';
  const readFailure = 'The admin request could not be completed.';
  // Exact enabled route/state contract. Empty lists and deliberately unavailable
  // synthetic reads prove recovery UI, not real server/populated/action outcomes.
  const routeStates = {
    '/admin/login': ['Collect admin login', 'login'],
    '/admin/denied': ['Admin access required', 'denied'],
    '/admin': ['Payments and receipts · Unavailable', 'unavailable-metrics'],
    '/admin/groups': ['No groups', 'empty'],
    '/admin/groups/:id': [readFailure, 'unavailable-read'],
    '/admin/users': ['No users', 'empty'],
    '/admin/users/:id': [readFailure, 'unavailable-read'],
    '/admin/members': ['No members', 'empty'],
    '/admin/members/:id': [readFailure, 'unavailable-read'],
    '/admin/payees': ['No payees', 'empty'],
    '/admin/transactions': ['No transactions', 'empty'],
    '/admin/transactions/:id': [readFailure, 'unavailable-read'],
    '/admin/reconciliations': ['No payments awaiting review', 'empty-payment-queue'],
    '/admin/ledgers': ['No ledgers', 'empty'],
    '/admin/sms-receipts': ['No sms receipts', 'empty'],
    '/admin/sms-receipts/:id': [readFailure, 'unavailable-read'],
    '/admin/notifications': ['No notifications', 'empty'],
    '/admin/notifications/:id': [readFailure, 'unavailable-read'],
    '/admin/audit-logs': ['No audit logs', 'empty'],
    '/admin/audit-logs/entity/:kind/:id': ['Action history service unavailable', 'unavailable-read'],
    '/admin/settings': ['No settings', 'empty'],
    '/admin/feature-flags': ['No feature flags', 'empty'],
    '/admin/system-health': [readFailure, 'unavailable-read'],
    '/admin/automations': ['Receipt operations policy service is unavailable.', 'unavailable-policy'],
    '/admin/sms-gateway': ['Gateway read failed', 'invalid-synthetic-read-refused'],
    '/admin/exceptions': ['Exception read failed', 'invalid-synthetic-read-refused'],
    '/admin/admin-users': ['No admin users', 'empty'],
    '/admin/admin-users/:id': [readFailure, 'unavailable-read'],
  };
  check('current-route-contract-covers-declared28', declaredRoutes.length === 28
    && JSON.stringify([...declaredRoutes].sort()) === JSON.stringify(Object.keys(routeStates).sort()));
  function concreteRoute(pattern) {
    const id = pattern === '/admin/transactions/:id' ? encodeURIComponent('momo:' + recordId) : recordId;
    return pattern.replace(':kind', 'gateway_device').replace(':id', id);
  }
  async function navigateHash(path) {
    await page.evaluate(value => { location.hash = value; }, path);
  }
  const beforeSignedOutRoutes = fixture.calls.length;
  for (const pattern of declaredRoutes) {
    await navigateHash(concreteRoute(pattern));
    await page.waitForFunction(() => location.hash === '#/admin/login');
    await visible(page, 'Collect admin login');
    check('signed-out-route:' + pattern, noCredentials(await storage(page)));
    report.route_states.push({ pattern, authority: 'signed-out', actual_path: new URL(page.url()).hash,
      state: 'login', status: 'pass' });
  }
  check('signed-out-routes-dispatch-no-private-rpc', !fixture.calls.slice(beforeSignedOutRoutes)
    .some(value => !['otp', 'verify', 'user', 'logout'].includes(value.action)));
  report.coverage.signed_out_all_routes = true;
  await navigateHash('/admin/groups');
  await login(page);
  for (const pattern of declaredRoutes) {
    const path = concreteRoute(pattern), [expected, state] = routeStates[pattern];
    const beforeCalls = fixture.calls.length;
    await navigateHash(path);
    await page.waitForFunction(value => decodeURIComponent(location.hash.slice(1)) === decodeURIComponent(value), path);
    await visible(page, expected);
    check('authenticated-route:' + pattern, noCredentials(await storage(page)), { state, expected });
    report.route_states.push({ pattern, authority: 'authenticated-email-owner', actual_path: new URL(page.url()).hash,
      state, expected, calls: fixture.calls.slice(beforeCalls).map(value => value.action), status: 'pass' });
    if (['/admin/sms-gateway', '/admin/exceptions', '/admin/automations', '/admin/audit-logs/entity/:kind/:id'].includes(pattern)) {
      await page.screenshot({ path: join(output, 'route-' + pattern.replace(/[^a-z0-9]/gi, '_') + '.png'), fullPage: true });
    }
  }
  report.coverage.authenticated_all_routes = true;
  await navigateHash('/admin/groups');
  await visible(page, 'No groups');
  check('email-sign-in-keeps-admin-route', new URL(page.url()).hash.startsWith('#/admin'));
  report.coverage.email_sign_in = true;
  check('confirmed-email-sign-in-stores-no-browser-credentials', noCredentials(await storage(page)));
  await activate(page, 'button', 'Groups admin section'); await visible(page, 'Create group');
  check('authenticated-groups-navigation', new URL(page.url()).hash.startsWith('#/admin/groups'));
  await activate(page, 'button', 'Create group'); await activate(page, 'menuitem', /^Create assisted group(?:\s|$)/);
  await enter(page, 'Group name', 'Private Current Group'); await enter(page, 'Reason', 'Private Current Review Reason');
  await enter(page, 'Member roster', 'member_name,momo_name,momo_number\nAlice Current,ALICE CURRENT,0788969111');
  await page.getByText('Prepare preview', { exact: true }).click(); await page.getByText('Save recovery draft', { exact: true }).click();
  await visible(page, 'Recovery draft saved for this sign-in.');
  const stored = await storage(page), bookmark = JSON.parse(stored.session['collect.admin.roster.recovery.v1']);
  check('reference-only-roster-storage', noCredentials(stored) && bookmark.version === 1
    && Object.keys(bookmark).every(key => ['version', 'owner_digest', 'upload_request_id', 'source_sha256', 'collection_id', 'import_id', 'checkpoint_id', 'pending_request_id', 'pending_sha256'].includes(key)));
  report.coverage.reference_only_storage = true;
  const beforeReload = fixture.calls.length; await page.reload(); await semantics(page); await visible(page, 'Collect admin login');
  check('reload-never-restores-auth-or-private-editor', noCredentials(await storage(page))
    && !fixture.calls.slice(beforeReload).some(value => ['admin_execute_roster_import_intent', 'prepare-roster-import'].includes(value.action)));
  report.coverage.reload_requires_sign_in = true; await login(page);
  const popup = context.waitForEvent('page'); await page.evaluate(url => window.open(url, '_blank'), origin + '/#/admin/groups');
  const peer = await popup; await semantics(peer); await visible(peer, 'Collect admin login');
  check('new-tab-does-not-adopt-sign-in', noCredentials(await storage(peer))); report.coverage.tabs_do_not_adopt_sign_in = true;
  const leaked = fixture.issueSession(0); await publish(peer, { event: 'SIGNED_IN', session: leaked });
  await peer.waitForTimeout(300); await visible(peer, 'Collect admin login'); await visible(page, 'Local Operator A');
  check('legacy-token-broadcast-cannot-authenticate-peer', noCredentials(await storage(peer))); report.coverage.legacy_broadcast_refused = true;
  await login(peer, 'b'); await visible(page, 'Local Operator A'); await visible(peer, 'Local Operator B');
  const claims = JSON.parse(Buffer.from(leaked.access_token.split('.')[1], 'base64url').toString());
  const issued = Math.floor(Date.now() / 1000);
  await publish(peer, { protocol: 'collect.auth.departed-session', version: 1, event: 'SIGNED_OUT',
    project: origin + '/auth/v1', actor: claims.sub, session: claims.session_id, issued, expires: issued + 30 });
  await page.waitForTimeout(300); await visible(page, 'Local Operator A'); await visible(peer, 'Local Operator B');
  check('departure-for-another-session-does-not-clear-live-tabs', noCredentials(await storage(page)) && noCredentials(await storage(peer)));
  report.coverage.mismatched_departure_refused = true;
  await activate(page, 'button', /^Operator menu(?:\s|$)/); await activate(page, 'menuitem', 'Sign out'); await visible(page, 'Collect admin login');
  await visible(peer, 'Local Operator B'); check('logout-clears-departed-private-ui-without-adopting-peer', noCredentials(await storage(page)));
  report.coverage.private_logout = true;
  await login(page, 'b'); await visible(page, 'Local Operator B');
  await activate(page, 'button', /^Operator menu(?:\s|$)/); await activate(page, 'menuitem', 'Sign out'); await visible(page, 'Collect admin login');
  await login(page, 'a'); check('explicit-a-b-a-sign-in-stays-private', noCredentials(await storage(page))); report.coverage.account_switch = true;
  // The exact owner is obtained only inside Node memory. Neither tokens nor user
  // objects are persisted in this report or sent through the denial protocol.
  const liveOwner = fixture.lastIssuedOwner();
  const verificationCalls = fixture.calls.filter(value => value.action === 'verify').length;
  const issuedForDenial = fixture.issueSession(0);
  await publish(peer, { event: 'SIGNED_IN', session: issuedForDenial });
  await page.waitForTimeout(250); await visible(page, 'Local Operator A');
  check('legacy-broadcast-cannot-replace-existing-session', fixture.calls.filter(value => value.action === 'verify').length === verificationCalls);
  const denialIssued = Math.floor(Date.now() / 1000);
  await publish(peer, { protocol: 'collect.auth.departed-session', version: 1, event: 'SIGNED_OUT',
    project: origin + '/auth/v1', ...liveOwner, issued: denialIssued, expires: denialIssued + 30 });
  await visible(page, 'Collect admin login');
  check('actual-exact-owner-departure-denies-runtime', noCredentials(await storage(page))); report.coverage.exact_departure_denies = true;
  const publicPage = await context.newPage(); await publicPage.goto(publicOrigin + '/'); await publicPage.locator('h1').waitFor();
  check('separate-public-artifact-omits-admin-bundle', !Object.keys(report.artifacts.public).some(path => ['main.dart.js', 'custom-sw.js'].includes(path)));
  check('public-storage-isolated', noCredentials(await storage(publicPage)) && await publicPage.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0));
  check('public-private-paths-return-404', (await publicPage.request.get(publicOrigin + '/admin/login')).status() === 404
    && (await publicPage.request.get(publicOrigin + '/main.dart.js')).status() === 404);
  report.coverage.public_admin_separation = true;
  await page.waitForFunction(() => navigator.serviceWorker.controller, null, { timeout: 90000 });
  check('static-cache-excludes-private-responses', await cachePrivacy(page)); report.coverage.static_cache_privacy = true;
  const builder = await readFile(join(root, 'scripts/admin_pwa_release_build.sh'), 'utf8');
  const marker = "ruby -r digest -r json -r open3 <<'RUBY'\n";
  if (builder.split(marker).length !== 2) throw Error('Ambiguous production postprocessor');
  await writeFile(join(output, 'postprocessor.rb'), builder.split(marker)[1].split('\nRUBY\n')[0]);
  async function stage(name) {
    const directory = join(output, name); await cp(join(output, 'admin-build'), join(directory, 'build/web'), { recursive: true });
    for (const name of ['lib/app/theme/collect_colors.dart', 'scripts/templates/admin_pwa_service_worker.js']) {
      await mkdir(dirname(join(directory, name)), { recursive: true }); await cp(join(root, name), join(directory, name));
    }
    const index = join(directory, 'build/web/index.html');
    await writeFile(index, (await readFile(index, 'utf8')).replace('</head>', `<meta name="qa-shell-version" content="${name}"></head>`));
    const bootstrap = join(directory, 'build/web/flutter_bootstrap.js');
    const bootstrapText = await readFile(bootstrap, 'utf8');
    const versionConstant = /var adminServiceWorkerVersion = 'collect-admin-[0-9a-f]{16}';/g;
    if ([...bootstrapText.matchAll(versionConstant)].length !== 1) throw Error('Ambiguous compiled worker version constant');
    await writeFile(bootstrap, bootstrapText.replace(versionConstant, "var adminServiceWorkerVersion = '__COLLECT_ADMIN_SW_VERSION__';"));
    await run(name + '-postprocess', 'ruby', ['-r', 'digest', '-r', 'json', '-r', 'open3', join(output, 'postprocessor.rb')], {}, directory);
    report.update_artifacts ||= {}; report.update_artifacts[name] = await hashes(join(directory, 'build/web'));
    return join(directory, 'build/web');
  }
  await page.evaluate(async () => { for (const name of ['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest', 'unrelated-static-fixture']) {
    const cache = await caches.open(name); await cache.put('/synthetic-old-shell', new Response('Synthetic old shell')); } });
  const oldKeys = await page.evaluate(() => caches.keys()); active = await stage('version-b');
  await page.evaluate(async () => {
    const registration = await navigator.serviceWorker.getRegistration(), old = navigator.serviceWorker.controller;
    const changed = new Promise((yes, no) => { const timer = setTimeout(() => no(Error('Worker did not claim page')), 90000);
      navigator.serviceWorker.addEventListener('controllerchange', () => { if (navigator.serviceWorker.controller !== old) { clearTimeout(timer); yes(); } }, { once: true }); });
    await registration.update(); await changed;
  });
  await page.reload(); await semantics(page); await visible(page, 'Collect admin login');
  check('warm-update-keeps-signed-out-shell', await page.locator('meta[name=qa-shell-version]').getAttribute('content') === 'version-b');
  const newKeys = await page.evaluate(() => caches.keys());
  check('update-removes-legacy-and-previous-admin-caches', !newKeys.some(name => ['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest'].includes(name))
    && !newKeys.some(name => name.startsWith('collect-admin-') && oldKeys.includes(name)) && newKeys.includes('unrelated-static-fixture'), { oldKeys, newKeys });
  report.coverage.warm_update = true; report.coverage.legacy_cache_migration = true;
  active = await stage('version-failed'); failedAsset = true;
  const failure = await page.evaluate(async () => {
    const registration = await navigator.serviceWorker.ready, controller = navigator.serviceWorker.controller;
    const result = new Promise((yes, no) => { const timer = setTimeout(() => no(Error('Failed update never terminated')), 90000);
      registration.addEventListener('updatefound', () => { const worker = registration.installing;
        worker.addEventListener('statechange', () => { if (['redundant', 'activated'].includes(worker.state)) { clearTimeout(timer); yes(worker.state); } }); }, { once: true }); });
    await registration.update(); return { state: await result, same: controller === navigator.serviceWorker.controller };
  });
  check('failed-update-retains-active-worker', failure.state === 'redundant' && failure.same);
  check('failed-update-retains-only-previous-cache', JSON.stringify((await page.evaluate(() => caches.keys())).sort()) === JSON.stringify(newKeys.sort()));
  report.coverage.failed_update = true; failedAsset = false; active = join(output, 'version-b/build/web');
  await context.setOffline(true); await page.reload(); await semantics(page); await visible(page, 'Collect admin login');
  check('offline-reload-remains-signed-out', noCredentials(await storage(page)) && await page.locator('meta[name=qa-shell-version]').getAttribute('content') === 'version-b');
  check('offline-api-fails-without-cached-private-response', await page.evaluate(() => fetch('/rest/v1/rpc/admin_current_user', { method: 'POST' }).then(() => false, () => true)));
  await context.setOffline(false); report.coverage.offline_signed_out = true;
  pwaSession = await browser.newBrowserCDPSession(); installedId = origin + '/';
  await pwaSession.send('PWA.install', { manifestId: installedId, installUrlOrBundleUrl: installedId });
  await pwaSession.send('PWA.changeAppUserSettings', { manifestId: installedId, displayMode: 'standalone' });
  const launched = await pwaSession.send('PWA.launch', { manifestId: installedId, url: origin + '/#/admin/login' });
  const window = await pwaSession.send('Browser.getWindowForTarget', { targetId: launched.targetId });
  let installed; const deadline = Date.now() + 30000;
  while (!installed && Date.now() < deadline) {
    for (const candidate of context.pages()) {
      if (candidate.isClosed()) continue; const session = await context.newCDPSession(candidate);
      try { const { targetInfo } = await session.send('Target.getTargetInfo');
        const current = await pwaSession.send('Browser.getWindowForTarget', { targetId: targetInfo.targetId });
        if (current.windowId === window.windowId && await candidate.evaluate(() => matchMedia('(display-mode: standalone)').matches)) installed = candidate;
      } finally { await session.detach(); }
    }
    if (!installed) await new Promise(yes => setTimeout(yes, 100));
  }
  if (!installed) throw Error('Actual installed window was not observed');
  await semantics(installed); await visible(installed, 'Collect admin login');
  await context.setOffline(true); await installed.reload(); await semantics(installed); await visible(installed, 'Collect admin login');
  check('installed-pwa-offline-launch-has-no-auth', noCredentials(await storage(installed)) && await installed.evaluate(() => matchMedia('(display-mode: standalone)').matches && !!navigator.serviceWorker.controller));
  await context.setOffline(false); report.coverage.installed_pwa = true;
  await installed.screenshot({ path: join(output, 'installed-signed-out.png'), fullPage: true });
  await page.screenshot({ path: join(output, 'signed-out-admin.png'), fullPage: true });
  await publicPage.screenshot({ path: join(output, 'public-isolation.png'), fullPage: true });
  check('final-static-cache-private-data-exclusion', await cachePrivacy(page));
  report.status = Object.values(report.coverage).every(Boolean) && report.errors.length === 0 ? 'pass' : 'fail';
} catch (error) {
  report.status = 'fail'; report.errors.push(error.stack || String(error)); console.error(error.message);
  if (context) for (const [index, page] of context.pages().entries()) {
    await writeFile(join(output, `failure-${index}.html`), await page.content().catch(() => ''));
    await page.screenshot({ path: join(output, `failure-${index}.png`), fullPage: true }).catch(() => {});
  }
} finally {
  report.sources_after = await snapshot(); report.source_inputs_stable = JSON.stringify(report.sources_before) === JSON.stringify(report.sources_after);
  if (!report.source_inputs_stable) report.status = 'fail';
  report.fixture_calls = fixture.calls; report.completed_at_utc = new Date().toISOString();
  await writeFile(join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  if (pwaSession && installedId) await pwaSession.send('PWA.uninstall', { manifestId: installedId }).catch(() => {});
  await context?.close().catch(() => {}); await browser?.close().catch(() => {});
  await new Promise(yes => server ? server.close(yes) : yes()); await new Promise(yes => publicServer ? publicServer.close(yes) : yes());
}
process.exitCode = report.status === 'pass' ? 0 : 1;
