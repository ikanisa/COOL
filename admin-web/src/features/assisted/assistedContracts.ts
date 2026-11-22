import type {JsonObject} from '../../api/client';

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i, HASH = /^[a-f0-9]{64}$/;
const MARKER = ['contract_version', 'scope', 'delivery_confirmed', 'provider_confirmation', 'settlement_status'];
export const ACTIONS = ['claim', 'confirm', 'record_send_start', 'release_claim', 'record_outcome'] as const;
export type Action = typeof ACTIONS[number];
export type AssistedObservation = 'observed_sent' | 'failed_no_send' | 'uncertain';
export interface Claim {jobId: string; claimToken: string; fence: number; workerId: string; expires: string; originatingSessionId: string; publicSessionId: string}
export interface Content {jobId: string; claimToken: string; fence: number; destination: string; destinationHash: string; destinationRevision: number; message: string; bodyHash: string; paymentId: string; expires: string}
export interface Confirmation {jobId: string; confirmationId: string; claimToken: string; fence: number; bodyHash: string; destinationHash: string; destinationRevision: number; expires: string; originatingSessionId: string; publicSessionId: string}
export interface Start {attemptId: string; jobId: string; confirmationId: string; claimToken: string; fence: number; originatingSessionId: string; publicSessionId: string; maySend: boolean; dispatchToken: string | null}
interface ReceiptDetails {action: Action | 'enqueue'; resourceId: string; attemptId: string | null; observation: AssistedObservation | null; evidenceReferenceSha256: string | null}

export function invalid(): never {throw new Error('The assisted SMS response could not be verified.');}
function object(value: unknown): value is JsonObject {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function fields(value: JsonObject, required: string[], optional: string[] = []) {if (required.some((key) => !Object.hasOwn(value, key)) || Object.keys(value).some((key) => !required.includes(key) && !optional.includes(key))) invalid();}
function identifier(value: unknown): string {if (typeof value !== 'string' || !UUID.test(value)) return invalid(); return value.toLowerCase();}
function hash(value: unknown): string {if (typeof value !== 'string' || !HASH.test(value)) return invalid(); return value;}
function integer(value: unknown, minimum = 0, maximum = Number.MAX_SAFE_INTEGER): number {if (!Number.isSafeInteger(value) || (value as number) < minimum || (value as number) > maximum) return invalid(); return value as number;}
function time(value: unknown): string {
  if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)) return invalid();
  const date = new Date(value); if (!Number.isFinite(date.getTime()) || date.toISOString() !== value) return invalid(); return value;
}
function row(value: unknown, required: string[], optional: string[] = []): JsonObject {
  if (!object(value)) return invalid(); fields(value, [...MARKER, ...required], optional);
  if (value.contract_version !== 1 || value.scope !== 'assisted_sms_internal_record' || value.delivery_confirmed !== false || value.provider_confirmation !== false || value.settlement_status !== 'not_asserted') return invalid();
  return value;
}
export function result(body: JsonObject): JsonObject {fields(body, ['ok', 'result']); if (body.ok !== true || !object(body.result)) return invalid(); return body.result;}
export function checkedClaim(value: unknown, allowReplay = false): Claim {
  const data = row(value, ['job_id', 'claim_token', 'fence_version', 'worker_id', 'claim_expires_at', 'originating_session_id', 'public_session_id'], allowReplay ? ['replay'] : []);
  if (Object.hasOwn(data, 'replay') && data.replay !== false) return invalid();
  if (typeof data.worker_id !== 'string' || !/^[A-Za-z0-9._:-]{3,80}$/.test(data.worker_id)) return invalid();
  return {jobId: identifier(data.job_id), claimToken: identifier(data.claim_token), fence: integer(data.fence_version, 1, 999_999_998), workerId: data.worker_id, expires: time(data.claim_expires_at), originatingSessionId: identifier(data.originating_session_id), publicSessionId: identifier(data.public_session_id)};
}
export function checkedConfirmation(value: unknown, allowReplay = false): Confirmation {
  const data = row(value, ['job_id', 'confirmation_id', 'claim_token', 'fence_version', 'body_sha256', 'destination_sha256', 'destination_revision', 'expires_at', 'originating_session_id', 'public_session_id'], allowReplay ? ['replay'] : []);
  if (Object.hasOwn(data, 'replay') && data.replay !== false) return invalid();
  return {jobId: identifier(data.job_id), confirmationId: identifier(data.confirmation_id), claimToken: identifier(data.claim_token), fence: integer(data.fence_version, 1, 999_999_998), bodyHash: hash(data.body_sha256), destinationHash: hash(data.destination_sha256), destinationRevision: integer(data.destination_revision, 1), expires: time(data.expires_at), originatingSessionId: identifier(data.originating_session_id), publicSessionId: identifier(data.public_session_id)};
}
export function checkedStart(value: unknown, stored = false): Start {
  const data = row(value, ['attempt_id', 'job_id', 'confirmation_id', 'claim_token', 'fence_version', 'state', 'originating_session_id', 'public_session_id'], stored ? [] : ['replay', 'may_send', 'acknowledgement', 'dispatch_token']);
  if (data.state !== 'send_started') return invalid();
  let maySend = false;
  if (!stored) {
    if (data.may_send === true && data.replay === false && data.acknowledgement === 'first_committed_response_only') maySend = true;
    else if (!(data.may_send === false && data.replay === true && ['recorded_start_permit_not_reissued', 'concurrent_start_observed_permit_not_reissued', 'start_observed_after_unknown_reply_permit_not_reissued'].includes(typeof data.acknowledgement === 'string' ? data.acknowledgement : ''))) return invalid();
  }
  const dispatchToken=Object.hasOwn(data,'dispatch_token')?hash(data.dispatch_token):null;
  if(dispatchToken&&!maySend)return invalid();
  return {attemptId: identifier(data.attempt_id), jobId: identifier(data.job_id), confirmationId: identifier(data.confirmation_id), claimToken: identifier(data.claim_token), fence: integer(data.fence_version, 1, 999_999_998), originatingSessionId: identifier(data.originating_session_id), publicSessionId: identifier(data.public_session_id), maySend, dispatchToken};
}
export function checkedRelease(value: unknown): {jobId: string; fence: number} {
  const data = row(value, ['job_id', 'state', 'fence_version']); if (data.state !== 'queued') return invalid();
  return {jobId: identifier(data.job_id), fence: integer(data.fence_version, 2, 999_999_999)};
}
export function checkedOutcome(value: unknown): {attemptId: string; observation: AssistedObservation; evidence: string} {
  const data = row(value, ['attempt_id', 'observation', 'evidence_reference_sha256', 'may_send']);
  if (data.may_send !== false || (typeof data.observation !== 'string' || !['observed_sent', 'failed_no_send', 'uncertain'].includes(data.observation))) return invalid();
  return {attemptId: identifier(data.attempt_id), observation: data.observation as AssistedObservation, evidence: hash(data.evidence_reference_sha256)};
}

export function parseClaimedContent(response: JsonObject): Content {
  const data = row(response, ['job_id', 'claim_token', 'fence_version', 'destination_e164', 'destination_sha256', 'destination_revision', 'message_body', 'body_sha256', 'payment_id', 'template_key', 'claim_expires_at']);
  const destination = data.destination_e164, message = data.message_body;
  if (typeof destination !== 'string' || !/^\+2507[2389][0-9]{7}$/.test(destination) || typeof message !== 'string' || !message || message.length > 4096 || data.template_key !== 'collect.recorded_contribution.v1') return invalid();
  return {jobId: identifier(data.job_id), claimToken: identifier(data.claim_token), fence: integer(data.fence_version, 1, 999_999_998), destination, destinationHash: hash(data.destination_sha256), destinationRevision: integer(data.destination_revision, 1), message, bodyHash: hash(data.body_sha256), paymentId: identifier(data.payment_id), expires: time(data.claim_expires_at)};
}

export function parseOperatorReceipt(response: JsonObject, requestId: string, sessionId: string): ReceiptDetails | null {
  const value = row(response, ['request_id', 'observed', 'receipt', 'may_send']);
  if (identifier(value.request_id) !== requestId || typeof value.observed !== 'boolean' || value.may_send !== false || (value.observed === false) !== (value.receipt === null)) return invalid();
  if (!value.observed) return null;
  if (!object(value.receipt)) return invalid();
  const receipt = value.receipt, noObservation = {attemptId: null, observation: null, evidenceReferenceSha256: null};
  if (Object.hasOwn(receipt, 'worker_id')) {const claim = checkedClaim(receipt); if (claim.publicSessionId !== sessionId.toLowerCase()) return invalid(); return {action: 'claim', resourceId: claim.jobId, ...noObservation};}
  if (Object.hasOwn(receipt, 'expires_at')) {const confirmation = checkedConfirmation(receipt); if (confirmation.publicSessionId !== sessionId.toLowerCase()) return invalid(); return {action: 'confirm', resourceId: confirmation.jobId, ...noObservation};}
  if (receipt.state === 'send_started') {const start = checkedStart(receipt, true); if (start.publicSessionId !== sessionId.toLowerCase()) return invalid(); return {action: 'record_send_start', resourceId: start.jobId, ...noObservation, attemptId: start.attemptId};}
  if (Object.hasOwn(receipt, 'observation')) {const outcome = checkedOutcome(receipt); return {action: 'record_outcome', resourceId: outcome.attemptId, attemptId: outcome.attemptId, observation: outcome.observation, evidenceReferenceSha256: outcome.evidence};}
  if (Object.hasOwn(receipt, 'payment_id')) {const queued = row(receipt, ['job_id', 'payment_id', 'state', 'body_sha256']); if (queued.state !== 'queued') return invalid(); identifier(queued.payment_id); hash(queued.body_sha256); return {action: 'enqueue', resourceId: identifier(queued.job_id), ...noObservation};}
  const release = checkedRelease(receipt); return {action: 'release_claim', resourceId: release.jobId, ...noObservation};
}

export const ASSISTED_PAGE_SIZE = 20;
export type JobState = 'queued' | 'claimed' | 'send_started' | 'uncertain';
export interface AssistedCursor {after_created_at: string; after_job_id: string}
export interface AssistedJob {id: string; payment_id: string; state: JobState; created_at: string; fence: number; attempt_id: string | null}
export interface AssistedPage {items: AssistedJob[]; next_cursor: AssistedCursor | null}

function cursor(value: unknown): AssistedCursor {
  if (!object(value)) return invalid();
  fields(value, ['after_created_at', 'after_job_id']);
  return {after_created_at: time(value.after_created_at), after_job_id: identifier(value.after_job_id)};
}

/** Reject inconsistent receipts, page boundaries and job states before display. */
export function parseAssistedPage(body: JsonObject, previous: AssistedCursor | null = null, limit = ASSISTED_PAGE_SIZE): AssistedPage {
  if (!Number.isInteger(limit) || limit < 1 || limit > 50) return invalid();
  const data = row(result(body), ['items', 'next_cursor']);
  if (!Array.isArray(data.items) || data.items.length > limit) return invalid();
  let last: AssistedCursor | null = previous ? cursor(previous) : null;
  const ids = new Set<string>();
  const items = data.items.map((value): AssistedJob => {
    if (!object(value)) return invalid();
    fields(value, ['id', 'payment_id', 'state', 'created_at', 'fence', 'attempt_id']);
    const jobId = identifier(value.id), paymentId = identifier(value.payment_id), created = time(value.created_at);
    if (typeof value.state !== 'string' || !['queued', 'claimed', 'send_started', 'uncertain'].includes(value.state) || !Number.isSafeInteger(value.fence) || (value.fence as number) < 0 || (value.fence as number) > 999_999_999) return invalid();
    const state = value.state as JobState, attempt = value.attempt_id === null ? null : identifier(value.attempt_id);
    if ((state === 'send_started' || state === 'uncertain') !== (attempt !== null) || (state !== 'queued' && (value.fence as number) < 1) || ids.has(jobId)) return invalid();
    if (last && (created < last.after_created_at || (created === last.after_created_at && jobId <= last.after_job_id))) return invalid();
    ids.add(jobId); last = {after_created_at: created, after_job_id: jobId};
    return {id: jobId, payment_id: paymentId, state, created_at: created, fence: value.fence as number, attempt_id: attempt};
  });
  const next = data.next_cursor === null ? null : cursor(data.next_cursor);
  if (next && (items.length !== limit || !last || next.after_created_at !== last.after_created_at || next.after_job_id !== last.after_job_id)) return invalid();
  return {items, next_cursor: next};
}
