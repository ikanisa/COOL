import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import { lookupEmailDispatch, restoreEmailDispatch, submitEmailDispatch, type EmailDispatchContext } from '../../src/features/operations/emailActions';

const actor = '22222222-2222-2222-2222-222222222222';
const key = '33333333-3333-4333-8333-333333333333';
const requestId = '44444444-4444-4444-8444-444444444444';
const receipt = {request_id: requestId, status: 'succeeded', resource_type: 'email_dispatch', resource_id: requestId, version: 1, accepted: 2, uncertain: 1, suppressed: 0};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'operator@example.com', role: 'admin', permissions: ['email.read', 'email.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: EmailDispatchContext['request'], enabled = true): EmailDispatchContext {
  return {request, identity: identity(), financialModel: 'transaction_journals', principalId: null, enabled, isCurrent: () => true,
    storage: sessionStorage, lock: async (_name, work) => work(), createKey: () => key};
}
async function revision(ctx: EmailDispatchContext): Promise<string> {const state = await restoreEmailDispatch(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('Queued email dispatch', () => {
  it('does not send a batch when the qualification gate is closed', async () => {
    const request = vi.fn();
    await expect(submitEmailDispatch(context(request, false), 'Review queued notifications', '')).rejects.toThrow('not enabled');
    expect(request).not.toHaveBeenCalled();
    expect(sessionStorage.length).toBe(0);
  });

  it('records the original key before sending and validates the provider outcome counts', async () => {
    const request = vi.fn(async (_path: string, options?: {idempotencyKey?: string}) => {
      expect(options?.idempotencyKey).toBe(key);
      expect(await readPending(identity(), 'email-dispatch', 'queue')).not.toBeNull();
      return receipt;
    });
    const ctx = context(request);
    const result = await submitEmailDispatch(ctx, 'Review queued notifications', await revision(ctx));
    expect(result).toEqual({status: 'succeeded', requestKey: key, receipt: {requestId, accepted: 2, uncertain: 1, suppressed: 0}});
    expect(await readPending(identity(), 'email-dispatch', 'queue')).toBeNull();
  });

  it('preserves a lost response and uses the same original key for lookup without resending', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('response lost'));
    const ctx = context(request);
    expect((await submitEmailDispatch(ctx, 'Review queued notifications', await revision(ctx))).status).toBe('unknown');
    const attempt = await restoreEmailDispatch(ctx);
    expect(attempt).toMatchObject({kind: 'owned', requestKey: key});
    request.mockResolvedValueOnce({status: 'not_found'});
    expect(await lookupEmailDispatch(ctx, attempt!)).toEqual({status: 'not_found'});
    expect(await restoreEmailDispatch(ctx)).toMatchObject({kind: 'owned'});
    expect(request).toHaveBeenLastCalledWith(`operations/requests/${key}`);
    request.mockResolvedValueOnce({status: 'succeeded', request_id: requestId, receipt});
    expect((await lookupEmailDispatch(ctx, attempt!)).status).toBe('succeeded');
    expect(await restoreEmailDispatch(ctx)).toMatchObject({kind: 'ready'});
    expect(request).toHaveBeenCalledTimes(3);
  });

  it('keeps the original key when response counts or resource identity are invalid', async () => {
    const request = vi.fn().mockResolvedValue({...receipt, accepted: 20, uncertain: 1});
    const ctx = context(request);
    expect((await submitEmailDispatch(ctx, 'Review queued notifications', await revision(ctx))).status).toBe('unknown');
    expect(await restoreEmailDispatch(ctx)).toMatchObject({kind: 'owned', requestKey: key});
  });

  it('rejects staff, missing permission and unavailable recovery storage before dispatch', async () => {
    const request = vi.fn();
    const staff = {...context(request), identity: {...identity(), role: 'staff' as const}};
    await expect(submitEmailDispatch(staff, 'Review queued notifications', '')).rejects.toThrow('unavailable');
    const broken = {getItem: () => null, setItem: () => {throw new Error('quota');}, removeItem: () => {}, clear: () => {}, key: () => null, length: 0} satisfies Storage;
    const ctx = context(request);
    const observed = await revision(ctx);
    await expect(submitEmailDispatch({...ctx, storage: broken}, 'Review queued notifications', observed)).rejects.toThrow();
    expect(request).not.toHaveBeenCalled();
  });
});
