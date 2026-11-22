import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import { parseMomoDetail } from '../../src/features/operations/momoContracts';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { loadMomoCandidates, parseMomoCandidates, restoreMomoAssignment, retryMomoAssignment, submitMomoAssignment, type MomoAssignmentContext, type MomoCandidate } from '../../src/features/operations/momoAssignment';

const txId = '11111111-1111-4111-8111-111111111111', actor = '22222222-2222-4222-8222-222222222222', account = '33333333-3333-4333-8333-333333333333', group = '44444444-4444-4444-8444-444444444444', member = '55555555-5555-4555-8555-555555555555', sourceId = '66666666-6666-4666-8666-666666666666', key = '77777777-7777-4777-8777-777777777777', payment = '88888888-8888-4888-8888-888888888888';
const time = '2026-10-18T08:00:00.000Z';
const tx = {id: txId, receiving_account_id: account, provider_transaction_id: 'MOMO-SYNTHETIC-001', recipient_name: 'Synthetic receiver', public_code: '123456', payer_name: 'Synthetic payer', payer_last3: '007', member_name: null, group_name: null, group_id: null, beneficiary_member_id: null, payment_id: null, amount_minor: 5000, has_conflict: 0, credited_amount_minor: 0, version: 1, currency: 'RWF', status: 'needs_allocation', event_kind: 'incoming_receipt', allocation_state: 'unallocated', transaction_at: time, created_at: time};
const source = {raw_sms_id: sourceId, relation: 'accepted', outcome: 'accepted', parser_version: 'v1', created_at: time};
const rawDetail = {transaction: tx, sources: [source], conflicting_attempt_ids: []};
const detail = parseMomoDetail(rawDetail, txId);
const candidate: MomoCandidate = {group_id: group, group_name: 'Synthetic group', member_id: member, member_name: 'Synthetic member', member_public_id: '123456'};
const page = {rows: [candidate], total: 1, limit: 25, offset: 0};
const intent = {group_id: group, member_id: member, expected_version: 1, reason: 'Review source attribution'};
const receipt = {transaction_id: txId, payment_id: payment, status: 'awaiting_review', version: 2, requires_independent_review: true};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.com', role: 'admin', permissions: ['payments.read', 'payments.write', 'users.read', 'collections.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: MomoAssignmentContext['request']): MomoAssignmentContext {return {request, identity: identity(), principalId: actor, financialModel: 'canonical_evidence_ledger', detail, enabled: true, isCurrent: () => true, verifyFresh: async () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: MomoAssignmentContext) {const state = await restoreMomoAssignment(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('MoMo beneficiary assignment', () => {
  it('validates bounded, distinct, eligible destination pages', () => {
    expect(parseMomoCandidates(page, 0).rows[0]).toEqual(candidate);
    expect(() => parseMomoCandidates({...page, offset: 25}, 0)).toThrow();
    expect(() => parseMomoCandidates({...page, total: 2}, 0)).toThrow();
    expect(() => parseMomoCandidates({...page, rows: [candidate, candidate], total: 2}, 0)).toThrow();
    expect(() => parseMomoCandidates({...page, rows: [{...candidate, member_public_id: 'invalid'}]}, 0)).toThrow();
  });
  it('requires the gate, actual read/write permissions, canonical model and fresh verification', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitMomoAssignment({...ctx, enabled: false}, candidate, intent.reason, '')).rejects.toThrow('not enabled');
    await expect(submitMomoAssignment({...ctx, identity: {...ctx.identity, permissions: ['payments.read', 'payments.write', 'users.read']}}, candidate, intent.reason, '')).rejects.toThrow('destinations are unavailable');
    await expect(submitMomoAssignment({...ctx, financialModel: 'transaction_journals'}, candidate, intent.reason, '')).rejects.toThrow('unavailable');
    const missingProof = {...ctx, verifyFresh: async () => false, request: vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce(page)};
    const observed = await revision(missingProof);
    await expect(submitMomoAssignment(missingProof, candidate, intent.reason, observed)).rejects.toThrow('current verification');
    expect(missingProof.request).toHaveBeenCalledTimes(2);
    expect(await readPending(identity(), 'momo-assign', txId)).toBeNull();
    expect(request).not.toHaveBeenCalled();
  });
  it('does not dispatch when the gate closes during verification', async () => {
    let enabled = true;
    const request = vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce(page);
    const ctx = {...context(request), isEnabled: () => enabled, verifyFresh: async () => {enabled = false; return true;}}, observed = await revision(ctx);
    await expect(submitMomoAssignment(ctx, candidate, intent.reason, observed)).rejects.toThrow('not enabled');
    expect(request).toHaveBeenCalledTimes(2);
    expect(await readPending(identity(), 'momo-assign', txId)).toBeNull();
  });
  it('rejects reversal, non-unallocated or missing event provenance before requesting destinations', async () => {
    const request = vi.fn(), base = context(request);
    for (const fields of [{event_kind: 'reversal'}, {allocation_state: 'linked'}, {event_kind: undefined}]) {
      const ctx = {...base, detail: parseMomoDetail({...rawDetail, transaction: {...tx, ...fields}}, txId)};
      const observed = await revision(ctx);
      await expect(submitMomoAssignment(ctx, candidate, intent.reason, observed)).rejects.toThrow('no longer available');
    }
    expect(request).not.toHaveBeenCalled();
  });
  it('never posts if principal-binding storage is unavailable', async () => {
    const storage: Storage = {get length() {return sessionStorage.length;}, clear() {sessionStorage.clear();}, getItem(k) {return sessionStorage.getItem(k);}, key(i) {return sessionStorage.key(i);}, removeItem(k) {sessionStorage.removeItem(k);}, setItem(k, v) {if (k.startsWith('collect.admin.momo-assign.owner.v1:')) throw new Error('blocked'); sessionStorage.setItem(k, v);}};
    const request = vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce(page);
    const ctx = {...context(request), storage}, observed = await revision(ctx);
    await expect(submitMomoAssignment(ctx, candidate, intent.reason, observed)).rejects.toThrow();
    expect(request).toHaveBeenCalledTimes(2);
    expect(await readPending(identity(), 'momo-assign', txId)).toBeNull();
  });
  it('rechecks source and destination, saves original intent, and distinguishes independent review from settlement', async () => {
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'POST') {
        expect(path).toBe(`momo/transactions/${txId}/assign`);
        expect(options).toEqual({method: 'POST', body: intent, idempotencyKey: key});
        expect(await readPending(identity(), 'momo-assign', txId)).toMatchObject({request_key: key, intent});
        return receipt;
      }
      return path.includes('/candidates?') ? page : rawDetail;
    });
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitMomoAssignment(ctx, candidate, intent.reason, observed)).toEqual({status: 'succeeded', receipt: {transactionId: txId, paymentId: payment, status: 'awaiting_review', version: 2, requiresIndependentReview: true}});
    expect(await readPending(identity(), 'momo-assign', txId)).toBeNull();
    expect(request).toHaveBeenCalledTimes(3);
  });
  it('rejects changed source, destination or version before creating a request', async () => {
    const changedSource = {...rawDetail, sources: [{...source, raw_sms_id: payment}]};
    const request = vi.fn().mockResolvedValueOnce(changedSource);
    const ctx = context(request), observed = await revision(ctx);
    await expect(submitMomoAssignment(ctx, candidate, intent.reason, observed)).rejects.toThrow('source changed');
    expect(request).toHaveBeenCalledTimes(1);
    expect(await readPending(identity(), 'momo-assign', txId)).toBeNull();
    const changedCandidate = vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce({...page, rows: [{...candidate, group_name: 'Different group'}]});
    await expect(submitMomoAssignment({...ctx, request: changedCandidate}, candidate, intent.reason, observed)).rejects.toThrow('destination changed');
    expect(changedCandidate).toHaveBeenCalledTimes(2);
  });
  it('retains unknown result and explicitly retries the same key and intent without inventing a status lookup', async () => {
    const request = vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce(page).mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce(receipt);
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitMomoAssignment(ctx, candidate, intent.reason, observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreMomoAssignment(ctx);
    expect(pending).toMatchObject({kind: 'owned', requestKey: key});
    expect((await retryMomoAssignment(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(4, `momo/transactions/${txId}/assign`, {method: 'POST', body: intent, idempotencyKey: key});
    expect(request).toHaveBeenCalledTimes(4);
    expect(await restoreMomoAssignment(ctx)).toMatchObject({kind: 'ready'});
  });
  it('keeps the checkpoint private when destination-search permissions change', async () => {
    const request = vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce(page).mockRejectedValueOnce(new Error('lost'));
    const ctx = context(request), observed = await revision(ctx);
    await submitMomoAssignment(ctx, candidate, intent.reason, observed);
    // The session authority changes when permissions change, so its persisted fence
    // remains foreign until the original session is restored. No new key is used.
    const changed = {...ctx, identity: {...ctx.identity, permissions: ['payments.read', 'payments.write']}, request: vi.fn()};
    expect(await restoreMomoAssignment(changed)).toEqual({kind: 'foreign'});
    expect(changed.request).not.toHaveBeenCalled();
  });
  it('binds replay to the same principal and refuses unbound older checkpoints', async () => {
    const request = vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce(page).mockRejectedValueOnce(new Error('lost'));
    const ctx = context(request), observed = await revision(ctx);
    await submitMomoAssignment(ctx, candidate, intent.reason, observed);
    const changed = {...ctx, principalId: payment, request: vi.fn()};
    expect(await restoreMomoAssignment(changed)).toEqual({kind: 'foreign'});
    expect(changed.request).not.toHaveBeenCalled();
    sessionStorage.clear(); localStorage.clear();
    const {retainPending} = await import('../../src/features/core/pendingAttempt');
    await retainPending(identity(), 'momo-assign', txId, key, 'payments.write', intent);
    const unbound = await restoreMomoAssignment(ctx);
    expect(unbound).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryMomoAssignment(ctx, unbound)).rejects.toThrow('intent is unavailable');
  });
  it('retains the original reference when receipt fields are inconsistent or verification expires', async () => {
    const request = vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce(page).mockResolvedValueOnce({...receipt, requires_independent_review: false});
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitMomoAssignment(ctx, candidate, intent.reason, observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreMomoAssignment(ctx);
    const noProof = {...ctx, verifyFresh: async () => false, request: vi.fn()};
    await expect(retryMomoAssignment(noProof, pending)).rejects.toThrow('current verification');
    expect(noProof.request).not.toHaveBeenCalled();
    expect((await restoreMomoAssignment(ctx)).kind).toBe('owned');
  });
  it('fails closed for stale confirmations, changed sessions, and a crash with no retained intent', async () => {
    const request = vi.fn().mockResolvedValue(rawDetail), ctx = context(request), observed = await revision(ctx);
    await withPendingFence({identity: ctx.identity, family: 'momo-assign', resourceId: txId, isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async (access) => {access.reserve(key, access.read().revision); access.clear(key);});
    request.mockResolvedValueOnce(rawDetail).mockResolvedValueOnce(page);
    await expect(submitMomoAssignment(ctx, candidate, intent.reason, observed)).rejects.toThrow('Shared request recovery');
    const next = await revision(ctx), original = {...ctx, request: vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce(page).mockRejectedValueOnce(new Error('lost'))};
    await submitMomoAssignment(original, candidate, intent.reason, next);
    const other = {...ctx, identity: {...ctx.identity, sessionId: 'other'}};
    expect(await restoreMomoAssignment(other)).toEqual({kind: 'foreign'});
    const blank: Storage = {length: 0, clear() {}, getItem() {return null;}, key() {return null;}, removeItem() {}, setItem() {}};
    const crash = {...ctx, storage: blank, request: vi.fn()};
    const pending = await restoreMomoAssignment(crash);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryMomoAssignment(crash, pending)).rejects.toThrow('intent is unavailable');
    expect(crash.request).not.toHaveBeenCalled();
  });
  it('uses granted permissions rather than assuming staff has no payment access', async () => {
    const request = vi.fn().mockResolvedValue(page), ctx = {...context(request), identity: {...identity(), role: 'staff' as const}};
    expect((await loadMomoCandidates(ctx, '', 0)).rows).toEqual([candidate]);
  });
});
