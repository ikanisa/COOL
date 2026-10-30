// Deno 2.9.6, cached-only/frozen, loopback-only synthetic measurement.
// This imports the actual adapter and application fence. It never changes the
// global advisory lock, offers caller SQL, resets a database or calls a provider.
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {cpus, totalmem} from 'node:os';
import {CAPACITY_DATABASE, CAPACITY_ENV, CAPACITY_CONTRACT, CAPACITY_LIMITS, CAPACITY_SOURCE_PINS,
  capacityNeed as need, validateCapacityInvocation, validateCapacityDatabaseIdentity, validateCapacityPristineCatalog, capacityKey,
  expectedCapacityRows, capacityLatency, capacityErrorCode} from './batch-capacity.mjs';

const CALLER = 'scripts/supabase/testing/measure-batch-capacity.mjs';
const HELPER = 'scripts/supabase/testing/curated-platform-fixture.mjs';
const FIXTURE_SOURCE = 'a'.repeat(64);
const BASELINE = 'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const READ = 'SELECT count FROM admin_rate_limits WHERE key_hash=? AND bucket=0';
const WRITE = 'UPDATE admin_rate_limits SET count=count+1 WHERE key_hash=? AND bucket=0 RETURNING count';
const SEED = 'INSERT INTO admin_rate_limits(key_hash,bucket,count,expires_at) VALUES(?,0,1,1)';
const startedAt = new Date().toISOString();
const sha = async value => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', typeof value === 'string' ? new TextEncoder().encode(value) : value)), n => n.toString(16).padStart(2, '0')).join('');
const phases = [], ownedWorks = new Set();
let stage = 'preflight', owner, sql, control, fixture, sourceInputs = [], sourceClosure = null, runtime = null, config, backend;
let externalFetches = 0, cleanupConfirmed = false, failure = null, admissionCount = 0;
const scope = Object.freeze({hosted_capacity_acceptance: false, financial_workflow_acceptance: false, provider_calls: 0,
  global_lock_changed: false, automatic_retry: false, reset_or_drop: false, preserve_database: true});
const watchdog = setTimeout(() => {
  console.log(JSON.stringify({contract: CAPACITY_CONTRACT, status: 'UNCONFIRMED', stage, code: 'PROCESS_BUDGET_EXCEEDED',
    started_at: startedAt, phases, cleanup_confirmed: false, ...scope}));
  // Process exit closes only this process's sockets. It does not manufacture a
  // successful admission close or terminate other PostgreSQL backends.
  Deno.exit(1);
}, CAPACITY_LIMITS.processBudgetMs);

async function sourceFile(root, role) {
  const path = join(root, role);
  need(await Deno.realPath(path) === path, 'PHYSICAL_SOURCE_REQUIRED');
  const bytes = await Deno.readFile(path);
  need(bytes.length > 0 && bytes.length <= 16000000, 'BOUNDED_SOURCE_REQUIRED');
  const digest = await sha(bytes);
  if (CAPACITY_SOURCE_PINS[role]) need(digest === CAPACITY_SOURCE_PINS[role], 'ACTUAL_ADAPTER_SOURCE_PIN_CHANGED');
  return {role, bytes: bytes.length, sha256: digest};
}

async function parity(root) {
  for (const input of sourceInputs) {
    const current = await sourceFile(root, input.role);
    need(current.bytes === input.bytes && current.sha256 === input.sha256, 'SOURCE_CHANGED_DURING_MEASUREMENT');
  }
  await fixture.parity();
}

async function finishWorks(works, failed) {
  const results = await Promise.allSettled(works.map(async work => {
    const result = await work.finish({failed});
    need(result.state === 'settled' && result.applicationWorkFinished === true && result.externalDispatches === 0 && result.uncertainDispatches === 0,
      'GENUINE_ADMISSION_CLOSE_UNCONFIRMED');
    ownedWorks.delete(work);
  }));
  need(results.every(result => result.status === 'fulfilled'), 'GENUINE_ADMISSION_CLOSE_UNCONFIRMED');
}

async function measurePhase(concurrency, operationsPerWorker, deadline, PostgresDatabase, openApplicationWork) {
  const works = [], clients = [], outcomes = [];
  let phaseFailed = true;
  try {
    // Each worker has its own real admission/lease. Reusing a single work object
    // would serialize its assertion queue and distort this adapter measurement.
    for (let worker = 0; worker < concurrency; worker++) {
      const work = await openApplicationWork({backend, sourceSha256: FIXTURE_SOURCE, kind: 'http_collect'});
      admissionCount++; works.push(work); ownedWorks.add(work);
      const db = new PostgresDatabase(sql, {role: 'authenticated'}, work); clients.push(db);
      await db.batch(['primary', 'mirror'].map(side => db.prepare(SEED).bind(capacityKey(concurrency, worker, side))));
    }
    const phaseStarted = performance.now();
    await Promise.all(clients.map(async (db, worker) => {
      let expected = 1;
      for (let operation = 0; operation < operationsPerWorker; operation++) {
        if (performance.now() >= deadline) {
          outcomes.push({kind: 'not_started', code: 'WORKLOAD_BUDGET_EXCEEDED', latency: 0}); break;
        }
        const write = operation % 4 !== 0, kind = write ? 'write' : 'read';
        const keys = ['primary', 'mirror'].map(side => capacityKey(concurrency, worker, side));
        const at = performance.now();
        try {
          const results = await db.batch(keys.map(key => db.prepare(write ? WRITE : READ).bind(key)));
          const wanted = expected + (write ? 1 : 0);
          need(results.length === 2 && results.every(result => result.success === true && result.results.length === 1 &&
            result.results[0].count === wanted && result.meta.changes === 1), 'BATCH_RESULT_OR_ATOMIC_PAIR_MISMATCH');
          expected = wanted;
          outcomes.push({kind, latency: performance.now() - at});
        } catch (error) {
          outcomes.push({kind, latency: performance.now() - at, code: capacityErrorCode(error)});
          // No replay of a failed/unknown batch. Later operations remain bounded
          // and a committed unknown outcome cannot be reported as exact success.
        }
      }
    }));
    const elapsed = performance.now() - phaseStarted;
    const expected = expectedCapacityRows(concurrency, operationsPerWorker);
    const actual = Array.from(await owner.unsafe('SELECT key_hash,bucket::integer,count::integer,expires_at::integer FROM app.admin_rate_limits WHERE key_hash LIKE $1 ORDER BY key_hash COLLATE "C"', [`batch_capacity:v1:c${concurrency}:%`]));
    const successful = outcomes.filter(row => !row.code), errors = outcomes.filter(row => row.code);
    const errorCounts = {};
    for (const item of errors) errorCounts[item.code] = (errorCounts[item.code] ?? 0) + 1;
    const finalValuesMatch = JSON.stringify(actual) === JSON.stringify(expected);
    const phase = {concurrency, planned_batches: concurrency * operationsPerWorker,
      successful_batches: successful.length, errors: errors.length, error_codes: errorCounts,
      read_only_batches: successful.filter(row => row.kind === 'read').length,
      write_batches: successful.filter(row => row.kind === 'write').length,
      duration_ms: Math.round(elapsed * 1000) / 1000,
      successful_batches_per_second: Math.round(successful.length * 1000000 / elapsed) / 1000,
      latency_ms: {all_successful: capacityLatency(successful.map(row => row.latency)),
        read_only: capacityLatency(successful.filter(row => row.kind === 'read').map(row => row.latency)),
        write: capacityLatency(successful.filter(row => row.kind === 'write').map(row => row.latency)),
        failed: capacityLatency(errors.filter(row => row.kind !== 'not_started').map(row => row.latency))},
      expected_final_rows: expected, observed_final_rows: actual, exact_final_values_match: finalValuesMatch};
    phases.push(phase);
    phaseFailed = errors.length !== 0 || successful.length !== phase.planned_batches || !finalValuesMatch;
    need(!phaseFailed, 'MEASUREMENT_OR_FINAL_VALUES_UNCONFIRMED');
  } finally {
    await finishWorks(works, phaseFailed);
  }
}

try {
  const environment = Deno.env.toObject();
  config = validateCapacityInvocation({args: Deno.args, env: environment, denoVersion: Deno.version.deno});
  // Consume the target once, then keep it in memory only. It is absent from all
  // output, source identity and error projections.
  Deno.env.delete(CAPACITY_ENV); delete environment[CAPACITY_ENV];
  need((await Deno.permissions.query({name: 'net'})).state !== 'granted' &&
    (await Deno.permissions.query({name: 'net', host: `127.0.0.1:${config.target.port}`})).state === 'granted',
    'EXACT_LOOPBACK_NETWORK_PERMISSION_REQUIRED');
  globalThis.fetch = () => { externalFetches++; throw new Error('EXTERNAL_FETCH_FORBIDDEN'); };
  const caller = fileURLToPath(import.meta.url), root = await Deno.realPath(resolve(dirname(caller), '../../..'));
  need(caller === join(root, CALLER) && await Deno.realPath(caller) === caller, 'FIXED_PHYSICAL_CALLER_REQUIRED');
  stage = 'reviewed_fixture_admission';
  const loader = await import(pathToFileURL(join(root, HELPER)).href);
  try { fixture = await loader.loadReviewedPlatformFixture(root); } catch { need(false, 'REVIEWED_FIXTURE_ADMISSION_REQUIRED'); }
  need(fixture.names.length === 11, 'EXACT_SQL11_FIXTURE_PREFIX_REQUIRED');
  const roles = [...new Set([CALLER, 'scripts/supabase/testing/batch-capacity.mjs', HELPER,
    'scripts/supabase/testing/member-realtime-fixture-plan.json', 'scripts/supabase/testing/member-realtime-interface.sql',
    'scripts/supabase/testing/member-realtime-metadata.sql', 'supabase/tests/sql/00_local_auth_fixture.sql',
    'supabase/functions/_shared/domain/core.js', 'supabase/functions/deno.json', ...Object.keys(CAPACITY_SOURCE_PINS),
    ...fixture.diskNames.map(name => 'supabase/migrations/' + name)])].sort();
  for (const role of roles) sourceInputs.push(await sourceFile(root, role));
  sourceClosure = await sha(JSON.stringify(sourceInputs));
  await parity(root);
  // Dynamic imports occur only after config/source admission. Deno must be run
  // with --cached-only --frozen and an exact loopback network permission.
  const {default: postgres} = await import('npm:postgres@3.4.7');
  const actual = await import(pathToFileURL(join(root, 'supabase/functions/_shared/postgres.js')).href);
  const fence = await import(pathToFileURL(join(root, 'supabase/functions/_shared/application-fence.js')).href);
  stage = 'database_identity';
  owner = postgres(config.target.href, {max: 1, prepare: false, ssl: false, connect_timeout: 5, idle_timeout: 5,
    onnotice: () => {}, connection: {application_name: 'collect-batch-capacity-owner', statement_timeout: 15000, lock_timeout: 5000}});
  const identity = (await owner.unsafe(`SELECT current_database()::text AS database,host(inet_server_addr()) AS address,
    inet_server_port() AS port,current_setting('server_version_num') AS version,current_setting('server_version') AS full_version,
    current_setting('default_transaction_isolation') AS default_isolation,current_setting('transaction_isolation') AS isolation,
    current_user::text AS current_role,session_user::text AS session_role,
    (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AS superuser,
    (SELECT rolbypassrls FROM pg_roles WHERE rolname=current_user) AS bypass,
    pg_get_userbyid((SELECT datdba FROM pg_database WHERE datname=current_database()))::text AS owner`))[0];
  validateCapacityDatabaseIdentity(identity, config.target);
  let resources = {logical_cpus: null, physical_memory_bytes: null, host_resources_verified: false};
  // Optional host metadata may be denied by Deno's sys permission. Missing
  // metadata is explicit and must not turn a valid bounded run into a false
  // failure or encourage a broader network/filesystem permission.
  try { resources = {logical_cpus: cpus().length, physical_memory_bytes: totalmem(), host_resources_verified: true}; } catch { /* explicit null metadata */ }
  runtime = {deno: Deno.version, target: Deno.build, postgres: identity.full_version, postgres_driver: '3.4.7',
    ...resources, business_pool_max: 4, control_lease_capacity: 8};
  const pristine = (await owner.unsafe(`SELECT
    (SELECT count(*)::integer FROM pg_namespace WHERE nspname IN('app','private','api','auth','realtime','collect_ops')) AS schemas,
    (SELECT count(*)::integer FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname NOT IN('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_toast%' AND n.nspname NOT LIKE 'pg_temp%' AND c.relkind IN('r','p','v','m','S','f')) AS objects,
    (SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname NOT IN('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_toast%' AND n.nspname NOT LIKE 'pg_temp%') AS functions,
    (SELECT count(*)::integer FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname NOT IN('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_toast%' AND n.nspname NOT LIKE 'pg_temp%') AS types,
    (SELECT count(*)::integer FROM pg_namespace WHERE nspname NOT IN('pg_catalog','information_schema','public') AND nspname NOT LIKE 'pg_toast%' AND nspname NOT LIKE 'pg_temp%') AS extra_schemas,
    (SELECT count(*)::integer FROM pg_extension WHERE extname<>'plpgsql') AS extra_extensions,
    (SELECT count(*)::integer FROM pg_event_trigger) AS event_triggers,
    (SELECT count(*)::integer FROM pg_foreign_server) AS foreign_servers,
    (SELECT count(*)::integer FROM pg_foreign_data_wrapper) AS foreign_wrappers,
    (SELECT count(*)::integer FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid()) AS other_connections`))[0];
  validateCapacityPristineCatalog(pristine);
  stage = 'reviewed_fixture_setup';
  await fixture.apply(statement => owner.unsafe(statement), {includeAuth: true});
  await owner.unsafe('SELECT private.collect_fence_initialize($1::uuid,$2::text,$3::text)', [crypto.randomUUID(), FIXTURE_SOURCE, BASELINE]);
  const status = (await owner.unsafe('SELECT private.collect_fence_owner_status() AS result'))[0].result;
  need(status.mode === 'open' && status.sourceSha256 === FIXTURE_SOURCE && status.activeAdmissions === 0 && status.unresolvedAdmissions === 0 &&
    status.schedulerStatus?.blocking === false, 'GENUINE_INITIAL_FENCE_REQUIRED');
  await parity(root);
  sql = actual.connection(config.target.href); control = actual.fenceConnection(config.target.href); backend = fence.sqlFenceBackend(sql, control);
  stage = 'measured_batches';
  const deadline = performance.now() + CAPACITY_LIMITS.workloadBudgetMs;
  for (const concurrency of config.concurrency) await measurePhase(concurrency, config.operationsPerWorker, deadline, actual.PostgresDatabase, fence.openApplicationWork);
  stage = 'final_invariants';
  const finalStatus = (await owner.unsafe('SELECT private.collect_fence_owner_status() AS result'))[0].result;
  const finalCounts = (await owner.unsafe(`SELECT (SELECT count(*)::integer FROM private.collect_fence_admissions) AS admissions,
    (SELECT count(*)::integer FROM app.admin_rate_limits) AS rows`))[0];
  need(finalStatus.mode === 'open' && finalStatus.activeAdmissions === 0 && finalStatus.unresolvedAdmissions === 0 &&
    finalStatus.retainedUnknownObligations === 0 && finalCounts.admissions === admissionCount && finalCounts.rows === config.concurrency.reduce((sum, value) => sum + value * 2, 0),
    'FINAL_FENCE_OR_ROW_INVARIANT_UNCONFIRMED');
  need(externalFetches === 0, 'EXTERNAL_FETCH_FORBIDDEN');
  await parity(root);
} catch (error) {
  failure = {stage, code: capacityErrorCode(error)};
} finally {
  if (ownedWorks.size) {
    try { await finishWorks([...ownedWorks], true); } catch { failure ??= {stage: 'cleanup', code: 'GENUINE_ADMISSION_CLOSE_UNCONFIRMED'}; }
  }
  const results = await Promise.allSettled([sql, control, owner].filter(Boolean).map(pool => pool.end({timeout: 1})));
  cleanupConfirmed = results.every(result => result.status === 'fulfilled') && ownedWorks.size === 0;
  if (!cleanupConfirmed) failure ??= {stage: 'cleanup', code: 'OWNED_CONNECTION_CLEANUP_UNCONFIRMED'};
  clearTimeout(watchdog);
}

const result = {contract: CAPACITY_CONTRACT, status: failure ? 'UNCONFIRMED' : 'MEASURED', started_at: startedAt,
  finished_at: new Date().toISOString(), failure, database: CAPACITY_DATABASE, runtime,
  source: {closure_sha256: sourceClosure, inputs: sourceInputs, applied_migration_count: fixture?.names.length ?? 0,
    applied_migrations: fixture?.rawMigrations.map(item => ({name: item.name, sha256: item.sha256})) ?? [],
    local_realtime_binding: fixture?.binding ?? null, synthetic_fence_source: FIXTURE_SOURCE},
  workload: {id: 'paired_disjoint_counter_rows_v1', concurrency: config?.concurrency ?? [], operations_per_worker: config?.operationsPerWorker ?? null,
    planned_batches: config?.plannedBatches ?? null, statements_per_batch: 2, read_only_fraction: 0.25, write_fraction: 0.75,
    setup_batches: config?.concurrency.reduce((sum, value) => sum + value, 0) ?? null,
    seed_value: 1, global_advisory_lock: '734636924058501',
    latency_scope: 'batch_call_to_commit_including_pool_fence_and_global_lock', percentile_method: 'nearest_rank',
    admission_scope: 'one_real_admission_per_worker_per_phase', admission_setup_in_measured_latency: false,
    row_scope: 'two_disjoint_synthetic_admin_rate_limits_rows_per_worker', limits: CAPACITY_LIMITS,
    read_sql: READ, write_sql: WRITE},
  phases, admissions: admissionCount, external_fetch_calls: externalFetches, cleanup_confirmed: cleanupConfirmed,
  limitations: ['single_local_host', 'fixed_synthetic_queries', 'warmup_and_admission_setup_excluded',
    'no_financial_workflow_or_provider_simulation', 'no_hosted_capacity_threshold_or_acceptance'], ...scope};
console.log(JSON.stringify(result, null, 2));
if (failure) Deno.exitCode = 1;
