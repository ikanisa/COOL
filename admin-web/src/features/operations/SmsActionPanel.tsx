import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { useSession } from '../../session/SessionProvider';
import { Button, Card, Dialog, Field, LoadingState } from '../../ui';
import type { PendingIdentity } from '../core/pendingAttempt';
import type { SmsReceipt } from './contracts';
import { lookupSmsExtraction, restoreSmsExtraction, revealSmsSource, submitSmsExtraction, type RevealedSms, type SmsActionContext, type SmsPending } from './smsActions';

/** Actions stay disabled unless the selected backend and recovery path are qualified. */
export function SmsActionPanel({source, enabled = false, extractionAvailable, onUpdated}: {source: SmsReceipt; enabled?: boolean; extractionAvailable: boolean; onUpdated: () => void}) {
  const session = useSession();
  const user = session.user;
  const userId = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role, expiresAt = user?.expiresAt;
  const permissionKey = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => userId && sessionId && email && role && expiresAt ? {
    id: userId, sessionId, email, role, permissions: JSON.parse(permissionKey) as string[], expiresAt,
  } : null, [userId, sessionId, email, role, expiresAt, permissionKey]);
  const scope = `${session.epoch}:${identity?.id ?? ''}:${source.source_kind}:${source.id}`;
  const current = useRef(scope);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  const context = useMemo<SmsActionContext | null>(() => identity ? {
    request: session.request, identity, source, enabled, isCurrent: () => current.current === scope && Date.parse(identity.expiresAt) > Date.now(),
  } : null, [identity, source, enabled, scope, session.request]);
  const canExtract = !!identity && identity.role !== 'staff' && identity.permissions.includes('sms.extract');
  const canReveal = !!identity && identity.role !== 'staff' && identity.permissions.includes('sms.reveal');
  const [attempt, setAttempt] = useState<SmsPending | null>(null);
  const [loadedScope, setLoadedScope] = useState('');
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  const [message, setMessage] = useState('');
  const [reason, setReason] = useState('');
  const [revealReason, setRevealReason] = useState('');
  const [reviewing, setReviewing] = useState(false);
  const [reviewRevision, setReviewRevision] = useState('');
  const [revealing, setRevealing] = useState(false);
  const [confirmed, setConfirmed] = useState(false);
  const [content, setContent] = useState<RevealedSms | null>(null);

  useEffect(() => {
    if (!context || !canExtract) return;
    let live = true;
    restoreSmsExtraction(context).then((restored) => {
      if (live && context.isCurrent()) {setAttempt(restored); setLoadedScope(scope); if (restored.kind !== 'ready') setMessage('Check the original request before another extraction.');}
    }, () => {if (live && context.isCurrent()) {setLoadedScope(scope); setMessage('Recovery data could not be verified. Check the original request before continuing.');}});
    return () => {live = false;};
  }, [canExtract, context, scope]);

  if (!identity || (!canExtract && !canReveal)) return null;
  if (canExtract && loadedScope !== scope) return <LoadingState label="Checking request recovery" />;
  const recovery = loadedScope === scope ? attempt : null;
  const currentAttempt = recovery && recovery.kind !== 'ready' ? recovery : null;
  const revision = recovery?.kind === 'ready' ? recovery.revision : null;
  if (!enabled && !currentAttempt && !message) return null;
  const review = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!enabled || !extractionAvailable || busyRef.current || !revision || reason.trim().length < 8 || reason.length > 1000) return;
    setReviewRevision(revision); setConfirmed(false); setReviewing(true);
  };
  const submit = async () => {
    if (!context || !enabled || !extractionAvailable || !confirmed || busyRef.current || !reviewRevision || currentAttempt) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {
      const result = await submitSmsExtraction(context, reason, reviewRevision);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setAttempt(null); setMessage('Extraction recorded. Payment and settlement are not asserted.'); onUpdated(); try {setAttempt(await restoreSmsExtraction(context));} catch { /* Keep further actions disabled until recovery is available. */ }}
      else if (result.status === 'existing') {setAttempt(result.pending); setMessage('Check the original request before continuing.');}
      else {
        setAttempt({kind: 'owned', requestKey: result.requestKey, attempt: null});
        setMessage(`The outcome is unknown. Keep request reference ${result.requestKey} and check the original request before continuing.`);
        try {setAttempt(await restoreSmsExtraction(context));} catch { /* The visible original reference must remain available. */ }
      }
    } catch {if (context.isCurrent()) {setAttempt(null); setMessage('The workspace changed or recovery is unavailable. Check the current request and review again.'); try {setAttempt(await restoreSmsExtraction(context));} catch { /* Keep further actions disabled. */ }}}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReviewing(false); setConfirmed(false);}}
  };
  const check = async () => {
    if (!context || !currentAttempt || currentAttempt.kind !== 'owned' || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {
      const result = await lookupSmsExtraction(context, currentAttempt);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setAttempt(null); setMessage('Extraction recorded. Payment and settlement are not asserted.'); onUpdated(); try {setAttempt(await restoreSmsExtraction(context));} catch { /* Keep further actions disabled. */ }}
      else if (result.status === 'failed') {setAttempt(null); setMessage('The server recorded a failed request. Refresh the source before another extraction.'); onUpdated(); try {setAttempt(await restoreSmsExtraction(context));} catch { /* Keep further actions disabled. */ }}
      else setMessage(result.status === 'not_found' ? 'No receipt was found. Keep the original reference and check again before continuing.' : 'The original request is pending. Check again before continuing.');
    } catch {if (context.isCurrent()) setMessage('The original request could not be verified. Keep its reference and check again.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const reveal = async () => {
    if (!context || !enabled || !confirmed || busyRef.current || currentAttempt) return;
    busyRef.current = true; setBusy(true); setMessage(''); setContent(null);
    try {
      const value = await revealSmsSource(context, revealReason);
      if (context.isCurrent()) {setContent(value); setMessage('Source access recorded. The message remains evidence, not provider confirmation.');}
    } catch {if (context.isCurrent()) setMessage('Source access could not be confirmed. Check before requesting it again.');}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setRevealing(false); setConfirmed(false);}}
  };

  return <Card className="operations-detail"><h2>Source review</h2>
    {message && <p role="status">{message}</p>}
    {currentAttempt?.kind === 'owned' && <section><h3>Original request</h3><p>Reference: <code>{currentAttempt.requestKey}</code></p><p>Check this request before submitting another extraction.</p><Button onClick={() => void check()} disabled={busy}>Check request</Button></section>}
    {currentAttempt?.kind === 'foreign' && <p>Another account has an unresolved request for this receipt. The original account must check it before another extraction.</p>}
    {enabled && canExtract && extractionAvailable && revision && <form onSubmit={review} className="operations-action-form"><Field label="Reason for extraction" htmlFor="sms-extract-reason"><textarea id="sms-extract-reason" className="admin-input" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy} /></Field><Button type="submit" variant="primary" disabled={busy}>Review extraction</Button></form>}
    {enabled && canReveal && !currentAttempt && <form onSubmit={(event) => {event.preventDefault(); if (revealReason.trim().length >= 8) {setConfirmed(false); setRevealing(true);}}} className="operations-action-form"><Field label="Reason to view the source message" htmlFor="sms-reveal-reason"><textarea id="sms-reveal-reason" className="admin-input" value={revealReason} onChange={(event) => setRevealReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy} /></Field><Button type="submit" disabled={busy}>Review source access</Button></form>}
    {content && <section><h3>Source message</h3><p>Sender: {content.sender}</p><pre className="operations-source-content">{content.body}</pre><Button onClick={() => setContent(null)}>Hide message</Button></section>}
    <Dialog open={reviewing} title="Confirm extraction" onClose={() => {if (!busy) setReviewing(false);}} footer={<><Button onClick={() => setReviewing(false)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>Confirm extraction</Button></>}><p>Source: {source.source_kind} / {source.id}</p><p>Source SHA-256: <code>{source.source_sha256}</code></p><p>Reason: {reason.trim()}</p><label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /> I reviewed the source digest and reason.</label></Dialog>
    <Dialog open={revealing} title="Confirm source access" onClose={() => {if (!busy) setRevealing(false);}} footer={<><Button onClick={() => setRevealing(false)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void reveal()} disabled={!confirmed || busy}>View source</Button></>}><p>Source access is recorded. The message is evidence and does not confirm settlement.</p><p>Reason: {revealReason.trim()}</p><label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /> I confirm this source review.</label></Dialog>
  </Card>;
}
