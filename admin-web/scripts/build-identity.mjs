import { execFileSync } from 'node:child_process';
import { promises as fs } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { sha256 } from './pwa-assets.mjs';

const { build: sourcePaths } = JSON.parse(await fs.readFile(new URL('./source-inputs.json', import.meta.url), 'utf8'));

export async function readBuildFile(path) {
  if (!(await fs.lstat(path)).isFile() || await fs.realpath(path) !== path) {
    throw new Error('Admin build inputs and outputs must be physical files.');
  }
  return fs.readFile(path);
}

async function fileSha(path) {
  return sha256(await readBuildFile(path));
}

export async function sourceIdentity(root) {
  const git = (args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  const deleted = new Set(git(['ls-files', '-z', '--deleted', '--', ...sourcePaths]).split('\0'));
  const names = git(['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', ...sourcePaths])
    .split('\0').filter(name => name && !deleted.has(name));
  const entries = await Promise.all([...new Set(names)].sort().map(async name => [name, await fileSha(join(root, name))]));
  const missing = sourcePaths.filter(path => !names.some(name => name === path || name.startsWith(path + '/')));
  if (missing.length) throw new Error('React Admin build inputs missing from the Git inventory: ' + missing.join(', '));
  return {
    commit: git(['rev-parse', 'HEAD']).trim(),
    clean: git(['status', '--porcelain', '--untracked-files=normal', '--', ...sourcePaths]).length === 0,
    sha256: sha256(JSON.stringify(entries)),
  };
}

export async function artifactIdentity(directory, base = directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(async entry => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return artifactIdentity(path, base);
    return [[relative(base, path).split(sep).join('/'), await fileSha(path)]];
  }));
  return files.flat().sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
}
