import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './canonical-core-fixtures.json';
import { MembershipCreatePage } from '../../src/features/core/MembershipCreatePage';
import { canonicalRequestId, PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';

const actorId = '11111111-1111-4111-8111-111111111111', principalId = '22222222-2222-4222-8222-222222222222';
const group = fixture.groups.rows[0], member = fixture.users.rows[0];
const identity: PendingIdentity = { id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'admin',
  permissions: ['collections.read', 'collections.manage', 'users.read', 'users.manage', 'overview.read', 'account.manage'], expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId, principalId, role: 'admin', authorityKey: 'authority-1',
  permissions: identity.permissions, financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
const groupDetail = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'groups', resource: group,
  current_actor_id: actorId, can_manage: true, allowed_operations: ['createMembership'], related: {}, related_pages: {}, related_truncated: false };
const userDetail = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'users', resource: member, current_actor_id: actorId };
const lookup = { contract_version: 2, model: 'canonical_evidence_ledger', kind: 'users', group_id: null,
  rows: [{ ...member, label: member.display_name, name: member.display_name }], total: 1 };
const body = { group_id: group.id, user_id: member.id, role: 'member', status: 'active', reason: 'Reviewed member assignment' };
beforeEach(() => { Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true }); sessionStorage.clear(); });
async function fill() {
  fireEvent.change(await screen.findByLabelText('Search members'), { target: { value: 'Recorded' } });
  fireEvent.click(screen.getByRole('button', { name: 'Find members' }));
  fireEvent.change(await screen.findByLabelText('Member'), { target: { value: member.id } });
  fireEvent.change(screen.getByLabelText('Reason for change'), { target: { value: body.reason } });
  fireEvent.click(screen.getByRole('button', { name: 'Review membership' }));
}

describe('canonical group membership creation', () => {
  it('keeps creation disabled unless explicitly enabled', async () => {
    const request = vi.fn();
    render(<MembershipCreatePage {...access} request={request} id={group.id} identity={identity} verifyFresh={async () => true} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('not enabled'); expect(request).not.toHaveBeenCalled();
  });
  it('does not offer writes without the bridge-required group management permission', async () => {
    const limited = { ...identity, permissions: identity.permissions.filter(permission => permission !== 'collections.manage') }, request = vi.fn();
    render(<MembershipCreatePage {...access} permissions={limited.permissions} request={request} id={group.id} identity={limited} allowMutations verifyFresh={async () => true} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('requires group management permission');
    expect(screen.queryByRole('button', { name: 'Find members' })).not.toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('retains a lost membership request and repeats the original key only after lookup and review', async () => {
    let key = '', writes = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/groups/${group.id}`) return groupDetail;
      if (path.startsWith('operations/lookups?')) return lookup;
      if (path === `operations/users/${member.id}`) return userDetail;
      if (path === `operations/requests/${key}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      if (path === 'operations/memberships' && options?.method === 'POST') {
        writes++; expect(options.body).toEqual(body); expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(body);
        if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(key);
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, key), resource_type: 'memberships', resource_id: `${group.id}/${member.id}`, version: 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<MembershipCreatePage {...access} request={request} id={group.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm membership' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(writes).toBe(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Confirm same request' }));
    expect(await screen.findByText('The membership was recorded.')).toBeInTheDocument(); expect(writes).toBe(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('fails closed if the group is no longer eligible before dispatch', async () => {
    let groupReads = 0;
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path === `operations/groups/${group.id}`) { groupReads++; return groupReads === 1 ? groupDetail : { ...groupDetail, can_manage: false, allowed_operations: [] }; }
      if (path.startsWith('operations/lookups?')) return lookup;
      if (path === `operations/users/${member.id}`) return userDetail;
      if (options?.method === 'POST') throw new Error('Unexpected mutation');
      throw new Error('Unexpected request');
    });
    render(<MembershipCreatePage {...access} request={request} id={group.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm membership' }));
    expect(await screen.findByText(/No membership was submitted/i)).toBeInTheDocument();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
  });
  it('checks a retained request for its original group even if opened from another group', async () => {
    const key = '44444444-4444-4444-8444-444444444444', otherGroup = '33333333-3333-4333-8333-333333333333';
    await retainPending(identity, 'operating-createmembership', 'new', key, 'users.manage', body);
    const navigate = vi.fn(), request = vi.fn(async (path: string) => {
      expect(path).toBe(`operations/requests/${key}`); const requestId = await canonicalRequestId(principalId, key);
      return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
        receipt: { status: 'succeeded', request_id: requestId, resource_type: 'memberships', resource_id: `${group.id}/${member.id}`, version: 1 } };
    });
    render(<MembershipCreatePage {...access} navigate={navigate} request={request} id={otherGroup} identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original membership was recorded.')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'View group' })); expect(navigate).toHaveBeenCalledWith(`/admin/groups/${group.id}`);
  });
});
