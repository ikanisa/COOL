import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GroupCreatePage } from '../../src/features/core/GroupCreatePage';
import { GroupEditPage } from '../../src/features/core/GroupEditPage';
import { retainPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actor = '11111111-1111-4111-8111-111111111111', key = '22222222-2222-4222-8222-222222222222', requestId = '33333333-3333-4333-8333-333333333333', groupId = '44444444-4444-4444-8444-444444444444', ownerId = '55555555-5555-4555-8555-555555555555';
const identity: PendingIdentity = {id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions: ['collections.create', 'collections.manage', 'collections.read', 'users.read', 'overview.read'], expiresAt: '2100-01-01T00:00:00.000Z'};
const access: Omit<FeatureAccess, 'request'> = {actorId: actor, principalId: null, role: 'admin', authorityKey: 'session-1', permissions: identity.permissions, financialModel: 'transaction_journals', navigate: vi.fn()};
const ownerRow = {id: ownerId, public_id: '123456', display_name: 'Recorded owner', member_type: 'app', momo_number: '0788123456', version: 2, label: 'Recorded owner · 123456 · 0788123456'};
const ownerDetail = {resource_type: 'users', current_actor_id: actor, can_manage: false, resource: {...ownerRow, collect_user_id: ownerId, status: 'active', display_name_recorded: true}};
const groupDetail = {resource_type: 'groups', current_actor_id: actor, can_manage: true, resource: {id: groupId, slug: 'test-group', title: 'Test group', collection_type: 'ikimina', description: '', category_subtype: null, purpose_label: null, recurring_cadence: null, suggested_amount_rwf: null, status: 'draft', visibility: 'private', is_platform_sponsored: 0, country_code: 'RW', currency: 'RWF', version: 1}};
const base = {title: 'Test group', collection_type: 'ikimina', description: '', category_subtype: null, purpose_label: null, recurring_cadence: null, suggested_amount_rwf: null, reason: 'Review group details'};
const active = {...base, slug: 'test-group', visibility: 'private', is_platform_sponsored: false, status: 'active', owner_user_id: ownerId, receiver: {label: 'Recorded receiver', network: 'mtn_momo', momo_number_or_code: '008000'}};
const edit = {...base, title: 'Updated group', expected_version: 1};
const createReceipt = {request_id: requestId, resource_type: 'groups', resource_id: groupId, version: 1, status: 'succeeded'}, editReceipt = {...createReceipt, version: 2};
const originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('legacy group pages', () => {
  it('routes legacy creation and editing while keeping the write gate closed by default', async () => {
    const request = vi.fn(); const page = render(<GroupCreatePage {...access} request={request} identity={identity} verifyFresh={async () => false} />);
    expect(await screen.findByText('Group changes are not enabled for this workspace.')).toBeVisible(); expect(screen.queryByRole('button', {name: 'Review group'})).not.toBeInTheDocument();
    page.rerender(<GroupEditPage {...access} id={groupId} request={request} identity={identity} verifyFresh={async () => false} />);
    expect(await screen.findByText('Group changes are not enabled for this workspace.')).toBeVisible(); expect(request).not.toHaveBeenCalled();
  });
  it('allows staff to review active private creation only with a selected owner and receiver', async () => {
    const user = userEvent.setup(), staff = {...identity, role: 'staff' as const}, request = vi.fn(async (path: string, options?: {method?: string; body?: unknown}) => {
      if (path.startsWith('operations/lookups?')) return {rows: [ownerRow]}; if (path === `operations/users/${ownerId}`) return ownerDetail;
      if (options?.method === 'POST') {expect(options.body).toEqual(active); return createReceipt;} return {status: 'succeeded', request_id: requestId, receipt: createReceipt};
    });
    render(<GroupCreatePage {...access} role="staff" identity={staff} request={request} allowMutations verifyFresh={async () => false} />);
    await user.type(await screen.findByLabelText('Group name'), 'Test group'); await user.type(screen.getByLabelText('Group slug'), 'test-group');
    await user.selectOptions(screen.getByLabelText('Group status'), 'active'); await user.type(screen.getByLabelText('Reason for creation'), base.reason);
    await user.click(screen.getByRole('button', {name: 'Review group'})); expect(screen.getByRole('alert')).toHaveTextContent('active group needs');
    await user.type(screen.getByLabelText('Search group owner'), 'Recorded'); await user.click(screen.getByRole('button', {name: 'Search owners'}));
    await user.selectOptions(await screen.findByLabelText('Group owner'), ownerId);
    await user.click(screen.getByRole('checkbox', {name: 'Record a receiver'}));
    await user.type(screen.getByLabelText('Receiver name on MoMo'), 'Recorded receiver'); await user.type(screen.getByLabelText('Receiver MoMo number or code'), '008000');
    await user.click(screen.getByRole('button', {name: 'Review group'})); expect(screen.getByText('Current owner: Recorded owner · 123456')).toBeVisible();
    expect(screen.getByRole('button', {name: 'Confirm group'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the group details and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm group'}));
    expect(await screen.findByText('The group was recorded.')).toBeVisible(); expect(request).toHaveBeenCalledTimes(4);
  });
  it('edits metadata using the current version without changing status or visibility', async () => {
    const user = userEvent.setup(), request = vi.fn(async (path: string, options?: {method?: string; body?: unknown}) => {
      if (options?.method === 'PATCH') {expect(options.body).toEqual(edit); return editReceipt;} return path.startsWith('operations/requests/') ? {status: 'succeeded', request_id: requestId, receipt: editReceipt} : groupDetail;
    });
    render(<GroupEditPage {...access} id={groupId} identity={identity} request={request} allowMutations verifyFresh={async () => false} />);
    const title = await screen.findByLabelText('Group name'); await user.clear(title); await user.type(title, 'Updated group');
    await user.type(screen.getByLabelText('Reason for change'), base.reason); await user.click(screen.getByRole('button', {name: 'Review group'}));
    expect(screen.getByText('Current group: Test group · version 1 · draft.')).toBeVisible();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the group details and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm group'}));
    const result = await screen.findByRole('status'); expect(within(result).getByText('Group changes were recorded.')).toBeVisible(); expect(request).toHaveBeenCalledTimes(4);
  });
  it('offers only a status check for an older unbound Flutter request', async () => {
    const user = userEvent.setup(); await retainPending(identity, 'operating-creategroup', 'new', key, 'collections.create', active);
    const request = vi.fn().mockResolvedValue({status: 'not_found'});
    render(<GroupCreatePage {...access} identity={identity} request={request} verifyFresh={async () => false} />);
    expect(await screen.findByText(key)).toBeVisible(); await user.click(screen.getByRole('button', {name: 'Check request'}));
    expect(await screen.findByText(/original model or intent cannot be verified/)).toBeVisible(); expect(screen.queryByRole('button', {name: 'Review same request'})).not.toBeInTheDocument(); expect(request).toHaveBeenCalledOnce();
  });
  it('retries an uncertain private draft only after an original-key check and confirmation', async () => {
    const user = userEvent.setup(), draft = {...base, slug: 'test-group', visibility: 'private', is_platform_sponsored: false, status: 'draft'}; let submittedKey = '', writes = 0;
    let holdRecovery = false, releaseRecovery: (() => void) | undefined;
    Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => {
      if (holdRecovery) {holdRecovery = false; await new Promise<void>(resolve => {releaseRecovery = resolve;});}
      return work({name});
    }}});
    const request = vi.fn(async (_path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'POST') {writes++; if (!submittedKey) {submittedKey = options.idempotencyKey!; holdRecovery = true; throw new Error('lost');} expect(options.idempotencyKey).toBe(submittedKey); expect(options.body).toEqual(draft); return createReceipt;}
      return writes === 1 ? {status: 'not_found'} : {status: 'succeeded', request_id: requestId, receipt: createReceipt};
    });
    render(<GroupCreatePage {...access} identity={identity} request={request} allowMutations verifyFresh={async () => false} />);
    await user.type(await screen.findByLabelText('Group name'), 'Test group'); await user.type(screen.getByLabelText('Group slug'), 'test-group');
    await user.type(screen.getByLabelText('Reason for creation'), base.reason); await user.click(screen.getByRole('button', {name: 'Review group'}));
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the group details and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm group'}));
    expect(await screen.findByText(/result is unconfirmed/)).toBeVisible(); expect(writes).toBe(1);
    expect(screen.getByRole('button', {name: 'Check request'})).toBeDisabled();
    await waitFor(() => expect(releaseRecovery).toBeDefined()); releaseRecovery?.();
    await waitFor(() => expect(screen.getByRole('button', {name: 'Check request'})).toBeEnabled());
    await user.click(screen.getByRole('button', {name: 'Check request'})); await user.click(await screen.findByRole('button', {name: 'Review same request'}));
    expect(screen.getByText(/may make this change if the earlier request did not commit/)).toBeVisible(); expect(screen.getByRole('button', {name: 'Confirm same request'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the group details and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm same request'}));
    expect(await screen.findByText('The group was recorded.')).toBeVisible(); expect(writes).toBe(2);
  });
});
