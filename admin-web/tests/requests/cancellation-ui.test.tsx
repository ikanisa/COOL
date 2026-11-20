import {render, screen, waitFor, within} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import type {AdminRequestOptions} from '../../src/api/client';
import {canonicalRequestId, type PendingIdentity} from '../../src/features/core';
import {RequestHistoryPage} from '../../src/features/requests/RequestHistoryPage';

const principalId = '12345678-1234-4123-8123-123456789012', target = 'request-original-001', reason = 'Review and block the original reference';
const marker = {contract_version: 2, model: 'canonical_evidence_ledger'}, missing = {...marker, status: 'not_found'};
const identity = (): PendingIdentity => ({id: 'actor-a', sessionId: 'session-a', email: 'admin@example.test', role: 'admin',
  permissions: ['overview.read', 'account.manage'], expiresAt: new Date(Date.now() + 3600000).toISOString()});
const originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
beforeEach(() => {
  sessionStorage.clear(); localStorage.clear();
  Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (_name: string, _options: unknown, work: (lock: object) => Promise<unknown>) => work({})}});
});
afterEach(() => {if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('request cancellation review', () => {
  it('keeps cancellation disabled by default and never posts', async () => {
    const request = vi.fn(async (path: string, _options?: AdminRequestOptions) => path.startsWith('operations/requests?') ? {...marker, rows: [], total: 0} : missing);
    render(<RequestHistoryPage request={request} permissions={['overview.read', 'account.manage']} actorId="actor-a" principalId={principalId}
      authorityKey="authority-a" financialModel="canonical_evidence_ledger" role="admin" navigate={() => undefined} identity={identity()} verifyFresh={async () => true} locationSearch={`?key=${target}`} />);
    const user = userEvent.setup(); await user.click(screen.getByRole('button', {name: 'Check request'}));
    await screen.findByText(/does not prove that an attempted change failed/i);
    expect(screen.queryByRole('button', {name: 'Review cancellation of original reference'})).not.toBeInTheDocument();
    expect(request.mock.calls.every(([, options]) => options?.method !== 'POST')).toBe(true);
  });
  it('requires a fresh verification before sending the reviewed cancellation', async () => {
    const request = vi.fn(async (path: string, _options?: AdminRequestOptions) => path.startsWith('operations/requests?') ? {...marker, rows: [], total: 0} : missing);
    render(<RequestHistoryPage request={request} permissions={['overview.read', 'account.manage']} actorId="actor-a" principalId={principalId}
      authorityKey="authority-a" financialModel="canonical_evidence_ledger" role="admin" navigate={() => undefined} identity={identity()} verifyFresh={async () => false} allowCancellation locationSearch={`?key=${target}`} />);
    const user = userEvent.setup(); await user.click(screen.getByRole('button', {name: 'Check request'}));
    await user.click(await screen.findByRole('button', {name: 'Review cancellation of original reference'}));
    await user.type(screen.getByLabelText('Cancellation reason'), reason);
    await user.click(screen.getByRole('button', {name: 'Cancel uncommitted request'}));
    expect(await screen.findByRole('button', {name: 'Open account security'})).toBeVisible();
    expect(request.mock.calls.every(([, options]) => options?.method !== 'POST')).toBe(true);
  });
  it('recovers a lost response with writes off, then retries only the original key and displayed reason after review', async () => {
    const done = {...marker, status: 'cancelled', request_id: await canonicalRequestId(principalId, target), receipt: null};
    let committed = false, posts = 0;
    const request = vi.fn(async (path: string, options?: AdminRequestOptions) => {
      if (path.startsWith('operations/requests?')) return {...marker, rows: [], total: 0};
      if (options?.method === 'POST') {posts++; committed = true; if (posts === 1) throw new Error('lost response'); return done;}
      return committed ? done : missing;
    });
    const props = {request, permissions: ['overview.read', 'account.manage'], actorId: 'actor-a', principalId, authorityKey: 'authority-a',
      financialModel: 'canonical_evidence_ledger' as const, role: 'admin' as const, navigate: () => undefined, identity: identity(), verifyFresh: async () => true};
    const user = userEvent.setup(), first = render(<RequestHistoryPage {...props} allowCancellation locationSearch={`?key=${target}`} />);
    await user.click(screen.getByRole('button', {name: 'Check request'}));
    await user.click(await screen.findByRole('button', {name: 'Review cancellation of original reference'}));
    await user.type(screen.getByLabelText('Cancellation reason'), reason);
    await user.click(screen.getByRole('button', {name: 'Cancel uncommitted request'}));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(await screen.findByText(/The cancellation result is unknown/)).toBeVisible();
    first.unmount();
    const second = render(<RequestHistoryPage {...props} />);
    await user.click(screen.getByRole('button', {name: 'Find retained cancellations'}));
    const recovery = await screen.findByText(target);
    await user.click(within(recovery.parentElement!.parentElement!).getByRole('button', {name: 'Check original target'}));
    const panel = await screen.findByRole('region', {name: 'Original request cancellation'});
    await user.click(await within(panel).findByRole('button', {name: 'Check original target'}));
    expect(await within(panel).findByText(/original reference is blocked/i)).toBeVisible();
    expect(within(panel).queryByRole('button', {name: 'Review same cancellation'})).not.toBeInTheDocument();
    second.rerender(<RequestHistoryPage {...props} allowCancellation />);
    await user.click(await within(panel).findByRole('button', {name: 'Review same cancellation'}));
    expect(screen.getByLabelText('Cancellation reason')).toHaveValue(reason);
    expect(screen.getByLabelText('Cancellation reason')).toHaveAttribute('readonly');
    await user.click(screen.getByRole('button', {name: 'Retry same cancellation'}));
    expect(await within(panel).findByText(/original reference is blocked/i)).toBeVisible();
    const sends = request.mock.calls.filter(([, options]) => options?.method === 'POST');
    expect(sends).toHaveLength(2); expect(sends[1]).toEqual(sends[0]);
    expect(sends[0][1]?.body).toEqual({reason});
  });
});
