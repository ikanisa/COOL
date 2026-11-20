import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './canonical-core-fixtures.json';
import { GroupCreatePage } from '../../src/features/core';
import { canonicalRequestId, PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';

const actorId = '11111111-1111-4111-8111-111111111111';
const principalId = '22222222-2222-4222-8222-222222222222';
const owner = fixture.users.rows[0];
const identity: PendingIdentity = { id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'staff',
  permissions: ['collections.create', 'users.read', 'overview.read', 'account.manage'], expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId, principalId, role: 'staff', authorityKey: 'authority-1',
  permissions: identity.permissions, financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
const lookup = { contract_version: 2, model: 'canonical_evidence_ledger', kind: 'users', group_id: null,
  rows: [{ ...owner, label: owner.display_name, name: owner.display_name }], total: 1 };
const detail = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'users', resource: owner, current_actor_id: actorId };
const intent = { title: 'Private savings', slug: 'private-savings', collection_type: 'ikimina', visibility: 'private', description: '',
  purpose_label: null, status: 'active', owner_user_id: owner.id, receiver: { label: 'Recorded receiver', network: 'mtn_momo', momo_number_or_code: '0788123456' },
  is_platform_sponsored: false, reason: 'Reviewed owner and receiver' };

beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  sessionStorage.clear();
});

async function fillGroup() {
  fireEvent.change(await screen.findByLabelText('Search group owner'), { target: { value: 'Recorded' } });
  fireEvent.click(screen.getByRole('button', { name: 'Search owners' }));
  fireEvent.change(await screen.findByLabelText('Group owner'), { target: { value: owner.id } });
  fireEvent.change(screen.getByLabelText('Group name'), { target: { value: intent.title } });
  fireEvent.change(screen.getByLabelText('Group slug'), { target: { value: intent.slug } });
  fireEvent.change(screen.getByLabelText('Receiver name on MoMo'), { target: { value: intent.receiver.label } });
  fireEvent.change(screen.getByLabelText('Receiver MoMo number'), { target: { value: intent.receiver.momo_number_or_code } });
  fireEvent.change(screen.getByLabelText('Reason for creation'), { target: { value: intent.reason } });
  fireEvent.click(screen.getByRole('button', { name: 'Review group' }));
}

describe('canonical group creation', () => {
  it('fails closed when the workspace write gate is disabled', async () => {
    const request = vi.fn();
    render(<GroupCreatePage {...access} request={request} identity={identity} verifyFresh={async () => true} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('not enabled');
    expect(request).not.toHaveBeenCalled();
  });

  it('retains the exact private Staff intent, checks a lost result, and retries only after original-key lookup and review', async () => {
    let originalKey = ''; let writes = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path.startsWith('operations/lookups?')) return lookup;
      if (path === `operations/users/${owner.id}`) return detail;
      if (path === `operations/requests/${originalKey}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      if (path === 'operations/groups' && options?.method === 'POST') {
        writes++;
        const stored = JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0];
        expect(options.body).toEqual(intent); expect(stored.intent).toEqual(intent);
        if (!originalKey) { originalKey = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(originalKey);
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, originalKey), resource_type: 'groups', resource_id: '33333333-3333-4333-8333-333333333333', version: 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<GroupCreatePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fillGroup();
    expect(screen.queryByLabelText('Visibility')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Confirm group' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument();
    expect(writes).toBe(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Confirm same request' }));
    expect(await screen.findByText('The group was created.')).toBeInTheDocument();
    expect(writes).toBe(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });

  it('recovers a retained Flutter-compatible creation while writes are disabled', async () => {
    const key = '44444444-4444-4444-8444-444444444444';
    await retainPending(identity, 'operating-creategroup', 'new', key, 'collections.create', intent);
    const request = vi.fn(async (path: string) => {
      expect(path).toBe(`operations/requests/${key}`);
      const requestId = await canonicalRequestId(principalId, key);
      return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
        receipt: { status: 'succeeded', request_id: requestId, resource_type: 'groups', resource_id: '33333333-3333-4333-8333-333333333333', version: 1 } };
    });
    render(<GroupCreatePage {...access} request={request} identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original group creation was recorded.')).toBeInTheDocument();
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });

  it('allows public sponsored creation with a merchant code only for an authorized Admin', async () => {
    const adminIdentity: PendingIdentity = { ...identity, role: 'admin', permissions: [...identity.permissions, 'collections.manage', 'receivers.manage'] };
    const adminAccess = { ...access, role: 'admin' as const, permissions: adminIdentity.permissions };
    const key = '55555555-5555-4555-8555-555555555555';
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path.startsWith('operations/lookups?')) return lookup;
      if (path === `operations/users/${owner.id}`) return detail;
      if (path === 'operations/groups' && options?.method === 'POST') {
        expect(options.body?.visibility).toBe('public_approved');
        expect(options.body?.is_platform_sponsored).toBe(true);
        expect((options.body?.receiver as Record<string, unknown>).momo_number_or_code).toBe('123456');
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, options.idempotencyKey ?? key), resource_type: 'groups', resource_id: '33333333-3333-4333-8333-333333333333', version: 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<GroupCreatePage {...adminAccess} request={request} identity={adminIdentity} allowMutations verifyFresh={async () => true} />);
    await fillGroup();
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    fireEvent.change(screen.getByLabelText('Visibility'), { target: { value: 'public_approved' } });
    fireEvent.change(screen.getByLabelText('Receiver MoMo number or merchant code'), { target: { value: '123456' } });
    fireEvent.click(screen.getByRole('button', { name: 'Review group' }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirm group' }));
    expect(await screen.findByText('The group was created.')).toBeInTheDocument();
  });

  it('does not send when the selected owner is no longer active', async () => {
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path.startsWith('operations/lookups?')) return lookup;
      if (path === `operations/users/${owner.id}`) return { ...detail, resource: { ...owner, status: 'suspended', account_status: 'suspended' } };
      if (options?.method === 'POST') throw new Error('Unexpected mutation');
      throw new Error('Unexpected request');
    });
    render(<GroupCreatePage {...access} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fillGroup(); fireEvent.click(screen.getByRole('button', { name: 'Confirm group' }));
    expect(await screen.findByText(/No group was submitted/i)).toBeInTheDocument();
    await waitFor(() => expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0));
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
