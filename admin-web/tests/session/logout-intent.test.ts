import {webcrypto} from 'node:crypto';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {AdminSessionController} from '../../src/session/SessionProvider';
import {LOGOUT_INTENT_PREFIX, logoutFingerprint} from '../../src/session/logoutIntent';
import {MFA_INTENT_KEY, type MfaRecoveryIntent} from '../../src/session/mfaRecovery';

const account = {id: 'actor-one', email: 'a@example.test', role: 'staff', sessionId: 'session-one', permissions: ['overview.read'], assuranceLevel: 1, mfaAt: null, financialModel: 'canonical_evidence_ledger'} as const;
const expiresAt = new Date(Date.now() + 3_600_000).toISOString(), csrf = 'c'.repeat(64), publishableKey = 'sb_publishable_' + 'a'.repeat(32);
const reply = (value: unknown, status = 200) => new Response(JSON.stringify(value), {status, headers: {'Content-Type': 'application/json'}});
const session = (user: (Omit<typeof account, 'sessionId'> & {sessionId: string}) | null = account) => ({user, expiresAt: user ? expiresAt : null, csrfToken: user ? csrf : null, ownerEmail: 'info@ikanisa.com'});
const proof = {contractVersion: 1, sessionId: account.sessionId, emailVerifiedAt: null};
const controllers: AdminSessionController[] = [];
const originalCrypto = globalThis.crypto;
beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true}); localStorage.clear(); sessionStorage.clear();});
afterEach(() => {controllers.splice(0).forEach((controller) => controller.stop()); localStorage.clear(); sessionStorage.clear(); Object.defineProperty(globalThis, 'crypto', {value: originalCrypto, configurable: true});});
function controller(fetchImpl: typeof fetch) {
  const instance = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(instance); return instance;
}

describe('Durable managed sign-out', () => {
  it('retains the exact fingerprint before dispatch and clears it only on confirmed sign-out', async () => {
    const fingerprint = await logoutFingerprint(account.sessionId), marker = LOGOUT_INTENT_PREFIX + fingerprint;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply(session());
      if (String(url).endsWith('/auth/email-verification')) return reply(proof);
      expect(localStorage.getItem(marker)).toBe('1'); return reply({ok: true});
    });
    const client = controller(fetchImpl); await client.refresh(); await client.signOut();
    expect(client.getSnapshot()).toMatchObject({status: 'anonymous', logoutUnconfirmed: false});
    expect(localStorage.getItem(marker)).toBeNull();
  });

  it('fences a lost response across reload and resolves only a confirmed absent session', async () => {
    let signedOut = false;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply(session(signedOut ? null : account));
      if (String(url).endsWith('/auth/email-verification')) return reply(proof);
      signedOut = true; throw new TypeError('lost response');
    });
    const first = controller(fetchImpl); await first.refresh();
    await expect(first.signOut()).rejects.toMatchObject({outcomeUnknown: true});
    const second = controller(fetchImpl), before = fetchImpl.mock.calls.length;
    await expect(second.refresh()).rejects.toThrow('Sign-out is not confirmed');
    await expect(second.signIn('a@example.test', 'password')).rejects.toThrow('Complete sign-out');
    expect(fetchImpl).toHaveBeenCalledTimes(before);
    await second.signOut();
    expect(second.getSnapshot()).toMatchObject({status: 'anonymous', logoutUnconfirmed: false});
    expect(localStorage.length).toBe(0);
  });

  it('does not sign out a different current public session when a prior logout is unresolved', async () => {
    const marker = LOGOUT_INTENT_PREFIX + await logoutFingerprint(account.sessionId); localStorage.setItem(marker, '1');
    const fetchImpl = vi.fn(async () => reply(session({...account, sessionId: 'another-session'})));
    const client = controller(fetchImpl);
    await expect(client.refresh()).rejects.toThrow('Sign-out is not confirmed');
    await expect(client.signOut()).rejects.toThrow('Another sign-out is unresolved');
    expect(localStorage.getItem(marker)).toBe('1'); expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it('fences other-tab and already-dispatched authenticated work as soon as a marker appears', async () => {
    let finish!: (response: Response) => void;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply(session());
      if (String(url).endsWith('/auth/email-verification')) return reply(proof);
      return new Promise<Response>((resolve) => {finish = resolve;});
    });
    const client = controller(fetchImpl); await client.refresh(); const epoch = client.getSnapshot().epoch;
    const request = client.request('core/users', {body: {}});
    const marker = LOGOUT_INTENT_PREFIX + await logoutFingerprint(account.sessionId); localStorage.setItem(marker, '1');
    window.dispatchEvent(new StorageEvent('storage', {key: marker, newValue: '1', storageArea: localStorage}));
    expect(client.getSnapshot()).toMatchObject({status: 'error', logoutUnconfirmed: true, user: null});
    expect(client.isCurrentAuthority(epoch, account.id, account.sessionId)).toBe(false);
    finish(reply({ok: true})); await expect(request).rejects.toMatchObject({outcomeUnknown: true});
  });

  it('uses only the original MFA recovery capability when logout has no CSRF token', async () => {
    const intent: MfaRecoveryIntent = {factor_id: '11111111-1111-4111-8111-111111111111', challenge_id: '22222222-2222-4222-8222-222222222222', verification_id: 'a'.repeat(64), session_id: account.sessionId, user_id: account.id, starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now()};
    sessionStorage.setItem(MFA_INTENT_KEY, JSON.stringify(intent));
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain('/auth/logout');
      expect(init?.body).toBe(JSON.stringify({factor_id: intent.factor_id, challenge_id: intent.challenge_id, verification_id: intent.verification_id}));
      expect(new Headers(init?.headers).has('X-Collect-CSRF')).toBe(false);
      expect(localStorage.getItem(LOGOUT_INTENT_PREFIX + await logoutFingerprint(account.sessionId))).toBe('1');
      return reply({ok: true});
    });
    const client = controller(fetchImpl); await client.signOut();
    expect(client.getSnapshot()).toMatchObject({status: 'anonymous', logoutUnconfirmed: false});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull();
  });

  it('retains both the sign-out marker and MFA capability if recovery logout returns 401', async () => {
    const intent: MfaRecoveryIntent = {factor_id: '11111111-1111-4111-8111-111111111111', challenge_id: '22222222-2222-4222-8222-222222222222', verification_id: 'a'.repeat(64), session_id: account.sessionId, user_id: account.id, starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now()};
    sessionStorage.setItem(MFA_INTENT_KEY, JSON.stringify(intent));
    const fetchImpl = vi.fn(async () => reply({error: {code: 'unauthenticated'}}, 401));
    const client = controller(fetchImpl);
    await expect(client.signOut()).rejects.toMatchObject({outcomeUnknown: true, statusCode: 401});
    expect(client.getSnapshot()).toMatchObject({status: 'error', logoutUnconfirmed: true});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBe(JSON.stringify(intent));
    expect(localStorage.getItem(LOGOUT_INTENT_PREFIX + await logoutFingerprint(account.sessionId))).toBe('1');
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it('fails closed on malformed storage and does not clear it', async () => {
    localStorage.setItem(LOGOUT_INTENT_PREFIX + 'bad', '1'); const fetchImpl = vi.fn(async () => reply(session()));
    const client = controller(fetchImpl);
    await expect(client.refresh()).rejects.toThrow('Sign-out is not confirmed');
    await expect(client.signOut()).rejects.toThrow('Sign-out could not be retained');
    expect(fetchImpl).not.toHaveBeenCalled(); expect(localStorage.getItem(LOGOUT_INTENT_PREFIX + 'bad')).toBe('1');
  });
});
