import {createHash} from 'node:crypto';
import {SafeError, UUID, object, invalid, unavailable} from './config.mjs';

export const SHA = /^[a-f0-9]{64}$/;
export const CLASS = /^[a-z][a-z0-9_]*(?::[a-z][a-z0-9_.-]*)?$/;
export const SQL_ERASABLE = Object.freeze(['notification_devices', 'notification_preferences', 'notification_events', 'support_requests']);
export const READ_RPC = Object.freeze({
  context: 'admin_get_account_retention_context_v1',
  inspect: 'admin_inspect_account_retention_scope_v1',
  continuation: 'admin_inspect_account_quarantine_continuation_v1',
  status: 'admin_get_account_retention_status_v1',
  lookup: 'admin_get_account_retention_operation_v1',
});
export const WRITE_RPC = Object.freeze({
  plan: 'admin_plan_account_retention_v1',
  claim: 'admin_claim_account_retention_task_v1',
  execute: 'admin_execute_account_retention_task_v1',
  reconcile: 'admin_reconcile_account_retention_v1',
});

const WORD = /^[a-z][a-z0-9_]{0,119}$/;
const PLAN_FIELDS = [
  'contract_version', 'scope', 'plan_id', 'request_id', 'policy_sha256', 'source_id', 'schema_sha256', 'state', 'revision',
  'scope_snapshot_sha256', 'erasure_completed', 'all_data_erased', 'financial_journal_preserved', 'policy_current',
  'operational_acceptance_granted', 'tasks',
];
const PLAN_VERIFICATION_FIELDS = ['eligible_dispositions_verified', 'all_actual_copy_outcomes_verified'];
const PLAN_KEYS = new Set([...PLAN_FIELDS, ...PLAN_VERIFICATION_FIELDS, 'retained_classes']);
const SCOPE_FIELDS = Object.freeze({plan: 'p_request_id', claim: 'p_plan_id', execute: 'p_claim_id'});

export const isRetentionUuid = value => typeof value === 'string' && UUID.test(value);
export const isRetentionHash = value => typeof value === 'string' && SHA.test(value);
export const isUnconfirmedRetentionState = state => state === 'unknown' || state === 'dispatching';
export const instant = value => typeof value === 'string' && Number.isFinite(Date.parse(value)) &&
  new Date(value).toISOString() === value;

const count = value => Number.isSafeInteger(value) && value >= 0;
const word = value => typeof value === 'string' && WORD.test(value);

export function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (!object(value)) return JSON.stringify(value);
  return '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
}

export const digest = value => createHash('sha256').update(canonical(value)).digest('hex');

export function retentionBlocked(code = 'retention_blocked') {
  throw new SafeError(code,
    'This retention step is blocked. Inspect the current approved scope, holds, original operations and supported adapters before continuing.');
}

export function hasUnresolvedRetentionOperation(records, kind, input) {
  if (!Object.hasOwn(SCOPE_FIELDS, kind)) return false;
  const field = SCOPE_FIELDS[kind];
  return records.some(({preview, state}) =>
    preview.kind === kind && preview.input[field] === input[field] && state !== 'observed' && state !== 'cancelled');
}

export function assertRetentionFields(value, keys) {
  if (!object(value) || Object.keys(value).length !== keys.length || keys.some(key => !Object.hasOwn(value, key))) unavailable();
}

function assertNoErasureClaim(value) {
  if (value.erasure_completed !== false || (Object.hasOwn(value, 'all_data_erased') && value.all_data_erased !== false)) unavailable();
}

export function parseContext(value) {
  assertRetentionFields(value, ['contract_version', 'scope', 'source_id', 'checked_at', 'valid_until', 'approval_granted', 'erasure_completed']);
  const now = Date.now();
  if (value.contract_version !== 1 || value.scope !== 'account_retention_inspection_context' ||
      !isRetentionHash(value.source_id) || !instant(value.checked_at) || !instant(value.valid_until) ||
      Date.parse(value.valid_until) <= now || Date.parse(value.checked_at) > now + 5000 ||
      now - Date.parse(value.checked_at) > 120000 || value.approval_granted !== false) unavailable();
  assertNoErasureClaim(value);
  return value;
}

function assertInventory(inventory) {
  if (!object(inventory)) unavailable();
  const names = Object.keys(inventory);
  if (names.length > 256 || names.some(key => key.length > 120 || !CLASS.test(key))) unavailable();
}

export function parseInspection(value, input) {
  assertRetentionFields(value, [
    'contract_version', 'request_id', 'subject_id', 'source_id', 'schema_sha256', 'snapshot_sha256', 'table_counts',
    'private_catalog_sha256', 'private_schema_sha256', 'private_copy_inventory', 'object_count', 'active_hold_count',
    'in_flight_unresolved', 'approval_granted', 'erasure_completed',
  ]);
  if (value.contract_version !== 1 || value.request_id !== input.p_request_id || value.source_id !== input.p_expected_source_id ||
      !isRetentionUuid(value.subject_id) || value.approval_granted !== false || typeof value.in_flight_unresolved !== 'boolean' ||
      !count(value.object_count) || !count(value.active_hold_count)) unavailable();
  for (const key of ['source_id', 'schema_sha256', 'snapshot_sha256', 'private_catalog_sha256', 'private_schema_sha256']) {
    if (!isRetentionHash(value[key])) unavailable();
  }
  assertInventory(value.table_counts);
  assertInventory(value.private_copy_inventory);
  if (Object.values(value.table_counts).some(entry => !count(entry))) unavailable();
  for (const row of Object.values(value.private_copy_inventory)) {
    assertRetentionFields(row, ['count', 'status']);
    if (!count(row.count) || !word(row.status)) unavailable();
  }
  assertNoErasureClaim(value);
  return value;
}

export function parseOutcome(value) {
  if (!object(value) || typeof value.verified !== 'boolean' || !word(value.disposition) ||
      (value.reason !== undefined && !word(value.reason)) || !isRetentionHash(value.source_id) ||
      !isRetentionHash(value.policy_sha256) || value.observation_only !== true || value.currentness_not_asserted !== true) unavailable();
  assertNoErasureClaim(value);

  // Undeclared backend fields may include record or object identities.
  // Project only the declared decision evidence into operator output.
  const result = {
    verified: value.verified, disposition: value.disposition, source_id: value.source_id,
    policy_sha256: value.policy_sha256, observation_only: true, currentness_not_asserted: true,
    erasure_completed: false, all_data_erased: false,
  };
  for (const key of ['rows_erased_or_confirmed_absent', 'rows_remaining', 'objects_verified_absent', 'objects_remaining', 'engine_rows_observed']) {
    if (value[key] === undefined) continue;
    if (!count(value[key])) unavailable();
    result[key] = value[key];
  }
  if (value.reason !== undefined) result.reason = value.reason;
  if (value.retained_until !== undefined) {
    if (!instant(value.retained_until)) unavailable();
    result.retained_until = value.retained_until;
  }
  if (value.session_reapproval_required !== undefined) {
    if (value.session_reapproval_required !== true) unavailable();
    result.session_reapproval_required = true;
  }
  return result;
}

function parseTasks(value) {
  const ids = new Set(), classes = new Set();
  const tasks = value.tasks.map(task => {
    assertRetentionFields(task, ['task_id', 'class_name', 'action', 'state', 'revision', 'fence', 'outcome']);
    if (!isRetentionUuid(task.task_id) || ids.has(task.task_id) || typeof task.class_name !== 'string' ||
        task.class_name.length > 120 || !CLASS.test(task.class_name) || classes.has(task.class_name) ||
        !['retain', 'erase', 'quarantine', 'blocked'].includes(task.action) ||
        !['pending', 'claimed', 'blocked', 'verified'].includes(task.state) || !count(task.revision) || !count(task.fence)) unavailable();
    ids.add(task.task_id);
    classes.add(task.class_name);
    return {...task, outcome: task.outcome === null ? null : parseOutcome(task.outcome)};
  });
  const retained = value.retained_classes;
  if (retained !== undefined && (!Array.isArray(retained) || retained.length > 256 || retained.some(name => !classes.has(name)))) unavailable();
  return tasks;
}

export function parsePlan(value, expectedId) {
  if (!object(value) || PLAN_FIELDS.some(key => !Object.hasOwn(value, key)) ||
      Object.keys(value).some(key => !PLAN_KEYS.has(key))) unavailable();
  if (value.contract_version !== 1 || value.scope !== 'approved_eligible_data_disposition' ||
      !isRetentionUuid(value.plan_id) || (expectedId !== undefined && value.plan_id !== expectedId) || !isRetentionUuid(value.request_id) ||
      !['planned', 'processing', 'blocked', 'disposition_verified'].includes(value.state) || !count(value.revision) ||
      typeof value.policy_current !== 'boolean' || typeof value.financial_journal_preserved !== 'boolean' ||
      value.operational_acceptance_granted !== false || !Array.isArray(value.tasks) || value.tasks.length > 256) unavailable();
  for (const key of ['policy_sha256', 'source_id', 'schema_sha256', 'scope_snapshot_sha256']) {
    if (!isRetentionHash(value[key])) unavailable();
  }
  assertNoErasureClaim(value);
  const tasks = parseTasks(value);
  for (const key of PLAN_VERIFICATION_FIELDS) {
    if (value[key] !== undefined && typeof value[key] !== 'boolean') unavailable();
  }
  return {...value, tasks};
}

export function parseClaim(value, input) {
  assertRetentionFields(value, ['contract_version', 'claim_id', 'task_id', 'operation_id', 'fence', 'claimed_seconds', 'expires_seconds', 'erasure_completed']);
  if (value.contract_version !== 1 || !isRetentionUuid(value.claim_id) || value.task_id !== input.p_task_id ||
      value.operation_id !== input.p_operation_id || !count(value.fence) || value.fence < 1 ||
      !count(value.claimed_seconds) || value.claimed_seconds < 1 || !count(value.expires_seconds) ||
      value.expires_seconds <= value.claimed_seconds || value.expires_seconds > value.claimed_seconds + 120) unavailable();
  assertNoErasureClaim(value);
  return value;
}

export function parseLookup(value, kind, id) {
  assertRetentionFields(value, ['contract_version', 'scope', 'operation_kind', 'operation_id', 'observed', 'receipt',
    'currentness_not_asserted', 'erasure_completed', 'all_data_erased']);
  if (value.contract_version !== 1 || value.scope !== 'approved_eligible_data_disposition_operation' ||
      value.operation_kind !== kind || value.operation_id !== id || typeof value.observed !== 'boolean' ||
      value.currentness_not_asserted !== true || (value.observed ? !object(value.receipt) : value.receipt !== null)) unavailable();
  assertNoErasureClaim(value);
  return value;
}

export function supportedTask(task) {
  if (task.class_name.startsWith('external:') || task.action === 'blocked') return false;
  if (task.action === 'retain') return task.class_name !== 'access';
  if (task.action === 'quarantine') return task.class_name === 'access';
  return task.action === 'erase' && (SQL_ERASABLE.includes(task.class_name) || task.class_name === 'r2:upload_objects');
}

export function inspectInput(requestId, revision, source) {
  if (!isRetentionUuid(requestId) || !count(revision) || revision > 1000000000 || !isRetentionHash(source)) invalid();
  return {p_request_id: requestId, p_expected_review_revision: revision, p_expected_source_id: source};
}

export function authorityBinding(user, origin) {
  return {
    origin, account_id: user.id, principal_id: user.principalId, session_id: user.sessionId,
    role: user.role, capabilities_sha256: digest(user.permissions),
  };
}

export function assertBinding(current, expected) {
  if (canonical(current) !== canonical(expected)) {
    throw new SafeError('retention_session_changed',
      'Use the original Admin session and unchanged grants. The original operation references remain retained; no action was replayed.');
  }
}
