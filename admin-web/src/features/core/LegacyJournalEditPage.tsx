import { useEffect, useLayoutEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, formatMoney, isId } from './contracts';
import { clearPending, readPending, retainPending } from './pendingAttempt';
import {usePendingIdentity} from './usePendingIdentity';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { FeatureAccess } from './types';
import {isLegacyJournalReceipt, parseLegacyJournalOutcome, verifyLegacyJournalScope, withLegacyJournalLock} from './legacyJournalRequest';
import {emptyJournalLine, invalidJournal, journalLineFromInput, type JournalLineInput, parseJournalEditIntent, type JournalEditIntent} from './legacyJournalInputs';
import {parseJournalChoices, readExistingJournal, readJournalEditSource, type JournalEditReview} from './legacyJournalSources';
import './core.css';

export interface LegacyJournalEditProps extends FeatureAccess { id: string; identity: PendingIdentity; allowMutations?: boolean }
const FAMILY = 'operating-updatejournal', PERMISSION = 'ledger.manage';
type VerifiedDraft = Awaited<ReturnType<typeof readExistingJournal>>;

/** Legacy double-entry draft replacement; disabled until deployment and rollback are qualified. */
export function LegacyJournalEditPage({ id, request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, allowMutations = false }: LegacyJournalEditProps) {
  const stableIdentity = usePendingIdentity(identity);
  const has = (name: string) => permissions.includes(name) && stableIdentity.permissions.includes(name);
  const allowed = financialModel === 'transaction_journals' && role !== 'staff' && isId(id) && isId(actorId) && stableIdentity.id === actorId && stableIdentity.role === role && has(PERMISSION);
  const canCheck = allowed && has('overview.read'), canWrite = canCheck && has('ledger.read') && has('collections.read'), canReadPayments = has('payments.read');
  const scope = JSON.stringify([authorityKey, id, financialModel, stableIdentity, [...new Set(permissions)].sort()]);
  const current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false), lookupEpoch = useRef(0);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const active = () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now();
  const [pending, setPending] = useState<PendingAttempt | null>(null), [original, setOriginal] = useState<VerifiedDraft | null>(null), [review, setReview] = useState<JournalEditIntent | null>(null), [verified, setVerified] = useState<JournalEditReview | null>(null);
  const [choices, setChoices] = useState<{ id: string; label: string }[]>([]), [accountSearch, setAccountSearch] = useState(''), [lines, setLines] = useState<JournalLineInput[]>([]), [description, setDescription] = useState(''), [reason, setReason] = useState('');
  const [retryAllowed, setRetryAllowed] = useState(false), [acknowledged, setAcknowledged] = useState(false), [message, setMessage] = useState('');
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading'), [scopeLoaded, setScopeLoaded] = useState('');
  useEffect(() => {
    if (!allowed) return;
    let live = true;
    readPending(stableIdentity, FAMILY, id).then(async saved => {
      if (saved && (saved.permission !== PERMISSION || saved.resource_id !== id)) return invalidJournal();
      if (saved) parseJournalEditIntent(saved.intent);
      const draft = !saved && allowMutations && canWrite ? await readExistingJournal(request, id, actorId, canReadPayments, 'edit') : null;
      if (!live || current.current !== scope) return;
      setPending(saved); setOriginal(draft); setReview(null); setVerified(null); setRetryAllowed(false); setAcknowledged(false); setScopeLoaded(scope); setState('ready');
      setDescription(draft?.description ?? ''); setLines(draft?.lines.map(line => ({ account: line.accountId, debit: line.debit ? String(line.debit) : '', credit: line.credit ? String(line.credit) : '', description: line.description })) ?? []);
      setChoices(draft?.accounts.map(account => ({ id: account.id, label: `${account.code} · ${account.name}${account.status === 'closed' ? ' (closed)' : ''}` })) ?? []);
      setMessage(saved ? 'A previous draft replacement needs recovery. Check its original request before continuing.' : !allowMutations ? 'Journal draft editing is not enabled for this workspace.' : !canWrite ? 'Ledger, group and request-history read permissions are required to edit a draft.' : '');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('The draft, linked allocation or recovery data could not be verified.'); } });
    return () => { live = false; };
  }, [allowed, allowMutations, canWrite, canReadPayments, stableIdentity, request, actorId, id, scope]);
  const searchAccounts = async () => {
    if (!allowMutations || !canWrite || !original || state !== 'ready' || !active() || accountSearch.length > 200 || containsControl(accountSearch)) return;
    const seq = ++lookupEpoch.current; setMessage('');
    try {
      const query = new URLSearchParams({ kind: 'accounts', group_id: original.groupId, search: accountSearch.trim(), limit: '100' });
      const loaded = parseJournalChoices(await request(`operations/lookups?${query}`));
      if (active() && gate.current && lookupEpoch.current === seq) setChoices(previous => [...new Map([...previous, ...loaded].map(item => [item.id, item])).values()]);
    } catch { if (active()) setMessage('Group accounts could not be verified. Search again.'); }
  };
  const changeLine = (index: number, field: keyof JournalLineInput, value: string) => setLines(previous => previous.map((line, i) => i === index ? { ...line, [field]: value } : line));
  const reviewRequest = async (body?: JournalEditIntent) => {
    if (!allowMutations || !canWrite || busy.current || !active()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      if (pending && !body || !pending && !original) return invalidJournal();
      const checked = parseJournalEditIntent(body ?? { expected_version: original!.version, description: description.trim(),
        entries: lines.map(journalLineFromInput), reason: reason.trim() });
      if (new TextEncoder().encode(JSON.stringify(checked)).byteLength > 16384) return invalidJournal();
      const latest = await readJournalEditSource(request, id, actorId, canReadPayments, checked);
      if (original && JSON.stringify(latest.draft) !== JSON.stringify(original)) throw new Error('Draft changed');
      if (!active() || !gate.current) return;
      setVerified(latest); setReview(checked); setRetryAllowed(false); setAcknowledged(false);
    } catch { if (active()) setMessage('Check the draft version, active group and accounts, balanced whole-franc entries and any confirmed allocation. No change was submitted.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const send = async (body: JournalEditIntent, key: string) => {
    if (!canWrite || !allowMutations || !verified || !acknowledged || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null, dispatched = false;
    try {
      const checked = parseJournalEditIntent(body);
      await withLegacyJournalLock(`collect-admin-legacy-journal:${actorId}:${id}`, async () => {
        if (pending) {
          const prior = parseLegacyJournalOutcome(await request(`operations/requests/${key}`), checked.expected_version + 1, id);
          if (!active() || !gate.current) return;
          if (prior.status === 'succeeded' && prior.receipt) {
            await verifyLegacyJournalScope(request, key, prior.receipt, 'journals.patch'); if (!active() || !gate.current) return;
            await clearPending(stableIdentity, FAMILY, id, key); if (!active()) return;
            setPending(null); setReview(null); setState('success'); setMessage('The original draft replacement was recorded.'); return;
          }
          if (prior.status !== 'not_found') throw new Error('Original request unresolved');
        }
        const latest = await readJournalEditSource(request, id, actorId, canReadPayments, checked);
        if (JSON.stringify(latest) !== JSON.stringify(verified) || !active() || !gate.current) throw new Error('Draft changed');
        if (!pending && await readPending(stableIdentity, FAMILY, id)) throw new Error('Original request needs review');
        retained = await retainPending(stableIdentity, FAMILY, id, key, PERMISSION, checked);
        if (!active() || !gate.current) return;
        setPending(retained); setRetryAllowed(false); dispatched = true;
        const direct = await request(`operations/journals/${id}`, { method: 'PATCH', body: checked, idempotencyKey: key });
        if (!active() || !isLegacyJournalReceipt(direct, checked.expected_version + 1, id)) throw new Error('Invalid receipt');
        const prior = parseLegacyJournalOutcome(await request(`operations/requests/${key}`), checked.expected_version + 1, id);
        if (!active() || prior.status !== 'succeeded' || !prior.receipt || !(['request_id', 'resource_type', 'resource_id', 'version', 'status'] as const).every(field => prior.receipt![field] === direct[field])) throw new Error('Unverified receipt');
        await verifyLegacyJournalScope(request, key, prior.receipt, 'journals.patch'); if (!active() || !gate.current) return;
        await clearPending(stableIdentity, FAMILY, id, key); if (!active()) return;
        setPending(null); setReview(null); setState('success'); setMessage('The journal draft was replaced.');
      });
    } catch {
      if (!active()) return;
      let storageFailed = false; const saved = retained ?? await readPending(stableIdentity, FAMILY, id).catch(() => { storageFailed = true; return null; });
      setPending(saved); setReview(null); setVerified(null); setAcknowledged(false);
      if (storageFailed || dispatched && !saved) { setState('error'); setMessage('Recovery data could not be verified. Check the original request before another change.'); }
      else { setState('ready'); setMessage(saved ? 'The result is unconfirmed. Check the original draft replacement before continuing.' : 'The draft, group, accounts or request lock could not be verified. No change was submitted.'); }
    } finally { busy.current = false; }
  };
  const check = async () => {
    if (!pending || !active() || busy.current) return;
    if (!canCheck) { setMessage('Your account cannot check request history. Contact an authorized administrator.'); return; }
    busy.current = true; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const saved = parseJournalEditIntent(pending.intent), result = parseLegacyJournalOutcome(await request(`operations/requests/${pending.request_key}`), saved.expected_version + 1, id);
      if (!active()) return;
      if (result.status === 'succeeded' && result.receipt) {
        await verifyLegacyJournalScope(request, pending.request_key, result.receipt, 'journals.patch'); if (!active()) return;
        await clearPending(stableIdentity, FAMILY, id, pending.request_key); if (!active()) return;
        setPending(null); setState('success'); setMessage('The original draft replacement was recorded.'); return;
      }
      if (result.status === 'not_found') { setRetryAllowed(allowMutations && canWrite); setMessage(allowMutations && canWrite ? 'No completed request was found. You may review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.'); }
      else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh the record.' : 'The request is still pending. Check again before continuing.');
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const submitReview = (event: FormEvent) => { event.preventDefault(); void reviewRequest(); };
  return <>
    <PageHeader title="Replace journal draft" subtitle="Review current and replacement entries before saving." actions={<Button type="button" onClick={() => navigate(isId(id) ? `/admin/ledgers/${id}` : '/admin/ledgers')}>Back to ledger</Button>} />
    {!allowed ? <ErrorState title="Editing unavailable" message={financialModel === 'canonical_evidence_ledger' ? 'Double-entry journal editing is unavailable for the canonical evidence ledger.' : 'Your account cannot edit journal drafts in this workspace.'} /> :
      state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Draft request recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/ledgers/${id}`)}>View journal</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Journal {id} · Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewRequest(parseJournalEditIntent(pending.intent))}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && canWrite && original && <>
          <p>Group: {original.groupTitle} · Draft version {original.version}. Replacements must use active RWF accounts in the same group.{original.allocationId ? ` Linked confirmed allocation: ${original.allocationId}. The total must remain ${formatMoney(original.total)}.` : ''}</p>
          <div className="core-edit-form"><label>Search accounts<input className="admin-input" value={accountSearch} maxLength={200} onChange={event => setAccountSearch(event.target.value)} /></label><Button type="button" disabled={state !== 'ready'} onClick={() => void searchAccounts()}>Search accounts</Button></div>
          <form className="core-edit-form" onSubmit={submitReview}><label>Journal description<textarea className="admin-input" value={description} minLength={3} maxLength={1000} required onChange={event => setDescription(event.target.value)} /></label>
            {lines.map((line, index) => <fieldset key={index}><legend>Entry {index + 1}</legend><label>Account {index + 1}<select className="admin-input" value={line.account} required onChange={event => changeLine(index, 'account', event.target.value)}><option value="">Select account</option>{choices.map(account => <option key={account.id} value={account.id}>{account.label}</option>)}</select></label>
              <label>Debit RWF {index + 1}<input className="admin-input" inputMode="numeric" value={line.debit} onChange={event => changeLine(index, 'debit', event.target.value)} /></label><label>Credit RWF {index + 1}<input className="admin-input" inputMode="numeric" value={line.credit} onChange={event => changeLine(index, 'credit', event.target.value)} /></label><label>Entry description {index + 1}<input className="admin-input" maxLength={500} value={line.description} onChange={event => changeLine(index, 'description', event.target.value)} /></label>
              {lines.length > 2 && <Button type="button" onClick={() => setLines(previous => previous.filter((_, i) => i !== index))}>Remove entry {index + 1}</Button>}</fieldset>)}
            {lines.length < 100 && <Button type="button" onClick={() => setLines(previous => [...previous, emptyJournalLine()])}>Add entry</Button>}<label>Reason for replacement<textarea className="admin-input" value={reason} minLength={8} maxLength={1000} required onChange={event => setReason(event.target.value)} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review replacement</Button></form>
        </>}
        {review && verified && allowMutations && canWrite && <section><h2>Review draft replacement</h2><p>Group: {verified.draft.groupTitle} · {verified.draft.groupId} · Current version {verified.draft.version}</p><p>Current description: {verified.draft.description}. Replacement description: {review.description}.</p>
          <div className="admin-table-wrap" role="region" aria-label="Current journal entries"><table className="admin-table"><caption>Current entries</caption><thead><tr><th scope="col">Account</th><th scope="col">Debit</th><th scope="col">Credit</th><th scope="col">Description</th></tr></thead><tbody>{verified.draft.lines.map(line => { const account = verified.draft.accounts.find(item => item.id === line.accountId)!; return <tr key={line.id}><td>{account.code} · {account.name} · {account.status}</td><td>{formatMoney(line.debit)}</td><td>{formatMoney(line.credit)}</td><td>{line.description || '—'}</td></tr>; })}</tbody></table></div>
          <div className="admin-table-wrap" role="region" aria-label="Replacement journal entries"><table className="admin-table"><caption>Replacement entries</caption><thead><tr><th scope="col">Account</th><th scope="col">Debit</th><th scope="col">Credit</th><th scope="col">Description</th></tr></thead><tbody>{review.entries.map((line, index) => { const account = verified.accounts.find(item => item.id === line.account_id)!; return <tr key={index}><td>{account.code} · {account.name} · {account.id}</td><td>{formatMoney(line.debit_rwf)}</td><td>{formatMoney(line.credit_rwf)}</td><td>{line.description || '—'}</td></tr>; })}</tbody></table></div>
          <p>Debit total: {formatMoney(review.entries.reduce((total, line) => total + line.debit_rwf, 0))} · Credit total: {formatMoney(review.entries.reduce((total, line) => total + line.credit_rwf, 0))}.</p>
          {verified.draft.allocationId && <p>Confirmed transaction {verified.draft.transactionId} · Allocation {verified.draft.allocationId} · Member {verified.draft.memberId ?? 'Not recorded'}.</p>}
          <p>Reason: {review.reason}. This replaces a draft; it does not post the journal or establish provider settlement.</p><label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed the original and replacement entries and the reason.</label>
          <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); setVerified(null); setAcknowledged(false); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !acknowledged} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No change was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm replacement'}</Button>
        </section>}
      </div></Card>}
  </>;
}
