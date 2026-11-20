import {describe, expect, it} from 'vitest';
import {featureAuthorityKey} from '../../src/app/authority';
import type {AdminUser} from '../../src/session/SessionProvider';

describe('workspace authority scope', () => {
  const user: AdminUser = {id: 'actor', email: 'team@example.test', role: 'admin', sessionId: 'session',
    expiresAt: '2026-11-16T15:00:00.000Z', permissions: ['overview.read', 'users.read'],
    assuranceLevel: 1, mfaAt: null, emailVerifiedAt: null, principalId: null, financialModel: 'transaction_journals'};

  it('keeps same-session email proof refresh separate from actor and permission changes', () => {
    const original = featureAuthorityKey(1, user);
    expect(featureAuthorityKey(1, {...user, emailVerifiedAt: '2026-11-16T12:00:00.000Z'})).toBe(original);
    expect(featureAuthorityKey(1, {...user, permissions: ['users.read', 'overview.read']})).toBe(original);
    expect(featureAuthorityKey(1, {...user, permissions: ['overview.read']})).not.toBe(original);
    expect(featureAuthorityKey(2, user)).not.toBe(original);
  });
});
