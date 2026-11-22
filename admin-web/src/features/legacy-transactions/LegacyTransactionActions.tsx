import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import type {AdminRequest} from '../../api/client';
import {Button, Card, Field, LoadingState} from '../../ui';
import type {PendingAttempt, PendingIdentity} from '../core/pendingAttempt';
import {usePendingIdentity} from '../core/usePendingIdentity';
import {checkLegacyTransaction, checkPreviousTransaction, loadLegacyTransaction, readPreviousTransaction, restoreLegacyTransaction, retryLegacyTransaction, submitLegacyTransaction, validateReview, verifyLegacyReentry,
  type LegacyIntent, type LegacyPending, type LegacyTransactionContext, type LegacyTransactionMode, type LegacyTransactionSnapshot} from './actions';
import '../core/core.css';

export interface LegacyTransactionActionsProps {
  id: string; mode: LegacyTransactionMode; request: AdminRequest; identity: PendingIdentity; permissions: readonly string[];
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; authorityKey: string;
  /** Must fence the current authenticated epoch, actor and session. */
  isCurrent: () => boolean;
  allowMutations?: boolean; onUpdated: () => void;
}

/** Legacy evidence actions remain disabled until the backend and rollout are qualified. */
export function LegacyTransactionActions(props: LegacyTransactionActionsProps) {
  const key = JSON.stringify([props.authorityKey, props.id, props.mode, props.financialModel, props.allowMutations ?? false, props.identity.id, props.identity.sessionId, props.identity.email, props.identity.role, props.identity.expiresAt, [...props.identity.permissions].sort(), [...props.permissions].sort()]);
  return <LegacyTransactionActionsPanel key={key} {...props} />;
}
function LegacyTransactionActionsPanel({id, mode, request, identity, permissions, financialModel, authorityKey, isCurrent, allowMutations = false, onUpdated}: LegacyTransactionActionsProps) {
  const grants = JSON.stringify([...new Set(permissions)].sort());
  const stableIdentity = usePendingIdentity(identity);
  const stablePermissions = useMemo<readonly string[]>(() => JSON.parse(grants) as string[], [grants]);
  const scope = JSON.stringify([authorityKey, id, mode, financialModel, stableIdentity, stablePermissions]), current = useRef(scope), live = useRef(isCurrent), gate = useRef(allowMutations), busyRef = useRef(false);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {live.current = isCurrent;}, [isCurrent]);
  useLayoutEffect(() => {gate.current = allowMutations; return () => {gate.current = false;};}, [allowMutations]);
  const context = useMemo<LegacyTransactionContext>(() => ({id, mode, request, identity: stableIdentity, permissions: stablePermissions, financialModel, enabled: allowMutations,
    isCurrent: () => current.current === scope && live.current() && Date.parse(stableIdentity.expiresAt) > Date.now(), isEnabled: () => gate.current}), [id, mode, request, stableIdentity, stablePermissions, financialModel, allowMutations, scope]);
  const allowed = financialModel === 'transaction_journals' && stableIdentity.role !== 'staff' && ['payments.read', 'payments.manage', 'overview.read'].every(value => stableIdentity.permissions.includes(value) && stablePermissions.includes(value));
  const [pending, setPending] = useState<LegacyPending | null>(null), [other, setOther] = useState<LegacyPending | null>(null), [previous, setPrevious] = useState<PendingAttempt | null>(null), [previousOther, setPreviousOther] = useState<PendingAttempt | null>(null), [loadedScope, setLoadedScope] = useState('');
  const [source, setSource] = useState<LegacyTransactionSnapshot | null>(null), [review, setReview] = useState<LegacyIntent | null>(null), [revision, setRevision] = useState('');
  const [kind, setKind] = useState('operator_observation'), [reference, setReference] = useState(''), [digest, setDigest] = useState(''), [evidenceId, setEvidenceId] = useState(''), [outcome, setOutcome] = useState('confirmation_recorded'), [reason, setReason] = useState('');
  const [confirmed, setConfirmed] = useState(false), [retryAvailable, setRetryAvailable] = useState(false), [message, setMessage] = useState(''), [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!allowed) return; let active = true;
    (async () => {const saved = await restoreLegacyTransaction(context); const another = await restoreLegacyTransaction(context, mode === 'add' ? 'review' : 'add'); const prior = await readPreviousTransaction(context); const priorOther = await readPreviousTransaction(context, mode === 'add' ? 'review' : 'add'); return [saved, another, prior, priorOther] as const;})().then(async ([saved, another, prior, priorOther]) => {
      const snapshot = allowMutations && saved.kind === 'ready' && another.kind === 'ready' && !prior && !priorOther ? await loadLegacyTransaction(context) : null;
      if (active && context.isCurrent()) {setPending(saved); setOther(another); setPrevious(prior); setPreviousOther(priorOther); setSource(snapshot); setLoadedScope(scope);
        setMessage(saved.kind !== 'ready' || prior ? 'Check the original request before continuing.' : another.kind !== 'ready' || priorOther ? 'Another request for this transaction needs recovery.' : !allowMutations ? 'This transaction action is not enabled for this workspace.' : '');}
    }).catch(() => {if (active && context.isCurrent()) {setLoadedScope(scope); setMessage('The transaction or recovery data could not be verified.');}});
    return () => {active = false;};
  }, [allowed, allowMutations, context, mode, scope]);
  if (!allowed) return null;
  if (loadedScope !== scope) return <LoadingState label="Checking transaction recovery" />;
  const ready = pending?.kind === 'ready' && other?.kind === 'ready' && !previous && !previousOther ? pending : null, original = pending && pending.kind !== 'ready' ? pending : null;
  const makeReview = async (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || !source || !ready && !(retryAvailable && original?.kind === 'owned' && original.attempt && !previous && !previousOther) || busyRef.current || !context.isCurrent()) return;
    busyRef.current = true; setBusy(true);
    try {
      const raw = mode === 'add' ? {expected_version: source.version, evidence: {kind, reference: reference.trim(), sha256: digest.trim()}, reason: reason.trim()} : {expected_version: source.version, evidence_id: evidenceId, outcome, reason: reason.trim()};
      const body = validateReview(context, source, raw); if (original?.kind === 'owned' && original.attempt) await verifyLegacyReentry(context, original.attempt, body);
      if (context.isCurrent() && gate.current) {setReview(body); setRevision(ready?.revision ?? ''); setConfirmed(false); setMessage('');}
    } catch {if (context.isCurrent()) setMessage('Check the evidence, review outcome, transaction version and reason. A retry must exactly match the original request.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const refreshAfterSuccess = async () => {
    try {
      const next = await restoreLegacyTransaction(context), another = await restoreLegacyTransaction(context, mode === 'add' ? 'review' : 'add');
      const prior = await readPreviousTransaction(context), priorOther = await readPreviousTransaction(context, mode === 'add' ? 'review' : 'add');
      const snapshot = gate.current && next.kind === 'ready' && another.kind === 'ready' && !prior && !priorOther ? await loadLegacyTransaction(context) : null;
      if (context.isCurrent()) {setPending(next); setOther(another); setPrevious(prior); setPreviousOther(priorOther); setSource(snapshot);}
    } catch { /* Keep further changes unavailable until the panel reloads. */ }
  };
  const recover = async () => {
    if (!original || original.kind !== 'owned' || busyRef.current || !context.isCurrent()) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = await checkLegacyTransaction(context, original); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setSource(null); setMessage(`Original request recorded. Reference ${result.receipt.request_id}.`); onUpdated(); await refreshAfterSuccess();}
      else if (result.status === 'not_found') {
        if (result.retryAvailable && gate.current && original.attempt && !previous && !previousOther) {
          const snapshot = await loadLegacyTransaction(context), saved = original.attempt.intent;
          if (snapshot.version !== saved.expected_version) throw new Error('Transaction changed');
          if (context.isCurrent() && gate.current) {
            if (mode === 'add') {setKind(String(saved.evidence_kind)); setDigest(String(saved.evidence_sha256)); setReference('');}
            else {setEvidenceId(String(saved.evidence_id)); setOutcome(String(saved.outcome));}
            setReason(''); setSource(snapshot); setReview(null); setConfirmed(false); setRetryAvailable(true); setMessage('No receipt was found. Re-enter the original evidence and reason to review the same request.');
          }
        } else setMessage('No receipt was found. Keep the original reference and check again.');
      } else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh before continuing.' : 'The original request is pending. Keep its reference and check again.');
    } catch {if (context.isCurrent()) setMessage('The original request or its current transaction could not be verified. Keep the reference.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const checkPrevious = async () => {
    if (!previous || busyRef.current || !context.isCurrent()) return; busyRef.current = true; setBusy(true); setMessage('');
    try {const result = await checkPreviousTransaction(context, previous); if (!context.isCurrent()) return;
      setMessage(result.status === 'succeeded' ? `The earlier request was recorded. Reference ${result.receipt.request_id}. Resolve it in its original workflow.` : result.status === 'not_found' ? 'No receipt was found. Keep the earlier reference; this panel cannot retry it.' : 'The earlier request is unresolved. Keep the reference and check again.');
    } catch {if (context.isCurrent()) setMessage('The earlier request could not be verified. Keep its reference and check again.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const submit = async () => {
    if (!allowMutations || !review || !source || !confirmed || busyRef.current || !context.isCurrent() || original?.kind === 'foreign' || original?.kind === 'owned' && !retryAvailable) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {
      const result = original?.kind === 'owned' ? await retryLegacyTransaction(context, original, source, review) : await submitLegacyTransaction(context, review, source, revision);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setSource(null); setMessage(`Request recorded. Reference ${result.receipt.request_id}.`); onUpdated(); await refreshAfterSuccess();}
      else if (result.status === 'existing') {setPending(result.pending); setMessage('Check the original request before continuing.');}
      else {setReference(''); setReason(''); setPending({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unconfirmed. Keep request reference ${result.requestKey} and check the original request.`); try {setPending(await restoreLegacyTransaction(context));} catch { /* Keep the reference visible. */ }}
    } catch {if (context.isCurrent()) {setMessage('The transaction or request could not be verified. Check recovery and review the current transaction.'); try {setPending(await restoreLegacyTransaction(context));} catch {setPending(null);}}}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false); setRetryAvailable(false);}}
  };
  const selected = review && 'evidence_id' in review ? source?.evidence.find(row => row.id === review.evidence_id) : null;
  return <Card className="core-detail"><h2>{mode === 'add' ? 'Add transaction evidence' : 'Independent evidence review'}</h2>
    <p>Recorded evidence and review do not establish provider settlement.</p>{message && <p role="status">{message}</p>}
    {original?.kind === 'foreign' && <p>Another account or session has an unresolved request. The original account must check it.</p>}
    {original?.kind === 'owned' && <section><h3>Original request</h3><p>Reference: <code>{original.requestKey}</code></p>{!original.attempt && <p>The original intent is unavailable; keep this reference.</p>}<Button disabled={busy} onClick={() => void recover()}>Check original request</Button></section>}
    {previous && <section><h3>Earlier request</h3><p>Reference: <code>{previous.request_key}</code></p><Button disabled={busy} onClick={() => void checkPrevious()}>Check earlier request</Button><p>Resolve this request in its original workflow before another change.</p></section>}
    {allowMutations && (ready || retryAvailable && original?.kind === 'owned' && original.attempt && !previous && !previousOther) && source && !review && <form className="core-edit-form" onSubmit={event => void makeReview(event)}>
      <p>Transaction {source.id} · version {source.version} · {source.status} · RWF {new Intl.NumberFormat('en-RW').format(source.amount)}</p>
      {mode === 'add' ? <><Field label="Evidence type" htmlFor="legacy-evidence-kind"><select id="legacy-evidence-kind" className="admin-input" value={kind} onChange={event => setKind(event.target.value)}><option value="operator_observation">Operator observation</option><option value="payer_receipt">Payer receipt</option><option value="receiver_statement">Receiver statement</option><option value="provider_statement">Provider statement</option></select></Field>
        <Field label="Evidence reference" htmlFor="legacy-evidence-reference"><input id="legacy-evidence-reference" className="admin-input" minLength={8} maxLength={500} required value={reference} onChange={event => setReference(event.target.value)} /></Field>
        <Field label="Evidence SHA-256" htmlFor="legacy-evidence-digest" hint="Enter the lowercase digest of the recorded artifact."><input id="legacy-evidence-digest" className="admin-input" pattern="[a-f0-9]{64}" required value={digest} onChange={event => setDigest(event.target.value)} /></Field></> : <>
        {source.posted && <p>Evidence review is unavailable while a journal for this transaction is posted.</p>}
        {!source.posted && !source.evidence.some(row => row.recorded_by_admin_id !== stableIdentity.id) && <p>No independently recorded evidence is available for review.</p>}
        <Field label="Independent evidence" htmlFor="legacy-evidence-select"><select id="legacy-evidence-select" className="admin-input" required value={evidenceId} onChange={event => setEvidenceId(event.target.value)}><option value="">Select evidence</option>{source.evidence.filter(row => row.recorded_by_admin_id !== stableIdentity.id).map(row => <option key={row.id} value={row.id}>{row.kind.replaceAll('_', ' ')} · {row.reference}</option>)}</select></Field>
        <Field label="Review outcome" htmlFor="legacy-evidence-outcome"><select id="legacy-evidence-outcome" className="admin-input" value={outcome} onChange={event => setOutcome(event.target.value)}><option value="confirmation_recorded">Confirmation recorded</option><option value="rejection_recorded">Rejection recorded</option><option value="evidence_conflict">Evidence conflict</option></select></Field></>}
      <Field label="Reason" htmlFor={`legacy-evidence-reason-${mode}`}><textarea id={`legacy-evidence-reason-${mode}`} className="admin-input" minLength={8} maxLength={1000} required value={reason} onChange={event => setReason(event.target.value)} /></Field>
      <Button type="submit" variant="primary" disabled={busy || mode === 'review' && source.posted}>Review request</Button>
    </form>}
    {review && source && allowMutations && <section><h3>{original ? 'Review identical request' : 'Review transaction request'}</h3>
      <dl><div><dt>Transaction</dt><dd>{source.id}</dd></div><div><dt>Version</dt><dd>{source.version}</dd></div><div><dt>Group</dt><dd>{source.groupId}</dd></div><div><dt>Receiver</dt><dd>{source.payeeId} · {source.network} · {source.receiver}</dd></div><div><dt>Recorded reference</dt><dd>{source.reference}</dd></div><div><dt>Amount</dt><dd>RWF {new Intl.NumberFormat('en-RW').format(source.amount)}</dd></div><div><dt>Outcome</dt><dd>{'outcome' in review ? review.outcome : 'Add evidence'}</dd></div><div><dt>Evidence</dt><dd>{'evidence' in review ? `${review.evidence.kind} · ${review.evidence.reference} · ${review.evidence.sha256}` : `${selected?.kind} · ${selected?.reference} · ${selected?.sha256} · recorded by ${selected?.recorded_by_admin_id}`}</dd></div><div><dt>Reason</dt><dd>{review.reason}</dd></div></dl>
      {original && <p>Retrying the same key may record the request if the original did not complete.</p>}<label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} disabled={busy} /> I reviewed the transaction, evidence and reason.</label>
      <Button disabled={busy} onClick={() => {setReview(null); setConfirmed(false); setRetryAvailable(false);}}>Cancel</Button><Button variant="primary" disabled={busy || !confirmed} onClick={() => void submit()}>{original ? 'Confirm same request' : 'Confirm request'}</Button>
    </section>}
  </Card>;
}
