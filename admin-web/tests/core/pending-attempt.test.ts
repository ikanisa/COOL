import { webcrypto } from 'node:crypto';
import { beforeEach, describe, expect, it } from 'vitest';
import { bindPendingIdentity, canonicalRequestId, clearEvidenceContext, clearPending, EVIDENCE_CONTEXT_KEY, listPending, pendingAuthority, PENDING_KEY, readEvidenceContext, readPending, retainEvidenceContext, retainPending } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';

const now = Date.parse('2026-11-16T12:00:00.000Z');
const identity: PendingIdentity = {
  id: '11111111-1111-4111-8111-111111111111', sessionId: '22222222-2222-4222-8222-222222222222',
  email: 'operator@example.test', role: 'admin', permissions: ['collections.read', 'collections.manage'],
  expiresAt: '2026-11-16T18:00:00.000Z',
};
const groupId = '33333333-3333-4333-8333-333333333333';
const key = '44444444-4444-4444-8444-444444444444';
const body = { title: 'Verified group', collection_type: 'ikimina', description: '', purpose_label: null, status: 'active', reason: 'Correct recorded name', expected_version: 3 };

beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  sessionStorage.clear();
});

describe('compatible pending request recovery', () => {
  it('matches the Flutter authority digest and canonical request identity', async () => {
    expect(await pendingAuthority(identity)).toBe('a056beea7d10c54473898ce62ebc2f595f1cc85d39a1c6200c5ba38bc025c498');
    expect(await canonicalRequestId('c0993074-cd04-4b62-a697-23b42b7450b6', '49dc515e-d96f-499f-af64-164f8c338152')).toBe('c5f124b6-e9cc-47ff-8a75-07acdc5dfe39');
  });

  it('matches v90 receipt derivation for the exact case and UTF-8 spelling of a retained principal', async () => {
    const originalKey = 'receipt-check-0001';
    const vectors = [
      ['Legacy-Principal-47', 'c06c9f2f-eb12-4c12-8fbf-34353eb7f1e6'],
      ['legacy-principal-47', '1ac9411a-b732-49e8-8e01-e8bd06489905'],
      ['Équipe-É4', 'c7e0d797-9462-4337-8252-220ae6d2d65f'],
      ['E\u0301quipe-É4', '953ea4c9-b786-453b-8714-6ed2e53658c4'],
    ];
    for (const [principalId, expected] of vectors) expect(await canonicalRequestId(principalId, originalKey)).toBe(expected);
    await expect(canonicalRequestId('Legacy-Principal-47 ', originalKey)).rejects.toThrow();
    await expect(canonicalRequestId('Legacy-Principal-47', 'invalid key')).rejects.toThrow();
  });

  it('retains the original intent before dispatch and refuses a different key', async () => {
    await retainPending(identity, 'operating-updategroup', groupId, key, 'collections.manage', body, sessionStorage, now);
    const envelope = JSON.parse(sessionStorage.getItem(PENDING_KEY)!);
    expect(envelope.version).toBe(1);
    expect(envelope.entries[0].request_key).toBe(key);
    expect((await readPending(identity, 'operating-updategroup', groupId, sessionStorage, now))?.intent).toEqual(body);
    await expect(retainPending(identity, 'operating-updategroup', groupId, '55555555-5555-4555-8555-555555555555', 'collections.manage', body, sessionStorage, now)).rejects.toThrow();
    expect((await readPending(identity, 'operating-updategroup', groupId, sessionStorage, now))?.request_key).toBe(key);
  });

  it('preserves other families and refuses authority or secret-field mismatches', async () => {
    await retainPending(identity, 'operating-updategroup', groupId, key, 'collections.manage', body, sessionStorage, now);
    await retainPending(identity, 'another-family', 'new', 'reference-123', 'collections.read', { reason: 'A separate pending item' }, sessionStorage, now);
    expect(await listPending(identity, 'another-family', 'collections.read', sessionStorage, now)).toHaveLength(1);
    await clearPending(identity, 'operating-updategroup', groupId, key, sessionStorage, now);
    expect((await readPending(identity, 'another-family', 'new', sessionStorage, now))?.request_key).toBe('reference-123');
    await expect(readPending({ ...identity, sessionId: 'another-session' }, 'another-family', 'new', sessionStorage, now)).rejects.toThrow();
    await expect(retainPending(identity, 'secret-family', 'new', 'reference-456', 'collections.read', { password: 'never store' }, sessionStorage, now)).rejects.toThrow();
  });

  it('fails closed before sending when recovery storage does not persist', async () => {
    const refused: Storage = { length: 0, clear() {}, getItem() { return null; }, key() { return null; }, removeItem() {}, setItem() { throw new Error('quota'); } };
    await expect(retainPending(identity, 'operating-updategroup', groupId, key, 'collections.manage', body, refused, now)).rejects.toThrow();
  });

  it('preserves the same authority, clears definitive changes, and never clears malformed data as a different authority', async () => {
    await retainPending(identity, 'operating-updategroup', groupId, key, 'collections.manage', body, sessionStorage, now);
    const original = sessionStorage.getItem(PENDING_KEY);
    expect(await bindPendingIdentity(identity, sessionStorage, now)).toBe('preserved');
    expect(sessionStorage.getItem(PENDING_KEY)).toBe(original);
    expect(await bindPendingIdentity({ ...identity, sessionId: 'different-session' }, sessionStorage, now, () => false)).toBe('stale');
    expect(sessionStorage.getItem(PENDING_KEY)).toBe(original);
    expect(await bindPendingIdentity({ ...identity, sessionId: 'different-session' }, sessionStorage, now)).toBe('cleared');
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
    sessionStorage.setItem(PENDING_KEY, '{broken');
    await expect(bindPendingIdentity(identity, sessionStorage, now)).rejects.toThrow();
    expect(sessionStorage.getItem(PENDING_KEY)).toBe('{broken');
    expect(await bindPendingIdentity(null, sessionStorage, now)).toBe('cleared');
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('binds and clears the evidence context without retaining evidence text', async () => {
    const operator = { ...identity, permissions: [...identity.permissions, 'payments.manage', 'payments.write'], expiresAt: '2100-01-01T00:00:00.000Z' };
    await retainEvidenceContext(operator, { request_key: key, group_id: groupId, payee_id: groupId, group_version: 2, receiver_sha256: 'a'.repeat(64) });
    expect((await readEvidenceContext(operator))?.receiver_sha256).toBe('a'.repeat(64));
    expect(sessionStorage.getItem(EVIDENCE_CONTEXT_KEY)).not.toContain('raw evidence');
    expect(await bindPendingIdentity(operator)).toBe('preserved');
    expect(await bindPendingIdentity({ ...operator, sessionId: 'different-session' }, sessionStorage, Date.now(), () => false)).toBe('stale');
    expect(sessionStorage.getItem(EVIDENCE_CONTEXT_KEY)).not.toBeNull();
    await expect(clearEvidenceContext(operator, 'wrong-reference')).rejects.toThrow();
    expect(await bindPendingIdentity(null)).toBe('cleared');
    expect(sessionStorage.getItem(EVIDENCE_CONTEXT_KEY)).toBeNull();
    await retainEvidenceContext(operator, { request_key: key, group_id: groupId, payee_id: groupId, group_version: 2, receiver_sha256: 'a'.repeat(64) });
    expect(await bindPendingIdentity({ ...operator, sessionId: 'different-session' })).toBe('cleared');
    expect(sessionStorage.getItem(EVIDENCE_CONTEXT_KEY)).toBeNull();
    sessionStorage.setItem(EVIDENCE_CONTEXT_KEY, '{broken');
    await expect(bindPendingIdentity(operator)).rejects.toThrow();
    expect(sessionStorage.getItem(EVIDENCE_CONTEXT_KEY)).toBe('{broken');
    expect(await bindPendingIdentity(null)).toBe('cleared');
  });
});
