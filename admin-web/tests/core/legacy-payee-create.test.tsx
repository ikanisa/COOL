import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { LegacyPayeeCreatePage } from '../../src/features/core';
import { PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actorId = '11111111-1111-4111-8111-111111111111', groupId = '22222222-2222-4222-8222-222222222222';
const payeeId = '33333333-3333-4333-8333-333333333333', requestId = '44444444-4444-4444-8444-444444444444';
const identity: PendingIdentity = { id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'admin',
  permissions: ['collections.read', 'receivers.manage', 'overview.read'], expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId, principalId: null, role: 'admin', authorityKey: 'authority-1', permissions: identity.permissions,
  financialModel: 'transaction_journals', navigate: vi.fn() };
const group = { resource_type: 'groups', current_actor_id: actorId, can_manage: true, resource: { id: groupId, title: 'Draft savings group', status: 'draft',
  version: 2, country_code: 'RW', currency: 'RWF', visibility: 'private' }, related: {}, related_pages: {}, related_truncated: false };
const body = { group_id: groupId, label: 'Recorded beneficiary', network: 'mtn_momo', momo_number_or_code: '008000', status: 'active', reason: 'Record reviewed receiver' };
const receipt = { request_id: requestId, resource_type: 'payees', resource_id: payeeId, version: 1, status: 'succeeded' };
beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  Object.defineProperty(navigator, 'locks', { value: { request: async (_name: string, _options: unknown, callback: (lock: object) => unknown) => callback({}) }, configurable: true });
  sessionStorage.clear();
});
async function fill() {
  fireEvent.change(await screen.findByLabelText('Receiver label'), { target: { value: body.label } });
  fireEvent.change(screen.getByLabelText('MoMo number or merchant code'), { target: { value: body.momo_number_or_code } });
  fireEvent.change(screen.getByLabelText('Reason for creation'), { target: { value: body.reason } });
  fireEvent.click(screen.getByRole('button', { name: 'Review receiver' })); fireEvent.click(screen.getByRole('checkbox'));
}

describe('legacy distinct payee creation', () => {
  it('defaults to disabled and never presents canonical POST as equivalent', async () => {
    const request = vi.fn();
    const view = render(<LegacyPayeeCreatePage {...access} request={request} groupId={groupId} identity={identity} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('not enabled'); expect(request).not.toHaveBeenCalled();
    view.rerender(<LegacyPayeeCreatePage {...access} financialModel="canonical_evidence_ledger" request={request} groupId={groupId} identity={identity} allowMutations />);
    expect(screen.getByText(/Separate receiver creation is unavailable/i)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('recovers a lost response and retries the exact original legacy body and key', async () => {
    let key = '', writes = 0, lookups = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/groups/${groupId}`) return group;
      if (path === `operations/requests/${key}`) {
        lookups++;
        return writes < 2 ? { status: 'not_found' } : { status: 'succeeded', request_id: requestId, receipt: { status: 'succeeded', version: 1, resource_id: payeeId, resource_type: 'payees', request_id: requestId } };
      }
      if (path === 'operations/payees' && options?.method === 'POST') {
        writes++; expect(options.body).toEqual(body); expect(options.body).not.toHaveProperty('expected_version');
        expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(body);
        if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(key); return receipt;
      }
      throw new Error('Unexpected request');
    });
    render(<LegacyPayeeCreatePage {...access} request={request} groupId={groupId} identity={identity} allowMutations />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm receiver' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(writes).toBe(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    const confirm = await screen.findByRole('button', { name: 'Confirm same request' }); fireEvent.click(screen.getByRole('checkbox')); fireEvent.click(confirm);
    expect(await screen.findByText('The recorded receiver was created.')).toBeInTheDocument(); expect(writes).toBe(2); expect(lookups).toBe(3); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('refuses a group archived after review, before any request is retained or sent', async () => {
    let reads = 0;
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path === `operations/groups/${groupId}` && !options?.method) { reads++; return reads === 1 ? group : { ...group, resource: { ...group.resource, status: 'archived', version: 3 } }; }
      throw new Error('Unexpected mutation');
    });
    render(<LegacyPayeeCreatePage {...access} request={request} groupId={groupId} identity={identity} allowMutations />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm receiver' }));
    expect(await screen.findByText(/No receiver was submitted/i)).toBeInTheDocument(); expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('keeps the original key if the post receipt and actor-scoped lookup disagree', async () => {
    let key = '';
    const request = vi.fn(async (path: string, options?: { method?: string; idempotencyKey?: string }) => {
      if (path === `operations/groups/${groupId}`) return group;
      if (path === 'operations/payees' && options?.method === 'POST') { key = options.idempotencyKey!; return receipt; }
      if (path === `operations/requests/${key}`) return { status: 'succeeded', request_id: '55555555-5555-4555-8555-555555555555', receipt: { ...receipt, request_id: '55555555-5555-4555-8555-555555555555' } };
      throw new Error('Unexpected request');
    });
    render(<LegacyPayeeCreatePage {...access} request={request} groupId={groupId} identity={identity} allowMutations />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm receiver' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
  });
  it('recovers an original request for another group while creation remains disabled', async () => {
    const key = '55555555-5555-4555-8555-555555555555', otherGroup = '66666666-6666-4666-8666-666666666666';
    await retainPending(identity, 'operating-createpayee', 'new', key, 'receivers.manage', body);
    const request = vi.fn(async (path: string) => { expect(path).toBe(`operations/requests/${key}`); return { status: 'succeeded', request_id: requestId, receipt }; });
    render(<LegacyPayeeCreatePage {...access} request={request} groupId={otherGroup} identity={identity} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original receiver creation was recorded.')).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
