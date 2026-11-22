import {lazy, type ReactElement} from 'react';
import {useLocation, useNavigate, useParams} from 'react-router';
import {Button} from '../../ui';
import {CORE_PERMISSIONS, type CoreArea} from '../../features/core/types';
import {UnavailablePage} from '../UnavailablePage';
import {useAccess, useCurrentAuthority, useSensitiveAccess} from './access';
import {LegacyJournalCreateRoute, LegacyJournalEditRoute, TransactionEvidenceRoute} from './financial-routes';
import {MomoReceiptsPage} from './operator-routes';
import {requiresAdminRole, requiresPermissions, workspaceRoute, type WorkspaceAccess} from './routePolicy';

const CoreListPage = lazy(() => import('../../features/core/CoreListPage').then(m => ({default: m.CoreListPage})));
const CoreRecordPage = lazy(() => import('../../features/core/CoreRecordPage').then(m => ({default: m.CoreRecordPage})));
const GroupCreatePage = lazy(() => import('../../features/core/GroupCreatePage').then(m => ({default: m.GroupCreatePage})));
const GroupEditPage = lazy(() => import('../../features/core/GroupEditPage').then(m => ({default: m.GroupEditPage})));
const UserCreatePage = lazy(() => import('../../features/core/UserCreatePage').then(m => ({default: m.UserCreatePage})));
const UserEditPage = lazy(() => import('../../features/core/UserEditPage').then(m => ({default: m.UserEditPage})));
const MembershipCreatePage = lazy(() => import('../../features/core/MembershipCreatePage').then(m => ({default: m.MembershipCreatePage})));
const MembershipEditPage = lazy(() => import('../../features/core/MembershipEditPage').then(m => ({default: m.MembershipEditPage})));
const LegacyPayeeCreatePage = lazy(() => import('../../features/core/LegacyPayeeCreatePage').then(m => ({default: m.LegacyPayeeCreatePage})));
const PayeeEditPage = lazy(() => import('../../features/core/PayeeEditPage').then(m => ({default: m.PayeeEditPage})));
const LegacyPayeeEditPage = lazy(() => import('../../features/legacy-payees/LegacyPayeeEditPage').then(m => ({default: m.LegacyPayeeEditPage})));
const LegacyLedgerAccountCreatePage = lazy(() => import('../../features/legacy-ledger-accounts/LegacyLedgerAccountCreatePage').then(m => ({default: m.LegacyLedgerAccountCreatePage})));
const GroupSelectionPage = lazy(() => import('../../features/route-compat/GroupSelectionPage').then(m => ({default: m.GroupSelectionPage})));

function CoreListRoute({area}: {area: CoreArea}) {
  const access = useAccess(), location = useLocation();
  return <CoreListPage key={`${access.authorityKey}:${area}`} {...access} area={area} locationSearch={location.search} />;
}

function CoreDetailRoute({area}: {area: CoreArea}) {
  const access = useAccess(), sensitive = useSensitiveAccess(), isCurrent = useCurrentAuthority(), {id = ''} = useParams(), location = useLocation();
  return <CoreRecordPage key={`${access.authorityKey}:${area}:${id}`} {...access} identity={sensitive.identity} area={area} id={id}
    isCurrent={isCurrent} returnTo={new URLSearchParams(location.search).get('returnTo')} />;
}

function GroupEditRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {id = ''} = useParams();
  return <GroupEditPage key={`${access.authorityKey}:${id}`} {...access} id={id}
    {...sensitive} allowMutations={false} allowStatusChanges={false} />;
}

function PayeeEditRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {id = ''} = useParams();
  return access.financialModel === 'transaction_journals' ?
    <LegacyPayeeEditPage key={`${access.authorityKey}:${id}`} {...access} id={id} {...sensitive} allowMutations={false} /> :
    <PayeeEditPage key={`${access.authorityKey}:${id}`} {...access} id={id} {...sensitive} allowMutations={false} />;
}

function UserEditRoute({returnArea = 'users'}: {returnArea?: 'users' | 'members'}) {
  const access = useAccess(), sensitive = useSensitiveAccess(), {id = ''} = useParams();
  return <UserEditPage key={`${access.authorityKey}:${returnArea}:${id}`} {...access} id={id} returnArea={returnArea} {...sensitive} allowMutations={false} />;
}

function MembershipCreateRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {id = ''} = useParams();
  return <MembershipCreatePage key={`${access.authorityKey}:${id}`} {...access} id={id} {...sensitive} allowMutations={false} />;
}

function MembershipEditRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {groupId = '', userId = ''} = useParams();
  return <MembershipEditPage key={`${access.authorityKey}:${groupId}:${userId}`} {...access} groupId={groupId} userId={userId} {...sensitive} allowMutations={false} />;
}

function LegacyPayeeCreateRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {groupId = ''} = useParams();
  return <LegacyPayeeCreatePage key={`${access.authorityKey}:${groupId}`} {...access} groupId={groupId} identity={sensitive.identity} allowMutations={false} />;
}

function LegacyLedgerAccountCreateRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {groupId = ''} = useParams();
  return <LegacyLedgerAccountCreatePage key={`${access.authorityKey}:${groupId}`} {...access} groupId={groupId} identity={sensitive.identity} allowMutations={false} />;
}

function GroupCreateRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess();
  return <GroupCreatePage key={access.authorityKey} {...access} {...sensitive} allowMutations={false} />;
}

function UserCreateRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess();
  return <UserCreatePage key={access.authorityKey} {...access} {...sensitive} allowMutations={false} />;
}

function GroupSelectionRoute({action}: {action: 'member' | 'payee'}) {
  const access = useAccess(), isCurrent = useCurrentAuthority();
  return <GroupSelectionPage key={`${access.authorityKey}:${action}`} {...access} action={action} isCurrent={isCurrent} />;
}

function TransactionListRoute() {
  const location = useLocation(), navigate = useNavigate();
  const momo = new URLSearchParams(location.search).get('view') === 'momo';
  return <>
    <nav className="transaction-view-switch" aria-label="Transaction views">
      <Button variant={!momo ? 'primary' : 'secondary'} aria-pressed={!momo} onClick={() => navigate('/admin/transactions')}>Collect payments</Button>
      <Button variant={momo ? 'primary' : 'secondary'} aria-pressed={momo} onClick={() => navigate('/admin/transactions?view=momo')}>MoMo transactions</Button>
    </nav>
    {momo ? <MomoReceiptsPage initialView="transactions" transactionsOnly /> : <CoreListRoute area="transactions" />}
  </>;
}

interface RecordAction {
  element: ReactElement;
  access: WorkspaceAccess;
}

interface RecordRoutes {
  list?: ReactElement;
  create: RecordAction;
  edit: RecordAction;
}

const canManageUsers = requiresPermissions('users.manage');
const canManageReceivers = requiresPermissions('receivers.manage');
const canManagePayments = requiresPermissions('payments.manage');
const canManageLedgers = requiresPermissions('ledger.manage');
const canEditLegacyPayee = requiresAdminRole('receivers.manage', 'collections.read', 'overview.read');
const canCreateLegacyTransaction = requiresAdminRole('payments.manage', 'collections.read', 'receivers.read', 'overview.read');

const records: Record<CoreArea, RecordRoutes> = {
  groups: {
    create: {element: <GroupCreateRoute />, access: requiresPermissions('collections.create')},
    edit: {element: <GroupEditRoute />, access: requiresPermissions('collections.manage')},
  },
  users: {
    create: {element: <UserCreateRoute />, access: canManageUsers},
    edit: {element: <UserEditRoute returnArea="users" />, access: canManageUsers},
  },
  members: {
    create: {element: <GroupSelectionRoute action="member" />, access: canManageUsers},
    edit: {element: <UserEditRoute returnArea="members" />, access: canManageUsers},
  },
  payees: {
    create: {element: <GroupSelectionRoute action="payee" />, access: canManageReceivers},
    edit: {element: <PayeeEditRoute />, access: user =>
      user.financialModel === 'transaction_journals' ? canEditLegacyPayee(user) : canManageReceivers(user)},
  },
  transactions: {
    list: <TransactionListRoute />,
    create: {element: <TransactionEvidenceRoute />, access: user =>
      user.financialModel === 'transaction_journals' ? canCreateLegacyTransaction(user) : canManagePayments(user)},
    edit: {element: <UnavailablePage title="Edit transaction" />, access: canManagePayments},
  },
  ledgers: {
    create: {element: <LegacyJournalCreateRoute />, access: canManageLedgers},
    edit: {element: <LegacyJournalEditRoute />, access: canManageLedgers},
  },
};

export const recordRoutes = (Object.keys(CORE_PERMISSIONS) as CoreArea[]).flatMap(area => {
  const {list, create, edit} = records[area];
  const canRead = requiresPermissions(CORE_PERMISSIONS[area]);
  return [
    workspaceRoute(area, list ?? <CoreListRoute area={area} />, canRead),
    workspaceRoute(area + '/new', create.element, user => canRead(user) && create.access(user)),
    workspaceRoute(area + '/:id/edit', edit.element, user => canRead(user) && edit.access(user)),
    workspaceRoute(area + '/:id', <CoreDetailRoute area={area} />, canRead),
  ];
});

const canManageMemberships = requiresPermissions('collections.read', 'users.manage');

export const groupRecordRoutes = [
  workspaceRoute('groups/:id/members/new', <MembershipCreateRoute />, canManageMemberships),
  workspaceRoute('groups/:groupId/members/:userId/edit', <MembershipEditRoute />, canManageMemberships),
  workspaceRoute('groups/:groupId/payees/new', <LegacyPayeeCreateRoute />, requiresPermissions('collections.read', 'receivers.manage')),
  workspaceRoute('groups/:groupId/ledger-accounts/new', <LegacyLedgerAccountCreateRoute />,
    requiresAdminRole('collections.read', 'ledger.read', 'ledger.manage', 'overview.read')),
];
