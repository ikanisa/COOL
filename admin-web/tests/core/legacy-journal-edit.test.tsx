import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { LegacyJournalEditPage } from '../../src/features/core';
import { PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actor = '11111111-1111-4111-8111-111111111111', group = '22222222-2222-4222-8222-222222222222', journal = '33333333-3333-4333-8333-333333333333';
const reqId = '44444444-4444-4444-8444-444444444444', account1 = '55555555-5555-4555-8555-555555555555', account2 = '66666666-6666-4666-8666-666666666666';
const account3 = '77777777-7777-4777-8777-777777777777', line1 = '88888888-8888-4888-8888-888888888888', line2 = '99999999-9999-4999-8999-999999999999';
const transaction = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', allocation = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', member = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const permissions = ['ledger.manage', 'ledger.read', 'collections.read', 'overview.read', 'payments.read'];
const identity: PendingIdentity = { id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions, expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId: actor, principalId: null, role: 'admin', authorityKey: 'authority-1', permissions, financialModel: 'transaction_journals', navigate: vi.fn() };
const body = { expected_version: 2, description: 'Revised contribution', entries: [
  { account_id: account1, debit_rwf: 3000, credit_rwf: 0, description: '' }, { account_id: account2, debit_rwf: 0, credit_rwf: 3000, description: '' },
], reason: 'Replace reviewed draft' };
const receipt = { request_id: reqId, resource_type: 'journals', resource_id: journal, version: 3, status: 'succeeded' };
const history = (key: string, scope = 'journals.patch') => ({ total: 1, rows: [{ id: reqId, idempotency_key: key, scope, status: 'succeeded', receipt }] });
function fixture() {
  return { row: { id: journal, group_id: group, status: 'draft', currency: 'RWF', version: 2, description: 'Original contribution', created_by_admin_id: actor, edited_by_admin_id: actor, allocation_id: null as string | null, transaction_id: null as string | null },
    rows: [
      { id: line1, journal_id: journal, group_id: group, account_id: account1, line_number: 1, debit_rwf: 2500, credit_rwf: 0, description: '', account_code: '1000', account_name: 'Cash account' },
      { id: line2, journal_id: journal, group_id: group, account_id: account2, line_number: 2, debit_rwf: 0, credit_rwf: 2500, description: '', account_code: '2000', account_name: 'Member account' },
    ],
    group: { id: group, title: 'Savings group', status: 'active', currency: 'RWF', country_code: 'RW', version: 3 },
    accounts: [ { id: account1, group_id: group, status: 'active', currency: 'RWF', version: 1, code: '1000', name: 'Cash account' },
      { id: account2, group_id: group, status: 'active', currency: 'RWF', version: 1, code: '2000', name: 'Member account' },
      { id: account3, group_id: group, status: 'active', currency: 'RWF', version: 1, code: '3000', name: 'Replacement account' } ],
    transaction: { id: transaction, group_id: group, version: 4, verification_status: 'confirmation_recorded' },
    allocation: { id: allocation, transaction_id: transaction, group_id: group, amount_rwf: 2500, member_user_id: member },
  };
}
function detail(type: string, resource: object) { return { resource_type: type, current_actor_id: actor, can_manage: true, resource }; }
function related(name: string, rows: object[]) { return { related: { [name]: rows }, related_pages: { [name]: { total: rows.length, limit: 100, offset: 0, next_offset: null } }, related_truncated: false }; }
function reader(data: ReturnType<typeof fixture>) {
  return async (path: string): Promise<Record<string, unknown>> => {
    if (path === `operations/journals/${journal}?relation=entries&limit=100&offset=0`) return { ...detail('journals', data.row), ...related('entries', data.rows) };
    if (path === `operations/groups/${group}`) return detail('groups', data.group);
    if (path.startsWith('operations/lookups?kind=accounts')) return { rows: data.accounts.filter(item => item.status === 'active').map(item => ({ id: item.id, label: `${item.code} · ${item.name}`, version: item.version })) };
    const account = data.accounts.find(item => path === `operations/accounts/${item.id}`); if (account) return detail('accounts', account);
    if (path === `operations/transactions/${transaction}?relation=allocations&limit=100&offset=0`) return { ...detail('transactions', data.transaction), ...related('allocations', [data.allocation]) };
    throw new Error('Unexpected request');
  };
}
beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  Object.defineProperty(navigator, 'locks', { value: { request: async (_name: string, _options: unknown, callback: (lock: object) => unknown) => callback({}) }, configurable: true });
  sessionStorage.clear();
});
async function fill(debit = '3000', credit = '3000') {
  fireEvent.change(await screen.findByLabelText('Journal description'), { target: { value: body.description } });
  fireEvent.change(screen.getByLabelText('Debit RWF 1'), { target: { value: debit } }); fireEvent.change(screen.getByLabelText('Credit RWF 2'), { target: { value: credit } });
  fireEvent.change(screen.getByLabelText('Reason for replacement'), { target: { value: body.reason } });
}
async function review() { fireEvent.click(screen.getByRole('button', { name: 'Review replacement' })); }
async function confirm() { await screen.findByRole('button', { name: 'Confirm replacement' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(screen.getByRole('button', { name: 'Confirm replacement' })); }
describe('legacy journal draft replacement', () => {
  it('defaults to disabled and refuses canonical evidence editing', async () => {
    const request = vi.fn(), view = render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} />);
    expect(await screen.findByText(/not enabled/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
    view.rerender(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} financialModel="canonical_evidence_ledger" allowMutations />);
    expect(screen.getByText(/unavailable for the canonical evidence ledger/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it.each(['posted', 'unbalanced existing', 'truncated', 'inactive group', 'wrong currency'] as const)('refuses the original %s', async fault => {
    const data = fixture(); if (fault === 'posted') data.row.status = 'posted'; if (fault === 'unbalanced existing') data.rows[1].credit_rwf = 2499;
    if (fault === 'inactive group') data.group.status = 'suspended'; if (fault === 'wrong currency') data.accounts[0].currency = 'USD';
    const read = reader(data), request = vi.fn(async (path: string) => { const value = await read(path); return fault === 'truncated' && path.includes('journals/') ? { ...value, related_truncated: true } : value; });
    render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    expect(await screen.findByText(/draft, linked allocation or recovery data could not be verified/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it.each([['unbalanced', '3000', '2999'], ['fraction', '25.5', '25.5'], ['unsafe', '9007199254740992', '9007199254740992']] as const)('rejects %s replacement values', async (_name, debit, credit) => {
    const request = vi.fn(reader(fixture())); render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill(debit, credit); await review(); expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('rejects a balanced total above the exact-integer limit even if each line is valid', async () => {
    const request = vi.fn(reader(fixture())); render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill('9007199254740991', '9007199254740991'); fireEvent.click(screen.getByRole('button', { name: 'Add entry' })); fireEvent.click(screen.getByRole('button', { name: 'Add entry' }));
    fireEvent.change(screen.getByLabelText('Account 3'), { target: { value: account1 } }); fireEvent.change(screen.getByLabelText('Debit RWF 3'), { target: { value: '1' } });
    fireEvent.change(screen.getByLabelText('Account 4'), { target: { value: account2 } }); fireEvent.change(screen.getByLabelText('Credit RWF 4'), { target: { value: '1' } });
    await review(); expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('shows original and replacement entries and verifies the exact PATCH receipt and scope', async () => {
    const read = reader(fixture()); let key = '';
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/journals/${journal}` && options?.method === 'PATCH') { key = options.idempotencyKey!; expect(options.body).toEqual(body); expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(body); return receipt; }
      if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: reqId, receipt };
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill(); await review(); expect(await screen.findByText(/Current description: Original contribution/i)).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Current journal entries' })).toHaveTextContent('RWF 2,500'); expect(screen.getByRole('region', { name: 'Replacement journal entries' })).toHaveTextContent('RWF 3,000');
    expect(screen.getByRole('button', { name: 'Confirm replacement' })).toBeDisabled(); await confirm();
    expect(await screen.findByText('The journal draft was replaced.')).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('allows replacing a closed old account only with a verified active account', async () => {
    const data = fixture(); data.accounts[0].status = 'closed'; const request = vi.fn(reader(data));
    render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill(); expect(screen.getAllByRole('option', { name: '1000 · Cash account (closed)' })).toHaveLength(2);
    fireEvent.click(screen.getByRole('button', { name: 'Search accounts' })); await screen.findAllByRole('option', { name: '3000 · Replacement account' });
    fireEvent.change(screen.getByLabelText('Account 1'), { target: { value: account3 } }); await review();
    expect(await screen.findByRole('button', { name: 'Confirm replacement' })).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Current journal entries' })).toHaveTextContent('Cash account · closed');
    expect(screen.getByRole('region', { name: 'Replacement journal entries' })).toHaveTextContent('Replacement account');
  });
  it('rejects replacement totals that differ from the confirmed allocation', async () => {
    const data = fixture(); data.row.allocation_id = allocation; data.row.transaction_id = transaction;
    const request = vi.fn(reader(data)); render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill(); await review(); expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('reviews allocation-linked drafts only with confirmed matching evidence and payment read access', async () => {
    const data = fixture(); data.row.allocation_id = allocation; data.row.transaction_id = transaction;
    const request = vi.fn(reader(data)), view = render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill('2500', '2500'); await review(); expect(await screen.findByText(new RegExp(`Confirmed transaction ${transaction}`))).toBeInTheDocument();
    view.unmount(); data.transaction.verification_status = 'pending'; render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    expect(await screen.findByText(/draft, linked allocation or recovery data could not be verified/i)).toBeInTheDocument();
  });
  it('refuses dispatch if the draft version changes after review', async () => {
    const data = fixture(), read = reader(data); let journalReads = 0;
    const request = vi.fn(async (path: string) => { if (path.includes('journals/') && ++journalReads === 3) data.row.version = 3; return read(path); });
    render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill(); await review(); await confirm(); expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('retains a lost response and explicitly retries the exact original key and PATCH body', async () => {
    const read = reader(fixture()); let key = '', writes = 0, lookups = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/journals/${journal}` && options?.method === 'PATCH') { writes++; expect(options.body).toEqual(body); if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); } expect(options.idempotencyKey).toBe(key); return receipt; }
      if (path === `operations/requests/${key}`) { lookups++; return writes < 2 ? { status: 'not_found' } : { status: 'succeeded', request_id: reqId, receipt }; }
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill(); await review(); await confirm(); expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const button = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(button);
    expect(await screen.findByText('The journal draft was replaced.')).toBeInTheDocument(); expect(writes).toBe(2); expect(lookups).toBe(3); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('does not resend when the original key succeeds between review and confirmation', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-updatejournal', journal, key, 'ledger.manage', body);
    const read = reader(fixture()); let checks = 0;
    const request = vi.fn(async (path: string) => {
      if (path === `operations/requests/${key}`) return ++checks === 1 ? { status: 'not_found' } : { status: 'succeeded', request_id: reqId, receipt };
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const button = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(button);
    expect(await screen.findByText('The original draft replacement was recorded.')).toBeInTheDocument();
    expect(request.mock.calls.some(([path]) => path === `operations/journals/${journal}`)).toBe(false); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('fences an in-flight review when the write gate closes', async () => {
    const read = reader(fixture()); let release: (() => void) | undefined, reads = 0;
    const request = vi.fn(async (path: string) => { if (path.includes('journals/') && ++reads === 2) await new Promise<void>(resolve => { release = resolve; }); return read(path); });
    const view = render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill(); await review(); expect(release).toBeDefined(); view.rerender(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} />); release!();
    expect(await screen.findByText(/not enabled/i)).toBeInTheDocument(); expect(screen.queryByRole('button', { name: 'Confirm replacement' })).not.toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('retains the key when direct and original lookup receipts disagree', async () => {
    const read = reader(fixture()); let key = '';
    const other = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
    const request = vi.fn(async (path: string, options?: { method?: string; idempotencyKey?: string }) => {
      if (path === `operations/journals/${journal}` && options?.method === 'PATCH') { key = options.idempotencyKey!; return receipt; }
      if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: other, receipt: { ...receipt, request_id: other } };
      return read(path);
    });
    render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill(); await review(); await confirm(); expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
  });
  it('recovers a receipt without reading an unavailable or already-posted draft', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-updatejournal', journal, key, 'ledger.manage', body);
    const request = vi.fn(async (path: string) => { if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: reqId, receipt }; if (path === 'operations/requests?limit=100&offset=0') return history(key); throw new Error('Unexpected'); });
    render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} />); fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original draft replacement was recorded.')).toBeInTheDocument(); expect(request).toHaveBeenCalledTimes(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('retains recovery when the receipt is for a different journal action', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-updatejournal', journal, key, 'ledger.manage', body);
    const request = vi.fn(async (path: string) => { if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: reqId, receipt }; if (path === 'operations/requests?limit=100&offset=0') return history(key, 'journals.post.post'); throw new Error('Unexpected'); });
    render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} />); fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText(/original request could not be verified/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
  });
  it('does not dispatch if the cross-tab lock is unavailable', async () => {
    Object.defineProperty(navigator, 'locks', { value: undefined, configurable: true });
    const request = vi.fn(reader(fixture())); render(<LegacyJournalEditPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await fill(); await review(); await confirm(); expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
