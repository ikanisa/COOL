import { useEffect, useLayoutEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, isId, isObject, isSafeCount } from './contracts';
import { clearPending, readPending, retainPending } from './pendingAttempt';
import {usePendingIdentity} from './usePendingIdentity';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { FeatureAccess } from './types';
import './core.css';

export interface LegacyPayeeCreateProps extends FeatureAccess {
  groupId: string;
  identity: PendingIdentity;
  allowMutations?: boolean;
}
const FAMILY = 'operating-createpayee', RESOURCE = 'new', PERMISSION = 'receivers.manage';
const FIELDS = ['group_id', 'label', 'network', 'momo_number_or_code', 'status', 'reason'];
interface Group { id: string; title: string; status: string; version: number; visibility: string }
function intent(value: unknown): Record<string, unknown> {
  if (!isObject(value) || Object.keys(value).length !== FIELDS.length || !FIELDS.every(key => key in value) || !isId(value.group_id) ||
      typeof value.label !== 'string' || value.label.trim().length < 2 || value.label.length > 120 || containsControl(value.label) ||
      !['mtn_momo', 'airtel_money'].includes(String(value.network)) || typeof value.momo_number_or_code !== 'string' || !/^\d{4,12}$/.test(value.momo_number_or_code) ||
      !['active', 'inactive'].includes(String(value.status)) || typeof value.reason !== 'string' || value.reason.trim().length < 8 || value.reason.length > 1000) throw new Error('Invalid payee');
  return value;
}
function group(data: Record<string, unknown>, id: string, actor: string): Group {
  if (data.contract_version !== undefined || data.model !== undefined || data.resource_type !== 'groups' || data.current_actor_id !== actor || data.can_manage !== true ||
      !isObject(data.resource) || data.resource.id !== id || typeof data.resource.title !== 'string' || data.resource.title.trim().length < 3 ||
      !['draft', 'active', 'suspended'].includes(String(data.resource.status)) || !isSafeCount(data.resource.version) || data.resource.version < 1 ||
      data.resource.country_code !== 'RW' || data.resource.currency !== 'RWF' || !['private', 'public_approved'].includes(String(data.resource.visibility))) throw new Error('Group unavailable');
  return { id, title: data.resource.title, status: String(data.resource.status), version: data.resource.version, visibility: String(data.resource.visibility) };
}
function receipt(value: unknown): value is Record<string, unknown> {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' && value.resource_type === 'payees' &&
    isId(value.request_id) && isId(value.resource_id) && value.version === 1;
}
function sameReceipt(left: Record<string, unknown>, right: Record<string, unknown>): boolean {
  return ['request_id', 'resource_type', 'resource_id', 'version', 'status'].every(key => left[key] === right[key]);
}
function outcome(value: unknown): { status: 'not_found' | 'pending' | 'failed' | 'succeeded'; receipt: Record<string, unknown> | null } {
  if (!isObject(value) || value.contract_version !== undefined || value.model !== undefined) throw new Error('Invalid lookup');
  if (value.status === 'not_found' && Object.keys(value).length === 1) return { status: 'not_found', receipt: null };
  if (!['pending', 'failed', 'succeeded'].includes(String(value.status)) || Object.keys(value).length !== 3 || !isId(value.request_id)) throw new Error('Invalid lookup');
  if (value.status === 'succeeded') {
    if (!receipt(value.receipt) || value.receipt.request_id !== value.request_id) throw new Error('Invalid receipt');
    return { status: 'succeeded', receipt: value.receipt };
  }
  if (value.receipt !== null) throw new Error('Invalid lookup');
  return { status: value.status as 'pending' | 'failed', receipt: null };
}
async function withLock<T>(name: string, operation: () => Promise<T>): Promise<T> {
  if (!navigator.locks) throw new Error('A protected request lock is unavailable.');
  return navigator.locks.request(name, { ifAvailable: true }, lock => { if (!lock) throw new Error('Another request is in progress.'); return operation(); });
}

/** Legacy distinct-payee creation; disabled pending release and rollback qualification. */
export function LegacyPayeeCreatePage({ groupId, request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, allowMutations = false }: LegacyPayeeCreateProps) {
  const stableIdentity = usePendingIdentity(identity);
  const allowed = financialModel === 'transaction_journals' && role !== 'staff' && isId(groupId) && isId(actorId) &&
    permissions.includes(PERMISSION) && stableIdentity.permissions.includes(PERMISSION) && stableIdentity.id === actorId && stableIdentity.role === role;
  const canWrite = allowed && ['collections.read', 'overview.read'].every(permission => permissions.includes(permission) && stableIdentity.permissions.includes(permission));
  const scope = JSON.stringify([authorityKey, groupId, financialModel]), current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const active = () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now();
  const [source, setSource] = useState<Group | null>(null), [label, setLabel] = useState(''), [network, setNetwork] = useState('mtn_momo'), [route, setRoute] = useState(''), [status, setStatus] = useState('active'), [reason, setReason] = useState('');
  const [pending, setPending] = useState<PendingAttempt | null>(null), [review, setReview] = useState<Record<string, unknown> | null>(null), [retryAllowed, setRetryAllowed] = useState(false), [acknowledged, setAcknowledged] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading');
  const [scopeLoaded, setScopeLoaded] = useState(''), [message, setMessage] = useState(''), [createdId, setCreatedId] = useState('');
  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController(); let live = true;
    readPending(stableIdentity, FAMILY, RESOURCE).then(async saved => {
      if (saved && (saved.permission !== PERMISSION || !isId(saved.intent.group_id))) throw new Error('Invalid recovery');
      if (saved) intent(saved.intent);
      const source = !saved && allowMutations && canWrite ? group(await request(`operations/groups/${groupId}`, { signal: controller.signal }), groupId, actorId) : null;
      if (!live || current.current !== scope) return;
      setPending(saved); setSource(source); setScopeLoaded(scope); setState('ready');
      if (saved) setMessage('A previous receiver creation needs recovery. Check its original request before continuing.');
      else if (!allowMutations) setMessage('Receiver creation is not enabled for this workspace.');
      else if (!canWrite) setMessage('Group and request-history read permissions are required for this action.');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('The group or recovery record could not be verified.'); } });
    return () => { live = false; controller.abort(); };
  }, [allowed, allowMutations, canWrite, stableIdentity, request, groupId, actorId, scope]);
  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || !canWrite || !source || pending || state !== 'ready' || !active()) return;
    try { setReview(intent({ group_id: groupId, label: label.trim(), network, momo_number_or_code: route.trim(), status, reason: reason.trim() })); setAcknowledged(false); setMessage(''); }
    catch { setMessage('Check the recorded receiver name, network, numeric MoMo route and reason.'); }
  };
  const send = async (body: Record<string, unknown>, key: string) => {
    if (!canWrite || !allowMutations || !source || !acknowledged || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null, dispatched = false;
    try {
      const checked = intent(body); if (checked.group_id !== groupId) throw new Error('Different group');
      await withLock(`collect-admin-legacy-payee:${actorId}:${groupId}`, async () => {
        if (pending) {
          const prior = outcome(await request(`operations/requests/${key}`));
          if (!active() || !gate.current) return;
          if (prior.status === 'succeeded' && prior.receipt) {
            await clearPending(stableIdentity, FAMILY, RESOURCE, key); if (!active()) return;
            setPending(null); setReview(null); setCreatedId(String(prior.receipt.resource_id)); setState('success'); setMessage('The original receiver creation was recorded.'); return;
          }
          if (prior.status !== 'not_found') throw new Error('Original request unresolved');
        }
        const latest = group(await request(`operations/groups/${groupId}`), groupId, actorId);
        if (JSON.stringify(latest) !== JSON.stringify(source) || !active() || !gate.current) throw new Error('Group changed');
        if (!pending && await readPending(stableIdentity, FAMILY, RESOURCE)) throw new Error('Original request needs review');
        retained = await retainPending(stableIdentity, FAMILY, RESOURCE, key, PERMISSION, checked);
        if (!active() || !gate.current) return;
        setPending(retained); setRetryAllowed(false); dispatched = true;
        const direct = await request('operations/payees', { method: 'POST', body: checked, idempotencyKey: key });
        if (!active() || !receipt(direct)) throw new Error('Invalid receipt');
        const original = outcome(await request(`operations/requests/${key}`));
        if (!active() || original.status !== 'succeeded' || !original.receipt || !sameReceipt(original.receipt, direct)) throw new Error('Unverified receipt');
        await clearPending(stableIdentity, FAMILY, RESOURCE, key); if (!active()) return;
        setPending(null); setReview(null); setCreatedId(String(direct.resource_id)); setState('success'); setMessage('The recorded receiver was created.');
      });
    } catch {
      if (!active()) return;
      let storageFailed = false; const saved = retained ?? await readPending(stableIdentity, FAMILY, RESOURCE).catch(() => { storageFailed = true; return null; });
      setPending(saved); setReview(null); setAcknowledged(false);
      if (storageFailed || dispatched && !saved) { setState('error'); setMessage('Recovery data could not be verified. Check the original request before another change.'); }
      else { setState('ready'); setMessage(saved ? 'The result is unconfirmed. Check the original request before creating another receiver.' : 'The group or recovery storage could not be verified. No receiver was submitted.'); }
    } finally { busy.current = false; }
  };
  const check = async () => {
    if (!pending || !active() || busy.current) return;
    if (!permissions.includes('overview.read')) { setMessage('Your account cannot check request history. Contact an authorized administrator.'); return; }
    busy.current = true; const original = pending; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const result = outcome(await request(`operations/requests/${original.request_key}`));
      if (!active()) return;
      if (result.status === 'succeeded' && result.receipt) {
        await clearPending(stableIdentity, FAMILY, RESOURCE, original.request_key); if (!active()) return;
        setPending(null); setCreatedId(String(result.receipt.resource_id)); setState('success'); setMessage('The original receiver creation was recorded.'); return;
      }
      if (result.status === 'not_found') {
        let retryable = false; try { const saved = intent(original.intent); retryable = allowMutations && canWrite && saved.group_id === groupId; } catch { /* Other original requests can be checked, but not recreated. */ }
        setRetryAllowed(retryable); setMessage(retryable ? 'No completed request was found. You may check again or review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.');
      } else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh the record.' : 'The request is still pending. Check again before continuing.');
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const reviewSame = async () => {
    if (!pending || !retryAllowed || !allowMutations || !canWrite || busy.current || !active()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      const original = intent(pending.intent); if (original.group_id !== groupId) throw new Error('Different group');
      const latest = group(await request(`operations/groups/${groupId}`), groupId, actorId);
      if (!active() || !gate.current) return;
      setSource(latest); setReview(original); setRetryAllowed(false); setAcknowledged(false);
    } catch { if (active()) { setRetryAllowed(false); setMessage('The current group could not be verified. Check the original request again.'); } }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  return <>
    <PageHeader title="Add recorded receiver" subtitle="Create a receiver for this legacy-model group." actions={<Button type="button" onClick={() => navigate(isId(groupId) ? `/admin/groups/${groupId}` : '/admin/groups')}>Back to group</Button>} />
    {!allowed ? <ErrorState title="Creation unavailable" message={financialModel === 'canonical_evidence_ledger' ? 'Separate receiver creation is unavailable for the canonical model. Use the existing group receiver workflow.' : 'Your account cannot create receivers in this workspace.'} /> :
      state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Receiver recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/payees/${createdId}`)}>View receiver</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p><p>Group: {String(pending.intent.group_id)}</p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && canWrite && source && <form className="core-edit-form" onSubmit={makeReview}><p>Group: {source.title} · {source.status}. A recorded MoMo route cannot be changed after creation.</p><label>Receiver label<input className="admin-input" value={label} maxLength={120} required onChange={event => setLabel(event.target.value)} /></label><label>MoMo network<select className="admin-input" value={network} onChange={event => setNetwork(event.target.value)}><option value="mtn_momo">MTN MoMo</option><option value="airtel_money">Airtel Money</option></select></label><label>MoMo number or merchant code<input className="admin-input" value={route} maxLength={12} required onChange={event => setRoute(event.target.value)} /></label><label>Receiver status<select className="admin-input" value={status} onChange={event => setStatus(event.target.value)}><option value="active">Active</option><option value="inactive">Inactive</option></select></label><label>Reason for creation<textarea className="admin-input" value={reason} minLength={8} maxLength={1000} required onChange={event => setReason(event.target.value)} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review receiver</Button></form>}
        {review && source && allowMutations && canWrite && <section><h2>Review receiver creation</h2><p>Group: {source.title} · {source.status} · version {source.version}.</p><dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{String(value)}</dd></div>)}</dl><p>The recorded MoMo route is immutable after creation; this does not verify provider identity.</p><label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed the group and recorded receiver details.</label><Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); setAcknowledged(false); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !acknowledged} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No receiver was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm receiver'}</Button></section>}
      </div></Card>}
  </>;
}
