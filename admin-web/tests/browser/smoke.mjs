import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { installLocalNetworkFence } from '../../../scripts/qa/public_browser_local_network.cjs';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const artifact = resolve(root, process.argv[2] ?? process.env.ADMIN_PWA_BUILD_DIR ?? 'build/admin-web-fixture');
const origin = process.env.ADMIN_PWA_FIXTURE_ORIGIN ?? 'http://127.0.0.1:4175';
const url = new URL(origin);
assert(url.protocol === 'http:' && url.hostname === '127.0.0.1' && url.origin === origin && url.port,
  'Use the explicit HTTP loopback origin of the fixture build.');
const { backend } = JSON.parse(await readFile(join(artifact, 'version.json'), 'utf8'));
assert.equal(backend, 'unconfigured', 'Use a synthetic artifact built in fixture mode.');
execFileSync(process.execPath, [join(root, 'admin-web/scripts/build-admin.mjs'), 'verify', artifact], {
  cwd: root, stdio: 'inherit',
});

const modulePath = process.env.PLAYWRIGHT_CORE_PATH;
const { chromium } = await import(modulePath ? pathToFileURL(resolve(modulePath)).href : 'playwright-core');
const server = spawn(process.execPath, [fileURLToPath(new URL('./fixture-server.mjs', import.meta.url)), artifact], {
  env: { COLLECT_FIXTURE_PORT: url.port, COLLECT_FIXTURE_SIGN_IN: '1' },
  stdio: ['ignore', 'pipe', 'inherit'],
});
const exited = new Promise(resolveExit => server.once('close', resolveExit));
const denied = [];
const pageErrors = [];
let browser;
try {
  await new Promise((ready, fail) => {
    const timer = setTimeout(() => fail(new Error('Admin fixture did not bind its loopback port.')), 5000);
    server.once('exit', code => {
      clearTimeout(timer);
      fail(new Error(`Admin fixture exited with status ${code}.`));
    });
    server.once('error', error => {
      clearTimeout(timer);
      fail(error);
    });
    server.stdout.on('data', output => {
      if (output.toString().includes(origin)) {
        clearTimeout(timer);
        ready();
      }
    });
  });

  const installed = chromium.executablePath();
  const executablePath = process.env.ADMIN_PWA_CHROME || (existsSync(installed) ? installed : undefined);
  browser = await chromium.launch({
    headless: true, args: ['--disable-background-networking'],
    // The fixture serves its own origin and refuses proxy requests. Bound the
    // network here too so the service-worker context can use normal navigation.
    proxy: { server: origin, bypass: '127.0.0.1' },
    ...(executablePath ? { executablePath } : { channel: 'chrome' }),
  });
  async function open(viewport, serviceWorkers) {
    const context = await browser.newContext({ viewport, serviceWorkers });
    context.setDefaultTimeout(10_000);
    const page = await context.newPage();
    page.on('pageerror', error => pageErrors.push(error.message));
    if (serviceWorkers === 'block') await installLocalNetworkFence(page, origin, denied);
    else context.on('request', request => {
      const target = new URL(request.url());
      if (target.origin !== origin) denied.push({ origin: target.origin, resourceType: request.resourceType() });
    });
    return { context, page };
  }

  const desktop = await open({ width: 1440, height: 900 }, 'block');
  const { page } = desktop;
  await page.goto(origin + '/admin');
  await page.getByRole('heading', { name: 'Welcome to Collect' }).waitFor();
  await page.getByLabel('Email', { exact: true }).fill('fixture@example.test');
  await page.getByRole('button', { name: 'Send sign-in code' }).click();
  await page.getByRole('heading', { name: 'Check your email' }).waitFor();
  await page.getByLabel('6-digit code', { exact: true }).fill('123456');
  await page.getByRole('button', { name: 'Verify and sign in' }).click();
  const overview = page.getByRole('heading', { name: 'Operations overview' });
  await overview.waitFor();
  const cookies = await desktop.context.cookies(origin);
  assert(cookies.some(cookie => cookie.name === 'collect_fixture_session' && cookie.httpOnly));
  assert(!String(await page.evaluate(() => document.cookie)).includes('collect_fixture_session'));
  await page.reload();
  await overview.waitFor();

  const receipts = requestUrl => requestUrl.origin === origin && requestUrl.pathname === '/api/admin/sms/receipts';
  await page.route(receipts, route => route.fulfill({
    status: 503, contentType: 'application/json', body: JSON.stringify({ error: { code: 'service_unavailable' } }),
  }), { times: 1 });
  const search = page.getByRole('searchbox', {name: 'Search admin sections'});
  await search.fill('SMS receipts');
  await search.press('ArrowDown');
  const receiptDestination = page.getByRole('link', {name: 'SMS receipts', exact: true});
  assert.equal(await receiptDestination.evaluate(link => link === document.activeElement), true);
  await page.keyboard.press('Enter');
  await page.getByRole('heading', { name: 'SMS receipts', level: 1, exact: true }).waitFor();
  await page.getByRole('button', { name: /retry|try again/i }).click();
  const receiptRow = page.getByRole('table').getByRole('row').nth(1);
  await receiptRow.waitFor();
  await page.setViewportSize({width: 320, height: 768});
  assert.equal(await receiptRow.evaluate((row) => getComputedStyle(row).display), 'grid');
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await page.setViewportSize({width: 1440, height: 900});
  await page.goBack();
  await overview.waitFor();

  const recovery = await open({ width: 1440, height: 900 }, 'block');
  await recovery.context.addCookies(cookies);
  const sessionPage = recovery.page;
  const sessionApi = url => url.origin === origin && url.pathname === '/api/admin/auth/session';
  let nextSession = 'default';
  await recovery.context.route(sessionApi, async route => {
    const mode = nextSession;
    nextSession = 'default';
    if (mode === 'default') return route.fallback();
    if (mode === 'unavailable') return route.fulfill({ status: 503, json: { error: { code: 'service_unavailable' } } });
    // The default fixture owner lacks the protected-owner proof and receiving permissions.
    const response = await route.fetch();
    const body = await response.json();
    const { id, principalId, email, permissions } = body.user;
    return route.fulfill({ response, json: { ...body, ownerEmail: email,
      user: { ...body.user, permissions: [...permissions, 'admin_users.manage', 'receivers.manage'] },
      ownerIdentity: { schemaVersion: 1, adminId: id, principalId, email } } });
  });
  const protectedReads = [];
  sessionPage.on('request', request => {
    const { pathname } = new URL(request.url());
    if (pathname.startsWith('/api/admin/burimunsi/') || ['/api/admin/momo/native-setup', '/api/admin/core/groups'].includes(pathname)) protectedReads.push(pathname);
  });

  await sessionPage.goto(origin + '/admin/security/authenticator?' + new URLSearchParams({ returnTo: '/admin/burimunsi?draft=private' }));
  await sessionPage.getByRole('heading', { name: 'Verify your email' }).waitFor();
  assert.equal(new URL(sessionPage.url()).hash, '#/admin/security/verify-email?returnTo=%2Fadmin%2Fburimunsi');
  await sessionPage.getByRole('button', { name: 'Back', exact: true }).click();
  await sessionPage.getByRole('heading', { name: 'Access unavailable' }).waitFor();
  assert.equal(new URL(sessionPage.url()).hash, '#/admin/burimunsi');

  nextSession = 'owner';
  await sessionPage.reload();
  await sessionPage.getByRole('heading', { name: 'BuriMunsi access' }).waitFor();
  await sessionPage.getByRole('button', { name: 'Verify email', exact: true }).click();
  await sessionPage.getByRole('heading', { name: 'Verify your email' }).waitFor();
  await sessionPage.getByRole('button', { name: 'Back', exact: true }).click();
  await sessionPage.getByRole('heading', { name: 'BuriMunsi access' }).waitFor();

  nextSession = 'unavailable';
  await sessionPage.reload();
  await sessionPage.getByRole('heading', { name: 'Workspace unavailable' }).waitFor();
  assert.equal(await sessionPage.getByRole('heading', { name: 'BuriMunsi access' }).count(), 0);
  await sessionPage.getByRole('button', { name: 'Try again' }).click();
  await sessionPage.getByRole('heading', { name: 'Access unavailable' }).waitFor();

  const sessionRead = sessionPage.waitForResponse(response => sessionApi(new URL(response.url())));
  await sessionPage.goto(origin + '/admin/licenses');
  const { expiresAt } = await (await sessionRead).json();
  await sessionPage.getByRole('heading', { name: 'Open-source licenses' }).waitFor();
  // Advance only wall time, as on tab resume before the browser runs due timers.
  await sessionPage.clock.setSystemTime(new Date(Date.parse(expiresAt) + 1));
  await sessionPage.getByRole('link', { name: 'Groups', exact: true }).click();
  await sessionPage.getByRole('heading', { name: 'Welcome to Collect' }).waitFor();
  assert.equal(new URL(sessionPage.url()).hash, '#/admin/login?returnTo=%2Fadmin%2Fgroups');
  await sessionPage.goBack();
  await sessionPage.waitForURL(url => url.hash === '#/admin/login?returnTo=%2Fadmin%2Flicenses');
  assert.equal(await sessionPage.getByRole('heading', { name: 'Open-source licenses' }).count(), 0);
  assert.deepEqual(protectedReads, []);
  await recovery.context.close();

  const mobile = await open({ width: 390, height: 844 }, 'block');
  await mobile.page.goto(origin + '/admin/sms-receipts');
  await mobile.page.getByRole('heading', { name: 'Welcome to Collect' }).waitFor();
  assert(!mobile.page.url().includes('fixture@example.test'));
  assert.equal(await mobile.page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  assert.equal(await mobile.page.getByRole('heading', { name: 'SMS receipts' }).count(), 0);

  await mobile.context.addCookies(cookies);
  await mobile.page.goto(origin + '/admin/sms-receipts');
  await mobile.page.getByRole('heading', { name: 'SMS receipts', level: 1, exact: true }).waitFor();
  const openNavigation = mobile.page.getByRole('button', { name: 'Open navigation' });
  const closeNavigation = mobile.page.getByRole('button', { name: 'Close navigation' });
  await openNavigation.click();
  await closeNavigation.waitFor();
  assert.equal(await closeNavigation.evaluate(button => document.activeElement === button), true);
  assert.equal(await mobile.page.locator('.admin-main-column').evaluate(column => column.inert), true,
    'Background controls should be inert while the drawer is open.');
  await mobile.page.keyboard.press('Control+k');
  assert.equal(await closeNavigation.evaluate(button => document.activeElement === button), true);
  await mobile.page.keyboard.press('Escape');
  await openNavigation.waitFor();
  assert.equal(await openNavigation.evaluate(button => document.activeElement === button), true);
  await openNavigation.click();
  await mobile.page.setViewportSize({ width: 1024, height: 844 });
  await mobile.page.waitForFunction(() => !document.querySelector('.admin-main-column').inert);
  await mobile.page.getByRole('main').waitFor();
  await mobile.context.close();

  await page.getByRole('button', { name: /^Account:/ }).click();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await page.getByRole('heading', { name: 'Welcome to Collect' }).waitFor();
  assert(!(await desktop.context.cookies(origin)).some(cookie => cookie.name === 'collect_fixture_session'));

  // Exercise an actual install with a separate browser context.
  const pwa = await open({ width: 1280, height: 800 }, 'allow');
  await pwa.page.goto(origin + '/');
  await pwa.page.waitForFunction(async () => (await navigator.serviceWorker.getRegistration())?.active?.state === 'activated');
  // A first install waits for an existing tab to close. Reopen the app under
  // the installed scope, then require the worker to serve a bookmarked URL
  // with the browser offline.
  await pwa.page.close();
  const reopened = await pwa.context.newPage();
  reopened.on('pageerror', error => pageErrors.push(error.message));
  await reopened.goto(origin + '/?reopen=online');
  await reopened.evaluate(() => navigator.serviceWorker.ready.then(() => true));
  // The first reopened document can begin loading while activation propagates.
  // A regular navigation from that document must enter the installed scope.
  if (!await reopened.evaluate(() => Boolean(navigator.serviceWorker.controller))) {
    const controlledNavigation = reopened.waitForNavigation();
    await reopened.evaluate(next => location.assign(next), origin + '/?resume=fixture');
    await controlledNavigation;
  }
  await reopened.waitForFunction(() => navigator.serviceWorker.controller?.state === 'activated');
  await pwa.context.setOffline(true);
  const offline = await reopened.goto(origin + '/admin?reopen=fixture');
  assert(offline?.fromServiceWorker() && offline.status() === 200, 'The installed worker must serve the offline bookmark.');
  await reopened.waitForFunction(() => navigator.serviceWorker.controller?.state === 'activated');
  const cachedPaths = await reopened.evaluate(async () => {
    const names = await caches.keys();
    const requests = (await Promise.all(names.map(async name => (await caches.open(name)).keys()))).flat();
    return requests.map(request => new URL(request.url).pathname);
  });
  assert(cachedPaths.some(path => /^\/_build\/[0-9a-f]{64}\/assets\/admin-entry\.js$/.test(path)));
  assert(cachedPaths.every(path => path.startsWith('/_build/') || ['/', '/manifest.json', '/version.json'].includes(path)));
  assert.deepEqual(pageErrors, []);
  assert.deepEqual(denied, []);
  console.log(JSON.stringify({
    status: 'pass', environment: 'synthetic_loopback',
    checks: ['otp_sign_in_and_httponly_cookie', 'reload_restores_session', 'keyboard_receipt_navigation', 'sms_read_failure_retry',
      'compact_receipt_cards', 'browser_back_restores_overview', 'fresh_mobile_deep_link_requires_sign_in',
      'verification_preserves_safe_destination_and_rechecks_owner', 'failed_session_recheck_drops_old_owner_grant', 'expired_request_and_history_return_require_sign_in',
      'mobile_drawer_traps_and_restores_focus_and_reflows', 'sign_out_clears_fixture_cookie', 'installed_worker_caches_static_files_only'],
  }, null, 2));
} finally {
  await browser?.close();
  if (server.exitCode === null && server.signalCode === null) server.kill('SIGTERM');
  await exited;
}
