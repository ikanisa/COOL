// The CI workflow pins the PostgreSQL image digest. Only its packaged PG 17.10
// tools may start this synthetic fixture; connection settings are never inputs.
import {execFile} from 'node:child_process';
import {lstat, realpath} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {promisify} from 'node:util';

const run = promisify(execFile);
const bin = '/usr/lib/postgresql/17/bin';
const path = '/usr/bin:/bin:/usr/sbin:/sbin';
const tools = ['initdb', 'postgres', 'pg_ctl', 'pg_isready'];

export function checkWriterJournalEnvironment(env, platform, uid, euid) {
  if (platform !== 'linux' || !Number.isInteger(uid) || uid <= 0 || uid !== euid) {
    throw Error('Writer journal CI requires an unprivileged Linux account.');
  }
  if (Object.keys(env).sort().join(',') !== 'COLLECT_SYNTHETIC_PG_BIN,PATH,TMPDIR' ||
      env.COLLECT_SYNTHETIC_PG_BIN !== bin || env.PATH !== path || env.TMPDIR !== '/tmp') {
    throw Error('Writer journal CI requires its clean environment and packaged PostgreSQL directory.');
  }
}

export function checkWriterJournalVersion(tool, stdout) {
  const version = /^(\w+) \(PostgreSQL\) 17\.10(?: \(Debian 17\.10-[A-Za-z0-9.~+:-]+\))?\n?$/.exec(stdout);
  if (!tools.includes(tool) || version?.[1] !== tool) {
    throw Error('Writer journal CI requires PostgreSQL 17.10 for ' + tool);
  }
}

function verifyEnvironment(env) {
  checkWriterJournalEnvironment(env, process.platform, process.getuid?.(), process.geteuid?.());
}

async function verifyBinaryPins() {
  verifyEnvironment(process.env);
  if (await realpath(bin) !== bin) throw Error('Expected a physical PostgreSQL binary directory.');
  for (let parent = bin; ; parent = dirname(parent)) {
    const stat = await lstat(parent);
    if (!stat.isDirectory() || stat.uid !== 0 || (stat.mode & 0o022) !== 0) {
      throw Error('Expected a root-owned, protected PostgreSQL path.');
    }
    if (parent === '/') break;
  }
  for (const tool of tools) {
    const file = join(bin, tool);
    const stat = await lstat(file);
    if (!stat.isFile() || stat.uid !== 0 || (stat.mode & 0o022) !== 0 || (stat.mode & 0o111) === 0) {
      throw Error('Expected a protected PostgreSQL executable for ' + tool);
    }
    const {stdout} = await run(file, ['--version'], {
      env: {PATH: '/usr/bin:/bin', LC_ALL: 'C'}, encoding: 'utf8', timeout: 5000, maxBuffer: 4096,
    });
    checkWriterJournalVersion(tool, stdout);
  }
}

export const writerJournalLinuxPg = Object.freeze({bin, verifyEnvironment, verifyBinaryPins});
