#!/usr/bin/env node
// Real service-worker lifecycle over a hash-verified, synthetic Admin build.
// No production target, user profile, Auth account or provider is used.
import { createHash } from 'node:crypto';
import { observeWaitingAdminUpdate, reopenAfterAllAdminTabsLeave } from './admin_pwa_update_policy.mjs';
import { createServer } from 'node:http';
import { spawnSync } from 'node:child_process';
import { lstat, mkdir, readFile, writeFile, copyFile, stat } from 'node:fs/promises';
import { createReadStream, existsSync } from 'node:fs';
import { dirname, extname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {observeCollectDiagnostics} from './collect_diagnostic_observer.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const [buildReportArgument, evidenceArgument] = process.argv.slice(2);
const installed = process.argv.slice(4).includes('--installed');
if (process.argv.slice(4).some((arg) => arg !== '--installed')) throw Error('Unknown lifecycle option');
if (!buildReportArgument || !evidenceArgument) {
  throw Error('Usage: admin_pwa_lifecycle_qa.mjs SYNTHETIC_BUILD_REPORT.json NEW_CACHE_EVIDENCE_DIR');
}
const buildReportPath = resolve(buildReportArgument);
const evidence = resolve(evidenceArgument);
for (const path of [buildReportPath, evidence]) {
  if (!path.startsWith(join(root, '.cache') + sep)) throw Error('Task-owned cached paths required');
}
if (existsSync(evidence)) throw Error('Evidence directory must be new');
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
const hashFile = async (path) => sha(await readFile(path));
// Root supplies reviewed bundled runtime paths and digests; there are no host defaults.
async function pinnedFile(path, expected, label) {
  if (!path || !isAbsolute(path) || !/^[a-f0-9]{64}$/.test(expected || '')) {
    throw Error(`Set ${label} to an absolute regular file and its reviewed SHA-256 pin`);
  }
  const before = await lstat(path);
  if (!before.isFile() || before.isSymbolicLink()) throw Error(`${label} must identify a regular file`);
  const hash = createHash('sha256');
  for await (const bytes of createReadStream(path)) hash.update(bytes);
  const actual = hash.digest('hex'), after = await lstat(path);
  if (actual !== expected || before.ino !== after.ino || before.size !== after.size ||
      before.mtimeMs !== after.mtimeMs || before.ctimeMs !== after.ctimeMs) {
    throw Error(`${label} changed or does not match its reviewed SHA-256 pin`);
  }
  return { path, sha256: actual, bytes: after.size };
}
async function runtimePins() {
  if (!process.env.ADMIN_PWA_NODE_VERSION || process.version !== process.env.ADMIN_PWA_NODE_VERSION) {
    throw Error('Set ADMIN_PWA_NODE_VERSION to the reviewed running Node version');
  }
  return {
    node: await pinnedFile(process.execPath, process.env.ADMIN_PWA_NODE_SHA256, 'ADMIN_PWA_NODE_SHA256'),
    playwright: await pinnedFile(process.env.PLAYWRIGHT_CORE_PATH, process.env.PLAYWRIGHT_CORE_SHA256, 'PLAYWRIGHT_CORE_PATH and PLAYWRIGHT_CORE_SHA256'),
    chrome: await pinnedFile(process.env.ADMIN_PWA_CHROME, process.env.ADMIN_PWA_CHROME_SHA256, 'ADMIN_PWA_CHROME and ADMIN_PWA_CHROME_SHA256'),
    node_version: process.version,
    pin_scope: 'running Node binary, Playwright module entry and Chrome executable; transitive runtime custody belongs to the managed runner',
  };
}
const runtime = await runtimePins();
await mkdir(evidence, { recursive: true });
const report = {
  startedAt: new Date().toISOString(), status: 'running', finalAcceptance: false,
  environment: 'isolated_chromium_synthetic_admin_build_real_service_worker',
  installedMode: 'not_exercised', realAuthentication: 'not_exercised',
  checks: [], sourceInputs: {}, requests: [], errors: [], runtimePins: runtime,
};
let browser, server, pwaSession, installedManifestId;
const contexts = [];
function check(id, condition, observed) {
  report.checks.push({ id, status: condition ? 'pass' : 'fail', observed });
  console.log(JSON.stringify({ id, status: condition ? 'pass' : 'fail' }));
}
async function save() {
  await writeFile(join(evidence, 'report.json'), JSON.stringify(report, null, 2) + '\n');
}
async function renderedAdmin(page) {
  await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder') ||
    document.querySelectorAll('flt-semantics').length > 5, null, { timeout: 90000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForFunction(() => [...document.querySelectorAll('flt-semantics[aria-label]')]
    .some((node) => node.getAttribute('aria-label').includes('Collect admin evidence mode marker')),
  null, { timeout: 30000 });
  await page.waitForFunction(() => [...document.querySelectorAll('flt-semantics[aria-label]')]
    .some((node) => node.getAttribute('aria-label').includes('Collect admin workspace')),
  null, { timeout: 30000 });
}
async function launchedPage(context, browserSession, targetId) {
  // PWA.launch returns a tab target above Playwright's page target. Resolve
  // the actual app window instead of comparing those different target IDs.
  const launchedWindow = await browserSession.send('Browser.getWindowForTarget', { targetId });
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    for (const page of context.pages()) {
      if (page.isClosed()) continue;
      let session;
      try {
        session = await context.newCDPSession(page);
        const { targetInfo } = await session.send('Target.getTargetInfo');
        const pageWindow = await browserSession.send('Browser.getWindowForTarget', { targetId: targetInfo.targetId });
        if (pageWindow.windowId === launchedWindow.windowId &&
            await page.evaluate(() => matchMedia('(display-mode: standalone)').matches)) {
          report.launchedWindows ||= [];
          report.launchedWindows.push({ tabTargetId: targetId, pageTargetId: targetInfo.targetId,
            windowId: pageWindow.windowId });
          return page;
        }
      } catch (error) {
        if (!page.isClosed()) throw error;
      } finally { await session?.detach().catch(() => {}); }
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw Error('Launched PWA target was not observed: ' + targetId);
}
try {
  const buildReport = JSON.parse(await readFile(buildReportPath, 'utf8'));
  if (buildReport.exit_code !== 0 || !buildReport.source_inputs_stable ||
      buildReport.fixture_mode !== true || buildReport.backend_configured !== false ||
      !buildReport.build_files?.length) throw Error('Verified synthetic, backend-free build required');
  const sourceManifest = JSON.parse(await readFile(join(dirname(buildReportPath), 'build-source-before.json'), 'utf8'));
  for (const entry of sourceManifest) {
    if (await hashFile(join(root, entry.path)) !== entry.sha256) throw Error(`Stale application source: ${entry.path}`);
  }
  const built = join(dirname(buildReportPath), 'build');
  for (const entry of buildReport.build_files) {
    if (await hashFile(join(built, entry.path)) !== entry.sha256) throw Error(`Changed build artifact: ${entry.path}`);
  }
  const sourcePaths = [
    'scripts/qa/collect_diagnostic_observer.mjs',
    'scripts/qa/admin_pwa_lifecycle_qa.mjs', 'scripts/qa/admin_pwa_update_policy.mjs', 'scripts/admin_pwa_release_build.sh',
    'scripts/admin_pwa_manifest_gate.sh', 'web/flutter_bootstrap.js',
    'lib/app/theme/collect_colors.dart',
  ];
  if (existsSync(join(root, 'scripts/templates/admin_pwa_service_worker.js'))) {
    sourcePaths.push('scripts/templates/admin_pwa_service_worker.js');
  }
  for (const path of sourcePaths) report.sourceInputs[path] = await hashFile(join(root, path));
  report.buildReport = relative(root, buildReportPath);
  report.buildReportSha256 = await hashFile(buildReportPath);
  report.applicationSourceCount = sourceManifest.length;
  report.verifiedArtifactCount = buildReport.build_files.length;
  const script = await readFile(join(root, 'scripts/admin_pwa_release_build.sh'), 'utf8');
  const marker = "ruby -r digest -r json -r open3 <<'RUBY'\n";
  if (script.split(marker).length !== 2) throw Error('Build postprocessor declaration is ambiguous');
  const ruby = script.split(marker)[1].split('\nRUBY\n')[0];
  if (!ruby.includes('ENV.fetch("COLLECT_ADMIN_BUILD_METADATA")')) throw Error('Current explicit public metadata handoff is required');
  await writeFile(join(evidence, 'postprocessor.rb'), ruby);
  report.postprocessor = { builderSha256: sha(script), extractedSha256: sha(ruby),
    writtenSha256: await hashFile(join(evidence, 'postprocessor.rb')), productionRubyModified: false };
  if (report.postprocessor.extractedSha256 !== report.postprocessor.writtenSha256) throw Error('Extracted production Ruby changed');
  async function stage(name, shellVersion) {
    const stageRoot = join(evidence, name);
    const web = join(stageRoot, 'build/web');
    // Ruby rewrites _headers and can overwrite an existing _build namespace.
    // Every staged file therefore needs an inode independent of the retained artifact.
    for (const entry of buildReport.build_files) {
      const retained = join(built, entry.path);
      const original = await lstat(retained);
      if (!original.isFile() || original.isSymbolicLink()) throw Error(`Retained artifact must be a regular file: ${entry.path}`);
      const target = join(web, entry.path);
      await mkdir(dirname(target), { recursive: true });
      await copyFile(retained, target);
      const staged = await lstat(target);
      if (!staged.isFile() || staged.isSymbolicLink() || staged.nlink !== 1 ||
          (original.dev === staged.dev && original.ino === staged.ino)) {
        throw Error(`Staged artifact aliases retained input: ${entry.path}`);
      }
    }
    for (const path of ['lib/app/theme/collect_colors.dart', 'scripts/templates/admin_pwa_service_worker.js']) {
      if (!existsSync(join(root, path))) continue;
      await mkdir(dirname(join(stageRoot, path)), { recursive: true });
      await copyFile(join(root, path), join(stageRoot, path));
    }
    const index = await readFile(join(web, 'index.html'), 'utf8');
    await writeFile(join(web, 'index.html'), index.replace('</head>', `<meta name="qa-shell-version" content="${shellVersion}"></head>`));
    const originalVersion = JSON.parse(await readFile(join(web, 'version.json'), 'utf8'));
    if (!originalVersion || Array.isArray(originalVersion) || typeof originalVersion !== 'object') {
      throw Error(`${name}: original version.json must contain public artifact metadata`);
    }
    const metadataPath = join(stageRoot, 'public-build-metadata.json');
    await writeFile(metadataPath, JSON.stringify(originalVersion, null, 2) + '\n', { mode: 0o600 });
    const childEnv = { ...process.env, COLLECT_ADMIN_BUILD_METADATA: metadataPath };
    delete childEnv.COLLECT_SOURCE_MANIFEST_SHA256;
    delete childEnv.COLLECT_PLATFORM_API_SOURCE_ID;
    const rendered = spawnSync('ruby', ['-r', 'digest', '-r', 'json', '-r', 'open3', join(evidence, 'postprocessor.rb')],
      { cwd: stageRoot, env: childEnv, encoding: 'utf8', timeout: 30000 });
    await writeFile(join(evidence, name + '.postprocess.log'), (rendered.stdout || '') + (rendered.stderr || ''));
    if (rendered.status !== 0) throw Error(`Postprocessor failed: ${name}`);
    const derivedVersion = JSON.parse(await readFile(join(web, 'version.json'), 'utf8'));
    const changedVersionFields = [...new Set([...Object.keys(originalVersion), ...Object.keys(derivedVersion)])]
      .filter((key) => JSON.stringify(originalVersion[key]) !== JSON.stringify(derivedVersion[key]));
    if (changedVersionFields.some((key) => !['source_commit', 'source_dirty'].includes(key))) {
      throw Error(`${name}: postprocessing changed artifact authority/runtime metadata`);
    }
    const metadata = { path: metadataPath, sha256: await hashFile(metadataPath), originalVersion, derivedVersion,
      derivedQaFields: changedVersionFields, sameProductionArtifactClaimed: false, authorityRuntimeFieldsPreserved: true };
    const worker = await readFile(join(web, 'custom-sw.js'), 'utf8');
    return { web, metadata, stagingCopyPolicy: 'independent_regular_files_including_headers_and_existing_build_namespaces',
      cache: worker.match(/const CACHE_NAME = "([^"]+)";/)?.[1],
      workerSha256: sha(worker), indexSha256: await hashFile(join(web, 'index.html')) };
  }
  const a = await stage('version-a', 'a');
  const b = await stage('version-b', 'b');
  const failedUpdate = await stage('version-failed-update', 'failed-update');
  report.stages = { a, b, failedUpdate };
  check('shell-only-change-versions-cache', a.cache !== b.cache, { before: a.cache, after: b.cache });
  check('shell-only-change-updates-worker-bytes', a.workerSha256 !== b.workerSha256, { before: a.workerSha256, after: b.workerSha256 });
  let active = a, outage = false, failAsset = false, actor = 'account-a';
  const mimes = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json',
    '.wasm': 'application/wasm', '.png': 'image/png', '.webp': 'image/webp', '.css': 'text/css' };
  server = createServer(async (request, response) => {
    const url = new URL(request.url, 'http://127.0.0.1');
    report.requests.push({ method: request.method, pathname: url.pathname, outage,
      qaProbe: url.searchParams.get('__qa_probe') });
    if (outage) { request.socket.destroy(); return; }
    if (failAsset && url.pathname === '/manifest.json') {
      response.writeHead(503); response.end('Synthetic update outage'); return;
    }
    if (url.pathname === '/__qa/account') {
      response.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      response.end(JSON.stringify({ actor })); return;
    }
    if (url.pathname === '/index.html') {
      response.writeHead(308, { Location: '/', 'Cache-Control': 'no-store' }); response.end(); return;
    }
    let path = resolve(active.web, '.' + decodeURIComponent(url.pathname));
    if (!path.startsWith(active.web + sep) && path !== active.web) {
      response.writeHead(404); response.end(); return;
    }
    try {
      if (!(await stat(path)).isFile()) path = join(active.web, 'index.html');
    } catch { path = join(active.web, 'index.html'); }
    const body = await readFile(path);
    response.writeHead(200, { 'Content-Type': mimes[extname(path)] || 'application/octet-stream',
      'Cache-Control': 'no-store' });
    response.end(body);
  });
  await new Promise((yes, no) => { server.once('error', no); server.listen(0, '127.0.0.1', yes); });
  const origin = `http://127.0.0.1:${server.address().port}`;
  report.origin = origin;
  await runtimePins();
  const loaded = await import(pathToFileURL(runtime.playwright.path).href);
  const { chromium } = loaded.default || loaded;
  const launchOptions = { headless: !installed,
    executablePath: runtime.chrome.path,
    args: ['--disable-background-networking', '--disable-component-update', '--disable-sync'] };
  const profile = join(evidence, 'isolated-chrome-profile');
  let context;
  if (installed) {
    context = await chromium.launchPersistentContext(profile, { ...launchOptions,
      serviceWorkers: 'allow', viewport: { width: 1280, height: 900 } });
    browser = context.browser();
    report.profile = relative(root, profile);
  } else {
    browser = await chromium.launch(launchOptions);
    context = await browser.newContext({ serviceWorkers: 'allow', viewport: { width: 1280, height: 900 } });
  }
  report.browserVersion = browser.version();
  contexts.push(context);
  const observePage = page => {
    page.on('pageerror', error => report.errors.push(error.message));
    observeCollectDiagnostics(page, diagnostic => report.errors.push('Collect diagnostic failure: ' + JSON.stringify(diagnostic)));
  };
  context.pages().forEach(observePage); context.on('page', observePage);
  await context.route('**/*', (route) => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
  const page = await context.newPage();
  page.setDefaultTimeout(30000);
  await page.goto(origin + '/#/admin/groups', { waitUntil: 'domcontentloaded' });
  await page.evaluate(() => navigator.serviceWorker.ready);
  check('first-install-does-not-claim-network-page', await page.evaluate(() => navigator.serviceWorker.controller === null));
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => navigator.serviceWorker.controller, null, { timeout: 90000 });
  await renderedAdmin(page);
  const cacheKeys = await page.evaluate(() => caches.keys());
  check('first-install-controls-rendered-admin', cacheKeys.includes(a.cache), cacheKeys);
  check('first-shell-version', await page.locator('meta[name=qa-shell-version]').getAttribute('content') === 'a', 'a');
  const cachedPaths = await page.evaluate(async () => {
    const keys = await caches.keys();
    return (await Promise.all(keys.map(async (key) => (await (await caches.open(key)).keys()).map((r) => new URL(r.url).pathname)))).flat();
  });
  check('root-shell-is-precached', cachedPaths.includes('/') && !cachedPaths.includes('/index.html'), cachedPaths.filter((p) => p === '/' || p === '/index.html'));
  const sibling = await context.newPage();
  await sibling.goto(origin + '/#/admin/transactions', { waitUntil: 'domcontentloaded' });
  await renderedAdmin(sibling);
  const first = await page.evaluate(() => fetch('/__qa/account').then((r) => r.json()));
  const siblingFirst = await sibling.evaluate(() => fetch('/__qa/account').then((r) => r.json()));
  actor = 'account-b';
  const second = await page.evaluate(() => fetch('/__qa/account').then((r) => r.json()));
  const siblingSecond = await sibling.evaluate(() => fetch('/__qa/account').then((r) => r.json()));
  check('no-store-response-fresh-after-account-change',
    first.actor === 'account-a' && siblingFirst.actor === 'account-a' &&
    second.actor === 'account-b' && siblingSecond.actor === 'account-b',
    { first, siblingFirst, second, siblingSecond });
  const privateCached = await page.evaluate(async () => Boolean(await caches.match('/__qa/account')));
  const siblingPrivateCached = await sibling.evaluate(async () => Boolean(await caches.match('/__qa/account')));
  check('non-asset-response-not-in-shell-cache', !privateCached && !siblingPrivateCached,
    { privateCached, siblingPrivateCached });
  outage = true; await context.setOffline(true);
  const offlinePrivate = await Promise.all([page, sibling].map((tab) => tab.evaluate(async () => {
    try { await fetch('/__qa/account'); return 'unexpected-response'; }
    catch { return 'network-failed'; }
  })));
  check('offline-private-response-unavailable-in-both-tabs',
    offlinePrivate.every((result) => result === 'network-failed'), offlinePrivate);
  const cold = await context.newPage();
  try {
    await cold.goto(origin + '/#/admin/settings', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await renderedAdmin(cold);
    check('offline-cold-hash-route-loads-admin-shell', true, cold.url());
  } catch (error) { check('offline-cold-hash-route-loads-admin-shell', false, error.message); }
  await cold.close();
  const fallback = await context.newPage();
  try {
    const response = await fallback.goto(origin + '/admin/qa-unvisited', { waitUntil: 'domcontentloaded', timeout: 15000 });
    check('offline-navigation-fallback-uses-root-shell', response?.status() === 200 &&
      await fallback.locator('meta[name=qa-shell-version]').getAttribute('content') === 'a', response?.status());
  } catch (error) { check('offline-navigation-fallback-uses-root-shell', false, error.message); }
  await fallback.close();
  outage = false; await context.setOffline(false);
  await page.evaluate(() => { window.qaUnsavedWork = 'synthetic-unsaved-input'; });
  active = b;
  const controllerUpdate = await observeWaitingAdminUpdate(page);
  report.controllerUpdate = controllerUpdate;
  check('worker-update-waits-with-old-controller', controllerUpdate.sameController && controllerUpdate.state === 'installed', controllerUpdate);
  check('waiting-update-preserves-open-page-state', await page.evaluate(() => window.qaUnsavedWork) === 'synthetic-unsaved-input', 'synthetic transient state');
  const waitingKeys = await page.evaluate(() => caches.keys());
  check('waiting-update-retains-both-static-builds', waitingKeys.includes(a.cache) && waitingKeys.includes(b.cache), waitingKeys);
  await page.reload({ waitUntil: 'domcontentloaded' });
  check('ordinary-reload-retains-old-shell-while-tabs-open', await page.locator('meta[name=qa-shell-version]').getAttribute('content') === 'a');
  await reopenAfterAllAdminTabsLeave(context, origin);
  check('reopen-after-all-tabs-close-receives-updated-shell', await page.locator('meta[name=qa-shell-version]').getAttribute('content') === 'b');
  const afterKeys = await page.evaluate(() => caches.keys());
  check('old-shell-cache-retired', a.cache !== b.cache && afterKeys.includes(b.cache) && !afterKeys.includes(a.cache), afterKeys);
  const siblingAfterUpdate = await sibling.evaluate(() => fetch('/__qa/account').then((r) => r.json()));
  check('open-sibling-tab-uses-fresh-private-response-after-worker-update',
    siblingAfterUpdate.actor === 'account-b', siblingAfterUpdate);
  report.cacheShellVersions = await page.evaluate(async () => Object.fromEntries(await Promise.all(
    (await caches.keys()).map(async (key) => {
      const response = await (await caches.open(key)).match('/');
      return [key, response ? (await response.text()).match(/name="qa-shell-version" content="([^"]+)"/)?.[1] : null];
    }))));
  active = failedUpdate; failAsset = true;
  const rejectedUpdate = await page.evaluate(async () => {
    const registration = await navigator.serviceWorker.ready;
    const controller = navigator.serviceWorker.controller;
    let timer;
    const outcome = new Promise((resolve, reject) => {
      const listen = () => {
        const worker = registration.installing;
        if (!worker) return;
        worker.addEventListener('statechange', () => {
          if (worker.state === 'redundant' || worker.state === 'activated') resolve(worker.state);
        });
      };
      registration.addEventListener('updatefound', listen, { once: true });
      timer = setTimeout(() => reject(Error('Update outcome not observed')), 90000);
    });
    try {
      await registration.update();
      return { state: await outcome, sameController: navigator.serviceWorker.controller === controller };
    } finally { clearTimeout(timer); }
  });
  check('failed-update-does-not-replace-active-worker', rejectedUpdate.state === 'redundant' && rejectedUpdate.sameController, rejectedUpdate);
  const failedKeys = await page.evaluate(() => caches.keys());
  check('failed-install-removes-partial-new-cache', failedKeys.includes(b.cache) && !failedKeys.includes(failedUpdate.cache), failedKeys);
  outage = true; await context.setOffline(true);
  await page.reload({ waitUntil: 'domcontentloaded' });
  check('failed-update-keeps-previous-shell-offline', await page.locator('meta[name=qa-shell-version]').getAttribute('content') === 'b',
    await page.locator('meta[name=qa-shell-version]').getAttribute('content'));
  outage = false; failAsset = false; active = b; await context.setOffline(false);
  await sibling.close();
  await renderedAdmin(page);
  await page.screenshot({ path: join(evidence, 'browser-admin.png') });
  if (installed) {
    pwaSession = await browser.newBrowserCDPSession();
    installedManifestId = origin + '/';
    await pwaSession.send('PWA.install', { manifestId: installedManifestId, installUrlOrBundleUrl: origin + '/' });
    await pwaSession.send('PWA.changeAppUserSettings', { manifestId: installedManifestId, displayMode: 'standalone' });
    report.installedDisplayPreference = 'standalone';
    report.installedOsState = await pwaSession.send('PWA.getOsAppState', { manifestId: installedManifestId });
    check('actual-pwa-installed-in-isolated-profile', true, report.installedOsState);
    const launched = await pwaSession.send('PWA.launch', { manifestId: installedManifestId, url: origin + '/#/admin/groups' });
    const app = await launchedPage(context, pwaSession, launched.targetId);
    await renderedAdmin(app);
    const appCdp = await context.newCDPSession(app);
    const target = await appCdp.send('Target.getTargetInfo');
    const standalone = await app.evaluate(() => matchMedia('(display-mode: standalone)').matches);
    check('installed-launch-is-standalone-target', standalone && target.targetInfo.targetId === report.launchedWindows.at(-1).pageTargetId,
      { standalone, ...report.launchedWindows.at(-1) });
    await app.screenshot({ path: join(evidence, 'installed-admin.png') });
    await app.close();
    await context.close();
    outage = true;
    context = await chromium.launchPersistentContext(profile, { ...launchOptions,
      serviceWorkers: 'allow', viewport: { width: 1280, height: 900 } });
    contexts.push(context); browser = context.browser();
    context.pages().forEach(observePage); context.on('page', observePage);
    await context.setOffline(true);
    await context.route('**/*', (route) => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
    pwaSession = await browser.newBrowserCDPSession();
    const coldLaunch = await pwaSession.send('PWA.launch', { manifestId: installedManifestId, url: origin + '/#/admin/settings' });
    const coldApp = await launchedPage(context, pwaSession, coldLaunch.targetId);
    await renderedAdmin(coldApp);
    const coldState = await coldApp.evaluate(() => ({ standalone: matchMedia('(display-mode: standalone)').matches,
      shell: document.querySelector('meta[name=qa-shell-version]')?.content,
      offline: !navigator.onLine, controller: Boolean(navigator.serviceWorker.controller), hash: location.hash }));
    const originUnavailable = await coldApp.evaluate(async () => {
      try { await fetch('/__qa/account'); return false; } catch { return true; }
    });
    check('installed-cold-browser-restart-during-origin-outage', coldState.standalone && coldState.shell === 'b' &&
      coldState.controller && outage && originUnavailable, { ...coldState, originUnavailable, targetId: coldLaunch.targetId });
    // Keep the server healthy for the separate network-emulation checks. A
    // failed fetch during the origin outage cannot prove browser-level offline.
    outage = false;
    async function blockedNetworkProbe(label) {
      const controlLabel = label + '-server-control';
      const control = await fetch(origin + '/__qa/account?__qa_probe=' + controlLabel);
      const serverHealthy = control.ok && (await control.json()).actor === 'account-b';
      const probeUrl = origin + '/__qa/account?__qa_probe=' + label;
      const failed = coldApp.waitForEvent('requestfailed', {
        predicate: (request) => request.url() === probeUrl, timeout: 10000,
      }).then((request) => request.failure()?.errorText, () => 'request-failure-not-observed');
      const browserSucceeded = await coldApp.evaluate((url) => fetch(url, { cache: 'no-store' })
        .then(() => true, () => false), probeUrl);
      const errorText = await failed;
      const serverReceivedProbe = report.requests.some((request) => request.qaProbe === label);
      const observed = { serverHealthy, browserSucceeded, errorText, serverReceivedProbe, originOutage: outage };
      check(label, serverHealthy && !outage && !browserSucceeded && !serverReceivedProbe &&
        errorText === 'net::ERR_INTERNET_DISCONNECTED', observed);
    }
    // Context-wide emulation does not reliably apply to a PWA tab opened by
    // Chrome. Keep origin-outage startup separate from explicit target-offline
    // reload; navigator.onLine alone cannot prove server reachability.
    const coldCdp = await context.newCDPSession(coldApp);
    report.installedContextMatches = coldApp.context() === context;
    // Refresh the automation context after Chrome has created its app target,
    // so a new renderer also receives the intended state on reload.
    await coldApp.context().setOffline(false);
    await coldApp.context().setOffline(true);
    await coldCdp.send('Network.enable');
    await coldCdp.send('Network.emulateNetworkConditionsByRule', { emulateOfflineServiceWorker: true,
      matchedNetworkConditions: [{ urlPattern: '', offline: true, latency: 0, downloadThroughput: -1, uploadThroughput: -1 }] });
    await coldCdp.send('Network.overrideNetworkState', { offline: true, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
    report.installedOfflineBeforeReload = await coldApp.evaluate(() => !navigator.onLine);
    await blockedNetworkProbe('installed-offline-blocks-network-before-reload');
    await coldApp.reload({ waitUntil: 'domcontentloaded' });
    await renderedAdmin(coldApp);
    const offlineReload = await coldApp.evaluate(() => ({ offline: !navigator.onLine,
      shell: document.querySelector('meta[name=qa-shell-version]')?.content,
      standalone: matchMedia('(display-mode: standalone)').matches, controller: Boolean(navigator.serviceWorker.controller) }));
    check('installed-target-offline-reload', report.installedOfflineBeforeReload && offlineReload.offline && offlineReload.shell === 'b' &&
      offlineReload.standalone && offlineReload.controller, offlineReload);
    await blockedNetworkProbe('installed-offline-blocks-network-after-reload');
    report.offlineIndicatorLimitation = 'Minimal ordinary-tab and installed-page reproduction also loses navigator.onLine state after reload. The indicator check remains failed; separate probes require a healthy server, no server receipt and Chromium ERR_INTERNET_DISCONNECTED.';
    report.startupNetworkBoundary = 'Origin unreachable before browser restart. Device-wide offline state before app startup is not proven; explicit target-offline reload is a separate check.';
    await coldApp.screenshot({ path: join(evidence, 'installed-cold-offline.png') });
    outage = false; await context.setOffline(false);
    await coldCdp.send('Network.emulateNetworkConditionsByRule', { emulateOfflineServiceWorker: false, matchedNetworkConditions: [] });
    await coldCdp.send('Network.overrideNetworkState', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
    await coldApp.reload({ waitUntil: 'domcontentloaded' });
    const reconnected = await coldApp.evaluate(() => fetch('/__qa/account').then((response) => response.json()));
    check('installed-window-reconnects-with-current-shell', await coldApp.evaluate(() => navigator.onLine) &&
      await coldApp.locator('meta[name=qa-shell-version]').getAttribute('content') === 'b' && reconnected.actor === 'account-b', reconnected);
    report.installedMode = report.checks.filter((item) => item.id.startsWith('installed-') ||
      item.id === 'actual-pwa-installed-in-isolated-profile').every((item) => item.status === 'pass')
      ? 'macos_chrome_install_outage_restart_and_target_offline_reload' : 'attempted_unverified';
  }
  report.renderedScope = 'Synthetic Admin workspace semantics rendered from the verified existing build. Complete operator tasks, real sessions and readers remain unverified; installed mode is reported separately.';
  for (const [path, expected] of Object.entries(report.sourceInputs)) {
    if (await hashFile(join(root, path)) !== expected) throw Error(`Source changed during run: ${path}`);
  }
  for (const entry of buildReport.build_files) {
    if (await hashFile(join(built, entry.path)) !== entry.sha256) throw Error(`Original artifact changed: ${entry.path}`);
  }
  report.sourceInputsUnchanged = true;
  report.originalBuildUnchanged = true;
  report.status = report.checks.every((c) => c.status === 'pass') ? 'pass' : 'fail';
} catch (error) {
  report.status = 'fail'; report.error = error.stack || String(error);
} finally {
  if (pwaSession && installedManifestId) {
    try {
      await pwaSession.send('PWA.uninstall', { manifestId: installedManifestId });
      let absent = false;
      try { await pwaSession.send('PWA.getOsAppState', { manifestId: installedManifestId }); }
      catch (error) { absent = /not installed|not found|unknown|no web app/i.test(error.message); }
      report.installedAppRemoved = absent;
      if (!absent) { report.status = 'fail'; report.errors.push('Uninstall could not be verified'); }
    } catch (error) { report.status = 'fail'; report.errors.push('PWA uninstall: ' + error.message); }
  }
  for (const context of contexts) await context.close().catch((e) => report.errors.push('Context close: ' + e.message));
  if (browser) await browser.close().catch((e) => report.errors.push('Browser close: ' + e.message));
  if (server) {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
  try { await runtimePins(); report.runtimePinsUnchanged = true; }
  catch (error) { report.status = 'fail'; report.errors.push(error.message); }
  report.listenersClosed = !server?.listening;
  if (report.errors.length) report.status = 'fail';
  report.finishedAt = new Date().toISOString();
  await save();
}
console.log(JSON.stringify({ status: report.status, checks: report.checks.length,
  failed: report.checks.filter((c) => c.status === 'fail').map((c) => c.id), error: report.error }));
process.exitCode = report.status === 'pass' ? 0 : 1;
