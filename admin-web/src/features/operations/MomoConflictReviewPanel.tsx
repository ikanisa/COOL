import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Link } from 'react-router';
import { verifySensitiveAccess } from '../../app/sensitive-access';
import { useSession } from '../../session/SessionProvider';
import { Button, Field, LoadingState } from '../../ui';
import type { PendingIdentity } from '../core/pendingAttempt';
import type { MomoDetail } from './momoContracts';
import { canReviewMomoConflict, momoConflictSources, parseMomoConflictIntent, restoreMomoConflict, retryMomoConflict, submitMomoConflict, type MomoConflictContext, type MomoConflictIntent, type MomoConflictPending, type MomoConflictReceipt } from './momoConflict';

/** Retrying is a reviewed, identical write; the MoMo API has no read-only receipt lookup. */
export function MomoConflictReviewPanel({detail, enabled = false, onUpdated}: {detail: MomoDetail; enabled?: boolean; onUpdated: () => void}) {
  const session = useSession(), user = session.user;
  const id = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role, expiresAt = user?.expiresAt, model = user?.financialModel, principalId = user?.principalId;
  const permissionKey = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => id && sessionId && email && role && expiresAt ? {id, sessionId, email, role, expiresAt, permissions: JSON.parse(permissionKey) as string[]} : null, [id, sessionId, email, role, expiresAt, permissionKey]);
  const scope = `${session.epoch}:${id ?? ''}:${principalId ?? ''}:${detail.transaction.id}:momo-conflict`;
  const current = useRef(scope), gate = useRef(enabled), liveSession = useRef(session);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = enabled; return () => {gate.current = false;};}, [enabled]);
  useLayoutEffect(() => {liveSession.current = session;}, [session]);
  const context = useMemo<MomoConflictContext | null>(() => identity && model && principalId ? {request: session.request, identity, principalId, financialModel: model, detail, enabled,
    isCurrent: () => current.current === scope && liveSession.current.isCurrentAuthority(session.epoch, identity.id, identity.sessionId) && Date.parse(identity.expiresAt) > Date.now(), isEnabled: () => gate.current,
    verifyFresh: async () => {const live = liveSession.current, actor = live.user; return !!actor && actor.id === identity.id && actor.sessionId === identity.sessionId && await verifySensitiveAccess(live, actor);},
  } : null, [identity, model, principalId, detail, enabled, scope, session.request, session.epoch]);
  const allowed = !!identity && model === 'canonical_evidence_ledger' && !!principalId && ['payments.read', 'payments.write', 'sms.extract'].every((permission) => identity.permissions.includes(permission));
  const [pendingState, setPendingState] = useState<MomoConflictPending | null>(null), [loadedScope, setLoadedScope] = useState('');
  const [evidence, setEvidence] = useState(''), [reason, setReason] = useState(''), [message, setMessage] = useState(''), [needsVerification, setNeedsVerification] = useState(false), [saved, setSaved] = useState<MomoConflictReceipt | null>(null);
  const [review, setReview] = useState<'new' | 'retry' | null>(null), [reviewIntent, setReviewIntent] = useState<MomoConflictIntent | null>(null), [revision, setRevision] = useState(''), [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false), busyRef = useRef(false);
  useEffect(() => {
    if (!context || !allowed) return;
    let live = true, timer: ReturnType<typeof setTimeout> | undefined;
    const apply = (state: MomoConflictPending) => {if (live && context.isCurrent()) {setPendingState(state); setLoadedScope(scope); if (state.kind !== 'ready') setMessage('An original conflict review is unresolved.');}};
    const failed = () => {if (live && context.isCurrent()) {setLoadedScope(scope); setMessage('Recovery data could not be verified. Check the original conflict review before continuing.');}};
    // Assignment recovery and conflict recovery can mount together. A short retry handles
    // transient contention for the shared browser lock; unresolved locks still fail closed.
    restoreMomoConflict(context).then(apply, () => {timer = setTimeout(() => {if (live) void restoreMomoConflict(context).then(apply, failed);}, 100);});
    return () => {live = false; if (timer) clearTimeout(timer);};
  }, [allowed, context, scope]);
  if (!identity || !model || !principalId || !allowed) return null;
  if (loadedScope !== scope) return <LoadingState label="Checking conflict review recovery" />;
  const pending = pendingState && pendingState.kind !== 'ready' ? pendingState : null, ready = pendingState?.kind === 'ready' ? pendingState : null;
  if (!pending && !message && !saved && (!enabled || detail.transaction.has_conflict !== 1)) return null;
  let sources: ReturnType<typeof momoConflictSources> | null = null;
  try {sources = momoConflictSources(detail);} catch { /* A truncated or inconsistent source list must not enable review. */ }
  const beginNew = (event: FormEvent) => {
    event.preventDefault();
    if (!enabled || !ready || !sources || busyRef.current || !canReviewMomoConflict(detail)) return;
    try {
      setReviewIntent(parseMomoConflictIntent({expected_version: detail.transaction.version, expected_conflicting_attempt_ids: sources.ids, decision: 'retain_original', evidence_reference: evidence.trim(), reason: reason.trim()}));
      setRevision(ready.revision); setConfirmed(false); setMessage(''); setReview('new');
    } catch {setMessage('Provide an evidence reference and reason of 8 to 500 characters each.');}
  };
  const beginRetry = () => {
    if (!enabled || pending?.kind !== 'owned' || !pending.attempt || !sources || busyRef.current) return;
    try {
      const intent = parseMomoConflictIntent(pending.attempt.intent);
      if (JSON.stringify([...intent.expected_conflicting_attempt_ids].sort()) !== JSON.stringify(sources.ids)) throw new Error('Source set changed.');
      setReviewIntent(intent); setConfirmed(false); setMessage(''); setReview('retry');
    } catch {setMessage('The original conflict set could not be verified.');}
  };
  const submit = async () => {
    if (!context || !enabled || !review || !reviewIntent || !confirmed || busyRef.current || review === 'new' && !revision || review === 'retry' && (pending?.kind !== 'owned' || !pending.attempt)) return;
    busyRef.current = true; setBusy(true); setMessage(''); setNeedsVerification(false);
    try {
      const result = review === 'new' ? await submitMomoConflict(context, reviewIntent.evidence_reference, reviewIntent.reason, revision) : await retryMomoConflict(context, pending!);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPendingState(null); setSaved(result.receipt); setMessage('Conflict review recorded. No contribution was credited and provider settlement is not asserted.');}
      else if (result.status === 'existing') {setPendingState(result.pending); setMessage('An original conflict review is unresolved.');}
      else {setPendingState({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unknown. Keep request reference ${result.requestKey}.`); try {setPendingState(await restoreMomoConflict(context));} catch { /* Keep the reference visible. */ }}
    } catch (error) {
      if (context.isCurrent()) {setNeedsVerification(error instanceof Error && error.message.includes('current verification')); setMessage('The conflict review could not be confirmed. Check the complete source set and current verification before reviewing again.'); try {setPendingState(await restoreMomoConflict(context));} catch {setPendingState(null);}}
    } finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false);}}
  };
  return <section className="momo-assignment"><h3>Conflicting evidence</h3><p>Review retains the original accepted facts and dismisses only the listed conflicting attempts. It does not change financial records or confirm provider settlement.</p>
    {message && <p role="status">{message}</p>}
    {needsVerification && <p><Link className="operations-link" to={`/admin/security/${session.verificationMode === 'email' ? 'verify-email' : 'authenticator'}?returnTo=%2Fadmin%2Fmomo-receipts`}>Verify identity</Link></p>}
    {saved && <Button onClick={onUpdated}>Refresh receipt</Button>}
    {pending?.kind === 'foreign' && <p>Another account or session has an unresolved conflict review. The original account must resolve it.</p>}
    {pending?.kind === 'owned' && <><p>Original request: <code>{pending.requestKey}</code></p><p>There is no read-only status lookup for this request. An identical retry may record the review if it was not already committed.</p>
      {pending.attempt ? <>{enabled && sources && <Button onClick={beginRetry} disabled={busy}>Review original conflict request</Button>}</> : <p>The original intent or source identity is unavailable. Keep the reference and contact an authorized operator before another review.</p>}</>}
    {enabled && ready && detail.transaction.has_conflict === 1 && !canReviewMomoConflict(detail) && <p>The complete unlinked conflict and its source evidence are unavailable for review. Refresh the receipt or investigate the original sources.</p>}
    {enabled && ready && sources && canReviewMomoConflict(detail) && !saved && <><p>Accepted source: <code>{sources.accepted.raw_sms_id}</code> · attempt <code>{sources.accepted.attempt_id}</code> · parser {sources.accepted.parser_version}.</p>
      <p>Review each conflicting source reference and the supporting evidence before retaining the original facts.</p>
      <div className="admin-table-wrap" role="region" aria-label="Conflicting source attempts" tabIndex={0}><table className="admin-table"><thead><tr><th scope="col">Attempt</th><th scope="col">Source reference</th><th scope="col">Outcome</th><th scope="col">Parser</th></tr></thead><tbody>{sources.conflicts.map((source) => <tr key={source.attempt_id}><td>{source.attempt_id}</td><td>{source.raw_sms_id}</td><td>{source.outcome}</td><td>{source.parser_version}</td></tr>)}</tbody></table></div>
      <form className="operations-action-form" onSubmit={beginNew}><Field label="Supporting evidence reference" htmlFor="momo-conflict-evidence"><textarea id="momo-conflict-evidence" className="admin-input" value={evidence} onChange={(event) => setEvidence(event.target.value)} minLength={8} maxLength={500} required disabled={busy} /></Field><Field label="Reason for conflict decision" htmlFor="momo-conflict-reason"><textarea id="momo-conflict-reason" className="admin-input" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={500} required disabled={busy} /></Field><Button type="submit" variant="primary" disabled={busy}>Review conflict decision</Button></form>
    </>}
    {review && reviewIntent && sources && <section className="momo-assignment-review" aria-label="Reviewed conflict decision"><h4>{review === 'retry' ? 'Review original conflict request' : 'Review conflict decision'}</h4><p>{review === 'retry' ? 'Retrying may record this review if it did not already commit. The original key and intent will be reused.' : 'The accepted facts remain unchanged. No financial operation will be performed.'}</p>
      <dl className="operations-facts"><div><dt>Receipt</dt><dd>{detail.transaction.provider_transaction_id}</dd></div><div><dt>Amount</dt><dd>RWF {new Intl.NumberFormat('en-RW').format(detail.transaction.amount_minor)}</dd></div><div><dt>Receiving account</dt><dd>{detail.transaction.recipient_name} · {detail.transaction.public_code}</dd></div><div><dt>Accepted source</dt><dd>{sources.accepted.raw_sms_id}</dd></div><div><dt>Original receipt version</dt><dd>{reviewIntent.expected_version}</dd></div><div><dt>Evidence reference</dt><dd>{reviewIntent.evidence_reference}</dd></div><div><dt>Reason</dt><dd>{reviewIntent.reason}</dd></div></dl>
      <p>Conflicting attempts: {reviewIntent.expected_conflicting_attempt_ids.map((attempt, index) => <span key={attempt}>{index > 0 ? ', ' : ''}<code>{attempt}</code></span>)}</p>
      <label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} disabled={busy} /> I reviewed the accepted source, every conflicting attempt and the supporting evidence.</label><div className="momo-assignment-actions"><Button onClick={() => setReview(null)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>{review === 'retry' ? 'Retry original conflict request' : 'Confirm conflict decision'}</Button></div>
    </section>}
  </section>;
}
