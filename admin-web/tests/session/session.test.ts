import {webcrypto} from 'node:crypto';
import {afterEach, describe, expect, it, vi} from 'vitest';
import {AdminSessionController, captureSetupLocation, parseAdminUser, safeAdminReturnLocation, safeAdminVerificationReturnLocation} from '../../src/session/SessionProvider';
import {PENDING_KEY, retainPending, type PendingIdentity} from '../../src/features/core/pendingAttempt';
import {googleAuthorizationUrl} from '../../src/session/google';
import {parseCaptchaEnvelope} from '../../src/session/captcha';
import {parseFactor, parseSetup} from '../../src/session/AuthenticatorPage';

const publishableKey = 'sb_publishable_' + 'a'.repeat(32);
const csrf = 'c'.repeat(64);
const expiresAt = new Date(Date.now() + 3_600_000).toISOString();
const account = {id: 'operator-one', email: 'a@example.com', role: 'staff', sessionId: 'session-one', permissions: ['overview.read'], assuranceLevel: 1, mfaAt: null, financialModel: 'canonical_evidence_ledger'} as const;
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status, headers: {'Content-Type': 'application/json'}});
const controllers: AdminSessionController[] = [];
const initialCrypto = globalThis.crypto;
afterEach(() => {controllers.splice(0).forEach((controller) => controller.stop()); Object.defineProperty(globalThis, 'crypto', {value: initialCrypto, configurable: true}); sessionStorage.clear(); localStorage.clear();});

describe('Admin session', () => {
  it('fails closed when a session requires an unsupported combined authenticator policy', () => {
    expect(() => parseAdminUser({user: {...account, mfaAvailable: true, mfaRequired: true}, expiresAt})).toThrow(/verification policy/);
    expect(() => parseAdminUser({user: {...account, mfaRequired: 'true'}, expiresAt})).toThrow(/verification policy/);
    expect(parseAdminUser({user: {...account, mfaAvailable: true, mfaRequired: false}, expiresAt}).id).toBe(account.id);
  });
  it('does not install an authenticated session that advertises the unimplemented combined policy', async () => {
    const fetchImpl = vi.fn(async () => reply({user: {...account, mfaAvailable: true, mfaRequired: true}, expiresAt, csrfToken: csrf}));
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await expect(controller.refresh()).rejects.toThrow(/verification policy/);
    expect(controller.getSnapshot()).toMatchObject({status: 'error', user: null}); expect(fetchImpl).toHaveBeenCalledOnce();
  });
  it('does not restore a session or discard an unresolved authenticator recovery reference', async () => {
    Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true});
    const retained = JSON.stringify({factor_id: '11111111-1111-4111-8111-111111111111', challenge_id: '22222222-2222-4222-8222-222222222222', verification_id: 'a'.repeat(64), session_id: 'session-one', user_id: 'operator-one', starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now() - 300_001});
    sessionStorage.setItem('collect.admin.mfa-intent.v1', retained);
    const fetchImpl = vi.fn(async () => reply({user: {...account, mfaAvailable: true, mfaRequired: true}, expiresAt, csrfToken: csrf}));
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await expect(controller.refresh()).rejects.toThrow(/Authenticator recovery is unavailable/);
    expect(controller.getSnapshot()).toMatchObject({status: 'error', mfaRecoveryPending: true, user: null});
    expect(controller.isRecentSensitiveVerification(controller.getSnapshot().epoch, account.id, account.sessionId)).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
    controller.clearLocalSession();
    await expect(controller.signIn('a@example.com', 'password')).rejects.toThrow('pending session verification');
    expect(sessionStorage.getItem('collect.admin.mfa-intent.v1')).toBe(retained);
  });
  it('binds the Supabase sensitive-email proof to the current public session', async () => {
    const proof = new Date(Date.now() - 5_000).toISOString();
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session') ? reply({user: account, expiresAt, csrfToken: csrf}) : reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: proof}));
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    expect(controller.getSnapshot()).toMatchObject({status: 'authenticated', user: {sessionId: 'session-one', emailVerifiedAt: proof, permissions: ['overview.read']}});
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('requires a current same-actor, same-session proof younger than five minutes', async () => {
    vi.useFakeTimers();
    try {
      const proof = new Date().toISOString();
      const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session') ? reply({user: account, expiresAt, csrfToken: csrf}) : reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: proof}));
      const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
      await controller.refresh();
      const epoch = controller.getSnapshot().epoch;
      expect(controller.isRecentSensitiveVerification(epoch, account.id, account.sessionId)).toBe(true);
      expect(controller.isRecentSensitiveVerification(epoch + 1, account.id, account.sessionId)).toBe(false);
      expect(controller.isRecentSensitiveVerification(epoch, 'other-actor', account.sessionId)).toBe(false);
      expect(controller.isRecentSensitiveVerification(epoch, account.id, 'other-session')).toBe(false);
      vi.setSystemTime(Date.now() + 300_001);
      expect(controller.isRecentSensitiveVerification(epoch, account.id, account.sessionId)).toBe(false);
    } finally {vi.useRealTimers();}
  });

  it('does not expire a session early when its expiry exceeds the browser timer limit', async () => {
    vi.useFakeTimers();
    const schedule = vi.spyOn(globalThis, 'setTimeout');
    try {
      const distantExpiry = new Date(Date.now() + 40 * 24 * 60 * 60 * 1000).toISOString();
      const fetchImpl = vi.fn(async () => reply({user: account, expiresAt: distantExpiry}));
      const controller = new AdminSessionController({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
      await controller.refresh();
      expect(schedule.mock.calls.some(([, delay]) => delay === 2_147_483_647)).toBe(true);
      await vi.advanceTimersByTimeAsync(10_000);
      expect(controller.getSnapshot()).toMatchObject({status: 'authenticated', user: {sessionId: 'session-one'}});
    } finally {vi.useRealTimers();}
  });

  it('fails closed on a proof from a different session', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session') ? reply({user: account, expiresAt, csrfToken: csrf}) : reply({contractVersion: 1, sessionId: 'other-session', emailVerifiedAt: null}));
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await expect(controller.refresh()).rejects.toThrow('Session mismatch');
    expect(controller.getSnapshot()).toMatchObject({status: 'error', user: null});
  });

  it('does not install an earlier session when the following proof request reports client retirement', async () => {
    let retired = false, hold = false;
    let release!: (response: Response) => void, markStarted!: () => void;
    const started = new Promise<void>(resolve => {markStarted = resolve;});
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) {
        if (hold) {markStarted(); return new Promise<Response>(resolve => {release = resolve;});}
        return reply({user: account, expiresAt, csrfToken: csrf});
      }
      if (String(url).endsWith('/auth/email-verification')) return retired ?
        reply({error: {code: 'admin_client_upgrade_required'}}, 426) :
        reply({contractVersion: 1, sessionId: account.sessionId, emailVerifiedAt: null});
      throw new Error('Unexpected test request');
    });
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    hold = true; const pending = controller.refresh(); await started;
    retired = true; release(reply({user: account, expiresAt, csrfToken: csrf}));
    await expect(pending).rejects.toMatchObject({statusCode: 426});
    expect(controller.getSnapshot()).toMatchObject({status: 'error', user: null, error: expect.stringContaining('needs to be updated')});
  });

  it('does not let an old verification attempt poison a newer authority', async () => {
    let role = 'staff', sends = 0;
    let finish!: (response: Response) => void;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: {...account, role}, expiresAt, csrfToken: csrf});
      if (path.endsWith('/auth/email-verification')) return reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: null});
      if (path.endsWith('/auth/email/request')) {
        sends++;
        if (sends === 1) return new Promise<Response>((resolve) => {finish = resolve;});
        return reply({challenge_id: '0f689afa-5a45-4fb5-a147-9aff36f137dd', retry_after: 60, expires_in: 300, delivery_status: 'accepted'}, 202);
      }
      return reply({error: {code: 'not_found'}}, 404);
    });
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    const old = controller.requestSensitiveEmailVerification();
    role = 'admin'; await controller.refresh();
    finish(reply({error: {code: 'proxy_outcome_unknown'}}, 503));
    await expect(old).rejects.toMatchObject({outcomeUnknown: true});
    await expect(controller.requestSensitiveEmailVerification()).resolves.toMatchObject({challengeId: '0f689afa-5a45-4fb5-a147-9aff36f137dd'});
  });

  it('requires a status check and the full uncertainty window before a new sensitive code request', async () => {
    vi.useFakeTimers();
    try {
      let sends = 0;
      const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
        const path = String(url);
        if (path.endsWith('/auth/session')) return reply({user: account, expiresAt, csrfToken: csrf});
        if (path.endsWith('/auth/email-verification')) return reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: null});
        if (path.endsWith('/auth/email/request')) {
          sends++;
          if (sends === 1) throw new TypeError('connection lost');
          return reply({challenge_id: '0f689afa-5a45-4fb5-a147-9aff36f137dd', retry_after: 60, expires_in: 300, delivery_status: 'accepted'}, 202);
        }
        return reply({error: {code: 'not_found'}}, 404);
      });
      const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
      await controller.refresh();
      await expect(controller.requestSensitiveEmailVerification()).rejects.toMatchObject({outcomeUnknown: true});
      expect(controller.sensitiveEmailRecovery()).toMatchObject({kind: 'request', checked: false});
      expect(() => controller.releaseExpiredSensitiveRequest()).toThrow();
      expect(await controller.recheckSensitiveEmailVerification()).toBe(false);
      expect(() => controller.releaseExpiredSensitiveRequest()).toThrow();
      vi.setSystemTime(Date.now() + 300_001);
      controller.releaseExpiredSensitiveRequest();
      expect(sends).toBe(1);
      await expect(controller.requestSensitiveEmailVerification()).resolves.toMatchObject({challengeId: '0f689afa-5a45-4fb5-a147-9aff36f137dd'});
      expect(sends).toBe(2);
    } finally {vi.useRealTimers();}
  });

  it('fences a sensitive verification left in flight and does not admit its old proof', async () => {
    const baseline = new Date(Date.now() - 10_000).toISOString(), newer = new Date(Date.now() - 1_000).toISOString();
    let finish!: (response: Response) => void, newProof = false;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: account, expiresAt, csrfToken: csrf});
      if (path.endsWith('/auth/email-verification')) return reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: newProof ? newer : baseline});
      if (path.endsWith('/auth/email/request')) return reply({challenge_id: '0f689afa-5a45-4fb5-a147-9aff36f137dd', retry_after: 60, expires_in: 300, delivery_status: 'accepted'}, 202);
      if (path.endsWith('/auth/email/verify')) return new Promise<Response>((resolve) => {finish = resolve;});
      return reply({error: {code: 'not_found'}}, 404);
    });
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    const receipt = await controller.requestSensitiveEmailVerification();
    const pending = controller.verifySensitiveEmailVerification(receipt.challengeId, '123456');
    controller.cancelSensitiveEmailVerification();
    expect(controller.sensitiveEmailRecovery()).toMatchObject({kind: 'verify'});
    expect(await controller.recheckSensitiveEmailVerification()).toBe(false);
    expect(() => controller.releaseExpiredSensitiveRequest()).toThrow();
    finish(reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: newer}));
    await expect(pending).rejects.toMatchObject({outcomeUnknown: true});
    expect(controller.getSnapshot().user?.emailVerifiedAt).toBeNull();
    newProof = true;
    expect(await controller.recheckSensitiveEmailVerification()).toBe(true);
    expect(controller.getSnapshot().user?.emailVerifiedAt).toBe(newer);
  });

  it('does not carry an uncertain verification across a failed refresh into a different account', async () => {
    let mode: 'first' | 'offline' | 'second' = 'first';
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) {
        if (mode === 'offline') throw new TypeError('offline');
        return reply({user: mode === 'first' ? account : {...account, id: 'other', sessionId: 'other-session'}, expiresAt, csrfToken: csrf});
      }
      if (path.endsWith('/auth/email-verification')) return reply({contractVersion: 1, sessionId: mode === 'first' ? 'session-one' : 'other-session', emailVerifiedAt: null});
      if (path.endsWith('/auth/email/request')) {
        if (mode === 'first') throw new TypeError('connection lost');
        return reply({challenge_id: '0f689afa-5a45-4fb5-a147-9aff36f137dd', retry_after: 60, expires_in: 300, delivery_status: 'accepted'}, 202);
      }
      return reply({error: {code: 'not_found'}}, 404);
    });
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    await expect(controller.requestSensitiveEmailVerification()).rejects.toMatchObject({outcomeUnknown: true});
    mode = 'offline'; await expect(controller.refresh()).rejects.toThrow();
    mode = 'second'; await controller.refresh();
    expect(controller.getSnapshot().user?.id).toBe('other');
    expect(controller.sensitiveEmailRecovery()).toBeNull();
    await expect(controller.requestSensitiveEmailVerification()).resolves.toMatchObject({challengeId: '0f689afa-5a45-4fb5-a147-9aff36f137dd'});
  });

  it('fences responses from an old role after a session refresh', async () => {
    let role = 'staff';
    let resolve!: (value: Response) => void;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply({user: {...account, role, permissions: role === 'staff' ? ['overview.read'] : ['overview.read', 'users.read']}, expiresAt});
      return new Promise<Response>((finish) => {resolve = finish;});
    });
    const controller = new AdminSessionController({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    const old = controller.request('core/users', {body: {}, idempotencyKey: 'request-123456'});
    role = 'admin'; await controller.refresh(); resolve(reply({ok: true}));
    await expect(old).rejects.toMatchObject({outcomeUnknown: true});
    expect(controller.getSnapshot().user?.role).toBe('admin');
  });

  it('does not replay an unconfirmed logout and blocks a new sign-in', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply({user: account, expiresAt});
      throw new TypeError('connection lost');
    });
    const controller = new AdminSessionController({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    await expect(controller.signOut()).rejects.toMatchObject({outcomeUnknown: true});
    expect(controller.getSnapshot()).toMatchObject({status: 'error', logoutUnconfirmed: true, user: null});
    await expect(controller.signIn('a@example.com', 'password')).rejects.toThrow('Complete sign-out');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('preserves same-session checkpoints through failed restoration and clears them only after confirmed logout', async () => {
    Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true});
    const identity: PendingIdentity = {...account, expiresAt};
    await retainPending(identity, 'test-family', 'item', 'original-key-123', 'overview.read', {operation: 'edit'});
    let failSession = true, failLogout = true;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) {if (failSession) throw new TypeError('offline'); return reply({user: account, expiresAt});}
      if (String(url).endsWith('/auth/logout')) {if (failLogout) throw new TypeError('offline'); return reply({ok: true});}
      return reply({error: {code: 'not_found'}}, 404);
    });
    const controller = new AdminSessionController({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await expect(controller.refresh()).rejects.toThrow();
    expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
    failSession = false; await controller.refresh();
    expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
    await expect(controller.signOut()).rejects.toMatchObject({outcomeUnknown: true});
    expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
    failLogout = false; await controller.signOut();
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
    expect(controller.getSnapshot().status).toBe('anonymous');
  });

  it('clears a checkpoint after a definitive anonymous session response', async () => {
    Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true});
    const identity: PendingIdentity = {...account, expiresAt};
    await retainPending(identity, 'test-family', 'item', 'original-key-123', 'overview.read', {operation: 'edit'});
    const fetchImpl = vi.fn(async () => reply({error: {code: 'unauthenticated'}}, 401));
    const controller = new AdminSessionController({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    expect(controller.getSnapshot().status).toBe('anonymous');
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });

  it('binds the confirmed authority before exposure and fences a slower stale restoration', async () => {
    Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true});
    const identity: PendingIdentity = {...account, expiresAt};
    await retainPending(identity, 'test-family', 'item', 'original-key-123', 'overview.read', {operation: 'edit'});
    let release!: () => void, digests = 0;
    const digest = webcrypto.subtle.digest.bind(webcrypto.subtle);
    Object.defineProperty(globalThis, 'crypto', {value: {subtle: {digest: (algorithm: AlgorithmIdentifier, data: BufferSource) => {
      digests++;
      if (digests !== 1) return digest(algorithm, data);
      return new Promise<ArrayBuffer>((resolve, reject) => {release = () => {void digest(algorithm, data).then(resolve, reject);};});
    }}}, configurable: true});
    let switched = false;
    const fetchImpl = vi.fn(async () => reply({user: switched ? {...account, id: 'different-operator', sessionId: 'different-session'} : account, expiresAt}));
    const controller = new AdminSessionController({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    const old = controller.refresh();
    await vi.waitFor(() => expect(digests).toBe(1));
    expect(controller.getSnapshot().status).toBe('loading');
    switched = true; await controller.refresh();
    expect(controller.getSnapshot().user?.id).toBe('different-operator');
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
    release(); await old;
    expect(controller.getSnapshot().user?.id).toBe('different-operator');
  });

  it('rechecks same-session email verification before changing the password', async () => {
    const proof = new Date(Date.now() - 5_000).toISOString();
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: {...account, permissions: ['account.manage']}, expiresAt, csrfToken: csrf});
      if (path.endsWith('/auth/email-verification')) return reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: proof});
      if (path.endsWith('/auth/change-password')) return reply({ok: true});
      return reply({error: {code: 'not_found'}}, 404);
    });
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh(); await controller.changePassword('old-password', 'different-new-password');
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/email-verification'))).toHaveLength(2);
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/change-password'))).toHaveLength(1);
    expect(controller.getSnapshot()).toMatchObject({status: 'anonymous', user: null});
  });

  it('does not submit a password change when the email proof is stale', async () => {
    const proof = new Date(Date.now() - 600_000).toISOString();
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session') ? reply({user: {...account, permissions: ['account.manage']}, expiresAt, csrfToken: csrf}) : reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: proof}));
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    await expect(controller.changePassword('old-password', 'different-new-password')).rejects.toMatchObject({code: 'recent_email_sign_in_required'});
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/change-password'))).toHaveLength(0);
  });

  it('does not replay a password change after a lost response', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply({user: {...account, permissions: ['account.manage']}, expiresAt});
      throw new TypeError('connection lost');
    });
    const controller = new AdminSessionController({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    await expect(controller.changePassword('old-password', 'different-new-password')).rejects.toMatchObject({outcomeUnknown: true});
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/change-password'))).toHaveLength(1);
  });

  it('confirms the rotated authenticator session after verification', async () => {
    let verified = false;
    const principalId = 'fa1e3f37-1e2b-4e57-9d7d-77f0c13d0d50';
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply({user: {...account, principalId, assuranceLevel: verified ? 2 : 1, mfaAt: verified ? new Date().toISOString() : null}, expiresAt});
      if (String(url).endsWith('/auth/mfa/verify')) {verified = true; return reply({ok: true});}
      return reply({error: {code: 'not_found'}}, 404);
    });
    const controller = new AdminSessionController({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh();
    await controller.verifyAuthenticator('cdd3c1c0-c124-4c8a-9719-bd2435d198d1', '0f689afa-5a45-4fb5-a147-9aff36f137dd', '123456');
    expect(controller.getSnapshot()).toMatchObject({status: 'authenticated', user: {assuranceLevel: 2, sessionId: 'session-one'}});
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/mfa/verify'))).toHaveLength(1);
  });
});

describe('browser handoffs', () => {
  it('removes one-use setup tokens from history and retains them only in memory', () => {
    const location = {hash: '#/admin/setup?token=' + 'a'.repeat(64) + '&invite=true', pathname: '/', search: '', origin: 'https://platform-admin.collect.ikanisa.com'} as Location;
    const history = {replaceState: vi.fn()} as unknown as History;
    expect(captureSetupLocation(location, history)).toEqual({token: 'a'.repeat(64), invite: true});
    expect(history.replaceState).toHaveBeenCalledWith(null, '', '/#/admin/setup');
  });

  it('rejects foreign or account return destinations and keeps encoded safe query values', () => {
    expect(safeAdminReturnLocation('https://evil.example/admin')).toBeNull();
    expect(safeAdminReturnLocation('//evil.example/admin')).toBeNull();
    expect(safeAdminReturnLocation('/admin/setup?token=abc')).toBeNull();
    expect(safeAdminReturnLocation('/admin/groups?search=a%26b')).toBe('/admin/groups?search=a%26b');
    expect(safeAdminVerificationReturnLocation('/admin/groups?returnTo=https%3A%2F%2Fevil.example&token=secret')).toBe('/admin/groups');
    expect(safeAdminVerificationReturnLocation('/admin/requests?key=request-123456&token=secret')).toBe('/admin/requests?key=request-123456');
    expect(safeAdminVerificationReturnLocation('/admin/groups/%2f..%2fsecret')).toBeNull();
  });

  it('accepts only the current exact CAPTCHA envelope', () => {
    const id = '0d7bfc80-d88c-4b4c-9f7d-9935f6c5aaf1';
    expect(parseCaptchaEnvelope({type: 'collect.turnstile.v1', attempt_id: id, token: 'abc123'}, id)).toBe('abc123');
    expect(() => parseCaptchaEnvelope({type: 'collect.turnstile.v1', attempt_id: 'wrong', token: 'abc123'}, id)).toThrow();
    expect(() => parseCaptchaEnvelope({type: 'collect.turnstile.v1', attempt_id: id, token: 'abc123', extra: true}, id)).toThrow();
  });

  it('allows only the existing managed Google authorization and callback origins', () => {
    const origin = 'https://platform-admin.collect.ikanisa.com', state = 'a'.repeat(43);
    const redirect = `${origin}/functions/v1/collect-api/v1/auth/google/callback?state=${state}`;
    const url = new URL('https://rrlduytparvsjfmegalh.supabase.co/auth/v1/authorize');
    url.search = new URLSearchParams({provider: 'google', redirect_to: redirect, code_challenge: state, code_challenge_method: 's256'}).toString();
    expect(googleAuthorizationUrl(url.href, origin, url.origin)).toBe(url.href);
    url.searchParams.append('redirect_to', 'https://evil.example/');
    expect(() => googleAuthorizationUrl(url.href, origin, url.origin)).toThrow();
  });

  it('validates authenticator factor and account-bound setup material', () => {
    const id = 'cdd3c1c0-c124-4c8a-9719-bd2435d198d1', secret = 'A'.repeat(32);
    const factor = {id, factor_type: 'totp', status: 'unverified', friendly_name: 'Collect Admin'};
    const uri = `otpauth://totp/${encodeURIComponent('Collect:a@example.com')}?secret=${secret}&issuer=Collect&algorithm=SHA1&digits=6&period=30`;
    const user = {...account, expiresAt, emailVerifiedAt: null, principalId: null} as const;
    expect(parseFactor(factor)).toEqual({id, name: 'Collect Admin', verified: false});
    expect(parseSetup({...factor, totp: {secret, uri}}, user).secret).toBe(secret);
    expect(() => parseSetup({...factor, totp: {secret, uri: uri.replace('a%40example.com', 'b%40example.com')}}, user)).toThrow();
  });
});
