import {fireEvent, render, screen, waitFor} from '@testing-library/react';
import {describe, expect, it, vi} from 'vitest';
import {LoginPage} from '../../src/session/AuthPages';
import {SessionProvider} from '../../src/session/SessionProvider';

const publishableKey = 'sb_publishable_' + 'a'.repeat(32);
const csrf = 'c'.repeat(64);
const account = {id: 'operator-one', email: 'a@example.com', role: 'staff', sessionId: 'session-one', permissions: ['overview.read'], assuranceLevel: 1, mfaAt: null, financialModel: 'canonical_evidence_ledger'};
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status, headers: {'Content-Type': 'application/json'}});

describe('email sign-in', () => {
  it('shows an initial session error and requires a fresh check before sign-in', async () => {
    let calls = 0;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session') && ++calls === 1) throw new TypeError('offline');
      return reply({user: null, expiresAt: null, csrfToken: null});
    });
    render(<SessionProvider config={{backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}}><LoginPage onSignedIn={() => undefined} onForgotPassword={() => undefined} /></SessionProvider>);
    const check = await screen.findByRole('button', {name: 'Check session'});
    expect(screen.getByLabelText('Email')).toBeDisabled();
    expect(screen.getByText(/workspace could not be reached/i)).toBeInTheDocument();
    fireEvent.click(check);
    expect(await screen.findByRole('button', {name: 'Send sign-in code'})).toBeInTheDocument();
    expect(screen.getByLabelText('Email')).toBeEnabled();
    expect(calls).toBe(2);
  });

  it('requests a real challenge, verifies it once and confirms the cookie session', async () => {
    let signedIn = false;
    const expiresAt = new Date(Date.now() + 3_600_000).toISOString();
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return signedIn ? reply({user: account, expiresAt, csrfToken: csrf}) : reply({user: null, expiresAt: null, csrfToken: null});
      if (path.endsWith('/auth/otp')) return reply({challenge_id: 'challenge-123', retry_after: 60, expires_in: 300, delivery_status: 'accepted'});
      if (path.endsWith('/auth/verify')) {signedIn = true; return reply({user: account, expiresAt, csrfToken: csrf});}
      if (path.endsWith('/auth/email-verification')) return reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: null});
      return reply({error: {code: 'not_found'}}, 404);
    });
    const onSignedIn = vi.fn();
    render(<SessionProvider config={{backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}}><LoginPage onSignedIn={onSignedIn} onForgotPassword={() => undefined} /></SessionProvider>);
    await waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(1));
    fireEvent.change(screen.getByLabelText('Email'), {target: {value: 'a@example.com'}});
    fireEvent.click(screen.getByRole('button', {name: 'Send sign-in code'}));
    const code = await screen.findByLabelText('6-digit code');
    fireEvent.change(code, {target: {value: '123456'}});
    fireEvent.click(screen.getByRole('button', {name: 'Verify and sign in'}));
    await waitFor(() => expect(onSignedIn).toHaveBeenCalled());
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/verify'))).toHaveLength(1);
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/email-verification'))).toHaveLength(1);
  });

  it('does not resubmit an OTP verification after a lost response', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: null, expiresAt: null, csrfToken: null});
      if (path.endsWith('/auth/otp')) return reply({challenge_id: 'challenge-123', retry_after: 60, expires_in: 300, delivery_status: 'accepted'});
      if (path.endsWith('/auth/verify')) throw new TypeError('connection lost');
      return reply({error: {code: 'not_found'}}, 404);
    });
    render(<SessionProvider config={{backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}}><LoginPage onSignedIn={() => undefined} onForgotPassword={() => undefined} /></SessionProvider>);
    await waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(1));
    fireEvent.change(screen.getByLabelText('Email'), {target: {value: 'a@example.com'}});
    fireEvent.click(screen.getByRole('button', {name: 'Send sign-in code'}));
    fireEvent.change(await screen.findByLabelText('6-digit code'), {target: {value: '123456'}});
    fireEvent.click(screen.getByRole('button', {name: 'Verify and sign in'}));
    expect(await screen.findByRole('button', {name: 'Check session'})).toBeInTheDocument();
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/verify'))).toHaveLength(1);
  });
});
