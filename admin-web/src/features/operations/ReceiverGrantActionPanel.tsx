import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { useSession } from '../../session/SessionProvider';
import { Button, Card, Dialog, Field, LoadingState } from '../../ui';
import type { PendingIdentity } from '../core/pendingAttempt';
import type { ReceiverGrant } from './contracts';
import { lookupGrantRevocation, restoreGrantRevocation, retryGrantRevocation, submitGrantRevocation, type GrantPending, type ReceiverGrantActionContext } from './receiverGrantActions';

/** Revocation remains disabled unless its backend and cross-version recovery are qualified. */
export function ReceiverGrantActionPanel({grant, canManage, enabled = false, onUpdated}: {grant: ReceiverGrant; canManage: boolean; enabled?: boolean; onUpdated: () => void}) {
  const session = useSession(), user = session.user;
  const id = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role, expiresAt = user?.expiresAt, model = user?.financialModel;
  const permissionKey = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => id && sessionId && email && role && expiresAt ? {id, sessionId, email, role, expiresAt, permissions: JSON.parse(permissionKey) as string[]} : null, [id, sessionId, email, role, expiresAt, permissionKey]);
  const scope = `${session.epoch}:${id ?? ''}:${grant.id}`;
  const current = useRef(scope);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  const context = useMemo<ReceiverGrantActionContext | null>(() => identity && model ? {request: session.request, identity, grant, canManage, financialModel: model, enabled,
    isCurrent: () => current.current === scope && Date.parse(identity.expiresAt) > Date.now()} : null, [identity, model, grant, canManage, enabled, scope, session.request]);
  const allowed = !!identity && canManage && model === 'transaction_journals' && identity?.role !== 'staff' && identity?.permissions.includes('gateway.read') && identity?.permissions.includes('gateway.manage');
  const [attempt, setAttempt] = useState<GrantPending | null>(null), [loadedScope, setLoadedScope] = useState('');
  const [reason, setReason] = useState(''), [message, setMessage] = useState('');
  const [review, setReview] = useState<'new' | 'retry' | null>(null), [revision, setRevision] = useState(''), [confirmed, setConfirmed] = useState(false), [retryAvailable, setRetryAvailable] = useState(false);
  const [busy, setBusy] = useState(false), busyRef = useRef(false);
  useEffect(() => {
    if (!context || !allowed) return;
    let live = true;
    restoreGrantRevocation(context).then((restored) => {
      if (live && context.isCurrent()) {setAttempt(restored); setLoadedScope(scope); if (restored.kind !== 'ready') setMessage('Check the original capture request before continuing.');}
    }, () => {if (live && context.isCurrent()) {setLoadedScope(scope); setMessage('Recovery data could not be verified. Check the original request before continuing.');}});
    return () => {live = false;};
  }, [allowed, context, scope]);
  if (!identity || !model || !allowed) return null;
  if (loadedScope !== scope) return <LoadingState label="Checking capture request recovery" />;
  const state = loadedScope === scope ? attempt : null;
  const pending = state && state.kind !== 'ready' ? state : null;
  const ready = state?.kind === 'ready' ? state : null;
  if (!enabled && !pending && !message) return null;
  const beginReview = (event: FormEvent) => {
    event.preventDefault();
    if (!enabled || busyRef.current || !ready || grant.status !== 'active' || [...reason.trim()].length < 8 || reason.trim().length > 1000) return;
    setRevision(ready.revision); setConfirmed(false); setReview('new');
  };
  const submit = async () => {
    if (!context || !enabled || !confirmed || busyRef.current || !review) return;
    if (review === 'new' && (!ready || !revision) || review === 'retry' && (!pending || pending.kind !== 'owned' || !pending.attempt || !retryAvailable)) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = review === 'new' ? await submitGrantRevocation(context, reason, revision) : await retryGrantRevocation(context, pending!);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {
        setAttempt(null); setMessage(`Capture change saved. Request ${result.receipt.requestId}.`); onUpdated();
      } else if (result.status === 'existing') {setAttempt(result.pending); setMessage('Check the original capture request before continuing.');}
      else {
        setAttempt({kind: 'owned', requestKey: result.requestKey, attempt: null});
        setMessage(`The outcome is unknown. Keep request reference ${result.requestKey} and check the original receipt.`);
        try {setAttempt(await restoreGrantRevocation(context));} catch { /* Keep the original reference visible. */ }
      }
    } catch {if (context.isCurrent()) {setMessage('The request could not be started safely. Check the original receipt and current grant before reviewing again.');
      try {setAttempt(await restoreGrantRevocation(context));} catch {setAttempt(null);}}}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false);}}
  };
  const check = async () => {
    if (!context || !pending || pending.kind !== 'owned' || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = await lookupGrantRevocation(context, pending);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {
        setAttempt(null); setMessage(`Capture change saved. Request ${result.receipt.requestId}.`); onUpdated();
      } else {setRetryAvailable(result.retryAvailable); setMessage(result.retryAvailable && enabled ? 'No receipt was found. You may review the identical request before retrying its original key.' : result.retryAvailable ? 'No receipt was found. Keep the original reference and check again before continuing.' : 'No receipt was found. The original intent is unavailable, so keep this reference and check again.');}
    } catch {if (context.isCurrent()) setMessage('The original receipt could not be verified. Keep its reference and check again.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const reviewReason = review === 'retry' && pending?.kind === 'owned' && typeof pending.attempt?.intent.reason === 'string' ? pending.attempt.intent.reason : reason.trim();
  return <Card className="operations-detail"><h2>Capture access</h2>
    {message && <p role="status">{message}</p>}
    {pending?.kind === 'owned' && <section><h3>Original request</h3><p>Reference: <code>{pending.requestKey}</code></p><Button onClick={() => void check()} disabled={busy}>Check original receipt</Button>{enabled && retryAvailable && pending.attempt && <Button onClick={() => {setConfirmed(false); setReview('retry');}} disabled={busy}>Review identical retry</Button>}</section>}
    {pending?.kind === 'foreign' && <p>Another account or session has an unresolved request for this grant. The original account must check it.</p>}
    {enabled && ready && grant.status === 'active' && <form className="operations-action-form" onSubmit={beginReview}><Field label="Capture access review reason" htmlFor="receiver-revoke-reason"><textarea className="admin-input" id="receiver-revoke-reason" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy} /></Field><Button type="submit" variant="primary" disabled={busy}>Review revocation</Button></form>}
    <Dialog open={review !== null} title={review === 'retry' ? 'Review identical retry' : 'Review capture revocation'} onClose={() => {if (!busy) setReview(null);}} footer={<><Button onClick={() => setReview(null)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>{review === 'retry' ? 'Confirm identical retry' : 'Confirm revocation'}</Button></>}>
      <p>The grant will stop accepting new captures. Accepted evidence remains available.</p><dl className="operations-facts"><div><dt>Device</dt><dd>{grant.device_label}</dd></div><div><dt>Payee</dt><dd>{grant.payee_label}</dd></div><div><dt>MoMo number or code</dt><dd>{grant.payee_momo_number_or_code}</dd></div><div><dt>Expected version</dt><dd>1</dd></div></dl><p>Reason: {reviewReason}</p><label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /> I reviewed the grant and reason.</label>
    </Dialog>
  </Card>;
}
