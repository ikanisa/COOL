import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Link } from 'react-router';
import { useSession } from '../../session/SessionProvider';
import { Button, Card, Dialog, ErrorState, Field, LoadingState, PageHeader } from '../../ui';
import type { PendingIdentity } from '../core/pendingAttempt';
import { lookupGatewayEnrollment, parseGatewayPublicIdentity, restoreGatewayEnrollment, retryGatewayEnrollment, submitGatewayEnrollment, verifyEnrollmentIntent, type EnrollmentPending, type EnrollmentReceipt, type GatewayEnrollmentContext, type GatewayEnrollmentIntent } from './gatewayEnrollment';
import './operations.css';

/** The route can recover known requests; new enrollment remains disabled until qualified. */
export function GatewayEnrollmentPage({allowActions = false}: {allowActions?: boolean}) {
  const session = useSession(), user = session.user;
  const id = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role, expiresAt = user?.expiresAt, model = user?.financialModel;
  const permissionKey = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => id && sessionId && email && role && expiresAt ? {id, sessionId, email, role, expiresAt, permissions: JSON.parse(permissionKey) as string[]} : null, [id, sessionId, email, role, expiresAt, permissionKey]);
  const scope = `${session.epoch}:${id ?? ''}:gateway-enrollment`;
  const current = useRef(scope);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  const context = useMemo<GatewayEnrollmentContext | null>(() => identity && model ? {request: session.request, identity, financialModel: model, enabled: allowActions,
    isCurrent: () => current.current === scope && Date.parse(identity.expiresAt) > Date.now()} : null, [identity, model, allowActions, scope, session.request]);
  const allowed = !!identity && identity.role !== 'staff' && model === 'transaction_journals' && ['gateway.read', 'gateway.manage', 'overview.read'].every((permission) => identity.permissions.includes(permission));
  const [attempt, setAttempt] = useState<EnrollmentPending | null>(null), [loadedScope, setLoadedScope] = useState('');
  const [label, setLabel] = useState(''), [appId, setAppId] = useState(''), [rawIdentity, setRawIdentity] = useState(''), [reason, setReason] = useState('');
  const [message, setMessage] = useState(''), [saved, setSaved] = useState<EnrollmentReceipt | null>(null);
  const [review, setReview] = useState<'new' | 'retry' | null>(null), [reviewIntent, setReviewIntent] = useState<GatewayEnrollmentIntent | null>(null), [revision, setRevision] = useState(''), [confirmed, setConfirmed] = useState(false), [retryAvailable, setRetryAvailable] = useState(false);
  const [busy, setBusy] = useState(false), busyRef = useRef(false);
  useEffect(() => {
    if (!context || !allowed) return;
    let live = true;
    restoreGatewayEnrollment(context).then((state) => {if (live && context.isCurrent()) {setAttempt(state); setLoadedScope(scope); if (state.kind !== 'ready') setMessage('Check the original enrollment request before continuing.');}},
      () => {if (live && context.isCurrent()) {setLoadedScope(scope); setMessage('Recovery data could not be verified. Check the original request before continuing.');}});
    return () => {live = false;};
  }, [allowed, context, scope]);
  const header = <><PageHeader eyebrow="Collect Admin / Operations" title="Enroll gateway device" subtitle="Use the public identity exported by the handset. Keep its private key on the device." /><p><Link className="operations-link" to="/admin/gateway">← Back to devices</Link></p></>;
  if (!identity || !model || !allowed) return <>{header}<ErrorState title="Access unavailable" message="Your current account cannot enroll or recover a gateway device." /></>;
  if (loadedScope !== scope) return <>{header}<LoadingState label="Checking enrollment recovery" /></>;
  const state = loadedScope === scope ? attempt : null;
  const pending = state && state.kind !== 'ready' ? state : null;
  const ready = state?.kind === 'ready' ? state : null;
  const beginReview = async (event: FormEvent) => {
    event.preventDefault();
    if (!context || !allowActions || !ready || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {
      const publicIdentity = await parseGatewayPublicIdentity(rawIdentity);
      const intent = await verifyEnrollmentIntent({label: label.trim(), app_id: appId.trim(), ...publicIdentity, reason: reason.trim()});
      if (context.isCurrent()) {setReviewIntent(intent); setRevision(ready.revision); setConfirmed(false); setReview('new');}
    } catch {if (context.isCurrent()) setMessage('Check the complete public identity, matching fingerprint, device label, Android app ID and reason.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const submit = async () => {
    if (!context || !allowActions || !review || !reviewIntent || !confirmed || busyRef.current || review === 'new' && !revision || review === 'retry' && (!retryAvailable || pending?.kind !== 'owned' || !pending.attempt)) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = review === 'new' ? await submitGatewayEnrollment(context, reviewIntent, revision) : await retryGatewayEnrollment(context, pending!);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setAttempt(null); setSaved(result.receipt); setMessage(`Device enrollment recorded. Request ${result.receipt.requestId}.`);}
      else if (result.status === 'existing') {setAttempt(result.pending); setMessage('Check the original enrollment request before continuing.');}
      else {setAttempt({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The outcome is unknown. Keep request reference ${result.requestKey} and check the original request.`); try {setAttempt(await restoreGatewayEnrollment(context));} catch { /* Keep the original reference visible. */ }}
    } catch {if (context.isCurrent()) {setAttempt(null); setMessage('The request could not be started safely. Check the original request and review again.'); try {setAttempt(await restoreGatewayEnrollment(context));} catch { /* Keep actions disabled. */ }}}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false);}}
  };
  const checkRequest = async () => {
    if (!context || !pending || pending.kind !== 'owned' || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = await lookupGatewayEnrollment(context, pending);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setAttempt(null); setSaved(result.receipt); setMessage(`Device enrollment recorded. Request ${result.receipt.requestId}.`);}
      else if (result.status === 'not_found') {setRetryAvailable(result.retryAvailable); setMessage(result.retryAvailable && allowActions ? 'No receipt was found. You may review the identical request before retrying its original key.' : result.retryAvailable ? 'No receipt was found. Keep the original reference and check again before continuing.' : 'No receipt was found. The original intent is unavailable, so keep this reference and check again.');}
      else setMessage('The original enrollment request remains unresolved. Keep its reference and check again.');
    } catch {if (context.isCurrent()) setMessage('The original enrollment request could not be verified. Keep its reference and check again.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const beginRetry = async () => {
    if (!context || !allowActions || !retryAvailable || pending?.kind !== 'owned' || !pending.attempt || busyRef.current) return;
    busyRef.current = true; setBusy(true);
    try {const intent = await verifyEnrollmentIntent(pending.attempt.intent); if (context.isCurrent()) {setReviewIntent(intent); setConfirmed(false); setReview('retry');}}
    catch {if (context.isCurrent()) setMessage('The original enrollment intent could not be verified.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  return <>{header}<Card className="operations-detail"><h2>Gateway identity</h2><p>Enrollment records a pending device. It does not activate the device or grant SMS sending authority.</p>
    {message && <p role="status">{message}</p>}
    {saved && <p><Link className="operations-link" to={`/admin/gateway/${saved.deviceId}`}>Open enrolled device</Link></p>}
    {pending?.kind === 'owned' && <section><h3>Original request</h3><p>Reference: <code>{pending.requestKey}</code></p><Button onClick={() => void checkRequest()} disabled={busy}>Check original request</Button>{allowActions && retryAvailable && pending.attempt && <Button onClick={() => void beginRetry()} disabled={busy}>Review identical retry</Button>}</section>}
    {pending?.kind === 'foreign' && <p>Another account or session has an unresolved enrollment. The original account must check it.</p>}
    {!allowActions && !pending && !saved && <p>Device enrollment is unavailable in this workspace.</p>}
    {allowActions && ready && !saved && <form className="operations-action-form" onSubmit={(event) => void beginReview(event)}>
      <Field label="Device label" htmlFor="gateway-label"><input id="gateway-label" className="admin-input" value={label} onChange={(event) => setLabel(event.target.value)} minLength={2} maxLength={120} required disabled={busy} /></Field>
      <Field label="Android app ID" htmlFor="gateway-app"><input id="gateway-app" className="admin-input" value={appId} onChange={(event) => setAppId(event.target.value)} maxLength={160} required disabled={busy} /></Field>
      <Field label="Handset public identity JSON" htmlFor="gateway-identity" hint="Paste the public identity exported by the handset."><textarea id="gateway-identity" className="admin-input" value={rawIdentity} onChange={(event) => setRawIdentity(event.target.value)} maxLength={4096} rows={5} required disabled={busy} /></Field>
      <Field label="Reason for device change" htmlFor="gateway-reason"><textarea id="gateway-reason" className="admin-input" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy} /></Field>
      <Button type="submit" variant="primary" disabled={busy}>Review device enrollment</Button>
    </form>}
    <Dialog open={review !== null} title={review === 'retry' ? 'Review identical enrollment retry' : 'Review device enrollment'} onClose={() => {if (!busy) setReview(null);}} footer={<><Button onClick={() => setReview(null)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>{review === 'retry' ? 'Confirm identical retry' : 'Confirm enrollment'}</Button></>}>
      {reviewIntent && <><p>Compare these details with the organization-owned handset. The private key stays on the handset.</p><dl className="operations-facts"><div><dt>Device label</dt><dd>{reviewIntent.label}</dd></div><div><dt>Android app ID</dt><dd>{reviewIntent.app_id}</dd></div><div><dt>Installation ID</dt><dd>{reviewIntent.installation_id}</dd></div><div><dt>Public key SHA-256</dt><dd>{reviewIntent.key_sha256}</dd></div><div><dt>Signing certificate SHA-256</dt><dd>{reviewIntent.signing_certificate_sha256}</dd></div><div><dt>Reason</dt><dd>{reviewIntent.reason}</dd></div></dl><label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /> I compared the installation and fingerprints with the handset.</label></>}
    </Dialog>
  </Card></>;
}
