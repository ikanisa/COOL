import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, isId, isObject, isSafeCount, parseCoreRow } from './contracts';
import { LegacyMembershipPage } from './LegacyMembershipPage';
import { canonicalRequestId, clearPending, readPending, retainPending } from './pendingAttempt';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { FeatureAccess } from './types';
import './core.css';

export interface MembershipEditProps extends FeatureAccess {
  groupId: string;
  userId: string;
  identity: PendingIdentity;
  allowMutations?: boolean;
  verifyFresh: () => Promise<boolean>;
}
const FAMILY = 'operating-updatemembership', PERMISSION = 'users.manage';
const FIELDS = ['role', 'status', 'reason', 'expected_version'];
type Membership = { id: string; groupId: string; userId: string; groupVersion: number; version: number; role: string; status: string; publicId: string; displayName: string; memberType: string; momoProvider: unknown; momoNumber: unknown; momoCode: unknown };
function intent(value: unknown): Record<string, unknown> {
  if (!isObject(value) || Object.keys(value).length !== FIELDS.length || !FIELDS.every(key => key in value) ||
      !['member', 'admin'].includes(String(value.role)) || !['active', 'removed', 'left'].includes(String(value.status)) ||
      typeof value.reason !== 'string' || value.reason.trim().length < 8 || value.reason.length > 500 ||
      !isSafeCount(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER) throw new Error('Invalid membership');
  return value;
}
async function validReceipt(value: unknown, groupId: string, userId: string, version: number, principal: string, key: string): Promise<boolean> {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' && value.resource_type === 'memberships' &&
    value.resource_id === `${groupId}/${userId}` && value.version === version + 1 && value.request_id === await canonicalRequestId(principal, key);
}
async function currentMembership(request: FeatureAccess['request'], groupId: string, userId: string, actor: string, isCurrent: () => boolean): Promise<Membership> {
  const seen = new Set<string>(); let offset = 0, total: number | null = null, version: number | null = null, found: Membership | null = null;
  do {
    const query = new URLSearchParams({ relation: 'memberships', limit: '100', offset: String(offset) });
    const data = await request(`operations/groups/${groupId}?${query.toString()}`);
    if (!isCurrent() || data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'groups' || data.current_actor_id !== actor ||
        data.can_manage !== true || !Array.isArray(data.allowed_operations) || !data.allowed_operations.includes('updateMembership') ||
        !isObject(data.resource) || data.resource.id !== groupId || !isObject(data.related) || Object.keys(data.related).length !== 1 ||
        !Array.isArray(data.related.memberships) || !isObject(data.related_pages) || Object.keys(data.related_pages).length !== 1 || !isObject(data.related_pages.memberships) || data.related_truncated !== false) throw new Error('Membership unavailable');
    const group = parseCoreRow('groups', 'canonical_evidence_ledger', data.resource), page = data.related_pages.memberships, rows = data.related.memberships;
    if (group.status !== 'active' || !isSafeCount(group.version) || group.version < 1 || (version !== null && group.version !== version) ||
        Object.keys(page).length !== 4 || !isSafeCount(page.total) || page.total > 1000 || page.limit !== 100 || page.offset !== offset ||
        rows.length !== Math.min(100, Math.max(0, page.total - offset)) || page.next_offset !== (offset + rows.length < page.total ? offset + rows.length : null) ||
        (total !== null && total !== page.total)) throw new Error('Membership unavailable');
    version = group.version; total = page.total;
    for (const row of rows) {
      if (!isObject(row) || !isId(row.id) || seen.has(row.id) || row.group_id !== groupId || !isId(row.user_id) ||
          !['owner', 'admin', 'member', 'receiver', 'contributor', 'viewer'].includes(String(row.role)) || !['active', 'removed'].includes(String(row.status))) throw new Error('Membership unavailable');
      seen.add(row.id);
      if (row.user_id !== userId) continue;
      if (found || !['member', 'admin'].includes(String(row.role)) || !isSafeCount(row.version) || row.version < 1 || row.account_status !== 'active' ||
          !['app', 'direct'].includes(String(row.member_type)) || typeof row.public_id !== 'string' || !/^\d{6}$/.test(row.public_id) ||
          typeof row.display_name !== 'string' || !row.display_name.trim() || row.display_name.length > 120 || containsControl(row.display_name) ||
          !(row.momo_provider === null || ['mtn_momo', 'airtel_money'].includes(String(row.momo_provider))) ||
          !(row.momo_number === null || typeof row.momo_number === 'string' && /^07[2389]\d{7}$/.test(row.momo_number)) ||
          !(row.momo_pay_code === null || typeof row.momo_pay_code === 'string' && /^\d{4,9}$/.test(row.momo_pay_code))) throw new Error('Membership unavailable');
      found = { id: row.id, groupId, userId, groupVersion: version, version: row.version, role: String(row.role), status: String(row.status),
        publicId: row.public_id, displayName: row.display_name, memberType: String(row.member_type), momoProvider: row.momo_provider, momoNumber: row.momo_number, momoCode: row.momo_pay_code };
    }
    offset += rows.length;
  } while (total !== null && offset < total);
  if (!found || !isCurrent()) throw new Error('Membership unavailable');
  return found;
}
function sameMembership(left: Membership, right: Membership): boolean { return JSON.stringify(left) === JSON.stringify(right); }

/** Canonical membership edits require both grants until the backend contract is reconciled. */
export function MembershipEditPage(props: MembershipEditProps) {
  return props.financialModel === 'transaction_journals' ? <LegacyMembershipPage {...props} mode="edit" /> : <CanonicalMembershipEditPage {...props} />;
}

function CanonicalMembershipEditPage({ groupId, userId, request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh }: MembershipEditProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const allowed = financialModel === 'canonical_evidence_ledger' && role !== 'staff' && isId(groupId) && isId(userId) && typeof principalId === 'string' && isId(principalId) &&
    ['collections.read', 'users.read', PERMISSION].every(permission => permissions.includes(permission) && stableIdentity.permissions.includes(permission)) && stableIdentity.id === actorId && stableIdentity.role === role;
  const canWrite = allowed && permissions.includes('collections.manage') && stableIdentity.permissions.includes('collections.manage');
  const resource = `${groupId}:${userId}`, scope = JSON.stringify([authorityKey, groupId, userId]);
  const [source, setSource] = useState<Membership | null>(null), [memberRole, setMemberRole] = useState('member'), [status, setStatus] = useState('active'), [reason, setReason] = useState('');
  const [pending, setPending] = useState<PendingAttempt | null>(null), [review, setReview] = useState<Record<string, unknown> | null>(null), [retryAllowed, setRetryAllowed] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'sending' | 'checking' | 'success' | 'error'>('loading');
  const [scopeLoaded, setScopeLoaded] = useState(''), [message, setMessage] = useState('');
  const current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const active = () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now();
  useEffect(() => {
    if (!allowed) return;
    let live = true;
    readPending(stableIdentity, FAMILY, resource).then(async saved => {
      if (saved && (saved.permission !== PERMISSION || !isSafeCount(saved.intent.expected_version) || saved.intent.expected_version < 1)) throw new Error('Invalid recovery');
      const row = !saved && allowMutations && canWrite ? await currentMembership(request, groupId, userId, actorId, () => live && current.current === scope) : null;
      if (!live || current.current !== scope) return;
      setPending(saved); setSource(row); if (row) { setMemberRole(row.role); setStatus(row.status); }
      setScopeLoaded(scope); setState('ready');
      if (saved) setMessage('A previous membership change needs recovery. Check its original reference before continuing.');
      else if (!allowMutations) setMessage('Membership editing is not enabled for this workspace.');
      else if (!canWrite) setMessage('Editing memberships also requires group management permission in this workspace.');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('The membership or recovery record could not be verified. Active group owners cannot be changed here.'); } });
    return () => { live = false; };
  }, [allowed, allowMutations, canWrite, stableIdentity, request, groupId, userId, actorId, resource, scope]);
  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || !canWrite || !source || pending || state !== 'ready' || !active()) return;
    try { setReview(intent({ role: memberRole, status, reason: reason.trim(), expected_version: source.version })); setMessage(''); }
    catch { setMessage('Check the role, membership status and reason.'); }
  };
  const send = async (body: Record<string, unknown>, key: string) => {
    if (!canWrite || !allowMutations || !principalId || !source || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null;
    try {
      const checked = intent(body), latest = await currentMembership(request, groupId, userId, actorId, () => active() && gate.current);
      if (!sameMembership(source, latest) || checked.expected_version !== latest.version || !active() || !gate.current || !await verifyFresh() || !active() || !gate.current) throw new Error('Membership changed');
      retained = await retainPending(stableIdentity, FAMILY, resource, key, PERMISSION, checked);
      if (!active() || !gate.current) return;
      setPending(retained); setRetryAllowed(false);
      const receipt = await request(`operations/memberships/${groupId}/${userId}`, { method: 'PATCH', body: checked, idempotencyKey: key });
      if (!active()) return;
      if (!await validReceipt(receipt, groupId, userId, checked.expected_version as number, principalId, key)) throw new Error('Invalid receipt');
      await clearPending(stableIdentity, FAMILY, resource, key);
      if (!active()) return;
      setPending(null); setReview(null); setState('success'); setMessage('The membership was updated.');
    } catch {
      if (!active()) return;
      const saved = retained ?? await readPending(stableIdentity, FAMILY, resource).catch(() => null);
      setPending(saved); setReview(null); setState('ready'); setMessage(saved ? 'The result is unconfirmed. Check the original request before another change.' : 'The current membership or verification could not be confirmed. No change was submitted.');
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
        let retryable = false; try { intent(original.intent); retryable = allowMutations && canWrite; } catch { /* Other intents can still be checked. */ }
        setRetryAllowed(retryable); setMessage(retryable ? 'No completed request was found. You may check again or review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.');
      } else {
        if (Object.keys(data).length !== 5 || data.request_id !== await canonicalRequestId(principalId, original.request_key)) throw new Error('Invalid lookup');
        if (data.status === 'succeeded') {
          if (!await validReceipt(data.receipt, groupId, userId, original.intent.expected_version as number, principalId, original.request_key)) throw new Error('Invalid receipt');
          await clearPending(stableIdentity, FAMILY, resource, original.request_key);
          if (!active()) return;
          setPending(null); setState('success'); setMessage('The original membership change was recorded.'); return;
        }
        if (data.receipt !== null) throw new Error('Invalid receipt');
        if (data.status === 'cancelled') {
          await clearPending(stableIdentity, FAMILY, resource, original.request_key);
          if (!active()) return;
          setPending(null); setState('error'); setMessage('The original request was cancelled. Reopen the group before editing.'); return;
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
      const original = intent(pending.intent), latest = await currentMembership(request, groupId, userId, actorId, () => active() && gate.current);
      if (original.expected_version !== latest.version || !active() || !gate.current) throw new Error('Membership changed');
      setSource(latest); setReview(original); setRetryAllowed(false);
    } catch { if (active()) { setRetryAllowed(false); setMessage('The current membership could not be verified. Check the original request again.'); } }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };

  return <>
    <PageHeader title="Edit membership" subtitle="Changes use the current group and membership records." actions={<Button type="button" onClick={() => navigate(isId(groupId) ? `/admin/groups/${groupId}` : '/admin/groups')}>Back to group</Button>} />
    {!allowed ? <ErrorState title="Editing unavailable" message="This operation is not enabled for the current account and workspace." /> : state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> :
      state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Change recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/groups/${groupId}`)}>View group</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && canWrite && source && <form className="core-edit-form" onSubmit={makeReview}><p>Member: {source.displayName} · {source.publicId}. Active group owners cannot be changed here.</p><label>Group role<select className="admin-input" value={memberRole} onChange={event => setMemberRole(event.target.value)}><option value="member">Member</option><option value="admin">Group administrator</option></select></label><label>Membership status<select className="admin-input" value={status} onChange={event => setStatus(event.target.value)}><option value="active">Active</option><option value="removed">Removed</option><option value="left">Left</option></select></label><label>Reason for change<textarea className="admin-input" value={reason} minLength={8} maxLength={500} required onChange={event => setReason(event.target.value)} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review membership</Button></form>}
        {review && allowMutations && canWrite && source && <section><h2>Review membership change</h2><p>Member: {source.displayName} · {source.publicId}</p><dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{String(value)}</dd></div>)}</dl><Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready'} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No change was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm membership changes'}</Button></section>}
      </div></Card>}
  </>;
}
