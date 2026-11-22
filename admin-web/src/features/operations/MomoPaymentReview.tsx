/* eslint-disable no-control-regex -- Reject control characters in member-supplied references. */
import {useCallback, useState} from 'react';
import {Link} from 'react-router';
import {useSession} from '../../session/SessionProvider';
import {Button, Dialog} from '../../ui';
import {isValidId, type Page} from './contracts';
import {parseMomoDetail, parseMomoMemberChecks, type MomoDetail, type MomoMemberCheck} from './momoContracts';
import {MomoAssignmentPanel} from './MomoAssignmentPanel';
import {MomoConflictReviewPanel} from './MomoConflictReviewPanel';
import {Facts, formatStatus, formatTime} from './OperationsRecords';
import {formatMomoAmount, MomoPager, MomoResult, MomoTable, momoReadOptions} from './MomoRecordViews';
import {useOperationRead} from './useOperationRead';

export function MomoMemberChecks({onClose, onSearch}: {onClose: () => void; onSearch: (reference: string) => void}) {
  const session = useSession(), request = session.request, [offset, setOffset] = useState(0);
  const permitted = session.status === 'authenticated' && ['payments.read', 'users.read', 'collections.read'].every((permission) => session.user?.permissions.includes(permission));
  const load = useCallback(async () => parseMomoMemberChecks(await request(`momo/transactions/payment-checks?limit=25&offset=${offset}`), offset), [offset, request]);
  const {result, retry} = useOperationRead(`${session.epoch}:member-checks:${offset}`, permitted, load, momoReadOptions);
  return <Dialog open title="Member payment checks" onClose={onClose} footer={<><Button onClick={retry}>Refresh</Button><Button onClick={onClose}>Close</Button></>}>
    <p>Member-supplied requests. References and notes are unverified; they do not establish a received payment or credit.</p>
    <MomoResult result={result} retry={retry} empty={(page: Page<MomoMemberCheck>) => page.rows.length === 0 && page.offset === 0}>{(page) => <>{page.rows.length > 0 && <MomoTable name="Member payment checks" headings={['Member', 'Member ID', 'Group', 'Expected amount', 'Requested · Kigali', 'Status', 'Unverified reference', 'Member note', 'Request ID', 'Search']}>
      {page.rows.map((row) => <tr key={row.id}><td>{row.member_name}</td><td>{row.member_public_id}</td><td>{row.group_name}</td><td>{formatMomoAmount(row.expected_amount_minor)}</td><td>{formatTime(row.requested_at)}</td><td>Request received</td><td>{row.provider_reference ?? 'Not recorded'}</td><td>{row.evidence_note ?? 'Not recorded'}</td><td>{row.id}</td><td><Button disabled={!row.provider_reference?.trim() || /[\x00-\x1f\x7f]/.test(row.provider_reference)} onClick={() => row.provider_reference && onSearch(row.provider_reference.trim())}>Search reference</Button></td></tr>)}</MomoTable>}<MomoPager page={page} change={setOffset} /></>}</MomoResult>
  </Dialog>;
}
export function MomoPaymentDetail({id, allowActions, allowRecovery, onClose}: {id: string; allowActions: boolean; allowRecovery: boolean; onClose: () => void}) {
  const session = useSession(), request = session.request;
  const load = useCallback(async () => parseMomoDetail(await request(`momo/transactions/${id}`), id), [id, request]);
  const {result, retry} = useOperationRead(`${session.epoch}:momo-detail:${id}`, session.status === 'authenticated' && !!session.user?.permissions.includes('payments.read') && isValidId(id), load, momoReadOptions);
  return <Dialog open title="Payment details" onClose={onClose} footer={<Button onClick={onClose}>Close</Button>}><MomoResult result={result} retry={retry} empty={() => false}>{(detail: MomoDetail) => <><Facts items={[
    ['Amount', formatMomoAmount(detail.transaction.amount_minor)], ['Status', formatStatus(detail.transaction.status)], ['MoMo TX ID', detail.transaction.provider_transaction_id], ['Receiving account', detail.transaction.recipient_name], ['MoMo code', detail.transaction.public_code], ['Payer', detail.transaction.payer_name ?? 'Unknown payer'], ['Payer last 3', detail.transaction.payer_last3 ?? 'Not recorded'], ['Beneficiary', detail.transaction.member_name ?? 'Unassigned'], ['Group', detail.transaction.group_name ?? 'Unassigned'], ['Transaction time · Kigali', detail.transaction.transaction_at ? formatTime(detail.transaction.transaction_at) : `Received ${formatTime(detail.transaction.created_at)}`],
  ]} />
  {detail.transaction.has_conflict === 1 && <p role="status">Conflicting payment evidence requires review. The recorded financial status is preserved.</p>}
  {detail.transaction.payment_id && session.user?.permissions.includes('reconciliations.read') && <p><Link className="operations-link" to={`/admin/reconciliations/${detail.transaction.payment_id}`}>Open financial review</Link></p>}
  {allowRecovery && <><MomoAssignmentPanel key={`${session.epoch}:${id}`} detail={detail} enabled={allowActions} onUpdated={retry} />
  <MomoConflictReviewPanel key={`${session.epoch}:${id}:conflict`} detail={detail} enabled={allowActions} onUpdated={retry} /></>}
  <h3>Source and processing history</h3><p>Parsing does not confirm provider API settlement.</p>{detail.sources.length ? <MomoTable name="Payment source and processing history" headings={['Source reference', 'Relationship', 'Outcome', 'Parser', 'Recorded · Kigali']}>{detail.sources.map((source, index) => <tr key={`${source.raw_sms_id}:${index}`}><td>{source.raw_sms_id}</td><td>{formatStatus(source.relation)}</td><td>{formatStatus(source.outcome)}</td><td>{source.parser_version}</td><td>{formatTime(source.created_at)}</td></tr>)}</MomoTable> : <p>No source history recorded.</p>}</>}</MomoResult></Dialog>;
}
