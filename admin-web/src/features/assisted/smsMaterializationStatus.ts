import type {JsonObject} from '../../api/client';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH = /^[0-9a-f]{64}$/;
const CODE = /^[a-z][a-z0-9_]{0,79}$/;
const MARKER = ['contract_version', 'scope', 'legal_release_approved', 'provider_approved', 'delivery_confirmed'];
const BASE = ['request_id', 'observed', 'status', 'may_be_in_flight', 'planned_count', 'items', 'materialized_jobs', 'materialized_count', 'blocked', 'recorded_state_only', 'may_send', 'transport_started', 'all_source_events_complete'];
export interface SmsMaterializationItem {entryId: string; paymentId: string; status: 'planned' | 'unknown' | 'blocked' | 'committed'; code: string | null; jobId: string | null}
export interface SmsMaterializationStatus {kind: 'materialization'; requestId: string; observed: boolean; status: 'not_recorded' | 'planned' | 'unknown' | 'partial_blocked' | 'bounded_pass'; collectionId: string | null; recordedAt: string | null; plannedCount: number | null; materializedCount: number; hasMore: boolean | null; mayBeInFlight: boolean; items: SmsMaterializationItem[]}
function invalid(): never {throw new Error('The job preparation status could not be verified.');}
function object(value: unknown): value is JsonObject {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function keys(value: JsonObject, fields: string[]) {if (Object.keys(value).length !== fields.length || fields.some(field => !Object.hasOwn(value, field))) invalid();}
function id(value: unknown): string {if (typeof value !== 'string' || !UUID.test(value)) return invalid(); return value.toLowerCase();}
function timestamp(value: unknown): string {if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value) || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString() !== value) return invalid(); return value;}
function receipt(value: unknown, payment: string): {jobId: string; bodyHash: string} {
  if (!object(value)) return invalid();
  keys(value, ['contract_version', 'scope', 'delivery_confirmed', 'provider_confirmation', 'settlement_status', 'job_id', 'payment_id', 'state', 'body_sha256']);
  if (value.contract_version !== 1 || value.scope !== 'assisted_sms_internal_record' || value.delivery_confirmed !== false || value.provider_confirmation !== false || value.settlement_status !== 'not_asserted' ||
      value.state !== 'queued' || id(value.payment_id) !== payment || typeof value.body_sha256 !== 'string' || !HASH.test(value.body_sha256)) return invalid();
  return {jobId: id(value.job_id), bodyHash: value.body_sha256};
}
/** Read-only owner/session-scoped status; no result grants sending or replay authority. */
export function parseSmsMaterializationStatus(body: JsonObject, requestId: string, publicSessionId: string): SmsMaterializationStatus {
  keys(body, ['ok', 'result']); if (body.ok !== true || !object(body.result)) return invalid();
  const row = body.result, observed = row.observed;
  if (typeof observed !== 'boolean') return invalid();
  keys(row, [...MARKER, ...BASE, ...(observed ? ['collection_id', 'source_identity', 'originating_session_id', 'public_session_id', 'recorded_at', 'has_more_observed'] : [])]);
  const request = id(row.request_id);
  if (request !== id(requestId) || row.contract_version !== 1 || row.scope !== 'bounded_receipt_sms_materialization' || row.legal_release_approved !== false || row.provider_approved !== false || row.delivery_confirmed !== false ||
      row.recorded_state_only !== true || row.may_send !== false || row.transport_started !== false || row.all_source_events_complete !== false || !Array.isArray(row.items) || !Array.isArray(row.materialized_jobs)) return invalid();
  if (!observed) {
    if (row.status !== 'not_recorded' || row.may_be_in_flight !== true || row.planned_count !== null || row.items.length || row.materialized_jobs.length || row.materialized_count !== 0 || row.blocked !== null) return invalid();
    return {kind: 'materialization', requestId: request, observed: false, status: 'not_recorded', collectionId: null, recordedAt: null, plannedCount: null, materializedCount: 0, hasMore: null, mayBeInFlight: true, items: []};
  }
  const collectionId = id(row.collection_id); id(row.originating_session_id);
  if (id(row.public_session_id) !== id(publicSessionId) || row.source_identity !== 'immutable_contribution_entry_id' || typeof row.has_more_observed !== 'boolean' ||
      !Number.isInteger(row.planned_count) || (row.planned_count as number) < 0 || (row.planned_count as number) > 10 || row.items.length !== row.planned_count ||
      !Number.isInteger(row.materialized_count) || (row.materialized_count as number) < 0 || (row.materialized_count as number) > row.items.length || row.materialized_jobs.length !== row.materialized_count) return invalid();
  const seen = new Set<string>(), committed: {payment: string; jobId: string; bodyHash: string}[] = [];
  const items: SmsMaterializationItem[] = row.items.map(raw => {
    if (!object(raw)) return invalid(); const entry = id(raw.entry_id), payment = id(raw.payment_id);
    if (seen.has(entry)) return invalid(); seen.add(entry);
    if (raw.status === 'committed') {
      keys(raw, ['entry_id', 'payment_id', 'status', 'receipt']); const result = receipt(raw.receipt, payment);
      committed.push({payment, ...result}); return {entryId: entry, paymentId: payment, status: 'committed', code: null, jobId: result.jobId};
    }
    if (raw.status === 'blocked') {
      keys(raw, ['entry_id', 'payment_id', 'status', 'code']); if (typeof raw.code !== 'string' || !CODE.test(raw.code)) return invalid();
      return {entryId: entry, paymentId: payment, status: 'blocked', code: raw.code, jobId: null};
    }
    if (raw.status === 'planned') {
      keys(raw, ['entry_id', 'payment_id', 'status', 'code', 'resume_safe']); if (raw.code !== null || raw.resume_safe !== true) return invalid();
      return {entryId: entry, paymentId: payment, status: 'planned', code: null, jobId: null};
    }
    if (raw.status === 'unknown') {
      keys(raw, ['entry_id', 'payment_id', 'status', 'code', 'resume_safe']);
      if (!((raw.code === 'enqueue_not_observed' && raw.resume_safe === true) || (raw.code === 'enqueue_readback_mismatch' && raw.resume_safe === false))) return invalid();
      return {entryId: entry, paymentId: payment, status: 'unknown', code: raw.code, jobId: null};
    }
    return invalid();
  });
  if (committed.length !== row.materialized_count) return invalid();
  row.materialized_jobs.forEach((raw, index) => {const expected = committed[index], actual = receipt(raw, expected.payment); if (actual.jobId !== expected.jobId || actual.bodyHash !== expected.bodyHash) invalid();});
  const firstBlocked = items.find(item => item.status === 'blocked'), hasUnknown = items.some(item => item.status === 'unknown');
  if (firstBlocked) {
    if (!object(row.blocked)) return invalid(); keys(row.blocked, ['source_entry_id', 'code']);
    if (id(row.blocked.source_entry_id) !== firstBlocked.entryId || row.blocked.code !== firstBlocked.code) return invalid();
  } else if (row.blocked !== null) return invalid();
  const status = firstBlocked ? 'partial_blocked' : hasUnknown ? 'unknown' : committed.length === items.length ? 'bounded_pass' : 'planned';
  if (row.status !== status || row.may_be_in_flight !== hasUnknown) return invalid();
  return {kind: 'materialization', requestId: request, observed: true, status, collectionId, recordedAt: timestamp(row.recorded_at), plannedCount: row.planned_count as number,
    materializedCount: committed.length, hasMore: row.has_more_observed, mayBeInFlight: hasUnknown, items};
}
