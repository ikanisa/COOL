import {webcrypto} from 'node:crypto';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {AdminSessionController, type AdminUser} from '../../src/session/SessionProvider';
// Exercise the unqualified protocol in isolation; the shipped candidate keeps it disabled.
vi.mock('../../src/session/mfaQualification', () => ({MANAGED_MFA_TRANSITION_QUALIFIED: true}));
import {MFA_INTENT_KEY, type MfaRecoveryIntent} from '../../src/session/mfaRecovery';
import {MFA_TRANSITION_PREFIX, mfaTransitionIdentity} from '../../src/session/mfaTransition';
import {createMfaAuthorityCheckpoint, MFA_AUTHORITY_KEY, writeMfaAuthorityCheckpoint} from '../../src/session/mfaAuthority';

const principalId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const factor = '11111111-1111-4111-8111-111111111111', challenge = '22222222-2222-4222-8222-222222222222';
const account = {id: 'actor-one', email: 'a@example.test', role: 'staff', sessionId: 'session-one', principalId, permissions: ['overview.read'], assuranceLevel: 1, mfaAt: null, mfaAvailable: true, financialModel: 'canonical_evidence_ledger'} as const;
const csrf = 'c'.repeat(64), publishableKey = 'sb_publishable_' + 'a'.repeat(32);
const reply = (value: unknown, status = 200) => new Response(JSON.stringify(value), {status, headers: {'Content-Type': 'application/json'}});
const expiry = () => new Date(Date.now() + 3_600_000).toISOString();
const session = (value: object) => ({user: value, expiresAt: expiry(), csrfToken: csrf, ownerEmail: 'info@ikanisa.com'});
const proof = () => ({contractVersion: 1, sessionId: account.sessionId, emailVerifiedAt: new Date(Date.now() - 1_000).toISOString()});
const controllers: AdminSessionController[] = [], originalCrypto = globalThis.crypto;
beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true}); localStorage.clear(); sessionStorage.clear();});
afterEach(() => {controllers.splice(0).forEach(client => client.stop()); vi.useRealTimers(); localStorage.clear(); sessionStorage.clear(); Object.defineProperty(globalThis, 'crypto', {value: originalCrypto, configurable: true});});
function create(fetchImpl: typeof fetch) {const client = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(client); return client;}

describe('Managed authenticator session upgrade', () => {
  it('retains a random capability before dispatch and admits only the confirmed same-authority AAL2 session', async () => {
    let upgraded = false, captured: Record<string, string> | undefined;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply(session(upgraded ? {...account, assuranceLevel: 2, mfaAt: new Date().toISOString()} : account));
      if (path.endsWith('/auth/email-verification')) return reply(proof());
      if (path.endsWith('/auth/mfa/verify')) {
        captured = JSON.parse(String(init?.body)); const retained = JSON.parse(sessionStorage.getItem(MFA_INTENT_KEY)!);
        expect(retained.verification_id).toMatch(/^[a-f0-9]{64}$/); expect(retained).not.toHaveProperty('code');
        expect(captured?.verification_id).toBe(retained.verification_id);
        const authority = sessionStorage.getItem(MFA_AUTHORITY_KEY)!;
        expect(authority).not.toContain(account.email); expect(authority).not.toContain(account.sessionId); expect(authority).not.toContain(retained.verification_id);
        expect([...Array(localStorage.length)].map((_, index) => localStorage.key(index)).some(key => key?.startsWith(MFA_TRANSITION_PREFIX))).toBe(true);
        upgraded = true; return reply({ok: true});
      }
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl); await client.refresh(); const oldEpoch = client.getSnapshot().epoch;
    await client.verifyAuthenticator(factor, challenge, '123456');
    expect(captured).toMatchObject({factor_id: factor, challenge_id: challenge, code: '123456'});
    expect(client.getSnapshot()).toMatchObject({status: 'authenticated', mfaRecoveryPending: false, user: {id: account.id, assuranceLevel: 2}});
    expect(client.isCurrentAuthority(oldEpoch, account.id, account.sessionId)).toBe(false);
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull(); expect(sessionStorage.getItem(MFA_AUTHORITY_KEY)).toBeNull(); expect(localStorage.length).toBe(0);
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/mfa/verify'))).toHaveLength(1);
  });

  it('waits 26 seconds after a lost verify reply, then recovers the original capability without resending the code', async () => {
    vi.useFakeTimers(); let stage = 'initial', verifyCalls = 0, recoverCalls = 0;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) {
        if (stage === 'initial') return reply(session(account));
        if (stage === 'pending') return reply({error: {code: 'mfa_recovery_pending'}}, 409);
        return reply(session({...account, assuranceLevel: 2, mfaAt: new Date().toISOString()}));
      }
      if (path.endsWith('/auth/email-verification')) return reply(proof());
      if (path.endsWith('/auth/mfa/verify')) {verifyCalls++; stage = 'pending'; throw new TypeError('lost response');}
      if (path.endsWith('/auth/mfa/recover')) {
        recoverCalls++; const retained = JSON.parse(sessionStorage.getItem(MFA_INTENT_KEY)!);
        expect(JSON.parse(String(init?.body))).toEqual({factor_id: factor, challenge_id: challenge, verification_id: retained.verification_id});
        expect(new Headers(init?.headers).has('X-Collect-CSRF')).toBe(false); stage = 'recovered'; return reply({ok: true});
      }
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl); await client.refresh();
    const pending = client.verifyAuthenticator(factor, challenge, '123456');
    await vi.waitFor(() => expect(verifyCalls).toBe(1));
    await vi.advanceTimersByTimeAsync(25_000); expect(recoverCalls).toBe(0);
    await vi.advanceTimersByTimeAsync(1_100); await pending;
    expect(recoverCalls).toBe(1); expect(verifyCalls).toBe(1);
    expect(client.getSnapshot()).toMatchObject({status: 'authenticated', user: {assuranceLevel: 2}});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull();
  });

  it('adopts an already-rotated cookie after a lost response without calling recover', async () => {
    vi.useFakeTimers(); let upgraded = false, sent = false;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply(session(upgraded ? {...account, assuranceLevel: 2, mfaAt: new Date().toISOString()} : account));
      if (String(url).endsWith('/auth/email-verification')) return reply(proof());
      if (String(url).endsWith('/auth/mfa/verify')) {upgraded = true; sent = true; throw new TypeError('reply lost after cookie rotation');}
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl); await client.refresh();
    const pending = client.verifyAuthenticator(factor, challenge, '123456');
    await vi.waitFor(() => expect(sent).toBe(true)); await vi.advanceTimersByTimeAsync(26_100); await pending;
    expect(client.getSnapshot()).toMatchObject({status: 'authenticated', user: {assuranceLevel: 2}});
    expect(fetchImpl.mock.calls.some(([url]) => String(url).endsWith('/auth/mfa/recover'))).toBe(false);
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull();
  });

  it('does not dispatch cold recovery when a legacy intent lacks its original authority baseline', async () => {
    const intent: MfaRecoveryIntent = {factor_id: factor, challenge_id: challenge, verification_id: 'a'.repeat(64), session_id: account.sessionId, user_id: account.id, starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now() - 27_000};
    sessionStorage.setItem(MFA_INTENT_KEY, JSON.stringify(intent));
    const fetchImpl = vi.fn(async () => reply(session(account))), client = create(fetchImpl);
    await expect(client.refresh()).rejects.toThrow('original authenticator authority is unavailable');
    expect(client.getSnapshot()).toMatchObject({status: 'error', mfaRecoveryPending: true, user: null});
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBe(JSON.stringify(intent)); expect(localStorage.length).toBe(1);
  });

  it.each([
    ['principal', {principalId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'}],
    ['role', {role: 'admin'}],
    ['email', {email: 'other@example.test'}],
    ['grants', {permissions: ['overview.read', 'users.read']}],
  ])('retains the React recovery intent if cold restoration changes the original %s', async (_label, changed) => {
    const intent: MfaRecoveryIntent = {factor_id: factor, challenge_id: challenge, verification_id: 'a'.repeat(64), session_id: account.sessionId, user_id: account.id, starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now() - 27_000};
    const before: AdminUser = {...account, role: 'staff', expiresAt: expiry(), emailVerifiedAt: null, mfaRequired: false};
    const checkpoint = await createMfaAuthorityCheckpoint(intent, before);
    writeMfaAuthorityCheckpoint(checkpoint); sessionStorage.setItem(MFA_INTENT_KEY, JSON.stringify(intent));
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply(session({...account, ...changed, assuranceLevel: 2, mfaAt: new Date().toISOString()}));
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl);
    await expect(client.refresh()).rejects.toMatchObject({outcomeUnknown: true});
    expect(client.getSnapshot()).toMatchObject({status: 'error', mfaRecoveryPending: true, user: null});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).not.toBeNull(); expect(sessionStorage.getItem(MFA_AUTHORITY_KEY)).not.toBeNull();
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it('clears the digest checkpoint only after a same-authority cold recovery succeeds', async () => {
    const intent: MfaRecoveryIntent = {factor_id: factor, challenge_id: challenge, verification_id: 'a'.repeat(64), session_id: account.sessionId, user_id: account.id, starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now() - 27_000};
    const before: AdminUser = {...account, role: 'staff', expiresAt: expiry(), emailVerifiedAt: null, mfaRequired: false};
    writeMfaAuthorityCheckpoint(await createMfaAuthorityCheckpoint(intent, before)); sessionStorage.setItem(MFA_INTENT_KEY, JSON.stringify(intent));
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session')
      ? reply(session({...account, assuranceLevel: 2, mfaAt: new Date().toISOString()})) : reply(proof()));
    const client = create(fetchImpl); await client.refresh();
    expect(client.getSnapshot()).toMatchObject({status: 'authenticated', user: {id: account.id, assuranceLevel: 2}});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull(); expect(sessionStorage.getItem(MFA_AUTHORITY_KEY)).toBeNull();
  });

  it('recovers a pending original React intent after reload without resubmitting a code', async () => {
    const intent: MfaRecoveryIntent = {factor_id: factor, challenge_id: challenge, verification_id: 'a'.repeat(64), session_id: account.sessionId, user_id: account.id, starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now() - 27_000};
    const before: AdminUser = {...account, role: 'staff', expiresAt: expiry(), emailVerifiedAt: null, mfaRequired: false};
    writeMfaAuthorityCheckpoint(await createMfaAuthorityCheckpoint(intent, before)); sessionStorage.setItem(MFA_INTENT_KEY, JSON.stringify(intent));
    let recovered = false;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return recovered ? reply(session({...account, assuranceLevel: 2, mfaAt: new Date().toISOString()})) : reply({error: {code: 'mfa_recovery_pending'}}, 409);
      if (path.endsWith('/auth/mfa/recover')) {expect(JSON.parse(String(init?.body))).toEqual({factor_id: factor, challenge_id: challenge, verification_id: intent.verification_id}); recovered = true; return reply({ok: true});}
      if (path.endsWith('/auth/email-verification')) return reply(proof());
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl); await client.refresh();
    expect(client.getSnapshot()).toMatchObject({status: 'authenticated', user: {id: account.id, assuranceLevel: 2}});
    expect(fetchImpl.mock.calls.some(([url]) => String(url).endsWith('/auth/mfa/verify'))).toBe(false);
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull(); expect(sessionStorage.getItem(MFA_AUTHORITY_KEY)).toBeNull();
  });

  it('does not contact the backend when the saved authority checkpoint names another intent', async () => {
    const intent: MfaRecoveryIntent = {factor_id: factor, challenge_id: challenge, verification_id: 'a'.repeat(64), session_id: account.sessionId, user_id: account.id, starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now() - 27_000};
    const before: AdminUser = {...account, role: 'staff', expiresAt: expiry(), emailVerifiedAt: null, mfaRequired: false};
    writeMfaAuthorityCheckpoint(await createMfaAuthorityCheckpoint({...intent, verification_id: 'b'.repeat(64)}, before)); sessionStorage.setItem(MFA_INTENT_KEY, JSON.stringify(intent));
    const fetchImpl = vi.fn(async () => reply(session(account))), client = create(fetchImpl);
    await expect(client.refresh()).rejects.toMatchObject({outcomeUnknown: true});
    expect(fetchImpl).not.toHaveBeenCalled(); expect(sessionStorage.getItem(MFA_INTENT_KEY)).not.toBeNull(); expect(sessionStorage.getItem(MFA_AUTHORITY_KEY)).not.toBeNull();
  });

  it.each([
    ['role', {role: 'admin'}],
    ['grants', {permissions: ['overview.read', 'users.read']}],
    ['email', {email: 'other@example.test'}],
    ['principal', {principalId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'}],
    ['session', {sessionId: 'different-session'}],
  ])('retains the original intent when the live upgrade changes %s', async (_label, changed) => {
    let verified = false;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply(session(verified ? {...account, ...changed, assuranceLevel: 2, mfaAt: new Date().toISOString()} : account));
      if (String(url).endsWith('/auth/email-verification')) return reply(proof());
      if (String(url).endsWith('/auth/mfa/verify')) {verified = true; return reply({ok: true});}
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl); await client.refresh();
    await expect(client.verifyAuthenticator(factor, challenge, '123456')).rejects.toMatchObject({outcomeUnknown: true});
    expect(client.getSnapshot()).toMatchObject({status: 'error', mfaRecoveryPending: true, user: null});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).not.toBeNull();
    expect(fetchImpl.mock.calls.some(([url]) => String(url).endsWith('/auth/mfa/recover'))).toBe(false);
  });

  it('fences an in-flight verification when sign-out completes and never reinstalls its late response', async () => {
    let finish!: (response: Response) => void, dispatched = false;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      if (String(url).endsWith('/auth/session')) return reply(session(account));
      if (String(url).endsWith('/auth/email-verification')) return reply(proof());
      if (String(url).endsWith('/auth/mfa/verify')) {dispatched = true; return new Promise<Response>(resolve => {finish = resolve;});}
      if (String(url).endsWith('/auth/logout')) {
        const retained = JSON.parse(sessionStorage.getItem(MFA_INTENT_KEY)!);
        expect(JSON.parse(String(init?.body))).toEqual({factor_id: factor, challenge_id: challenge, verification_id: retained.verification_id});
        expect(new Headers(init?.headers).has('X-Collect-CSRF')).toBe(false); return reply({ok: true});
      }
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl); await client.refresh();
    const verifying = client.verifyAuthenticator(factor, challenge, '123456'), rejected = expect(verifying).rejects.toMatchObject({outcomeUnknown: true});
    await vi.waitFor(() => expect(dispatched).toBe(true));
    await client.signOut(); expect(client.getSnapshot()).toMatchObject({status: 'anonymous', user: null});
    finish(reply({ok: true})); await rejected;
    expect(client.getSnapshot()).toMatchObject({status: 'anonymous', user: null});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull(); expect(sessionStorage.getItem(MFA_AUTHORITY_KEY)).toBeNull(); expect(localStorage.length).toBe(0);
  });

  it('does not treat an ordinary empty-cookie logout as proof that a pending upgrade was revoked', async () => {
    let finish!: (response: Response) => void, dispatched = false;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      if (String(url).endsWith('/auth/session')) return reply(session(account));
      if (String(url).endsWith('/auth/email-verification')) return reply(proof());
      if (String(url).endsWith('/auth/mfa/verify')) {dispatched = true; return new Promise<Response>(resolve => {finish = resolve;});}
      if (String(url).endsWith('/auth/logout')) {
        expect(JSON.parse(String(init?.body))).toHaveProperty('verification_id');
        expect(new Headers(init?.headers).has('X-Collect-CSRF')).toBe(false);
        return reply({error: {code: 'mfa_recovery_unavailable'}}, 409);
      }
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl); await client.refresh();
    const verifying = client.verifyAuthenticator(factor, challenge, '123456'), rejected = expect(verifying).rejects.toMatchObject({outcomeUnknown: true});
    await vi.waitFor(() => expect(dispatched).toBe(true));
    await expect(client.signOut()).rejects.toThrow();
    expect(client.getSnapshot()).toMatchObject({status: 'error', logoutUnconfirmed: true, user: null});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).not.toBeNull(); expect(sessionStorage.getItem(MFA_AUTHORITY_KEY)).not.toBeNull();
    expect([...Array(localStorage.length)].some((_, index) => localStorage.key(index)?.startsWith(MFA_TRANSITION_PREFIX))).toBe(true);
    finish(reply({ok: true})); await rejected;
  });

  it('keeps the original intent when AAL2 proof is not newer than the starting proof', async () => {
    vi.useFakeTimers(); const prior = new Date(Date.now() - 60_000).toISOString(); let verified = false;
    const existing = {...account, assuranceLevel: 2, mfaAt: prior};
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply(session(existing));
      if (String(url).endsWith('/auth/email-verification')) return reply(proof());
      if (String(url).endsWith('/auth/mfa/verify')) {verified = true; return reply({ok: true});}
      if (String(url).endsWith('/auth/mfa/recover')) return reply({error: {code: 'mfa_recovery_unavailable'}}, 409);
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl); await client.refresh();
    const pending = client.verifyAuthenticator(factor, challenge, '123456'), rejected = expect(pending).rejects.toThrow();
    await vi.waitFor(() => expect(verified).toBe(true)); await vi.advanceTimersByTimeAsync(26_100); await rejected;
    expect(client.getSnapshot()).toMatchObject({status: 'error', mfaRecoveryPending: true, user: null});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).not.toBeNull();
  });

  it('clears the original recovery capability after a definite verification rejection', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply(session(account));
      if (String(url).endsWith('/auth/email-verification')) return reply(proof());
      if (String(url).endsWith('/auth/mfa/verify')) return reply({error: {code: 'invalid_mfa_request'}}, 400);
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl); await client.refresh();
    await expect(client.verifyAuthenticator(factor, challenge, '123456')).rejects.toMatchObject({statusCode: 400});
    expect(client.getSnapshot()).toMatchObject({status: 'authenticated', mfaRecoveryPending: false});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull(); expect(localStorage.length).toBe(0);
  });

  it('does not dispatch a verification after local authority preparation has gone stale', async () => {
    vi.useFakeTimers();
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session') ? reply(session(account)) : reply(proof()));
    const client = create(fetchImpl); await client.refresh();
    let release!: () => void, count = 0;
    const gate = new Promise<void>(resolve => {release = resolve;}), digest = webcrypto.subtle.digest.bind(webcrypto.subtle);
    Object.defineProperty(globalThis, 'crypto', {value: {getRandomValues: webcrypto.getRandomValues.bind(webcrypto), subtle: {digest: async (...args: Parameters<typeof digest>) => {
      if (++count === 1) await gate;
      return digest(...args);
    }}}, configurable: true});
    const verifying = client.verifyAuthenticator(factor, challenge, '123456'), rejected = expect(verifying).rejects.toThrow('challenge expired');
    await vi.waitFor(() => expect(count).toBeGreaterThan(0));
    vi.setSystemTime(Date.now() + 60_001); release(); await rejected;
    expect(fetchImpl.mock.calls.some(([url]) => String(url).endsWith('/auth/mfa/verify'))).toBe(false);
    expect(client.getSnapshot()).toMatchObject({status: 'authenticated', mfaRecoveryPending: false});
    expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull(); expect(sessionStorage.getItem(MFA_AUTHORITY_KEY)).toBeNull();
  });

  it('does not install a candidate when its session envelope or cookie proof is unconfirmed', async () => {
    for (const bad of ['missing-csrf', 'email-401'] as const) {
      let verified = false;
      const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
        if (String(url).endsWith('/auth/session')) {
          if (!verified) return reply(session(account));
          const candidate = session({...account, assuranceLevel: 2, mfaAt: new Date().toISOString()});
          return reply(bad === 'missing-csrf' ? {...candidate, csrfToken: undefined} : candidate);
        }
        if (String(url).endsWith('/auth/email-verification')) return verified && bad === 'email-401' ? reply({error: {code: 'unauthenticated'}}, 401) : reply(proof());
        if (String(url).endsWith('/auth/mfa/verify')) {verified = true; return reply({ok: true});}
        throw new Error('Unexpected request');
      });
      const client = create(fetchImpl); await client.refresh();
      await expect(client.verifyAuthenticator(factor, challenge, '123456')).rejects.toThrow();
      expect(client.getSnapshot()).toMatchObject({status: 'error', mfaRecoveryPending: true, user: null});
      expect(sessionStorage.getItem(MFA_INTENT_KEY)).not.toBeNull();
      client.stop(); sessionStorage.clear(); localStorage.clear();
    }
  });

  it('blocks other tabs when a transition marker exists and fences an already-dispatched response', async () => {
    let finish!: (response: Response) => void;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply(session(account));
      if (String(url).endsWith('/auth/email-verification')) return reply(proof());
      return new Promise<Response>(resolve => {finish = resolve;});
    });
    const client = create(fetchImpl); await client.refresh(); const epoch = client.getSnapshot().epoch;
    const old = client.request('core/users', {body: {}});
    const intent: MfaRecoveryIntent = {factor_id: factor, challenge_id: challenge, verification_id: 'a'.repeat(64), session_id: account.sessionId, user_id: account.id, starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now()};
    const marker = await mfaTransitionIdentity(intent), key = MFA_TRANSITION_PREFIX + marker.key;
    localStorage.setItem(key, marker.session); window.dispatchEvent(new StorageEvent('storage', {key, newValue: marker.session, storageArea: localStorage}));
    expect(client.getSnapshot()).toMatchObject({status: 'error', mfaRecoveryPending: true});
    expect(client.isCurrentAuthority(epoch, account.id, account.sessionId)).toBe(false);
    finish(reply({ok: true})); await expect(old).rejects.toMatchObject({outcomeUnknown: true});
  });

  it('rechecks the session after a different tab removes its resolved transition marker', async () => {
    let checks = 0;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) {checks++; return reply(session(account));}
      if (String(url).endsWith('/auth/email-verification')) return reply(proof());
      throw new Error('Unexpected request');
    });
    const client = create(fetchImpl); await client.refresh();
    const intent: MfaRecoveryIntent = {factor_id: factor, challenge_id: challenge, verification_id: 'a'.repeat(64), session_id: account.sessionId, user_id: account.id, starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now()};
    const marker = await mfaTransitionIdentity(intent), key = MFA_TRANSITION_PREFIX + marker.key;
    localStorage.setItem(key, marker.session); window.dispatchEvent(new StorageEvent('storage', {key, newValue: marker.session, storageArea: localStorage}));
    expect(client.getSnapshot()).toMatchObject({status: 'error', mfaRecoveryPending: true});
    localStorage.removeItem(key); window.dispatchEvent(new StorageEvent('storage', {key, oldValue: marker.session, storageArea: localStorage}));
    await vi.waitFor(() => expect(client.getSnapshot()).toMatchObject({status: 'authenticated', mfaRecoveryPending: false}));
    expect(checks).toBe(2);
  });

  it('does not allow a caller to bypass managed MFA recovery with the generic request method', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session') ? reply(session(account)) : reply(proof()));
    const client = create(fetchImpl); await client.refresh();
    await expect(client.request('auth/mfa/verify', {body: {factor_id: factor, challenge_id: challenge, code: '123456'}})).rejects.toThrow('authenticator verification flow');
    await expect(client.request('auth/mfa/recover', {body: {factor_id: factor, challenge_id: challenge, verification_id: 'a'.repeat(64)}, mfaRecovery: true})).rejects.toThrow('authenticator verification flow');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });
});
