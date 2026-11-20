import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, isId, isObject, isSafeCount, parseCoreRow } from './contracts';
import { canonicalRequestId, clearPending, readPending, retainPending } from './pendingAttempt';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { DataRow, FeatureAccess } from './types';
import { LegacyGroupPage } from './LegacyGroupPage';
import './core.css';

/** Canonical creation and recovery. Writes remain opt-in pending release qualification. */
export interface GroupCreateProps extends FeatureAccess {
  identity: PendingIdentity;
  allowMutations?: boolean;
  verifyFresh: () => Promise<boolean>;
}

const FAMILY = 'operating-creategroup', RESOURCE = 'new', PERMISSION = 'collections.create';
const GROUP_TYPES = ['ikimina', 'sport', 'church', 'wedding', 'other'] as const;
const BODY_FIELDS = ['title', 'slug', 'collection_type', 'visibility', 'description', 'purpose_label', 'status', 'owner_user_id', 'receiver', 'is_platform_sponsored', 'reason'];
type Draft = { title: string; slug: string; collection_type: string; visibility: 'private' | 'public_approved'; description: string; purpose_label: string; receiverLabel: string; receiverNetwork: string; receiverRoute: string; reason: string };
const initialDraft: Draft = { title: '', slug: '', collection_type: 'ikimina', visibility: 'private', description: '', purpose_label: '', receiverLabel: '', receiverNetwork: 'mtn_momo', receiverRoute: '', reason: '' };

function validatedIntent(value: unknown, canPublish: boolean): Record<string, unknown> {
  if (!isObject(value) || Object.keys(value).length !== BODY_FIELDS.length || !BODY_FIELDS.every(key => key in value) ||
      typeof value.title !== 'string' || value.title.trim().length < 3 || value.title.length > 160 || containsControl(value.title) ||
      typeof value.slug !== 'string' || value.slug.length < 3 || value.slug.length > 100 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value.slug) ||
      typeof value.collection_type !== 'string' || !GROUP_TYPES.includes(value.collection_type as typeof GROUP_TYPES[number]) ||
      typeof value.description !== 'string' || value.description.length > 2000 ||
      !(value.purpose_label === null || typeof value.purpose_label === 'string' && value.purpose_label.length <= 120) ||
      value.status !== 'active' || !isId(value.owner_user_id) ||
      !['private', 'public_approved'].includes(String(value.visibility)) || value.is_platform_sponsored !== (value.visibility === 'public_approved') ||
      (value.visibility === 'public_approved' && !canPublish) ||
      typeof value.reason !== 'string' || value.reason.trim().length < 8 || value.reason.length > 500 ||
      !isObject(value.receiver) || Object.keys(value.receiver).length !== 3 ||
      typeof value.receiver.label !== 'string' || value.receiver.label.trim().length < 2 || value.receiver.label.length > 120 ||
      !['mtn_momo', 'airtel_money'].includes(String(value.receiver.network)) || typeof value.receiver.momo_number_or_code !== 'string' ||
      !(value.visibility === 'public_approved' ? /^(?:07[2389]\d{7}|\+?2507[2389]\d{7}|\d{4,12})$/ : /^(?:07[2389]\d{7}|\+?2507[2389]\d{7})$/).test(value.receiver.momo_number_or_code)) {
    throw new Error('The group details could not be verified.');
  }
  return value;
}

export function activeOwner(row: unknown): DataRow {
  const owner = parseCoreRow('users', 'canonical_evidence_ledger', row);
  if (owner.status !== 'active' || owner.collect_user_id !== owner.id || !['app', 'direct'].includes(String(owner.member_type)) ||
      !isSafeCount(owner.version) || owner.version < 1 || !owner.display_name_recorded) throw new Error('Owner unavailable');
  return owner;
}
function ownerResource(data: Record<string, unknown>, id: unknown, actor: string): DataRow {
  if (!isId(id) || data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'users' ||
      data.current_actor_id !== actor || !isObject(data.resource) || data.resource.id !== id) throw new Error('Owner unavailable');
  return activeOwner(data.resource);
}
function sameOwner(left: DataRow, right: DataRow): boolean {
  return ['id', 'version', 'public_id', 'display_name', 'momo_provider', 'momo_number', 'momo_pay_code'].every(key => left[key] === right[key]);
}
export function parseOwners(value: unknown): DataRow[] {
  if (!isObject(value) || Object.keys(value).length !== 6 || value.contract_version !== 2 || value.model !== 'canonical_evidence_ledger' ||
      value.kind !== 'users' || value.group_id !== null || !Array.isArray(value.rows) || !isSafeCount(value.total) ||
      value.rows.length !== Math.min(100, value.total)) throw new Error('Owner lookup unavailable');
  const result = value.rows.map(row => {
    if (!isObject(row) || typeof row.label !== 'string' || !row.label.trim() || row.label !== row.name || row.label !== row.display_name) throw new Error('Owner lookup unavailable');
    return activeOwner(row);
  });
  if (new Set(result.map(row => row.id)).size !== result.length) throw new Error('Owner lookup unavailable');
  return result;
}
async function validReceipt(value: unknown, principalId: string, key: string): Promise<boolean> {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' && value.resource_type === 'groups' &&
    isId(value.resource_id) && value.version === 1 && value.request_id === await canonicalRequestId(principalId, key);
}

export function GroupCreatePage(props: GroupCreateProps) {
  return props.financialModel === 'transaction_journals' ? <LegacyGroupPage {...props} mode="create" /> : <CanonicalGroupCreatePage {...props} />;
}

function CanonicalGroupCreatePage({ request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh }: GroupCreateProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const allowed = financialModel === 'canonical_evidence_ledger' && permissions.includes(PERMISSION) && stableIdentity.permissions.includes(PERMISSION) &&
    stableIdentity.id === actorId && stableIdentity.role === role && typeof principalId === 'string' && isId(principalId);
  const canPublish = role !== 'staff' && ['collections.manage', 'receivers.manage'].every(permission => permissions.includes(permission) && stableIdentity.permissions.includes(permission));
  const [draft, setDraft] = useState<Draft>(initialDraft);
  const [search, setSearch] = useState('');
  const [owners, setOwners] = useState<DataRow[]>([]);
  const [selected, setSelected] = useState<DataRow | null>(null);
  const [pending, setPending] = useState<PendingAttempt | null>(null);
  const [review, setReview] = useState<Record<string, unknown> | null>(null);
  const [retryAllowed, setRetryAllowed] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'searching' | 'sending' | 'checking' | 'success' | 'error'>('loading');
  const [message, setMessage] = useState('');
  const [loadedScope, setLoadedScope] = useState('');
  const [createdId, setCreatedId] = useState('');
  const current = useRef(authorityKey), writeGate = useRef(allowMutations), busy = useRef(false), lookupEpoch = useRef(0);
  useLayoutEffect(() => { current.current = authorityKey; return () => { current.current = ''; }; }, [authorityKey]);
  useLayoutEffect(() => { writeGate.current = allowMutations; return () => { writeGate.current = false; }; }, [allowMutations]);
  const active = () => current.current === authorityKey && Date.parse(stableIdentity.expiresAt) > Date.now();
  const scope = JSON.stringify([authorityKey, financialModel]);
  useEffect(() => {
    if (!allowed) return;
    let live = true; const lookupVersion = lookupEpoch;
    readPending(stableIdentity, FAMILY, RESOURCE).then(value => {
      if (!live || current.current !== authorityKey) return;
      if (value && value.permission !== PERMISSION) throw new Error('Invalid pending request');
      setPending(value); setLoadedScope(scope); setState('ready');
      if (value) setMessage('A previous group creation needs recovery. Check its original request before continuing.');
      else if (!allowMutations) setMessage('Group creation is not enabled for this workspace.');
    }).catch(() => { if (live) { setLoadedScope(scope); setState('error'); setMessage('The recovery record could not be verified.'); } });
    return () => { live = false; lookupVersion.current++; };
  }, [allowed, allowMutations, stableIdentity, authorityKey, scope]);

  const searchOwners = async (event: FormEvent) => {
    event.preventDefault();
    const term = search.trim();
    if (!allowMutations || !permissions.includes('users.read') || !stableIdentity.permissions.includes('users.read') || !active() || pending || busy.current || term.length > 200 || containsControl(term)) return;
    const epoch = ++lookupEpoch.current;
    setState('searching'); setMessage(''); setSelected(null);
    try {
      const query = new URLSearchParams({ kind: 'users', search: term, limit: '100' });
      const rows = parseOwners(await request(`operations/lookups?${query.toString()}`));
      if (!active() || epoch !== lookupEpoch.current) return;
      setOwners(rows); if (!rows.length) setMessage('No active owners found.');
    } catch { if (active() && epoch === lookupEpoch.current) { setOwners([]); setMessage('The owner search could not be verified.'); } }
    finally { if (active() && epoch === lookupEpoch.current) setState('ready'); }
  };
  const makeReview = (event: FormEvent) => {
    event.preventDefault();
    if (!allowMutations || !active() || !selected || pending || state !== 'ready') return;
    try {
      const body = validatedIntent({ title: draft.title.trim(), slug: draft.slug.trim(), collection_type: draft.collection_type,
        visibility: draft.visibility, description: draft.description.trim(), purpose_label: draft.purpose_label.trim() || null, status: 'active', owner_user_id: selected.id,
        receiver: { label: draft.receiverLabel.trim(), network: draft.receiverNetwork, momo_number_or_code: draft.receiverRoute.trim() },
        is_platform_sponsored: draft.visibility === 'public_approved', reason: draft.reason.trim() }, canPublish);
      setMessage(''); setReview(body);
    } catch { setMessage('Check the group, owner, recorded receiver and reason before continuing.'); }
  };
  const send = async (intent: Record<string, unknown>, key: string) => {
    if (!allowed || !allowMutations || !principalId || !active() || busy.current || !permissions.includes('users.read') || !stableIdentity.permissions.includes('users.read')) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null;
    try {
      const body = validatedIntent(intent, canPublish);
      const owner = ownerResource(await request(`operations/users/${body.owner_user_id}`), body.owner_user_id, actorId);
      if (!selected || !sameOwner(selected, owner)) throw new Error('Owner changed');
      if (!active() || !writeGate.current || !await verifyFresh() || !active() || !writeGate.current) throw new Error('Verification required');
      retained = await retainPending(stableIdentity, FAMILY, RESOURCE, key, PERMISSION, body);
      if (!active() || !writeGate.current) return;
      setPending(retained); setRetryAllowed(false);
      const receipt = await request('operations/groups', { method: 'POST', body, idempotencyKey: key });
      if (!active()) return;
      if (!await validReceipt(receipt, principalId, key)) throw new Error('Invalid receipt');
      await clearPending(stableIdentity, FAMILY, RESOURCE, key);
      if (!active()) return;
      setPending(null); setReview(null); setCreatedId(receipt.resource_id as string); setState('success'); setMessage('The group was created.');
    } catch {
      if (!active()) return;
      const existing = retained ?? await readPending(stableIdentity, FAMILY, RESOURCE).catch(() => null);
      setPending(existing); setReview(null); setState('ready');
      setMessage(existing ? 'The result is unconfirmed. Check the original request before creating another group.' : 'The owner or verification could not be confirmed. No group was submitted.');
    } finally { busy.current = false; }
  };
  const check = async () => {
    if (!pending || !principalId || !active() || busy.current) return;
    if (!permissions.includes('overview.read') || !permissions.includes('account.manage')) { setMessage('Your account cannot check request history. Contact an authorized administrator.'); return; }
    busy.current = true; const original = pending; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const data = await request(`operations/requests/${original.request_key}`);
      if (!active()) return;
      if (data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || !['not_found', 'unconfirmed', 'cancelled', 'succeeded'].includes(String(data.status))) throw new Error('Invalid lookup');
      if (data.status === 'not_found') {
        if (Object.keys(data).length !== 3) throw new Error('Invalid lookup');
        let retryable = false; try { validatedIntent(original.intent, canPublish); retryable = allowMutations; } catch { /* Other retained intents may be checked, but not recreated. */ }
        setRetryAllowed(retryable); setMessage(retryable ? 'No completed request was found. You may check again or review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.');
      } else {
        if (Object.keys(data).length !== 5 || data.request_id !== await canonicalRequestId(principalId, original.request_key)) throw new Error('Invalid lookup');
        if (data.status === 'succeeded') {
          if (!await validReceipt(data.receipt, principalId, original.request_key)) throw new Error('Invalid receipt');
          await clearPending(stableIdentity, FAMILY, RESOURCE, original.request_key);
          if (!active()) return;
          setPending(null); setCreatedId((data.receipt as Record<string, unknown>).resource_id as string); setState('success'); setMessage('The original group creation was recorded.'); return;
        }
        if (data.receipt !== null) throw new Error('Invalid receipt');
        if (data.status === 'cancelled') {
          await clearPending(stableIdentity, FAMILY, RESOURCE, original.request_key);
          if (!active()) return;
          setPending(null); setState('error'); setMessage('The original request was cancelled. Reopen creation to start a new request.'); return;
        }
        setMessage('The request is still unconfirmed. Check again before continuing.');
      }
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const reviewSame = async () => {
    if (!pending || !retryAllowed || !allowMutations || busy.current || !active() || !permissions.includes('users.read') || !stableIdentity.permissions.includes('users.read')) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      const original = validatedIntent(pending.intent, canPublish);
      const owner = ownerResource(await request(`operations/users/${original.owner_user_id}`), original.owner_user_id, actorId);
      if (!active() || !writeGate.current) return;
      setSelected(owner); setReview(original); setRetryAllowed(false);
    } catch { if (active()) { setRetryAllowed(false); setMessage('The owner could not be verified. Check the original request again.'); } }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };

  return <>
    <PageHeader title="Create group" subtitle="Select the recorded owner and MoMo receiver for the new group." actions={<Button type="button" onClick={() => navigate('/admin/groups')}>Back to groups</Button>} />
    {!allowed ? <ErrorState title="Creation unavailable" message={financialModel === 'transaction_journals' ? 'This workspace uses the legacy financial model. Its group creation workflow is not available here yet.' : 'Your account cannot create groups in this workspace.'} /> :
      state === 'loading' || loadedScope !== scope ? <LoadingState label="Checking recovery" /> : state === 'error' ? <ErrorState message={message} /> :
      state === 'success' ? <Card><div className="core-detail" role="status"><h2>Group created</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/groups/${createdId}`)}>View group</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending ? <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section> : null}
        {!pending && !review && allowMutations && <>
          {!permissions.includes('users.read') ? <ErrorState title="Owner search unavailable" message="Your account needs permission to view users before selecting a group owner." /> : <form className="core-search" onSubmit={event => void searchOwners(event)}><label>Search group owner<input className="admin-input" value={search} maxLength={200} onChange={event => setSearch(event.target.value)} /></label><Button type="submit" disabled={state !== 'ready'}>Search owners</Button></form>}
          {owners.length > 0 && <label>Group owner<select className="admin-input" value={selected?.id ?? ''} onChange={event => setSelected(owners.find(owner => owner.id === event.target.value) ?? null)}><option value="">Select owner</option>{owners.map(owner => <option key={owner.id} value={owner.id}>{String(owner.display_name)} · {owner.public_id as string}</option>)}</select></label>}
          <form className="core-edit-form" onSubmit={makeReview}>
            <label>Group name<input className="admin-input" value={draft.title} maxLength={160} required onChange={event => setDraft({ ...draft, title: event.target.value })} /></label>
            <label>Group slug<input className="admin-input" value={draft.slug} maxLength={100} required onChange={event => setDraft({ ...draft, slug: event.target.value })} /></label>
            <label>Group type<select className="admin-input" value={draft.collection_type} onChange={event => setDraft({ ...draft, collection_type: event.target.value })}>{GROUP_TYPES.map(type => <option value={type} key={type}>{type}</option>)}</select></label>
            {canPublish && <label>Visibility<select className="admin-input" value={draft.visibility} onChange={event => setDraft({ ...draft, visibility: event.target.value as Draft['visibility'] })}><option value="private">Private</option><option value="public_approved">Public · Collect sponsored</option></select></label>}
            <label>Description<textarea className="admin-input" value={draft.description} maxLength={2000} onChange={event => setDraft({ ...draft, description: event.target.value })} /></label>
            <label>Purpose<input className="admin-input" value={draft.purpose_label} maxLength={120} onChange={event => setDraft({ ...draft, purpose_label: event.target.value })} /></label>
            <label>Receiver name on MoMo<input className="admin-input" value={draft.receiverLabel} maxLength={120} required onChange={event => setDraft({ ...draft, receiverLabel: event.target.value })} /></label>
            <label>Receiver MoMo provider<select className="admin-input" value={draft.receiverNetwork} onChange={event => setDraft({ ...draft, receiverNetwork: event.target.value })}><option value="mtn_momo">MTN MoMo</option><option value="airtel_money">Airtel Money</option></select></label>
            <label>Receiver MoMo number{draft.visibility === 'public_approved' ? ' or merchant code' : ''}<input className="admin-input" value={draft.receiverRoute} maxLength={13} required onChange={event => setDraft({ ...draft, receiverRoute: event.target.value })} /></label>
            <label>Reason for creation<textarea className="admin-input" value={draft.reason} minLength={8} maxLength={500} required onChange={event => setDraft({ ...draft, reason: event.target.value })} /></label>
            <p>Public groups are Collect sponsored and their receiver becomes permanently locked. Recorded details do not confirm provider settlement or identity.</p>
            <Button type="submit" variant="primary" disabled={state !== 'ready' || !selected}>Review group</Button>
          </form>
        </>}
        {review && allowMutations && <section><h2>Review group creation</h2>{selected && selected.id === review.owner_user_id && <p>Selected owner: {String(selected.display_name)} · {String(selected.public_id)}</p>}<dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{key === 'receiver' && isObject(value) ? `${String(value.label)} · ${String(value.network)} · ${String(value.momo_number_or_code)}` : value === null ? 'Not recorded' : String(value)}</dd></div>)}</dl><p>Confirm the recorded owner and receiver. This does not confirm provider settlement or identity.</p><Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready'} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No group was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm group'}</Button></section>}
      </div></Card>}
  </>;
}
