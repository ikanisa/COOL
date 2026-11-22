import {randomUUID} from 'node:crypto';
import {readdir, readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateTarget} from './data_stage.mjs';
import {fixtureIdentitySql, loadReviewedPlatformFixture} from './testing/curated-platform-fixture.mjs';
import {captureCurrent14MemberHistory} from './testing/current14-member-history.mjs';

const root = resolve(import.meta.dirname, '../..');
const suiteDirectory = resolve(root, 'supabase/tests/sql');
const fixtureSchemas = ['app', 'private', 'api', 'auth', 'realtime'];
// These identities label the reviewed local fixture only.
const fixtureSource = 'a'.repeat(64);
const baseline = 'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';

export function selectSchemaCase(argv) {
  if (argv.length === 0) return 'schema';
  if (argv.length === 1 && argv[0] === '--case=current14-member-history') return 'current14-member-history';
  throw new Error('Only the default schema suite or --case=current14-member-history is supported');
}

async function loadSuites() {
  const names = (await readdir(suiteDirectory))
    .filter(name => /^\d+_[a-z0-9_]+\.sql$/.test(name) && !name.startsWith('00_')).sort();
  if (!names.length) throw new Error('No PostgreSQL acceptance cases');
  return Promise.all(names.map(async name => {
    const source = await readFile(resolve(suiteDirectory, name), 'utf8');
    const begin = source.indexOf('BEGIN;\n');
    const beforeBegin = source.slice(0, begin);
    if (begin < 0 || !/^(?:\s|--[^\n]*(?:\n|$))*$/.test(beforeBegin) || !source.endsWith('ROLLBACK;\n')) {
      throw new Error('Suite must retain an outer BEGIN/ROLLBACK: ' + name);
    }
    return {name, prefix: beforeBegin + 'BEGIN;\n', body: source.slice(begin + 'BEGIN;\n'.length)};
  }));
}

async function runtimeCall(db, text, args) {
  await db.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  try {
    await db.query('SET LOCAL ROLE collect_runtime');
    await db.query("SELECT pg_catalog.set_config('collect.edge_verified','true',true)");
    const result = await db.query(text, args);
    await db.query('COMMIT');
    return result.rows[0]?.value;
  } catch (error) {
    await db.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

async function runAdmittedSuite(db, lease, suite) {
  const id = randomUUID();
  const registered = await runtimeCall(
    db, 'SELECT private.collect_fence_register($1,$2,$3) AS value', [id, fixtureSource, 'jobs'],
  );
  if (registered?.state !== 'active' || registered.mode !== 'open' ||
      registered.sourceSha256 !== fixtureSource || registered.epoch !== 1) {
    throw new Error('Synthetic admission refused');
  }
  const identity = [id, registered.epoch, fixtureSource];
  const assertWork = 'SELECT private.collect_fence_assert_work($1,$2,$3) AS value';
  const close = 'SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7) AS value';
  let leaseOpen = false;
  try {
    await lease.query('BEGIN ISOLATION LEVEL READ COMMITTED');
    leaseOpen = true;
    await lease.query(`
      SET LOCAL idle_in_transaction_session_timeout = '120s';
      SET LOCAL statement_timeout = '30s';
      SET LOCAL lock_timeout = '5s';
      SET LOCAL ROLE collect_runtime;
      SELECT pg_catalog.set_config('collect.edge_verified','true',true);
      SELECT pg_catalog.pg_advisory_xact_lock_shared(7346371,1);
    `);
    const proof = (await lease.query(assertWork, identity)).rows[0].value;
    if (proof.mode !== 'open' || proof.admissionId !== id) {
      throw new Error('Synthetic work lease not OPEN');
    }

    // The generated UUID, verified epoch and constant digest have fixed grammar.
    const context = `SELECT
      pg_catalog.set_config('collect.edge_verified','true',true),
      pg_catalog.set_config('collect.fence_admission_id','${id}',true),
      pg_catalog.set_config('collect.fence_epoch','${registered.epoch}',true),
      pg_catalog.set_config('collect.fence_source_sha256','${fixtureSource}',true);\n`;
    await db.query(suite.prefix + context + suite.body);
    await lease.query(assertWork, identity);
    await runtimeCall(db, close, [...identity, 'settled', 'completed', 0, 0]);
    // Release the work lease only after the durable close.
    await lease.query('ROLLBACK');
    leaseOpen = false;
  } catch (error) {
    await db.query('ROLLBACK').catch(() => {});
    await runtimeCall(db, close, [...identity, 'unresolved', 'work_lost', 0, 0]).catch(() => {});
    if (leaseOpen) await lease.query('ROLLBACK').catch(() => {});
    throw new Error(`${suite.name}: ${error.message}`, {cause: error});
  }
}

async function initializeFixture(db, platform, requireFresh) {
  // Qualify the actual server, version and bootstrap identity before any reset.
  await db.query(fixtureIdentitySql);
  const lock = await db.query('SELECT pg_catalog.pg_try_advisory_lock(7346371,61) AS owned');
  if (!lock.rows[0].owned) throw new Error('The local schema fixture is already in use');

  if (requireFresh) {
    const existing = await db.query('SELECT nspname FROM pg_catalog.pg_namespace WHERE nspname = ANY($1::name[])', [
      fixtureSchemas,
    ]);
    if (existing.rowCount) throw new Error('Use a fresh isolated PostgreSQL fixture database');
  } else {
    await db.query(fixtureSchemas.map(name => `DROP SCHEMA IF EXISTS ${name} CASCADE;`).join(' '));
  }

  await platform.apply(sql => db.query(sql), {includeAuth: true});
  const fixture = await db.query("SELECT pg_catalog.to_regprocedure('private.collect_fence_initialize(uuid,text,text)') AS installed");
  if (!fixture.rows[0].installed) throw new Error('Fenced SQL suite requires the reviewed additive fence migration');
  await db.query('SELECT private.collect_fence_initialize($1,$2,$3)', [randomUUID(), fixtureSource, baseline]);
}

export async function runDefaultSchema({
  connectionString = process.env.COLLECT_TEST_PG_URL,
  pgModule = process.env.COLLECT_PG_MODULE ?? 'pg',
  requireFresh = false,
} = {}) {
  const target = validateTarget(connectionString, 'local', {localTest: true});
  if (!/^\/collect_[a-z0-9_]+_test$/.test(target.pathname)) {
    throw new Error('Use a dedicated collect_*_test fixture database');
  }
  const [platform, suites] = await Promise.all([loadReviewedPlatformFixture(root), loadSuites()]);
  const require = createRequire(import.meta.url);
  const {Client} = require(pgModule);
  const options = {
    connectionString: target.href, ssl: false, connectionTimeoutMillis: 5000, statement_timeout: 30000,
  };
  const db = new Client(options);
  const lease = new Client(options);
  try {
    await db.connect();
    await lease.connect();
    await initializeFixture(db, platform, requireFresh);
    for (const suite of suites) {
      await runAdmittedSuite(db, lease, suite);
      console.log('PASS ' + suite.name);
    }
    const {rows: [counts]} = await db.query(`
      SELECT
        (SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname='app') AS app_tables,
        (SELECT count(*) FROM pg_catalog.pg_trigger AS t
          JOIN pg_catalog.pg_class AS c ON c.oid=t.tgrelid
          JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
          WHERE n.nspname='app' AND NOT t.tgisinternal) AS app_triggers
    `);
    console.log(JSON.stringify({
      database: 'isolated_local_fixture', migration_count: platform.names.length, sql_suites: suites.length, ...counts,
      synthetic_fence_source: fixtureSource, genuine_durable_admission: true, hosted_acceptance: false,
    }));
  } finally {
    try {
      await db.end();
    } finally {
      await lease.end();
    }
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const selected = selectSchemaCase(process.argv.slice(2));
  if (selected === 'schema') await runDefaultSchema();
  else console.log(JSON.stringify(await captureCurrent14MemberHistory()));
}
