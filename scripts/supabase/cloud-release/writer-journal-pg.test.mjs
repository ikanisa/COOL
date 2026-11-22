import assert from 'node:assert/strict';
import test from 'node:test';
import {withOwnedArchiveFixture} from '../managed-migration-next/synthetic-fixture.mjs';
import {checkWriterJournalEnvironment, checkWriterJournalVersion, writerJournalLinuxPg}
  from '../testing/writer-journal-pg.mjs';

const clean = {
  PATH: '/usr/bin:/bin:/usr/sbin:/sbin',
  TMPDIR: '/tmp',
  COLLECT_SYNTHETIC_PG_BIN: '/usr/lib/postgresql/17/bin',
};

test('the image binary policy requires the clean nonroot invocation', () => {
  const validate = (env = clean, platform = 'linux', uid = 999, euid = uid) =>
    checkWriterJournalEnvironment(env, platform, uid, euid);
  validate();
  for (const env of [
    {...clean, PGHOST: '/tmp/another-socket'}, {...clean, DATABASE_URL: 'postgres://example.invalid/db'},
    {...clean, NODE_OPTIONS: 'unexpected'}, {...clean, COLLECT_SYNTHETIC_PG_BIN: '/tmp/bin'},
    {...clean, PATH: '/tmp/bin:/usr/bin'}, {...clean, TMPDIR: '/tmp/alias'}, {},
  ]) assert.throws(() => validate(env), /clean environment/);
  assert.throws(() => validate(clean, 'linux', 0), /unprivileged Linux/);
  assert.throws(() => validate(clean, 'linux', 999, 0), /unprivileged Linux/);
  assert.throws(() => validate(clean, 'darwin'), /unprivileged Linux/);
});

test('every image tool must identify itself at the reviewed patch version', () => {
  for (const name of ['postgres', 'initdb', 'pg_ctl', 'pg_isready']) {
    checkWriterJournalVersion(name, name + ' (PostgreSQL) 17.10 (Debian 17.10-1.pgdg13+1)\n');
    checkWriterJournalVersion(name, name + ' (PostgreSQL) 17.10\n');
    for (const version of ['17.1', '17.10.1', '17.11', '17.10beta1', '17.10\nextra']) {
      assert.throws(() => checkWriterJournalVersion(name, name + ' (PostgreSQL) ' + version), /17\.10/);
    }
  }
  assert.throws(() => checkWriterJournalVersion('initdb', 'postgres (PostgreSQL) 17.10'), /17\.10/);
  assert.throws(() => checkWriterJournalVersion('psql', 'psql (PostgreSQL) 17.10'), /17\.10/);
});

test('the archive fixture refuses caller-defined binary policies before opening a cluster', async () => {
  let opened = false;
  await assert.rejects(withOwnedArchiveFixture(() => { opened = true; }, {...writerJournalLinuxPg}),
    /UNKNOWN_FIXTURE_BINARY_POLICY/);
  assert.equal(opened, false);
});
