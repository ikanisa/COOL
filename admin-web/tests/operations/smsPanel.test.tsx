import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { SmsReceipt } from '../../src/features/operations/contracts';
import { retainPending } from '../../src/features/core';
import { withPendingFence } from '../../src/features/operations/pendingFence';

const mock = vi.hoisted(() => ({
  request: vi.fn(),
  user: {id: '22222222-2222-2222-2222-222222222222', sessionId: 'session-1', email: 'operator@example.com', role: 'admin' as const,
    permissions: ['sms.read', 'sms.extract', 'sms.reveal'], expiresAt: new Date(Date.now() + 3600000).toISOString()},
}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request})}));
import { SmsActionPanel } from '../../src/features/operations/SmsActionPanel';

const id = '11111111-1111-1111-1111-111111111111';
const key = '33333333-3333-4333-8333-333333333333';
const hash = 'a'.repeat(64);
const source = {source_kind: 'capture', id, source_sha256: hash, evidence_level: 'client_received'} as SmsReceipt;
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

describe('SMS source action panel', () => {
  it('does not offer unqualified actions by default', async () => {
    render(<SmsActionPanel source={source} extractionAvailable onUpdated={() => {}} />);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(screen.queryByRole('button', {name: 'Review extraction'})).not.toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Review source access'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });

  it('requires explicit review and confirmation before an enabled extraction', async () => {
    const user = userEvent.setup();
    const onUpdated = vi.fn();
    mock.request.mockResolvedValue({request_id: '44444444-4444-4444-8444-444444444444', status: 'succeeded', resource_type: 'sms_facts', resource_id: '55555555-5555-4555-8555-555555555555', source_kind: 'capture', source_id: id, parser_version: 'collect-admin-source-facts-v1'});
    render(<SmsActionPanel source={source} enabled extractionAvailable onUpdated={onUpdated} />);
    await user.type(await screen.findByLabelText('Reason for extraction'), 'Review source evidence');
    await user.click(screen.getByRole('button', {name: 'Review extraction'}));
    const confirm = screen.getByRole('button', {name: 'Confirm extraction'});
    expect(confirm).toBeDisabled();
    expect(mock.request).not.toHaveBeenCalled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the source digest and reason.'}));
    await user.click(confirm);
    expect(await screen.findByText('Extraction recorded. Payment and settlement are not asserted.')).toBeVisible();
    expect(mock.request).toHaveBeenCalledTimes(1);
    expect(onUpdated).toHaveBeenCalledTimes(1);
  });

  it('does not dispatch a confirmation made stale by another tab', async () => {
    const user = userEvent.setup();
    render(<SmsActionPanel source={source} enabled extractionAvailable onUpdated={() => {}} />);
    await user.type(await screen.findByLabelText('Reason for extraction'), 'Review source evidence');
    await user.click(screen.getByRole('button', {name: 'Review extraction'}));
    await withPendingFence({identity: mock.user, family: 'sms-extraction', resourceId: `capture:${id}`, isCurrent: () => true}, async (access) => {
      access.reserve(key, access.read().revision); access.clear(key);
    });
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the source digest and reason.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm extraction'}));
    expect(await screen.findByText('The workspace changed or recovery is unavailable. Check the current request and review again.')).toBeVisible();
    expect(mock.request).not.toHaveBeenCalled();
    expect(await screen.findByRole('button', {name: 'Review extraction'})).toBeVisible();
  });
  it('permits checking an existing original request while new actions remain disabled', async () => {
    const user = userEvent.setup();
    await retainPending(mock.user, 'sms-extraction', `capture:${id}`, key, 'sms.extract', {reason: 'Review source evidence', expected_source_sha256: hash});
    mock.request.mockResolvedValue({status: 'not_found'});
    render(<SmsActionPanel source={source} extractionAvailable onUpdated={() => {}} />);
    await user.click(await screen.findByRole('button', {name: 'Check request'}));
    expect(await screen.findByText('No receipt was found. Keep the original reference and check again before continuing.')).toBeVisible();
    expect(mock.request).toHaveBeenCalledWith(`sms/requests/${key}`);
    expect(screen.queryByRole('button', {name: 'Review extraction'})).not.toBeInTheDocument();
  });
});
