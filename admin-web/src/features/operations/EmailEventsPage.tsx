import { useSession } from '../../session/SessionProvider';
import { StatusBadge } from '../../ui';
import { parseEmailPage, type EmailEvent } from './contracts';
import { EmailDispatchPanel } from './EmailDispatchPanel';
import { RecordsPage, formatStatus, formatTime, query, statusTone, type Column, type RecordsProps } from './OperationsRecords';

const emailStatuses = ['queued', 'leased', 'send_started', 'accepted', 'delivered', 'failed_no_send', 'uncertain', 'suppressed'] as const;

const emailLoad: RecordsProps<EmailEvent>['load'] = async (request, offset, status) => parseEmailPage(await request(`email/events?${query(offset, status)}`), offset, status);

const emailColumns: Column<EmailEvent>[] = [
  {label: 'Recipient', render: (row) => row.recipient_masked}, {label: 'Notification', render: (row) => formatStatus(row.notification_type)},
  {label: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{formatStatus(row.status)}</StatusBadge>},
  {label: 'Attempts', render: (row) => row.attempt_count}, {label: 'Created', render: (row) => formatTime(row.created_at)},
];

export function EmailEventsPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {epoch} = useSession();
  return <RecordsPage title="Email notifications" subtitle="Review recorded email delivery events." permission="email.read" statuses={emailStatuses} rowKey={(row) => row.id} columns={emailColumns} load={emailLoad} extra={(reload) => allowRecovery ? <EmailDispatchPanel key={epoch} enabled={allowActions} onUpdated={reload} /> : null} />;
}
