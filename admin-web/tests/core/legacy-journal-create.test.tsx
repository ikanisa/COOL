import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { LegacyJournalCreatePage } from '../../src/features/core';
import { PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actor = '11111111-1111-4111-8111-111111111111', group = '22222222-2222-4222-8222-222222222222';
const journal = '33333333-3333-4333-8333-333333333333', reqId = '44444444-4444-4444-8444-444444444444';
const account1 = '55555555-5555-4555-8555-555555555555', account2 = '66666666-6666-4666-8666-666666666666', allocation = '77777777-7777-4777-8777-777777777777';
const permissions = ['ledger.manage', 'ledger.read', 'collections.read', 'overview.read'];
const identity: PendingIdentity = { id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions, expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId: actor, principalId: null, role: 'admin', authorityKey: 'authority-1', permissions, financialModel: 'transaction_journals', navigate: vi.fn() };
const body = { group_id: group, description: 'Record reviewed contribution', allocation_id: null, entries: [
  { account_id: account1, debit_rwf: 2500, credit_rwf: 0, description: '' }, { account_id: account2, debit_rwf: 0, credit_rwf: 2500, description: '' },
], reason: 'Create reviewed draft' };
const receipt = { request_id: reqId, resource_type: 'journals', resource_id: journal, version: 1, status: 'succeeded' };
const history = (key: string, scope = 'journals.post') => ({ total: 1, rows: [{ id: reqId, idempotency_key: key, scope, status: 'succeeded', receipt }] });
function fixture() {
  return { group: { id: group, title: 'Savings group', status: 'active', currency: 'RWF', country_code: 'RW', version: 2 },
    accounts: [ { id: account1, group_id: group, status: 'active', currency: 'RWF', version: 1, code: '1000', name: 'Cash account' },
      { id: account2, group_id: group, status: 'active', currency: 'RWF', version: 1, code: '2000', name: 'Member account' } ] };
}
function detail(type: string, resource: object) { return { resource_type: type, current_actor_id: actor, can_manage: true, resource }; }
function reader(data: ReturnType<typeof fixture>) {
  return async (path: string): Promise<Record<string, unknown>> => {
    if (path.startsWith('operations/lookups?kind=groups')) return { rows: [{ id: group, label: data.group.title, version: data.group.version }] };
    if (path.startsWith('operations/lookups?kind=accounts')) return { rows: data.accounts.map(item => ({ id: item.id, label: `${item.code} · ${item.name}`, version: item.version, account_type: 'asset', normal_side: 'debit' })) };
    if (path === `operations/groups/${group}`) return detail('groups', data.group);
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
  fireEvent.change(await screen.findByLabelText('Group'), { target: { value: group } });
  await screen.findAllByRole('option', { name: '1000 · Cash account' });
  fireEvent.change(screen.getByLabelText('Account 1'), { target: { value: account1 } });
  fireEvent.change(screen.getByLabelText('Account 2'), { target: { value: account2 } });
  fireEvent.change(screen.getByLabelText('Journal description'), { target: { value: body.description } });
  fireEvent.change(screen.getByLabelText('Debit RWF 1'), { target: { value: debit } });
  fireEvent.change(screen.getByLabelText('Credit RWF 2'), { target: { value: credit } });
  fireEvent.change(screen.getByLabelText('Reason for draft'), { target: { value: body.reason } });
}
async function review() { fireEvent.click(screen.getByRole('button', { name: 'Review journal draft' })); }
async function confirm() { await screen.findByRole('button', { name: 'Confirm draft' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(screen.getByRole('button', { name: 'Confirm draft' })); }

describe('legacy journal draft creation', () => {
  it('revalidates a fixed group and locks the draft to that group', async () => {
    const request = vi.fn(reader(fixture()));
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} fixedGroupId={group} allowMutations />);
    expect(await screen.findByText(`Group: Savings group · ${group}`)).toBeInTheDocument();
    expect(screen.queryByLabelText('Group')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Search groups'})).not.toBeInTheDocument();
    expect(request).toHaveBeenCalledWith(`operations/groups/${group}`);
    expect(request).toHaveBeenCalledWith(`operations/lookups?kind=accounts&group_id=${group}&search=&limit=100`);
  });
  it('rejects an inactive fixed group before presenting a draft', async () => {
    const data = fixture(); data.group.status = 'suspended';
    const request = vi.fn(reader(data));
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} fixedGroupId={group} allowMutations />);
    expect(await screen.findByText(/could not be verified/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Review journal draft'})).not.toBeInTheDocument();
  });
  it('can check an earlier draft for another group but cannot retry it from a fixed-group page', async () => {
    const key = 'original-other-group', otherGroup = '88888888-8888-4888-8888-888888888888';
    await retainPending(identity, 'operating-createjournal', 'new', key, 'ledger.manage', {...body, group_id: otherGroup});
    const request = vi.fn(async () => ({status: 'not_found'}));
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} fixedGroupId={group} allowMutations />);
    fireEvent.click(await screen.findByRole('button', {name: 'Check request'}));
    expect(await screen.findByText(/Keep the reference and check again/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Review same request'})).not.toBeInTheDocument();
    expect(request).toHaveBeenCalledWith(`operations/requests/${key}`);
  });
  it('defaults to disabled and refuses the canonical evidence model', async () => {
    const request = vi.fn(), view = render(<LegacyJournalCreatePage {...access} request={request} identity={identity} />);
    expect(await screen.findByText(/not enabled/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
    view.rerender(<LegacyJournalCreatePage {...access} request={request} identity={identity} financialModel="canonical_evidence_ledger" allowMutations />);
    expect(screen.getByText(/unavailable for the canonical evidence ledger/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it.each([['unbalanced', '2500', '2499'], ['decimal', '25.5', '25.5'], ['overflow', '9007199254740992', '9007199254740992'], ['zero', '', '']] as const)('rejects %s before review or storage', async (_name, debit, credit) => {
    const request = vi.fn(reader(fixture())); render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    await fill(debit, credit); await review(); expect(await screen.findByText(/No draft was submitted/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Confirm draft' })).not.toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('rejects a balanced total above the exact limit even if each line is valid', async () => {
    const request = vi.fn(reader(fixture())); render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    await fill('9007199254740991', '9007199254740991');
    fireEvent.click(screen.getByRole('button', { name: 'Add entry' })); fireEvent.click(screen.getByRole('button', { name: 'Add entry' }));
    fireEvent.change(screen.getByLabelText('Account 3'), { target: { value: account1 } }); fireEvent.change(screen.getByLabelText('Debit RWF 3'), { target: { value: '1' } });
    fireEvent.change(screen.getByLabelText('Account 4'), { target: { value: account2 } }); fireEvent.change(screen.getByLabelText('Credit RWF 4'), { target: { value: '1' } });
    await review(); expect(await screen.findByText(/No draft was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('rejects a journal line with both sides entered', async () => {
    const request = vi.fn(reader(fixture())); render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    await fill(); fireEvent.change(screen.getByLabelText('Credit RWF 1'), { target: { value: '1' } }); await review();
    expect(await screen.findByText(/No draft was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it.each(['inactive group', 'closed account', 'wrong currency', 'wrong group'] as const)('fails closed for %s', async fault => {
    const data = fixture();
    if (fault === 'inactive group') data.group.status = 'suspended';
    if (fault === 'closed account') data.accounts[0].status = 'closed';
    if (fault === 'wrong currency') data.accounts[0].currency = 'USD';
    if (fault === 'wrong group') data.accounts[0].group_id = journal;
    const request = vi.fn(reader(data)); render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    await fill(); await review(); expect(await screen.findByText(/No draft was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('shows actual accounts and equal totals, then records the exact unallocated draft and verifies scope', async () => {
    const read = reader(fixture()); let key = '';
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === 'operations/journals' && options?.method === 'POST') { key = options.idempotencyKey!; expect(options.body).toEqual(body); expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(body); return receipt; }
      if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: reqId, receipt };
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    await fill(); await review(); expect(await screen.findByText(/Debit total: RWF 2,500 · Credit total: RWF 2,500/)).toBeInTheDocument();
    expect(screen.getByRole('table')).toHaveTextContent('1000 · Cash account'); expect(screen.getByRole('table')).toHaveTextContent('2000 · Member account');
    expect(screen.getByRole('button', { name: 'Confirm draft' })).toBeDisabled(); await confirm();
    expect(await screen.findByText('The journal draft was recorded.')).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('retains the original key after a lost response and retries the exact request only after review', async () => {
    const read = reader(fixture()); let key = '', writes = 0, lookups = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === 'operations/journals' && options?.method === 'POST') {
        writes++; expect(options.body).toEqual(body);
        if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(key); return receipt;
      }
      if (path === `operations/requests/${key}`) { lookups++; return writes < 2 ? { status: 'not_found' } : { status: 'succeeded', request_id: reqId, receipt }; }
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    await fill(); await review(); await confirm(); expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const button = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(button);
    expect(await screen.findByText('The journal draft was recorded.')).toBeInTheDocument(); expect(writes).toBe(2); expect(lookups).toBe(3); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('refuses dispatch if an account changes after review', async () => {
    const data = fixture(), read = reader(data); let groupReads = 0;
    const request = vi.fn(async (path: string) => { if (path === `operations/groups/${group}` && ++groupReads === 2) data.accounts[0].status = 'closed'; return read(path); });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    await fill(); await review(); await confirm(); expect(await screen.findByText(/No draft was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('does not send a second request if the original key succeeds after review', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-createjournal', 'new', key, 'ledger.manage', body);
    const read = reader(fixture()); let checks = 0;
    const request = vi.fn(async (path: string) => {
      if (path === `operations/requests/${key}`) return ++checks === 1 ? { status: 'not_found' } : { status: 'succeeded', request_id: reqId, receipt };
      if (path === 'operations/requests?limit=100&offset=0') return history(key);
      return read(path);
    });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const button = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(button);
    expect(await screen.findByText('The original journal draft request was recorded.')).toBeInTheDocument();
    expect(request.mock.calls.some(([path]) => path === 'operations/journals')).toBe(false); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('fences an in-flight review when the write gate closes', async () => {
    const read = reader(fixture()); let release: (() => void) | undefined;
    const request = vi.fn(async (path: string) => { if (path === `operations/groups/${group}`) await new Promise<void>(resolve => { release = resolve; }); return read(path); });
    const view = render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    await fill(); await review(); expect(release).toBeDefined(); view.rerender(<LegacyJournalCreatePage {...access} request={request} identity={identity} />); release!();
    expect(await screen.findByText(/not enabled/i)).toBeInTheDocument(); expect(screen.queryByRole('button', { name: 'Confirm draft' })).not.toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('checks an allocation-linked Flutter request but refuses to recreate it', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-createjournal', 'new', key, 'ledger.manage', { ...body, allocation_id: allocation });
    const request = vi.fn(async (path: string) => { expect(path).toBe(`operations/requests/${key}`); return { status: 'not_found' }; });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText(/Return to the original transaction allocation/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Review same request' })).not.toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
  });
  it('recovers an allocation-linked receipt with writes disabled', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-createjournal', 'new', key, 'ledger.manage', { ...body, allocation_id: allocation });
    const request = vi.fn(async (path: string) => { if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: reqId, receipt }; if (path === 'operations/requests?limit=100&offset=0') return history(key); throw new Error('Unexpected'); });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} />); fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original journal draft request was recorded.')).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('does not accept a receipt with another action scope', async () => {
    const key = '12345678-original'; await retainPending(identity, 'operating-createjournal', 'new', key, 'ledger.manage', body);
    const request = vi.fn(async (path: string) => { if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: reqId, receipt }; if (path === 'operations/requests?limit=100&offset=0') return history(key, 'journals.post.post'); throw new Error('Unexpected'); });
    render(<LegacyJournalCreatePage {...access} request={request} identity={identity} />); fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText(/original request could not be verified/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
  });
  it('does not submit if the browser lock is unavailable', async () => {
    Object.defineProperty(navigator, 'locks', { value: undefined, configurable: true });
    const request = vi.fn(reader(fixture())); render(<LegacyJournalCreatePage {...access} request={request} identity={identity} allowMutations />);
    await fill(); await review(); await confirm(); expect(await screen.findByText(/No draft was submitted/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
