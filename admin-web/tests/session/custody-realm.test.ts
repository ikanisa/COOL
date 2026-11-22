import {afterEach, expect, it, vi} from 'vitest';

const production = 'https://platform-admin.collect.ikanisa.com';
const qa = 'https://admin-supabase-qa.collect.ikanisa.com';
const managed = 'https://rrlduytparvsjfmegalh.supabase.co';
const id = '11111111-1111-4111-8111-111111111111';
const session = '22222222-2222-4222-8222-222222222222';
const pending = 'collect.admin.pending-attempts.v1';
const privacy = `collect.privacy-review.v1.${id}.${session}`;

afterEach(() => {sessionStorage.clear(); localStorage.clear(); vi.unstubAllEnvs(); vi.unstubAllGlobals(); vi.resetModules();});

it.each([production, qa])('binds only the current service’s browser recovery keys at %s', async origin => {
  vi.stubGlobal('location', new URL(origin));
  vi.stubEnv('VITE_ADMIN_EXPECTED_ORIGIN', origin);
  vi.stubEnv('VITE_ADMIN_BACKEND', 'supabase');
  vi.stubEnv('VITE_SUPABASE_PROJECT_ORIGIN', managed);
  const [attempts, logout, mfa, authority, transition, privacyContracts, realm] = await Promise.all([
    import('../../src/features/core/pendingAttempt'), import('../../src/session/logoutIntent'),
    import('../../src/session/mfaRecovery'), import('../../src/session/mfaAuthority'),
    import('../../src/session/mfaTransition'), import('../../src/features/privacy/contracts'), import('../../src/custodyRealm'),
  ]);
  const keys = [
    [attempts.PENDING_KEY, pending], [attempts.EVIDENCE_CONTEXT_KEY, 'collect.admin.evidence-context.v1'],
    [logout.LOGOUT_INTENT_PREFIX, 'collect.admin.logout-intent.v1.'], [mfa.MFA_INTENT_KEY, 'collect.admin.mfa-intent.v1'],
    [authority.MFA_AUTHORITY_KEY, 'collect.admin.mfa-authority.v1'], [transition.MFA_TRANSITION_PREFIX, 'collect.admin.mfa-transition.v1.'],
    [privacyContracts.privacyJournalKey(id, session), privacy],
  ];
  for (const [actual, previous] of keys) {
    if (origin === qa) expect(actual).toBe(previous);
    else expect(actual).toBe(`collect.realm.${managed}:${previous}`);
  }
  expect(realm.hasPredecessorCustody()).toBe(false);
  const management = `collect.admin.notification-management.${id}.${session}.${id}.${pending}`;
  for (const [storage, key] of [[sessionStorage, pending], [sessionStorage, management], [sessionStorage, 'collect.admin.mfa-intent.v1'],
    [localStorage, 'collect.admin.logout-intent.v1.' + 'a'.repeat(64)], [localStorage, privacy]] as const) {
    storage.setItem(key, 'untouched earlier data');
    expect(realm.hasPredecessorCustody()).toBe(origin === production);
    expect(storage.getItem(key)).toBe('untouched earlier data');
    storage.removeItem(key);
  }
});
