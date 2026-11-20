import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { readPending, type PendingIdentity } from '../../src/features/core';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { parseGatewayDetail } from '../../src/features/operations/contracts';
import { lookupGatewayEnrollment, parseGatewayPublicIdentity, restoreGatewayEnrollment, retryGatewayEnrollment, submitGatewayEnrollment, type GatewayEnrollmentContext, type GatewayEnrollmentIntent } from '../../src/features/operations/gatewayEnrollment';

const actor = '22222222-2222-4222-8222-222222222222', installation = '33333333-3333-4333-8333-333333333333', key = '44444444-4444-4444-8444-444444444444', operation = '55555555-5555-4555-8555-555555555555', device = '66666666-6666-4666-8666-666666666666';
const time = '2026-11-16T08:00:00.000Z';
let intent: GatewayEnrollmentIntent, publicIdentity: Record<string, unknown>, detail: Record<string, unknown>;
const receipt = {request_id: operation, resource_type: 'gateway_devices', resource_id: device, version: 1, status: 'succeeded'};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.com', role: 'admin', permissions: ['gateway.read', 'gateway.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: GatewayEnrollmentContext['request']): GatewayEnrollmentContext {return {request, identity: identity(), financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: GatewayEnrollmentContext) {const state = await restoreGatewayEnrollment(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, true, ['sign', 'verify']);
  const bytes = new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey));
  const publicKey = btoa(String.fromCharCode(...bytes));
  const fingerprint = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((value) => value.toString(16).padStart(2, '0')).join('');
  publicIdentity = {contract_version: 1, installation_id: installation, public_key_spki_base64: publicKey, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64)};
  intent = {label: 'Receiver handset', app_id: 'app.collect.gateway', installation_id: installation, public_key_spki_base64: publicKey, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64), reason: 'Review device identity'};
  const resource = {id: device, label: intent.label, app_id: intent.app_id, installation_id: installation, public_key_spki_base64: publicKey, key_sha256: fingerprint, signing_certificate_sha256: intent.signing_certificate_sha256, state: 'pending', version: 1, created_at: time, activated_at: null, revoked_at: null, last_heartbeat_at: null, carrier_proof: false, send_authority: false};
  detail = {resource_type: 'gateway_devices', resource, current_actor_id: actor, can_manage: true, related_truncated: false, related: {heartbeats: []}, enrollment: {contract_version: 1, device_id: device, installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: intent.signing_certificate_sha256}};
});
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('Gateway enrollment', () => {
  it('validates the exact handset identity, canonical public key, P-256 curve and fingerprints', async () => {
    expect(await parseGatewayPublicIdentity(JSON.stringify(publicIdentity))).toEqual({installation_id: installation, public_key_spki_base64: intent.public_key_spki_base64, key_sha256: intent.key_sha256, signing_certificate_sha256: intent.signing_certificate_sha256});
    await expect(parseGatewayPublicIdentity(JSON.stringify({...publicIdentity, key_sha256: 'c'.repeat(64)}))).rejects.toThrow();
    await expect(parseGatewayPublicIdentity(JSON.stringify({...publicIdentity, extra: 'value'}))).rejects.toThrow();
    await expect(parseGatewayPublicIdentity(JSON.stringify(publicIdentity).replace('{', '{"contract_version":1,'))).rejects.toThrow('duplicate');
    await expect(parseGatewayPublicIdentity(JSON.stringify(publicIdentity).replace(/}$/, ',}'))).rejects.toThrow();
    const invalidPoint = new Uint8Array(91); invalidPoint.set(new Uint8Array(await crypto.subtle.exportKey('spki', (await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, true, ['sign', 'verify'])).publicKey)).slice(0, 27));
    const invalidFingerprint = [...new Uint8Array(await crypto.subtle.digest('SHA-256', invalidPoint))].map((value) => value.toString(16).padStart(2, '0')).join('');
    await expect(parseGatewayPublicIdentity(JSON.stringify({...publicIdentity, public_key_spki_base64: btoa(String.fromCharCode(...invalidPoint)), key_sha256: invalidFingerprint}))).rejects.toThrow();
  });
  it('requires the disabled gate, non-staff permissions and the legacy backend contract', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitGatewayEnrollment({...ctx, enabled: false}, intent, '')).rejects.toThrow('not enabled');
    await expect(submitGatewayEnrollment({...ctx, identity: {...ctx.identity, role: 'staff'}}, intent, '')).rejects.toThrow('unavailable');
    await expect(submitGatewayEnrollment({...ctx, identity: {...ctx.identity, permissions: ['gateway.manage', 'gateway.read']}}, intent, '')).rejects.toThrow('unavailable');
    await expect(submitGatewayEnrollment({...ctx, financialModel: 'canonical_evidence_ledger'}, intent, '')).rejects.toThrow('unavailable');
    expect(request).not.toHaveBeenCalled();
  });
  it('persists original intent before POST, verifies the enrolled device, then clears recovery', async () => {
    const request = vi.fn(async (path: string, options?: {body?: unknown; idempotencyKey?: string}) => {
      if (path === 'gateway/devices') {
        expect(options).toMatchObject({method: 'POST', body: intent, idempotencyKey: key});
        expect(await readPending(identity(), 'gateway-device-enrollment', 'new')).toMatchObject({request_key: key, intent});
        return receipt;
      }
      expect(path).toBe(`gateway/devices/${device}`); return detail;
    });
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitGatewayEnrollment(ctx, intent, observed)).toEqual({status: 'succeeded', receipt: {requestId: operation, deviceId: device, version: 1}});
    expect(await readPending(identity(), 'gateway-device-enrollment', 'new')).toBeNull();
    expect(await restoreGatewayEnrollment(ctx)).toMatchObject({kind: 'ready'});
    expect((await parseGatewayDetail(detail, device, actor, false)).enrollment).toEqual(detail.enrollment);
    expect(request).toHaveBeenCalledTimes(2);
  });
  it('recovers the original lost-response key without resending and validates device identity', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('response lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'succeeded', request_id: operation, receipt}).mockResolvedValueOnce(detail);
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitGatewayEnrollment(ctx, intent, observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreGatewayEnrollment(ctx);
    expect(await lookupGatewayEnrollment(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect((await lookupGatewayEnrollment(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(2, `operations/requests/${key}`);
    expect(request).toHaveBeenNthCalledWith(3, `operations/requests/${key}`);
    expect(request).toHaveBeenCalledTimes(4);
    expect(await restoreGatewayEnrollment(ctx)).toMatchObject({kind: 'ready'});
  });
  it('allows explicit identical retry only after a fresh original-key lookup', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('response lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(receipt).mockResolvedValueOnce(detail);
    const ctx = context(request), observed = await revision(ctx);
    await submitGatewayEnrollment(ctx, intent, observed);
    const pending = await restoreGatewayEnrollment(ctx);
    expect(await lookupGatewayEnrollment(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect((await retryGatewayEnrollment(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(3, `operations/requests/${key}`);
    expect(request).toHaveBeenNthCalledWith(4, 'gateway/devices', {method: 'POST', body: intent, idempotencyKey: key});
    expect(request).toHaveBeenCalledTimes(5);
  });
  it('preserves recovery when the saved device differs or the original result is pending', async () => {
    const altered = {...detail, resource: {...detail.resource as Record<string, unknown>, label: 'Different handset'}};
    const request = vi.fn().mockResolvedValueOnce(receipt).mockResolvedValueOnce(altered).mockResolvedValueOnce({status: 'pending', request_id: operation, receipt: null});
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitGatewayEnrollment(ctx, intent, observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreGatewayEnrollment(ctx);
    expect(await lookupGatewayEnrollment(ctx, pending)).toEqual({status: 'pending'});
    expect((await restoreGatewayEnrollment(ctx)).kind).toBe('owned');
    expect(request).toHaveBeenCalledTimes(3);
  });
  it('blocks stale confirmations, changed authorities, and a crash with no retry intent', async () => {
    const request = vi.fn(), ctx = context(request), observed = await revision(ctx);
    await withPendingFence({identity: ctx.identity, family: 'gateway-device-enrollment', resourceId: 'new', isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async (access) => {access.reserve(key, access.read().revision); access.clear(key);});
    await expect(submitGatewayEnrollment(ctx, intent, observed)).rejects.toThrow('Shared request recovery');
    const next = await revision(ctx), original = {...ctx, request: vi.fn().mockRejectedValue(new Error('lost'))};
    await submitGatewayEnrollment(original, intent, next);
    const changed = {...ctx, identity: {...ctx.identity, sessionId: 'other'}};
    expect(await restoreGatewayEnrollment(changed)).toEqual({kind: 'foreign'});
    const blank: Storage = {length: 0, clear() {}, getItem() {return null;}, key() {return null;}, removeItem() {}, setItem() {}};
    const crash = {...ctx, storage: blank, request: vi.fn().mockResolvedValue({status: 'not_found'})};
    const pending = await restoreGatewayEnrollment(crash);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    expect(await lookupGatewayEnrollment(crash, pending)).toEqual({status: 'not_found', retryAvailable: false});
    await expect(retryGatewayEnrollment(crash, pending)).rejects.toThrow('intent is unavailable');
    expect(request).not.toHaveBeenCalled();
  });
});
