import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { useSession } from '../../session/SessionProvider';
import { Button, Card, Dialog, Field, LoadingState } from '../../ui';
import type { PendingIdentity } from '../core';
import { lookupEmailDispatch, restoreEmailDispatch, submitEmailDispatch, type EmailDispatchContext, type EmailPending, type EmailReceipt } from './emailActions';

/** Manual dispatch remains disabled until the provider and recovery path are qualified. */
export function EmailDispatchPanel({enabled = false, onUpdated}: {enabled?: boolean; onUpdated: () => void}) {
  const session = useSession(), user = session.user;
  const userId = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role, expiresAt = user?.expiresAt;
  const permissionKey = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => userId && sessionId && email && role && expiresAt ? {
    id: userId, sessionId, email, role, permissions: JSON.parse(permissionKey) as string[], expiresAt,
  } : null, [userId, sessionId, email, role, expiresAt, permissionKey]);
  const scope = `${session.epoch}:${identity?.id ?? ''}:email-dispatch`;
  const current = useRef(scope);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  const model = user?.financialModel, principalId = user?.principalId ?? null;
  const context = useMemo<EmailDispatchContext | null>(() => identity && model ? {
    request: session.request, identity, financialModel: model, principalId, enabled,
    isCurrent: () => current.current === scope && Date.parse(identity.expiresAt) > Date.now(),
  } : null, [identity, model, principalId, enabled, scope, session.request]);
  const canManage = !!identity && identity.role !== 'staff' && identity.permissions.includes('email.manage');
  const [attempt, setAttempt] = useState<EmailPending | null>(null);
  const [loadedScope, setLoadedScope] = useState('');
  const [reason, setReason] = useState('');
  const [message, setMessage] = useState('');
  const [saved, setSaved] = useState<EmailReceipt | null>(null);
  const [reviewing, setReviewing] = useState(false);
  const [reviewRevision, setReviewRevision] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);

  useEffect(() => {
    if (!context || !canManage) return;
    let live = true;
    restoreEmailDispatch(context).then((restored) => {
      if (live && context.isCurrent()) {setAttempt(restored); setLoadedScope(scope); if (restored.kind !== 'ready') setMessage('Check the original dispatch before starting another batch.');}
    }, () => {if (live && context.isCurrent()) {setLoadedScope(scope); setMessage('Recovery data could not be verified. Check the original request before continuing.');}});
    return () => {live = false;};
  }, [context, canManage, scope]);

  if (!identity || !canManage) return null;
  if (loadedScope !== scope) return <LoadingState label="Checking dispatch recovery" />;
  const recovery = loadedScope === scope ? attempt : null;
  const currentAttempt = recovery && recovery.kind !== 'ready' ? recovery : null;
  const revision = recovery?.kind === 'ready' ? recovery.revision : null;
  if (!enabled && !currentAttempt && !message && !saved) return null;
  const review = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!enabled || busyRef.current || !revision || reason.trim().length < 8 || reason.length > 1000) return;
    setReviewRevision(revision); setConfirmed(false); setReviewing(true);
  };
  const submit = async () => {
    if (!context || !enabled || !confirmed || busyRef.current || !reviewRevision || currentAttempt) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {
      const result = await submitEmailDispatch(context, reason, reviewRevision);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setAttempt(null); setSaved(result.receipt); setMessage('Dispatch recorded. Provider acceptance is not proof of delivery.'); onUpdated(); try {setAttempt(await restoreEmailDispatch(context));} catch { /* Keep further actions disabled until recovery is available. */ }}
      else if (result.status === 'existing') {setAttempt(result.pending); setMessage('Check the original dispatch before continuing.');}
      else {
        setAttempt({kind: 'owned', requestKey: result.requestKey, attempt: null});
        setMessage(`The outcome is unknown. Keep request reference ${result.requestKey} and check the original dispatch.`);
        try {setAttempt(await restoreEmailDispatch(context));} catch { /* Keep the displayed reference available. */ }
      }
    } catch {if (context.isCurrent()) {setAttempt(null); setMessage('The workspace changed or recovery is unavailable. Check the current request and review again.'); try {setAttempt(await restoreEmailDispatch(context));} catch { /* Keep further actions disabled. */ }}}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReviewing(false); setConfirmed(false);}}
  };
  const check = async () => {
    if (!context || !currentAttempt || currentAttempt.kind !== 'owned' || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {
      const result = await lookupEmailDispatch(context, currentAttempt);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setAttempt(null); setSaved(result.receipt); setMessage('Dispatch recorded. Provider acceptance is not proof of delivery.'); onUpdated(); try {setAttempt(await restoreEmailDispatch(context));} catch { /* Keep further actions disabled. */ }}
      else if (result.status === 'failed' || result.status === 'cancelled') {setAttempt(null); setMessage('The original request was closed. Refresh the email events before taking another action.'); onUpdated(); try {setAttempt(await restoreEmailDispatch(context));} catch { /* Keep further actions disabled. */ }}
      else setMessage(result.status === 'not_found' ? 'No receipt was found. Keep the original reference and check again before continuing.' : 'The original request is still pending. Check again before continuing.');
    } catch {if (context.isCurrent()) setMessage('The original dispatch could not be verified. Keep its reference and check again.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  return <Card className="operations-detail"><h2>Queued email batch</h2>
    {message && <p role="status">{message}</p>}
    {saved && <p>Provider accepted: {saved.accepted}; outcome uncertain: {saved.uncertain}; suppressed: {saved.suppressed}.</p>}
    {currentAttempt?.kind === 'owned' && <section><h3>Original request</h3><p>Reference: <code>{currentAttempt.requestKey}</code></p><p>Check this request before another batch.</p><Button onClick={() => void check()} disabled={busy}>Check dispatch</Button></section>}
    {currentAttempt?.kind === 'foreign' && <p>Another account has an unresolved batch. The original account must check it before another dispatch.</p>}
    {enabled && revision && <form className="operations-action-form" onSubmit={review}><Field label="Reason for manual dispatch" htmlFor="email-dispatch-reason"><textarea className="admin-input" id="email-dispatch-reason" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy} /></Field><Button type="submit" variant="primary" disabled={busy}>Review queued batch</Button></form>}
    <Dialog open={reviewing} title="Confirm queued email batch" onClose={() => {if (!busy) setReviewing(false);}} footer={<><Button onClick={() => setReviewing(false)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>Confirm batch</Button></>}><p>This requests processing of up to 20 queued notifications. Provider acceptance does not prove delivery. An uncertain send must not be automatically retried.</p><p>Reason: {reason.trim()}</p><label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /> I reviewed the batch and reason.</label></Dialog>
  </Card>;
}
