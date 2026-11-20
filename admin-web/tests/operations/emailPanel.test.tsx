import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { retainPending } from '../../src/features/core';
import { withPendingFence } from '../../src/features/operations/pendingFence';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {
  id: '22222222-2222-2222-2222-222222222222', sessionId: 'session-1', email: 'operator@example.com', role: 'admin' as const,
  permissions: ['email.read', 'email.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString(),
  financialModel: 'transaction_journals' as const, principalId: null,
}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request})}));
import { EmailDispatchPanel } from '../../src/features/operations/EmailDispatchPanel';

const key = '33333333-3333-4333-8333-333333333333';
const requestId = '44444444-4444-4444-8444-444444444444';
const originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
beforeEach(() => {
  sessionStorage.clear(); localStorage.clear();
  Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});
});
afterEach(() => {
  mock.request.mockReset();
  if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks);
  else Reflect.deleteProperty(navigator, 'locks');
});

describe('Email dispatch panel', () => {
  it('does not offer a batch action without the qualification gate', async () => {
    render(<EmailDispatchPanel onUpdated={() => {}} />);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(screen.queryByRole('button', {name: 'Review queued batch'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });

  it('requires reason and confirmation before an enabled batch', async () => {
    const user = userEvent.setup(), updated = vi.fn();
    mock.request.mockResolvedValue({request_id: requestId, status: 'succeeded', resource_type: 'email_dispatch', resource_id: requestId, version: 1, accepted: 2, uncertain: 1, suppressed: 0});
    render(<EmailDispatchPanel enabled onUpdated={updated} />);
    await user.type(await screen.findByLabelText('Reason for manual dispatch'), 'Review queued notifications');
    await user.click(screen.getByRole('button', {name: 'Review queued batch'}));
    const confirm = screen.getByRole('button', {name: 'Confirm batch'});
    expect(confirm).toBeDisabled();
    expect(mock.request).not.toHaveBeenCalled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the batch and reason.'}));
    await user.click(confirm);
    expect(await screen.findByText('Dispatch recorded. Provider acceptance is not proof of delivery.')).toBeVisible();
    expect(screen.getByText('Provider accepted: 2; outcome uncertain: 1; suppressed: 0.')).toBeVisible();
    expect(mock.request).toHaveBeenCalledTimes(1);
    expect(updated).toHaveBeenCalledTimes(1);
  });

  it('does not send a confirmation made stale by another tab', async () => {
    const user = userEvent.setup();
    render(<EmailDispatchPanel enabled onUpdated={() => {}} />);
    await user.type(await screen.findByLabelText('Reason for manual dispatch'), 'Review queued notifications');
    await user.click(screen.getByRole('button', {name: 'Review queued batch'}));
    await withPendingFence({identity: mock.user, family: 'email-dispatch', resourceId: 'queue', isCurrent: () => true}, async (access) => {
      access.reserve(key, access.read().revision); access.clear(key);
    });
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the batch and reason.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm batch'}));
    expect(await screen.findByText('The workspace changed or recovery is unavailable. Check the current request and review again.')).toBeVisible();
    expect(mock.request).not.toHaveBeenCalled();
    expect(await screen.findByRole('button', {name: 'Review queued batch'})).toBeVisible();
  });
  it('allows an existing original key to be checked while new batches are gated', async () => {
    const user = userEvent.setup();
    await retainPending(mock.user, 'email-dispatch', 'queue', key, 'email.manage', {reason: 'Review queued notifications'});
    mock.request.mockResolvedValue({status: 'not_found'});
    render(<EmailDispatchPanel onUpdated={() => {}} />);
    await user.click(await screen.findByRole('button', {name: 'Check dispatch'}));
    expect(await screen.findByText('No receipt was found. Keep the original reference and check again before continuing.')).toBeVisible();
    expect(mock.request).toHaveBeenCalledWith(`operations/requests/${key}`);
    expect(screen.queryByRole('button', {name: 'Review queued batch'})).not.toBeInTheDocument();
  });
});
