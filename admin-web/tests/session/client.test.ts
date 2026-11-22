import {describe, expect, it, vi} from 'vitest';
import {AdminApiClient, AdminRequestError, type AuthoritySnapshot} from '../../src/api/client';

const publishableKey = 'sb_publishable_' + 'a'.repeat(32);
const csrf = 'c'.repeat(64);
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status, headers: {'Content-Type': 'application/json'}});

describe('same-origin Admin transport', () => {
  it('negotiates protected owner metadata only on the Supabase session read', async () => {
    const fetchImpl = vi.fn(async () => reply({ok: true}));
    const client = new AdminApiClient({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}, () => ({epoch: 1, key: 'session', csrfToken: csrf}), () => undefined, () => undefined);
    await client.request('auth/session', {authenticated: false});
    await client.request('core/groups');
    expect((fetchImpl.mock.calls[0] as unknown as [string, RequestInit])[1].headers).toHaveProperty('X-Collect-Owner-Identity-Version', '1');
    expect((fetchImpl.mock.calls[1] as unknown as [string, RequestInit])[1].headers).not.toHaveProperty('X-Collect-Owner-Identity-Version');
  });

  it('limits CSRF-free MFA recovery to the exact cookie-bound per-tab intent', async () => {
    const fetchImpl = vi.fn(async () => reply({ok: true})), unauthorized = vi.fn();
    const client = new AdminApiClient({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}, () => ({epoch: 1, key: 'session', csrfToken: csrf}), () => undefined, unauthorized);
    const intent = {factor_id: '11111111-1111-4111-8111-111111111111', challenge_id: '22222222-2222-4222-8222-222222222222', verification_id: 'a'.repeat(64)};
    for (const path of ['auth/mfa/recover', 'auth/logout']) {
      await client.request(path, {method: 'POST', body: intent, authenticated: false, mfaRecovery: true});
      const [, init] = fetchImpl.mock.calls.at(-1) as unknown as [string, RequestInit];
      expect(init.credentials).toBe('same-origin');
      expect(init.headers).toEqual(expect.objectContaining({'X-Collect-Admin': '1', 'X-Collect-Requested-With': 'collect-admin'}));
      expect(init.headers).not.toHaveProperty('X-Collect-CSRF');
      expect(JSON.parse(String(init.body))).toEqual(intent);
    }
    await expect(client.request('core/groups', {method: 'POST', body: intent, mfaRecovery: true})).rejects.toThrow('Invalid MFA recovery request');
    await expect(client.request('auth/mfa/recover', {method: 'POST', body: {...intent, extra: 'x'}, authenticated: false, mfaRecovery: true})).rejects.toThrow('Invalid MFA recovery request');
    await expect(client.request('auth/mfa/recover', {method: 'POST', body: intent, authenticated: false})).rejects.toThrow('original intent');
    const other = new AdminApiClient({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}, () => ({epoch: 1, key: null, csrfToken: null}), () => undefined, unauthorized);
    await expect(other.request('auth/logout', {method: 'POST', body: intent, authenticated: false, mfaRecovery: true})).rejects.toThrow('Invalid MFA recovery request');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it.each([false, true])('retains MFA recovery context on HTTP 401 (unreadable body: %s)', async (unreadable) => {
    const unauthorized = vi.fn(), fetchImpl = vi.fn(async () => unreadable ?
      new Response(new Uint8Array([0x80]), {status: 401}) : reply({error: {code: 'unauthenticated'}}, 401));
    const client = new AdminApiClient({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}, () => ({epoch: 1, key: null, csrfToken: null}), () => undefined, unauthorized);
    await expect(client.request('auth/mfa/recover', {method: 'POST', authenticated: false, mfaRecovery: true, body: {factor_id: '11111111-1111-4111-8111-111111111111', challenge_id: '22222222-2222-4222-8222-222222222222', verification_id: 'a'.repeat(64)}})).rejects.toMatchObject({statusCode: 401, outcomeUnknown: true});
    expect(unauthorized).not.toHaveBeenCalled();
  });

  it('uses server session headers and never a browser bearer token', async () => {
    let authority: AuthoritySnapshot = {epoch: 1, key: 'owner-session', csrfToken: csrf};
    const fetchImpl = vi.fn(async () => reply({ok: true}));
    const client = new AdminApiClient({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}, () => authority, () => undefined, () => {authority = {epoch: 2, key: null, csrfToken: null};});
    await expect(client.request('core/groups', {body: {name: 'A'}, idempotencyKey: 'request-123456', reviewReason: 'Correct group record'})).resolves.toEqual({ok: true});
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('/api/admin/core/groups');
    expect(init.method).toBe('POST');
    expect(init.credentials).toBe('same-origin');
    expect(init.redirect).toBe('error');
    expect(init.headers).toEqual(expect.objectContaining({apikey: publishableKey, 'X-Collect-Admin': '1', 'X-Collect-Requested-With': 'collect-admin', 'X-Collect-CSRF': csrf, 'Idempotency-Key': 'request-123456'}));
    expect(init.headers).not.toHaveProperty('Authorization');
  });

  it('refuses path escapes and authenticated writes without current CSRF', async () => {
    const fetchImpl = vi.fn(async () => reply({ok: true}));
    const client = new AdminApiClient({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}, () => ({epoch: 1, key: 'session', csrfToken: null}), () => undefined, () => undefined);
    await expect(client.request('../auth/session')).rejects.toThrow('Invalid Admin request path');
    await expect(client.request('core/groups', {body: {}})).rejects.toThrow('Refresh your session');
    await expect(client.request('core/groups', {authenticated: false})).rejects.toThrow('requires an authenticated session');
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it.each([200, 401])('does not apply HTTP %i after an authority change', async (status) => {
    let authority: AuthoritySnapshot = {epoch: 1, key: 'one', csrfToken: csrf};
    let resolve!: (value: Response) => void;
    const unauthorized = vi.fn();
    const fetchImpl = vi.fn(() => new Promise<Response>((finish) => {resolve = finish;}));
    const client = new AdminApiClient({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}, () => authority, () => undefined, unauthorized);
    const operation = client.request('core/groups', {body: {}, idempotencyKey: 'request-123456'});
    authority = {epoch: 2, key: 'two', csrfToken: csrf};
    resolve(reply({ok: status === 200}, status));
    await expect(operation).rejects.toMatchObject({outcomeUnknown: true});
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(unauthorized).not.toHaveBeenCalled();
  });

  it('preserves unknown outcomes and never retries a mutation or effectful read', async () => {
    const fetchImpl = vi.fn(async () => reply({error: {code: 'proxy_outcome_unknown'}}, 502));
    const client = new AdminApiClient({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}, () => ({epoch: 1, key: 'session', csrfToken: csrf}), () => undefined, () => undefined);
    await expect(client.request('auth/session', {authenticated: false})).rejects.toMatchObject({outcomeUnknown: true, code: 'proxy_outcome_unknown'});
    await expect(client.request('core/groups', {body: {}, idempotencyKey: 'request-123456'})).rejects.toMatchObject({outcomeUnknown: true});
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('fails closed if a required challenge cannot be acquired', async () => {
    const fetchImpl = vi.fn(async () => reply({ok: true}));
    const client = new AdminApiClient({backend: 'supabase', publishableKey, captchaEnabled: true, googleEnabled: false, fetchImpl}, () => ({epoch: 1, key: null, csrfToken: null}), () => undefined, () => undefined);
    await expect(client.request('auth/otp', {body: {email: 'a@example.com'}, authenticated: false})).rejects.toBeInstanceOf(AdminRequestError);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('refuses the unsupported Cloudflare challenge rather than dropping it', () => {
    expect(() => new AdminApiClient({backend: 'cloudflare', captchaEnabled: true, googleEnabled: false},
      () => ({epoch: 0, key: null, csrfToken: null}), () => undefined, () => undefined)).toThrow('challenge is unavailable');
  });

  it('calls the native fetch with its global receiver', async () => {
    const nativeFetch = vi.fn(function (this: typeof globalThis) {
      if (this !== globalThis) throw new TypeError('Illegal invocation');
      return Promise.resolve(reply({user: null}));
    });
    vi.stubGlobal('fetch', nativeFetch);
    try {
      const client = new AdminApiClient({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false}, () => ({epoch: 0, key: null, csrfToken: null}), () => undefined, () => undefined);
      await expect(client.request('auth/session', {authenticated: false})).resolves.toEqual({user: null});
      expect(nativeFetch).toHaveBeenCalledOnce();
    } finally {vi.unstubAllGlobals();}
  });
});
