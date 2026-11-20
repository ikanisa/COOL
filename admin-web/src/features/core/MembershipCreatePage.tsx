import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, isId, isObject, parseCoreRow } from './contracts';
import { activeOwner, parseOwners } from './GroupCreatePage';
import { LegacyMembershipPage } from './LegacyMembershipPage';
import { canonicalRequestId, clearPending, readPending, retainPending } from './pendingAttempt';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { DataRow, FeatureAccess } from './types';
import './core.css';

export interface MembershipCreateProps extends FeatureAccess {
  id: string;
  identity: PendingIdentity;
  allowMutations?: boolean;
  verifyFresh: () => Promise<boolean>;
}
const FAMILY = 'operating-createmembership', RESOURCE = 'new', PERMISSION = 'users.manage';
const FIELDS = ['group_id', 'user_id', 'role', 'status', 'reason'];
function intent(value: unknown): Record<string, unknown> {
  if (!isObject(value) || Object.keys(value).length !== FIELDS.length || !FIELDS.every(key => key in value) ||
      !isId(value.group_id) || !isId(value.user_id) || !['member', 'admin'].includes(String(value.role)) ||
      !['active', 'removed', 'left'].includes(String(value.status)) || typeof value.reason !== 'string' || value.reason.trim().length < 8 || value.reason.length > 500) throw new Error('Invalid membership');
  return value;
}
function group(data: Record<string, unknown>, id: string, actor: string): void {
  if (data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'groups' || data.current_actor_id !== actor ||
      data.can_manage !== true || !Array.isArray(data.allowed_operations) || !data.allowed_operations.includes('createMembership') || !isObject(data.resource) || data.resource.id !== id) throw new Error('Group unavailable');
  const row = parseCoreRow('groups', 'canonical_evidence_ledger', data.resource);
  if (row.status !== 'active') throw new Error('Group unavailable');
}
function memberResource(data: Record<string, unknown>, id: unknown, actor: string): DataRow {
  if (!isId(id) || data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'users' || data.current_actor_id !== actor ||
      !isObject(data.resource) || data.resource.id !== id) throw new Error('Member unavailable');
  return activeOwner(data.resource);
}
function sameMember(left: DataRow, right: DataRow): boolean {
  return ['id', 'version', 'public_id', 'display_name', 'momo_provider', 'momo_number', 'momo_pay_code'].every(key => left[key] === right[key]);
}
async function validReceipt(value: unknown, principal: string, key: string, body: Record<string, unknown>): Promise<boolean> {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' && value.resource_type === 'memberships' &&
    value.resource_id === `${body.group_id}/${body.user_id}` && value.version === 1 && value.request_id === await canonicalRequestId(principal, key);
}

/** Canonical membership creation, disabled until the migration is qualified. */
export function MembershipCreatePage(props: MembershipCreateProps) {
  return props.financialModel === 'transaction_journals' ? <LegacyMembershipPage {...props} mode="create" groupId={props.id} /> : <CanonicalMembershipCreatePage {...props} />;
}

function CanonicalMembershipCreatePage({ id, request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh }: MembershipCreateProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const allowed = financialModel === 'canonical_evidence_ledger' && role !== 'staff' && isId(id) && typeof principalId === 'string' && isId(principalId) &&
    ['collections.read', 'users.read', PERMISSION].every(permission => permissions.includes(permission) && stableIdentity.permissions.includes(permission)) && stableIdentity.id === actorId && stableIdentity.role === role;
  // The advertised Flutter operation uses users.manage, while the canonical
  // bridge currently derives collections.manage for memberships. Require both.
  const canWrite = allowed && permissions.includes('collections.manage') && stableIdentity.permissions.includes('collections.manage');
  const [search, setSearch] = useState(''), [owners, setOwners] = useState<DataRow[]>([]), [selected, setSelected] = useState<DataRow | null>(null);
  const [membershipRole, setMembershipRole] = useState('member'), [membershipStatus, setMembershipStatus] = useState('active'), [reason, setReason] = useState('');
  const [pending, setPending] = useState<PendingAttempt | null>(null), [review, setReview] = useState<Record<string, unknown> | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'searching' | 'sending' | 'checking' | 'success' | 'error'>('loading');
  const [loadedScope, setLoadedScope] = useState(''), [message, setMessage] = useState(''), [retryAllowed, setRetryAllowed] = useState(false);
  const [completedGroup, setCompletedGroup] = useState(id);
  const current = useRef(authorityKey), gate = useRef(allowMutations), busy = useRef(false), searchEpoch = useRef(0);
  useLayoutEffect(() => { current.current = authorityKey; return () => { current.current = ''; }; }, [authorityKey]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const scope = JSON.stringify([authorityKey, id]);
  const active = () => current.current === authorityKey && Date.parse(stableIdentity.expiresAt) > Date.now();
  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController(); let live = true; const epoch = searchEpoch;
    readPending(stableIdentity, FAMILY, RESOURCE).then(async stored => {
      if (stored && (stored.permission !== PERMISSION || !isId(stored.intent.group_id) || !isId(stored.intent.user_id))) throw new Error('Invalid recovery');
      if (!stored && allowMutations && canWrite) group(await request(`operations/groups/${id}`, { signal: controller.signal }), id, actorId);
      if (!live || current.current !== authorityKey) return;
      setPending(stored); setLoadedScope(scope); setState('ready');
      if (stored) setMessage('A previous membership request needs recovery. Check its original reference before continuing.');
      else if (!allowMutations) setMessage('Adding members is not enabled for this workspace.');
      else if (!canWrite) setMessage('Adding members also requires group management permission in this workspace.');
    }).catch(() => { if (live) { setLoadedScope(scope); setState('error'); setMessage('The group or recovery record could not be verified.'); } });
    return () => { live = false; epoch.current++; controller.abort(); };
  }, [allowed, allowMutations, canWrite, request, actorId, authorityKey, id, scope, stableIdentity]);

  const findMembers = async (event: FormEvent) => {
    event.preventDefault(); const term = search.trim();
    if (!allowMutations || !canWrite || !active() || pending || busy.current || term.length > 200 || containsControl(term)) return;
    const epoch = ++searchEpoch.current; setState('searching'); setSelected(null); setMessage('');
    try {
      const query = new URLSearchParams({ kind: 'users', search: term, limit: '100' });
      const rows = parseOwners(await request(`operations/lookups?${query.toString()}`));
      if (!active() || epoch !== searchEpoch.current) return;
      setOwners(rows); if (!rows.length) setMessage('No active members found.');
    } catch { if (active() && epoch === searchEpoch.current) { setOwners([]); setMessage('The member search could not be verified.'); } }
    finally { if (active() && epoch === searchEpoch.current) setState('ready'); }
  };
  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || !canWrite || !selected || pending || state !== 'ready' || !active()) return;
    try { setReview(intent({ group_id: id, user_id: selected.id, role: membershipRole, status: membershipStatus, reason: reason.trim() })); setMessage(''); }
    catch { setMessage('Select a member and provide a reason of 8 to 500 characters.'); }
  };
  const send = async (body: Record<string, unknown>, key: string) => {
    if (!canWrite || !allowMutations || !principalId || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null;
    try {
      const checked = intent(body); if (checked.group_id !== id) throw new Error('Different group');
      group(await request(`operations/groups/${id}`), id, actorId);
      const member = memberResource(await request(`operations/users/${checked.user_id}`), checked.user_id, actorId);
      if (!selected || !sameMember(selected, member)) throw new Error('Member changed');
      if (!active() || !gate.current || !await verifyFresh() || !active() || !gate.current) throw new Error('Verification required');
      retained = await retainPending(stableIdentity, FAMILY, RESOURCE, key, PERMISSION, checked);
      if (!active() || !gate.current) return;
      setPending(retained); setRetryAllowed(false);
      const receipt = await request('operations/memberships', { method: 'POST', body: checked, idempotencyKey: key });
      if (!active()) return;
      if (!await validReceipt(receipt, principalId, key, checked)) throw new Error('Invalid receipt');
      await clearPending(stableIdentity, FAMILY, RESOURCE, key);
      if (!active()) return;
      setPending(null); setReview(null); setCompletedGroup(String(checked.group_id)); setState('success'); setMessage('The membership was recorded.');
    } catch {
      if (!active()) return;
      const saved = retained ?? await readPending(stableIdentity, FAMILY, RESOURCE).catch(() => null);
      setPending(saved); setReview(null); setState('ready'); setMessage(saved ? 'The result is unconfirmed. Check the original request before another change.' : 'The group, member or verification could not be confirmed. No membership was submitted.');
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
        let retryable = false; try { intent(original.intent); retryable = allowMutations && canWrite && original.intent.group_id === id; } catch { /* Unknown intents may still be checked. */ }
        setRetryAllowed(retryable); setMessage(retryable ? 'No completed request was found. You may check again or review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.');
      } else {
        if (Object.keys(data).length !== 5 || data.request_id !== await canonicalRequestId(principalId, original.request_key)) throw new Error('Invalid lookup');
        if (data.status === 'succeeded') {
          if (!await validReceipt(data.receipt, principalId, original.request_key, original.intent)) throw new Error('Invalid receipt');
          await clearPending(stableIdentity, FAMILY, RESOURCE, original.request_key);
          if (!active()) return;
          setPending(null); setCompletedGroup(String(original.intent.group_id)); setState('success'); setMessage('The original membership was recorded.'); return;
        }
        if (data.receipt !== null) throw new Error('Invalid receipt');
        if (data.status === 'cancelled') {
          await clearPending(stableIdentity, FAMILY, RESOURCE, original.request_key);
          if (!active()) return;
          setPending(null); setState('error'); setMessage('The original request was cancelled. Reopen the group before adding a member.'); return;
        }
        setMessage('The request is still unconfirmed. Check again before continuing.');
      }
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const reviewSame = async () => {
    if (!pending || !retryAllowed || !allowMutations || !canWrite || busy.current || !active()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      const original = intent(pending.intent);
      if (original.group_id !== id) throw new Error('Different group');
      const member = memberResource(await request(`operations/users/${original.user_id}`), original.user_id, actorId);
      if (!active() || !gate.current) return;
      setSelected(member); setReview(original); setRetryAllowed(false);
    } catch { if (active()) { setRetryAllowed(false); setMessage('The member could not be verified. Check the original request again.'); } }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };

  return <>
    <PageHeader title="Add group member" subtitle="Select an active App or Direct member and record the group role." actions={<Button type="button" onClick={() => navigate(isId(id) ? `/admin/groups/${id}` : '/admin/groups')}>Back to group</Button>} />
    {!allowed ? <ErrorState title="Adding members unavailable" message="This operation is not enabled for the current account and workspace." /> :
      state === 'loading' || loadedScope !== scope ? <LoadingState label="Checking recovery" /> : state === 'error' ? <ErrorState message={message} /> :
      state === 'success' ? <Card><div className="core-detail" role="status"><h2>Membership recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/groups/${completedGroup}`)}>View group</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p><p>Group: {String(pending.intent.group_id)}</p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && canWrite && <><form className="core-search" onSubmit={event => void findMembers(event)}><label>Search members<input className="admin-input" value={search} maxLength={200} onChange={event => setSearch(event.target.value)} /></label><Button type="submit" disabled={state !== 'ready'}>Find members</Button></form>
          {owners.length > 0 && <label>Member<select className="admin-input" value={selected?.id ?? ''} onChange={event => setSelected(owners.find(owner => owner.id === event.target.value) ?? null)}><option value="">Select member</option>{owners.map(owner => <option key={owner.id} value={owner.id}>{String(owner.display_name)} · {owner.public_id as string}</option>)}</select></label>}
          <form className="core-edit-form" onSubmit={makeReview}><label>Group role<select className="admin-input" value={membershipRole} onChange={event => setMembershipRole(event.target.value)}><option value="member">Member</option><option value="admin">Group administrator</option></select></label><label>Membership status<select className="admin-input" value={membershipStatus} onChange={event => setMembershipStatus(event.target.value)}><option value="active">Active</option><option value="removed">Removed</option><option value="left">Left</option></select></label><label>Reason for change<textarea className="admin-input" value={reason} minLength={8} maxLength={500} required onChange={event => setReason(event.target.value)} /></label><Button type="submit" variant="primary" disabled={state !== 'ready' || !selected}>Review membership</Button></form>
        </>}
        {review && allowMutations && canWrite && <section><h2>Review membership</h2>{selected && selected.id === review.user_id && <p>Selected member: {String(selected.display_name)} · {String(selected.public_id)}</p>}<dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{String(value)}</dd></div>)}</dl><Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready'} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No membership was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm membership'}</Button></section>}
      </div></Card>}
  </>;
}
