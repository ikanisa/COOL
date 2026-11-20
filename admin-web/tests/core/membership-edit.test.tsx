import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './canonical-core-fixtures.json';
import { MembershipEditPage } from '../../src/features/core';
import { canonicalRequestId, PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';

const actorId = '11111111-1111-4111-8111-111111111111', principalId = '22222222-2222-4222-8222-222222222222';
const group = fixture.groups.rows[0], user = fixture.users.rows[0], membershipId = '33333333-3333-4333-8333-333333333333';
const identity: PendingIdentity = { id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'admin',
  permissions: ['collections.read', 'collections.manage', 'users.read', 'users.manage', 'overview.read', 'account.manage'], expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId, principalId, role: 'admin', authorityKey: 'authority-1', permissions: identity.permissions,
  financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
const member = { id: membershipId, group_id: group.id, user_id: user.id, role: 'member', status: 'active', version: 3, public_id: user.public_id,
  display_name: user.display_name, member_type: user.member_type, momo_provider: user.momo_provider, momo_number: user.momo_number, momo_pay_code: user.momo_pay_code, account_status: 'active' };
const page = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'groups', resource: group, current_actor_id: actorId,
  can_manage: true, allowed_operations: ['updateMembership'], related: { memberships: [member] },
  related_pages: { memberships: { total: 1, limit: 100, offset: 0, next_offset: null } }, related_truncated: false };
const body = { role: 'admin', status: 'active', reason: 'Review group member role', expected_version: member.version };
beforeEach(() => { Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true }); sessionStorage.clear(); });
async function fill() {
  fireEvent.change(await screen.findByLabelText('Group role'), { target: { value: 'admin' } });
  fireEvent.change(screen.getByLabelText('Reason for change'), { target: { value: body.reason } });
  fireEvent.click(screen.getByRole('button', { name: 'Review membership' }));
}

describe('canonical membership editing', () => {
  it('defaults to disabled and requires both advertised and bridge permissions', async () => {
    const request = vi.fn();
    const view = render(<MembershipEditPage {...access} request={request} groupId={group.id} userId={user.id} identity={identity} verifyFresh={async () => true} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('not enabled'); expect(request).not.toHaveBeenCalled();
    const limited = { ...identity, permissions: identity.permissions.filter(permission => permission !== 'collections.manage') };
    view.rerender(<MembershipEditPage {...access} permissions={limited.permissions} request={request} groupId={group.id} userId={user.id} identity={limited} allowMutations verifyFresh={async () => true} />);
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('requires group management permission')); expect(request).not.toHaveBeenCalled();
  });
  it('retains a lost edit and retries only the reviewed original key and exact compound target', async () => {
    let key = '', writes = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path.startsWith(`operations/groups/${group.id}?`)) return page;
      if (path === `operations/requests/${key}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      if (path === `operations/memberships/${group.id}/${user.id}` && options?.method === 'PATCH') {
        writes++; expect(options.body).toEqual(body); const saved = JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0];
        expect(saved.intent).toEqual(body); expect(saved.resource_id).toBe(`${group.id}:${user.id}`);
        if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(key);
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, key), resource_type: 'memberships', resource_id: `${group.id}/${user.id}`, version: member.version + 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<MembershipEditPage {...access} request={request} groupId={group.id} userId={user.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm membership changes' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(writes).toBe(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Confirm same request' }));
    expect(await screen.findByText('The membership was updated.')).toBeInTheDocument(); expect(writes).toBe(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('refuses an owner or a membership that changes before dispatch', async () => {
    let reads = 0;
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path.startsWith(`operations/groups/${group.id}?`) && !options?.method) { reads++; return reads === 1 ? page : { ...page, related: { memberships: [{ ...member, role: 'owner' }] } }; }
      throw new Error('Unexpected mutation');
    });
    render(<MembershipEditPage {...access} request={request} groupId={group.id} userId={user.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm membership changes' }));
    expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(0);
  });
  it('finds the requested member beyond the first related-record page', async () => {
    const rows = Array.from({ length: 100 }, (_, index) => {
      const value = (index + 100).toString(16).padStart(8, '0');
      return { id: `${value}-0000-4000-8000-000000000000`, user_id: `${value}-1111-4111-8111-111111111111`, group_id: group.id, role: 'member', status: 'active' };
    });
    const request = vi.fn(async (path: string) => {
      if (path.includes('offset=0')) return { ...page, related: { memberships: rows }, related_pages: { memberships: { total: 101, limit: 100, offset: 0, next_offset: 100 } } };
      if (path.includes('offset=100')) return { ...page, related_pages: { memberships: { total: 101, limit: 100, offset: 100, next_offset: null } } };
      throw new Error('Unexpected request');
    });
    render(<MembershipEditPage {...access} request={request} groupId={group.id} userId={user.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    expect(await screen.findByLabelText('Group role')).toBeInTheDocument(); expect(request).toHaveBeenCalledTimes(2);
  });
  it('recovers a lost response without reopening a no-longer-editable membership', async () => {
    const key = '44444444-4444-4444-8444-444444444444';
    await retainPending(identity, 'operating-updatemembership', `${group.id}:${user.id}`, key, 'users.manage', body);
    const request = vi.fn(async (path: string) => {
      expect(path).toBe(`operations/requests/${key}`); const requestId = await canonicalRequestId(principalId, key);
      return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
        receipt: { status: 'succeeded', request_id: requestId, resource_type: 'memberships', resource_id: `${group.id}/${user.id}`, version: member.version + 1 } };
    });
    render(<MembershipEditPage {...access} request={request} groupId={group.id} userId={user.id} identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original membership change was recorded.')).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
