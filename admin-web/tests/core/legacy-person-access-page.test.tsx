import {act, render, screen, waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {LegacyPersonAccessPage} from '../../src/features/core/LegacyPersonAccessPage';
import type {PendingIdentity} from '../../src/features/core/pendingAttempt';

const actor = '11111111-1111-4111-8111-111111111111', userId = '44444444-4444-4444-8444-444444444444';
const operatorId = '55555555-5555-4555-8555-555555555555', requestId = '33333333-3333-4333-8333-333333333333';
const identity: PendingIdentity = {id: actor, sessionId: 'session-1', email: 'owner@example.test', role: 'owner', permissions: ['users.read', 'users.manage', 'overview.read', 'admin_users.manage'], expiresAt: '2100-01-01T00:00:00.000Z'};
const detail = {resource_type: 'users', current_actor_id: actor, can_manage: true, resource: {id: userId, collect_user_id: userId, public_id: '123456', display_name: 'Recorded Person', display_name_recorded: true, member_type: 'app', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: null, email: 'person@example.test', phone_e164: '+250788123456', status: 'active', operator_admin_id: null, version: 1}};
const receipt = {request_id: requestId, resource_type: 'users', resource_id: userId, version: 2, status: 'succeeded'};
const team = {currentEmail: identity.email, canManage: true, members: [{id: operatorId, email: 'staff@example.test', role: 'staff', status: 'active', publicId: '654321', displayName: 'Staff Member'}]};
const originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
const props = {id: userId, identity, actorId: actor, principalId: null, role: 'owner' as const, authorityKey: 'session-1', permissions: identity.permissions, financialModel: 'transaction_journals' as const, navigate: vi.fn()};
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('legacy person access page', () => {
  it('shows no editing controls and makes no requests by default', async () => {
    const request = vi.fn(); render(<LegacyPersonAccessPage {...props} request={request} />);
    expect(await screen.findByText('Person access changes are not enabled for this workspace.')).toBeVisible();
    expect(screen.queryByLabelText('Phone contact')).not.toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('calls the phone a contact, requires review and fresh verification, and writes the exact reviewed fields', async () => {
    const user = userEvent.setup(), verify = vi.fn().mockResolvedValue(true);
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown}) => {
      if (options?.method === 'PATCH') {expect(options.body).toEqual({phone_e164: '+250788123457', expected_version: 1, reason: 'Review recorded contact'}); return receipt;}
      return path.startsWith('operations/requests/') ? {status: 'succeeded', request_id: requestId, receipt} : detail;
    });
    render(<LegacyPersonAccessPage {...props} request={request} allowContacts verifyFresh={verify} />);
    const phone = await screen.findByLabelText('Phone contact');
    expect(screen.getByText(/sign-in on this service uses an email code/i)).toBeVisible();
    await user.clear(phone); await user.type(phone, '+250788123457'); await user.type(screen.getByLabelText('Reason for contact change'), 'Review recorded contact');
    await user.click(screen.getByRole('button', {name: 'Review contact change'}));
    expect(screen.getByRole('button', {name: 'Confirm change'})).toBeDisabled(); expect(verify).not.toHaveBeenCalled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person and this change.'})); await user.click(screen.getByRole('button', {name: 'Confirm change'}));
    expect(await screen.findByText('The person was updated.')).toBeVisible(); expect(verify).toHaveBeenCalledOnce();
  });
  it('keeps operator linking owner-only and prevents submission even when its candidate UI is requested', async () => {
    const user = userEvent.setup(), request = vi.fn(async (path: string, _options?: {method?: string}) => path === 'team' ? team : detail);
    render(<LegacyPersonAccessPage {...props} request={request} allowOperatorLinks verifyFresh={async () => true} />);
    const select = await screen.findByLabelText('Operator'); await user.selectOptions(select, operatorId);
    await user.type(screen.getByLabelText('Reason for operator link'), 'Review operator link'); await user.click(screen.getByRole('button', {name: 'Review operator link'}));
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person and this change.'}));
    expect(screen.getByRole('button', {name: 'Confirm change'})).toBeDisabled();
    expect(request.mock.calls.every(([, options]) => options?.method !== 'PATCH')).toBe(true);
    expect(request).toHaveBeenCalledTimes(2);
  });
  it('keeps login email and member-type changes hard-gated even if the candidate controls are requested', async () => {
    const user = userEvent.setup(), request = vi.fn(async (_path: string, _options?: {method?: string}) => detail);
    render(<LegacyPersonAccessPage {...props} request={request} allowLoginType verifyFresh={async () => true} />);
    const email = await screen.findByLabelText('Sign-in email'); await user.clear(email); await user.type(email, 'new@example.test');
    await user.type(screen.getByLabelText('Reason for email change'), 'Review sign-in email'); await user.click(screen.getByRole('button', {name: 'Review email change'}));
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person and this change.'})); expect(screen.getByRole('button', {name: 'Confirm change'})).toBeDisabled();
    await user.click(screen.getByRole('button', {name: 'Cancel'}));
    await user.type(screen.getByLabelText('Reason for sign-in change'), 'Review membership type'); await user.click(screen.getByRole('button', {name: 'Review sign-in change'}));
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person and this change.'})); expect(screen.getByRole('button', {name: 'Confirm change'})).toBeDisabled();
    expect(request.mock.calls.every(([, options]) => options?.method !== 'PATCH')).toBe(true);
  });
  it('does not show operator-link controls to a non-owner', async () => {
    const adminIdentity: PendingIdentity = {...identity, role: 'admin', permissions: identity.permissions.filter(p => p !== 'admin_users.manage')};
    const request = vi.fn(); render(<LegacyPersonAccessPage {...props} role="admin" identity={adminIdentity} permissions={adminIdentity.permissions} request={request} allowOperatorLinks />);
    expect(await screen.findByText('Person access changes are not enabled for this workspace.')).toBeVisible();
    expect(screen.queryByLabelText('Operator')).not.toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('recovers a lost contact result before allowing the exact original request to be retried', async () => {
    const user = userEvent.setup(); let writes = 0;
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown}) => {
      if (options?.method === 'PATCH') {writes++; if (writes === 1) throw new Error('lost'); return receipt;}
      return path.startsWith('operations/requests/') ? writes === 1 ? {status: 'not_found'} : {status: 'succeeded', request_id: requestId, receipt} : detail;
    });
    render(<LegacyPersonAccessPage {...props} request={request} allowContacts verifyFresh={async () => true} />);
    const phone = await screen.findByLabelText('Phone contact'); await user.clear(phone); await user.type(phone, '+250788123457');
    await user.type(screen.getByLabelText('Reason for contact change'), 'Review recorded contact'); await user.click(screen.getByRole('button', {name: 'Review contact change'}));
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person and this change.'})); await user.click(screen.getByRole('button', {name: 'Confirm change'}));
    const check = await screen.findByRole('button', {name: 'Check original request'});
    await waitFor(() => expect(check).toBeEnabled()); await user.click(check);
    expect(await screen.findByText(/original request was not found/i)).toBeVisible();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person and this change.'})); await user.click(screen.getByRole('button', {name: 'Confirm change'}));
    expect(await screen.findByText('The person was updated.')).toBeVisible(); expect(writes).toBe(2);
  });
  it('keeps recovery disabled while the original checkpoint is being restored', async () => {
    const user = userEvent.setup(); let holdRestore = false, releaseRestore!: () => void, markStarted!: () => void;
    const restoreStarted = new Promise<void>(resolve => {markStarted = resolve;});
    const restoreRelease = new Promise<void>(resolve => {releaseRestore = resolve;});
    Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => {
      if (holdRestore) {holdRestore = false; markStarted(); await restoreRelease;}
      return work({name});
    }}});
    const request = vi.fn(async (path: string, options?: {method?: string}) => {
      if (options?.method === 'PATCH') {holdRestore = true; throw new Error('lost');}
      return path.startsWith('operations/requests/') ? {status: 'not_found'} : detail;
    });
    render(<LegacyPersonAccessPage {...props} request={request} allowContacts verifyFresh={async () => true} />);
    const phone = await screen.findByLabelText('Phone contact'); await user.clear(phone); await user.type(phone, '+250788123457');
    await user.type(screen.getByLabelText('Reason for contact change'), 'Review recorded contact'); await user.click(screen.getByRole('button', {name: 'Review contact change'}));
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person and this change.'})); await user.click(screen.getByRole('button', {name: 'Confirm change'}));
    await restoreStarted;
    const check = await screen.findByRole('button', {name: 'Check original request'});
    expect(check).toBeDisabled(); await user.click(check);
    expect(request.mock.calls.some(([path]) => path.startsWith('operations/requests/'))).toBe(false);
    await act(async () => {releaseRestore();});
    await waitFor(() => expect(check).toBeEnabled()); await user.click(check);
    expect(await screen.findByText(/original request was not found/i)).toBeVisible();
  });
});
