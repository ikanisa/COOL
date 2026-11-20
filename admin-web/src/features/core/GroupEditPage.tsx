import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { isId, isObject, isSafeCount, parseCoreRow } from './contracts';
import { canonicalRequestId, clearPending, readPending, retainPending } from './pendingAttempt';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { FeatureAccess } from './types';
import { LegacyGroupPage } from './LegacyGroupPage';
import './core.css';

/** The caller must only enable writes after backend and old-tab/rollback qualification. */
export interface GroupEditProps extends FeatureAccess {
  id: string;
  identity: PendingIdentity;
  allowMutations?: boolean;
  allowStatusChanges?: boolean;
  verifyFresh: () => Promise<boolean>;
}

const FAMILY = 'operating-updategroup';
const PERMISSION = 'collections.manage';
const TYPES = ['ikimina', 'sport', 'church', 'wedding', 'other'] as const;
const STATUSES = ['active', 'suspended', 'archived'] as const;
const BODY_FIELDS = ['collection_type', 'description', 'expected_version', 'purpose_label', 'reason', 'status', 'title'];
const PUBLICATION_FIELDS = ['visibility', 'is_platform_sponsored'];

type GroupDraft = { title: string; collection_type: string; description: string; purpose_label: string; status: string; reason: string };
type PublicationProof = { ownerId: string; receiver: string; network: string; route: string };

function validatedBody(value: unknown, canPublish = false): Record<string, unknown> {
  if (!isObject(value)) throw new Error('Check the group details and reason before continuing.');
  const publication = PUBLICATION_FIELDS.some(key => key in value);
  if (Object.keys(value).length !== BODY_FIELDS.length + (publication ? PUBLICATION_FIELDS.length : 0) || !BODY_FIELDS.every(key => key in value) ||
      (publication && (!canPublish || value.visibility !== 'public_approved' || value.is_platform_sponsored !== true)) ||
      typeof value.title !== 'string' || value.title.trim().length < 3 || value.title.length > 160 ||
      typeof value.collection_type !== 'string' || !TYPES.includes(value.collection_type as typeof TYPES[number]) ||
      typeof value.description !== 'string' || value.description.length > 2000 ||
      !(value.purpose_label === null || typeof value.purpose_label === 'string' && value.purpose_label.length <= 120) ||
      typeof value.status !== 'string' || !STATUSES.includes(value.status as typeof STATUSES[number]) ||
      typeof value.reason !== 'string' || value.reason.trim().length < 8 || value.reason.length > 500 ||
      !isSafeCount(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER) {
    throw new Error('Check the group details and reason before continuing.');
  }
  return value;
}

function publicationProof(data: Record<string, unknown>, resource: Record<string, unknown>, id: string): PublicationProof | null {
  if (!isObject(data.related) || !Array.isArray(data.related.payees) || data.related.payees.length !== 1 ||
      !isObject(data.related_pages) || !isObject(data.related_pages.payees) || data.related_truncated !== false ||
      data.related_pages.payees.total !== 1 || data.related_pages.payees.offset !== 0 || data.related_pages.payees.next_offset !== null ||
      !isSafeCount(data.related_pages.payees.limit) || data.related_pages.payees.limit < 1 || data.related_pages.payees.limit > 100 ||
      !isId(resource.owner_user_id) || !['private', 'public_pending'].includes(String(resource.visibility))) return null;
  try {
    const receiver = parseCoreRow('payees', 'canonical_evidence_ledger', data.related.payees[0]);
    if (receiver.id !== id || receiver.group_id !== id || receiver.version !== resource.version || receiver.status !== 'active' ||
        receiver.receiver_basis !== 'operator_recorded' || typeof receiver.momo_number_or_code !== 'string' ||
        !/^(?:07[2389]\d{7}|\+?2507[2389]\d{7}|\d{4,12})$/.test(receiver.momo_number_or_code)) return null;
    return { ownerId: resource.owner_user_id, receiver: receiver.title, network: String(receiver.network), route: receiver.momo_number_or_code };
  } catch { return null; }
}

function parseGroup(data: Record<string, unknown>, id: string, actorId: string, recovering: boolean): Record<string, unknown> {
  if (data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'groups' ||
      data.current_actor_id !== actorId || typeof data.can_manage !== 'boolean' || !Array.isArray(data.allowed_operations) ||
      (!recovering && (data.can_manage !== true || !data.allowed_operations.includes('updateGroup'))) || !isObject(data.resource) || data.resource.id !== id ||
      !isSafeCount(data.resource.version) || data.resource.version < 1 || (!recovering && data.resource.status === 'archived') ||
      typeof data.resource.description !== 'string' || !isId(data.resource.owner_user_id)) throw new Error('The group cannot be verified.');
  parseCoreRow('groups', 'canonical_evidence_ledger', data.resource);
  return data.resource;
}

async function validReceipt(value: unknown, id: string, version: number, principalId: string, key: string): Promise<boolean> {
  if (!isObject(value) || Object.keys(value).length !== 5 || value.status !== 'succeeded' ||
      value.resource_type !== 'groups' || value.resource_id !== id || value.version !== version + 1) return false;
  return value.request_id === await canonicalRequestId(principalId, key);
}

export function GroupEditPage(props: GroupEditProps) {
  return props.financialModel === 'transaction_journals' ? <LegacyGroupPage {...props} mode="edit" /> : <CanonicalGroupEditPage {...props} />;
}

function CanonicalGroupEditPage({ id, request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh }: GroupEditProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email,
    role: identity.role, permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }),
  [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const allowed = financialModel === 'canonical_evidence_ledger' && role !== 'staff' &&
    permissions.includes('collections.read') && permissions.includes(PERMISSION) && isId(id) &&
    stableIdentity.id === actorId && stableIdentity.role === role && stableIdentity.permissions.includes(PERMISSION) &&
    typeof principalId === 'string' && isId(principalId);
  const canPublish = role !== 'staff' && ['collections.manage', 'receivers.manage', 'receivers.read'].every(permission => permissions.includes(permission) && stableIdentity.permissions.includes(permission));
  const [draft, setDraft] = useState<GroupDraft | null>(null);
  const [proof, setProof] = useState<PublicationProof | null>(null);
  const [publish, setPublish] = useState(false);
  const [version, setVersion] = useState<number | null>(null);
  const [pending, setPending] = useState<PendingAttempt | null>(null);
  const [review, setReview] = useState<Record<string, unknown> | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'sending' | 'checking' | 'success' | 'error'>('loading');
  const [message, setMessage] = useState('');
  const [retryAllowed, setRetryAllowed] = useState(false);
  const current = useRef(authorityKey);
  useLayoutEffect(() => { current.current = authorityKey; return () => { current.current = ''; }; }, [authorityKey]);
  const writeGate = useRef(allowMutations);
  useLayoutEffect(() => { writeGate.current = allowMutations; return () => { writeGate.current = false; }; }, [allowMutations]);
  const busy = useRef(false);
  const scope = JSON.stringify([authorityKey, id]);
  const [loadedScope, setLoadedScope] = useState('');

  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController(); let live = true;
    readPending(stableIdentity, FAMILY, id).then(async stored => {
      if (!stored && !allowMutations) {
        if (live) { setLoadedScope(scope); setState('ready'); setMessage('Editing is not enabled for this workspace.'); }
        return null;
      }
      const data = await request(`operations/groups/${id}`, { signal: controller.signal });
      return {data, stored};
    }).then(result => {
      if (!result) return;
      const {data, stored} = result;
      const resource = parseGroup(data, id, actorId, stored !== null);
      if (stored) {
        if (stored.permission !== PERMISSION || stored.family !== FAMILY || stored.resource_id !== id || !isSafeCount(stored.intent.expected_version) || stored.intent.expected_version < 1) throw new Error('Invalid pending request');
      }
      if (!live || current.current !== authorityKey) return;
      setDraft({ title: String(resource.title), collection_type: String(resource.collection_type), description: String(resource.description), purpose_label: typeof resource.purpose_label === 'string' ? resource.purpose_label : '', status: String(resource.status), reason: '' });
      setProof(canPublish ? publicationProof(data, resource, id) : null); setPublish(false);
      setVersion(resource.version as number); setPending(stored); setLoadedScope(scope); setState('ready');
    }).catch(() => { if (live) { setLoadedScope(scope); setState('error'); setMessage('The current group or recovery record could not be verified.'); } });
    return () => { live = false; controller.abort(); };
  }, [allowed, allowMutations, request, actorId, authorityKey, id, scope, stableIdentity, canPublish]);

  const active = () => current.current === authorityKey && Date.parse(stableIdentity.expiresAt) > Date.now();
  const makeReview = (event: FormEvent) => {
    event.preventDefault();
    if (!allowMutations || !draft || version === null || pending || state !== 'ready' || !active()) return;
    try {
      if (publish && (!canPublish || !proof)) throw new Error('The receiver is unavailable.');
      const body = validatedBody({ title: draft.title.trim(), collection_type: draft.collection_type, description: draft.description.trim(),
        purpose_label: draft.purpose_label.trim() || null, status: draft.status, reason: draft.reason.trim(), expected_version: version,
        ...(publish ? { visibility: 'public_approved', is_platform_sponsored: true } : {}) }, canPublish);
      setMessage(''); setReview(body);
    } catch { setMessage('Check the group details and provide a reason of 8 to 500 characters.'); }
  };

  const send = async (body: Record<string, unknown>, key: string) => {
    if (!allowed || !allowMutations || !principalId || !active() || busy.current) return;
    busy.current = true;
    setState('sending'); setMessage('');
    let retained: PendingAttempt | null = null;
    try {
      const currentDetail = await request(`operations/groups/${id}`);
      const currentGroup = parseGroup(currentDetail, id, actorId, false);
      const currentProof = body.visibility === 'public_approved' ? publicationProof(currentDetail, currentGroup, id) : null;
      if (currentGroup.version !== validatedBody(body, canPublish).expected_version || !active() || !writeGate.current ||
          (body.visibility === 'public_approved' && (!proof || !currentProof || JSON.stringify(currentProof) !== JSON.stringify(proof)))) throw new Error('The group changed.');
      if (!await verifyFresh() || !active() || !writeGate.current) throw new Error('Verify your email before making this change.');
      retained = await retainPending(stableIdentity, FAMILY, id, key, PERMISSION, validatedBody(body, canPublish));
      if (!active() || !writeGate.current) return;
      setPending(retained); setRetryAllowed(false);
      const receipt = await request(`operations/groups/${id}`, { method: 'PATCH', body, idempotencyKey: key });
      if (!active()) return;
      if (!await validReceipt(receipt, id, body.expected_version as number, principalId, key)) throw new Error('Unverified receipt');
      await clearPending(stableIdentity, FAMILY, id, key);
      if (!active()) return;
      setPending(null); setReview(null); setState('success'); setMessage('Group changes recorded.');
    } catch {
      if (!active()) return;
      // Any failure after retaining the original key remains unresolved until lookup.
      const existing = retained ?? await readPending(stableIdentity, FAMILY, id).catch(() => null);
      setPending(existing); setReview(null); setState('ready');
      setMessage(existing ? 'The result is unconfirmed. Check the original request before making another change.' : 'Verification or recovery storage is unavailable. No change was submitted.');
    } finally { busy.current = false; }
  };

  const check = async () => {
    if (!pending || !principalId || !active() || busy.current) return;
    if (!permissions.includes('overview.read') || !permissions.includes('account.manage')) { setMessage('Your account cannot check request history. Contact an authorized administrator.'); return; }
    busy.current = true;
    const original = pending;
    setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const data = await request(`operations/requests/${original.request_key}`);
      if (!active()) return;
      if (data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' ||
          !['not_found', 'unconfirmed', 'cancelled', 'succeeded'].includes(String(data.status))) throw new Error('Invalid request lookup');
      if (data.status === 'not_found') {
        if (Object.keys(data).length !== 3) throw new Error('Invalid request lookup');
        let retryable = false;
        try { validatedBody(original.intent, canPublish); retryable = allowMutations && (original.intent.visibility !== 'public_approved' || proof !== null); } catch { /* Other intents can still be checked, but cannot be reconstructed here. */ }
        setRetryAllowed(retryable);
        setMessage(retryable ? 'No completed request was found. You may check again or review the same request with its original reference.' : 'No completed request was found. Keep this reference and check it again before making another change.');
      } else {
        if (Object.keys(data).length !== 5 || data.request_id !== await canonicalRequestId(principalId, original.request_key)) throw new Error('Invalid request lookup');
        if (data.status === 'succeeded') {
          if (!await validReceipt(data.receipt, id, original.intent.expected_version as number, principalId, original.request_key)) throw new Error('Invalid receipt');
          await clearPending(stableIdentity, FAMILY, id, original.request_key);
          if (!active()) return;
          setPending(null); setState('success'); setMessage('The original group change was recorded.'); return;
        }
        if (data.status === 'cancelled') {
          if (data.receipt !== null) throw new Error('Invalid receipt');
          await clearPending(stableIdentity, FAMILY, id, original.request_key);
          if (!active()) return;
          setPending(null); setState('error'); setMessage('The original request was cancelled. Reopen the current group before editing.'); return;
        }
        if (data.receipt !== null) throw new Error('Invalid receipt');
        setMessage('The request is still unconfirmed. Check again before continuing.');
      }
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };

  return <>
    <PageHeader title="Edit group" subtitle="Changes use the current group version and require a recorded reason." actions={<Button type="button" onClick={() => navigate(isId(id) ? `/admin/groups/${id}` : '/admin/groups')}>Back to group</Button>} />
    {!allowed ? <ErrorState title="Editing unavailable" message="This operation is not enabled for the current account and workspace." /> :
      state === 'loading' || loadedScope !== scope ? <LoadingState label="Loading group" /> :
      state === 'error' ? <ErrorState message={message || 'The group could not be verified.'} /> :
      state === 'success' ? <Card><div className="core-detail" role="status"><h2>Change recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/groups/${id}`)}>View group</Button></div></Card> :
      !draft || version === null ? <ErrorState title="Editing unavailable" message={message || 'The group could not be verified.'} /> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending ? <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p><p>Check the original request before another change.</p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(validatedBody(pending.intent, canPublish)); setRetryAllowed(false); }}>Review same request</Button>}</section> : null}
        {!pending && !review && allowMutations && <form onSubmit={makeReview} className="core-edit-form">
          <label>Group name<input className="admin-input" value={draft.title} maxLength={160} required onChange={event => setDraft({ ...draft, title: event.target.value })} /></label>
          <label>Group type<select className="admin-input" value={draft.collection_type} onChange={event => setDraft({ ...draft, collection_type: event.target.value })}>{TYPES.map(type => <option value={type} key={type}>{type}</option>)}</select></label>
          <label>Description<textarea className="admin-input" value={draft.description} maxLength={2000} onChange={event => setDraft({ ...draft, description: event.target.value })} /></label>
          <label>Purpose<input className="admin-input" value={draft.purpose_label} maxLength={120} onChange={event => setDraft({ ...draft, purpose_label: event.target.value })} /></label>
          <label>Status<select className="admin-input" value={draft.status} onChange={event => setDraft({ ...draft, status: event.target.value })}>{STATUSES.map(status => <option value={status} key={status}>{status}</option>)}</select></label>
          {canPublish && proof && <label><input type="checkbox" checked={publish} onChange={event => setPublish(event.target.checked)} /> Publish as a Collect-sponsored public group</label>}
          {publish && proof && <p>Owner: {proof.ownerId}. Recorded receiver: {proof.receiver} · {proof.network} · {proof.route}. Publishing permanently locks the receiver.</p>}
          <p>Archiving a group is permanent. Suspending or archiving may cancel pending payment instructions.</p>
          <label>Reason for change<textarea className="admin-input" value={draft.reason} minLength={8} maxLength={500} required onChange={event => setDraft({ ...draft, reason: event.target.value })} /></label>
          <Button type="submit" variant="primary" disabled={state !== 'ready'}>Review changes</Button>
        </form>}
        {review && allowMutations && <section><h2>Review group change</h2><dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{value === null ? 'Not recorded' : String(value)}</dd></div>)}</dl>{review.visibility === 'public_approved' && proof && <p>Owner: {proof.ownerId}. Recorded receiver: {proof.receiver} · {proof.network} · {proof.route}. Publishing permanently locks the receiver.</p>}<p>Archiving is permanent. This action does not confirm provider settlement.</p>
          <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); if (pending) setRetryAllowed(true); }}>Cancel</Button>
          <Button type="button" variant="primary" disabled={state !== 'ready'} onClick={() => {
            const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.();
            if (!key) { setMessage('A secure request reference is unavailable. No change was submitted.'); return; }
            void send(review, key);
          }}>{pending ? 'Confirm same request' : 'Confirm changes'}</Button>
        </section>}
      </div></Card>}
  </>;
}
