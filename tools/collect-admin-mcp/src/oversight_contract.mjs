import {UUID, invalid, object, strictKeys, unavailable} from './config.mjs';

export const SOURCE_REVISION=/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;
export const AUDIT_ACTION=/^[a-z][a-z0-9_.:-]{0,119}$/;
const decimal=value=>typeof value==='string'&&/^[1-9][0-9]{0,18}$/.test(value)&&BigInt(value)<=9223372036854775807n;
function exact(value, keys) {
  if (!object(value) || Object.keys(value).length !== keys.length || keys.some(key => !Object.hasOwn(value, key))) unavailable();
}

function instant(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
}

function checked(value) {
  const now = Date.now();
  if (!instant(value) || now - Date.parse(value) > 120_000 || Date.parse(value) - now > 5000) unavailable();
  return Date.parse(value);
}

const FINGERPRINT = /^[a-f0-9]{64}$/;
export const matches = (rule, value) => typeof value === 'string' && rule.test(value);

const QUEUE_SPECS=Object.freeze({
  momo:[['pending','retry','processing','expired_lease','needs_review','source_unresolved','attempt_exhausted','records_with_error'],['oldest_due_seconds'],['last_changed_at'],{}],
  assisted_sms:[['queued','claimed','expired_claim','send_started','observed_sent','failed_no_send','uncertain'],['oldest_queued_seconds','oldest_unobserved_send_seconds'],['last_created_at'],{automatic_retry:false}],
  notifications:[['pending','sent','failed','read'],['oldest_pending_seconds'],['last_created_at'],{semantics:'persisted_in_app_events'}],
  admin_email:[['pending','accepted','failed'],['oldest_pending_seconds'],['last_changed_at'],{semantics:'legacy_email_records'}],
  invitations:[['reserved','dispatching','accepted','rejected','unknown','already_registered'],['oldest_unconfirmed_seconds'],['last_changed_at'],{semantics:'original_invitation_attempts',accepted_means:'provider_accepted'}],
  push_delivery:[['pending','retry','claimed','sending','accepted','rejected','suppressed','unknown','expired_lease','due','records_with_error'],['oldest_due_seconds','oldest_pending_seconds'],['last_changed_at'],{semantics:'persisted_push_dispatches',accepted_means:'provider_accepted',unknown_is_retryable:false}],
 });

export function auditQuery(args) {
  strictKeys(args, ['source', 'limit', 'cursor', 'actor_id', 'entity_id', 'action']);
  const source = args.source ?? 'domain', limit = args.limit ?? 25;
  if (!['domain', 'accounts'].includes(source) || !Number.isSafeInteger(limit) || limit < 1 || limit > 100) invalid();
  const query = new URLSearchParams({limit: String(limit)});
  for (const key of ['actor_id', 'entity_id']) {
    if (args[key] === undefined) continue;
    if (!matches(UUID, args[key])) invalid();
    query.set(key, args[key]);
  }
  if (args.action !== undefined) {
    if (!matches(AUDIT_ACTION, args.action)) invalid();
    query.set('action', args.action);
  }
  if (args.cursor !== undefined) {
    const cursor = args.cursor;
    strictKeys(cursor, source === 'domain' ? ['before_id'] : ['before_id', 'before_seconds']);
    if (source === 'domain') {
      if (!decimal(cursor.before_id)) invalid();
    } else if (!matches(UUID, cursor.before_id) || !Number.isSafeInteger(cursor.before_seconds) ||
      cursor.before_seconds < 1 || cursor.before_seconds > 999999999999) {
      invalid();
    }
    for (const [key, value] of Object.entries(cursor)) query.set(key, String(value));
  }
  return {source, limit, path: '/api/admin/oversight/audit/' + source + '?' + query};
}

function follows(previous, row, domain) {
  if (domain) return BigInt(previous.id) > BigInt(row.id);
  if (previous.created_at === row.created_at) return previous.id > row.id;
  return Date.parse(previous.created_at) > Date.parse(row.created_at);
}

export function auditPage(value, requested) {
  exact(value, ['contract_version', 'scope', 'source', 'actor_reference', 'limit', 'next_cursor', 'rows', 'details_included', 'checked_at']);
  const domain = requested.source === 'domain';
  if (value.contract_version !== 1 || value.scope !== 'cross_operator_audit_metadata' ||
      value.source !== requested.source || value.limit !== requested.limit || value.details_included !== false ||
      value.actor_reference !== (domain ? 'canonical_principal' : 'admin_account') ||
      !Array.isArray(value.rows) || value.rows.length > requested.limit) unavailable();

  checked(value.checked_at);
  const seen = new Set();
  let previous = null;
  for (const row of value.rows) {
    exact(row, ['id', 'actor_id', 'action', 'entity_type', 'entity_id', 'request_id', 'created_at']);
    if (!(domain ? decimal(row.id) : matches(UUID, row.id)) || seen.has(row.id) || !instant(row.created_at) ||
      !matches(AUDIT_ACTION, row.action) || !matches(AUDIT_ACTION, row.entity_type)) unavailable();
    for (const key of ['actor_id', 'entity_id', 'request_id']) {
      if (row[key] !== null && !matches(UUID, row[key])) unavailable();
    }
    if (previous && !follows(previous, row, domain)) unavailable();
    if (requested.source === 'accounts' && (row.entity_type !== 'admin_account' || row.request_id !== null)) unavailable();
    seen.add(row.id);
    previous = row;
  }
  const cursor = value.next_cursor;
  if (cursor !== null) {
    if (value.rows.length !== requested.limit || !previous) unavailable();
    exact(cursor, domain ? ['before_id'] : ['before_id', 'before_seconds']);
    if (cursor.before_id !== previous.id || (!domain && cursor.before_seconds !== Date.parse(previous.created_at) / 1000)) unavailable();
  }
  return value;
}

function assertQueueMetrics(queues, checkedAt) {
  exact(queues, Object.keys(QUEUE_SPECS));
  for (const [name, [counts, ages, dates, constants]] of Object.entries(QUEUE_SPECS)) {
    const row = queues[name];
    exact(row, [...counts, ...ages, ...dates, ...Object.keys(constants)]);
    for (const key of counts) if (!Number.isSafeInteger(row[key]) || row[key] < 0) unavailable();
    for (const key of ages) if (row[key] !== null && (!Number.isSafeInteger(row[key]) || row[key] < 0)) unavailable();
    for (const key of dates) if (row[key] !== null && (!instant(row[key]) || Date.parse(row[key]) > checkedAt + 5000)) unavailable();
    for (const [key, constant] of Object.entries(constants)) if (row[key] !== constant) unavailable();
  }

  const {momo, assisted_sms: assistedSms, push_delivery: push} = queues;
  if (momo.expired_lease > momo.processing || assistedSms.expired_claim > assistedSms.claimed ||
      push.expired_lease > push.claimed + push.sending || push.due > push.pending + push.retry) unavailable();
}

export function operationalHealth(value, expected) {
  exact(value, ['contract_version', 'scope', 'database', 'storage_binding', 'source_revision', 'checked_at',
    'external_services_checked', 'configuration', 'metrics_scope', 'worker_heartbeat', 'queues']);
  if (value.contract_version !== 1 || value.scope !== 'admin_operational_health' || value.database !== 'available' ||
      !['configured', 'missing'].includes(value.storage_binding) ||
      (value.source_revision !== 'unknown' && !matches(SOURCE_REVISION, value.source_revision)) ||
      value.external_services_checked !== false || value.metrics_scope !== 'all_retained_rows' ||
      value.worker_heartbeat !== 'not_recorded') unavailable();

  const checkedAt = checked(value.checked_at);
  const configuration = value.configuration;
  exact(configuration, ['momo_processing', 'momo_extractor', 'transactional_email']);
  if (!['enabled', 'paused'].includes(configuration.momo_processing) ||
      !['disabled', 'configured', 'missing'].includes(configuration.momo_extractor) ||
      !['configured', 'missing'].includes(configuration.transactional_email)) unavailable();

  assertQueueMetrics(value.queues, checkedAt);
  return {...value, source_matches: expected === undefined ? null : value.source_revision === expected};
}

const DIAGNOSTIC_CODES={startupStarted:'info',startupWaiting:'info',startupTimedOut:'warning',startupFailed:'error',startupReady:'info',frameworkFailure:'error',platformFailure:'error',diagnosticsSuppressed:'warning'};
export function diagnosticGroups(value){
 exact(value,['contract_version','window_hours','retention_hours','checked_at','limit','truncated','groups']);
 if(value.contract_version!==1||value.window_hours!==24||value.retention_hours!==24||value.limit!==64||typeof value.truncated!=='boolean'||!Array.isArray(value.groups)||value.groups.length>64||value.truncated&&value.groups.length!==64)unavailable();
 checked(value.checked_at);let previous=null;const seen=new Set();
 for(const row of value.groups){
  exact(row,['surface','environment','build_version','source_revision','code','severity','fingerprint','occurrences','reports','last_received_hour']);
  if(!['member','admin'].includes(row.surface)||!['local','development','staging','production','unknown'].includes(row.environment)||
   !(row.build_version==='unknown'||typeof row.build_version==='string'&&row.build_version.length<=32&&/^\d+\.\d+\.\d+(?:\+\d+)?$/.test(row.build_version))||
   !(row.source_revision==='unknown'||matches(SOURCE_REVISION,row.source_revision))||typeof row.code!=='string'||!Object.hasOwn(DIAGNOSTIC_CODES,row.code)||DIAGNOSTIC_CODES[row.code]!==row.severity||
   !matches(FINGERPRINT,row.fingerprint)||seen.has(row.fingerprint)||!Number.isSafeInteger(row.occurrences)||!Number.isSafeInteger(row.reports)||row.reports<1||row.occurrences<row.reports||
   !instant(row.last_received_hour)||!row.last_received_hour.endsWith(':00:00.000Z')||Date.parse(row.last_received_hour)>Date.parse(value.checked_at)||Date.parse(value.checked_at)-Date.parse(row.last_received_hour)>25*3600_000)unavailable();
  if(previous&&(previous.last_received_hour<row.last_received_hour||previous.last_received_hour===row.last_received_hour&&previous.fingerprint>=row.fingerprint))unavailable();
  seen.add(row.fingerprint);previous=row;
 }
 return value;
}
