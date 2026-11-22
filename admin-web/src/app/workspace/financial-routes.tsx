import {lazy} from 'react';
import {useLocation, useParams} from 'react-router';
import {Button, PageHeader} from '../../ui';
import {useAccess, useCurrentAuthority, useSensitiveAccess} from './access';
import {requiresAdminRole, requiresPermissions, workspaceRoute} from './routePolicy';

const LegacyJournalCreatePage = lazy(() => import('../../features/core/LegacyJournalCreatePage').then(m => ({default: m.LegacyJournalCreatePage})));
const LegacyJournalEditPage = lazy(() => import('../../features/core/LegacyJournalEditPage').then(m => ({default: m.LegacyJournalEditPage})));
const LegacyJournalPostPage = lazy(() => import('../../features/core/LegacyJournalPostPage').then(m => ({default: m.LegacyJournalPostPage})));
const LegacyTransactionCreate = lazy(() => import('../../features/legacy-transactions/LegacyTransactionCreate').then(m => ({default: m.LegacyTransactionCreate})));
const TransactionEvidencePage = lazy(() => import('../../features/core/TransactionEvidencePage').then(m => ({default: m.TransactionEvidencePage})));
const TransactionReversePage = lazy(() => import('../../features/core/TransactionReversePage').then(m => ({default: m.TransactionReversePage})));
const ReconciliationDetailPage = lazy(() => import('../../features/reconciliation/ReconciliationDetailPage').then(m => ({default: m.ReconciliationDetailPage})));
const ReconciliationQueuePage = lazy(() => import('../../features/reconciliation/ReconciliationQueuePage').then(m => ({default: m.ReconciliationQueuePage})));
const LedgerAccountDetailPage = lazy(() => import('../../features/ledger-accounts/LedgerAccountPages').then(m => ({default: m.LedgerAccountDetailPage})));
const LedgerAccountEditPage = lazy(() => import('../../features/ledger-accounts/LedgerAccountPages').then(m => ({default: m.LedgerAccountEditPage})));

export function TransactionEvidenceRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), isCurrent = useCurrentAuthority();
  return access.financialModel === 'transaction_journals' ? <>
    <PageHeader title="Record payment evidence" actions={<Button onClick={() => access.navigate('/admin/transactions')}>Back to transactions</Button>} />
    <LegacyTransactionCreate key={access.authorityKey} request={access.request} identity={sensitive.identity} permissions={access.permissions}
      financialModel={access.financialModel} authorityKey={access.authorityKey} isCurrent={isCurrent} allowMutations={false}
      onCreated={id => access.navigate(`/admin/transactions/${id}`)} />
  </> : <TransactionEvidencePage key={access.authorityKey} {...access} {...sensitive} allowMutations={false} />;
}

function LegacyGroupTransactionCreateRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), isCurrent = useCurrentAuthority(), {groupId = ''} = useParams();
  return <>
    <PageHeader title="Record payment evidence" actions={<Button onClick={() => access.navigate(`/admin/groups/${groupId}`)}>Back to group</Button>} />
    <LegacyTransactionCreate key={`${access.authorityKey}:${groupId}`} request={access.request} identity={sensitive.identity} permissions={access.permissions}
      financialModel={access.financialModel} authorityKey={access.authorityKey} isCurrent={isCurrent} initialGroupId={groupId} allowMutations={false}
      onCreated={id => access.navigate(`/admin/transactions/${id}`)} />
  </>;
}

function TransactionReverseRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {id = ''} = useParams();
  return <TransactionReversePage key={`${access.authorityKey}:${id}`} {...access} id={id} {...sensitive} allowMutations={false} />;
}

export function LegacyJournalCreateRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess();
  return <LegacyJournalCreatePage key={access.authorityKey} {...access} identity={sensitive.identity} allowMutations={false} />;
}

function LegacyGroupJournalCreateRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {groupId = ''} = useParams();
  return <LegacyJournalCreatePage key={`${access.authorityKey}:${groupId}`} {...access} identity={sensitive.identity} fixedGroupId={groupId} allowMutations={false} />;
}

function LegacyAllocationJournalCreateRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {id = '', allocationId = ''} = useParams();
  return <LegacyJournalCreatePage key={`${access.authorityKey}:${id}:${allocationId}`} {...access} identity={sensitive.identity}
    transactionId={id} allocationId={allocationId} allowMutations={false} />;
}

export function LegacyJournalEditRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {id = ''} = useParams();
  return <LegacyJournalEditPage key={`${access.authorityKey}:${id}`} {...access} id={id} identity={sensitive.identity} allowMutations={false} />;
}

function LegacyJournalPostRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {id = ''} = useParams();
  return <LegacyJournalPostPage key={`${access.authorityKey}:${id}`} {...access} id={id} identity={sensitive.identity} allowMutations={false} />;
}

function ReconciliationRoute({detail = false}: {detail?: boolean}) {
  const access = useAccess(), sensitive = useSensitiveAccess(), location = useLocation(), {id = ''} = useParams();
  return detail ? <ReconciliationDetailPage key={`${access.authorityKey}:${id}`} {...access} id={id}
    {...sensitive} allowMutations={false} returnTo={new URLSearchParams(location.search).get('returnTo')} /> :
    <ReconciliationQueuePage key={access.authorityKey} {...access} locationSearch={location.search} />;
}

const canReadReconciliation = requiresPermissions('reconciliations.read');
const canReadLedger = requiresPermissions('ledger.read');
const canWriteLedger = requiresPermissions('ledger.read', 'ledger.manage');

export const reconciliationRoutes = [
  workspaceRoute('reconciliations', <ReconciliationRoute />, canReadReconciliation),
  workspaceRoute('reconciliations/:id', <ReconciliationRoute detail />, canReadReconciliation),
];

export const financialActionRoutes = [
  workspaceRoute('groups/:groupId/journals/new', <LegacyGroupJournalCreateRoute />,
    requiresAdminRole('collections.read', 'ledger.read', 'ledger.manage', 'overview.read')),
  workspaceRoute('groups/:groupId/transactions/new', <LegacyGroupTransactionCreateRoute />,
    requiresAdminRole('collections.read', 'payments.read', 'payments.manage', 'receivers.read', 'overview.read')),
  workspaceRoute('transactions/:id/reverse', <TransactionReverseRoute />,
    requiresPermissions('payments.read', 'payments.reconcile')),
  workspaceRoute('transactions/:id/allocations/:allocationId/journal/new', <LegacyAllocationJournalCreateRoute />,
    requiresPermissions('payments.read', 'ledger.read', 'ledger.manage')),
  workspaceRoute('ledgers/:id/post', <LegacyJournalPostRoute />, canWriteLedger),
];

export const ledgerAccountRoutes = [
  workspaceRoute('ledger-accounts/:id', <LedgerAccountDetailPage />, canReadLedger),
  workspaceRoute('ledger-accounts/:id/edit', <LedgerAccountEditPage />, canWriteLedger),
];
