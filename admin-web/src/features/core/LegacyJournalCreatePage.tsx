import { useEffect, useLayoutEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, formatMoney, isId } from './contracts';
import { clearPending, readPending, retainPending } from './pendingAttempt';
import {usePendingIdentity} from './usePendingIdentity';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { FeatureAccess } from './types';
import {isLegacyJournalReceipt, parseLegacyJournalOutcome, verifyLegacyJournalScope, withLegacyJournalLock} from './legacyJournalRequest';
import {emptyJournalLine, invalidJournal, journalLineFromInput, type JournalLineInput, parseJournalCreateIntent, type JournalCreateIntent} from './legacyJournalInputs';
import {parseJournalChoices, readActiveJournalGroup, readJournalCreateSource, readLinkedJournalAllocation, type JournalChoice} from './legacyJournalSources';
import './core.css';

export interface LegacyJournalCreateProps extends FeatureAccess { identity: PendingIdentity; allowMutations?: boolean; transactionId?: string; allocationId?: string; fixedGroupId?: string }
const FAMILY = 'operating-createjournal', RESOURCE = 'new', PERMISSION = 'ledger.manage';
type VerifiedSource = Awaited<ReturnType<typeof readJournalCreateSource>>;
type LinkedAllocation = Awaited<ReturnType<typeof readLinkedJournalAllocation>>;

/** Legacy double-entry draft creation; disabled until deployment and rollback are qualified. */
export function LegacyJournalCreatePage({ request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, transactionId, allocationId, fixedGroupId, allowMutations = false }: LegacyJournalCreateProps) {
  const stableIdentity = usePendingIdentity(identity);
  const has = (name: string) => permissions.includes(name) && stableIdentity.permissions.includes(name);
  const linked = transactionId !== undefined || allocationId !== undefined;
  const allowed = financialModel === 'transaction_journals' && (!linked || isId(transactionId) && isId(allocationId)) &&
    (fixedGroupId === undefined || !linked && isId(fixedGroupId)) && role !== 'staff' && isId(actorId) && stableIdentity.id === actorId && stableIdentity.role === role && has(PERMISSION);
  const canCheck = allowed && has('overview.read'); const canWrite = canCheck && has('ledger.read') && has('collections.read') && (!linked || has('payments.read'));
  const scope = JSON.stringify([authorityKey, financialModel, stableIdentity, [...new Set(permissions)].sort(), transactionId, allocationId, fixedGroupId]);
  const current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false), groupRef = useRef(''), lookupEpoch = useRef(0);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const active = () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now();
  const [pending, setPending] = useState<PendingAttempt | null>(null), [review, setReview] = useState<JournalCreateIntent | null>(null), [verified, setVerified] = useState<VerifiedSource | null>(null);
  const [retryAllowed, setRetryAllowed] = useState(false), [acknowledged, setAcknowledged] = useState(false), [createdId, setCreatedId] = useState('');
  const [groups, setGroups] = useState<JournalChoice[]>([]), [accounts, setAccounts] = useState<JournalChoice[]>([]), [groupId, setGroupId] = useState(''), [linkedInfo, setLinkedInfo] = useState<LinkedAllocation | null>(null);
  const [groupSearch, setGroupSearch] = useState(''), [accountSearch, setAccountSearch] = useState(''), [lines, setLines] = useState<JournalLineInput[]>([emptyJournalLine(), emptyJournalLine()]);
  const [description, setDescription] = useState(''), [reason, setReason] = useState(''), [message, setMessage] = useState('');
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading'), [scopeLoaded, setScopeLoaded] = useState('');
  useEffect(() => {
    if (!allowed) return;
    let live = true;
    readPending(stableIdentity, FAMILY, RESOURCE).then(async saved => {
      if (saved && (saved.permission !== PERMISSION || saved.resource_id !== RESOURCE)) return invalidJournal();
      if (saved) parseJournalCreateIntent(saved.intent);
      let fixed: LinkedAllocation | null = null, choices: JournalChoice[] = [], accountChoices: JournalChoice[] = [];
      if (!saved && allowMutations && canWrite) {
        if (linked || fixedGroupId) {
          if (linked) {
            if (!isId(transactionId) || !isId(allocationId)) return invalidJournal();
            fixed = await readLinkedJournalAllocation(request, transactionId, allocationId, actorId);
          }
          const selectedId = fixed?.groupId ?? fixedGroupId!;
          choices = [await readActiveJournalGroup(request, selectedId, actorId)];
          accountChoices = parseJournalChoices(await request(`operations/lookups?kind=accounts&group_id=${selectedId}&search=&limit=100`));
        } else choices = parseJournalChoices(await request('operations/lookups?kind=groups&search=&limit=100'));
      }
      if (!live || current.current !== scope) return;
      groupRef.current = fixed?.groupId ?? fixedGroupId ?? ''; setGroupId(fixed?.groupId ?? fixedGroupId ?? ''); setLinkedInfo(fixed); setAccounts(accountChoices); setLines([emptyJournalLine(), emptyJournalLine()]); setGroups(choices); setPending(saved); setScopeLoaded(scope);
      setState('ready'); setReview(null); setVerified(null); setRetryAllowed(false); setAcknowledged(false);
      setMessage(saved ? 'A previous journal draft needs recovery. Check its original request before continuing.' : !allowMutations ? 'Journal draft creation is not enabled for this workspace.' : !canWrite ? 'Ledger, group, request-history and, for linked drafts, payment read permissions are required.' : '');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('The group, linked allocation, existing journals or draft recovery data could not be verified.'); } });
    return () => { live = false; };
  }, [allowed, allowMutations, canWrite, stableIdentity, request, scope, linked, transactionId, allocationId, fixedGroupId, actorId]);
  const searchGroups = async () => {
    if (!allowMutations || !canWrite || state !== 'ready' || !active() || groupSearch.length > 200 || containsControl(groupSearch)) return;
    const seq = ++lookupEpoch.current; setMessage('');
    try {
      const query = new URLSearchParams({ kind: 'groups', search: groupSearch.trim(), limit: '100' });
      const choices = parseJournalChoices(await request(`operations/lookups?${query}`));
      if (active() && gate.current && lookupEpoch.current === seq) setGroups(previous => [...new Map([...previous, ...choices].map(item => [item.id, item])).values()]);
    } catch { if (active()) setMessage('Groups could not be verified. Search again.'); }
  };
  const searchAccounts = async (selectedGroup: string, search: string, reset: boolean) => {
    if (!allowMutations || !canWrite || !active() || !isId(selectedGroup) || search.length > 200 || containsControl(search)) return;
    const seq = ++lookupEpoch.current; setMessage('');
    try {
      const query = new URLSearchParams({ kind: 'accounts', group_id: selectedGroup, search: search.trim(), limit: '100' });
      const choices = parseJournalChoices(await request(`operations/lookups?${query}`));
      if (active() && gate.current && lookupEpoch.current === seq && groupRef.current === selectedGroup) setAccounts(previous => [...new Map([...(reset ? [] : previous), ...choices].map(item => [item.id, item])).values()]);
    } catch { if (active() && groupRef.current === selectedGroup) setMessage('Group accounts could not be verified. Search again.'); }
  };
  const changeGroup = (value: string) => {
    groupRef.current = value; ++lookupEpoch.current; setGroupId(value); setAccounts([]); setAccountSearch(''); setLines([emptyJournalLine(), emptyJournalLine()]);
    if (value) void searchAccounts(value, '', true);
  };
  const changeLine = (index: number, field: keyof JournalLineInput, value: string) => setLines(previous => previous.map((line, i) => i === index ? { ...line, [field]: value } : line));
  const reviewRequest = async (body?: JournalCreateIntent) => {
    if (!allowMutations || !canWrite || busy.current || !active()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      if (pending && !body) return invalidJournal();
      const checked = parseJournalCreateIntent(body ?? { group_id: groupId, description: description.trim(), allocation_id: linked ? allocationId : null,
        entries: lines.map(journalLineFromInput), reason: reason.trim() });
      if (fixedGroupId && checked.group_id !== fixedGroupId) return invalidJournal();
      if (new TextEncoder().encode(JSON.stringify(checked)).byteLength > 16384) throw new Error('Recovery limit');
      const latest = await readJournalCreateSource(request, checked, actorId, transactionId, allocationId);
      if (!active() || !gate.current) return;
      setVerified(latest); setReview(checked); setRetryAllowed(false); setAcknowledged(false);
    } catch { if (active()) setMessage('Check the active group, RWF accounts, balanced whole-franc entries, confirmed allocation and reason. No draft was submitted.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const send = async (body: JournalCreateIntent, key: string) => {
    if (!canWrite || !allowMutations || !verified || !acknowledged || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null, dispatched = false;
    try {
      const checked = parseJournalCreateIntent(body);
      await withLegacyJournalLock(`collect-admin-legacy-journal-create:${actorId}`, async () => {
        if (pending) {
          const original = parseLegacyJournalOutcome(await request(`operations/requests/${key}`), 1);
          if (!active() || !gate.current) return;
          if (original.status === 'succeeded' && original.receipt) {
            await verifyLegacyJournalScope(request, key, original.receipt, 'journals.post'); if (!active() || !gate.current) return;
            await clearPending(stableIdentity, FAMILY, RESOURCE, key); if (!active()) return;
            setPending(null); setReview(null); setCreatedId(original.receipt.resource_id); setState('success'); setMessage('The original journal draft request was recorded.'); return;
          }
          if (original.status !== 'not_found') throw new Error('Original request unresolved');
        }
        const latest = await readJournalCreateSource(request, checked, actorId, transactionId, allocationId);
        if (JSON.stringify(latest) !== JSON.stringify(verified) || !active() || !gate.current) throw new Error('Group or account changed');
        if (!pending && await readPending(stableIdentity, FAMILY, RESOURCE)) throw new Error('Original request needs review');
        retained = await retainPending(stableIdentity, FAMILY, RESOURCE, key, PERMISSION, checked);
        if (!active() || !gate.current) return;
        setPending(retained); setRetryAllowed(false); dispatched = true;
        const direct = await request('operations/journals', { method: 'POST', body: checked, idempotencyKey: key });
        if (!active() || !isLegacyJournalReceipt(direct, 1)) throw new Error('Invalid receipt');
        const original = parseLegacyJournalOutcome(await request(`operations/requests/${key}`), 1);
        if (!active() || original.status !== 'succeeded' || !original.receipt || !(['request_id', 'resource_type', 'resource_id', 'version', 'status'] as const).every(field => original.receipt![field] === direct[field])) throw new Error('Unverified receipt');
        await verifyLegacyJournalScope(request, key, original.receipt, 'journals.post'); if (!active() || !gate.current) return;
        await clearPending(stableIdentity, FAMILY, RESOURCE, key); if (!active()) return;
        setPending(null); setReview(null); setCreatedId(direct.resource_id); setState('success'); setMessage('The journal draft was recorded.');
      });
    } catch {
      if (!active()) return;
      let storageFailed = false; const saved = retained ?? await readPending(stableIdentity, FAMILY, RESOURCE).catch(() => { storageFailed = true; return null; });
      setPending(saved); setReview(null); setVerified(null); setAcknowledged(false);
      if (storageFailed || dispatched && !saved) { setState('error'); setMessage('Recovery data could not be verified. Check the original request before another change.'); }
      else { setState('ready'); setMessage(saved ? 'The result is unconfirmed. Check the original journal draft request before continuing.' : 'The group, accounts or request lock could not be verified. No draft was submitted.'); }
    } finally { busy.current = false; }
  };
  const check = async () => {
    if (!pending || !active() || busy.current) return;
    if (!canCheck) { setMessage('Your account cannot check request history. Contact an authorized administrator.'); return; }
    busy.current = true; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const saved = parseJournalCreateIntent(pending.intent), result = parseLegacyJournalOutcome(await request(`operations/requests/${pending.request_key}`), 1);
      if (!active()) return;
      if (result.status === 'succeeded' && result.receipt) {
        await verifyLegacyJournalScope(request, pending.request_key, result.receipt, 'journals.post'); if (!active()) return;
        await clearPending(stableIdentity, FAMILY, RESOURCE, pending.request_key); if (!active()) return;
        setPending(null); setCreatedId(result.receipt.resource_id); setState('success'); setMessage('The original journal draft request was recorded.'); return;
      }
      if (result.status === 'not_found') {
        const retry = allowMutations && canWrite && (!fixedGroupId || saved.group_id === fixedGroupId) && (linked ? saved.allocation_id === allocationId : saved.allocation_id == null); setRetryAllowed(retry);
        setMessage(retry ? 'No completed request was found. You may review the same request with its original reference.' : saved.allocation_id != null ? 'No completed request was found. Return to the original transaction allocation to review the same request, or keep the reference and check again.' : 'No completed request was found. Keep the reference and check again.');
      } else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh the record.' : 'The request is still pending. Check again before continuing.');
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const submitReview = (event: FormEvent) => { event.preventDefault(); void reviewRequest(); };
  return <>
    <PageHeader title="Create journal draft" subtitle="Prepare balanced legacy RWF entries for independent posting." actions={<Button type="button" onClick={() => navigate(linked && isId(transactionId) ? `/admin/transactions/${transactionId}` : fixedGroupId && isId(fixedGroupId) ? `/admin/groups/${fixedGroupId}` : '/admin/ledgers')}>{linked ? 'Back to transaction' : fixedGroupId ? 'Back to group' : 'Back to ledgers'}</Button>} />
    {!allowed ? <ErrorState title="Creation unavailable" message={financialModel === 'canonical_evidence_ledger' ? 'Double-entry journal creation is unavailable for the canonical evidence ledger.' : 'Your account cannot create journal drafts in this workspace.'} /> :
      state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Draft request recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/ledgers/${createdId}`)}>View journal</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code> · Group {String(pending.intent.group_id)}</p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewRequest(parseJournalCreateIntent(pending.intent))}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && canWrite && <>
          <p>Use active accounts in the same active group. Search to find groups or accounts beyond the first 100 results.</p>
          {linkedInfo && <p>Confirmed transaction {linkedInfo.transactionId} · Allocation {linkedInfo.allocationId} · Member {linkedInfo.memberId ?? 'Not recorded'} · Required debit and credit totals: {formatMoney(linkedInfo.amount)}.</p>}
          <div className="core-edit-form">{!linked && !fixedGroupId && <><label>Search groups<input className="admin-input" value={groupSearch} maxLength={200} onChange={event => setGroupSearch(event.target.value)} /></label><Button type="button" disabled={state !== 'ready'} onClick={() => void searchGroups()}>Search groups</Button>
          <label>Group<select className="admin-input" value={groupId} onChange={event => changeGroup(event.target.value)}><option value="">Select group</option>{groups.map(group => <option key={group.id} value={group.id}>{group.label}</option>)}</select></label></>}
          {(linkedInfo || fixedGroupId) && <p>Group: {groups[0]?.label} · {linkedInfo?.groupId ?? fixedGroupId}</p>}
          <label>Search accounts<input className="admin-input" value={accountSearch} maxLength={200} onChange={event => setAccountSearch(event.target.value)} /></label><Button type="button" disabled={!groupId || state !== 'ready'} onClick={() => void searchAccounts(groupId, accountSearch, false)}>Search accounts</Button></div>
          <form className="core-edit-form" onSubmit={submitReview}><label>Journal description<textarea className="admin-input" value={description} minLength={3} maxLength={1000} required onChange={event => setDescription(event.target.value)} /></label>
            {lines.map((line, index) => <fieldset key={index}><legend>Entry {index + 1}</legend><label>Account {index + 1}<select className="admin-input" value={line.account} required onChange={event => changeLine(index, 'account', event.target.value)}><option value="">Select account</option>{accounts.map(account => <option key={account.id} value={account.id}>{account.label}</option>)}</select></label>
              <label>Debit RWF {index + 1}<input className="admin-input" inputMode="numeric" value={line.debit} onChange={event => changeLine(index, 'debit', event.target.value)} /></label><label>Credit RWF {index + 1}<input className="admin-input" inputMode="numeric" value={line.credit} onChange={event => changeLine(index, 'credit', event.target.value)} /></label><label>Entry description {index + 1}<input className="admin-input" maxLength={500} value={line.description} onChange={event => changeLine(index, 'description', event.target.value)} /></label>
              {lines.length > 2 && <Button type="button" onClick={() => setLines(previous => previous.filter((_, i) => i !== index))}>Remove entry {index + 1}</Button>}</fieldset>)}
            {lines.length < 100 && <Button type="button" onClick={() => setLines(previous => [...previous, emptyJournalLine()])}>Add entry</Button>}
            <label>Reason for draft<textarea className="admin-input" value={reason} minLength={8} maxLength={1000} required onChange={event => setReason(event.target.value)} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review journal draft</Button></form>
        </>}
        {review && verified && allowMutations && canWrite && <section><h2>Review journal draft</h2><p>{review.description} · Group: {verified.groupTitle} · {verified.groupId}</p>{verified.linked && <p>Confirmed transaction {verified.linked.transactionId} · Allocation {verified.linked.allocationId} · Member {verified.linked.memberId ?? 'Not recorded'} · Allocation amount {formatMoney(verified.linked.amount)}.</p>}
          <div className="admin-table-wrap" role="region" aria-label="Draft journal entries"><table className="admin-table"><thead><tr><th scope="col">Line</th><th scope="col">Account</th><th scope="col">Debit</th><th scope="col">Credit</th><th scope="col">Description</th></tr></thead><tbody>{review.entries.map((line, index) => { const account = verified.accounts.find(item => item.id === line.account_id)!; return <tr key={index}><td>{index + 1}</td><td>{account.code} · {account.name} · {account.id}</td><td>{formatMoney(line.debit_rwf)}</td><td>{formatMoney(line.credit_rwf)}</td><td>{line.description || '—'}</td></tr>; })}</tbody></table></div>
          <p>Debit total: {formatMoney(review.entries.reduce((total, line) => total + line.debit_rwf, 0))} · Credit total: {formatMoney(review.entries.reduce((total, line) => total + line.credit_rwf, 0))}</p><p>Reason: {review.reason}. This creates a draft, not a posted journal or provider settlement.</p>
          <label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed the group, every debit and credit, and the reason.</label>
          <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); setVerified(null); setAcknowledged(false); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !acknowledged} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No draft was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm draft'}</Button>
        </section>}
      </div></Card>}
  </>;
}
