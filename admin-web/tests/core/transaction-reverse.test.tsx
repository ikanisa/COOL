import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './canonical-reconciliation-fixture.json';
import { TransactionReversePage } from '../../src/features/core/TransactionReversePage';
import { canonicalRequestId, PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actorId = fixture.after.current_actor_id, principalId = fixture.after.current_principal_id, transaction = fixture.after.resource;
const entry = fixture.after.related.ledger_entries.rows[0], keyValue = '44444444-4444-4444-8444-444444444444';
const identity: PendingIdentity = { id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'admin',
  permissions: ['payments.read', 'payments.reconcile', 'ledger.read', 'overview.read', 'account.manage'], expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId, principalId, role: 'admin', authorityKey: 'authority-1', permissions: identity.permissions,
  financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
const detail = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'transactions', resource: transaction,
  current_actor_id: actorId, can_manage: true, allowed_operations: ['reverseTransaction'], related: { ledger_entries: [entry] },
  related_pages: { ledger_entries: { total: 1, limit: 100, offset: 0, next_offset: null } }, related_truncated: false };
const body = { expected_version: transaction.version, reason: 'Reverse reviewed contribution' };
beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  Object.defineProperty(navigator, 'locks', { value: { request: async (_name: string, _options: unknown, callback: (lock: object) => unknown) => callback({}) }, configurable: true });
  sessionStorage.clear();
});
async function fill() {
  fireEvent.change(await screen.findByLabelText('Reason for reversal'), { target: { value: body.reason } });
  fireEvent.click(screen.getByRole('button', { name: 'Review reversal' }));
  fireEvent.click(screen.getByRole('checkbox'));
}

describe('canonical contribution reversal', () => {
  it('keeps reversal off unless explicitly enabled', async () => {
    const request = vi.fn();
    render(<TransactionReversePage {...access} request={request} id={transaction.id} identity={identity} verifyFresh={async () => true} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('not enabled'); expect(request).not.toHaveBeenCalled();
  });
  it('retains a lost reversal and retries only the exact original key after review and renewed lookup', async () => {
    let key = '', writes = 0, lookups = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path.startsWith(`operations/transactions/${transaction.id}?`)) return detail;
      if (path === `operations/requests/${key}`) { lookups++; return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' }; }
      if (path === `operations/transactions/${transaction.id}/reverse` && options?.method === 'POST') {
        writes++; expect(options.body).toEqual(body); expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(body);
        if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(key);
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, key), resource_type: 'transactions', resource_id: transaction.id, version: transaction.version + 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<TransactionReversePage {...access} request={request} id={transaction.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); expect(screen.getByText(/does not refund or move provider funds/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Confirm reversal' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(writes).toBe(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const confirm = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(confirm);
    expect(await screen.findByText('The contribution reversal was recorded.')).toBeInTheDocument(); expect(writes).toBe(2); expect(lookups).toBe(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('refuses a changed contribution even if the transaction version is unchanged', async () => {
    let reads = 0;
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path.startsWith(`operations/transactions/${transaction.id}?`) && !options?.method) { reads++; return reads === 1 ? detail : { ...detail, related: { ledger_entries: [{ ...entry, signed_amount_rwf: 1000, amount_rwf: 1000, amount: '1000' }] } }; }
      throw new Error('Unexpected mutation');
    });
    render(<TransactionReversePage {...access} request={request} id={transaction.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm reversal' }));
    expect(await screen.findByText(/No reversal was submitted/i)).toBeInTheDocument();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('does not submit without a browser lock', async () => {
    Object.defineProperty(navigator, 'locks', { value: undefined, configurable: true });
    const request = vi.fn(async () => detail);
    render(<TransactionReversePage {...access} request={request} id={transaction.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm reversal' }));
    expect(await screen.findByText(/No reversal was submitted/i)).toBeInTheDocument(); expect(request).toHaveBeenCalledTimes(1);
  });
  it('does not replay when the original reversal completes before confirmation', async () => {
    await retainPending(identity, 'operating-reversetransaction', transaction.id, keyValue, 'payments.reconcile', body);
    let lookups = 0, writes = 0;
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path.startsWith(`operations/transactions/${transaction.id}?`)) return detail;
      if (path === `operations/requests/${keyValue}`) {
        lookups++;
        if (lookups === 1) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
        const requestId = await canonicalRequestId(principalId, keyValue);
        return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
          receipt: { status: 'succeeded', request_id: requestId, resource_type: 'transactions', resource_id: transaction.id, version: transaction.version + 1 } };
      }
      if (options?.method === 'POST') { writes++; throw new Error('Unexpected replay'); }
      throw new Error('Unexpected request');
    });
    render(<TransactionReversePage {...access} request={request} id={transaction.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const confirm = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(confirm);
    expect(await screen.findByText('The original contribution reversal was recorded.')).toBeInTheDocument();
    expect(writes).toBe(0); expect(lookups).toBe(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('keeps the original reference if lookup returns an unrelated receipt', async () => {
    await retainPending(identity, 'operating-reversetransaction', transaction.id, keyValue, 'payments.reconcile', body);
    const request = vi.fn(async () => { const requestId = await canonicalRequestId(principalId, keyValue);
      return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
        receipt: { status: 'succeeded', request_id: requestId, resource_type: 'transactions', resource_id: '99999999-9999-4999-8999-999999999999', version: transaction.version + 1 } }; });
    render(<TransactionReversePage {...access} request={request} id={transaction.id} identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText(/original request could not be verified/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
  });
  it('checks a completed original reversal without ledger-read access or opening the changed transaction', async () => {
    const limited = { ...identity, permissions: identity.permissions.filter(permission => permission !== 'ledger.read') };
    await retainPending(limited, 'operating-reversetransaction', transaction.id, keyValue, 'payments.reconcile', body);
    const request = vi.fn(async (path: string) => {
      expect(path).toBe(`operations/requests/${keyValue}`); const requestId = await canonicalRequestId(principalId, keyValue);
      return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
        receipt: { status: 'succeeded', request_id: requestId, resource_type: 'transactions', resource_id: transaction.id, version: transaction.version + 1 } };
    });
    render(<TransactionReversePage {...access} permissions={limited.permissions} request={request} id={transaction.id} identity={limited} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original contribution reversal was recorded.')).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
