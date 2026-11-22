import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './canonical-core-fixtures.json';
import { UserEditPage } from '../../src/features/core/UserEditPage';
import { canonicalRequestId, PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';

const actorId = '11111111-1111-4111-8111-111111111111', principalId = '22222222-2222-4222-8222-222222222222';
const user = fixture.users.rows[0], group = fixture.groups.rows[0];
const identity: PendingIdentity = { id: actorId, sessionId: 'same-session', email: 'operator@example.test', role: 'admin',
  permissions: ['users.read', 'users.manage', 'collections.read', 'overview.read', 'account.manage'], expiresAt: '2100-01-01T00:00:00.000Z' };
const access: Omit<FeatureAccess, 'request'> = { actorId, principalId, role: 'admin', authorityKey: 'authority-1',
  permissions: identity.permissions, financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
const detail = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'users', resource: user,
  current_actor_id: actorId, can_manage: true, allowed_operations: ['updateUser'], related: {}, related_pages: {}, related_truncated: false };
const body = { display_name: 'Updated Member', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '', status: 'active', reason: 'Correct recorded person', expected_version: user.version };
const relationId = (i: number) => `${i.toString(16).padStart(8, '0')}-0000-4000-8000-000000000000`;
const groupDetail = { contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'groups', resource: { ...group, visibility: 'public_approved', is_platform_sponsored: true }, current_actor_id: actorId };
function page(offset: number, total: number, ownerOffset = -1) {
  const rows = Array.from({ length: Math.min(100, total - offset) }, (_, j) => ({ id: relationId(offset + j), group_id: group.id, user_id: user.id, role: offset + j === ownerOffset ? 'owner' : 'member', status: 'active' }));
  return { ...detail, related: { memberships: rows }, related_pages: { memberships: { total, limit: 100, offset, next_offset: offset + rows.length < total ? offset + rows.length : null } } };
}
beforeEach(() => { Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true }); sessionStorage.clear(); });
async function fill(status = 'active') {
  fireEvent.change(await screen.findByLabelText('Recorded full name'), { target: { value: body.display_name } });
  fireEvent.change(screen.getByLabelText('Account status'), { target: { value: status } });
  fireEvent.change(screen.getByLabelText('Reason for change'), { target: { value: body.reason } });
  fireEvent.click(screen.getByRole('button', { name: 'Review person changes' }));
}

describe('canonical person editing', () => {
  it.each(['canonical_evidence_ledger', 'transaction_journals'] as const)('returns to the member detail from a member edit link in %s', async (financialModel) => {
    const navigate = vi.fn(), request = vi.fn();
    render(<UserEditPage {...access} financialModel={financialModel} navigate={navigate} request={request} id={user.id} returnArea="members" identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(screen.getByRole('button', {name: 'Back to person'}));
    expect(navigate).toHaveBeenCalledWith(`/admin/members/${user.id}`);
    expect(request).not.toHaveBeenCalled();
  });
  it('keeps edits off by default and refuses linked operator targets', async () => {
    const request = vi.fn();
    const view = render(<UserEditPage {...access} request={request} id={user.id} identity={identity} verifyFresh={async () => true} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('not enabled'); expect(request).not.toHaveBeenCalled();
    const linked = { ...detail, resource: { ...user, operator_admin_id: '55555555-5555-4555-8555-555555555555' } };
    const get = vi.fn(async () => linked);
    view.rerender(<UserEditPage {...access} request={get} id={user.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    expect(await screen.findByText(/Operator accounts are managed separately/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Review person changes' })).not.toBeInTheDocument();
  });
  it('retains and retries a lost exact person edit after explicit same-key review', async () => {
    let key = '', writes = 0;
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/users/${user.id}` && !options?.method) return detail;
      if (path === `operations/requests/${key}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      if (path === `operations/users/${user.id}` && options?.method === 'PATCH') {
        writes++; expect(options.body).toEqual(body); expect(options.body).not.toHaveProperty('email'); expect(options.body).not.toHaveProperty('phone_e164');
        expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].intent).toEqual(body);
        if (!key) { key = options.idempotencyKey!; throw new Error('Lost response'); }
        expect(options.idempotencyKey).toBe(key);
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, key), resource_type: 'users', resource_id: user.id, version: user.version + 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<UserEditPage {...access} request={request} id={user.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm person changes' }));
    expect(await screen.findByText(/result is unconfirmed/i)).toBeInTheDocument(); expect(writes).toBe(1);
    fireEvent.click(screen.getByRole('button', { name: 'Check request' })); fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Confirm same request' }));
    expect(await screen.findByText('The person was updated.')).toBeInTheDocument(); expect(writes).toBe(2); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('checks every membership page and refuses suspension of a public-group owner', async () => {
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path === `operations/users/${user.id}` && !options?.method) return detail;
      if (path.includes('relation=memberships') && path.includes('offset=0')) return page(0, 101);
      if (path.includes('relation=memberships') && path.includes('offset=100')) return page(100, 101, 100);
      if (path === `operations/groups/${group.id}`) return groupDetail;
      throw new Error('Unexpected mutation');
    });
    render(<UserEditPage {...access} request={request} id={user.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill('suspended'); fireEvent.click(screen.getByRole('button', { name: 'Confirm person changes' }));
    expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument();
    expect(request.mock.calls.filter(([path]) => path.includes('relation=memberships'))).toHaveLength(2);
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(0); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
  it('permits reviewed suspension if the only owned group is suspended', async () => {
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/users/${user.id}` && !options?.method) return detail;
      if (path.includes('relation=memberships')) return page(0, 1, 0);
      if (path === `operations/groups/${group.id}`) return { ...groupDetail, resource: { ...groupDetail.resource, status: 'suspended' } };
      if (path === `operations/users/${user.id}` && options?.method === 'PATCH') {
        expect(options.body).toEqual({ ...body, status: 'suspended' });
        return { status: 'succeeded', request_id: await canonicalRequestId(principalId, options.idempotencyKey!), resource_type: 'users', resource_id: user.id, version: user.version + 1 };
      }
      throw new Error('Unexpected request');
    });
    render(<UserEditPage {...access} request={request} id={user.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill('suspended'); fireEvent.click(screen.getByRole('button', { name: 'Confirm person changes' }));
    expect(await screen.findByText('The person was updated.')).toBeInTheDocument();
  });
  it('does not suspend if the account cannot verify group ownership', async () => {
    const limitedIdentity = { ...identity, permissions: identity.permissions.filter(permission => permission !== 'collections.read') };
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path === `operations/users/${user.id}` && !options?.method) return detail;
      throw new Error('Unexpected request');
    });
    render(<UserEditPage {...access} permissions={limitedIdentity.permissions} request={request} id={user.id} identity={limitedIdentity} allowMutations verifyFresh={async () => true} />);
    await fill('suspended'); fireEvent.click(screen.getByRole('button', { name: 'Confirm person changes' }));
    expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(0);
  });
  it('refuses a person whose version changes after review', async () => {
    let reads = 0;
    const request = vi.fn(async (path: string, options?: { method?: string }) => {
      if (path === `operations/users/${user.id}` && !options?.method) { reads++; return reads === 1 ? detail : { ...detail, resource: { ...user, version: user.version + 1 } }; }
      throw new Error('Unexpected request');
    });
    render(<UserEditPage {...access} request={request} id={user.id} identity={identity} allowMutations verifyFresh={async () => true} />);
    await fill(); fireEvent.click(screen.getByRole('button', { name: 'Confirm person changes' }));
    expect(await screen.findByText(/No change was submitted/i)).toBeInTheDocument();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(0);
  });
  it('recovers the original receipt without opening a now-protected person', async () => {
    const key = '44444444-4444-4444-8444-444444444444';
    await retainPending(identity, 'operating-updateuser', user.id, key, 'users.manage', body);
    const request = vi.fn(async (path: string) => {
      expect(path).toBe(`operations/requests/${key}`); const requestId = await canonicalRequestId(principalId, key);
      return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
        receipt: { status: 'succeeded', request_id: requestId, resource_type: 'users', resource_id: user.id, version: user.version + 1 } };
    });
    render(<UserEditPage {...access} request={request} id={user.id} identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check request' }));
    expect(await screen.findByText('The original person change was recorded.')).toBeInTheDocument(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
