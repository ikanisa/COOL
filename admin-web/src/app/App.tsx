import {Component, lazy, Suspense, useCallback, useMemo, type ReactNode} from 'react';
import {createHashRouter, Navigate, Outlet, RouterProvider, useLocation, useNavigate, useParams} from 'react-router';
import {AdminShell, type AdminNavItem} from '../layout/AdminShell';
import {Button, ErrorState, LoadingState, PageHeader} from '../ui';
import type {CoreArea, FeatureAccess} from '../features/core/types';
import {AccountSecurityPage, ForgotPasswordPage, LoginPage, PasswordSetupPage, SensitiveEmailVerificationPage} from '../session/AuthPages';
import {isVerifiedCurrentOwner, safeAdminReturnLocation, safeAdminVerificationReturnLocation, useSession, type SessionContextValue} from '../session/SessionProvider';
import {featureAuthorityKey} from './authority';
import {canOpenAdminPath} from './route-access';
import {verifySensitiveAccess} from './sensitive-access';
import './transaction-view.css';

// Large operator workflows load only when opened; the integrity-checked PWA
// package still retains every generated chunk for the installed build.
const core = () => import('../features/core');
const operations = () => import('../features/operations');
const reconciliation = () => import('../features/reconciliation/ReconciliationPages');
const ledgerAccounts = () => import('../features/ledger-accounts');
const legacyTransactions = () => import('../features/legacy-transactions');
const legacyPayees = () => import('../features/legacy-payees');
const legacyLedgerAccounts = () => import('../features/legacy-ledger-accounts');
const GroupSelectionPage = lazy(() => import('../features/route-compat/GroupSelectionPage').then(m => ({default: m.GroupSelectionPage})));
const CoreListPage = lazy(() => core().then(m => ({default: m.CoreListPage})));
const CoreRecordPage = lazy(() => core().then(m => ({default: m.CoreRecordPage})));
const GroupCreatePage = lazy(() => core().then(m => ({default: m.GroupCreatePage})));
const GroupEditPage = lazy(() => core().then(m => ({default: m.GroupEditPage})));
const LegacyPayeeCreatePage = lazy(() => core().then(m => ({default: m.LegacyPayeeCreatePage})));
const LegacyJournalPostPage = lazy(() => core().then(m => ({default: m.LegacyJournalPostPage})));
const LegacyJournalCreatePage = lazy(() => core().then(m => ({default: m.LegacyJournalCreatePage})));
const LegacyJournalEditPage = lazy(() => core().then(m => ({default: m.LegacyJournalEditPage})));
const MembershipCreatePage = lazy(() => core().then(m => ({default: m.MembershipCreatePage})));
const MembershipEditPage = lazy(() => core().then(m => ({default: m.MembershipEditPage})));
const PayeeEditPage = lazy(() => core().then(m => ({default: m.PayeeEditPage})));
const LegacyPayeeEditPage = lazy(() => legacyPayees().then(m => ({default: m.LegacyPayeeEditPage})));
const LegacyLedgerAccountCreatePage = lazy(() => legacyLedgerAccounts().then(m => ({default: m.LegacyLedgerAccountCreatePage})));
const LegacyTransactionCreate = lazy(() => legacyTransactions().then(m => ({default: m.LegacyTransactionCreate})));
const BuriMunsiPage = lazy(() => import('../features/burimunsi').then(m => ({default: m.BuriMunsiPage})));
const TransactionEvidencePage = lazy(() => core().then(m => ({default: m.TransactionEvidencePage})));
const TransactionReversePage = lazy(() => core().then(m => ({default: m.TransactionReversePage})));
const UserCreatePage = lazy(() => core().then(m => ({default: m.UserCreatePage})));
const UserEditPage = lazy(() => core().then(m => ({default: m.UserEditPage})));
const ReconciliationDetailPage = lazy(() => reconciliation().then(m => ({default: m.ReconciliationDetailPage})));
const ReconciliationQueuePage = lazy(() => reconciliation().then(m => ({default: m.ReconciliationQueuePage})));
const OverviewPage = lazy(() => import('../features/overview/OverviewPage').then(m => ({default: m.OverviewPage})));
const RequestHistoryPage = lazy(() => import('../features/requests/RequestHistoryPage').then(m => ({default: m.RequestHistoryPage})));
const LicensesPage = lazy(() => import('../features/licenses/LicensesPage').then(m => ({default: m.LicensesPage})));
const PrivacyPage = lazy(() => import('../features/privacy/PrivacyPage').then(m => ({default: m.PrivacyPage})));
const AssistedSmsPage = lazy(() => import('../features/assisted/AssistedSmsPage').then(m => ({default: m.AssistedSmsPage})));
const SmsControlsPage = lazy(() => import('../features/assisted/SmsControlsPage').then(m => ({default: m.SmsControlsPage})));
const LedgerAccountDetailPage = lazy(() => ledgerAccounts().then(m => ({default: m.LedgerAccountDetailPage})));
const LedgerAccountEditPage = lazy(() => ledgerAccounts().then(m => ({default: m.LedgerAccountEditPage})));
const SmsReceiptsPage = lazy(() => operations().then(m => ({default: m.SmsReceiptsPage})));
const SmsReceiptDetailPage = lazy(() => operations().then(m => ({default: m.SmsReceiptDetailPage})));
const GatewayDevicesPage = lazy(() => operations().then(m => ({default: m.GatewayDevicesPage})));
const GatewayDeviceDetailPage = lazy(() => operations().then(m => ({default: m.GatewayDeviceDetailPage})));
const ReceiverGrantsPage = lazy(() => operations().then(m => ({default: m.ReceiverGrantsPage})));
const ReceiverGrantDetailPage = lazy(() => operations().then(m => ({default: m.ReceiverGrantDetailPage})));
const MemberReceiptsPage = lazy(() => operations().then(m => ({default: m.MemberReceiptsPage})));
const MemberReceiptDetailPage = lazy(() => operations().then(m => ({default: m.MemberReceiptDetailPage})));
const EmailEventsPage = lazy(() => operations().then(m => ({default: m.EmailEventsPage})));
const MomoReceiptsPage = lazy(() => operations().then(m => ({default: m.MomoReceiptsPage})));
const GatewayEnrollmentPage = lazy(() => operations().then(m => ({default: m.GatewayEnrollmentPage})));
const AuthenticatorPage = lazy(() => import('../session/AuthenticatorPage').then(m => ({default: m.AuthenticatorPage})));
const TeamPage = lazy(() => import('../session/TeamPage').then(m => ({default: m.TeamPage})));

export class ScreenBoundary extends Component<{children: ReactNode}, {failed: boolean}> {
  state = {failed: false};
  static getDerivedStateFromError() {return {failed: true};}
  render() {
    return this.state.failed ? <ErrorState title="Page unavailable" message="Finish work in other Admin tabs, then reopen this page online."
      onRetry={() => window.location.reload()} /> : this.props.children;
  }
}

const coreAreas: readonly CoreArea[] = ['groups', 'users', 'members', 'payees', 'transactions', 'ledgers'];

type NavigationRule = AdminNavItem & {permission: string; alternativePermissions?: readonly string[]; requiredPermissions?: readonly string[]; ownerOnly?: boolean; ownerProof?: boolean};
const navigation: NavigationRule[] = [
  {label: 'Overview', path: '/admin', section: 'Workspace', icon: 'home', permission: 'overview.read'},
  {label: 'Groups', path: '/admin/groups', section: 'Workspace', icon: 'users', permission: 'collections.read'},
  {label: 'Users', path: '/admin/users', section: 'People', icon: 'user', permission: 'users.read'},
  {label: 'Members', path: '/admin/members', section: 'People', icon: 'users', permission: 'users.read'},
  {label: 'Payees', path: '/admin/payees', section: 'People', icon: 'contact', permission: 'receivers.read'},
  {label: 'Transactions', path: '/admin/transactions', section: 'Operations', icon: 'swap', permission: 'payments.read'},
  {label: 'Reconciliations', path: '/admin/reconciliations', section: 'Operations', icon: 'layers', permission: 'reconciliations.read'},
  {label: 'Ledgers', path: '/admin/ledgers', section: 'Operations', icon: 'book', permission: 'ledger.read'},
  {label: 'SMS receipts', path: '/admin/sms-receipts', section: 'Communications', icon: 'message', permission: 'sms.read'},
  {label: 'MoMo receipts', path: '/admin/momo-receipts', section: 'Communications', icon: 'message', permission: 'sms.read', alternativePermissions: ['payments.read']},
  {label: 'Assisted SMS', path: '/admin/notification-operator', section: 'Communications', icon: 'message', permission: 'assisted_sms.read'},
  {label: 'SMS controls', path: '/admin/notification-settings', section: 'Communications', icon: 'settings', permission: 'admin_users.manage', ownerOnly: true},
  {label: 'Gateway devices', path: '/admin/gateway', section: 'Communications', icon: 'smartphone', permission: 'gateway.read'},
  {label: 'Member receipts', path: '/admin/member-receipts', section: 'Communications', icon: 'file', permission: 'payments.read'},
  {label: 'Email notifications', path: '/admin/email', section: 'Communications', icon: 'message', permission: 'email.read'},
  {label: 'Request history', path: '/admin/requests', section: 'Administration', icon: 'clock', permission: 'overview.read'},
  {label: 'Privacy requests', path: '/admin/privacy-requests', section: 'Administration', icon: 'lock', permission: 'privacy.review'},
  {label: 'Admins and staff', path: '/admin/admin-users', section: 'Administration', icon: 'users', permission: 'admin_users.read'},
  {label: 'BuriMunsi access', path: '/admin/burimunsi', section: 'Administration', icon: 'lock', permission: 'admin_users.manage', requiredPermissions: ['receivers.read', 'receivers.manage'], ownerProof: true},
  {label: 'Password and security', path: '/admin/security', section: 'Administration', icon: 'settings', permission: 'account.manage'},
];

export function SessionProblem({session}: {session: Pick<SessionContextValue, 'logoutUnconfirmed' | 'mfaRecoveryPending' | 'error' | 'signOut' | 'refresh'>}) {
  return <><ErrorState title={session.logoutUnconfirmed ? 'Sign-out not confirmed' : 'Workspace unavailable'}
    message={session.error ?? 'Account access could not be checked.'}
    onRetry={() => {void (session.logoutUnconfirmed ? session.signOut() : session.refresh()).catch(() => undefined);}} />
    {!session.logoutUnconfirmed && <Button onClick={() => {void session.signOut().catch(() => undefined);}}>Sign out of this session</Button>}
  </>;
}

function SessionState({children}: {children: ReactNode}) {
  const session = useSession();
  if (session.status === 'loading') return <LoadingState label="Checking account access" />;
  if (session.logoutUnconfirmed || session.status === 'error' && session.mfaRecoveryPending) return <SessionProblem session={session} />;
  return children;
}

function ProtectedShell() {
  const session = useSession(), location = useLocation();
  if (session.status === 'loading') return <LoadingState label="Checking account access" />;
  if (session.status === 'error') return <SessionProblem session={session} />;
  if (!session.user) {
    const requested = safeAdminReturnLocation(`${location.pathname}${location.search}`);
    return <Navigate to={`/admin/login${requested ? `?${new URLSearchParams({returnTo: requested})}` : ''}`} replace />;
  }
  const user = session.user;
  const permitted = navigation.filter((item) => (user.permissions.includes(item.permission) || item.alternativePermissions?.some(permission => user.permissions.includes(permission))) &&
    (!item.requiredPermissions || item.requiredPermissions.every(permission => user.permissions.includes(permission))) && (!item.ownerOnly || user.role === 'owner') &&
    (!item.ownerProof || user.financialModel === 'canonical_evidence_ledger' && isVerifiedCurrentOwner(user)) && canOpenAdminPath(item.path, user));
  return <AdminShell navigation={permitted} currentPath={`${location.pathname}${location.search}`}
    identity={{name: user.email, role: user.role === 'owner' ? 'Owner' : user.role === 'admin' ? 'Admin' : 'Staff'}}
    onSignOut={() => {void session.signOut().catch(() => undefined);}}>
    {canOpenAdminPath(location.pathname, user) ? <ScreenBoundary key={location.pathname}><Suspense fallback={<LoadingState label="Opening workspace" />}><Outlet /></Suspense></ScreenBoundary> : <ErrorState title="Access unavailable"
      message="Your account cannot open this page." />}
  </AdminShell>;
}

function useAccess(): FeatureAccess {
  const session = useSession(), go = useNavigate();
  if (!session.user) throw new Error('The workspace session is unavailable.');
  const user = session.user;
  const authorityKey = featureAuthorityKey(session.epoch, user);
  return {request: session.request, permissions: user.permissions, actorId: user.id, principalId: user.principalId,
    role: user.role, authorityKey, financialModel: user.financialModel, navigate: go};
}

function OverviewRoute() {
  const access = useAccess();
  return <OverviewPage key={access.authorityKey} request={access.request} permissions={access.permissions}
    financialModel={access.financialModel} authorityKey={access.authorityKey} />;
}

function CoreListRoute({area}: {area: CoreArea}) {
  const access = useAccess(), location = useLocation();
  return <CoreListPage key={`${access.authorityKey}:${area}`} {...access} area={area} locationSearch={location.search} />;
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

function CoreDetailRoute({area}: {area: CoreArea}) {
  const access = useAccess(), sensitive = useSensitiveAccess(), isCurrent = useCurrentAuthority(), {id = ''} = useParams(), location = useLocation();
  return <CoreRecordPage key={`${access.authorityKey}:${area}:${id}`} {...access} identity={sensitive.identity} area={area} id={id}
    isCurrent={isCurrent} returnTo={new URLSearchParams(location.search).get('returnTo')} />;
}

function useCurrentAuthority() {
  const session = useSession(), user = session.user!;
  const {epoch, isCurrentAuthority} = session, {id, sessionId} = user;
  return useCallback(() => isCurrentAuthority(epoch, id, sessionId), [epoch, id, sessionId, isCurrentAuthority]);
}

function useSensitiveAccess() {
  const session = useSession();
  const user = session.user!;
  return {identity: {id: user.id, sessionId: user.sessionId, email: user.email, role: user.role,
    permissions: user.permissions, expiresAt: user.expiresAt}, verifyFresh: () => verifySensitiveAccess(session, user)};
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

function LegacyJournalPostRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {id = ''} = useParams();
  return <LegacyJournalPostPage key={`${access.authorityKey}:${id}`} {...access} id={id} identity={sensitive.identity} allowMutations={false} />;
}

function LegacyJournalCreateRoute() {
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

function LegacyJournalEditRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), {id = ''} = useParams();
  return <LegacyJournalEditPage key={`${access.authorityKey}:${id}`} {...access} id={id} identity={sensitive.identity} allowMutations={false} />;
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

function TransactionEvidenceRoute() {
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

function ReconciliationRoute({detail = false}: {detail?: boolean}) {
  const access = useAccess(), sensitive = useSensitiveAccess(), location = useLocation(), {id = ''} = useParams();
  return detail ? <ReconciliationDetailPage key={`${access.authorityKey}:${id}`} {...access} id={id}
    {...sensitive} allowMutations={false} returnTo={new URLSearchParams(location.search).get('returnTo')} /> :
    <ReconciliationQueuePage key={access.authorityKey} {...access} locationSearch={location.search} />;
}

function RequestHistoryRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), location = useLocation();
  return <RequestHistoryPage key={`${access.authorityKey}:${location.search}`} {...access} {...sensitive}
    allowCancellation={false} locationSearch={location.search} />;
}

function UnavailablePage({title}: {title: string}) {
  const go = useNavigate();
  return <><PageHeader title={title} /><ErrorState title="Workspace unavailable"
    message="This part of your workspace is unavailable." /><Button onClick={() => go('/admin')}>Go to overview</Button></>;
}

function LoginRoute() {
  const go = useNavigate(), location = useLocation();
  const destination = safeAdminReturnLocation(new URLSearchParams(location.search).get('returnTo')) ?? '/admin';
  const onSignedIn = useCallback(() => go(destination, {replace: true}), [destination, go]);
  const onForgotPassword = useCallback(() => go(`/admin/forgot-password?${new URLSearchParams({returnTo: destination})}`), [destination, go]);
  return <SessionState><LoginPage onSignedIn={onSignedIn} onForgotPassword={onForgotPassword} /></SessionState>;
}

export function SessionRedirectRoute() {
  const location = useLocation();
  const destination = safeAdminReturnLocation(new URLSearchParams(location.search).get('returnTo')) ?? '/admin';
  return <Navigate to={destination} replace />;
}

function ForgotPasswordRoute() {
  const go = useNavigate(), location = useLocation();
  const destination = safeAdminReturnLocation(new URLSearchParams(location.search).get('returnTo'));
  return <SessionState><ForgotPasswordPage onBackToLogin={() => go(`/admin/login${destination ? `?${new URLSearchParams({returnTo: destination})}` : ''}`)} /></SessionState>;
}

function SetupRoute({setup}: {setup: {token: string; invite: boolean} | null}) {
  const go = useNavigate();
  return <SessionState><PasswordSetupPage setup={setup} onBackToLogin={() => go('/admin/login')}
    onRequestReset={() => go('/admin/forgot-password')} /></SessionState>;
}

function VerifyEmailRoute() {
  const go = useNavigate(), location = useLocation(), session = useSession();
  const destination = safeAdminVerificationReturnLocation(new URLSearchParams(location.search).get('returnTo')) ?? '/admin';
  if (session.verificationMode !== 'email') return <Navigate to="/admin/security/authenticator" replace />;
  return <SensitiveEmailVerificationPage onDone={(completed) => go(completed && session.user?.mfaRequired ?
    `/admin/security/authenticator?${new URLSearchParams({returnTo: destination})}` : destination, {replace: true})} />;
}

function AccountSecurityRoute() {
  const session = useSession(), go = useNavigate();
  if (!session.user?.permissions.includes('account.manage')) return <UnavailablePage title="Account security" />;
  return <AccountSecurityPage onVerify={() => go(session.verificationMode === 'email' ? '/admin/security/verify-email?returnTo=%2Fadmin%2Fsecurity' : '/admin/security/authenticator')}
    onAuthenticator={() => go('/admin/security/authenticator?returnTo=%2Fadmin%2Fsecurity')}
    onLicenses={() => go('/admin/licenses')} onPasswordRecovery={() => go('/admin/forgot-password')}
    onSignIn={() => go('/admin/login', {replace: true})} />;
}

function AuthenticatorRoute() {
  const session = useSession(), go = useNavigate(), location = useLocation();
  const destination = safeAdminVerificationReturnLocation(new URLSearchParams(location.search).get('returnTo')) ?? '/admin/security';
  if (session.verificationMode === 'email' && !session.user?.mfaAvailable) return <Navigate to="/admin/security/verify-email" replace />;
  return <AuthenticatorPage onBack={() => go(destination)} onSignIn={() => go('/admin/login', {replace: true})} />;
}

function TeamRoute() {
  const session = useSession(), go = useNavigate();
  return <TeamPage onVerify={() => go(`/admin/security/${session.verificationMode === 'email' ? 'verify-email' : 'authenticator'}?returnTo=%2Fadmin%2Fadmin-users`)} />;
}

function PrivacyRoute() {
  const session = useSession(), sensitive = useSensitiveAccess(), go = useNavigate(), access = useAccess();
  return <PrivacyPage key={access.authorityKey} user={session.user!} epoch={session.epoch} verificationMode={session.verificationMode}
    request={session.request} verifyFresh={sensitive.verifyFresh} isCurrentAuthority={session.isCurrentAuthority}
    onVerify={() => go(`/admin/security/${session.verificationMode === 'email' ? 'verify-email' : 'authenticator'}?returnTo=%2Fadmin%2Fprivacy-requests`)} />;
}

function AssistedSmsRoute() {
  const session = useSession(), go = useNavigate(), access = useAccess();
  return <AssistedSmsPage key={access.authorityKey} onVerify={() => go(`/admin/security/${session.verificationMode === 'email' ? 'verify-email' : 'authenticator'}?returnTo=%2Fadmin%2Fnotification-operator`)} />;
}

function SmsControlsRoute() {
  const session = useSession(), go = useNavigate(), access = useAccess();
  return <SmsControlsPage key={access.authorityKey} onVerify={() => go(`/admin/security/${session.verificationMode === 'email' ? 'verify-email' : 'authenticator'}?returnTo=%2Fadmin%2Fnotification-settings`)} />;
}

function BuriMunsiRoute() {
  const go = useNavigate();
  return <BuriMunsiPage operatorApprovalEnabled nativeAdministrationEnabled
    onBack={() => go('/admin')} onVerify={() => go('/admin/security/verify-email?returnTo=%2Fadmin%2Fburimunsi')} />;
}

export function makeAdminRouter(setup: {token: string; invite: boolean} | null) {
  const protectedChildren = [
    {index: true, element: <OverviewRoute />},
    ...coreAreas.flatMap((area) => [
      {path: area, element: area === 'transactions' ? <TransactionListRoute /> : <CoreListRoute area={area} />},
      {path: `${area}/new`, element: area === 'groups' ? <GroupCreateRoute /> : area === 'users' ? <UserCreateRoute /> : area === 'members' ? <GroupSelectionRoute action="member" /> : area === 'payees' ? <GroupSelectionRoute action="payee" /> : area === 'transactions' ? <TransactionEvidenceRoute /> : <LegacyJournalCreateRoute />},
      {path: `${area}/:id/edit`, element: area === 'groups' ? <GroupEditRoute /> : area === 'payees' ? <PayeeEditRoute /> : area === 'users' || area === 'members' ? <UserEditRoute returnArea={area} /> : area === 'ledgers' ? <LegacyJournalEditRoute /> : <UnavailablePage title={`Edit ${area.slice(0, -1)}`} />},
      {path: `${area}/:id`, element: <CoreDetailRoute area={area} />},
    ]),
    {path: 'reconciliations', element: <ReconciliationRoute />},
    {path: 'reconciliations/:id', element: <ReconciliationRoute detail />},
    {path: 'groups/:id/members/new', element: <MembershipCreateRoute />},
    {path: 'groups/:groupId/members/:userId/edit', element: <MembershipEditRoute />},
    {path: 'groups/:groupId/payees/new', element: <LegacyPayeeCreateRoute />},
    {path: 'groups/:groupId/ledger-accounts/new', element: <LegacyLedgerAccountCreateRoute />},
    {path: 'groups/:groupId/journals/new', element: <LegacyGroupJournalCreateRoute />},
    {path: 'groups/:groupId/transactions/new', element: <LegacyGroupTransactionCreateRoute />},
    {path: 'transactions/:id/reverse', element: <TransactionReverseRoute />},
    {path: 'transactions/:id/allocations/:allocationId/journal/new', element: <LegacyAllocationJournalCreateRoute />},
    {path: 'ledgers/:id/post', element: <LegacyJournalPostRoute />},
    {path: 'requests', element: <RequestHistoryRoute />},
    {path: 'security/verify-email', element: <VerifyEmailRoute />},
    {path: 'security', element: <AccountSecurityRoute />},
    {path: 'security/authenticator', element: <AuthenticatorRoute />},
    {path: 'licenses', element: <LicensesPage />},
    {path: 'admin-users', element: <TeamRoute />},
    {path: 'sms-receipts', element: <SmsReceiptsPage />},
    {path: 'sms-receipts/:kind/:id', element: <SmsReceiptDetailPage />},
    {path: 'gateway', element: <GatewayDevicesPage />},
    {path: 'gateway/new', element: <GatewayEnrollmentPage />},
    {path: 'gateway/receiver-grants', element: <ReceiverGrantsPage />},
    {path: 'gateway/receiver-grants/:id', element: <ReceiverGrantDetailPage />},
    {path: 'gateway/:id', element: <GatewayDeviceDetailPage />},
    {path: 'member-receipts', element: <MemberReceiptsPage />},
    {path: 'member-receipts/:id', element: <MemberReceiptDetailPage />},
    {path: 'email', element: <EmailEventsPage />},
    {path: 'momo-receipts', element: <MomoReceiptsPage />},
    {path: 'notification-operator', element: <AssistedSmsRoute />},
    {path: 'notification-settings', element: <SmsControlsRoute />},
    {path: 'burimunsi', element: <BuriMunsiRoute />},
    {path: 'ledger-accounts/:id', element: <LedgerAccountDetailPage />},
    {path: 'ledger-accounts/:id/edit', element: <LedgerAccountEditPage />},
    {path: 'privacy-requests', element: <PrivacyRoute />},
  ];
  return createHashRouter([
    {path: '/', element: <Navigate to="/admin" replace />},
    {path: '/admin/login', element: <LoginRoute />},
    {path: '/admin/forgot-password', element: <ForgotPasswordRoute />},
    {path: '/admin/setup', element: <SetupRoute setup={setup} />},
    {path: '/admin/session', element: <SessionRedirectRoute />},
    {path: '/admin', element: <ProtectedShell />, children: protectedChildren},
    {path: '*', element: <UnavailablePage title="Page unavailable" />},
  ]);
}

export function AdminApp({setup}: {setup: {token: string; invite: boolean} | null}) {
  const router = useMemo(() => makeAdminRouter(setup), [setup]);
  return <RouterProvider router={router} />;
}
