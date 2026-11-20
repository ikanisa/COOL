import {beforeEach, describe, expect, it, vi} from 'vitest';
import {canonicalRequestId, readPending, type PendingIdentity} from '../../src/features/core';
import {CANCELLATION_FAMILY, checkCancellation, restoreCancellation, retryCancellation, submitCancellation,
  type CancellationContext} from '../../src/features/requests/cancellation';

const principal = '12345678-1234-4123-8123-123456789012', target = 'request-original-001', key = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const reason = 'Block the original uncommitted request';
const marker = {contract_version: 2, model: 'canonical_evidence_ledger'};
const missing = {...marker, status: 'not_found'};
const identity = (): PendingIdentity => ({id: 'actor-a', sessionId: 'session-a', email: 'admin@example.test', role: 'admin',
  permissions: ['overview.read', 'account.manage'], expiresAt: new Date(Date.now() + 3600000).toISOString()});
function context(request: CancellationContext['request']): CancellationContext {
  return {request, identity: identity(), principalId: principal, targetKey: target, financialModel: 'canonical_evidence_ledger', enabled: true,
    isCurrent: () => true, verifyFresh: async () => true, storage: sessionStorage, sharedStorage: localStorage,
    lock: async (_name, work) => work(), createKey: () => key};
}
async function terminal(status: 'cancelled' | 'unconfirmed' = 'cancelled') {
  return {...marker, status, request_id: await canonicalRequestId(principal, target), receipt: null};
}
async function revision(ctx: CancellationContext) {
  const state = await restoreCancellation(ctx);
  if (state.kind !== 'ready') throw new Error('Expected an empty cancellation fence');
  return state.revision;
}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('canonical request cancellation', () => {
  it('requires an explicit gate, canonical model, current permissions and fresh verification', async () => {
    const request = vi.fn().mockResolvedValue(missing), ctx = context(request);
    await expect(submitCancellation({...ctx, enabled: false}, reason, '')).rejects.toThrow(/not enabled/);
    await expect(submitCancellation({...ctx, financialModel: 'transaction_journals'}, reason, '')).rejects.toThrow(/unavailable/);
    await expect(submitCancellation({...ctx, identity: {...ctx.identity, permissions: ['overview.read']}}, reason, '')).rejects.toThrow(/unavailable/);
    const unverified = {...ctx, verifyFresh: async () => false};
    await expect(submitCancellation(unverified, reason, await revision(unverified))).rejects.toThrow(/current verification/);
    expect(request.mock.calls.every(([, options]) => !options?.method)).toBe(true);
    expect(await readPending(ctx.identity, CANCELLATION_FAMILY, target)).toBeNull();
  });
  it('retains the separate key and exact intent before sending, and verifies the response against the target', async () => {
    const done = await terminal(), request = vi.fn(async (path: string, options) => {
      if (!options?.method) return request.mock.calls.length === 1 ? missing : done;
      const saved = await readPending(identity(), CANCELLATION_FAMILY, target);
      expect(saved).toMatchObject({request_key: key, resource_id: target, permission: 'account.manage', intent: {reason, model: 'canonical_evidence_ledger'}});
      expect(saved?.intent.principal_sha256).toMatch(/^[a-f0-9]{64}$/);
      expect(path).toBe(`operations/requests/${target}/cancel`);
      expect(options).toEqual({method: 'POST', body: {reason}, idempotencyKey: key});
      return done;
    }), ctx = context(request);
    expect(await submitCancellation(ctx, reason, await revision(ctx))).toMatchObject({status: 'confirmed', outcome: {status: 'cancelled'}});
    expect(await readPending(ctx.identity, CANCELLATION_FAMILY, target)).toBeNull();
    expect((await restoreCancellation(ctx)).kind).toBe('ready');
  });
  it('retains a lost response, checks the target, and uses the same key and exact intent only on explicit retry', async () => {
    const done = await terminal(), request = vi.fn().mockResolvedValueOnce(missing).mockRejectedValueOnce(new Error('response lost'))
      .mockResolvedValueOnce(done).mockResolvedValueOnce(done).mockResolvedValueOnce(done).mockResolvedValueOnce(done), ctx = context(request);
    expect(await submitCancellation(ctx, reason, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreCancellation(ctx);
    expect(pending).toMatchObject({kind: 'owned', requestKey: key, attempt: {intent: {reason}}});
    expect((await checkCancellation({...ctx, enabled: false}, pending)).status).toBe('cancelled');
    expect(await readPending(ctx.identity, CANCELLATION_FAMILY, target)).not.toBeNull();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
    expect(await retryCancellation(ctx, pending)).toMatchObject({status: 'confirmed', outcome: {status: 'cancelled'}});
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toEqual([
      [`operations/requests/${target}/cancel`, {method: 'POST', body: {reason}, idempotencyKey: key}],
      [`operations/requests/${target}/cancel`, {method: 'POST', body: {reason}, idempotencyKey: key}],
    ]);
  });
  it('does not retry while the target is unconfirmed and does not silently create a new key', async () => {
    const request = vi.fn().mockResolvedValueOnce(missing).mockRejectedValueOnce(new Error('lost')).mockResolvedValue(await terminal('unconfirmed')),
      ctx = context(request);
    await submitCancellation(ctx, reason, await revision(ctx));
    const pending = await restoreCancellation(ctx);
    expect((await checkCancellation(ctx, pending)).status).toBe('unconfirmed');
    await expect(retryCancellation(ctx, pending)).rejects.toThrow(/unconfirmed/);
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
    expect(await readPending(ctx.identity, CANCELLATION_FAMILY, target)).toMatchObject({request_key: key});
  });
  it('reports a target that completed before dispatch without sending a cancellation', async () => {
    const done = await terminal(), request = vi.fn().mockResolvedValue(done), ctx = context(request);
    expect(await submitCancellation(ctx, reason, await revision(ctx))).toMatchObject({status: 'target_changed', outcome: {status: 'cancelled'}});
    expect(request).toHaveBeenCalledTimes(1);
    expect(await readPending(ctx.identity, CANCELLATION_FAMILY, target)).toBeNull();
  });
  it('reports a committed original returned by a racing cancellation as succeeded, not cancelled', async () => {
    const id = await canonicalRequestId(principal, target), receipt = {request_id: id, status: 'succeeded', resource_type: 'groups',
      resource_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', version: 1};
    const done = {...marker, status: 'succeeded', request_id: id, receipt};
    const request = vi.fn().mockResolvedValueOnce(missing).mockResolvedValueOnce(done).mockResolvedValueOnce(done), ctx = context(request);
    expect(await submitCancellation(ctx, reason, await revision(ctx))).toMatchObject({status: 'confirmed', outcome: {status: 'succeeded', receipt: {requestId: id}}});
    expect(await readPending(ctx.identity, CANCELLATION_FAMILY, target)).toBeNull();
  });
  it('retains a response with a wrong target or a contradictory target lookup', async () => {
    const wrong = {...await terminal(), request_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'}, request = vi.fn().mockResolvedValueOnce(missing).mockResolvedValueOnce(wrong), ctx = context(request);
    expect(await submitCancellation(ctx, reason, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    expect(await readPending(ctx.identity, CANCELLATION_FAMILY, target)).toMatchObject({request_key: key});
  });
  it('does not send after authority or gate changes during verification', async () => {
    const request = vi.fn().mockResolvedValue(missing); let enabled = true;
    const ctx = {...context(request), isEnabled: () => enabled, verifyFresh: async () => {enabled = false; return true;}};
    await expect(submitCancellation(ctx, reason, await revision(ctx))).rejects.toThrow(/not enabled/);
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
    expect(await readPending(ctx.identity, CANCELLATION_FAMILY, target)).toBeNull();
  });
  it('fences a changed authority even while the target lookup is in flight', async () => {
    let active = true;
    const request = vi.fn(async () => {active = false; return missing;}), ctx = {...context(request), isCurrent: () => active};
    await expect(submitCancellation(ctx, reason, await revision(ctx))).rejects.toThrow(/unavailable/);
    expect(request).toHaveBeenCalledTimes(1);
    expect(await readPending(ctx.identity, CANCELLATION_FAMILY, target)).toBeNull();
  });
  it('does not replay a different principal or a fence with missing per-tab intent', async () => {
    const request = vi.fn().mockResolvedValueOnce(missing).mockRejectedValueOnce(new Error('lost')), ctx = context(request);
    await submitCancellation(ctx, reason, await revision(ctx));
    const other = {...ctx, principalId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'};
    const different = await restoreCancellation(other);
    expect(different).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryCancellation(other, different)).rejects.toThrow(/unavailable/);
    sessionStorage.clear();
    const missingIntent = await restoreCancellation(ctx);
    expect(missingIntent).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryCancellation(ctx, missingIntent)).rejects.toThrow(/unavailable/);
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
  });
  it('fails closed if the same cancellation key is selected as the original reference', async () => {
    const request = vi.fn().mockResolvedValue(missing), ctx = {...context(request), targetKey: key};
    await expect(submitCancellation(ctx, reason, await revision(ctx))).rejects.toThrow(/separate secure/);
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
  });
  it('blocks another tab during a pending post and never exposes its exact intent in shared storage', async () => {
    let release!: () => void, started!: () => void, active = false;
    const startedPromise = new Promise<void>((resolve) => {started = resolve;});
    const lost = new Promise<never>((_resolve, reject) => {release = () => reject(new Error('lost'));});
    const lock: NonNullable<CancellationContext['lock']> = async (_name, work) => {
      if (active) throw new Error('locked'); active = true; try {return await work();} finally {active = false;}
    };
    const request = vi.fn(async (_path: string, options) => options?.method === 'POST' ? (started(), lost) : missing), ctx = {...context(request), lock};
    const observed = await revision(ctx), otherObserved = await revision(ctx);
    const dispatch = submitCancellation(ctx, reason, observed); await startedPromise;
    await expect(submitCancellation(ctx, reason, otherObserved)).rejects.toThrow('locked');
    release(); expect(await dispatch).toEqual({status: 'unknown', requestKey: key});
    const shared = localStorage.getItem('collect.admin.pending-fence.v2')!;
    expect(shared).not.toContain(reason); expect(shared).not.toContain(target); expect(shared).not.toContain(ctx.identity.email);
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
  });
});
