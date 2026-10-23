import { DatabaseSync } from 'node:sqlite';
import {
  closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync,
} from 'node:fs';
import { dirname, isAbsolute, join, normalize, parse } from 'node:path';
import { DesktopError } from './contract.mjs';

const MESSAGES = Object.freeze({
  journal_unavailable: 'Desktop journal is unavailable.',
  journal_corrupt: 'Desktop journal is corrupt or incompatible.',
  unsafe_journal_path: 'Desktop journal path is unsafe.',
});

const TABLES = Object.freeze([
  'tickets', 'jobs', 'attempts', 'observations', 'policies', 'syncs', 'control',
]);
const APPLICATION_ID = 0x43444a31;
const VERSION = 1;
const MAX_JSON_BYTES = 1024 * 1024;
const MAX_RESULT_BYTES = 16 * MAX_JSON_BYTES;
const MAX_ROWS = 100_000;
const MAX_NODES = 100_000;
const MAX_DEPTH = 64;
const DATA_COLUMN = `data TEXT NOT NULL CHECK (length(CAST(data AS BLOB)) BETWEEN 1 AND ${MAX_JSON_BYTES} AND json_valid(data))`;
const SCHEMA = new Map(TABLES.map((table) => [
  table, `CREATE TABLE ${table} (key TEXT PRIMARY KEY NOT NULL, ${DATA_COLUMN}) STRICT`,
]));
SCHEMA.set('events', `CREATE TABLE events (seq INTEGER PRIMARY KEY AUTOINCREMENT, ${DATA_COLUMN}) STRICT`);

function failure(code) {
  return new DesktopError(code, MESSAGES[code]);
}

function storageFailure(error) {
  if (error instanceof DesktopError) return error;
  if (['ELOOP', 'ENOTDIR'].includes(error?.code)) return failure('unsafe_journal_path');
  const code = Number(error?.errcode) & 255;
  return failure([11, 17, 19, 26].includes(code) ? 'journal_corrupt' : 'journal_unavailable');
}

function validateJson(value, code) {
  let nodes = 0;
  let bytes = 0;
  const ancestors = new Set();
  function visit(item, depth) {
    if (++nodes > MAX_NODES || depth > MAX_DEPTH) throw failure(code);
    if (item === null || typeof item === 'boolean') return;
    if (typeof item === 'number') {
      if (!Number.isFinite(item)) throw failure(code);
      return;
    }
    if (typeof item === 'string') {
      bytes += Buffer.byteLength(item);
    } else if (typeof item === 'object') {
      if (ancestors.has(item)) throw failure(code);
      const array = Array.isArray(item);
      const prototype = Object.getPrototypeOf(item);
      if (!array && prototype !== Object.prototype && prototype !== null) throw failure(code);
      if (Object.getOwnPropertySymbols(item).length) throw failure(code);
      const keys = Object.keys(item);
      if (keys.length > MAX_NODES || (array && keys.length !== item.length)) throw failure(code);
      ancestors.add(item);
      for (const key of keys) {
        if (array && (!/^(0|[1-9][0-9]*)$/.test(key) || Number(key) >= item.length)) throw failure(code);
        bytes += Buffer.byteLength(key);
        if (bytes > MAX_JSON_BYTES) throw failure(code);
        const descriptor = Object.getOwnPropertyDescriptor(item, key);
        if (!descriptor || !Object.hasOwn(descriptor, 'value')) throw failure(code);
        visit(descriptor.value, depth + 1);
      }
      ancestors.delete(item);
    } else {
      throw failure(code);
    }
    if (bytes > MAX_JSON_BYTES) throw failure(code);
  }
  visit(value, 0);
}

function encode(value) {
  try {
    validateJson(value, 'journal_unavailable');
    const data = JSON.stringify(value);
    if (typeof data !== 'string' || Buffer.byteLength(data) > MAX_JSON_BYTES) throw failure('journal_unavailable');
    return data;
  } catch {
    throw failure('journal_unavailable');
  }
}

function decode(data) {
  try {
    if (typeof data !== 'string' || Buffer.byteLength(data) > MAX_JSON_BYTES) throw failure('journal_corrupt');
    const value = JSON.parse(data);
    validateJson(value, 'journal_corrupt');
    return value;
  } catch {
    throw failure('journal_corrupt');
  }
}

function values(rows) {
  const result = [];
  let bytes = 0;
  for (const data of rows) {
    if (typeof data !== 'string') throw failure('journal_corrupt');
    bytes += Buffer.byteLength(data);
    if (result.length >= MAX_ROWS || bytes > MAX_RESULT_BYTES) throw failure('journal_corrupt');
    result.push(decode(data));
  }
  return result;
}

function tableName(table) {
  if (!TABLES.includes(table)) throw failure('journal_unavailable');
  return table;
}

function keyName(key) {
  if (typeof key !== 'string' || Buffer.byteLength(key) > 4096 || key.includes('\0')) {
    throw failure('journal_unavailable');
  }
  return key;
}

function runAction(action, operations) {
  let active = true;
  let failed;
  const tx = Object.freeze(Object.fromEntries(Object.entries(operations).map(([name, operation]) => [
    name, (...args) => {
      if (!active) throw failure('journal_unavailable');
      if (failed) throw failed;
      try {
        return operation(...args);
      } catch (error) {
        failed = storageFailure(error);
        throw failed;
      }
    },
  ])));
  try {
    if (typeof action !== 'function') throw failure('journal_unavailable');
    const result = action(tx);
    if (result !== null && (typeof result === 'object' || typeof result === 'function')
        && typeof result.then === 'function') {
      // Consume a rejected async continuation after its transaction has been revoked.
      Promise.resolve(result).catch(() => {});
      throw failure('journal_unavailable');
    }
    if (failed) throw failed;
    return result;
  } finally {
    active = false;
  }
}

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
    throw failure('unsafe_journal_path');
  }
}

function checkFile(stat) {
  if (!stat?.isFile() || stat.uid !== BigInt(process.getuid()) || stat.nlink !== 1n
      || (stat.mode & 0o7777n) !== 0o600n) throw failure('unsafe_journal_path');
}

export class SqliteDesktopJournal {
  #db;
  #path;
  #file;
  #identity;
  #directories = [];
  #busy = false;
  #closed = false;

  get durable() { return true; }

  constructor(path) {
    try {
      if (process.platform === 'win32' || typeof process.getuid !== 'function'
          || typeof path !== 'string' || !isAbsolute(path) || normalize(path) !== path
          || path.includes('\0') || path.endsWith('/') || Buffer.byteLength(path) > 4096 || dirname(path) === path) {
        throw failure('unsafe_journal_path');
      }
      this.#path = path;
      this.#openPath();
      const initialize = this.#identity.size === 0n;
      this.#checkPath();
      this.#db = new DatabaseSync(path, {
        allowExtension: false, enableDoubleQuotedStringLiterals: false,
        enableForeignKeyConstraints: true, timeout: 500,
      });
      this.#db.exec('PRAGMA busy_timeout=500; PRAGMA trusted_schema=OFF; PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; PRAGMA temp_store=MEMORY');
      this.#checkPath();
      this.#db.exec('BEGIN');
      this.#checkSchema(initialize);
      this.#db.exec('COMMIT');
      if (this.#db.prepare('PRAGMA journal_mode').get().journal_mode !== 'delete') throw failure('journal_corrupt');
      this.#db.exec('PRAGMA journal_mode=DELETE');
      this.#db.exec('BEGIN IMMEDIATE');
      this.#checkPath();
      if (this.#checkSchema(initialize)) {
        for (const sql of SCHEMA.values()) this.#db.exec(sql);
        this.#db.exec(`PRAGMA application_id=${APPLICATION_ID}; PRAGMA user_version=${VERSION}`);
      }
      this.#checkSchema(false);
      const check = this.#db.prepare('PRAGMA quick_check(1)').all();
      if (check.length !== 1 || check[0].quick_check !== 'ok') throw failure('journal_corrupt');
      this.#checkPath();
      this.#db.exec('COMMIT');
      fsyncSync(this.#directories.at(-1).fd);
      this.#checkPath();
    } catch (error) {
      this.#dispose();
      throw storageFailure(error);
    }
  }

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
      if (!sameIdentity(stat, opened)) throw failure('unsafe_journal_path');
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
    if (!sameIdentity(stat, this.#identity)) throw failure('unsafe_journal_path');
  }

  #checkSidecars() {
    for (const suffix of ['-journal', '-wal', '-shm']) {
      const stat = optionalStat(this.#path + suffix);
      if (stat) checkFile(stat);
    }
  }

  #checkPath() {
    for (const directory of this.#directories) {
      const stat = optionalStat(directory.path);
      checkDirectory(stat, directory.privateDirectory);
      const opened = fstatSync(directory.fd, { bigint: true });
      checkDirectory(opened, directory.privateDirectory);
      if (!sameIdentity(stat, directory.identity) || !sameIdentity(opened, directory.identity)) {
        throw failure('unsafe_journal_path');
      }
    }
    const stat = optionalStat(this.#path);
    checkFile(stat);
    const opened = fstatSync(this.#file, { bigint: true });
    checkFile(opened);
    if (!sameIdentity(stat, this.#identity) || !sameIdentity(opened, this.#identity)) {
      throw failure('unsafe_journal_path');
    }
    this.#checkSidecars();
  }

  #checkSchema(initialize) {
    const application = this.#db.prepare('PRAGMA application_id').get().application_id;
    const version = this.#db.prepare('PRAGMA user_version').get().user_version;
    const schema = this.#db.prepare(`SELECT type, name, sql FROM sqlite_schema WHERE substr(name,1,7) <> 'sqlite_' ORDER BY name LIMIT ${SCHEMA.size + 1}`).all();
    // BEGIN IMMEDIATE allocates page 1 before the first table is created.
    if (initialize && application === 0 && version === 0 && schema.length === 0
        && this.#db.prepare('PRAGMA page_count').get().page_count <= (this.#db.isTransaction ? 1 : 0)) return true;
    if (application !== APPLICATION_ID || version !== VERSION || schema.length !== SCHEMA.size
        || schema.some((row) => row.type !== 'table' || SCHEMA.get(row.name) !== row.sql)) {
      throw failure('journal_corrupt');
    }
    return false;
  }

  #rows(sql) {
    return values((function* (statement) {
      for (const row of statement.iterate()) yield row.data;
    })(this.#db.prepare(sql)));
  }

  #run(action, callback = false) {
    if (this.#closed || this.#busy) throw failure('journal_unavailable');
    this.#busy = true;
    let callbackError;
    try {
      this.#checkPath();
      this.#db.exec('BEGIN IMMEDIATE');
      this.#checkPath();
      this.#checkSchema(false);
      let result;
      try {
        result = action();
      } catch (error) {
        if (callback) callbackError = { error };
        throw error;
      }
      this.#checkPath();
      this.#db.exec('COMMIT');
      fsyncSync(this.#directories.at(-1).fd);
      this.#checkPath();
      return result;
    } catch (error) {
      try {
        if (this.#db.isTransaction) this.#db.exec('ROLLBACK');
      } catch {
        this.#dispose();
      }
      if (callbackError) throw callbackError.error;
      throw storageFailure(error);
    } finally {
      this.#busy = false;
    }
  }

  transaction(action) {
    return this.#run(() => runAction(action, {
      get: (table, key) => {
        const row = this.#db.prepare(`SELECT data FROM ${tableName(table)} WHERE key=?`).get(keyName(key));
        return row ? decode(row.data) : null;
      },
      put: (table, key, value) => {
        const sql = `INSERT INTO ${tableName(table)} (key, data) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET data=excluded.data`;
        this.#db.prepare(sql).run(keyName(key), encode(value));
      },
      all: (table) => this.#rows(`SELECT data FROM ${tableName(table)} ORDER BY key`),
      append: (event) => { this.#db.prepare('INSERT INTO events (data) VALUES (?)').run(encode(event)); },
    }), true);
  }

  events() {
    return this.#run(() => this.#rows('SELECT data FROM events ORDER BY seq'));
  }

  #dispose() {
    this.#closed = true;
    if (this.#db?.isOpen) {
      try { this.#db.close(); } catch { /* Preserve the original safe failure. */ }
    }
    for (const fd of [this.#file, ...this.#directories.map((directory) => directory.fd)]) {
      if (fd !== undefined) {
        try { closeSync(fd); } catch { /* Continue releasing the remaining handles. */ }
      }
    }
    this.#file = undefined;
    this.#directories = [];
  }

  close() {
    if (this.#busy) throw failure('journal_unavailable');
    if (this.#closed) return;
    this.#dispose();
  }
}

export class MemoryDesktopJournal {
  #tables = new Map(TABLES.map((table) => [table, new Map()]));
  #events = [];
  #closed = false;
  #busy = false;

  get durable() { return false; }

  transaction(action) {
    if (this.#closed || this.#busy) throw failure('journal_unavailable');
    this.#busy = true;
    const tables = new Map([...this.#tables].map(([table, data]) => [table, new Map(data)]));
    const events = [...this.#events];
    try {
      const result = runAction(action, {
        get: (table, key) => {
          const data = tables.get(tableName(table)).get(keyName(key));
          return data === undefined ? null : decode(data);
        },
        put: (table, key, value) => { tables.get(tableName(table)).set(keyName(key), encode(value)); },
        all: (table) => values([...tables.get(tableName(table))].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([, data]) => data)),
        append: (event) => { events.push(encode(event)); },
      });
      this.#tables = tables;
      this.#events = events;
      return result;
    } finally {
      this.#busy = false;
    }
  }

  events() {
    if (this.#closed || this.#busy) throw failure('journal_unavailable');
    return values(this.#events);
  }

  close() {
    if (this.#busy) throw failure('journal_unavailable');
    this.#closed = true;
  }
}
