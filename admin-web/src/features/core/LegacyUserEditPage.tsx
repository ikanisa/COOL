import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { isId } from './contracts';
import { currentLegacyPerson, lookupLegacyUserEdit, parseLegacyUserEditIntent, restoreLegacyUserEdit, retryLegacyUserEdit, submitLegacyUserEdit, type LegacyPersonSnapshot, type LegacyUserEditContext, type LegacyUserEditIntent, type LegacyUserEditPending, type LegacyUserProfileIntent, type LegacyUserStatus } from './legacyUserEdit';
import type { PendingIdentity } from './pendingAttempt';
import type { FeatureAccess } from './types';
import './core.css';

export interface LegacyUserEditProps extends FeatureAccess {id: string; returnArea?: 'users' | 'members'; identity: PendingIdentity; allowMutations?: boolean; allowStatusChanges?: boolean; verifyFresh?: () => Promise<boolean>;}
type Draft = {display_name: string; momo_provider: LegacyUserProfileIntent['momo_provider']; momo_number: string; momo_pay_code: string; reason: string;};
function draftFor(person: LegacyPersonSnapshot): Draft {return {display_name: person.displayName ?? '', momo_provider: person.momoProvider, momo_number: person.momoNumber, momo_pay_code: person.momoCode, reason: ''};}

/** Legacy profile changes remain opt-in while migration and recovery are qualified. */
export function LegacyUserEditPage({id, returnArea = 'users', request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, allowStatusChanges = false, verifyFresh}: LegacyUserEditProps) {
  const identityKey = JSON.stringify([...new Set(identity.permissions)].sort()), providedKey = JSON.stringify([...new Set(permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role, permissions: JSON.parse(identityKey) as string[], expiresAt: identity.expiresAt}), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, identityKey]);
  const stablePermissions = useMemo<readonly string[]>(() => JSON.parse(providedKey) as string[], [providedKey]);
  const allowed = financialModel === 'transaction_journals' && role !== 'staff' && isId(id) && isId(actorId) && stableIdentity.id === actorId && stableIdentity.role === role &&
    ['users.read', 'users.manage', 'overview.read'].every(value => stablePermissions.includes(value) && stableIdentity.permissions.includes(value));
  const scope = JSON.stringify([authorityKey, financialModel, id]), current = useRef(scope), gate = useRef(allowMutations), statusGate = useRef(allowStatusChanges), fresh = useRef(verifyFresh), busy = useRef(false);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = allowMutations; return () => {gate.current = false;};}, [allowMutations]);
  useLayoutEffect(() => {statusGate.current = allowStatusChanges; fresh.current = verifyFresh; return () => {statusGate.current = false;};}, [allowStatusChanges, verifyFresh]);
  const context = useMemo<LegacyUserEditContext>(() => ({request, identity: stableIdentity, actorId, userId: id, permissions: stablePermissions, financialModel, enabled: allowMutations,
    statusEnabled: allowStatusChanges, isStatusEnabled: () => statusGate.current, verifyStatusFresh: () => fresh.current?.() ?? Promise.resolve(false),
    isCurrent: () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now(), isEnabled: () => gate.current}), [request, stableIdentity, actorId, id, stablePermissions, financialModel, allowMutations, allowStatusChanges, scope]);
  const [source, setSource] = useState<LegacyPersonSnapshot | null>(null), [draft, setDraft] = useState<Draft | null>(null), [pendingState, setPendingState] = useState<LegacyUserEditPending | null>(null), [loadedScope, setLoadedScope] = useState('');
  const [review, setReview] = useState<LegacyUserEditIntent | null>(null), [revision, setRevision] = useState(''), [retryAllowed, setRetryAllowed] = useState(false), [confirmed, setConfirmed] = useState(false);
  const [targetStatus, setTargetStatus] = useState<LegacyUserStatus>('suspended'), [statusReason, setStatusReason] = useState('');
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading'), [message, setMessage] = useState('');
  useEffect(() => {
    if (!allowed) return; let live = true;
    restoreLegacyUserEdit(context).then(async saved => {
      const person = saved.kind === 'ready' && (allowMutations || allowStatusChanges) ? await currentLegacyPerson(context) : null;
      if (live && context.isCurrent()) {setPendingState(saved); setSource(person); if (person) {setDraft(draftFor(person)); setTargetStatus(person.status === 'active' ? 'suspended' : 'active'); setStatusReason('');} setLoadedScope(scope); setState('ready'); setMessage(saved.kind !== 'ready' ? 'A previous person change needs recovery. Check its original reference before continuing.' : !allowMutations && !allowStatusChanges ? 'Person editing is not enabled for this workspace.' : '');}
    }).catch(() => {if (live && context.isCurrent()) {setLoadedScope(scope); setState('error'); setMessage('The person or recovery data could not be verified. Operator-linked and closed accounts need separate review.');}});
    return () => {live = false;};
  }, [allowed, allowMutations, allowStatusChanges, context, scope]);
  const pending = pendingState && pendingState.kind !== 'ready' ? pendingState : null, ready = pendingState?.kind === 'ready' ? pendingState : null;
  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!ready || !allowMutations || !draft || !source || busy.current || !context.isCurrent()) return;
    try {setReview(parseLegacyUserEditIntent({display_name: draft.display_name.trim(), momo_provider: draft.momo_provider, momo_number: draft.momo_number.trim(), momo_pay_code: draft.momo_pay_code.trim(), expected_version: source.version, reason: draft.reason.trim()}, source.memberType)); setRevision(ready.revision); setConfirmed(false); setMessage('');}
    catch {setMessage('Check the recorded name, provider, MoMo details and reason. Direct members need a recorded MoMo number.');}
  };
  const makeStatusReview = (event: FormEvent) => {
    event.preventDefault(); if (!ready || !allowStatusChanges || !source || source.status === 'closed' || targetStatus === source.status || busy.current || !context.isCurrent()) return;
    try {setReview(parseLegacyUserEditIntent({status: targetStatus, expected_version: source.version, reason: statusReason.trim()}, source.memberType)); setRevision(ready.revision); setConfirmed(false); setMessage('');}
    catch {setMessage('Choose a different account status and enter a reason for the change.');}
  };
  const send = async () => {
    if (!allowed || !review || !('status' in review ? allowStatusChanges : allowMutations) || !confirmed || busy.current || !context.isCurrent() || pending?.kind === 'foreign' || pending?.kind === 'owned' && !retryAllowed) return;
    busy.current = true; setState('sending'); setMessage('');
    try {
      const result = pending?.kind === 'owned' ? await retryLegacyUserEdit(context, pending) : source ? await submitLegacyUserEdit(context, review, source, revision) : null;
      if (!result || !context.isCurrent()) return;
      if (result.status === 'succeeded') {setPendingState(null); setState('success'); setMessage('The person was updated.');}
      else if (result.status === 'existing') {setPendingState(result.pending); setState('ready'); setMessage('A previous person change needs recovery.');}
      else {setPendingState({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unconfirmed. Keep request reference ${result.requestKey} and check the original request.`); try {const saved = await restoreLegacyUserEdit(context); if (context.isCurrent()) setPendingState(saved);} catch { /* Keep the reference visible. */ }}
    } catch (failure) {if (context.isCurrent()) {setMessage(failure instanceof Error && failure.message === 'Verify your account before changing this status.' ? failure.message : 'The person or recovery data could not be verified. Check the original request before continuing.'); try {const saved = await restoreLegacyUserEdit(context); if (context.isCurrent()) setPendingState(saved);} catch {if (context.isCurrent()) {setPendingState(null); setState('error');}}}}
    finally {busy.current = false; if (context.isCurrent()) {setState(previous => previous === 'sending' ? 'ready' : previous); setReview(null); setConfirmed(false); setRetryAllowed(false);}}
  };
  const check = async () => {
    if (!pending || pending.kind !== 'owned' || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const result = await lookupLegacyUserEdit(context, pending); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPendingState(null); setState('success'); setMessage('The original person change was recorded.'); return;}
      if (result.status === 'not_found') {setRetryAllowed(result.retryAvailable); setMessage(result.retryAvailable ? 'No completed request was found. You may review the same request with its original reference.' : 'No completed request was found. Keep the reference; the original model or intent cannot be verified for a retry.');}
      else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh before another change.' : 'The original request is still pending. Check again before continuing.');
    } catch {if (context.isCurrent()) setMessage('The original request could not be verified. Keep its reference and check again.');}
    finally {busy.current = false; if (context.isCurrent()) setState(previous => previous === 'checking' ? 'ready' : previous);}
  };
  const reviewSame = async () => {
    if (!pending || pending.kind !== 'owned' || !pending.attempt || !retryAllowed || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {const person = await currentLegacyPerson(context), original = parseLegacyUserEditIntent(pending.attempt.intent, person.memberType); if (context.isCurrent() && ('status' in original ? statusGate.current : gate.current)) {setSource(person); setReview(original); setConfirmed(false);}}
    catch {if (context.isCurrent()) {setRetryAllowed(false); setMessage('The current person or original intent could not be verified. Check the request again.');}}
    finally {busy.current = false; if (context.isCurrent()) setState(previous => previous === 'checking' ? 'ready' : previous);}
  };
  return <><PageHeader title="Edit person" subtitle="Review the recorded profile and its current version." actions={<Button type="button" onClick={() => navigate(isId(id) ? `/admin/${returnArea}/${id}` : `/admin/${returnArea}`)}>Back to person</Button>} />
    {!allowed ? <ErrorState title="Editing unavailable" message="Your account cannot edit people in this workspace." /> : state === 'loading' || loadedScope !== scope ? <LoadingState label="Checking person recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Person updated</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/${returnArea}/${id}`)}>View person</Button></div></Card> : <Card><div className="core-detail">
      {message && <p role="alert">{message}</p>}
      {pending?.kind === 'foreign' && <p>Another account or session has an unresolved person change. The original account must check it.</p>}
      {pending?.kind === 'owned' && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.requestKey}</code></p>{!pending.attempt && <p>The original form is unavailable. Keep this reference and check the request.</p>}<Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section>}
      {!pending && !review && allowMutations && ready && draft && source && <form className="core-edit-form" onSubmit={makeReview}>
        <p>Person: {source.publicId} · {source.memberType} · version {source.version} · {source.status}.</p>
        <label>Recorded full name<input className="admin-input" value={draft.display_name} maxLength={120} required onChange={event => setDraft({...draft, display_name: event.target.value})} /></label>
        <label>MoMo provider<select className="admin-input" value={draft.momo_provider} onChange={event => setDraft({...draft, momo_provider: event.target.value as Draft['momo_provider']})}><option value="">Not recorded</option><option value="mtn_momo">MTN MoMo</option><option value="airtel_money">Airtel Money</option></select></label>
        <label>MoMo number<input className="admin-input" value={draft.momo_number} maxLength={10} onChange={event => setDraft({...draft, momo_number: event.target.value})} /></label>
        <label>MoMo code (optional)<input className="admin-input" value={draft.momo_pay_code} maxLength={9} onChange={event => setDraft({...draft, momo_pay_code: event.target.value})} /></label>
        <label>Reason for change<textarea className="admin-input" value={draft.reason} minLength={8} maxLength={1000} required onChange={event => setDraft({...draft, reason: event.target.value})} /></label>
        <p>Recorded payment details are not provider verified. Changing the MoMo number can change receipt attribution based on a full-number match.</p><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review person changes</Button>
      </form>}
      {!pending && !review && allowStatusChanges && ready && source && <form className="core-edit-form" onSubmit={makeStatusReview}>
        <h2>Account status</h2><p>Current status: {source.status} · version {source.version}. A person who owns an active group cannot be made inactive.</p>
        <label>New account status<select className="admin-input" value={targetStatus} onChange={event => setTargetStatus(event.target.value as LegacyUserStatus)}>{(['invited', 'active', 'suspended', 'closed'] as const).map(value => <option key={value} value={value} disabled={value === source.status}>{value}</option>)}</select></label>
        <label>Reason for status change<textarea className="admin-input" value={statusReason} minLength={8} maxLength={1000} required onChange={event => setStatusReason(event.target.value)} /></label>
        <p>Inviting, suspending or closing ends existing member sessions. Closing cannot be reversed from this editor.</p>
        <Button type="submit" variant="primary" disabled={state !== 'ready'}>Review account status</Button>
      </form>}
      {review && ('status' in review ? allowStatusChanges : allowMutations) && source && <section><h2>{'status' in review ? 'Review account status' : 'Review person change'}</h2><p>Current person: {source.displayName ?? 'Name not recorded'} · {source.publicId} · version {source.version}.</p>{'status' in review && <p>Account status: {source.status} → {review.status}. {review.status === 'closed' ? 'Closing cannot be reversed from this editor.' : review.status === 'active' ? 'Earlier member sessions are not restored.' : 'Existing member sessions will end.'}</p>}<dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{value === '' ? 'Not recorded' : String(value)}</dd></div>)}</dl><p>{pending ? 'The same original request will be used; it may make this change if the earlier request did not commit.' : 'Review the recorded details and reason before confirming.'}{'status' in review ? ' Account verification is required before the change.' : ' Provider identity is not verified.'}</p><label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} /> I reviewed the person details and reason.</label><Button type="button" disabled={state !== 'ready'} onClick={() => {setReview(null); setConfirmed(false);}}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !confirmed} onClick={() => void send()}>{pending ? 'Confirm same request' : 'status' in review ? 'Confirm account status' : 'Confirm person changes'}</Button></section>}
    </div></Card>}</>;
}
