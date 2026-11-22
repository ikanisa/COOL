// Pure contract for the loopback-only adapter measurement. No driver import,
// connection, filesystem write, arbitrary SQL or provider operation on import.
export const CAPACITY_DATABASE = 'collect_batch_capacity_test';
export const CAPACITY_ENV = 'COLLECT_BATCH_CAPACITY_DATABASE_URL';
export const CAPACITY_CONTRACT = 'collect.local.batch-capacity.v1';
export const CAPACITY_LIMITS = Object.freeze({maxConcurrency: 8, maxOperationsPerWorker: 32, maxBatches: 384, workloadBudgetMs: 60000, processBudgetMs: 120000});
export const CAPACITY_SOURCE_PINS = Object.freeze({
  'supabase/functions/_shared/postgres.js': 'bcb995361298517ec297601c260fe3c885616e267eef632731bdd075e66cd0d9',
  'supabase/functions/_shared/application-fence.js': '7abbf94ff699f6942619b6a0409a5623a6fa7322b41cdabe72e32d99689184de',
  'supabase/functions/deno.lock': '070d1f79d59faebba520e3d14c1b10f4d73a84584eafa8c34f767c013c628b9b',
});

export function capacityNeed(condition, code) {
  if (!condition) { const error = new Error('Local batch capacity measurement unconfirmed'); error.capacityCode = code; throw error; }
}

export function validateCapacityInvocation({args = [], env, denoVersion = '2.9.6'}) {
  capacityNeed(Array.isArray(args) && args.length === 0, 'NO_ARGUMENTS_ALLOWED');
  capacityNeed(denoVersion === '2.9.6', 'PINNED_DENO_REQUIRED');
  capacityNeed(env?.COLLECT_CI_SYNTHETIC === 'true', 'EXPLICIT_SYNTHETIC_FIXTURE_REQUIRED');
  // Even unused ambient credentials/driver overrides make invocation ambiguous.
  capacityNeed(!Object.keys(env).some(key => /^PG[A-Z_]+$/.test(key) && env[key] !== undefined && env[key] !== '') &&
    !['DATABASE_URL', 'COLLECT_DATABASE_URL'].some(key => env[key]), 'AMBIENT_DATABASE_OVERRIDE_FORBIDDEN');
  const raw = env[CAPACITY_ENV];
  capacityNeed(typeof raw === 'string' && raw.length <= 2048 &&
    /^postgres(?:ql)?:\/\/collect_test:[^\s/?#@]+@127\.0\.0\.1:[1-9][0-9]{0,4}\/collect_batch_capacity_test$/.test(raw), 'EXACT_OWNED_LOOPBACK_URL_REQUIRED');
  let target, password;
  try { target = new URL(raw); password = decodeURIComponent(target.password); } catch { capacityNeed(false, 'EXACT_OWNED_LOOPBACK_URL_REQUIRED'); }
  capacityNeed(target.hostname === '127.0.0.1' && target.username === 'collect_test' && target.pathname === '/' + CAPACITY_DATABASE &&
    Number(target.port) >= 1 && Number(target.port) <= 65535 && password.length > 0 && !/[\x00-\x1f\x7f]/.test(password) &&
    !target.search && !target.hash, 'EXACT_OWNED_LOOPBACK_URL_REQUIRED');
  const rawConcurrency = env.COLLECT_BATCH_CAPACITY_CONCURRENCY ?? '1,2,4';
  capacityNeed(typeof rawConcurrency === 'string' && /^[1-8](?:,[1-8]){0,3}$/.test(rawConcurrency), 'BOUNDED_CONCURRENCY_REQUIRED');
  const concurrency = rawConcurrency.split(',').map(Number);
  capacityNeed(concurrency.every((value, index) => index === 0 || value > concurrency[index - 1]), 'ORDERED_UNIQUE_CONCURRENCY_REQUIRED');
  const rawOperations = env.COLLECT_BATCH_CAPACITY_OPERATIONS_PER_WORKER ?? '12';
  capacityNeed(typeof rawOperations === 'string' && /^(?:[4-9]|[12][0-9]|3[0-2])$/.test(rawOperations), 'BOUNDED_OPERATIONS_REQUIRED');
  const operationsPerWorker = Number(rawOperations);
  capacityNeed(operationsPerWorker % 4 === 0, 'COMPLETE_WORKLOAD_CYCLES_REQUIRED');
  const plannedBatches = concurrency.reduce((sum, value) => sum + value * operationsPerWorker, 0);
  capacityNeed(plannedBatches <= CAPACITY_LIMITS.maxBatches, 'TOTAL_WORKLOAD_LIMIT_EXCEEDED');
  return Object.freeze({target, concurrency: Object.freeze(concurrency), operationsPerWorker, plannedBatches});
}

export function validateCapacityDatabaseIdentity(row, target) {
  capacityNeed(row?.database === CAPACITY_DATABASE && row.address === '127.0.0.1' && row.port === Number(target.port) &&
    /^17\d{4}$/.test(row.version) && row.default_isolation === 'read committed' && row.isolation === 'read committed' &&
    row.current_role === 'collect_test' && row.session_role === 'collect_test' && row.owner === 'collect_test' &&
    row.superuser === true && row.bypass === true, 'OWNED_NATIVE_POSTGRES17_REQUIRED');
}

export function validateCapacityPristineCatalog(row) {
  capacityNeed(row && ['schemas', 'objects', 'functions', 'types', 'extra_schemas', 'extra_extensions', 'event_triggers',
    'foreign_servers', 'foreign_wrappers', 'other_connections'].every(key => row[key] === 0), 'NEW_EMPTY_UNSHARED_DATABASE_REQUIRED');
}

export function capacityKey(concurrency, worker, side) {
  capacityNeed(Number.isSafeInteger(concurrency) && concurrency >= 1 && concurrency <= CAPACITY_LIMITS.maxConcurrency &&
    Number.isSafeInteger(worker) && worker >= 0 && worker < concurrency && ['primary', 'mirror'].includes(side), 'BOUNDED_SYNTHETIC_KEY_REQUIRED');
  return `batch_capacity:v1:c${concurrency}:w${worker}:${side}`;
}

export function expectedCapacityRows(concurrency, operationsPerWorker) {
  capacityNeed(Number.isSafeInteger(concurrency) && concurrency >= 1 && concurrency <= CAPACITY_LIMITS.maxConcurrency, 'BOUNDED_CONCURRENCY_REQUIRED');
  capacityNeed(Number.isSafeInteger(operationsPerWorker) && operationsPerWorker >= 4 && operationsPerWorker <= CAPACITY_LIMITS.maxOperationsPerWorker &&
    operationsPerWorker % 4 === 0, 'BOUNDED_OPERATIONS_REQUIRED');
  const rows = [];
  for (let worker = 0; worker < concurrency; worker++) {
    for (const side of ['primary', 'mirror']) rows.push({key_hash: capacityKey(concurrency, worker, side), bucket: 0, count: 1 + operationsPerWorker * 3 / 4, expires_at: 1});
  }
  return rows.sort((a, b) => a.key_hash.localeCompare(b.key_hash, 'en'));
}

export function capacityLatency(values) {
  capacityNeed(Array.isArray(values) && values.length <= CAPACITY_LIMITS.maxBatches && values.every(value => Number.isFinite(value) && value >= 0), 'BOUNDED_LATENCY_SAMPLE_REQUIRED');
  if (values.length === 0) return {samples: 0, min: null, p50: null, p95: null, p99: null, max: null};
  const sorted = [...values].sort((a, b) => a - b);
  const round = value => Math.round(value * 1000) / 1000;
  const percentile = fraction => round(sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)]);
  return {samples: sorted.length, min: round(sorted[0]), p50: percentile(0.50), p95: percentile(0.95), p99: percentile(0.99), max: round(sorted.at(-1))};
}

export function capacityErrorCode(error) {
  if (typeof error?.capacityCode === 'string' && /^[A-Z][A-Z0-9_]{0,63}$/.test(error.capacityCode)) return error.capacityCode;
  if (typeof error?.code === 'string' && /^(?:[0-9]{2}|[0-9][A-Z]|[A-Z][0-9])[A-Z0-9]{3}$/.test(error.code)) return 'SQLSTATE_' + error.code;
  if (['application_fence_unavailable', 'application_fenced'].includes(error?.code)) return 'APPLICATION_FENCE_UNCONFIRMED';
  return 'LOCAL_MEASUREMENT_UNCONFIRMED';
}
