import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {fixtureRoles, seedMemberListing} from './fixtures/burimunsi-members.mjs';

const flags = process.argv.slice(2);
const plans = flags.includes('--plans');
const option = flags.filter(flag => flag !== '--plans');
assert.ok(option.length === 0 || option.length === 1 && /^--samples=([1-9]|[1-9]\d|100)$/.test(option[0]),
  'usage: node scripts/supabase/cloud-release/burimunsi-members-profile.mjs [--samples=1..100] [--plans]');
const samples = option.length ? Number(option[0].split('=')[1]) : 25;
const fixture = await startOwnedPg17({prefix:'collect-pg-transfer-', initialUser:'collect_fixture', clusterName:'collect_members_profile'});
const connection = {host:fixture.socket, port:fixture.port, user:fixture.initialUser};
const bootstrap = new pg.Client({...connection, database:'postgres'});
const sources = await readFile(new URL('./fixtures/burimunsi-members-profile.sql', import.meta.url), 'utf8');
const driver = fileURLToPath(new URL('./fixtures/burimunsi-members-profile-driver.mjs', import.meta.url));
const deno = fileURLToPath(new URL('../node_modules/deno/deno', import.meta.url));
const lock = fileURLToPath(new URL('../deno.lock', import.meta.url));
try {
  await bootstrap.connect();
  await bootstrap.query(fixtureRoles);
  console.log('PostgreSQL %s · Node %s · %s/%s · %d measured pairs per scenario', (await bootstrap.query('SHOW server_version')).rows[0].server_version,
    process.version, process.platform, process.arch, samples);
  for (const size of [1000, 10000, 100000]) {
    const database = 'members_' + size;
    await bootstrap.query('CREATE DATABASE ' + database);
    const setup = new pg.Client({...connection, database});
    try {
      await setup.connect();
      await seedMemberListing(setup, [size]);
      await setup.query(sources);
      await setup.query('VACUUM ANALYZE');
    } finally {
      await setup.end();
    }
    const pgSocket = fixture.socket + '/.s.PGSQL.' + fixture.port;
    const args = ['run','--node-modules-dir=none','--lock=' + lock,'--frozen','--cached-only','--allow-read','--allow-env',
      '--allow-net=unix:' + pgSocket,'--allow-write=' + pgSocket, driver,
      fixture.socket,String(fixture.port),String(size),String(samples),...(plans ? ['--plans'] : [])];
    const child = fixture.trackChild(spawn(deno, args, {stdio:'inherit'}));
    const [code, signal] = await once(child, 'close');
    assert.equal(code, 0, 'Members driver failed for ' + size + (signal ? ' (' + signal + ')' : ''));
  }
} finally {
  try { await bootstrap.end(); } finally { assert.equal((await fixture.close()).removed, true, 'owned cluster cleanup'); }
}
