import {webcrypto} from 'node:crypto';
import {fireEvent, render, screen, waitFor} from '@testing-library/react';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import type {ReactNode} from 'react';
import {AuthenticatorPage} from '../../src/session/AuthenticatorPage';
import {SessionProvider, useSession} from '../../src/session/SessionProvider';
// Exercise the unqualified protocol in isolation; the shipped candidate keeps it disabled.
vi.mock('../../src/session/mfaQualification', () => ({MANAGED_MFA_TRANSITION_QUALIFIED: true}));

const principalId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', factorId = '11111111-1111-4111-8111-111111111111';
const challengeId = '22222222-2222-4222-8222-222222222222', csrf = 'c'.repeat(64), publishableKey = 'sb_publishable_' + 'a'.repeat(32);
const user = {id: 'actor-one', email: 'a@example.test', role: 'staff', sessionId: 'session-one', principalId, permissions: ['overview.read'], assuranceLevel: 1, mfaAt: null, mfaAvailable: true, financialModel: 'canonical_evidence_ledger'};
const reply = (body: unknown) => new Response(JSON.stringify(body), {status: 200, headers: {'Content-Type': 'application/json'}});
const proof = () => ({contractVersion: 1, sessionId: user.sessionId, emailVerifiedAt: new Date().toISOString()});
const originalCrypto = globalThis.crypto;
beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true}); localStorage.clear(); sessionStorage.clear();});
afterEach(() => {localStorage.clear(); sessionStorage.clear(); Object.defineProperty(globalThis, 'crypto', {value: originalCrypto, configurable: true});});
function Protected({children}: {children: ReactNode}) {return useSession().status === 'authenticated' ? children : null;}
function app(fetchImpl: typeof fetch) {return <SessionProvider config={{backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}}><Protected><AuthenticatorPage onBack={() => undefined} onSignIn={() => undefined} /></Protected></SessionProvider>;}

describe('Managed authenticator page', () => {
  it('requires fresh email for enrollment and cancellation, with the setup key only in memory', async () => {
    const secret = 'A'.repeat(32), label = encodeURIComponent('Collect:a@example.test');
    const uri = `otpauth://totp/${label}?secret=${secret}&issuer=Collect&algorithm=SHA1&digits=6&period=30`;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user, expiresAt: new Date(Date.now() + 3_600_000).toISOString(), csrfToken: csrf});
      if (path.endsWith('/auth/email-verification')) return reply(proof());
      if (path.endsWith('/auth/mfa/factors')) return reply({id: principalId, factors: []});
      if (path.endsWith('/auth/mfa/enroll')) {expect(JSON.parse(String(init?.body))).toEqual({friendly_name: 'Collect Admin', factor_type: 'totp'}); return reply({id: factorId, factor_type: 'totp', status: 'unverified', friendly_name: 'Collect Admin', totp: {secret, uri}});}
      if (path.endsWith('/auth/mfa/cancel-enrollment')) {expect(JSON.parse(String(init?.body))).toEqual({factor_id: factorId}); return reply({id: factorId, factor_type: 'totp', status: 'revoked'});}
      throw new Error('Unexpected request');
    });
    render(app(fetchImpl)); fireEvent.click(await screen.findByRole('button', {name: 'Connect authenticator'}));
    expect(await screen.findByLabelText('Setup key')).toHaveValue(secret);
    expect(JSON.stringify(sessionStorage)).not.toContain(secret); expect(JSON.stringify(localStorage)).not.toContain(secret);
    fireEvent.click(screen.getByRole('button', {name: 'Cancel pending setup'}));
    fireEvent.click(screen.getByRole('button', {name: 'Confirm cancellation'}));
    await waitFor(() => expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/mfa/cancel-enrollment'))).toHaveLength(1));
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/email-verification')).length).toBeGreaterThanOrEqual(3);
  });

  it('rejects a challenge bound to a different factor before dispatching the code', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user, expiresAt: new Date(Date.now() + 3_600_000).toISOString(), csrfToken: csrf});
      if (path.endsWith('/auth/email-verification')) return reply(proof());
      if (path.endsWith('/auth/mfa/factors')) return reply({id: principalId, factors: [{id: factorId, factor_type: 'totp', status: 'verified', friendly_name: 'Authenticator'}]});
      if (path.endsWith('/auth/mfa/challenge')) return reply({id: challengeId, challenge_id: challengeId, factor_id: '33333333-3333-4333-8333-333333333333', expires_at: Math.floor(Date.now() / 1000) + 60});
      throw new Error('Unexpected request');
    });
    render(app(fetchImpl)); fireEvent.change(await screen.findByLabelText('Authenticator code'), {target: {value: '123456'}});
    fireEvent.click(screen.getByRole('button', {name: 'Verify code'}));
    expect(await screen.findByRole('alert')).toHaveTextContent('challenge could not be verified');
    expect(fetchImpl.mock.calls.some(([url]) => String(url).endsWith('/auth/mfa/verify'))).toBe(false);
  });

  it('does not enroll when the same-session email verification is stale', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user, expiresAt: new Date(Date.now() + 3_600_000).toISOString(), csrfToken: csrf});
      if (path.endsWith('/auth/email-verification')) return reply({...proof(), emailVerifiedAt: new Date(Date.now() - 300_001).toISOString()});
      if (path.endsWith('/auth/mfa/factors')) return reply({id: principalId, factors: []});
      throw new Error('Unexpected request');
    });
    render(app(fetchImpl)); fireEvent.click(await screen.findByRole('button', {name: 'Connect authenticator'}));
    expect(await screen.findByRole('alert')).toHaveTextContent('Verify your email');
    expect(fetchImpl.mock.calls.some(([url]) => String(url).endsWith('/auth/mfa/enroll'))).toBe(false);
  });
});
