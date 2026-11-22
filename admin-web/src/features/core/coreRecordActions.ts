import { isId, isObject } from './contracts';
import type { PendingIdentity } from './pendingAttempt';
import type { CoreArea, FeatureAccess } from './types';

interface ActionScope extends Pick<FeatureAccess, 'permissions' | 'role' | 'financialModel'> {
  area: CoreArea;
  allowMutations: boolean;
}

interface ListAction {path: string; label: string}
interface RecordAction extends ListAction {variant: 'primary' | 'secondary'}

export function coreListAction({area, role, permissions, financialModel, allowMutations, allowed}: ActionScope & {allowed: boolean}): ListAction | null {
  if (!allowed) return null;
  if (area === 'groups' && permissions.includes('collections.create')) {
    return {path: '/admin/groups/new', label: allowMutations ? 'Create group' : 'Check group creation request'};
  }
  if (role === 'staff') return null;

  const canonical = financialModel === 'canonical_evidence_ledger';
  const collections = permissions.includes('collections.read');
  const receivers = permissions.includes('receivers.read');
  const overview = permissions.includes('overview.read');
  if (area === 'users' && permissions.includes('users.manage')) {
    return {path: '/admin/users/new', label: allowMutations ? 'Create person' : 'Check person creation request'};
  }
  if (area === 'transactions' && permissions.includes('payments.manage') && (canonical || collections && receivers && overview)) {
    const write = allowMutations && collections && receivers && (!canonical || permissions.includes('payments.write'));
    return {path: '/admin/transactions/new', label: write ? 'Record payment evidence' : 'Check evidence request'};
  }
  if (area === 'ledgers' && !canonical && permissions.includes('ledger.manage')) {
    const write = allowMutations && collections && overview;
    return {path: '/admin/ledgers/new', label: write ? 'Create journal draft' : 'Check journal draft request'};
  }
  return null;
}

interface RecordActionScope extends ActionScope {
  actorId: string;
  id: string;
  resource: string;
  current: boolean;
  detail: Record<string, unknown> | null;
  identity?: PendingIdentity;
}

export function coreRecordActions({area, role, permissions, financialModel, allowMutations, actorId, id, resource, current, detail, identity}: RecordActionScope) {
  const actions: RecordAction[] = [];
  const canReview = current && role !== 'staff';
  const canWrite = allowMutations && detail?.can_manage === true;
  const record = isObject(detail?.resource) ? detail.resource : null;
  const operations = Array.isArray(detail?.allowed_operations) ? detail.allowed_operations : [];
  const can = (permission: string) => permissions.includes(permission);
  const hasIdentityPermissions = (required: string[]) => identity?.id === actorId && identity.role === role &&
    required.every(permission => can(permission) && identity.permissions.includes(permission));
  const canonical = financialModel === 'canonical_evidence_ledger';
  const collectionsOverview = can('collections.read') && can('overview.read');
  const group = canReview && area === 'groups';
  const transactions = canReview && area === 'transactions';

  function offer(path: string, write: boolean, enabled: string, recovery: string) {
    actions.push({path, label: write ? enabled : recovery, variant: write ? 'primary' : 'secondary'});
  }

  if (group && can('collections.manage')) {
    const write = canWrite && (canonical ? operations.includes('updateGroup') : can('overview.read') && !!record && record.status !== 'archived');
    offer(`/admin/groups/${id}/edit`, write, 'Edit group', 'Check group change request');
  }
  if (group && can('users.read') && can('users.manage') && (canonical || collectionsOverview)) {
    const write = canWrite && (canonical ? can('collections.manage') && operations.includes('createMembership') : !!record && record.status !== 'archived');
    offer(`/admin/groups/${id}/members/new`, write, 'Add member', 'Check membership request');
  }
  if (group && !canonical && can('receivers.manage')) {
    const write = canWrite && can('overview.read') && !!record && ['draft', 'active', 'suspended'].includes(String(record.status));
    offer(`/admin/groups/${id}/payees/new`, write, 'Add receiver', 'Check receiver creation request');
  }
  if (group && !canonical && hasIdentityPermissions(['collections.read', 'ledger.read', 'ledger.manage', 'overview.read'])) {
    offer(`/admin/groups/${id}/ledger-accounts/new`, canWrite && !!record && record.status !== 'archived', 'Add ledger account', 'Check ledger account request');
    offer(`/admin/groups/${id}/journals/new`, canWrite && record?.status === 'active', 'Create journal draft', 'Check journal draft request');
  }
  if (group && !canonical && hasIdentityPermissions(['collections.read', 'receivers.read', 'payments.read', 'payments.manage', 'overview.read'])) {
    offer(`/admin/groups/${id}/transactions/new`, canWrite && record?.status === 'active', 'Record payment evidence', 'Check payment request');
  }
  if (canReview && (area === 'users' || area === 'members') && can('users.manage') && (canonical || record?.collect_user_id === id)) {
    const write = canWrite && !!record && record.operator_admin_id === null && ['app', 'direct'].includes(String(record.member_type)) &&
      (canonical ? operations.includes('updateUser') : can('overview.read') && record.status !== 'closed');
    offer(`/admin/users/${id}/edit`, write, 'Edit person', 'Check person change request');
  }
  if (canReview && area === 'payees' && can('receivers.manage') &&
    (canonical || hasIdentityPermissions(['receivers.read', 'receivers.manage', 'collections.read', 'overview.read']))) {
    offer(`/admin/payees/${id}/edit`, canWrite && (!canonical || operations.includes('updatePayee')), 'Edit receiver', 'Check receiver change request');
  }
  if (transactions && canonical && can('payments.reconcile')) {
    offer(`/admin/transactions/${id}/reverse`, canWrite && can('ledger.read') && operations.includes('reverseTransaction'), 'Reverse contribution', 'Check reversal request');
  }
  if (canReview && area === 'ledgers' && !canonical && can('ledger.manage')) {
    const draft = canWrite && collectionsOverview && record?.status === 'draft' && (record.allocation_id === null || can('payments.read'));
    const post = draft && isId(record.created_by_admin_id) && isId(record.edited_by_admin_id) &&
      record.created_by_admin_id !== actorId && record.edited_by_admin_id !== actorId;
    offer(`/admin/ledgers/${id}/post`, post, 'Review posting', 'Check journal posting request');
    offer(`/admin/ledgers/${id}/edit`, draft, 'Replace draft', 'Check journal draft change');
  }

  const membershipRecovery = canReview && ['groups', 'users'].includes(resource) &&
    can('collections.read') && can('users.read') && can('users.manage') && (canonical || can('overview.read'));
  const membershipWrite = canWrite && membershipRecovery && (canonical ?
    resource === 'groups' && can('collections.manage') && operations.includes('updateMembership') :
    !!record && (resource !== 'groups' || record.status !== 'archived'));
  const journalRecovery = transactions && !canonical && can('ledger.read') && can('ledger.manage');
  const journalWrite = canWrite && journalRecovery && collectionsOverview && record?.verification_status === 'confirmation_recorded';
  return {actions, membershipRecovery, membershipWrite, journalRecovery, journalWrite};
}
