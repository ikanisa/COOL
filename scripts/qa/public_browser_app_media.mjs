#!/usr/bin/env node
// Genuine current Flutter route captures. No invented phone UI or image edits.
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {mkdir, readFile, readdir, writeFile, stat, realpath, cp} from 'node:fs/promises';
import {dirname, extname, join, relative, resolve, basename} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {observeCollectDiagnostics, collectDiagnosticSourceSnapshot} from './collect_diagnostic_observer.mjs';

const root = await realpath(resolve(dirname(fileURLToPath(import.meta.url)), '../..'));
// Compile from an explicit immutable export when other work is active in the
// checkout. Generated bindings belong to that export, not the original tree.
const sourceRoot = resolve(process.env.COLLECT_MEDIA_SOURCE || root);
if (await realpath(sourceRoot) !== sourceRoot || (sourceRoot !== root && sourceRoot.startsWith(root + '/'))) {
  throw Error('An immutable media source export must be outside the checkout.');
}
let out = resolve(process.argv[2] || '');
if (!process.argv[2] || !out.startsWith(join(root, '.cache') + '/')) {
  throw Error('Fresh repository-local .cache output required.');
}
await mkdir(dirname(out), {recursive: true});
const canonicalParent = await realpath(dirname(out));
const canonicalCache = await realpath(join(root, '.cache'));
if (!canonicalCache.startsWith(root + '/') ||
    !(canonicalParent === canonicalCache || canonicalParent.startsWith(canonicalCache + '/'))) {
  throw Error('Capture output escapes the repository cache through a symlink.');
}
out = join(canonicalParent, basename(out));
await mkdir(out, {recursive: false});
const flutter = process.env.FLUTTER || 'flutter';
const chrome = process.env.COLLECT_MEDIA_CHROME;
if (!chrome) throw Error('Explicit locally installed Chromium executable required.');
const playwright = await import(process.env.PLAYWRIGHT_CORE_PATH || '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js');
const {chromium} = playwright.chromium ? playwright : playwright.default;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
// BEGIN strict served-resource observer (also exercised by local regressions).
function serveVerifiedLocalResource(route, origin, buildFiles, servedResources, errors, pending, id) {
  let path = null;
  const observation = (async () => {
    const url = new URL(route.request().url());
    if (url.origin !== origin) throw Error('Resource observation refuses remote HTTP');
    path = decodeURIComponent(url.pathname).replace(/^\//, '') || 'index.html';
    // Read the real loopback HTTP response before delivering those exact bytes
    // to Chromium. CDP body handles can expire during Flutter hash navigation.
    // Redirects remain disabled so the API request cannot escape loopback.
    const response = await route.fetch({maxRedirects: 0, timeout: 90000});
    const bytes = await response.body();
    if (response.status() >= 300 && response.status() < 400) throw Error('Local redirect refused');
    if (response.status() === 200) {
      const actual = hash(bytes);
      if (buildFiles[path] !== actual) throw Error('Served resource differs: ' + path);
      servedResources[path] = actual;
    }
    await route.fulfill({response, body: bytes});
  })().catch(error => {
    errors.push({id, resource: path, message: 'Served resource observation failed: ' + error.message});
    // The context can close while an in-flight request is failing. Attach this
    // handler immediately too, so the failed report always reaches finally.
    return Promise.resolve().then(() => route.abort()).catch(() => {});
  });
  pending.push(observation);
  return observation;
}
// END strict served-resource observer.
// BEGIN strict reusable compilation contract (also exercised by regressions).
function assertReusableCompilation(previous, sources, bindings, version, expectedSourceRoot, observerSources) {
  if (previous.kind !== 'browser_flutter_fixture' || previous.runtime_fingerprint_version !== 4 ||
      previous.browser_entrypoint !== 'tool/public_app_media_capture.dart' ||
      previous.source_root !== expectedSourceRoot ||
      !['fail', 'captured_pending_visual_review'].includes(previous.status) ||
      JSON.stringify(previous.sources_before) !== JSON.stringify(sources) ||
      !observerSources || !observerSources['scripts/qa/collect_diagnostic_observer.mjs'] ||
      JSON.stringify(previous.diagnostic_observer_sources_before) !== JSON.stringify(observerSources) ||
      JSON.stringify(previous.diagnostic_observer_sources_after) !== JSON.stringify(observerSources) ||
      JSON.stringify(previous.generated_bindings_before) !== JSON.stringify(bindings) ||
      JSON.stringify(previous.flutter) !== JSON.stringify(version)) throw Error('Reusable compilation source/toolchain binding differs');
  const builds = previous.commands.filter(row => row.name === 'flutter-build');
  if (builds.length !== 1 || builds[0].exit_code !== 0 || builds[0].cwd !== expectedSourceRoot ||
      builds[0].args.length !== 9 || JSON.stringify(builds[0].args.slice(0, 8)) !== JSON.stringify([
        'build', 'web', '--release', '--no-pub', '--no-wasm-dry-run', '--no-web-resources-cdn',
        '--target=tool/public_app_media_capture.dart', '--dart-define=COLLECT_PUBLIC_MEDIA_CAPTURE=true']) || !builds[0].args.at(-1).startsWith('--output=')) {
    throw Error('Reusable compilation command is absent or changed');
  }
  if (Object.keys(previous.build_files || {}).length < 2 || !previous.build_files['main.dart.js'] ||
      !previous.build_files['flutter_bootstrap.js'] ||
      hash(Buffer.from(JSON.stringify(previous.build_files))) !== previous.build_manifest_sha256) {
    throw Error('Reusable compilation artifact map is missing or changed');
  }
  return builds[0];
}
// END strict reusable compilation contract.

// BEGIN strict loopback media bootstrap configuration (tested directly).
function configureLoopbackMediaBootstrap(original, assetBase) {
  if (assetBase !== '/') throw Error('Media fixture asset base must be the loopback root');
  const asset = "var adminAssetBase = '__COLLECT_ADMIN_ASSET_BASE__';";
  const worker = "var adminServiceWorkerVersion = '__COLLECT_ADMIN_SW_VERSION__';";
  const markers = original.match(/__COLLECT_ADMIN_[A-Z_]+__/g) || [];
  if (markers.length !== 2 || original.split(asset).length !== 2 || original.split(worker).length !== 2 ||
      (original.match(/\badminAssetBase\s*=/g) || []).length !== 1 ||
      (original.match(/\badminServiceWorkerVersion\s*=/g) || []).length !== 1 ||
      !original.includes('entrypointBaseUrl: adminAssetBase') ||
      !original.includes('assetBase: adminAssetBase') ||
      !original.includes("canvasKitBaseUrl: adminAssetBase + 'canvaskit/'")) {
    throw Error('Missing or unexpected Admin bootstrap substitution contract');
  }
  return original.replace(asset, "var adminAssetBase = '/';")
    .replace(worker, "var adminServiceWorkerVersion = '';");
}
// END strict loopback media bootstrap configuration.


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
async function broaderSourceSnapshot(base = sourceRoot) {
  const paths = [];
  for (const name of ['lib', 'assets', 'android/app/src', 'ios/Runner']) paths.push(...await files(join(base, name)));
  for (const name of ['third_party/file_saver', 'third_party/gotrue', 'third_party/firebase_messaging']) {
    paths.push(...await files(join(base, name), new Set(['build', '__pycache__'])));
  }
  paths.push(...['.fvmrc', 'pubspec.yaml', 'pubspec.lock', 'web/index.html', 'web/manifest.json',
    'tool/public_app_media_capture.dart', 'test/fixtures/collect_repository_fixture.dart',
    'analysis_options.yaml',
    'third_party/file_saver/pubspec.yaml', 'third_party/file_saver/LICENSE', 'third_party/file_saver/COLLECT_FORK.md',
    'third_party/gotrue/pubspec.yaml', 'third_party/gotrue/LICENSE', 'third_party/gotrue/COLLECT_FORK.md', 'third_party/gotrue/UPSTREAM-SHA256.json',
    'third_party/firebase_messaging/pubspec.yaml', 'third_party/firebase_messaging/LICENSE', 'third_party/firebase_messaging/COLLECT_FORK.md', 'third_party/firebase_messaging/UPSTREAM-SHA256.json',
    'scripts/public_app_media.rb', 'scripts/qa/asset_manifest_integrity.rb'].map(p => join(base, p)));
  return Object.fromEntries(await Promise.all([...new Set(paths)].sort().map(async p => [relative(base, p), hash(await readFile(p))])));
}
async function sourceSnapshot(base = sourceRoot) {
  const child = spawn('ruby', ['-r', './scripts/public_app_media', '-e',
    'puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)'],
    {cwd: base, env: process.env, stdio: ['ignore', 'pipe', 'pipe']});
  const stdout = [], stderr = [];
  child.stdout.on('data', bytes => stdout.push(bytes));
  child.stderr.on('data', bytes => stderr.push(bytes));
  const code = await new Promise((yes, no) => {child.once('error', no); child.once('exit', yes);});
  if (code !== 0) throw Error('Conservative browser source closure failed: ' + Buffer.concat(stderr).toString('utf8'));
  return JSON.parse(Buffer.concat(stdout).toString('utf8'));
}
async function bindingSnapshot() {
  return Object.fromEntries(await Promise.all(['.dart_tool/package_config.json', '.flutter-plugins-dependencies']
    .map(async name => [name, hash(await readFile(join(sourceRoot, name)))])));
}
async function validateBindingTargets() {
  const configPath = join(sourceRoot, '.dart_tool/package_config.json');
  const config = JSON.parse(await readFile(configPath, 'utf8'));
  const expected = {collect_app: sourceRoot, file_saver: join(sourceRoot, 'third_party/file_saver'),
    gotrue: join(sourceRoot, 'third_party/gotrue'), firebase_messaging: join(sourceRoot, 'third_party/firebase_messaging')};
  if (!Array.isArray(config.packages)) throw Error('Resolved package bindings are malformed');
  const observed = {};
  for (const [name, target] of Object.entries(expected)) {
    const rows = config.packages.filter(row => row.name === name);
    if (rows.length !== 1 || typeof rows[0].rootUri !== 'string') throw Error('Required local package binding missing: ' + name);
    const url = new URL(rows[0].rootUri, pathToFileURL(configPath));
    if (url.protocol !== 'file:' || url.hostname || url.search || url.hash ||
        await realpath(fileURLToPath(url)) !== target || await realpath(target) !== target) {
      throw Error('Local package binding points outside its declared export: ' + name);
    }
    observed[name] = target;
  }
  const plugins = JSON.parse(await readFile(join(sourceRoot, '.flutter-plugins-dependencies'), 'utf8'));
  if (!plugins.plugins || typeof plugins.plugins !== 'object' || Array.isArray(plugins.plugins)) throw Error('Resolved plugin bindings are malformed');
  const found = new Set();
  for (const rows of Object.values(plugins.plugins)) {
    if (!Array.isArray(rows)) throw Error('Resolved plugin platform bindings are malformed');
    for (const row of rows) {
      if (!['file_saver', 'firebase_messaging'].includes(row.name)) continue;
      if (typeof row.path !== 'string' || !row.path.startsWith('/') || await realpath(row.path) !== expected[row.name]) {
        throw Error('Local plugin binding points outside its declared export: ' + row.name);
      }
      found.add(row.name);
    }
  }
  if (found.size !== 2) throw Error('Required local plugin bindings are missing');
  return observed;
}
async function runtime(name, cwd = sourceRoot) {
  const result = await command(name, 'ruby', ['-r', './scripts/public_app_media', '-e', 'puts PublicAppMedia.new(Dir.pwd).browser_runtime_fingerprint'], cwd);
  return result.trim();
}
const report = {schema_version: 1, kind: 'browser_flutter_fixture', status: 'running',
  scope: 'Current Collect Flutter interface previews at seven real routes with synthetic data; browser rendering only, no native or release acceptance.',
  source_snapshot_scope: 'Conservative complete fixture-entrypoint local Dart import/export/part graph, all declared assets/fonts/licenses, local fork Dart trees and provenance, web scaffold and actual helpers. Generated bindings are recorded separately; unrelated Admin/native drift grants no whole-app acceptance.',
  runtime_fingerprint_version: 4, browser_entrypoint: 'tool/public_app_media_capture.dart',
  source_root: sourceRoot, isolated_source_export: sourceRoot !== root,
  capture_recorder_sha256: hash(await readFile(fileURLToPath(import.meta.url))),
  diagnostic_observer_sources_before: await collectDiagnosticSourceSnapshot(import.meta.url),
  started_at: new Date().toISOString(), sources_before: await sourceSnapshot(),
  broader_checkout_sources_before: await broaderSourceSnapshot(root), commands: [], captures: [],
  external_requests: [], blocked_engine_font_requests: [], served_resources: {}, errors: [], native_capture_passed: false,
  served_resource_observation_method: 'real_loopback_http_bytes_verified_before_browser_fulfillment',
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
  ['account-deletion', '/settings/account/delete', 'Request service unavailable'],
];
const mime = {'.html':'text/html', '.js':'text/javascript', '.json':'application/json', '.wasm':'application/wasm', '.png':'image/png', '.webp':'image/webp', '.ttf':'font/ttf', '.otf':'font/otf', '.woff2':'font/woff2', '.css':'text/css'};
let server, browser;
const build = join(out, 'build');
try {
  report.resolved_local_bindings_before = await validateBindingTargets();
  report.checkout_browser_sources_before = await sourceSnapshot(root);
  if (JSON.stringify(report.checkout_browser_sources_before) !== JSON.stringify(report.sources_before)) throw Error('Current browser source graph differs from export before capture');
  for (const name of ['scripts/public_app_media.rb', 'scripts/qa/asset_manifest_integrity.rb']) {
    if (hash(await readFile(join(root, name))) !== report.sources_before[name]) throw Error('Capture helper differs from current checkout: ' + name);
  }
  report.runtime_before_sha256 = await runtime('runtime-fingerprint-before');
  report.checkout_runtime_before_sha256 = await runtime('checkout-runtime-fingerprint-before', root);
  if (report.runtime_before_sha256 !== report.checkout_runtime_before_sha256) throw Error('Source export differs from current runtime before capture');
  report.generated_bindings_before = await bindingSnapshot();
  report.flutter = JSON.parse(await command('flutter-version', flutter, ['--version', '--machine']));
  const pinnedFlutter = JSON.parse(await readFile(join(sourceRoot, '.fvmrc'), 'utf8')).flutter;
  if (report.flutter.flutterVersion !== pinnedFlutter) throw Error('Flutter SDK differs from .fvmrc pin; select the exact SDK with FLUTTER.');
  const reusePath = process.env.COLLECT_MEDIA_REUSE_BUILD_REPORT;
  if (reusePath) {
    const previousPath = resolve(reusePath);
    if (!previousPath.startsWith(join(root, '.cache') + '/') || await realpath(previousPath) !== previousPath) {
      throw Error('Reusable compilation report must be canonical repository-local evidence');
    }
    const raw = await readFile(previousPath), previous = JSON.parse(raw);
    const actualBuild = assertReusableCompilation(previous, report.sources_before,
      report.generated_bindings_before, report.flutter, sourceRoot, report.diagnostic_observer_sources_before);
    if (actualBuild.executable !== flutter) throw Error('Reusable compilation SDK executable differs');
    const oldBuild = join(dirname(previousPath), 'build');
    if (await realpath(oldBuild) !== oldBuild) throw Error('Reusable compilation artifact directory is aliased');
    const actualFiles = Object.fromEntries(await Promise.all((await files(oldBuild)).sort().map(async path =>
      [relative(oldBuild, path), hash(await readFile(path))])));
    if (JSON.stringify(actualFiles) !== JSON.stringify(previous.build_files)) throw Error('Reusable compilation artifact bytes differ');
    for (const stream of ['stdout', 'stderr']) {
      const bytes = await readFile(join(dirname(previousPath), 'flutter-build.' + stream));
      if (hash(bytes) !== actualBuild[stream + '_sha256']) throw Error('Reusable compilation command log differs');
      await writeFile(join(out, 'flutter-build.' + stream), bytes);
    }
    await cp(oldBuild, build, {recursive: true, errorOnExist: true, force: false});
    report.commands.push({...actualBuild, reused_verified_compilation: true});
    report.reused_compilation = {capture_report: relative(root, previousPath), capture_report_sha256: hash(raw),
      original_build_directory: relative(root, oldBuild), source_root: sourceRoot,
      scope: 'Previous successful real compiler command reused only after exact current complete source graph, generated bindings, SDK version/executable, command logs and every compiled artifact byte match; all seven browser captures are new.'};
  } else {
  await command('flutter-build', flutter, ['build', 'web', '--release', '--no-pub', '--no-wasm-dry-run', '--no-web-resources-cdn', '--target=tool/public_app_media_capture.dart', '--dart-define=COLLECT_PUBLIC_MEDIA_CAPTURE=true', '--output=' + build]);
  }
  report.build_files = Object.fromEntries(await Promise.all((await files(build)).sort().map(async p => [relative(build, p), hash(await readFile(p))])));
  report.build_manifest_sha256 = hash(Buffer.from(JSON.stringify(report.build_files)));
  if (report.reused_compilation) {
    const previous = JSON.parse(await readFile(join(root, report.reused_compilation.capture_report), 'utf8'));
    if (JSON.stringify(report.build_files) !== JSON.stringify(previous.build_files)) throw Error('Copied reusable build differs');
  }
  // The source web scaffold is shared with Admin's versioned-asset build. Its
  // placeholders need the same explicit substitution contract for this local
  // fixture. Keep production source untouched; disable the Admin worker here.
  const bootstrap = join(build, 'flutter_bootstrap.js');
  let originalBootstrap = await readFile(bootstrap, 'utf8');
  if (report.reused_compilation) {
    const previousPath = join(root, report.reused_compilation.capture_report);
    const previous = JSON.parse(await readFile(previousPath, 'utf8'));
    const configuration = previous.fixture_bootstrap_configuration;
    if (!configuration || configuration.asset_base !== '/' || configuration.service_worker_enabled !== false) {
      throw Error('Reusable compilation lacks the exact loopback fixture bootstrap; fresh build required');
    }
    const original = await readFile(join(dirname(previousPath), 'flutter-bootstrap.original.js'), 'utf8');
    if (hash(Buffer.from(original)) !== configuration.original_sha256 ||
        hash(Buffer.from(originalBootstrap)) !== configuration.configured_sha256 ||
        configureLoopbackMediaBootstrap(original, '/') !== originalBootstrap) {
      throw Error('Reusable loopback fixture bootstrap configuration differs');
    }
    originalBootstrap = original;
  }
  const configuredBootstrap = configureLoopbackMediaBootstrap(originalBootstrap, '/');
  await writeFile(join(out, 'flutter-bootstrap.original.js'), originalBootstrap);
  await writeFile(bootstrap, configuredBootstrap);
  report.fixture_bootstrap_configuration = {
    contract: 'existing_Admin_asset_base_and_worker_version_placeholders',
    original: relative(root, join(out, 'flutter-bootstrap.original.js')),
    original_sha256: hash(Buffer.from(originalBootstrap)),
    configured_sha256: hash(Buffer.from(configuredBootstrap)),
    asset_base: '/', service_worker_enabled: false,
    scope: 'Only this generated unauthenticated loopback media fixture; production bootstrap unchanged',
  };
  report.build_files['flutter_bootstrap.js'] = report.fixture_bootstrap_configuration.configured_sha256;
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
      if (new URL(request.request().url()).origin === origin) return serveVerifiedLocalResource(request, origin,
        report.build_files, report.served_resources, report.errors, pending, id);
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
    observeCollectDiagnostics(page, diagnostic => report.errors.push({id,
      message: 'Collect diagnostic failure', diagnostic}));
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
    await page.waitForLoadState('networkidle', {timeout: 90000});
    await Promise.all(pending);
    if (report.errors.length) throw Error('Browser or served-resource observation failed: ' + id);
    report.captures.push({id, app_route: route, marker, marker_verified: true, path: relative(root, capture), sha256: hash(bytes), bytes: bytes.length, width, height, platform: 'Chromium browser', theme: 'dark', text_scale: 1, data: 'synthetic example data'});
    await context.close(); console.log(id + ' captured');
  }
  if (report.errors.length || report.external_requests.length || !report.served_resources['main.dart.js']) throw Error('Browser errors, outbound requests or missing served application proof');
  report.runtime_after_sha256 = await runtime('runtime-fingerprint-after'); report.sources_after = await sourceSnapshot();
  report.checkout_runtime_after_sha256 = await runtime('checkout-runtime-fingerprint-after', root);
  report.checkout_browser_sources_after = await sourceSnapshot(root);
  report.broader_checkout_sources_after = await broaderSourceSnapshot(root);
  const broaderNames = new Set([...Object.keys(report.broader_checkout_sources_before), ...Object.keys(report.broader_checkout_sources_after)]);
  report.unrelated_checkout_source_drift = Object.fromEntries([...broaderNames].sort().filter(name =>
    report.broader_checkout_sources_before[name] !== report.broader_checkout_sources_after[name]).map(name =>
    [name, {before: report.broader_checkout_sources_before[name] || null, after: report.broader_checkout_sources_after[name] || null}]));
  if (Object.keys(report.unrelated_checkout_source_drift).some(name => name in report.sources_after) ||
      JSON.stringify(report.checkout_browser_sources_after) !== JSON.stringify(report.sources_after)) throw Error('Reachable browser source changed during capture');
  report.generated_bindings_after = await bindingSnapshot();
  report.resolved_local_bindings_after = await validateBindingTargets();
  for (const name of ['scripts/public_app_media.rb', 'scripts/qa/asset_manifest_integrity.rb']) {
    if (hash(await readFile(join(root, name))) !== report.sources_after[name]) throw Error('Capture helper changed in checkout: ' + name);
  }
  report.generated_bindings_unchanged = JSON.stringify(report.generated_bindings_before) === JSON.stringify(report.generated_bindings_after);
  if (report.checkout_runtime_after_sha256 !== report.runtime_after_sha256 ||
      !report.generated_bindings_unchanged ||
      JSON.stringify(report.resolved_local_bindings_before) !== JSON.stringify(report.resolved_local_bindings_after) ||
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
  report.diagnostic_observer_sources_after = await collectDiagnosticSourceSnapshot(import.meta.url);
  if (JSON.stringify(report.diagnostic_observer_sources_before) !== JSON.stringify(report.diagnostic_observer_sources_after)) {
    report.status = 'fail'; report.failure = 'Diagnostic observer sources changed'; process.exitCode = 1;
  }
  report.finished_at = new Date().toISOString();
  await writeFile(join(out, 'capture-report.json'), JSON.stringify(report, null, 2) + '\n');
}
