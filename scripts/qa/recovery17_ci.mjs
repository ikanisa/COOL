import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname, join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

// Public CI runs synthetic recovery only. Private production SQL is a separate
// controlled qualification input and must never be inherited by this command.
assert.equal(process.argv.length, 2, 'This command accepts no arguments');
assert.equal(process.version, 'v24.19.0', 'Use the repository-pinned Node 24.19.0');
const root = fileURLToPath(new URL('../../', import.meta.url));
const require = createRequire(join(root, 'deploy/platform-api/package.json'));
const env = {...process.env, CI: 'true', WRANGLER_SEND_METRICS: 'false', WRANGLER_SEND_ERROR_REPORTS: 'false'};
delete env.ACTUAL13_SQL;
delete env.EXPECT_ORIGINAL_VIEWS_REFUSAL;
if (!env.COLLECT_WRANGLER_MODULE) {
  env.COLLECT_WRANGLER_MODULE = dirname(dirname(require.resolve('wrangler')));
}
assert.equal(JSON.parse(readFileSync(join(env.COLLECT_WRANGLER_MODULE, 'package.json'))).version,
  '4.151.0', 'Use the locked Wrangler 4.151.0 dependency');
env.COLLECT_MINIFLARE_MODULE ??= require.resolve('miniflare');
env.COLLECT_ESBUILD_MODULE ??= require.resolve('esbuild');
const tests = [
  'scripts/tests/recovery_auth17_test.mjs',
  'scripts/tests/platform_backup_test.mjs',
  'scripts/tests/sql_snapshot_import_test.mjs',
  'scripts/tests/recovery_quarantine_test.mjs',
  'scripts/tests/recovery_auth17_qualification_test.mjs',
];
const result = spawnSync(process.execPath, ['--test', '--test-concurrency=1', ...tests], {
  cwd: root, env, stdio: 'inherit', timeout: 300000,
});
if (result.error) throw result.error;
assert.equal(result.signal, null, 'Recovery qualification was interrupted');
process.exitCode = result.status ?? 1;
