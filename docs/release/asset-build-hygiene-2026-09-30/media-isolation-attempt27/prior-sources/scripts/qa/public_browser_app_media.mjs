#!/usr/bin/env node
// Genuine current Flutter route captures. No invented phone UI or image edits.
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {mkdir, readFile, readdir, writeFile, stat} from 'node:fs/promises';
import {dirname, extname, join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
// Compile from an explicit immutable export when other work is active in the
// checkout. Generated bindings belong to that export, not the original tree.
const sourceRoot = resolve(process.env.COLLECT_MEDIA_SOURCE || root);
if (sourceRoot !== root && sourceRoot.startsWith(root + '/')) {
  throw Error('An immutable media source export must be outside the checkout.');
}
const out = resolve(process.argv[2] || '');
if (!process.argv[2] || !out.startsWith(join(root, '.cache') + '/')) {
  throw Error('Fresh repository-local .cache output required.');
}
await mkdir(dirname(out), {recursive: true});
await mkdir(out, {recursive: false});
const flutter = process.env.FLUTTER || 'flutter';
const chrome = process.env.COLLECT_MEDIA_CHROME;
if (!chrome) throw Error('Explicit locally installed Chromium executable required.');
const playwright = await import(process.env.PLAYWRIGHT_CORE_PATH || '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js');
const {chromium} = playwright.chromium ? playwright : playwright.default;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
async function files(directory, excluded = new Set()) {
  const paths = [];
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    if (entry.name.startsWith('.') || entry.name.includes('GeneratedPluginRegistrant') || excluded.has(entry.name)) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) paths.push(...await files(path, excluded));
    else if (entry.isFile()) paths.push(path);
    else throw Error('Unsupported source path: ' + relative(root, path));
  }
  return paths;
}
async function sourceSnapshot() {
  const paths = [];
  for (const name of ['lib', 'assets', 'android/app/src', 'ios/Runner']) paths.push(...await files(join(sourceRoot, name)));
  for (const name of ['third_party/file_saver', 'third_party/gotrue', 'third_party/firebase_messaging']) {
    paths.push(...await files(join(sourceRoot, name), new Set(['build', '__pycache__'])));
  }
  paths.push(...['.fvmrc', 'pubspec.yaml', 'pubspec.lock', 'web/index.html', 'web/manifest.json',
    'tool/public_app_media_capture.dart', 'test/fixtures/collect_repository_fixture.dart',
    'analysis_options.yaml',
    'third_party/file_saver/pubspec.yaml', 'third_party/file_saver/LICENSE', 'third_party/file_saver/COLLECT_FORK.md',
    'third_party/gotrue/pubspec.yaml', 'third_party/gotrue/LICENSE', 'third_party/gotrue/COLLECT_FORK.md', 'third_party/gotrue/UPSTREAM-SHA256.json',
    'third_party/firebase_messaging/pubspec.yaml', 'third_party/firebase_messaging/LICENSE', 'third_party/firebase_messaging/COLLECT_FORK.md', 'third_party/firebase_messaging/UPSTREAM-SHA256.json',
    'scripts/public_app_media.rb'].map(p => join(sourceRoot, p)));
  return Object.fromEntries(await Promise.all([...new Set(paths)].sort().map(async p => [relative(sourceRoot, p), hash(await readFile(p))])));
}
async function bindingSnapshot() {
  return Object.fromEntries(await Promise.all(['.dart_tool/package_config.json', '.flutter-plugins-dependencies']
    .map(async name => [name, hash(await readFile(join(sourceRoot, name)))])));
}
async function runtime(name, cwd = sourceRoot) {
  const result = await command(name, 'ruby', ['-r', './scripts/public_app_media', '-e', 'puts PublicAppMedia.new(Dir.pwd).runtime_fingerprint'], cwd);
  return result.trim();
}
const report = {schema_version: 1, kind: 'browser_flutter_fixture', status: 'running',
  scope: 'Current Collect Flutter interface previews at seven real routes with synthetic data; browser rendering only, no native or release acceptance.',
  source_snapshot_scope: 'Declared exported runtime/native/asset sources, capture fixture, all three regular vendored package source trees and license/provenance; generated package/plugin bindings recorded separately for the actual compilation directory; no complete installed SDK/cache attestation.',
  source_root: sourceRoot, isolated_source_export: sourceRoot !== root,
  capture_recorder_sha256: hash(await readFile(fileURLToPath(import.meta.url))),
  started_at: new Date().toISOString(), sources_before: await sourceSnapshot(), commands: [], captures: [],
  external_requests: [], blocked_engine_font_requests: [], served_resources: {}, errors: [], native_capture_passed: false,
  provider_calls: 0, hosted_calls: 0, database_calls: 0};
report.remote_resources_blocked_before_http = true;
async function command(name, executable, args, cwd = sourceRoot) {
  const stdout = [], stderr = [];
  const child = spawn(executable, args, {cwd, env: process.env, stdio: ['ignore', 'pipe', 'pipe']});
  child.stdout.on('data', bytes => stdout.push(bytes)); child.stderr.on('data', bytes => stderr.push(bytes));
  const code = await new Promise((yes, no) => {child.once('error', no); child.once('exit', yes);});
  const output = Buffer.concat(stdout), error = Buffer.concat(stderr);
  await writeFile(join(out, name + '.stdout'), output); await writeFile(join(out, name + '.stderr'), error);
  report.commands.push({name, executable, args, cwd, exit_code: code, stdout_sha256: hash(output), stderr_sha256: hash(error)});
  if (code !== 0) throw Error(name + ' failed: ' + code);
  return output.toString('utf8');
}
const routes = [
  ['home', '/home', 'RWF 35,000'],
  ['groups', '/groups', 'Groups'],
  ['group-detail', '/groups/qa-private-group', 'QA private group'],
  ['security', '/settings/security', 'Approve payments in MoMo'],
  ['privacy', '/settings/legal/privacy', 'Data we collect'],
  ['terms', '/settings/legal/terms', 'Using Collect'],
  ['account-deletion', '/settings/account/delete', 'Select a reason to submit.'],
];
const mime = {'.html':'text/html', '.js':'text/javascript', '.json':'application/json', '.wasm':'application/wasm', '.png':'image/png', '.webp':'image/webp', '.ttf':'font/ttf', '.otf':'font/otf', '.woff2':'font/woff2', '.css':'text/css'};
let server, browser;
const build = join(out, 'build');
try {
  report.runtime_before_sha256 = await runtime('runtime-fingerprint-before');
  report.checkout_runtime_before_sha256 = await runtime('checkout-runtime-fingerprint-before', root);
  if (report.runtime_before_sha256 !== report.checkout_runtime_before_sha256) throw Error('Source export differs from current runtime before capture');
  report.generated_bindings_before = await bindingSnapshot();
  report.flutter = JSON.parse(await command('flutter-version', flutter, ['--version', '--machine']));
  const pinnedFlutter = JSON.parse(await readFile(join(sourceRoot, '.fvmrc'), 'utf8')).flutter;
  if (report.flutter.flutterVersion !== pinnedFlutter) throw Error('Flutter SDK differs from .fvmrc pin; select the exact SDK with FLUTTER.');
  await command('flutter-build', flutter, ['build', 'web', '--release', '--no-pub', '--no-wasm-dry-run', '--no-web-resources-cdn', '--target=tool/public_app_media_capture.dart', '--dart-define=COLLECT_PUBLIC_MEDIA_CAPTURE=true', '--output=' + build]);
  report.build_files = Object.fromEntries(await Promise.all((await files(build)).sort().map(async p => [relative(build, p), hash(await readFile(p))])));
  report.build_manifest_sha256 = hash(Buffer.from(JSON.stringify(report.build_files)));
  server = createServer(async (request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
      const candidate = resolve(build, '.' + (pathname === '/' ? '/index.html' : pathname));
      if (!candidate.startsWith(build + '/')) throw Error('Invalid path');
      const bytes = await readFile(candidate);
      response.writeHead(200, {'content-type': mime[extname(candidate)] || 'application/octet-stream', 'cache-control': 'no-store'}); response.end(bytes);
    } catch {response.writeHead(404); response.end();}
  });
  await new Promise(yes => server.listen(0, '127.0.0.1', yes));
  const origin = 'http://127.0.0.1:' + server.address().port;
  report.capture_origin = origin; report.browser_executable_sha256 = hash(await readFile(chrome));
  browser = await chromium.launch({executablePath: chrome, headless: true, args: ['--disable-background-networking', '--disable-component-update', '--disable-sync']});
  report.browser_version = browser.version();
  await mkdir(join(out, 'screenshots'));
  for (const [id, route, marker] of routes) {
    const context = await browser.newContext({viewport: {width: 390, height: 844}, deviceScaleFactor: 3, colorScheme: 'dark', reducedMotion: 'reduce', locale: 'en-US'});
    const pending = [];
    await context.route('**/*', request => {
      if (new URL(request.request().url()).origin === origin) return request.continue();
      const url = request.request().url();
      // Flutter's renderer attempts its built-in Roboto fallback even when the
      // app's own bundled fonts render these screens. Intercept before HTTP;
      // no remote font bytes or substitute font are supplied to the app.
      if (url === 'https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2') report.blocked_engine_font_requests.push(url);
      else report.external_requests.push(url);
      return request.abort();
    });
    const page = await context.newPage();
    page.on('pageerror', error => report.errors.push({id, message: error.message}));
    page.on('response', response => {
      if (response.status() !== 200 || new URL(response.url()).origin !== origin) return;
      pending.push((async () => {
        const path = decodeURIComponent(new URL(response.url()).pathname).replace(/^\//, '') || 'index.html';
        const actual = hash(await response.body());
        if (report.build_files[path] !== actual) throw Error('Served resource differs: ' + path);
        report.served_resources[path] = actual;
      })());
    });
    await page.goto(origin + '/#' + route, {waitUntil: 'networkidle', timeout: 90000});
    await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder') || document.querySelectorAll('flt-semantics').length > 5, null, {timeout: 90000});
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForFunction(marker => [...document.querySelectorAll('flt-semantics')].some(node => {
      const rect = node.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0 &&
        ((node.getAttribute('aria-label') || '') + node.textContent).includes(marker);
    }), marker, {timeout: 30000});
    await page.waitForTimeout(1800);
    if (new URL(page.url()).hash !== '#' + route || await page.title() !== 'Collect') throw Error('Wrong route or title: ' + id);
    const capture = join(out, 'screenshots', id + '.png');
    await page.screenshot({path: capture, animations: 'disabled', fullPage: false});
    const bytes = await readFile(capture), width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
    if (width !== 1170 || height !== 2532 || bytes.length < 8001) throw Error('Invalid capture dimensions: ' + id);
    await Promise.all(pending);
    report.captures.push({id, app_route: route, marker, marker_verified: true, path: relative(root, capture), sha256: hash(bytes), bytes: bytes.length, width, height, platform: 'Chromium browser', theme: 'dark', text_scale: 1, data: 'synthetic example data'});
    await context.close(); console.log(id + ' captured');
  }
  if (report.errors.length || report.external_requests.length || !report.served_resources['main.dart.js']) throw Error('Browser errors, outbound requests or missing served application proof');
  report.runtime_after_sha256 = await runtime('runtime-fingerprint-after'); report.sources_after = await sourceSnapshot();
  report.checkout_runtime_after_sha256 = await runtime('checkout-runtime-fingerprint-after', root);
  report.generated_bindings_after = await bindingSnapshot();
  report.generated_bindings_unchanged = JSON.stringify(report.generated_bindings_before) === JSON.stringify(report.generated_bindings_after);
  if (report.checkout_runtime_after_sha256 !== report.runtime_after_sha256 ||
      !report.generated_bindings_unchanged ||
      report.capture_recorder_sha256 !== hash(await readFile(fileURLToPath(import.meta.url)))) {
    throw Error('Checkout runtime, generated bindings or recorder changed during capture');
  }
  report.sources_unchanged = JSON.stringify(report.sources_before) === JSON.stringify(report.sources_after);
  if (!report.sources_unchanged || report.runtime_before_sha256 !== report.runtime_after_sha256) throw Error('Source changed during capture');
  if (new Set(report.captures.map(c => c.sha256)).size !== 7) throw Error('Repeated route image');
  report.status = 'captured_pending_visual_review';
} catch (error) {
  report.status = 'fail'; report.failure = error.message; process.exitCode = 1;
} finally {
  await browser?.close(); if (server) await new Promise(yes => server.close(yes));
  report.finished_at = new Date().toISOString();
  await writeFile(join(out, 'capture-report.json'), JSON.stringify(report, null, 2) + '\n');
}
