import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import {useSession} from '../../session/SessionProvider';
import {Button, Card, Dialog, Field, LoadingState} from '../../ui';
import type {PendingIdentity} from '../core/pendingAttempt';
import type {GatewayDevice} from './contracts';
import {gatewayTrustActions, type GatewayTrustContext} from './gatewayDeviceTrust';
import type {OperationPending} from './operationRequestCustody';
import {Facts} from './OperationsRecords';

const trustCopy = {
  activate: {
    title: 'Device activation', loading: 'Checking device activation recovery', reasonLabel: 'Reason for activation', reasonId: 'gateway-activate-reason',
    review: 'Review device activation', reviewRetry: 'Review identical activation retry', confirm: 'Confirm activation',
    note: 'Activation records trust for this installation. It does not grant SMS sending or confirm carrier delivery.',
    result: 'Device activation recorded.',
  },
  revoke: {
    title: 'Device trust', loading: 'Checking device request recovery', reasonLabel: 'Reason for device change', reasonId: 'gateway-revoke-reason',
    review: 'Review device revocation', reviewRetry: 'Review identical device retry', confirm: 'Confirm device revocation',
    note: 'Revocation permanently removes trusted status for this installation.',
    result: 'Device revocation recorded.',
  },
};

interface GatewayTrustProps {
  mode: keyof typeof gatewayTrustActions;
  device: GatewayDevice;
  canManage: boolean;
  enabled?: boolean;
  onUpdated: () => void;
}

export function GatewayTrustPanel({mode, device, canManage, enabled = false, onUpdated}: GatewayTrustProps) {
  const session = useSession(), user = session.user, operation = gatewayTrustActions[mode], copy = trustCopy[mode];
  const activation = mode === 'activate';
  const id = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role, expiresAt = user?.expiresAt, model = user?.financialModel;
  const permissionKey = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => id && sessionId && email && role && expiresAt ?
    {id, sessionId, email, role, expiresAt, permissions: JSON.parse(permissionKey) as string[]} : null,
  [id, sessionId, email, role, expiresAt, permissionKey]);
  const scope = activation ? `${session.epoch}:${id ?? ''}:${sessionId ?? ''}:${device.id}:device-activation` :
    `${session.epoch}:${id ?? ''}:${device.id}:device-revocation`;
  const current = useRef(scope), gate = useRef(enabled), live = useRef(session);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = enabled; return () => {gate.current = false;};}, [enabled]);
  useLayoutEffect(() => {live.current = session;}, [session]);
  const context = useMemo<GatewayTrustContext | null>(() => identity && model ? {
    request: session.request, identity, device, canManage, financialModel: model, enabled,
    isCurrent: () => current.current === scope && Date.parse(identity.expiresAt) > Date.now() &&
      (!activation || live.current.isCurrentAuthority(session.epoch, identity.id, identity.sessionId)),
    isEnabled: () => gate.current,
  } : null, [identity, model, device, canManage, enabled, scope, session.request, session.epoch, activation]);
  const allowed = !!identity && canManage && model === 'transaction_journals' && identity.role !== 'staff' &&
    ['gateway.read', 'gateway.manage', 'overview.read'].every(permission => identity.permissions.includes(permission));
  const [attempt, setAttempt] = useState<OperationPending | null>(null), [loadedScope, setLoadedScope] = useState('');
  const [reason, setReason] = useState(''), [message, setMessage] = useState(''), [review, setReview] = useState<'new' | 'retry' | null>(null);
  const [revision, setRevision] = useState(''), [confirmed, setConfirmed] = useState(false), [retryAvailable, setRetryAvailable] = useState(false);
  const [busy, setBusy] = useState(false), busyRef = useRef(false);
  useEffect(() => {
    if (!context || !allowed) return;
    let active = true;
    operation.restore(context).then(state => {
      if (!active || !context.isCurrent()) return;
      setAttempt(state); setLoadedScope(scope);
      if (state.kind !== 'ready') setMessage('Check the original device request before continuing.');
    }, () => {
      if (!active || !context.isCurrent()) return;
      setLoadedScope(scope);
      setMessage('Recovery data could not be verified. Check the original request before continuing.');
    });
    return () => {active = false;};
  }, [allowed, context, operation, scope]);
  if (!allowed) return null;
  if (loadedScope !== scope) return <LoadingState label={copy.loading} />;
  const pending = attempt && attempt.kind !== 'ready' ? attempt : null, ready = attempt?.kind === 'ready' ? attempt : null;
  if (!enabled && !pending && !message) return null;
  const canChangeDevice = device.state === 'pending' || !activation && device.state === 'active';

  const beginReview = (event: FormEvent) => {
    event.preventDefault();
    const length = reason.trim().length;
    if (!enabled || !ready || busyRef.current || !canChangeDevice || length < 8 || length > 1000) return;
    setRevision(ready.revision); setConfirmed(false); setReview('new');
  };
  const submit = async () => {
    if (!context || !enabled || !review || !confirmed || busyRef.current || review === 'new' && !revision ||
        review === 'retry' && (!retryAvailable || pending?.kind !== 'owned' || !pending.attempt)) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = review === 'new' ? await operation.submit(context, reason, revision) : await operation.retry(context, pending!);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {
        setAttempt(null); setMessage(`${copy.result} Request ${result.receipt.requestId}.`); onUpdated();
      } else if (result.status === 'existing') {
        setAttempt(result.pending); setMessage('Check the original device request before continuing.');
      } else {
        setAttempt({kind: 'owned', requestKey: result.requestKey, attempt: null});
        setMessage(`The outcome is unknown. Keep request reference ${result.requestKey} and check the original request.`);
        try {setAttempt(await operation.restore(context));} catch { /* Keep the reference visible. */ }
      }
    } catch {
      if (context.isCurrent()) {
        setMessage('The request could not be started safely. Check the original request and current device before reviewing again.');
        try {setAttempt(await operation.restore(context));} catch {setAttempt(null);}
      }
    } finally {
      busyRef.current = false;
      if (context.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false);}
    }
  };
  const checkRequest = async () => {
    if (!context || pending?.kind !== 'owned' || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = await operation.lookup(context, pending);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {
        setAttempt(null); setMessage(`${copy.result} Request ${result.receipt.requestId}.`); onUpdated();
      } else if (result.status === 'not_found') {
        setRetryAvailable(result.retryAvailable);
        setMessage(result.retryAvailable && enabled ? 'No receipt was found. You may review the identical request before retrying its original key.' :
          result.retryAvailable ? 'No receipt was found. Keep the original reference and check again before continuing.' :
            'No receipt was found. The original intent is unavailable, so keep this reference and check again.');
      } else {
        setMessage('The original device request remains unresolved. Keep its reference and check again.');
      }
    } catch {if (context.isCurrent()) setMessage('The original device request could not be verified. Keep its reference and check again.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const saved = review === 'retry' && pending?.kind === 'owned' ? pending.attempt?.intent : undefined;
  const reviewReason = typeof saved?.reason === 'string' ? saved.reason : reason.trim();
  const reviewVersion = typeof saved?.expected_version === 'number' ? saved.expected_version : device.version;
  return <Card className="operations-detail"><h2>{copy.title}</h2>
    {message && <p role="status">{message}</p>}
    {pending?.kind === 'owned' && <section><h3>Original request</h3><p>Reference: <code>{pending.requestKey}</code></p>
      <Button onClick={() => void checkRequest()} disabled={busy}>Check original request</Button>
      {enabled && retryAvailable && pending.attempt && <Button onClick={() => {setConfirmed(false); setReview('retry');}} disabled={busy}>Review identical retry</Button>}
    </section>}
    {pending?.kind === 'foreign' && <p>Another account or session has an unresolved request for this device. The original account must check it.</p>}
    {enabled && ready && canChangeDevice && <form className="operations-action-form" onSubmit={beginReview}>
      <Field label={copy.reasonLabel} htmlFor={copy.reasonId}><textarea className="admin-input" id={copy.reasonId} value={reason} onChange={event => setReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy} /></Field>
      <Button type="submit" variant="primary" disabled={busy}>{copy.review}</Button>
    </form>}
    <Dialog open={review !== null} title={review === 'retry' ? copy.reviewRetry : copy.review} onClose={() => {if (!busy) setReview(null);}} footer={<>
      <Button onClick={() => setReview(null)} disabled={busy}>Cancel</Button>
      <Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>{review === 'retry' ? 'Confirm identical retry' : copy.confirm}</Button>
    </>}>
      <p>{copy.note}</p>
      <Facts items={[
        ['Device', device.label], ...(activation ? [['Application', device.app_id] as [string, string]] : []),
        ['Installation ID', device.installation_id], ['Expected version', reviewVersion], ['Public key SHA-256', device.key_sha256],
        ['Signing certificate SHA-256', device.signing_certificate_sha256], ['Reason', reviewReason],
      ]} />
      <label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} /> I compared the installation and both fingerprints with the device.</label>
    </Dialog>
  </Card>;
}
