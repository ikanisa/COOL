import {webcrypto} from 'node:crypto';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {AdminSessionController} from '../../src/session/SessionProvider';

const state = 'a'.repeat(43);
vi.mock('../../src/session/google', () => ({
  googleAvailable: () => true,
  googleAuthorizationUrl: () => 'https://example.test/authorize',
  googleChallenge: async () => state,
  randomUrlValue: () => state,
  openGooglePopup: () => ({authorize: async (makeUrl: () => Promise<string>) => {await makeUrl(); return {state, code: 'b'.repeat(43)};}, cancel: () => undefined}),
}));

const expiresAt = new Date(Date.now() + 3_600_000).toISOString(), csrf = 'c'.repeat(64), publishableKey = 'sb_publishable_' + 'a'.repeat(32);
const account = {id: 'actor-one', email: 'a@example.test', role: 'staff', sessionId: 'session-one', permissions: ['overview.read'], assuranceLevel: 1, mfaAt: null, financialModel: 'canonical_evidence_ledger'};
const reply = (body: unknown) => new Response(JSON.stringify(body), {status: 200, headers: {'Content-Type': 'application/json'}});
const controllers: AdminSessionController[] = [], originalCrypto = globalThis.crypto;
beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true}); localStorage.clear(); sessionStorage.clear();});
afterEach(() => {controllers.splice(0).forEach(controller => controller.stop()); localStorage.clear(); sessionStorage.clear(); Object.defineProperty(globalThis, 'crypto', {value: originalCrypto, configurable: true});});

describe('Google sign-in session authority', () => {
  it('accepts a policy advertised only by auth/session after a matching exchange', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/google/start')) return reply({authorization_url: 'https://example.test/authorize'});
      if (String(url).endsWith('/auth/google/exchange')) return reply({user: account, expiresAt, csrfToken: csrf});
      if (String(url).endsWith('/auth/session')) return reply({user: {...account, mfaAvailable: true}, expiresAt, csrfToken: csrf});
      return reply({contractVersion: 1, sessionId: account.sessionId, emailVerifiedAt: null});
    });
    const client = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: true, fetchImpl}); controllers.push(client);
    await client.signInWithGoogle();
    expect(client.getSnapshot()).toMatchObject({status: 'authenticated', user: {id: account.id, mfaAvailable: true}});
  });

  it('still rejects a different role or a required policy in the authoritative session', async () => {
    for (const changed of [{role: 'admin'}, {mfaAvailable: true, mfaRequired: true}]) {
      const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
        if (String(url).endsWith('/auth/google/start')) return reply({authorization_url: 'https://example.test/authorize'});
        if (String(url).endsWith('/auth/google/exchange')) return reply({user: account, expiresAt, csrfToken: csrf});
        if (String(url).endsWith('/auth/session')) return reply({user: {...account, ...changed}, expiresAt, csrfToken: csrf});
        return reply({contractVersion: 1, sessionId: account.sessionId, emailVerifiedAt: null});
      });
      const client = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: true, fetchImpl}); controllers.push(client);
      await expect(client.signInWithGoogle()).rejects.toThrow(); expect(client.getSnapshot().user).toBeNull();
    }
  });
});
