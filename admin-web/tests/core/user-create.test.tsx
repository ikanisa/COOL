import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { UserCreatePage } from '../../src/features/core/UserCreatePage';
import { canonicalRequestId, PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actorId = '11111111-1111-4111-8111-111111111111', principalId = '22222222-2222-4222-8222-222222222222';
const personId = '33333333-3333-4333-8333-333333333333';
const identity: PendingIdentity = { id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'admin',
  permissions: ['users.read', 'users.manage', 'overview.read', 'account.manage'], expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId, principalId, role: 'admin', authorityKey: 'authority-1',
  permissions: identity.permissions, financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
const app = { display_name: 'Recorded Member', member_type: 'app', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '',
  email: 'member@example.test', phone_e164: null, status: 'active', reason: 'Record reviewed person' };
const direct = { display_name: 'Direct Member', member_type: 'direct', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '',
  email: null, status: 'active', reason: 'Record reviewed person' };

beforeEach(() => { Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true }); sessionStorage.clear(); });
async function fillApp() {
  fireEvent.change(await screen.findByLabelText('Recorded full name'), { target: { value: app.display_name } });
  fireEvent.change(screen.getByLabelText('MoMo number'), { target: { value: app.momo_number } });
  fireEvent.change(screen.getByLabelText('Email'), { target: { value: 'Member@Example.Test' } });
  fireEvent.change(screen.getByLabelText('Reason for creation'), { target: { value: app.reason } });
  fireEvent.click(screen.getByRole('button', { name: 'Review person' }));
}

describe('canonical person creation', () => {
  it('defaults to disabled and rejects staff', async () => {
    const request = vi.fn();
    const view = render(<UserCreatePage {...access} request={request} identity={identity} verifyFresh={async () => true} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('not enabled'); expect(request).not.toHaveBeenCalled();
    const staff = { ...identity, role: 'staff' as const };
    view.rerender(<UserCreatePage {...access} role="staff" request={request} identity={staff} allowMutations verifyFresh={async () => true} />);
    expect(screen.getByText(/cannot create people/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('retains an unknown App-person result and retries only the reviewed exact key and body', async () => {
    let key = '', writes = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/requests/${key}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      if (path === 'operations/users' && options?.method === 'POST') {
        writes++; expect(options.body).toEqual(app); expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(app);
        if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(key);
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, key), resource_type: 'users', resource_id: personId, version: 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<UserCreatePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fillApp(); fireEvent.click(screen.getByRole('button', { name: 'Confirm person' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(writes).toBe(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirm same request' }));
    expect(await screen.findByText('The person was recorded.')).toBeInTheDocument(); expect(writes).toBe(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('requires a recorded MoMo number for Direct members and omits login identifiers', async () => {
    const request = vi.fn(async (_path: string, options?: { body?: Record<string, unknown>; idempotencyKey?: string }) => {
      expect(options?.body).toEqual(direct); expect(options?.body).not.toHaveProperty('phone_e164');
      return { status: 'succeeded', request_id: await canonicalRequestId(principalId, options!.idempotencyKey!), resource_type: 'users', resource_id: personId, version: 1 };
    });
    render(<UserCreatePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    fireEvent.change(await screen.findByLabelText('Recorded full name'), { target: { value: direct.display_name } });
    fireEvent.change(screen.getByLabelText('Member type'), { target: { value: 'direct' } });
    fireEvent.change(screen.getByLabelText('Reason for creation'), { target: { value: direct.reason } });
    fireEvent.click(screen.getByRole('button', { name: 'Review person' }));
    expect(screen.getByRole('alert')).toHaveTextContent('Direct members need'); expect(request).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText('MoMo number'), { target: { value: direct.momo_number } });
    expect(screen.queryByLabelText('Email')).not.toBeInTheDocument(); expect(screen.queryByLabelText('WhatsApp login number')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Review person' })); fireEvent.click(screen.getByRole('button', { name: 'Confirm person' }));
    expect(await screen.findByText('The person was recorded.')).toBeInTheDocument();
  });
  it('recovers a Flutter-compatible original request while creation remains disabled', async () => {
    const key = '44444444-4444-4444-8444-444444444444';
    await retainPending(identity, 'operating-createuser', 'new', key, 'users.manage', app);
    const request = vi.fn(async (path: string) => {
      expect(path).toBe(`operations/requests/${key}`); const requestId = await canonicalRequestId(principalId, key);
      return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
        receipt: { status: 'succeeded', request_id: requestId, resource_type: 'users', resource_id: personId, version: 1 } };
    });
    render(<UserCreatePage {...access} request={request} identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original person creation was recorded.')).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('preserves a replacement intent when an earlier lookup returns after the stored request changed', async () => {
    const family = 'operating-createuser';
    const key = '44444444-4444-4444-8444-444444444444';
    const now = Date.now();
    const replacement = {...app, reason: 'Record another reviewed intent'};
    await retainPending(identity, family, 'new', key, 'users.manage', app, sessionStorage, now);
    const requestId = await canonicalRequestId(principalId, key);
    const request = vi.fn(async () => {
      sessionStorage.removeItem(PENDING_KEY);
      await retainPending(identity, family, 'new', key, 'users.manage', replacement, sessionStorage, now);
      return {contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
        receipt: {status: 'succeeded', request_id: requestId, resource_type: 'users', resource_id: personId, version: 1}};
    });

    render(<UserCreatePage {...access} request={request} identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', {name: 'Check request'}));

    expect(await screen.findByText(/the original request could not be verified/i)).toBeInTheDocument();
    expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(replacement);
    expect(request).toHaveBeenCalledExactlyOnceWith(`operations/requests/${key}`);
  });
  it('does not submit when fresh verification is refused', async () => {
    const request = vi.fn();
    render(<UserCreatePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => false} />);
    await fillApp(); fireEvent.click(screen.getByRole('button', { name: 'Confirm person' }));
    expect(await screen.findByText(/No person was submitted/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
