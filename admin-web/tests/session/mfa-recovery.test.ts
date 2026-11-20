import {afterEach, describe, expect, it} from 'vitest';
import {clearMfaRecoveryIntent, MFA_INTENT_KEY, mfaRecoveryDelay, parseMfaRecoveryIntent, readMfaRecoveryIntent, writeMfaRecoveryIntent, type MfaRecoveryIntent} from '../../src/session/mfaRecovery';

const now = 1_800_000_000_000;
const intent: MfaRecoveryIntent = {factor_id: '11111111-1111-4111-8111-111111111111', challenge_id: '22222222-2222-4222-8222-222222222222', verification_id: 'a'.repeat(64), session_id: 'session-one', user_id: 'actor-one', starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: now};
afterEach(() => sessionStorage.clear());

describe('Authenticator recovery intent', () => {
  it('round-trips the exact migration format without a code or session secret', () => {
    writeMfaRecoveryIntent(intent); expect(readMfaRecoveryIntent()).toEqual(intent);
    const saved = JSON.parse(sessionStorage.getItem(MFA_INTENT_KEY)!);
    expect(Object.keys(saved)).toHaveLength(8); expect(saved).not.toHaveProperty('code'); expect(saved).not.toHaveProperty('token'); expect(saved).not.toHaveProperty('csrf');
    clearMfaRecoveryIntent(intent); expect(readMfaRecoveryIntent()).toBeNull();
  });
  it('rejects malformed and extra fields, missing AAL2 baseline, or replacement of an unresolved intent', () => {
    expect(() => parseMfaRecoveryIntent({...intent, code: '123456'})).toThrow();
    expect(() => parseMfaRecoveryIntent({...intent, verification_id: 'A'.repeat(64)})).toThrow();
    expect(() => parseMfaRecoveryIntent({...intent, starting_assurance_level: 2})).toThrow();
    writeMfaRecoveryIntent(intent); expect(() => writeMfaRecoveryIntent({...intent, verification_id: 'b'.repeat(64)})).toThrow();
    expect(() => clearMfaRecoveryIntent({...intent, verification_id: 'b'.repeat(64)})).toThrow(); expect(readMfaRecoveryIntent()).toEqual(intent);
    expect(() => clearMfaRecoveryIntent({...intent, challenge_id: '33333333-3333-4333-8333-333333333333'})).toThrow();
    expect(readMfaRecoveryIntent()).toEqual(intent);
  });
  it('bounds automatic recovery without erasing expired or future intent', () => {
    expect(mfaRecoveryDelay(intent, now)).toBe(26_000); expect(mfaRecoveryDelay(intent, now + 25_000)).toBe(1_000);
    expect(mfaRecoveryDelay(intent, now + 26_000)).toBe(0); expect(mfaRecoveryDelay(intent, now - 60_001)).toBeNull();
    expect(mfaRecoveryDelay(intent, now + 300_001)).toBeNull();
    writeMfaRecoveryIntent(intent); expect(readMfaRecoveryIntent()).toEqual(intent);
  });
});
