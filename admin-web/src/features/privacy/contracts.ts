import {custodyKey} from '../../custodyRealm';

type Row = Record<string, unknown>;
const flags = ['policy_acceptance_granted', 'destructive_execution_available', 'erasure_completed', 'account_access_restricted', 'auth_removed', 'processor_operation_started'] as const;
const envelope = ['contract_version', 'scope', 'checked_at', 'completion', 'blocking_reason', ...flags];
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const utcPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/;
function invalid(): never {throw new Error('Privacy review evidence could not be verified.');}
function exact(value: unknown, keys: readonly string[]): Row {
  if (!value || typeof value !== 'object' || Array.isArray(value)) invalid();
  const row = value as Row;
  if (Object.keys(row).length !== keys.length || keys.some(key => !Object.hasOwn(row, key))) invalid();
  return row;
}
function uuid(value: unknown): string {if (typeof value !== 'string' || !uuidPattern.test(value)) invalid(); return value;}
interface Time {ms: number; micros: bigint; wire: string}
function date(value: unknown): Time {
  if (typeof value !== 'string' || !utcPattern.test(value)) invalid();
  const result = Date.parse(value);
  if (!Number.isFinite(result) || new Date(result).toISOString().slice(0, 19) !== value.slice(0, 19)) invalid();
  const fraction = value.match(/\.(\d+)Z$/)?.[1] ?? '';
  return {ms: result, micros: BigInt(Math.floor(result / 1000)) * 1_000_000n + BigInt(fraction.padEnd(6, '0') || '0'), wire: value};
}
function count(value: unknown, min = 0): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < min || value > 1_000_000_000) invalid();
  return value;
}
function identity(row: Row) {if (row.contract_version !== 1 || row.scope !== 'account_privacy_review_only') invalid();}
function falseFlags(row: Row, keys: readonly string[]) {if (keys.some(key => row[key] !== false)) invalid();}
function evidence(row: Row, now: number): Time {
  identity(row); falseFlags(row, flags);
  const checked = date(row.checked_at);
  const current = BigInt(now) * 1000n;
  if (row.completion !== 'blocked' || row.blocking_reason !== 'policy_authority_unavailable' || checked.micros > current || current - checked.micros >= 600_000_000n) invalid();
  return checked;
}
export interface RetentionContext {sourceId: string; checkedAt: number; validUntil: number}
export function parseRetentionContext(value: unknown, now = Date.now()): RetentionContext {
  const row = exact(value, ['contract_version', 'scope', 'source_id', 'checked_at', 'valid_until', 'approval_granted', 'erasure_completed']);
  if (row.contract_version !== 1 || row.scope !== 'account_retention_inspection_context' || row.approval_granted !== false || row.erasure_completed !== false ||
      typeof row.source_id !== 'string' || !/^[a-f0-9]{64}$/.test(row.source_id) ||
      typeof row.checked_at !== 'string' || !/\.\d{3}Z$/.test(row.checked_at) || typeof row.valid_until !== 'string' || !/\.\d{3}Z$/.test(row.valid_until)) invalid();
  const checkedAt = date(row.checked_at), validUntil = date(row.valid_until);
  if (checkedAt.ms > now || validUntil.ms <= now || validUntil.ms <= checkedAt.ms || validUntil.ms - checkedAt.ms > 300_000) invalid();
  return {sourceId: row.source_id, checkedAt: checkedAt.ms, validUntil: validUntil.ms};
}
export interface PrivacyItem {requestId: string; acceptedAt: number; acceptedAtWire: string; revision: number; state: string; claimExpiresAt: number | null; claimExpiresAtWire: string | null; outcomeRecordedAt: number | null; outcomeRecordedAtWire: string | null}
export interface PrivacyCursor {requestId: string; acceptedAt: number; acceptedAtWire: string}
function cursor(value: unknown): PrivacyCursor {const row = exact(value, ['accepted_at', 'request_id']), accepted = date(row.accepted_at); return {acceptedAt: accepted.ms, acceptedAtWire: accepted.wire, requestId: uuid(row.request_id)};}
function before(cursorValue: PrivacyCursor, item: PrivacyCursor): boolean {
  const a = date(item.acceptedAtWire).micros, b = date(cursorValue.acceptedAtWire).micros;
  return a < b || a === b && item.requestId < cursorValue.requestId;
}
function item(value: unknown, checked: Time): PrivacyItem {
  const row = exact(value, ['request_id', 'accepted_at', 'revision', 'review_state', 'claim_expires_at', 'outcome_code', 'outcome_recorded_at']);
  const requestId = uuid(row.request_id), acceptedAt = date(row.accepted_at), revision = count(row.revision);
  const state = row.review_state, claimExpiresAt = row.claim_expires_at === null ? null : date(row.claim_expires_at);
  const outcomeRecordedAt = row.outcome_recorded_at === null ? null : date(row.outcome_recorded_at);
  if (acceptedAt.micros > checked.micros || typeof state !== 'string' || !['not_started', 'awaiting_review', 'claim_active', 'claim_expired', 'blocked'].includes(state)) invalid();
  if (state === 'not_started' || state === 'awaiting_review') {
    if (revision !== 0 || claimExpiresAt !== null || outcomeRecordedAt !== null || row.outcome_code !== null) invalid();
  } else if (state === 'blocked') {
    if (revision < 2 || claimExpiresAt === null || outcomeRecordedAt === null || row.outcome_code !== 'policy_authority_unavailable' || outcomeRecordedAt.micros < acceptedAt.micros || outcomeRecordedAt.micros > checked.micros || outcomeRecordedAt.micros >= claimExpiresAt.micros) invalid();
  } else if (revision < 1 || claimExpiresAt === null || outcomeRecordedAt !== null || row.outcome_code !== null || (state === 'claim_active') !== (claimExpiresAt.micros > checked.micros)) invalid();
  return {requestId, acceptedAt: acceptedAt.ms, acceptedAtWire: acceptedAt.wire, revision, state,
    claimExpiresAt: claimExpiresAt?.ms ?? null, claimExpiresAtWire: claimExpiresAt?.wire ?? null,
    outcomeRecordedAt: outcomeRecordedAt?.ms ?? null, outcomeRecordedAtWire: outcomeRecordedAt?.wire ?? null};
}
export interface PrivacyPageData {checkedAt: number; items: PrivacyItem[]; next: PrivacyCursor | null}
export function parsePrivacyPage(value: unknown, limit: number, prior: PrivacyCursor | null, now = Date.now()): PrivacyPageData {
  const row = exact(value, [...envelope, 'items', 'limit', 'next_cursor']);
  const checkedAt = evidence(row, now);
  if (count(row.limit, 1) !== limit || limit > 100 || !Array.isArray(row.items) || row.items.length > limit) invalid();
  const items = row.items.map(entry => item(entry, checkedAt));
  if (new Set(items.map(entry => entry.requestId)).size !== items.length) invalid();
  let current = prior;
  for (const entry of items) {if (current && !before(current, entry)) invalid(); current = entry;}
  const next = row.next_cursor === null ? null : cursor(row.next_cursor);
  const last = items.at(-1);
  if (next && (items.length !== limit || !last || next.requestId !== last.requestId || date(next.acceptedAtWire).micros !== date(last.acceptedAtWire).micros)) invalid();
  return {checkedAt: checkedAt.ms, items, next};
}
interface Claim {requestId: string; operationId: string; claimId: string; revision: number; fence: number; claimedAt: Time; expiresAt: Time}
function claim(value: unknown): Claim {
  const row = exact(value, ['contract_version', 'scope', 'request_id', 'claim_request_id', 'claim_id', 'revision', 'fence', 'claimed_at', 'expires_at', 'policy_acceptance_granted', 'destructive_execution_available', 'erasure_completed']);
  identity(row); falseFlags(row, flags.slice(0, 3));
  const claimedAt = date(row.claimed_at), expiresAt = date(row.expires_at), revision = count(row.revision, 1), fence = count(row.fence, 1);
  if (expiresAt.micros - claimedAt.micros < 1_000_000n || expiresAt.micros - claimedAt.micros > 120_000_000n || fence > revision) invalid();
  return {requestId: uuid(row.request_id), operationId: uuid(row.claim_request_id), claimId: uuid(row.claim_id), revision, fence, claimedAt, expiresAt};
}
interface Outcome {requestId: string; operationId: string; claimId: string; revision: number; fence: number; recordedAt: Time}
function outcome(value: unknown): Outcome {
  const row = exact(value, ['contract_version', 'scope', 'request_id', 'outcome_request_id', 'claim_id', 'revision', 'fence', 'outcome_code', 'recorded_at', 'completion', ...flags]);
  identity(row); falseFlags(row, flags);
  if (row.outcome_code !== 'policy_authority_unavailable' || row.completion !== 'blocked') invalid();
  return {requestId: uuid(row.request_id), operationId: uuid(row.outcome_request_id), claimId: uuid(row.claim_id), revision: count(row.revision, 2), fence: count(row.fence, 1), recordedAt: date(row.recorded_at)};
}
export interface PrivacyDetail {checkedAt: number; item: PrivacyItem | null; ownClaim: boolean; claim: {claimId: string; fence: number; expiresAt: number} | null}
export function parsePrivacyDetail(value: unknown, requestId: string, now = Date.now()): PrivacyDetail {
  uuid(requestId);
  const row = exact(value, [...envelope, 'item', 'own_claim_receipt', 'own_outcome_receipt', 'own_claim_authority_current']);
  const checkedAt = evidence(row, now), entry = row.item === null ? null : item(row.item, checkedAt);
  const ownClaim = row.own_claim_receipt === null ? null : claim(row.own_claim_receipt);
  const ownOutcome = row.own_outcome_receipt === null ? null : outcome(row.own_outcome_receipt);
  if (typeof row.own_claim_authority_current !== 'boolean' || entry && entry.requestId !== requestId || ownClaim && ownClaim.requestId !== requestId || ownOutcome && ownOutcome.requestId !== requestId || !entry && (ownClaim || ownOutcome || row.own_claim_authority_current)) invalid();
  if (row.own_claim_authority_current && (!entry || entry.state !== 'claim_active' || !ownClaim || ownClaim.revision !== entry.revision || !entry.claimExpiresAtWire || ownClaim.expiresAt.micros !== date(entry.claimExpiresAtWire).micros || ownClaim.expiresAt.micros <= checkedAt.micros || ownClaim.claimedAt.micros > checkedAt.micros || ownClaim.claimedAt.micros < date(entry.acceptedAtWire).micros || ownOutcome)) invalid();
  if (ownOutcome && (!entry || entry.state !== 'blocked' || ownOutcome.revision !== entry.revision || !entry.outcomeRecordedAtWire || ownOutcome.recordedAt.micros !== date(entry.outcomeRecordedAtWire).micros || !ownClaim || ownOutcome.claimId !== ownClaim.claimId || ownOutcome.fence !== ownClaim.fence || ownOutcome.revision !== ownClaim.revision + 1 || ownOutcome.recordedAt.micros < ownClaim.claimedAt.micros || ownOutcome.recordedAt.micros >= ownClaim.expiresAt.micros)) invalid();
  return {checkedAt: checkedAt.ms, item: entry, ownClaim: row.own_claim_authority_current,
    claim: row.own_claim_authority_current && ownClaim ? {claimId: ownClaim.claimId, fence: ownClaim.fence, expiresAt: ownClaim.expiresAt.ms} : null};
}

export interface RetentionInspection {objectCount: number; activeHoldCount: number; inFlightUnresolved: boolean; tableCounts: Record<string, number>; sourceId: string; schemaSha256: string; snapshotSha256: string}
export function parseRetentionInspection(value: unknown, requestId: string, sourceId: string, actorId: string): RetentionInspection {
  const row = exact(value, ['contract_version', 'request_id', 'subject_id', 'source_id', 'schema_sha256', 'snapshot_sha256',
    'table_counts', 'object_count', 'active_hold_count', 'in_flight_unresolved', 'approval_granted', 'erasure_completed']);
  const sha = (input: unknown): string => {if (typeof input !== 'string' || !/^[a-f0-9]{64}$/.test(input)) invalid(); return input;};
  const safeCount = (input: unknown): number => {if (typeof input !== 'number' || !Number.isSafeInteger(input) || input < 0) invalid(); return input;};
  if (row.contract_version !== 1 || uuid(row.request_id) !== requestId || uuid(row.subject_id) === actorId || sha(row.source_id) !== sourceId ||
      typeof row.in_flight_unresolved !== 'boolean' || row.approval_granted !== false || row.erasure_completed !== false ||
      !row.table_counts || typeof row.table_counts !== 'object' || Array.isArray(row.table_counts)) invalid();
  const rawCounts = row.table_counts as Row, names = Object.keys(rawCounts);
  if (!names.length || names.length > 512 || names.some(name => !/^[a-z][a-z0-9_]{0,62}$/.test(name))) invalid();
  const tableCounts = Object.fromEntries(names.sort().map(name => [name, safeCount(rawCounts[name])]));
  return {objectCount: safeCount(row.object_count), activeHoldCount: safeCount(row.active_hold_count), inFlightUnresolved: row.in_flight_unresolved,
    tableCounts, sourceId, schemaSha256: sha(row.schema_sha256), snapshotSha256: sha(row.snapshot_sha256)};
}

export interface PrivacyPending {kind: 'claim' | 'outcome'; operationId: string; requestId: string; actorId: string; sessionId: string; parameters: Row}
export function privacyIntentApplies(intent: PrivacyPending, detail: PrivacyDetail, now: number): boolean {
  const item = detail.item;
  if (!item || item.requestId !== intent.requestId || now < detail.checkedAt || now - detail.checkedAt >= 600_000) return false;
  if (intent.kind === 'claim') return ['not_started', 'awaiting_review', 'claim_expired'].includes(item.state) && item.revision < 999_999_999 &&
    intent.parameters.p_request_id === item.requestId && intent.parameters.p_expected_revision === item.revision;
  return detail.ownClaim && !!detail.claim && detail.claim.expiresAt > now && intent.parameters.p_claim_id === detail.claim.claimId && intent.parameters.p_fence === detail.claim.fence;
}
export function privacyJournalKey(actorId: string, sessionId: string): string {return custodyKey(`collect.privacy-review.v1.${uuid(actorId)}.${uuid(sessionId)}`);}
export function parsePrivacyJournal(raw: string | null, actorId: string, sessionId: string): {generation: number; pending: PrivacyPending | null} {
  uuid(actorId); uuid(sessionId);
  if (raw === null) return {generation: 0, pending: null};
  if (new TextEncoder().encode(raw).length > 4096) invalid();
  let value: unknown;
  try {value = JSON.parse(raw);} catch {invalid();}
  const row = exact(value, ['version', 'generation', 'actor_id', 'session_id', 'pending']);
  if (row.version !== 1 || row.actor_id !== actorId || row.session_id !== sessionId) invalid();
  const generation = count(row.generation);
  if (row.pending === null) return {generation, pending: null};
  if (!generation) invalid();
  const pending = exact(row.pending, ['kind', 'operation_id', 'actor_id', 'session_id', 'request_id', 'parameters']);
  if ((pending.kind !== 'claim' && pending.kind !== 'outcome') || pending.actor_id !== actorId || pending.session_id !== sessionId) invalid();
  const operationId = uuid(pending.operation_id), requestId = uuid(pending.request_id);
  const parameters = exact(pending.parameters, pending.kind === 'claim' ?
    ['p_request_id', 'p_claim_request_id', 'p_expected_revision', 'p_lease_seconds'] :
    ['p_outcome_request_id', 'p_claim_id', 'p_fence', 'p_outcome_code']);
  if (pending.kind === 'claim') {
    if (uuid(parameters.p_request_id) !== requestId || uuid(parameters.p_claim_request_id) !== operationId || parameters.p_lease_seconds !== 60 || count(parameters.p_expected_revision) > 999_999_998) invalid();
  } else if (uuid(parameters.p_outcome_request_id) !== operationId || !uuid(parameters.p_claim_id) || count(parameters.p_fence, 1) < 1 || parameters.p_outcome_code !== 'policy_authority_unavailable') invalid();
  return {generation, pending: {kind: pending.kind, operationId, requestId, actorId, sessionId, parameters}};
}
export function parsePrivacyCheckpoint(raw: string | null, actorId: string, sessionId: string): PrivacyPending | null {return parsePrivacyJournal(raw, actorId, sessionId).pending;}

export function validatePrivacyReceipt(value: unknown, pending: PrivacyPending): Claim | Outcome {
  if (pending.kind === 'claim') {
    const receipt = claim(value);
    if (receipt.operationId !== pending.operationId || receipt.requestId !== pending.requestId || receipt.revision !== Number(pending.parameters.p_expected_revision) + 1 ||
        receipt.expiresAt.micros - receipt.claimedAt.micros !== 60_000_000n) invalid();
    return receipt;
  }
  const receipt = outcome(value);
  if (receipt.operationId !== pending.operationId || receipt.requestId !== pending.requestId || receipt.claimId !== pending.parameters.p_claim_id || receipt.fence !== pending.parameters.p_fence) invalid();
  return receipt;
}

export function parsePrivacyOperation(value: unknown, pending: PrivacyPending, now = Date.now()): boolean {
  const row = exact(value, [...envelope, 'operation_kind', 'operation_id', 'observed', 'receipt', 'claim_authority_current']);
  const checkedAt = evidence(row, now);
  if (row.operation_kind !== pending.kind || row.operation_id !== pending.operationId || typeof row.observed !== 'boolean' ||
      typeof row.claim_authority_current !== 'boolean' || row.observed !== (row.receipt !== null) ||
      (!row.observed || pending.kind === 'outcome') && row.claim_authority_current !== false) invalid();
  if (!row.observed) return false;
  const receipt = validatePrivacyReceipt(row.receipt, pending);
  if (pending.kind === 'claim') {
    if (!('expiresAt' in receipt) || row.claim_authority_current && receipt.expiresAt.micros <= checkedAt.micros) invalid();
  }
  return true;
}
