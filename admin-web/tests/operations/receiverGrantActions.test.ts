import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readPending, type PendingIdentity } from '../../src/features/core';
import { parseGrantPage } from '../../src/features/operations/contracts';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { lookupGrantRevocation, restoreGrantRevocation, retryGrantRevocation, submitGrantRevocation, type ReceiverGrantActionContext } from '../../src/features/operations/receiverGrantActions';

const grantId = '11111111-1111-4111-8111-111111111111', actor = '22222222-2222-4222-8222-222222222222', device = '33333333-3333-4333-8333-333333333333', payee = '44444444-4444-4444-8444-444444444444', key = '55555555-5555-4555-8555-555555555555', operationId = '66666666-6666-4666-8666-666666666666';
const time = '2026-11-16T08:00:00.000Z';
const grant = {id: grantId, device_id: device, device_label: 'Receiver handset', installation_id: device, key_sha256: 'a'.repeat(64), payee_id: payee, payee_label: 'Payee', payee_network: 'mtn_momo', payee_momo_number_or_code: '123456', status: 'active', version: 1, created_by_admin_id: actor, created_at: time, revoked_by_admin_id: null, revoked_at: null, capture_authority: true, send_authority: false, financial_authority: false};
const parsed = parseGrantPage({rows: [grant], total: 1, limit: 25, offset: 0}, 0).rows[0];
const receipt = {request_id: operationId, resource_type: 'receiver_capture_grants', resource_id: grantId, version: 2, status: 'succeeded'};
const detail = {resource_type: 'receiver_capture_grants', resource: grant, current_actor_id: actor, can_manage: true, related: {captures: []}, related_total: 0, related_limit: 25, related_offset: 0};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.com', role: 'admin', permissions: ['gateway.read', 'gateway.manage'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: ReceiverGrantActionContext['request']): ReceiverGrantActionContext {return {request, identity: identity(), grant: parsed, canManage: true, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: ReceiverGrantActionContext) {const state = await restoreGrantRevocation(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('Receiver grant revocation', () => {
  it('requires the default-off gate and current non-staff read/manage authority on the legacy contract', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitGrantRevocation({...ctx, enabled: false}, 'Review capture access', '')).rejects.toThrow('not enabled');
    await expect(submitGrantRevocation({...ctx, identity: {...ctx.identity, role: 'staff'}}, 'Review capture access', '')).rejects.toThrow('unavailable');
    await expect(submitGrantRevocation({...ctx, identity: {...ctx.identity, permissions: ['gateway.manage']}}, 'Review capture access', '')).rejects.toThrow('unavailable');
    await expect(submitGrantRevocation({...ctx, canManage: false}, 'Review capture access', '')).rejects.toThrow('unavailable');
    await expect(submitGrantRevocation({...ctx, financialModel: 'canonical_evidence_ledger'}, 'Review capture access', '')).rejects.toThrow('unavailable');
    expect(request).not.toHaveBeenCalled();
  });
  it('retains the exact intent and key before posting, then validates and clears a separate operation receipt', async () => {
    const request = vi.fn(async (path: string, options?: {body?: unknown; idempotencyKey?: string}) => {
      expect(path).toBe(`gateway/receiver-grants/${grantId}/revoke`);
      expect(options).toMatchObject({method: 'POST', body: {expected_version: 1, reason: 'Review capture access'}, idempotencyKey: key});
      expect(await readPending(identity(), 'receiver-capture-grant', grantId)).toMatchObject({request_key: key, intent: {expected_version: 1, reason: 'Review capture access'}});
      return receipt;
    });
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitGrantRevocation(ctx, 'Review capture access', observed)).toEqual({status: 'succeeded', receipt: {requestId: operationId, grantId, version: 2}});
    expect(await readPending(identity(), 'receiver-capture-grant', grantId)).toBeNull();
    expect(await restoreGrantRevocation(ctx)).toMatchObject({kind: 'ready'});
    expect(request).toHaveBeenCalledTimes(1);
  });
  it('retains an unknown original request, checks it without replay and clears only a verified receipt', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('response lost')).mockResolvedValueOnce({found: false}).mockResolvedValueOnce({found: true, receipt});
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitGrantRevocation(ctx, 'Review capture access', observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreGrantRevocation(ctx);
    expect(pending).toMatchObject({kind: 'owned', requestKey: key});
    expect(await lookupGrantRevocation(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect(request).toHaveBeenLastCalledWith(`gateway/receiver-requests/${key}`);
    expect((await lookupGrantRevocation(ctx, pending)).status).toBe('succeeded');
    expect(await restoreGrantRevocation(ctx)).toMatchObject({kind: 'ready'});
    expect(request).toHaveBeenCalledTimes(3);
  });
  it('explicitly retries only the original key and intent after fresh lookup and matching grant detail', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('response lost')).mockResolvedValueOnce({found: false}).mockResolvedValueOnce({found: false}).mockResolvedValueOnce(detail).mockResolvedValueOnce(receipt);
    const ctx = context(request), observed = await revision(ctx);
    await submitGrantRevocation(ctx, 'Review capture access', observed);
    const pending = await restoreGrantRevocation(ctx);
    expect(await lookupGrantRevocation(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect(request).toHaveBeenCalledTimes(2);
    expect((await retryGrantRevocation(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(3, `gateway/receiver-requests/${key}`);
    expect(request).toHaveBeenNthCalledWith(4, `gateway/receiver-grants/${grantId}?limit=25&offset=0`);
    expect(request).toHaveBeenNthCalledWith(5, `gateway/receiver-grants/${grantId}/revoke`, {method: 'POST', body: {expected_version: 1, reason: 'Review capture access'}, idempotencyKey: key});
  });
  it('never retries if the grant changed, the receipt was malformed, or the original intent is absent', async () => {
    const revoked = {...grant, status: 'revoked', version: 2, capture_authority: false, revoked_by_admin_id: actor, revoked_at: time};
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({found: false}).mockResolvedValueOnce({...detail, resource: revoked});
    const ctx = context(request), observed = await revision(ctx);
    await submitGrantRevocation(ctx, 'Review capture access', observed);
    const pending = await restoreGrantRevocation(ctx);
    await expect(retryGrantRevocation(ctx, pending)).rejects.toThrow('grant changed');
    expect(request).toHaveBeenCalledTimes(3);
    expect((await restoreGrantRevocation(ctx)).kind).toBe('owned');
    request.mockResolvedValueOnce({found: true, receipt: {...receipt, resource_id: payee}});
    await expect(lookupGrantRevocation(ctx, pending)).rejects.toThrow();
    expect((await restoreGrantRevocation(ctx)).kind).toBe('owned');
    const other = context(vi.fn().mockResolvedValue({found: false}));
    other.storage = {length: 0, clear() {}, getItem() {return null;}, key() {return null;}, removeItem() {}, setItem() {}};
    const crashRecovery = await restoreGrantRevocation(other);
    expect(crashRecovery).toEqual({kind: 'owned', requestKey: key, attempt: null});
    expect(await lookupGrantRevocation(other, crashRecovery)).toEqual({status: 'not_found', retryAvailable: false});
    await expect(retryGrantRevocation(other, crashRecovery)).rejects.toThrow('intent is unavailable');
  });
  it('blocks a foreign authority and stale confirmation without posting', async () => {
    const request = vi.fn(), ctx = context(request), observed = await revision(ctx);
    await withPendingFence({identity: ctx.identity, family: 'receiver-capture-grant', resourceId: grantId, isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async (access) => {access.reserve(key, access.read().revision); access.clear(key);});
    await expect(submitGrantRevocation(ctx, 'Review capture access', observed)).rejects.toThrow('Shared request recovery');
    const fresh = await revision(ctx);
    const first = {...ctx, request: vi.fn().mockRejectedValue(new Error('lost'))};
    await submitGrantRevocation(first, 'Review capture access', fresh);
    const other = {...ctx, identity: {...ctx.identity, sessionId: 'other-session'}};
    expect(await restoreGrantRevocation(other)).toEqual({kind: 'foreign'});
    expect(await submitGrantRevocation(other, 'Review capture access', fresh)).toEqual({status: 'existing', pending: {kind: 'foreign'}});
    expect(request).not.toHaveBeenCalled();
  });
});
