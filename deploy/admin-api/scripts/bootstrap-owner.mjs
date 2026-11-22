import { spawnSync } from 'node:child_process';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { OWNER_EMAIL } from '../src/security.mjs';

// Account creation requires Cloudflare CLI credentials. No public bootstrap
// endpoint, default password or bearer setup credential is ever generated.
const args = process.argv.slice(2);
const remote = args.includes('--remote');
const local = args.includes('--local');
const index = args.indexOf('--config');
if (remote === local || index < 0 || !args[index + 1] || args.some((a, i) => !['--remote', '--local', '--config'].includes(a) && i !== index + 1)) {
  console.error('Usage: npm run bootstrap -- --local|--remote --config PATH');
  process.exit(1);
}
const config = path.resolve(args[index + 1]);
const directory = await mkdtemp(path.join(tmpdir(), 'collect-owner-bootstrap-'));
try {
  const time = Math.floor(Date.now() / 1000);
  const sql = `INSERT INTO admin_users(id,email,role,status,created_at,invited_at,updated_at) VALUES ('${crypto.randomUUID()}','${OWNER_EMAIL}','owner','invited',${time},${time},${time}) ON CONFLICT(email) DO NOTHING;`;
  const sqlFile = path.join(directory, 'bootstrap.sql');
  await writeFile(sqlFile, sql, { mode: 0o600 });
  const wrangler = fileURLToPath(new URL('../node_modules/wrangler/bin/wrangler.js', import.meta.url));
  const result = spawnSync(process.execPath, [wrangler, 'd1', 'execute', 'ADMIN_DB', remote ? '--remote' : '--local', '--config', config, '--file', sqlFile], { stdio: 'inherit' });
  if (result.status !== 0) process.exitCode = result.status || 1;
  else console.log('Owner record exists. On the admin sign-in page, request a password link for info@ikanisa.com. Only the owner inbox can activate this account. Existing credentials and role were not changed.');
} finally {
  await rm(directory, { recursive: true, force: true });
}
