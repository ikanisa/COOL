import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readPending, retainPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import { parseMomoDetail } from '../../src/features/operations/momoContracts';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { canReviewMomoConflict, momoConflictSources, parseMomoConflictIntent, restoreMomoConflict, retryMomoConflict, submitMomoConflict, type MomoConflictContext } from '../../src/features/operations/momoConflict';

const txId = '11111111-1111-4111-8111-111111111111', actor = '22222222-2222-4222-8222-222222222222', account = '33333333-3333-4333-8333-333333333333', original = '44444444-4444-4444-8444-444444444444', conflict = '55555555-5555-4555-8555-555555555555', raw1 = '66666666-6666-4666-8666-666666666666', key = '77777777-7777-4777-8777-777777777777', raw2 = '88888888-8888-4888-8888-888888888888', other = '99999999-9999-4999-8999-999999999999';
const time = '2026-10-18T08:00:00.000Z';
const tx = {id: txId, receiving_account_id: account, provider_transaction_id: 'MOMO-SYNTHETIC-001', recipient_name: 'Synthetic receiver', public_code: '123456', payer_name: 'Synthetic payer', payer_last3: '007', member_name: null, group_name: null, group_id: null, beneficiary_member_id: null, payment_id: null, amount_minor: 5000, has_conflict: 1, credited_amount_minor: 0, version: 1, currency: 'RWF', status: 'needs_review', event_kind: 'incoming_receipt', allocation_state: 'needs_review', transaction_at: time, created_at: time};
const accepted = {raw_sms_id: raw1, attempt_id: original, relation: 'accepted', outcome: 'accepted', parser_version: 'v1', created_at: time};
const contradictory = {raw_sms_id: raw2, attempt_id: conflict, relation: 'conflict', outcome: 'conflict', parser_version: 'v1', created_at: time};
const rawDetail = {transaction: tx, sources: [accepted, contradictory], conflicting_attempt_ids: [conflict]};
const detail = parseMomoDetail(rawDetail, txId);
const intent = {expected_version: 1, expected_conflicting_attempt_ids: [conflict], decision: 'retain_original', evidence_reference: 'Support evidence 123', reason: 'Reviewed source evidence'};
const receipt = {transaction_id: txId, version: 2, status: 'needs_allocation', financial_effects: 0};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.com', role: 'admin', permissions: ['payments.read', 'payments.write', 'sms.extract'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: MomoConflictContext['request']): MomoConflictContext {return {request, identity: identity(), principalId: actor, financialModel: 'canonical_evidence_ledger', detail, enabled: true, isCurrent: () => true, verifyFresh: async () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: MomoConflictContext) {const state = await restoreMomoConflict(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('MoMo conflict review', () => {
  it('requires exactly one accepted source and the complete bounded conflict attempt set', () => {
    expect(momoConflictSources(detail).ids).toEqual([conflict]);
    expect(canReviewMomoConflict(detail)).toBe(true);
    for (const changed of [
      {...rawDetail, conflicting_attempt_ids: [conflict, other]},
      {...rawDetail, sources: [accepted, {...contradictory, attempt_id: undefined}]},
      {...rawDetail, sources: [accepted, contradictory, contradictory]},
      {...rawDetail, sources: [contradictory]},
      {...rawDetail, transaction: {...tx, payment_id: other}},
      {...rawDetail, transaction: {...tx, allocation_state: 'unallocated'}},
    ]) expect(canReviewMomoConflict(parseMomoDetail(changed, txId))).toBe(false);
    expect(() => parseMomoConflictIntent({...intent, expected_conflicting_attempt_ids: [conflict, conflict]})).toThrow();
    expect(() => parseMomoConflictIntent({...intent, decision: 'replace_original'})).toThrow();
    expect(() => parseMomoConflictIntent({...intent, reason: 'short'})).toThrow();
  });
  it('requires the gate, actual permissions, canonical model and fresh verification', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitMomoConflict({...ctx, enabled: false}, intent.evidence_reference, intent.reason, '')).rejects.toThrow('not enabled');
    await expect(submitMomoConflict({...ctx, identity: {...ctx.identity, permissions: ['payments.read', 'payments.write']}}, intent.evidence_reference, intent.reason, '')).rejects.toThrow('unavailable');
    await expect(submitMomoConflict({...ctx, financialModel: 'transaction_journals'}, intent.evidence_reference, intent.reason, '')).rejects.toThrow('unavailable');
    const missingProof = {...ctx, verifyFresh: async () => false, request: vi.fn().mockResolvedValue(rawDetail)}, observed = await revision(missingProof);
    await expect(submitMomoConflict(missingProof, intent.evidence_reference, intent.reason, observed)).rejects.toThrow('current verification');
    expect(await readPending(identity(), 'momo-review-conflict', txId)).toBeNull();
    expect(missingProof.request).toHaveBeenCalledTimes(1);
  });
  it('does not dispatch if the gate closes during verification or the binding cannot be stored', async () => {
    let enabled = true;
    const request = vi.fn().mockResolvedValue(rawDetail), ctx = {...context(request), isEnabled: () => enabled, verifyFresh: async () => {enabled = false; return true;}}, observed = await revision(ctx);
    await expect(submitMomoConflict(ctx, intent.evidence_reference, intent.reason, observed)).rejects.toThrow('not enabled');
    expect(request).toHaveBeenCalledTimes(1);
    const storage: Storage = {get length() {return sessionStorage.length;}, clear() {sessionStorage.clear();}, getItem(k) {return sessionStorage.getItem(k);}, key(i) {return sessionStorage.key(i);}, removeItem(k) {sessionStorage.removeItem(k);}, setItem(k, v) {if (k.startsWith('collect.admin.momo-conflict.owner.v1:')) throw new Error('blocked'); sessionStorage.setItem(k, v);}};
    const bad = {...context(request), storage}, next = await revision(bad);
    await expect(submitMomoConflict(bad, intent.evidence_reference, intent.reason, next)).rejects.toThrow();
    expect(request).toHaveBeenCalledTimes(2);
    expect(await readPending(identity(), 'momo-review-conflict', txId)).toBeNull();
  });
  it('rechecks complete evidence and records the exact audited decision with no financial effects', async () => {
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'POST') {
        expect(path).toBe(`momo/transactions/${txId}/review-conflict`);
        expect(options).toEqual({method: 'POST', body: intent, idempotencyKey: key});
        expect(await readPending(identity(), 'momo-review-conflict', txId)).toMatchObject({request_key: key, intent});
        return receipt;
      }
      return rawDetail;
    });
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitMomoConflict(ctx, intent.evidence_reference, intent.reason, observed)).toEqual({status: 'succeeded', receipt: {transactionId: txId, version: 2, status: 'needs_allocation', financialEffects: 0}});
    expect(await readPending(identity(), 'momo-review-conflict', txId)).toBeNull();
    expect(request).toHaveBeenCalledTimes(2);
  });
  it('rejects changed source identities, conflict sets and versions before creating a request', async () => {
    for (const changed of [
      {...rawDetail, sources: [accepted, {...contradictory, raw_sms_id: other}]},
      {...rawDetail, transaction: {...tx, version: 2}},
      {...rawDetail, conflicting_attempt_ids: [conflict, other]},
    ]) {
      sessionStorage.clear(); localStorage.clear();
      const request = vi.fn().mockResolvedValue(changed), ctx = context(request), observed = await revision(ctx);
      await expect(submitMomoConflict(ctx, intent.evidence_reference, intent.reason, observed)).rejects.toThrow();
      expect(request).toHaveBeenCalledTimes(1);
      expect(await readPending(identity(), 'momo-review-conflict', txId)).toBeNull();
    }
  });
  it('retains an unknown outcome and retries only the exact key and body after a fresh source check', async () => {
    const postCommitDetail = {...rawDetail, transaction: {...tx, has_conflict: 0, allocation_state: 'unallocated', status: 'needs_allocation', version: 2}};
    const request = vi.fn().mockResolvedValueOnce(rawDetail).mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce(postCommitDetail).mockResolvedValueOnce(receipt);
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitMomoConflict(ctx, intent.evidence_reference, intent.reason, observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreMomoConflict(ctx);
    expect(pending).toMatchObject({kind: 'owned', requestKey: key});
    expect((await retryMomoConflict(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(4, `momo/transactions/${txId}/review-conflict`, {method: 'POST', body: intent, idempotencyKey: key});
    expect(request).toHaveBeenCalledTimes(4);
    expect(await restoreMomoConflict(ctx)).toMatchObject({kind: 'ready'});
  });
  it('refuses recovery after source changes and retains malformed or inconsistent responses as unknown', async () => {
    const request = vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce({...receipt, financial_effects: 1}).mockResolvedValueOnce({...rawDetail, sources: [accepted, {...contradictory, raw_sms_id: other}]});
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitMomoConflict(ctx, intent.evidence_reference, intent.reason, observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreMomoConflict(ctx);
    await expect(retryMomoConflict(ctx, pending)).rejects.toThrow('sources could not be verified');
    expect(request).toHaveBeenCalledTimes(3);
    expect((await restoreMomoConflict(ctx)).kind).toBe('owned');
  });
  it('binds replay to the same principal and refuses older unbound Flutter checkpoints', async () => {
    const request = vi.fn().mockResolvedValueOnce(rawDetail).mockRejectedValueOnce(new Error('lost'));
    const ctx = context(request), observed = await revision(ctx);
    await submitMomoConflict(ctx, intent.evidence_reference, intent.reason, observed);
    expect(await restoreMomoConflict({...ctx, principalId: other})).toEqual({kind: 'foreign'});
    expect(await restoreMomoConflict({...ctx, identity: {...ctx.identity, sessionId: 'another'}})).toEqual({kind: 'foreign'});
    sessionStorage.clear(); localStorage.clear();
    await retainPending(identity(), 'momo-review-conflict', txId, key, 'payments.write', intent);
    const unbound = await restoreMomoConflict(ctx);
    expect(unbound).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryMomoConflict(ctx, unbound)).rejects.toThrow('intent is unavailable');
  });
  it('fails closed for stale confirmations and a crash with no retained intent', async () => {
    const request = vi.fn().mockResolvedValue(rawDetail), ctx = context(request), observed = await revision(ctx);
    await withPendingFence({identity: ctx.identity, family: 'momo-review-conflict', resourceId: txId, isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async (access) => {access.reserve(key, access.read().revision); access.clear(key);});
    await expect(submitMomoConflict(ctx, intent.evidence_reference, intent.reason, observed)).rejects.toThrow('Shared request recovery');
    const next = await revision(ctx), lost = {...ctx, request: vi.fn().mockResolvedValueOnce(rawDetail).mockRejectedValueOnce(new Error('lost'))};
    await submitMomoConflict(lost, intent.evidence_reference, intent.reason, next);
    const blank: Storage = {length: 0, clear() {}, getItem() {return null;}, key() {return null;}, removeItem() {}, setItem() {}};
    const crash = {...ctx, storage: blank, request: vi.fn()}, pending = await restoreMomoConflict(crash);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryMomoConflict(crash, pending)).rejects.toThrow('intent is unavailable');
    expect(crash.request).not.toHaveBeenCalled();
  });
});
