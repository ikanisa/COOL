import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { LegacyJournalCreatePage } from '../../src/features/core/LegacyJournalCreatePage';
import { PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actor = '11111111-1111-4111-8111-111111111111', group = '22222222-2222-4222-8222-222222222222', transaction = '33333333-3333-4333-8333-333333333333';
const allocation = '44444444-4444-4444-8444-444444444444', journal = '55555555-5555-4555-8555-555555555555', reqId = '66666666-6666-4666-8666-666666666666';
const account1 = '77777777-7777-4777-8777-777777777777', account2 = '88888888-8888-4888-8888-888888888888', member = '99999999-9999-4999-8999-999999999999';
const permissions = ['ledger.manage', 'ledger.read', 'collections.read', 'overview.read', 'payments.read'];
const identity: PendingIdentity = { id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions, expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId: actor, principalId: null, role: 'admin', authorityKey: 'authority-1', permissions, financialModel: 'transaction_journals', navigate: vi.fn() };
const body = { group_id: group, description: 'Record confirmed allocation', allocation_id: allocation, entries: [
  { account_id: account1, debit_rwf: 2500, credit_rwf: 0, description: '' }, { account_id: account2, debit_rwf: 0, credit_rwf: 2500, description: '' },
], reason: 'Create reviewed linked draft' };
const receipt = { request_id: reqId, resource_type: 'journals', resource_id: journal, version: 1, status: 'succeeded' };
const history = (key: string) => ({ total: 1, rows: [{ id: reqId, idempotency_key: key, scope: 'journals.post', status: 'succeeded', receipt }] });
function fixture() {
  return { transaction: { id: transaction, group_id: group, version: 3, amount_rwf: 5000, verification_status: 'confirmation_recorded' },
    allocation: { id: allocation, group_id: group, transaction_id: transaction, amount_rwf: 2500, member_user_id: member as string | null },
    journals: [] as { id: string; allocation_id: string | null; status: string; version: number }[],
    group: { id: group, title: 'Savings group', status: 'active', currency: 'RWF', country_code: 'RW', version: 2 },
    accounts: [{ id: account1, group_id: group, status: 'active', currency: 'RWF', version: 1, code: '1000', name: 'Cash account' },
      { id: account2, group_id: group, status: 'active', currency: 'RWF', version: 1, code: '2000', name: 'Member account' }] };
}
function detail(type: string, resource: object) { return { resource_type: type, current_actor_id: actor, can_manage: true, resource }; }
function related(name: string, rows: object[]) { return { related: { [name]: rows }, related_pages: { [name]: { total: rows.length, limit: 100, offset: 0, next_offset: null } }, related_truncated: false }; }
function reader(data: ReturnType<typeof fixture>) {
  return async (path: string): Promise<Record<string, unknown>> => {
    if (path === `operations/transactions/${transaction}?relation=allocations&limit=100&offset=0`) return { ...detail('transactions', data.transaction), ...related('allocations', [data.allocation]) };
    if (path === `operations/transactions/${transaction}?relation=journals&limit=100&offset=0`) return { ...detail('transactions', data.transaction), ...related('journals', data.journals) };
    if (path === `operations/groups/${group}`) return detail('groups', data.group);
    if (path.startsWith('operations/lookups?kind=accounts')) return { rows: data.accounts.map(item => ({ id: item.id, label: `${item.code} · ${item.name}`, version: item.version })) };
    const account = data.accounts.find(item => path === `operations/accounts/${item.id}`); if (account) return detail('accounts', account);
    throw new Error('Unexpected request');
  };
}
beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  Object.defineProperty(navigator, 'locks', { value: { request: async (_name: string, _options: unknown, callback: (lock: object) => unknown) => callback({}) }, configurable: true });
  sessionStorage.clear();
});
async function fill(debit = '2500', credit = '2500') {
  await screen.findAllByRole('option', { name: '1000 · Cash account' });
  fireEvent.change(screen.getByLabelText('Account 1'), { target: { value: account1 } }); fireEvent.change(screen.getByLabelText('Account 2'), { target: { value: account2 } });
  fireEvent.change(screen.getByLabelText('Journal description'), { target: { value: body.description } }); fireEvent.change(screen.getByLabelText('Debit RWF 1'), { target: { value: debit } });
  fireEvent.change(screen.getByLabelText('Credit RWF 2'), { target: { value: credit } }); fireEvent.change(screen.getByLabelText('Reason for draft'), { target: { value: body.reason } });
}
async function review() { fireEvent.click(screen.getByRole('button', { name: 'Review journal draft' })); }
async function confirm() { await screen.findByRole('button', { name: 'Confirm draft' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(screen.getByRole('button', { name: 'Confirm draft' })); }
describe('legacy transaction-allocation journal creation', () => {
  it('defaults to disabled and refuses incomplete or canonical contexts', async () => {
    const request = vi.fn(), view = render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} />);
    expect(await screen.findByText(/not enabled/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
    view.rerender(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allowMutations />);
    expect(screen.getByText(/cannot create journal drafts/i)).toBeInTheDocument();
    view.rerender(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} financialModel="canonical_evidence_ledger" allowMutations />);
    expect(screen.getByText(/unavailable for the canonical evidence ledger/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it.each(['unconfirmed', 'wrong group', 'wrong transaction', 'zero amount', 'duplicate', 'inactive group', 'wrong currency'] as const)('refuses %s context before offering a draft', async fault => {
    const data = fixture();
    if (fault === 'unconfirmed') data.transaction.verification_status = 'pending'; if (fault === 'wrong group') data.allocation.group_id = journal;
    if (fault === 'wrong transaction') data.allocation.transaction_id = journal; if (fault === 'zero amount') data.allocation.amount_rwf = 0;
    if (fault === 'duplicate') data.journals.push({ id: journal, allocation_id: allocation, status: 'draft', version: 1 });
    if (fault === 'inactive group') data.group.status = 'suspended'; if (fault === 'wrong currency') data.group.currency = 'USD';
    const request = vi.fn(reader(data)); render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} allowMutations />);
    expect(await screen.findByText(/linked allocation, existing journals or draft recovery data could not be verified/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Review journal draft' })).not.toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('compares the whole allocation total before review', async () => {
    const request = vi.fn(reader(fixture())); render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} allowMutations />);
    await fill('2499', '2499'); await review(); expect(await screen.findByText(/No draft was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('creates the exact linked draft after full review and verifies receipt plus action scope', async () => {
    const read = reader(fixture()); let key = '';
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === 'operations/journals' && options?.method === 'POST') { key = options.idempotencyKey!; expect(options.body).toEqual(body); expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(body); return receipt; }
      if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: reqId, receipt };
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} allowMutations />);
    await fill(); expect(screen.getByText(new RegExp(`Required debit and credit totals: RWF 2,500`))).toBeInTheDocument();
    await review(); expect(await screen.findByText(new RegExp(`Allocation ${allocation}.*Allocation amount RWF 2,500`))).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Confirm draft' })).toBeDisabled(); await confirm();
    expect(await screen.findByText('The journal draft was recorded.')).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('rechecks allocation evidence and declines a changed amount before dispatch', async () => {
    const data = fixture(), read = reader(data); let reads = 0;
    const request = vi.fn(async (path: string) => { if (path.includes('relation=allocations') && ++reads === 3) data.allocation.amount_rwf = 3000; return read(path); });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} allowMutations />);
    await fill(); await review(); await confirm(); expect(await screen.findByText(/No draft was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('finds an existing journal beyond the first related-record page', async () => {
    const data = fixture(), read = reader(data);
    const makeId = (index: number) => `aaaaaaaa-aaaa-4aaa-8aaa-${index.toString(16).padStart(12, '0')}`;
    const first = Array.from({ length: 100 }, (_, index) => ({ id: makeId(index), allocation_id: null, status: 'draft', version: 1 }));
    const request = vi.fn(async (path: string) => {
      if (path.includes('relation=journals')) {
        const next = path.endsWith('offset=0') ? 100 : null, rows = next ? first : [{ id: journal, allocation_id: allocation, status: 'posted', version: 2 }];
        return { ...detail('transactions', data.transaction), related: { journals: rows }, related_pages: { journals: { total: 101, limit: 100, offset: next ? 0 : 100, next_offset: next } }, related_truncated: true };
      }
      return read(path);
    });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} allowMutations />);
    expect(await screen.findByText(/linked allocation, existing journals or draft recovery data could not be verified/i)).toBeInTheDocument();
    expect(request).toHaveBeenCalledWith(`operations/transactions/${transaction}?relation=journals&limit=100&offset=100`); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('recovers a lost response and retries the same linked request only after rechecking its original allocation', async () => {
    const read = reader(fixture()); let key = '', writes = 0, lookups = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === 'operations/journals' && options?.method === 'POST') { writes++; expect(options.body).toEqual(body); if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); } expect(options.idempotencyKey).toBe(key); return receipt; }
      if (path === `operations/requests/${key}`) { lookups++; return writes < 2 ? { status: 'not_found' } : { status: 'succeeded', request_id: reqId, receipt }; }
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} allowMutations />);
    await fill(); await review(); await confirm(); expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const button = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(button);
    expect(await screen.findByText('The journal draft was recorded.')).toBeInTheDocument(); expect(writes).toBe(2); expect(lookups).toBe(3); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('keeps a not-found request when another journal has since claimed the allocation', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-createjournal', 'new', key, 'ledger.manage', body);
    const data = fixture(); data.journals.push({ id: journal, allocation_id: allocation, status: 'draft', version: 1 }); const read = reader(data);
    const request = vi.fn(async (path: string) => path === `operations/requests/${key}` ? { status: 'not_found' } : read(path));
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} allowMutations />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    expect(await screen.findByText(/No draft was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
    expect(request.mock.calls.some(([path]) => path === 'operations/journals')).toBe(false);
  });
  it('does not submit again when the original key succeeds after review', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-createjournal', 'new', key, 'ledger.manage', body);
    const read = reader(fixture()); let checks = 0;
    const request = vi.fn(async (path: string) => {
      if (path === `operations/requests/${key}`) return ++checks === 1 ? { status: 'not_found' } : { status: 'succeeded', request_id: reqId, receipt };
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} allowMutations />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const button = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(button);
    expect(await screen.findByText('The original journal draft request was recorded.')).toBeInTheDocument();
    expect(request.mock.calls.some(([path]) => path === 'operations/journals')).toBe(false); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('does not read or create linked drafts without payment-read permission', async () => {
    const restricted = { ...identity, permissions: permissions.filter(permission => permission !== 'payments.read') };
    const request = vi.fn(); render(<LegacyJournalCreatePage {...access} permissions={restricted.permissions} request={request} identity={restricted} transactionId={transaction} allocationId={allocation} allowMutations />);
    expect(await screen.findByText(/payment read permissions are required/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
    expect(screen.queryByRole('button', { name: 'Review journal draft' })).not.toBeInTheDocument();
  });
  it('will not retry an original request from a different allocation context', async () => {
    const key = '12345678-original', other = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    await retainPending(identity, 'operating-createjournal', 'new', key, 'ledger.manage', body);
    const request = vi.fn(async (path: string) => { expect(path).toBe(`operations/requests/${key}`); return { status: 'not_found' }; });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={other} allowMutations />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText(/Return to the original transaction allocation/i)).toBeInTheDocument(); expect(screen.queryByRole('button', { name: 'Review same request' })).not.toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
  });
  it('checks an original receipt without loading a changed allocation when writes are disabled', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-createjournal', 'new', key, 'ledger.manage', body);
    const request = vi.fn(async (path: string) => { if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: reqId, receipt }; if (path === 'operations/requests?limit=100&offset=0') return history(key); throw new Error('Unexpected'); });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} transactionId={transaction} allocationId={allocation} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' })); expect(await screen.findByText('The original journal draft request was recorded.')).toBeInTheDocument(); expect(request).toHaveBeenCalledTimes(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
