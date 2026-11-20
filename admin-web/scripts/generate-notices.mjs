import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const lockPath = path.join(root, 'package-lock.json');
const target = path.join(root, 'src/generated/notices.json');
const hash = (value) => createHash('sha256').update(value).digest('hex');

async function textFile(file) {
  const data = await fs.readFile(file);
  if (!data.length || data.length > 262144) throw new Error(`Invalid license file: ${file}`);
  return {text: new TextDecoder('utf-8', {fatal: true}).decode(data), sha256: hash(data)};
}

/** Create deterministic, offline notices from the locked production dependency set. */
export async function notices() {
  const lockBytes = await fs.readFile(lockPath);
  const lock = JSON.parse(lockBytes.toString('utf8'));
  if (!lock.packages || typeof lock.packages !== 'object') throw new Error('Invalid package lock');
  const entries = Object.entries(lock.packages).filter(([name, item]) =>
    name.startsWith('node_modules/') && item && typeof item === 'object' && !item.dev).sort(([a], [b]) => a.localeCompare(b));
  if (!entries.length) throw new Error('No locked production packages');
  const packages = [];
  for (const [relative, item] of entries) {
    if (!/^node_modules\/(?:@[A-Za-z0-9._-]+\/)?[A-Za-z0-9._-]+(?:\/node_modules\/(?:@[A-Za-z0-9._-]+\/)?[A-Za-z0-9._-]+)*$/.test(relative) ||
        typeof item.version !== 'string' || typeof item.license !== 'string') throw new Error('Invalid package lock entry');
    const directory = path.join(root, relative);
    const metadata = JSON.parse(await fs.readFile(path.join(directory, 'package.json'), 'utf8'));
    if (metadata.version !== item.version || typeof metadata.name !== 'string') throw new Error(`Installed package differs from lock: ${relative}`);
    const files = (await fs.readdir(directory)).filter((name) => /^(?:license|copying|notice)(?:\.[A-Za-z0-9_-]+)?$/i.test(name)).sort();
    if (!files.length) throw new Error(`No bundled license text: ${metadata.name}`);
    const licenseFiles = [];
    for (const file of files) licenseFiles.push({file, ...await textFile(path.join(directory, file))});
    packages.push({name: metadata.name, version: item.version, license: item.license, notices: licenseFiles});
  }
  const font = await textFile(path.join(root, 'public/licenses/OFL-Inter.txt'));
  return {format: 'collect.admin.notices.v1', lock_sha256: hash(lockBytes), packages,
    assets: [{name: 'Inter', license: 'OFL-1.1', notices: [{file: 'OFL-Inter.txt', ...font}]}]};
}

const output = `${JSON.stringify(await notices(), null, 2)}\n`;
if (process.argv.includes('--check')) {
  if (await fs.readFile(target, 'utf8').catch(() => '') !== output) {
    console.error('Admin license notices do not match the current lock and installed license files.');
    process.exitCode = 1;
  } else console.log('Admin license notices match the locked packages.');
} else {
  await fs.mkdir(path.dirname(target), {recursive: true});
  await fs.writeFile(target, output);
  console.log('Generated offline Admin license notices.');
}
