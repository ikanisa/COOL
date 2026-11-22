/* eslint-disable no-control-regex -- Reject prohibited control characters in operator-supplied evidence. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import { clearPending, readPending, retainPending, sha256Text, type PendingAttempt } from '../core/pendingAttempt';
import { parseMomoDetail, type MomoDetail } from './momoContracts';
import { withPendingFence, type FenceAccess } from './pendingFence';
import type {OperationPending, OperationRequestContext} from './operationRequestCustody';
import {momoOwnerBinding} from './momoOwnerBinding';

const FAMILY = 'momo-review-conflict', PERMISSION = 'payments.write', BINDING_PREFIX = 'collect.admin.momo-conflict.owner.v1:';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const id = z.string().regex(UUID);

export interface MomoConflictContext extends OperationRequestContext {
  request: AdminRequest; principalId: string; financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; detail: MomoDetail;
  /** Do not enable until cross-version coordination and backend recovery are qualified. */
  enabled: boolean; isEnabled?: () => boolean; verifyFresh: () => Promise<boolean>;
}
export interface MomoConflictIntent {expected_version: number; expected_conflicting_attempt_ids: string[]; decision: 'retain_original'; evidence_reference: string; reason: string;}
export interface MomoConflictReceipt {transactionId: string; version: number; status: 'needs_allocation'; financialEffects: 0;}
export type MomoConflictPending = OperationPending;
export type MomoConflictResult = {status: 'succeeded'; receipt: MomoConflictReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: MomoConflictPending};

function fail(message: string): never {throw new Error(message);}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));}
function current(context: MomoConflictContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'canonical_evidence_ledger' || !UUID.test(context.principalId) ||
      !['payments.read', PERMISSION, 'sms.extract'].every((permission) => context.identity.permissions.includes(permission)) ||
      !Number.isFinite(expires) || expires <= Date.now() || !UUID.test(context.detail.transaction.id)) fail('Conflict review is unavailable to your current account.');
}
function write(context: MomoConflictContext) {
  current(context);
  if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Conflict review is not enabled for the current workspace.');
}
export function parseMomoConflictIntent(input: unknown): MomoConflictIntent {
  if (!input || typeof input !== 'object' || Array.isArray(input)) fail('The original conflict review could not be verified.');
  const body = input as Record<string, unknown>, attempts = body.expected_conflicting_attempt_ids;
  const validText = (value: unknown) => typeof value === 'string' && value === value.trim() && value.length >= 8 && value.length <= 500 && !/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value);
  if (!exact(body, ['expected_version', 'expected_conflicting_attempt_ids', 'decision', 'evidence_reference', 'reason']) ||
      typeof body.expected_version !== 'number' || !Number.isSafeInteger(body.expected_version) || body.expected_version < 1 || body.expected_version >= Number.MAX_SAFE_INTEGER ||
      body.decision !== 'retain_original' || !Array.isArray(attempts) || attempts.length < 1 || attempts.length > 100 || attempts.some((attempt) => typeof attempt !== 'string' || !UUID.test(attempt)) || new Set(attempts).size !== attempts.length ||
      !validText(body.evidence_reference) || !validText(body.reason)) fail('The original conflict review could not be verified.');
  return {expected_version: body.expected_version, expected_conflicting_attempt_ids: [...attempts] as string[], decision: 'retain_original', evidence_reference: body.evidence_reference as string, reason: body.reason as string};
}
function verifyAttempt(attempt: PendingAttempt, context: MomoConflictContext) {
  if (attempt.family !== FAMILY || attempt.resource_id !== context.detail.transaction.id || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key)) fail('The original conflict review could not be verified.');
  return parseMomoConflictIntent(attempt.intent);
}

/** Require source rows for the complete bounded set, not only the server's ID list. */
export function momoConflictSources(detail: MomoDetail) {
  const ids = detail.conflicting_attempt_ids;
  if (!ids || ids.length < 1 || ids.length > 100 || ids.some((value) => !UUID.test(value)) || new Set(ids).size !== ids.length) fail('The complete conflict set could not be verified.');
  const accepted = detail.sources.filter((source) => source.relation === 'accepted' && source.outcome === 'accepted');
  const conflicts = detail.sources.filter((source) => source.relation === 'conflict');
  if (accepted.length !== 1 || !accepted[0].attempt_id || !UUID.test(accepted[0].attempt_id) ||
      conflicts.length !== ids.length || conflicts.some((source) => !source.attempt_id || !UUID.test(source.attempt_id)) ||
      new Set(conflicts.map((source) => source.attempt_id)).size !== ids.length || conflicts.some((source) => !ids.includes(source.attempt_id!))) fail('The complete source evidence could not be verified.');
  return {accepted: accepted[0], conflicts: [...conflicts].sort((a, b) => a.attempt_id!.localeCompare(b.attempt_id!)), ids: [...ids].sort()};
}
export function canReviewMomoConflict(detail: MomoDetail): boolean {
  try {readyDetail(detail); return true;} catch {return false;}
}
function readyDetail(detail: MomoDetail) {
  const tx = detail.transaction;
  if (tx.has_conflict !== 1 || tx.allocation_state !== 'needs_review' || tx.status !== 'needs_review' || tx.payment_id !== null || tx.version >= Number.MAX_SAFE_INTEGER) fail('The unlinked conflict is no longer available for review.');
  return momoConflictSources(detail);
}
function sourceSnapshot(detail: MomoDetail) {
  const {accepted, conflicts, ids} = momoConflictSources(detail), tx = detail.transaction;
  const source = (row: typeof accepted) => ({raw_sms_id: row.raw_sms_id, attempt_id: row.attempt_id, relation: row.relation, outcome: row.outcome, parser_version: row.parser_version, created_at: row.created_at});
  return {transaction: {id: tx.id, receiving_account_id: tx.receiving_account_id, public_code: tx.public_code, recipient_name: tx.recipient_name,
    provider_transaction_id: tx.provider_transaction_id, payer_name: tx.payer_name, payer_last3: tx.payer_last3, amount_minor: tx.amount_minor,
    currency: tx.currency, event_kind: tx.event_kind, transaction_at: tx.transaction_at, created_at: tx.created_at}, accepted: source(accepted), conflicts: conflicts.map(source), ids};
}
function sourceDigest(detail: MomoDetail) {
  return sha256Text(JSON.stringify(sourceSnapshot(detail)));
}
const ownerBinding = momoOwnerBinding<MomoConflictContext>(
  context => BINDING_PREFIX + context.detail.transaction.id, current, 'The original conflict review identity could not be verified.', true,
);
async function withFence<T>(context: MomoConflictContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: FAMILY, resourceId: context.detail.transaction.id, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restoreUnderFence(context: MomoConflictContext, access: FenceAccess): Promise<MomoConflictPending> {
  current(context); const fence = access.read();
  if (fence.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, FAMILY, context.detail.transaction.id, context.storage);
  if (attempt) verifyAttempt(attempt, context);
  const owner = attempt ? await ownerBinding.read(context, attempt.request_key) : {kind: 'missing' as const}; current(context);
  if (owner.kind === 'foreign') return {kind: 'foreign'};
  if (fence.kind === 'owned') {if (attempt && attempt.request_key !== fence.requestKey) fail('The original conflict review could not be verified.'); return {kind: 'owned', requestKey: fence.requestKey, attempt: owner.kind === 'valid' ? attempt : null};}
  if (attempt) {access.reserve(attempt.request_key, fence.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt: owner.kind === 'valid' ? attempt : null};}
  return {kind: 'ready', revision: fence.revision};
}
export async function restoreMomoConflict(context: MomoConflictContext): Promise<MomoConflictPending> {current(context); return withFence(context, (access) => restoreUnderFence(context, access));}
async function clear(context: MomoConflictContext, access: FenceAccess, pending: Extract<MomoConflictPending, {kind: 'owned'}>) {
  if (pending.attempt) {await ownerBinding.clear(context, pending.requestKey); await clearPending(context.identity, FAMILY, context.detail.transaction.id, pending.requestKey, context.storage);}
  current(context); access.clear(pending.requestKey);
}
function receipt(value: unknown, context: MomoConflictContext, intent: MomoConflictIntent): MomoConflictReceipt {
  const body = z.object({transaction_id: id, version: z.number().int().min(2).max(Number.MAX_SAFE_INTEGER), status: z.literal('needs_allocation'), financial_effects: z.literal(0)}).strict().parse(value);
  if (body.transaction_id !== context.detail.transaction.id || body.version !== intent.expected_version + 1) fail('The conflict review response could not be verified.');
  return {transactionId: body.transaction_id, version: body.version, status: body.status, financialEffects: body.financial_effects};
}
async function freshDetail(context: MomoConflictContext) {
  const data = parseMomoDetail(await context.request(`momo/transactions/${context.detail.transaction.id}`), context.detail.transaction.id); current(context); return data;
}
export async function submitMomoConflict(context: MomoConflictContext, evidence: string, reason: string, observedRevision: string): Promise<MomoConflictResult> {
  write(context); const sources = readyDetail(context.detail);
  const intent = parseMomoConflictIntent({expected_version: context.detail.transaction.version, expected_conflicting_attempt_ids: sources.ids, decision: 'retain_original', evidence_reference: evidence.trim(), reason: reason.trim()});
  return withFence(context, async (access) => {
    const existing = await restoreUnderFence(context, access);
    if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const fresh = await freshDetail(context); readyDetail(fresh);
    const before = await sourceDigest(context.detail), after = await sourceDigest(fresh);
    if (context.detail.transaction.version !== fresh.transaction.version || before !== after) fail('The conflict or its source evidence changed. Review it again.');
    write(context);
    if (!await context.verifyFresh()) fail('Complete current verification before recording the conflict review.');
    write(context); const requestKey = (context.createKey ?? (() => crypto.randomUUID()))();
    if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision);
    let attempt: PendingAttempt;
    try {
      attempt = await retainPending(context.identity, FAMILY, context.detail.transaction.id, requestKey, PERMISSION, {...intent}, context.storage);
      verifyAttempt(attempt, context); await ownerBinding.retain(context, requestKey, before);
    } catch (error) {
      if (context.isCurrent()) {try {const retained = await readPending(context.identity, FAMILY, context.detail.transaction.id, context.storage); if (retained?.request_key === requestKey) await clearPending(context.identity, FAMILY, context.detail.transaction.id, requestKey, context.storage); await ownerBinding.clear(context, requestKey); access.clear(requestKey);} catch { /* Preserve the fence when cleanup cannot be verified. */ }}
      throw error;
    }
    const pending: Extract<MomoConflictPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey};
    try {
      const response = await context.request(`momo/transactions/${context.detail.transaction.id}/review-conflict`, {method: 'POST', body: {...intent}, idempotencyKey: requestKey});
      current(context); const saved = receipt(response, context, intent); await clear(context, access, pending); return {status: 'succeeded', receipt: saved};
    } catch {return {status: 'unknown', requestKey};}
  });
}
/** No read-only receipt lookup exists. An explicit same-key retry may record a previously uncommitted review. */
export async function retryMomoConflict(context: MomoConflictContext, pending: MomoConflictPending): Promise<MomoConflictResult> {
  write(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original conflict review intent is unavailable.');
  return withFence(context, async (access) => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original conflict review could not be verified.');
    const intent = verifyAttempt(stored.attempt, context), owner = await ownerBinding.read(context, stored.requestKey), fresh = await freshDetail(context);
    if (owner.kind !== 'valid' || await sourceDigest(fresh) !== owner.sourceSha256 || JSON.stringify(momoConflictSources(fresh).ids) !== JSON.stringify([...intent.expected_conflicting_attempt_ids].sort())) fail('The original conflict sources could not be verified.');
    write(context);
    if (!await context.verifyFresh()) fail('Complete current verification before retrying the conflict review.');
    write(context);
    try {
      const response = await context.request(`momo/transactions/${context.detail.transaction.id}/review-conflict`, {method: 'POST', body: {...intent}, idempotencyKey: stored.requestKey});
      current(context); const saved = receipt(response, context, intent); await clear(context, access, stored); return {status: 'succeeded', receipt: saved};
    } catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
