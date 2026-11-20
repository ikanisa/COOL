/* eslint-disable no-control-regex -- Reject prohibited control characters in operator evidence. */
import {z} from 'zod';
import type {AdminRequest} from '../../api/client';
import {clearPending, readPending, retainPending, type PendingAttempt, type PendingIdentity} from '../core';
import {sha256Text} from '../core/pendingAttempt';
import {withPendingFence, type FenceAccess, type FenceLock} from './pendingFence';
import type {MomoSourceJob} from './momoContracts';

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const id = z.string().regex(UUID), bounded = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const rawKeys = ['transaction_id_raw', 'original_transaction_id_raw', 'transaction_datetime_raw', 'principal_amount_raw', 'currency_raw', 'payer_name_raw', 'payer_identifier_raw', 'payment_reference_raw', 'fee_amount_raw', 'wallet_balance_after_raw'] as const;
const evidenceKeys = ['incoming_success', 'principal', 'transaction_id', 'transaction_datetime', 'payer', 'fee', 'wallet_balance_after'] as const;
const field = z.string().min(1).max(500).refine((value) => !/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value)).nullable();
const reason = z.string().min(8).max(500).refine((value) => value === value.trim() && !/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value));
const extraction = z.object({schema_version: z.literal('momo-extraction.v1'), event_kind: z.enum(['incoming_receipt', 'reversal', 'outgoing', 'failed', 'pending', 'other', 'unknown']),
  payment_outcome: z.enum(['successful', 'failed', 'pending', 'unknown']),
  ...Object.fromEntries(rawKeys.map((key) => [key, field])) as Record<typeof rawKeys[number], typeof field>,
  evidence: z.object(Object.fromEntries(evidenceKeys.map((key) => [key, field])) as Record<typeof evidenceKeys[number], typeof field>).strict(), issues: z.array(z.never()).max(0)}).strict();
const review = z.object({expected_state: z.enum(['needs_review', 'completed']), expected_attempt_count: bounded, expected_body_sha256: z.string().regex(HASH), extraction, evidence_reference: reason, reason}).strict();
const classification = review.extend({classification_evidence: z.string().min(1).max(500).refine((value) => value.trim().length > 0 && !/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value))}).strict();
const resolution = z.object({receiving_account_id: id, evidence_reference: reason, reason}).strict();
const reparse = z.object({expected_state: z.enum(['needs_review', 'completed']), expected_attempt_count: bounded.max(Number.MAX_SAFE_INTEGER - 4),
  expected_body_sha256: z.string().regex(HASH), expected_receiving_account_id: id, reason}).strict();
const reviewReceipt = z.object({raw_sms_id: id, parse_attempt_id: id, status: z.literal('review_recorded'), financial_effects: z.literal(0)}).strict();
const resolutionReceipt = z.object({raw_sms_id: id, receiving_account_id: id, status: z.literal('pending'), mode: z.literal('historical'), financial_effects: z.literal(0)}).strict();
const reparseReceipt = z.object({raw_sms_id: id, status: z.literal('pending')}).strict();
const receivingAccount = z.object({id, provider: z.enum(['mtn_momo', 'airtel_money']), public_code: z.string().min(1).max(32), recipient_name: z.string().min(1).max(160), status: z.enum(['active', 'suspended'])});

export type MomoSourceActionKind = 'correct' | 'non-payment' | 'resolve' | 'reparse';
export type MomoExtraction = z.infer<typeof extraction>;
export type MomoSourceIntent = z.infer<typeof review> | z.infer<typeof classification> | z.infer<typeof resolution> | z.infer<typeof reparse>;
export type MomoReceivingAccount = z.infer<typeof receivingAccount>;
export interface MomoSourceActionContext {
  request: AdminRequest; identity: PendingIdentity; principalId: string; financialModel: 'transaction_journals' | 'canonical_evidence_ledger';
  sourceId: string; kind: MomoSourceActionKind; source?: MomoSourceJob;
  /** Enable only after the target backend and old-client recovery have been qualified. */
  enabled: boolean; isEnabled?: () => boolean; isCurrent: () => boolean; verifyFresh: () => Promise<boolean>;
  storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;
}
export type MomoSourcePending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type MomoSourceResult = {status: 'succeeded'} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: MomoSourcePending};
export const momoSourceFamily = (kind: MomoSourceActionKind) => kind === 'resolve' ? 'momo-source-resolve' : kind === 'reparse' ? 'momo-reparse-v2' : `momo-review-${kind}`;
const family = momoSourceFamily;
const endpoint = (kind: MomoSourceActionKind) => kind === 'resolve' ? 'resolve' : kind === 'correct' ? 'correct-extraction' : kind === 'reparse' ? 'reparse' : 'classify-non-payment';
const bindingName = (context: MomoSourceActionContext) => `collect.admin.momo-source.owner.v1:${context.kind}:${context.sourceId}`;
function fail(message: string): never {throw new Error(message);}
function current(context: MomoSourceActionContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'canonical_evidence_ledger' || !UUID.test(context.principalId) || !UUID.test(context.sourceId) ||
      !['sms.read', 'sms.extract', ...(context.kind === 'resolve' ? ['receivers.read'] : [])].every((permission) => context.identity.permissions.includes(permission)) ||
      !Number.isFinite(expires) || expires <= Date.now()) fail('Source review is unavailable to your current account.');
}
function write(context: MomoSourceActionContext) {current(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Source review is not enabled for this workspace.');}
function sourceEligible(context: MomoSourceActionContext) {
  const source = context.source;
  if (!source || source.raw_sms_id !== context.sourceId || !source.body_sha256 || !HASH.test(source.body_sha256)) fail('The original source details could not be verified.');
  if (context.kind === 'resolve') {
    if (source.state !== 'source_unresolved' || source.binding_id !== null || source.receiving_account_id !== null) fail('The historical source is no longer available for resolution.');
  } else if (!['needs_review', 'completed'].includes(source.state) || !source.receiving_account_id || typeof source.attempt_count !== 'number' || !Number.isSafeInteger(source.attempt_count) || source.attempt_count < 0 ||
      (context.kind === 'reparse' ? source.attempt_count > Number.MAX_SAFE_INTEGER - 4 : !Object.hasOwn(source, 'latest_attempt_outcome') || ['accepted', 'duplicate'].includes(source.latest_attempt_outcome ?? ''))) fail('The source is no longer available for this review.');
  return source;
}
export function canReviewMomoSource(source: MomoSourceJob, kind: MomoSourceActionKind): boolean {
  const context = {source, sourceId: source.raw_sms_id, kind} as MomoSourceActionContext;
  try {sourceEligible(context); return true;} catch {return false;}
}
export function parseMomoSourceIntent(kind: MomoSourceActionKind, input: unknown): MomoSourceIntent {
  if (kind === 'resolve') return resolution.parse(input);
  if (kind === 'reparse') return reparse.parse(input);
  if (kind === 'correct') {
    const data = review.parse(input), value = data.extraction;
    if (value.event_kind !== 'incoming_receipt' || value.payment_outcome !== 'successful' || !value.transaction_id_raw || !value.principal_amount_raw || !value.currency_raw || !value.evidence.incoming_success || !value.evidence.principal || !value.evidence.transaction_id) fail('The corrected source fields are incomplete.');
    return data;
  }
  const data = classification.parse(input), value = data.extraction;
  if (!['outgoing', 'failed', 'pending'].includes(value.event_kind) || value.payment_outcome !== (value.event_kind === 'outgoing' ? 'successful' : value.event_kind) ||
      value.evidence.incoming_success !== data.classification_evidence || rawKeys.some((key) => value[key] !== null) || evidenceKeys.some((key) => key !== 'incoming_success' && value.evidence[key] !== null)) fail('The non-payment evidence could not be verified.');
  return data;
}
export function nonPaymentExtraction(kind: 'outgoing' | 'failed' | 'pending', excerpt: string): MomoExtraction {
  return extraction.parse({schema_version: 'momo-extraction.v1', event_kind: kind, payment_outcome: kind === 'outgoing' ? 'successful' : kind,
    ...Object.fromEntries(rawKeys.map((key) => [key, null])), evidence: {...Object.fromEntries(evidenceKeys.map((key) => [key, null])), incoming_success: excerpt}, issues: []});
}
/** Suggestions remain untrusted evidence and are never submitted without review. */
export function parseMomoSourceCandidate(value: unknown): MomoExtraction | null {
  if (typeof value !== 'string' || value.length > 32768) return null;
  let parsed: unknown; try {parsed = JSON.parse(value);} catch {return null;}
  const result = extraction.extend({issues: z.array(z.string().max(160)).max(20)}).safeParse(parsed);
  if (!result.success || result.data.event_kind !== 'incoming_receipt' || result.data.payment_outcome !== 'successful') return null;
  return {...result.data, issues: []};
}
export async function loadMomoReceivingAccounts(context: MomoSourceActionContext): Promise<MomoReceivingAccount[]> {
  current(context); if (context.kind !== 'resolve') fail('Receiving accounts are unavailable.');
  const body = await context.request('momo/accounts'); current(context);
  const data = z.object({rows: z.array(receivingAccount).max(1000)}).parse(body);
  if (new Set(data.rows.map((account) => account.id)).size !== data.rows.length) fail('Receiving accounts could not be verified.');
  return data.rows.filter((account) => account.status === 'active');
}
class CurrentStorage implements Storage {
  constructor(private readonly base: Storage, private readonly context: MomoSourceActionContext) {}
  get length() {return 0;} clear(): void {throw new Error('Unsupported recovery operation.');} key(): string | null {return null;}
  getItem(key: string): string | null {current(this.context); return this.base.getItem(key);}
  setItem(key: string, value: string): void {current(this.context); this.base.setItem(key, value);}
  removeItem(key: string): void {current(this.context); this.base.removeItem(key);}
}
function storage(context: MomoSourceActionContext): Storage {return new CurrentStorage(context.storage ?? sessionStorage, context);}
async function principalHash(context: MomoSourceActionContext) {const value = await sha256Text(`collect-momo-principal-v1:${context.principalId}`); current(context); return value;}
async function binding(context: MomoSourceActionContext, key: string): Promise<{kind: 'valid'; sourceHash: string} | {kind: 'missing' | 'foreign'}> {
  const saved = storage(context).getItem(bindingName(context)); if (saved === null) return {kind: 'missing'};
  if (saved.length > 1000) fail('The original source request could not be verified.');
  let value: unknown; try {value = JSON.parse(saved);} catch {return fail('The original source request could not be verified.');}
  const data = z.object({version: z.literal(1), request_key: id, principal_sha256: z.string().regex(HASH), source_sha256: z.string().regex(HASH)}).strict().parse(value);
  if (data.request_key !== key) fail('The original source request could not be verified.');
  return data.principal_sha256 === await principalHash(context) ? {kind: 'valid', sourceHash: data.source_sha256} : {kind: 'foreign'};
}
async function saveBinding(context: MomoSourceActionContext, key: string, sourceHash: string) {
  if ((await binding(context, key)).kind !== 'missing') fail('The original source request could not be verified.');
  const s = storage(context), text = JSON.stringify({version: 1, request_key: key, principal_sha256: await principalHash(context), source_sha256: sourceHash});
  s.setItem(bindingName(context), text); if (s.getItem(bindingName(context)) !== text) fail('The original source request could not be verified.');
}
async function clearBinding(context: MomoSourceActionContext, key: string) {
  const result = await binding(context, key); if (result.kind === 'foreign') fail('The original source request could not be verified.');
  if (result.kind === 'valid') {const s = storage(context); s.removeItem(bindingName(context)); if (s.getItem(bindingName(context)) !== null) fail('The original source request could not be verified.');}
}
function validateAttempt(context: MomoSourceActionContext, attempt: PendingAttempt): MomoSourceIntent {
  if (attempt.family !== family(context.kind) || attempt.resource_id !== context.sourceId || attempt.permission !== 'sms.extract' || !UUID.test(attempt.request_key)) fail('The original source request could not be verified.');
  return parseMomoSourceIntent(context.kind, attempt.intent);
}
async function fence<T>(context: MomoSourceActionContext, work: (access: FenceAccess) => Promise<T>) {
  return withPendingFence({identity: context.identity, family: family(context.kind), resourceId: context.sourceId, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restore(context: MomoSourceActionContext, access: FenceAccess): Promise<MomoSourcePending> {
  current(context); const state = access.read(); if (state.kind === 'foreign') return {kind: 'foreign'};
  // Older Admins cannot parse the guarded intent and remove unknown fields on
  // restore. Keep a separate family and stop if an old request is unresolved.
  if (context.kind === 'reparse') {
    const legacy = await readPending(context.identity, 'momo-reparse', context.sourceId, storage(context));
    if (legacy) return {kind: 'owned', requestKey: legacy.request_key, attempt: null};
  }
  const attempt = await readPending(context.identity, family(context.kind), context.sourceId, storage(context)), intent = attempt ? validateAttempt(context, attempt) : null;
  const owner = attempt ? await binding(context, attempt.request_key) : {kind: 'missing' as const}; current(context);
  if (owner.kind === 'foreign') return {kind: 'foreign'};
  if (owner.kind === 'valid' && intent && context.kind !== 'resolve' && (intent as z.infer<typeof review>).expected_body_sha256 !== owner.sourceHash) fail('The original source request could not be verified.');
  if (state.kind === 'owned') {if (attempt && attempt.request_key !== state.requestKey) fail('The original source request could not be verified.'); return {kind: 'owned', requestKey: state.requestKey, attempt: owner.kind === 'valid' ? attempt : null};}
  if (attempt) {access.reserve(attempt.request_key, state.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt: owner.kind === 'valid' ? attempt : null};}
  return {kind: 'ready', revision: state.revision};
}
export async function restoreMomoSource(context: MomoSourceActionContext): Promise<MomoSourcePending> {current(context); return fence(context, (access) => restore(context, access));}
async function clear(context: MomoSourceActionContext, access: FenceAccess, saved: Extract<MomoSourcePending, {kind: 'owned'}>) {
  if (saved.attempt) {await clearBinding(context, saved.requestKey); await clearPending(context.identity, family(context.kind), context.sourceId, saved.requestKey, storage(context));}
  current(context); access.clear(saved.requestKey);
}
function validateReceipt(context: MomoSourceActionContext, intent: MomoSourceIntent, body: unknown) {
  if (context.kind === 'resolve') {
    const result = resolutionReceipt.parse(body), expected = resolution.parse(intent);
    if (result.raw_sms_id !== context.sourceId || result.receiving_account_id !== expected.receiving_account_id) fail('The source resolution receipt could not be verified.');
  } else if (context.kind === 'reparse') {
    if (reparseReceipt.parse(body).raw_sms_id !== context.sourceId) fail('The source reparse receipt could not be verified.');
  } else if (reviewReceipt.parse(body).raw_sms_id !== context.sourceId) fail('The source review receipt could not be verified.');
}
async function dispatch(context: MomoSourceActionContext, access: FenceAccess, saved: Extract<MomoSourcePending, {kind: 'owned'}>): Promise<MomoSourceResult> {
  if (!saved.attempt) fail('The original source request is unavailable.');
  const intent = validateAttempt(context, saved.attempt);
  try {
    const result = await context.request(`momo/sources/${context.sourceId}/${endpoint(context.kind)}`, {method: 'POST', body: {...intent}, idempotencyKey: saved.requestKey});
    current(context); validateReceipt(context, intent, result); await clear(context, access, saved); return {status: 'succeeded'};
  } catch {return {status: 'unknown', requestKey: saved.requestKey};}
}
export async function submitMomoSource(context: MomoSourceActionContext, input: unknown, observedRevision: string): Promise<MomoSourceResult> {
  write(context); const source = sourceEligible(context), intent = parseMomoSourceIntent(context.kind, input);
  if (context.kind !== 'resolve') {
    const reviewIntent = context.kind === 'non-payment' ? classification.parse(intent) : context.kind === 'reparse' ? reparse.parse(intent) : review.parse(intent);
    if (reviewIntent.expected_state !== source.state || reviewIntent.expected_attempt_count !== source.attempt_count || reviewIntent.expected_body_sha256 !== source.body_sha256 ||
        context.kind === 'reparse' && reparse.parse(intent).expected_receiving_account_id !== source.receiving_account_id) fail('The reviewed source details changed.');
  } else {
    const accountId = resolution.parse(intent).receiving_account_id, accounts = await loadMomoReceivingAccounts(context);
    if (!accounts.some((account) => account.id === accountId)) fail('The receiving account is no longer available.');
  }
  return fence(context, async (access) => {
    const existing = await restore(context, access); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    write(context); if (!await context.verifyFresh()) fail('Complete current verification before reviewing this source.'); write(context);
    const key = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(key)) fail('A secure request reference is unavailable.');
    access.reserve(key, observedRevision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, family(context.kind), context.sourceId, key, 'sms.extract', {...intent}, storage(context)); validateAttempt(context, attempt); await saveBinding(context, key, source.body_sha256!);}
    catch (error) {
      if (context.isCurrent()) {try {const saved = await readPending(context.identity, family(context.kind), context.sourceId, storage(context)); if (saved?.request_key === key) await clearPending(context.identity, family(context.kind), context.sourceId, key, storage(context)); await clearBinding(context, key); access.clear(key);} catch { /* Keep the fence if cleanup could not be confirmed. */ }}
      throw error;
    }
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey: key};
    return dispatch(context, access, {kind: 'owned', requestKey: key, attempt});
  });
}
/** This is a write, not a status lookup; it may execute a previously uncommitted action. */
export async function retryMomoSource(context: MomoSourceActionContext, pending: MomoSourcePending): Promise<MomoSourceResult> {
  write(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original source request is unavailable.');
  return fence(context, async (access) => {
    const saved = await restore(context, access);
    if (saved.kind !== 'owned' || !saved.attempt || saved.requestKey !== pending.requestKey || JSON.stringify(saved.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original source request could not be verified.');
    write(context); if (!await context.verifyFresh()) fail('Complete current verification before retrying this source request.'); write(context);
    return dispatch(context, access, saved);
  });
}
