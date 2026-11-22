import {fireEvent, render, screen, waitFor, within} from '@testing-library/react';
import {RouterProvider} from 'react-router';
import {afterEach, describe, expect, it, vi} from 'vitest';
import type {AdminBackend} from '../../src/api/client';
import {makeAdminRouter} from '../../src/app/App';
import {SessionProvider, type AdminOwnerIdentity} from '../../src/session/SessionProvider';

const account = {
  id: 'staff-one', email: 'staff@example.com', role: 'staff', sessionId: 'session-one',
  permissions: ['overview.read', 'collections.read'], assuranceLevel: 1, mfaAt: null,
  financialModel: 'canonical_evidence_ledger',
};
const reply = (body: unknown, status = 200) => Response.json(body, {status});
let router: ReturnType<typeof makeAdminRouter>;

type SessionFixture = {user: typeof account; ownerIdentity?: AdminOwnerIdentity; ownerEmail?: string};

function openAdmin(path: string, {backend = 'supabase', failFirstCheck = false, session = {user: account}}:
  {backend?: AdminBackend; failFirstCheck?: boolean; session?: SessionFixture} = {}) {
  const expiresAt = new Date(Date.now() + 3_600_000).toISOString();
  const requests: string[] = [];
  const fetchImpl: typeof fetch = async (input) => {
    const url = new URL(String(input), window.location.origin);
    requests.push(url.pathname);
    if (url.pathname.endsWith('/auth/session')) {
      if (failFirstCheck) {failFirstCheck = false; return reply({error: {code: 'service_unavailable'}}, 503);}
      return reply({...session, expiresAt, csrfToken: 'c'.repeat(64)});
    }
    if (url.pathname.endsWith('/auth/email-verification')) {
      return reply({contractVersion: 1, sessionId: session.user.sessionId, emailVerifiedAt: null});
    }
    return reply({error: {code: 'not_found'}}, 404);
  };
  window.history.replaceState(null, '', '/#' + path);
  router = makeAdminRouter(null);
  render(<SessionProvider config={{backend, publishableKey: backend === 'supabase' ? 'sb_publishable_' + 'a'.repeat(32) : undefined,
    captchaEnabled: false, googleEnabled: false, fetchImpl}}><RouterProvider router={router} /></SessionProvider>);
  return {requests, expiresAt};
}

afterEach(() => {
  router?.dispose();
  window.history.replaceState(null, '', '/');
});

describe('Admin session recovery through the router', () => {
  it.each([
    ['supabase', 'authenticator', 'verify-email', 'Verify your email'],
    ['cloudflare', 'verify-email', 'authenticator', 'Authenticator'],
  ] as const)('preserves a safe destination when %s switches verification method, then rechecks access', async (backend, start, target, heading) => {
    const query = new URLSearchParams({returnTo: '/admin/burimunsi?draft=private'});
    const {requests} = openAdmin(`/admin/security/${start}?${query}`, {backend});
    await screen.findByRole('heading', {name: heading});
    expect(router.state.location.pathname).toBe(`/admin/security/${target}`);
    expect(new URLSearchParams(router.state.location.search).get('returnTo')).toBe('/admin/burimunsi');

    fireEvent.click(screen.getByRole('button', {name: 'Back'}));
    await screen.findByRole('heading', {name: 'Access unavailable'});
    expect(router.state.location.pathname).toBe('/admin/burimunsi');
    expect(router.state.location.search).toBe('');
    expect(requests.filter(path => !path.includes('/auth/'))).toEqual([]);
  });

  it('returns a resumed expired tab to sign-in before the selected feature can read', async () => {
    const {requests, expiresAt} = openAdmin('/admin/licenses');
    await screen.findByRole('heading', {name: 'Open-source licenses'});
    const now = Date.now.bind(Date);
    const elapsed = Date.parse(expiresAt) - now() + 1;
    vi.spyOn(Date, 'now').mockImplementation(() => now() + elapsed);

    fireEvent.click(screen.getByRole('link', {name: 'Groups'}));
    await screen.findByRole('heading', {name: 'Welcome to Collect'}, {timeout: 4_000});
    expect(router.state.location.pathname).toBe('/admin/login');
    expect(new URLSearchParams(router.state.location.search).get('returnTo')).toBe('/admin/groups');
    expect(requests.filter(path => !path.includes('/auth/'))).toEqual([]);
  });

  it('rechecks a failed session in place before opening the original destination', async () => {
    const {requests} = openAdmin('/admin/licenses', {failFirstCheck: true});
    await screen.findByRole('heading', {name: 'Workspace unavailable'});
    expect(screen.queryByRole('heading', {name: 'Open-source licenses'})).toBeNull();
    fireEvent.click(screen.getByRole('button', {name: 'Try again'}));
    await screen.findByRole('heading', {name: 'Open-source licenses'});
    await waitFor(() => expect(requests.filter(path => path.endsWith('/auth/session'))).toHaveLength(2));
    expect(router.state.location.pathname).toBe('/admin/licenses');
  });
});

describe('Admin navigation for the current session', () => {
  it.each([
    {description: 'managed staff', role: 'staff', model: 'canonical_evidence_ledger', attested: false, accountAccess: false, smsControls: false, requests: false, buri: false},
    {description: 'unattested managed owner', role: 'owner', model: 'canonical_evidence_ledger', attested: false, accountAccess: true, smsControls: true, requests: true, buri: false},
    {description: 'attested managed owner', role: 'owner', model: 'canonical_evidence_ledger', attested: true, accountAccess: true, smsControls: true, requests: true, buri: true},
    {description: 'legacy owner', role: 'owner', model: 'transaction_journals', attested: true, accountAccess: false, smsControls: true, requests: true, buri: false},
  ])('shows the permitted links for a $description', async ({role, model, attested, accountAccess, smsControls, requests, buri}) => {
    const permissions = ['overview.read', 'payments.read', 'admin_users.manage', 'receivers.read', 'receivers.manage'];
    if (accountAccess) permissions.push('account.manage');
    const user = {...account, role, financialModel: model, principalId: 'principal-one', permissions};
    const session: SessionFixture = {user};
    if (attested) {
      session.ownerIdentity = {schemaVersion: 1, adminId: user.id, principalId: user.principalId, email: user.email};
      session.ownerEmail = user.email;
    }
    openAdmin('/admin/licenses', {session});
    await screen.findByRole('heading', {name: 'Open-source licenses'});
    const links = within(screen.getByRole('navigation', {name: 'Admin sections'}));
    expect(links.getByRole('link', {name: 'MoMo receipts'})).toHaveAttribute('href', '#/admin/momo-receipts');
    expect(links.queryByRole('link', {name: 'SMS receipts'})).toBeNull();
    expect(Boolean(links.queryByRole('link', {name: 'SMS controls'}))).toBe(smsControls);
    expect(Boolean(links.queryByRole('link', {name: 'Request history'}))).toBe(requests);
    expect(Boolean(links.queryByRole('link', {name: 'BuriMunsi access'}))).toBe(buri);
  });
});
