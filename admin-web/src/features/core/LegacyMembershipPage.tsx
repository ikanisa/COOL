import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { isId } from './contracts';
import { currentLegacyMembership, lookupLegacyMembership, parseLegacyMembershipIntent, restoreLegacyMembership, retryLegacyMembership, searchLegacyMembers, submitLegacyMembership, type LegacyMemberChoice, type LegacyMembershipContext, type LegacyMembershipIntent, type LegacyMembershipPending, type LegacyMembershipSource } from './legacyMembershipActions';
import type { PendingIdentity } from './pendingAttempt';
import {usePendingIdentity} from './usePendingIdentity';
import type { FeatureAccess } from './types';
import './core.css';

export interface LegacyMembershipProps extends FeatureAccess {mode: 'create' | 'edit'; groupId: string; userId?: string; identity: PendingIdentity; allowMutations?: boolean; verifyFresh: () => Promise<boolean>;}
type Draft = {role: LegacyMembershipIntent['role']; status: LegacyMembershipIntent['status']; reason: string};
const initial: Draft = {role: 'member', status: 'active', reason: ''};
const roles: Draft['role'][] = ['admin', 'receiver', 'member', 'contributor', 'viewer'];

/** Legacy membership changes remain opt-in while coexistence is qualified. */
export function LegacyMembershipPage({mode, groupId, userId, request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh}: LegacyMembershipProps) {
  const identityKey = JSON.stringify([...new Set(identity.permissions)].sort()), permissionKey = JSON.stringify([...new Set(permissions)].sort());
  const stableIdentity = usePendingIdentity(identity);
  const stablePermissions = useMemo<readonly string[]>(() => JSON.parse(permissionKey) as string[], [permissionKey]);
  const allowed = financialModel === 'transaction_journals' && isId(actorId) && isId(groupId) && (mode === 'create' || isId(userId)) && role !== 'staff' && stableIdentity.id === actorId && stableIdentity.role === role &&
    ['collections.read', 'users.read', 'users.manage', 'overview.read'].every(value => stablePermissions.includes(value) && stableIdentity.permissions.includes(value));
  const scope = JSON.stringify([authorityKey, financialModel, mode, groupId, userId, actorId, role, stableIdentity.id, stableIdentity.sessionId, stableIdentity.role, stableIdentity.expiresAt, identityKey, permissionKey]), current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false), searchEpoch = useRef(0), verification = useRef(verifyFresh);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = allowMutations; return () => {gate.current = false;};}, [allowMutations]);
  useLayoutEffect(() => {verification.current = verifyFresh;}, [verifyFresh]);
  const context = useMemo<LegacyMembershipContext>(() => ({mode, groupId, userId, request, identity: stableIdentity, actorId, permissions: stablePermissions, financialModel, enabled: allowMutations,
    isCurrent: () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now(), isEnabled: () => gate.current, verifyFresh: () => verification.current()}), [mode, groupId, userId, request, stableIdentity, actorId, stablePermissions, financialModel, allowMutations, scope]);
  const [pendingState, setPendingState] = useState<LegacyMembershipPending | null>(null), [loadedScope, setLoadedScope] = useState(''), [source, setSource] = useState<LegacyMembershipSource | null>(null);
  const [draft, setDraft] = useState<Draft>(initial), [search, setSearch] = useState(''), [choices, setChoices] = useState<LegacyMemberChoice[]>([]), [selected, setSelected] = useState<LegacyMemberChoice | null>(null);
  const [review, setReview] = useState<LegacyMembershipIntent | null>(null), [reviewSource, setReviewSource] = useState<LegacyMembershipSource | null>(null), [revision, setRevision] = useState(''), [retryAllowed, setRetryAllowed] = useState(false), [confirmed, setConfirmed] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'searching' | 'checking' | 'sending' | 'success' | 'error'>('loading'), [message, setMessage] = useState('');
  useEffect(() => {
    if (!allowed) return; let live = true; const epoch = searchEpoch;
    restoreLegacyMembership(context).then(async saved => {
      const value = saved.kind === 'ready' && allowMutations && mode === 'edit' ? await currentLegacyMembership(context, userId!) : null;
      if (live && context.isCurrent()) {setPendingState(saved); setSource(value); if (value?.membership) setDraft({role: value.membership.role as Draft['role'], status: value.membership.status as Draft['status'], reason: ''}); setLoadedScope(scope); setState('ready'); setMessage(saved.kind !== 'ready' ? 'A previous membership request needs recovery. Check its original reference before continuing.' : !allowMutations ? 'Membership changes are not enabled for this workspace.' : '');}
    }).catch(() => {if (live && context.isCurrent()) {setLoadedScope(scope); setState('error'); setMessage('The membership or recovery data could not be verified.');}});
    return () => {live = false; epoch.current++;};
  }, [allowed, allowMutations, context, mode, scope, userId]);
  const pending = pendingState && pendingState.kind !== 'ready' ? pendingState : null, ready = pendingState?.kind === 'ready' ? pendingState : null;
  const find = async (event: FormEvent) => {
    event.preventDefault(); if (!ready || !allowMutations || busy.current || !context.isCurrent()) return;
    const epoch = ++searchEpoch.current; busy.current = true; setState('searching'); setMessage('');
    try {const found = await searchLegacyMembers(context, search); if (context.isCurrent() && epoch === searchEpoch.current) {setChoices(found); setSelected(null); if (!found.length) setMessage('No active people match this search.');}}
    catch {if (context.isCurrent() && epoch === searchEpoch.current) setMessage('Active people could not be verified.');}
    finally {busy.current = false; if (context.isCurrent() && epoch === searchEpoch.current) setState('ready');}
  };
  const makeReview = async (event: FormEvent) => {
    event.preventDefault(); if (!ready || !allowMutations || busy.current || !context.isCurrent() || mode === 'create' && !selected || mode === 'edit' && !source) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      const target = mode === 'create' ? selected!.id : userId!, latest = await currentLegacyMembership(context, target);
      const selectedSource: LegacyMemberChoice = {id: latest.member.id, publicId: latest.member.publicId, displayName: latest.member.displayName, memberType: latest.member.memberType, momoNumber: latest.member.momoNumber, version: latest.member.version};
      if (mode === 'create' && JSON.stringify(selected) !== JSON.stringify(selectedSource) || mode === 'edit' && JSON.stringify(source) !== JSON.stringify(latest)) throw new Error('Changed source');
      const value = mode === 'create' ? {group_id: groupId, user_id: target, role: draft.role, status: draft.status, reason: draft.reason.trim()} : {role: draft.role, status: draft.status, expected_version: latest.membership?.version, reason: draft.reason.trim()};
      const intent = parseLegacyMembershipIntent(value, context); if (intent.status === 'active' && latest.member.status !== 'active') throw new Error('Member inactive');
      if (context.isCurrent() && gate.current) {setReview(intent); setReviewSource(latest); setRevision(ready.revision); setConfirmed(false);}
    } catch {if (context.isCurrent()) setMessage('Check the membership details and reason. The group or person may have changed.');}
    finally {busy.current = false; if (context.isCurrent()) setState(previous => previous === 'checking' ? 'ready' : previous);}
  };
  const send = async () => {
    if (!allowMutations || !review || !reviewSource || !confirmed || busy.current || !context.isCurrent() || pending?.kind === 'foreign' || pending?.kind === 'owned' && !retryAllowed) return;
    busy.current = true; setState('sending'); setMessage('');
    try {
      const result = pending?.kind === 'owned' ? await retryLegacyMembership(context, pending) : await submitLegacyMembership(context, review, reviewSource, revision);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPendingState(null); setState('success'); setMessage('The membership request was recorded.');}
      else if (result.status === 'existing') {setPendingState(result.pending); setState('ready'); setMessage('A previous membership request needs recovery.');}
      else {setPendingState({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unconfirmed. Keep request reference ${result.requestKey} and check the original request.`); try {const saved = await restoreLegacyMembership(context); if (context.isCurrent()) setPendingState(saved);} catch { /* Preserve the visible reference. */ }}
    } catch {if (context.isCurrent()) {setMessage('The group, member or recovery data could not be verified. Check the original request before continuing.'); try {const saved = await restoreLegacyMembership(context); if (context.isCurrent()) setPendingState(saved);} catch {if (context.isCurrent()) {setPendingState(null); setState('error');}}}}
    finally {busy.current = false; if (context.isCurrent()) {setState(previous => previous === 'sending' ? 'ready' : previous); setReview(null); setConfirmed(false); setRetryAllowed(false);}}
  };
  const check = async () => {
    if (!pending || pending.kind !== 'owned' || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const result = await lookupLegacyMembership(context, pending); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPendingState(null); setState('success'); setMessage('The original membership request was recorded.'); return;}
      if (result.status === 'not_found') {setRetryAllowed(result.retryAvailable && allowMutations); setMessage(result.retryAvailable && allowMutations ? 'No completed request was found. You may review the same request with its original reference.' : 'No completed request was found. Keep the reference; the original model or intent cannot be verified for a retry.');}
      else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh before another change.' : 'The original request is still pending. Check again before continuing.');
    } catch {if (context.isCurrent()) setMessage('The original request could not be verified. Keep its reference and check the original group.');}
    finally {busy.current = false; if (context.isCurrent()) setState(previous => previous === 'checking' ? 'ready' : previous);}
  };
  const reviewSame = async () => {
    if (!pending || pending.kind !== 'owned' || !pending.attempt || !retryAllowed || !allowMutations || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {const intent = parseLegacyMembershipIntent(pending.attempt.intent, context), latest = await currentLegacyMembership(context, mode === 'create' ? intent.user_id! : userId!);
      if (context.isCurrent() && gate.current) {setReview(intent); setReviewSource(latest); setConfirmed(false);}}
    catch {if (context.isCurrent()) {setRetryAllowed(false); setMessage('The current group or member could not be verified. Check the original request again.');}}
    finally {busy.current = false; if (context.isCurrent()) setState(previous => previous === 'checking' ? 'ready' : previous);}
  };
  const originalGroup = pending?.kind === 'owned' && isId(pending.attempt?.intent.group_id) ? pending.attempt.intent.group_id : null;
  return <><PageHeader title={mode === 'create' ? 'Add member' : 'Edit membership'} subtitle="Review the group, person and membership before confirming." actions={<Button type="button" onClick={() => navigate(`/admin/groups/${groupId}`)}>Back to group</Button>} />
    {!allowed ? <ErrorState title="Membership changes unavailable" message="Your account cannot use this membership workflow in this workspace." /> : state === 'loading' || loadedScope !== scope ? <LoadingState label="Checking membership recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Membership recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/groups/${groupId}`)}>View group</Button></div></Card> : <Card><div className="core-detail">
      {message && <p role="alert">{message}</p>}
      {pending?.kind === 'foreign' && <p>Another account or session has an unresolved membership request. The original account must check it.</p>}
      {pending?.kind === 'owned' && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.requestKey}</code></p>{originalGroup && originalGroup !== groupId && <p>This request belongs to group {originalGroup}. Open that group to check its receipt.</p>}{!pending.attempt && <p>The original form is unavailable. Keep this reference and check the request.</p>}<Button type="button" disabled={state !== 'ready' || !!originalGroup && originalGroup !== groupId} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section>}
      {!pending && !review && allowMutations && ready && <>
        {mode === 'create' && <><p>Search for an active person. Existing memberships and group owners cannot be changed through this form.</p><form className="core-search" onSubmit={event => void find(event)}><label>Search people<input className="admin-input" value={search} maxLength={200} onChange={event => setSearch(event.target.value)} /></label><Button type="submit" disabled={state !== 'ready'}>Search people</Button></form>{choices.length > 0 && <label>Person<select className="admin-input" value={selected?.id ?? ''} onChange={event => setSelected(choices.find(value => value.id === event.target.value) ?? null)}><option value="">Select a person</option>{choices.map(value => <option key={value.id} value={value.id}>{value.displayName ?? 'Name not recorded'} · {value.publicId}</option>)}</select></label>}</>}
        {mode === 'edit' && source && <p>{source.member.displayName ?? 'Name not recorded'} · {source.member.publicId} · membership version {source.membership?.version} · {source.membership?.role} / {source.membership?.status}</p>}
        <form className="core-edit-form" onSubmit={event => void makeReview(event)}><label>Role<select className="admin-input" value={draft.role} onChange={event => setDraft({...draft, role: event.target.value as Draft['role']})}>{roles.map(value => <option key={value} value={value}>{value}</option>)}</select></label><label>Membership status<select className="admin-input" value={draft.status} onChange={event => setDraft({...draft, status: event.target.value as Draft['status']})}>{(mode === 'create' ? ['active', 'invited'] : ['active', 'invited', 'removed', 'left']).map(value => <option key={value} value={value}>{value}</option>)}</select></label><label>Reason<textarea className="admin-input" value={draft.reason} minLength={8} maxLength={1000} required onChange={event => setDraft({...draft, reason: event.target.value})} /></label><Button type="submit" variant="primary" disabled={state !== 'ready' || mode === 'create' && !selected}>Review membership</Button></form>
      </>}
      {review && reviewSource && allowMutations && <section><h2>Review membership {mode === 'create' ? 'creation' : 'change'}</h2><p>Group: {reviewSource.group.title} · version {reviewSource.group.version} · {reviewSource.group.status}</p><p>Person: {reviewSource.member.displayName ?? 'Name not recorded'} · {reviewSource.member.publicId} · {reviewSource.member.memberType} · {reviewSource.member.status}</p>{reviewSource.membership && <p>Current membership: {reviewSource.membership.role} / {reviewSource.membership.status} · version {reviewSource.membership.version}</p>}<p>Requested role: {review.role} · status: {review.status}</p><p>Reason: {review.reason}</p><p>{pending ? 'The same original request will be used; it may make this change if the earlier request did not commit. ' : ''}This request may create an email notification for the person; delivery is not confirmed here.</p><label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} /> I reviewed the group, person, membership and reason.</label><Button type="button" disabled={state !== 'ready'} onClick={() => {setReview(null); setConfirmed(false);}}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !confirmed} onClick={() => void send()}>{pending ? 'Confirm same request' : 'Confirm membership'}</Button></section>}
    </div></Card>}</>;
}
