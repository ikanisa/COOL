import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { retainPending } from '../../src/features/core/pendingAttempt';
import { parseGrantPage } from '../../src/features/operations/contracts';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {id: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.com', role: 'admin' as const, permissions: ['gateway.read', 'gateway.manage'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'transaction_journals' as const}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request})}));
import { ReceiverGrantActionPanel } from '../../src/features/operations/ReceiverGrantActionPanel';

const id = '11111111-1111-4111-8111-111111111111', actor = mock.user.id, device = '33333333-3333-4333-8333-333333333333', payee = '44444444-4444-4444-8444-444444444444', key = '55555555-5555-4555-8555-555555555555', operationId = '66666666-6666-4666-8666-666666666666';
const time = '2026-11-16T08:00:00.000Z';
const grant = {id, device_id: device, device_label: 'Receiver handset', installation_id: device, key_sha256: 'a'.repeat(64), payee_id: payee, payee_label: 'Payee', payee_network: 'mtn_momo', payee_momo_number_or_code: '123456', status: 'active', version: 1, created_by_admin_id: actor, created_at: time, revoked_by_admin_id: null, revoked_at: null, capture_authority: true, send_authority: false, financial_authority: false};
const parsed = parseGrantPage({rows: [grant], total: 1, limit: 25, offset: 0}, 0).rows[0];
const receipt = {request_id: operationId, resource_type: 'receiver_capture_grants', resource_id: id, version: 2, status: 'succeeded'};
const detail = {resource_type: 'receiver_capture_grants', resource: grant, current_actor_id: actor, can_manage: true, related: {captures: []}, related_total: 0, related_limit: 25, related_offset: 0};
const originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {mock.request.mockReset(); if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('Receiver capture revocation panel', () => {
  it('does not expose a write by default', async () => {
    render(<ReceiverGrantActionPanel grant={parsed} canManage onUpdated={() => {}} />);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(screen.queryByRole('button', {name: 'Review revocation'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('requires a reason, review and confirmation when enabled', async () => {
    const user = userEvent.setup(), updated = vi.fn();
    mock.request.mockResolvedValue(receipt);
    render(<ReceiverGrantActionPanel grant={parsed} canManage enabled onUpdated={updated} />);
    await user.type(await screen.findByLabelText('Capture access review reason'), 'Review capture access');
    await user.click(screen.getByRole('button', {name: 'Review revocation'}));
    expect(screen.getByRole('button', {name: 'Confirm revocation'})).toBeDisabled();
    expect(mock.request).not.toHaveBeenCalled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the grant and reason.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm revocation'}));
    expect(await screen.findByText(`Capture change saved. Request ${operationId}.`)).toBeVisible();
    expect(mock.request).toHaveBeenCalledTimes(1);
    expect(updated).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('button', {name: 'Review revocation'})).not.toBeInTheDocument();
  });
  it('checks an existing request and requires a second review before an identical retry', async () => {
    const user = userEvent.setup();
    await retainPending(mock.user, 'receiver-capture-grant', id, key, 'gateway.manage', {expected_version: 1, reason: 'Review capture access'});
    mock.request.mockResolvedValueOnce({found: false}).mockResolvedValueOnce({found: false}).mockResolvedValueOnce(detail).mockResolvedValueOnce(receipt);
    render(<ReceiverGrantActionPanel grant={parsed} canManage enabled onUpdated={() => {}} />);
    await user.click(await screen.findByRole('button', {name: 'Check original receipt'}));
    await user.click(await screen.findByRole('button', {name: 'Review identical retry'}));
    expect(screen.getByText('Reason: Review capture access')).toBeVisible();
    expect(screen.getByRole('button', {name: 'Confirm identical retry'})).toBeDisabled();
    expect(mock.request).toHaveBeenCalledTimes(1);
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the grant and reason.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm identical retry'}));
    expect(await screen.findByText(`Capture change saved. Request ${operationId}.`)).toBeVisible();
    expect(mock.request).toHaveBeenLastCalledWith(`gateway/receiver-grants/${id}/revoke`, {method: 'POST', body: {expected_version: 1, reason: 'Review capture access'}, idempotencyKey: key});
  });
});
