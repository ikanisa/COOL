import { isAdminIdentityId } from '../../session/ownerIdentity';
import { containsControl, isId, isObject, isSafeCount } from '../core/contracts';
import { canonicalRequestId, readPending, retainPending } from '../core/pendingAttempt';
import type { PendingAttempt, PendingIdentity } from '../core/pendingAttempt';
import type { FeatureAccess } from '../core/types';
import type { parseReconciliationDetail } from './contracts';
import { clearOriginalReconciliationAttempt, sameReconciliationAttempt } from './custody';

export const RECONCILIATION_FAMILY = 'canonical-reconciliation';
export type ReconciliationSnapshot = ReturnType<typeof parseReconciliationDetail>;
export type ReconciliationMember = Record<string, unknown> & { member_user_id: string; group_id: string; payment_identity: Record<string, unknown> };
export interface FinancialIntent { kind: 'propose' | 'review'; path: string; transaction_id: string; proposal_id: string | null; body: Record<string, unknown> }
type Outcome = 'approved' | 'rejected';

export class FinancialAttemptError extends Error {
  constructor(readonly possiblySubmitted: boolean) {
    super(possiblySubmitted ? 'The original request needs review.' : 'The request was not submitted.');
  }
}

function invalid(): never { throw new Error('The reconciliation request could not be verified.'); }
function exactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean { return Object.keys(value).length === keys.length && keys.every(key => key in value); }
function positive(value: unknown): value is number { return isSafeCount(value) && value > 0; }
function validReason(reason: unknown): reason is string {
  return typeof reason === 'string' && reason.trim().length >= 8 && reason.trim().length <= 500 &&
    [...reason].every(char => { const c = char.codePointAt(0)!; return c >= 0x20 && c !== 0x7f || c === 9 || c === 10 || c === 13; });
}

function paymentIdentity(value: unknown): Record<string, unknown> {
  if (!isObject(value) || !exactKeys(value, ['display_name', 'momo_provider', 'momo_number', 'momo_pay_code']) ||
      typeof value.display_name !== 'string' || value.display_name.length > 120 || containsControl(value.display_name) ||
      !['', 'mtn_momo', 'airtel_money'].includes(String(value.momo_provider)) ||
      typeof value.momo_number !== 'string' || (value.momo_number !== '' && !/^07[2389]\d{7}$/.test(value.momo_number)) ||
      typeof value.momo_pay_code !== 'string' || (value.momo_pay_code !== '' && !/^\d{4,9}$/.test(value.momo_pay_code))) invalid();
  return value;
}

function eligibleIdentity(value: Record<string, unknown>): boolean {
  return typeof value.display_name === 'string' && value.display_name.trim().length >= 2 && typeof value.momo_number === 'string' && value.momo_number.length > 0;
}

export function parseReconciliationMembers(input: unknown, detail: ReconciliationSnapshot, limit: number, offset: number): { rows: ReconciliationMember[]; total: number; nextOffset: number | null } {
  const keys = ['contract_version', 'model', 'transaction_id', 'rows', 'total', 'limit', 'offset', 'next_offset'];
  if (!isObject(input) || !exactKeys(input, keys) || input.contract_version !== 2 || input.model !== 'canonical_evidence_ledger' ||
      input.transaction_id !== detail.resource.id || !Array.isArray(input.rows) || !isSafeCount(input.total) ||
      input.limit !== limit || input.offset !== offset || limit < 1 || limit > 100 || offset < 0 || offset > 2147483647 ||
      input.rows.length !== Math.min(limit, Math.max(0, input.total - offset)) ||
      input.next_offset !== (offset + input.rows.length < input.total ? offset + input.rows.length : null)) invalid();
  const expected = ['member_user_id', 'member_version', 'member_type', 'public_id', 'display_name', 'momo_provider', 'momo_number', 'momo_pay_code', 'membership_version', 'membership_role', 'group_id', 'group_title', 'group_version', 'payment_identity'];
  const rows: ReconciliationMember[] = input.rows.map(value => {
    if (!isObject(value) || !exactKeys(value, expected) || !isId(value.member_user_id) || value.group_id !== detail.resource.group_id ||
        !positive(value.member_version) || !positive(value.membership_version) || !positive(value.group_version) ||
        !['app', 'direct'].includes(String(value.member_type)) || typeof value.public_id !== 'string' || !/^\d{6}$/.test(value.public_id) ||
        !['owner', 'admin', 'receiver', 'member', 'contributor', 'viewer'].includes(String(value.membership_role)) ||
        typeof value.group_title !== 'string' || !value.group_title.trim()) invalid();
    const identity = paymentIdentity(value.payment_identity);
    if (Object.entries(identity).some(([key, item]) => value[key] !== item)) invalid();
    return value as ReconciliationMember;
  });
  if (new Set(rows.map(row => row.member_user_id)).size !== rows.length) invalid();
  return { rows, total: input.total, nextOffset: input.next_offset as number | null };
}

function eligiblePayment(detail: ReconciliationSnapshot): boolean {
  return detail.groupState?.status === 'active' && ['recorded', 'ambiguous'].includes(String(detail.resource.status)) &&
    detail.resource.member_user_id === null && detail.resource.allocated_amount_rwf === 0;
}

export function prepareProposal(detail: ReconciliationSnapshot, member: ReconciliationMember, reason: string, permissions: readonly string[]): FinancialIntent {
  if (!detail.canPropose || !permissions.includes('reconciliations.propose') || !permissions.includes('users.read') ||
      !eligiblePayment(detail) || !isId(detail.resource.id) || !positive(detail.resource.version) || !positive(detail.resource.amount_rwf) ||
      !isId(member.member_user_id) || member.group_id !== detail.resource.group_id || member.group_version !== detail.groupVersion ||
      !positive(member.member_version) || !positive(member.membership_version) || !eligibleIdentity(paymentIdentity(member.payment_identity)) || !validReason(reason)) invalid();
  return { kind: 'propose', path: `/${detail.resource.id}/proposals`, transaction_id: detail.resource.id, proposal_id: null,
    body: { member_user_id: member.member_user_id, amount_rwf: detail.resource.amount_rwf, expected_transaction_version: detail.resource.version,
      expected_member_version: member.member_version, expected_membership_version: member.membership_version,
      expected_payment_identity: member.payment_identity, reason: reason.trim() } };
}

function sameRecord(left: Record<string, unknown>, right: Record<string, unknown>): boolean {
  const keys = Object.keys(left).sort();
  return keys.length === Object.keys(right).length && keys.every(key => left[key] === right[key]);
}

export function prepareReview(detail: ReconciliationSnapshot, proposal: Record<string, unknown>, outcome: Outcome, reason: string, principalId: string, role: string, permissions: readonly string[], member?: ReconciliationMember): FinancialIntent {
  if (!detail.canReview || !permissions.includes('reconciliations.review') || role === 'staff' || !isAdminIdentityId(principalId) ||
      !isId(proposal.id) || !detail.related.proposals?.rows.includes(proposal) || proposal.payment_id !== detail.resource.id || proposal.evidence_id !== detail.resource.evidence_id || proposal.status !== 'proposed' || proposal.version !== 1 ||
      proposal.snapshot_available !== true || proposal.proposed_by_principal_id === principalId || !isAdminIdentityId(proposal.proposed_by_principal_id) ||
      !['approved', 'rejected'].includes(outcome) || !positive(detail.resource.version) || !isId(detail.resource.id) || !validReason(reason)) invalid();
  if (outcome === 'approved') {
    const snapshot = paymentIdentity(proposal.payment_identity);
    if (!member || !eligiblePayment(detail) || !eligibleIdentity(snapshot) || !eligibleIdentity(paymentIdentity(member.payment_identity)) ||
        !sameRecord(snapshot, member.payment_identity) || member.member_user_id !== proposal.member_user_id ||
        member.group_id !== detail.resource.group_id || member.member_version !== proposal.member_version ||
        member.membership_version !== proposal.membership_version || member.group_version !== proposal.group_version ||
        member.group_version !== detail.groupVersion || proposal.expected_payment_version !== detail.resource.version ||
        !isObject(proposal.receiver_identity) || !isObject(detail.groupState?.receiver) ||
        !sameRecord(proposal.receiver_identity, detail.groupState.receiver) ||
        typeof detail.resource.provider_reference !== 'string' || !detail.resource.provider_reference.trim()) invalid();
  }
  return { kind: 'review', path: `/proposals/${proposal.id}/reviews`, transaction_id: detail.resource.id, proposal_id: proposal.id,
    body: { outcome, expected_proposal_version: 1, expected_transaction_version: detail.resource.version, reason: reason.trim() } };
}

export function parseFinancialIntent(value: unknown, id: string, permission: string): FinancialIntent {
  if (!isObject(value) || !exactKeys(value, ['kind', 'path', 'transaction_id', 'proposal_id', 'body']) ||
      value.transaction_id !== id || !isId(id) || !isObject(value.body) || !validReason(value.body.reason) ||
      !positive(value.body.expected_transaction_version)) invalid();
  if (value.kind === 'propose') {
    if (permission !== 'reconciliations.propose' || value.proposal_id !== null || value.path !== `/${id}/proposals` ||
        !exactKeys(value.body, ['member_user_id', 'amount_rwf', 'expected_transaction_version', 'expected_member_version', 'expected_membership_version', 'expected_payment_identity', 'reason']) ||
        !isId(value.body.member_user_id) || !positive(value.body.amount_rwf) || !positive(value.body.expected_member_version) ||
        !positive(value.body.expected_membership_version) || !eligibleIdentity(paymentIdentity(value.body.expected_payment_identity))) invalid();
  } else if (value.kind === 'review') {
    if (permission !== 'reconciliations.review' || !isId(value.proposal_id) || value.path !== `/proposals/${value.proposal_id}/reviews` ||
        !exactKeys(value.body, ['outcome', 'expected_proposal_version', 'expected_transaction_version', 'reason']) ||
        !['approved', 'rejected'].includes(String(value.body.outcome)) || value.body.expected_proposal_version !== 1 ||
        (value.body.outcome === 'approved' && value.body.expected_transaction_version >= Number.MAX_SAFE_INTEGER)) invalid();
  } else invalid();
  return value as unknown as FinancialIntent;
}

export async function verifyFinancialReceipt(value: unknown, intent: FinancialIntent, principalId: string, key: string): Promise<boolean> {
  if (!isObject(value) || !exactKeys(value, ['contract_version', 'model', 'status', 'request_id', 'resource_type', 'resource_id', 'version', 'transaction_id', 'proposal_status', 'settlement_status', ...(intent.kind === 'review' ? ['transaction_version'] : [])]) ||
      value.contract_version !== 2 || value.model !== 'canonical_evidence_ledger' || value.status !== 'succeeded' ||
      value.resource_type !== 'reconciliation_proposals' || !isId(value.resource_id) || value.transaction_id !== intent.transaction_id ||
      value.settlement_status !== 'not_asserted' || value.request_id !== await canonicalRequestId(principalId, key)) return false;
  if (intent.kind === 'propose') return value.version === 1 && value.proposal_status === 'proposed';
  return value.resource_id === intent.proposal_id && value.version === 2 && value.proposal_status === intent.body.outcome &&
    value.transaction_version === (intent.body.expected_transaction_version as number) + (intent.body.outcome === 'approved' ? 1 : 0);
}

type Lock = <T>(name: string, operation: () => Promise<T>) => Promise<T>;
const browserLock: Lock = async (name, operation) => {
  if (!navigator.locks) throw new Error('A protected request lock is unavailable.');
  return navigator.locks.request(name, { ifAvailable: true }, lock => {
    if (!lock) throw new Error('Another review is in progress.');
    return operation();
  });
};

/** One fresh attempt only. Unknown outcomes stay in the original envelope; no automatic replay. */
export async function submitFinancialAttempt(access: FeatureAccess, identity: PendingIdentity, intentValue: FinancialIntent, key: string, gate: boolean,
  verifyFresh: () => Promise<boolean>, isCurrent: () => boolean, revalidate: (intent: FinancialIntent) => Promise<boolean>, lock: Lock = browserLock): Promise<Record<string, unknown>> {
  const permission = intentValue.kind === 'propose' ? 'reconciliations.propose' : 'reconciliations.review';
  const intent = parseFinancialIntent(intentValue, intentValue.transaction_id, permission);
  const principalId = access.principalId;
  if (!gate || !isId(key) || access.financialModel !== 'canonical_evidence_ledger' || !isAdminIdentityId(principalId) ||
      identity.id !== access.actorId || identity.role !== access.role || !access.permissions.includes(permission) ||
      !identity.permissions.includes(permission) || !access.permissions.includes('users.read') || !access.permissions.includes('reconciliations.read') ||
      !Number.isFinite(Date.parse(identity.expiresAt)) || Date.parse(identity.expiresAt) <= Date.now() ||
      (intent.kind === 'review' && access.role === 'staff') || !isCurrent()) invalid();
  let dispatched = false;
  try {
    return await lock(`collect-admin-canonical-reconciliation:${principalId}:${intent.transaction_id}`, async () => {
      if (!isCurrent() || !await verifyFresh() || !isCurrent() || !await revalidate(intent) || !isCurrent()) invalid();
      if (await readPending(identity, RECONCILIATION_FAMILY, intent.transaction_id)) throw new Error('Check the original request before continuing.');
      if (!isCurrent()) invalid();
      const pending = await retainPending(identity, RECONCILIATION_FAMILY, intent.transaction_id, key, permission, intent as unknown as Record<string, unknown>);
      if (!isCurrent()) invalid();
      dispatched = true;
      return recordFinancialAttempt(access, identity, principalId, pending, isCurrent);
    });
  } catch {
    throw new FinancialAttemptError(dispatched);
  }
}

async function recordFinancialAttempt(access: FeatureAccess, identity: PendingIdentity, principalId: string,
  pending: PendingAttempt, isCurrent: () => boolean): Promise<Record<string, unknown>> {
  const intent = parseFinancialIntent(pending.intent, pending.resource_id, pending.permission);
  const receipt = await access.request(`reconciliations${intent.path}`,
    { method: 'POST', body: intent.body, idempotencyKey: pending.request_key });
  if (!isCurrent() || !await verifyFinancialReceipt(receipt, intent, principalId, pending.request_key)) invalid();
  await clearOriginalReconciliationAttempt(identity, pending, isCurrent);
  return receipt;
}

export async function lookupFinancialAttempt(access: FeatureAccess, identity: PendingIdentity, pending: PendingAttempt, isCurrent: () => boolean): Promise<'not_found' | 'unconfirmed' | 'cancelled' | 'succeeded'> {
  const principalId = access.principalId;
  if (access.financialModel !== 'canonical_evidence_ledger' || !isAdminIdentityId(principalId) || !access.permissions.includes('account.manage') ||
      identity.id !== access.actorId || identity.role !== access.role || !isId(pending.request_key) ||
      pending.family !== RECONCILIATION_FAMILY || !access.permissions.includes(pending.permission) || !identity.permissions.includes(pending.permission) || !isCurrent()) invalid();
  const stored = await readPending(identity, RECONCILIATION_FAMILY, pending.resource_id);
  if (!sameReconciliationAttempt(stored, pending) || !isCurrent()) invalid();
  const intent = parseFinancialIntent(pending.intent, pending.resource_id, pending.permission);
  const data = await access.request(`operations/requests/${pending.request_key}`);
  if (!isCurrent() || data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger') invalid();
  if (data.status === 'not_found' && exactKeys(data, ['contract_version', 'model', 'status'])) return 'not_found';
  if (!exactKeys(data, ['contract_version', 'model', 'status', 'request_id', 'receipt']) ||
      data.request_id !== await canonicalRequestId(principalId, pending.request_key) || !isCurrent()) invalid();
  if (data.status === 'unconfirmed' && data.receipt === null) return 'unconfirmed';
  if (data.status === 'cancelled' && data.receipt === null) {
    await clearOriginalReconciliationAttempt(identity, pending, isCurrent);
    return 'cancelled';
  }
  if (data.status !== 'succeeded' || !await verifyFinancialReceipt(data.receipt, intent, principalId, pending.request_key)) invalid();
  await clearOriginalReconciliationAttempt(identity, pending, isCurrent);
  return 'succeeded';
}

/** Explicit, reviewed retry of a retained request only; never generate a replacement key. */
export async function retryFinancialAttempt(access: FeatureAccess, identity: PendingIdentity, pending: PendingAttempt, gate: boolean,
  verifyFresh: () => Promise<boolean>, isCurrent: () => boolean, revalidate: (intent: FinancialIntent) => Promise<boolean>, lock: Lock = browserLock): Promise<'succeeded' | 'cancelled' | 'retried'> {
  const intent = parseFinancialIntent(pending.intent, pending.resource_id, pending.permission);
  const principalId = access.principalId;
  if (!gate || access.financialModel !== 'canonical_evidence_ledger' || !isAdminIdentityId(principalId) ||
      identity.id !== access.actorId || identity.role !== access.role || !access.permissions.includes(pending.permission) ||
      !identity.permissions.includes(pending.permission) || !access.permissions.includes('users.read') || !access.permissions.includes('reconciliations.read') ||
      (intent.kind === 'review' && access.role === 'staff') || !Number.isFinite(Date.parse(identity.expiresAt)) || Date.parse(identity.expiresAt) <= Date.now() || !isCurrent()) invalid();
  let dispatched = false;
  try {
    return await lock(`collect-admin-canonical-reconciliation:${principalId}:${intent.transaction_id}`, async () => {
      const status = await lookupFinancialAttempt(access, identity, pending, isCurrent);
      if (status === 'succeeded' || status === 'cancelled') return status;
      if (status !== 'not_found' || !isCurrent() || !await verifyFresh() || !isCurrent() || !await revalidate(intent) || !isCurrent()) invalid();
      const stored = await readPending(identity, RECONCILIATION_FAMILY, intent.transaction_id);
      if (!stored || !sameReconciliationAttempt(stored, pending) || !isCurrent()) invalid();
      dispatched = true;
      await recordFinancialAttempt(access, identity, principalId, stored, isCurrent);
      return 'retried';
    });
  } catch { throw new FinancialAttemptError(dispatched); }
}
