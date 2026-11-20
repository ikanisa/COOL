import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { LegacyJournalPostPage } from '../../src/features/core';
import { PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actor = '11111111-1111-4111-8111-111111111111', group = '22222222-2222-4222-8222-222222222222', journal = '33333333-3333-4333-8333-333333333333';
const creator = '44444444-4444-4444-8444-444444444444', editor = '55555555-5555-4555-8555-555555555555', reqId = '66666666-6666-4666-8666-666666666666';
const account1 = '77777777-7777-4777-8777-777777777777', account2 = '88888888-8888-4888-8888-888888888888';
const line1 = '99999999-9999-4999-8999-999999999999', line2 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const transaction = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', allocation = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', member = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const permissions = ['ledger.manage', 'ledger.read', 'collections.read', 'overview.read', 'payments.read'];
const identity: PendingIdentity = { id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions, expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId: actor, principalId: null, role: 'admin', authorityKey: 'authority-1', permissions, financialModel: 'transaction_journals', navigate: vi.fn() };
const intent = { expected_version: 2, reason: 'Post reviewed journal' };
const receipt = { request_id: reqId, resource_type: 'journals', resource_id: journal, version: 3, status: 'succeeded' };
const history = (key: string, scope = 'journals.post.post') => ({ total: 1, rows: [{ id: reqId, idempotency_key: key, scope, status: 'succeeded', receipt }] });
function fixture() {
  const row = { id: journal, group_id: group, version: 2, status: 'draft', currency: 'RWF', description: 'Record contribution', created_by_admin_id: creator, edited_by_admin_id: editor, allocation_id: null as string | null, transaction_id: null as string | null };
  const rows = [
    { id: line1, journal_id: journal, group_id: group, account_id: account1, line_number: 1, debit_rwf: 2500, credit_rwf: 0, description: '', account_code: '1000', account_name: 'Recorded receiver funds' },
    { id: line2, journal_id: journal, group_id: group, account_id: account2, line_number: 2, debit_rwf: 0, credit_rwf: 2500, description: '', account_code: '2000', account_name: 'Member contributions' },
  ];
  const groupRow = { id: group, title: 'Savings group', status: 'active', currency: 'RWF', country_code: 'RW', version: 3 };
  const accounts = [ { id: account1, group_id: group, currency: 'RWF', status: 'active', version: 1, code: '1000', name: 'Recorded receiver funds' },
    { id: account2, group_id: group, currency: 'RWF', status: 'active', version: 1, code: '2000', name: 'Member contributions' } ];
  return { row, rows, groupRow, accounts };
}
function detail(type: string, resource: object) { return { resource_type: type, current_actor_id: actor, can_manage: true, resource }; }
function related(name: string, rows: object[]) { return { related: { [name]: rows }, related_pages: { [name]: { total: rows.length, limit: 100, offset: 0, next_offset: null } }, related_truncated: false }; }
function reader(data: ReturnType<typeof fixture>) {
  return async (path: string): Promise<Record<string, unknown>> => {
    if (path === `operations/journals/${journal}?relation=entries&limit=100&offset=0`) return { ...detail('journals', data.row), ...related('entries', data.rows) };
    if (path === `operations/groups/${group}`) return detail('groups', data.groupRow);
    const account = data.accounts.find(item => path === `operations/accounts/${item.id}`); if (account) return detail('accounts', account);
    if (path === `operations/transactions/${transaction}?relation=allocations&limit=100&offset=0`) return { ...detail('transactions', { id: transaction, group_id: group, version: 4, verification_status: 'confirmation_recorded' }), ...related('allocations', [{ id: allocation, transaction_id: transaction, group_id: group, amount_rwf: 2500, member_user_id: member }]) };
    throw new Error('Unexpected request');
  };
}
beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  Object.defineProperty(navigator, 'locks', { value: { request: async (_name: string, _options: unknown, callback: (lock: object) => unknown) => callback({}) }, configurable: true });
  sessionStorage.clear();
});
async function review() {
  fireEvent.change(await screen.findByLabelText('Reason for posting'), { target: { value: intent.reason } });
  fireEvent.click(screen.getByRole('button', { name: 'Review journal' }));
}
async function confirm() {
  await screen.findByRole('button', { name: 'Confirm posting' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(screen.getByRole('button', { name: 'Confirm posting' }));
}
describe('legacy journal posting', () => {
  it('defaults to disabled and leaves canonical signed evidence unavailable', async () => {
    const request = vi.fn(); const view = render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} />);
    expect(await screen.findByText(/not enabled/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
    view.rerender(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} financialModel="canonical_evidence_ledger" allowMutations />);
    expect(screen.getByText(/unavailable for the canonical evidence ledger/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it.each(['creator', 'editor', 'unbalanced', 'two-sided', 'inexact', 'group', 'currency', 'account', 'truncated'] as const)('fails closed for %s before posting', async fault => {
    const data = fixture();
    if (fault === 'creator') data.row.created_by_admin_id = actor;
    if (fault === 'editor') data.row.edited_by_admin_id = actor;
    if (fault === 'unbalanced') data.rows[1].credit_rwf = 2499;
    if (fault === 'two-sided') data.rows[0].credit_rwf = 1;
    if (fault === 'inexact') data.rows[0].debit_rwf = Number.MAX_SAFE_INTEGER + 1;
    if (fault === 'group') data.groupRow.status = 'suspended';
    if (fault === 'currency') data.accounts[0].currency = 'USD';
    if (fault === 'account') data.accounts[1].status = 'closed';
    const read = reader(data);
    const request = vi.fn(async (path: string) => { const value = await read(path); return fault === 'truncated' && path.includes('journals/') ? { ...value, related_truncated: true } : value; });
    render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await review(); expect(await screen.findByText(/No posting was submitted/i)).toBeInTheDocument(); expect(screen.queryByRole('button', { name: 'Confirm posting' })).not.toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('rejects totals above the exact-integer limit even when every line is individually exact', async () => {
    const data = fixture(); data.rows[0].debit_rwf = Number.MAX_SAFE_INTEGER; data.rows[1].credit_rwf = Number.MAX_SAFE_INTEGER;
    data.rows.push({ ...data.rows[0], id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', line_number: 3, debit_rwf: 1 });
    data.rows.push({ ...data.rows[1], id: 'ffffffff-ffff-4fff-8fff-ffffffffffff', line_number: 4, credit_rwf: 1 });
    const request = vi.fn(reader(data)); render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await review(); expect(await screen.findByText(/No posting was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('reviews all exact double-entry lines and the linked allocation with notification impact', async () => {
    const data = fixture(); data.row.allocation_id = allocation; data.row.transaction_id = transaction;
    const request = vi.fn(reader(data)); render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await review(); expect(await screen.findByText(/Posting may queue a member email notification/i)).toBeInTheDocument();
    expect(screen.getByRole('table')).toHaveTextContent('Recorded receiver funds'); expect(screen.getByRole('table')).toHaveTextContent('Member contributions');
    expect(screen.getByText(/Debit total: RWF 2,500 · Credit total: RWF 2,500/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Confirm posting' })).toBeDisabled();
  });
  it('does not post an allocation with a mismatched amount', async () => {
    const data = fixture(); data.row.allocation_id = allocation; data.row.transaction_id = transaction;
    const read = reader(data);
    const request = vi.fn(async (path: string) => {
      const result = await read(path);
      if (path.includes('transactions/')) return { ...result, related: { allocations: [{ id: allocation, transaction_id: transaction, group_id: group, amount_rwf: 2499, member_user_id: member }] } };
      return result;
    });
    render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await review(); expect(await screen.findByText(/No posting was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('fences an in-flight review when the write gate closes', async () => {
    const read = reader(fixture()); let release: (() => void) | undefined;
    const request = vi.fn(async (path: string) => {
      if (path.includes('journals/')) await new Promise<void>(resolve => { release = resolve; });
      return read(path);
    });
    const view = render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await review(); expect(release).toBeDefined(); view.rerender(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} />);
    release!(); expect(await screen.findByText(/not enabled/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Confirm posting' })).not.toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('rejects a changed draft after review without storing or sending a request', async () => {
    const data = fixture(); const read = reader(data); let journalReads = 0;
    const request = vi.fn(async (path: string) => { if (path.includes('journals/') && ++journalReads === 2) data.row.version = 3; return read(path); });
    render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await review(); await confirm(); expect(await screen.findByText(/No posting was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('recovers an uncertain response and explicitly retries the same body and original key', async () => {
    const data = fixture(), read = reader(data); let writes = 0, key = '', lookups = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/journals/${journal}/post` && options?.method === 'POST') {
        writes++; expect(options.body).toEqual(intent); expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(intent);
        if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(key); return receipt;
      }
      if (path === `operations/requests/${key}`) { lookups++; return writes < 2 ? { status: 'not_found' } : { status: 'succeeded', request_id: reqId, receipt }; }
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await review(); await confirm(); expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const button = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(button);
    expect(await screen.findByText('The journal posting was recorded.')).toBeInTheDocument(); expect(writes).toBe(2); expect(lookups).toBe(3); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('does not resend when another same-key attempt succeeds after review', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-postjournal', journal, key, 'ledger.manage', intent);
    const read = reader(fixture()); let checks = 0;
    const request = vi.fn(async (path: string) => {
      if (path === `operations/requests/${key}`) return ++checks === 1 ? { status: 'not_found' } : { status: 'succeeded', request_id: reqId, receipt };
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const button = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(button);
    expect(await screen.findByText('The original journal posting was recorded.')).toBeInTheDocument();
    expect(request.mock.calls.some(([path]) => path.endsWith('/post'))).toBe(false); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('recovers the actor-scoped original receipt without reading a posted journal or enabling writes', async () => {
    const restricted = { ...identity, permissions: ['ledger.manage', 'overview.read'] }; const key = '12345678-original';
    await retainPending(restricted, 'operating-postjournal', journal, key, 'ledger.manage', intent);
    const request = vi.fn(async (path: string) => { if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: reqId, receipt }; if (path === 'operations/requests?limit=100&offset=0') return history(key); throw new Error('Unexpected read'); });
    render(<LegacyJournalPostPage {...access} permissions={restricted.permissions} request={request} id={journal} identity={restricted} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' })); expect(await screen.findByText('The original journal posting was recorded.')).toBeInTheDocument();
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull(); expect(request).toHaveBeenCalledTimes(2);
  });
  it('does not mistake an unrelated journal update receipt for a posting', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-postjournal', journal, key, 'ledger.manage', intent);
    const request = vi.fn(async (path: string) => {
      if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: reqId, receipt };
      if (path === 'operations/requests?limit=100&offset=0') return history(key, 'journals.patch');
      throw new Error('Unexpected read');
    });
    render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText(/original request could not be verified/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
  });
  it('retains the original key if direct and lookup receipts disagree', async () => {
    const data = fixture(), read = reader(data); let key = '';
    const request = vi.fn(async (path: string, options?: { method?: string; idempotencyKey?: string }) => {
      if (path === `operations/journals/${journal}/post` && options?.method === 'POST') { key = options.idempotencyKey!; return receipt; }
      if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: creator, receipt: { ...receipt, request_id: creator } };
      return read(path);
    });
    render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await review(); await confirm(); expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
  });
  it('does not submit without a cross-tab lock', async () => {
    Object.defineProperty(navigator, 'locks', { value: undefined, configurable: true });
    const request = vi.fn(reader(fixture())); render(<LegacyJournalPostPage {...access} request={request} id={journal} identity={identity} allowMutations />);
    await review(); await confirm(); expect(await screen.findByText(/No posting was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
