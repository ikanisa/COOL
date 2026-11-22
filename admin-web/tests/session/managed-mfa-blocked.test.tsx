import {webcrypto} from 'node:crypto';
import {render, screen} from '@testing-library/react';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import type {ReactNode} from 'react';
import {AuthenticatorPage} from '../../src/session/AuthenticatorPage';
import {AdminSessionController, SessionProvider, useSession} from '../../src/session/SessionProvider';
import {MFA_INTENT_KEY} from '../../src/session/mfaRecovery';

const principalId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', factorId = '11111111-1111-4111-8111-111111111111', challengeId = '22222222-2222-4222-8222-222222222222';
const user = {id: 'actor-one', email: 'a@example.test', role: 'staff', sessionId: 'session-one', principalId, permissions: ['overview.read'], assuranceLevel: 1, mfaAt: null, mfaAvailable: true, financialModel: 'canonical_evidence_ledger'};
const config = {backend: 'supabase' as const, publishableKey: 'sb_publishable_' + 'a'.repeat(32), captchaEnabled: false, googleEnabled: false};
const reply = (body: unknown) => new Response(JSON.stringify(body), {status: 200, headers: {'Content-Type': 'application/json'}});
const originalCrypto = globalThis.crypto;
beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true}); localStorage.clear(); sessionStorage.clear();});
afterEach(() => {localStorage.clear(); sessionStorage.clear(); Object.defineProperty(globalThis, 'crypto', {value: originalCrypto, configurable: true});});
function Protected({children}: {children: ReactNode}) {return useSession().status === 'authenticated' ? children : null;}

describe('unqualified managed authenticator transitions', () => {
  it('blocks every managed MFA request and upgrade before any dispatch', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session') ?
      reply({user, expiresAt: new Date(Date.now() + 3_600_000).toISOString(), csrfToken: 'c'.repeat(64)}) :
      reply({contractVersion: 1, sessionId: user.sessionId, emailVerifiedAt: null}));
    const client = new AdminSessionController({...config, fetchImpl});
    try {
      await client.refresh(); const count = fetchImpl.mock.calls.length;
      for (const path of ['auth/mfa/factors', 'auth/mfa/enroll', 'auth/mfa/challenge', 'auth/mfa/verify', 'auth/mfa/recover', 'auth/mfa/cancel-enrollment']) {
        await expect(client.request(path, {body: {}})).rejects.toThrow('Authenticator access is unavailable');
      }
      await expect(client.verifyAuthenticator(factorId, challengeId, '123456')).rejects.toThrow('Authenticator access is unavailable');
      expect(fetchImpl).toHaveBeenCalledTimes(count); expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull();
    } finally {client.stop();}
  });

  it('preserves an existing intent without restoring the session and permits only exact-intent logout', async () => {
    const intent = {factor_id: factorId, challenge_id: challengeId, verification_id: 'a'.repeat(64), session_id: user.sessionId, user_id: user.id, starting_assurance_level: 1, starting_mfa_at_ms: null, created_at_ms: Date.now()};
    const retained = JSON.stringify(intent); sessionStorage.setItem(MFA_INTENT_KEY, retained);
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain('/auth/logout');
      expect(init?.body).toBe(JSON.stringify({factor_id: factorId, challenge_id: challengeId, verification_id: intent.verification_id}));
      return reply({ok: true});
    });
    const client = new AdminSessionController({...config, fetchImpl});
    try {
      await expect(client.refresh()).rejects.toThrow('Authenticator recovery is unavailable');
      expect(client.getSnapshot()).toMatchObject({status: 'error', user: null, mfaRecoveryPending: true});
      expect(fetchImpl).not.toHaveBeenCalled(); expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBe(retained);
      await client.signOut(); expect(client.getSnapshot().status).toBe('anonymous');
      expect(sessionStorage.getItem(MFA_INTENT_KEY)).toBeNull(); expect(fetchImpl).toHaveBeenCalledOnce();
    } finally {client.stop();}
  });

  it('shows the unavailable state instead of loading managed factors', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session') ?
      reply({user, expiresAt: new Date(Date.now() + 3_600_000).toISOString(), csrfToken: 'c'.repeat(64)}) :
      reply({contractVersion: 1, sessionId: user.sessionId, emailVerifiedAt: null}));
    render(<SessionProvider config={{...config, fetchImpl}}><Protected><AuthenticatorPage onBack={() => undefined} onSignIn={() => undefined} /></Protected></SessionProvider>);
    expect(await screen.findByText('Authenticator access is unavailable for this account.')).toBeInTheDocument();
    expect(fetchImpl.mock.calls.every(([url]) => !String(url).includes('/auth/mfa/'))).toBe(true);
  });
});
