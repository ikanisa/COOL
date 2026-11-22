import { isAdminIdentityId } from '../../session/ownerIdentity';
import { isId, isObject, isSafeCount, parseCoreRow } from '../core/contracts';
import type { DataRow, FinancialModel } from '../core/types';

type RecordValue = Record<string, unknown>;
export interface ReconciliationPage { rows: RecordValue[]; total: number; limit: number; offset: number; nextOffset: number | null }

function invalid(): never { throw new Error('The reconciliation response could not be verified.'); }
// A receiver can be a Rwandan mobile number or a 4–9 digit MoMo pay code.
function validReceiverNumberOrCode(value: string): boolean {
  return /^(?:07[2389]\d{7}|\+?2507[2389]\d{7}|\d{4,9})$/.test(value);
}

function parseLegacyTransaction(input: unknown): RecordValue {
  if (!isObject(input) || !isId(input.id) || !isId(input.group_id) || !isId(input.payee_id) ||
      !isSafeCount(input.amount_rwf) || input.amount_rwf === 0 || !isSafeCount(input.allocated_amount_rwf) ||
      !isSafeCount(input.unallocated_amount_rwf) || input.allocated_amount_rwf > input.amount_rwf ||
      input.unallocated_amount_rwf !== input.amount_rwf - input.allocated_amount_rwf ||
      input.currency !== 'RWF' || input.rail !== 'rwanda_momo' || input.settlement_status !== 'not_asserted' ||
      !['mtn_momo', 'airtel_money'].includes(String(input.network)) ||
      !['pending', 'confirmation_recorded', 'rejection_recorded', 'evidence_conflict'].includes(String(input.verification_status)) ||
      typeof input.provider_reference !== 'string' || !input.provider_reference.trim() ||
      typeof input.group_title !== 'string' || typeof input.payee_name !== 'string' || !isSafeCount(input.version) || input.version < 1) invalid();
  const expected = input.unallocated_amount_rwf === 0 ? 'allocated' : input.allocated_amount_rwf === 0 ? 'unallocated' : 'partially_allocated';
  if (input.allocation_status !== expected) invalid();
  return input;
}

export function parseReconciliationPage(input: unknown, model: FinancialModel, limit: number, offset: number, status = ''): ReconciliationPage {
  if (!isObject(input) || !Array.isArray(input.rows) || !isSafeCount(input.total) || !isSafeCount(input.limit) || !isSafeCount(input.offset) ||
      input.limit !== limit || input.offset !== offset || limit < 1 || limit > 100 || offset > 2147483647 ||
      (input.next_offset !== null && !isSafeCount(input.next_offset))) invalid();
  const canonical = model === 'canonical_evidence_ledger';
  const keys = canonical ? ['contract_version', 'model', 'rows', 'total', 'limit', 'offset', 'next_offset'] : ['rows', 'total', 'limit', 'offset', 'next_offset'];
  if (Object.keys(input).length !== keys.length || !keys.every(key => key in input) ||
      (canonical && (input.contract_version !== 2 || input.model !== model))) invalid();
  if (input.rows.length !== Math.min(limit, Math.max(0, input.total - offset))) invalid();
  const next = offset + input.rows.length < input.total ? offset + input.rows.length : null;
  if (input.next_offset !== next) invalid();
  const rows = input.rows.map(row => canonical ? parseCoreRow('transactions', model, row) : parseLegacyTransaction(row));
  if (new Set(rows.map(row => row.id)).size !== rows.length || rows.some(row =>
    canonical ? status !== '' && row.status !== status :
      row.unallocated_amount_rwf === 0 || row.verification_status === 'rejection_recorded' || (status !== '' && row.verification_status !== status))) invalid();
  return { rows, total: input.total, limit, offset, nextOffset: next };
}

export function parseReconciliationDetail(input: unknown, model: FinancialModel, id: string, actorId: string, principalId: string | null, permissions: readonly string[], role: string, relation?: string, limit = 25, offset = 0): { resource: RecordValue; related: Record<string, ReconciliationPage>; groupVersion: number | null; groupState: RecordValue | null; canPropose: boolean; canReview: boolean } {
  if (!isId(id) || !isObject(input) || input.resource_type !== 'reconciliations' || input.current_actor_id !== actorId ||
      typeof input.can_propose !== 'boolean' || typeof input.can_review !== 'boolean' || !isObject(input.related) ||
      (input.can_propose && !permissions.includes('reconciliations.propose')) ||
      (input.can_review && (!permissions.includes('reconciliations.review') || role === 'staff'))) invalid();
  let resource: RecordValue;
  let groupVersion: number | null = null;
  let groupState: RecordValue | null = null;
  if (model === 'canonical_evidence_ledger') {
    if (input.contract_version !== 2 || input.model !== model || !isAdminIdentityId(principalId) || input.current_principal_id !== principalId || !isObject(input.group_state) ||
        !isId(input.group_state.id) || !isSafeCount(input.group_state.version) || input.group_state.version === 0 ||
        !['active', 'suspended', 'archived'].includes(String(input.group_state.status)) || !isObject(input.group_state.receiver)) invalid();
    resource = parseCoreRow('transactions', model, input.resource) as DataRow;
    if (input.group_state.id !== resource.group_id) invalid();
    if (Object.keys(input.group_state).length !== 4 || !isObject(input.group_state.receiver) ||
        Object.keys(input.group_state.receiver).length !== 3 || typeof input.group_state.receiver.momo_number_or_code !== 'string' ||
        !validReceiverNumberOrCode(input.group_state.receiver.momo_number_or_code) ||
        !['mtn_momo', 'airtel_money'].includes(String(input.group_state.receiver.network)) ||
        typeof input.group_state.receiver.label !== 'string' || !input.group_state.receiver.label.trim()) invalid();
    groupVersion = input.group_state.version;
    groupState = input.group_state;
    if (input.can_propose && (input.group_state.status !== 'active' || !['recorded', 'ambiguous'].includes(String(resource.status)) || resource.member_user_id !== null || resource.allocated_amount_rwf !== 0)) invalid();
  } else resource = parseLegacyTransaction(input.resource);
  if (resource.id !== id) invalid();
  const permitted = model === 'canonical_evidence_ledger' ?
    ['evidence', 'proposals', ...(permissions.includes('ledger.read') ? ['ledger_entries'] : [])] :
    ['evidence', 'verification_reviews', 'allocations', 'proposals', 'journals'];
  if (relation && !permitted.includes(relation)) invalid();
  const expected = relation ? [relation] : permitted;
  const relatedInput = input.related;
  if (Object.keys(relatedInput).length !== expected.length || !expected.every(key => key in relatedInput)) invalid();
  const related: Record<string, ReconciliationPage> = {};
  for (const key of expected) {
    const page = relatedInput[key];
    if (!isObject(page) || !Array.isArray(page.rows) || !isSafeCount(page.total) || !isSafeCount(page.limit) ||
        !isSafeCount(page.offset) || page.limit !== limit || page.offset !== offset || page.limit < 1 || page.limit > 100 ||
        page.rows.length !== Math.min(page.limit, Math.max(0, page.total - page.offset)) ||
        page.next_offset !== (page.offset + page.rows.length < page.total ? page.offset + page.rows.length : null) ||
        page.rows.some(row => !isObject(row) || !isId(row.id)) ||
        new Set(page.rows.map(row => (row as RecordValue).id)).size !== page.rows.length) invalid();
    if (model === 'canonical_evidence_ledger') {
      for (const item of page.rows as RecordValue[]) {
        if (key === 'evidence' && (item.id !== resource.evidence_id || typeof item.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(item.sha256) ||
            !isSafeCount(item.size_bytes) || item.size_bytes === 0 || !['operator_recorded', 'provider_authenticated'].includes(String(item.authenticity)))) invalid();
        if (key === 'proposals' && (item.payment_id !== id || item.evidence_id !== resource.evidence_id || !isId(item.member_user_id) ||
            !isAdminIdentityId(item.proposed_by_principal_id) || !isId(item.request_id) || !['proposed', 'approved', 'rejected', 'cancelled'].includes(String(item.status)) ||
            typeof item.member_public_id !== 'string' || !/^\d{6}$/.test(item.member_public_id) || !isSafeCount(item.expected_payment_version) || item.expected_payment_version === 0 ||
            typeof item.snapshot_available !== 'boolean' || item.version !== (item.status === 'proposed' ? 1 : 2) ||
            (item.snapshot_available && (!isObject(item.payment_identity) || !isObject(item.receiver_identity) || !isSafeCount(item.member_version) || !item.member_version || !isSafeCount(item.membership_version) || !item.membership_version || !isSafeCount(item.group_version) || !item.group_version)) ||
            (!item.snapshot_available && (item.payment_identity !== null || item.receiver_identity !== null || item.member_version !== null || item.membership_version !== null || item.group_version !== null)) ||
            (['approved', 'rejected'].includes(String(item.status)) ?
              !isAdminIdentityId(item.reviewed_by_principal_id) || item.reviewed_by_principal_id === item.proposed_by_principal_id || typeof item.reviewed_at !== 'string' || !Number.isFinite(Date.parse(item.reviewed_at)) :
              item.reviewed_by_principal_id !== null || item.reviewed_at !== null))) invalid();
        if (key === 'proposals' && item.snapshot_available) {
          const identity = item.payment_identity as Record<string, unknown>, receiver = item.receiver_identity as Record<string, unknown>;
          if (Object.keys(identity).length !== 4 || typeof identity.display_name !== 'string' || identity.display_name.length > 120 ||
              !['', 'mtn_momo', 'airtel_money'].includes(String(identity.momo_provider)) ||
              typeof identity.momo_number !== 'string' || (identity.momo_number !== '' && !/^07[2389]\d{7}$/.test(identity.momo_number)) ||
              typeof identity.momo_pay_code !== 'string' || (identity.momo_pay_code !== '' && !/^\d{4,9}$/.test(identity.momo_pay_code)) ||
              Object.keys(receiver).length !== 3 || typeof receiver.momo_number_or_code !== 'string' ||
              !validReceiverNumberOrCode(receiver.momo_number_or_code) ||
              !['mtn_momo', 'airtel_money'].includes(String(receiver.network)) || typeof receiver.label !== 'string' || !receiver.label.trim()) invalid();
        }
        if (key === 'ledger_entries') {
          const ledger = parseCoreRow('ledgers', model, item);
          if (ledger.payment_id !== id || ledger.evidence_id !== resource.evidence_id) invalid();
        }
      }
    }
    related[key] = { rows: page.rows as RecordValue[], total: page.total, limit: page.limit, offset: page.offset, nextOffset: page.next_offset as number | null };
  }
  return { resource, related, groupVersion, groupState, canPropose: input.can_propose as boolean, canReview: input.can_review as boolean };
}
