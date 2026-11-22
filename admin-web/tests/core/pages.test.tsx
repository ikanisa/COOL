import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import fixture from './canonical-core-fixtures.json';
import relatedFixture from './group-detail-fixtures.json';
import reconciliationFixture from './canonical-reconciliation-fixture.json';
import { CoreListPage } from '../../src/features/core/CoreListPage';
import { CoreRecordPage } from '../../src/features/core/CoreRecordPage';
import type { FeatureAccess } from '../../src/features/core/types';
import { retainPending } from '../../src/features/core/pendingAttempt';

const base: Omit<FeatureAccess, 'request'> = {
  permissions: ['collections.read'], actorId: '11111111-1111-4111-8111-111111111111',
  principalId: null, authorityKey: 'session-a', role: 'admin', financialModel: 'canonical_evidence_ledger',
  navigate: vi.fn(),
};

describe('core list access and authority', () => {
  it('does not request records without the required permission', () => {
    const request = vi.fn();
    render(<CoreListPage {...base} request={request} permissions={[]} area="groups" />);
    expect(screen.getByRole('alert')).toHaveTextContent('permission');
    expect(request).not.toHaveBeenCalled();
  });

  it('displays server records and does not retain old actor data when authority changes', async () => {
    let resolveNext: ((value: Record<string, unknown>) => void) | undefined;
    const request = vi.fn().mockResolvedValueOnce(fixture.groups).mockImplementationOnce(() => new Promise(resolve => { resolveNext = resolve; }));
    const { rerender } = render(<CoreListPage {...base} request={request} area="groups" />);
    expect(await screen.findByText('Controlled collection')).toBeInTheDocument();
    rerender(<CoreListPage {...base} request={request} area="groups" authorityKey="session-b" />);
    expect(screen.queryByText('Controlled collection')).not.toBeInTheDocument();
    await waitFor(() => expect(resolveNext).toBeDefined());
    resolveNext?.({ ...fixture.groups, rows: [], total: 0 });
    expect(await screen.findByText('No records found')).toBeInTheDocument();
  });

  it('offers a truthful group recovery entry when creation is disabled', async () => {
    const navigate = vi.fn(), request = vi.fn().mockResolvedValue(fixture.groups);
    const { rerender } = render(<CoreListPage {...base} request={request} navigate={navigate} permissions={['collections.read', 'collections.create']} area="groups" />);
    fireEvent.click(screen.getByRole('button', { name: 'Check group creation request' }));
    expect(navigate).toHaveBeenCalledWith('/admin/groups/new');
    expect(screen.queryByRole('button', { name: 'Create group' })).not.toBeInTheDocument();
    rerender(<CoreListPage {...base} request={request} navigate={navigate} permissions={['collections.read', 'collections.create']} area="groups" allowMutations />);
    expect(screen.getByRole('button', { name: 'Create group' })).toBeInTheDocument();
    expect(await screen.findByText('Controlled collection')).toBeInTheDocument();
  });

  it('offers legacy journal-draft recovery when creation is disabled', () => {
    const navigate = vi.fn(), request = vi.fn(async () => ({}));
    render(<CoreListPage {...base} financialModel="transaction_journals" permissions={['ledger.read', 'ledger.manage']} request={request} navigate={navigate} area="ledgers" />);
    fireEvent.click(screen.getByRole('button', { name: 'Check journal draft request' }));
    expect(navigate).toHaveBeenCalledWith('/admin/ledgers/new');
    expect(screen.queryByRole('button', { name: 'Create journal draft' })).not.toBeInTheDocument();
  });

  it('offers legacy payment recovery only with the permissions needed by its screen', () => {
    const navigate = vi.fn(), request = vi.fn(async () => ({}));
    const permissions = ['payments.read', 'payments.manage', 'collections.read', 'receivers.read', 'overview.read'];
    const {rerender} = render(<CoreListPage {...base} financialModel="transaction_journals" permissions={permissions} request={request} navigate={navigate} area="transactions" />);
    fireEvent.click(screen.getByRole('button', {name: 'Check evidence request'}));
    expect(navigate).toHaveBeenCalledWith('/admin/transactions/new');
    expect(screen.queryByRole('button', {name: 'Record payment evidence'})).not.toBeInTheDocument();
    rerender(<CoreListPage {...base} financialModel="transaction_journals" permissions={permissions.filter(permission => permission !== 'receivers.read')} request={request} navigate={navigate} area="transactions" />);
    expect(screen.queryByRole('button', {name: 'Check evidence request'})).not.toBeInTheDocument();
  });

  it('offers legacy person-creation recovery while writes are disabled', () => {
    const navigate = vi.fn(), request = vi.fn(async () => ({}));
    render(<CoreListPage {...base} financialModel="transaction_journals" permissions={['users.read', 'users.manage', 'overview.read']} request={request} navigate={navigate} area="users" />);
    fireEvent.click(screen.getByRole('button', { name: 'Check person creation request' }));
    expect(navigate).toHaveBeenCalledWith('/admin/users/new');
    expect(screen.queryByRole('button', { name: 'Create person' })).not.toBeInTheDocument();
  });

  it('offers legacy group creation recovery to staff while writes are disabled', () => {
    const navigate = vi.fn(), request = vi.fn(async () => ({}));
    render(<CoreListPage {...base} role="staff" financialModel="transaction_journals" permissions={['collections.read', 'collections.create', 'overview.read']} request={request} navigate={navigate} area="groups" />);
    fireEvent.click(screen.getByRole('button', { name: 'Check group creation request' }));
    expect(navigate).toHaveBeenCalledWith('/admin/groups/new'); expect(screen.queryByRole('button', { name: 'Create group' })).not.toBeInTheDocument();
  });

  it('loads subsequent server-backed membership pages without hiding the total', async () => {
    const request = vi.fn(async (path: string) => path.includes('?') ? relatedFixture.next : relatedFixture.first);
    render(<CoreRecordPage {...base} actorId={relatedFixture.first.current_actor_id} request={request} area="groups" id={relatedFixture.first.resource.id} />);
    const heading = await screen.findByRole('heading', { name: 'Memberships' });
    const container = heading.closest('.core-detail') as HTMLElement;
    expect(within(container).getByText('1–25 of 28')).toBeInTheDocument();
    fireEvent.click(within(container).getByRole('button', { name: 'Next' }));
    expect(await within(container).findByText('26–28 of 28')).toBeInTheDocument();
    expect(request).toHaveBeenCalledWith(expect.stringContaining('relation=memberships&limit=25&offset=25'));
  });

  it('surfaces retained membership recovery even when its row is no longer in the group', async () => {
    Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true }); sessionStorage.clear();
    const groupId = relatedFixture.first.resource.id, userId = '99999999-9999-4999-8999-999999999999';
    const identity = { id: relatedFixture.first.current_actor_id, sessionId: 'same-session', email: 'operator@example.test', role: 'admin' as const,
      permissions: ['collections.read', 'users.read', 'users.manage'], expiresAt: '2100-01-01T00:00:00.000Z' };
    await retainPending(identity, 'operating-updatemembership', `${groupId}:${userId}`, 'reference-123', 'users.manage', { expected_version: 1, role: 'member', status: 'removed', reason: 'Recorded reviewed change' });
    const navigate = vi.fn(), request = vi.fn(async () => relatedFixture.first);
    render(<CoreRecordPage {...base} actorId={identity.id} permissions={identity.permissions} identity={identity} request={request} navigate={navigate} area="groups" id={groupId} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check pending membership change' }));
    expect(navigate).toHaveBeenCalledWith(`/admin/groups/${groupId}/members/${userId}/edit`); sessionStorage.clear();
  });

  it('loads canonical support notes in the matching group detail without enabling writes', async () => {
    const groupId = relatedFixture.first.resource.id, actorId = relatedFixture.first.current_actor_id;
    const identity = {id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'admin' as const,
      permissions: ['collections.read'], expiresAt: '2100-01-01T00:00:00.000Z'};
    const request = vi.fn(async (path: string) => path.includes('/notes?') ? {contract_version: 1, entity_type: 'collection',
      entity_id: groupId, total: 1, limit: 25, offset: 0, rows: [{id: '99999999-9999-4999-8999-999999999999',
        body: 'A retained support note', created_by: actorId, author_name: 'Operator', created_at: '2026-11-16T12:00:00.000Z'}]} : relatedFixture.first);
    render(<CoreRecordPage {...base} actorId={actorId} identity={identity} request={request} area="groups" id={groupId} />);
    expect(await screen.findByText('A retained support note')).toBeInTheDocument();
    expect(screen.getByText('Recording new notes is currently unavailable.')).toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Record note'})).not.toBeInTheDocument();
  });

  it('opens a legacy group ledger account when ledger-read access is granted', async () => {
    const groupId = '33333333-3333-4333-8333-333333333333', accountId = '44444444-4444-4444-8444-444444444444';
    const response = { resource_type: 'groups', current_actor_id: base.actorId, can_manage: false, resource: { id: groupId, version: 1 },
      related: { accounts: [{ id: accountId, code: '1000', name: 'Group cash' }] }, related_truncated: false };
    const navigate = vi.fn(), request = vi.fn(async () => response);
    render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={['collections.read', 'ledger.read']} request={request} navigate={navigate} area="groups" id={groupId} />);
    fireEvent.click(await screen.findByRole('button', { name: 'View account' }));
    expect(navigate).toHaveBeenCalledWith(`/admin/ledger-accounts/${accountId}`);
  });
  it('offers legacy receiver-creation recovery without implying writes are enabled', async () => {
    const groupId = '33333333-3333-4333-8333-333333333333';
    const response = { resource_type: 'groups', current_actor_id: base.actorId, can_manage: true, resource: { id: groupId, version: 1, status: 'draft' }, related: {}, related_truncated: false };
    const navigate = vi.fn(), request = vi.fn(async () => response);
    render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={['collections.read', 'receivers.manage', 'overview.read']} request={request} navigate={navigate} area="groups" id={groupId} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check receiver creation request' }));
    expect(navigate).toHaveBeenCalledWith(`/admin/groups/${groupId}/payees/new`);
    expect(screen.queryByRole('button', { name: 'Add receiver' })).not.toBeInTheDocument();
  });
  it('offers account creation recovery only for matching legacy authority', async () => {
    const groupId = '33333333-3333-4333-8333-333333333333';
    const permissions = ['collections.read', 'ledger.read', 'ledger.manage', 'overview.read'];
    const identity = {id: base.actorId, sessionId: 'same-session', email: 'admin@example.test', role: 'admin' as const, permissions, expiresAt: '2100-01-01T00:00:00.000Z'};
    const response = {resource_type: 'groups', current_actor_id: base.actorId, can_manage: true, resource: {id: groupId, version: 1, status: 'draft'}, related: {}, related_truncated: false};
    const navigate = vi.fn(), request = vi.fn(async () => response);
    const {rerender} = render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={permissions} identity={identity} request={request} navigate={navigate} area="groups" id={groupId} />);
    fireEvent.click(await screen.findByRole('button', {name: 'Check ledger account request'}));
    expect(navigate).toHaveBeenCalledWith(`/admin/groups/${groupId}/ledger-accounts/new`);
    expect(screen.queryByRole('button', {name: 'Add ledger account'})).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', {name: 'Check journal draft request'}));
    expect(navigate).toHaveBeenCalledWith(`/admin/groups/${groupId}/journals/new`);
    rerender(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={permissions} identity={{...identity, permissions: ['collections.read']}} request={request} navigate={navigate} area="groups" id={groupId} />);
    expect(screen.queryByRole('button', {name: 'Check ledger account request'})).not.toBeInTheDocument();
  });
  it('links a group to payment recovery only for matching legacy authority', async () => {
    const groupId = '33333333-3333-4333-8333-333333333333';
    const permissions = ['collections.read', 'receivers.read', 'payments.read', 'payments.manage', 'overview.read'];
    const identity = {id: base.actorId, sessionId: 'same-session', email: 'admin@example.test', role: 'admin' as const, permissions, expiresAt: '2100-01-01T00:00:00.000Z'};
    const response = {resource_type: 'groups', current_actor_id: base.actorId, can_manage: true, resource: {id: groupId, version: 1, status: 'active'}, related: {}, related_truncated: false};
    const navigate = vi.fn(), request = vi.fn(async () => response);
    const {rerender} = render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={permissions} identity={identity} request={request} navigate={navigate} area="groups" id={groupId} />);
    fireEvent.click(await screen.findByRole('button', {name: 'Check payment request'}));
    expect(navigate).toHaveBeenCalledWith(`/admin/groups/${groupId}/transactions/new`);
    expect(screen.queryByRole('button', {name: 'Record payment evidence'})).not.toBeInTheDocument();
    rerender(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={permissions} identity={{...identity, permissions: ['collections.read']}} request={request} navigate={navigate} area="groups" id={groupId} />);
    expect(screen.queryByRole('button', {name: 'Check payment request'})).not.toBeInTheDocument();
  });
  it('offers legacy receiver edit recovery only when both authority views grant access', async () => {
    const payeeId = '33333333-3333-4333-8333-333333333333';
    const permissions = ['receivers.read', 'receivers.manage', 'collections.read', 'overview.read'];
    const identity = {id: base.actorId, sessionId: 'same-session', email: 'admin@example.test', role: 'admin' as const, permissions, expiresAt: '2100-01-01T00:00:00.000Z'};
    const response = {resource_type: 'payees', current_actor_id: base.actorId, can_manage: true, resource: {id: payeeId, version: 1, status: 'active'}, related: {}, related_truncated: false};
    const navigate = vi.fn(), request = vi.fn(async () => response);
    const {rerender} = render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={permissions} identity={identity} request={request} navigate={navigate} area="payees" id={payeeId} />);
    fireEvent.click(await screen.findByRole('button', {name: 'Check receiver change request'}));
    expect(navigate).toHaveBeenCalledWith(`/admin/payees/${payeeId}/edit`);
    expect(screen.queryByRole('button', {name: 'Edit receiver'})).not.toBeInTheDocument();
    rerender(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={permissions} identity={{...identity, permissions: ['receivers.read']}} request={request} navigate={navigate} area="payees" id={payeeId} />);
    expect(screen.queryByRole('button', {name: 'Check receiver change request'})).not.toBeInTheDocument();
  });
  it('offers legacy membership recovery from group and person details, with change labels only when enabled', async () => {
    const groupId = '33333333-3333-4333-8333-333333333333', userId = '44444444-4444-4444-8444-444444444444';
    const permissions = ['collections.read', 'users.read', 'users.manage', 'overview.read'], navigate = vi.fn();
    const row = {group_id: groupId, user_id: userId, role: 'receiver', status: 'active', version: 1};
    const request = vi.fn(async (path: string) => ({resource_type: path.includes('/groups/') ? 'groups' : 'users', current_actor_id: base.actorId, can_manage: true,
      resource: {id: path.includes('/groups/') ? groupId : userId, version: 1, status: 'active'}, related: {memberships: [row]}, related_truncated: false}));
    const {rerender} = render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={permissions} request={request} navigate={navigate} area="groups" id={groupId} />);
    const recovery = await screen.findAllByRole('button', {name: 'Check membership request'}); expect(recovery).toHaveLength(2);
    fireEvent.click(recovery[0]); expect(navigate).toHaveBeenCalledWith(`/admin/groups/${groupId}/members/new`);
    fireEvent.click(recovery[1]); expect(navigate).toHaveBeenCalledWith(`/admin/groups/${groupId}/members/${userId}/edit`);
    rerender(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={permissions} request={request} navigate={navigate} area="users" id={userId} allowMutations />);
    fireEvent.click(await screen.findByRole('button', {name: 'Edit membership'})); expect(navigate).toHaveBeenCalledWith(`/admin/groups/${groupId}/members/${userId}/edit`);
  });
  it('offers legacy group-change recovery without implying edits are enabled', async () => {
    const groupId = '33333333-3333-4333-8333-333333333333';
    const response = { resource_type: 'groups', current_actor_id: base.actorId, can_manage: true, resource: { id: groupId, version: 1, status: 'draft' }, related: {}, related_truncated: false };
    const navigate = vi.fn(), request = vi.fn(async () => response);
    render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={['collections.read', 'collections.manage', 'overview.read']} request={request} navigate={navigate} area="groups" id={groupId} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check group change request' }));
    expect(navigate).toHaveBeenCalledWith(`/admin/groups/${groupId}/edit`); expect(screen.queryByRole('button', { name: 'Edit group' })).not.toBeInTheDocument();
  });
  it('offers legacy person-change recovery without implying edits are enabled', async () => {
    const userId = '33333333-3333-4333-8333-333333333333';
    const response = { resource_type: 'users', current_actor_id: base.actorId, can_manage: true, resource: { id: userId, collect_user_id: userId, operator_admin_id: null, member_type: 'app', version: 1, status: 'active' }, related: {}, related_truncated: false };
    const navigate = vi.fn(), request = vi.fn(async () => response);
    render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={['users.read', 'users.manage', 'overview.read']} request={request} navigate={navigate} area="users" id={userId} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check person change request' }));
    expect(navigate).toHaveBeenCalledWith(`/admin/users/${userId}/edit`); expect(screen.queryByRole('button', { name: 'Edit person' })).not.toBeInTheDocument();
  });
  it('offers legacy journal posting recovery while writes are disabled', async () => {
    const journalId = '33333333-3333-4333-8333-333333333333';
    const response = { resource_type: 'journals', current_actor_id: base.actorId, can_manage: true, resource: { id: journalId, version: 1, status: 'posted' }, related: {}, related_truncated: false };
    const navigate = vi.fn(), request = vi.fn(async () => response);
    render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={['ledger.read', 'ledger.manage']} request={request} navigate={navigate} area="ledgers" id={journalId} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check journal posting request' }));
    expect(navigate).toHaveBeenCalledWith(`/admin/ledgers/${journalId}/post`);
    fireEvent.click(screen.getByRole('button', { name: 'Check journal draft change' }));
    expect(navigate).toHaveBeenCalledWith(`/admin/ledgers/${journalId}/edit`);
    expect(screen.queryByRole('button', { name: 'Review posting' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Replace draft' })).not.toBeInTheDocument();
  });
  it('offers a linked-journal recovery entry from a legacy transaction allocation', async () => {
    const transactionId = '33333333-3333-4333-8333-333333333333', allocationId = '44444444-4444-4444-8444-444444444444';
    const response = { resource_type: 'transactions', current_actor_id: base.actorId, can_manage: true, resource: { id: transactionId, version: 1, verification_status: 'confirmation_recorded' },
      related: { allocations: [{ id: allocationId, amount_rwf: 2500 }] }, related_truncated: false };
    const navigate = vi.fn(), request = vi.fn(async () => response);
    render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={['payments.read', 'ledger.read', 'ledger.manage']} request={request} navigate={navigate} area="transactions" id={transactionId} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check linked journal request' }));
    expect(navigate).toHaveBeenCalledWith(`/admin/transactions/${transactionId}/allocations/${allocationId}/journal/new`);
    expect(screen.queryByRole('button', { name: 'Review linked draft' })).not.toBeInTheDocument();
  });
  it('mounts disabled legacy transaction recovery panels for the matching current session', async () => {
    sessionStorage.clear(); localStorage.clear();
    const originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
    Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, task: (lock: {name: string}) => Promise<unknown>) => task({name})}});
    const transactionId = '33333333-3333-4333-8333-333333333333';
    const permissions = ['payments.read', 'payments.manage', 'overview.read'];
    const identity = {id: base.actorId, sessionId: 'same-session', email: 'admin@example.test', role: 'admin' as const, permissions, expiresAt: '2100-01-01T00:00:00.000Z'};
    const response = {resource_type: 'transactions', current_actor_id: base.actorId, can_manage: true, resource: {id: transactionId, version: 1}, related: {}, related_truncated: false};
    const request = vi.fn(async () => response);
    try {
      render(<CoreRecordPage {...base} financialModel="transaction_journals" permissions={permissions} identity={identity} isCurrent={() => true} request={request} area="transactions" id={transactionId} />);
      expect(await screen.findByRole('heading', {name: 'Add transaction evidence'})).toBeInTheDocument();
      expect(await screen.findByRole('heading', {name: 'Independent evidence review'})).toBeInTheDocument();
      expect(await screen.findAllByText('This transaction action is not enabled for this workspace.')).toHaveLength(2);
      expect(screen.queryByRole('button', {name: 'Review request'})).not.toBeInTheDocument();
    } finally {if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');}
  });
  it('offers original reversal recovery without requiring ledger-read access', async () => {
    const transaction = reconciliationFixture.after.resource, navigate = vi.fn();
    const request = vi.fn(async () => ({ contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'transactions',
      current_actor_id: base.actorId, can_manage: false, allowed_operations: [], resource: transaction, related: {}, related_pages: {}, related_truncated: false }));
    render(<CoreRecordPage {...base} permissions={['payments.read', 'payments.reconcile']} request={request} navigate={navigate} area="transactions" id={transaction.id} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check reversal request' }));
    expect(navigate).toHaveBeenCalledWith(`/admin/transactions/${transaction.id}/reverse`);
  });
});
