import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { UserEditPage } from '../../src/features/core/UserEditPage';
import { retainPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actor = '11111111-1111-4111-8111-111111111111', key = '22222222-2222-4222-8222-222222222222', requestId = '33333333-3333-4333-8333-333333333333', userId = '44444444-4444-4444-8444-444444444444';
const identity: PendingIdentity = {id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions: ['users.read', 'users.manage', 'overview.read'], expiresAt: '2100-01-01T00:00:00.000Z'};
const access: Omit<FeatureAccess, 'request'> = {actorId: actor, principalId: null, role: 'admin', authorityKey: 'session-1', permissions: identity.permissions, financialModel: 'transaction_journals', navigate: vi.fn()};
const detail = {resource_type: 'users', current_actor_id: actor, can_manage: true, resource: {id: userId, collect_user_id: userId, public_id: '123456', display_name: 'Recorded Person', display_name_recorded: true, member_type: 'app', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '0009', email: 'person@example.test', phone_e164: '+250788123456', status: 'active', operator_admin_id: null, version: 1}};
const intent = {display_name: 'Updated Person', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '0009', expected_version: 1, reason: 'Review recorded profile'};
const receipt = {request_id: requestId, resource_type: 'users', resource_id: userId, version: 2, status: 'succeeded'}, originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('legacy person profile editing page', () => {
  it('routes legacy editing but keeps the write gate closed by default', async () => {
    const request = vi.fn(); render(<UserEditPage {...access} id={userId} request={request} identity={identity} verifyFresh={async () => false} />);
    expect(await screen.findByText('Person editing is not enabled for this workspace.')).toBeVisible(); expect(screen.queryByRole('button', {name: 'Review person changes'})).not.toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('requires a current person, review and confirmation and changes only profile fields', async () => {
    const user = userEvent.setup(), request = vi.fn(async (path: string, options?: {method?: string; body?: unknown}) => {
      if (options?.method === 'PATCH') {expect(options.body).toEqual(intent); return receipt;} return path.startsWith('operations/requests/') ? {status: 'succeeded', request_id: requestId, receipt} : detail;
    });
    render(<UserEditPage {...access} id={userId} request={request} identity={identity} allowMutations verifyFresh={async () => false} />);
    const name = await screen.findByLabelText('Recorded full name'); await user.clear(name); await user.type(name, intent.display_name);
    await user.type(screen.getByLabelText('Reason for change'), intent.reason);
    expect(screen.queryByLabelText('Account status')).not.toBeInTheDocument(); expect(screen.queryByLabelText('Email')).not.toBeInTheDocument();
    expect(screen.getByText(/Changing the MoMo number can change receipt attribution/)).toBeVisible();
    await user.click(screen.getByRole('button', {name: 'Review person changes'})); expect(screen.getByRole('button', {name: 'Confirm person changes'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person details and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm person changes'}));
    const result = await screen.findByRole('status'); expect(within(result).getByText('The person was updated.')).toBeVisible(); expect(request).toHaveBeenCalledTimes(4);
  });
  it('checks an older unbound Flutter request while writes are disabled without offering retry', async () => {
    const user = userEvent.setup(); await retainPending(identity, 'operating-updateuser', userId, key, 'users.manage', {...intent, status: 'suspended'});
    const request = vi.fn().mockResolvedValue({status: 'not_found'});
    render(<UserEditPage {...access} id={userId} request={request} identity={identity} verifyFresh={async () => false} />);
    expect(await screen.findByText(key)).toBeVisible(); await user.click(screen.getByRole('button', {name: 'Check request'}));
    expect(await screen.findByText(/original model or intent cannot be verified/)).toBeVisible(); expect(screen.queryByRole('button', {name: 'Review same request'})).not.toBeInTheDocument(); expect(request).toHaveBeenCalledOnce();
  });
  it('requires original-key check and explicit confirmation for a React-retained retry', async () => {
    const user = userEvent.setup(); let submittedKey = '', writes = 0;
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'PATCH') {writes++; if (!submittedKey) {submittedKey = options.idempotencyKey!; throw new Error('lost');} expect(options.idempotencyKey).toBe(submittedKey); expect(options.body).toEqual(intent); return receipt;}
      if (path.startsWith('operations/requests/')) return writes === 1 ? {status: 'not_found'} : {status: 'succeeded', request_id: requestId, receipt}; return detail;
    });
    render(<UserEditPage {...access} id={userId} request={request} identity={identity} allowMutations verifyFresh={async () => false} />);
    const name = await screen.findByLabelText('Recorded full name'); await user.clear(name); await user.type(name, intent.display_name); await user.type(screen.getByLabelText('Reason for change'), intent.reason);
    await user.click(screen.getByRole('button', {name: 'Review person changes'})); await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person details and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm person changes'}));
    expect(await screen.findByText(/result is unconfirmed/)).toBeVisible(); expect(writes).toBe(1);
    await waitFor(() => expect(screen.getByRole('button', {name: 'Check request'})).toBeEnabled());
    await user.click(screen.getByRole('button', {name: 'Check request'})); await user.click(await screen.findByRole('button', {name: 'Review same request'}));
    expect(screen.getByText(/may make this change if the earlier request did not commit/)).toBeVisible(); expect(screen.getByRole('button', {name: 'Confirm same request'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person details and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm same request'}));
    expect(await screen.findByText('The person was updated.')).toBeVisible(); expect(writes).toBe(2);
  });
});
