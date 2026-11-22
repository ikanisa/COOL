/* eslint-disable no-control-regex -- Reject control characters in operator search input. */
import {useCallback, useState, type FormEvent} from 'react';
import {useSession} from '../../session/SessionProvider';
import {Button, Card, EmptyState, StatusBadge} from '../../ui';
import {isValidId} from './contracts';
import {momoStatuses, parseMomoPage, type MomoFilters, type MomoPage, type MomoStatus} from './momoContracts';
import {MomoMemberChecks, MomoPaymentDetail} from './MomoPaymentReview';
import {MomoSourceReview} from './MomoSourceReview';
import {formatStatus, formatTime} from './OperationsRecords';
import {formatMomoAmount, MomoPager, MomoResult, MomoTable, momoReadOptions} from './MomoRecordViews';
import {useOperationRead} from './useOperationRead';

const initialFilters: MomoFilters = {search: '', status: '', account: '', group: '', from: '', to: ''};
function kigaliDate(value: string, end: boolean): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const date = new Date(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) return null;
  return new Date(date.getTime() - 7200000 + (end ? 86399999 : 0)).toISOString();
}
export function MomoTransactionList({allowActions, allowRecovery}: {allowActions: boolean; allowRecovery: boolean}) {
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
  const {result, retry} = useOperationRead(`${session.epoch}:transactions:${JSON.stringify(filters)}:${offset}`, session.status === 'authenticated' && permissions.includes('payments.read'), load, momoReadOptions);
  const apply = (event: FormEvent) => {
    event.preventDefault();
    const start = from ? kigaliDate(from, false) : '', end = to ? kigaliDate(to, true) : '';
    if (search.length > 200 || /[\x00-\x1f\x7f]/.test(search) || account && !isValidId(account) || group && !isValidId(group) || start === null || end === null || start && end && start > end) {setFilterError('Check the search, account, group and date values.'); return;}
    setFilterError(''); setOffset(0); setFilters({search: search.trim(), status, account: permissions.includes('receivers.read') ? account : '', group: permissions.includes('collections.read') ? group : '', from: start, to: end});
  };
  return <><Card className="operations-records"><form className="operations-toolbar" onSubmit={apply}><h2>Transactions</h2>
    <label className="operations-filter">Search MoMo TX ID or payer<input className="admin-input" value={search} onChange={(event) => setSearch(event.target.value)} maxLength={200} /></label>
    <label className="operations-filter">Payment status<select className="admin-input" value={status} onChange={(event) => setStatus(event.target.value as MomoStatus)}><option value="">All statuses</option>{momoStatuses.map((value) => <option key={value} value={value}>{formatStatus(value)}</option>)}</select></label>
    {permissions.includes('receivers.read') && <label className="operations-filter">Receiving account ID<input className="admin-input" value={account} onChange={(event) => setAccount(event.target.value)} /></label>}
    {permissions.includes('collections.read') && <label className="operations-filter">Group ID<input className="admin-input" value={group} onChange={(event) => setGroup(event.target.value)} /></label>}
    <label className="operations-filter">From · Kigali<input type="date" className="admin-input" value={from} onChange={(event) => setFrom(event.target.value)} /></label><label className="operations-filter">To · Kigali<input type="date" className="admin-input" value={to} onChange={(event) => setTo(event.target.value)} /></label>
    <Button type="submit">Apply filters</Button><Button onClick={retry}>Refresh</Button>{canCheck && <Button onClick={() => setChecking(true)}>Member checks</Button>}</form>{filterError && <p role="alert" className="operations-note">{filterError}</p>}
    <MomoResult result={result} retry={retry} empty={() => false}>{(page: MomoPage) => <><p className="operations-note">Received {formatMomoAmount(page.totals.received_minor)} · Credited {formatMomoAmount(page.totals.credited_minor)} · Unallocated {formatMomoAmount(page.totals.unallocated_minor)}<br />Provider transaction date · As of {formatTime(page.asOf)} Kigali. Provider confirmation and settlement are not asserted.</p>
      {page.rows.length === 0 ? <EmptyState title="No matching validated payments" /> : <MomoTable name="MoMo transactions" headings={['Transaction time · Kigali', 'Amount', 'Payer', 'MoMo TX ID', 'Beneficiary', 'Group', 'Status', 'Review issue']}>
      {page.rows.map((row) => <tr key={row.id}><td>{row.transaction_at ? formatTime(row.transaction_at) : `Received ${formatTime(row.created_at)}`}</td><td>{formatMomoAmount(row.amount_minor)}</td><td>{row.payer_name ?? 'Unknown payer'}{row.payer_last3 ? ` · …${row.payer_last3}` : ''}</td><td><button type="button" className="operations-link" onClick={() => setSelected({id: row.id, epoch: session.epoch})}>{row.provider_transaction_id}</button></td><td>{row.member_name ?? 'Unassigned'}</td><td>{row.group_name ?? 'Unassigned'}</td><td><StatusBadge>{formatStatus(row.status)}</StatusBadge></td><td>{row.has_conflict ? 'Needs review' : '—'}</td></tr>)}</MomoTable>}<MomoPager page={page} change={setOffset} /></>}</MomoResult>
  </Card>{filters.status === 'needs_attention' && permissions.includes('sms.read') && <MomoSourceReview allowActions={allowActions} allowRecovery={allowRecovery} />}
  {selected?.epoch === session.epoch && <MomoPaymentDetail id={selected.id} allowActions={allowActions} allowRecovery={allowRecovery} onClose={() => setSelected(null)} />}
  {checking && canCheck && <MomoMemberChecks onClose={() => setChecking(false)} onSearch={(value) => {setChecking(false); setSearch(value); setStatus(''); setOffset(0); setFilters((previous) => ({...previous, search: value, status: ''}));}} />}</>;
}
