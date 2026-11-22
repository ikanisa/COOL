import { act, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, MemoryRouter, Route, RouterProvider, Routes } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { retainPending } from '../../src/features/core/pendingAttempt';
import { withPendingFence } from '../../src/features/operations/pendingFence';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {id: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.com', role: 'admin' as 'owner' | 'admin' | 'staff', permissions: ['ledger.read', 'ledger.manage', 'overview.read'] as string[], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'transaction_journals' as 'transaction_journals' | 'canonical_evidence_ledger'}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request})}));
import { LedgerAccountDetailPage, LedgerAccountEditPage } from '../../src/features/ledger-accounts/LedgerAccountPages';

const id = '11111111-1111-4111-8111-111111111111', actor = mock.user.id, group = '33333333-3333-4333-8333-333333333333', key = '44444444-4444-4444-8444-444444444444', operation = '55555555-5555-4555-8555-555555555555';
const account = {id, group_id: group, code: '1000', name: 'Recorded funds', account_type: 'asset', normal_side: 'debit', currency: 'RWF', status: 'active', created_by_admin_id: actor, created_at: 1794816000, version: 1};
const detail = {resource_type: 'accounts', resource: account, current_actor_id: actor, can_manage: true, related: {}, related_pages: {}, related_truncated: false};
const receipt = {request_id: operation, resource_type: 'accounts', resource_id: id, version: 2, status: 'succeeded'};
const originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
function mount(edit: boolean, allow = false) {return render(<MemoryRouter initialEntries={[`/admin/ledger-accounts/${id}${edit ? '/edit' : ''}`]}><Routes><Route path="/admin/ledger-accounts/:id" element={<LedgerAccountDetailPage allowMutations={allow} />} /><Route path="/admin/ledger-accounts/:id/edit" element={<LedgerAccountEditPage allowMutations={allow} />} /></Routes></MemoryRouter>);}
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {mock.request.mockReset(); mock.user.role = 'admin'; mock.user.permissions = ['ledger.read', 'ledger.manage', 'overview.read']; mock.user.financialModel = 'transaction_journals'; if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('Ledger account pages', () => {
  it('shows exact legacy account facts and an authorized recovery link', async () => {
    mock.request.mockResolvedValue(detail); mount(false);
    expect(await screen.findByText('1000 · Recorded funds')).toBeVisible();
    expect(screen.getByText('asset')).toBeVisible();
    expect(screen.getByText('debit')).toBeVisible();
    expect(screen.getByRole('link', {name: 'Check ledger account change request'})).toHaveAttribute('href', `/admin/ledger-accounts/${id}/edit`);
    expect(mock.request).toHaveBeenCalledWith(`operations/accounts/${id}`, expect.objectContaining({signal: expect.any(AbortSignal)}));
  });
  it('does not treat the canonical evidence ledger as a chart-of-accounts endpoint', () => {
    mock.user.financialModel = 'canonical_evidence_ledger'; mount(false);
    expect(screen.getByText('This workspace does not expose ledger accounts through this route.')).toBeVisible();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('keeps edits disabled by default and checks an existing request', async () => {
    const user = userEvent.setup();
    await retainPending(mock.user, 'operating-updateaccount', id, key, 'ledger.manage', {name: 'Updated funds', status: 'closed', expected_version: 1, reason: 'Review account change'});
    mock.request.mockResolvedValueOnce(detail).mockResolvedValueOnce({status: 'not_found'});
    mount(true);
    await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    expect(await screen.findByText('No receipt was found. Keep the original reference and check again before continuing.')).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review account change'})).not.toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Review identical retry'})).not.toBeInTheDocument();
    expect(mock.request).toHaveBeenLastCalledWith(`operations/requests/${key}`);
  });
  it('requires change review and confirmation before the versioned PATCH', async () => {
    const user = userEvent.setup();
    mock.request.mockImplementation(async (_path: string, options?: {method?: string}) => options?.method === 'PATCH' ? receipt : detail);
    mount(true, true);
    const name = await screen.findByLabelText('Account name'); await user.clear(name); await user.type(name, 'Updated funds');
    await user.selectOptions(screen.getByLabelText('Account status'), 'closed');
    await user.type(screen.getByLabelText('Reason for account change'), 'Review account change');
    await user.click(screen.getByRole('button', {name: 'Review account change'}));
    const dialog = await screen.findByRole('dialog', {name: 'Review account change'});
    expect(within(dialog).getByText('Updated funds')).toBeVisible();
    expect(within(dialog).getByRole('button', {name: 'Confirm account change'})).toBeDisabled();
    expect(mock.request).toHaveBeenCalledTimes(1);
    await user.click(within(dialog).getByRole('checkbox', {name: 'I reviewed the account, version and change.'}));
    await user.click(within(dialog).getByRole('button', {name: 'Confirm account change'}));
    expect(await screen.findByText(`Account change recorded. Request ${operation}.`)).toBeVisible();
    expect(mock.request).toHaveBeenCalledTimes(3);
    expect(mock.request).toHaveBeenLastCalledWith(`operations/accounts/${id}`, expect.objectContaining({method: 'PATCH', body: {name: 'Updated funds', status: 'closed', expected_version: 1, reason: 'Review account change'}}));
    expect(screen.queryByRole('button', {name: 'Review account change'})).not.toBeInTheDocument();
  });
  it('requires review before explicitly retrying the identical original change', async () => {
    const user = userEvent.setup();
    const intent = {name: 'Updated funds', status: 'closed', expected_version: 1, reason: 'Review account change'};
    await retainPending(mock.user, 'operating-updateaccount', id, key, 'ledger.manage', intent);
    mock.request.mockResolvedValueOnce(detail).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(detail).mockResolvedValueOnce(receipt);
    mount(true, true);
    await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    await user.click(await screen.findByRole('button', {name: 'Review identical retry'}));
    const dialog = screen.getByRole('dialog', {name: 'Review identical account retry'});
    expect(within(dialog).getByRole('button', {name: 'Confirm identical retry'})).toBeDisabled();
    expect(mock.request).toHaveBeenCalledTimes(2);
    await user.click(within(dialog).getByRole('checkbox', {name: 'I reviewed the account, version and change.'}));
    await user.click(within(dialog).getByRole('button', {name: 'Confirm identical retry'}));
    expect(await screen.findByText(`Account change recorded. Request ${operation}.`)).toBeVisible();
    expect(mock.request).toHaveBeenLastCalledWith(`operations/accounts/${id}`, {method: 'PATCH', body: intent, idempotencyKey: key});
  });
  it('does not submit a confirmation made stale by another tab', async () => {
    const user = userEvent.setup(); mock.request.mockResolvedValue(detail); mount(true, true);
    const name = await screen.findByLabelText('Account name'); await user.clear(name); await user.type(name, 'Updated funds');
    await user.type(screen.getByLabelText('Reason for account change'), 'Review account change');
    await user.click(screen.getByRole('button', {name: 'Review account change'}));
    const dialog = screen.getByRole('dialog', {name: 'Review account change'});
    await withPendingFence({identity: mock.user, family: 'operating-updateaccount', resourceId: id, isCurrent: () => true}, async (access) => {access.reserve(key, access.read().revision); access.clear(key);});
    await user.click(within(dialog).getByRole('checkbox', {name: 'I reviewed the account, version and change.'}));
    await user.click(within(dialog).getByRole('button', {name: 'Confirm account change'}));
    expect(await screen.findByText('The request could not be started safely. Check the original request and current account before reviewing again.')).toBeVisible();
    expect(mock.request.mock.calls.every(([, options]) => !options || options.method !== 'PATCH')).toBe(true);
  });
  it('closes an open review when navigating to a different ledger account', async () => {
    const user = userEvent.setup();
    const otherId = '66666666-6666-4666-8666-666666666666';
    const otherAccount = {...account, id: otherId, name: 'Second account'};
    const router = createMemoryRouter([
      {path: '/admin/ledger-accounts/:id/edit', element: <LedgerAccountEditPage allowMutations />},
    ], {initialEntries: [`/admin/ledger-accounts/${id}/edit`]});
    mock.request.mockImplementation(async (path: string) => path === `operations/accounts/${otherId}` ? {...detail, resource: otherAccount} : detail);
    render(<RouterProvider router={router} />);

    const name = await screen.findByLabelText('Account name');
    await user.clear(name);
    await user.type(name, 'Edited first account');
    await user.type(screen.getByLabelText('Reason for account change'), 'Review first account change');
    await user.click(screen.getByRole('button', {name: 'Review account change'}));
    expect(await screen.findByRole('dialog', {name: 'Review account change'})).toBeVisible();

    await act(() => router.navigate(`/admin/ledger-accounts/${otherId}/edit`));
    expect(await screen.findByLabelText('Account name')).toHaveValue('Second account');
    expect(screen.getByLabelText('Reason for account change')).toHaveValue('');
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(mock.request.mock.calls).toHaveLength(2);
    expect(mock.request.mock.calls.every(([, options]) => options.method !== 'PATCH')).toBe(true);
  });
  it('hides recovery from staff or accounts missing manage permission', async () => {
    mock.request.mockResolvedValue({...detail, can_manage: false}); mock.user.role = 'staff'; mock.user.permissions = ['ledger.read'];
    mount(false);
    expect(await screen.findByText('1000 · Recorded funds')).toBeVisible();
    expect(screen.queryByRole('link', {name: 'Check ledger account change request'})).not.toBeInTheDocument();
  });
});
