import {render, screen} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import type {AdminRequest, AdminRequestOptions} from '../../src/api/client';
import {readPending, retainPending, sha256Text, type PendingIdentity} from '../../src/features/core/pendingAttempt';
import {checkCreate, checkOldCreate, loadCreateTargets, oldCreateAttempt, restoreCreate, retryCreate, submitCreate, type CreateContext} from '../../src/features/legacy-transactions/create';
import {LegacyTransactionCreate} from '../../src/features/legacy-transactions';

const actor = '11111111-1111-4111-8111-111111111111', group = '22222222-2222-4222-8222-222222222222', payee = '33333333-3333-4333-8333-333333333333', transaction = '44444444-4444-4444-8444-444444444444', evidenceId = '55555555-5555-4555-8555-555555555555', key = '66666666-6666-4666-8666-666666666666', requestId = '77777777-7777-4777-8777-777777777777';
const reason = 'Record inspected payment evidence', digest = 'a'.repeat(64), observed = '2026-10-04T12:00:00Z', time = Date.parse(observed) / 1000, originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
const body = {group_id: group, payee_id: payee, expected_group_version: 4, expected_payee_version: 3, provider_reference: 'PRIVATE-SYNTHETIC-REFERENCE', amount_rwf: 2500, observed_at: time, evidence: {kind: 'receiver_statement', reference: 'Private evidence label', sha256: digest}, reason};
const receipt = {request_id: requestId, resource_type: 'transactions', resource_id: transaction, version: 1, status: 'succeeded'};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.test', role: 'admin', permissions: ['collections.read', 'receivers.read', 'payments.read', 'payments.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function ctx(request: AdminRequest): CreateContext {const user = identity(); return {request, identity: user, permissions: user.permissions, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
function details(type: 'groups' | 'payees', version?: number) {
  const resource = type === 'groups' ? {id: group, title: 'Synthetic group', status: 'active', country_code: 'RW', currency: 'RWF', version: version ?? 4} : {id: payee, group_id: group, label: 'Synthetic receiver', status: 'active', network: 'mtn_momo', momo_number_or_code: '123456', version: version ?? 3};
  return {resource_type: type, resource, current_actor_id: actor, can_manage: true, related: {}, related_pages: {}, related_truncated: false};
}
function transactionDetails() {
  const source = {id: transaction, group_id: group, payee_id: payee, network: 'mtn_momo', payee_momo_number_or_code: '123456', provider_reference: body.provider_reference, amount_rwf: body.amount_rwf, observed_at: time, verification_status: 'pending', version: 1, recorded_by_admin_id: actor, reference_source_fact_id: null, currency: 'RWF', provider_confirmation: false, settlement_status: 'not_asserted'};
  const item = {id: evidenceId, kind: body.evidence.kind, reference: body.evidence.reference, sha256: digest, recorded_by_admin_id: actor, recorded_at: time};
  return {resource_type: 'transactions', resource: source, current_actor_id: actor, can_manage: true, related: {evidence: [item]}, related_pages: {evidence: {total: 1, limit: 100, offset: 0, next_offset: null}}, related_truncated: false};
}
function requestFor(onPost: (options?: AdminRequestOptions) => Promise<Record<string, unknown>> = async () => receipt) {
  return vi.fn(async (path: string, options?: AdminRequestOptions): Promise<Record<string, unknown>> => {
    if (path.startsWith('operations/lookups?kind=groups')) return {rows: [{id: group, label: 'Synthetic group', version: 4}]};
    if (path.startsWith('operations/lookups?kind=payees')) return {rows: [{id: payee, label: 'Synthetic receiver', version: 3, network: 'mtn_momo'}]};
    if (path === `operations/groups/${group}`) return details('groups');
    if (path === `operations/payees/${payee}`) return details('payees');
    if (path === 'operations/transactions') return onPost(options);
    if (path === `operations/transactions/${transaction}?relation=evidence&limit=100&offset=0`) return transactionDetails();
    if (path === `operations/requests/${key}`) return {status: 'succeeded', request_id: requestId, receipt};
    if (path === 'operations/requests?limit=100&offset=0') return {total: 1, rows: [{id: requestId, idempotency_key: key, scope: 'transactions.post', status: 'succeeded', receipt}]};
    throw new Error(`Unexpected synthetic request ${path}`);
  });
}
async function revision(context: CreateContext) {const value = await restoreCreate(context); if (value.kind !== 'ready') throw new Error('Expected clear checkpoint'); return value.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, task: (lock: {name: string}) => Promise<unknown>) => task({name})}});});
afterEach(() => {if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('Guarded legacy payment evidence creation', () => {
  it('requires explicit enablement, legacy model, current authority and the required grants', async () => {
    const request = requestFor(), context = ctx(request), targets = await loadCreateTargets(context, group, payee); request.mockClear();
    await expect(submitCreate({...context, enabled: false}, body, targets, '')).rejects.toThrow(/not enabled/);
    await expect(submitCreate({...context, financialModel: 'canonical_evidence_ledger'}, body, targets, '')).rejects.toThrow(/unavailable/);
    await expect(submitCreate({...context, identity: {...context.identity, role: 'staff'}}, body, targets, '')).rejects.toThrow(/unavailable/);
    await expect(submitCreate({...context, permissions: ['payments.manage']}, body, targets, '')).rejects.toThrow(/unavailable/);
    await expect(submitCreate({...context, isCurrent: () => false}, body, targets, '')).rejects.toThrow(/unavailable/); expect(request).not.toHaveBeenCalled();
  });
  it('posts both reviewed versions and persists only identifiers, versions and digests until the actor-scoped receipt is verified', async () => {
    const request = requestFor(async options => {
      expect(options).toEqual({method: 'POST', body, idempotencyKey: key});
      const stored = await readPending(identity(), 'legacy-guarded-transaction-create', 'new');
      expect(stored).toMatchObject({request_key: key, intent: {group_id: group, payee_id: payee, expected_group_version: 4, expected_payee_version: 3, evidence_sha256: digest, request_sha256: await sha256Text(JSON.stringify(body))}});
      const serialized = sessionStorage.getItem('collect.admin.pending-attempts.v1') ?? '';
      expect(serialized).not.toContain(reason); expect(serialized).not.toContain(body.provider_reference); expect(serialized).not.toContain(body.evidence.reference); return receipt;
    });
    const context = ctx(request), targets = await loadCreateTargets(context, group, payee);
    expect(await submitCreate(context, body, targets, await revision(context))).toEqual({status: 'succeeded', receipt});
    expect(await readPending(identity(), 'legacy-guarded-transaction-create', 'new')).toBeNull();
  });
  it('recovers a lost response with the same key only after exact private details are re-entered', async () => {
    let sends = 0, recorded = false; const request = requestFor(async options => {sends++; expect(options).toEqual({method: 'POST', body, idempotencyKey: key}); if (sends === 1) throw new Error('Lost'); recorded = true; return receipt;});
    const original = request.getMockImplementation()!; request.mockImplementation(async (path, options) => path === `operations/requests/${key}` && !recorded ? {status: 'not_found'} : original(path, options));
    const context = ctx(request), targets = await loadCreateTargets(context, group, payee);
    expect(await submitCreate(context, body, targets, await revision(context))).toEqual({status: 'unknown', requestKey: key}); const pending = await restoreCreate(context);
    expect(await checkCreate(context, pending)).toEqual({status: 'not_found', retryAvailable: true});
    await expect(retryCreate(context, pending, {...body, reason: 'Different private reason'}, targets)).rejects.toThrow(/does not match/);
    expect((await retryCreate(context, pending, body, targets)).status).toBe('succeeded'); expect(sends).toBe(2);
  });
  it('does not dispatch or retry after a group or receiver version changes', async () => {
    const request = requestFor(async () => {throw new Error('Lost');}), context = ctx(request), targets = await loadCreateTargets(context, group, payee), observed = await revision(context);
    const original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => path === `operations/groups/${group}` ? details('groups', 5) : original(path, options));
    await expect(submitCreate(context, body, targets, observed)).rejects.toThrow(/changed/); expect(request.mock.calls.some(([path]) => path === 'operations/transactions')).toBe(false);
    request.mockImplementation(original); await submitCreate(context, body, targets, observed); const pending = await restoreCreate(context);
    request.mockImplementation(async (path, options) => path === `operations/requests/${key}` ? {status: 'not_found'} : path === `operations/payees/${payee}` ? details('payees', 4) : original(path, options));
    await expect(retryCreate(context, pending, body, targets)).rejects.toThrow(/changed/); expect(request.mock.calls.filter(([path]) => path === 'operations/transactions')).toHaveLength(1);
  });
  it('blocks guarded creation when a same-tab Flutter request exists and permits only lookup of that old key', async () => {
    await retainPending(identity(), 'operating-createtransaction', 'new', key, 'payments.manage', {reason: 'Earlier payment evidence'});
    const request = requestFor(), context = ctx(request), old = await oldCreateAttempt(context), targets = await loadCreateTargets(context, group, payee);
    expect(old.saved?.request_key).toBe(key); expect((await checkOldCreate(context, old.saved!)).status).toBe('succeeded');
    await expect(submitCreate(context, body, targets, await revision(context))).rejects.toThrow(/earlier payment request/);
    expect(await readPending(identity(), 'operating-createtransaction', 'new')).not.toBeNull(); expect(request.mock.calls.some(([path]) => path === 'operations/transactions')).toBe(false);
  });
  it('does not clear an original receipt for a different action or mismatched receiving scope', async () => {
    const request = requestFor(async () => {throw new Error('Lost');}), context = ctx(request), targets = await loadCreateTargets(context, group, payee);
    await submitCreate(context, body, targets, await revision(context)); const pending = await restoreCreate(context), original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => path === 'operations/requests?limit=100&offset=0' ? {total: 1, rows: [{id: requestId, idempotency_key: key, scope: 'transactions.post.evidence', status: 'succeeded', receipt}]} : original(path, options));
    await expect(checkCreate(context, pending)).rejects.toThrow(); expect((await restoreCreate(context)).kind).toBe('owned');
    request.mockImplementation(async (path, options) => path.includes(`operations/transactions/${transaction}?relation=evidence`) ? {...transactionDetails(), resource: {...transactionDetails().resource, payee_id: group}} : original(path, options));
    await expect(checkCreate(context, pending)).rejects.toThrow(/payment evidence/); expect((await restoreCreate(context)).kind).toBe('owned');
  });
  it('retains the key without dispatch when the gate closes during checkpoint retention', async () => {
    let enabled = true; const storage: Storage = {get length() {return sessionStorage.length;}, clear: () => sessionStorage.clear(), key: index => sessionStorage.key(index), getItem: name => sessionStorage.getItem(name), removeItem: name => sessionStorage.removeItem(name), setItem: (name, value) => {sessionStorage.setItem(name, value); enabled = false;}};
    const request = requestFor(), context = {...ctx(request), storage, isEnabled: () => enabled}, targets = await loadCreateTargets(context, group, payee);
    expect(await submitCreate(context, body, targets, await revision(context))).toEqual({status: 'unknown', requestKey: key});
    expect(await readPending(identity(), 'legacy-guarded-transaction-create', 'new')).toMatchObject({request_key: key}); expect(request.mock.calls.some(([path]) => path === 'operations/transactions')).toBe(false);
  });
});

describe('Guarded payment evidence form', () => {
  it('does not expose recording by default', async () => {
    const authority = identity(), request = requestFor(); render(<LegacyTransactionCreate request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="epoch-1" isCurrent={() => true} onCreated={() => undefined} />);
    expect(await screen.findByText('Payment recording is not enabled for this workspace.')).toBeVisible(); expect(screen.queryByRole('button', {name: 'Find groups'})).not.toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('does not expose a stale group search after the authority epoch changes', async () => {
    const user = userEvent.setup(), authority = identity(), request = requestFor(); let finish!: (value: Record<string, unknown>) => void;
    request.mockImplementation(async path => path.startsWith('operations/lookups?kind=groups') ? new Promise(resolve => {finish = resolve;}) : {});
    const view = render(<LegacyTransactionCreate request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="epoch-1" isCurrent={() => true} allowMutations onCreated={() => undefined} />);
    await user.click(await screen.findByRole('button', {name: 'Find groups'}));
    view.rerender(<LegacyTransactionCreate request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="epoch-2" isCurrent={() => true} allowMutations onCreated={() => undefined} />);
    finish({rows: [{id: group, label: 'Synthetic group', version: 4}]});
    await new Promise(resolve => setTimeout(resolve, 0)); expect(screen.queryByLabelText('Group')).not.toBeInTheDocument();
  });
  it('requires reviewed receiver scope and explicit confirmation before guarded creation', async () => {
    const user = userEvent.setup(), authority = identity(), request = requestFor(), created = vi.fn(); let generatedKey = '';
    const original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => {
      if (path === 'operations/transactions' && options?.method === 'POST') {generatedKey = options.idempotencyKey ?? ''; expect(options.body).toEqual(body); return receipt;}
      if (path === `operations/requests/${generatedKey}`) return {status: 'succeeded', request_id: requestId, receipt};
      if (path === 'operations/requests?limit=100&offset=0') return {total: 1, rows: [{id: requestId, idempotency_key: generatedKey, scope: 'transactions.post', status: 'succeeded', receipt}]};
      return original(path, options);
    });
    render(<LegacyTransactionCreate request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="epoch-1" isCurrent={() => true} allowMutations onCreated={created} />);
    await user.click(await screen.findByRole('button', {name: 'Find groups'})); await user.selectOptions(await screen.findByLabelText('Group'), group); await user.click(screen.getByRole('button', {name: 'Find receivers'})); await user.selectOptions(await screen.findByLabelText('Receiver'), payee);
    await user.type(screen.getByLabelText('Provider reference'), body.provider_reference); await user.type(screen.getByLabelText('Payment amount (RWF)'), '2500'); await user.type(screen.getByLabelText('Observed at (UTC)'), observed);
    await user.selectOptions(screen.getByLabelText('Evidence type'), 'receiver_statement'); await user.type(screen.getByLabelText('Evidence reference'), body.evidence.reference); await user.type(screen.getByLabelText('Evidence SHA-256'), digest); await user.type(screen.getByLabelText('Reason'), reason);
    await user.click(screen.getByRole('button', {name: 'Review payment evidence'})); expect(await screen.findByText(new RegExp(`Synthetic receiver.*${payee}`))).toBeVisible(); expect(screen.getByRole('button', {name: 'Confirm payment evidence'})).toBeDisabled();
    expect(request.mock.calls.some(([path, options]) => path === 'operations/transactions' && options?.method === 'POST')).toBe(false);
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the payment, receiving account, evidence and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm payment evidence'}));
    expect(await screen.findByText(`Payment evidence recorded. Reference ${requestId}.`)).toBeVisible(); expect(created).toHaveBeenCalledWith(transaction);
  });
  it('requires exact re-entry after a lost result before allowing the same-key retry', async () => {
    await retainPending(identity(), 'legacy-guarded-transaction-create', 'new', key, 'payments.manage', {group_id: group, payee_id: payee, expected_group_version: 4, expected_payee_version: 3, evidence_sha256: digest, request_sha256: await sha256Text(JSON.stringify(body))});
    const user = userEvent.setup(), authority = identity(), request = requestFor(), created = vi.fn(); let posted = false;
    const original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => {
      if (path === `operations/requests/${key}` && !posted) return {status: 'not_found'};
      if (path === 'operations/transactions' && options?.method === 'POST') {expect(options).toEqual({method: 'POST', body, idempotencyKey: key}); posted = true; return receipt;}
      return original(path, options);
    });
    render(<LegacyTransactionCreate request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="epoch-1" isCurrent={() => true} allowMutations onCreated={created} />);
    await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    expect(await screen.findByText('No receipt was found. Re-enter the original payment details, evidence and reason to review the same request.')).toBeVisible();
    expect(screen.getByLabelText('Provider reference')).toHaveValue(''); expect(screen.getByLabelText('Evidence reference')).toHaveValue(''); expect(screen.getByLabelText('Reason')).toHaveValue('');
    await user.type(screen.getByLabelText('Provider reference'), body.provider_reference); await user.type(screen.getByLabelText('Payment amount (RWF)'), '2500'); await user.type(screen.getByLabelText('Observed at (UTC)'), observed);
    await user.selectOptions(screen.getByLabelText('Evidence type'), 'receiver_statement'); await user.type(screen.getByLabelText('Evidence reference'), body.evidence.reference); await user.type(screen.getByLabelText('Reason'), 'An incorrect review reason');
    await user.click(screen.getByRole('button', {name: 'Review payment evidence'})); expect(await screen.findByText(/A retry must match the original request/)).toBeVisible(); expect(posted).toBe(false);
    await user.clear(screen.getByLabelText('Reason')); await user.type(screen.getByLabelText('Reason'), reason); await user.click(screen.getByRole('button', {name: 'Review payment evidence'}));
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the payment, receiving account, evidence and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm same request'}));
    expect(await screen.findByText(`Payment evidence recorded. Reference ${requestId}.`)).toBeVisible(); expect(created).toHaveBeenCalledWith(transaction);
  });
});
