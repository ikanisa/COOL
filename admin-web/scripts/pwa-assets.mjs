import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const templatePath = path.resolve(here, '../../scripts/templates/admin_pwa_service_worker.js');
export const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
export const expectedIconHash = 'cae23ce3562e8aac2e248e7b22f7feed194f4fcfd2b57725ec1026f064bb0ad9';

export async function filesUnder(root, directory = root) {
  const files = [];
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('._') || entry.name === '.DS_Store') continue;
    const absolute = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error('Static build must not contain symlinks');
    if (entry.isDirectory()) files.push(...await filesUnder(root, absolute));
    else if (entry.isFile()) {
      const name = path.relative(root, absolute).split(path.sep).join('/');
      if (!/^[A-Za-z0-9._/-]+$/.test(name) || name.split('/').includes('..')) {
        throw new Error('Static build contains an invalid asset name');
      }
      files.push(name);
    } else throw new Error('Static build contains a non-regular asset');
  }
  return files.sort();
}

function replaceOnce(source, marker, value) {
  if (source.split(marker).length !== 2) throw new Error(`Invalid worker template: ${marker}`);
  return source.replace(marker, value);
}

export function renderWorker(template, urls, hashes) {
  const cacheId = sha256(`${sha256(template)}\n${JSON.stringify(hashes)}`).slice(0, 16);
  let worker = replaceOnce(template, '__COLLECT_ADMIN_CACHE_NAME__', JSON.stringify(`collect-admin-${cacheId}`));
  worker = replaceOnce(worker, '__COLLECT_ADMIN_CACHE_URLS__', JSON.stringify(urls));
  worker = replaceOnce(worker, '__COLLECT_ADMIN_CACHE_HASHES__', JSON.stringify(hashes));
  return { cacheId, worker };
}

export function versionedAssetHash(entries) {
  return sha256(entries.map(([name, digest]) => `${name}\0${digest}`).join('\n'));
}

export function cacheAsset(root, url) {
  return path.join(root, url === './' ? 'index.html' : url.slice(2));
}
