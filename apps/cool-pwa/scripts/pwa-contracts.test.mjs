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
  assert.equal(manifest.start_url, '/?source=pwa');
  assert.ok(Array.isArray(manifest.shortcuts) && manifest.shortcuts.length === 4);
  assert.ok(Array.isArray(manifest.screenshots) && manifest.screenshots.length >= 2);
  assert.ok(manifest.share_target);
  assert.ok(
    manifest.icons.some((icon) => icon.purpose === 'maskable'),
    'maskable icon required',
  );
  assert.ok(
    manifest.icons.some((icon) => icon.sizes === '1024x1024'),
    '1024 icon required',
  );
});

test('core pages expose metadata and manifest wiring', () => {
  for (const page of [
    'index.html',
    'home/index.html',
    'groups/index.html',
    'momo/index.html',
    'profile/index.html',
    'notifications/index.html',
    'install/index.html',
  ]) {
    const html = read(page);
    assert.match(html, /<title>.+<\/title>/);
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

test('robots and sitemap are configured for discovery', () => {
  const robots = read('robots.txt');
  const sitemap = read('sitemap.xml');
  assert.match(robots, /Allow:\s+\//);
  assert.match(robots, /Disallow:\s+\/admin\//);
  assert.match(robots, /Sitemap:\s+https:\/\/cool\.ikanisa\.com\/sitemap\.xml/);
  assert.match(sitemap, /https:\/\/cool\.ikanisa\.com\/home\//);
  assert.match(sitemap, /https:\/\/cool\.ikanisa\.com\/notifications\//);
});

test('utility routes are intentionally crawler-controlled', () => {
  const admin = read('admin/index.html');
  const share = read('share/index.html');
  const offline = read('offline/index.html');

  assert.match(admin, /meta name="robots" content="noindex,nofollow"/);
  assert.match(share, /meta name="robots" content="noindex,nofollow"/);
  assert.match(offline, /meta name="robots" content="noindex,nofollow"/);
  assert.match(offline, /You are still inside COOL/);
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

test('landing page carries software application structured data', () => {
  const html = read('index.html');
  assert.match(html, /application\/ld\+json/);
  assert.match(html, /SoftwareApplication/);
  assert.match(html, /FinanceApplication/);
  assert.match(html, /https:\/\/cool\.ikanisa\.com\//);
});

test('cloudflare deployment routing keeps the landing on cool and admin on acool', () => {
  const wrangler = read('wrangler.toml');
  const fn = read('functions/index.js');
  const headers = read('_headers');
  const admin = read('admin/index.html');
  const landing = read('landing/index.html');

  assert.match(wrangler, /name\s*=\s*"cool"/);
  assert.match(wrangler, /pages_build_output_dir\s*=\s*"\."/);
  assert.match(fn, /acool\.ikanisa\.com/);
  assert.match(fn, /\/landing\//);
  assert.match(fn, /\/admin\//);
  assert.match(headers, /fonts\.googleapis\.com/);
  assert.match(headers, /\/landing-assets\/\*/);
  assert.match(headers, /Strict-Transport-Security:/);
  assert.match(headers, /Content-Security-Policy:/);
  assert.match(admin, /https:\/\/acool\.ikanisa\.com\//);
  assert.match(landing, /Community Finance & Mobility for Rwanda/);
  assert.match(landing, /\/landing-assets\/icon\.png/);
});
