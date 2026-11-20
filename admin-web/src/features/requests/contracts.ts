import {canonicalRequestId} from '../core/pendingAttempt';
import {isId, isObject, isSafeCount} from '../core/contracts';
import type {FinancialModel} from '../core/types';

const keyPattern = /^[A-Za-z0-9_.-]{8,200}$/;
const versionedScopes: Record<string, readonly string[]> = {
  operator_notes: ['operator_notes.post'], groups: ['groups.post', 'groups.patch'],
  users: ['users.post', 'users.patch'], memberships: ['memberships.post', 'memberships.patch'],
  payees: ['payees.post', 'payees.patch'], accounts: ['accounts.post', 'accounts.patch'],
  transactions: ['transactions.post', 'transactions.post.evidence', 'transactions.post.verification', 'transactions.post.reverse', 'transactions.post.allocations'],
  journals: ['journals.post', 'journals.patch', 'journals.post.post'],
  gateway_devices: ['gateway.enroll', 'gateway.activate', 'gateway.revoke'],
  member_receipts: ['receipt.review'], receiver_capture_grants: ['gateway.receiver.grant', 'gateway.receiver.revoke'],
  email_dispatch: ['email_dispatch'], allocations: ['transactions.post.allocations'], evidence: ['transactions.post.evidence'],
};

function invalid(): never { throw new Error('The request response could not be verified.'); }
function keys(value: Record<string, unknown>, expected: string[]): boolean {
  return Object.keys(value).length === expected.length && expected.every((key) => Object.hasOwn(value, key));
}
function positive(value: unknown): value is number { return isSafeCount(value) && value > 0; }
function utc(value: unknown): boolean {
  return typeof value === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value) &&
    Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
}

export interface RequestReceipt {requestId: string; resourceType: string; resourceId: string; scope?: string}

/** Accept only an actual, internally consistent server receipt. */
export function parseReceipt(value: unknown): RequestReceipt {
  if (!isObject(value) || value.status !== 'succeeded' || !isId(value.request_id) ||
      typeof value.resource_type !== 'string' || typeof value.resource_id !== 'string') return invalid();
  const type = value.resource_type;
  if (type === 'sms_facts') {
    if (!keys(value, ['request_id', 'status', 'resource_type', 'resource_id', 'source_kind', 'source_id', 'parser_version']) ||
        !isId(value.resource_id) || !isId(value.source_id) || !['member', 'receiver', 'capture'].includes(String(value.source_kind)) ||
        value.parser_version !== 'collect-admin-source-facts-v1') return invalid();
    return {requestId: value.request_id, resourceType: type, resourceId: value.resource_id, scope: 'sms.extract'};
  }
  if (type === 'reconciliation_proposals') {
    const canonical = Object.hasOwn(value, 'contract_version') || Object.hasOwn(value, 'model');
    const review = value.proposal_status !== (canonical ? 'proposed' : 'pending');
    const base = ['request_id', 'status', 'resource_type', 'resource_id', 'transaction_id', 'version', 'proposal_status'];
    const expected = canonical ? [...base, 'contract_version', 'model', 'settlement_status', ...(review ? ['transaction_version'] : [])] :
      [...base, ...(review ? ['review_id', 'allocation_id', 'transaction_version', 'settlement_status'] : [])];
    if (!keys(value, expected) || !isId(value.resource_id) || !isId(value.transaction_id) ||
        !['proposed', 'pending', 'approved', 'rejected'].includes(String(value.proposal_status)) ||
        value.version !== (review ? 2 : 1) ||
        (canonical && (value.contract_version !== 2 || value.model !== 'canonical_evidence_ledger' ||
          value.proposal_status === 'pending' || value.settlement_status !== 'not_asserted')) ||
        (!canonical && value.proposal_status === 'proposed') ||
        (review && (!positive(value.transaction_version) || value.settlement_status !== 'not_asserted')) ||
        (!canonical && review && (!isId(value.review_id) ||
          (value.proposal_status === 'approved' ? !isId(value.allocation_id) : value.allocation_id !== null)))) return invalid();
    return {requestId: value.request_id, resourceType: type, resourceId: value.resource_id,
      scope: review ? 'reconciliations.review' : 'reconciliations.propose'};
  }
  if (!Object.hasOwn(versionedScopes, type)) return invalid();
  const email = type === 'email_dispatch';
  if (!keys(value, ['status', 'request_id', 'resource_type', 'resource_id', 'version', ...(email ? ['accepted', 'uncertain', 'suppressed'] : [])]) ||
      !positive(value.version) || !value.resource_id.split('/').every(isId) ||
      value.resource_id.split('/').length !== (type === 'memberships' ? 2 : 1) ||
      (email && (value.resource_id !== value.request_id || value.version !== 1 ||
        !['accepted', 'uncertain', 'suppressed'].every((key) => isSafeCount(value[key]) && (value[key] as number) <= 20) ||
        (value.accepted as number) + (value.uncertain as number) + (value.suppressed as number) > 20))) return invalid();
  return {requestId: value.request_id, resourceType: type, resourceId: value.resource_id};
}

export interface RequestHistoryRow {id: string; key: string; scope: string; status: string; createdAt: string | number; receipt: RequestReceipt | null}
export interface RequestHistory {rows: RequestHistoryRow[]; total: number}

export async function parseHistory(input: unknown, model: FinancialModel, principalId: string | null, offset: number): Promise<RequestHistory> {
  const canonical = model === 'canonical_evidence_ledger';
  if (!isObject(input) || !keys(input, canonical ? ['contract_version', 'model', 'rows', 'total'] : ['rows', 'total']) ||
      (canonical && (input.contract_version !== 2 || input.model !== model)) ||
      !Array.isArray(input.rows) || !isSafeCount(input.total) || !Number.isSafeInteger(offset) || offset < 0 || offset > 2147483647 ||
      input.rows.length !== Math.min(25, Math.max(0, input.total - offset))) return invalid();
  const rows = await Promise.all(input.rows.map(async (raw): Promise<RequestHistoryRow> => {
    if (!isObject(raw) || !isId(raw.id) || typeof raw.idempotency_key !== 'string' || !keyPattern.test(raw.idempotency_key) ||
        typeof raw.scope !== 'string' || typeof raw.status !== 'string' ||
        !(canonical ? ['unconfirmed', 'succeeded', 'cancelled'] : ['pending', 'succeeded', 'failed']).includes(raw.status) ||
        (canonical ? !utc(raw.created_at) : !isSafeCount(raw.created_at))) return invalid();
    if (canonical && (!keys(raw, ['id', 'idempotency_key', 'scope', 'status', 'receipt', 'created_at']) ||
        !principalId || raw.id !== await canonicalRequestId(principalId, raw.idempotency_key) ||
        (raw.status !== 'succeeded' && raw.receipt !== null))) return invalid();
    const receipt = raw.status === 'succeeded' ? parseReceipt(raw.receipt) : null;
    if (receipt && (receipt.requestId !== raw.id ||
      (receipt.scope ? receipt.scope !== raw.scope : !versionedScopes[receipt.resourceType]?.includes(raw.scope)))) return invalid();
    return {id: raw.id, key: raw.idempotency_key, scope: raw.scope, status: raw.status,
      createdAt: raw.created_at as string | number, receipt};
  }));
  if (new Set(rows.map((row) => row.id)).size !== rows.length || new Set(rows.map((row) => row.key)).size !== rows.length) return invalid();
  return {rows, total: input.total};
}

export interface RequestLookup {status: string; requestId?: string; receipt: RequestReceipt | null}
export async function parseLookup(input: unknown, model: FinancialModel, principalId: string | null, requestKey: string): Promise<RequestLookup> {
  if (!keyPattern.test(requestKey) || !isObject(input) || typeof input.status !== 'string') return invalid();
  const canonical = model === 'canonical_evidence_ledger';
  const statuses = canonical ? ['unconfirmed', 'succeeded', 'cancelled', 'not_found'] : ['pending', 'succeeded', 'failed', 'not_found'];
  if (!statuses.includes(input.status)) return invalid();
  if (canonical) {
    if (!keys(input, ['contract_version', 'model', 'status', ...(input.status === 'not_found' ? [] : ['request_id', 'receipt'])]) ||
        input.contract_version !== 2 || input.model !== model ||
        (input.status !== 'not_found' && (!principalId || input.request_id !== await canonicalRequestId(principalId, requestKey))) ||
        (['unconfirmed', 'cancelled'].includes(input.status) && input.receipt !== null)) return invalid();
  } else if (Object.hasOwn(input, 'contract_version') || Object.hasOwn(input, 'model')) return invalid();
  const receipt = input.status === 'succeeded' ? parseReceipt(input.receipt) : null;
  if (receipt && receipt.requestId !== input.request_id) return invalid();
  if (input.status !== 'not_found' && !isId(input.request_id)) return invalid();
  return {status: input.status, ...(isId(input.request_id) ? {requestId: input.request_id} : {}), receipt};
}

export function validRequestKey(value: string): boolean { return keyPattern.test(value); }
