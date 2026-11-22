import {fireEvent, render, screen, waitFor} from '@testing-library/react';
import {describe, expect, it, vi} from 'vitest';
import type {ReactNode} from 'react';
import {AccountSecurityPage} from '../../src/session/AccountSecurityPage';
import {SensitiveEmailVerificationPage} from '../../src/session/SensitiveEmailVerificationPage';
import {SessionProvider, useSession} from '../../src/session/SessionProvider';

const expiresAt = new Date(Date.now() + 3_600_000).toISOString();
const user = {id: 'operator-one', email: 'a@example.com', role: 'staff', sessionId: 'session-one', permissions: ['account.manage'], assuranceLevel: 1, mfaAt: null, financialModel: 'transaction_journals'};
const reply = (body: unknown) => new Response(JSON.stringify(body), {status: 200, headers: {'Content-Type': 'application/json'}});
function Protected({children}: {children: ReactNode}) {return useSession().status === 'authenticated' ? children : null;}

describe('account security', () => {
  it.each([true, false])('shows managed authenticator access only when the server advertises it: %s', async (mfaAvailable) => {
    const publishableKey = 'sb_publishable_' + 'a'.repeat(32), csrf = 'c'.repeat(64), onAuthenticator = vi.fn();
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session')
      ? reply({user: {...user, mfaAvailable, financialModel: 'canonical_evidence_ledger'}, expiresAt, csrfToken: csrf})
      : reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: null}));
    render(<SessionProvider config={{backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}}><Protected><AccountSecurityPage onVerify={() => undefined} onAuthenticator={onAuthenticator} onLicenses={() => undefined} onPasswordRecovery={() => undefined} onSignIn={() => undefined} /></Protected></SessionProvider>);
    await screen.findByRole('button', {name: 'Verify email'});
    const button = screen.queryByRole('button', {name: 'Authenticator'});
    if (mfaAvailable) {expect(button).toBeInTheDocument(); fireEvent.click(button!); expect(onAuthenticator).toHaveBeenCalledOnce();}
    else expect(button).not.toBeInTheDocument();
  });

  it('keeps the existing Cloudflare authenticator verification link', async () => {
    const onVerify = vi.fn(), fetchImpl = vi.fn(async () => reply({user, expiresAt}));
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><Protected><AccountSecurityPage onVerify={onVerify} onAuthenticator={() => undefined} onLicenses={() => undefined} onPasswordRecovery={() => undefined} onSignIn={() => undefined} /></Protected></SessionProvider>);
    fireEvent.click(await screen.findByRole('button', {name: 'Authenticator'})); expect(onVerify).toHaveBeenCalledOnce();
  });

  it('clears credential fields and blocks repeated password changes after a lost response', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply({user, expiresAt});
      throw new TypeError('connection lost');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><Protected><AccountSecurityPage onVerify={() => undefined} onLicenses={() => undefined} onPasswordRecovery={() => undefined} onSignIn={() => undefined} /></Protected></SessionProvider>);
    await screen.findByLabelText('Current password');
    fireEvent.change(screen.getByLabelText('Current password'), {target: {value: 'old-password'}});
    fireEvent.change(screen.getByLabelText('New password'), {target: {value: 'different-new-password'}});
    fireEvent.change(screen.getByLabelText('Confirm new password'), {target: {value: 'different-new-password'}});
    fireEvent.click(screen.getByRole('button', {name: 'Change password'}));
    expect(await screen.findByRole('button', {name: 'Back to sign in'})).toBeInTheDocument();
    expect(screen.getByLabelText('Current password')).toHaveValue('');
    expect(screen.getByLabelText('New password')).toHaveValue('');
    expect(screen.getByRole('button', {name: 'Change password'})).toBeDisabled();
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/change-password'))).toHaveLength(1);
  });

  it('shows an expired sensitive code and honors the server resend interval', async () => {
    const publishableKey = 'sb_publishable_' + 'a'.repeat(32), csrf = 'c'.repeat(64);
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: {...user, financialModel: 'canonical_evidence_ledger'}, expiresAt, csrfToken: csrf});
      if (path.endsWith('/auth/email-verification')) return reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: null});
      if (path.endsWith('/auth/email/request')) return new Response(JSON.stringify({challenge_id: '0f689afa-5a45-4fb5-a147-9aff36f137dd', retry_after: 60, expires_in: 0, delivery_status: 'accepted'}), {status: 202, headers: {'Content-Type': 'application/json'}});
      return reply({error: {code: 'not_found'}});
    });
    render(<SessionProvider config={{backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}}><Protected><SensitiveEmailVerificationPage onDone={() => undefined} /></Protected></SessionProvider>);
    await waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(2));
    fireEvent.click(await screen.findByRole('button', {name: 'Send email code'}));
    expect(await screen.findByText('This code has expired. Request a new code.')).toBeInTheDocument();
    expect(screen.getByRole('button', {name: /Request again in/})).toBeDisabled();
    expect(screen.queryByRole('button', {name: 'Verify email'})).not.toBeInTheDocument();
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/email/request'))).toHaveLength(1);
  });

  it('reports a confirmed email step separately from going back', async () => {
    const publishableKey = 'sb_publishable_' + 'a'.repeat(32), csrf = 'c'.repeat(64), onDone = vi.fn();
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session')
      ? reply({user: {...user, financialModel: 'canonical_evidence_ledger'}, expiresAt, csrfToken: csrf})
      : reply({contractVersion: 1, sessionId: 'session-one', emailVerifiedAt: new Date().toISOString()}));
    render(<SessionProvider config={{backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}}><Protected><SensitiveEmailVerificationPage onDone={onDone} /></Protected></SessionProvider>);
    fireEvent.click(await screen.findByRole('button', {name: 'Check verification'}));
    await waitFor(() => expect(onDone).toHaveBeenCalledWith(true));
    fireEvent.click(screen.getByRole('button', {name: 'Back'}));
    expect(onDone).toHaveBeenLastCalledWith(false);
  });
});
