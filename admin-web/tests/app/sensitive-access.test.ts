import {describe, expect, it, vi} from 'vitest';
import {verifySensitiveAccess} from '../../src/app/sensitive-access';
import type {AdminUser} from '../../src/session/SessionProvider';

const now = Date.parse('2026-11-16T12:00:00Z');
const user: AdminUser = {id: 'actor', email: 'team@example.test', role: 'admin', sessionId: 'session',
  expiresAt: '2026-11-16T15:00:00Z', permissions: ['overview.read'], assuranceLevel: 2,
  mfaAt: '2026-11-16T11:59:00Z', emailVerifiedAt: null, principalId: null, financialModel: 'transaction_journals'};

describe('sensitive action verification', () => {
  it('uses email proof for the email backend even when no proof is cached', async () => {
    const recheckSensitiveEmailVerification = vi.fn().mockResolvedValue(false);
    const session = {epoch: 2, verificationMode: 'email' as const, isCurrentAuthority: () => true, isRecentSensitiveVerification: () => true, recheckSensitiveEmailVerification};
    expect(await verifySensitiveAccess(session, user, now)).toBe(false);
    expect(recheckSensitiveEmailVerification).toHaveBeenCalledOnce();
  });

  it('rejects a verification that completed after the authority changed', async () => {
    let current = true;
    const session = {epoch: 2, verificationMode: 'email' as const, isCurrentAuthority: () => current, isRecentSensitiveVerification: () => true,
      recheckSensitiveEmailVerification: async () => {current = false; return true;}};
    expect(await verifySensitiveAccess(session, user, now)).toBe(false);
  });

  it('requires a current session and a recent authenticator proof', async () => {
    const session = {epoch: 2, verificationMode: 'authenticator' as const, isCurrentAuthority: () => true, isRecentSensitiveVerification: () => true,
      recheckSensitiveEmailVerification: vi.fn()};
    expect(await verifySensitiveAccess(session, user, now)).toBe(true);
    expect(await verifySensitiveAccess(session, {...user, mfaAt: '2026-11-16T11:54:59Z'}, now)).toBe(false);
    expect(await verifySensitiveAccess({...session, isCurrentAuthority: () => false}, user, now)).toBe(false);
    expect(session.recheckSensitiveEmailVerification).not.toHaveBeenCalled();
  });

  it('does not accept fresh email alone when the current policy also requires an authenticator', async () => {
    const session = {epoch: 2, verificationMode: 'email' as const, isCurrentAuthority: () => true,
      isRecentSensitiveVerification: () => false, recheckSensitiveEmailVerification: async () => true};
    expect(await verifySensitiveAccess(session, {...user, mfaRequired: true}, now)).toBe(false);
  });
});
