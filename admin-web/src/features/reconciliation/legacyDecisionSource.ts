/* eslint-disable no-control-regex -- Reject control characters in reviewed payment data. */
import type {AdminRequest} from '../../api/client';
import {isId, isObject, isSafeCount} from '../core/contracts';
import type {PendingIdentity} from '../core/pendingAttempt';
import type {FenceLock} from '../operations/pendingFence';
import {parseReconciliationDetail} from './contracts';

const HASH = /^[a-f0-9]{64}$/;
const MAX = Number.MAX_SAFE_INTEGER;

export type LegacyDecisionRow = Record<string, unknown>;
export type LegacyDecisionKind = 'propose' | 'review';
export interface LegacyDecisionContext {transactionId: string; request: AdminRequest; identity: PendingIdentity; actorId: string; permissions: readonly string[]; financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean; verifyFresh: () => Promise<boolean>; storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;}
export interface LegacyPaymentIdentity {display_name: string; momo_provider: string; momo_number: string; momo_pay_code: string;}
export interface LegacyMember {member_user_id: string; member_version: number; member_type: string; public_id: string; group_id: string; group_title: string; group_version: number; membership_version: number; membership_role: string; payment_identity: LegacyPaymentIdentity;}
export interface LegacyProposal {id: string; transaction_id: string; group_id: string; member_user_id: string; amount_rwf: number; transaction_version: number; member_version: number; membership_version: number; group_version: number; payee_version: number; proposed_by_admin_id: string; operation_request_id: string; reason: string; status: 'pending' | 'approved' | 'rejected'; version: number; public_id: string | null; payment_identity: LegacyPaymentIdentity; payee_identity: {payee_id: string; network: string; momo_number_or_code: string};}
export interface LegacyDecisionIntent {path: string; transaction_id: string; proposal_id: string | null; member_public_id: string | null; body: Record<string, unknown>;}
export interface LegacyDecisionSource {transaction: LegacyDecisionRow; proposal: LegacyProposal | null; member: LegacyMember | null;}
export function invalidLegacyDecision(message = 'The reconciliation request could not be verified.'): never {throw new Error(message);}
export function exactLegacyFields(value: LegacyDecisionRow, keys: readonly string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function text(value: unknown, min: number, max: number): value is string {return typeof value === 'string' && value === value.trim() && value.length >= min && value.length <= max && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value);}
export function positiveLegacyCount(value: unknown): value is number {return isSafeCount(value) && value > 0;}
function sourceState(value: unknown): {link_basis: string; source_fact_id: string | null} {
  if (!isObject(value) || !exactLegacyFields(value, ['link_basis', 'source_fact_id']) || !['public_reference', 'reviewed_member_receipt', 'not_recorded'].includes(String(value.link_basis)) ||
      (value.link_basis === 'not_recorded' ? value.source_fact_id !== null : !isId(value.source_fact_id))) invalidLegacyDecision('The recorded payment source could not be verified.');
  return {link_basis: String(value.link_basis), source_fact_id: value.source_fact_id as string | null};
}
function currentSourceState(value: LegacyDecisionRow) {return sourceState({link_basis: value.source_link_basis, source_fact_id: value.source_fact_id});}
export function legacyDecisionKind(intent: LegacyDecisionIntent): LegacyDecisionKind {return intent.proposal_id === null ? 'propose' : 'review';}
export function legacyDecisionPermission(intent: LegacyDecisionIntent) {return legacyDecisionKind(intent) === 'propose' ? 'reconciliations.propose' : 'reconciliations.review';}
export function checkLegacyDecision(context: LegacyDecisionContext, action?: string) {
  const expiry = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'transaction_journals' || !isId(context.transactionId) || !isId(context.actorId) || context.identity.id !== context.actorId ||
      !Number.isFinite(expiry) || expiry <= Date.now() || !context.permissions.includes('reconciliations.read') || !context.identity.permissions.includes('reconciliations.read') ||
      action && (!context.permissions.includes(action) || !context.identity.permissions.includes(action) || action === 'reconciliations.review' && context.identity.role === 'staff')) invalidLegacyDecision('Reconciliation is unavailable to your current account.');
}
export function requireLegacyDecisionWrite(context: LegacyDecisionContext, action: string) {checkLegacyDecision(context, action); if (!context.enabled || context.isEnabled && !context.isEnabled()) invalidLegacyDecision('Reconciliation changes are not enabled for this workspace.');}
function paymentIdentity(value: unknown): LegacyPaymentIdentity {
  if (!isObject(value) || !exactLegacyFields(value, ['display_name', 'momo_provider', 'momo_number', 'momo_pay_code']) || !text(value.display_name, 2, 120) || !['', 'mtn_momo', 'airtel_money'].includes(String(value.momo_provider)) ||
      typeof value.momo_number !== 'string' || !/^07[2389]\d{7}$/.test(value.momo_number) || typeof value.momo_pay_code !== 'string' || value.momo_pay_code !== '' && !/^\d{4,9}$/.test(value.momo_pay_code)) invalidLegacyDecision('The recorded member payment identity could not be verified.');
  return {display_name: value.display_name, momo_provider: String(value.momo_provider), momo_number: value.momo_number, momo_pay_code: value.momo_pay_code};
}
export function parseLegacyDecisionIntent(value: unknown, context: LegacyDecisionContext, expectedPermission?: string): LegacyDecisionIntent {
  if (!isObject(value) || !exactLegacyFields(value, ['path', 'transaction_id', 'proposal_id', 'member_public_id', 'body']) || value.transaction_id !== context.transactionId || !isObject(value.body) ||
      !(value.member_public_id === null || typeof value.member_public_id === 'string' && /^\d{6}$/.test(value.member_public_id))) invalidLegacyDecision();
  const body = value.body, review = value.proposal_id !== null;
  const extra = Object.hasOwn(body, 'expected_source_state') ? ['expected_source_state'] : [];
  if (review ? !isId(value.proposal_id) || value.path !== `/proposals/${value.proposal_id}/reviews` || !exactLegacyFields(body, ['outcome', 'expected_proposal_version', 'expected_transaction_version', 'reason', ...extra]) ||
      !['approved', 'rejected'].includes(String(body.outcome)) || body.expected_proposal_version !== 1 : value.path !== `/${context.transactionId}/proposals` || !exactLegacyFields(body, ['member_user_id', 'amount_rwf', 'expected_transaction_version', 'expected_member_version', 'expected_membership_version', 'expected_payment_identity', 'reason', ...extra]) ||
      !isId(body.member_user_id) || !positiveLegacyCount(body.amount_rwf) || !positiveLegacyCount(body.expected_member_version) || !positiveLegacyCount(body.expected_membership_version) || value.member_public_id === null) invalidLegacyDecision();
  if (!positiveLegacyCount(body.expected_transaction_version) || body.expected_transaction_version >= MAX || !text(body.reason, 8, 1000)) invalidLegacyDecision();
  if (extra.length) sourceState(body.expected_source_state);
  if (!review) paymentIdentity(body.expected_payment_identity);
  const intent = value as unknown as LegacyDecisionIntent;
  if (expectedPermission && expectedPermission !== legacyDecisionPermission(intent)) invalidLegacyDecision(); return intent;
}
function transaction(value: unknown, id: string): LegacyDecisionRow {
  if (!isObject(value) || value.id !== id || !isId(value.group_id) || !isId(value.payee_id) || !positiveLegacyCount(value.version) || value.version >= MAX || !positiveLegacyCount(value.group_version) || !positiveLegacyCount(value.payee_version) ||
      !positiveLegacyCount(value.amount_rwf) || !isSafeCount(value.allocated_amount_rwf) || !isSafeCount(value.unallocated_amount_rwf) || value.allocated_amount_rwf + value.unallocated_amount_rwf !== value.amount_rwf ||
      !['pending', 'confirmation_recorded', 'rejection_recorded', 'evidence_conflict'].includes(String(value.verification_status)) || !['draft', 'active', 'suspended', 'archived'].includes(String(value.group_status)) || !['active', 'inactive'].includes(String(value.payee_status)) ||
      !['mtn_momo', 'airtel_money'].includes(String(value.network)) || typeof value.payee_momo !== 'string' || !/^\d{4,12}$/.test(value.payee_momo) || !text(value.group_title, 1, 200) || !text(value.payee_name, 1, 200) || !text(value.provider_reference, 1, 200) ||
      value.rail !== 'rwanda_momo' || value.currency !== 'RWF' || value.settlement_status !== 'not_asserted') invalidLegacyDecision('The current payment could not be verified.');
  const keys = ['id', 'version', 'group_id', 'group_title', 'group_status', 'group_version', 'payee_id', 'payee_name', 'payee_status', 'payee_version', 'payee_momo', 'network', 'provider_reference', 'amount_rwf', 'allocated_amount_rwf', 'unallocated_amount_rwf', 'verification_status', 'rail', 'currency', 'settlement_status'];
  if ('source_link_basis' in value) {
    if (!['public_reference', 'reviewed_member_receipt', 'not_recorded'].includes(String(value.source_link_basis)) || !(value.source_fact_id === null || isId(value.source_fact_id)) ||
        !(value.source_kind === null || ['receiver', 'member'].includes(String(value.source_kind))) || value.provider_confirmation !== false ||
        !(value.source_body_sha256 === null || typeof value.source_body_sha256 === 'string' && HASH.test(value.source_body_sha256)) || !(value.source_payload_sha256 === null || typeof value.source_payload_sha256 === 'string' && HASH.test(value.source_payload_sha256))) invalidLegacyDecision('The recorded payment source could not be verified.');
    const state = sourceState({link_basis: value.source_link_basis, source_fact_id: value.source_fact_id});
    if (state.link_basis === 'not_recorded' ? value.source_kind !== null || value.source_review_id !== null || value.source_body_sha256 !== null || value.source_payload_sha256 !== null || value.source_amount_rwf !== null || value.source_network !== null :
        !['receiver', 'member'].includes(String(value.source_kind)) || state.link_basis === 'reviewed_member_receipt' && (value.source_kind !== 'member' || !isId(value.source_review_id)) ||
        state.link_basis === 'public_reference' && value.source_review_id !== null || typeof value.source_body_sha256 !== 'string' || typeof value.source_payload_sha256 !== 'string' ||
        value.source_amount_rwf !== value.amount_rwf || value.source_network !== value.network) invalidLegacyDecision('The recorded payment source could not be verified.');
    keys.push('source_link_basis', 'source_fact_id', 'source_kind', 'source_review_id', 'source_body_sha256', 'source_payload_sha256', 'source_amount_rwf', 'source_network', 'payer_source_match_status', 'provider_confirmation');
  }
  return Object.fromEntries(keys.map(key => [key, value[key]]));
}
function member(value: unknown, groupId: string): LegacyMember {
  const keys = ['member_user_id', 'member_version', 'member_type', 'public_id', 'display_name', 'momo_provider', 'momo_number', 'momo_pay_code', 'membership_version', 'membership_role', 'group_id', 'group_title', 'group_version', 'payment_identity'];
  if (!isObject(value) || !exactLegacyFields(value, keys) || !isId(value.member_user_id) || value.group_id !== groupId || !positiveLegacyCount(value.member_version) || !positiveLegacyCount(value.membership_version) || !positiveLegacyCount(value.group_version) ||
      !['app', 'direct'].includes(String(value.member_type)) || typeof value.public_id !== 'string' || !/^\d{6}$/.test(value.public_id) || !text(value.group_title, 1, 200) || !['owner', 'admin', 'receiver', 'member', 'contributor', 'viewer'].includes(String(value.membership_role))) invalidLegacyDecision('The member could not be verified.');
  const identity = paymentIdentity(value.payment_identity); if (Object.entries(identity).some(([key, item]) => value[key] !== item)) invalidLegacyDecision('The member could not be verified.');
  return {member_user_id: value.member_user_id, member_version: value.member_version, member_type: String(value.member_type), public_id: value.public_id, group_id: groupId, group_title: value.group_title, group_version: value.group_version, membership_version: value.membership_version, membership_role: String(value.membership_role), payment_identity: identity};
}
export function parseLegacyProposal(value: unknown, transactionId: string): LegacyProposal {
  if (!isObject(value) || !isId(value.id) || value.transaction_id !== transactionId || !isId(value.group_id) || !isId(value.member_user_id) || !isId(value.proposed_by_admin_id) || !isId(value.operation_request_id) ||
      !['amount_rwf', 'transaction_version', 'member_version', 'membership_version', 'group_version', 'payee_version'].every(key => positiveLegacyCount(value[key])) || !text(value.reason, 8, 1000) ||
      !['pending', 'approved', 'rejected'].includes(String(value.status)) || value.version !== (value.status === 'pending' ? 1 : 2) || !(value.public_id === null || typeof value.public_id === 'string' && /^\d{6}$/.test(value.public_id)) || !isObject(value.payee_identity)) invalidLegacyDecision('The proposal could not be verified.');
  const payee = value.payee_identity;
  if (!exactLegacyFields(payee, ['payee_id', 'network', 'momo_number_or_code']) || !isId(payee.payee_id) || !['mtn_momo', 'airtel_money'].includes(String(payee.network)) || typeof payee.momo_number_or_code !== 'string' || !/^\d{4,12}$/.test(payee.momo_number_or_code)) invalidLegacyDecision('The proposal could not be verified.');
  if (value.status === 'pending' ? ['review_id', 'allocation_id', 'reviewed_by_admin_id', 'review_reason', 'reviewed_at'].some(key => value[key] !== null) : !isId(value.review_id) || !isId(value.reviewed_by_admin_id) || value.reviewed_by_admin_id === value.proposed_by_admin_id || !positiveLegacyCount(value.reviewed_at) || !text(value.review_reason, 8, 1000) || (value.status === 'approved' ? !isId(value.allocation_id) : value.allocation_id !== null)) invalidLegacyDecision('The proposal could not be verified.');
  return {id: value.id, transaction_id: transactionId, group_id: value.group_id, member_user_id: value.member_user_id, amount_rwf: value.amount_rwf as number, transaction_version: value.transaction_version as number, member_version: value.member_version as number, membership_version: value.membership_version as number, group_version: value.group_version as number, payee_version: value.payee_version as number, proposed_by_admin_id: value.proposed_by_admin_id, operation_request_id: value.operation_request_id, reason: value.reason, status: value.status as LegacyProposal['status'], version: value.version as number, public_id: value.public_id as string | null, payment_identity: paymentIdentity(value.payment_identity), payee_identity: {payee_id: payee.payee_id, network: String(payee.network), momo_number_or_code: payee.momo_number_or_code}};
}
async function detail(context: LegacyDecisionContext, relation?: string, limit = 25, offset = 0) {
  checkLegacyDecision(context); const query = new URLSearchParams({limit: String(limit), offset: String(offset), ...(relation ? {related: relation} : {})});
  const response = await context.request(`reconciliations/${context.transactionId}?${query}`); checkLegacyDecision(context);
  const parsed = parseReconciliationDetail(response, 'transaction_journals', context.transactionId, context.actorId, null, context.permissions, context.identity.role, relation, limit, offset);
  return {...parsed, transaction: transaction(parsed.resource, context.transactionId)};
}
export async function searchLegacyReconciliationMembers(context: LegacyDecisionContext, search: string, offset = 0) {
  checkLegacyDecision(context); if (!text(search.trim(), 0, 200) || !Number.isInteger(offset) || offset < 0 || offset > 2147483647) invalidLegacyDecision();
  const current = await detail(context), query = new URLSearchParams({transaction_id: context.transactionId, search: search.trim(), limit: '25', offset: String(offset)}), body = await context.request(`reconciliations/members?${query}`); checkLegacyDecision(context);
  if (!exactLegacyFields(body, ['rows', 'total', 'limit', 'offset', 'next_offset']) || !Array.isArray(body.rows) || !isSafeCount(body.total) || body.limit !== 25 || body.offset !== offset || body.rows.length !== Math.max(0, Math.min(25, body.total - offset)) || body.next_offset !== (offset + body.rows.length < body.total ? offset + body.rows.length : null)) invalidLegacyDecision();
  const rows = body.rows.map(row => member(row, String(current.transaction.group_id)));
  if (new Set(rows.map(row => row.member_user_id)).size !== rows.length || rows.some(row => row.group_title !== current.transaction.group_title || row.group_version !== current.transaction.group_version)) invalidLegacyDecision();
  return {rows, total: body.total, offset, nextOffset: body.next_offset as number | null};
}
export async function listLegacyProposals(context: LegacyDecisionContext) {
  checkLegacyDecision(context, 'reconciliations.review'); let offset = 0, total: number | null = null, current: LegacyDecisionRow | null = null; const rows: LegacyProposal[] = [], seen = new Set<string>();
  do {const result = await detail(context, 'proposals', 100, offset), page = result.related.proposals;
    if (!result.canReview || page.total > 1000 || total !== null && total !== page.total || current && JSON.stringify(current) !== JSON.stringify(result.transaction)) invalidLegacyDecision('The proposal list changed. Refresh before continuing.');
    total = page.total; current = result.transaction;
    for (const raw of page.rows) {const item = parseLegacyProposal(raw, context.transactionId); if (seen.has(item.id)) invalidLegacyDecision(); seen.add(item.id); rows.push(item);}
    offset += page.rows.length;
  } while (total !== null && offset < total);
  return rows;
}
export function makeLegacyProposal(context: LegacyDecisionContext, snapshot: LegacyDecisionRow, selected: LegacyMember, amount: number, reason: string): LegacyDecisionIntent {
  requireLegacyDecisionWrite(context, 'reconciliations.propose'); const t = transaction(snapshot, context.transactionId);
  if (t.group_status !== 'active' || t.payee_status !== 'active' || t.verification_status === 'rejection_recorded' || !positiveLegacyCount(amount) || amount > Number(t.unallocated_amount_rwf) || selected.group_id !== t.group_id || selected.group_version !== t.group_version || selected.group_title !== t.group_title) invalidLegacyDecision('The current member or payment cannot be proposed.');
  return parseLegacyDecisionIntent({path: `/${context.transactionId}/proposals`, transaction_id: context.transactionId, proposal_id: null, member_public_id: selected.public_id,
    body: {member_user_id: selected.member_user_id, amount_rwf: amount, expected_transaction_version: t.version, expected_member_version: selected.member_version, expected_membership_version: selected.membership_version, expected_payment_identity: selected.payment_identity, expected_source_state: currentSourceState(t), reason: reason.trim()}}, context);
}
export function makeLegacyReview(context: LegacyDecisionContext, snapshot: LegacyDecisionRow, proposal: LegacyProposal, outcome: 'approved' | 'rejected', reason: string): LegacyDecisionIntent {
  requireLegacyDecisionWrite(context, 'reconciliations.review'); const t = transaction(snapshot, context.transactionId);
  if (proposal.transaction_id !== context.transactionId || proposal.group_id !== t.group_id || proposal.status !== 'pending' || proposal.version !== 1 || proposal.proposed_by_admin_id === context.actorId) invalidLegacyDecision('An independent pending proposal is required.');
  return parseLegacyDecisionIntent({path: `/proposals/${proposal.id}/reviews`, transaction_id: context.transactionId, proposal_id: proposal.id, member_public_id: proposal.public_id,
    body: {outcome, expected_proposal_version: 1, expected_transaction_version: t.version, expected_source_state: currentSourceState(t), reason: reason.trim()}}, context);
}
export async function currentLegacyDecision(context: LegacyDecisionContext, input: LegacyDecisionIntent): Promise<LegacyDecisionSource> {
  const intent = parseLegacyDecisionIntent(input, context); checkLegacyDecision(context, legacyDecisionPermission(intent)); const fresh = await detail(context), t = fresh.transaction;
  if (!Object.hasOwn(intent.body, 'expected_source_state') || JSON.stringify(sourceState(intent.body.expected_source_state)) !== JSON.stringify(currentSourceState(t)) || t.version !== intent.body.expected_transaction_version || legacyDecisionKind(intent) === 'propose' && !fresh.canPropose || legacyDecisionKind(intent) === 'review' && !fresh.canReview) invalidLegacyDecision('The payment or source changed. Review it again.');
  const proposal = intent.proposal_id ? (await listLegacyProposals(context)).find(row => row.id === intent.proposal_id) ?? null : null;
  if (intent.proposal_id && (!proposal || proposal.group_id !== t.group_id || proposal.status !== 'pending' || proposal.proposed_by_admin_id === context.actorId)) invalidLegacyDecision('The proposal changed. Review it again.');
  let selected: LegacyMember | null = null;
  if (legacyDecisionKind(intent) === 'propose' || intent.body.outcome === 'approved') {
    if (!intent.member_public_id) invalidLegacyDecision('The member identity is unavailable.');
    const found = await searchLegacyReconciliationMembers(context, intent.member_public_id), memberId = proposal?.member_user_id ?? intent.body.member_user_id;
    selected = found.rows.find(row => row.member_user_id === memberId && row.public_id === intent.member_public_id) ?? null; if (!selected) invalidLegacyDecision('The current member could not be verified.');
  }
  if (legacyDecisionKind(intent) === 'propose') {
    if (!selected || t.group_status !== 'active' || t.payee_status !== 'active' || t.verification_status === 'rejection_recorded' || Number(intent.body.amount_rwf) > Number(t.unallocated_amount_rwf) ||
        selected.member_version !== intent.body.expected_member_version || selected.membership_version !== intent.body.expected_membership_version || JSON.stringify(selected.payment_identity) !== JSON.stringify(paymentIdentity(intent.body.expected_payment_identity))) invalidLegacyDecision('The current member or payment changed.');
  } else if (intent.body.outcome === 'approved') {
    if (!proposal || !selected || t.verification_status !== 'confirmation_recorded' || t.group_status !== 'active' || t.payee_status !== 'active' || t.version !== proposal.transaction_version || t.group_version !== proposal.group_version || t.payee_version !== proposal.payee_version ||
        proposal.payee_identity.payee_id !== t.payee_id || proposal.payee_identity.network !== t.network || proposal.payee_identity.momo_number_or_code !== t.payee_momo || proposal.amount_rwf > Number(t.unallocated_amount_rwf) ||
        selected.member_version !== proposal.member_version || selected.membership_version !== proposal.membership_version || JSON.stringify(selected.payment_identity) !== JSON.stringify(proposal.payment_identity)) invalidLegacyDecision('The current member, receiver or payment changed.');
  }
  const final = await detail(context);
  if (JSON.stringify(final.transaction) !== JSON.stringify(t) || legacyDecisionKind(intent) === 'propose' && !final.canPropose || legacyDecisionKind(intent) === 'review' && !final.canReview) invalidLegacyDecision('The payment changed. Review it again.');
  return {transaction: t, proposal, member: selected};
}
