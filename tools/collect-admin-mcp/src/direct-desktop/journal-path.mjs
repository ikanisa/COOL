import {
  closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync,
} from 'node:fs';
import { dirname, isAbsolute, join, normalize, parse } from 'node:path';
import { journalFailure } from './journal-data.mjs';

function optionalStat(path) {
  try {
    return lstatSync(path, { bigint: true });
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

function sameIdentity(left, right) {
  return left.dev === right.dev && left.ino === right.ino;
}

function checkDirectory(stat, privateDirectory) {
  if (!stat?.isDirectory() || (privateDirectory
      && (stat.uid !== BigInt(process.getuid()) || (stat.mode & 0o7777n) !== 0o700n))) {
    throw journalFailure('unsafe_journal_path');
  }
}

function checkFile(stat) {
  if (!stat?.isFile() || stat.uid !== BigInt(process.getuid()) || stat.nlink !== 1n
      || (stat.mode & 0o7777n) !== 0o600n) throw journalFailure('unsafe_journal_path');
}

/** Keeps the file and its directory chain bound to their original physical identities. */
export class PrivateJournalPath {
  #path;
  #file;
  #identity;
  #directories = [];

  constructor(path) {
    try {
      if (process.platform === 'win32' || typeof process.getuid !== 'function'
          || typeof path !== 'string' || !isAbsolute(path) || normalize(path) !== path
          || path.includes('\0') || path.endsWith('/') || Buffer.byteLength(path) > 4096 || dirname(path) === path) {
        throw journalFailure('unsafe_journal_path');
      }
      this.#path = path;
      this.#openPath();
    } catch (error) {
      this.close();
      throw error;
    }
  }

  get emptyAtOpen() { return this.#identity.size === 0n; }
  syncParent() { fsyncSync(this.#directories.at(-1).fd); }

  #openPath() {
    const parent = dirname(this.#path);
    const root = parse(parent).root;
    const paths = [root];
    let current = root;
    for (const component of parent.slice(root.length).split('/').filter(Boolean)) {
      current = join(current, component);
      paths.push(current);
    }
    for (const directory of paths) {
      let created = false;
      if (!optionalStat(directory)) {
        try {
          mkdirSync(directory, { mode: 0o700 });
          created = true;
        } catch (error) {
          if (error.code !== 'EEXIST') throw error;
        }
      }
      const privateDirectory = created || directory === parent;
      const stat = lstatSync(directory, { bigint: true });
      checkDirectory(stat, privateDirectory);
      const fd = openSync(directory, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_DIRECTORY);
      this.#directories.push({ path: directory, fd, identity: stat, privateDirectory });
      const opened = fstatSync(fd, { bigint: true });
      checkDirectory(opened, privateDirectory);
      if (!sameIdentity(stat, opened)) throw journalFailure('unsafe_journal_path');
      if (created) {
        fsyncSync(fd);
        fsyncSync(this.#directories.at(-2).fd);
      }
    }
    let stat = optionalStat(this.#path);
    if (stat) checkFile(stat);
    this.#checkSidecars();
    if (!stat) {
      try {
        this.#file = openSync(this.#path, constants.O_RDWR | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
        fsyncSync(this.#file);
        fsyncSync(this.#directories.at(-1).fd);
      } catch (error) {
        if (error.code !== 'EEXIST') throw error;
      }
      stat = lstatSync(this.#path, { bigint: true });
      checkFile(stat);
    }
    if (this.#file === undefined) {
      this.#file = openSync(this.#path, constants.O_RDWR | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    }
    this.#identity = fstatSync(this.#file, { bigint: true });
    checkFile(this.#identity);
    if (!sameIdentity(stat, this.#identity)) throw journalFailure('unsafe_journal_path');
  }

  #checkSidecars() {
    for (const suffix of ['-journal', '-wal', '-shm']) {
      const stat = optionalStat(this.#path + suffix);
      if (stat) checkFile(stat);
    }
  }

  assertCurrent() {
    for (const directory of this.#directories) {
      const stat = optionalStat(directory.path);
      checkDirectory(stat, directory.privateDirectory);
      const opened = fstatSync(directory.fd, { bigint: true });
      checkDirectory(opened, directory.privateDirectory);
      if (!sameIdentity(stat, directory.identity) || !sameIdentity(opened, directory.identity)) {
        throw journalFailure('unsafe_journal_path');
      }
    }
    const stat = optionalStat(this.#path);
    checkFile(stat);
    const opened = fstatSync(this.#file, { bigint: true });
    checkFile(opened);
    if (!sameIdentity(stat, this.#identity) || !sameIdentity(opened, this.#identity)) {
      throw journalFailure('unsafe_journal_path');
    }
    this.#checkSidecars();
  }

  close() {
    for (const fd of [this.#file, ...this.#directories.map(directory => directory.fd)]) {
      if (fd === undefined) continue;
      try { closeSync(fd); } catch { /* Continue releasing the remaining handles. */ }
    }
    this.#file = undefined;
    this.#directories = [];
  }
}
