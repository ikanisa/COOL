import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

test('authenticated CLI bootstrap is local-only in test, idempotent and creates no credential', async () => {
  const root = fileURLToPath(new URL('..', import.meta.url));
  const generated = path.join(root, 'test/.generated');
  await mkdir(generated, { recursive: true });
  const directory = await mkdtemp(path.join(generated, 'bootstrap-'));
  const wrangler = path.join(root, 'node_modules/wrangler/bin/wrangler.js');
  const bootstrap = path.join(root, 'scripts/bootstrap-owner.mjs');
  const config = path.join(directory, 'wrangler.json');
  function command(script, args) {
    const result = spawnSync(process.execPath, [script, ...args], { cwd: directory, encoding: 'utf8', env: { ...process.env, CI: '1', WRANGLER_SEND_METRICS: 'false' } });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    return result.stdout;
  }
  try {
    await writeFile(config, JSON.stringify({
      name: 'collect-owner-bootstrap-test', compatibility_date: '2026-10-04',
      d1_databases: [{ binding: 'ADMIN_DB', database_name: 'bootstrap-test', database_id: crypto.randomUUID() }],
    }));
    command(wrangler, ['d1', 'execute', 'ADMIN_DB', '--local', '--config', config, '--file', path.join(root, 'migrations/0001_admin_accounts.sql')]);
    command(bootstrap, ['--local', '--config', config]);
    command(bootstrap, ['--local', '--config', config]);
    const output = command(wrangler, ['d1', 'execute', 'ADMIN_DB', '--local', '--config', config, '--command', 'SELECT email,role,status,password_hash FROM admin_users', '--json']);
    const parsed = JSON.parse(output);
    assert.deepEqual(parsed[0].results, [{ email: 'info@ikanisa.com', role: 'owner', status: 'invited', password_hash: null }]);
    const invalid = spawnSync(process.execPath, [bootstrap, '--config', config], { cwd: directory, encoding: 'utf8' });
    assert.equal(invalid.status, 1, 'An explicit --local or --remote target is required');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
