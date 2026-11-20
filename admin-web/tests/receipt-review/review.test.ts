import {beforeEach, describe, expect, it, vi} from 'vitest';
import {readPending, type PendingIdentity} from '../../src/features/core/pendingAttempt';
import type {MemberReceipt} from '../../src/features/operations/contracts';
import {lookupReceiptReview, restoreReceiptReview, retryReceiptReview, submitReceiptReview, type ReceiptReviewContext, type ReviewTransaction} from '../../src/features/receipt-review/review';

const actor = '22222222-2222-4222-8222-222222222222', id = '11111111-1111-4111-8111-111111111111', key = '33333333-3333-4333-8333-333333333333', operation = '44444444-4444-4444-8444-444444444444', txId = '55555555-5555-4555-8555-555555555555', group = '66666666-6666-4666-8666-666666666666', evidence = '77777777-7777-4777-8777-777777777777', reviewId = '88888888-8888-4888-8888-888888888888';
const hash = 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9', time = '2026-10-18T08:00:00.000Z', why = 'Check this submitted receipt';
const receipt: MemberReceipt = {id, user_id: actor, body_sha256: hash, status: 'needs_review', version: 1, received_at: time, created_at: time, public_id: '123456', display_name: 'Synthetic member', transaction_id: null, reviewed_at: null};
const transaction: ReviewTransaction = {id: txId, label: 'TEST-REF · RWF 2400 · Fixture group', version: 9, amount_rwf: 2400, group_id: group, group_name: 'Fixture group', provider_reference: 'TEST-REF'};
const serverReceipt = {request_id: operation, resource_type: 'member_receipts', resource_id: id, version: 2, status: 'succeeded'};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.test', role: 'admin', permissions: ['payments.read', 'payments.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: ReceiptReviewContext['request']): ReceiptReviewContext {return {request, identity: identity(), receipt, financialModel: 'transaction_journals', canManage: true, enabled: true, allowAttachment: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
function detail(outcome?: 'reviewed'|'rejected', attach = false, reason = why) {return {resource_type: 'member_receipts', resource: outcome ? {...receipt, status: outcome, version: 2, transaction_id: attach ? txId : null, reviewed_at: time} : receipt, current_actor_id: actor, can_manage: true, related_truncated: false, related: {reviews: outcome ? [{id: reviewId, outcome, transaction_id: attach ? txId : null, evidence_id: attach ? evidence : null, actor_admin_id: actor, reason, reviewed_at: time}] : []}};}
async function revision(ctx: ReceiptReviewContext) {const state = await restoreReceiptReview(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('Legacy member receipt review', () => {
  it('requires current authority, explicit enablement, recovery permission and the separate attachment gate', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitReceiptReview({...ctx, enabled: false}, 'reviewed', why, null, hash, '')).rejects.toThrow(/not enabled/);
    await expect(submitReceiptReview({...ctx, financialModel: 'canonical_evidence_ledger'}, 'reviewed', why, null, hash, '')).rejects.toThrow(/unavailable/);
    await expect(submitReceiptReview({...ctx, identity: {...ctx.identity, permissions: ['payments.read', 'payments.manage']}}, 'reviewed', why, null, hash, '')).rejects.toThrow(/unavailable/);
    await expect(submitReceiptReview({...ctx, identity: {...ctx.identity, role: 'staff'}}, 'reviewed', why, null, hash, '')).rejects.toThrow(/unavailable/);
    await expect(submitReceiptReview({...ctx, isCurrent: () => false}, 'reviewed', why, null, hash, '')).rejects.toThrow(/unavailable/);
    await expect(submitReceiptReview({...ctx, allowAttachment: false}, 'reviewed', why, transaction, hash, '')).rejects.toThrow(/not enabled/);
    await expect(submitReceiptReview(ctx, 'reviewed', why, null, 'a'.repeat(64), '')).rejects.toThrow(/original receipt/);
    expect(request).not.toHaveBeenCalled();
  });
  it('checks the source, stores only digests and identifiers, and verifies a no-attachment review', async () => {
    const request = vi.fn(async (path: string, options?: {body?: unknown; idempotencyKey?: string}) => {
      if (path.includes('operations/requests/')) return {status: 'succeeded', request_id: operation, receipt: serverReceipt};
      if (path.endsWith('/review')) {
        const saved = await readPending(identity(), 'member-receipt-review-v2', id);
        expect(saved).toMatchObject({request_key: key, intent: {expected_version: 1, outcome: 'rejected', transaction_id: null, source_sha256: hash}});
        expect(JSON.stringify(saved)).not.toContain(why); expect(JSON.stringify(saved)).not.toContain('hello world');
        expect(options).toEqual({method: 'POST', idempotencyKey: key, body: {expected_version: 1, outcome: 'rejected', transaction_id: null, reason: why}}); return serverReceipt;
      }
      return request.mock.calls.filter(call => String(call[0]).endsWith('/review')).length ? detail('rejected') : detail();
    });
    const ctx = context(request);
    expect(await submitReceiptReview(ctx, 'rejected', why, null, hash, await revision(ctx))).toEqual({status: 'succeeded', requestId: operation});
    expect(await readPending(identity(), 'member-receipt-review-v2', id)).toBeNull();
  });
  it('binds and rechecks the reviewed transaction, sending the exact version to the guarded contract', async () => {
    const request = vi.fn(async (path: string, options?: {body?: unknown}) => {
      if (path.includes('operations/requests/')) return {status: 'succeeded', request_id: operation, receipt: serverReceipt};
      if (path.includes('/transactions?')) return {rows: [transaction]};
      if (path.endsWith('/review')) {
        expect(options?.body).toEqual({expected_version: 1, outcome: 'reviewed', transaction_id: txId, reason: why, expected_transaction_version: 9});
        const raw = JSON.stringify(await readPending(identity(), 'member-receipt-review-v2', id));
        expect(raw).not.toContain(why); expect(raw).not.toContain(transaction.label); expect(raw).not.toContain(transaction.provider_reference); return serverReceipt;
      }
      return request.mock.calls.some(call => String(call[0]).endsWith('/review')) ? detail('reviewed', true) : detail();
    });
    const ctx = context(request);
    expect(await submitReceiptReview(ctx, 'reviewed', why, transaction, hash, await revision(ctx))).toEqual({status: 'succeeded', requestId: operation});
  });
  it('blocks stale transaction data before reserving or submitting', async () => {
    const request = vi.fn(async (path: string) => path.includes('/transactions?') ? {rows: [{...transaction, version: 10}]} : detail());
    const ctx = context(request);
    await expect(submitReceiptReview(ctx, 'reviewed', why, transaction, hash, await revision(ctx))).rejects.toThrow(/transaction changed/i);
    expect(request.mock.calls.some(call => String(call[0]).endsWith('/review'))).toBe(false);
    expect((await restoreReceiptReview(ctx)).kind).toBe('ready');
  });
  it('retains a lost response, permits read-only lookup with writes off, and retries only the same key, reason and transaction after another lookup', async () => {
    let posts = 0;
    const request = vi.fn(async (path: string, options?: {body?: unknown; idempotencyKey?: string}) => {
      if (path.includes('operations/requests/')) return posts > 1 ? {status: 'succeeded', request_id: operation, receipt: serverReceipt} : {status: 'not_found'};
      if (path.includes('/transactions?')) return {rows: [transaction]};
      if (path.endsWith('/review')) {posts++; expect(options?.idempotencyKey).toBe(key); if (posts === 1) throw new Error('lost response'); return serverReceipt;}
      return posts > 1 ? detail('reviewed', true) : detail();
    });
    const ctx = context(request);
    expect(await submitReceiptReview(ctx, 'reviewed', why, transaction, hash, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreReceiptReview(ctx);
    expect(await lookupReceiptReview({...ctx, enabled: false}, pending)).toEqual({status: 'not_found', retryAvailable: true});
    await expect(retryReceiptReview(ctx, pending, 'A different review reason', transaction, hash)).rejects.toThrow(/exact original reason/);
    await expect(retryReceiptReview(ctx, pending, why, {...transaction, version: 10}, hash)).rejects.toThrow(/exact originally reviewed/);
    expect(posts).toBe(1);
    expect(await retryReceiptReview(ctx, pending, why, transaction, hash)).toEqual({status: 'succeeded', requestId: operation});
    const sent = request.mock.calls.filter(call => String(call[0]).endsWith('/review'));
    expect(sent).toHaveLength(2); expect(sent[0][1]).toEqual(sent[1][1]);
  });
  it('never clears a saved request after an unverified receipt or changed result', async () => {
    const request = vi.fn(async (path: string) => {
      if (path.includes('operations/requests/')) return {status: 'succeeded', request_id: operation, receipt: serverReceipt};
      if (path.endsWith('/review')) throw new Error('lost response');
      return request.mock.calls.some(call => String(call[0]).includes('operations/requests/')) ? detail('reviewed', false, 'Different reason') : detail();
    });
    const ctx = context(request);
    await submitReceiptReview(ctx, 'reviewed', why, null, hash, await revision(ctx));
    const pending = await restoreReceiptReview(ctx);
    await expect(lookupReceiptReview(ctx, pending)).rejects.toThrow(/could not be verified/);
    expect((await restoreReceiptReview(ctx)).kind).toBe('owned');
  });
  it('keeps a reservation and avoids dispatch when the action gate closes during retention', async () => {
    let enabled = true;
    const storage: Storage = {get length() {return sessionStorage.length;}, clear: () => sessionStorage.clear(), key: index => sessionStorage.key(index), getItem: name => sessionStorage.getItem(name), removeItem: name => sessionStorage.removeItem(name), setItem: (name, value) => {sessionStorage.setItem(name, value); enabled = false;}};
    const request = vi.fn().mockResolvedValue(detail()), ctx = {...context(request), storage, isEnabled: () => enabled};
    expect(await submitReceiptReview(ctx, 'reviewed', why, null, hash, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    expect(request.mock.calls.some(call => String(call[0]).endsWith('/review'))).toBe(false);
    expect((await restoreReceiptReview(ctx)).kind).toBe('owned');
  });
  it('does not report success when the actor-scoped lookup does not confirm the response under the original key', async () => {
    const request = vi.fn(async (path: string) => path.includes('operations/requests/') ? {status: 'not_found'} : path.endsWith('/review') ? serverReceipt : detail());
    const ctx = context(request);
    expect(await submitReceiptReview(ctx, 'reviewed', why, null, hash, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    expect((await restoreReceiptReview(ctx)).kind).toBe('owned');
  });
  it('makes a surviving fence without its intent check-only and prevents another authority from claiming it', async () => {
    const request = vi.fn(async (path: string) => path.endsWith('/review') ? Promise.reject(new Error('lost response')) : path.includes('operations/requests/') ? {status: 'succeeded', request_id: operation, receipt: serverReceipt} : detail());
    const ctx = context(request);
    await submitReceiptReview(ctx, 'reviewed', why, null, hash, await revision(ctx));
    sessionStorage.clear();
    const unbound = await restoreReceiptReview(ctx);
    expect(unbound).toEqual({kind: 'owned', requestKey: key, attempt: null});
    expect(await lookupReceiptReview({...ctx, enabled: false}, unbound)).toEqual({status: 'succeeded', requestId: operation, verifiedIntent: false});
    expect((await restoreReceiptReview(ctx)).kind).toBe('owned');
    const other = {...ctx, identity: {...ctx.identity, sessionId: 'another-session'}};
    expect(await restoreReceiptReview(other)).toEqual({kind: 'foreign'});
    await expect(retryReceiptReview(ctx, unbound, why, null, hash)).rejects.toThrow(/intent is unavailable/);
  });
});
