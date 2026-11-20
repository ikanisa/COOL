import {describe, expect, it} from 'vitest';
import {sensitiveVerificationDeadline, type AdminUser} from '../../src/session/SessionProvider';

const now = Date.parse('2026-11-16T12:00:00.000Z');
const at = (offset: number) => new Date(now + offset).toISOString();
const base: AdminUser = {id: 'operator', email: 'a@example.test', role: 'admin', sessionId: 'session', expiresAt: at(600_000), permissions: ['overview.read'],
  assuranceLevel: 2, mfaAt: at(-90_000), emailVerifiedAt: at(-30_000), mfaAvailable: true, mfaRequired: true, principalId: null, financialModel: 'canonical_evidence_ledger'};

describe('Sensitive proof deadline', () => {
  it('uses the earlier email or authenticator proof under the combined policy', () => {
    expect(sensitiveVerificationDeadline(base, 'supabase', now)).toBe(now + 210_000);
    expect(sensitiveVerificationDeadline({...base, emailVerifiedAt: at(-120_000)}, 'supabase', now)).toBe(now + 180_000);
  });
  it('fails closed if either required proof is missing, mismatched in assurance, or invalid', () => {
    expect(sensitiveVerificationDeadline({...base, emailVerifiedAt: null}, 'supabase', now)).toBeNull();
    expect(sensitiveVerificationDeadline({...base, mfaAt: null}, 'supabase', now)).toBeNull();
    expect(sensitiveVerificationDeadline({...base, assuranceLevel: 1}, 'supabase', now)).toBeNull();
    expect(sensitiveVerificationDeadline({...base, emailVerifiedAt: at(1)}, 'supabase', now)).toBeNull();
    expect(sensitiveVerificationDeadline({...base, mfaAt: at(60_001)}, 'supabase', now)).toBeNull();
    expect(sensitiveVerificationDeadline({...base, expiresAt: at(0)}, 'supabase', now)).toBeNull();
  });
  it('limits the deadline by session expiry and preserves email-only and authenticator-only policies', () => {
    expect(sensitiveVerificationDeadline({...base, expiresAt: at(5_000)}, 'supabase', now)).toBe(now + 5_000);
    expect(sensitiveVerificationDeadline({...base, mfaRequired: false, mfaAt: null, assuranceLevel: 1}, 'supabase', now)).toBe(now + 270_000);
    expect(sensitiveVerificationDeadline({...base, emailVerifiedAt: null}, 'cloudflare', now)).toBe(now + 210_000);
    expect(sensitiveVerificationDeadline({...base, assuranceLevel: 1}, 'cloudflare', now)).toBeNull();
  });
});
