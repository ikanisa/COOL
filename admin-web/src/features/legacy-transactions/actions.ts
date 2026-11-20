/* eslint-disable no-control-regex -- Validate recorded evidence before display or retention. */
import {z} from 'zod';
import type {AdminRequest} from '../../api/client';
import {clearPending, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity} from '../core/pendingAttempt';
import {withPendingFence, type FenceAccess, type FenceLock} from '../operations/pendingFence';

const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const CONTROL = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/;
const identifier = z.string().regex(UUID);
const version = z.number().int().min(1).max(Number.MAX_SAFE_INTEGER - 1);
const text = (min: number, max: number) => z.string().min(min).max(max).refine(value => value === value.trim() && !CONTROL.test(value));
const evidenceKind = z.enum(['operator_observation', 'payer_receipt', 'receiver_statement', 'provider_statement']);
const evidence = z.object({kind: evidenceKind, reference: text(8, 500), sha256: z.string().regex(/^[a-f0-9]{64}$/)}).strict();
const addIntent = z.object({expected_version: version, evidence, reason: text(8, 1000)}).strict();
const reviewIntent = z.object({expected_version: version, evidence_id: identifier, outcome: z.enum(['confirmation_recorded', 'rejection_recorded', 'evidence_conflict']), reason: text(8, 1000)}).strict();
const hash = z.string().regex(/^[a-f0-9]{64}$/);
const retainedAdd = z.object({expected_version: version, evidence_kind: evidenceKind, evidence_sha256: hash, request_sha256: hash}).strict();
const retainedReview = z.object({expected_version: version, evidence_id: identifier, outcome: reviewIntent.shape.outcome, request_sha256: hash}).strict();
const evidenceRow = z.object({id: identifier, kind: evidenceKind, reference: text(8, 500), sha256: z.string().regex(/^[a-f0-9]{64}$/), recorded_by_admin_id: identifier, recorded_at: z.number().int().positive().safe()}).strict();
const journalRow = z.object({id: identifier, status: z.enum(['draft', 'posted']), version: z.number().int().positive().safe()}).passthrough();
const receiptSchema = z.object({request_id: identifier, resource_type: z.literal('transactions'), resource_id: identifier, version: z.number().int().min(2).safe(), status: z.literal('succeeded')}).strict();

export type LegacyTransactionMode = 'add' | 'review';
export type LegacyEvidence = z.infer<typeof evidenceRow>;
export type LegacyIntent = z.infer<typeof addIntent> | z.infer<typeof reviewIntent>;
export interface LegacyTransactionSnapshot {
  id: string; groupId: string; payeeId: string; network: string; receiver: string; reference: string; amount: number;
  observedAt: number; status: string; version: number; recordedBy: string | null; referenceSourceFactId: string | null; evidence: LegacyEvidence[]; posted: boolean;
}
export interface LegacyTransactionContext {
  id: string; mode: LegacyTransactionMode; request: AdminRequest; identity: PendingIdentity; permissions: readonly string[];
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean;
  storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;
}
export type LegacyPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type LegacyResult = {status: 'succeeded'; receipt: z.infer<typeof receiptSchema>} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LegacyPending};
export type LegacyLookup = {status: 'succeeded'; receipt: z.infer<typeof receiptSchema>} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
const family = (mode: LegacyTransactionMode) => mode === 'add' ? 'legacy-guarded-add-evidence' : 'legacy-guarded-review-evidence';
const previousFamily = (mode: LegacyTransactionMode) => mode === 'add' ? 'operating-addevidence' : 'operating-verifytransaction';
const operation = (mode: LegacyTransactionMode) => mode === 'add' ? 'evidence' : 'verification';
const otherMode = (mode: LegacyTransactionMode): LegacyTransactionMode => mode === 'add' ? 'review' : 'add';
function fail(message = 'The original transaction request could not be verified.'): never {throw new Error(message);}
function obj(value: unknown): value is Record<string, unknown> {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function exact(value: Record<string, unknown>, keys: readonly string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function check(context: LegacyTransactionContext) {
  if (!context.isCurrent() || !UUID.test(context.id) || !UUID.test(context.identity.id) || context.financialModel !== 'transaction_journals' || context.identity.role === 'staff' ||
      !['payments.read', 'payments.manage', 'overview.read'].every(value => context.permissions.includes(value) && context.identity.permissions.includes(value)) ||
      !Number.isFinite(Date.parse(context.identity.expiresAt)) || Date.parse(context.identity.expiresAt) <= Date.now()) fail('This transaction action is unavailable.');
}
function write(context: LegacyTransactionContext) {check(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('This transaction action is not enabled.');}
export function parseLegacyIntent(mode: LegacyTransactionMode, value: unknown): LegacyIntent {return mode === 'add' ? addIntent.parse(value) : reviewIntent.parse(value);}
function attempt(context: LegacyTransactionContext, value: PendingAttempt, mode = context.mode) {
  if (value.family !== family(mode) || value.resource_id !== context.id || value.permission !== 'payments.manage' || !UUID.test(value.request_key)) fail();
  return mode === 'add' ? retainedAdd.parse(value.intent) : retainedReview.parse(value.intent);
}
async function retainedIntent(mode: LegacyTransactionMode, input: unknown) {
  const body = parseLegacyIntent(mode, input), request_sha256 = await sha256Text(JSON.stringify(body));
  return mode === 'add' ? {expected_version: body.expected_version, evidence_kind: addIntent.parse(body).evidence.kind, evidence_sha256: addIntent.parse(body).evidence.sha256, request_sha256}
    : {expected_version: body.expected_version, evidence_id: reviewIntent.parse(body).evidence_id, outcome: reviewIntent.parse(body).outcome, request_sha256};
}
export async function verifyLegacyReentry(context: LegacyTransactionContext, saved: PendingAttempt, input: unknown): Promise<LegacyIntent> {
  const expected = attempt(context, saved), body = parseLegacyIntent(context.mode, input), actual = await retainedIntent(context.mode, body); check(context);
  if (JSON.stringify(expected) !== JSON.stringify(actual)) fail('The re-entered request does not match the original.'); return body;
}
export async function readPreviousTransaction(context: LegacyTransactionContext, mode = context.mode): Promise<PendingAttempt | null> {
  check(context); const saved = await readPending(context.identity, previousFamily(mode), context.id, context.storage); check(context);
  if (saved && (saved.permission !== 'payments.manage' || !UUID.test(saved.request_key))) fail(); return saved;
}
async function requireNoPrevious(context: LegacyTransactionContext) {
  if (await readPreviousTransaction(context) || await readPreviousTransaction(context, otherMode(context.mode))) fail('An earlier transaction request needs recovery.');
}
function rowIdentity(value: unknown, context: LegacyTransactionContext) {
  if (!obj(value) || value.id !== context.id || !UUID.test(String(value.group_id)) || !UUID.test(String(value.payee_id)) ||
      !['mtn_momo', 'airtel_money'].includes(String(value.network)) || typeof value.payee_momo_number_or_code !== 'string' || !/^[0-9]{4,12}$/.test(value.payee_momo_number_or_code) ||
      typeof value.provider_reference !== 'string' || value.provider_reference.trim().length < 1 || value.provider_reference.length > 160 || CONTROL.test(value.provider_reference) ||
      !Number.isSafeInteger(value.amount_rwf) || Number(value.amount_rwf) < 1 || !Number.isSafeInteger(value.observed_at) || Number(value.observed_at) < 1 ||
      !['pending', 'confirmation_recorded', 'rejection_recorded', 'evidence_conflict'].includes(String(value.verification_status)) || !version.safeParse(value.version).success ||
      !(value.recorded_by_admin_id === null || typeof value.recorded_by_admin_id === 'string' && UUID.test(value.recorded_by_admin_id)) ||
      !(value.reference_source_fact_id === null || typeof value.reference_source_fact_id === 'string' && UUID.test(value.reference_source_fact_id)) ||
      value.currency !== 'RWF' || value.provider_confirmation !== false || value.settlement_status !== 'not_asserted') fail('The transaction could not be verified.');
  return {id: context.id, groupId: String(value.group_id), payeeId: String(value.payee_id), network: String(value.network), receiver: value.payee_momo_number_or_code,
    reference: value.provider_reference, amount: value.amount_rwf as number, observedAt: value.observed_at as number, status: String(value.verification_status), version: value.version as number, recordedBy: value.recorded_by_admin_id as string | null, referenceSourceFactId: value.reference_source_fact_id as string | null};
}
async function related(context: LegacyTransactionContext, relation: 'evidence' | 'journals') {
  let offset = 0, total: number | null = null, base: ReturnType<typeof rowIdentity> | null = null; const rows: Record<string, unknown>[] = [], ids = new Set<string>();
  while (true) {
    const body = await context.request(`operations/transactions/${context.id}?relation=${relation}&limit=100&offset=${offset}`); check(context);
    if (!exact(body, ['resource_type', 'resource', 'current_actor_id', 'can_manage', 'related', 'related_pages', 'related_truncated']) || body.resource_type !== 'transactions' || body.current_actor_id !== context.identity.id || body.can_manage !== true ||
        !obj(body.related) || !exact(body.related, [relation]) || !Array.isArray(body.related[relation]) || !obj(body.related_pages) || !exact(body.related_pages, [relation]) || !obj(body.related_pages[relation])) fail('The transaction could not be verified.');
    const current = rowIdentity(body.resource, context), page = body.related_pages[relation], values = body.related[relation];
    if (!Number.isSafeInteger(page.total) || Number(page.total) < 0 || Number(page.total) > 10000 || page.limit !== 100 || page.offset !== offset ||
        values.length !== Math.max(0, Math.min(100, Number(page.total) - offset)) || page.next_offset !== (offset + values.length < Number(page.total) ? offset + values.length : null) ||
        body.related_truncated !== (Number(page.total) > values.length) || total !== null && total !== page.total || base && JSON.stringify(base) !== JSON.stringify(current)) fail('The transaction evidence changed while loading.');
    base = current; total = page.total as number;
    for (const value of values) {if (!obj(value) || typeof value.id !== 'string' || ids.has(value.id)) fail('The transaction evidence could not be verified.'); ids.add(value.id); rows.push(value);}
    if (page.next_offset === null) break; offset = page.next_offset as number;
  }
  if (!base) fail('The transaction could not be verified.'); return {base, rows};
}
export async function loadLegacyTransaction(context: LegacyTransactionContext): Promise<LegacyTransactionSnapshot> {
  check(context); const data = await related(context, 'evidence'), rows = data.rows.map(row => evidenceRow.parse(row));
  let posted = false;
  if (context.mode === 'review') {
    const journals = await related(context, 'journals'); if (JSON.stringify(data.base) !== JSON.stringify(journals.base)) fail('The transaction changed while loading.');
    posted = journals.rows.map(row => journalRow.parse(row)).some(row => row.status === 'posted');
  }
  check(context); return {...data.base, evidence: rows, posted};
}
export function validateReview(context: LegacyTransactionContext, snapshot: LegacyTransactionSnapshot, input: unknown): LegacyIntent {
  const body = parseLegacyIntent(context.mode, input);
  if (snapshot.id !== context.id || snapshot.version !== body.expected_version) fail('The transaction changed.');
  if (context.mode === 'review') {
    const value = reviewIntent.parse(body), selected = snapshot.evidence.find(row => row.id === value.evidence_id);
    if (snapshot.posted || !selected || selected.recorded_by_admin_id === context.identity.id || value.outcome === 'confirmation_recorded' &&
        (snapshot.recordedBy === context.identity.id || !['receiver_statement', 'provider_statement'].includes(selected.kind))) fail('This evidence cannot be independently reviewed by your account.');
  }
  return body;
}
async function fence<T>(context: LegacyTransactionContext, mode: LegacyTransactionMode, work: (access: FenceAccess) => Promise<T>) {
  return withPendingFence({identity: context.identity, family: family(mode), resourceId: context.id, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock ?? browserLock}, work);
}
const browserLock: FenceLock = async (name, task) => {
  if (!navigator.locks) fail('Protected request recovery is unavailable.');
  // Queue the short shared-storage section; unrelated panels can restore at
  // once without causing a false recovery error. Never queue transaction work.
  const options: LockOptions = name === 'collect.admin.pending-fence.v2' ? {mode: 'exclusive'} : {mode: 'exclusive', ifAvailable: true};
  return navigator.locks.request(name, options, held => held ? task() : fail('Another transaction request is in progress.'));
};
async function scoped<T>(context: LegacyTransactionContext, work: () => Promise<T>): Promise<T> {
  const lock: FenceLock = context.lock ?? browserLock;
  return lock(`collect.admin.legacy-transaction:${context.id}`, async () => {check(context); return work();});
}
async function restoreUnder(context: LegacyTransactionContext, access: FenceAccess, mode: LegacyTransactionMode): Promise<LegacyPending> {
  check(context); const shared = access.read(); if (shared.kind === 'foreign') return {kind: 'foreign'};
  const saved = await readPending(context.identity, family(mode), context.id, context.storage); if (saved) attempt(context, saved, mode); check(context);
  if (shared.kind === 'owned') {if (saved && saved.request_key !== shared.requestKey) fail(); return {kind: 'owned', requestKey: shared.requestKey, attempt: saved};}
  if (saved) {access.reserve(saved.request_key, shared.revision); return {kind: 'owned', requestKey: saved.request_key, attempt: saved};}
  return {kind: 'ready', revision: shared.revision};
}
export async function restoreLegacyTransaction(context: LegacyTransactionContext, mode = context.mode) {check(context); return fence(context, mode, access => restoreUnder(context, access, mode));}
async function clearVerified(context: LegacyTransactionContext, pending: Extract<LegacyPending, {kind: 'owned'}>) {
  await fence(context, context.mode, async access => {
    const saved = await restoreUnder(context, access, context.mode);
    if (saved.kind !== 'owned' || !saved.attempt || !pending.attempt || saved.requestKey !== pending.requestKey || JSON.stringify(attempt(context, saved.attempt)) !== JSON.stringify(attempt(context, pending.attempt))) fail();
    await clearPending(context.identity, family(context.mode), context.id, saved.requestKey, context.storage); check(context); access.clear(saved.requestKey);
  });
}
function receipt(context: LegacyTransactionContext, input: unknown, saved: PendingAttempt | null) {
  if (!saved) fail('The original transaction intent is unavailable.');
  const value = receiptSchema.parse(input), original = attempt(context, saved);
  if (value.resource_id !== context.id || value.version !== original.expected_version + 1) fail(); return value;
}
async function verifyScope(context: LegacyTransactionContext, key: string, expected: z.infer<typeof receiptSchema>) {
  for (let offset = 0; offset < 10000; offset += 100) {
    const data = await context.request(`operations/requests?limit=100&offset=${offset}`); check(context);
    if (!exact(data, ['total', 'rows']) || !Number.isSafeInteger(data.total) || Number(data.total) < 0 || !Array.isArray(data.rows) || data.rows.length !== Math.max(0, Math.min(100, Number(data.total) - offset)) || data.rows.some(row => !obj(row))) fail();
    const row = data.rows.find(value => value.idempotency_key === key);
    if (row) {
      if (row.id !== expected.request_id || row.scope !== `transactions.post.${operation(context.mode)}` || row.status !== 'succeeded' || JSON.stringify(receiptSchema.parse(row.receipt)) !== JSON.stringify(expected)) fail();
      return;
    }
    if (offset + data.rows.length >= Number(data.total)) break;
  }
  fail('The original request is not in the bounded actor history.');
}
async function lookup(context: LegacyTransactionContext, pending: Extract<LegacyPending, {kind: 'owned'}>): Promise<LegacyLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) return {status: 'not_found', retryAvailable: !!pending.attempt};
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail();
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail(); const result = receipt(context, body.receipt, pending.attempt); if (result.request_id !== body.request_id) fail();
  await verifyScope(context, pending.requestKey, result); return {status: 'succeeded', receipt: result};
}
async function settle(context: LegacyTransactionContext, pending: Extract<LegacyPending, {kind: 'owned'}>, input: unknown): Promise<LegacyResult> {
  const direct = receipt(context, input, pending.attempt), found = await lookup(context, pending);
  if (found.status !== 'succeeded' || JSON.stringify(found.receipt) !== JSON.stringify(direct)) fail();
  await clearVerified(context, pending); return {status: 'succeeded', receipt: direct};
}
export async function checkLegacyTransaction(context: LegacyTransactionContext, pending: LegacyPending): Promise<LegacyLookup> {
  check(context); if (pending.kind !== 'owned') fail();
  return scoped(context, async () => {
    const saved = await restoreLegacyTransaction(context); if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey) fail();
    const result = await lookup(context, saved); if (result.status === 'succeeded') await clearVerified(context, saved); return result;
  });
}
/** Existing Flutter attempts are lookup-only; this component never replays or clears them. */
export async function checkPreviousTransaction(context: LegacyTransactionContext, saved: PendingAttempt): Promise<LegacyLookup> {
  check(context); const previous = await readPreviousTransaction(context);
  if (!previous || previous.request_key !== saved.request_key) fail();
  const original = parseLegacyIntent(context.mode, previous.intent), data = await context.request(`operations/requests/${previous.request_key}`); check(context);
  if (data.status === 'not_found' && exact(data, ['status'])) return {status: 'not_found', retryAvailable: false};
  if (!exact(data, ['status', 'request_id', 'receipt']) || typeof data.request_id !== 'string' || !UUID.test(data.request_id)) fail();
  if ((data.status === 'pending' || data.status === 'failed') && data.receipt === null) return {status: data.status};
  if (data.status !== 'succeeded') fail(); const result = receiptSchema.parse(data.receipt);
  if (result.request_id !== data.request_id || result.resource_id !== context.id || result.version !== original.expected_version + 1) fail();
  await verifyScope(context, previous.request_key, result); return {status: 'succeeded', receipt: result};
}
export async function submitLegacyTransaction(context: LegacyTransactionContext, input: unknown, reviewed: LegacyTransactionSnapshot, revision: string): Promise<LegacyResult> {
  write(context); const body = validateReview(context, reviewed, input);
  return scoped(context, async () => {
    await requireNoPrevious(context);
    const other = await restoreLegacyTransaction(context, otherMode(context.mode)); if (other.kind !== 'ready') fail('Another transaction request needs recovery.');
    const latest = await loadLegacyTransaction(context); if (JSON.stringify(latest) !== JSON.stringify(reviewed)) fail('The transaction changed.'); validateReview(context, latest, body); write(context);
    const retainedBody = await retainedIntent(context.mode, body); write(context);
    const checkpoint = await fence(context, context.mode, async access => {
      const saved = await restoreUnder(context, access, context.mode); if (saved.kind !== 'ready') return {kind: 'existing' as const, pending: saved};
      write(context); const key = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(key)) fail(); access.reserve(key, revision);
      let retained: PendingAttempt;
      try {retained = await retainPending(context.identity, family(context.mode), context.id, key, 'payments.manage', retainedBody, context.storage); attempt(context, retained);}
      catch (error) {if (context.isCurrent()) {try {const found = await readPending(context.identity, family(context.mode), context.id, context.storage); if (found?.request_key === key) await clearPending(context.identity, family(context.mode), context.id, key, context.storage); access.clear(key);} catch { /* Keep the shared fence if cleanup is uncertain. */ }} throw error;}
      return {kind: 'new' as const, pending: {kind: 'owned' as const, requestKey: key, attempt: retained}};
    });
    if (checkpoint.kind === 'existing') return {status: 'existing', pending: checkpoint.pending}; const pending = checkpoint.pending;
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey: pending.requestKey};
    try {const result = await context.request(`operations/transactions/${context.id}/${operation(context.mode)}`, {method: 'POST', body: {...body}, idempotencyKey: pending.requestKey}); check(context); return await settle(context, pending, result);}
    catch {return {status: 'unknown', requestKey: pending.requestKey};}
  });
}
export async function retryLegacyTransaction(context: LegacyTransactionContext, pending: LegacyPending, reviewed: LegacyTransactionSnapshot, input: unknown): Promise<LegacyResult> {
  write(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original transaction intent is unavailable.'); const original = attempt(context, pending.attempt);
  return scoped(context, async () => {
    const saved = await restoreLegacyTransaction(context); if (saved.kind !== 'owned' || !saved.attempt || saved.requestKey !== pending.requestKey || JSON.stringify(attempt(context, saved.attempt)) !== JSON.stringify(original)) fail();
    const prior = await lookup(context, saved); if (prior.status === 'succeeded') {await clearVerified(context, saved); return {status: 'succeeded', receipt: prior.receipt};}
    if (prior.status !== 'not_found') fail('The original transaction request is unresolved.');
    await requireNoPrevious(context); const body = await verifyLegacyReentry(context, saved.attempt, input);
    const other = await restoreLegacyTransaction(context, otherMode(context.mode)); if (other.kind !== 'ready') fail('Another transaction request needs recovery.');
    const latest = await loadLegacyTransaction(context); if (JSON.stringify(latest) !== JSON.stringify(reviewed)) fail('The transaction changed.'); validateReview(context, latest, body); write(context);
    try {const result = await context.request(`operations/transactions/${context.id}/${operation(context.mode)}`, {method: 'POST', body: {...body}, idempotencyKey: saved.requestKey}); check(context); return await settle(context, saved, result);}
    catch {return {status: 'unknown', requestKey: saved.requestKey};}
  });
}
