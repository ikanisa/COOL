import {lazy} from 'react';
import {useLocation, useNavigate} from 'react-router';
import {canReadRequestHistory} from '../../features/requests/permissions';
import {isVerifiedCurrentOwner} from '../../session/ownerIdentity';
import {useSession} from '../../session/SessionProvider';
import {verificationPath} from '../../session/returnLocation';
import {useAccess, useSensitiveAccess} from './access';
import {requiresPermissions, workspaceRoute} from './routePolicy';

const OverviewPage = lazy(() => import('../../features/overview/OverviewPage').then(m => ({default: m.OverviewPage})));
const RequestHistoryPage = lazy(() => import('../../features/requests/RequestHistoryPage').then(m => ({default: m.RequestHistoryPage})));
const SmsReceiptsPage = lazy(() => import('../../features/operations/SmsReceiptPages').then(m => ({default: m.SmsReceiptsPage})));
const SmsReceiptDetailPage = lazy(() => import('../../features/operations/SmsReceiptPages').then(m => ({default: m.SmsReceiptDetailPage})));
const GatewayDevicesPage = lazy(() => import('../../features/operations/GatewayDevicePages').then(m => ({default: m.GatewayDevicesPage})));
const GatewayEnrollmentPage = lazy(() => import('../../features/operations/GatewayEnrollmentPage').then(m => ({default: m.GatewayEnrollmentPage})));
const GatewayDeviceDetailPage = lazy(() => import('../../features/operations/GatewayDevicePages').then(m => ({default: m.GatewayDeviceDetailPage})));
const ReceiverGrantsPage = lazy(() => import('../../features/operations/ReceiverGrantPages').then(m => ({default: m.ReceiverGrantsPage})));
const ReceiverGrantDetailPage = lazy(() => import('../../features/operations/ReceiverGrantPages').then(m => ({default: m.ReceiverGrantDetailPage})));
const MemberReceiptsPage = lazy(() => import('../../features/operations/MemberReceiptPages').then(m => ({default: m.MemberReceiptsPage})));
const MemberReceiptDetailPage = lazy(() => import('../../features/operations/MemberReceiptPages').then(m => ({default: m.MemberReceiptDetailPage})));
const EmailEventsPage = lazy(() => import('../../features/operations/EmailEventsPage').then(m => ({default: m.EmailEventsPage})));
const AssistedSmsPage = lazy(() => import('../../features/assisted/AssistedSmsPage').then(m => ({default: m.AssistedSmsPage})));
const SmsControlsPage = lazy(() => import('../../features/assisted/SmsControlsPage').then(m => ({default: m.SmsControlsPage})));
const BuriMunsiPage = lazy(() => import('../../features/burimunsi').then(m => ({default: m.BuriMunsiPage})));

export const MomoReceiptsPage = lazy(() => import('../../features/operations/MomoReceiptsPage').then(m => ({default: m.MomoReceiptsPage})));

export function OverviewRoute() {
  const access = useAccess();
  return <OverviewPage key={access.authorityKey} request={access.request} permissions={access.permissions}
    financialModel={access.financialModel} authorityKey={access.authorityKey} />;
}

function RequestHistoryRoute() {
  const access = useAccess(), sensitive = useSensitiveAccess(), location = useLocation();
  return <RequestHistoryPage key={`${access.authorityKey}:${location.search}`} {...access} {...sensitive}
    allowCancellation={false} locationSearch={location.search} />;
}

function AssistedSmsRoute() {
  const session = useSession(), go = useNavigate(), access = useAccess();
  return <AssistedSmsPage key={access.authorityKey} onVerify={() => go(verificationPath(session.verificationMode, '/admin/notification-operator'))} />;
}

function SmsControlsRoute() {
  const session = useSession(), go = useNavigate(), access = useAccess();
  return <SmsControlsPage key={access.authorityKey} onVerify={() => go(verificationPath(session.verificationMode, '/admin/notification-settings'))} />;
}

function BuriMunsiRoute() {
  const go = useNavigate();
  return <BuriMunsiPage operatorApprovalEnabled nativeAdministrationEnabled
    onBack={() => go('/admin')} onVerify={() => go(verificationPath('email', '/admin/burimunsi'))} />;
}

const canReadSms = requiresPermissions('sms.read');
const canReadGateway = requiresPermissions('gateway.read');
const canReadPayments = requiresPermissions('payments.read');
const canManageReceiverAccess = requiresPermissions('admin_users.manage', 'receivers.read', 'receivers.manage');

export const requestHistoryRoute = workspaceRoute('requests', <RequestHistoryRoute />,
  user => canReadRequestHistory(user.financialModel, user.permissions));

export const operatorRoutes = [
  workspaceRoute('sms-receipts', <SmsReceiptsPage />, canReadSms),
  workspaceRoute('sms-receipts/:kind/:id', <SmsReceiptDetailPage />, canReadSms),
  workspaceRoute('gateway', <GatewayDevicesPage />, canReadGateway),
  workspaceRoute('gateway/new', <GatewayEnrollmentPage />, requiresPermissions('gateway.read', 'gateway.manage')),
  workspaceRoute('gateway/receiver-grants', <ReceiverGrantsPage />, canReadGateway),
  workspaceRoute('gateway/receiver-grants/:id', <ReceiverGrantDetailPage />, canReadGateway),
  workspaceRoute('gateway/:id', <GatewayDeviceDetailPage />, canReadGateway),
  workspaceRoute('member-receipts', <MemberReceiptsPage />, canReadPayments),
  workspaceRoute('member-receipts/:id', <MemberReceiptDetailPage />, canReadPayments),
  workspaceRoute('email', <EmailEventsPage />, requiresPermissions('email.read')),
  workspaceRoute('momo-receipts', <MomoReceiptsPage />, user => canReadSms(user) || canReadPayments(user)),
  workspaceRoute('notification-operator', <AssistedSmsRoute />, requiresPermissions('assisted_sms.read')),
  workspaceRoute('notification-settings', <SmsControlsRoute />, user => user.role === 'owner' && user.permissions.includes('admin_users.manage')),
  workspaceRoute('burimunsi', <BuriMunsiRoute />, user => user.financialModel === 'canonical_evidence_ledger' &&
    isVerifiedCurrentOwner(user) && canManageReceiverAccess(user)),
];
