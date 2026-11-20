import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, formatMoney, isId, isObject, isSafeCount } from './contracts';
import { clearPending, readPending, retainPending } from './pendingAttempt';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { AdminRequest, FeatureAccess } from './types';
import './core.css';

export interface LegacyJournalEditProps extends FeatureAccess { id: string; identity: PendingIdentity; allowMutations?: boolean }
const FAMILY = 'operating-updatejournal', PERMISSION = 'ledger.manage';
type Entry = { account_id: string; debit_rwf: number; credit_rwf: number; description: string };
type Intent = Record<string, unknown> & { expected_version: number; description: string; entries: Entry[]; reason: string };
type InputLine = { account: string; debit: string; credit: string; description: string };
type Account = { id: string; code: string; name: string; status: 'active' | 'closed'; version: number };
type ExistingLine = { id: string; accountId: string; debit: number; credit: number; description: string };
type Draft = { id: string; groupId: string; groupTitle: string; groupVersion: number; version: number; description: string; allocationId: string | null; transactionId: string | null; memberId: string | null; transactionVersion: number | null; allocationCount: number | null; total: number; lines: ExistingLine[]; accounts: Account[] };
type Review = { draft: Draft; accounts: Account[] };
type Receipt = { request_id: string; resource_type: 'journals'; resource_id: string; version: number; status: 'succeeded' };
function invalid(): never { throw new Error('Invalid journal request'); }
function safeText(value: unknown, min: number, max: number): value is string {
  return typeof value === 'string' && value === value.trim() && value.length >= min && value.length <= max &&
    ![...value].some(char => { const code = char.codePointAt(0)!; return (code < 32 && ![9, 10, 13].includes(code)) || code === 127; });
}
function intent(value: unknown): Intent {
  if (!isObject(value) || !Object.keys(value).every(key => ['expected_version', 'description', 'entries', 'reason'].includes(key)) ||
      !isSafeCount(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER ||
      !safeText(value.description, 3, 1000) || !safeText(value.reason, 8, 1000) || !Array.isArray(value.entries) || value.entries.length < 2 || value.entries.length > 100) return invalid();
  let debits = 0n, credits = 0n;
  for (const line of value.entries) {
    if (!isObject(line) || !Object.keys(line).every(key => ['account_id', 'debit_rwf', 'credit_rwf', 'description'].includes(key)) || !isId(line.account_id) ||
        !isSafeCount(line.debit_rwf) || !isSafeCount(line.credit_rwf) || ((line.debit_rwf === 0) === (line.credit_rwf === 0)) ||
        !(line.description === undefined || safeText(line.description, 0, 500))) return invalid();
    debits += BigInt(line.debit_rwf); credits += BigInt(line.credit_rwf);
  }
  if (debits === 0n || debits !== credits || debits > BigInt(Number.MAX_SAFE_INTEGER)) return invalid();
  return value as Intent;
}
function amount(value: string): number {
  const text = value.trim(); if (!text) return 0;
  if (!/^(?:0|[1-9][0-9]*)$/.test(text)) return invalid();
  const parsed = BigInt(text); if (parsed > BigInt(Number.MAX_SAFE_INTEGER)) return invalid();
  return Number(parsed);
}
function detail(data: Record<string, unknown>, type: string, id: string, actor: string): Record<string, unknown> {
  if (data.contract_version !== undefined || data.model !== undefined || data.resource_type !== type || data.current_actor_id !== actor || data.can_manage !== true || !isObject(data.resource) || data.resource.id !== id) return invalid();
  return data.resource;
}
function page(data: Record<string, unknown>, name: string, offset: number): { rows: Record<string, unknown>[]; total: number; next: number | null } {
  if (!isObject(data.related) || Object.keys(data.related).length !== 1 || !Array.isArray(data.related[name]) || !isObject(data.related_pages) || Object.keys(data.related_pages).length !== 1 || !isObject(data.related_pages[name])) return invalid();
  const rows = data.related[name], p = data.related_pages[name];
  if (!isSafeCount(p.total) || p.limit !== 100 || p.offset !== offset || rows.length !== Math.max(0, Math.min(100, p.total - offset)) ||
      p.next_offset !== (offset + rows.length < p.total ? offset + rows.length : null) || rows.some(row => !isObject(row)) || data.related_truncated !== (p.total > rows.length)) return invalid();
  return { rows: rows as Record<string, unknown>[], total: p.total, next: p.next_offset as number | null };
}
async function getAccount(request: AdminRequest, id: string, groupId: string, actor: string): Promise<Account> {
  const account = detail(await request(`operations/accounts/${id}`), 'accounts', id, actor);
  if (account.group_id !== groupId || account.currency !== 'RWF' || !['active', 'closed'].includes(String(account.status)) || !isSafeCount(account.version) || account.version < 1 ||
      typeof account.code !== 'string' || !account.code.trim() || account.code.length > 40 || typeof account.name !== 'string' || account.name.trim().length < 2 || account.name.length > 120) return invalid();
  return { id, code: account.code, name: account.name, status: account.status as 'active' | 'closed', version: account.version };
}
async function readDraft(request: AdminRequest, id: string, actor: string, canReadPayments: boolean, expected?: number): Promise<Draft> {
  const response = await request(`operations/journals/${id}?relation=entries&limit=100&offset=0`), record = detail(response, 'journals', id, actor), entries = page(response, 'entries', 0);
  if (entries.total < 2 || entries.total > 100 || entries.next !== null || !isId(record.group_id) || record.status !== 'draft' || record.currency !== 'RWF' ||
      !isSafeCount(record.version) || record.version < 1 || record.version >= Number.MAX_SAFE_INTEGER || (expected !== undefined && expected !== record.version) ||
      typeof record.description !== 'string' || record.description.trim().length < 3 || record.description.length > 1000 ||
      !isId(record.created_by_admin_id) || !(record.edited_by_admin_id === null || isId(record.edited_by_admin_id)) ||
      !(record.allocation_id === null || isId(record.allocation_id)) || !(record.transaction_id === null || isId(record.transaction_id)) ||
      ((record.allocation_id === null) !== (record.transaction_id === null))) return invalid();
  const ids = new Set<string>(); let debit = 0n, credit = 0n;
  const lines: ExistingLine[] = entries.rows.map((row, index) => {
    if (!isId(row.id) || ids.has(row.id) || row.journal_id !== id || row.group_id !== record.group_id || !isId(row.account_id) || row.line_number !== index + 1 ||
        !isSafeCount(row.debit_rwf) || !isSafeCount(row.credit_rwf) || ((row.debit_rwf === 0) === (row.credit_rwf === 0)) ||
        typeof row.description !== 'string' || row.description.length > 500 || typeof row.account_code !== 'string' || !row.account_code.trim() || row.account_code.length > 40 ||
        typeof row.account_name !== 'string' || row.account_name.trim().length < 2 || row.account_name.length > 120) return invalid();
    ids.add(row.id); debit += BigInt(row.debit_rwf); credit += BigInt(row.credit_rwf);
    return { id: row.id, accountId: row.account_id, debit: row.debit_rwf, credit: row.credit_rwf, description: row.description };
  });
  if (debit === 0n || debit !== credit || debit > BigInt(Number.MAX_SAFE_INTEGER)) return invalid();
  const groupId = record.group_id, group = detail(await request(`operations/groups/${groupId}`), 'groups', groupId, actor);
  if (group.status !== 'active' || group.currency !== 'RWF' || group.country_code !== 'RW' || typeof group.title !== 'string' || !group.title.trim() || !isSafeCount(group.version) || group.version < 1) return invalid();
  const accounts = await Promise.all([...new Set(lines.map(line => line.accountId))].map(accountId => getAccount(request, accountId, groupId, actor)));
  if (entries.rows.some(row => { const account = accounts.find(item => item.id === row.account_id); return !account || account.code !== row.account_code || account.name !== row.account_name; })) return invalid();
  let memberId: string | null = null, transactionVersion: number | null = null, allocationCount: number | null = null;
  if (record.allocation_id !== null && record.transaction_id !== null) {
    if (!canReadPayments) throw new Error('Payment read access is required');
    let offset = 0, found = false;
    do {
      const response = await request(`operations/transactions/${record.transaction_id}?relation=allocations&limit=100&offset=${offset}`);
      const transaction = detail(response, 'transactions', record.transaction_id, actor), allocations = page(response, 'allocations', offset);
      if (transaction.group_id !== groupId || transaction.verification_status !== 'confirmation_recorded' || !isSafeCount(transaction.version) || transaction.version < 1 ||
          (transactionVersion !== null && transaction.version !== transactionVersion) || (allocationCount !== null && allocations.total !== allocationCount) || allocations.total > 10000) return invalid();
      transactionVersion = transaction.version; allocationCount = allocations.total;
      for (const allocation of allocations.rows) if (allocation.id === record.allocation_id) {
        if (found || allocation.transaction_id !== record.transaction_id || allocation.group_id !== groupId || allocation.amount_rwf !== Number(debit) ||
            !(allocation.member_user_id === null || isId(allocation.member_user_id))) return invalid();
        found = true; memberId = allocation.member_user_id as string | null;
      }
      if (allocations.next === null) break;
      offset = allocations.next;
    } while (offset <= 10000);
    if (!found) return invalid();
  }
  return { id, groupId, groupTitle: group.title, groupVersion: group.version, version: record.version, description: record.description,
    allocationId: record.allocation_id as string | null, transactionId: record.transaction_id as string | null, memberId, transactionVersion, allocationCount, total: Number(debit), lines, accounts };
}
async function reviewSource(request: AdminRequest, id: string, actor: string, canReadPayments: boolean, body: Intent): Promise<Review> {
  const draft = await readDraft(request, id, actor, canReadPayments, body.expected_version);
  const total = body.entries.reduce((sum, line) => sum + BigInt(line.debit_rwf), 0n);
  if (draft.allocationId !== null && total !== BigInt(draft.total)) throw new Error('Allocation amount changed');
  const accounts = await Promise.all([...new Set(body.entries.map(line => line.account_id))].map(accountId => getAccount(request, accountId, draft.groupId, actor)));
  if (accounts.some(account => account.status !== 'active')) return invalid();
  return { draft, accounts };
}
function receipt(value: unknown, id: string, version: number): value is Receipt {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' && value.resource_type === 'journals' && isId(value.request_id) && value.resource_id === id && value.version === version + 1;
}
function outcome(value: unknown, id: string, version: number): { status: 'not_found' | 'pending' | 'failed' | 'succeeded'; receipt: Receipt | null } {
  if (!isObject(value) || value.contract_version !== undefined || value.model !== undefined) return invalid();
  if (value.status === 'not_found' && Object.keys(value).length === 1) return { status: 'not_found', receipt: null };
  if (!['pending', 'failed', 'succeeded'].includes(String(value.status)) || Object.keys(value).length !== 3 || !isId(value.request_id)) return invalid();
  if (value.status === 'succeeded') {
    if (!receipt(value.receipt, id, version) || value.receipt.request_id !== value.request_id) return invalid();
    return { status: 'succeeded', receipt: value.receipt };
  }
  if (value.receipt !== null) return invalid();
  return { status: value.status as 'pending' | 'failed', receipt: null };
}
async function verifyScope(request: AdminRequest, key: string, expected: Receipt): Promise<void> {
  for (let offset = 0; offset < 10000; offset += 100) {
    const history = await request(`operations/requests?limit=100&offset=${offset}`);
    if (history.contract_version !== undefined || history.model !== undefined || !isSafeCount(history.total) || !Array.isArray(history.rows) ||
        history.rows.length !== Math.max(0, Math.min(100, history.total - offset)) || history.rows.some(row => !isObject(row))) return invalid();
    const match = history.rows.find(row => row.idempotency_key === key);
    if (match) {
      if (match.id !== expected.request_id || match.scope !== 'journals.patch' || match.status !== 'succeeded' || !receipt(match.receipt, expected.resource_id, expected.version - 1) ||
          !(['request_id', 'resource_type', 'resource_id', 'version', 'status'] as const).every(field => match.receipt[field] === expected[field])) return invalid();
      return;
    }
    if (offset + history.rows.length >= history.total) break;
  }
  return invalid();
}
async function withLock<T>(name: string, operation: () => Promise<T>): Promise<T> {
  if (!navigator.locks) throw new Error('Protected request lock unavailable');
  return navigator.locks.request(name, { ifAvailable: true }, lock => { if (!lock) throw new Error('Another request is in progress'); return operation(); });
}
const emptyLine = (): InputLine => ({ account: '', debit: '', credit: '', description: '' });

/** Legacy double-entry draft replacement; disabled until deployment and rollback are qualified. */
export function LegacyJournalEditPage({ id, request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, allowMutations = false }: LegacyJournalEditProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const has = (name: string) => permissions.includes(name) && stableIdentity.permissions.includes(name);
  const allowed = financialModel === 'transaction_journals' && role !== 'staff' && isId(id) && isId(actorId) && stableIdentity.id === actorId && stableIdentity.role === role && has(PERMISSION);
  const canCheck = allowed && has('overview.read'), canWrite = canCheck && has('ledger.read') && has('collections.read'), canReadPayments = has('payments.read');
  const scope = JSON.stringify([authorityKey, id, financialModel, stableIdentity, [...new Set(permissions)].sort()]);
  const current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false), lookupEpoch = useRef(0);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const active = () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now();
  const [pending, setPending] = useState<PendingAttempt | null>(null), [original, setOriginal] = useState<Draft | null>(null), [review, setReview] = useState<Intent | null>(null), [verified, setVerified] = useState<Review | null>(null);
  const [choices, setChoices] = useState<{ id: string; label: string }[]>([]), [accountSearch, setAccountSearch] = useState(''), [lines, setLines] = useState<InputLine[]>([]), [description, setDescription] = useState(''), [reason, setReason] = useState('');
  const [retryAllowed, setRetryAllowed] = useState(false), [acknowledged, setAcknowledged] = useState(false), [message, setMessage] = useState('');
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading'), [scopeLoaded, setScopeLoaded] = useState('');
  useEffect(() => {
    if (!allowed) return;
    let live = true;
    readPending(stableIdentity, FAMILY, id).then(async saved => {
      if (saved && (saved.permission !== PERMISSION || saved.resource_id !== id)) return invalid();
      if (saved) intent(saved.intent);
      const draft = !saved && allowMutations && canWrite ? await readDraft(request, id, actorId, canReadPayments) : null;
      if (!live || current.current !== scope) return;
      setPending(saved); setOriginal(draft); setReview(null); setVerified(null); setRetryAllowed(false); setAcknowledged(false); setScopeLoaded(scope); setState('ready');
      setDescription(draft?.description ?? ''); setLines(draft?.lines.map(line => ({ account: line.accountId, debit: line.debit ? String(line.debit) : '', credit: line.credit ? String(line.credit) : '', description: line.description })) ?? []);
      setChoices(draft?.accounts.map(account => ({ id: account.id, label: `${account.code} · ${account.name}${account.status === 'closed' ? ' (closed)' : ''}` })) ?? []);
      setMessage(saved ? 'A previous draft replacement needs recovery. Check its original request before continuing.' : !allowMutations ? 'Journal draft editing is not enabled for this workspace.' : !canWrite ? 'Ledger, group and request-history read permissions are required to edit a draft.' : '');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('The draft, linked allocation or recovery data could not be verified.'); } });
    return () => { live = false; };
  }, [allowed, allowMutations, canWrite, canReadPayments, stableIdentity, request, actorId, id, scope]);
  const searchAccounts = async () => {
    if (!allowMutations || !canWrite || !original || state !== 'ready' || !active() || accountSearch.length > 200 || containsControl(accountSearch)) return;
    const seq = ++lookupEpoch.current; setMessage('');
    try {
      const query = new URLSearchParams({ kind: 'accounts', group_id: original.groupId, search: accountSearch.trim(), limit: '100' });
      const data = await request(`operations/lookups?${query}`);
      if (data.contract_version !== undefined || data.model !== undefined || Object.keys(data).length !== 1 || !Array.isArray(data.rows) || data.rows.length > 100) return invalid();
      const seen = new Set<string>(), loaded = data.rows.map(row => {
        if (!isObject(row) || !isId(row.id) || seen.has(row.id) || typeof row.label !== 'string' || !row.label.trim() || row.label.length > 300 || !isSafeCount(row.version) || row.version < 1) return invalid();
        seen.add(row.id); return { id: row.id, label: row.label };
      });
      if (active() && gate.current && lookupEpoch.current === seq) setChoices(previous => [...new Map([...previous, ...loaded].map(item => [item.id, item])).values()]);
    } catch { if (active()) setMessage('Group accounts could not be verified. Search again.'); }
  };
  const changeLine = (index: number, field: keyof InputLine, value: string) => setLines(previous => previous.map((line, i) => i === index ? { ...line, [field]: value } : line));
  const reviewRequest = async (body?: Intent) => {
    if (!allowMutations || !canWrite || busy.current || !active()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      if (pending && !body || !pending && !original) return invalid();
      const checked = intent(body ?? { expected_version: original!.version, description: description.trim(),
        entries: lines.map(line => ({ account_id: line.account, debit_rwf: amount(line.debit), credit_rwf: amount(line.credit), description: line.description.trim() })), reason: reason.trim() });
      if (new TextEncoder().encode(JSON.stringify(checked)).byteLength > 16384) return invalid();
      const latest = await reviewSource(request, id, actorId, canReadPayments, checked);
      if (original && JSON.stringify(latest.draft) !== JSON.stringify(original)) throw new Error('Draft changed');
      if (!active() || !gate.current) return;
      setVerified(latest); setReview(checked); setRetryAllowed(false); setAcknowledged(false);
    } catch { if (active()) setMessage('Check the draft version, active group and accounts, balanced whole-franc entries and any confirmed allocation. No change was submitted.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const send = async (body: Intent, key: string) => {
    if (!canWrite || !allowMutations || !verified || !acknowledged || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null, dispatched = false;
    try {
      const checked = intent(body);
      await withLock(`collect-admin-legacy-journal:${actorId}:${id}`, async () => {
        if (pending) {
          const prior = outcome(await request(`operations/requests/${key}`), id, checked.expected_version);
          if (!active() || !gate.current) return;
          if (prior.status === 'succeeded' && prior.receipt) {
            await verifyScope(request, key, prior.receipt); if (!active() || !gate.current) return;
            await clearPending(stableIdentity, FAMILY, id, key); if (!active()) return;
            setPending(null); setReview(null); setState('success'); setMessage('The original draft replacement was recorded.'); return;
          }
          if (prior.status !== 'not_found') throw new Error('Original request unresolved');
        }
        const latest = await reviewSource(request, id, actorId, canReadPayments, checked);
        if (JSON.stringify(latest) !== JSON.stringify(verified) || !active() || !gate.current) throw new Error('Draft changed');
        if (!pending && await readPending(stableIdentity, FAMILY, id)) throw new Error('Original request needs review');
        retained = await retainPending(stableIdentity, FAMILY, id, key, PERMISSION, checked);
        if (!active() || !gate.current) return;
        setPending(retained); setRetryAllowed(false); dispatched = true;
        const direct = await request(`operations/journals/${id}`, { method: 'PATCH', body: checked, idempotencyKey: key });
        if (!active() || !receipt(direct, id, checked.expected_version)) throw new Error('Invalid receipt');
        const prior = outcome(await request(`operations/requests/${key}`), id, checked.expected_version);
        if (!active() || prior.status !== 'succeeded' || !prior.receipt || !(['request_id', 'resource_type', 'resource_id', 'version', 'status'] as const).every(field => prior.receipt![field] === direct[field])) throw new Error('Unverified receipt');
        await verifyScope(request, key, prior.receipt); if (!active() || !gate.current) return;
        await clearPending(stableIdentity, FAMILY, id, key); if (!active()) return;
        setPending(null); setReview(null); setState('success'); setMessage('The journal draft was replaced.');
      });
    } catch {
      if (!active()) return;
      let storageFailed = false; const saved = retained ?? await readPending(stableIdentity, FAMILY, id).catch(() => { storageFailed = true; return null; });
      setPending(saved); setReview(null); setVerified(null); setAcknowledged(false);
      if (storageFailed || dispatched && !saved) { setState('error'); setMessage('Recovery data could not be verified. Check the original request before another change.'); }
      else { setState('ready'); setMessage(saved ? 'The result is unconfirmed. Check the original draft replacement before continuing.' : 'The draft, group, accounts or request lock could not be verified. No change was submitted.'); }
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
        await verifyScope(request, pending.request_key, result.receipt); if (!active()) return;
        await clearPending(stableIdentity, FAMILY, id, pending.request_key); if (!active()) return;
        setPending(null); setState('success'); setMessage('The original draft replacement was recorded.'); return;
      }
      if (result.status === 'not_found') { setRetryAllowed(allowMutations && canWrite); setMessage(allowMutations && canWrite ? 'No completed request was found. You may review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.'); }
      else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh the record.' : 'The request is still pending. Check again before continuing.');
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const submitReview = (event: FormEvent) => { event.preventDefault(); void reviewRequest(); };
  return <>
    <PageHeader title="Replace journal draft" subtitle="Review current and replacement entries before saving." actions={<Button type="button" onClick={() => navigate(isId(id) ? `/admin/ledgers/${id}` : '/admin/ledgers')}>Back to ledger</Button>} />
    {!allowed ? <ErrorState title="Editing unavailable" message={financialModel === 'canonical_evidence_ledger' ? 'Double-entry journal editing is unavailable for the canonical evidence ledger.' : 'Your account cannot edit journal drafts in this workspace.'} /> :
      state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Draft request recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/ledgers/${id}`)}>View journal</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Journal {id} · Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewRequest(intent(pending.intent))}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && canWrite && original && <>
          <p>Group: {original.groupTitle} · Draft version {original.version}. Replacements must use active RWF accounts in the same group.{original.allocationId ? ` Linked confirmed allocation: ${original.allocationId}. The total must remain ${formatMoney(original.total)}.` : ''}</p>
          <div className="core-edit-form"><label>Search accounts<input className="admin-input" value={accountSearch} maxLength={200} onChange={event => setAccountSearch(event.target.value)} /></label><Button type="button" disabled={state !== 'ready'} onClick={() => void searchAccounts()}>Search accounts</Button></div>
          <form className="core-edit-form" onSubmit={submitReview}><label>Journal description<textarea className="admin-input" value={description} minLength={3} maxLength={1000} required onChange={event => setDescription(event.target.value)} /></label>
            {lines.map((line, index) => <fieldset key={index}><legend>Entry {index + 1}</legend><label>Account {index + 1}<select className="admin-input" value={line.account} required onChange={event => changeLine(index, 'account', event.target.value)}><option value="">Select account</option>{choices.map(account => <option key={account.id} value={account.id}>{account.label}</option>)}</select></label>
              <label>Debit RWF {index + 1}<input className="admin-input" inputMode="numeric" value={line.debit} onChange={event => changeLine(index, 'debit', event.target.value)} /></label><label>Credit RWF {index + 1}<input className="admin-input" inputMode="numeric" value={line.credit} onChange={event => changeLine(index, 'credit', event.target.value)} /></label><label>Entry description {index + 1}<input className="admin-input" maxLength={500} value={line.description} onChange={event => changeLine(index, 'description', event.target.value)} /></label>
              {lines.length > 2 && <Button type="button" onClick={() => setLines(previous => previous.filter((_, i) => i !== index))}>Remove entry {index + 1}</Button>}</fieldset>)}
            {lines.length < 100 && <Button type="button" onClick={() => setLines(previous => [...previous, emptyLine()])}>Add entry</Button>}<label>Reason for replacement<textarea className="admin-input" value={reason} minLength={8} maxLength={1000} required onChange={event => setReason(event.target.value)} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review replacement</Button></form>
        </>}
        {review && verified && allowMutations && canWrite && <section><h2>Review draft replacement</h2><p>Group: {verified.draft.groupTitle} · {verified.draft.groupId} · Current version {verified.draft.version}</p><p>Current description: {verified.draft.description}. Replacement description: {review.description}.</p>
          <div className="admin-table-wrap" role="region" aria-label="Current journal entries"><table className="admin-table"><caption>Current entries</caption><thead><tr><th scope="col">Account</th><th scope="col">Debit</th><th scope="col">Credit</th><th scope="col">Description</th></tr></thead><tbody>{verified.draft.lines.map(line => { const account = verified.draft.accounts.find(item => item.id === line.accountId)!; return <tr key={line.id}><td>{account.code} · {account.name} · {account.status}</td><td>{formatMoney(line.debit)}</td><td>{formatMoney(line.credit)}</td><td>{line.description || '—'}</td></tr>; })}</tbody></table></div>
          <div className="admin-table-wrap" role="region" aria-label="Replacement journal entries"><table className="admin-table"><caption>Replacement entries</caption><thead><tr><th scope="col">Account</th><th scope="col">Debit</th><th scope="col">Credit</th><th scope="col">Description</th></tr></thead><tbody>{review.entries.map((line, index) => { const account = verified.accounts.find(item => item.id === line.account_id)!; return <tr key={index}><td>{account.code} · {account.name} · {account.id}</td><td>{formatMoney(line.debit_rwf)}</td><td>{formatMoney(line.credit_rwf)}</td><td>{line.description || '—'}</td></tr>; })}</tbody></table></div>
          <p>Debit total: {formatMoney(review.entries.reduce((total, line) => total + line.debit_rwf, 0))} · Credit total: {formatMoney(review.entries.reduce((total, line) => total + line.credit_rwf, 0))}.</p>
          {verified.draft.allocationId && <p>Confirmed transaction {verified.draft.transactionId} · Allocation {verified.draft.allocationId} · Member {verified.draft.memberId ?? 'Not recorded'}.</p>}
          <p>Reason: {review.reason}. This replaces a draft; it does not post the journal or establish provider settlement.</p><label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed the original and replacement entries and the reason.</label>
          <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); setVerified(null); setAcknowledged(false); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !acknowledged} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No change was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm replacement'}</Button>
        </section>}
      </div></Card>}
  </>;
}
