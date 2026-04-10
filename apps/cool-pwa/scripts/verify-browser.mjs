import assert from 'node:assert/strict';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const port = await findAvailablePort();
const baseUrl = `http://127.0.0.1:${port}`;

async function findAvailablePort() {
  return await new Promise((resolve, reject) => {
    const probe = createServer();
    probe.unref();
    probe.on('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const address = probe.address();
      if (!address || typeof address === 'string') {
        probe.close(() => reject(new Error('Failed to acquire an open port.')));
        return;
      }
      const openPort = address.port;
      probe.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(openPort);
      });
    });
  });
}

async function waitForServer() {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      const response = await fetch(baseUrl, { cache: 'no-store' });
      if (response.ok) {
        return;
      }
    } catch (_) {
      // Retry.
    }
    await delay(250);
  }
  throw new Error('Local PWA server failed to start.');
}

function startServer() {
  const httpServerBin = resolve(
    root,
    'node_modules/.bin/http-server' + (process.platform === 'win32' ? '.cmd' : ''),
  );

  return spawn(
    httpServerBin,
    ['.', '-p', String(port), '-c-1', '--silent'],
    {
      cwd: root,
      stdio: 'ignore',
    },
  );
}

let server = startServer();

try {
  await waitForServer();
  console.log(`Serving COOL PWA at ${baseUrl}`);

  mkdirSync(resolve(root, '../../output/playwright'), { recursive: true });

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();
  page.setDefaultTimeout(15_000);

  console.log('Step 1: load admin entry and activate service worker');
  await page.goto(`${baseUrl}/admin/`, { waitUntil: 'networkidle' });
  await page.evaluate(() => navigator.serviceWorker?.ready.then(() => true));
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForFunction(() => Boolean(navigator.serviceWorker?.controller));
  await page.screenshot({ path: resolve(root, '../../output/playwright/cool-pwa-home.png'), fullPage: true });

  console.log('Step 2: run accessibility audit');
  const a11y = await new AxeBuilder({ page }).withTags([
    'wcag2a',
    'wcag2aa',
    'wcag21aa',
    'wcag22aa',
  ]).analyze();
  assert.equal(
    a11y.violations.length,
    0,
    `Accessibility violations:\n${a11y.violations.map((violation) => violation.id).join('\n')}`,
  );

  console.log('Step 3: queue offline-safe group action');
  await page.goto(`${baseUrl}/groups/`, { waitUntil: 'domcontentloaded' });
  await page.fill('#group-name', 'Kigali Savings Circle');
  await page.fill('#pledge-amount', '25000');
  await page.fill('#pledge-phone', '+250788123456');
  await page.fill('#pledge-date', '2026-04-05');
  await page.fill('#pledge-note', 'Monthly contribution queued for offline replay.');
  await page.click('button[type="submit"]');

  const queueCount = await page.evaluate(async () => {
    const request = indexedDB.open('cool-pwa-db');
    const db = await new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    return await new Promise((resolve, reject) => {
      const tx = db.transaction('queue', 'readonly');
      const countRequest = tx.objectStore('queue').count();
      countRequest.onsuccess = () => resolve(countRequest.result);
      countRequest.onerror = () => reject(countRequest.error);
    });
  });
  assert.ok(queueCount >= 1, 'Queued action should be persisted to IndexedDB.');

  console.log('Step 4: prove cached route shells and offline fallback are stored');
  await page.goto(`${baseUrl}/home/`, { waitUntil: 'networkidle' });
  await page.waitForSelector('text=Cached dashboard');

  server.kill('SIGTERM');
  await delay(500);
  const offlineProof = await page.evaluate(async () => {
    const home = await caches.match('/home/');
    const offline = await caches.match('/offline/');
    return {
      homeText: home ? await home.text() : null,
      offlineText: offline ? await offline.text() : null,
    };
  });
  assert.match(offlineProof.homeText ?? '', /Cached dashboard/, 'Home route shell should be present in cache.');
  assert.match(offlineProof.offlineText ?? '', /You are still inside COOL/, 'Custom offline fallback should be present in cache.');

  console.log('Step 5: restore server and verify notifications + theming');
  server = startServer();
  await waitForServer();
  await context.grantPermissions(['notifications'], { origin: baseUrl });
  await page.goto(`${baseUrl}/notifications/`, { waitUntil: 'networkidle' });
  if (await page.locator('[data-enable-notifications]').isVisible()) {
    await page.click('[data-enable-notifications]');
  }
  const notificationStatus = await page.locator('[data-notification-status]').textContent();
  assert.ok(
    ['Enabled', 'Blocked', 'Not enabled'].includes(notificationStatus?.trim() ?? ''),
    `Unexpected notification status: ${notificationStatus}`,
  );
  await page.click('[data-demo-notification]');
  await page.waitForFunction(async () => {
    const badgeCount = document.querySelector('[data-badge-count]')?.textContent?.trim();
    const request = indexedDB.open('cool-pwa-db');
    const db = await new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const notificationCount = await new Promise((resolve, reject) => {
      const tx = db.transaction('notifications', 'readonly');
      const countRequest = tx.objectStore('notifications').count();
      countRequest.onsuccess = () => resolve(countRequest.result);
      countRequest.onerror = () => reject(countRequest.error);
    });
    return badgeCount === '1' && notificationCount >= 1;
  });

  await page.goto(`${baseUrl}/profile/`, { waitUntil: 'networkidle' });
  await page.click('[data-theme-toggle]');
  const theme = await page.evaluate(() => document.documentElement.dataset.theme);
  assert.ok(theme === 'light' || theme === 'dark', 'Theme toggle should set a valid theme.');

  console.log('Step 6: browser verification passed');
  await browser.close();
} finally {
  server?.kill('SIGTERM');
}
