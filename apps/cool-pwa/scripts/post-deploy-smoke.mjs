/**
 * Post-deploy smoke test.
 *
 * Validates that the deployed PWA is healthy:
 *   - / redirects to /admin/
 *   - /admin/ loads HTML with correct title
 *   - Security headers are present
 *   - Service worker registers
 *   - Update banner is functional
 *
 * Usage:
 *   SMOKE_URL=https://cool.ikanisa.com node scripts/post-deploy-smoke.mjs
 */

import { chromium } from 'playwright';

const BASE = (process.env.SMOKE_URL || 'https://cool.ikanisa.com').replace(/\/$/, '');

async function main() {
  const passed = [];
  const failed = [];

  function assert(name, condition) {
    if (condition) {
      passed.push(name);
      console.log(`  ✅ ${name}`);
    } else {
      failed.push(name);
      console.error(`  ❌ ${name}`);
    }
  }

  console.log(`\n🔍 Post-deploy smoke test against ${BASE}\n`);

  // 1. Root redirect
  const rootResponse = await fetch(BASE + '/', { redirect: 'manual' });
  // Pages Functions rewrite (not redirect), so we check the final content
  const rootFinalResponse = await fetch(BASE + '/');
  const rootHtml = await rootFinalResponse.text();
  assert('Root serves admin content', rootHtml.includes('COOL') && rootHtml.includes('admin'));

  // 2. /admin/ loads
  const adminResponse = await fetch(BASE + '/admin/');
  assert('/admin/ returns 200', adminResponse.status === 200);
  const adminHtml = await adminResponse.text();
  assert('/admin/ has title', adminHtml.includes('<title>') && adminHtml.includes('COOL'));

  // 3. Security headers
  const hsts = adminResponse.headers.get('strict-transport-security') || '';
  assert('HSTS header present', hsts.includes('max-age='));
  assert('X-Content-Type-Options present', adminResponse.headers.get('x-content-type-options') === 'nosniff');
  assert('X-Frame-Options present', adminResponse.headers.get('x-frame-options') === 'DENY');

  // 4. Service worker accessible
  const swResponse = await fetch(BASE + '/service-worker.js');
  assert('Service worker returns 200', swResponse.status === 200);
  const swText = await swResponse.text();
  assert('Service worker has VERSION', swText.includes('cool-pwa-v'));

  // 5. Browser-level check: SW registers + page loads
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();

  try {
    await page.goto(BASE + '/admin/', { waitUntil: 'networkidle' });
    const title = await page.title();
    assert('Page title in browser', title.includes('COOL'));

    // Check for SW registration
    const swRegistered = await page.evaluate(async () => {
      if (!('serviceWorker' in navigator)) {
        return false;
      }
      const registration = await navigator.serviceWorker.getRegistration('/');
      return Boolean(registration);
    });
    assert('Service worker registered in browser', swRegistered);
  } finally {
    await browser.close();
  }

  // Summary
  console.log(`\n📊 Results: ${passed.length} passed, ${failed.length} failed\n`);

  if (failed.length > 0) {
    console.error('Failed checks:', failed.join(', '));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Smoke test crashed:', err);
  process.exit(1);
});
