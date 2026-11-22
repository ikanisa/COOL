import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { lstat, readFile, realpath } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scope = [
  '.dvmrc',
  '.supabase-cli-version',
  '.github/workflows/supabase.yml',
  'supabase',
  'deploy/collect-sms',
  'deploy/managed-sms',
  'deploy/managed-native-ingress',
  'scripts/make/supabase.mk',
  'scripts/supabase',
];

export async function currentInventory(directory) {
  const root = await realpath(directory);
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' });
  if (git('rev-parse', '--show-toplevel').trimEnd() !== root) {
    throw new Error('Run the Supabase inventory at the repository root.');
  }

  const names = (...args) => git(...args, '--', ...scope).split('\0').filter(Boolean);
  const committed = new Set(names('ls-tree', '-r', '-z', '--name-only', 'HEAD'));
  const indexed = names('ls-files', '--cached', '-z');
  const untracked = names('ls-files', '--others', '--exclude-standard', '-z');
  const modified = new Set(names('diff', 'HEAD', '--name-only', '--no-renames', '-z'));
  const files = [];
  for (const path of [...new Set([...committed, ...indexed, ...untracked])].sort()) {
    const fullPath = resolve(root, path);
    const entry = await lstat(fullPath).catch((error) => {
      if (error.code !== 'ENOENT') throw error;
      return null;
    });
    if (!entry) {
      files.push({ path, status: 'removed', bytes: null, sha256: null });
      continue;
    }
    if (!entry.isFile() || await realpath(fullPath) !== fullPath) {
      throw new Error('The Supabase inventory accepts only regular source files: ' + path);
    }
    const bytes = await readFile(fullPath);
    const status = !committed.has(path) ? 'added' : modified.has(path) ? 'modified' : 'retained';
    files.push({
      path,
      status,
      bytes: bytes.length,
      sha256: createHash('sha256').update(bytes).digest('hex'),
    });
  }
  return {
    format: 'collect.supabase.current-source-inventory.v1',
    base_commit: git('rev-parse', 'HEAD').trim(),
    scope,
    files,
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = await currentInventory(process.argv[2] ?? process.cwd());
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
