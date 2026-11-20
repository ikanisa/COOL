/* eslint-disable no-control-regex -- Reject prohibited control characters in the review reason. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import { clearPending, readPending, retainPending, type PendingAttempt, type PendingIdentity } from '../core';
import { withPendingFence, type FenceAccess, type FenceLock } from './pendingFence';
import { parseMomoDetail, type MomoDetail } from './momoContracts';

const FAMILY = 'momo-assign', PERMISSION = 'payments.write', BINDING_PREFIX = 'collect.admin.momo-assign.owner.v1:';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const id = z.string().regex(UUID);
const safeInt = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const text = z.string().min(1).max(2000).refine((value) => value.trim().length > 0 && !/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value));
const candidateSchema = z.object({group_id: id, group_name: text, member_id: id, member_name: text, member_public_id: z.string().regex(/^[0-9]{6}$/)}).strict();
export type MomoCandidate = z.infer<typeof candidateSchema>;
export interface MomoCandidatesPage {rows: MomoCandidate[]; total: number; offset: number; limit: 25;}
export function parseMomoCandidates(value: unknown, offset: number): MomoCandidatesPage {
  const data = z.object({rows: z.array(candidateSchema).max(25), total: safeInt, offset: safeInt.max(2147483647), limit: z.literal(25)}).strict().parse(value);
  if (data.offset !== offset || data.rows.length !== Math.max(0, Math.min(25, data.total - offset)) || new Set(data.rows.map((row) => `${row.group_id}:${row.member_id}`)).size !== data.rows.length) throw new Error('Eligible destinations could not be verified.');
  return data;
}
export interface MomoAssignmentContext {
  request: AdminRequest; identity: PendingIdentity; principalId: string; financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; detail: MomoDetail;
  /** Must remain false until cross-version coordination and backend recovery are qualified. */
  enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean; verifyFresh: () => Promise<boolean>;
  storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;
}
export interface MomoAssignmentIntent {group_id: string; member_id: string; expected_version: number; reason: string;}
export interface MomoAssignmentReceipt {transactionId: string; paymentId: string; status: 'awaiting_review' | 'linked_existing'; version: number; requiresIndependentReview: boolean;}
export type MomoAssignmentPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type MomoAssignmentResult = {status: 'succeeded'; receipt: MomoAssignmentReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: MomoAssignmentPending};
function fail(message: string): never {throw new Error(message);}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));}
function current(context: MomoAssignmentContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'canonical_evidence_ledger' || !UUID.test(context.principalId) ||
      !['payments.read', PERMISSION].every((permission) => context.identity.permissions.includes(permission)) ||
      !Number.isFinite(expires) || expires <= Date.now() || !UUID.test(context.detail.transaction.id)) fail('This assignment is unavailable to your current account.');
}
function requireDestinationAccess(context: MomoAssignmentContext) {
  if (!['users.read', 'collections.read'].every((permission) => context.identity.permissions.includes(permission))) fail('Eligible destinations are unavailable to your current account.');
}
function write(context: MomoAssignmentContext) {
  current(context);
  if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('This assignment is not enabled for the current workspace.');
}
export function parseMomoAssignmentIntent(input: unknown): MomoAssignmentIntent {
  if (!input || typeof input !== 'object' || Array.isArray(input)) fail('The original assignment could not be verified.');
  const body = input as Record<string, unknown>;
  if (!exact(body, ['group_id', 'member_id', 'expected_version', 'reason']) || typeof body.group_id !== 'string' || !UUID.test(body.group_id) || typeof body.member_id !== 'string' || !UUID.test(body.member_id) ||
      typeof body.expected_version !== 'number' || !Number.isSafeInteger(body.expected_version) || body.expected_version < 1 || body.expected_version >= Number.MAX_SAFE_INTEGER ||
      typeof body.reason !== 'string' || body.reason !== body.reason.trim() || body.reason.length < 8 || body.reason.length > 500 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(body.reason)) fail('The original assignment could not be verified.');
  return {group_id: body.group_id, member_id: body.member_id, expected_version: body.expected_version, reason: body.reason};
}
function verifyAttempt(attempt: PendingAttempt, context: MomoAssignmentContext) {
  if (attempt.family !== FAMILY || attempt.resource_id !== context.detail.transaction.id || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key)) fail('The original assignment could not be verified.');
  return parseMomoAssignmentIntent(attempt.intent);
}
function acceptedSource(detail: MomoDetail) {
  const accepted = detail.sources.filter((source) => source.relation === 'accepted' && source.outcome === 'accepted');
  if (accepted.length !== 1) fail('The accepted source evidence could not be verified.');
  return accepted[0];
}
export function hasAcceptedMomoSource(detail: MomoDetail): boolean {try {acceptedSource(detail); return true;} catch {return false;}}
export function canStartMomoAssignment(detail: MomoDetail): boolean {try {readyDetail(detail); return true;} catch {return false;}}
function readyDetail(detail: MomoDetail) {
  const tx = detail.transaction;
  if (tx.status !== 'needs_allocation' || tx.event_kind !== 'incoming_receipt' || tx.allocation_state !== 'unallocated' || tx.has_conflict !== 0 || tx.payment_id !== null || tx.version >= Number.MAX_SAFE_INTEGER) fail('The receipt is no longer available for assignment.');
  return acceptedSource(detail);
}
function receipt(value: unknown, context: MomoAssignmentContext, intent: MomoAssignmentIntent): MomoAssignmentReceipt {
  const body = z.object({transaction_id: id, payment_id: id, status: z.enum(['awaiting_review', 'linked_existing']), version: safeInt.min(2), requires_independent_review: z.boolean()}).strict().parse(value);
  if (body.transaction_id !== context.detail.transaction.id || body.version !== intent.expected_version + 1 || body.requires_independent_review !== (body.status === 'awaiting_review')) fail('The assignment response could not be verified.');
  return {transactionId: body.transaction_id, paymentId: body.payment_id, status: body.status, version: body.version, requiresIndependentReview: body.requires_independent_review};
}
async function principalDigest(context: MomoAssignmentContext): Promise<string> {
  if (!globalThis.crypto?.subtle) fail('The original assignment identity could not be verified.');
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`collect-momo-principal-v1:${context.principalId}`));
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
function bindingStorage(context: MomoAssignmentContext): Storage {
  try {return context.storage ?? sessionStorage;} catch {return fail('The original assignment identity could not be verified.');}
}
async function binding(context: MomoAssignmentContext, key: string): Promise<'valid' | 'missing' | 'foreign'> {
  const storage = bindingStorage(context), name = BINDING_PREFIX + context.detail.transaction.id;
  let raw: string | null;
  try {raw = storage.getItem(name);} catch {return fail('The original assignment identity could not be verified.');}
  if (raw === null) return 'missing';
  if (raw.length > 1000) fail('The original assignment identity could not be verified.');
  let value: unknown;
  try {value = JSON.parse(raw);} catch {return fail('The original assignment identity could not be verified.');}
  const schema = z.object({version: z.literal(1), request_key: z.string().regex(UUID), principal_sha256: z.string().regex(/^[a-f0-9]{64}$/)}).strict().parse(value);
  if (schema.request_key !== key) fail('The original assignment identity could not be verified.');
  return schema.principal_sha256 === await principalDigest(context) ? 'valid' : 'foreign';
}
async function saveBinding(context: MomoAssignmentContext, key: string) {
  const storage = bindingStorage(context), name = BINDING_PREFIX + context.detail.transaction.id;
  const existing = await binding(context, key);
  if (existing !== 'missing') fail('The original assignment identity could not be verified.');
  const raw = JSON.stringify({version: 1, request_key: key, principal_sha256: await principalDigest(context)});
  current(context);
  try {storage.setItem(name, raw); if (storage.getItem(name) !== raw) fail('The original assignment identity could not be verified.');}
  catch {fail('The original assignment identity could not be verified.');}
  current(context);
}
async function clearBinding(context: MomoAssignmentContext, key: string) {
  const state = await binding(context, key);
  if (state === 'foreign') fail('The original assignment identity could not be verified.');
  if (state === 'missing') return;
  const storage = bindingStorage(context), name = BINDING_PREFIX + context.detail.transaction.id;
  current(context);
  try {storage.removeItem(name); if (storage.getItem(name) !== null) fail('The original assignment identity could not be verified.');}
  catch {fail('The original assignment identity could not be verified.');}
}
async function withFence<T>(context: MomoAssignmentContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: FAMILY, resourceId: context.detail.transaction.id, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restoreUnderFence(context: MomoAssignmentContext, access: FenceAccess): Promise<MomoAssignmentPending> {
  current(context); const fence = access.read();
  if (fence.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, FAMILY, context.detail.transaction.id, context.storage);
  if (attempt) verifyAttempt(attempt, context);
  const owner = attempt ? await binding(context, attempt.request_key) : 'missing';
  current(context);
  if (owner === 'foreign') return {kind: 'foreign'};
  if (fence.kind === 'owned') {if (attempt && attempt.request_key !== fence.requestKey) fail('The original assignment could not be verified.'); return {kind: 'owned', requestKey: fence.requestKey, attempt: owner === 'valid' ? attempt : null};}
  if (attempt) {access.reserve(attempt.request_key, fence.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt: owner === 'valid' ? attempt : null};}
  return {kind: 'ready', revision: fence.revision};
}
export async function restoreMomoAssignment(context: MomoAssignmentContext): Promise<MomoAssignmentPending> {current(context); return withFence(context, (access) => restoreUnderFence(context, access));}
async function clear(context: MomoAssignmentContext, access: FenceAccess, pending: Extract<MomoAssignmentPending, {kind: 'owned'}>) {
  if (pending.attempt) {await clearBinding(context, pending.requestKey); await clearPending(context.identity, FAMILY, context.detail.transaction.id, pending.requestKey, context.storage);}
  current(context); access.clear(pending.requestKey);
}
function sameSource(a: MomoDetail, b: MomoDetail) {
  const before = readyDetail(a), after = readyDetail(b), left = a.transaction, right = b.transaction;
  return before.raw_sms_id === after.raw_sms_id && before.parser_version === after.parser_version && before.created_at === after.created_at &&
    left.id === right.id && left.version === right.version && left.event_kind === right.event_kind && left.allocation_state === right.allocation_state && left.receiving_account_id === right.receiving_account_id && left.public_code === right.public_code &&
    left.provider_transaction_id === right.provider_transaction_id && left.amount_minor === right.amount_minor && left.currency === right.currency;
}
export async function loadMomoCandidates(context: MomoAssignmentContext, search: string, offset: number): Promise<MomoCandidatesPage> {
  current(context); requireDestinationAccess(context);
  if (search.length > 200 || /[\x00-\x1f\x7f]/.test(search) || !Number.isSafeInteger(offset) || offset < 0 || offset > 2147483647) fail('Choose a valid destination search.');
  const query = new URLSearchParams({search: search.trim(), limit: '25', offset: String(offset)});
  const page = parseMomoCandidates(await context.request(`momo/transactions/${context.detail.transaction.id}/candidates?${query}`), offset);
  current(context); return page;
}
async function revalidateNew(context: MomoAssignmentContext, candidate: MomoCandidate) {
  const parsed = candidateSchema.parse(candidate), fresh = parseMomoDetail(await context.request(`momo/transactions/${context.detail.transaction.id}`), context.detail.transaction.id);
  current(context);
  if (!sameSource(context.detail, fresh)) fail('The receipt or accepted source changed. Review it again.');
  const page = await loadMomoCandidates(context, parsed.member_public_id, 0);
  const matches = page.rows.filter((row) => row.group_id === parsed.group_id && row.member_id === parsed.member_id);
  if (matches.length !== 1 || JSON.stringify(matches[0]) !== JSON.stringify(parsed)) fail('The destination changed. Review it again.');
}
export async function submitMomoAssignment(context: MomoAssignmentContext, candidate: MomoCandidate, reason: string, observedRevision: string): Promise<MomoAssignmentResult> {
  write(context); requireDestinationAccess(context); readyDetail(context.detail);
  const intent = parseMomoAssignmentIntent({group_id: candidate.group_id, member_id: candidate.member_id, expected_version: context.detail.transaction.version, reason: reason.trim()});
  return withFence(context, async (access) => {
    const existing = await restoreUnderFence(context, access);
    if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    await revalidateNew(context, candidate); write(context);
    if (!await context.verifyFresh()) fail('Complete current verification before assigning this receipt.');
    write(context);
    const requestKey = (context.createKey ?? (() => crypto.randomUUID()))();
    if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision);
    let attempt: PendingAttempt;
    try {
      attempt = await retainPending(context.identity, FAMILY, context.detail.transaction.id, requestKey, PERMISSION, {...intent}, context.storage);
      verifyAttempt(attempt, context);
      await saveBinding(context, requestKey);
    } catch (error) {
      if (context.isCurrent()) {
        try {
          const retained = await readPending(context.identity, FAMILY, context.detail.transaction.id, context.storage);
          if (retained?.request_key === requestKey) await clearPending(context.identity, FAMILY, context.detail.transaction.id, requestKey, context.storage);
          await clearBinding(context, requestKey); access.clear(requestKey);
        } catch { /* Preserve the fence when cleanup cannot be verified. */ }
      }
      throw error;
    }
    const pending: Extract<MomoAssignmentPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey};
    try {
      const response = await context.request(`momo/transactions/${context.detail.transaction.id}/assign`, {method: 'POST', body: {...intent}, idempotencyKey: requestKey});
      current(context); const saved = receipt(response, context, intent); await clear(context, access, pending); return {status: 'succeeded', receipt: saved};
    } catch {return {status: 'unknown', requestKey};}
  });
}
/** The backend has no read-only MoMo receipt lookup. Retry is explicit and may record an uncommitted assignment. */
export async function retryMomoAssignment(context: MomoAssignmentContext, pending: MomoAssignmentPending): Promise<MomoAssignmentResult> {
  write(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original assignment intent is unavailable.');
  acceptedSource(context.detail);
  return withFence(context, async (access) => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original assignment could not be verified.');
    const intent = verifyAttempt(stored.attempt, context);
    if (!await context.verifyFresh()) fail('Complete current verification before retrying this assignment.');
    write(context);
    try {
      const response = await context.request(`momo/transactions/${context.detail.transaction.id}/assign`, {method: 'POST', body: {...intent}, idempotencyKey: stored.requestKey});
      current(context); const saved = receipt(response, context, intent); await clear(context, access, stored); return {status: 'succeeded', receipt: saved};
    } catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
