import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './canonical-core-fixtures.json';
import { PayeeEditPage } from '../../src/features/core';
import { canonicalRequestId, PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';

const actorId = '11111111-1111-4111-8111-111111111111', principalId = '22222222-2222-4222-8222-222222222222';
const payee = fixture.payees.rows[0];
const identity: PendingIdentity = { id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'admin',
  permissions: ['receivers.read', 'receivers.manage', 'overview.read', 'account.manage'], expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId, principalId, role: 'admin', authorityKey: 'authority-1',
  permissions: identity.permissions, financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
const detail = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'payees',
  resource: { ...payee, label: payee.title, group_title: payee.group_name }, current_actor_id: actorId, can_manage: true, allowed_operations: ['updatePayee'], related: {}, related_pages: {}, related_truncated: false };
const original = { label: 'Updated receiver', network: 'mtn_momo', momo_number_or_code: '0788123459', status: 'active', reason: 'Correct recorded receiver', expected_version: payee.version };

beforeEach(() => { Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true }); sessionStorage.clear(); });
async function fillReceiver() {
  fireEvent.change(await screen.findByLabelText('Recorded receiver name'), { target: { value: original.label } });
  fireEvent.change(screen.getByLabelText('Receiver MoMo number'), { target: { value: original.momo_number_or_code } });
  fireEvent.change(screen.getByLabelText('Reason for change'), { target: { value: original.reason } });
  fireEvent.click(screen.getByRole('button', { name: 'Review receiver' }));
}

describe('canonical receiver editing', () => {
  it('does not fetch or send a write with the gate disabled', async () => {
    const request = vi.fn();
    render(<PayeeEditPage {...access} request={request} id={payee.id} identity={identity} verifyFresh={async () => true} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('not enabled');
    expect(request).not.toHaveBeenCalled();
  });
  it('retains an unknown outcome and retries the same reviewed key only after lookup', async () => {
    let key = '', count = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/payees/${payee.id}` && !options?.method) return detail;
      if (path === `operations/requests/${key}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      if (options?.method === 'PATCH') {
        count++; expect(options.body).toEqual(original);
        expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(original);
        if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(key);
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, key), resource_type: 'payees', resource_id: payee.id, version: payee.version + 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<PayeeEditPage {...access} request={request} id={payee.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fillReceiver(); fireEvent.click(screen.getByRole('button', { name: 'Confirm receiver' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(count).toBe(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirm same request' }));
    expect(await screen.findByText('The recorded receiver was updated.')).toBeInTheDocument();
    expect(count).toBe(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('refuses a receiver newly locked for public sponsorship before dispatch', async () => {
    let reads = 0;
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path === `operations/payees/${payee.id}` && !options?.method) { reads++; return reads === 1 ? detail : { ...detail, can_manage: false, allowed_operations: [] }; }
      throw new Error('Unexpected mutation');
    });
    render(<PayeeEditPage {...access} request={request} id={payee.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fillReceiver(); fireEvent.click(screen.getByRole('button', { name: 'Confirm receiver' }));
    expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(0); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('recovers a lost reply even if the receiver is subsequently locked', async () => {
    const key = '44444444-4444-4444-8444-444444444444';
    await retainPending(identity, 'operating-updatepayee', payee.id, key, 'receivers.manage', original);
    const request = vi.fn(async (path: string) => {
      if (path === `operations/payees/${payee.id}`) return { ...detail, resource: { ...detail.resource, version: payee.version + 1 }, can_manage: false, allowed_operations: [] };
      if (path === `operations/requests/${key}`) { const requestId = await canonicalRequestId(principalId, key); return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
        receipt: { status: 'succeeded', request_id: requestId, resource_type: 'payees', resource_id: payee.id, version: payee.version + 1 } }; }
      throw new Error('Unexpected request');
    });
    render(<PayeeEditPage {...access} request={request} id={payee.id} identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original receiver change was recorded.')).toBeInTheDocument();
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
