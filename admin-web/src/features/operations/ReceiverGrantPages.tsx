import { useCallback } from 'react';
import { useParams } from 'react-router';
import type { AdminRequest } from '../../api/client';
import { useSession } from '../../session/SessionProvider';
import { Card, StatusBadge } from '../../ui';
import { isValidId, parseGrantDetail, parseGrantPage, type ReceiverGrant } from './contracts';
import { DetailPage, Facts, RecordLink, RecordsPage, RelatedPagination, formatStatus, formatTime, query, statusTone, type Actor, type Column, type RecordsProps } from './OperationsRecords';
import { ReceiverGrantActionPanel } from './ReceiverGrantActionPanel';
import { ReceiverGrantCreatePanel } from './ReceiverGrantCreatePanel';

const grantStatuses = ['active', 'revoked'] as const;

const grantLoad: RecordsProps<ReceiverGrant>['load'] = async (request, offset, status) => parseGrantPage(await request(`gateway/receiver-grants?${query(offset, status)}`), offset, status);

const grantColumns: Column<ReceiverGrant>[] = [
  {label: 'Device', render: (row) => <RecordLink to={`/admin/gateway/receiver-grants/${row.id}`}>{row.device_label}</RecordLink>},
  {label: 'Payee', render: (row) => row.payee_label},
  {label: 'Collection number or code', render: (row) => row.payee_momo_number_or_code},
  {label: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{formatStatus(row.status)}</StatusBadge>},
  {label: 'Created', render: (row) => formatTime(row.created_at)},
];

export function ReceiverGrantsPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {epoch} = useSession();
  return <RecordsPage title="Receiver capture grants" subtitle="Review the link between a device and a payee." permission="gateway.read" statuses={grantStatuses} rowKey={(row) => row.id} columns={grantColumns} load={grantLoad} extra={(reload) => <><p className="operations-note">Capture does not grant sending, payment confirmation or financial authority.</p>{allowRecovery && <ReceiverGrantCreatePanel key={epoch} enabled={allowActions} onUpdated={reload} />}</>} />;
}

export function ReceiverGrantDetailPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {id = ''} = useParams();
  const {epoch} = useSession();
  const load = useCallback(async (request: AdminRequest, actor: Actor, offset: number) => parseGrantDetail(await request(`gateway/receiver-grants/${id}?limit=25&offset=${offset}`), id, actor.id, actor.canManageGateway, offset), [id]);
  return <DetailPage title="Receiver capture grant" subtitle="Review the recorded device and payee relationship." permission="gateway.read" back="/admin/gateway/receiver-grants" resourceKey={id} valid={isValidId(id)} load={load} render={(value, offset, setOffset, reload) => <>
    <p className="operations-note">Capture does not grant sending, payment confirmation or financial authority.</p>
    <Card className="operations-detail"><h2>Grant details</h2><Facts items={[
      ['Device', value.resource.device_label], ['Payee', value.resource.payee_label], ['Collection number or code', value.resource.payee_momo_number_or_code],
      ['Network', formatStatus(value.resource.payee_network)], ['Status', formatStatus(value.resource.status)], ['Created', formatTime(value.resource.created_at)],
      ['Revoked', formatTime(value.resource.revoked_at)], ['Grant ID', value.resource.id],
    ]} /></Card>
    {allowRecovery && <ReceiverGrantActionPanel key={`${epoch}:${id}`} grant={value.resource} canManage={value.canManage} enabled={allowActions} onUpdated={reload} />}
    <Card className="operations-detail"><h2>Recorded captures</h2>{value.captures.rows.length > 0 && <ul className="operations-related">{value.captures.rows.map((row) => <li key={row.id}><span>{row.id}</span><span>{formatTime(row.accepted_at)}</span></li>)}</ul>}<RelatedPagination page={value.captures} offset={offset} onChange={setOffset} /></Card>
  </>} />;
}
