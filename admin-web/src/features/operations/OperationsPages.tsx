/* eslint-disable no-control-regex -- Reject control characters in user-supplied filters. */
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Link, useLocation, useParams, useSearchParams } from 'react-router';
import { AdminRequestError, type AdminRequest } from '../../api/client';
import { safeAdminReturnLocation, useSession } from '../../session/SessionProvider';
import { Button, Card, EmptyState, ErrorState, LoadingState, PageHeader, StatusBadge } from '../../ui';
import { isValidId, parseEmailPage, parseGatewayDetail, parseGatewayPage, parseGrantDetail, parseGrantPage, parseMemberDetail, parseMemberPage, parseSmsDetail, parseSmsPage, type EmailEvent, type GatewayDevice, type MemberReceipt, type Page, type ReceiverGrant, type SmsReceipt } from './contracts';
import { SmsActionPanel } from './SmsActionPanel';
import { EmailDispatchPanel } from './EmailDispatchPanel';
import { ReceiverGrantActionPanel } from './ReceiverGrantActionPanel';
import { ReceiverGrantCreatePanel } from './ReceiverGrantCreatePanel';
import { GatewayRevocationPanel } from './GatewayRevocationPanel';
import { GatewayActivationPanel } from './GatewayActivationPanel';
import { ReceiptReviewPanel } from '../receipt-review';
import './operations.css';

interface Actor { id: string; role: string; canonical: boolean; canExtract: boolean; canManageGateway: boolean; }
type ReadState<T> = { key: string; status: 'success'; value: T } | { key: string; status: 'error'; message: string };

/** Coalesce a single in-flight read across React's development effect replay. */
function useRead<T>(key: string, enabled: boolean, load: () => Promise<T>) {
  const [result, setResult] = useState<ReadState<T> | null>(null);
  const [attempt, setAttempt] = useState(0);
  const flight = useRef<{key: string; promise: Promise<T>} | null>(null);
  const attemptKey = `${key}:${attempt}`;
  useEffect(() => {
    if (!enabled) return;
    let current = flight.current;
    if (!current || current.key !== attemptKey) {
      current = {key: attemptKey, promise: load()};
      flight.current = current;
    }
    let active = true;
    const entry = current;
    entry.promise.then((value) => {
      if (active) setResult({key: attemptKey, status: 'success', value});
    }, (error: unknown) => {
      if (active) setResult({key: attemptKey, status: 'error', message: error instanceof AdminRequestError ? error.message : 'The workspace response could not be verified.'});
    }).finally(() => { if (flight.current === entry) flight.current = null; });
    return () => { active = false; };
  }, [attemptKey, enabled, load]);
  return {result: result?.key === attemptKey ? result : null, retry: () => setAttempt((value) => value + 1)};
}

function useActor() {
  const session = useSession();
  const user = session.user;
  const id = user?.id, role = user?.role, model = user?.financialModel;
  const canExtract = user?.role !== 'staff' && (user?.permissions.includes('sms.extract') ?? false);
  const canManageGateway = user?.role !== 'staff' && (user?.permissions.includes('gateway.manage') ?? false);
  const actor = useMemo<Actor | null>(() => id && role ? {
    id, role, canonical: model === 'canonical_evidence_ledger', canExtract, canManageGateway,
  } : null, [id, role, model, canExtract, canManageGateway]);
  return {session, actor};
}

function formatStatus(value: string) { return value.replace(/_/g, ' ').replace(/^./, (first) => first.toUpperCase()); }
function statusTone(value: string): 'success' | 'warning' | 'danger' | 'info' | 'neutral' {
  if (['active', 'reviewed', 'linked', 'delivered', 'accepted'].includes(value)) return 'success';
  if (['rejected', 'revoked', 'failed_no_send', 'parse_failed', 'suppressed'].includes(value)) return 'danger';
  if (['pending', 'needs_review', 'under_review', 'queued', 'uncertain', 'received', 'not_extracted'].includes(value)) return 'warning';
  return 'info';
}
function formatTime(value: string | number | null | undefined) {
  if (value === null || value === undefined) return 'Not recorded';
  const date = new Date(typeof value === 'number' ? value * 1000 : value);
  return Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat('en-GB', {timeZone: 'Africa/Kigali', dateStyle: 'medium', timeStyle: 'short'}).format(date) : 'Not recorded';
}
function formatMoney(value: number | null) { return value === null ? 'Not recorded' : `RWF ${new Intl.NumberFormat('en-RW', {maximumFractionDigits: 0}).format(value)}`; }
function query(offset: number, status: string, search = '', limit = 25) {
  const params = new URLSearchParams({limit: String(limit), offset: String(offset)});
  if (status) params.set('status', status);
  if (search) params.set('search', search);
  return params.toString();
}

interface Column<T> { label: string; render: (row: T) => ReactNode; }
interface RecordsFilter { key: string; label: string; allLabel: string; options: readonly {value: string; label: string}[] }
interface RecordsProps<T> {
  title: string; subtitle: string; permission: string; statuses?: readonly string[]; searchable?: boolean;
  filters?: readonly RecordsFilter[]; smsPagination?: boolean;
  rowKey: (row: T) => string; columns: Column<T>[];
  load: (request: AdminRequest, offset: number, status: string, search: string, actor: Actor, filters: Record<string, string>, limit: number) => Promise<Page<T>>;
  extra?: ReactNode | ((reload: () => void) => ReactNode);
}

function RecordsPage<T>({title, subtitle, permission, statuses = [], searchable = false, filters = [], smsPagination = false, rowKey, columns, load, extra}: RecordsProps<T>) {
  const {session, actor} = useActor();
  const [params, setParams] = useSearchParams();
  const limits = params.getAll('limit'), offsets = params.getAll('offset');
  const rawLimit = smsPagination && limits.length === 1 ? limits[0] : '25';
  const validLimit = !smsPagination || limits.length === 0 || limits.length === 1 && /^[1-9]\d{0,2}$/.test(rawLimit) && Number(rawLimit) <= 100;
  const limit = smsPagination && validLimit ? Number(rawLimit) : 25;
  const rawOffset = offsets.length === 1 ? offsets[0] : null;
  const rawPage = smsPagination && validLimit && params.getAll('page').length === 1 ? params.get('page') : null;
  const pageOffset = rawPage && /^[1-9]\d{0,9}$/.test(rawPage) && (Number(rawPage) - 1) * limit <= 2147483647 ? (Number(rawPage) - 1) * limit : 0;
  const offset = !validLimit || offsets.length > 1 ? 0 : rawOffset === null ? pageOffset : /^\d{1,10}$/.test(rawOffset) && Number(rawOffset) <= 2147483647 && Number(rawOffset) % limit === 0 ? Number(rawOffset) : 0;
  const candidateStatus = params.get('status') ?? '';
  const status = statuses.includes(candidateStatus) ? candidateStatus : '';
  const candidateSearch = params.get('search') ?? '';
  const search = searchable && candidateSearch.length <= 200 && !/[\x00-\x1f\x7f]/.test(candidateSearch) ? candidateSearch : '';
  const selectedFilters = Object.fromEntries(filters.map(filter => {
    const candidate = params.getAll(filter.key).length === 1 ? params.get(filter.key) ?? '' : '';
    return [filter.key, filter.options.some(option => option.value === candidate) ? candidate : ''];
  }));
  const filterKey = JSON.stringify(selectedFilters);
  const changeParams = (changes: Record<string, string | number>) => {
    const next = new URLSearchParams(params);
    if (smsPagination && Object.hasOwn(changes, 'offset')) next.delete('page');
    for (const [name, value] of Object.entries(changes)) {
      if (value === '' || value === 0) next.delete(name);
      else next.set(name, String(value));
    }
    setParams(next);
  };
  const canRead = !!actor && session.status === 'authenticated' && !!session.user?.permissions.includes(permission);
  const loadPage = useCallback(() => actor ? load(session.request, offset, status, search, actor, JSON.parse(filterKey) as Record<string, string>, limit) : Promise.reject(new Error('Account unavailable.')), [actor, filterKey, limit, load, offset, search, session.request, status]);
  const key = JSON.stringify([session.epoch, actor?.id ?? '', actor?.canonical ?? null, permission, offset, limit, status, search, filterKey]);
  const {result, retry} = useRead(key, canRead, loadPage);

  return <><PageHeader eyebrow="Collect Admin / Operations" title={title} subtitle={subtitle} />
    {canRead && (typeof extra === 'function' ? extra(retry) : extra)}
    {!canRead ? <ErrorState title="Access unavailable" message="Your current account cannot open these records." /> : <Card className="operations-records">
      <div className="operations-toolbar"><h2>{title}</h2>
        {searchable && <form className="operations-search" onSubmit={(event) => { event.preventDefault(); const value = new FormData(event.currentTarget).get('search'); if (typeof value === 'string' && !/[\x00-\x1f\x7f]/.test(value) && value.length <= 200) changeParams({offset: 0, search: value.trim()}); }}>
          <label className="admin-sr-only" htmlFor="operations-search">Search {title}</label><input key={search} id="operations-search" name="search" className="admin-input" type="search" maxLength={200} defaultValue={search} placeholder="Search records" /><Button type="submit" icon="search">Search</Button>
        </form>}
        {statuses.length > 0 && <label className="operations-filter"><span>Status</span><select className="admin-input" value={status} onChange={(event) => changeParams({offset: 0, status: event.target.value})}><option value="">All statuses</option>{statuses.map((value) => <option key={value} value={value}>{formatStatus(value)}</option>)}</select></label>}
        {filters.map(filter => <label className="operations-filter" key={filter.key}><span>{filter.label}</span><select className="admin-input" value={selectedFilters[filter.key]} onChange={(event) => changeParams({offset: 0, [filter.key]: event.target.value})}><option value="">{filter.allLabel}</option>{filter.options.map(option => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>)}
      </div>
      {!result ? <LoadingState label={`Loading ${title.toLowerCase()}`} /> : result.status === 'error' ? <ErrorState message={result.message} onRetry={retry} /> : result.value.rows.length === 0 ? <><EmptyState title="No records found" description="Change your filters or check again later." />{offset > 0 && <div className="operations-pagination"><Button onClick={() => changeParams({offset: Math.max(0, offset - result.value.limit)})}>Previous</Button></div>}</> : <>
        <div className="admin-table-wrap" tabIndex={0} role="region" aria-label={`${title} records`}><table className="admin-table"><thead><tr>{columns.map((column) => <th key={column.label} scope="col">{column.label}</th>)}</tr></thead><tbody>{result.value.rows.map((row) => <tr key={rowKey(row)}>{columns.map((column) => <td key={column.label}>{column.render(row)}</td>)}</tr>)}</tbody></table></div>
        <div className="operations-pagination"><span>Showing {offset + 1}–{offset + result.value.rows.length} of {result.value.total}</span><div><Button onClick={() => changeParams({offset: Math.max(0, offset - result.value.limit)})} disabled={offset === 0}>Previous</Button><Button onClick={() => changeParams({offset: offset + result.value.limit})} disabled={offset + result.value.rows.length >= result.value.total || offset + result.value.limit > 2147483647}>Next</Button></div></div>
      </>}
    </Card>}
  </>;
}

const smsStatuses = ['pending', 'parsed', 'parse_failed', 'needs_review', 'rejected', 'reviewed', 'received', 'under_review', 'linked'] as const;
const legacySmsStatuses = ['pending', 'parsed', 'parse_failed', 'needs_review', 'rejected', 'reviewed'] as const;
const gatewayStatuses = ['pending', 'active', 'revoked'] as const;
const grantStatuses = ['active', 'revoked'] as const;
const emailStatuses = ['queued', 'leased', 'send_started', 'accepted', 'delivered', 'failed_no_send', 'uncertain', 'suppressed'] as const;

const smsLoad: RecordsProps<SmsReceipt>['load'] = async (request, offset, status, search, actor, filters, limit) => {
  const params = new URLSearchParams(query(offset, status, search, limit));
  if (filters.source) params.set('source_kind', filters.source);
  if (filters.extraction) params.set('extraction_status', filters.extraction);
  if (filters.duplicates) params.set('duplicates', filters.duplicates);
  return parseSmsPage(await request(`sms/receipts?${params}`), offset, limit, status, {
    sourceKind: filters.source, extractionStatus: filters.extraction, duplicates: filters.duplicates, canonical: actor.canonical,
  });
};
const gatewayLoad: RecordsProps<GatewayDevice>['load'] = async (request, offset, status) => {
  const params = new URLSearchParams({limit: '25', offset: String(offset)}); if (status) params.set('state', status);
  return parseGatewayPage(await request(`gateway/devices?${params}`), offset, status);
};
const grantLoad: RecordsProps<ReceiverGrant>['load'] = async (request, offset, status) => parseGrantPage(await request(`gateway/receiver-grants?${query(offset, status)}`), offset, status);
const memberLoad: RecordsProps<MemberReceipt>['load'] = async (request, offset, status, _search, actor) => parseMemberPage(await request(`gateway/receipts?${query(offset, status)}`), offset, actor.canonical, status);
const emailLoad: RecordsProps<EmailEvent>['load'] = async (request, offset, status) => parseEmailPage(await request(`email/events?${query(offset, status)}`), offset, status);

function RecordLink({to, children, returnTo}: {to: string; children: ReactNode; returnTo?: string}) {
  const location = useLocation();
  const query = new URLSearchParams({returnTo: returnTo ?? location.pathname + location.search});
  return <Link className="operations-link" to={`${to}?${query}`}>{children}</Link>;
}

const smsColumns: Column<SmsReceipt>[] = [
  {label: 'Source', render: (row) => <RecordLink to={`/admin/sms-receipts/${row.source_kind}/${row.id}`}>{formatStatus(row.source_kind)} · {row.id.slice(0, 8)}</RecordLink>},
  {label: 'Received', render: (row) => formatTime(row.received_at)},
  {label: 'Payer', render: (row) => row.payer_name ?? row.display_name ?? 'Not recorded'},
  {label: 'Amount', render: (row) => formatMoney(row.amount_rwf)},
  {label: 'Extraction', render: (row) => <StatusBadge tone={row.source_kind === 'capture' ? 'info' : statusTone(row.extraction_status)}>{row.source_kind === 'capture' ? 'Source metadata' : formatStatus(row.extraction_status)}</StatusBadge>},
  {label: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{formatStatus(row.status)}</StatusBadge>},
];
const gatewayColumns: Column<GatewayDevice>[] = [
  {label: 'Device', render: (row) => <RecordLink to={`/admin/gateway/${row.id}`}>{row.label}</RecordLink>},
  {label: 'Status', render: (row) => <StatusBadge tone={statusTone(row.state)}>{formatStatus(row.state)}</StatusBadge>},
  {label: 'Last heartbeat', render: (row) => formatTime(row.last_heartbeat_at)},
  {label: 'Version', render: (row) => row.version},
];
const grantColumns: Column<ReceiverGrant>[] = [
  {label: 'Device', render: (row) => <RecordLink to={`/admin/gateway/receiver-grants/${row.id}`}>{row.device_label}</RecordLink>},
  {label: 'Payee', render: (row) => row.payee_label},
  {label: 'Collection number or code', render: (row) => row.payee_momo_number_or_code},
  {label: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{formatStatus(row.status)}</StatusBadge>},
  {label: 'Created', render: (row) => formatTime(row.created_at)},
];
const memberColumns: Column<MemberReceipt>[] = [
  {label: 'Receipt', render: (row) => <RecordLink to={`/admin/member-receipts/${row.id}`}>{row.id.slice(0, 8)}</RecordLink>},
  {label: 'Member', render: (row) => row.display_name ?? row.public_id ?? 'Not recorded'},
  {label: 'Received', render: (row) => formatTime(row.received_at)},
  {label: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{formatStatus(row.status)}</StatusBadge>},
];
const emailColumns: Column<EmailEvent>[] = [
  {label: 'Recipient', render: (row) => row.recipient_masked}, {label: 'Notification', render: (row) => formatStatus(row.notification_type)},
  {label: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{formatStatus(row.status)}</StatusBadge>},
  {label: 'Attempts', render: (row) => row.attempt_count}, {label: 'Created', render: (row) => formatTime(row.created_at)},
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
export function GatewayDevicesPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {user} = useSession();
  const canRecover = !!user && user.role !== 'staff' && user.financialModel === 'transaction_journals' && ['gateway.read', 'gateway.manage', 'overview.read'].every((permission) => user.permissions.includes(permission));
  return <RecordsPage title="Gateway devices" subtitle="Review enrolled devices and their reported status." permission="gateway.read" statuses={gatewayStatuses} rowKey={(row) => row.id} columns={gatewayColumns} load={gatewayLoad} extra={<p className="operations-note"><Link className="operations-link" to="/admin/gateway/receiver-grants">View receiver capture grants</Link>{allowRecovery && canRecover && <> · <Link className="operations-link" to="/admin/gateway/new">{allowActions ? 'Enroll device' : 'Check gateway enrollment request'}</Link></>}</p>} />;
}
export function ReceiverGrantsPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {epoch} = useSession();
  return <RecordsPage title="Receiver capture grants" subtitle="Review the link between a device and a payee." permission="gateway.read" statuses={grantStatuses} rowKey={(row) => row.id} columns={grantColumns} load={grantLoad} extra={(reload) => <><p className="operations-note">Capture does not grant sending, payment confirmation or financial authority.</p>{allowRecovery && <ReceiverGrantCreatePanel key={epoch} enabled={allowActions} onUpdated={reload} />}</>} />;
}
export function MemberReceiptsPage() {
  const {actor} = useActor();
  const statuses = actor?.canonical ? ['received', 'under_review', 'rejected', 'linked'] : ['needs_review', 'reviewed', 'rejected'];
  return <RecordsPage title="Member receipts" subtitle="Review recorded member receipt evidence." permission="payments.read" statuses={statuses} rowKey={(row) => row.id} columns={memberColumns} load={memberLoad} extra={<p className="operations-note">A receipt is evidence and does not by itself confirm provider settlement.</p>} />;
}
export function EmailEventsPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {epoch} = useSession();
  return <RecordsPage title="Email notifications" subtitle="Review recorded email delivery events." permission="email.read" statuses={emailStatuses} rowKey={(row) => row.id} columns={emailColumns} load={emailLoad} extra={(reload) => allowRecovery ? <EmailDispatchPanel key={epoch} enabled={allowActions} onUpdated={reload} /> : null} />;
}

interface DetailProps<T> {
  title: string; subtitle: string; permission: string; back: string; resourceKey: string; valid: boolean;
  load: (request: AdminRequest, actor: Actor, offset: number) => Promise<T>;
  render: (value: T, offset: number, setOffset: (offset: number) => void, reload: () => void, returnPath: string) => ReactNode;
  additionalReturns?: string[];
}

function DetailPage<T>({title, subtitle, permission, back, resourceKey, valid, load, render, additionalReturns = []}: DetailProps<T>) {
  const {session, actor} = useActor();
  const [params, setParams] = useSearchParams();
  const rawOffset = params.get('relatedOffset') ?? '0';
  const offset = /^\d{1,10}$/.test(rawOffset) && Number(rawOffset) <= 2147483647 && Number(rawOffset) % 25 === 0 ? Number(rawOffset) : 0;
  const setOffset = (value: number) => {const next = new URLSearchParams(params); if (value === 0) next.delete('relatedOffset'); else next.set('relatedOffset', String(value)); setParams(next);};
  const canRead = !!actor && session.status === 'authenticated' && !!session.user?.permissions.includes(permission);
  const loadDetail = useCallback(() => actor ? load(session.request, actor, offset) : Promise.reject(new Error('Account unavailable.')), [actor, load, offset, session.request]);
  const {result, retry} = useRead(`${session.epoch}:${actor?.id ?? ''}:${resourceKey}:${offset}`, canRead && valid, loadDetail);
  const candidate = safeAdminReturnLocation(params.get('returnTo'));
  const returnPath = candidate && [back, ...additionalReturns].includes(new URL(candidate, 'https://admin.invalid').pathname) ? candidate : back;
  return <><PageHeader eyebrow="Collect Admin / Operations" title={title} subtitle={subtitle} /><p><Link className="operations-link" to={returnPath}>← Back to records</Link></p>
    {!canRead ? <ErrorState title="Access unavailable" message="Your current account cannot open this record." /> : !valid ? <ErrorState title="Record unavailable" message="Select a valid record." /> : !result ? <LoadingState label="Loading record" /> : result.status === 'error' ? <ErrorState message={result.message} onRetry={retry} /> : render(result.value, offset, setOffset, retry, returnPath)}
  </>;
}

function Facts({items}: {items: [string, ReactNode][]}) {
  return <dl className="operations-facts">{items.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value ?? 'Not recorded'}</dd></div>)}</dl>;
}

function RelatedPagination<T>({page, offset, onChange}: {page: Page<T>; offset: number; onChange: (offset: number) => void}) {
  if (page.total === 0) return <p>No related records.</p>;
  if (page.rows.length === 0) return <div className="operations-pagination"><span>No records on this page.</span><Button onClick={() => onChange(Math.max(0, offset - page.limit))} disabled={offset === 0}>Previous</Button></div>;
  return <div className="operations-pagination"><span>Showing {offset + 1}–{offset + page.rows.length} of {page.total}</span><div><Button onClick={() => onChange(Math.max(0, offset - page.limit))} disabled={offset === 0}>Previous</Button><Button onClick={() => onChange(offset + page.limit)} disabled={offset + page.rows.length >= page.total}>Next</Button></div></div>;
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
      ['Payer number', value.resource.payer_phone ?? value.resource.payer_masked_phone], ['Amount', formatMoney(value.resource.amount_rwf)],
      ['Network', value.resource.network ? formatStatus(value.resource.network) : null], ['Reference', value.resource.momo_transaction_reference],
      ['Extraction', formatStatus(value.resource.extraction_status)], ['Source SHA-256', value.resource.source_sha256],
    ]} /></Card>
    <Card className="operations-detail"><h2>Related references</h2>{value.duplicates.rows.length > 0 && <ul className="operations-related">{value.duplicates.rows.map((row) => <li key={`${row.source_kind}/${row.id}`}><RecordLink to={`/admin/sms-receipts/${row.source_kind}/${row.id}`} returnTo={returnPath}>{formatStatus(row.source_kind)} · {row.id}</RecordLink><span>{formatStatus(row.status)}</span></li>)}</ul>}<RelatedPagination page={value.duplicates} offset={offset} onChange={setOffset} /></Card>
    {allowRecovery && <SmsActionPanel key={`${epoch}:${kind}:${id}`} source={value.resource} enabled={allowActions} extractionAvailable={value.canExtract} onUpdated={reload} />}
  </>} />;
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
    {allowRecovery && <><GatewayActivationPanel key={`${epoch}:${id}:activate`} device={value.resource} canManage={value.canManage} enabled={allowActions} onUpdated={reload} />
    <GatewayRevocationPanel key={`${epoch}:${id}:revoke`} device={value.resource} canManage={value.canManage} enabled={allowActions} onUpdated={reload} /></>}
    <Card className="operations-detail"><h2>Enrollment response</h2><p>This public response identifies the enrolled installation.</p><pre className="operations-source-content">{JSON.stringify(value.enrollment, null, 2)}</pre></Card>
    <Card className="operations-detail"><h2>Device observations</h2>{value.heartbeats.length ? <div className="admin-table-wrap" tabIndex={0} role="region" aria-label="Device observations"><table className="admin-table"><thead><tr><th scope="col">Reported</th><th scope="col">Network</th><th scope="col">Telephony</th><th scope="col">SMS permission</th><th scope="col">Local pause</th></tr></thead><tbody>{value.heartbeats.map((row) => <tr key={row.observation_id}><td>{formatTime(row.reported_at)}</td><td>{formatStatus(row.network)}</td><td>{formatStatus(row.telephony)}</td><td>{row.sms_permission ? 'Granted' : 'Not granted'}</td><td>{row.local_pause ? 'Paused' : 'Not paused'}</td></tr>)}</tbody></table></div> : <p>No observations recorded.</p>}{value.truncated && <p>Additional observations are not shown.</p>}</Card>
  </>} />;
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

export function MemberReceiptDetailPage({allowActions = false, allowRecovery = true}: {allowActions?: boolean; allowRecovery?: boolean}) {
  const {id = ''} = useParams();
  const {epoch} = useSession();
  const load = useCallback(async (request: AdminRequest, actor: Actor) => parseMemberDetail(await request(`gateway/receipts/${id}`), id, actor.id, actor.role === 'staff', actor.canonical), [id]);
  return <DetailPage title="Member receipt" subtitle="Review the recorded receipt and its review history." permission="payments.read" back="/admin/member-receipts" resourceKey={id} valid={isValidId(id)} load={load} render={(value, ...detail) => <>
    <p className="operations-note">A receipt is evidence and does not by itself confirm provider settlement.</p>
    <Card className="operations-detail"><h2>Receipt details</h2><Facts items={[
      ['Receipt ID', value.resource.id], ['Member', value.resource.display_name ?? value.resource.public_id],
      ['Status', formatStatus(value.resource.status)], ['Received', formatTime(value.resource.received_at)],
      ['Created', formatTime(value.resource.created_at)], ['Version', value.resource.version], ['Evidence SHA-256', value.resource.body_sha256],
    ]} /></Card>
    {allowRecovery && <ReceiptReviewPanel key={`${epoch}:${id}`} receipt={value.resource} canManage={value.canManage} enabled={allowActions} allowAttachment={false} onUpdated={detail[2]} />}
    <Card className="operations-detail"><h2>Review history</h2>{value.reviews.length ? <ul className="operations-related">{value.reviews.map((row) => <li key={row.id}><span>{formatStatus(row.outcome)} · {row.reason}</span><span>{formatTime(row.reviewed_at)}</span></li>)}</ul> : <p>No reviews recorded.</p>}</Card>
  </>} />;
}
