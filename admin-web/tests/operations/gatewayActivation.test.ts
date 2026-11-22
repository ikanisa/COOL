import {beforeAll, beforeEach, describe, expect, it, vi} from 'vitest';
import { readPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import {parseGatewayPage, type GatewayDevice} from '../../src/features/operations/contracts';
import {gatewayTrustActions, type GatewayTrustContext} from '../../src/features/operations/gatewayDeviceTrust';
const {lookup: lookupGatewayActivation, restore: restoreGatewayActivation, retry: retryGatewayActivation, submit: submitGatewayActivation} = gatewayTrustActions.activate;

const actor = '22222222-2222-4222-8222-222222222222', installation = '33333333-3333-4333-8333-333333333333', key = '44444444-4444-4444-8444-444444444444', operation = '55555555-5555-4555-8555-555555555555', deviceId = '66666666-6666-4666-8666-666666666666';
const time = '2026-11-16T08:00:00.000Z';
const receipt = {request_id: operation, resource_type: 'gateway_devices', resource_id: deviceId, version: 2, status: 'succeeded'};
let device: GatewayDevice, current: Record<string, unknown>, active: Record<string, unknown>, changed: Record<string, unknown>;
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.test', role: 'admin', permissions: ['gateway.read', 'gateway.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: GatewayTrustContext['request']): GatewayTrustContext {return {request, identity: identity(), device, canManage: true, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: GatewayTrustContext) {const state = await restoreGatewayActivation(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, true, ['sign', 'verify']);
  const bytes = new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey)), encoded = btoa(String.fromCharCode(...bytes));
  const fingerprint = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((value) => value.toString(16).padStart(2, '0')).join('');
  const base = {id: deviceId, label: 'Synthetic handset', app_id: 'app.collect.gateway', installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64), state: 'pending', version: 1, created_at: time, activated_at: null, revoked_at: null, last_heartbeat_at: null, carrier_proof: false, send_authority: false};
  device = parseGatewayPage({rows: [base], total: 1}, 0).rows[0];
  const detail = (resource: Record<string, unknown>) => ({resource_type: 'gateway_devices', resource: {...resource, public_key_spki_base64: encoded}, current_actor_id: actor, can_manage: true, related_truncated: false, related: {heartbeats: []}, enrollment: {contract_version: 1, device_id: deviceId, installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64)}});
  current = detail(base); active = detail({...base, state: 'active', version: 2, activated_at: time}); changed = detail({...base, state: 'revoked', version: 2, revoked_at: time});
});
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('Legacy gateway activation', () => {
  it('requires the explicit gate, legacy model, current authority, and administrator permissions', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitGatewayActivation({...ctx, enabled: false}, 'Review device identity', '')).rejects.toThrow(/not enabled/);
    await expect(submitGatewayActivation({...ctx, financialModel: 'canonical_evidence_ledger'}, 'Review device identity', '')).rejects.toThrow(/unavailable/);
    await expect(submitGatewayActivation({...ctx, identity: {...ctx.identity, role: 'staff'}}, 'Review device identity', '')).rejects.toThrow(/unavailable/);
    await expect(submitGatewayActivation({...ctx, identity: {...ctx.identity, permissions: ['gateway.manage']}}, 'Review device identity', '')).rejects.toThrow(/unavailable/);
    await expect(submitGatewayActivation({...ctx, isCurrent: () => false}, 'Review device identity', '')).rejects.toThrow(/unavailable/);
    expect(request).not.toHaveBeenCalled();
  });
  it('retains the exact device version and fingerprints before posting and verifies the active device', async () => {
    const intent = {expected_version: 1, expected_key_sha256: device.key_sha256, expected_signing_certificate_sha256: device.signing_certificate_sha256, reason: 'Review device identity'};
    const request = vi.fn(async (path: string, options?: {body?: unknown; idempotencyKey?: string}) => {
      if (path.endsWith('/activate')) {expect(await readPending(identity(), 'gateway-device-activate', deviceId)).toMatchObject({request_key: key, intent}); expect(options).toEqual({method: 'POST', body: intent, idempotencyKey: key}); return receipt;}
      expect(path).toBe(`gateway/devices/${deviceId}`); return active;
    });
    const ctx = context(request);
    expect(await submitGatewayActivation(ctx, 'Review device identity', await revision(ctx))).toEqual({status: 'succeeded', receipt: {requestId: operation, deviceId, version: 2}});
    expect(await readPending(identity(), 'gateway-device-activate', deviceId)).toBeNull();
  });
  it('checks the original receipt and explicitly retries the same key and intent only while the device version remains pending', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost reply')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(current).mockResolvedValueOnce(receipt).mockResolvedValueOnce(active);
    const ctx = context(request);
    expect(await submitGatewayActivation(ctx, 'Review device identity', await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreGatewayActivation(ctx); expect(await lookupGatewayActivation(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect((await retryGatewayActivation(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(5, `gateway/devices/${deviceId}/activate`, {method: 'POST', body: {expected_version: 1, expected_key_sha256: device.key_sha256, expected_signing_certificate_sha256: device.signing_certificate_sha256, reason: 'Review device identity'}, idempotencyKey: key});
  });
  it('refuses a changed device and retains an unmatched original receipt', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(changed).mockResolvedValueOnce({status: 'succeeded', request_id: operation, receipt: {...receipt, version: 3}});
    const ctx = context(request); await submitGatewayActivation(ctx, 'Review device identity', await revision(ctx));
    const pending = await restoreGatewayActivation(ctx); await expect(retryGatewayActivation(ctx, pending)).rejects.toThrow(/device changed/i);
    await expect(lookupGatewayActivation(ctx, pending)).rejects.toThrow(); expect((await restoreGatewayActivation(ctx)).kind).toBe('owned');
    expect(request).toHaveBeenCalledTimes(4);
  });
  it('keeps the original reference without dispatch when the gate closes during retention', async () => {
    let enabled = true;
    const storage: Storage = {get length() {return sessionStorage.length;}, clear: () => sessionStorage.clear(), key: (index) => sessionStorage.key(index), getItem: (name) => sessionStorage.getItem(name), removeItem: (name) => sessionStorage.removeItem(name), setItem: (name, value) => {sessionStorage.setItem(name, value); enabled = false;}};
    const request = vi.fn(), ctx = {...context(request), storage, isEnabled: () => enabled};
    expect(await submitGatewayActivation(ctx, 'Review device identity', await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    expect(await readPending(identity(), 'gateway-device-activate', deviceId)).toMatchObject({request_key: key}); expect(request).not.toHaveBeenCalled();
  });
});
