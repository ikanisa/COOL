import { useCallback } from 'react';
import { useParams } from 'react-router';
import type { AdminRequest } from '../../api/client';
import { useSession } from '../../session/SessionProvider';
import { Card, StatusBadge } from '../../ui';
import { ReceiptReviewPanel } from '../receipt-review';
import { isValidId, parseMemberDetail, parseMemberPage, type MemberReceipt } from './contracts';
import { DetailPage, Facts, RecordLink, RecordsPage, formatStatus, formatTime, query, statusTone, useActor, type Actor, type Column, type RecordsProps } from './OperationsRecords';

const memberLoad: RecordsProps<MemberReceipt>['load'] = async (request, offset, status, _search, actor) => parseMemberPage(await request(`gateway/receipts?${query(offset, status)}`), offset, actor.canonical, status);

const memberColumns: Column<MemberReceipt>[] = [
  {label: 'Receipt', render: (row) => <RecordLink to={`/admin/member-receipts/${row.id}`}>{row.id.slice(0, 8)}</RecordLink>},
  {label: 'Member', render: (row) => row.display_name ?? row.public_id ?? 'Not recorded'},
  {label: 'Received', render: (row) => formatTime(row.received_at)},
  {label: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{formatStatus(row.status)}</StatusBadge>},
];

export function MemberReceiptsPage() {
  const {actor} = useActor();
  const statuses = actor?.canonical ? ['received', 'under_review', 'rejected', 'linked'] : ['needs_review', 'reviewed', 'rejected'];
  return <RecordsPage title="Member receipts" subtitle="Review recorded member receipt evidence." permission="payments.read" statuses={statuses} rowKey={(row) => row.id} columns={memberColumns} load={memberLoad} extra={<p className="operations-note">A receipt is evidence and does not by itself confirm provider settlement.</p>} />;
}

export function MemberReceiptDetailPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {id = ''} = useParams();
  const {epoch} = useSession();
  const load = useCallback(async (request: AdminRequest, actor: Actor) => parseMemberDetail(await request(`gateway/receipts/${id}`), id, actor.id, actor.role === 'staff', actor.canonical), [id]);
  return <DetailPage title="Member receipt" subtitle="Review the recorded receipt and its review history." permission="payments.read" back="/admin/member-receipts" resourceKey={id} valid={isValidId(id)} load={load} render={(value, _offset, _setOffset, reload) => <>
    <p className="operations-note">A receipt is evidence and does not by itself confirm provider settlement.</p>
    <Card className="operations-detail"><h2>Receipt details</h2><Facts items={[
      ['Receipt ID', value.resource.id], ['Member', value.resource.display_name ?? value.resource.public_id],
      ['Status', formatStatus(value.resource.status)], ['Received', formatTime(value.resource.received_at)],
      ['Created', formatTime(value.resource.created_at)], ['Version', value.resource.version], ['Evidence SHA-256', value.resource.body_sha256],
    ]} /></Card>
    {allowRecovery && <ReceiptReviewPanel key={`${epoch}:${id}`} receipt={value.resource} canManage={value.canManage} enabled={allowActions} allowAttachment={false} onUpdated={reload} />}
    <Card className="operations-detail"><h2>Review history</h2>{value.reviews.length ? <ul className="operations-related">{value.reviews.map((row) => <li key={row.id}><span>{formatStatus(row.outcome)} · {row.reason}</span><span>{formatTime(row.reviewed_at)}</span></li>)}</ul> : <p>No reviews recorded.</p>}</Card>
  </>} />;
}
