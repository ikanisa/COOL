import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import {useSession} from '../../session/SessionProvider';
import {Button, Card, Dialog, Field, LoadingState} from '../../ui';
import type {PendingIdentity} from '../core';
import type {GatewayDevice} from './contracts';
import {lookupGatewayActivation, restoreGatewayActivation, retryGatewayActivation, submitGatewayActivation, type GatewayActivationContext, type GatewayActivationPending} from './gatewayActivation';

/** Activation is available only when the legacy backend is explicitly qualified. */
export function GatewayActivationPanel({device, canManage, enabled = false, onUpdated}: {device: GatewayDevice; canManage: boolean; enabled?: boolean; onUpdated: () => void}) {
  const session = useSession(), user = session.user;
  const id = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role, expiresAt = user?.expiresAt, model = user?.financialModel;
  const permissions = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => id && sessionId && email && role && expiresAt ? {id, sessionId, email, role, expiresAt, permissions: JSON.parse(permissions) as string[]} : null, [id, sessionId, email, role, expiresAt, permissions]);
  const scope = `${session.epoch}:${id ?? ''}:${sessionId ?? ''}:${device.id}:device-activation`;
  const current = useRef(scope), gate = useRef(enabled), live = useRef(session);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = enabled; return () => {gate.current = false;};}, [enabled]);
  useLayoutEffect(() => {live.current = session;}, [session]);
  const context = useMemo<GatewayActivationContext | null>(() => identity && model ? {request: session.request, identity, device, canManage, financialModel: model, enabled,
    isCurrent: () => current.current === scope && Date.parse(identity.expiresAt) > Date.now() && live.current.isCurrentAuthority(session.epoch, identity.id, identity.sessionId),
    isEnabled: () => gate.current} : null, [identity, model, device, canManage, enabled, scope, session.request, session.epoch]);
  const allowed = !!identity && canManage && model === 'transaction_journals' && identity.role !== 'staff' && ['gateway.read', 'gateway.manage', 'overview.read'].every((permission) => identity.permissions.includes(permission));
  const [attempt, setAttempt] = useState<GatewayActivationPending | null>(null), [loadedScope, setLoadedScope] = useState('');
  const [reason, setReason] = useState(''), [message, setMessage] = useState(''), [review, setReview] = useState<'new' | 'retry' | null>(null), [revision, setRevision] = useState('');
  const [confirmed, setConfirmed] = useState(false), [retryAvailable, setRetryAvailable] = useState(false), [busy, setBusy] = useState(false), busyRef = useRef(false);
  useEffect(() => {
    if (!context || !allowed) return;
    let active = true;
    restoreGatewayActivation(context).then((state) => {if (active && context.isCurrent()) {setAttempt(state); setLoadedScope(scope); if (state.kind !== 'ready') setMessage('Check the original device request before continuing.');}},
      () => {if (active && context.isCurrent()) {setLoadedScope(scope); setMessage('Recovery data could not be verified. Check the original request before continuing.');}});
    return () => {active = false;};
  }, [allowed, context, scope]);
  if (!identity || !model || !allowed) return null;
  if (loadedScope !== scope) return <LoadingState label="Checking device activation recovery" />;
  const pending = attempt && attempt.kind !== 'ready' ? attempt : null, ready = attempt?.kind === 'ready' ? attempt : null;
  if (!enabled && !pending && !message) return null;
  const beginReview = (event: FormEvent) => {
    event.preventDefault(); if (!enabled || !ready || busyRef.current || device.state !== 'pending' || reason.trim().length < 8 || reason.trim().length > 1000) return;
    setRevision(ready.revision); setConfirmed(false); setReview('new');
  };
  const submit = async () => {
    if (!context || !enabled || !review || !confirmed || busyRef.current || review === 'new' && !revision || review === 'retry' && (!retryAvailable || pending?.kind !== 'owned' || !pending.attempt)) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = review === 'new' ? await submitGatewayActivation(context, reason, revision) : await retryGatewayActivation(context, pending!);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setAttempt(null); setMessage(`Device activation recorded. Request ${result.receipt.requestId}.`); onUpdated();}
      else if (result.status === 'existing') {setAttempt(result.pending); setMessage('Check the original device request before continuing.');}
      else {setAttempt({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The outcome is unknown. Keep request reference ${result.requestKey} and check the original request.`); try {setAttempt(await restoreGatewayActivation(context));} catch { /* Keep the reference visible. */ }}
    } catch {if (context.isCurrent()) {setMessage('The request could not be started safely. Check the original request and current device before reviewing again.'); try {setAttempt(await restoreGatewayActivation(context));} catch {setAttempt(null);}}}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false);}}
  };
  const checkRequest = async () => {
    if (!context || pending?.kind !== 'owned' || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = await lookupGatewayActivation(context, pending); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setAttempt(null); setMessage(`Device activation recorded. Request ${result.receipt.requestId}.`); onUpdated();}
      else if (result.status === 'not_found') {setRetryAvailable(result.retryAvailable); setMessage(result.retryAvailable && enabled ? 'No receipt was found. You may review the identical request before retrying its original key.' : result.retryAvailable ? 'No receipt was found. Keep the original reference and check again before continuing.' : 'No receipt was found. The original intent is unavailable, so keep this reference and check again.');}
      else setMessage('The original device request remains unresolved. Keep its reference and check again.');
    } catch {if (context.isCurrent()) setMessage('The original device request could not be verified. Keep its reference and check again.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const reviewReason = review === 'retry' && pending?.kind === 'owned' && typeof pending.attempt?.intent.reason === 'string' ? pending.attempt.intent.reason : reason.trim();
  const reviewVersion = review === 'retry' && pending?.kind === 'owned' && typeof pending.attempt?.intent.expected_version === 'number' ? pending.attempt.intent.expected_version : device.version;
  return <Card className="operations-detail"><h2>Device activation</h2>
    {message && <p role="status">{message}</p>}
    {pending?.kind === 'owned' && <section><h3>Original request</h3><p>Reference: <code>{pending.requestKey}</code></p><Button onClick={() => void checkRequest()} disabled={busy}>Check original request</Button>{enabled && retryAvailable && pending.attempt && <Button onClick={() => {setConfirmed(false); setReview('retry');}} disabled={busy}>Review identical retry</Button>}</section>}
    {pending?.kind === 'foreign' && <p>Another account or session has an unresolved request for this device. The original account must check it.</p>}
    {enabled && ready && device.state === 'pending' && <form className="operations-action-form" onSubmit={beginReview}><Field label="Reason for activation" htmlFor="gateway-activate-reason"><textarea className="admin-input" id="gateway-activate-reason" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy} /></Field><Button type="submit" variant="primary" disabled={busy}>Review device activation</Button></form>}
    <Dialog open={review !== null} title={review === 'retry' ? 'Review identical activation retry' : 'Review device activation'} onClose={() => {if (!busy) setReview(null);}} footer={<><Button onClick={() => setReview(null)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>{review === 'retry' ? 'Confirm identical retry' : 'Confirm activation'}</Button></>}>
      <p>Activation records trust for this installation. It does not grant SMS sending or confirm carrier delivery.</p><dl className="operations-facts"><div><dt>Device</dt><dd>{device.label}</dd></div><div><dt>Application</dt><dd>{device.app_id}</dd></div><div><dt>Installation ID</dt><dd>{device.installation_id}</dd></div><div><dt>Expected version</dt><dd>{reviewVersion}</dd></div><div><dt>Public key SHA-256</dt><dd>{device.key_sha256}</dd></div><div><dt>Signing certificate SHA-256</dt><dd>{device.signing_certificate_sha256}</dd></div><div><dt>Reason</dt><dd>{reviewReason}</dd></div></dl><label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /> I compared the installation and both fingerprints with the device.</label>
    </Dialog>
  </Card>;
}
