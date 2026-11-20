import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { isId, isObject, isSafeCount, parseCoreRow } from './contracts';
import { canonicalRequestId, clearPending, readPending, retainPending } from './pendingAttempt';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { FeatureAccess } from './types';
import './core.css';

export interface PayeeEditProps extends FeatureAccess {
  id: string;
  identity: PendingIdentity;
  allowMutations?: boolean;
  verifyFresh: () => Promise<boolean>;
}

const FAMILY = 'operating-updatepayee', PERMISSION = 'receivers.manage';
const FIELDS = ['label', 'network', 'momo_number_or_code', 'status', 'reason', 'expected_version'];
type Draft = { label: string; network: string; momo_number_or_code: string; reason: string };
function intent(value: unknown): Record<string, unknown> {
  if (!isObject(value) || Object.keys(value).length !== FIELDS.length || !FIELDS.every(key => key in value) ||
      typeof value.label !== 'string' || value.label.trim().length < 2 || value.label.length > 120 ||
      !['mtn_momo', 'airtel_money'].includes(String(value.network)) || typeof value.momo_number_or_code !== 'string' ||
      !/^(?:07[2389]\d{7}|\+?2507[2389]\d{7})$/.test(value.momo_number_or_code) || value.status !== 'active' ||
      typeof value.reason !== 'string' || value.reason.trim().length < 8 || value.reason.length > 500 ||
      !isSafeCount(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER) throw new Error('Invalid receiver details');
  return value;
}
function resource(data: Record<string, unknown>, id: string, actorId: string, recovering: boolean): Record<string, unknown> {
  if (data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'payees' ||
      data.current_actor_id !== actorId || typeof data.can_manage !== 'boolean' || !Array.isArray(data.allowed_operations) ||
      (!recovering && (data.can_manage !== true || !data.allowed_operations.includes('updatePayee'))) || !isObject(data.resource) ||
      data.resource.id !== id || data.resource.group_id !== id || !isSafeCount(data.resource.version) || data.resource.version < 1) throw new Error('Receiver unavailable');
  const row = parseCoreRow('payees', 'canonical_evidence_ledger', data.resource);
  if ((!recovering && row.status !== 'active') || typeof row.label !== 'string') throw new Error('Receiver unavailable');
  return row;
}
async function validReceipt(value: unknown, id: string, version: number, principal: string, key: string): Promise<boolean> {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' && value.resource_type === 'payees' &&
    value.resource_id === id && value.version === version + 1 && value.request_id === await canonicalRequestId(principal, key);
}

/** Canonical receiver updates are opt-in after release and old-tab qualification. */
export function PayeeEditPage({ id, request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh }: PayeeEditProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const allowed = financialModel === 'canonical_evidence_ledger' && role !== 'staff' && permissions.includes('receivers.read') && permissions.includes(PERMISSION) &&
    stableIdentity.permissions.includes(PERMISSION) && stableIdentity.id === actorId && stableIdentity.role === role && isId(id) && typeof principalId === 'string' && isId(principalId);
  const [draft, setDraft] = useState<Draft | null>(null), [version, setVersion] = useState<number | null>(null);
  const [pending, setPending] = useState<PendingAttempt | null>(null), [review, setReview] = useState<Record<string, unknown> | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'sending' | 'checking' | 'success' | 'error'>('loading');
  const [message, setMessage] = useState(''), [loadedScope, setLoadedScope] = useState('');
  const [retryAllowed, setRetryAllowed] = useState(false);
  const current = useRef(authorityKey), gate = useRef(allowMutations), busy = useRef(false);
  useLayoutEffect(() => { current.current = authorityKey; return () => { current.current = ''; }; }, [authorityKey]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const scope = JSON.stringify([authorityKey, id]);
  const active = () => current.current === authorityKey && Date.parse(stableIdentity.expiresAt) > Date.now();
  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController(); let live = true;
    readPending(stableIdentity, FAMILY, id).then(async stored => {
      if (!stored && !allowMutations) {
        if (live) { setLoadedScope(scope); setState('ready'); setMessage('Receiver editing is not enabled for this workspace.'); }
        return null;
      }
      if (stored && (stored.permission !== PERMISSION || !isSafeCount(stored.intent.expected_version) || stored.intent.expected_version < 1)) throw new Error('Invalid recovery');
      return { stored, data: await request(`operations/payees/${id}`, { signal: controller.signal }) };
    }).then(result => {
      if (!result) return;
      const row = resource(result.data, id, actorId, result.stored !== null);
      if (!live || current.current !== authorityKey) return;
      setDraft({ label: String(row.label), network: String(row.network), momo_number_or_code: String(row.momo_number_or_code), reason: '' });
      setVersion(row.version as number); setPending(result.stored); setLoadedScope(scope); setState('ready');
    }).catch(() => { if (live) { setLoadedScope(scope); setState('error'); setMessage('The receiver or recovery record could not be verified.'); } });
    return () => { live = false; controller.abort(); };
  }, [allowed, allowMutations, request, actorId, authorityKey, id, scope, stableIdentity]);

  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || !draft || version === null || pending || state !== 'ready' || !active()) return;
    try { setReview(intent({ label: draft.label.trim(), network: draft.network, momo_number_or_code: draft.momo_number_or_code.trim(),
      status: 'active', reason: draft.reason.trim(), expected_version: version })); setMessage(''); }
    catch { setMessage('Check the recorded receiver and provide a reason of 8 to 500 characters.'); }
  };
  const send = async (body: Record<string, unknown>, key: string) => {
    if (!allowed || !allowMutations || !principalId || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null;
    try {
      const checked = intent(body), row = resource(await request(`operations/payees/${id}`), id, actorId, false);
      if (row.version !== checked.expected_version || !active() || !gate.current || !await verifyFresh() || !active() || !gate.current) throw new Error('Receiver or verification changed');
      retained = await retainPending(stableIdentity, FAMILY, id, key, PERMISSION, checked);
      if (!active() || !gate.current) return;
      setPending(retained); setRetryAllowed(false);
      const receipt = await request(`operations/payees/${id}`, { method: 'PATCH', body: checked, idempotencyKey: key });
      if (!active()) return;
      if (!await validReceipt(receipt, id, checked.expected_version as number, principalId, key)) throw new Error('Invalid receipt');
      await clearPending(stableIdentity, FAMILY, id, key);
      if (!active()) return;
      setPending(null); setReview(null); setState('success'); setMessage('The recorded receiver was updated.');
    } catch {
      if (!active()) return;
      const stored = retained ?? await readPending(stableIdentity, FAMILY, id).catch(() => null);
      setPending(stored); setReview(null); setState('ready'); setMessage(stored ? 'The result is unconfirmed. Check the original request before another change.' : 'The receiver or verification could not be confirmed. No change was submitted.');
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
        let retryable = false; try { intent(original.intent); retryable = allowMutations; } catch { /* Other intents can be checked without being reconstructed. */ }
        setRetryAllowed(retryable); setMessage(retryable ? 'No completed request was found. You may check again or review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.');
      } else {
        if (Object.keys(data).length !== 5 || data.request_id !== await canonicalRequestId(principalId, original.request_key)) throw new Error('Invalid lookup');
        if (data.status === 'succeeded') {
          if (!await validReceipt(data.receipt, id, original.intent.expected_version as number, principalId, original.request_key)) throw new Error('Invalid receipt');
          await clearPending(stableIdentity, FAMILY, id, original.request_key);
          if (!active()) return;
          setPending(null); setState('success'); setMessage('The original receiver change was recorded.'); return;
        }
        if (data.receipt !== null) throw new Error('Invalid receipt');
        if (data.status === 'cancelled') {
          await clearPending(stableIdentity, FAMILY, id, original.request_key);
          if (!active()) return;
          setPending(null); setState('error'); setMessage('The original request was cancelled. Reopen the current receiver before editing.'); return;
        }
        setMessage('The request is still unconfirmed. Check again before continuing.');
      }
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };

  return <>
    <PageHeader title="Edit recorded receiver" subtitle="Changes use the current group version." actions={<Button type="button" onClick={() => navigate(isId(id) ? `/admin/payees/${id}` : '/admin/payees')}>Back to receiver</Button>} />
    {!allowed ? <ErrorState title="Editing unavailable" message="This operation is not enabled for the current account and workspace." /> :
      state === 'loading' || loadedScope !== scope ? <LoadingState label="Loading receiver" /> : state === 'error' ? <ErrorState message={message} /> :
      state === 'success' ? <Card><div className="core-detail" role="status"><h2>Change recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/payees/${id}`)}>View receiver</Button></div></Card> :
      !draft || version === null ? <ErrorState title="Editing unavailable" message={message || 'The receiver could not be verified.'} /> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(intent(pending.intent)); setRetryAllowed(false); }}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && <form className="core-edit-form" onSubmit={makeReview}>
          <label>Recorded receiver name<input className="admin-input" value={draft.label} maxLength={120} required onChange={event => setDraft({ ...draft, label: event.target.value })} /></label>
          <label>MoMo provider<select className="admin-input" value={draft.network} onChange={event => setDraft({ ...draft, network: event.target.value })}><option value="mtn_momo">MTN MoMo</option><option value="airtel_money">Airtel Money</option></select></label>
          <label>Receiver MoMo number<input className="admin-input" value={draft.momo_number_or_code} maxLength={13} required onChange={event => setDraft({ ...draft, momo_number_or_code: event.target.value })} /></label>
          <label>Reason for change<textarea className="admin-input" value={draft.reason} minLength={8} maxLength={500} required onChange={event => setDraft({ ...draft, reason: event.target.value })} /></label>
          <p>Changing the receiver cancels pending payment instructions. Earlier evidence retains its original receiver.</p><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review receiver</Button>
        </form>}
        {review && allowMutations && <section><h2>Review receiver change</h2><dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{String(value)}</dd></div>)}</dl><p>Pending payment instructions will be cancelled. Recorded details do not confirm provider identity or settlement.</p><Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready'} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No change was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm receiver'}</Button></section>}
      </div></Card>}
  </>;
}
