import {constants} from 'node:fs';
import {lstat, mkdir, open} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {canonical, need, sha} from './contract.mjs';

export async function privateDirectory(path, {create = false} = {}) {
  need(typeof path === 'string' && resolve(path) === path && !/[\x00-\x1f\x7f]/.test(path), 'absolute_private_directory_required');
  if (create) await mkdir(path, {mode: 0o700});

  const stat = await lstat(path);
  need(!stat.isSymbolicLink(), 'aliased_private_state_refused');
  for (let ancestor = dirname(path); ancestor !== '/'; ancestor = dirname(ancestor)) {
    need(!(await lstat(ancestor)).isSymbolicLink(), 'aliased_private_state_refused');
  }
  need(stat.isDirectory() && stat.uid === process.getuid() && (stat.mode & 0o077) === 0, 'private_owned_directory_required');
  return path;
}

function privateFile(stat, max) {
  return stat.isFile() && stat.nlink === 1 && stat.uid === process.getuid() &&
    (stat.mode & 0o077) === 0 && stat.size <= max;
}

function sameVersion(first, second) {
  return first.ino === second.ino && first.dev === second.dev && first.size === second.size &&
    first.mtimeMs === second.mtimeMs && first.ctimeMs === second.ctimeMs;
}

export async function privateRead(path, {max = 65536} = {}) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = await file.stat();
    need(privateFile(before, max), 'private_owned_regular_file_required');
    const buffer = Buffer.alloc(before.size + 1);
    let offset = 0;
    while (offset < buffer.length) {
      const {bytesRead} = await file.read(buffer, offset, buffer.length - offset, offset);
      if (bytesRead === 0) break;
      offset += bytesRead;
    }

    const after = await file.stat();
    const named = await lstat(path);
    need(offset === before.size && privateFile(after, max) && privateFile(named, max) &&
      sameVersion(before, named) && sameVersion(before, after), 'private_file_changed');
    return {raw: buffer.subarray(0, offset), stat: after};
  } finally {
    await file.close();
  }
}

export async function privateWrite(path, value) {
  const raw = Buffer.from(canonical(value) + '\n');
  const file = await open(path, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  try {
    await file.writeFile(raw);
    await file.sync();
  } finally {
    await file.close();
  }

  const parent = await open(dirname(path), constants.O_RDONLY | constants.O_DIRECTORY);
  try {
    await parent.sync();
  } finally {
    await parent.close();
  }
  return sha(raw);
}
