import { useCallback } from 'react';
import { useParams } from 'react-router';
import type { AdminRequest } from '../../api/client';
import { useSession } from '../../session/SessionProvider';
import { Card, StatusBadge } from '../../ui';
import { isValidId, parseSmsDetail, parseSmsPage, type SmsReceipt } from './contracts';
import { DetailPage, Facts, RecordLink, RecordsPage, RelatedPagination, formatStatus, formatTime, query, statusTone, useActor, type Actor, type Column, type RecordsFilter, type RecordsProps } from './OperationsRecords';
import { SmsActionPanel } from './SmsActionPanel';

const smsStatuses = ['pending', 'parsed', 'parse_failed', 'needs_review', 'rejected', 'reviewed', 'received', 'under_review', 'linked'] as const;
const legacySmsStatuses = ['pending', 'parsed', 'parse_failed', 'needs_review', 'rejected', 'reviewed'] as const;

const smsLoad: RecordsProps<SmsReceipt>['load'] = async (request, offset, status, search, actor, filters, limit) => {
  const params = new URLSearchParams(query(offset, status, search, limit));
  if (filters.source) params.set('source_kind', filters.source);
  if (filters.extraction) params.set('extraction_status', filters.extraction);
  if (filters.duplicates) params.set('duplicates', filters.duplicates);
  return parseSmsPage(await request(`sms/receipts?${params}`), offset, limit, status, {
    sourceKind: filters.source, extractionStatus: filters.extraction, duplicates: filters.duplicates, canonical: actor.canonical,
  });
};

function formatMoney(value: number | null) { return value === null ? 'Not recorded' : `RWF ${new Intl.NumberFormat('en-RW', {maximumFractionDigits: 0}).format(value)}`; }

function maskedReceiptContact(row: SmsReceipt): string | null {
  return row.payer_masked_phone ?? (row.payer_last3 ? '•••• ' + row.payer_last3 : null);
}

const smsColumns: Column<SmsReceipt>[] = [
  {label: 'Source', render: (row) => <RecordLink to={`/admin/sms-receipts/${row.source_kind}/${row.id}`}>{formatStatus(row.source_kind)} · {row.id.slice(0, 8)}</RecordLink>},
  {label: 'Received', render: (row) => formatTime(row.received_at)},
  {label: 'Payer', render: (row) => row.payer_name ?? row.display_name ?? 'Not recorded'},
  {label: 'Masked contact', render: (row) => maskedReceiptContact(row) ?? 'Not recorded'},
  {label: 'Amount', render: (row) => formatMoney(row.amount_rwf)},
  {label: 'Extraction', render: (row) => <StatusBadge tone={row.source_kind === 'capture' ? 'info' : statusTone(row.extraction_status)}>{row.source_kind === 'capture' ? 'Source metadata' : formatStatus(row.extraction_status)}</StatusBadge>},
  {label: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{formatStatus(row.status)}</StatusBadge>},
  {label: 'Conflicts', render: (row) => row.conflicting_reference_count},
];

export function SmsReceiptsPage() {
  const {actor} = useActor();
  const filters: RecordsFilter[] = [
    {key: 'source', label: 'Source', allLabel: 'All sources', options: [
      {value: 'member', label: 'Member'}, {value: 'receiver', label: 'Receiver'}, ...(actor?.canonical ? [{value: 'capture', label: 'Capture'}] : []),
    ]},
    {key: 'extraction', label: 'Extraction', allLabel: 'All extraction states', options: [
      {value: 'not_extracted', label: 'Not extracted'}, {value: 'parsed', label: 'Parsed'}, {value: 'needs_review', label: 'Needs review'},
    ]},
    {key: 'duplicates', label: 'Duplicate references', allLabel: 'Any references', options: [
      {value: 'all', label: 'Any duplicates'}, {value: 'conflicting', label: 'Conflicting duplicates'},
    ]},
  ];
  return <RecordsPage title="SMS receipts" subtitle="Review source evidence and extracted facts." permission="sms.read" statuses={actor?.canonical ? smsStatuses : legacySmsStatuses} searchable filters={filters} smsPagination rowKey={(row) => `${row.source_kind}/${row.id}`} columns={smsColumns} load={smsLoad} extra={<p className="operations-note">Recorded SMS evidence does not establish provider confirmation or settlement.</p>} />;
}

export function SmsReceiptDetailPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {id = '', kind = ''} = useParams();
  const {epoch} = useSession();
  const valid = isValidId(id) && ['member', 'receiver', 'capture'].includes(kind);
  const load = useCallback(async (request: AdminRequest, actor: Actor, offset: number) => parseSmsDetail(await request(`sms/receipts/${kind}/${id}?limit=25&offset=${offset}`), kind, id, actor.id, actor.canExtract, offset), [id, kind]);
  return <DetailPage title="SMS receipt" subtitle="Review recorded source evidence and extracted facts." permission="sms.read" back="/admin/sms-receipts" additionalReturns={['/admin/momo-receipts']} resourceKey={`${kind}/${id}`} valid={valid} load={load} render={(value, offset, setOffset, reload, returnPath) => <>
    <p className="operations-note">The source is evidence only; provider confirmation and settlement are not asserted.</p>
    <Card className="operations-detail"><h2>Receipt details</h2><Facts items={[
      ['Source', formatStatus(value.resource.source_kind)], ['Receipt ID', value.resource.id], ['Status', formatStatus(value.resource.status)],
      ['Received', formatTime(value.resource.received_at)], ['Payer name', value.resource.payer_name ?? value.resource.display_name],
      ['Masked contact', maskedReceiptContact(value.resource)], ['Amount', formatMoney(value.resource.amount_rwf)],
      ['Network', value.resource.network ? formatStatus(value.resource.network) : null], ['Reference', value.resource.momo_transaction_reference],
      ['Evidence', formatStatus(value.resource.evidence_level)], ['Extraction', formatStatus(value.resource.extraction_status)],
      ['Conflicting references', value.resource.conflicting_reference_count],
    ]} />
      <details className="operations-receipt-provenance">
        <summary>Technical provenance</summary>
        <Facts items={[
          ['Source SHA-256', value.resource.source_sha256],
          ['Extraction time', formatTime(value.resource.parsed_at)],
          ['Parser', value.resource.parser_version],
        ]} />
      </details>
    </Card>
    <Card className="operations-detail"><h2>Related references</h2>{value.duplicates.rows.length > 0 && <ul className="operations-related">{value.duplicates.rows.map((row) => <li key={`${row.source_kind}/${row.id}`}><RecordLink to={`/admin/sms-receipts/${row.source_kind}/${row.id}`} returnTo={returnPath}>{formatStatus(row.source_kind)} · {row.id}</RecordLink><span>{formatStatus(row.status)}</span></li>)}</ul>}<RelatedPagination page={value.duplicates} offset={offset} onChange={setOffset} /></Card>
    {allowRecovery && <SmsActionPanel key={`${epoch}:${kind}:${id}`} source={value.resource} enabled={allowActions} extractionAvailable={value.canExtract} onUpdated={reload} />}
  </>} />;
}
