import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { isId } from '../core/contracts';
import type { PendingIdentity } from '../core/pendingAttempt';
import {usePendingIdentity} from '../core/usePendingIdentity';
import type { FeatureAccess } from '../core/types';
import { currentLegacyPayee, lookupLegacyPayee, parseLegacyPayeeIntent, restoreLegacyPayee, retryLegacyPayee, submitLegacyPayee, type LegacyPayeeContext, type LegacyPayeeIntent, type LegacyPayeePending, type LegacyPayeeSource } from './actions';
import '../core/core.css';

export interface LegacyPayeeEditProps extends FeatureAccess {id: string; identity: PendingIdentity; allowMutations?: boolean; verifyFresh: () => Promise<boolean>;}

/** Legacy receiver edits require the guarded backend and remain opt-in. */
export function LegacyPayeeEditPage({id, request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh}: LegacyPayeeEditProps) {
  const identityKey = JSON.stringify([...new Set(identity.permissions)].sort()), permissionKey = JSON.stringify([...new Set(permissions)].sort());
  const user = usePendingIdentity(identity);
  const stablePermissions = useMemo<readonly string[]>(() => JSON.parse(permissionKey) as string[], [permissionKey]);
  const allowed = financialModel === 'transaction_journals' && isId(id) && isId(actorId) && user.id === actorId && user.role === role && role !== 'staff' &&
    ['receivers.read', 'receivers.manage', 'collections.read', 'overview.read'].every(value => stablePermissions.includes(value) && user.permissions.includes(value));
  const scope = JSON.stringify([authorityKey, financialModel, id, actorId, role, user.id, user.sessionId, user.email, user.expiresAt, identityKey, permissionKey]), current = useRef(scope), gate = useRef(allowMutations), verify = useRef(verifyFresh), busy = useRef(false);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = allowMutations; return () => {gate.current = false;};}, [allowMutations]);
  useLayoutEffect(() => {verify.current = verifyFresh;}, [verifyFresh]);
  const context = useMemo<LegacyPayeeContext>(() => ({id, request, identity: user, actorId, permissions: stablePermissions, financialModel, enabled: allowMutations,
    isCurrent: () => current.current === scope && Date.parse(user.expiresAt) > Date.now(), isEnabled: () => gate.current, verifyFresh: () => verify.current()}), [id, request, user, actorId, stablePermissions, financialModel, allowMutations, scope]);
  const [pending, setPending] = useState<LegacyPayeePending | null>(null), [loadedScope, setLoadedScope] = useState(''), [source, setSource] = useState<LegacyPayeeSource | null>(null);
  const [label, setLabel] = useState(''), [status, setStatus] = useState<'active' | 'inactive'>('active'), [reason, setReason] = useState('');
  const [review, setReview] = useState<LegacyPayeeIntent | null>(null), [reviewSource, setReviewSource] = useState<LegacyPayeeSource | null>(null), [revision, setRevision] = useState(''), [confirmed, setConfirmed] = useState(false), [retryAllowed, setRetryAllowed] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading'), [message, setMessage] = useState('');
  useEffect(() => {
    if (!allowed) return; let live = true;
    restoreLegacyPayee(context).then(async saved => {
      const value = saved.kind === 'ready' && allowMutations ? await currentLegacyPayee(context) : null;
      if (live && context.isCurrent()) {setPending(saved); setSource(value); if (value) {setLabel(value.payee.label); setStatus(value.payee.status);} setLoadedScope(scope); setState('ready'); setMessage(saved.kind !== 'ready' ? 'A previous receiver request needs recovery. Check its original reference before continuing.' : !allowMutations ? 'Receiver changes are not enabled for this workspace.' : '');}
    }).catch(() => {if (live && context.isCurrent()) {setLoadedScope(scope); setState('error'); setMessage('The receiver or recovery data could not be verified.');}});
    return () => {live = false;};
  }, [allowed, allowMutations, context, scope]);
  const unresolved = pending && pending.kind !== 'ready' ? pending : null, ready = pending?.kind === 'ready' ? pending : null;
  const prepare = (event: FormEvent) => {
    event.preventDefault(); if (!ready || !allowMutations || !source || busy.current || !context.isCurrent()) return;
    try {
      if (status === 'inactive' && source.payee.status === 'active' && source.group.status === 'active' || status === 'active' && source.activePayeeId !== null && source.activePayeeId !== id) throw new Error('Receiver state conflict');
      const intent = parseLegacyPayeeIntent({label: label.trim(), status, expected_version: source.payee.version, expected_group_version: source.group.version, reason: reason.trim()});
      setReview(intent); setReviewSource(source); setRevision(ready.revision); setConfirmed(false); setMessage('');
    } catch {setMessage('Check the receiver name, status and reason. An active group must retain its active receiver.');}
  };
  const send = async () => {
    if (!allowMutations || !review || !reviewSource || !confirmed || busy.current || !context.isCurrent() || unresolved?.kind === 'foreign' || unresolved?.kind === 'owned' && !retryAllowed) return;
    busy.current = true; setState('sending'); setMessage('');
    try {
      const result = unresolved?.kind === 'owned' ? await retryLegacyPayee(context, unresolved) : await submitLegacyPayee(context, review, reviewSource, revision);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setState('success'); setMessage('The receiver change was recorded.');}
      else if (result.status === 'existing') {setPending(result.pending); setState('ready'); setMessage('A previous receiver request needs recovery.');}
      else {setPending({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unconfirmed. Keep request reference ${result.requestKey} and check the original request.`); try {const saved = await restoreLegacyPayee(context); if (context.isCurrent()) setPending(saved);} catch { /* Keep the reference visible. */ }}
    } catch {if (context.isCurrent()) {setMessage('The receiver, group or recovery data could not be verified. Check the original request before continuing.'); try {const saved = await restoreLegacyPayee(context); if (context.isCurrent()) setPending(saved);} catch {if (context.isCurrent()) {setPending(null); setState('error');}}}}
    finally {busy.current = false; if (context.isCurrent()) {setState(previous => previous === 'sending' ? 'ready' : previous); setReview(null); setReviewSource(null); setConfirmed(false); setRetryAllowed(false);}}
  };
  const lookup = async () => {
    if (!unresolved || unresolved.kind !== 'owned' || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {const result = await lookupLegacyPayee(context, unresolved); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setState('success'); setMessage('The original receiver request was recorded.'); return;}
      if (result.status === 'not_found') {setRetryAllowed(result.retryAvailable && allowMutations); setMessage(result.retryAvailable && allowMutations ? 'No completed request was found. You may review the same request using its original reference.' : 'No completed request was found. Keep its reference; the original intent cannot be verified for retry.');}
      else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh before another change.' : 'The original request is still pending. Check again before continuing.');}
    catch {if (context.isCurrent()) setMessage('The original receiver request could not be verified. Keep its reference and check again.');}
    finally {busy.current = false; if (context.isCurrent()) setState(previous => previous === 'checking' ? 'ready' : previous);}
  };
  const reviewSame = async () => {
    if (!unresolved || unresolved.kind !== 'owned' || !unresolved.attempt || !retryAllowed || !allowMutations || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {const original = parseLegacyPayeeIntent(unresolved.attempt.intent), latest = await currentLegacyPayee(context); if (context.isCurrent() && gate.current) {setReview(original); setReviewSource(latest); setConfirmed(false);}}
    catch {if (context.isCurrent()) {setRetryAllowed(false); setMessage('The current receiver or group could not be verified. Check the original request again.');}}
    finally {busy.current = false; if (context.isCurrent()) setState(previous => previous === 'checking' ? 'ready' : previous);}
  };
  return <><PageHeader title="Edit receiver" subtitle="Review the group and recorded receiver before changing its name or status." actions={<Button type="button" onClick={() => navigate(`/admin/payees/${id}`)}>Back to receiver</Button>} />
    {!allowed ? <ErrorState title="Receiver editing unavailable" message="Your account cannot use this receiver workflow in this workspace." /> : state === 'loading' || loadedScope !== scope ? <LoadingState label="Checking receiver recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Receiver recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/payees/${id}`)}>View receiver</Button></div></Card> : <Card><div className="core-detail">
      {message && <p role="alert">{message}</p>}
      {unresolved?.kind === 'foreign' && <p>Another account or session has an unresolved receiver request. The original account must check it.</p>}
      {unresolved?.kind === 'owned' && <section><h2>Original request needs review</h2><p>Request reference: <code>{unresolved.requestKey}</code></p>{!unresolved.attempt && <p>The original form is unavailable. Keep this reference and check the request.</p>}<Button type="button" disabled={state !== 'ready'} onClick={() => void lookup()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section>}
      {!unresolved && !review && ready && allowMutations && source && <><p>Group: {source.group.title} · {source.group.status} · version {source.group.version}</p><p>Recorded route: {source.payee.network} · {source.payee.route} · receiver version {source.payee.version}. The recorded route cannot be changed here.</p><form className="core-edit-form" onSubmit={prepare}><label>Receiver name<input className="admin-input" value={label} minLength={2} maxLength={120} required onChange={event => setLabel(event.target.value)} /></label><label>Receiver status<select className="admin-input" value={status} onChange={event => setStatus(event.target.value as 'active' | 'inactive')}><option value="active">Active</option><option value="inactive">Inactive</option></select></label><label>Reason<textarea className="admin-input" value={reason} minLength={8} maxLength={1000} required onChange={event => setReason(event.target.value)} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review receiver</Button></form></>}
      {review && reviewSource && allowMutations && <section><h2>Review receiver change</h2><p>Group: {reviewSource.group.title} · {reviewSource.group.status} · version {reviewSource.group.version}</p><p>Current receiver: {reviewSource.payee.label} · {reviewSource.payee.network} · {reviewSource.payee.route} · {reviewSource.payee.status} · version {reviewSource.payee.version}</p><p>Requested name: {review.label} · status: {review.status}</p><p>Reason: {review.reason}</p>{unresolved && <p>The same original request will be used; it may make this change if the earlier request did not commit.</p>}<label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} /> I reviewed the group, receiver, route, status and reason.</label><Button type="button" disabled={state !== 'ready'} onClick={() => {setReview(null); setReviewSource(null); setConfirmed(false);}}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !confirmed} onClick={() => void send()}>{unresolved ? 'Confirm same request' : 'Confirm receiver'}</Button></section>}
    </div></Card>}</>;
}
