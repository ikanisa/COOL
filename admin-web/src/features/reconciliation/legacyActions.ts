/* eslint-disable no-control-regex -- Reject control characters in reviewed payment data. */
import type { AdminRequest } from '../../api/client';
import { clearPending, pendingAuthority, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity } from '../core/pendingAttempt';
import { isId, isObject, isSafeCount } from '../core/contracts';
import { withPendingFence, type FenceAccess, type FenceLock } from '../operations/pendingFence';
import { parseReconciliationDetail } from './contracts';

// Flutter's older schema cannot deserialize the added source-state field. Keep
// guarded React intents in a distinct family while sharing the React fence.
const FENCE_FAMILY = 'reconciliation', FLUTTER_FAMILY = 'reconciliation', GUARDED_FAMILY = 'legacy-reconciliation-guarded', HASH = /^[a-f0-9]{64}$/, MAX = Number.MAX_SAFE_INTEGER;
type Row = Record<string, unknown>;
export type LegacyDecisionKind = 'propose' | 'review';
export interface LegacyDecisionContext {transactionId: string; request: AdminRequest; identity: PendingIdentity; actorId: string; permissions: readonly string[]; financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean; verifyFresh: () => Promise<boolean>; storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;}
export interface LegacyPaymentIdentity {display_name: string; momo_provider: string; momo_number: string; momo_pay_code: string;}
export interface LegacyMember {member_user_id: string; member_version: number; member_type: string; public_id: string; group_id: string; group_title: string; group_version: number; membership_version: number; membership_role: string; payment_identity: LegacyPaymentIdentity;}
export interface LegacyProposal {id: string; transaction_id: string; group_id: string; member_user_id: string; amount_rwf: number; transaction_version: number; member_version: number; membership_version: number; group_version: number; payee_version: number; proposed_by_admin_id: string; operation_request_id: string; reason: string; status: 'pending' | 'approved' | 'rejected'; version: number; public_id: string | null; payment_identity: LegacyPaymentIdentity; payee_identity: {payee_id: string; network: string; momo_number_or_code: string};}
export interface LegacyDecisionIntent {path: string; transaction_id: string; proposal_id: string | null; member_public_id: string | null; body: Record<string, unknown>;}
export interface LegacyDecisionSource {transaction: Row; proposal: LegacyProposal | null; member: LegacyMember | null;}
export type LegacyDecisionPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export interface LegacyDecisionReceipt {requestId: string; proposalId: string; transactionId: string; status: 'pending' | 'approved' | 'rejected'; version: number;}
export type LegacyDecisionLookup = {status: 'succeeded'; receipt: LegacyDecisionReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
export type LegacyDecisionResult = {status: 'succeeded'; receipt: LegacyDecisionReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LegacyDecisionPending};
function fail(message = 'The reconciliation request could not be verified.'): never {throw new Error(message);}
function exact(value: Row, keys: readonly string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function text(value: unknown, min: number, max: number): value is string {return typeof value === 'string' && value === value.trim() && value.length >= min && value.length <= max && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value);}
function positive(value: unknown): value is number {return isSafeCount(value) && value > 0;}
function sourceState(value: unknown): {link_basis: string; source_fact_id: string | null} {
  if (!isObject(value) || !exact(value, ['link_basis', 'source_fact_id']) || !['public_reference', 'reviewed_member_receipt', 'not_recorded'].includes(String(value.link_basis)) ||
      (value.link_basis === 'not_recorded' ? value.source_fact_id !== null : !isId(value.source_fact_id))) fail('The recorded payment source could not be verified.');
  return {link_basis: String(value.link_basis), source_fact_id: value.source_fact_id as string | null};
}
function currentSourceState(value: Row) {return sourceState({link_basis: value.source_link_basis, source_fact_id: value.source_fact_id});}
function kind(intent: LegacyDecisionIntent): LegacyDecisionKind {return intent.proposal_id === null ? 'propose' : 'review';}
function permission(intent: LegacyDecisionIntent) {return kind(intent) === 'propose' ? 'reconciliations.propose' : 'reconciliations.review';}
function check(context: LegacyDecisionContext, action?: string) {
  const expiry = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'transaction_journals' || !isId(context.transactionId) || !isId(context.actorId) || context.identity.id !== context.actorId ||
      !Number.isFinite(expiry) || expiry <= Date.now() || !context.permissions.includes('reconciliations.read') || !context.identity.permissions.includes('reconciliations.read') ||
      action && (!context.permissions.includes(action) || !context.identity.permissions.includes(action) || action === 'reconciliations.review' && context.identity.role === 'staff')) fail('Reconciliation is unavailable to your current account.');
}
function write(context: LegacyDecisionContext, action: string) {check(context, action); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Reconciliation changes are not enabled for this workspace.');}
function paymentIdentity(value: unknown): LegacyPaymentIdentity {
  if (!isObject(value) || !exact(value, ['display_name', 'momo_provider', 'momo_number', 'momo_pay_code']) || !text(value.display_name, 2, 120) || !['', 'mtn_momo', 'airtel_money'].includes(String(value.momo_provider)) ||
      typeof value.momo_number !== 'string' || !/^07[2389]\d{7}$/.test(value.momo_number) || typeof value.momo_pay_code !== 'string' || value.momo_pay_code !== '' && !/^\d{4,9}$/.test(value.momo_pay_code)) fail('The recorded member payment identity could not be verified.');
  return {display_name: value.display_name, momo_provider: String(value.momo_provider), momo_number: value.momo_number, momo_pay_code: value.momo_pay_code};
}
export function parseLegacyDecisionIntent(value: unknown, context: LegacyDecisionContext, expectedPermission?: string): LegacyDecisionIntent {
  if (!isObject(value) || !exact(value, ['path', 'transaction_id', 'proposal_id', 'member_public_id', 'body']) || value.transaction_id !== context.transactionId || !isObject(value.body) ||
      !(value.member_public_id === null || typeof value.member_public_id === 'string' && /^\d{6}$/.test(value.member_public_id))) fail();
  const body = value.body, review = value.proposal_id !== null;
  const extra = Object.hasOwn(body, 'expected_source_state') ? ['expected_source_state'] : [];
  if (review ? !isId(value.proposal_id) || value.path !== `/proposals/${value.proposal_id}/reviews` || !exact(body, ['outcome', 'expected_proposal_version', 'expected_transaction_version', 'reason', ...extra]) ||
      !['approved', 'rejected'].includes(String(body.outcome)) || body.expected_proposal_version !== 1 : value.path !== `/${context.transactionId}/proposals` || !exact(body, ['member_user_id', 'amount_rwf', 'expected_transaction_version', 'expected_member_version', 'expected_membership_version', 'expected_payment_identity', 'reason', ...extra]) ||
      !isId(body.member_user_id) || !positive(body.amount_rwf) || !positive(body.expected_member_version) || !positive(body.expected_membership_version) || value.member_public_id === null) fail();
  if (!positive(body.expected_transaction_version) || body.expected_transaction_version >= MAX || !text(body.reason, 8, 1000)) fail();
  if (extra.length) sourceState(body.expected_source_state);
  if (!review) paymentIdentity(body.expected_payment_identity);
  const intent = value as unknown as LegacyDecisionIntent;
  if (expectedPermission && expectedPermission !== permission(intent)) fail(); return intent;
}
function transaction(value: unknown, id: string): Row {
  if (!isObject(value) || value.id !== id || !isId(value.group_id) || !isId(value.payee_id) || !positive(value.version) || value.version >= MAX || !positive(value.group_version) || !positive(value.payee_version) ||
      !positive(value.amount_rwf) || !isSafeCount(value.allocated_amount_rwf) || !isSafeCount(value.unallocated_amount_rwf) || value.allocated_amount_rwf + value.unallocated_amount_rwf !== value.amount_rwf ||
      !['pending', 'confirmation_recorded', 'rejection_recorded', 'evidence_conflict'].includes(String(value.verification_status)) || !['draft', 'active', 'suspended', 'archived'].includes(String(value.group_status)) || !['active', 'inactive'].includes(String(value.payee_status)) ||
      !['mtn_momo', 'airtel_money'].includes(String(value.network)) || typeof value.payee_momo !== 'string' || !/^\d{4,12}$/.test(value.payee_momo) || !text(value.group_title, 1, 200) || !text(value.payee_name, 1, 200) || !text(value.provider_reference, 1, 200) ||
      value.rail !== 'rwanda_momo' || value.currency !== 'RWF' || value.settlement_status !== 'not_asserted') fail('The current payment could not be verified.');
  const keys = ['id', 'version', 'group_id', 'group_title', 'group_status', 'group_version', 'payee_id', 'payee_name', 'payee_status', 'payee_version', 'payee_momo', 'network', 'provider_reference', 'amount_rwf', 'allocated_amount_rwf', 'unallocated_amount_rwf', 'verification_status', 'rail', 'currency', 'settlement_status'];
  if ('source_link_basis' in value) {
    if (!['public_reference', 'reviewed_member_receipt', 'not_recorded'].includes(String(value.source_link_basis)) || !(value.source_fact_id === null || isId(value.source_fact_id)) ||
        !(value.source_kind === null || ['receiver', 'member'].includes(String(value.source_kind))) || value.provider_confirmation !== false ||
        !(value.source_body_sha256 === null || typeof value.source_body_sha256 === 'string' && HASH.test(value.source_body_sha256)) || !(value.source_payload_sha256 === null || typeof value.source_payload_sha256 === 'string' && HASH.test(value.source_payload_sha256))) fail('The recorded payment source could not be verified.');
    const state = sourceState({link_basis: value.source_link_basis, source_fact_id: value.source_fact_id});
    if (state.link_basis === 'not_recorded' ? value.source_kind !== null || value.source_review_id !== null || value.source_body_sha256 !== null || value.source_payload_sha256 !== null || value.source_amount_rwf !== null || value.source_network !== null :
        !['receiver', 'member'].includes(String(value.source_kind)) || state.link_basis === 'reviewed_member_receipt' && (value.source_kind !== 'member' || !isId(value.source_review_id)) ||
        state.link_basis === 'public_reference' && value.source_review_id !== null || typeof value.source_body_sha256 !== 'string' || typeof value.source_payload_sha256 !== 'string' ||
        value.source_amount_rwf !== value.amount_rwf || value.source_network !== value.network) fail('The recorded payment source could not be verified.');
    keys.push('source_link_basis', 'source_fact_id', 'source_kind', 'source_review_id', 'source_body_sha256', 'source_payload_sha256', 'source_amount_rwf', 'source_network', 'payer_source_match_status', 'provider_confirmation');
  }
  return Object.fromEntries(keys.map(key => [key, value[key]]));
}
function member(value: unknown, groupId: string): LegacyMember {
  const keys = ['member_user_id', 'member_version', 'member_type', 'public_id', 'display_name', 'momo_provider', 'momo_number', 'momo_pay_code', 'membership_version', 'membership_role', 'group_id', 'group_title', 'group_version', 'payment_identity'];
  if (!isObject(value) || !exact(value, keys) || !isId(value.member_user_id) || value.group_id !== groupId || !positive(value.member_version) || !positive(value.membership_version) || !positive(value.group_version) ||
      !['app', 'direct'].includes(String(value.member_type)) || typeof value.public_id !== 'string' || !/^\d{6}$/.test(value.public_id) || !text(value.group_title, 1, 200) || !['owner', 'admin', 'receiver', 'member', 'contributor', 'viewer'].includes(String(value.membership_role))) fail('The member could not be verified.');
  const identity = paymentIdentity(value.payment_identity); if (Object.entries(identity).some(([key, item]) => value[key] !== item)) fail('The member could not be verified.');
  return {member_user_id: value.member_user_id, member_version: value.member_version, member_type: String(value.member_type), public_id: value.public_id, group_id: groupId, group_title: value.group_title, group_version: value.group_version, membership_version: value.membership_version, membership_role: String(value.membership_role), payment_identity: identity};
}
export function parseLegacyProposal(value: unknown, transactionId: string): LegacyProposal {
  if (!isObject(value) || !isId(value.id) || value.transaction_id !== transactionId || !isId(value.group_id) || !isId(value.member_user_id) || !isId(value.proposed_by_admin_id) || !isId(value.operation_request_id) ||
      !['amount_rwf', 'transaction_version', 'member_version', 'membership_version', 'group_version', 'payee_version'].every(key => positive(value[key])) || !text(value.reason, 8, 1000) ||
      !['pending', 'approved', 'rejected'].includes(String(value.status)) || value.version !== (value.status === 'pending' ? 1 : 2) || !(value.public_id === null || typeof value.public_id === 'string' && /^\d{6}$/.test(value.public_id)) || !isObject(value.payee_identity)) fail('The proposal could not be verified.');
  const payee = value.payee_identity;
  if (!exact(payee, ['payee_id', 'network', 'momo_number_or_code']) || !isId(payee.payee_id) || !['mtn_momo', 'airtel_money'].includes(String(payee.network)) || typeof payee.momo_number_or_code !== 'string' || !/^\d{4,12}$/.test(payee.momo_number_or_code)) fail('The proposal could not be verified.');
  if (value.status === 'pending' ? ['review_id', 'allocation_id', 'reviewed_by_admin_id', 'review_reason', 'reviewed_at'].some(key => value[key] !== null) : !isId(value.review_id) || !isId(value.reviewed_by_admin_id) || value.reviewed_by_admin_id === value.proposed_by_admin_id || !positive(value.reviewed_at) || !text(value.review_reason, 8, 1000) || (value.status === 'approved' ? !isId(value.allocation_id) : value.allocation_id !== null)) fail('The proposal could not be verified.');
  return {id: value.id, transaction_id: transactionId, group_id: value.group_id, member_user_id: value.member_user_id, amount_rwf: value.amount_rwf as number, transaction_version: value.transaction_version as number, member_version: value.member_version as number, membership_version: value.membership_version as number, group_version: value.group_version as number, payee_version: value.payee_version as number, proposed_by_admin_id: value.proposed_by_admin_id, operation_request_id: value.operation_request_id, reason: value.reason, status: value.status as LegacyProposal['status'], version: value.version as number, public_id: value.public_id as string | null, payment_identity: paymentIdentity(value.payment_identity), payee_identity: {payee_id: payee.payee_id, network: String(payee.network), momo_number_or_code: payee.momo_number_or_code}};
}
async function detail(context: LegacyDecisionContext, relation?: string, limit = 25, offset = 0) {
  check(context); const query = new URLSearchParams({limit: String(limit), offset: String(offset), ...(relation ? {related: relation} : {})});
  const response = await context.request(`reconciliations/${context.transactionId}?${query}`); check(context);
  const parsed = parseReconciliationDetail(response, 'transaction_journals', context.transactionId, context.actorId, null, context.permissions, context.identity.role, relation, limit, offset);
  return {...parsed, transaction: transaction(parsed.resource, context.transactionId)};
}
export async function searchLegacyReconciliationMembers(context: LegacyDecisionContext, search: string, offset = 0) {
  check(context); if (!text(search.trim(), 0, 200) || !Number.isInteger(offset) || offset < 0 || offset > 2147483647) fail();
  const current = await detail(context), query = new URLSearchParams({transaction_id: context.transactionId, search: search.trim(), limit: '25', offset: String(offset)}), body = await context.request(`reconciliations/members?${query}`); check(context);
  if (!exact(body, ['rows', 'total', 'limit', 'offset', 'next_offset']) || !Array.isArray(body.rows) || !isSafeCount(body.total) || body.limit !== 25 || body.offset !== offset || body.rows.length !== Math.max(0, Math.min(25, body.total - offset)) || body.next_offset !== (offset + body.rows.length < body.total ? offset + body.rows.length : null)) fail();
  const rows = body.rows.map(row => member(row, String(current.transaction.group_id)));
  if (new Set(rows.map(row => row.member_user_id)).size !== rows.length || rows.some(row => row.group_title !== current.transaction.group_title || row.group_version !== current.transaction.group_version)) fail();
  return {rows, total: body.total, offset, nextOffset: body.next_offset as number | null};
}
export async function listLegacyProposals(context: LegacyDecisionContext) {
  check(context, 'reconciliations.review'); let offset = 0, total: number | null = null, current: Row | null = null; const rows: LegacyProposal[] = [], seen = new Set<string>();
  do {const result = await detail(context, 'proposals', 100, offset), page = result.related.proposals;
    if (!result.canReview || page.total > 1000 || total !== null && total !== page.total || current && JSON.stringify(current) !== JSON.stringify(result.transaction)) fail('The proposal list changed. Refresh before continuing.');
    total = page.total; current = result.transaction;
    for (const raw of page.rows) {const item = parseLegacyProposal(raw, context.transactionId); if (seen.has(item.id)) fail(); seen.add(item.id); rows.push(item);}
    offset += page.rows.length;
  } while (total !== null && offset < total);
  return rows;
}
export function makeLegacyProposal(context: LegacyDecisionContext, snapshot: Row, selected: LegacyMember, amount: number, reason: string): LegacyDecisionIntent {
  write(context, 'reconciliations.propose'); const t = transaction(snapshot, context.transactionId);
  if (t.group_status !== 'active' || t.payee_status !== 'active' || t.verification_status === 'rejection_recorded' || !positive(amount) || amount > Number(t.unallocated_amount_rwf) || selected.group_id !== t.group_id || selected.group_version !== t.group_version || selected.group_title !== t.group_title) fail('The current member or payment cannot be proposed.');
  return parseLegacyDecisionIntent({path: `/${context.transactionId}/proposals`, transaction_id: context.transactionId, proposal_id: null, member_public_id: selected.public_id,
    body: {member_user_id: selected.member_user_id, amount_rwf: amount, expected_transaction_version: t.version, expected_member_version: selected.member_version, expected_membership_version: selected.membership_version, expected_payment_identity: selected.payment_identity, expected_source_state: currentSourceState(t), reason: reason.trim()}}, context);
}
export function makeLegacyReview(context: LegacyDecisionContext, snapshot: Row, proposal: LegacyProposal, outcome: 'approved' | 'rejected', reason: string): LegacyDecisionIntent {
  write(context, 'reconciliations.review'); const t = transaction(snapshot, context.transactionId);
  if (proposal.transaction_id !== context.transactionId || proposal.group_id !== t.group_id || proposal.status !== 'pending' || proposal.version !== 1 || proposal.proposed_by_admin_id === context.actorId) fail('An independent pending proposal is required.');
  return parseLegacyDecisionIntent({path: `/proposals/${proposal.id}/reviews`, transaction_id: context.transactionId, proposal_id: proposal.id, member_public_id: proposal.public_id,
    body: {outcome, expected_proposal_version: 1, expected_transaction_version: t.version, expected_source_state: currentSourceState(t), reason: reason.trim()}}, context);
}
export async function currentLegacyDecision(context: LegacyDecisionContext, input: LegacyDecisionIntent): Promise<LegacyDecisionSource> {
  const intent = parseLegacyDecisionIntent(input, context); check(context, permission(intent)); const fresh = await detail(context), t = fresh.transaction;
  if (!Object.hasOwn(intent.body, 'expected_source_state') || JSON.stringify(sourceState(intent.body.expected_source_state)) !== JSON.stringify(currentSourceState(t)) || t.version !== intent.body.expected_transaction_version || kind(intent) === 'propose' && !fresh.canPropose || kind(intent) === 'review' && !fresh.canReview) fail('The payment or source changed. Review it again.');
  const proposal = intent.proposal_id ? (await listLegacyProposals(context)).find(row => row.id === intent.proposal_id) ?? null : null;
  if (intent.proposal_id && (!proposal || proposal.group_id !== t.group_id || proposal.status !== 'pending' || proposal.proposed_by_admin_id === context.actorId)) fail('The proposal changed. Review it again.');
  let selected: LegacyMember | null = null;
  if (kind(intent) === 'propose' || intent.body.outcome === 'approved') {
    if (!intent.member_public_id) fail('The member identity is unavailable.');
    const found = await searchLegacyReconciliationMembers(context, intent.member_public_id), memberId = proposal?.member_user_id ?? intent.body.member_user_id;
    selected = found.rows.find(row => row.member_user_id === memberId && row.public_id === intent.member_public_id) ?? null; if (!selected) fail('The current member could not be verified.');
  }
  if (kind(intent) === 'propose') {
    if (!selected || t.group_status !== 'active' || t.payee_status !== 'active' || t.verification_status === 'rejection_recorded' || Number(intent.body.amount_rwf) > Number(t.unallocated_amount_rwf) ||
        selected.member_version !== intent.body.expected_member_version || selected.membership_version !== intent.body.expected_membership_version || JSON.stringify(selected.payment_identity) !== JSON.stringify(paymentIdentity(intent.body.expected_payment_identity))) fail('The current member or payment changed.');
  } else if (intent.body.outcome === 'approved') {
    if (!proposal || !selected || t.verification_status !== 'confirmation_recorded' || t.group_status !== 'active' || t.payee_status !== 'active' || t.version !== proposal.transaction_version || t.group_version !== proposal.group_version || t.payee_version !== proposal.payee_version ||
        proposal.payee_identity.payee_id !== t.payee_id || proposal.payee_identity.network !== t.network || proposal.payee_identity.momo_number_or_code !== t.payee_momo || proposal.amount_rwf > Number(t.unallocated_amount_rwf) ||
        selected.member_version !== proposal.member_version || selected.membership_version !== proposal.membership_version || JSON.stringify(selected.payment_identity) !== JSON.stringify(proposal.payment_identity)) fail('The current member, receiver or payment changed.');
  }
  const final = await detail(context);
  if (JSON.stringify(final.transaction) !== JSON.stringify(t) || kind(intent) === 'propose' && !final.canPropose || kind(intent) === 'review' && !final.canReview) fail('The payment changed. Review it again.');
  return {transaction: t, proposal, member: selected};
}

function storage(context: LegacyDecisionContext): Storage {try {return context.storage ?? sessionStorage;} catch {return fail('Recovery storage is unavailable.');}}
function bindingKey(context: LegacyDecisionContext) {return `collect.admin.legacy-reconciliation.context.v1:${context.transactionId}`;}
async function binding(context: LegacyDecisionContext, requestKey: string, attempt?: PendingAttempt): Promise<{kind: 'valid'; sourceHash: string} | {kind: 'missing' | 'foreign' | 'mismatch'}> {
  let raw: string | null; try {raw = storage(context).getItem(bindingKey(context));} catch {return fail('Recovery storage is unavailable.');}
  if (raw === null) return {kind: 'missing'}; if (raw.length > 1000) fail(); let value: unknown; try {value = JSON.parse(raw);} catch {return fail();}
  if (!isObject(value) || !exact(value, ['version', 'request_key', 'authority_sha256', 'intent_sha256', 'source_sha256', 'model']) || value.version !== 1 || value.request_key !== requestKey || value.model !== 'transaction_journals' ||
      typeof value.authority_sha256 !== 'string' || !HASH.test(value.authority_sha256) || typeof value.intent_sha256 !== 'string' || !HASH.test(value.intent_sha256) || typeof value.source_sha256 !== 'string' || !HASH.test(value.source_sha256)) fail();
  if (value.authority_sha256 !== await pendingAuthority(context.identity)) return {kind: 'foreign'};
  if (attempt && value.intent_sha256 !== await sha256Text(JSON.stringify(attempt.intent))) return {kind: 'mismatch'};
  return {kind: 'valid', sourceHash: value.source_sha256};
}
async function saveBinding(context: LegacyDecisionContext, attempt: PendingAttempt, source: LegacyDecisionSource) {
  if ((await binding(context, attempt.request_key)).kind !== 'missing') fail(); const store = storage(context), name = bindingKey(context);
  const raw = JSON.stringify({version: 1, request_key: attempt.request_key, authority_sha256: await pendingAuthority(context.identity), intent_sha256: await sha256Text(JSON.stringify(attempt.intent)), source_sha256: await sha256Text(JSON.stringify(source)), model: 'transaction_journals'}); check(context);
  try {store.setItem(name, raw); if (store.getItem(name) !== raw) fail();} catch {fail('Recovery storage is unavailable.');} check(context);
}
async function clearBinding(context: LegacyDecisionContext, requestKey: string) {
  const value = await binding(context, requestKey); if (value.kind === 'foreign') fail(); if (value.kind === 'missing') return;
  const store = storage(context), name = bindingKey(context); check(context); try {store.removeItem(name); if (store.getItem(name) !== null) fail();} catch {fail('Recovery storage is unavailable.');}
}
async function fence<T>(context: LegacyDecisionContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {return withPendingFence({identity: context.identity, family: FENCE_FAMILY, resourceId: context.transactionId, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);}
async function restoreUnderFence(context: LegacyDecisionContext, access: FenceAccess): Promise<LegacyDecisionPending> {
  check(context); const shared = access.read(); if (shared.kind === 'foreign') return {kind: 'foreign'};
  const guarded = await readPending(context.identity, GUARDED_FAMILY, context.transactionId, context.storage), flutter = await readPending(context.identity, FLUTTER_FAMILY, context.transactionId, context.storage);
  if (guarded && flutter) fail('Multiple original reconciliation requests need review.');
  const attempt = guarded ?? flutter;
  if (attempt && (![GUARDED_FAMILY, FLUTTER_FAMILY].includes(attempt.family) || attempt.resource_id !== context.transactionId || !isId(attempt.request_key) || !['reconciliations.propose', 'reconciliations.review'].includes(attempt.permission))) fail();
  const owner = attempt ? await binding(context, attempt.request_key, attempt) : {kind: 'missing' as const}; check(context);
  if (owner.kind === 'foreign') return {kind: 'foreign'};
  if (shared.kind === 'owned') {if (attempt && attempt.request_key !== shared.requestKey) fail(); return {kind: 'owned', requestKey: shared.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, shared.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};}
  return {kind: 'ready', revision: shared.revision};
}
export async function restoreLegacyDecision(context: LegacyDecisionContext): Promise<LegacyDecisionPending> {check(context); return fence(context, access => restoreUnderFence(context, access));}
async function clear(context: LegacyDecisionContext, access: FenceAccess, pending: Extract<LegacyDecisionPending, {kind: 'owned'}>) {
  await clearBinding(context, pending.requestKey); if (pending.attempt) await clearPending(context.identity, pending.attempt.family, context.transactionId, pending.requestKey, context.storage); check(context); access.clear(pending.requestKey);
}
function receipt(context: LegacyDecisionContext, value: unknown, attempt: PendingAttempt | null): LegacyDecisionReceipt {
  if (!isObject(value) || !isId(value.request_id) || value.status !== 'succeeded' || value.resource_type !== 'reconciliation_proposals' || !isId(value.resource_id) || value.transaction_id !== context.transactionId || !['pending', 'approved', 'rejected'].includes(String(value.proposal_status))) fail('The original reconciliation receipt could not be verified.');
  const reviewed = value.proposal_status !== 'pending', keys = ['request_id', 'status', 'resource_type', 'resource_id', 'transaction_id', 'version', 'proposal_status', ...(reviewed ? ['review_id', 'allocation_id', 'transaction_version', 'settlement_status'] : [])];
  if (!exact(value, keys) || value.version !== (reviewed ? 2 : 1) || reviewed && (!isId(value.review_id) || !positive(value.transaction_version) || value.settlement_status !== 'not_asserted' || (value.proposal_status === 'approved' ? !isId(value.allocation_id) : value.allocation_id !== null))) fail('The original reconciliation receipt could not be verified.');
  if (attempt) {const original = parseLegacyDecisionIntent(attempt.intent, context, attempt.permission);
    if (reviewed !== (kind(original) === 'review') || reviewed && (value.resource_id !== original.proposal_id || value.proposal_status !== original.body.outcome || value.transaction_version !== Number(original.body.expected_transaction_version) + (original.body.outcome === 'approved' ? 1 : 0))) fail('The original reconciliation receipt could not be verified.');}
  return {requestId: value.request_id, proposalId: value.resource_id, transactionId: context.transactionId, status: value.proposal_status as LegacyDecisionReceipt['status'], version: value.version as number};
}
async function lookupUnderFence(context: LegacyDecisionContext, pending: Extract<LegacyDecisionPending, {kind: 'owned'}>): Promise<LegacyDecisionLookup> {
  check(context); const body = await context.request(`reconciliations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) {
    let retryAvailable = false;
    if (pending.attempt?.family === GUARDED_FAMILY && (await binding(context, pending.requestKey, pending.attempt)).kind === 'valid') {try {const intent = parseLegacyDecisionIntent(pending.attempt.intent, context, pending.attempt.permission); check(context, permission(intent)); retryAvailable = Object.hasOwn(intent.body, 'expected_source_state');} catch { /* Keep other attempts check-only. */ }}
    return {status: 'not_found', retryAvailable};
  }
  if (!exact(body, ['status', 'request_id', 'receipt']) || !isId(body.request_id)) fail('The original reconciliation receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded' || pending.attempt && (await binding(context, pending.requestKey, pending.attempt)).kind === 'mismatch') fail('The original reconciliation receipt could not be verified.');
  const saved = receipt(context, body.receipt, pending.attempt); if (saved.requestId !== body.request_id) fail('The original reconciliation receipt could not be verified.'); return {status: 'succeeded', receipt: saved};
}
async function finish(context: LegacyDecisionContext, access: FenceAccess, pending: Extract<LegacyDecisionPending, {kind: 'owned'}>, response: unknown): Promise<LegacyDecisionResult> {
  const direct = receipt(context, response, pending.attempt), original = await lookupUnderFence(context, pending);
  if (original.status !== 'succeeded' || JSON.stringify(direct) !== JSON.stringify(original.receipt)) fail('The original reconciliation receipt could not be verified.');
  await clear(context, access, pending); return {status: 'succeeded', receipt: direct};
}
export async function submitLegacyDecision(context: LegacyDecisionContext, input: LegacyDecisionIntent, source: LegacyDecisionSource, observedRevision: string): Promise<LegacyDecisionResult> {
  const intent = parseLegacyDecisionIntent(input, context); write(context, permission(intent));
  return fence(context, async access => {
    const existing = await restoreUnderFence(context, access); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const latest = await currentLegacyDecision(context, intent); if (JSON.stringify(latest) !== JSON.stringify(source)) fail('The payment or review changed. Review it again.');
    if (!await context.verifyFresh()) fail('Complete current account verification before recording reconciliation.'); write(context, permission(intent));
    const current = await restoreUnderFence(context, access); if (current.kind !== 'ready') return {status: 'existing', pending: current};
    const requestKey = (context.createKey ?? (() => crypto.randomUUID()))(); if (!isId(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, GUARDED_FAMILY, context.transactionId, requestKey, permission(intent), {...intent}, context.storage); await saveBinding(context, attempt, latest);}
    catch (error) {if (context.isCurrent()) {try {const retained = await readPending(context.identity, GUARDED_FAMILY, context.transactionId, context.storage); if (retained?.request_key === requestKey) await clearPending(context.identity, GUARDED_FAMILY, context.transactionId, requestKey, context.storage); await clearBinding(context, requestKey); access.clear(requestKey);} catch { /* Preserve the fence when cleanup is uncertain. */ }} throw error;}
    const pending: Extract<LegacyDecisionPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey};
    try {const response = await context.request(`reconciliations${intent.path}`, {method: 'POST', body: intent.body, idempotencyKey: requestKey}); check(context, permission(intent)); return await finish(context, access, pending, response);}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLegacyDecision(context: LegacyDecisionContext, pending: LegacyDecisionPending): Promise<LegacyDecisionLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return fence(context, async access => {const saved = await restoreUnderFence(context, access); if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey) fail(); const result = await lookupUnderFence(context, saved); if (result.status === 'succeeded') await clear(context, access, saved); return result;});
}
export async function retryLegacyDecision(context: LegacyDecisionContext, pending: LegacyDecisionPending): Promise<LegacyDecisionResult> {
  if (pending.kind !== 'owned' || !pending.attempt) fail('The original reconciliation intent is unavailable.');
  const original = parseLegacyDecisionIntent(pending.attempt.intent, context, pending.attempt.permission); write(context, permission(original));
  return fence(context, async access => {
    const saved = await restoreUnderFence(context, access); if (saved.kind !== 'owned' || !saved.attempt || saved.requestKey !== pending.requestKey || JSON.stringify(saved.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail();
    const status = await lookupUnderFence(context, saved); if (status.status === 'succeeded') {await clear(context, access, saved); return {status: 'succeeded', receipt: status.receipt};}
    if (status.status !== 'not_found' || !status.retryAvailable) fail('The original reconciliation request remains unresolved.');
    const intent = parseLegacyDecisionIntent(saved.attempt.intent, context, saved.attempt.permission), owner = await binding(context, saved.requestKey, saved.attempt), latest = await currentLegacyDecision(context, intent);
    if (owner.kind !== 'valid' || await sha256Text(JSON.stringify(latest)) !== owner.sourceHash) fail('The original payment or review changed. Check the request before continuing.');
    if (!await context.verifyFresh()) fail('Complete current account verification before retrying reconciliation.'); write(context, permission(intent));
    try {const response = await context.request(`reconciliations${intent.path}`, {method: 'POST', body: intent.body, idempotencyKey: saved.requestKey}); check(context, permission(intent)); return await finish(context, access, saved, response);}
    catch {return {status: 'unknown', requestKey: saved.requestKey};}
  });
}
