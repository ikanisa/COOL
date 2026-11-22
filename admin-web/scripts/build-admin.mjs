import { execFileSync } from 'node:child_process';
import { promises as fs } from 'node:fs';
import { join, resolve, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { packagePwa, verifyPwaPackage } from './package-pwa.mjs';
import { artifactIdentity, readBuildFile, sourceIdentity } from './build-identity.mjs';
import { publicConfiguration } from './build-configuration.mjs';

const root = await fs.realpath(fileURLToPath(new URL('../../', import.meta.url)));
const packageRoot = join(root, 'admin-web');
const outputPaths = { fixture: 'build/admin-web-fixture', qualification: 'build/admin-web-qualification' };
const associationFiles = ['assetlinks.json', 'apple-app-site-association'];
const json = (value) => JSON.stringify(value, null, 2) + '\n';

async function verify(output, action) {
  const raw = await readBuildFile(output + '.json');
  await verifyPwaPackage(output);
  const receipt = JSON.parse(raw);
  const files = await artifactIdentity(output);
  const source = await sourceIdentity(root);
  const version = JSON.parse(await fs.readFile(join(output, 'version.json'), 'utf8'));
  if (receipt.format !== 'collect.react-admin.build.v1' || receipt.hosted_verified !== false ||
      JSON.stringify(receipt.files) !== JSON.stringify(files) ||
      JSON.stringify(receipt.source) !== JSON.stringify(source) ||
      receipt.backend !== version.backend || receipt.build_config_sha256 !== version.public_build_config_sha256) {
    throw new Error('React Admin artifact, source, or release profile differs from the build receipt.');
  }
  if (action === 'verify-ci') {
    const { metadata } = publicConfiguration(root, 'production');
    if (!source.clean || source.commit !== process.env.GITHUB_SHA ||
        Object.entries(metadata).some(([key, value]) => JSON.stringify(version[key]) !== JSON.stringify(value))) {
      throw new Error('React Admin candidate differs from the expected clean commit or public release configuration.');
    }
  }
  if (action === 'verify-hosting' && version.backend !== 'supabase') {
    throw new Error('Hosting checks require a build for a reviewed Supabase origin.');
  }
  return receipt;
}

async function build(output, mode) {
  if (await fs.realpath(packageRoot) !== packageRoot) throw new Error('Expected the physical React package.');
  // Keep generated compiler and PWA outputs outside the source inventory.
  const staging = await fs.mkdtemp(join(root, 'build', 'react-admin-'));
  try {
    const raw = join(staging, 'vite');
    const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('VITE_')));
    const npm = (args, childEnv = env) => execFileSync('npm', args, { cwd: packageRoot, env: childEnv, stdio: 'inherit' });
    const source = await sourceIdentity(root);
    const { defines, metadata } = publicConfiguration(root, mode);
    npm(['run', 'notices', '--', '--check']);
    npm(['exec', '--no', '--', 'vite', 'build', '--outDir', raw],
      { ...env, ...defines, NODE_ENV: 'production', ADMIN_ASSET_BASE: './' });
    if (JSON.stringify(await sourceIdentity(root)) !== JSON.stringify(source)) {
      throw new Error('React Admin sources changed during compilation.');
    }
    const staged = join(staging, 'site');
    await packagePwa(raw, staged, { publicBuild: metadata });
    await fs.mkdir(join(staged, '.well-known'));
    for (const name of associationFiles) {
      await fs.copyFile(join(root, 'web', '.well-known', name), join(staged, '.well-known', name));
    }
    const receipt = {
      format: 'collect.react-admin.build.v1', source, backend: metadata?.backend ?? 'unconfigured',
      build_config_sha256: metadata?.public_build_config_sha256,
      files: await artifactIdentity(staged), hosted_verified: false,
    };
    // Reserve both destinations before publishing. If another build owns either
    // path, remove only the files and directory created by this build.
    await fs.mkdir(output);
    let receiptWritten = false;
    try {
      const receiptFile = await fs.open(output + '.json', 'wx');
      receiptWritten = true;
      try {
        await receiptFile.writeFile(json(receipt));
      } finally {
        await receiptFile.close();
      }
      for (const entry of await fs.readdir(staged)) await fs.rename(join(staged, entry), join(output, entry));
      return await verify(output, 'verify');
    } catch (error) {
      if (receiptWritten) await fs.unlink(output + '.json');
      await fs.rm(output, { recursive: true, force: true });
      throw error;
    }
  } finally {
    await fs.rm(staging, { recursive: true, force: true });
  }
}

try {
  const { positionals } = parseArgs({ options: { json: { type: 'boolean' } }, allowPositionals: true });
  const [action = 'production', ...argumentsAfterAction] = positionals;
  const [directory = process.env.ADMIN_PWA_BUILD_DIR ?? join(root, outputPaths[action] ?? 'build/admin-web'), ...rest] = argumentsAfterAction;
  if (rest.length || !['production', 'qualification', 'fixture', 'verify', 'verify-ci', 'verify-hosting'].includes(action)) {
    throw new Error('Usage: build-admin.mjs [production|qualification|fixture|verify|verify-ci|verify-hosting] [build-directory] [--json]');
  }
  const output = resolve(root, directory);
  const parent = resolve(output, '..');
  if (!action.startsWith('verify')) {
    if (!output.startsWith(join(root, 'build') + sep)) throw new Error('Use a new directory under build/.');
    await fs.mkdir(parent, { recursive: true });
  }
  if (await fs.realpath(parent) !== parent) throw new Error('Admin artifact destination must be physical.');
  const receipt = action.startsWith('verify') ? await verify(output, action) : await build(output, action);
  console.log(json({ status: 'pass', frontend: 'react-vite', source: receipt.source, files: receipt.files.length,
    backend: receipt.backend, hosted_verified: false, artifact: relative(root, output) }));
} catch (error) {
  if (process.argv.includes('--json')) console.log(json({ status: 'fail', failures: [error.message] }));
  else console.error('React Admin: ' + error.message);
  process.exitCode = 1;
}
