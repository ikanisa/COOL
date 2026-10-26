#!/usr/bin/env node
// Execute the maintained recorder's actual substitution on the current source
// scaffold. Foreign bases, duplicate assignments and incomplete markers fail.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';

const recorder = await readFile(new URL('../qa/public_browser_app_media.mjs', import.meta.url), 'utf8');
const begin = recorder.indexOf('// BEGIN strict loopback media bootstrap configuration');
const end = recorder.indexOf('// END strict loopback media bootstrap configuration');
assert(begin >= 0 && end > begin);
const configure = runInNewContext(recorder.slice(begin, end) + '\nconfigureLoopbackMediaBootstrap', {Error});
const original = await readFile(new URL('../../web/flutter_bootstrap.js', import.meta.url), 'utf8');
const configured = configure(original, '/');
assert.equal(configured, original.replace('__COLLECT_ADMIN_ASSET_BASE__', '/').replace('__COLLECT_ADMIN_SW_VERSION__', ''));
assert(!configured.includes('__COLLECT_ADMIN_'));
assert(configured.includes("var adminAssetBase = '/';"));
assert(configured.includes("var adminServiceWorkerVersion = '';"));
assert(configured.includes('adminServiceWorkerVersion &&'));
for (const base of ['https://foreign.invalid/', '//foreign.invalid/', '/admin/', '../', '']) {
  assert.throws(() => configure(original, base), /loopback root/);
}
for (const malformed of [
  original.replace('__COLLECT_ADMIN_ASSET_BASE__', 'https://foreign.invalid/'),
  original.replace('__COLLECT_ADMIN_SW_VERSION__', 'unapproved-worker'),
  original + "\nadminAssetBase = 'https://foreign.invalid/';",
  original + "\nadminServiceWorkerVersion = 'unapproved-worker';",
  original + "\nvar adminAssetBase = '__COLLECT_ADMIN_ASSET_BASE__';",
  original + "\n// __COLLECT_ADMIN_UNKNOWN__",
  original.replace('assetBase: adminAssetBase', 'assetBase: foreignBase'),
]) {
  assert.throws(() => configure(malformed, '/'), /substitution contract/);
}
console.log(JSON.stringify({status: 'pass', actual_current_scaffold_configured: true, foreign_base_denials: 5, malformed_scaffold_denials: 7}));
