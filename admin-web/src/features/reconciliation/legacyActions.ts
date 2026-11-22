import {pendingAuthority, readPending, retainPending, sha256Text, type PendingAttempt} from '../core/pendingAttempt';
import {isId, isObject} from '../core/contracts';
import {withPendingFence, type FenceAccess} from '../operations/pendingFence';
import {clearOriginalReconciliationAttempt, sameReconciliationAttempt} from './custody';
import {
  checkLegacyDecision, currentLegacyDecision, exactLegacyFields, invalidLegacyDecision, legacyDecisionKind, legacyDecisionPermission,
  parseLegacyDecisionIntent, positiveLegacyCount, requireLegacyDecisionWrite,
  type LegacyDecisionContext, type LegacyDecisionIntent, type LegacyDecisionSource,
} from './legacyDecisionSource';

export {
  currentLegacyDecision, listLegacyProposals, makeLegacyProposal, makeLegacyReview, parseLegacyDecisionIntent,
  parseLegacyProposal, searchLegacyReconciliationMembers,
} from './legacyDecisionSource';
export type {
  LegacyDecisionContext, LegacyDecisionIntent, LegacyDecisionKind, LegacyDecisionSource, LegacyMember, LegacyPaymentIdentity, LegacyProposal,
} from './legacyDecisionSource';

// Flutter's older schema cannot deserialize the added source-state field. Keep
// guarded React intents in a distinct family while sharing the React fence.
const FENCE_FAMILY = 'reconciliation';
const FLUTTER_FAMILY = 'reconciliation';
const GUARDED_FAMILY = 'legacy-reconciliation-guarded';
const HASH = /^[a-f0-9]{64}$/;

export type LegacyDecisionPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export interface LegacyDecisionReceipt {requestId: string; proposalId: string; transactionId: string; status: 'pending' | 'approved' | 'rejected'; version: number;}
export type LegacyDecisionLookup = {status: 'succeeded'; receipt: LegacyDecisionReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
export type LegacyDecisionResult = {status: 'succeeded'; receipt: LegacyDecisionReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LegacyDecisionPending};

function storage(context: LegacyDecisionContext): Storage {try {return context.storage ?? sessionStorage;} catch {return invalidLegacyDecision('Recovery storage is unavailable.');}}
function bindingKey(context: LegacyDecisionContext) {return `collect.admin.legacy-reconciliation.context.v1:${context.transactionId}`;}
async function binding(context: LegacyDecisionContext, requestKey: string, attempt?: PendingAttempt): Promise<{kind: 'valid'; sourceHash: string; raw: string} | {kind: 'missing' | 'foreign' | 'mismatch'}> {
  let raw: string | null; try {raw = storage(context).getItem(bindingKey(context));} catch {return invalidLegacyDecision('Recovery storage is unavailable.');}
  if (raw === null) return {kind: 'missing'}; if (raw.length > 1000) invalidLegacyDecision(); let value: unknown; try {value = JSON.parse(raw);} catch {return invalidLegacyDecision();}
  if (!isObject(value) || !exactLegacyFields(value, ['version', 'request_key', 'authority_sha256', 'intent_sha256', 'source_sha256', 'model']) || value.version !== 1 || value.request_key !== requestKey || value.model !== 'transaction_journals' ||
      typeof value.authority_sha256 !== 'string' || !HASH.test(value.authority_sha256) || typeof value.intent_sha256 !== 'string' || !HASH.test(value.intent_sha256) || typeof value.source_sha256 !== 'string' || !HASH.test(value.source_sha256)) invalidLegacyDecision();
  if (value.authority_sha256 !== await pendingAuthority(context.identity)) return {kind: 'foreign'};
  if (attempt && value.intent_sha256 !== await sha256Text(JSON.stringify(attempt.intent))) return {kind: 'mismatch'};
  return {kind: 'valid', sourceHash: value.source_sha256, raw};
}
async function saveBinding(context: LegacyDecisionContext, attempt: PendingAttempt, source: LegacyDecisionSource) {
  if ((await binding(context, attempt.request_key)).kind !== 'missing') invalidLegacyDecision(); const store = storage(context), name = bindingKey(context);
  const raw = JSON.stringify({version: 1, request_key: attempt.request_key, authority_sha256: await pendingAuthority(context.identity), intent_sha256: await sha256Text(JSON.stringify(attempt.intent)), source_sha256: await sha256Text(JSON.stringify(source)), model: 'transaction_journals'}); checkLegacyDecision(context);
  try {store.setItem(name, raw); if (store.getItem(name) !== raw) invalidLegacyDecision();} catch {invalidLegacyDecision('Recovery storage is unavailable.');} checkLegacyDecision(context);
}
function removeBinding(context: LegacyDecisionContext, expected: string | null) {
  const store = storage(context), name = bindingKey(context);
  checkLegacyDecision(context);
  try {
    if (store.getItem(name) !== expected) invalidLegacyDecision();
    if (expected !== null) {
      store.removeItem(name);
      if (store.getItem(name) !== null) invalidLegacyDecision();
    }
  } catch {invalidLegacyDecision('Recovery storage is unavailable.');}
}
async function fence<T>(context: LegacyDecisionContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {return withPendingFence({identity: context.identity, family: FENCE_FAMILY, resourceId: context.transactionId, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);}
async function restoreUnderFence(context: LegacyDecisionContext, access: FenceAccess): Promise<LegacyDecisionPending> {
  checkLegacyDecision(context); const shared = access.read(); if (shared.kind === 'foreign') return {kind: 'foreign'};
  const guarded = await readPending(context.identity, GUARDED_FAMILY, context.transactionId, context.storage), flutter = await readPending(context.identity, FLUTTER_FAMILY, context.transactionId, context.storage);
  if (guarded && flutter) invalidLegacyDecision('Multiple original reconciliation requests need review.');
  const attempt = guarded ?? flutter;
  if (attempt && (![GUARDED_FAMILY, FLUTTER_FAMILY].includes(attempt.family) || attempt.resource_id !== context.transactionId || !isId(attempt.request_key) || !['reconciliations.propose', 'reconciliations.review'].includes(attempt.permission))) invalidLegacyDecision();
  const owner = attempt ? await binding(context, attempt.request_key, attempt) : {kind: 'missing' as const}; checkLegacyDecision(context);
  if (owner.kind === 'foreign') return {kind: 'foreign'};
  if (shared.kind === 'owned') {if (attempt && attempt.request_key !== shared.requestKey) invalidLegacyDecision(); return {kind: 'owned', requestKey: shared.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, shared.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};}
  return {kind: 'ready', revision: shared.revision};
}
export async function restoreLegacyDecision(context: LegacyDecisionContext): Promise<LegacyDecisionPending> {checkLegacyDecision(context); return fence(context, access => restoreUnderFence(context, access));}
async function clear(context: LegacyDecisionContext, access: FenceAccess, pending: Extract<LegacyDecisionPending, {kind: 'owned'}>) {
  const saved = await binding(context, pending.requestKey, pending.attempt ?? undefined);
  if (saved.kind !== 'valid' && saved.kind !== 'missing') invalidLegacyDecision();
  const expected = saved.kind === 'valid' ? saved.raw : null;
  const store = storage(context);
  const ownsOriginal = () => {
    checkLegacyDecision(context);
    const shared = access.read();
    return shared.kind === 'owned' && shared.requestKey === pending.requestKey &&
      store.getItem(bindingKey(context)) === expected;
  };
  if (pending.attempt) await clearOriginalReconciliationAttempt(context.identity, pending.attempt, ownsOriginal, store);
  if (!ownsOriginal()) invalidLegacyDecision();
  removeBinding(context, expected);
  access.clear(pending.requestKey);
}
function receipt(context: LegacyDecisionContext, value: unknown, attempt: PendingAttempt | null): LegacyDecisionReceipt {
  if (!isObject(value) || !isId(value.request_id) || value.status !== 'succeeded' || value.resource_type !== 'reconciliation_proposals' || !isId(value.resource_id) || value.transaction_id !== context.transactionId || !['pending', 'approved', 'rejected'].includes(String(value.proposal_status))) invalidLegacyDecision('The original reconciliation receipt could not be verified.');
  const reviewed = value.proposal_status !== 'pending', keys = ['request_id', 'status', 'resource_type', 'resource_id', 'transaction_id', 'version', 'proposal_status', ...(reviewed ? ['review_id', 'allocation_id', 'transaction_version', 'settlement_status'] : [])];
  if (!exactLegacyFields(value, keys) || value.version !== (reviewed ? 2 : 1) || reviewed && (!isId(value.review_id) || !positiveLegacyCount(value.transaction_version) || value.settlement_status !== 'not_asserted' || (value.proposal_status === 'approved' ? !isId(value.allocation_id) : value.allocation_id !== null))) invalidLegacyDecision('The original reconciliation receipt could not be verified.');
  if (attempt) {const original = parseLegacyDecisionIntent(attempt.intent, context, attempt.permission);
    if (reviewed !== (legacyDecisionKind(original) === 'review') || reviewed && (value.resource_id !== original.proposal_id || value.proposal_status !== original.body.outcome || value.transaction_version !== Number(original.body.expected_transaction_version) + (original.body.outcome === 'approved' ? 1 : 0))) invalidLegacyDecision('The original reconciliation receipt could not be verified.');}
  return {requestId: value.request_id, proposalId: value.resource_id, transactionId: context.transactionId, status: value.proposal_status as LegacyDecisionReceipt['status'], version: value.version as number};
}
async function lookupUnderFence(context: LegacyDecisionContext, pending: Extract<LegacyDecisionPending, {kind: 'owned'}>): Promise<LegacyDecisionLookup> {
  checkLegacyDecision(context); const body = await context.request(`reconciliations/requests/${pending.requestKey}`); checkLegacyDecision(context);
  if (body.status === 'not_found' && exactLegacyFields(body, ['status'])) {
    let retryAvailable = false;
    if (pending.attempt?.family === GUARDED_FAMILY && (await binding(context, pending.requestKey, pending.attempt)).kind === 'valid') {try {const intent = parseLegacyDecisionIntent(pending.attempt.intent, context, pending.attempt.permission); checkLegacyDecision(context, legacyDecisionPermission(intent)); retryAvailable = Object.hasOwn(intent.body, 'expected_source_state');} catch { /* Keep other attempts check-only. */ }}
    checkLegacyDecision(context);
    return {status: 'not_found', retryAvailable};
  }
  if (!exactLegacyFields(body, ['status', 'request_id', 'receipt']) || !isId(body.request_id)) invalidLegacyDecision('The original reconciliation receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded' || pending.attempt && (await binding(context, pending.requestKey, pending.attempt)).kind === 'mismatch') invalidLegacyDecision('The original reconciliation receipt could not be verified.');
  checkLegacyDecision(context);
  const saved = receipt(context, body.receipt, pending.attempt); if (saved.requestId !== body.request_id) invalidLegacyDecision('The original reconciliation receipt could not be verified.'); return {status: 'succeeded', receipt: saved};
}
async function finish(context: LegacyDecisionContext, access: FenceAccess, pending: Extract<LegacyDecisionPending, {kind: 'owned'}>, response: unknown): Promise<LegacyDecisionResult> {
  const direct = receipt(context, response, pending.attempt), original = await lookupUnderFence(context, pending);
  if (original.status !== 'succeeded' || JSON.stringify(direct) !== JSON.stringify(original.receipt)) invalidLegacyDecision('The original reconciliation receipt could not be verified.');
  await clear(context, access, pending); return {status: 'succeeded', receipt: direct};
}
export async function submitLegacyDecision(context: LegacyDecisionContext, input: LegacyDecisionIntent, source: LegacyDecisionSource, observedRevision: string): Promise<LegacyDecisionResult> {
  const intent = parseLegacyDecisionIntent(input, context); requireLegacyDecisionWrite(context, legacyDecisionPermission(intent));
  return fence(context, async access => {
    const existing = await restoreUnderFence(context, access); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const latest = await currentLegacyDecision(context, intent); if (JSON.stringify(latest) !== JSON.stringify(source)) invalidLegacyDecision('The payment or review changed. Review it again.');
    if (!await context.verifyFresh()) invalidLegacyDecision('Complete current account verification before recording reconciliation.'); requireLegacyDecisionWrite(context, legacyDecisionPermission(intent));
    const current = await restoreUnderFence(context, access); if (current.kind !== 'ready') return {status: 'existing', pending: current};
    const requestKey = (context.createKey ?? (() => crypto.randomUUID()))(); if (!isId(requestKey)) invalidLegacyDecision('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, GUARDED_FAMILY, context.transactionId, requestKey, legacyDecisionPermission(intent), {...intent}, context.storage); await saveBinding(context, attempt, latest);}
    catch (error) {
      if (context.isCurrent()) {
        try {
          const retained = await readPending(context.identity, GUARDED_FAMILY, context.transactionId, context.storage);
          if (retained && retained.request_key !== requestKey) invalidLegacyDecision();
          await clear(context, access, {kind: 'owned', requestKey, attempt: retained});
        } catch { /* Preserve the fence when cleanup is uncertain. */ }
      }
      throw error;
    }
    const pending: Extract<LegacyDecisionPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey};
    try {const response = await context.request(`reconciliations${intent.path}`, {method: 'POST', body: intent.body, idempotencyKey: requestKey}); checkLegacyDecision(context, legacyDecisionPermission(intent)); return await finish(context, access, pending, response);}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLegacyDecision(context: LegacyDecisionContext, pending: LegacyDecisionPending): Promise<LegacyDecisionLookup> {
  checkLegacyDecision(context); if (pending.kind !== 'owned') invalidLegacyDecision('The original account must check this request.');
  return fence(context, async access => {
    const saved = await restoreUnderFence(context, access);
    if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey ||
        (pending.attempt ? !sameReconciliationAttempt(saved.attempt, pending.attempt) : saved.attempt !== null)) invalidLegacyDecision();
    const result = await lookupUnderFence(context, saved);
    if (result.status === 'succeeded') await clear(context, access, saved);
    return result;
  });
}
export async function retryLegacyDecision(context: LegacyDecisionContext, pending: LegacyDecisionPending): Promise<LegacyDecisionResult> {
  if (pending.kind !== 'owned' || !pending.attempt) invalidLegacyDecision('The original reconciliation intent is unavailable.');
  const originalAttempt = pending.attempt;
  const original = parseLegacyDecisionIntent(originalAttempt.intent, context, originalAttempt.permission); requireLegacyDecisionWrite(context, legacyDecisionPermission(original));
  return fence(context, async access => {
    const saved = await restoreUnderFence(context, access); if (saved.kind !== 'owned' || !saved.attempt || saved.requestKey !== pending.requestKey || !sameReconciliationAttempt(saved.attempt, originalAttempt)) invalidLegacyDecision();
    const status = await lookupUnderFence(context, saved); if (status.status === 'succeeded') {await clear(context, access, saved); return {status: 'succeeded', receipt: status.receipt};}
    if (status.status !== 'not_found' || !status.retryAvailable) invalidLegacyDecision('The original reconciliation request remains unresolved.');
    const intent = parseLegacyDecisionIntent(saved.attempt.intent, context, saved.attempt.permission), owner = await binding(context, saved.requestKey, saved.attempt), latest = await currentLegacyDecision(context, intent);
    if (owner.kind !== 'valid' || await sha256Text(JSON.stringify(latest)) !== owner.sourceHash) invalidLegacyDecision('The original payment or review changed. Check the request before continuing.');
    if (!await context.verifyFresh()) invalidLegacyDecision('Complete current account verification before retrying reconciliation.');
    const retained = await readPending(context.identity, saved.attempt.family, context.transactionId, context.storage);
    if (!sameReconciliationAttempt(retained, saved.attempt) || storage(context).getItem(bindingKey(context)) !== owner.raw) invalidLegacyDecision();
    requireLegacyDecisionWrite(context, legacyDecisionPermission(intent));
    try {const response = await context.request(`reconciliations${intent.path}`, {method: 'POST', body: intent.body, idempotencyKey: saved.requestKey}); checkLegacyDecision(context, legacyDecisionPermission(intent)); return await finish(context, access, saved, response);}
    catch {return {status: 'unknown', requestKey: saved.requestKey};}
  });
}
