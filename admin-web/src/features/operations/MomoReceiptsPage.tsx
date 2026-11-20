/* eslint-disable no-control-regex -- Reject control characters in operator search input. */
import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react';
import { Link } from 'react-router';
import { AdminRequestError } from '../../api/client';
import { useSession } from '../../session/SessionProvider';
import { Button, Card, Dialog, EmptyState, ErrorState, LoadingState, PageHeader, StatusBadge } from '../../ui';
import { isValidId, parseSmsPage, type Page, type SmsReceipt } from './contracts';
import { momoStatuses, parseMomoDetail, parseMomoMemberChecks, parseMomoPage, parseMomoSources, sourceStatuses, type MomoDetail, type MomoFilters, type MomoMemberCheck, type MomoPage, type MomoSourceJob, type MomoStatus, type SourceStatus } from './momoContracts';
import { MomoAssignmentPanel } from './MomoAssignmentPanel';
import { MomoConflictReviewPanel } from './MomoConflictReviewPanel';
import { MomoSourceRevealPanel } from './MomoSourceRevealPanel';
import { MomoSourceActionsPanel, MomoSourceRecoveryPanel } from './MomoSourceActionsPanel';
import type { MomoExtraction } from './momoSourceActions';
import './operations.css';

type Result<T> = {key: string; value: T} | {key: string; error: string};
/** Ignore prior-authority responses and coalesce StrictMode's effect replay. */
function useRecords<T>(key: string, enabled: boolean, load: () => Promise<T>, interval = false) {
  const [state, setState] = useState<Result<T> | null>(null);
  const [refresh, setRefresh] = useState(0);
  const pending = useRef<{key: string; promise: Promise<T>} | null>(null);
  const requestKey = `${key}:${refresh}`;
  useEffect(() => {
    if (!enabled) return;
    let item = pending.current;
    if (!item || item.key !== requestKey) {item = {key: requestKey, promise: load()}; pending.current = item;}
    const current = item;
    let active = true;
    current.promise.then((value) => {if (active) setState({key: requestKey, value});}, (error: unknown) => {
      if (active) setState({key: requestKey, error: error instanceof AdminRequestError ? error.message : 'The MoMo records could not be verified.'});
    }).finally(() => {if (pending.current === current) pending.current = null;});
    return () => {active = false;};
  }, [enabled, load, requestKey]);
  useEffect(() => {
    if (!enabled || !interval) return;
    const timer = window.setInterval(() => {if (document.visibilityState === 'visible') setRefresh((value) => value + 1);}, 15000);
    return () => window.clearInterval(timer);
  }, [enabled, interval]);
  return {result: enabled && state?.key === requestKey ? state : null, retry: () => setRefresh((value) => value + 1)};
}
const label = (value: string) => value.replace(/_/g, ' ').replace(/^./, (value) => value.toUpperCase());
const time = (value: string | number | null) => {
  if (value === null) return 'Not recorded';
  const date = new Date(typeof value === 'number' ? value * 1000 : value);
  return Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat('en-GB', {timeZone: 'Africa/Kigali', dateStyle: 'medium', timeStyle: 'short'}).format(date) : 'Not recorded';
};
const money = (value: number) => `RWF ${new Intl.NumberFormat('en-RW', {maximumFractionDigits: 0}).format(value)}`;
function Pager<T>({page, change}: {page: Page<T>; change: (offset: number) => void}) {
  return <div className="operations-pagination"><span>{page.rows.length ? `Showing ${page.offset + 1}–${page.offset + page.rows.length} of ${page.total}` : `No records on this page · ${page.total} total`}</span><div><Button onClick={() => change(Math.max(0, page.offset - page.limit))} disabled={page.offset === 0}>Previous</Button><Button onClick={() => change(page.offset + page.limit)} disabled={page.offset + page.rows.length >= page.total}>Next</Button></div></div>;
}
function Table({name, headings, children}: {name: string; headings: string[]; children: ReactNode}) {
  return <div className="admin-table-wrap" role="region" aria-label={name} tabIndex={0}><table className="admin-table"><thead><tr>{headings.map((heading) => <th scope="col" key={heading}>{heading}</th>)}</tr></thead><tbody>{children}</tbody></table></div>;
}
function ResultView<T>({result, retry, empty, children}: {result: Result<T> | null; retry: () => void; empty: (value: T) => boolean; children: (value: T) => ReactNode}) {
  if (!result) return <LoadingState label="Loading records" />;
  if ('error' in result) return <ErrorState message={result.error} onRetry={retry} />;
  if (empty(result.value)) return <EmptyState title="No matching records" description="Change your filters or check again later." />;
  return children(result.value);
}
function Incoming() {
  const session = useSession(), request = session.request, [input, setInput] = useState(''), [search, setSearch] = useState(''), [offset, setOffset] = useState(0);
  const load = useCallback(async () => {
    const query = new URLSearchParams({source_kind: 'capture', limit: '25', offset: String(offset)});
    if (search) query.set('search', search);
    const page = parseSmsPage(await request(`sms/receipts?${query}`), offset);
    if (page.rows.some((row) => row.source_kind !== 'capture')) throw new Error('Source mismatch.');
    return page;
  }, [offset, search, request]);
  const {result, retry} = useRecords(`${session.epoch}:capture:${search}:${offset}`, session.status === 'authenticated' && !!session.user?.permissions.includes('sms.read'), load, true);
  const submit = (event: FormEvent) => {event.preventDefault(); if (input.length <= 200 && !/[\x00-\x1f\x7f]/.test(input)) {setSearch(input.trim()); setOffset(0);}};
  return <Card className="operations-records"><div className="operations-toolbar"><h2>Incoming SMS</h2><form className="operations-search" onSubmit={submit}><label className="admin-sr-only" htmlFor="momo-sms-search">Search incoming SMS</label><input id="momo-sms-search" className="admin-input" value={input} maxLength={200} onChange={(event) => setInput(event.target.value)} placeholder="User name, member ID or receipt ID" /><Button type="submit">Search</Button></form><Button onClick={retry}>Refresh</Button></div>
    <p className="operations-note">Updates automatically while this page is visible. An upload does not confirm payment or settlement.</p>
    <ResultView result={result} retry={retry} empty={(page: Page<SmsReceipt>) => page.rows.length === 0 && page.offset === 0}>{(page) => <>{page.rows.length > 0 && <Table name="Incoming mobile-money SMS" headings={['App user', 'Member ID', 'SMS time · Kigali', 'Uploaded · Kigali', 'Status']}>
      {page.rows.map((row) => <tr key={row.id}><td><Link className="operations-link" to={`/admin/sms-receipts/capture/${row.id}?returnTo=%2Fadmin%2Fmomo-receipts`}>{row.display_name ?? 'App user'}</Link></td><td>{row.public_id ?? 'Not recorded'}</td><td>{time(row.received_at)}</td><td>{time(row.created_at)}</td><td><StatusBadge>{label(row.status)}</StatusBadge></td></tr>)}</Table>}<Pager page={page} change={setOffset} /></>}</ResultView>
  </Card>;
}
const initialFilters: MomoFilters = {search: '', status: '', account: '', group: '', from: '', to: ''};
function kigaliDate(value: string, end: boolean): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const date = new Date(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) return null;
  return new Date(date.getTime() - 7200000 + (end ? 86399999 : 0)).toISOString();
}
function Transactions({allowActions, allowRecovery}: {allowActions: boolean; allowRecovery: boolean}) {
  const session = useSession(), request = session.request, permissions = session.user?.permissions ?? [];
  const [search, setSearch] = useState(''), [status, setStatus] = useState<MomoStatus>(''), [account, setAccount] = useState(''), [group, setGroup] = useState(''), [from, setFrom] = useState(''), [to, setTo] = useState('');
  const [filters, setFilters] = useState(initialFilters), [offset, setOffset] = useState(0), [filterError, setFilterError] = useState('');
  const [selected, setSelected] = useState<{id: string; epoch: number} | null>(null);
  const [checking, setChecking] = useState(false);
  const canCheck = ['payments.read', 'users.read', 'collections.read'].every((permission) => permissions.includes(permission));
  const load = useCallback(async () => {
    const query = new URLSearchParams({limit: '25', offset: String(offset), search: filters.search, status: filters.status});
    if (filters.account) query.set('receiving_account_id', filters.account); if (filters.group) query.set('group_id', filters.group);
    if (filters.from) query.set('from', filters.from); if (filters.to) query.set('to', filters.to);
    return parseMomoPage(await request(`momo/transactions?${query}`), offset, filters);
  }, [filters, offset, request]);
  const {result, retry} = useRecords(`${session.epoch}:transactions:${JSON.stringify(filters)}:${offset}`, session.status === 'authenticated' && permissions.includes('payments.read'), load);
  const apply = (event: FormEvent) => {
    event.preventDefault();
    const start = from ? kigaliDate(from, false) : '', end = to ? kigaliDate(to, true) : '';
    if (search.length > 200 || /[\x00-\x1f\x7f]/.test(search) || account && !isValidId(account) || group && !isValidId(group) || start === null || end === null || start && end && start > end) {setFilterError('Check the search, account, group and date values.'); return;}
    setFilterError(''); setOffset(0); setFilters({search: search.trim(), status, account: permissions.includes('receivers.read') ? account : '', group: permissions.includes('collections.read') ? group : '', from: start, to: end});
  };
  return <><Card className="operations-records"><form className="operations-toolbar" onSubmit={apply}><h2>Transactions</h2>
    <label className="operations-filter">Search MoMo TX ID or payer<input className="admin-input" value={search} onChange={(event) => setSearch(event.target.value)} maxLength={200} /></label>
    <label className="operations-filter">Payment status<select className="admin-input" value={status} onChange={(event) => setStatus(event.target.value as MomoStatus)}><option value="">All statuses</option>{momoStatuses.map((value) => <option key={value} value={value}>{label(value)}</option>)}</select></label>
    {permissions.includes('receivers.read') && <label className="operations-filter">Receiving account ID<input className="admin-input" value={account} onChange={(event) => setAccount(event.target.value)} /></label>}
    {permissions.includes('collections.read') && <label className="operations-filter">Group ID<input className="admin-input" value={group} onChange={(event) => setGroup(event.target.value)} /></label>}
    <label className="operations-filter">From · Kigali<input type="date" className="admin-input" value={from} onChange={(event) => setFrom(event.target.value)} /></label><label className="operations-filter">To · Kigali<input type="date" className="admin-input" value={to} onChange={(event) => setTo(event.target.value)} /></label>
    <Button type="submit">Apply filters</Button><Button onClick={retry}>Refresh</Button>{canCheck && <Button onClick={() => setChecking(true)}>Member checks</Button>}</form>{filterError && <p role="alert" className="operations-note">{filterError}</p>}
    <ResultView result={result} retry={retry} empty={() => false}>{(page: MomoPage) => <><p className="operations-note">Received {money(page.totals.received_minor)} · Credited {money(page.totals.credited_minor)} · Unallocated {money(page.totals.unallocated_minor)}<br />Provider transaction date · As of {time(page.asOf)} Kigali. Provider confirmation and settlement are not asserted.</p>
      {page.rows.length === 0 ? <EmptyState title="No matching validated payments" /> : <Table name="MoMo transactions" headings={['Transaction time · Kigali', 'Amount', 'Payer', 'MoMo TX ID', 'Beneficiary', 'Group', 'Status', 'Review issue']}>
      {page.rows.map((row) => <tr key={row.id}><td>{row.transaction_at ? time(row.transaction_at) : `Received ${time(row.created_at)}`}</td><td>{money(row.amount_minor)}</td><td>{row.payer_name ?? 'Unknown payer'}{row.payer_last3 ? ` · …${row.payer_last3}` : ''}</td><td><button type="button" className="operations-link" onClick={() => setSelected({id: row.id, epoch: session.epoch})}>{row.provider_transaction_id}</button></td><td>{row.member_name ?? 'Unassigned'}</td><td>{row.group_name ?? 'Unassigned'}</td><td><StatusBadge>{label(row.status)}</StatusBadge></td><td>{row.has_conflict ? 'Needs review' : '—'}</td></tr>)}</Table>}<Pager page={page} change={setOffset} /></>}</ResultView>
  </Card>{filters.status === 'needs_attention' && permissions.includes('sms.read') && <Sources allowActions={allowActions} allowRecovery={allowRecovery} />}
  {selected?.epoch === session.epoch && <TransactionDetail id={selected.id} allowActions={allowActions} allowRecovery={allowRecovery} onClose={() => setSelected(null)} />}
  {checking && canCheck && <MemberChecks onClose={() => setChecking(false)} onSearch={(value) => {setChecking(false); setSearch(value); setStatus(''); setOffset(0); setFilters((previous) => ({...previous, search: value, status: ''}));}} />}</>;
}
function Sources({allowActions, allowRecovery}: {allowActions: boolean; allowRecovery: boolean}) {
  const session = useSession(), request = session.request, [status, setStatus] = useState<SourceStatus>('needs_review'), [offset, setOffset] = useState(0);
  const [selected, setSelected] = useState<{source: MomoSourceJob; epoch: number} | null>(null);
  const load = useCallback(async () => parseMomoSources(await request(`momo/sources?${new URLSearchParams({status, limit: '25', offset: String(offset)})}`), offset, status), [request, offset, status]);
  const {result, retry} = useRecords(`${session.epoch}:momo-sources:${status}:${offset}`, session.status === 'authenticated' && !!session.user?.permissions.includes('sms.read'), load);
  return <Card className="operations-detail"><h2>Source messages needing attention</h2><p>Unresolved source messages are not validated payments. This view uses separate source filters and excludes transaction totals.</p><label className="operations-filter">Source state<select className="admin-input" value={status} onChange={(event) => {setStatus(event.target.value as SourceStatus); setOffset(0);}}>{sourceStatuses.map((value) => <option key={value} value={value}>{label(value)}</option>)}</select></label>
    <ResultView result={result} retry={retry} empty={(page: Page<MomoSourceJob>) => page.rows.length === 0 && page.offset === 0}>{(page) => <>{page.rows.length > 0 && <Table name="MoMo source messages" headings={['SMS reference', 'State', 'Received · Kigali', 'Processing issue', 'Receiving account', 'Binding']}>
      {page.rows.map((row) => <tr key={row.raw_sms_id}><td><button type="button" className="operations-link" onClick={() => setSelected({source: row, epoch: session.epoch})}>{row.raw_sms_id}</button></td><td>{label(row.state)}</td><td>{time(row.received_at)}</td><td>{row.last_error ?? label(row.state)}</td><td>{row.receiving_account_id ?? 'Unassigned'}</td><td>{row.binding_id ?? 'Unassigned'}</td></tr>)}</Table>}<Pager page={page} change={setOffset} /></>}</ResultView>
  {allowRecovery && <MomoSourceRecoveryPanel enabled={allowActions} onUpdated={retry} />}
  {selected?.epoch === session.epoch && <MomoSourceDialog source={selected.source} allowActions={allowActions} allowRecovery={allowRecovery} onClose={() => setSelected(null)} onUpdated={() => {setSelected(null); retry();}} />}</Card>;
}
function MomoSourceDialog({source, allowActions, allowRecovery, onClose, onUpdated}: {source: MomoSourceJob; allowActions: boolean; allowRecovery: boolean; onClose: () => void; onUpdated: () => void}) {
  const [candidate, setCandidate] = useState<MomoExtraction | null>(null);
  return <Dialog open title="Source message" onClose={onClose} footer={<Button onClick={onClose}>Close</Button>}><p>A source message is evidence and does not by itself credit a contribution.</p><dl className="operations-facts">{[
    ['SMS reference', source.raw_sms_id], ['State', label(source.state)], ['Received · Kigali', time(source.received_at)], ['Processing issue', source.last_error ?? label(source.state)], ['Receiving account', source.receiving_account_id ?? 'Unassigned'], ['Binding', source.binding_id ?? 'Unassigned'], ['Body SHA-256', source.body_sha256 ?? 'Not recorded'],
  ].map(([name, value]) => <div key={name}><dt>{name}</dt><dd>{value}</dd></div>)}</dl>{allowRecovery && <><MomoSourceRevealPanel source={source} enabled={allowActions} onCandidate={setCandidate} /><MomoSourceActionsPanel source={source} candidate={candidate} enabled={allowActions} onUpdated={onUpdated} /></>}</Dialog>;
}
function MemberChecks({onClose, onSearch}: {onClose: () => void; onSearch: (reference: string) => void}) {
  const session = useSession(), request = session.request, [offset, setOffset] = useState(0);
  const permitted = session.status === 'authenticated' && ['payments.read', 'users.read', 'collections.read'].every((permission) => session.user?.permissions.includes(permission));
  const load = useCallback(async () => parseMomoMemberChecks(await request(`momo/transactions/payment-checks?limit=25&offset=${offset}`), offset), [offset, request]);
  const {result, retry} = useRecords(`${session.epoch}:member-checks:${offset}`, permitted, load);
  return <Dialog open title="Member payment checks" onClose={onClose} footer={<><Button onClick={retry}>Refresh</Button><Button onClick={onClose}>Close</Button></>}>
    <p>Member-supplied requests. References and notes are unverified; they do not establish a received payment or credit.</p>
    <ResultView result={result} retry={retry} empty={(page: Page<MomoMemberCheck>) => page.rows.length === 0 && page.offset === 0}>{(page) => <>{page.rows.length > 0 && <Table name="Member payment checks" headings={['Member', 'Member ID', 'Group', 'Expected amount', 'Requested · Kigali', 'Status', 'Unverified reference', 'Member note', 'Request ID', 'Search']}>
      {page.rows.map((row) => <tr key={row.id}><td>{row.member_name}</td><td>{row.member_public_id}</td><td>{row.group_name}</td><td>{money(row.expected_amount_minor)}</td><td>{time(row.requested_at)}</td><td>Request received</td><td>{row.provider_reference ?? 'Not recorded'}</td><td>{row.evidence_note ?? 'Not recorded'}</td><td>{row.id}</td><td><Button disabled={!row.provider_reference?.trim() || /[\x00-\x1f\x7f]/.test(row.provider_reference)} onClick={() => row.provider_reference && onSearch(row.provider_reference.trim())}>Search reference</Button></td></tr>)}</Table>}<Pager page={page} change={setOffset} /></>}</ResultView>
  </Dialog>;
}
function TransactionDetail({id, allowActions, allowRecovery, onClose}: {id: string; allowActions: boolean; allowRecovery: boolean; onClose: () => void}) {
  const session = useSession(), request = session.request;
  const load = useCallback(async () => parseMomoDetail(await request(`momo/transactions/${id}`), id), [id, request]);
  const {result, retry} = useRecords(`${session.epoch}:momo-detail:${id}`, session.status === 'authenticated' && !!session.user?.permissions.includes('payments.read') && isValidId(id), load);
  return <Dialog open title="Payment details" onClose={onClose} footer={<Button onClick={onClose}>Close</Button>}><ResultView result={result} retry={retry} empty={() => false}>{(detail: MomoDetail) => <><dl className="operations-facts">{[
    ['Amount', money(detail.transaction.amount_minor)], ['Status', label(detail.transaction.status)], ['MoMo TX ID', detail.transaction.provider_transaction_id], ['Receiving account', detail.transaction.recipient_name], ['MoMo code', detail.transaction.public_code], ['Payer', detail.transaction.payer_name ?? 'Unknown payer'], ['Payer last 3', detail.transaction.payer_last3 ?? 'Not recorded'], ['Beneficiary', detail.transaction.member_name ?? 'Unassigned'], ['Group', detail.transaction.group_name ?? 'Unassigned'], ['Transaction time · Kigali', detail.transaction.transaction_at ? time(detail.transaction.transaction_at) : `Received ${time(detail.transaction.created_at)}`],
  ].map(([name, value]) => <div key={name}><dt>{name}</dt><dd>{value}</dd></div>)}</dl>
  {detail.transaction.has_conflict === 1 && <p role="status">Conflicting payment evidence requires review. The recorded financial status is preserved.</p>}
  {detail.transaction.payment_id && session.user?.permissions.includes('reconciliations.read') && <p><Link className="operations-link" to={`/admin/reconciliations/${detail.transaction.payment_id}`}>Open financial review</Link></p>}
  {allowRecovery && <><MomoAssignmentPanel key={`${session.epoch}:${id}`} detail={detail} enabled={allowActions} onUpdated={retry} />
  <MomoConflictReviewPanel key={`${session.epoch}:${id}:conflict`} detail={detail} enabled={allowActions} onUpdated={retry} /></>}
  <h3>Source and processing history</h3><p>Parsing does not confirm provider API settlement.</p>{detail.sources.length ? <Table name="Payment source and processing history" headings={['Source reference', 'Relationship', 'Outcome', 'Parser', 'Recorded · Kigali']}>{detail.sources.map((source, index) => <tr key={`${source.raw_sms_id}:${index}`}><td>{source.raw_sms_id}</td><td>{label(source.relation)}</td><td>{label(source.outcome)}</td><td>{source.parser_version}</td><td>{time(source.created_at)}</td></tr>)}</Table> : <p>No source history recorded.</p>}</>}</ResultView></Dialog>;
}
export function MomoReceiptsPage({allowActions = false, allowRecovery = true, initialView = 'incoming', transactionsOnly = false}: {allowActions?: boolean; allowRecovery?: boolean; initialView?: 'incoming' | 'transactions'; transactionsOnly?: boolean}) {
  const session = useSession(), permissions = session.user?.permissions ?? [];
  const canSms = session.status === 'authenticated' && permissions.includes('sms.read'), canPayments = session.status === 'authenticated' && permissions.includes('payments.read');
  const [view, setView] = useState<'incoming' | 'transactions'>(initialView);
  const actual = transactionsOnly ? 'transactions' : view === 'incoming' && canSms || !canPayments ? 'incoming' : 'transactions';
  const available = transactionsOnly ? canPayments : canSms || canPayments;
  return <><PageHeader eyebrow="Collect Admin / Operations" title={transactionsOnly ? 'MoMo transactions' : 'MoMo receipts'} subtitle={actual === 'incoming' ? 'Mobile-money SMS shared by app users.' : 'Validated payments and their allocation status.'} />
    {!available ? <ErrorState title="Access unavailable" message="Your current account cannot open these records." /> : <>{!transactionsOnly && <div className="momo-views" aria-label="MoMo receipt views">{canSms && <Button variant={actual === 'incoming' ? 'primary' : 'secondary'} aria-pressed={actual === 'incoming'} onClick={() => setView('incoming')}>Incoming SMS</Button>}{canPayments && <Button variant={actual === 'transactions' ? 'primary' : 'secondary'} aria-pressed={actual === 'transactions'} onClick={() => setView('transactions')}>Transactions</Button>}</div>}{actual === 'incoming' ? <Incoming key={session.epoch} /> : <Transactions key={session.epoch} allowActions={allowActions} allowRecovery={allowRecovery} />}</>}
  </>;
}
