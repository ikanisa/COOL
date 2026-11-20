import { beforeEach, describe, expect, it } from 'vitest';
import { PENDING_KEY, readPending, retainPending } from '../../src/features/core/pendingAttempt';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { currentLegacyDecision, listLegacyProposals, lookupLegacyDecision, makeLegacyProposal, makeLegacyReview, parseLegacyDecisionIntent, restoreLegacyDecision, retryLegacyDecision, searchLegacyReconciliationMembers, submitLegacyDecision } from '../../src/features/reconciliation/legacyActions';
import { actor, approvedReceipt, context, groupId, identity, key, memberId, memberRow, mockApi, payment, proposal, proposedReceipt, rejectedReceipt, saved, transactionId } from './legacy-fixture';

beforeEach(() => {sessionStorage.clear(); localStorage.clear();});
async function ready(ctx: ReturnType<typeof context>) {const value = await restoreLegacyDecision(ctx); if (value.kind !== 'ready') throw new Error('Expected ready'); return value.revision;}
async function proposalIntent(ctx: ReturnType<typeof context>) {const member = (await searchLegacyReconciliationMembers(ctx, '123456')).rows[0]; return makeLegacyProposal(ctx, payment, member, 400, 'Review member attribution');}
async function reviewIntent(ctx: ReturnType<typeof context>, outcome: 'approved' | 'rejected' = 'approved') {const item = (await listLegacyProposals(ctx))[0]; return makeLegacyReview(ctx, payment, item, outcome, 'Independent reconciliation review');}

describe('legacy reconciliation actions', () => {
  it('validates exact versioned proposal and independent-review requests', async () => {
    const ctx = context(mockApi()), proposed = await proposalIntent(ctx), review = await reviewIntent(ctx);
    expect(proposed.body).toEqual({member_user_id: memberId, amount_rwf: 400, expected_transaction_version: 2, expected_member_version: 1, expected_membership_version: 1, expected_payment_identity: memberRow.payment_identity, expected_source_state: {link_basis: 'public_reference', source_fact_id: payment.source_fact_id}, reason: 'Review member attribution'});
    expect(review.body).toEqual({outcome: 'approved', expected_proposal_version: 1, expected_transaction_version: 2, expected_source_state: {link_basis: 'public_reference', source_fact_id: payment.source_fact_id}, reason: 'Independent reconciliation review'});
    for (const invalid of [{...proposed, body: {...proposed.body, group_id: groupId}}, {...proposed, body: {...proposed.body, amount_rwf: 0}}, {...proposed, body: {...proposed.body, expected_transaction_version: Number.MAX_SAFE_INTEGER}}, {...review, body: {...review.body, expected_proposal_version: 2}}]) expect(() => parseLegacyDecisionIntent(invalid, ctx)).toThrow();
    const own = (await listLegacyProposals(ctx))[0]; expect(() => makeLegacyReview(ctx, payment, {...own, proposed_by_admin_id: actor}, 'approved', 'Independent reconciliation review')).toThrow('independent');
    expect(() => makeLegacyReview({...ctx, identity: {...identity, role: 'staff'}}, payment, own, 'approved', 'Independent reconciliation review')).toThrow('unavailable');
    expect(() => makeLegacyProposal({...ctx, enabled: false}, payment, ({} as never), 400, 'Review member attribution')).toThrow('not enabled');
  });
  it('permits a staff proposal but never a staff review', async () => {
    const api = mockApi(), staffApi = async (path: string, options?: Parameters<typeof api>[1]) => {const result = await api(path, options); return path.startsWith(`reconciliations/${transactionId}?`) ? {...result, can_review: false} : result;};
    const ctx = {...context(staffApi), identity: {...identity, role: 'staff' as const, permissions: ['reconciliations.read', 'reconciliations.propose']}, permissions: ['reconciliations.read', 'reconciliations.propose']};
    expect((await proposalIntent(ctx)).body.member_user_id).toBe(memberId); await expect(listLegacyProposals(ctx)).rejects.toThrow('unavailable');
  });
  it('rechecks current member, source, amount and receiver before the original proposal is sent', async () => {
    const request = mockApi({write: async (path, options) => options?.method ? proposedReceipt : saved(proposedReceipt)}), ctx = context(request), intent = await proposalIntent(ctx), source = await currentLegacyDecision(ctx, intent), revision = await ready(ctx);
    expect((await submitLegacyDecision(ctx, intent, source, revision)).status).toBe('succeeded');
    expect(request).toHaveBeenCalledWith(`reconciliations/${transactionId}/proposals`, {method: 'POST', body: intent.body, idempotencyKey: key});
    expect(source.transaction.source_fact_id).toBe('cccccccc-cccc-4ccc-8ccc-cccccccccccc'); expect((await restoreLegacyDecision(ctx)).kind).toBe('ready');
  });
  it('records independent approval with exact expected versions and no claim of settlement', async () => {
    const request = mockApi({write: async (_path, options) => options?.method ? approvedReceipt : saved(approvedReceipt)}), ctx = context(request), intent = await reviewIntent(ctx), source = await currentLegacyDecision(ctx, intent), revision = await ready(ctx);
    expect((await submitLegacyDecision(ctx, intent, source, revision)).status).toBe('succeeded');
    expect(request).toHaveBeenCalledWith(`reconciliations/proposals/${proposal.id}/reviews`, {method: 'POST', body: intent.body, idempotencyKey: key});
  });
  it('allows independent rejection of a stale member without creating an allocation', async () => {
    const request = mockApi({member: null, write: async (_path, options) => options?.method ? rejectedReceipt : saved(rejectedReceipt)}), ctx = context(request), intent = await reviewIntent(ctx, 'rejected'), source = await currentLegacyDecision(ctx, intent), revision = await ready(ctx);
    expect(source.member).toBeNull(); expect((await submitLegacyDecision(ctx, intent, source, revision)).status).toBe('succeeded');
    expect(request.mock.calls.some(([path]) => path.startsWith('reconciliations/members?'))).toBe(false);
  });
  it('rejects stale identities, source versions, inactive receiver and unconfirmed payment for approvals', async () => {
    for (const options of [{member: {...memberRow, member_version: 2}}, {member: {...memberRow, membership_version: 2}}, {member: {...memberRow, momo_number: '0788123457'}}, {payment: {...payment, payee_version: 2}}, {payment: {...payment, payee_status: 'inactive'}}, {payment: {...payment, verification_status: 'pending'}}, {payment: {...payment, unallocated_amount_rwf: 0, allocated_amount_rwf: 1000, allocation_status: 'allocated'}}]) {
      const ctx = context(mockApi(options)); const intent = await reviewIntent(ctx); await expect(currentLegacyDecision(ctx, intent)).rejects.toThrow();
    }
  });
  it('binds unlinked source state to proposals and reviews and detects a later source link without a transaction version change', async () => {
    const noSource = {...payment, source_link_basis: 'not_recorded', source_fact_id: null, source_kind: null, source_body_sha256: null, source_payload_sha256: null, source_amount_rwf: null, source_network: null}, ctx = context(mockApi({payment: noSource}));
    const selected = (await searchLegacyReconciliationMembers(ctx, '123456')).rows[0], proposed = makeLegacyProposal(ctx, noSource, selected, 400, 'Review member attribution');
    expect(proposed.body.expected_source_state).toEqual({link_basis: 'not_recorded', source_fact_id: null}); expect((await currentLegacyDecision(ctx, proposed)).member?.member_user_id).toBe(memberId);
    const item = (await listLegacyProposals(ctx))[0], approval = makeLegacyReview(ctx, noSource, item, 'approved', 'Independent reconciliation review');
    expect((await currentLegacyDecision(ctx, approval)).proposal?.id).toBe(proposal.id); await expect(currentLegacyDecision(context(mockApi()), approval)).rejects.toThrow('source changed');
  });
  it('rejects mismatched direct and actor-scoped receipts, retaining the original key', async () => {
    const request = mockApi({write: async (_path, options) => options?.method ? proposedReceipt : saved({...proposedReceipt, transaction_id: groupId})}), ctx = context(request), intent = await proposalIntent(ctx), source = await currentLegacyDecision(ctx, intent), revision = await ready(ctx);
    expect(await submitLegacyDecision(ctx, intent, source, revision)).toEqual({status: 'unknown', requestKey: key}); expect((await restoreLegacyDecision(ctx)).kind).toBe('owned');
  });
  it('never automatically replays an unknown write; explicit retry retains its key and exact body', async () => {
    let writes = 0, original: unknown; const request = mockApi({write: async (_path, options) => {if (options?.method) {writes++; expect(options.idempotencyKey).toBe(key); if (writes === 1) {original = options.body; throw new Error('lost');} expect(options.body).toEqual(original); return approvedReceipt;} return writes === 1 ? {status: 'not_found'} : saved(approvedReceipt);}}), ctx = context(request), intent = await reviewIntent(ctx), source = await currentLegacyDecision(ctx, intent), revision = await ready(ctx);
    expect((await submitLegacyDecision(ctx, intent, source, revision)).status).toBe('unknown');
    expect((await readPending(identity, 'legacy-reconciliation-guarded', transactionId))?.request_key).toBe(key); expect(await readPending(identity, 'reconciliation', transactionId)).toBeNull();
    const pending = await restoreLegacyDecision(ctx);
    expect(await lookupLegacyDecision(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true}); expect(writes).toBe(1);
    expect((await retryLegacyDecision(ctx, pending)).status).toBe('succeeded'); expect(writes).toBe(2);
  });
  it('blocks changed source, tampered body, foreign actor/session and stale confirmations', async () => {
    const request = mockApi({write: async (_path, options) => options?.method ? Promise.reject(new Error('lost')) : {status: 'not_found'}}), ctx = context(request), intent = await proposalIntent(ctx), source = await currentLegacyDecision(ctx, intent), revision = await ready(ctx);
    await submitLegacyDecision(ctx, intent, source, revision); const pending = await restoreLegacyDecision(ctx);
    const changed = mockApi({payment: {...payment, source_body_sha256: 'c'.repeat(64)}, write: async () => ({status: 'not_found'})}); await expect(retryLegacyDecision({...ctx, request: changed}, pending)).rejects.toThrow('changed');
    const envelope = JSON.parse(sessionStorage.getItem(PENDING_KEY)!) as {entries: Array<{intent: {body: {reason: string}}}>}; envelope.entries[0].intent.body.reason = 'Altered retained reason'; sessionStorage.setItem(PENDING_KEY, JSON.stringify(envelope));
    const altered = await restoreLegacyDecision(ctx); expect(await lookupLegacyDecision(ctx, altered)).toEqual({status: 'not_found', retryAvailable: false});
    expect(await restoreLegacyDecision({...ctx, identity: {...identity, sessionId: 'different-session'}})).toEqual({kind: 'foreign'});
    sessionStorage.clear(); localStorage.clear(); const old = await ready(ctx);
    await withPendingFence({identity, family: 'reconciliation', resourceId: transactionId, isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async access => {access.reserve(key, access.read().revision); access.clear(key);});
    await expect(submitLegacyDecision(ctx, intent, source, old)).rejects.toThrow('Shared request recovery');
  });
  it('checks an unbound Flutter request and a crash reference, but neither can replay', async () => {
    const request = mockApi({write: async () => ({status: 'not_found'})}), ctx = context(request), intent = await proposalIntent(ctx);
    const oldBody = {...intent.body}; delete oldBody.expected_source_state;
    await retainPending(identity, 'reconciliation', transactionId, key, 'reconciliations.propose', {...intent, body: oldBody}); let pending = await restoreLegacyDecision(ctx);
    expect(await lookupLegacyDecision(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false}); await expect(retryLegacyDecision(ctx, pending)).rejects.toThrow('unresolved');
    sessionStorage.clear(); pending = await restoreLegacyDecision(ctx); expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null}); await expect(retryLegacyDecision(ctx, pending)).rejects.toThrow('intent is unavailable');
  });
  it('blocks a guarded write when an older same-tab Flutter request appears after review', async () => {
    const request = mockApi(), ctx = context(request), intent = await proposalIntent(ctx), source = await currentLegacyDecision(ctx, intent), revision = await ready(ctx), oldBody = {...intent.body}; delete oldBody.expected_source_state;
    await retainPending(identity, 'reconciliation', transactionId, key, 'reconciliations.propose', {...intent, body: oldBody});
    const result = await submitLegacyDecision(ctx, intent, source, revision); expect(result.status).toBe('existing');
    expect(request.mock.calls.every(([, options]) => !options?.method)).toBe(true); expect(await readPending(identity, 'legacy-reconciliation-guarded', transactionId)).toBeNull();
  });
  it('preserves both references and fails closed if guarded and Flutter requests coexist', async () => {
    const request = mockApi({write: async (_path, options) => options?.method ? Promise.reject(new Error('lost')) : {status: 'not_found'}}), ctx = context(request), intent = await proposalIntent(ctx), source = await currentLegacyDecision(ctx, intent), revision = await ready(ctx);
    await submitLegacyDecision(ctx, intent, source, revision); const oldBody = {...intent.body}; delete oldBody.expected_source_state;
    await retainPending(identity, 'reconciliation', transactionId, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'reconciliations.propose', {...intent, body: oldBody});
    await expect(restoreLegacyDecision(ctx)).rejects.toThrow('Multiple original');
    expect(await readPending(identity, 'reconciliation', transactionId)).not.toBeNull(); expect(await readPending(identity, 'legacy-reconciliation-guarded', transactionId)).not.toBeNull();
  });
  it('stops before reservation or dispatch when verification fails or a gate closes', async () => {
    const request = mockApi(), ctx = {...context(request), verifyFresh: async () => false}, intent = await proposalIntent(ctx), source = await currentLegacyDecision(ctx, intent), revision = await ready(ctx);
    await expect(submitLegacyDecision(ctx, intent, source, revision)).rejects.toThrow('verification'); expect((await restoreLegacyDecision(ctx)).kind).toBe('ready');
    const closed = {...ctx, verifyFresh: async () => true, isEnabled: () => false}; await expect(submitLegacyDecision(closed, intent, source, revision)).rejects.toThrow('not enabled');
    expect(request.mock.calls.every(([, options]) => !options?.method)).toBe(true);
  });
});
