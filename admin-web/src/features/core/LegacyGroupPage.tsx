import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { isId } from './contracts';
import {
  lookupLegacyGroupAction, parseLegacyGroupIntent, restoreLegacyGroupAction, retryLegacyGroupAction,
  submitLegacyGroupAction, type LegacyGroupPending,
} from './legacyGroupActions';
import {currentLegacyGroup, readLegacyOwner, searchLegacyOwners, type LegacyGroupContext, type LegacyGroupIntent, type LegacyGroupSnapshot, type LegacyOwner} from './legacyGroupRecords';
import type {LegacyGroupStatusContext} from './legacyGroupStatus';
import {LegacyGroupStatusControls} from './LegacyGroupStatusControls';
import type { PendingIdentity } from './pendingAttempt';
import {usePendingIdentity} from './usePendingIdentity';
import type { FeatureAccess } from './types';
import './core.css';

export interface LegacyGroupProps extends FeatureAccess {mode: 'create' | 'edit'; id?: string; identity: PendingIdentity; allowMutations?: boolean; allowStatusChanges?:boolean; verifyFresh?:()=>Promise<boolean>;}
type Draft = {title: string; slug: string; collection_type: LegacyGroupIntent['collection_type']; description: string; category_subtype: string; purpose_label: string; recurring_cadence: string; suggested_amount_rwf: string; status: 'draft' | 'active'; reason: string; receiverEnabled: boolean; receiverLabel: string; receiverNetwork: 'mtn_momo' | 'airtel_money'; receiverRoute: string;};
const blank: Draft = {title: '', slug: '', collection_type: 'ikimina', description: '', category_subtype: '', purpose_label: '', recurring_cadence: '', suggested_amount_rwf: '', status: 'draft', reason: '', receiverEnabled: false, receiverLabel: '', receiverNetwork: 'mtn_momo', receiverRoute: ''};
function amount(value: string): number | null {if (!value.trim()) return null; if (!/^[1-9]\d*$/.test(value.trim())) throw new Error('Invalid amount'); const number = Number(value.trim()); if (!Number.isSafeInteger(number)) throw new Error('Invalid amount'); return number;}
function draftFor(group: LegacyGroupSnapshot): Draft {return {...blank, title: group.title, slug: group.slug, collection_type: group.type as Draft['collection_type'], description: group.description, category_subtype: group.category ?? '', purpose_label: group.purpose ?? '', recurring_cadence: group.cadence ?? '', suggested_amount_rwf: group.amount === null ? '' : String(group.amount)};}

/** Legacy group operations are opt-in until recovery and rollback are qualified. */
export function LegacyGroupPage({mode, id, request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, allowStatusChanges = false, verifyFresh}: LegacyGroupProps) {
  const providedKey = JSON.stringify([...new Set(permissions)].sort());
  const stableIdentity = usePendingIdentity(identity);
  const stablePermissions = useMemo<readonly string[]>(() => JSON.parse(providedKey) as string[], [providedKey]);
  const needed = mode === 'create' ? 'collections.create' : 'collections.manage';
  const allowed = financialModel === 'transaction_journals' && isId(actorId) && stableIdentity.id === actorId && stableIdentity.role === role && (mode === 'create' || role !== 'staff' && isId(id)) &&
    [needed, 'overview.read', ...(mode === 'edit' ? ['collections.read'] : role === 'staff' ? [] : ['collections.manage'])].every(value => stablePermissions.includes(value) && stableIdentity.permissions.includes(value));
  const canFindOwner = ['users.read'].every(value => stablePermissions.includes(value) && stableIdentity.permissions.includes(value));
  const scope = JSON.stringify([authorityKey, financialModel, mode, id]), current = useRef(scope), gate = useRef(allowMutations), statusGate=useRef(allowStatusChanges), fresh=useRef(verifyFresh), busy = useRef(false), lookupEpoch = useRef(0);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = allowMutations; return () => {gate.current = false;};}, [allowMutations]);
  useLayoutEffect(()=>{statusGate.current=allowStatusChanges;fresh.current=verifyFresh;return()=>{statusGate.current=false;};},[allowStatusChanges,verifyFresh]);
  const context = useMemo<LegacyGroupContext>(() => ({mode, groupId: id, request, identity: stableIdentity, actorId, permissions: stablePermissions, financialModel, enabled: allowMutations,
    isCurrent: () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now(), isEnabled: () => gate.current}), [mode, id, request, stableIdentity, actorId, stablePermissions, financialModel, allowMutations, scope]);
  const statusContext=useMemo<LegacyGroupStatusContext>(()=>({...context,enabled:allowStatusChanges,isEnabled:()=>statusGate.current,verifyFresh:()=>fresh.current?.()??Promise.resolve(false)}),[context,allowStatusChanges]);
  const [draft, setDraft] = useState<Draft>(blank), [group, setGroup] = useState<LegacyGroupSnapshot | null>(null), [search, setSearch] = useState(''), [owners, setOwners] = useState<LegacyOwner[]>([]), [selected, setSelected] = useState<LegacyOwner | null>(null);
  const [pendingState, setPendingState] = useState<LegacyGroupPending | null>(null), [loadedScope, setLoadedScope] = useState(''), [review, setReview] = useState<LegacyGroupIntent | null>(null), [reviewSource, setReviewSource] = useState<LegacyOwner | LegacyGroupSnapshot | null>(null), [revision, setRevision] = useState(''), [retryAllowed, setRetryAllowed] = useState(false), [confirmed, setConfirmed] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'searching' | 'success' | 'error'>('loading'), [message, setMessage] = useState(''), [savedId, setSavedId] = useState('');
  const [statusBlocked,setStatusBlocked]=useState(false);
  useEffect(() => {
    if (!allowed) return; let live = true; const epochRef = lookupEpoch;
    restoreLegacyGroupAction(context).then(async saved => {
      const source = saved.kind === 'ready' && allowMutations && mode === 'edit' ? await currentLegacyGroup(context) : null;
      if (live && context.isCurrent()) {setPendingState(saved); setGroup(source); if (source) setDraft(draftFor(source)); setLoadedScope(scope); setState('ready'); setMessage(saved.kind !== 'ready' ? 'A previous group request needs recovery. Check its original reference before continuing.' : !allowMutations ? 'Group changes are not enabled for this workspace.' : '');}
    }).catch(() => {if (live && context.isCurrent()) {setLoadedScope(scope); setState('error'); setMessage('The group or recovery data could not be verified.');}});
    return () => {live = false; epochRef.current++;};
  }, [allowed, allowMutations, context, scope, mode]);
  const pending = pendingState && pendingState.kind !== 'ready' ? pendingState : null, ready = pendingState?.kind === 'ready' ? pendingState : null;
  const findOwners = async (event: FormEvent) => {
    event.preventDefault(); if (!ready || !allowMutations || !canFindOwner || busy.current || !context.isCurrent()) return;
    const epoch = ++lookupEpoch.current; busy.current = true; setState('searching'); setMessage('');
    try {const rows = await searchLegacyOwners(context, search); if (context.isCurrent() && epoch === lookupEpoch.current) {setOwners(rows); setSelected(null); if (!rows.length) setMessage('No active owner matches were found.');}}
    catch {if (context.isCurrent() && epoch === lookupEpoch.current) setMessage('Active owners could not be verified.');}
    finally {busy.current = false; if (context.isCurrent() && epoch === lookupEpoch.current) setState('ready');}
  };
  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!ready || !allowMutations || busy.current || !context.isCurrent() || mode === 'edit' && !group) return;
    try {
      const base = {title: draft.title.trim(), collection_type: draft.collection_type, description: draft.description.trim(), category_subtype: draft.category_subtype.trim() || null, purpose_label: draft.purpose_label.trim() || null,
        recurring_cadence: draft.recurring_cadence || null, suggested_amount_rwf: amount(draft.suggested_amount_rwf), reason: draft.reason.trim()};
      const payload = mode === 'edit' ? {...base, expected_version: group!.version} : {...base, slug: draft.slug.trim(), visibility: 'private', is_platform_sponsored: false, status: draft.status,
        ...(selected ? {owner_user_id: selected.id} : {}), ...(draft.receiverEnabled ? {receiver: {label: draft.receiverLabel.trim(), network: draft.receiverNetwork, momo_number_or_code: draft.receiverRoute.trim()}} : {})};
      setReview(parseLegacyGroupIntent(payload, mode)); setReviewSource(mode === 'edit' ? group : selected); setRevision(ready.revision); setConfirmed(false); setMessage('');
    } catch {setMessage('Check the group fields and reason. An active group needs a selected active owner and a recorded receiver.');}
  };
  const send = async () => {
    if (!allowed || !allowMutations || !review || !confirmed || busy.current || !context.isCurrent() || pending?.kind === 'foreign' || pending?.kind === 'owned' && !retryAllowed) return;
    busy.current = true; setState('sending'); setMessage('');
    try {
      const result = pending?.kind === 'owned' ? await retryLegacyGroupAction(context, pending) : await submitLegacyGroupAction(context, review, reviewSource, revision);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPendingState(null); setSavedId(result.receipt.groupId); setState('success'); setMessage(mode === 'create' ? 'The group was recorded.' : 'Group changes were recorded.');}
      else if (result.status === 'existing') {setPendingState(result.pending); setState('ready'); setMessage('A previous group request needs recovery.');}
      else {setPendingState({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unconfirmed. Keep request reference ${result.requestKey} and check the original request.`); try {const saved = await restoreLegacyGroupAction(context); if (context.isCurrent()) setPendingState(saved);} catch { /* Keep the reference visible. */ }}
    } catch {if (context.isCurrent()) {setMessage('The group, owner or recovery data could not be verified. Check the original request before continuing.'); try {const saved = await restoreLegacyGroupAction(context); if (context.isCurrent()) setPendingState(saved);} catch {if (context.isCurrent()) {setPendingState(null); setState('error');}}}}
    finally {busy.current = false; if (context.isCurrent()) {setState(previous => previous === 'sending' ? 'ready' : previous); setReview(null); setConfirmed(false); setRetryAllowed(false);}}
  };
  const check = async () => {
    if (!pending || pending.kind !== 'owned' || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const result = await lookupLegacyGroupAction(context, pending); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPendingState(null); setSavedId(result.receipt.groupId); setState('success'); setMessage('The original group request was recorded.'); return;}
      if (result.status === 'not_found') {setRetryAllowed(result.retryAvailable && allowMutations); setMessage(result.retryAvailable && allowMutations ? 'No completed request was found. You may review the same request with its original reference.' : 'No completed request was found. Keep the reference; the original model or intent cannot be verified for a retry.');}
      else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh before another change.' : 'The original request is still pending. Check again before continuing.');
    } catch {if (context.isCurrent()) setMessage('The original request could not be verified. Keep its reference and check again.');}
    finally {busy.current = false; if (context.isCurrent()) setState(previous => previous === 'checking' ? 'ready' : previous);}
  };
  const reviewSame = async () => {
    if (!pending || pending.kind !== 'owned' || !pending.attempt || !retryAllowed || !allowMutations || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {const original = parseLegacyGroupIntent(pending.attempt.intent, mode), latest = mode === 'edit' ? await currentLegacyGroup(context) : original.owner_user_id ? await readLegacyOwner(context, original.owner_user_id) : null;
      if (context.isCurrent() && gate.current) {setReview(original); setReviewSource(latest); setConfirmed(false);}}
    catch {if (context.isCurrent()) {setRetryAllowed(false); setMessage('The current group or owner could not be verified. Check the original request again.');}}
    finally {busy.current = false; if (context.isCurrent()) setState(previous => previous === 'checking' ? 'ready' : previous);}
  };
  return <><PageHeader title={mode === 'create' ? 'Create group' : 'Edit group'} subtitle={mode === 'create' ? 'Record a private draft or an active group with an owner and receiver.' : 'Review the current group and its version before changing its details.'} actions={<Button type="button" onClick={() => navigate(mode === 'edit' && isId(id) ? `/admin/groups/${id}` : '/admin/groups')}>Back to {mode === 'edit' ? 'group' : 'groups'}</Button>} />
    {!allowed ? <ErrorState title="Group changes unavailable" message="Your account cannot use this group workflow in this workspace." /> : state === 'loading' || loadedScope !== scope ? <LoadingState label="Checking group recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Group recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/groups/${savedId}`)}>View group</Button></div></Card> : <Card><div className="core-detail">
      {message && <p role="alert">{message}</p>}
      {pending?.kind === 'foreign' && <p>Another account or session has an unresolved group request. The original account must check it.</p>}
      {pending?.kind === 'guarded' && <p>A group status request needs recovery below before editing group details.</p>}
      {pending?.kind === 'owned' && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.requestKey}</code></p>{!pending.attempt && <p>The original form is unavailable. Keep this reference and check the request.</p>}<Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section>}
      {!pending && !review && !statusBlocked && allowMutations && ready && <>
        {mode === 'create' && <><p>Select an active owner when needed. Active groups require an owner and a recorded receiver. Public or sponsored creation is unavailable in this workflow.</p>{canFindOwner ? <form className="core-search" onSubmit={event => void findOwners(event)}><label>Search group owner<input className="admin-input" value={search} maxLength={200} onChange={event => setSearch(event.target.value)} /></label><Button type="submit" disabled={state !== 'ready'}>Search owners</Button></form> : <p>Owner search is unavailable to your current account.</p>}
          {owners.length > 0 && <label>Group owner<select className="admin-input" value={selected?.id ?? ''} onChange={event => setSelected(owners.find(owner => owner.id === event.target.value) ?? null)}><option value="">No owner selected</option>{owners.map(owner => <option key={owner.id} value={owner.id}>{owner.displayName ?? 'Name not recorded'} · {owner.publicId}</option>)}</select></label>}</>}
        {mode === 'edit' && group && <p>Current version {group.version} · status {group.status} · visibility {group.visibility}. This form updates group details.</p>}
        <form className="core-edit-form" onSubmit={makeReview}><label>Group name<input className="admin-input" value={draft.title} minLength={3} maxLength={160} required onChange={event => setDraft({...draft, title: event.target.value})} /></label>
          {mode === 'create' && <label>Group slug<input className="admin-input" value={draft.slug} minLength={3} maxLength={100} required onChange={event => setDraft({...draft, slug: event.target.value})} /></label>}
          <label>Group type<select className="admin-input" value={draft.collection_type} onChange={event => setDraft({...draft, collection_type: event.target.value as Draft['collection_type']})}>{['ikimina', 'sport', 'church', 'wedding', 'other'].map(value => <option key={value} value={value}>{value}</option>)}</select></label>
          <label>Description<textarea className="admin-input" value={draft.description} maxLength={1000} onChange={event => setDraft({...draft, description: event.target.value})} /></label>
          <label>Category subtype<input className="admin-input" value={draft.category_subtype} maxLength={120} onChange={event => setDraft({...draft, category_subtype: event.target.value})} /></label>
          <label>Purpose<input className="admin-input" value={draft.purpose_label} maxLength={120} onChange={event => setDraft({...draft, purpose_label: event.target.value})} /></label>
          <label>Recurring cadence<select className="admin-input" value={draft.recurring_cadence} onChange={event => setDraft({...draft, recurring_cadence: event.target.value})}><option value="">Not recorded</option>{['weekly', 'monthly', 'quarterly', 'annually'].map(value => <option key={value} value={value}>{value}</option>)}</select></label>
          <label>Suggested amount (RWF)<input className="admin-input" inputMode="numeric" value={draft.suggested_amount_rwf} onChange={event => setDraft({...draft, suggested_amount_rwf: event.target.value})} /></label>
          {mode === 'create' && <><label>Group status<select className="admin-input" value={draft.status} onChange={event => setDraft({...draft, status: event.target.value as Draft['status']})}><option value="draft">Draft</option><option value="active">Active</option></select></label><label><input type="checkbox" checked={draft.receiverEnabled} onChange={event => setDraft({...draft, receiverEnabled: event.target.checked})} /> Record a receiver</label>
            {draft.receiverEnabled && <><label>Receiver name on MoMo<input className="admin-input" value={draft.receiverLabel} maxLength={120} onChange={event => setDraft({...draft, receiverLabel: event.target.value})} /></label><label>Receiver MoMo provider<select className="admin-input" value={draft.receiverNetwork} onChange={event => setDraft({...draft, receiverNetwork: event.target.value as Draft['receiverNetwork']})}><option value="mtn_momo">MTN MoMo</option><option value="airtel_money">Airtel Money</option></select></label><label>Receiver MoMo number or code<input className="admin-input" value={draft.receiverRoute} maxLength={12} onChange={event => setDraft({...draft, receiverRoute: event.target.value})} /></label></>}</>}
          <label>Reason for {mode === 'create' ? 'creation' : 'change'}<textarea className="admin-input" value={draft.reason} minLength={8} maxLength={1000} required onChange={event => setDraft({...draft, reason: event.target.value})} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review group</Button>
        </form></>}
      {review && allowMutations && <section><h2>Review group {mode === 'create' ? 'creation' : 'change'}</h2>{reviewSource && 'publicId' in reviewSource && <p>Current owner: {reviewSource.displayName ?? 'Name not recorded'} · {reviewSource.publicId}</p>}{reviewSource && 'slug' in reviewSource && <p>Current group: {reviewSource.title} · version {reviewSource.version} · {reviewSource.status}.</p>}
        <dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{key === 'receiver' && value && typeof value === 'object' ? `${String(value.label)} · ${String(value.network)} · ${String(value.momo_number_or_code)}` : value === null || value === '' ? 'Not recorded' : String(value)}</dd></div>)}</dl><p>{pending ? 'The same original request will be used; it may make this change if the earlier request did not commit.' : 'Review the group and recorded owner or receiver before confirming.'} Recorded details do not establish provider identity.</p><label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} /> I reviewed the group details and reason.</label><Button type="button" disabled={state !== 'ready'} onClick={() => {setReview(null); setConfirmed(false);}}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !confirmed} onClick={() => void send()}>{pending ? 'Confirm same request' : 'Confirm group'}</Button></section>}
    </div></Card>}
    {mode==='edit'&&allowed&&loadedScope===scope&&state==='ready'&&<LegacyGroupStatusControls key={JSON.stringify([scope,allowStatusChanges])} context={statusContext} enabled={allowStatusChanges} onBlocked={setStatusBlocked} onRecorded={()=>{setSavedId(id!);setMessage('The group status change was recorded.');setState('success');}}/>}
  </>;
}
