import { useEffect, useLayoutEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { formatMoney, isId } from './contracts';
import { clearPending, readPending, retainPending } from './pendingAttempt';
import {usePendingIdentity} from './usePendingIdentity';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { FeatureAccess } from './types';
import {isLegacyJournalReceipt, parseLegacyJournalOutcome, verifyLegacyJournalScope, withLegacyJournalLock} from './legacyJournalRequest';
import {parseJournalPostingIntent} from './legacyJournalInputs';
import {readExistingJournal} from './legacyJournalSources';
import './core.css';

export interface LegacyJournalPostProps extends FeatureAccess {
  id: string;
  identity: PendingIdentity;
  allowMutations?: boolean;
}
const FAMILY = 'operating-postjournal', PERMISSION = 'ledger.manage';
type VerifiedDraft = Awaited<ReturnType<typeof readExistingJournal>>;
type PostingIntent = ReturnType<typeof parseJournalPostingIntent>;

/** Posts a legacy double-entry draft. Disabled until deployment and rollback are qualified. */
export function LegacyJournalPostPage({ id, request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, allowMutations = false }: LegacyJournalPostProps) {
  const stableIdentity = usePendingIdentity(identity);
  const has = (name: string) => permissions.includes(name) && stableIdentity.permissions.includes(name);
  const allowed = financialModel === 'transaction_journals' && role !== 'staff' && isId(id) && isId(actorId) && stableIdentity.id === actorId && stableIdentity.role === role && has(PERMISSION);
  const canCheck = allowed && has('overview.read');
  const canWrite = canCheck && has('ledger.read') && has('collections.read');
  const canReadPayments = has('payments.read');
  const scope = JSON.stringify([authorityKey, id, financialModel, stableIdentity, [...new Set(permissions)].sort()]), current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const active = () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now();
  const [pending, setPending] = useState<PendingAttempt | null>(null), [reason, setReason] = useState(''), [review, setReview] = useState<PostingIntent | null>(null);
  const [source, setSource] = useState<VerifiedDraft | null>(null), [retryAllowed, setRetryAllowed] = useState(false), [acknowledged, setAcknowledged] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading');
  const [scopeLoaded, setScopeLoaded] = useState(''), [message, setMessage] = useState('');
  useEffect(() => {
    if (!allowed) return;
    let live = true;
    readPending(stableIdentity, FAMILY, id).then(saved => {
      if (saved && (saved.permission !== PERMISSION || saved.resource_id !== id)) throw new Error('Invalid recovery');
      if (saved) parseJournalPostingIntent(saved.intent);
      if (!live || current.current !== scope) return;
      setPending(saved); setScopeLoaded(scope); setState('ready'); setReview(null); setSource(null); setRetryAllowed(false); setAcknowledged(false);
      setMessage(saved ? 'A previous posting needs recovery. Check its original request before continuing.' : !allowMutations ? 'Journal posting is not enabled for this workspace.' : !canWrite ? 'Ledger, group and request-history read permissions are required to post.' : '');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('Posting recovery data could not be verified.'); } });
    return () => { live = false; };
  }, [allowed, allowMutations, canWrite, stableIdentity, id, scope]);
  const reviewRequest = async (body?: PostingIntent) => {
    if (!allowMutations || !canWrite || busy.current || !active()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      if (pending && !body) throw new Error('Check pending first');
      const latest = await readExistingJournal(request, id, actorId, canReadPayments, 'post', body?.expected_version);
      const checked = parseJournalPostingIntent(body ?? { expected_version: latest.version, reason: reason.trim() });
      if (!active() || !gate.current) return;
      setSource(latest); setReview(checked); setRetryAllowed(false); setAcknowledged(false);
    } catch { if (active()) setMessage('The complete journal, active group, accounts or linked allocation could not be verified. No posting was submitted.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const send = async (body: PostingIntent, key: string) => {
    if (!canWrite || !allowMutations || !source || !acknowledged || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null, dispatched = false;
    try {
      const checked = parseJournalPostingIntent(body);
      await withLegacyJournalLock(`collect-admin-legacy-journal:${actorId}:${id}`, async () => {
        if (pending) {
          const original = parseLegacyJournalOutcome(await request(`operations/requests/${key}`), checked.expected_version + 1, id);
          if (!active() || !gate.current) return;
          if (original.status === 'succeeded' && original.receipt) {
            await verifyLegacyJournalScope(request, key, original.receipt, 'journals.post.post'); if (!active() || !gate.current) return;
            await clearPending(stableIdentity, FAMILY, id, key); if (!active()) return;
            setPending(null); setReview(null); setState('success'); setMessage('The original journal posting was recorded.'); return;
          }
          if (original.status !== 'not_found') throw new Error('Original request unresolved');
        }
        const latest = await readExistingJournal(request, id, actorId, canReadPayments, 'post', checked.expected_version);
        if (JSON.stringify(latest) !== JSON.stringify(source) || !active() || !gate.current) throw new Error('Journal changed');
        if (!pending && await readPending(stableIdentity, FAMILY, id)) throw new Error('Original request needs review');
        retained = await retainPending(stableIdentity, FAMILY, id, key, PERMISSION, checked);
        if (!active() || !gate.current) return;
        setPending(retained); setRetryAllowed(false); dispatched = true;
        const direct = await request(`operations/journals/${id}/post`, { method: 'POST', body: checked, idempotencyKey: key });
        if (!active() || !isLegacyJournalReceipt(direct, checked.expected_version + 1, id)) throw new Error('Invalid receipt');
        const original = parseLegacyJournalOutcome(await request(`operations/requests/${key}`), checked.expected_version + 1, id);
        if (!active() || original.status !== 'succeeded' || !original.receipt || !(['request_id', 'resource_type', 'resource_id', 'version', 'status'] as const).every(field => original.receipt![field] === direct[field])) throw new Error('Unverified receipt');
        await verifyLegacyJournalScope(request, key, original.receipt, 'journals.post.post'); if (!active() || !gate.current) return;
        await clearPending(stableIdentity, FAMILY, id, key); if (!active()) return;
        setPending(null); setReview(null); setState('success'); setMessage('The journal posting was recorded.');
      });
    } catch {
      if (!active()) return;
      let storageFailed = false; const saved = retained ?? await readPending(stableIdentity, FAMILY, id).catch(() => { storageFailed = true; return null; });
      setPending(saved); setReview(null); setSource(null); setAcknowledged(false);
      if (storageFailed || dispatched && !saved) { setState('error'); setMessage('Recovery data could not be verified. Check the original request before another change.'); }
      else { setState('ready'); setMessage(saved ? 'The result is unconfirmed. Check the original posting request before continuing.' : 'The journal or request lock could not be verified. No posting was submitted.'); }
    } finally { busy.current = false; }
  };
  const check = async () => {
    if (!pending || !active() || busy.current) return;
    if (!canCheck) { setMessage('Your account cannot check request history. Contact an authorized administrator.'); return; }
    busy.current = true; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const saved = parseJournalPostingIntent(pending.intent), result = parseLegacyJournalOutcome(await request(`operations/requests/${pending.request_key}`), saved.expected_version + 1, id);
      if (!active()) return;
      if (result.status === 'succeeded' && result.receipt) {
        await verifyLegacyJournalScope(request, pending.request_key, result.receipt, 'journals.post.post'); if (!active()) return;
        await clearPending(stableIdentity, FAMILY, id, pending.request_key); if (!active()) return;
        setPending(null); setState('success'); setMessage('The original journal posting was recorded.'); return;
      }
      if (result.status === 'not_found') { setRetryAllowed(allowMutations && canWrite); setMessage(allowMutations && canWrite ? 'No completed request was found. You may review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.'); }
      else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh the record.' : 'The request is still pending. Check again before continuing.');
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const submitReview = (event: FormEvent) => { event.preventDefault(); void reviewRequest(); };
  return <>
    <PageHeader title="Post journal" subtitle="Review a legacy double-entry draft before posting." actions={<Button type="button" onClick={() => navigate(isId(id) ? `/admin/ledgers/${id}` : '/admin/ledgers')}>Back to ledger</Button>} />
    {!allowed ? <ErrorState title="Posting unavailable" message={financialModel === 'canonical_evidence_ledger' ? 'Journal posting is unavailable for the canonical evidence ledger.' : 'Your account cannot post journals in this workspace.'} /> :
      state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Journal posted</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/ledgers/${id}`)}>View ledger</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Journal: {id} · Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewRequest(parseJournalPostingIntent(pending.intent))}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && canWrite && <form className="core-edit-form" onSubmit={submitReview}><label>Reason for posting<textarea className="admin-input" value={reason} minLength={8} maxLength={1000} required onChange={event => setReason(event.target.value)} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review journal</Button></form>}
        {review && source && allowMutations && canWrite && <section><h2>Review journal posting</h2><p>{source.description} · {source.groupTitle} · version {source.version}</p><p>Journal {source.id} · Group {source.groupId} · Creator {source.createdBy} · Last editor {source.editedBy}</p><p>Debit total: {formatMoney(source.total)} · Credit total: {formatMoney(source.total)}</p><div className="admin-table-wrap" role="region" aria-label="Journal entries"><table className="admin-table"><thead><tr><th scope="col">Line</th><th scope="col">Account</th><th scope="col">Debit</th><th scope="col">Credit</th><th scope="col">Description</th></tr></thead><tbody>{source.lines.map((line, index) => <tr key={line.id}><td>{index + 1}</td><td>{line.accountCode} · {line.accountName} · {line.accountId}</td><td>{formatMoney(line.debit)}</td><td>{formatMoney(line.credit)}</td><td>{line.description || '—'}</td></tr>)}</tbody></table></div>
          {source.allocationId && <p>Confirmed transaction {source.transactionId} · Allocation {source.allocationId} · Member {source.memberId ?? 'Not recorded'}. Posting may queue a member email notification.</p>}
          <p>Reason: {review.reason}. Posting records this journal; it does not establish provider settlement. The server checks account totals and independent approval at posting.</p><label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed every debit and credit and the posting reason.</label>
          <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); setSource(null); setAcknowledged(false); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !acknowledged} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No journal was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm posting'}</Button>
        </section>}
      </div></Card>}
  </>;
}
