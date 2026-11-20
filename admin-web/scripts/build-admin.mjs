import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import { join, resolve, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { packagePwa, verifyPwaPackage } from './package-pwa.mjs';

const root = await fs.realpath(fileURLToPath(new URL('../../', import.meta.url)));
const packageRoot = join(root, 'admin-web');
const outputPaths = { fixture: 'build/admin-web-fixture', qualification: 'build/admin-web-qualification' };
const associationFiles = ['assetlinks.json', 'apple-app-site-association'];
const { build: sourcePaths } = JSON.parse(await fs.readFile(new URL('./source-inputs.json', import.meta.url), 'utf8'));
const sha256 = (data) => createHash('sha256').update(data).digest('hex');
const git = (args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
const json = (value) => JSON.stringify(value, null, 2) + '\n';

async function fileSha(path) {
  if (!(await fs.lstat(path)).isFile() || await fs.realpath(path) !== path) {
    throw new Error('Admin build inputs and outputs must be physical files.');
  }
  return sha256(await fs.readFile(path));
}

async function sourceIdentity() {
  const names = git(['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', ...sourcePaths])
    .split('\0').filter(Boolean);
  const entries = await Promise.all([...new Set(names)].sort().map(async name => [name, await fileSha(join(root, name))]));
  const missing = sourcePaths.filter(path => !names.some(name => name === path || name.startsWith(path + '/')));
  if (missing.length) throw new Error('React Admin build inputs missing from the Git inventory: ' + missing.join(', '));
  return {
    commit: git(['rev-parse', 'HEAD']).trim(),
    clean: git(['status', '--porcelain', '--untracked-files=normal', '--', ...sourcePaths]).length === 0,
    sha256: sha256(JSON.stringify(entries)),
  };
}

async function artifactIdentity(directory, base = directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(async entry => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return artifactIdentity(path, base);
    return [[relative(base, path).split(sep).join('/'), await fileSha(path)]];
  }));
  return files.flat().sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
}

function publicConfiguration(mode) {
  if (mode === 'fixture') {
    const origin = process.env.ADMIN_PWA_FIXTURE_ORIGIN ?? 'http://127.0.0.1:4175';
    const url = new URL(origin);
    if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || url.origin !== origin || !url.port) {
      throw new Error('React Admin fixture requires an explicit HTTP loopback port.');
    }
    return {
      defines: {
        VITE_ADMIN_EXPECTED_ORIGIN: origin, VITE_ADMIN_BACKEND: 'supabase',
        VITE_ADMIN_CAPTCHA_ENABLED: 'false', VITE_ADMIN_GOOGLE_ENABLED: 'false',
        VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_react_admin_local_fixture',
      },
    };
  }
  const script = [
    'import json, os, sys',
    'from pathlib import Path',
    'from scripts.supabase.admin_build_config import configuration',
    'print(json.dumps(configuration(dict(os.environ), Path.cwd(), qualification=sys.argv[1] == "qualification")))',
  ].join('\n');
  let validated;
  try {
    validated = JSON.parse(execFileSync('python3', ['-c', script, mode], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
  } catch {
    throw new Error('Supply the reviewed Admin origin, Supabase project, public key and security settings.');
  }
  const [settings, metadata] = validated;
  const defines = {
    VITE_ADMIN_EXPECTED_ORIGIN: settings.ADMIN_APP_URL, VITE_ADMIN_BACKEND: 'supabase',
    VITE_ADMIN_CAPTCHA_ENABLED: settings.AUTH_CAPTCHA_ENABLED, VITE_ADMIN_GOOGLE_ENABLED: settings.GOOGLE_AUTH_ENABLED,
    VITE_SUPABASE_PUBLISHABLE_KEY: settings.SUPABASE_PUBLISHABLE_KEY, VITE_SUPABASE_PROJECT_ORIGIN: settings.SUPABASE_URL,
  };
  return {
    defines,
    metadata: {
      ...metadata,
      environment: mode,
      public_build_config_sha256: sha256(JSON.stringify({ defines, settings, metadata })),
    },
  };
}

async function verify(output, action) {
  await fileSha(output + '.json');
  await verifyPwaPackage(output);
  const receipt = JSON.parse(await fs.readFile(output + '.json', 'utf8'));
  const files = await artifactIdentity(output);
  const source = await sourceIdentity();
  const version = JSON.parse(await fs.readFile(join(output, 'version.json'), 'utf8'));
  if (receipt.format !== 'collect.react-admin.build.v1' || receipt.hosted_verified !== false ||
      JSON.stringify(receipt.files) !== JSON.stringify(files) ||
      JSON.stringify(receipt.source) !== JSON.stringify(source) ||
      receipt.backend !== version.backend || receipt.build_config_sha256 !== version.public_build_config_sha256) {
    throw new Error('React Admin artifact, source, or release profile differs from the build receipt.');
  }
  if (action === 'verify-ci') {
    const { metadata } = publicConfiguration('production');
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
    const source = await sourceIdentity();
    const { defines, metadata } = publicConfiguration(mode);
    npm(['run', 'notices', '--', '--check']);
    npm(['exec', '--no', '--', 'vite', 'build', '--outDir', raw],
      { ...env, ...defines, NODE_ENV: 'production', ADMIN_ASSET_BASE: './' });
    if (JSON.stringify(await sourceIdentity()) !== JSON.stringify(source)) {
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
