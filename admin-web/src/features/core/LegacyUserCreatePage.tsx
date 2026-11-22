import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { isId } from './contracts';
import { lookupLegacyUserCreate, parseLegacyUserIntent, restoreLegacyUserCreate, retryLegacyUserCreate, submitLegacyUserCreate, type LegacyUserCreateContext, type LegacyUserIntent, type LegacyUserPending } from './legacyUserCreate';
import type { PendingIdentity } from './pendingAttempt';
import {usePendingIdentity} from './usePendingIdentity';
import type { FeatureAccess } from './types';
import './core.css';

export interface LegacyUserCreateProps extends FeatureAccess {identity: PendingIdentity; allowMutations?: boolean;}
type Draft = {display_name: string; member_type: 'app' | 'direct'; momo_provider: '' | 'mtn_momo' | 'airtel_money'; momo_number: string; momo_pay_code: string; email: string; phone_e164: string; status: 'invited' | 'active' | 'suspended' | 'closed'; reason: string;};
const initialDraft: Draft = {display_name: '', member_type: 'app', momo_provider: '', momo_number: '', momo_pay_code: '', email: '', phone_e164: '', status: 'invited', reason: ''};

/** Legacy person creation remains opt-in while migration and cross-version recovery are qualified. */
export function LegacyUserCreatePage({request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, allowMutations = false}: LegacyUserCreateProps) {
  const providedKey = JSON.stringify([...new Set(permissions)].sort());
  const stableIdentity = usePendingIdentity(identity);
  const stablePermissions = useMemo<readonly string[]>(() => JSON.parse(providedKey) as string[], [providedKey]);
  const allowed = financialModel === 'transaction_journals' && role !== 'staff' && isId(actorId) && stableIdentity.id === actorId && stableIdentity.role === role &&
    ['users.manage', 'overview.read'].every(permission => stablePermissions.includes(permission) && stableIdentity.permissions.includes(permission));
  const scope = JSON.stringify([authorityKey, financialModel]), current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = allowMutations; return () => {gate.current = false;};}, [allowMutations]);
  const context = useMemo<LegacyUserCreateContext>(() => ({request, identity: stableIdentity, actorId, permissions: stablePermissions, financialModel, enabled: allowMutations,
    isCurrent: () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now(), isEnabled: () => gate.current}), [request, stableIdentity, actorId, stablePermissions, financialModel, allowMutations, scope]);
  const [draft, setDraft] = useState<Draft>(initialDraft), [pendingState, setPendingState] = useState<LegacyUserPending | null>(null), [loadedScope, setLoadedScope] = useState('');
  const [review, setReview] = useState<LegacyUserIntent | null>(null), [revision, setRevision] = useState(''), [retryAllowed, setRetryAllowed] = useState(false), [confirmed, setConfirmed] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading'), [message, setMessage] = useState(''), [createdId, setCreatedId] = useState('');
  useEffect(() => {
    if (!allowed) return; let live = true;
    restoreLegacyUserCreate(context).then(saved => {if (live && context.isCurrent()) {setPendingState(saved); setLoadedScope(scope); setState('ready'); setMessage(saved.kind !== 'ready' ? 'A previous person creation needs recovery. Check its original request before continuing.' : !allowMutations ? 'Person creation is not enabled for this workspace.' : '');}},
      () => {if (live && context.isCurrent()) {setLoadedScope(scope); setState('error'); setMessage('Recovery data could not be verified. Check the original request before continuing.');}});
    return () => {live = false;};
  }, [allowed, allowMutations, context, scope]);
  const pending = pendingState && pendingState.kind !== 'ready' ? pendingState : null, ready = pendingState?.kind === 'ready' ? pendingState : null;
  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!allowed || !allowMutations || !ready || busy.current || !context.isCurrent()) return;
    try {
      const value = parseLegacyUserIntent({display_name: draft.display_name.trim(), member_type: draft.member_type, momo_provider: draft.momo_provider, momo_number: draft.momo_number.trim(), momo_pay_code: draft.momo_pay_code.trim(),
        email: draft.email.trim().toLowerCase() || null, ...(draft.member_type === 'app' ? {phone_e164: draft.phone_e164.trim() || null} : {}), status: draft.status, reason: draft.reason.trim()});
      setReview(value); setRevision(ready.revision); setConfirmed(false); setMessage('');
    } catch {setMessage('Check the recorded name, member type, provider, MoMo details, contact and reason. App members need an email or Rwanda login number; Direct members need a recorded MoMo number.');}
  };
  const send = async () => {
    if (!allowed || !allowMutations || !review || !confirmed || busy.current || !context.isCurrent() || pending?.kind === 'foreign' || pending?.kind === 'owned' && !retryAllowed) return;
    busy.current = true; setState('sending'); setMessage('');
    try {
      const result = pending?.kind === 'owned' ? await retryLegacyUserCreate(context, pending) : await submitLegacyUserCreate(context, review, revision);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPendingState(null); setCreatedId(result.receipt.userId); setState('success'); setMessage('The person was recorded.');}
      else if (result.status === 'existing') {setPendingState(result.pending); setState('ready'); setMessage('A previous person creation needs recovery. Check its original request before continuing.');}
      else {setPendingState({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unconfirmed. Keep request reference ${result.requestKey} and check the original request.`); try {const saved = await restoreLegacyUserCreate(context); if (context.isCurrent()) setPendingState(saved);} catch { /* Keep the original reference visible. */ }}
    } catch {
      if (context.isCurrent()) {setMessage('The person or recovery data could not be verified. Check the original request before continuing.'); try {const saved = await restoreLegacyUserCreate(context); if (context.isCurrent()) setPendingState(saved);} catch {if (context.isCurrent()) {setPendingState(null); setState('error');}}}
    } finally {busy.current = false; if (context.isCurrent()) {setState(previous => previous === 'sending' ? 'ready' : previous); setReview(null); setConfirmed(false); setRetryAllowed(false);}}
  };
  const check = async () => {
    if (!pending || pending.kind !== 'owned' || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const result = await lookupLegacyUserCreate(context, pending); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPendingState(null); setCreatedId(result.receipt.userId); setState('success'); setMessage('The original person creation was recorded.'); return;}
      if (result.status === 'not_found') {setRetryAllowed(result.retryAvailable && allowMutations); setMessage(result.retryAvailable && allowMutations ? 'No completed request was found. You may review the same request with its original reference.' : 'No completed request was found. Keep the reference; the original model or intent cannot be verified for a retry.');}
      else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh before another change.' : 'The original request is still pending. Check again before continuing.');
    } catch {if (context.isCurrent()) setMessage('The original request could not be verified. Keep its reference and check again.');}
    finally {busy.current = false; if (context.isCurrent()) setState(previous => previous === 'checking' ? 'ready' : previous);}
  };
  const reviewSame = () => {
    if (!pending || pending.kind !== 'owned' || !pending.attempt || !retryAllowed || !allowMutations || busy.current || !context.isCurrent()) return;
    try {setReview(parseLegacyUserIntent(pending.attempt.intent)); setConfirmed(false); setMessage('');} catch {setRetryAllowed(false); setMessage('The original intent could not be verified.');}
  };
  return <><PageHeader title="Create person" subtitle="Record an App or Direct person and their payment details." actions={<Button type="button" onClick={() => navigate('/admin/users')}>Back to users</Button>} />
    {!allowed ? <ErrorState title="Creation unavailable" message="Your account cannot create people in this workspace." /> : state === 'loading' || loadedScope !== scope ? <LoadingState label="Checking recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Person recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/users/${createdId}`)}>View person</Button></div></Card> : <Card><div className="core-detail">
      {message && <p role="alert">{message}</p>}
      {pending?.kind === 'foreign' && <p>Another account or session has an unresolved person creation. The original account must check it.</p>}
      {pending?.kind === 'owned' && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.requestKey}</code></p>{!pending.attempt && <p>The original form is unavailable. Keep this reference and check the request.</p>}<Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={reviewSame}>Review same request</Button>}</section>}
      {!pending && !review && allowMutations && ready && <form className="core-edit-form" onSubmit={makeReview}>
        <label>Recorded full name<input className="admin-input" value={draft.display_name} maxLength={120} required onChange={event => setDraft({...draft, display_name: event.target.value})} /></label>
        <label>Member type<select className="admin-input" value={draft.member_type} onChange={event => setDraft({...draft, member_type: event.target.value as Draft['member_type']})}><option value="app">App</option><option value="direct">Direct</option></select></label>
        <label>MoMo provider<select className="admin-input" value={draft.momo_provider} onChange={event => setDraft({...draft, momo_provider: event.target.value as Draft['momo_provider']})}><option value="">Not recorded</option><option value="mtn_momo">MTN MoMo</option><option value="airtel_money">Airtel Money</option></select></label>
        <label>MoMo number<input className="admin-input" value={draft.momo_number} maxLength={10} onChange={event => setDraft({...draft, momo_number: event.target.value})} /></label>
        <label>MoMo code (optional)<input className="admin-input" value={draft.momo_pay_code} maxLength={9} onChange={event => setDraft({...draft, momo_pay_code: event.target.value})} /></label>
        <label>Email<input className="admin-input" type="email" value={draft.email} maxLength={254} onChange={event => setDraft({...draft, email: event.target.value})} /></label>
        {draft.member_type === 'app' && <label>WhatsApp login number<input className="admin-input" value={draft.phone_e164} maxLength={13} placeholder="+25078…" onChange={event => setDraft({...draft, phone_e164: event.target.value})} /></label>}
        <label>Account status<select className="admin-input" value={draft.status} onChange={event => setDraft({...draft, status: event.target.value as Draft['status']})}><option value="invited">Invited</option><option value="active">Active</option><option value="suspended">Suspended</option><option value="closed">Closed</option></select></label>
        <label>Reason for creation<textarea className="admin-input" value={draft.reason} minLength={8} maxLength={1000} required onChange={event => setDraft({...draft, reason: event.target.value})} /></label>
        <p>Recorded names and payment details are not provider verified. A Direct member's MoMo number is not an App login. App creation also records a notification for delivery separately.</p><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review person</Button>
      </form>}
      {review && allowMutations && <section><h2>Review person creation</h2><dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{value === null || value === '' ? 'Not recorded' : String(value)}</dd></div>)}</dl><p>Recorded payment details are not provider verified. {pending ? 'The same original request will be used; it may create this person if the earlier request did not commit.' : 'Review the member type and recorded contact before confirming.'}</p><label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} /> I reviewed the person details and reason.</label><Button type="button" disabled={state !== 'ready'} onClick={() => {setReview(null); setConfirmed(false);}}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !confirmed} onClick={() => void send()}>{pending ? 'Confirm same request' : 'Confirm person'}</Button></section>}
    </div></Card>}</>;
}
