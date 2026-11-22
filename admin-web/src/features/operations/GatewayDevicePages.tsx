import { useCallback } from 'react';
import { Link, useParams } from 'react-router';
import type { AdminRequest } from '../../api/client';
import { useSession } from '../../session/SessionProvider';
import { Card, StatusBadge } from '../../ui';
import { isValidId, parseGatewayDetail, parseGatewayPage, type GatewayDevice } from './contracts';
import { GatewayTrustPanel } from './GatewayTrustPanel';
import { DetailPage, Facts, RecordLink, RecordsPage, formatStatus, formatTime, statusTone, type Actor, type Column, type RecordsProps } from './OperationsRecords';

const gatewayStatuses = ['pending', 'active', 'revoked'] as const;

const gatewayLoad: RecordsProps<GatewayDevice>['load'] = async (request, offset, status) => {
  const params = new URLSearchParams({limit: '25', offset: String(offset)}); if (status) params.set('state', status);
  return parseGatewayPage(await request(`gateway/devices?${params}`), offset, status);
};

const gatewayColumns: Column<GatewayDevice>[] = [
  {label: 'Device', render: (row) => <RecordLink to={`/admin/gateway/${row.id}`}>{row.label}</RecordLink>},
  {label: 'Status', render: (row) => <StatusBadge tone={statusTone(row.state)}>{formatStatus(row.state)}</StatusBadge>},
  {label: 'Last heartbeat', render: (row) => formatTime(row.last_heartbeat_at)},
  {label: 'Version', render: (row) => row.version},
];

export function GatewayDevicesPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {user} = useSession();
  const canRecover = !!user && user.role !== 'staff' && user.financialModel === 'transaction_journals' && ['gateway.read', 'gateway.manage', 'overview.read'].every((permission) => user.permissions.includes(permission));
  return <RecordsPage title="Gateway devices" subtitle="Review enrolled devices and their reported status." permission="gateway.read" statuses={gatewayStatuses} rowKey={(row) => row.id} columns={gatewayColumns} load={gatewayLoad} extra={<p className="operations-note"><Link className="operations-link" to="/admin/gateway/receiver-grants">View receiver capture grants</Link>{allowRecovery && canRecover && <> · <Link className="operations-link" to="/admin/gateway/new">{allowActions ? 'Enroll device' : 'Check gateway enrollment request'}</Link></>}</p>} />;
}

export function GatewayDeviceDetailPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {id = ''} = useParams();
  const {epoch} = useSession();
  const load = useCallback(async (request: AdminRequest, actor: Actor) => parseGatewayDetail(await request(`gateway/devices/${id}`), id, actor.id, actor.role === 'staff'), [id]);
  return <DetailPage title="Gateway device" subtitle="Review the device and its reported observations." permission="gateway.read" back="/admin/gateway" resourceKey={id} valid={isValidId(id)} load={load} render={(value, _offset, _setOffset, reload) => <>
    <p className="operations-note">Device observations do not establish carrier proof or sending authority.</p>
    <Card className="operations-detail"><h2>Device details</h2><Facts items={[
      ['Label', value.resource.label], ['Status', formatStatus(value.resource.state)], ['Device ID', value.resource.id],
      ['Application', value.resource.app_id], ['Installation', value.resource.installation_id], ['Version', value.resource.version],
      ['Created', formatTime(value.resource.created_at)], ['Last heartbeat', formatTime(value.resource.last_heartbeat_at)],
      ['Key fingerprint', value.resource.key_sha256], ['Signing certificate', value.resource.signing_certificate_sha256],
    ]} /></Card>
    {allowRecovery && <><GatewayTrustPanel mode="activate" key={`${epoch}:${id}:activate`} device={value.resource} canManage={value.canManage} enabled={allowActions} onUpdated={reload} />
    <GatewayTrustPanel mode="revoke" key={`${epoch}:${id}:revoke`} device={value.resource} canManage={value.canManage} enabled={allowActions} onUpdated={reload} /></>}
    <Card className="operations-detail"><h2>Enrollment response</h2><p>This public response identifies the enrolled installation.</p><pre className="operations-source-content">{JSON.stringify(value.enrollment, null, 2)}</pre></Card>
    <Card className="operations-detail"><h2>Device observations</h2>{value.heartbeats.length ? <div className="admin-table-wrap" tabIndex={0} role="region" aria-label="Device observations"><table className="admin-table"><thead><tr><th scope="col">Reported</th><th scope="col">Network</th><th scope="col">Telephony</th><th scope="col">SMS permission</th><th scope="col">Local pause</th></tr></thead><tbody>{value.heartbeats.map((row) => <tr key={row.observation_id}><td>{formatTime(row.reported_at)}</td><td>{formatStatus(row.network)}</td><td>{formatStatus(row.telephony)}</td><td>{row.sms_permission ? 'Granted' : 'Not granted'}</td><td>{row.local_pause ? 'Paused' : 'Not paused'}</td></tr>)}</tbody></table></div> : <p>No observations recorded.</p>}{value.truncated && <p>Additional observations are not shown.</p>}</Card>
  </>} />;
}
