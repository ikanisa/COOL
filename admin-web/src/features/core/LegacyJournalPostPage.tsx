import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { formatMoney, isId, isObject, isSafeCount } from './contracts';
import { clearPending, readPending, retainPending } from './pendingAttempt';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { AdminRequest, FeatureAccess } from './types';
import './core.css';

export interface LegacyJournalPostProps extends FeatureAccess {
  id: string;
  identity: PendingIdentity;
  allowMutations?: boolean;
}
const FAMILY = 'operating-postjournal', PERMISSION = 'ledger.manage';
type Intent = { expected_version: number; reason: string };
type Line = { id: string; accountId: string; accountCode: string; accountName: string; debit: number; credit: number; description: string };
type Snapshot = { id: string; groupId: string; groupTitle: string; groupVersion: number; version: number; description: string; createdBy: string; editedBy: string; allocationId: string | null; transactionId: string | null; memberId: string | null; transactionVersion: number | null; allocationCount: number | null; total: number; lines: Line[]; accounts: { id: string; version: number }[] };
type Receipt = { request_id: string; resource_type: 'journals'; resource_id: string; version: number; status: 'succeeded' };
function intent(value: unknown): Intent {
  if (!isObject(value) || Object.keys(value).length !== 2 || !isSafeCount(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER ||
      typeof value.reason !== 'string' || value.reason !== value.reason.trim() || value.reason.length < 8 || value.reason.length > 1000 || [...value.reason].some(char => { const code = char.codePointAt(0)!; return (code < 32 && ![9, 10, 13].includes(code)) || code === 127; })) throw new Error('Invalid original posting request');
  return { expected_version: value.expected_version, reason: value.reason };
}
function detail(data: Record<string, unknown>, type: string, id: string, actor: string): Record<string, unknown> {
  if (data.contract_version !== undefined || data.model !== undefined || data.resource_type !== type || data.current_actor_id !== actor || data.can_manage !== true ||
      !isObject(data.resource) || data.resource.id !== id) throw new Error('Unverified record');
  return data.resource;
}
function page(data: Record<string, unknown>, name: string, offset: number): { rows: Record<string, unknown>[]; total: number; next: number | null } {
  if (!isObject(data.related) || Object.keys(data.related).length !== 1 || !Array.isArray(data.related[name]) || !isObject(data.related_pages) || Object.keys(data.related_pages).length !== 1 || !isObject(data.related_pages[name])) throw new Error('Unverified related records');
  const rows = data.related[name], p = data.related_pages[name];
  if (!isSafeCount(p.total) || p.limit !== 100 || p.offset !== offset || rows.length !== Math.max(0, Math.min(100, p.total - offset)) ||
      p.next_offset !== (offset + rows.length < p.total ? offset + rows.length : null) || rows.some(row => !isObject(row)) || data.related_truncated !== (p.total > rows.length)) throw new Error('Incomplete related records');
  return { rows: rows as Record<string, unknown>[], total: p.total, next: p.next_offset as number | null };
}
async function snapshot(request: AdminRequest, id: string, actor: string, canReadPayments: boolean, expected?: number): Promise<Snapshot> {
  const response = await request(`operations/journals/${id}?relation=entries&limit=100&offset=0`);
  const journal = detail(response, 'journals', id, actor);
  const entries = page(response, 'entries', 0);
  if (entries.total < 2 || entries.total > 100 || entries.next !== null || !isId(journal.group_id) || journal.status !== 'draft' || journal.currency !== 'RWF' ||
      !isSafeCount(journal.version) || journal.version < 1 || journal.version >= Number.MAX_SAFE_INTEGER || (expected !== undefined && expected !== journal.version) ||
      !isId(journal.created_by_admin_id) || !isId(journal.edited_by_admin_id) || journal.created_by_admin_id === actor || journal.edited_by_admin_id === actor ||
      typeof journal.description !== 'string' || journal.description.trim().length < 3 || journal.description.length > 1000 ||
      !(journal.allocation_id === null || isId(journal.allocation_id)) || !(journal.transaction_id === null || isId(journal.transaction_id)) ||
      ((journal.allocation_id === null) !== (journal.transaction_id === null))) throw new Error('Journal is not eligible');
  const seen = new Set<string>(); let debits = 0n, credits = 0n;
  const lines: Line[] = entries.rows.map((row, index) => {
    if (!isId(row.id) || seen.has(row.id) || row.journal_id !== id || row.group_id !== journal.group_id || !isId(row.account_id) || row.line_number !== index + 1 ||
        !isSafeCount(row.debit_rwf) || !isSafeCount(row.credit_rwf) || ((row.debit_rwf === 0) === (row.credit_rwf === 0)) ||
        typeof row.description !== 'string' || row.description.length > 500 || typeof row.account_code !== 'string' || !row.account_code.trim() || row.account_code.length > 40 ||
        typeof row.account_name !== 'string' || row.account_name.trim().length < 2 || row.account_name.length > 120) throw new Error('Invalid entry');
    seen.add(row.id); debits += BigInt(row.debit_rwf); credits += BigInt(row.credit_rwf);
    return { id: row.id, accountId: row.account_id, accountCode: row.account_code, accountName: row.account_name, debit: row.debit_rwf, credit: row.credit_rwf, description: row.description };
  });
  if (debits !== credits || debits === 0n || debits > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('Unbalanced journal');
  const groupId = journal.group_id;
  const group = detail(await request(`operations/groups/${groupId}`), 'groups', groupId, actor);
  if (group.status !== 'active' || group.currency !== 'RWF' || group.country_code !== 'RW' || typeof group.title !== 'string' || !group.title.trim() || !isSafeCount(group.version) || group.version < 1) throw new Error('Group unavailable');
  const accountIds = [...new Set(lines.map(line => line.accountId))];
  const accounts = await Promise.all(accountIds.map(async accountId => {
    const account = detail(await request(`operations/accounts/${accountId}`), 'accounts', accountId, actor);
    if (account.group_id !== groupId || account.currency !== 'RWF' || account.status !== 'active' || !isSafeCount(account.version) || account.version < 1 ||
        lines.some(line => line.accountId === accountId && (line.accountCode !== account.code || line.accountName !== account.name))) throw new Error('Account unavailable');
    return { id: accountId, version: account.version };
  }));
  let memberId: string | null = null, checkedTransactionVersion: number | null = null, allocationCount: number | null = null;
  if (journal.allocation_id !== null && journal.transaction_id !== null) {
    if (!canReadPayments) throw new Error('Payment read access is required to review this allocation');
    let offset = 0, transactionVersion: number | undefined, found = false;
    do {
      const response = await request(`operations/transactions/${journal.transaction_id}?relation=allocations&limit=100&offset=${offset}`);
      const transaction = detail(response, 'transactions', journal.transaction_id, actor), allocations = page(response, 'allocations', offset);
      if (transaction.group_id !== groupId || transaction.verification_status !== 'confirmation_recorded' || !isSafeCount(transaction.version) || transaction.version < 1 ||
          (transactionVersion !== undefined && transaction.version !== transactionVersion) || (allocationCount !== null && allocations.total !== allocationCount) || allocations.total > 10000) throw new Error('Transaction unavailable');
      transactionVersion = transaction.version; checkedTransactionVersion = transaction.version; allocationCount = allocations.total;
      for (const allocation of allocations.rows) if (allocation.id === journal.allocation_id) {
        if (found || allocation.transaction_id !== journal.transaction_id || allocation.group_id !== groupId || allocation.amount_rwf !== Number(debits) ||
            !(allocation.member_user_id === null || isId(allocation.member_user_id))) throw new Error('Invalid allocation');
        found = true; memberId = allocation.member_user_id as string | null;
      }
      if (allocations.next === null) break;
      offset = allocations.next;
    } while (offset <= 10000);
    if (!found) throw new Error('Allocation unavailable');
  }
  return { id, groupId, groupTitle: group.title, groupVersion: group.version, version: journal.version, description: journal.description,
    createdBy: journal.created_by_admin_id, editedBy: journal.edited_by_admin_id, allocationId: journal.allocation_id as string | null,
    transactionId: journal.transaction_id as string | null, memberId, transactionVersion: checkedTransactionVersion, allocationCount, total: Number(debits), lines, accounts };
}
function receipt(value: unknown, id: string, version: number): value is Receipt {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' && value.resource_type === 'journals' &&
    isId(value.request_id) && value.resource_id === id && value.version === version + 1;
}
function outcome(value: unknown, id: string, version: number): { status: 'not_found' | 'pending' | 'failed' | 'succeeded'; receipt: Receipt | null } {
  if (!isObject(value) || value.contract_version !== undefined || value.model !== undefined) throw new Error('Invalid lookup');
  if (value.status === 'not_found' && Object.keys(value).length === 1) return { status: 'not_found', receipt: null };
  if (!['pending', 'failed', 'succeeded'].includes(String(value.status)) || Object.keys(value).length !== 3 || !isId(value.request_id)) throw new Error('Invalid lookup');
  if (value.status === 'succeeded') {
    if (!receipt(value.receipt, id, version) || value.receipt.request_id !== value.request_id) throw new Error('Invalid receipt');
    return { status: 'succeeded', receipt: value.receipt };
  }
  if (value.receipt !== null) throw new Error('Invalid lookup');
  return { status: value.status as 'pending' | 'failed', receipt: null };
}
async function verifyPostingScope(request: AdminRequest, key: string, expected: Receipt): Promise<void> {
  // The single-key legacy lookup does not expose action scope. Check the same
  // actor's bounded request history before treating a journal receipt as posting.
  for (let offset = 0; offset < 10000; offset += 100) {
    const history = await request(`operations/requests?limit=100&offset=${offset}`);
    if (history.contract_version !== undefined || history.model !== undefined || !isSafeCount(history.total) || !Array.isArray(history.rows) ||
        history.rows.length !== Math.max(0, Math.min(100, history.total - offset)) || history.rows.some(row => !isObject(row))) throw new Error('Invalid request history');
    const match = history.rows.find(row => row.idempotency_key === key);
    if (match) {
      if (match.id !== expected.request_id || match.scope !== 'journals.post.post' || match.status !== 'succeeded' || !receipt(match.receipt, expected.resource_id, expected.version - 1) ||
          !(['request_id', 'resource_type', 'resource_id', 'version', 'status'] as const).every(field => match.receipt[field] === expected[field])) throw new Error('Request scope could not be verified');
      return;
    }
    if (offset + history.rows.length >= history.total) break;
  }
  throw new Error('Original request is not in bounded history');
}
async function withLock<T>(name: string, operation: () => Promise<T>): Promise<T> {
  if (!navigator.locks) throw new Error('Protected request lock unavailable');
  return navigator.locks.request(name, { ifAvailable: true }, lock => { if (!lock) throw new Error('Another request is in progress'); return operation(); });
}

/** Posts a legacy double-entry draft. Disabled until deployment and rollback are qualified. */
export function LegacyJournalPostPage({ id, request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, allowMutations = false }: LegacyJournalPostProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const has = (name: string) => permissions.includes(name) && stableIdentity.permissions.includes(name);
  const allowed = financialModel === 'transaction_journals' && role !== 'staff' && isId(id) && isId(actorId) && stableIdentity.id === actorId && stableIdentity.role === role && has(PERMISSION);
  const canCheck = allowed && has('overview.read');
  const canWrite = canCheck && has('ledger.read') && has('collections.read');
  const canReadPayments = has('payments.read');
  const scope = JSON.stringify([authorityKey, id, financialModel, stableIdentity, [...new Set(permissions)].sort()]), current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const active = () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now();
  const [pending, setPending] = useState<PendingAttempt | null>(null), [reason, setReason] = useState(''), [review, setReview] = useState<Intent | null>(null);
  const [source, setSource] = useState<Snapshot | null>(null), [retryAllowed, setRetryAllowed] = useState(false), [acknowledged, setAcknowledged] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading');
  const [scopeLoaded, setScopeLoaded] = useState(''), [message, setMessage] = useState('');
  useEffect(() => {
    if (!allowed) return;
    let live = true;
    readPending(stableIdentity, FAMILY, id).then(saved => {
      if (saved && (saved.permission !== PERMISSION || saved.resource_id !== id)) throw new Error('Invalid recovery');
      if (saved) intent(saved.intent);
      if (!live || current.current !== scope) return;
      setPending(saved); setScopeLoaded(scope); setState('ready'); setReview(null); setSource(null); setRetryAllowed(false); setAcknowledged(false);
      setMessage(saved ? 'A previous posting needs recovery. Check its original request before continuing.' : !allowMutations ? 'Journal posting is not enabled for this workspace.' : !canWrite ? 'Ledger, group and request-history read permissions are required to post.' : '');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('Posting recovery data could not be verified.'); } });
    return () => { live = false; };
  }, [allowed, allowMutations, canWrite, stableIdentity, id, scope]);
  const reviewRequest = async (body?: Intent) => {
    if (!allowMutations || !canWrite || busy.current || !active()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      if (pending && !body) throw new Error('Check pending first');
      const latest = await snapshot(request, id, actorId, canReadPayments, body?.expected_version);
      const checked = intent(body ?? { expected_version: latest.version, reason: reason.trim() });
      if (!active() || !gate.current) return;
      setSource(latest); setReview(checked); setRetryAllowed(false); setAcknowledged(false);
    } catch { if (active()) setMessage('The complete journal, active group, accounts or linked allocation could not be verified. No posting was submitted.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const send = async (body: Intent, key: string) => {
    if (!canWrite || !allowMutations || !source || !acknowledged || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null, dispatched = false;
    try {
      const checked = intent(body);
      await withLock(`collect-admin-legacy-journal:${actorId}:${id}`, async () => {
        if (pending) {
          const original = outcome(await request(`operations/requests/${key}`), id, checked.expected_version);
          if (!active() || !gate.current) return;
          if (original.status === 'succeeded' && original.receipt) {
            await verifyPostingScope(request, key, original.receipt); if (!active() || !gate.current) return;
            await clearPending(stableIdentity, FAMILY, id, key); if (!active()) return;
            setPending(null); setReview(null); setState('success'); setMessage('The original journal posting was recorded.'); return;
          }
          if (original.status !== 'not_found') throw new Error('Original request unresolved');
        }
        const latest = await snapshot(request, id, actorId, canReadPayments, checked.expected_version);
        if (JSON.stringify(latest) !== JSON.stringify(source) || !active() || !gate.current) throw new Error('Journal changed');
        if (!pending && await readPending(stableIdentity, FAMILY, id)) throw new Error('Original request needs review');
        retained = await retainPending(stableIdentity, FAMILY, id, key, PERMISSION, checked);
        if (!active() || !gate.current) return;
        setPending(retained); setRetryAllowed(false); dispatched = true;
        const direct = await request(`operations/journals/${id}/post`, { method: 'POST', body: checked, idempotencyKey: key });
        if (!active() || !receipt(direct, id, checked.expected_version)) throw new Error('Invalid receipt');
        const original = outcome(await request(`operations/requests/${key}`), id, checked.expected_version);
        if (!active() || original.status !== 'succeeded' || !original.receipt || !(['request_id', 'resource_type', 'resource_id', 'version', 'status'] as const).every(field => original.receipt![field] === direct[field])) throw new Error('Unverified receipt');
        await verifyPostingScope(request, key, original.receipt); if (!active() || !gate.current) return;
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
      const saved = intent(pending.intent), result = outcome(await request(`operations/requests/${pending.request_key}`), id, saved.expected_version);
      if (!active()) return;
      if (result.status === 'succeeded' && result.receipt) {
        await verifyPostingScope(request, pending.request_key, result.receipt); if (!active()) return;
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
        {pending && <section><h2>Original request needs review</h2><p>Journal: {id} · Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewRequest(intent(pending.intent))}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && canWrite && <form className="core-edit-form" onSubmit={submitReview}><label>Reason for posting<textarea className="admin-input" value={reason} minLength={8} maxLength={1000} required onChange={event => setReason(event.target.value)} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review journal</Button></form>}
        {review && source && allowMutations && canWrite && <section><h2>Review journal posting</h2><p>{source.description} · {source.groupTitle} · version {source.version}</p><p>Journal {source.id} · Group {source.groupId} · Creator {source.createdBy} · Last editor {source.editedBy}</p><p>Debit total: {formatMoney(source.total)} · Credit total: {formatMoney(source.total)}</p><div className="admin-table-wrap" role="region" aria-label="Journal entries"><table className="admin-table"><thead><tr><th scope="col">Line</th><th scope="col">Account</th><th scope="col">Debit</th><th scope="col">Credit</th><th scope="col">Description</th></tr></thead><tbody>{source.lines.map((line, index) => <tr key={line.id}><td>{index + 1}</td><td>{line.accountCode} · {line.accountName} · {line.accountId}</td><td>{formatMoney(line.debit)}</td><td>{formatMoney(line.credit)}</td><td>{line.description || '—'}</td></tr>)}</tbody></table></div>
          {source.allocationId && <p>Confirmed transaction {source.transactionId} · Allocation {source.allocationId} · Member {source.memberId ?? 'Not recorded'}. Posting may queue a member email notification.</p>}
          <p>Reason: {review.reason}. Posting records this journal; it does not establish provider settlement. The server checks account totals and independent approval at posting.</p><label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed every debit and credit and the posting reason.</label>
          <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); setSource(null); setAcknowledged(false); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !acknowledged} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No journal was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm posting'}</Button>
        </section>}
      </div></Card>}
  </>;
}
