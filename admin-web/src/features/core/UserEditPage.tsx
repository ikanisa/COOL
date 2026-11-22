import { useEffect, useLayoutEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, isId, isObject, isSafeCount, parseCoreRow } from './contracts';
import { readPending, retainPending } from './pendingAttempt';
import {clearOriginalAttempt, lookupCanonicalMutation, matchesCanonicalReceipt} from './canonicalMutation';
import {usePendingIdentity} from './usePendingIdentity';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { DataRow, FeatureAccess } from './types';
import { LegacyUserEditPage } from './LegacyUserEditPage';
import './core.css';

export interface UserEditProps extends FeatureAccess {
  id: string;
  returnArea?: 'users' | 'members';
  identity: PendingIdentity;
  allowMutations?: boolean;
  /** Legacy status changes have a separate gate and require fresh verification. */
  allowStatusChanges?: boolean;
  verifyFresh: () => Promise<boolean>;
}
const FAMILY = 'operating-updateuser', PERMISSION = 'users.manage';
const FIELDS = ['display_name', 'momo_provider', 'momo_number', 'momo_pay_code', 'status', 'reason', 'expected_version'];
type Draft = { display_name: string; momo_provider: string; momo_number: string; momo_pay_code: string; status: string; reason: string };
function intent(value: unknown, person: DataRow): Record<string, unknown> {
  if (!isObject(value) || Object.keys(value).length !== FIELDS.length || !FIELDS.every(key => key in value) ||
      typeof value.display_name !== 'string' || value.display_name.trim().length < 2 || value.display_name.length > 120 || containsControl(value.display_name) ||
      !['mtn_momo', 'airtel_money'].includes(String(value.momo_provider)) || typeof value.momo_number !== 'string' ||
      (value.momo_number !== '' && !/^07[2389]\d{7}$/.test(value.momo_number)) || typeof value.momo_pay_code !== 'string' ||
      (value.momo_pay_code !== '' && !/^\d{4,9}$/.test(value.momo_pay_code)) ||
      (person.member_type === 'direct' && value.momo_number === '') ||
      (person.member_type === 'app' && !(typeof person.email === 'string' && person.email.length > 0) && !(typeof person.phone_e164 === 'string' && person.phone_e164.length > 0)) ||
      !['active', 'suspended'].includes(String(value.status)) || typeof value.reason !== 'string' || value.reason.trim().length < 8 || value.reason.length > 500 ||
      !isSafeCount(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER) throw new Error('Invalid person details');
  return value;
}
function person(data: Record<string, unknown>, id: string, actor: string): DataRow {
  if (data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'users' || data.current_actor_id !== actor ||
      data.can_manage !== true || !Array.isArray(data.allowed_operations) || !data.allowed_operations.includes('updateUser') || !isObject(data.resource) || data.resource.id !== id) throw new Error('Person unavailable');
  const row = parseCoreRow('users', 'canonical_evidence_ledger', data.resource);
  if (!['app', 'direct'].includes(String(row.member_type)) || row.collect_user_id !== id || row.operator_admin_id !== null ||
      !['active', 'suspended'].includes(row.status) || !isSafeCount(row.version) || row.version < 1) throw new Error('Person unavailable');
  return row;
}
function samePerson(left: DataRow, right: DataRow): boolean {
  return ['id', 'version', 'public_id', 'member_type', 'display_name', 'momo_provider', 'momo_number', 'momo_pay_code', 'phone_e164', 'email', 'status', 'operator_admin_id'].every(key => left[key] === right[key]);
}

/** Check every membership window; server repeats ownership and operator guards atomically at commit. */
async function canSuspend(request: FeatureAccess['request'], id: string, actor: string, principal: string, original: DataRow, isCurrent: () => boolean): Promise<boolean> {
  if (id === principal) return false;
  const owners = new Set<string>(), seen = new Set<string>(); let offset = 0, total: number | null = null;
  do {
    const query = new URLSearchParams({ relation: 'memberships', limit: '100', offset: String(offset) });
    const data = await request(`operations/users/${id}?${query.toString()}`);
    if (!isCurrent()) return false;
    const row = person(data, id, actor);
    if (!samePerson(original, row) || !isObject(data.related) || Object.keys(data.related).length !== 1 || !Array.isArray(data.related.memberships) ||
        !isObject(data.related_pages) || Object.keys(data.related_pages).length !== 1 || !isObject(data.related_pages.memberships) || data.related_truncated !== false) return false;
    const page = data.related_pages.memberships, rows = data.related.memberships;
    if (Object.keys(page).length !== 4 || !isSafeCount(page.total) || page.total > 1000 || page.limit !== 100 || page.offset !== offset ||
        rows.length !== Math.min(100, Math.max(0, page.total - offset)) || page.next_offset !== (offset + rows.length < page.total ? offset + rows.length : null) ||
        (total !== null && total !== page.total)) return false;
    total = page.total;
    for (const item of rows) {
      if (!isObject(item) || !isId(item.id) || seen.has(item.id) || item.user_id !== id || !isId(item.group_id) ||
          !['owner', 'admin', 'member', 'receiver', 'contributor', 'viewer'].includes(String(item.role)) || !['active', 'removed'].includes(String(item.status))) return false;
      seen.add(item.id);
      if (item.role === 'owner' && item.status === 'active') owners.add(item.group_id);
    }
    offset += rows.length;
  } while (total !== null && offset < total);
  for (const groupId of owners) {
    const data = await request(`operations/groups/${groupId}`);
    if (!isCurrent() || data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'groups' || data.current_actor_id !== actor ||
        !isObject(data.resource) || data.resource.id !== groupId) return false;
    const row = parseCoreRow('groups', 'canonical_evidence_ledger', data.resource);
    if (row.status === 'active') return false;
  }
  return isCurrent();
}

/** Canonical user editing is disabled until the migration is qualified. */
export function UserEditPage(props: UserEditProps) {
  return props.financialModel === 'transaction_journals' ? <LegacyUserEditPage {...props} /> : <CanonicalUserEditPage {...props} />;
}

function CanonicalUserEditPage({ id, returnArea = 'users', request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh }: UserEditProps) {
  const stableIdentity = usePendingIdentity(identity);
  const allowed = financialModel === 'canonical_evidence_ledger' && role !== 'staff' && isId(id) && typeof principalId === 'string' && isId(principalId) &&
    permissions.includes('users.read') && permissions.includes(PERMISSION) && stableIdentity.permissions.includes('users.read') && stableIdentity.permissions.includes(PERMISSION) && stableIdentity.id === actorId && stableIdentity.role === role;
  const [draft, setDraft] = useState<Draft | null>(null), [source, setSource] = useState<DataRow | null>(null);
  const [pending, setPending] = useState<PendingAttempt | null>(null), [review, setReview] = useState<Record<string, unknown> | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'sending' | 'checking' | 'success' | 'error'>('loading');
  const [scopeLoaded, setScopeLoaded] = useState(''), [message, setMessage] = useState(''), [retryAllowed, setRetryAllowed] = useState(false);
  const current = useRef(authorityKey), gate = useRef(allowMutations), busy = useRef(false);
  useLayoutEffect(() => { current.current = authorityKey; return () => { current.current = ''; }; }, [authorityKey]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const scope = JSON.stringify([authorityKey, id]);
  const active = () => current.current === authorityKey && Date.parse(stableIdentity.expiresAt) > Date.now();
  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController(); let live = true;
    readPending(stableIdentity, FAMILY, id).then(async saved => {
      if (saved && (saved.permission !== PERMISSION || !isSafeCount(saved.intent.expected_version) || saved.intent.expected_version < 1)) throw new Error('Invalid recovery');
      const row = !saved && allowMutations ? person(await request(`operations/users/${id}`, { signal: controller.signal }), id, actorId) : null;
      if (!live || current.current !== authorityKey) return;
      setPending(saved); setSource(row);
      if (row) setDraft({ display_name: String(row.display_name ?? ''), momo_provider: String(row.momo_provider ?? 'mtn_momo'), momo_number: String(row.momo_number ?? ''), momo_pay_code: String(row.momo_pay_code ?? ''), status: row.status, reason: '' });
      setScopeLoaded(scope); setState('ready');
      if (saved) setMessage('A previous person change needs recovery. Check its original request before continuing.');
      else if (!allowMutations) setMessage('Person editing is not enabled for this workspace.');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('The person or recovery record could not be verified. Operator accounts are managed separately.'); } });
    return () => { live = false; controller.abort(); };
  }, [allowed, allowMutations, request, actorId, authorityKey, id, scope, stableIdentity]);
  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || !draft || !source || pending || state !== 'ready' || !active()) return;
    try { setReview(intent({ display_name: draft.display_name.trim(), momo_provider: draft.momo_provider, momo_number: draft.momo_number.trim(),
      momo_pay_code: draft.momo_pay_code.trim(), status: draft.status, reason: draft.reason.trim(), expected_version: source.version }, source)); setMessage(''); }
    catch { setMessage('Check the recorded name, MoMo details and reason. Direct members need a recorded MoMo number.'); }
  };
  const send = async (body: Record<string, unknown>, key: string) => {
    if (!allowed || !allowMutations || !principalId || !source || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null;
    try {
      const latest = person(await request(`operations/users/${id}`), id, actorId), checked = intent(body, latest);
      if (!samePerson(source, latest) || checked.expected_version !== latest.version || !active() || !gate.current) throw new Error('Person changed');
      if (checked.status === 'suspended' && (!permissions.includes('collections.read') || !stableIdentity.permissions.includes('collections.read') ||
          !await canSuspend(request, id, actorId, principalId, latest, () => active() && gate.current))) throw new Error('Active group ownership cannot be ruled out');
      if (!await verifyFresh() || !active() || !gate.current) throw new Error('Verification required');
      retained = await retainPending(stableIdentity, FAMILY, id, key, PERMISSION, checked);
      if (!active() || !gate.current) return;
      setPending(retained); setRetryAllowed(false);
      const receipt = await request(`operations/users/${id}`, { method: 'PATCH', body: checked, idempotencyKey: key });
      if (!active()) return;
      if (!await matchesCanonicalReceipt(receipt, principalId, key, {resourceType: 'users', version: (checked.expected_version as number) + 1, resourceId: id})) throw new Error('Invalid receipt');
      await clearOriginalAttempt(stableIdentity, retained, active);
      if (!active()) return;
      setPending(null); setReview(null); setState('success'); setMessage('The person was updated.');
    } catch {
      if (!active()) return;
      const stored = retained ?? await readPending(stableIdentity, FAMILY, id).catch(() => null);
      setPending(stored); setReview(null); setState('ready'); setMessage(stored ? 'The result is unconfirmed. Check the original request before another change.' : 'The person, active-group ownership or verification could not be confirmed. No change was submitted.');
    } finally { busy.current = false; }
  };
  const check = async () => {
    if (!pending || !principalId || !active() || busy.current) return;
    if (!permissions.includes('overview.read') || !permissions.includes('account.manage')) { setMessage('Your account cannot check request history. Contact an authorized administrator.'); return; }
    busy.current = true; const original = pending; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const data = await lookupCanonicalMutation(request, principalId, original.request_key);
      if (!active()) return;
      if (data.status === 'not_found') {
        setRetryAllowed(allowMutations); setMessage(allowMutations ? 'No completed request was found. You may check again or review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.');
      } else {
        if (data.status === 'succeeded') {
          if (!await matchesCanonicalReceipt(data.receipt, principalId, original.request_key, {resourceType: 'users', version: (original.intent.expected_version as number) + 1, resourceId: id})) throw new Error('Invalid receipt');
          await clearOriginalAttempt(stableIdentity, original, active);
          if (!active()) return;
          setPending(null); setState('success'); setMessage('The original person change was recorded.'); return;
        }
        if (data.status === 'cancelled') {
          await clearOriginalAttempt(stableIdentity, original, active);
          if (!active()) return;
          setPending(null); setState('error'); setMessage('The original request was cancelled. Reopen the current person before editing.'); return;
        }
        setMessage('The request is still unconfirmed. Check again before continuing.');
      }
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const reviewSame = async () => {
    if (!pending || !retryAllowed || !allowMutations || busy.current || !active()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      const latest = person(await request(`operations/users/${id}`), id, actorId), original = intent(pending.intent, latest);
      if (original.expected_version !== latest.version || !active() || !gate.current) throw new Error('Person changed');
      setSource(latest); setReview(original); setRetryAllowed(false);
    } catch { if (active()) { setRetryAllowed(false); setMessage('The current person could not be verified. Check the original request again.'); } }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };

  return <>
    <PageHeader title="Edit person" subtitle="Changes use the current person version; sign-in identifiers are managed separately." actions={<Button type="button" onClick={() => navigate(isId(id) ? `/admin/${returnArea}/${id}` : `/admin/${returnArea}`)}>Back to person</Button>} />
    {!allowed ? <ErrorState title="Editing unavailable" message="This operation is not enabled for the current account and workspace." /> : state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> :
      state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Change recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/${returnArea}/${id}`)}>View person</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && draft && source && <form className="core-edit-form" onSubmit={makeReview}>
          <p>Person: {String(source.public_id)} · {String(source.member_type)}. Email and login number require a separate verified workflow.</p>
          <label>Recorded full name<input className="admin-input" value={draft.display_name} maxLength={120} required onChange={event => setDraft({ ...draft, display_name: event.target.value })} /></label>
          <label>MoMo provider<select className="admin-input" value={draft.momo_provider} onChange={event => setDraft({ ...draft, momo_provider: event.target.value })}><option value="mtn_momo">MTN MoMo</option><option value="airtel_money">Airtel Money</option></select></label>
          <label>MoMo number<input className="admin-input" value={draft.momo_number} maxLength={10} onChange={event => setDraft({ ...draft, momo_number: event.target.value })} /></label><label>MoMo code (optional)<input className="admin-input" value={draft.momo_pay_code} maxLength={9} onChange={event => setDraft({ ...draft, momo_pay_code: event.target.value })} /></label>
          <label>Account status<select className="admin-input" value={draft.status} onChange={event => setDraft({ ...draft, status: event.target.value })}><option value="active">Active</option><option value="suspended">Suspended</option></select></label>
          <p>Suspension revokes active sign-in sessions and is unavailable while this person owns an active group, including a public group.</p><label>Reason for change<textarea className="admin-input" value={draft.reason} minLength={8} maxLength={500} required onChange={event => setDraft({ ...draft, reason: event.target.value })} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review person changes</Button>
        </form>}
        {review && allowMutations && source && <section><h2>Review person change</h2><p>Person: {String(source.public_id)} · {String(source.member_type)}</p><dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{value === '' ? 'Not recorded' : String(value)}</dd></div>)}</dl><p>Recorded payment identity is not provider verified. Suspended accounts lose active sessions.</p><Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready'} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No change was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm person changes'}</Button></section>}
      </div></Card>}
  </>;
}
