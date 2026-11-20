import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { readPending, type PendingIdentity } from '../../src/features/core';
import { parseGatewayPage, type GatewayDevice } from '../../src/features/operations/contracts';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { lookupGatewayRevocation, restoreGatewayRevocation, retryGatewayRevocation, submitGatewayRevocation, type GatewayRevocationContext } from '../../src/features/operations/gatewayRevocation';

const actor = '22222222-2222-4222-8222-222222222222', installation = '33333333-3333-4333-8333-333333333333', key = '44444444-4444-4444-8444-444444444444', operation = '55555555-5555-4555-8555-555555555555', deviceId = '66666666-6666-4666-8666-666666666666';
const time = '2026-11-16T08:00:00.000Z';
let device: GatewayDevice, current: Record<string, unknown>, revoked: Record<string, unknown>, changed: Record<string, unknown>;
const receipt = {request_id: operation, resource_type: 'gateway_devices', resource_id: deviceId, version: 2, status: 'succeeded'};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.com', role: 'admin', permissions: ['gateway.read', 'gateway.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: GatewayRevocationContext['request']): GatewayRevocationContext {return {request, identity: identity(), device, canManage: true, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: GatewayRevocationContext) {const state = await restoreGatewayRevocation(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, true, ['sign', 'verify']);
  const bytes = new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey));
  const publicKey = btoa(String.fromCharCode(...bytes));
  const fingerprint = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((value) => value.toString(16).padStart(2, '0')).join('');
  const base = {id: deviceId, label: 'Receiver handset', app_id: 'app.collect.gateway', installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64), state: 'pending', version: 1, created_at: time, activated_at: null, revoked_at: null, last_heartbeat_at: null, carrier_proof: false, send_authority: false};
  device = parseGatewayPage({rows: [base], total: 1}, 0).rows[0];
  const detail = (resource: Record<string, unknown>) => ({resource_type: 'gateway_devices', resource: {...resource, public_key_spki_base64: publicKey}, current_actor_id: actor, can_manage: true, related_truncated: false, related: {heartbeats: []}, enrollment: {contract_version: 1, device_id: deviceId, installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64)}});
  current = detail(base);
  revoked = detail({...base, state: 'revoked', version: 2, revoked_at: time});
  changed = detail({...base, state: 'active', version: 2, activated_at: time});
});
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('Gateway device revocation', () => {
  it('requires its gate, non-staff read/manage/recovery permissions and legacy contract', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitGatewayRevocation({...ctx, enabled: false}, 'Review device identity', '')).rejects.toThrow('not enabled');
    await expect(submitGatewayRevocation({...ctx, identity: {...ctx.identity, role: 'staff'}}, 'Review device identity', '')).rejects.toThrow('unavailable');
    await expect(submitGatewayRevocation({...ctx, identity: {...ctx.identity, permissions: ['gateway.manage', 'gateway.read']}}, 'Review device identity', '')).rejects.toThrow('unavailable');
    await expect(submitGatewayRevocation({...ctx, canManage: false}, 'Review device identity', '')).rejects.toThrow('unavailable');
    await expect(submitGatewayRevocation({...ctx, financialModel: 'canonical_evidence_ledger'}, 'Review device identity', '')).rejects.toThrow('unavailable');
    expect(request).not.toHaveBeenCalled();
  });
  it('retains the current version and fingerprints before POST and verifies the revoked device', async () => {
    const expected = {expected_version: 1, expected_key_sha256: device.key_sha256, expected_signing_certificate_sha256: device.signing_certificate_sha256, reason: 'Review device identity'};
    const request = vi.fn(async (path: string, options?: {body?: unknown; idempotencyKey?: string}) => {
      if (path.endsWith('/revoke')) {
        expect(options).toMatchObject({method: 'POST', body: expected, idempotencyKey: key});
        expect(await readPending(identity(), 'gateway-device-revoke', deviceId)).toMatchObject({request_key: key, intent: expected});
        return receipt;
      }
      expect(path).toBe(`gateway/devices/${deviceId}`); return revoked;
    });
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitGatewayRevocation(ctx, 'Review device identity', observed)).toEqual({status: 'succeeded', receipt: {requestId: operation, deviceId, version: 2}});
    expect(await readPending(identity(), 'gateway-device-revoke', deviceId)).toBeNull();
    expect(await restoreGatewayRevocation(ctx)).toMatchObject({kind: 'ready'});
    expect(request).toHaveBeenCalledTimes(2);
  });
  it('checks a lost response without replay and clears only the verified revoked device', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'succeeded', request_id: operation, receipt}).mockResolvedValueOnce(revoked);
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitGatewayRevocation(ctx, 'Review device identity', observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreGatewayRevocation(ctx);
    expect(await lookupGatewayRevocation(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect((await lookupGatewayRevocation(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(2, `operations/requests/${key}`);
    expect(request).toHaveBeenNthCalledWith(3, `operations/requests/${key}`);
    expect(request).toHaveBeenCalledTimes(4);
    expect(await restoreGatewayRevocation(ctx)).toMatchObject({kind: 'ready'});
  });
  it('explicitly retries the same key and exact intent only after a fresh receipt and device check', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(current).mockResolvedValueOnce(receipt).mockResolvedValueOnce(revoked);
    const ctx = context(request), observed = await revision(ctx);
    await submitGatewayRevocation(ctx, 'Review device identity', observed);
    const pending = await restoreGatewayRevocation(ctx);
    expect(await lookupGatewayRevocation(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect((await retryGatewayRevocation(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(3, `operations/requests/${key}`);
    expect(request).toHaveBeenNthCalledWith(4, `gateway/devices/${deviceId}`);
    expect(request).toHaveBeenNthCalledWith(5, `gateway/devices/${deviceId}/revoke`, {method: 'POST', body: {expected_version: 1, expected_key_sha256: device.key_sha256, expected_signing_certificate_sha256: device.signing_certificate_sha256, reason: 'Review device identity'}, idempotencyKey: key});
    expect(request).toHaveBeenCalledTimes(6);
  });
  it('does not retry a changed version and retains an unverified receipt', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(changed).mockResolvedValueOnce({status: 'succeeded', request_id: operation, receipt: {...receipt, version: 3}});
    const ctx = context(request), observed = await revision(ctx);
    await submitGatewayRevocation(ctx, 'Review device identity', observed);
    const pending = await restoreGatewayRevocation(ctx);
    await expect(retryGatewayRevocation(ctx, pending)).rejects.toThrow('device changed');
    expect(request).toHaveBeenCalledTimes(3);
    await expect(lookupGatewayRevocation(ctx, pending)).rejects.toThrow();
    expect((await restoreGatewayRevocation(ctx)).kind).toBe('owned');
  });
  it('fails closed after concurrent completion, actor change, or loss of the local intent', async () => {
    const request = vi.fn(), ctx = context(request), observed = await revision(ctx);
    await withPendingFence({identity: ctx.identity, family: 'gateway-device-revoke', resourceId: deviceId, isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async (access) => {access.reserve(key, access.read().revision); access.clear(key);});
    await expect(submitGatewayRevocation(ctx, 'Review device identity', observed)).rejects.toThrow('Shared request recovery');
    const next = await revision(ctx), original = {...ctx, request: vi.fn().mockRejectedValue(new Error('lost'))};
    await submitGatewayRevocation(original, 'Review device identity', next);
    const other = {...ctx, identity: {...ctx.identity, sessionId: 'other'}};
    expect(await restoreGatewayRevocation(other)).toEqual({kind: 'foreign'});
    const blank: Storage = {length: 0, clear() {}, getItem() {return null;}, key() {return null;}, removeItem() {}, setItem() {}};
    const crash = {...ctx, storage: blank, request: vi.fn().mockResolvedValue({status: 'not_found'})};
    const pending = await restoreGatewayRevocation(crash);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    expect(await lookupGatewayRevocation(crash, pending)).toEqual({status: 'not_found', retryAvailable: false});
    await expect(retryGatewayRevocation(crash, pending)).rejects.toThrow('intent is unavailable');
    expect(request).not.toHaveBeenCalled();
  });
});
