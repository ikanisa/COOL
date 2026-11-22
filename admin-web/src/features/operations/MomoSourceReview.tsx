import {useCallback, useState} from 'react';
import {useSession} from '../../session/SessionProvider';
import {Button, Card, Dialog} from '../../ui';
import type {Page} from './contracts';
import {parseMomoSources, sourceStatuses, type MomoSourceJob, type SourceStatus} from './momoContracts';
import {MomoSourceRevealPanel} from './MomoSourceRevealPanel';
import {MomoSourceActionsPanel, MomoSourceRecoveryPanel} from './MomoSourceActionsPanel';
import type {MomoExtraction} from './momoSourceActions';
import {Facts, formatStatus, formatTime} from './OperationsRecords';
import {MomoPager, MomoResult, MomoTable, momoReadOptions} from './MomoRecordViews';
import {useOperationRead} from './useOperationRead';

export function MomoSourceReview({allowActions, allowRecovery}: {allowActions: boolean; allowRecovery: boolean}) {
  const session = useSession(), request = session.request, [status, setStatus] = useState<SourceStatus>('needs_review'), [offset, setOffset] = useState(0);
  const [selected, setSelected] = useState<{source: MomoSourceJob; epoch: number} | null>(null);
  const load = useCallback(async () => parseMomoSources(await request(`momo/sources?${new URLSearchParams({status, limit: '25', offset: String(offset)})}`), offset, status), [request, offset, status]);
  const {result, retry} = useOperationRead(`${session.epoch}:momo-sources:${status}:${offset}`, session.status === 'authenticated' && !!session.user?.permissions.includes('sms.read'), load, momoReadOptions);
  return <Card className="operations-detail"><h2>Source messages needing attention</h2><p>Unresolved source messages are not validated payments. This view uses separate source filters and excludes transaction totals.</p><label className="operations-filter">Source state<select className="admin-input" value={status} onChange={(event) => {setStatus(event.target.value as SourceStatus); setOffset(0);}}>{sourceStatuses.map((value) => <option key={value} value={value}>{formatStatus(value)}</option>)}</select></label>
    <MomoResult result={result} retry={retry} empty={(page: Page<MomoSourceJob>) => page.rows.length === 0 && page.offset === 0}>{(page) => <>{page.rows.length > 0 && <MomoTable name="MoMo source messages" headings={['SMS reference', 'State', 'Received · Kigali', 'Processing issue', 'Receiving account', 'Binding']}>
      {page.rows.map((row) => <tr key={row.raw_sms_id}><td><button type="button" className="operations-link" onClick={() => setSelected({source: row, epoch: session.epoch})}>{row.raw_sms_id}</button></td><td>{formatStatus(row.state)}</td><td>{formatTime(row.received_at)}</td><td>{row.last_error ?? formatStatus(row.state)}</td><td>{row.receiving_account_id ?? 'Unassigned'}</td><td>{row.binding_id ?? 'Unassigned'}</td></tr>)}</MomoTable>}<MomoPager page={page} change={setOffset} /></>}</MomoResult>
  {allowRecovery && <MomoSourceRecoveryPanel enabled={allowActions} onUpdated={retry} />}
  {selected?.epoch === session.epoch && <MomoSourceDialog source={selected.source} allowActions={allowActions} allowRecovery={allowRecovery} onClose={() => setSelected(null)} onUpdated={() => {setSelected(null); retry();}} />}</Card>;
}
function MomoSourceDialog({source, allowActions, allowRecovery, onClose, onUpdated}: {source: MomoSourceJob; allowActions: boolean; allowRecovery: boolean; onClose: () => void; onUpdated: () => void}) {
  const [candidate, setCandidate] = useState<MomoExtraction | null>(null);
  return <Dialog open title="Source message" onClose={onClose} footer={<Button onClick={onClose}>Close</Button>}><p>A source message is evidence and does not by itself credit a contribution.</p><Facts items={[
    ['SMS reference', source.raw_sms_id], ['State', formatStatus(source.state)], ['Received · Kigali', formatTime(source.received_at)], ['Processing issue', source.last_error ?? formatStatus(source.state)], ['Receiving account', source.receiving_account_id ?? 'Unassigned'], ['Binding', source.binding_id ?? 'Unassigned'], ['Body SHA-256', source.body_sha256 ?? 'Not recorded'],
  ]} />{allowRecovery && <><MomoSourceRevealPanel source={source} enabled={allowActions} onCandidate={setCandidate} /><MomoSourceActionsPanel source={source} candidate={candidate} enabled={allowActions} onUpdated={onUpdated} /></>}</Dialog>;
}
