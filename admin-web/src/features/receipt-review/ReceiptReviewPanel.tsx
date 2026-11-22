import {useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import {useSession, type AdminUser, type SessionContextValue} from '../../session/SessionProvider';
import {Button, Card, Dialog, Field, LoadingState} from '../../ui';
import type {PendingIdentity} from '../core/pendingAttempt';
import type {MemberReceipt} from '../operations/contracts';
import {memberReceiptRevealReason, revealMemberReceipt, type RevealedMemberReceipt} from '../operations/memberReceiptReveal';
import {lookupReceiptReview, restoreReceiptReview, retryReceiptReview, reviewReason, searchReceiptTransactions, submitReceiptReview,
  type ReceiptOutcome, type ReceiptReviewContext, type ReceiptReviewPending, type ReviewTransaction} from './review';

export interface ReceiptReviewPanelProps {
  receipt: MemberReceipt;
  canManage: boolean;
  enabled?: boolean;
  allowAttachment?: boolean;
  onUpdated: () => void;
}
interface ReviewDraft {mode: 'new' | 'retry'; outcome: ReceiptOutcome; reason: string; selected: ReviewTransaction | null; sourceHash: string; revision: string;}

/** Legacy member receipts only. Both new access and mutation controls require opt-in. */
export function ReceiptReviewPanel({receipt, canManage, enabled = false, allowAttachment = false, onUpdated}: ReceiptReviewPanelProps) {
  const session = useSession(), user = session.user;
  if (session.status !== 'authenticated' || !user || user.financialModel !== 'transaction_journals' || receipt.source_kind === 'capture' ||
      !canManage || user.role === 'staff' || !['payments.read', 'payments.manage'].every(permission => user.permissions.includes(permission))) return null;
  // Changing the authority, action gate or source immediately unmounts plaintext.
  const scope = JSON.stringify([session.epoch, user.id, user.sessionId, user.email, user.role, user.expiresAt, [...user.permissions].sort(),
    receipt.id, receipt.user_id, receipt.body_sha256, receipt.status, receipt.version, enabled, allowAttachment]);
  return <ReceiptReviewSession key={scope} receipt={receipt} canManage={canManage} enabled={enabled} allowAttachment={allowAttachment} onUpdated={onUpdated} session={session} user={user} />;
}

function ReceiptReviewSession({receipt, canManage, enabled, allowAttachment, onUpdated, session, user}: Required<ReceiptReviewPanelProps> & {session: SessionContextValue; user: AdminUser}) {
  const [initial] = useState(() => ({epoch: session.epoch, user}));
  const live = useRef(session), mounted = useRef(false), busyRef = useRef(false), controller = useRef<AbortController | null>(null);
  const gate = useRef(enabled), attachmentGate = useRef(allowAttachment);
  useLayoutEffect(() => {live.current = session;}, [session]);
  useLayoutEffect(() => {gate.current = enabled; attachmentGate.current = allowAttachment;}, [enabled, allowAttachment]);
  useLayoutEffect(() => {mounted.current = true; return () => {mounted.current = false; gate.current = false; attachmentGate.current = false; controller.current?.abort();};}, []);
  const current = useCallback(() => {
    const actor = live.current.user, expected = initial.user;
    return mounted.current && live.current.status === 'authenticated' && !!actor && actor.id === expected.id && actor.sessionId === expected.sessionId &&
      actor.email === expected.email && actor.role === expected.role && actor.financialModel === expected.financialModel && actor.expiresAt === expected.expiresAt &&
      JSON.stringify([...actor.permissions].sort()) === JSON.stringify([...expected.permissions].sort()) && Date.parse(actor.expiresAt) > Date.now() &&
      live.current.isCurrentAuthority(initial.epoch, expected.id, expected.sessionId);
  }, [initial]);
  const identity = useMemo<PendingIdentity>(() => ({id: initial.user.id, sessionId: initial.user.sessionId, email: initial.user.email,
    role: initial.user.role, permissions: initial.user.permissions, expiresAt: initial.user.expiresAt}), [initial]);
  const context = useMemo<ReceiptReviewContext>(() => ({request: session.request, identity, receipt, canManage, financialModel: 'transaction_journals', enabled,
    allowAttachment, isCurrent: current, isEnabled: () => gate.current, attachmentEnabled: () => attachmentGate.current}),
  [session.request, identity, receipt, canManage, enabled, allowAttachment, current]);
  const canRecover = identity.permissions.includes('overview.read');
  const [attempt, setAttempt] = useState<ReceiptReviewPending | null>(null), [loaded, setLoaded] = useState(false), [recoveryError, setRecoveryError] = useState(false);
  const [accessReason, setAccessReason] = useState(''), [accessReview, setAccessReview] = useState<string | null>(null), [accessConfirmed, setAccessConfirmed] = useState(false);
  const [content, setContent] = useState<RevealedMemberReceipt | null>(null), [outcome, setOutcome] = useState<ReceiptOutcome>('reviewed'), [reason, setReason] = useState('');
  const [search, setSearch] = useState(''), [transactions, setTransactions] = useState<ReviewTransaction[]>([]), [selected, setSelected] = useState<ReviewTransaction | null>(null);
  const [message, setMessage] = useState(''), [retryAvailable, setRetryAvailable] = useState(false), [busy, setBusy] = useState(false);
  const [review, setReview] = useState<ReviewDraft | null>(null), [confirmed, setConfirmed] = useState(false);
  useEffect(() => {
    if (!canRecover) return;
    let active = true;
    restoreReceiptReview(context).then(state => {if (active && current()) {setAttempt(state); setLoaded(true);}},
      () => {if (active && current()) {setRecoveryError(true); setLoaded(true);}});
    return () => {active = false;};
  }, [canRecover, context, current]);
  const ready = attempt?.kind === 'ready' ? attempt : null, pending = attempt && attempt.kind !== 'ready' ? attempt : null;
  const reviewIntent = pending?.kind === 'owned' ? pending.attempt?.intent : undefined;
  const originalOutcome = reviewIntent?.outcome === 'rejected' ? 'rejected' : 'reviewed';
  const originalTransaction = typeof reviewIntent?.transaction_id === 'string' ? reviewIntent.transaction_id : null;
  if (!enabled && !pending && !recoveryError && (loaded || !canRecover)) return null;
  if (!enabled && canRecover && !loaded) return <LoadingState label="Checking receipt review recovery" />;

  const prepareAccess = (event: FormEvent) => {
    event.preventDefault(); if (!current() || !enabled || busyRef.current) return;
    try {setAccessReview(memberReceiptRevealReason(accessReason)); setAccessConfirmed(false); setMessage('');}
    catch {setMessage('Enter a reason of 8 to 1000 characters on one line.');}
  };
  const reveal = async () => {
    if (!accessReview || !accessConfirmed || !current() || !enabled || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setContent(null);
    const abort = new AbortController(); controller.current = abort;
    try {
      const result = await revealMemberReceipt({request: session.request, identity, financialModel: 'transaction_journals', receipt, canManage,
        enabled, isEnabled: () => gate.current, isCurrent: current, signal: abort.signal}, accessReview);
      if (current()) {setContent(result); setMessage('Receipt access recorded. The message is member-submitted evidence.');}
    } catch {if (current()) setMessage('Receipt access could not be confirmed. An access event may have been recorded. A new request requires confirmation and may record another event.');}
    finally {controller.current = null; busyRef.current = false; if (current()) {setBusy(false); setAccessReview(null); setAccessConfirmed(false);}}
  };
  const findTransactions = async (event: FormEvent) => {
    event.preventDefault(); if (!enabled || !allowAttachment || !current() || busyRef.current) return;
    busyRef.current = true; setBusy(true); setSelected(null); setMessage('');
    try {const rows = await searchReceiptTransactions(context, search); if (current() && gate.current && attachmentGate.current) {setTransactions(rows); if (!rows.length) setMessage('No eligible transactions matched this search.');}}
    catch {if (current()) {setTransactions([]); setMessage('Eligible transactions could not be verified.');}}
    finally {busyRef.current = false; if (current()) setBusy(false);}
  };
  const checkRequest = async () => {
    if (!pending || pending.kind !== 'owned' || busyRef.current || !current()) return;
    busyRef.current = true; setBusy(true); setRetryAvailable(false); setMessage('');
    try {
      const result = await lookupReceiptReview(context, pending); if (!current()) return;
      if (result.status === 'succeeded' && result.verifiedIntent) {setAttempt(null); setContent(null); setMessage(`Receipt review recorded. Request ${result.requestId}.`); onUpdated();}
      else if (result.status === 'succeeded') setMessage(`The server recorded a review under request ${result.requestId}, but its original intent is unavailable. Keep the reference for investigation.`);
      else if (result.status === 'not_found') {setRetryAvailable(result.retryAvailable); setMessage(result.retryAvailable ? 'No server receipt was found. The original request may be reviewed for a deliberate identical retry when actions are enabled.' : 'No server receipt was found. The original intent is unavailable, so keep the reference and check again.');}
      else setMessage('The original review remains unresolved. Keep its reference and check again.');
    } catch {if (current()) setMessage('The original review could not be verified. Keep its reference and check again.');}
    finally {busyRef.current = false; if (current()) setBusy(false);}
  };
  const prepareReview = (event: FormEvent) => {
    event.preventDefault(); if (!enabled || !content || !current() || busyRef.current || recoveryError || !loaded) return;
    try {
      const reviewedReason = reviewReason(reason);
      if (pending?.kind === 'owned' && pending.attempt && retryAvailable) {setReview({mode: 'retry', outcome: originalOutcome, reason: reviewedReason, selected, sourceHash: content.bodySha256, revision: ''}); setConfirmed(false);}
      else if (ready && receipt.status === 'needs_review') {setReview({mode: 'new', outcome, reason: reviewedReason, selected, sourceHash: content.bodySha256, revision: ready.revision}); setConfirmed(false);}
    } catch {setMessage('Enter a reason of 8 to 1000 characters on one line.');}
  };
  const submit = async () => {
    if (!review || !confirmed || !content || !enabled || !current() || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = review.mode === 'new' ? await submitReceiptReview(context, review.outcome, review.reason, review.selected, review.sourceHash, review.revision)
        : await retryReceiptReview(context, pending!, review.reason, review.selected, review.sourceHash);
      if (!current()) return;
      if (result.status === 'succeeded') {setAttempt(null); setContent(null); setMessage(`Receipt review recorded. Request ${result.requestId}.`); onUpdated();}
      else if (result.status === 'existing') {setAttempt(result.pending); setMessage('Check the original review before continuing.');}
      else {setAttempt({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The outcome is unknown. Keep request reference ${result.requestKey} and check the original request.`); try {setAttempt(await restoreReceiptReview(context));} catch { /* Keep the original reference. */ }}
    } catch {if (current()) {setMessage('The review could not be started safely. Check the original request and current receipt before continuing.'); try {setAttempt(await restoreReceiptReview(context));} catch {setRecoveryError(true);}}}
    finally {busyRef.current = false; if (current()) {setBusy(false); setReview(null); setConfirmed(false);}}
  };
  const canPrepare = enabled && content && canRecover && loaded && !recoveryError && (ready && receipt.status === 'needs_review' || pending?.kind === 'owned' && !!pending.attempt && retryAvailable);
  const chooseAttachment = allowAttachment && (pending?.kind === 'owned' ? originalTransaction !== null : outcome === 'reviewed');
  return <Card className="operations-detail"><h2>Submitted receipt</h2>
    <p>The submitted message is evidence and does not confirm provider settlement.</p>
    {message && <p role="status">{message}</p>}
    {recoveryError && <p>Review recovery could not be verified. Check the original request before continuing.</p>}
    {!canRecover && enabled && <p>Review actions are unavailable because this account cannot check original requests.</p>}
    {pending?.kind === 'owned' && <section><h3>Original review request</h3><p>Reference: <code>{pending.requestKey}</code></p><Button onClick={() => void checkRequest()} disabled={busy}>Check original review</Button></section>}
    {pending?.kind === 'foreign' && <p>Another account or session has an unresolved review. The original account must check it.</p>}
    {enabled && !content && <form className="operations-action-form" onSubmit={prepareAccess}><Field label="Reason to review the submitted receipt" htmlFor="receipt-access-reason"><input id="receipt-access-reason" className="admin-input" value={accessReason} onChange={event => setAccessReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy || accessReview !== null} /></Field><Button type="submit" disabled={busy || accessReview !== null}>Review receipt access</Button></form>}
    {enabled && accessReview && <section className="momo-assignment-review" aria-label="Confirm receipt access"><h3>Confirm receipt access</h3><p>Receipt reference: <code>{receipt.id}</code></p><p>Reason: {accessReview}</p><p>Each access is separately recorded. There is no access status lookup.</p><label><input type="checkbox" checked={accessConfirmed} onChange={event => setAccessConfirmed(event.target.checked)} disabled={busy} /> I confirm this receipt review.</label><div className="momo-assignment-actions"><Button onClick={() => {setAccessReview(null); setAccessConfirmed(false);}} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void reveal()} disabled={!accessConfirmed || busy}>View submitted receipt</Button></div></section>}
    {enabled && content && <section><h3>Sender</h3><p>{content.sender}</p><h3>Message</h3><pre className="operations-source-content">{content.body}</pre><Button onClick={() => {setContent(null); setAccessReason(''); setMessage('');}}>Hide message</Button></section>}
    {canPrepare && <section><h3>{pending ? 'Review identical retry' : 'Review receipt'}</h3>
      {pending ? <p>Original classification: {originalOutcome}. Re-enter the exact original reason{originalTransaction ? ` and select transaction ${originalTransaction} again` : ''}.</p> : <Field label="Classification" htmlFor="receipt-outcome"><select id="receipt-outcome" className="admin-input" value={outcome} onChange={event => {setOutcome(event.target.value as ReceiptOutcome); setSelected(null);}} disabled={busy}><option value="reviewed">Reviewed</option><option value="rejected">Rejected</option></select></Field>}
      {chooseAttachment && <><form className="operations-action-form" onSubmit={event => void findTransactions(event)}><Field label="Search eligible transactions" htmlFor="receipt-transaction-search"><input id="receipt-transaction-search" className="admin-input" value={search} maxLength={200} onChange={event => setSearch(event.target.value)} disabled={busy} /></Field><Button type="submit" disabled={busy}>Search transactions</Button></form>
        {transactions.map(row => <label key={row.id} className="operations-action-form"><input type="radio" name="receipt-transaction" checked={selected?.id === row.id} onChange={() => setSelected(row)} disabled={busy} /> {row.label} · version {row.version}</label>)}
        {!originalTransaction && selected && <Button onClick={() => setSelected(null)} disabled={busy}>Remove attachment</Button>}</>}
      {pending && originalTransaction && !allowAttachment && <p>Retrying this attachment is unavailable until the transaction precondition is qualified.</p>}
      <form className="operations-action-form" onSubmit={prepareReview}><Field label={pending ? 'Exact original review reason' : 'Reason for review'} htmlFor="receipt-review-reason"><input id="receipt-review-reason" className="admin-input" value={reason} onChange={event => setReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy} /></Field><Button type="submit" variant="primary" disabled={busy || !!originalTransaction && (!allowAttachment || !selected)}>Review {pending ? 'identical retry' : 'classification'}</Button></form>
    </section>}
    <Dialog open={review !== null} title={review?.mode === 'retry' ? 'Review identical receipt retry' : 'Review receipt classification'} onClose={() => {if (!busy) setReview(null);}} footer={<><Button onClick={() => setReview(null)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>Confirm {review?.mode === 'retry' ? 'identical retry' : 'review'}</Button></>}>
      <p>This records a classification of member-submitted evidence. It does not confirm provider settlement.</p><dl className="operations-facts"><div><dt>Receipt</dt><dd>{receipt.id}</dd></div><div><dt>Classification</dt><dd>{review?.outcome}</dd></div><div><dt>Transaction</dt><dd>{review?.selected ? `${review.selected.label} · version ${review.selected.version}` : 'None'}</dd></div><div><dt>Reason</dt><dd>{review?.reason}</dd></div></dl><label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} disabled={busy} /> I reviewed the receipt and classification.</label>
    </Dialog>
  </Card>;
}
