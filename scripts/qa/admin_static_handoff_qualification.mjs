#!/usr/bin/env node
// Root-only local asset-router qualification. No browser, Auth or remote send.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {lstat, mkdir, open, readFile, realpath, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join, resolve, sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {STATIC_RECOVERY_SCRIPT} from '../../deploy/platform-admin/src/static-recovery.js';
import {installedWorker, recoveryDom} from '../../deploy/platform-admin/test/fixtures/static-handoff-harness.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
async function pinned(path, expected) {
  assert.ok(isAbsolute(path)); assert.match(expected.sha256, /^[a-f0-9]{64}$/);
  assert.equal(await realpath(path), path, 'No symlinked input or ancestor');
  const before = await lstat(path); assert.ok(before.isFile() && !before.isSymbolicLink());
  assert.equal(before.size, expected.bytes);
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const bytes = await file.readFile(); const after = await file.stat();
    assert.equal(after.ino, before.ino); assert.equal(after.size, before.size);
    assert.equal(after.mtimeMs, before.mtimeMs); assert.equal(after.ctimeMs, before.ctimeMs);
    assert.equal(sha(bytes), expected.sha256, 'Pinned source/artifact bytes');
    return bytes;
  } finally {await file.close();}
}

const inputPath = process.env.COLLECT_ADMIN_HANDOFF_INPUTS;
const inputSha = process.env.COLLECT_ADMIN_HANDOFF_INPUTS_SHA256;
assert.ok(inputPath && inputSha && isAbsolute(inputPath));
const inputRaw = await readFile(inputPath); assert.equal(sha(inputRaw), inputSha);
assert.equal(await realpath(inputPath), inputPath);
const inputs = JSON.parse(inputRaw);
assert.equal(inputs.format, 'collect.admin-static-handoff-inputs.v1');
assert.equal(inputs.remote_provider_calls_allowed, false);
assert.equal(inputs.origin, 'https://admin-supabase-qa.collect.ikanisa.com');
assert.equal(process.version, inputs.runtime.node.version);
await pinned(process.execPath, inputs.runtime.node);
await pinned(inputs.runtime.miniflare.path, inputs.runtime.miniflare);
await pinned(inputs.runtime.workerd.path, inputs.runtime.workerd);
const origin = inputs.origin;
const output = resolve(process.argv[2] || '');
assert.ok(process.argv[2] && isAbsolute(process.argv[2]));
assert.ok(output.startsWith(resolve(dirname(inputPath)) + sep));
assert.equal(await realpath(dirname(output)), dirname(output));
await mkdir(output, {mode: 0o700});
const report = {format: 'collect.admin-static-handoff-local-qualification.v1',
  at: new Date().toISOString(), accepted: false, browser_or_installed_PWA_acceptance: false,
  hosted_or_production_or_retention_policy_acceptance: false,
  origin_is_fixture_only: true, outbound_provider_attempts: 0, checks: [],
  inputs: {path: inputPath, sha256: inputSha}, failure: null};
function check(id, condition, observed = null) {
  report.checks.push({id, pass: Boolean(condition), observed}); assert.ok(condition, id);
}
async function fixture(kind) {
  const spec = inputs.artifacts[kind];
  const manifest = JSON.parse(await pinned(spec.manifest.path, spec.manifest));
  assert.equal(Object.keys(manifest).length, 300);
  const files = new Map();
  async function read(key) {
    assert.ok(key && !key.startsWith('/') && !key.split('/').some(x => x === '..' || x === '.'));
    const path = join(spec.root, key); assert.ok(path.startsWith(spec.root + sep));
    assert.ok(manifest[key], 'Actual artifact manifest contains ' + key);
    const bytes = await pinned(path, manifest[key]); files.set(key, bytes); return bytes;
  }
  const bootstrap = await read('flutter_bootstrap.js');
  const matches = [...bootstrap.toString().matchAll(/var adminAssetBase = '([^']+)';/g)];
  assert.equal(matches.length, 1); const base = matches[0][1]; assert.equal(base, spec.asset_base);
  const mainKey = base + 'main.dart.js'; await read(mainKey);
  for (const key of ['index.html', 'version.json', 'custom-sw.js', '_headers']) await read(key);
  const actualVersion = JSON.parse(files.get('version.json'));
  assert.equal(actualVersion.source_commit, spec.source_commit);
  assert.equal(actualVersion.source_manifest_sha256, spec.source_manifest_sha256);
  assert.equal(actualVersion.api_source_id, inputs.backend_source_sha256);
  const worker = files.get('custom-sw.js').toString();
  const urls = JSON.parse(worker.match(/const CACHE_URLS = (\[[\s\S]*?\]);/)[1]);
  if (kind === 'prior') for (const url of urls) await read(url === './' ? 'index.html' : url.slice(2));
  assert.equal(files.size, spec.required_read_file_count);
  return {spec, manifest, files, base, mainKey, worker, urls};
}
let mf;
try {
  // Admission reads every dynamic cache/fixture input before starting workerd.
  const prior = await fixture('prior'), current = await fixture('current');
  const moduleFile = await pinned(inputs.source.profile.path, inputs.source.profile);
  const profile = JSON.parse(moduleFile);
  const workerModule = await pinned(inputs.source.worker.path, inputs.source.worker);
  assert.ok(workerModule.length); // The exact source identity is retained above.
  const closureBodies = new Map();
  for (const file of inputs.source.closure) closureBodies.set(file.path, await pinned(file.path, file));
  const stage = async (name, value) => {
    const dir = join(output, name); await mkdir(dir, {mode: 0o700});
    // This is deliberately a selected static HTTP fixture, not a full app build.
    for (const key of ['index.html', 'version.json', 'flutter_bootstrap.js', 'custom-sw.js', '_headers', value.mainKey]) {
      const path = join(dir, key); await mkdir(dirname(path), {recursive: true});
      await writeFile(path, value.files.get(key), {flag: 'wx', mode: 0o600});
    }
    return dir;
  };
  const priorDir = await stage('prior-selected-static', prior);
  const currentDir = await stage('current-selected-static', current);
  const loaded = await import(pathToFileURL(inputs.runtime.miniflare.path).href);
  const Miniflare = loaded.Miniflare || loaded.default?.Miniflare; assert.equal(typeof Miniflare, 'function');
  const convertOptions = loaded.convertV4MiniflareOptions || loaded.default?.convertV4MiniflareOptions;
  assert.equal(typeof convertOptions, 'function', 'Pinned Miniflare supports its V4 option converter');
  // Miniflare 5 accepts {workers:[{config,dev}]}, including setOptions. Its
  // supported converter preserves the actual profile/asset/fetcher semantics.
  // Supply the closed runtime graph explicitly: this version does not crawl
  // scriptPath imports into its manifest. Every body was admitted above.
  const sourceRoot = resolve(dirname(inputs.source.worker.path), '../../..');
  const admitted = new Map([[inputs.source.worker.path, workerModule]]);
  for (const [path, bytes] of closureBodies) admitted.set(path, bytes);
  const modules = [
    'deploy/platform-admin/src/index.js',
    'deploy/platform-admin/src/static-recovery.js',
    'deploy/platform-admin/src/supabase-transport.js',
    'supabase/functions/_shared/deployment-profile.js',
    'deploy/platform-supabase-free/local-challenge.mjs',
  ].map(name => {
    const path = join(sourceRoot, name); const contents = admitted.get(path);
    assert.ok(contents, 'Admitted closed runtime module: ' + name);
    return {type: 'ESModule', path, contents: contents.toString('utf8')};
  });
  const options = directory => convertOptions({name: 'collect-admin-static-handoff-local',
    cf: false, // Never refresh unrelated remote Request.cf metadata in this local fixture.
    modules, modulesRoot: sourceRoot,
    compatibilityDate: profile.compatibility_date,
    compatibilityFlags: profile.compatibility_flags,
    bindings: {...profile.vars, ADMIN_ORIGIN: origin},
    assets: {directory, binding: 'ASSETS', run_worker_first: profile.assets.run_worker_first,
      routerConfig: {has_user_worker: true},
      assetConfig: {not_found_handling: profile.assets.not_found_handling}},
    outboundService: () => {report.outbound_provider_attempts++; return new Response('External HTTP forbidden', {status: 599});}});
  mf = new Miniflare(options(priorDir));
  const first = await mf.dispatchFetch(origin + '/flutter_bootstrap.js');
  check('actual-prior-bootstrap-before-switch', first.status === 200 && sha(new Uint8Array(await first.arrayBuffer())) === sha(prior.files.get('flutter_bootstrap.js')));
  const genuineOldMainURL = origin + '/' + prior.mainKey;
  // No worker/controller cache exists for this first visit. The actual old
  // bootstrap's pending main URL is resumed after the local asset-set switch.
  await mf.setOptions(options(currentDir));
  const handoff = await mf.dispatchFetch(genuineOldMainURL);
  const body = await handoff.text();
  check('actual-router-predecessor-main-recovery', handoff.status === 200 && body === STATIC_RECOVERY_SCRIPT &&
    /^text\/javascript(?:;|$)/i.test(handoff.headers.get('Content-Type') || '') && handoff.headers.get('X-Content-Type-Options') === 'nosniff',
    {url: genuineOldMainURL, status: handoff.status, content_type: handoff.headers.get('Content-Type')});
  check('actual-router-error-is-not-immutable-HTML', handoff.headers.get('X-Collect-Static-Recovery') === '1' &&
    handoff.headers.get('Cache-Control')?.includes('no-store') && !handoff.headers.get('Cache-Control')?.includes('immutable'));
  const dom = recoveryDom(); dom.run(body);
  check('uncontrolled-first-visit-manual-recovery', Boolean(dom.panel()) && dom.reloads === 0 && dom.forbiddenEffects === 0);
  const served = await mf.dispatchFetch(origin + '/' + current.mainKey);
  const servedBytes = new Uint8Array(await served.arrayBuffer());
  check('actual-current-main-exact-unchanged-bytes', served.status === 200 && sha(servedBytes) === current.manifest[current.mainKey].sha256);
  const absent = await mf.dispatchFetch(origin + '/' + prior.base + 'assets/absent.woff2');
  check('actual-router-other-missing-static404-no-store', absent.status === 404 && absent.headers.get('Cache-Control')?.includes('no-store'));
  // The complete actual predecessor cache inventory is read and cryptographically
  // admitted by its unmodified worker. This is VM Cache Storage, not Chromium.
  const files = new Map(prior.urls.map(url => [new URL(url, origin + '/custom-sw.js').href,
    prior.files.get(url === './' ? 'index.html' : url.slice(2))]));
  const sw = await installedWorker(prior.worker, origin, files);
  const afterInstall = sw.fetches;
  const cached = await sw.read(genuineOldMainURL);
  const cachedBootstrap = await sw.read(origin + '/flutter_bootstrap.js');
  const cachedBootstrapSha = sha(new Uint8Array(await cachedBootstrap.arrayBuffer()));
  check('complete-actual-predecessor-cache-survives-switch',
    sha(new Uint8Array(await cached.arrayBuffer())) === prior.manifest[prior.mainKey].sha256 &&
    cachedBootstrapSha === prior.manifest['flutter_bootstrap.js'].sha256 &&
    cachedBootstrapSha !== current.manifest['flutter_bootstrap.js'].sha256 && sw.fetches === afterInstall,
    {actual_cached_URLs: prior.urls.length, distinct_old_bootstrap_retained: true,
      admission: 'unmodified actual worker with in-memory Cache Storage model'});
  await sw.evict(genuineOldMainURL);
  const missing = await sw.read(genuineOldMainURL);
  check('evicted-old-entry503-no-server-fallback', missing.status === 503 && missing.headers.get('Cache-Control')?.includes('no-store') && sw.fetches === afterInstall);
  check('no-outbound-provider-attempt', report.outbound_provider_attempts === 0);
  report.accepted = true;
} catch (error) {
  report.failure = {name: error.name, message: error.message};
  process.exitCode = 1;
} finally {
  if (mf) {
    try {await mf.dispose(); report.miniflare_dispose_completed = true;}
    catch (error) {report.miniflare_dispose_completed = false; report.cleanup_failure = error.name; report.accepted = false; process.exitCode = 1;}
  }
  report.completed_at = new Date().toISOString();
  await writeFile(join(output, 'RESULT.json'), JSON.stringify(report, null, 2) + '\n', {flag: 'wx', mode: 0o600});
  console.log(JSON.stringify({accepted: report.accepted, checks: report.checks.length, outbound_provider_attempts: report.outbound_provider_attempts}));
}
