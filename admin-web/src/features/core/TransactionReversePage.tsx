import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { formatMoney, isId, isObject, isSafeCount, parseCoreRow, paymentReference } from './contracts';
import { canonicalRequestId, clearPending, readPending, retainPending } from './pendingAttempt';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { DataRow, FeatureAccess } from './types';
import './core.css';

export interface TransactionReverseProps extends FeatureAccess {
  id: string;
  identity: PendingIdentity;
  allowMutations?: boolean;
  verifyFresh: () => Promise<boolean>;
}
const FAMILY = 'operating-reversetransaction', PERMISSION = 'payments.reconcile';
interface ReversalTarget { id: string; version: number; groupId: string; groupName: string; memberId: string; evidenceId: string; contributionId: string; amount: number; reference: string; paymentReference: string; receiver: string }
function intent(value: unknown): Record<string, unknown> {
  if (!isObject(value) || Object.keys(value).length !== 2 || !isSafeCount(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER ||
      typeof value.reason !== 'string' || value.reason.trim().length < 8 || value.reason.length > 500) throw new Error('Invalid reversal intent');
  return value;
}
async function receipt(value: unknown, id: string, version: number, principal: string, key: string): Promise<boolean> {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' && value.resource_type === 'transactions' &&
    value.resource_id === id && value.version === version + 1 && value.request_id === await canonicalRequestId(principal, key);
}
async function lock<T>(name: string, run: () => Promise<T>): Promise<T> {
  if (!navigator.locks) throw new Error('A protected request lock is unavailable.');
  return navigator.locks.request(name, { ifAvailable: true }, acquired => { if (!acquired) throw new Error('Another review is in progress.'); return run(); });
}
async function currentTarget(request: FeatureAccess['request'], id: string, actor: string, isCurrent: () => boolean): Promise<ReversalTarget> {
  let offset = 0, total: number | null = null, transaction: DataRow | null = null;
  const entries: DataRow[] = [], seen = new Set<string>();
  do {
    const query = new URLSearchParams({ relation: 'ledger_entries', limit: '100', offset: String(offset) });
    const data = await request(`operations/transactions/${id}?${query.toString()}`);
    if (!isCurrent() || data.contract_version !== 2 || data.model !== 'canonical_evidence_ledger' || data.resource_type !== 'transactions' || data.current_actor_id !== actor ||
        data.can_manage !== true || !Array.isArray(data.allowed_operations) || !data.allowed_operations.includes('reverseTransaction') ||
        !isObject(data.resource) || data.resource.id !== id || !isObject(data.related) || Object.keys(data.related).length !== 1 || !Array.isArray(data.related.ledger_entries) ||
        !isObject(data.related_pages) || Object.keys(data.related_pages).length !== 1 || !isObject(data.related_pages.ledger_entries) || data.related_truncated !== false) throw new Error('Reversal unavailable');
    const row = parseCoreRow('transactions', 'canonical_evidence_ledger', data.resource), page = data.related_pages.ledger_entries, rows = data.related.ledger_entries;
    if (!['reconciled', 'confirmed'].includes(row.status) || !isSafeCount(row.version) || row.version < 1 || row.version >= Number.MAX_SAFE_INTEGER ||
        !isId(row.member_user_id) || row.allocated_amount_rwf !== row.amount_rwf || typeof row.group_name !== 'string' || typeof row.payee_label !== 'string' ||
        (transaction !== null && (row.version !== transaction.version || row.status !== transaction.status || row.amount_rwf !== transaction.amount_rwf ||
          row.member_user_id !== transaction.member_user_id || row.group_id !== transaction.group_id || row.evidence_id !== transaction.evidence_id ||
          row.provider_reference !== transaction.provider_reference || row.payment_reference !== transaction.payment_reference)) ||
        Object.keys(page).length !== 4 || !isSafeCount(page.total) || page.total > 1000 || page.limit !== 100 || page.offset !== offset ||
        rows.length !== Math.min(100, Math.max(0, page.total - offset)) || page.next_offset !== (offset + rows.length < page.total ? offset + rows.length : null) ||
        (total !== null && total !== page.total)) throw new Error('Reversal unavailable');
    transaction = row; total = page.total;
    for (const input of rows) {
      const entry = parseCoreRow('ledgers', 'canonical_evidence_ledger', input);
      if (seen.has(entry.id) || entry.payment_id !== id || entry.transaction_id !== id || entry.group_id !== row.group_id || entry.evidence_id !== row.evidence_id) throw new Error('Reversal unavailable');
      seen.add(entry.id); entries.push(entry);
    }
    offset += rows.length;
  } while (total !== null && offset < total);
  if (!transaction || entries.length !== 1 || entries[0].kind !== 'contribution' || entries[0].reverses_entry_id !== null ||
      entries[0].signed_amount_rwf !== transaction.amount_rwf || entries[0].member_user_id !== transaction.member_user_id || !isCurrent()) throw new Error('Reversal unavailable');
  return { id, version: transaction.version as number, groupId: String(transaction.group_id), groupName: transaction.group_name as string,
    memberId: String(transaction.member_user_id), evidenceId: String(transaction.evidence_id), contributionId: entries[0].id,
    amount: transaction.amount_rwf as number, reference: String(transaction.provider_reference ?? ''), paymentReference: paymentReference(transaction), receiver: transaction.payee_label as string };
}
function sameTarget(a: ReversalTarget, b: ReversalTarget): boolean { return JSON.stringify(a) === JSON.stringify(b); }

/** Canonical ledger reversal is opt-in pending end-to-end migration qualification. */
export function TransactionReversePage({ id, request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh }: TransactionReverseProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const allowed = financialModel === 'canonical_evidence_ledger' && role !== 'staff' && isId(id) && typeof principalId === 'string' && isId(principalId) &&
    ['payments.read', PERMISSION].every(permission => permissions.includes(permission) && stableIdentity.permissions.includes(permission)) && stableIdentity.id === actorId && stableIdentity.role === role;
  const canWrite = allowed && permissions.includes('ledger.read') && stableIdentity.permissions.includes('ledger.read');
  const scope = JSON.stringify([authorityKey, id]), current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const active = () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now();
  const [target, setTarget] = useState<ReversalTarget | null>(null), [reason, setReason] = useState('');
  const [pending, setPending] = useState<PendingAttempt | null>(null), [review, setReview] = useState<Record<string, unknown> | null>(null), [retryAllowed, setRetryAllowed] = useState(false), [acknowledged, setAcknowledged] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'sending' | 'checking' | 'success' | 'error'>('loading');
  const [scopeLoaded, setScopeLoaded] = useState(''), [message, setMessage] = useState('');
  useEffect(() => {
    if (!allowed) return;
    let live = true;
    readPending(stableIdentity, FAMILY, id).then(async saved => {
      if (saved && (saved.permission !== PERMISSION || !isSafeCount(saved.intent.expected_version) || saved.intent.expected_version < 1)) throw new Error('Invalid recovery');
      const target = !saved && allowMutations && canWrite ? await currentTarget(request, id, actorId, () => live && current.current === scope) : null;
      if (!live || current.current !== scope) return;
      setPending(saved); setTarget(target); setScopeLoaded(scope); setState('ready');
      if (saved) setMessage('A previous reversal needs recovery. Check its original request before continuing.');
      else if (!allowMutations) setMessage('Ledger reversal is not enabled for this workspace.');
      else if (!canWrite) setMessage('Ledger-read permission is required to verify the original contribution.');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('The transaction, contribution or recovery record could not be verified.'); } });
    return () => { live = false; };
  }, [allowed, allowMutations, canWrite, stableIdentity, request, id, actorId, scope]);
  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || !canWrite || !target || pending || state !== 'ready' || !active()) return;
    try { setReview(intent({ expected_version: target.version, reason: reason.trim() })); setAcknowledged(false); setMessage(''); }
    catch { setMessage('Provide a reason of 8 to 500 characters.'); }
  };
  const send = async (body: Record<string, unknown>, key: string) => {
    if (!canWrite || !allowMutations || !principalId || !target || !acknowledged || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null, dispatched = false;
    try {
      const checked = intent(body);
      await lock(`collect-admin-canonical-reconciliation:${principalId}:${id}`, async () => {
        if (pending) {
          if (!permissions.includes('overview.read') || !permissions.includes('account.manage')) throw new Error('Request lookup unavailable');
          const outcome = await request(`operations/requests/${key}`);
          if (!active() || !gate.current || outcome.contract_version !== 2 || outcome.model !== 'canonical_evidence_ledger') throw new Error('Invalid lookup');
          if (outcome.status !== 'not_found') {
            if (Object.keys(outcome).length !== 5 || outcome.request_id !== await canonicalRequestId(principalId, key)) throw new Error('Invalid lookup');
            if (outcome.status === 'succeeded') {
              if (!await receipt(outcome.receipt, id, checked.expected_version as number, principalId, key)) throw new Error('Invalid receipt');
              await clearPending(stableIdentity, FAMILY, id, key); if (!active()) return;
              setPending(null); setReview(null); setState('success'); setMessage('The original contribution reversal was recorded.'); return;
            }
            if (outcome.status === 'cancelled' && outcome.receipt === null) {
              await clearPending(stableIdentity, FAMILY, id, key); if (!active()) return;
              setPending(null); setReview(null); setState('error'); setMessage('The original request was cancelled. Reopen the transaction before continuing.'); return;
            }
            throw new Error('Original request is unconfirmed');
          }
          if (Object.keys(outcome).length !== 3) throw new Error('Invalid lookup');
        }
        const latest = await currentTarget(request, id, actorId, () => active() && gate.current);
        if (!sameTarget(target, latest) || checked.expected_version !== latest.version || !active() || !gate.current || !await verifyFresh() || !active() || !gate.current) throw new Error('Transaction changed');
        if (!pending && await readPending(stableIdentity, FAMILY, id)) throw new Error('Original request needs review');
        retained = await retainPending(stableIdentity, FAMILY, id, key, PERMISSION, checked);
        if (!active() || !gate.current) return;
        setPending(retained); setRetryAllowed(false); dispatched = true;
        const result = await request(`operations/transactions/${id}/reverse`, { method: 'POST', body: checked, idempotencyKey: key });
        if (!active() || !await receipt(result, id, checked.expected_version as number, principalId, key)) throw new Error('Invalid receipt');
        await clearPending(stableIdentity, FAMILY, id, key); if (!active()) return;
        setPending(null); setReview(null); setState('success'); setMessage('The contribution reversal was recorded.');
      });
    } catch {
      if (!active()) return;
      let storageFailed = false;
      const saved = retained ?? await readPending(stableIdentity, FAMILY, id).catch(() => { storageFailed = true; return null; });
      setPending(saved); setReview(null); setAcknowledged(false);
      if (storageFailed || dispatched && !saved) { setState('error'); setMessage('Recovery storage could not be verified. Check the original request before another change.'); }
      else { setState('ready'); setMessage(saved ? 'The result is unconfirmed. Check the original request before another change.' : 'The transaction, contribution or verification could not be confirmed. No reversal was submitted.'); }
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
        let retryable = false; try { intent(original.intent); retryable = allowMutations && canWrite; } catch { /* Unsupported retained intents can still be checked. */ }
        setRetryAllowed(retryable); setMessage(retryable ? 'No completed request was found. You may check again or review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.');
      } else {
        if (Object.keys(data).length !== 5 || data.request_id !== await canonicalRequestId(principalId, original.request_key)) throw new Error('Invalid lookup');
        if (data.status === 'succeeded') {
          if (!await receipt(data.receipt, id, original.intent.expected_version as number, principalId, original.request_key)) throw new Error('Invalid receipt');
          await clearPending(stableIdentity, FAMILY, id, original.request_key); if (!active()) return;
          setPending(null); setState('success'); setMessage('The original contribution reversal was recorded.'); return;
        }
        if (data.receipt !== null) throw new Error('Invalid receipt');
        if (data.status === 'cancelled') {
          await clearPending(stableIdentity, FAMILY, id, original.request_key); if (!active()) return;
          setPending(null); setState('error'); setMessage('The original request was cancelled. Reopen the transaction before continuing.'); return;
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
      const original = intent(pending.intent), latest = await currentTarget(request, id, actorId, () => active() && gate.current);
      if (original.expected_version !== latest.version || !active() || !gate.current) throw new Error('Transaction changed');
      setTarget(latest); setReview(original); setRetryAllowed(false); setAcknowledged(false);
    } catch { if (active()) { setRetryAllowed(false); setMessage('The current transaction and contribution could not be verified. Check the original request again.'); } }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };

  return <>
    <PageHeader title="Reverse contribution" subtitle="Record an opposite ledger entry for the reviewed contribution." actions={<Button type="button" onClick={() => navigate(isId(id) ? `/admin/transactions/${id}` : '/admin/transactions')}>Back to transaction</Button>} />
    {!allowed ? <ErrorState title="Reversal unavailable" message="This operation is not enabled for the current account and workspace." /> : state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> :
      state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Reversal recorded</h2><p>{message}</p><p>This does not refund or move provider funds.</p><Button type="button" onClick={() => navigate(`/admin/transactions/${id}`)}>View transaction</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && canWrite && target && <form className="core-edit-form" onSubmit={makeReview}><p>Group: {target.groupName}. Contribution: {formatMoney(target.amount)}. Member ID: {target.memberId}.</p><label>Reason for reversal<textarea className="admin-input" value={reason} minLength={8} maxLength={500} required onChange={event => setReason(event.target.value)} /></label><p>This records an opposite contribution entry. It does not refund or move provider funds.</p><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review reversal</Button></form>}
        {review && target && allowMutations && canWrite && <section><h2>Review contribution reversal</h2><p>Group: {target.groupName}. Contribution: {formatMoney(target.amount)}. Member ID: {target.memberId}.</p><p>Evidence: {target.evidenceId}. Original contribution: {target.contributionId}. Reference: {target.paymentReference}. Receiver: {target.receiver || 'Not recorded'}.</p><p>Reason: {String(review.reason)}. This records an opposite ledger entry and does not refund or move provider funds.</p><label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed the contribution and understand that this is a ledger reversal.</label><Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); setAcknowledged(false); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !acknowledged} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No reversal was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm reversal'}</Button></section>}
      </div></Card>}
  </>;
}
