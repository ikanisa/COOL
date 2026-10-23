import test from 'node:test';
import assert from 'node:assert/strict';
import {
  chmodSync, copyFileSync, existsSync, linkSync, lstatSync, mkdirSync, mkdtempSync,
  readFileSync, realpathSync, renameSync, rmSync, statfsSync, symlinkSync, unlinkSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { DesktopError } from '../src/direct-desktop/contract.mjs';
import {
  MemoryDesktopJournal, SqliteDesktopJournal,
} from '../src/direct-desktop/journal.mjs';

const JOURNAL_URL = new URL('../src/direct-desktop/journal.mjs', import.meta.url).href;
const TABLES = ['tickets', 'jobs', 'attempts', 'observations', 'policies', 'syncs', 'control'];
const MESSAGES = {
  journal_unavailable: 'Desktop journal is unavailable.',
  journal_corrupt: 'Desktop journal is corrupt or incompatible.',
  unsafe_journal_path: 'Desktop journal path is unsafe.',
};

function safeError(code) {
  return (error) => {
    assert.ok(error instanceof DesktopError);
    assert.equal(error.code, code);
    assert.equal(error.message, MESSAGES[code]);
    assert.equal(error.cause, undefined);
    return true;
  };
}

function fixture(t) {
  const root = realpathSync(tmpdir());
  if (process.platform === 'darwin') assert.equal(statfsSync(root).type, 26, 'journal fixtures must use APFS');
  const directory = mkdtempSync(join(root, 'collect-desktop-journal-'));
  assert.equal(lstatSync(directory).mode & 0o7777, 0o700);
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return { directory, path: join(directory, 'journal.sqlite') };
}

function diskJournal(t, path = fixture(t).path) {
  const journal = new SqliteDesktopJournal(path);
  t.after(() => journal.close());
  return journal;
}

function worker(t, source, path) {
  const child = spawn(process.execPath, ['--input-type=module', '--eval', source, JOURNAL_URL, path], {
    stdio: ['ignore', 'ignore', 'pipe', 'ipc'],
  });
  let diagnostic = '';
  child.stderr.on('data', (data) => { diagnostic = (diagnostic + data).slice(0, 2048); });
  const messages = [];
  const pending = [];
  child.on('message', (message) => {
    if (pending.length) pending.shift().resolve(message);
    else messages.push(message);
  });
  const done = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => {
      for (const waiter of pending.splice(0)) waiter.reject(new Error('Worker exited before its checkpoint.'));
      resolve({ code, signal, diagnostic });
    });
  });
  const timeout = setTimeout(() => child.kill('SIGKILL'), 15_000);
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
    await done;
    clearTimeout(timeout);
  });
  done.finally(() => clearTimeout(timeout));
  return {
    child, done,
    next: () => messages.length ? Promise.resolve(messages.shift())
      : new Promise((resolve, reject) => pending.push({ resolve, reject })),
  };
}

for (const [name, create, durable] of [
  ['memory', (t) => { const journal = new MemoryDesktopJournal(); t.after(() => journal.close()); return journal; }, false],
  ['sqlite', diskJournal, true],
]) {
  test(`${name}: synchronous transactions preserve arbitrary JSON and detach stored values`, (t) => {
    const journal = create(t);
    assert.equal(journal.durable, durable);
    const input = { arbitrary: ['payload', null, false, 0], __proto_field: 'kept' };
    const result = journal.transaction((tx) => {
      for (const table of TABLES) {
        assert.equal(tx.get(table, 'missing'), null);
        assert.equal(tx.put(table, 'key', input), undefined);
        assert.deepEqual(tx.all(table), [input]);
      }
      assert.equal(tx.append({ core_supplied: 'no event schema imposed' }), undefined);
      tx.append(['any', 'JSON', 1]);
      tx.append(null);
      tx.put('control', "__proto__'); DROP TABLE jobs; --", false);
      return 123;
    });
    assert.equal(result, 123);
    input.arbitrary.push('changed');
    journal.transaction((tx) => {
      const stored = tx.get('jobs', 'key');
      assert.deepEqual(stored.arbitrary, ['payload', null, false, 0]);
      stored.arbitrary.push('not saved');
      tx.all('jobs')[0].arbitrary.push('also not saved');
      assert.equal(tx.get('control', "__proto__'); DROP TABLE jobs; --"), false);
    });
    assert.deepEqual(journal.transaction((tx) => tx.get('jobs', 'key')).arbitrary, ['payload', null, false, 0]);
    const events = journal.events();
    assert.deepEqual(events, [{ core_supplied: 'no event schema imposed' }, ['any', 'JSON', 1], null]);
    events[0].core_supplied = 'changed';
    assert.equal(journal.events()[0].core_supplied, 'no event schema imposed');
  });

  test(`${name}: callback errors roll back every table and event and preserve DesktopError identity`, (t) => {
    const journal = create(t);
    journal.transaction((tx) => { tx.put('control', 'original', { count: 1 }); tx.append('committed'); });
    const injected = new DesktopError('core_rollback_required');
    let retained;
    assert.throws(() => journal.transaction((tx) => {
      retained = tx;
      for (const table of TABLES) tx.put(table, 'temporary', { count: 2 });
      tx.put('control', 'original', { count: 3 });
      tx.append('uncommitted');
      throw injected;
    }), (error) => error === injected);
    journal.transaction((tx) => {
      for (const table of TABLES) assert.equal(tx.get(table, 'temporary'), null);
      assert.deepEqual(tx.get('control', 'original'), { count: 1 });
    });
    assert.deepEqual(journal.events(), ['committed']);
    assert.throws(() => retained.append('late'), safeError('journal_unavailable'));
  });

  test(`${name}: async callbacks and escaped handles cannot commit partial state`, async (t) => {
    const journal = create(t);
    assert.throws(() => journal.transaction(async (tx) => {
      tx.put('jobs', 'async', { started: true });
      tx.append('before await');
      await Promise.resolve();
      tx.put('jobs', 'async', { finished: true });
    }), safeError('journal_unavailable'));
    assert.throws(() => journal.transaction((tx) => {
      tx.put('jobs', 'promise', 1);
      return Promise.reject(new Error('private async diagnostic'));
    }), safeError('journal_unavailable'));
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(journal.transaction((tx) => tx.all('jobs')), []);
    assert.deepEqual(journal.events(), []);
    let retained;
    journal.transaction((tx) => { retained = tx; });
    assert.throws(() => retained.put('jobs', 'escaped', 1), safeError('journal_unavailable'));
  });

  test(`${name}: invalid JSON, bounds, tables and keys fail closed even when caught by the callback`, (t) => {
    const journal = create(t);
    const cyclic = {}; cyclic.self = cyclic;
    let deep = 0;
    for (let i = 0; i < 66; i++) deep = [deep];
    let accessed = false;
    const accessor = { get secret() { accessed = true; return 'not JSON data'; } };
    const badValues = [undefined, NaN, Infinity, 1n, () => {}, cyclic, deep, new Date(),
      { missing: undefined }, Array(1), accessor, 'x'.repeat(1024 * 1024)];
    for (const value of badValues) {
      assert.throws(() => journal.transaction((tx) => {
        tx.put('jobs', 'partial', 'must roll back');
        try { tx.append(value); } catch { /* A caught operation error still aborts. */ }
      }), safeError('journal_unavailable'));
    }
    assert.equal(accessed, false);
    for (const table of ['events', 'sqlite_schema', '__proto__', 'jobs; DELETE FROM jobs']) {
      assert.throws(() => journal.transaction((tx) => tx.all(table)), safeError('journal_unavailable'));
    }
    for (const key of [null, 1, '\0', 'x'.repeat(4097)]) {
      assert.throws(() => journal.transaction((tx) => tx.put('jobs', key, 1)), safeError('journal_unavailable'));
    }
    assert.deepEqual(journal.transaction((tx) => tx.all('jobs')), []);
    assert.deepEqual(journal.events(), []);
  });

  test(`${name}: nested transactions and closed journals fail without losing prior commits`, (t) => {
    const journal = create(t);
    journal.transaction((tx) => tx.put('control', 'saved', 1));
    assert.throws(() => journal.transaction(() => journal.transaction(() => {})), safeError('journal_unavailable'));
    assert.throws(() => journal.transaction(() => journal.close()), safeError('journal_unavailable'));
    assert.equal(journal.transaction((tx) => tx.get('control', 'saved')), 1);
    journal.close(); journal.close();
    assert.throws(() => journal.transaction(() => {}), safeError('journal_unavailable'));
    assert.throws(() => journal.events(), safeError('journal_unavailable'));
  });
}

test('sqlite: creates private nested storage and persists committed event order across reopen', (t) => {
  const { directory } = fixture(t);
  const parent = join(directory, 'new', 'private');
  const path = join(parent, 'journal.sqlite');
  const journal = diskJournal(t, path);
  assert.equal(lstatSync(join(directory, 'new')).mode & 0o7777, 0o700);
  assert.equal(lstatSync(parent).mode & 0o7777, 0o700);
  assert.equal(lstatSync(path).mode & 0o7777, 0o600);
  assert.equal(lstatSync(path).uid, process.getuid());
  assert.equal(lstatSync(path).nlink, 1);
  journal.transaction((tx) => { tx.put('tickets', 'ticket', { ready: true }); tx.append('first'); });
  assert.throws(() => journal.transaction((tx) => { tx.append('rolled back'); throw new DesktopError('rollback'); }));
  journal.transaction((tx) => tx.append('second'));
  journal.close();
  const reopened = diskJournal(t, path);
  assert.deepEqual(reopened.transaction((tx) => tx.get('tickets', 'ticket')), { ready: true });
  assert.deepEqual(reopened.events(), ['first', 'second']);
  reopened.transaction((tx) => tx.append('third'));
  reopened.close();
  const db = new DatabaseSync(path);
  try {
    assert.equal(db.prepare('PRAGMA journal_mode').get().journal_mode, 'delete');
    assert.deepEqual(db.prepare('SELECT seq FROM events ORDER BY seq').all().map((row) => row.seq), [1, 2, 3]);
  } finally { db.close(); }
  assert.equal(existsSync(path + '-wal'), false);
  assert.equal(existsSync(path + '-shm'), false);
});

test('sqlite: rejects noncanonical paths and unsafe existing directories without changing their permissions', (t) => {
  const { directory, path } = fixture(t);
  for (const candidate of ['journal.sqlite', path + '/', directory + '/./journal.sqlite', directory + '//journal.sqlite', path + '\0']) {
    assert.throws(() => new SqliteDesktopJournal(candidate), safeError('unsafe_journal_path'));
  }
  chmodSync(directory, 0o755);
  assert.throws(() => new SqliteDesktopJournal(path), safeError('unsafe_journal_path'));
  assert.equal(lstatSync(directory).mode & 0o7777, 0o755);
  assert.equal(existsSync(path), false);
});

test('sqlite: rejects leaf symlinks, hardlinks, nonregular files and insecure modes without touching targets', (t) => {
  const { directory, path } = fixture(t);
  const target = join(directory, 'target');
  writeFileSync(target, 'private existing bytes', { mode: 0o600 });
  symlinkSync(target, path);
  assert.throws(() => new SqliteDesktopJournal(path), safeError('unsafe_journal_path'));
  assert.equal(readFileSync(target, 'utf8'), 'private existing bytes');
  unlinkSync(path);
  linkSync(target, path);
  assert.throws(() => new SqliteDesktopJournal(path), safeError('unsafe_journal_path'));
  unlinkSync(path);
  mkdirSync(path, { mode: 0o700 });
  assert.throws(() => new SqliteDesktopJournal(path), safeError('unsafe_journal_path'));
  rmSync(path, { recursive: true });
  writeFileSync(path, 'private existing bytes', { mode: 0o644 });
  chmodSync(path, 0o644);
  assert.throws(() => new SqliteDesktopJournal(path), safeError('unsafe_journal_path'));
  assert.equal(lstatSync(path).mode & 0o7777, 0o644);
  assert.equal(readFileSync(path, 'utf8'), 'private existing bytes');
});

test('sqlite: rejects symlink ancestors before creating storage', (t) => {
  const { directory } = fixture(t);
  const target = join(directory, 'real');
  mkdirSync(target, { mode: 0o700 });
  const alias = join(directory, 'alias');
  symlinkSync(target, alias);
  assert.throws(() => new SqliteDesktopJournal(join(alias, 'new', 'journal.sqlite')), safeError('unsafe_journal_path'));
  assert.equal(existsSync(join(target, 'new')), false);
});

for (const suffix of ['-journal', '-wal', '-shm']) {
  test(`sqlite: rejects dangerous preexisting ${suffix} sidecars`, (t) => {
    const { directory, path } = fixture(t);
    const sidecar = path + suffix;
    const target = join(directory, 'sidecar-target');
    writeFileSync(target, 'do not modify', { mode: 0o600 });
    symlinkSync(target, sidecar);
    assert.throws(() => new SqliteDesktopJournal(path), safeError('unsafe_journal_path'));
    assert.equal(existsSync(path), false);
    assert.equal(readFileSync(target, 'utf8'), 'do not modify');
    unlinkSync(sidecar);
    writeFileSync(sidecar, 'unsafe mode', { mode: 0o644 });
    chmodSync(sidecar, 0o644);
    assert.throws(() => new SqliteDesktopJournal(path), safeError('unsafe_journal_path'));
    assert.equal(lstatSync(sidecar).mode & 0o7777, 0o644);
    unlinkSync(sidecar);
    linkSync(target, sidecar);
    assert.throws(() => new SqliteDesktopJournal(path), safeError('unsafe_journal_path'));
  });
}

test('sqlite: checks file and ancestor identity before every transaction and read', (t) => {
  const { directory, path } = fixture(t);
  const journal = diskJournal(t, path);
  journal.transaction((tx) => tx.put('control', 'saved', 1));
  const moved = join(directory, 'moved.sqlite');
  renameSync(path, moved);
  copyFileSync(moved, path);
  chmodSync(path, 0o600);
  let called = false;
  assert.throws(() => journal.transaction(() => { called = true; }), safeError('unsafe_journal_path'));
  assert.equal(called, false);
  assert.throws(() => journal.events(), safeError('unsafe_journal_path'));
  journal.close();

  const nested = join(directory, 'parent');
  const nestedPath = join(nested, 'journal.sqlite');
  const other = diskJournal(t, nestedPath);
  renameSync(nested, nested + '-moved');
  mkdirSync(nested, { mode: 0o700 });
  copyFileSync(join(nested + '-moved', 'journal.sqlite'), nestedPath);
  chmodSync(nestedPath, 0o600);
  assert.throws(() => other.transaction(() => {}), safeError('unsafe_journal_path'));
});

test('sqlite: metadata or link changes during a callback abort its writes and events', (t) => {
  const { directory, path } = fixture(t);
  const journal = diskJournal(t, path);
  journal.transaction((tx) => tx.put('control', 'saved', 1));
  const alias = join(directory, 'hardlink');
  assert.throws(() => journal.transaction((tx) => {
    tx.put('control', 'saved', 2);
    tx.append('uncommitted');
    linkSync(path, alias);
  }), safeError('unsafe_journal_path'));
  unlinkSync(alias);
  assert.equal(journal.transaction((tx) => tx.get('control', 'saved')), 1);
  assert.deepEqual(journal.events(), []);
  assert.throws(() => journal.transaction((tx) => {
    tx.put('control', 'saved', 3);
    chmodSync(directory, 0o755);
  }), safeError('unsafe_journal_path'));
  chmodSync(directory, 0o700);
  assert.equal(journal.transaction((tx) => tx.get('control', 'saved')), 1);
});

test('sqlite: rejects corrupt bytes with safe diagnostics', (t) => {
  const { path } = fixture(t);
  writeFileSync(path, 'secret non-database contents', { mode: 0o600 });
  assert.throws(() => new SqliteDesktopJournal(path), safeError('journal_corrupt'));
  assert.equal(readFileSync(path, 'utf8'), 'secret non-database contents');
});

test('sqlite: rejects foreign databases and pinned version/schema changes without modifying their bytes', (t) => {
  for (const mutation of [
    'PRAGMA application_id=123', 'PRAGMA user_version=999',
    'CREATE TABLE unexpected (value TEXT)', 'CREATE TABLE sqliteXhidden (value TEXT)',
    'CREATE TRIGGER unexpected AFTER INSERT ON jobs BEGIN DELETE FROM tickets; END',
  ]) {
    const { path } = fixture(t);
    const journal = diskJournal(t, path);
    journal.close();
    const db = new DatabaseSync(path);
    db.exec(mutation);
    db.close();
    const before = readFileSync(path);
    assert.throws(() => new SqliteDesktopJournal(path), safeError('journal_corrupt'));
    assert.deepEqual(readFileSync(path), before);
  }
  const { path } = fixture(t);
  writeFileSync(path, '', { mode: 0o600 });
  const foreign = new DatabaseSync(path);
  foreign.exec('CREATE TABLE foreign_data (value TEXT)');
  foreign.close();
  const before = readFileSync(path);
  assert.throws(() => new SqliteDesktopJournal(path), safeError('journal_corrupt'));
  assert.deepEqual(readFileSync(path), before);
});

test('sqlite: quick_check catches corrupted stored JSON and reads reject excessive JSON depth', (t) => {
  const { path } = fixture(t);
  const journal = diskJournal(t, path);
  journal.transaction((tx) => tx.put('jobs', 'bad', 1));
  journal.close();
  const db = new DatabaseSync(path);
  db.exec("PRAGMA ignore_check_constraints=ON; UPDATE jobs SET data='{' WHERE key='bad'");
  db.close();
  assert.throws(() => new SqliteDesktopJournal(path), safeError('journal_corrupt'));

  const fresh = fixture(t);
  const other = diskJournal(t, fresh.path);
  const edit = new DatabaseSync(fresh.path);
  edit.prepare('INSERT INTO jobs (key,data) VALUES (?,?)').run('deep', '['.repeat(66) + '0' + ']'.repeat(66));
  edit.close();
  assert.throws(() => other.transaction((tx) => tx.get('jobs', 'deep')), safeError('journal_corrupt'));
});

test('sqlite: SQLite disk-full errors roll back earlier writes and preserve only safe diagnostics', (t) => {
  const { path } = fixture(t);
  const journal = diskJournal(t, path);
  journal.transaction((tx) => { tx.put('control', 'saved', 1); tx.append('committed'); });
  const original = DatabaseSync.prototype.exec;
  const mock = t.mock.method(DatabaseSync.prototype, 'exec', function (sql) {
    if (sql === 'BEGIN IMMEDIATE') {
      const pages = this.prepare('PRAGMA page_count').get().page_count;
      original.call(this, `PRAGMA max_page_count=${pages}`);
    }
    return original.call(this, sql);
  });
  assert.throws(() => journal.transaction((tx) => {
    tx.put('control', 'saved', 2);
    tx.append('must roll back');
    tx.put('jobs', 'large', 'x'.repeat(300_000));
  }), safeError('journal_unavailable'));
  mock.mock.restore();
  journal.close();
  const reopened = diskJournal(t, path);
  assert.equal(reopened.transaction((tx) => tx.get('control', 'saved')), 1);
  assert.equal(reopened.transaction((tx) => tx.get('jobs', 'large')), null);
  assert.deepEqual(reopened.events(), ['committed']);
});

test('sqlite: injected append DesktopError is preserved and still aborts a caught failure', (t) => {
  const journal = diskJournal(t);
  const injected = new DesktopError('core_append_failed');
  const original = DatabaseSync.prototype.prepare;
  const mock = t.mock.method(DatabaseSync.prototype, 'prepare', function (sql) {
    if (sql === 'INSERT INTO events (data) VALUES (?)') return { run() { throw injected; } };
    return original.call(this, sql);
  });
  assert.throws(() => journal.transaction((tx) => {
    tx.put('control', 'partial', 1);
    try { tx.append('aborted'); } catch (error) { assert.equal(error, injected); }
  }), (error) => error === injected);
  mock.mock.restore();
  assert.equal(journal.transaction((tx) => tx.get('control', 'partial')), null);
  assert.deepEqual(journal.events(), []);
});

test('sqlite: changed version and newly linked sidecars fail before invoking a transaction', (t) => {
  const { directory, path } = fixture(t);
  const journal = diskJournal(t, path);
  const target = join(directory, 'target');
  writeFileSync(target, 'private sidecar target', { mode: 0o600 });
  symlinkSync(target, path + '-journal');
  let called = false;
  assert.throws(() => journal.transaction(() => { called = true; }), safeError('unsafe_journal_path'));
  assert.equal(called, false);
  unlinkSync(path + '-journal');
  const db = new DatabaseSync(path);
  db.exec('PRAGMA user_version=999');
  db.close();
  assert.throws(() => journal.transaction(() => { called = true; }), safeError('journal_corrupt'));
  assert.equal(called, false);
  assert.equal(readFileSync(target, 'utf8'), 'private sidecar target');
});

test('sqlite: internal event-read errors expose only the static storage diagnostic', (t) => {
  const journal = diskJournal(t);
  const original = DatabaseSync.prototype.prepare;
  const mock = t.mock.method(DatabaseSync.prototype, 'prepare', function (sql) {
    if (sql === 'SELECT data FROM events ORDER BY seq') throw new Error('private SQLite file diagnostics');
    return original.call(this, sql);
  });
  assert.throws(() => journal.events(), safeError('journal_unavailable'));
  mock.mock.restore();
  assert.deepEqual(journal.events(), []);
});

test('sqlite: independent processes serialize read-modify-write counters and event sequence', { timeout: 20_000 }, async (t) => {
  const { path } = fixture(t);
  const journal = diskJournal(t, path);
  journal.transaction((tx) => tx.put('control', 'counter', 0));
  const source = `
    const { SqliteDesktopJournal } = await import(process.argv[1]);
    const journal = new SqliteDesktopJournal(process.argv[2]);
    process.send('ready');
    process.once('message', async () => {
      try {
        for (let i = 0; i < 30; i++) {
          for (let retry = 0; ; retry++) {
            try {
              journal.transaction(tx => {
                const next = tx.get('control', 'counter') + 1;
                tx.put('control', 'counter', next); tx.append({ count: next });
              });
              break;
            } catch (error) {
              if (error.code !== 'journal_unavailable' || retry >= 10) throw error;
              await new Promise(resolve => setTimeout(resolve, 10));
            }
          }
          await new Promise(resolve => setImmediate(resolve));
        }
      } catch (error) { process.stderr.write(error.code || 'worker_failed'); process.exitCode = 1; }
      finally { journal.close(); process.disconnect(); }
    });
  `;
  const workers = Array.from({ length: 4 }, () => worker(t, source, path));
  assert.deepEqual(await Promise.all(workers.map((child) => child.next())), ['ready', 'ready', 'ready', 'ready']);
  for (const child of workers) child.child.send('start');
  const results = await Promise.all(workers.map((child) => child.done));
  for (const result of results) assert.deepEqual(result, { code: 0, signal: null, diagnostic: '' });
  assert.equal(journal.transaction((tx) => tx.get('control', 'counter')), 120);
  assert.deepEqual(journal.events().map((event) => event.count), Array.from({ length: 120 }, (_, i) => i + 1));
});

test('sqlite: lock contention fails after a short timeout before invoking the callback', { timeout: 10_000 }, async (t) => {
  const { path } = fixture(t);
  const journal = diskJournal(t, path);
  const child = worker(t, `
    const { DatabaseSync } = await import('node:sqlite');
    const db = new DatabaseSync(process.argv[2]); db.exec('BEGIN IMMEDIATE');
    process.send('locked');
    process.once('message', () => { db.exec('ROLLBACK'); db.close(); process.disconnect(); });
  `, path);
  assert.equal(await child.next(), 'locked');
  let called = false;
  const started = performance.now();
  assert.throws(() => journal.transaction(() => { called = true; }), safeError('journal_unavailable'));
  assert.equal(called, false);
  assert.ok(performance.now() - started < 3000, 'busy wait must remain short');
  child.child.send('release');
  assert.equal((await child.done).code, 0);
  journal.transaction((tx) => tx.put('control', 'after-lock', true));
});

test('sqlite: concurrent first opens initialize one complete pinned schema', { timeout: 15_000 }, async (t) => {
  const { path } = fixture(t);
  const source = `
    const { SqliteDesktopJournal } = await import(process.argv[1]);
    try {
      const journal = new SqliteDesktopJournal(process.argv[2]);
      journal.transaction(tx => tx.append('initialized'));
      journal.close();
    } catch (error) { process.stderr.write(error.code || 'worker_failed'); process.exitCode = 1; }
    process.disconnect();
  `;
  const workers = Array.from({ length: 4 }, () => worker(t, source, path));
  for (const result of await Promise.all(workers.map((child) => child.done))) {
    assert.deepEqual(result, { code: 0, signal: null, diagnostic: '' });
  }
  const journal = diskJournal(t, path);
  assert.deepEqual(journal.events(), ['initialized', 'initialized', 'initialized', 'initialized']);
});

test('sqlite: a killed writer leaves a recoverable hot journal without partial commits', { timeout: 10_000 }, async (t) => {
  const { path } = fixture(t);
  const journal = diskJournal(t, path);
  journal.transaction((tx) => { tx.put('control', 'saved', 1); tx.append('committed'); });
  journal.close();
  const child = worker(t, `
    const { SqliteDesktopJournal } = await import(process.argv[1]);
    const journal = new SqliteDesktopJournal(process.argv[2]);
    journal.transaction(tx => {
      tx.put('control', 'saved', 2); tx.append('uncommitted');
      tx.put('jobs', 'large', 'x'.repeat(300000));
      process.send('uncommitted');
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0);
    });
  `, path);
  assert.equal(await child.next(), 'uncommitted');
  assert.equal(existsSync(path + '-journal'), true);
  child.child.kill('SIGKILL');
  assert.equal((await child.done).signal, 'SIGKILL');
  const recovered = diskJournal(t, path);
  assert.equal(recovered.transaction((tx) => tx.get('control', 'saved')), 1);
  assert.equal(recovered.transaction((tx) => tx.get('jobs', 'large')), null);
  assert.deepEqual(recovered.events(), ['committed']);
});
