import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './canonical-core-fixtures.json';
import { TransactionEvidencePage } from '../../src/features/core';
import { canonicalRequestId, EVIDENCE_CONTEXT_KEY, PENDING_KEY, retainPending, sha256Text } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actorId = '11111111-1111-4111-8111-111111111111', principalId = '22222222-2222-4222-8222-222222222222';
const transactionId = '33333333-3333-4333-8333-333333333333', group = fixture.groups.rows[0], receiver = fixture.payees.rows[0];
const identity: PendingIdentity = { id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'admin',
  permissions: ['payments.read', 'payments.manage', 'payments.write', 'collections.read', 'receivers.read', 'overview.read', 'account.manage'], expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId, principalId, role: 'admin', authorityKey: 'authority-1', permissions: identity.permissions,
  financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
const groupLookup = { contract_version: 2, model: 'canonical_evidence_ledger', kind: 'groups', group_id: null, rows: [{ ...group, label: group.title, name: group.title }], total: 1 };
const receiverLookup = { contract_version: 2, model: 'canonical_evidence_ledger', kind: 'payees', group_id: group.id, rows: [{ ...receiver, label: receiver.title, name: receiver.title }], total: 1 };
const groupDetail = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'groups', resource: group, current_actor_id: actorId, can_manage: true, allowed_operations: ['createTransaction'] };
const receiverDetail = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'payees', resource: receiver, current_actor_id: actorId };
const evidence = 'Synthetic operator evidence, retained exactly for this test.';
const body = { group_id: group.id, payee_id: group.id, provider_reference: 'receipt-123', amount_rwf: 1500, observed_at: '2026-01-15T12:00:00.000Z', payer_name: 'Recorded payer', evidence, reason: 'Record reviewed evidence' };

beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  Object.defineProperty(navigator, 'locks', { value: { request: async (_name: string, _options: unknown, callback: (lock: object) => unknown) => callback({}) }, configurable: true });
  sessionStorage.clear();
});
async function fill(amount = '1500') {
  fireEvent.change(await screen.findByLabelText('Search groups'), { target: { value: 'Controlled' } });
  fireEvent.click(screen.getByRole('button', { name: 'Find groups' }));
  fireEvent.change(await screen.findByLabelText('Group'), { target: { value: group.id } });
  await screen.findByText(/Recorded receiver:/i);
  fireEvent.change(screen.getByLabelText('Evidence reference'), { target: { value: body.provider_reference } });
  fireEvent.change(screen.getByLabelText('Recorded amount (RWF)'), { target: { value: amount } });
  fireEvent.change(screen.getByLabelText('Observed at (UTC)'), { target: { value: '2026-01-15T12:00:00Z' } });
  fireEvent.change(screen.getByLabelText('Recorded payer name'), { target: { value: body.payer_name } });
  fireEvent.change(screen.getByLabelText('Exact evidence text'), { target: { value: evidence } });
  fireEvent.change(screen.getByLabelText('Reason for recording'), { target: { value: body.reason } });
  fireEvent.click(screen.getByRole('button', { name: 'Review evidence' }));
}
function baseRead(path: string): Record<string, unknown> | null {
  if (path.startsWith('operations/lookups?kind=groups')) return groupLookup;
  if (path.startsWith('operations/lookups?kind=payees')) return receiverLookup;
  if (path === `operations/groups/${group.id}`) return groupDetail;
  if (path === `operations/payees/${group.id}`) return receiverDetail;
  return null;
}

describe('canonical payment evidence recording', () => {
  it('defaults off and requires the additional bridge payment-write permission', async () => {
    const request = vi.fn();
    const view = render(<TransactionEvidencePage {...access} request={request} identity={identity} verifyFresh={async () => true} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('not enabled'); expect(request).not.toHaveBeenCalled();
    const limited = { ...identity, permissions: identity.permissions.filter(permission => permission !== 'payments.write') };
    view.rerender(<TransactionEvidencePage {...access} permissions={limited.permissions} request={request} identity={limited} allowMutations verifyFresh={async () => true} />);
    expect(await screen.findByText(/requires the payment-write/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('retains only a digest, requires exact re-entry, and retries the original key with the same body', async () => {
    let key = '', writes = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      const read = baseRead(path); if (read) return read;
      if (path === `operations/requests/${key}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      if (path === 'operations/transactions' && options?.method === 'POST') {
        writes++; expect(options.body).toEqual(body);
        const stored = sessionStorage.getItem(PENDING_KEY)!, context = sessionStorage.getItem(EVIDENCE_CONTEXT_KEY)!;
        expect(stored).not.toContain(evidence); expect(context).not.toContain(evidence); expect(context).not.toContain(receiver.momo_number_or_code);
        expect(JSON.parse(stored).entries[0].intent.evidence.sha256).toBe(await sha256Text(evidence));
        if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(key);
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, key), resource_type: 'transactions', resource_id: transactionId, version: 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<TransactionEvidencePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(screen.getByRole('button', { name: 'Confirm evidence' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(writes).toBe(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' }));
    fireEvent.change(await screen.findByLabelText('Re-enter original evidence text'), { target: { value: 'Different evidence text' } });
    fireEvent.click(screen.getByRole('button', { name: 'Review same request' }));
    expect(await screen.findByText(/exact original evidence and its recorded receiver could not be verified/i)).toBeInTheDocument(); expect(writes).toBe(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' }));
    fireEvent.change(await screen.findByLabelText('Re-enter original evidence text'), { target: { value: evidence } });
    fireEvent.click(screen.getByRole('button', { name: 'Review same request' }));
    const confirm = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(confirm);
    expect(await screen.findByText(/The evidence was recorded. Provider settlement is not asserted/i)).toBeInTheDocument();
    expect(writes).toBe(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull(); expect(sessionStorage.getItem(EVIDENCE_CONTEXT_KEY)).toBeNull();
  });
  it('rejects an amount outside exact integer range before review', async () => {
    const request = vi.fn(async (path: string) => { const data = baseRead(path); if (data) return data; throw new Error('Unexpected request'); });
    render(<TransactionEvidencePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill('9007199254740992'); expect(screen.getByRole('alert')).toHaveTextContent('exact whole RWF amount');
    expect(screen.queryByRole('button', { name: 'Confirm evidence' })).not.toBeInTheDocument();
  });
  it('does not send if the selected recorded receiver changes before confirmation', async () => {
    const changed = { ...receiver, amount: '250788123459', momo_number: '250788123459', momo_number_or_code: '250788123459' };
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path === `operations/payees/${group.id}`) return { ...receiverDetail, resource: changed };
      const data = baseRead(path); if (data) return data;
      if (options?.method === 'POST') throw new Error('Unexpected mutation');
      throw new Error('Unexpected request');
    });
    render(<TransactionEvidencePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(screen.getByRole('button', { name: 'Confirm evidence' }));
    expect(await screen.findByText(/No evidence was submitted/i)).toBeInTheDocument();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('does not replay when the original request completes between review and retry', async () => {
    let key = '', lookups = 0, writes = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; idempotencyKey?: string }) => {
      const read = baseRead(path); if (read) return read;
      if (path === `operations/requests/${key}`) {
        lookups++;
        if (lookups === 1) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
        const requestId = await canonicalRequestId(principalId, key);
        return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
          receipt: { status: 'succeeded', request_id: requestId, resource_type: 'transactions', resource_id: transactionId, version: 1 } };
      }
      if (path === 'operations/transactions' && options?.method === 'POST') { writes++; key = options.idempotencyKey!; throw new Error('Lost response'); }
      throw new Error('Unexpected request');
    });
    render(<TransactionEvidencePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(screen.getByRole('button', { name: 'Confirm evidence' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Check request' }));
    fireEvent.change(await screen.findByLabelText('Re-enter original evidence text'), { target: { value: evidence } });
    fireEvent.click(screen.getByRole('button', { name: 'Review same request' }));
    const confirm = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(confirm);
    expect(await screen.findByText(/original evidence was recorded/i)).toBeInTheDocument();
    expect(writes).toBe(1); expect(lookups).toBe(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull(); expect(sessionStorage.getItem(EVIDENCE_CONTEXT_KEY)).toBeNull();
  });
  it('does not send without a browser lock', async () => {
    Object.defineProperty(navigator, 'locks', { value: undefined, configurable: true });
    const request = vi.fn(async (path: string) => { const data = baseRead(path); if (data) return data; throw new Error('Unexpected mutation'); });
    render(<TransactionEvidencePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(screen.getByRole('button', { name: 'Confirm evidence' }));
    expect(await screen.findByText(/No evidence was submitted/i)).toBeInTheDocument();
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull(); expect(sessionStorage.getItem(EVIDENCE_CONTEXT_KEY)).toBeNull();
  });
  it('allows status lookup for old Flutter recovery but cannot retry without original receiver context', async () => {
    const key = '44444444-4444-4444-8444-444444444444';
    const retained = { ...body, evidence: { kind: 'retained_operator_text', reference: 'Exact text must be re-entered to retry after reloading', sha256: await sha256Text(evidence) } };
    await retainPending(identity, 'operating-createtransaction', 'new', key, 'payments.manage', retained);
    const request = vi.fn(async (path: string) => { expect(path).toBe(`operations/requests/${key}`); return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' }; });
    render(<TransactionEvidencePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText(/original receiver context is unavailable/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Review same request' })).not.toBeInTheDocument(); expect(request).toHaveBeenCalledTimes(1);
  });
  it('does not attempt request-history lookup without the backend account-management permission', async () => {
    const limited = { ...identity, permissions: identity.permissions.filter(permission => permission !== 'account.manage') };
    const key = '44444444-4444-4444-8444-444444444444';
    await retainPending(limited, 'operating-createtransaction', 'new', key, 'payments.manage', { ...body, evidence: { kind: 'retained_operator_text', reference: 'Exact text must be re-entered to retry after reloading', sha256: await sha256Text(evidence) } });
    const request = vi.fn();
    render(<TransactionEvidencePage {...access} permissions={limited.permissions} request={request} identity={limited} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText(/Your account cannot check request history/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('clears a matching completed old request while writes remain disabled', async () => {
    const key = '44444444-4444-4444-8444-444444444444';
    await retainPending(identity, 'operating-createtransaction', 'new', key, 'payments.manage', { ...body, evidence: { kind: 'retained_operator_text', reference: 'Exact text must be re-entered to retry after reloading', sha256: await sha256Text(evidence) } });
    const request = vi.fn(async (path: string) => { expect(path).toBe(`operations/requests/${key}`); const requestId = await canonicalRequestId(principalId, key); return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
      receipt: { status: 'succeeded', request_id: requestId, resource_type: 'transactions', resource_id: transactionId, version: 1 } }; });
    render(<TransactionEvidencePage {...access} request={request} identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText(/original evidence was recorded/i)).toBeInTheDocument(); await waitFor(() => expect(sessionStorage.getItem(PENDING_KEY)).toBeNull());
  });
});
