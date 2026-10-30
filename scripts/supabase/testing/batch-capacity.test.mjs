import test from 'node:test';
import assert from 'node:assert/strict';
import {CAPACITY_ENV, CAPACITY_LIMITS, validateCapacityInvocation, validateCapacityDatabaseIdentity, validateCapacityPristineCatalog, capacityKey, expectedCapacityRows, capacityLatency, capacityErrorCode} from './batch-capacity.mjs';

const local = 'postgresql://collect_test:synthetic_only@127.0.0.1:55441/collect_batch_capacity_test';
const environment = {[CAPACITY_ENV]: local, COLLECT_CI_SYNTHETIC: 'true'};
const invoke = change => validateCapacityInvocation({env: {...environment, ...change}});
const refused = (change, code) => assert.throws(() => invoke(change), error => error.capacityCode === code);

test('small defaults are bounded and declare exact owned local target', () => {
  const result = invoke({});
  assert.deepEqual(result.concurrency, [1, 2, 4]); assert.equal(result.operationsPerWorker, 12);
  assert.equal(result.plannedBatches, 84); assert.equal(result.target.pathname, '/collect_batch_capacity_test');
  assert(result.plannedBatches < CAPACITY_LIMITS.maxBatches);
});

test('remote, redirected, alternate database/user and malformed URLs refuse before driver import', () => {
  for (const raw of [
    local.replace('127.0.0.1', 'db.example.com'), local.replace('127.0.0.1', 'localhost'), local.replace('127.0.0.1', '[::1]'),
    local.replace('127.0.0.1', '127.1'), local.replace('127.0.0.1', '2130706433'), local + '?sslmode=disable', local + '#x',
    local.replace('collect_batch_capacity_test', 'postgres'), local.replace('collect_batch_capacity_test', 'collect_live'),
    local.replace('collect_test:', 'postgres:'), local.replace('55441', '65536'), local.replace('55441', '0'),
    local.replace('synthetic_only', '%00'), local.replace('synthetic_only', '%'), local.replace('postgresql:', 'https:'),
    local.replace(':55441', ''), local.replace('/collect_batch_capacity_test', '/%63ollect_batch_capacity_test'),
  ]) refused({[CAPACITY_ENV]: raw}, 'EXACT_OWNED_LOOPBACK_URL_REQUIRED');
});

test('explicit synthetic consent, pinned runtime, no args or ambient driver credentials', () => {
  refused({COLLECT_CI_SYNTHETIC: undefined}, 'EXPLICIT_SYNTHETIC_FIXTURE_REQUIRED');
  for (const key of ['PGHOST', 'PGPORT', 'PGDATABASE', 'PGPASSWORD', 'PGSSLMODE', 'DATABASE_URL', 'COLLECT_DATABASE_URL']) {
    refused({[key]: 'unexpected'}, 'AMBIENT_DATABASE_OVERRIDE_FORBIDDEN');
  }
  assert.throws(() => validateCapacityInvocation({env: environment, args: ['--sql=SELECT 1']}), {capacityCode: 'NO_ARGUMENTS_ALLOWED'});
  assert.throws(() => validateCapacityInvocation({env: environment, denoVersion: '2.8.0'}), {capacityCode: 'PINNED_DENO_REQUIRED'});
});

test('concurrency, ordered phases and total work cannot exceed fixed caps', () => {
  for (const raw of ['0', '9', '-1', '1,2,4,8,8', '1, 2', '2.5', '1;SELECT 1', '']) refused({COLLECT_BATCH_CAPACITY_CONCURRENCY: raw}, 'BOUNDED_CONCURRENCY_REQUIRED');
  for (const raw of ['4,2', '2,2']) refused({COLLECT_BATCH_CAPACITY_CONCURRENCY: raw}, 'ORDERED_UNIQUE_CONCURRENCY_REQUIRED');
  for (const raw of ['0', '3', '33', '100000', '-1', '4.0', '']) refused({COLLECT_BATCH_CAPACITY_OPERATIONS_PER_WORKER: raw}, 'BOUNDED_OPERATIONS_REQUIRED');
  refused({COLLECT_BATCH_CAPACITY_OPERATIONS_PER_WORKER: '7'}, 'COMPLETE_WORKLOAD_CYCLES_REQUIRED');
  refused({COLLECT_BATCH_CAPACITY_CONCURRENCY: '1,2,4,8', COLLECT_BATCH_CAPACITY_OPERATIONS_PER_WORKER: '32'}, 'TOTAL_WORKLOAD_LIMIT_EXCEEDED');
  assert.equal(invoke({COLLECT_BATCH_CAPACITY_CONCURRENCY: '8', COLLECT_BATCH_CAPACITY_OPERATIONS_PER_WORKER: '32'}).plannedBatches, 256);
});

test('actual server identity requires local address, exact owner, native PG17 and RC isolation', () => {
  const target = new URL(local);
  const row = {database: 'collect_batch_capacity_test', address: '127.0.0.1', port: 55441, version: '170010', default_isolation: 'read committed',
    isolation: 'read committed', current_role: 'collect_test', session_role: 'collect_test', owner: 'collect_test', superuser: true, bypass: true};
  validateCapacityDatabaseIdentity(row, target);
  for (const change of [{database: 'postgres'}, {address: '10.0.0.1'}, {port: 5432}, {version: '160008'}, {default_isolation: 'repeatable read'},
    {isolation: 'serializable'}, {current_role: 'postgres'}, {session_role: 'postgres'}, {owner: 'postgres'}, {superuser: false}, {bypass: false}]) {
    assert.throws(() => validateCapacityDatabaseIdentity({...row, ...change}, target), {capacityCode: 'OWNED_NATIVE_POSTGRES17_REQUIRED'});
  }
});

test('fixed paired row expectations count only the three writes per four operations', () => {
  const rows = expectedCapacityRows(4, 12);
  assert.equal(rows.length, 8); assert(rows.every(row => row.count === 10 && row.bucket === 0 && row.expires_at === 1));
  assert.equal(new Set(rows.map(row => row.key_hash)).size, 8);
  assert.equal(capacityKey(4, 3, 'mirror'), 'batch_capacity:v1:c4:w3:mirror');
  assert.throws(() => capacityKey(4, 4, 'primary'), {capacityCode: 'BOUNDED_SYNTHETIC_KEY_REQUIRED'});
  assert.throws(() => capacityKey(4, 1, 'arbitrary'), {capacityCode: 'BOUNDED_SYNTHETIC_KEY_REQUIRED'});
});

test('existing user functions, types, schemas, extensions, foreign objects and sessions refuse setup', () => {
  const empty = {schemas: 0, objects: 0, functions: 0, types: 0, extra_schemas: 0, extra_extensions: 0,
    event_triggers: 0, foreign_servers: 0, foreign_wrappers: 0, other_connections: 0};
  validateCapacityPristineCatalog(empty);
  for (const key of Object.keys(empty)) {
    assert.throws(() => validateCapacityPristineCatalog({...empty, [key]: 1}), {capacityCode: 'NEW_EMPTY_UNSHARED_DATABASE_REQUIRED'});
    assert.throws(() => validateCapacityPristineCatalog({...empty, [key]: undefined}), {capacityCode: 'NEW_EMPTY_UNSHARED_DATABASE_REQUIRED'});
  }
});

test('latency uses nearest-rank percentiles with explicit empty samples', () => {
  assert.deepEqual(capacityLatency([]), {samples: 0, min: null, p50: null, p95: null, p99: null, max: null});
  assert.deepEqual(capacityLatency([5, 1, 4, 3, 2]), {samples: 5, min: 1, p50: 3, p95: 5, p99: 5, max: 5});
  assert.equal(capacityLatency(Array.from({length: 100}, (_, i) => i + 1)).p99, 99);
  assert.throws(() => capacityLatency([Infinity]), {capacityCode: 'BOUNDED_LATENCY_SAMPLE_REQUIRED'});
  assert.throws(() => capacityLatency(Array(385).fill(1)), {capacityCode: 'BOUNDED_LATENCY_SAMPLE_REQUIRED'});
});

test('errors project bounded codes and never messages, SQL, connection URLs or stacks', () => {
  assert.equal(capacityErrorCode({code: '55P03', message: local, collectSql: 'private input', stack: 'private stack'}), 'SQLSTATE_55P03');
  assert.equal(capacityErrorCode({code: 'application_fence_unavailable'}), 'APPLICATION_FENCE_UNCONFIRMED');
  assert.equal(capacityErrorCode({message: local}), 'LOCAL_MEASUREMENT_UNCONFIRMED');
  assert.equal(capacityErrorCode({capacityCode: local}), 'LOCAL_MEASUREMENT_UNCONFIRMED');
});
