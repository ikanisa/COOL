import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function read(path) {
  return readFileSync(resolve(root, path), 'utf8');
}

test('manifest is installable and rich', () => {
  const manifest = JSON.parse(read('manifest.webmanifest'));
  assert.equal(manifest.display, 'standalone');
  assert.equal(manifest.start_url, '/admin/?source=pwa');
  assert.equal(manifest.scope, '/admin/');
  assert.ok(Array.isArray(manifest.shortcuts) && manifest.shortcuts.length === 5);
  assert.ok(Array.isArray(manifest.screenshots) && manifest.screenshots.length >= 2);
  assert.ok(
    manifest.icons.some((icon) => icon.purpose === 'maskable'),
    'maskable icon required',
  );
  assert.ok(
    manifest.icons.some((icon) => icon.sizes === '1024x1024'),
    '1024 icon required',
  );
});

test('admin pages expose metadata and manifest wiring', () => {
  for (const page of [
    'admin/index.html',
    'admin/platform/index.html',
    'admin/users/index.html',
    'admin/app-config/index.html',
    'admin/operations/index.html',
    'admin/roles/index.html',
    'admin/analytics/index.html',
    'admin/audit-log/index.html',
    'admin/groups/index.html',
  ]) {
    const html = read(page);
    assert.match(html, /<title>.+<\/title>/);
    assert.match(html, /meta name="robots" content="noindex,nofollow"/);
    assert.match(html, /meta name="description"/);
    assert.match(html, /meta name="theme-color"/);
    assert.match(html, /apple-mobile-web-app-capable/);
    assert.match(html, /apple-touch-icon/);
    assert.match(html, /twitter:card/);
    assert.match(html, /og:image/);
    assert.match(html, /link rel="manifest" href="\/manifest\.webmanifest"/);
    assert.match(html, /link rel="canonical"/);
  }
});

test('robots and sitemap describe the admin-only route tree', () => {
  const robots = read('robots.txt');
  const sitemap = read('sitemap.xml');
  assert.match(robots, /Disallow:\s+\//);
  assert.match(robots, /Sitemap:\s+https:\/\/cool\.ikanisa\.com\/sitemap\.xml/);
  assert.match(sitemap, /https:\/\/cool\.ikanisa\.com\/admin\/platform\//);
  assert.match(sitemap, /https:\/\/cool\.ikanisa\.com\/admin\/operations\//);
});

test('offline and admin routes are intentionally crawler-controlled', () => {
  const admin = read('admin/index.html');
  const command = read('admin/platform/index.html');
  const offline = read('admin/offline/index.html');

  assert.match(admin, /meta name="robots" content="noindex,nofollow"/);
  assert.match(command, /meta name="robots" content="noindex,nofollow"/);
  assert.match(offline, /meta name="robots" content="noindex,nofollow"/);
  assert.match(offline, /You are still inside the COOL admin console/);
});

test('service worker covers offline, sync, periodic refresh, and push', () => {
  const sw = read('service-worker.js');
  for (const required of [
    "addEventListener('install'",
    "addEventListener('activate'",
    "addEventListener('fetch'",
    "addEventListener('sync'",
    "addEventListener('periodicsync'",
    "addEventListener('push'",
    "addEventListener('notificationclick'",
    'DOWNLOAD_OFFLINE',
  ]) {
    assert.match(sw, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
});

test('styles enforce accessibility and PWA polish', () => {
  const css = read('assets/css/app.css');
  assert.match(css, /:focus-visible/);
  assert.match(css, /prefers-reduced-motion: reduce/);
  assert.match(css, /min-height:\s*48px/);
  assert.match(css, /font-display:\s*swap/);
  assert.match(css, /@view-transition/);
});

test('root route redirects to the admin workspace', () => {
  const html = read('index.html');
  assert.match(html, /http-equiv="refresh"/);
  assert.match(html, /url=\/admin\//);
});

test('cloudflare deployment routing keeps the app admin-only', () => {
  const wrangler = read('wrangler.toml');
  const fn = read('functions/index.js');
  const headers = read('_headers');
  const admin = read('admin/index.html');

  assert.match(wrangler, /name\s*=\s*"cool"/);
  assert.match(wrangler, /pages_build_output_dir\s*=\s*"\."/);
  assert.match(fn, /\/admin\//);
  assert.doesNotMatch(fn, /\/landing\//);
  assert.match(headers, /\/admin\/\*/);
  assert.match(headers, /Strict-Transport-Security:/);
  assert.match(headers, /Content-Security-Policy:/);
  assert.match(admin, /https:\/\/cool\.ikanisa\.com\/admin\//);
});
