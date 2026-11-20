import {webcrypto} from 'node:crypto';
import {afterEach, beforeEach, describe, expect, it} from 'vitest';
import {clearMfaAuthorityCheckpoint, createMfaAuthorityCheckpoint, MFA_AUTHORITY_KEY, mfaActorDigest, readMfaAuthorityCheckpoint, writeMfaAuthorityCheckpoint} from '../../src/session/mfaAuthority';
import type {MfaRecoveryIntent} from '../../src/session/mfaRecovery';
import type {AdminUser} from '../../src/session/SessionProvider';

const originalCrypto = globalThis.crypto;
const intent: MfaRecoveryIntent = {factor_id: '11111111-1111-4111-8111-111111111111', challenge_id: '22222222-2222-4222-8222-222222222222', verification_id: 'a'.repeat(64), session_id: 'session-one', user_id: 'actor-one', starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: 1_800_000_000_000};
const user: AdminUser = {id: intent.user_id, sessionId: intent.session_id, email: 'person@example.test', role: 'staff', permissions: ['users.read', 'overview.read'], principalId: '33333333-3333-4333-8333-333333333333', expiresAt: '2030-01-01T00:00:00.000Z', assuranceLevel: 1, mfaAt: null, emailVerifiedAt: null, mfaAvailable: true, mfaRequired: false, financialModel: 'canonical_evidence_ledger'};
beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true}); sessionStorage.clear();});
afterEach(() => {sessionStorage.clear(); Object.defineProperty(globalThis, 'crypto', {value: originalCrypto, configurable: true});});

describe('MFA authority checkpoint', () => {
  it('stores only intent and authority digests, canonicalizing permissions', async () => {
    const checkpoint = await createMfaAuthorityCheckpoint(intent, user); writeMfaAuthorityCheckpoint(checkpoint);
    expect(readMfaAuthorityCheckpoint()).toEqual(checkpoint);
    const raw = sessionStorage.getItem(MFA_AUTHORITY_KEY)!;
    for (const privateValue of [user.email, user.id, user.sessionId, user.principalId!, intent.verification_id, intent.factor_id]) expect(raw).not.toContain(privateValue);
    expect(await mfaActorDigest({...user, permissions: [...user.permissions].reverse()})).toBe(checkpoint.authority);
    expect(await mfaActorDigest({...user, permissions: ['overview.read']})).not.toBe(checkpoint.authority);
    expect(await mfaActorDigest({...user, principalId: '44444444-4444-4444-8444-444444444444'})).not.toBe(checkpoint.authority);
    clearMfaAuthorityCheckpoint(checkpoint); expect(readMfaAuthorityCheckpoint()).toBeNull();
  });

  it('never overwrites an unresolved checkpoint and refuses a different or malformed record', async () => {
    const checkpoint = await createMfaAuthorityCheckpoint(intent, user); writeMfaAuthorityCheckpoint(checkpoint);
    expect(() => writeMfaAuthorityCheckpoint(checkpoint)).toThrow();
    expect(() => clearMfaAuthorityCheckpoint({...checkpoint, intent: 'b'.repeat(64)})).toThrow();
    expect(readMfaAuthorityCheckpoint()).toEqual(checkpoint);
    sessionStorage.setItem(MFA_AUTHORITY_KEY, JSON.stringify({...checkpoint, code: '123456'}));
    expect(() => readMfaAuthorityCheckpoint()).toThrow();
    expect(() => clearMfaAuthorityCheckpoint(checkpoint)).toThrow();
    expect(sessionStorage.getItem(MFA_AUTHORITY_KEY)).not.toBeNull();
  });
});
