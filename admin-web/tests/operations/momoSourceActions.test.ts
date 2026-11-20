import {beforeEach, describe, expect, it, vi} from 'vitest';
import {readPending, retainPending, type PendingIdentity} from '../../src/features/core';
import type {MomoSourceJob} from '../../src/features/operations/momoContracts';
import {canReviewMomoSource, nonPaymentExtraction, parseMomoSourceCandidate, parseMomoSourceIntent, restoreMomoSource, retryMomoSource, submitMomoSource, type MomoSourceActionContext, type MomoSourceActionKind} from '../../src/features/operations/momoSourceActions';

const sourceId = '11111111-1111-4111-8111-111111111111', actor = '22222222-2222-4222-8222-222222222222', account = '33333333-3333-4333-8333-333333333333', key = '44444444-4444-4444-8444-444444444444', attemptId = '55555555-5555-4555-8555-555555555555', other = '66666666-6666-4666-8666-666666666666', hash = 'a'.repeat(64);
const source: MomoSourceJob = {raw_sms_id: sourceId, state: 'needs_review', binding_id: null, receiving_account_id: account, received_at: '2026-10-18T08:00:00.000Z', last_error: 'schema_mismatch', body_sha256: hash, attempt_count: 2, latest_attempt_id: attemptId, latest_attempt_outcome: 'needs_review'};
const unresolved: MomoSourceJob = {...source, state: 'source_unresolved', receiving_account_id: null, latest_attempt_id: null, latest_attempt_outcome: null};
const accounts = {rows: [{id: account, provider: 'mtn_momo', public_code: '123456', recipient_name: 'Synthetic account', status: 'active'}]};
const evidenceReference = 'Reviewed synthetic evidence', reason = 'Explain the reviewed synthetic source';
const identity = (): PendingIdentity => ({id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'staff', permissions: ['sms.read', 'sms.extract', 'receivers.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()});
function context(kind: MomoSourceActionKind, request: MomoSourceActionContext['request']): MomoSourceActionContext {
  return {request, identity: identity(), principalId: actor, financialModel: 'canonical_evidence_ledger', sourceId, kind, source: kind === 'resolve' ? unresolved : source, enabled: true, isCurrent: () => true, verifyFresh: async () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};
}
const common = {expected_state: 'needs_review' as const, expected_attempt_count: 2, expected_body_sha256: hash, evidence_reference: evidenceReference, reason};
const classification = {...common, extraction: nonPaymentExtraction('failed', 'Payment failed.'), classification_evidence: 'Payment failed.'};
const base = nonPaymentExtraction('failed', 'Payment failed.');
const correction = {...common, extraction: {...base, event_kind: 'incoming_receipt', payment_outcome: 'successful', transaction_id_raw: 'ABC123', principal_amount_raw: '5000', currency_raw: 'RWF', evidence: {...base.evidence, incoming_success: 'You have received RWF 5000', principal: 'RWF 5000', transaction_id: 'Transaction ABC123'}}};
const resolve = {receiving_account_id: account, evidence_reference: evidenceReference, reason};
const reparse = {expected_state: 'needs_review' as const, expected_attempt_count: 2, expected_body_sha256: hash, expected_receiving_account_id: account, reason};
const receipt = {raw_sms_id: sourceId, parse_attempt_id: attemptId, status: 'review_recorded', financial_effects: 0};
async function revision(ctx: MomoSourceActionContext) {const state = await restoreMomoSource(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('MoMo source review and resolution', () => {
  it('requires explicit activation, actual permissions, a canonical model and current proof', async () => {
    const request = vi.fn(), ctx = context('correct', request);
    await expect(submitMomoSource({...ctx, enabled: false}, correction, '')).rejects.toThrow(/not enabled/);
    await expect(submitMomoSource({...ctx, financialModel: 'transaction_journals'}, correction, '')).rejects.toThrow(/unavailable/);
    await expect(submitMomoSource({...ctx, identity: {...ctx.identity, permissions: ['sms.extract']}}, correction, '')).rejects.toThrow(/unavailable/);
    const withoutProof = {...ctx, verifyFresh: async () => false}, observed = await revision(withoutProof);
    await expect(submitMomoSource(withoutProof, correction, observed)).rejects.toThrow(/current verification/);
    expect(request).not.toHaveBeenCalled();
  });
  it('requires reviewed source state, source digest and attempt metadata', () => {
    expect(canReviewMomoSource(source, 'correct')).toBe(true);
    expect(canReviewMomoSource({...source, attempt_count: undefined}, 'correct')).toBe(false);
    expect(canReviewMomoSource({...source, latest_attempt_outcome: 'accepted'}, 'correct')).toBe(false);
    expect(canReviewMomoSource({...source, body_sha256: undefined}, 'non-payment')).toBe(false);
    expect(canReviewMomoSource(unresolved, 'resolve')).toBe(true);
    expect(canReviewMomoSource({...unresolved, binding_id: account}, 'resolve')).toBe(false);
    expect(() => parseMomoSourceIntent('non-payment', {...classification, classification_evidence: 'invented'})).toThrow();
    expect(() => parseMomoSourceIntent('correct', {...correction, extraction: {...correction.extraction, payment_outcome: 'failed'}})).toThrow();
    expect(canReviewMomoSource({...source, latest_attempt_outcome: 'accepted', state: 'completed'}, 'reparse')).toBe(true);
    expect(canReviewMomoSource({...source, state: 'retry'}, 'reparse')).toBe(false);
    expect(canReviewMomoSource({...source, attempt_count: Number.MAX_SAFE_INTEGER}, 'reparse')).toBe(false);
    expect(() => parseMomoSourceIntent('reparse', {reason})).toThrow();
  });
  it('retains a guarded reparse and retries the exact original version only after confirmation', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost reply')).mockResolvedValueOnce({raw_sms_id: sourceId, status: 'pending'}), ctx = context('reparse', request);
    expect(await submitMomoSource(ctx, reparse, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    expect(await readPending(identity(), 'momo-reparse-v2', sourceId)).toMatchObject({request_key: key, intent: reparse});
    const pending = await restoreMomoSource({...ctx, source: undefined}); expect(request).toHaveBeenCalledOnce();
    expect(await retryMomoSource({...ctx, source: undefined}, pending)).toEqual({status: 'succeeded'});
    expect(request).toHaveBeenNthCalledWith(2, `momo/sources/${sourceId}/reparse`, {method: 'POST', body: reparse, idempotencyKey: key});
    expect(await readPending(identity(), 'momo-reparse-v2', sourceId)).toBeNull();
  });
  it('refuses a stale source, wrong receipt, disabled gate and an unresolved old reparse key', async () => {
    const request = vi.fn().mockResolvedValue({raw_sms_id: other, status: 'pending'}), ctx = context('reparse', request);
    await expect(submitMomoSource({...ctx, source: {...source, attempt_count: 3}}, reparse, await revision(ctx))).rejects.toThrow(/changed/);
    await expect(submitMomoSource({...ctx, enabled: false}, reparse, '')).rejects.toThrow(/not enabled/);
    expect(await submitMomoSource(ctx, reparse, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    expect(await readPending(identity(), 'momo-reparse-v2', sourceId)).toMatchObject({request_key: key});
    sessionStorage.clear(); localStorage.clear();
    await retainPending(identity(), 'momo-reparse', sourceId, key, 'sms.extract', {reason});
    const pending = await restoreMomoSource(ctx);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryMomoSource(ctx, pending)).rejects.toThrow(/unavailable/);
    expect(await submitMomoSource(ctx, reparse, 'unused')).toEqual({status: 'existing', pending});
    expect(request).toHaveBeenCalledOnce();
    expect(await readPending(identity(), 'momo-reparse', sourceId)).toMatchObject({request_key: key});
  });
  it('treats retained model output as an untrusted suggestion, never as a review', () => {
    const input = JSON.stringify({...correction.extraction, issues: ['needs_review']});
    expect(parseMomoSourceCandidate(input)).toMatchObject({transaction_id_raw: 'ABC123', issues: []});
    expect(parseMomoSourceCandidate(JSON.stringify({...correction.extraction, unexpected: true}))).toBeNull();
    expect(parseMomoSourceCandidate(JSON.stringify({...correction.extraction, event_kind: 'failed'}))).toBeNull();
    expect(parseMomoSourceCandidate('{broken')).toBeNull();
  });
  it('records each exact reviewed intent and verifies no financial effects in its receipt', async () => {
    for (const [kind, intent] of [['correct', correction], ['non-payment', classification]] as const) {
      sessionStorage.clear(); localStorage.clear();
      const request = vi.fn(async (path: string, options) => {
        const saved = await readPending(identity(), `momo-review-${kind}`, sourceId);
        expect(saved?.request_key).toBe(key); expect(saved?.intent).toEqual(intent);
        expect(path).toBe(`momo/sources/${sourceId}/${kind === 'correct' ? 'correct-extraction' : 'classify-non-payment'}`);
        expect(options).toEqual({method: 'POST', body: intent, idempotencyKey: key}); return receipt;
      });
      const ctx = context(kind, request);
      expect(await submitMomoSource(ctx, intent, await revision(ctx))).toEqual({status: 'succeeded'});
      expect(await readPending(identity(), `momo-review-${kind}`, sourceId)).toBeNull();
    }
  });
  it('retains a lost original and permits only an explicit identical-key retry, even after the source leaves the list', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost reply')).mockResolvedValueOnce(receipt), ctx = context('non-payment', request);
    expect(await submitMomoSource(ctx, classification, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    expect(request).toHaveBeenCalledTimes(1);
    const afterReload = {...ctx, source: undefined}, pending = await restoreMomoSource(afterReload);
    expect(pending).toMatchObject({kind: 'owned', requestKey: key});
    expect(await retryMomoSource(afterReload, pending)).toEqual({status: 'succeeded'});
    expect(request).toHaveBeenNthCalledWith(2, `momo/sources/${sourceId}/classify-non-payment`, {method: 'POST', body: classification, idempotencyKey: key});
    expect((await restoreMomoSource(afterReload)).kind).toBe('ready');
  });
  it('rejects mismatched receipts and does not retry unbound or different-principal originals', async () => {
    const request = vi.fn().mockResolvedValue({...receipt, financial_effects: 1}), ctx = context('correct', request);
    expect(await submitMomoSource(ctx, correction, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreMomoSource(ctx);
    await expect(retryMomoSource({...ctx, principalId: other}, pending)).rejects.toThrow();
    sessionStorage.removeItem(`collect.admin.momo-source.owner.v1:correct:${sourceId}`);
    const unbound = await restoreMomoSource(ctx);
    expect(unbound).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryMomoSource(ctx, unbound)).rejects.toThrow(/unavailable/);
    expect(request).toHaveBeenCalledOnce();
  });
  it('never promotes an old unbound Flutter checkpoint into replay authority', async () => {
    await retainPending(identity(), 'momo-review-non-payment', sourceId, key, 'sms.extract', classification);
    const request = vi.fn(), ctx = context('non-payment', request), pending = await restoreMomoSource(ctx);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryMomoSource(ctx, pending)).rejects.toThrow(); expect(request).not.toHaveBeenCalled();
  });
  it('resolves only an active reviewed receiving account and validates the historical zero-effect receipt', async () => {
    const request = vi.fn(async (path: string, options) => path === 'momo/accounts' ? accounts : (expect(options).toEqual({method: 'POST', body: resolve, idempotencyKey: key}), {raw_sms_id: sourceId, receiving_account_id: account, status: 'pending', mode: 'historical', financial_effects: 0}));
    const ctx = context('resolve', request);
    expect(await submitMomoSource(ctx, resolve, await revision(ctx))).toEqual({status: 'succeeded'});
    expect(request).toHaveBeenCalledTimes(2);
    sessionStorage.clear(); localStorage.clear();
    const inactive = context('resolve', vi.fn().mockResolvedValue({rows: [{...accounts.rows[0], status: 'suspended'}]}));
    await expect(submitMomoSource(inactive, resolve, await revision(inactive))).rejects.toThrow(/no longer available/);
    expect(inactive.request).toHaveBeenCalledTimes(1);
  });
  it('does not dispatch if the action gate closes during verification', async () => {
    let enabled = true;
    const request = vi.fn(), ctx = {...context('correct', request), isEnabled: () => enabled, verifyFresh: async () => {enabled = false; return true;}};
    await expect(submitMomoSource(ctx, correction, await revision(ctx))).rejects.toThrow(/not enabled/);
    expect(request).not.toHaveBeenCalled();
    expect(await readPending(identity(), 'momo-review-correct', sourceId)).toBeNull();
  });
  it('retains the original when authority changes before a successful response is observed', async () => {
    let active = true;
    const request = vi.fn(async () => {active = false; return receipt;}), ctx = {...context('correct', request), isCurrent: () => active};
    expect(await submitMomoSource(ctx, correction, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    expect(await readPending(identity(), 'momo-review-correct', sourceId)).toMatchObject({request_key: key, intent: correction});
    expect(request).toHaveBeenCalledOnce();
  });
});
