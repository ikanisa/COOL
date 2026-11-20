#!/usr/bin/env node
// Check the local asset policy against the maintained compiler scaffold.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';

const recorder = await readFile(new URL('../qa/public_browser_app_media.mjs', import.meta.url), 'utf8');
const begin = recorder.indexOf('// BEGIN strict loopback media bootstrap configuration');
const end = recorder.indexOf('// END strict loopback media bootstrap configuration');
assert(begin >= 0 && end > begin);
const configure = runInNewContext(recorder.slice(begin, end) + '\nconfigureLoopbackMediaBootstrap', {Error});
const original = await readFile(new URL('../../web/flutter_bootstrap.js', import.meta.url), 'utf8');
assert.equal(configure(original, '/'), original);
for (const base of ['https://foreign.invalid/', '//foreign.invalid/', '/admin/', '../', '']) {
  assert.throws(() => configure(original, base), /loopback root/);
}
for (const malformed of [
  original.replace("entrypointBaseUrl: '/'", "entrypointBaseUrl: 'https://foreign.invalid/'"),
  original.replace("assetBase: '/'", "assetBase: '/admin/'"),
  original.replace("canvasKitBaseUrl: '/canvaskit/'", "canvasKitBaseUrl: 'https://foreign.invalid/'"),
  original.replace('  config:', '  serviceWorkerSettings: {},\n  config:'),
  original + original,
  original + "\nnavigator.serviceWorker.register('/custom-sw.js');\n",
]) {
  assert.throws(() => configure(malformed, '/'), /bootstrap contract/);
}
console.log(JSON.stringify({status: 'pass', current_scaffold_verified: true, foreign_base_denials: 5, malformed_scaffold_denials: 6}));
