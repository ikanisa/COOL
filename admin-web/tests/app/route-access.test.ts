import {describe, expect, it} from 'vitest';
import {canOpenAdminPath} from '../../src/app/route-access';
import type {AdminUser} from '../../src/session/SessionProvider';

const user: AdminUser = {id: 'actor', email: 'staff@example.test', role: 'staff', sessionId: 'session',
  expiresAt: '2030-01-01T00:00:00.000Z', permissions: ['overview.read', 'collections.read'],
  assuranceLevel: 1, mfaAt: null, emailVerifiedAt: null, principalId: null, financialModel: 'transaction_journals'};

describe('Admin route access', () => {
  it('matches registered route shapes and applies the same rule to encoded route segments', () => {
    expect(canOpenAdminPath('/admin/groups/record/unsupported', user)).toBe(false);
    expect(canOpenAdminPath('/admin/groups/%6Eew', user)).toBe(false);
    expect(canOpenAdminPath('/admin/groups/%6Eew', {...user, permissions: ['collections.read', 'collections.create']})).toBe(true);
  });

  it('checks direct deep links and action permissions, not only visible navigation', () => {
    expect(canOpenAdminPath('/admin/groups', user)).toBe(true);
    expect(canOpenAdminPath('/admin/groups/record', user)).toBe(true);
    expect(canOpenAdminPath('/admin/groups/new', user)).toBe(false);
    expect(canOpenAdminPath('/admin/groups/record/edit', user)).toBe(false);
    expect(canOpenAdminPath('/admin/groups/record/members/new', user)).toBe(false);
    expect(canOpenAdminPath('/admin/groups/record/members/new', {...user, permissions: [...user.permissions, 'users.manage']})).toBe(true);
    expect(canOpenAdminPath('/admin/groups/record/members/person/edit', user)).toBe(false);
    expect(canOpenAdminPath('/admin/groups/record/members/person/edit', {...user, permissions: [...user.permissions, 'users.manage']})).toBe(true);
    expect(canOpenAdminPath('/admin/groups/record/payees/new', user)).toBe(false);
    expect(canOpenAdminPath('/admin/groups/record/payees/new', {...user, permissions: [...user.permissions, 'receivers.manage']})).toBe(true);
    expect(canOpenAdminPath('/admin/groups/record/ledger-accounts/new', user)).toBe(false);
    expect(canOpenAdminPath('/admin/groups/record/ledger-accounts/new', {...user, role: 'admin', permissions: [...user.permissions, 'ledger.manage']})).toBe(false);
    expect(canOpenAdminPath('/admin/groups/record/ledger-accounts/new', {...user, permissions: [...user.permissions, 'ledger.read', 'ledger.manage']})).toBe(false);
    expect(canOpenAdminPath('/admin/groups/record/ledger-accounts/new', {...user, role: 'admin', permissions: [...user.permissions, 'ledger.read', 'ledger.manage']})).toBe(true);
    expect(canOpenAdminPath('/admin/groups/record/journals/new', user)).toBe(false);
    expect(canOpenAdminPath('/admin/groups/record/journals/new', {...user, role: 'admin', permissions: [...user.permissions, 'ledger.read', 'ledger.manage']})).toBe(true);
    expect(canOpenAdminPath('/admin/groups/record/transactions/new', {...user, role: 'admin', permissions: [...user.permissions, 'payments.manage']})).toBe(false);
    expect(canOpenAdminPath('/admin/groups/record/transactions/new', {...user, role: 'admin', permissions: [...user.permissions, 'payments.read', 'payments.manage', 'receivers.read']})).toBe(true);
    expect(canOpenAdminPath('/admin/payees/record/edit', {...user, role: 'admin', permissions: ['receivers.read', 'receivers.manage']})).toBe(false);
    expect(canOpenAdminPath('/admin/payees/record/edit', {...user, role: 'admin', permissions: ['receivers.read', 'receivers.manage', 'collections.read', 'overview.read']})).toBe(true);
    expect(canOpenAdminPath('/admin/transactions/new', {...user, role: 'admin', permissions: ['payments.read', 'payments.manage']})).toBe(false);
    expect(canOpenAdminPath('/admin/transactions/new', {...user, role: 'admin', permissions: ['payments.read', 'payments.manage', 'collections.read', 'receivers.read', 'overview.read']})).toBe(true);
    expect(canOpenAdminPath('/admin/transactions/record/reverse', {...user, permissions: ['payments.read']})).toBe(false);
    expect(canOpenAdminPath('/admin/transactions/record/reverse', {...user, permissions: ['payments.read', 'payments.reconcile']})).toBe(true);
    expect(canOpenAdminPath('/admin/transactions/record/allocations/allocation/journal/new', {...user, permissions: ['payments.read']})).toBe(false);
    expect(canOpenAdminPath('/admin/transactions/record/allocations/allocation/journal/new', {...user, permissions: ['payments.read', 'ledger.read', 'ledger.manage']})).toBe(true);
    expect(canOpenAdminPath('/admin/ledgers/record/post', {...user, permissions: ['ledger.read']})).toBe(false);
    expect(canOpenAdminPath('/admin/ledgers/record/post', {...user, permissions: ['ledger.read', 'ledger.manage']})).toBe(true);
    expect(canOpenAdminPath('/admin/admin-users', user)).toBe(false);
    expect(canOpenAdminPath('/admin/requests', user)).toBe(true);
    expect(canOpenAdminPath('/admin/requests', {...user, permissions: [...user.permissions, 'account.manage']})).toBe(true);
    expect(canOpenAdminPath('/admin/requests', {...user, financialModel: 'canonical_evidence_ledger'})).toBe(false);
    expect(canOpenAdminPath('/admin/requests', {...user, financialModel: 'canonical_evidence_ledger', permissions: [...user.permissions, 'account.manage']})).toBe(true);
    expect(canOpenAdminPath('/admin/requests', {...user, permissions: ['account.manage']})).toBe(false);
    expect(canOpenAdminPath('/admin/security', user)).toBe(false);
    expect(canOpenAdminPath('/admin/security/authenticator', user)).toBe(true);
    expect(canOpenAdminPath('/admin/security/verify-email', user)).toBe(true);
    expect(canOpenAdminPath('/admin/notification-settings', {...user, permissions: [...user.permissions, 'admin_users.manage']})).toBe(false);
    expect(canOpenAdminPath('/admin/notification-settings', {...user, role: 'owner', permissions: ['admin_users.manage']})).toBe(true);
    const owner = {...user, role: 'owner' as const, financialModel: 'canonical_evidence_ledger' as const, principalId: 'principal', permissions: ['admin_users.manage', 'receivers.read', 'receivers.manage']};
    expect(canOpenAdminPath('/admin/burimunsi', owner)).toBe(false);
    const verifiedOwner = {...owner, ownerIdentity: {schemaVersion: 1 as const, adminId: owner.id, principalId: owner.principalId, email: owner.email}};
    expect(canOpenAdminPath('/admin/burimunsi', verifiedOwner)).toBe(true);
    expect(canOpenAdminPath('/admin/burimunsi', {...verifiedOwner, ownerIdentity: {...verifiedOwner.ownerIdentity, adminId: 'different'}})).toBe(false);
    expect(canOpenAdminPath('/admin/burimunsi', {...verifiedOwner, permissions: ['admin_users.manage', 'receivers.read']})).toBe(false);
  });
});
