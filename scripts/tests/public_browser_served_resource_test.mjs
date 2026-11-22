import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';
const source = await readFile(new URL('../qa/public_browser_app_media.mjs', import.meta.url), 'utf8');
const begin = source.indexOf('// BEGIN strict served-resource observer');
const end = source.indexOf('// END strict served-resource observer');
assert(begin > 0 && end > begin, 'Actual recorder observer must be identifiable');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const serve = runInNewContext(source.slice(begin, end) + '\nserveVerifiedLocalResource', {hash, URL, Error, decodeURIComponent});
const origin = 'http://127.0.0.1:45678', bytes = Buffer.from('actual compiled fixture bytes');
function fixture(path = '/main.dart.js', value = bytes, status = 200) {
  const result = {build: {'main.dart.js': hash(bytes), 'index.html': hash(bytes)}, served: {}, errors: [], pending: [], fetches: 0, aborts: 0, fulfilled: null, options: null};
  result.route = {request: () => ({url: () => origin + path}), fetch: async options => {result.fetches++; result.options = options; return {status: () => status, body: async () => value};},
    fulfill: async value => {result.fulfilled = value;}, abort: async () => {result.aborts++;}};
  return result;
}
const record = f => serve(f.route, origin, f.build, f.served, f.errors, f.pending, 'home');
test('Real HTTP response bytes are verified before identical fulfillment, redirects disabled', async () => {
  for (const path of ['/main.dart.js', '/']) {
    const f = fixture(path); await record(f); assert.equal(f.errors.length, 0); assert.equal(f.fetches, 1);
    assert.equal(f.options.maxRedirects, 0); assert.deepEqual(f.fulfilled.body, bytes); assert.equal(f.served[path === '/' ? 'index.html' : 'main.dart.js'], hash(bytes));
  }
});
test('Changed or undeclared actual body aborts and cannot be fulfilled', async () => {
  for (const [path, value] of [['/main.dart.js', Buffer.from('changed')], ['/undeclared.js', bytes]]) {
    const f = fixture(path, value); await record(f); assert.equal(f.errors.length, 1); assert.equal(f.aborts, 1); assert.equal(f.fulfilled, null); assert.equal(Object.keys(f.served).length, 0);
  }
});
test('Delayed failed HTTP body and failed abort cannot escape before caller drain', async () => {
  const f = fixture(); let rejectBody; const body = new Promise((_, reject) => {rejectBody = reject;});
  f.route.fetch = async () => ({status: () => 200, body: () => body}); f.route.abort = () => {throw Error('context already closed');};
  const unexpected = [], observer = reason => unexpected.push(reason); process.on('unhandledRejection', observer);
  try {record(f); await Promise.resolve(); rejectBody(Error('actual body read failed')); await new Promise(resolve => setImmediate(resolve)); await Promise.all(f.pending);
    assert.equal(unexpected.length, 0); assert.equal(f.errors.length, 1); assert.equal(f.fulfilled, null);
  } finally {process.off('unhandledRejection', observer);}
});
test('Remote HTTP and redirects are refused without remote follow', async () => {
  const remote = fixture(); remote.route.request = () => ({url: () => 'https://remote.invalid/main.dart.js'}); await record(remote);
  assert.equal(remote.fetches, 0); assert.equal(remote.errors.length, 1); assert.equal(remote.fulfilled, null);
  const redirect = fixture('/main.dart.js', bytes, 302); await record(redirect); assert.equal(redirect.options.maxRedirects, 0); assert.equal(redirect.errors.length, 1); assert.equal(redirect.fulfilled, null);
});
test('Actual non-200 HTTP bytes are delivered without granting compiled-byte proof', async () => {
  const value = Buffer.from('missing'); const f = fixture('/missing.js', value, 404); await record(f);
  assert.equal(f.errors.length, 0); assert.deepEqual(f.fulfilled.body, value); assert.equal(Object.keys(f.served).length, 0);
});
test('Synchronous fetch and fulfillment failures are retained and abort safely', async () => {
  for (const operation of ['fetch', 'fulfill']) {const f = fixture(); f.route[operation] = () => {throw Error(operation + ' failed');}; await record(f); assert.equal(f.errors.length, 1); assert.equal(f.aborts, 1);}
});

const reuseBegin = source.indexOf('// BEGIN strict reusable compilation contract');
const reuseEnd = source.indexOf('// END strict reusable compilation contract');
assert(reuseBegin > 0 && reuseEnd > reuseBegin);
const checkReuse = runInNewContext(source.slice(reuseBegin, reuseEnd) + '\nassertReusableCompilation', {hash, Buffer, Error});
function reusableFixture() {
  const sources = {'lib/main.dart': 'a'.repeat(64)}, bindings = {'package_config': 'b'.repeat(64)}, version = {'frameworkVersion': '3.44.4'}, sourceRoot = '/actual/export';
  const observerSources = {'scripts/qa/collect_diagnostic_observer.mjs': 'd'.repeat(64), 'scripts/qa/public_browser_app_media.mjs': 'e'.repeat(64)};
  const build = {'main.dart.js': hash(bytes), 'flutter_bootstrap.js': hash(Buffer.from('bootstrap'))};
  const previous = {kind: 'browser_flutter_fixture', status: 'fail', runtime_fingerprint_version: 4, browser_entrypoint: 'tool/public_app_media_capture.dart',
    source_root: sourceRoot, sources_before: sources, generated_bindings_before: bindings, flutter: version,
    diagnostic_observer_sources_before: observerSources, diagnostic_observer_sources_after: {...observerSources},
    build_files: build, build_manifest_sha256: hash(Buffer.from(JSON.stringify(build))), commands: [{name: 'flutter-build', exit_code: 0, cwd: sourceRoot,
      args: ['build','web','--release','--no-pub','--no-wasm-dry-run','--no-web-resources-cdn','--target=tool/public_app_media_capture.dart','--dart-define=COLLECT_PUBLIC_MEDIA_CAPTURE=true','--output=/actual/compiled']} ]};
  return {previous, sources, bindings, version, sourceRoot, observerSources};
}
const check = f => checkReuse(f.previous, f.sources, f.bindings, f.version, f.sourceRoot, f.observerSources);
test('Successful actual compiler receipt may be reused independently of failed browser observation', () => {const f = reusableFixture(); assert.equal(check(f).exit_code, 0);});
test('Changed current reachable source, generated package binding or selected SDK refuses reuse', () => {
  for (const field of ['sources', 'bindings', 'version', 'sourceRoot']) {const f = reusableFixture(); f[field] = field === 'sourceRoot' ? '/different/export' : {changed: true}; assert.throws(() => check(f), /binding differs/);}
});
test('Changed compiled byte manifest refuses reuse', () => {const f = reusableFixture(); f.previous.build_files['main.dart.js'] = 'c'.repeat(64); assert.throws(() => check(f), /artifact map/);});
test('Failed, duplicate or altered compiler recipe cannot grant reuse', () => {
  for (const mode of ['failed', 'duplicate', 'target', 'flags']) {const f = reusableFixture(); const command = f.previous.commands[0];
    if (mode === 'failed') command.exit_code = 1; else if (mode === 'duplicate') f.previous.commands.push(command); else if (mode === 'target') command.args[6] = '--target=lib/main.dart'; else command.args.splice(3, 1);
    assert.throws(() => check(f), /command/);}
});
test('Unknown source graph or wrong compiler entrypoint refuses reuse', () => {
  for (const field of ['runtime_fingerprint_version','browser_entrypoint']) {const f = reusableFixture(); f.previous[field] = 'unknown'; assert.throws(() => check(f), /binding differs/);}
});
test('Missing or changed diagnostic observer provenance refuses artifact reuse', () => {
  for (const field of ['diagnostic_observer_sources_before','diagnostic_observer_sources_after']) {
    const f = reusableFixture(); delete f.previous[field]; assert.throws(() => check(f), /binding differs/);
    f.previous[field] = {'scripts/qa/collect_diagnostic_observer.mjs': '0'.repeat(64)};
    assert.throws(() => check(f), /binding differs/);
  }
  const f = reusableFixture(); f.observerSources = {}; assert.throws(() => check(f), /binding differs/);
});
