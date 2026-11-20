import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Link } from 'react-router';
import { verifySensitiveAccess } from '../../app/sensitive-access';
import { useSession } from '../../session/SessionProvider';
import { Button, Field, LoadingState } from '../../ui';
import type { PendingIdentity } from '../core';
import { isObject, parseCoreRow } from '../core/contracts';
import type { MomoDetail } from './momoContracts';
import { canStartMomoAssignment, hasAcceptedMomoSource, loadMomoCandidates, parseMomoAssignmentIntent, restoreMomoAssignment, retryMomoAssignment, submitMomoAssignment, type MomoAssignmentContext, type MomoAssignmentIntent, type MomoAssignmentPending, type MomoAssignmentReceipt, type MomoCandidate, type MomoCandidatesPage } from './momoAssignment';

/** A retry is an explicit, idempotent write because the MoMo API has no read-only lookup. */
export function MomoAssignmentPanel({detail, enabled = false, onUpdated}: {detail: MomoDetail; enabled?: boolean; onUpdated: () => void}) {
  const session = useSession(), user = session.user;
  const id = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role, expiresAt = user?.expiresAt, model = user?.financialModel, principalId = user?.principalId;
  const permissionKey = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => id && sessionId && email && role && expiresAt ? {id, sessionId, email, role, expiresAt, permissions: JSON.parse(permissionKey) as string[]} : null, [id, sessionId, email, role, expiresAt, permissionKey]);
  const scope = JSON.stringify([session.epoch, id ?? '', sessionId ?? '', principalId ?? '', detail.transaction.id, 'momo-assignment']);
  const current = useRef(scope), gate = useRef(enabled), liveSession = useRef(session);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = enabled; return () => {gate.current = false;};}, [enabled]);
  useLayoutEffect(() => {liveSession.current = session;}, [session]);
  const context = useMemo<MomoAssignmentContext | null>(() => identity && model && principalId ? {request: session.request, identity, principalId, financialModel: model, detail, enabled,
    isCurrent: () => current.current === scope && liveSession.current.isCurrentAuthority(session.epoch, identity.id, identity.sessionId) && Date.parse(identity.expiresAt) > Date.now(), isEnabled: () => gate.current,
    verifyFresh: async () => {const live = liveSession.current, actor = live.user; return !!actor && actor.id === identity.id && actor.sessionId === identity.sessionId && await verifySensitiveAccess(live, actor);},
  } : null, [identity, model, principalId, detail, enabled, scope, session.request, session.epoch]);
  const allowed = !!identity && model === 'canonical_evidence_ledger' && !!principalId && ['payments.read', 'payments.write'].every((permission) => identity.permissions.includes(permission));
  const canChoose = !!identity && ['users.read', 'collections.read'].every((permission) => identity.permissions.includes(permission));
  const [pendingState, setPendingState] = useState<MomoAssignmentPending | null>(null), [loadedScope, setLoadedScope] = useState('');
  const [search, setSearch] = useState(''), [appliedSearch, setAppliedSearch] = useState(''), [page, setPage] = useState<MomoCandidatesPage | null>(null), [selected, setSelected] = useState<MomoCandidate | null>(null);
  const [reason, setReason] = useState(''), [message, setMessage] = useState(''), [needsVerification, setNeedsVerification] = useState(false);
  const [savedState, setSavedState] = useState<{scope: string; receipt: MomoAssignmentReceipt} | null>(null);
  const [referenceState, setReferenceState] = useState<{scope: string; paymentId: string; reference: string | null} | null>(null);
  const saved = savedState?.scope === scope ? savedState.receipt : null;
  const [review, setReview] = useState<'new' | 'retry' | null>(null), [reviewIntent, setReviewIntent] = useState<MomoAssignmentIntent | null>(null), [revision, setRevision] = useState(''), [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false), busyRef = useRef(false);
  useEffect(() => {
    if (!context || !allowed) return;
    let live = true, timer: ReturnType<typeof setTimeout> | undefined;
    const apply = (savedState: MomoAssignmentPending) => {if (live && context.isCurrent()) {setPendingState(savedState); setLoadedScope(scope); if (savedState.kind !== 'ready') setMessage('An original assignment request is unresolved.');}};
    const failed = () => {if (live && context.isCurrent()) {setLoadedScope(scope); setMessage('Recovery data could not be verified. Check the original assignment before continuing.');}};
    // Another recovery check may briefly own the shared browser lock.
    restoreMomoAssignment(context).then(apply, () => {timer = setTimeout(() => {if (live) void restoreMomoAssignment(context).then(apply, failed);}, 100);});
    return () => {live = false; if (timer) clearTimeout(timer);};
  }, [allowed, context, scope]);
  useEffect(() => {
    if (!saved || !context || !allowed || !identity) return;
    const controller = new AbortController(); let live = true;
    void context.request(`operations/transactions/${saved.paymentId}`, {signal: controller.signal}).then(data => {
      if (data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'transactions' ||
          data.current_actor_id !== identity.id || !isObject(data.resource)) throw new Error('Invalid payment detail');
      const row = parseCoreRow('transactions', 'canonical_evidence_ledger', data.resource);
      if (row.id !== saved.paymentId) throw new Error('Invalid payment identity');
      if (live && context.isCurrent()) setReferenceState({scope, paymentId: saved.paymentId, reference: typeof row.payment_reference === 'string' ? row.payment_reference : null});
    }).catch(() => {if (live && context.isCurrent()) setReferenceState({scope, paymentId: saved.paymentId, reference: null});});
    return () => {live = false; controller.abort();};
  }, [saved, context, allowed, identity, scope]);
  if (!identity || !model || !principalId || !allowed) return null;
  if (loadedScope !== scope) return <LoadingState label="Checking assignment recovery" />;
  const pending = pendingState && pendingState.kind !== 'ready' ? pendingState : null, ready = pendingState?.kind === 'ready' ? pendingState : null;
  if (!enabled && !pending && !message && !saved) return null;
  const findCandidates = async (query: string, offset: number) => {
    if (!context || !enabled || !ready || busyRef.current || !canStartMomoAssignment(detail)) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {const value = await loadMomoCandidates(context, query, offset); if (context.isCurrent()) {setPage(value); setAppliedSearch(query.trim()); setSelected(null);}}
    catch {if (context.isCurrent()) setMessage('Eligible destinations could not be verified. Refresh the receipt before continuing.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const searchForm = (event: FormEvent) => {event.preventDefault(); void findCandidates(search, 0);};
  const beginNew = (event: FormEvent) => {
    event.preventDefault();
    if (!enabled || !ready || !selected || busyRef.current || !canStartMomoAssignment(detail)) return;
    try {
      const intent = parseMomoAssignmentIntent({group_id: selected.group_id, member_id: selected.member_id, expected_version: detail.transaction.version, reason: reason.trim()});
      setReviewIntent(intent); setRevision(ready.revision); setConfirmed(false); setMessage(''); setReview('new');
    } catch {setMessage('Select an eligible destination and provide a reason of 8 to 500 characters.');}
  };
  const beginRetry = () => {
    if (!enabled || pending?.kind !== 'owned' || !pending.attempt || busyRef.current || !hasAcceptedMomoSource(detail)) return;
    try {setReviewIntent(parseMomoAssignmentIntent(pending.attempt.intent)); setConfirmed(false); setMessage(''); setReview('retry');}
    catch {setMessage('The original assignment intent could not be verified.');}
  };
  const submit = async () => {
    if (!context || !enabled || !review || !reviewIntent || !confirmed || busyRef.current || review === 'new' && (!selected || !revision) || review === 'retry' && (pending?.kind !== 'owned' || !pending.attempt)) return;
    busyRef.current = true; setBusy(true); setMessage(''); setNeedsVerification(false);
    try {
      const result = review === 'new' ? await submitMomoAssignment(context, selected!, reviewIntent.reason, revision) : await retryMomoAssignment(context, pending!);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPendingState(null); setSavedState({scope, receipt: result.receipt}); setMessage(result.receipt.requiresIndependentReview ? 'Assignment recorded for independent financial review. Provider settlement is not asserted.' : 'Existing payment linked. Check its recorded financial status; provider settlement is not asserted.');}
      else if (result.status === 'existing') {setPendingState(result.pending); setMessage('An original assignment request is unresolved.');}
      else {setPendingState({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unknown. Keep request reference ${result.requestKey}.`); try {setPendingState(await restoreMomoAssignment(context));} catch { /* Keep the reference visible. */ }}
    } catch (error) {if (context.isCurrent()) {setNeedsVerification(error instanceof Error && error.message.includes('current verification')); setMessage('The assignment could not be confirmed. Check the receipt, destination and current verification before reviewing again.'); try {setPendingState(await restoreMomoAssignment(context));} catch {setPendingState(null);}}}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false);}}
  };
  const accepted = detail.sources.find((source) => source.relation === 'accepted' && source.outcome === 'accepted');
  return <section className="momo-assignment"><h3>Beneficiary assignment</h3><p>The receiving account remains fixed. Assignment prepares review or links an existing payment; it does not establish provider settlement.</p>
    {message && <p role="status">{message}</p>}
    {needsVerification && <p><Link className="operations-link" to={`/admin/security/${session.verificationMode === 'email' ? 'verify-email' : 'authenticator'}?returnTo=%2Fadmin%2Fmomo-receipts`}>Verify identity</Link></p>}
    {saved && <><p>Payment reference: <code>{referenceState?.scope === scope && referenceState.paymentId === saved.paymentId ? referenceState.reference ?? 'Not available' : 'Not available'}</code></p><p>Payment ID: <code>{saved.paymentId}</code>{identity.permissions.includes('reconciliations.read') && <> · <Link className="operations-link" to={`/admin/reconciliations/${saved.paymentId}`}>Open financial review</Link></>}</p><Button onClick={onUpdated}>Refresh receipt</Button></>}
    {pending?.kind === 'foreign' && <p>Another account or session has an unresolved assignment. The original account must resolve it.</p>}
    {pending?.kind === 'owned' && <><p>Original request: <code>{pending.requestKey}</code></p><p>There is no read-only status lookup for this request. An identical retry may record the assignment if it was not already committed.</p>
      {pending.attempt ? <><p>Original destination: group <code>{String(pending.attempt.intent.group_id)}</code>, member <code>{String(pending.attempt.intent.member_id)}</code>, receipt version {String(pending.attempt.intent.expected_version)}.</p>{enabled && hasAcceptedMomoSource(detail) && <Button onClick={beginRetry} disabled={busy}>Review original assignment</Button>}</> : <p>The original intent is unavailable. Keep the reference and contact an authorized operator before another assignment.</p>}</>}
    {enabled && ready && !canChoose && <p>Eligible destinations are unavailable to your current account.</p>}
    {enabled && ready && canChoose && canStartMomoAssignment(detail) && !saved && <><p>Accepted source: <code>{accepted?.raw_sms_id}</code> · parser {accepted?.parser_version}. Compare the payer, receiving account and destination before continuing.</p>
      <form className="operations-search" onSubmit={searchForm}><label className="admin-sr-only" htmlFor="momo-candidate-search">Find eligible group and beneficiary</label><input id="momo-candidate-search" className="admin-input" value={search} onChange={(event) => setSearch(event.target.value)} maxLength={200} placeholder="Find eligible group or beneficiary" disabled={busy} /><Button type="submit" disabled={busy}>Search destinations</Button></form>
      {page && (page.rows.length ? <><div className="admin-table-wrap" role="region" aria-label="Eligible destinations" tabIndex={0}><table className="admin-table"><thead><tr><th scope="col">Group</th><th scope="col">Member</th><th scope="col">Member ID</th><th scope="col">Select</th></tr></thead><tbody>{page.rows.map((row) => <tr key={`${row.group_id}:${row.member_id}`}><td>{row.group_name}</td><td>{row.member_name}</td><td>{row.member_public_id}</td><td><Button onClick={() => setSelected(row)} disabled={busy} aria-pressed={selected?.group_id === row.group_id && selected.member_id === row.member_id}>{selected?.group_id === row.group_id && selected.member_id === row.member_id ? 'Selected' : 'Select'}</Button></td></tr>)}</tbody></table></div><div className="operations-pagination"><span>{page.total} eligible destinations</span><div><Button onClick={() => void findCandidates(appliedSearch, Math.max(0, page.offset - 25))} disabled={busy || page.offset === 0}>Previous</Button><Button onClick={() => void findCandidates(appliedSearch, page.offset + 25)} disabled={busy || page.offset + page.rows.length >= page.total}>Next</Button></div></div></> : <p>No eligible destinations found.</p>)}
      <form className="operations-action-form" onSubmit={beginNew}><Field label="Reason for assignment" htmlFor="momo-assign-reason"><textarea id="momo-assign-reason" className="admin-input" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={500} required disabled={busy} /></Field><Button type="submit" variant="primary" disabled={!selected || busy}>Review assignment</Button></form>
    </>}
    {review && reviewIntent && <section className="momo-assignment-review" aria-label="Reviewed assignment"><h4>{review === 'retry' ? 'Review original assignment' : 'Review beneficiary assignment'}</h4><p>{review === 'retry' ? 'Retrying may make this assignment if it did not already commit. The original key and intent will be reused.' : 'This request prepares financial review or links an existing payment. It does not assert provider settlement.'}</p>
      <dl className="operations-facts"><div><dt>Receipt</dt><dd>{detail.transaction.provider_transaction_id}</dd></div><div><dt>Amount</dt><dd>RWF {new Intl.NumberFormat('en-RW').format(detail.transaction.amount_minor)}</dd></div><div><dt>Receiving account</dt><dd>{detail.transaction.recipient_name} · {detail.transaction.public_code}</dd></div><div><dt>Accepted source</dt><dd>{accepted?.raw_sms_id}</dd></div><div><dt>Group</dt><dd>{review === 'new' ? selected?.group_name : reviewIntent.group_id}</dd></div><div><dt>Member</dt><dd>{review === 'new' ? `${selected?.member_name} · ${selected?.member_public_id}` : reviewIntent.member_id}</dd></div><div><dt>Receipt version</dt><dd>{reviewIntent.expected_version}</dd></div><div><dt>Reason</dt><dd>{reviewIntent.reason}</dd></div></dl>
      <label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} disabled={busy} /> I reviewed the accepted source, destination and original request.</label><div className="momo-assignment-actions"><Button onClick={() => setReview(null)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>{review === 'retry' ? 'Retry original assignment' : 'Confirm assignment'}</Button></div>
    </section>}
  </section>;
}
