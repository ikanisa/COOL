import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './canonical-core-fixtures.json';
import groupDetails from './group-detail-fixtures.json';
import { GroupEditPage } from '../../src/features/core';
import { canonicalRequestId, PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';

const actorId = '11111111-1111-4111-8111-111111111111';
const principalId = '22222222-2222-4222-8222-222222222222';
const group = fixture.groups.rows[0];
const identity: PendingIdentity = { id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'admin',
  permissions: ['collections.read', 'collections.manage', 'overview.read', 'account.manage'], expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId, principalId, role: 'admin', authorityKey: 'authority-1',
  permissions: identity.permissions, financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
const response = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'groups',
  resource: { ...group, description: 'Current description', owner_user_id: actorId }, current_actor_id: actorId,
  can_manage: true, allowed_operations: ['updateGroup'], related: {}, related_pages: {}, related_truncated: false };

beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  sessionStorage.clear();
});

describe('group update safety', () => {
  it('keeps mutation unavailable unless the workspace gate is enabled', async () => {
    const request = vi.fn();
    render(<GroupEditPage {...access} request={request} id={group.id} identity={identity} verifyFresh={async () => true} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('not enabled');
    expect(request).not.toHaveBeenCalled();
  });

  it('retains an unknown request, checks it, and retries only the identical key after review', async () => {
    let originalKey = '';
    let originalBody: Record<string, unknown> | undefined;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/groups/${group.id}` && !options?.method) return response;
      if (options?.method === 'PATCH') {
        if (!originalKey) { originalKey = options.idempotencyKey!; originalBody = options.body; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(originalKey);
        expect(options.body).toEqual(originalBody);
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, originalKey), resource_type: 'groups', resource_id: group.id, version: group.version + 1 };
      }
      if (path === `operations/requests/${originalKey}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      throw new Error('Unexpected request');
    });
    render(<GroupEditPage {...access} request={request} id={group.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    fireEvent.change(await screen.findByLabelText('Group name'), { target: { value: 'Updated group name' } });
    fireEvent.change(screen.getByLabelText('Reason for change'), { target: { value: 'Correct recorded group name' } });
    fireEvent.click(screen.getByRole('button', { name: 'Review changes' }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirm changes' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument();
    expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].request_key).toBe(originalKey);
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirm same request' }));
    await waitFor(() => expect(screen.getByText('Group changes recorded.')).toBeInTheDocument());
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(2);
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });

  it('can recover a lost archive response after the group becomes uneditable', async () => {
    const originalKey = '33333333-3333-4333-8333-333333333333';
    await retainPending(identity, 'operating-updategroup', group.id, originalKey, 'collections.manage', {
      title: group.title, collection_type: group.collection_type, description: 'Current description', purpose_label: null,
      status: 'archived', reason: 'Archive this inactive group', expected_version: group.version,
    });
    const archived = { ...response, resource: { ...response.resource, status: 'archived', version: group.version + 1 }, can_manage: false, allowed_operations: [] };
    const request = vi.fn(async (path: string) => {
      if (path === `operations/groups/${group.id}`) return archived;
      if (path === `operations/requests/${originalKey}`) {
        const requestId = await canonicalRequestId(principalId, originalKey);
        return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
          receipt: { status: 'succeeded', request_id: requestId, resource_type: 'groups', resource_id: group.id, version: group.version + 1 } };
      }
      throw new Error('Unexpected request');
    });
    render(<GroupEditPage {...access} request={request} id={group.id} identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original group change was recorded.')).toBeInTheDocument();
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });

  it('does not dispatch an edit after the group version changes during review', async () => {
    let reads = 0;
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path === `operations/groups/${group.id}` && !options?.method) {
        reads++;
        return reads === 1 ? response : { ...response, resource: { ...response.resource, version: group.version + 1 } };
      }
      throw new Error('Unexpected mutation');
    });
    render(<GroupEditPage {...access} request={request} id={group.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    fireEvent.change(await screen.findByLabelText('Group name'), { target: { value: 'Updated group name' } });
    fireEvent.change(screen.getByLabelText('Reason for change'), { target: { value: 'Correct recorded group name' } });
    fireEvent.click(screen.getByRole('button', { name: 'Review changes' }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirm changes' }));
    expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(0);
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });

  it('publishes only with a validated current owner and receiver, without substituting either', async () => {
    const publisherIdentity: PendingIdentity = { ...identity, permissions: [...identity.permissions, 'receivers.manage', 'receivers.read'] };
    const publisher = { ...access, permissions: publisherIdentity.permissions };
    const source = { ...groupDetails.first, current_actor_id: actorId };
    const groupId = source.resource.id;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/groups/${groupId}` && !options?.method) return source;
      if (path === `operations/groups/${groupId}` && options?.method === 'PATCH') {
        expect(options.body?.visibility).toBe('public_approved');
        expect(options.body?.is_platform_sponsored).toBe(true);
        expect(options.body).not.toHaveProperty('owner_user_id'); expect(options.body).not.toHaveProperty('receiver');
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, options.idempotencyKey!), resource_type: 'groups', resource_id: groupId, version: source.resource.version + 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<GroupEditPage {...publisher} request={request} id={groupId} identity={publisherIdentity} allowMutations verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByLabelText('Publish as a Collect-sponsored public group'));
    expect(screen.getByText(/Publishing permanently locks the receiver/i)).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('Reason for change'), { target: { value: 'Publish the reviewed group' } });
    fireEvent.click(screen.getByRole('button', { name: 'Review changes' }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirm changes' }));
    expect(await screen.findByText('Group changes recorded.')).toBeInTheDocument();
  });

  it('withholds publication when the recorded receiver is missing', async () => {
    const publisherIdentity: PendingIdentity = { ...identity, permissions: [...identity.permissions, 'receivers.manage', 'receivers.read'] };
    const source = { ...groupDetails.first, current_actor_id: actorId, related: { ...groupDetails.first.related, payees: [] } };
    const request = vi.fn(async () => source);
    render(<GroupEditPage {...access} permissions={publisherIdentity.permissions} request={request} id={source.resource.id} identity={publisherIdentity} allowMutations verifyFresh={async () => true} />);
    expect(await screen.findByLabelText('Group name')).toBeInTheDocument();
    expect(screen.queryByLabelText('Publish as a Collect-sponsored public group')).not.toBeInTheDocument();
  });

  it('does not publish if the reviewed receiver changes before dispatch', async () => {
    const publisherIdentity: PendingIdentity = { ...identity, permissions: [...identity.permissions, 'receivers.manage', 'receivers.read'] };
    const source = { ...groupDetails.first, current_actor_id: actorId };
    const receiver = source.related.payees[0];
    let reads = 0;
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path === `operations/groups/${source.resource.id}` && !options?.method) {
        reads++;
        return reads === 1 ? source : { ...source, related: { ...source.related, payees: [{ ...receiver, amount: '250788123459', momo_number: '250788123459', momo_number_or_code: '250788123459' }] } };
      }
      throw new Error('Unexpected mutation');
    });
    render(<GroupEditPage {...access} permissions={publisherIdentity.permissions} request={request} id={source.resource.id} identity={publisherIdentity} allowMutations verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByLabelText('Publish as a Collect-sponsored public group'));
    fireEvent.change(screen.getByLabelText('Reason for change'), { target: { value: 'Publish the reviewed group' } });
    fireEvent.click(screen.getByRole('button', { name: 'Review changes' }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirm changes' }));
    expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(0);
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
