/* eslint-disable no-control-regex -- Reject control characters in operator search input. */
import {useCallback, useState, type FormEvent} from 'react';
import {Link} from 'react-router';
import {useSession} from '../../session/SessionProvider';
import {Button, Card, StatusBadge} from '../../ui';
import {parseSmsPage, type Page, type SmsReceipt} from './contracts';
import {formatStatus, formatTime} from './OperationsRecords';
import {MomoPager, MomoResult, MomoTable, momoReadOptions} from './MomoRecordViews';
import {useOperationRead} from './useOperationRead';

export function MomoIncomingSms() {
  const session = useSession(), request = session.request, [input, setInput] = useState(''), [search, setSearch] = useState(''), [offset, setOffset] = useState(0);
  const load = useCallback(async () => {
    const query = new URLSearchParams({source_kind: 'capture', limit: '25', offset: String(offset)});
    if (search) query.set('search', search);
    const page = parseSmsPage(await request(`sms/receipts?${query}`), offset);
    if (page.rows.some((row) => row.source_kind !== 'capture')) throw new Error('Source mismatch.');
    return page;
  }, [offset, search, request]);
  const {result, retry} = useOperationRead(`${session.epoch}:capture:${search}:${offset}`, session.status === 'authenticated' && !!session.user?.permissions.includes('sms.read'), load, {...momoReadOptions, pollMs: 15000});
  const submit = (event: FormEvent) => {event.preventDefault(); if (input.length <= 200 && !/[\x00-\x1f\x7f]/.test(input)) {setSearch(input.trim()); setOffset(0);}};
  return <Card className="operations-records"><div className="operations-toolbar"><h2>Incoming SMS</h2><form className="operations-search" onSubmit={submit}><label className="admin-sr-only" htmlFor="momo-sms-search">Search incoming SMS</label><input id="momo-sms-search" className="admin-input" value={input} maxLength={200} onChange={(event) => setInput(event.target.value)} placeholder="User name, member ID or receipt ID" /><Button type="submit">Search</Button></form><Button onClick={retry}>Refresh</Button></div>
    <p className="operations-note">Updates automatically while this page is visible. An upload does not confirm payment or settlement.</p>
    <MomoResult result={result} retry={retry} empty={(page: Page<SmsReceipt>) => page.rows.length === 0 && page.offset === 0}>{(page) => <>{page.rows.length > 0 && <MomoTable name="Incoming mobile-money SMS" headings={['App user', 'Member ID', 'SMS time · Kigali', 'Uploaded · Kigali', 'Status']}>
      {page.rows.map((row) => <tr key={row.id}><td><Link className="operations-link" to={`/admin/sms-receipts/capture/${row.id}?returnTo=%2Fadmin%2Fmomo-receipts`}>{row.display_name ?? 'App user'}</Link></td><td>{row.public_id ?? 'Not recorded'}</td><td>{formatTime(row.received_at)}</td><td>{formatTime(row.created_at)}</td><td><StatusBadge>{formatStatus(row.status)}</StatusBadge></td></tr>)}</MomoTable>}<MomoPager page={page} change={setOffset} /></>}</MomoResult>
  </Card>;
}
