import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { UserCreatePage } from '../../src/features/core';
import { retainPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actor = '11111111-1111-4111-8111-111111111111', key = '22222222-2222-4222-8222-222222222222', requestId = '33333333-3333-4333-8333-333333333333', personId = '44444444-4444-4444-8444-444444444444';
const identity: PendingIdentity = {id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions: ['users.read', 'users.manage', 'overview.read'], expiresAt: '2100-01-01T00:00:00.000Z'};
const access: Omit<FeatureAccess, 'request'> = {actorId: actor, principalId: null, role: 'admin', authorityKey: 'session-1', permissions: identity.permissions, financialModel: 'transaction_journals', navigate: vi.fn()};
const app = {display_name: 'Recorded Person', member_type: 'app', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '0009', email: 'person@example.test', phone_e164: null, status: 'invited', reason: 'Record verified form details'};
const receipt = {request_id: requestId, resource_type: 'users', resource_id: personId, version: 1, status: 'succeeded'}, originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('legacy person creation page', () => {
  it('is routed for the legacy model but defaults to disabled', async () => {
    const request = vi.fn(); render(<UserCreatePage {...access} request={request} identity={identity} verifyFresh={async () => false} />);
    expect(await screen.findByText('Person creation is not enabled for this workspace.')).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review person'})).not.toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('requires review and confirmation and validates the actor-scoped receipt', async () => {
    const user = userEvent.setup(), request = vi.fn(async (path: string, options?: {method?: string; body?: Record<string, unknown>; idempotencyKey?: string}) => {
      if (options?.method === 'POST') {expect(path).toBe('operations/users'); expect(options.body).toEqual(app); return receipt;}
      return {status: 'succeeded', request_id: requestId, receipt};
    });
    render(<UserCreatePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => false} />);
    await user.type(await screen.findByLabelText('Recorded full name'), app.display_name);
    await user.selectOptions(screen.getByLabelText('MoMo provider'), app.momo_provider);
    await user.type(screen.getByLabelText('MoMo number'), app.momo_number);
    await user.type(screen.getByLabelText('MoMo code (optional)'), app.momo_pay_code);
    await user.type(screen.getByLabelText('Email'), app.email);
    await user.type(screen.getByLabelText('Reason for creation'), app.reason);
    await user.click(screen.getByRole('button', {name: 'Review person'}));
    expect(screen.getByRole('button', {name: 'Confirm person'})).toBeDisabled(); expect(request).not.toHaveBeenCalled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person details and reason.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm person'}));
    const success = await screen.findByRole('status'); expect(within(success).getByText('The person was recorded.')).toBeVisible();
    expect(request).toHaveBeenCalledTimes(2); expect(String(request.mock.calls[1][0])).toMatch(/^operations\/requests\//);
    await user.click(within(success).getByRole('button', {name: 'View person'})); expect(access.navigate).toHaveBeenCalledWith(`/admin/users/${personId}`);
  });
  it('shows and checks a legacy Flutter request while creation is disabled without fabricating a retry', async () => {
    const user = userEvent.setup(); await retainPending(identity, 'operating-createuser', 'new', key, 'users.manage', app);
    const request = vi.fn().mockResolvedValue({status: 'not_found'});
    render(<UserCreatePage {...access} request={request} identity={identity} verifyFresh={async () => false} />);
    expect(await screen.findByText(key)).toBeVisible();
    await user.click(screen.getByRole('button', {name: 'Check request'}));
    expect(await screen.findByText(/original model or intent cannot be verified/)).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review same request'})).not.toBeInTheDocument(); expect(request).toHaveBeenCalledOnce();
  });
  it('retries an unresolved React request only after checking, reviewing and confirming the original key', async () => {
    const user = userEvent.setup(); let submittedKey = '', writes = 0;
    const request = vi.fn(async (_path: string, options?: {method?: string; body?: Record<string, unknown>; idempotencyKey?: string}) => {
      if (options?.method === 'POST') {
        writes++; if (!submittedKey) {submittedKey = options.idempotencyKey!; throw new Error('lost');}
        expect(options.idempotencyKey).toBe(submittedKey); expect(options.body).toEqual(app); return receipt;
      }
      return writes === 1 ? {status: 'not_found'} : {status: 'succeeded', request_id: requestId, receipt};
    });
    render(<UserCreatePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => false} />);
    await user.type(await screen.findByLabelText('Recorded full name'), app.display_name);
    await user.selectOptions(screen.getByLabelText('MoMo provider'), app.momo_provider);
    await user.type(screen.getByLabelText('MoMo number'), app.momo_number);
    await user.type(screen.getByLabelText('MoMo code (optional)'), app.momo_pay_code);
    await user.type(screen.getByLabelText('Email'), app.email);
    await user.type(screen.getByLabelText('Reason for creation'), app.reason);
    await user.click(screen.getByRole('button', {name: 'Review person'}));
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person details and reason.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm person'}));
    expect(await screen.findByText(/result is unconfirmed/)).toBeVisible(); expect(writes).toBe(1);
    await waitFor(() => expect(screen.getByRole('button', {name: 'Check request'})).toBeEnabled());
    await user.click(screen.getByRole('button', {name: 'Check request'}));
    await user.click(await screen.findByRole('button', {name: 'Review same request'}));
    expect(screen.getByText(/may create this person if the earlier request did not commit/)).toBeVisible();
    expect(screen.getByRole('button', {name: 'Confirm same request'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person details and reason.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm same request'}));
    expect(await screen.findByText('The person was recorded.')).toBeVisible(); expect(writes).toBe(2);
  });
  it('enforces Direct member MoMo requirements and preserves optional email as contact', async () => {
    const user = userEvent.setup(), request = vi.fn();
    render(<UserCreatePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => false} />);
    await user.type(await screen.findByLabelText('Recorded full name'), 'Direct Member');
    await user.selectOptions(screen.getByLabelText('Member type'), 'direct');
    expect(screen.queryByLabelText('WhatsApp login number')).not.toBeInTheDocument();
    await user.type(screen.getByLabelText('Email'), 'direct@example.test');
    await user.type(screen.getByLabelText('Reason for creation'), 'Record direct member details');
    await user.click(screen.getByRole('button', {name: 'Review person'}));
    expect(screen.getByRole('alert')).toHaveTextContent('Direct members need a recorded MoMo number');
    await user.type(screen.getByLabelText('MoMo number'), '0788123456');
    await user.click(screen.getByRole('button', {name: 'Review person'}));
    expect(screen.getByRole('heading', {name: 'Review person creation'})).toBeVisible();
    expect(screen.getByText('direct@example.test')).toBeVisible(); expect(request).not.toHaveBeenCalled();
  });
});
