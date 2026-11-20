import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, formatMoney, isId, isObject, isSafeCount } from './contracts';
import { clearPending, readPending, retainPending } from './pendingAttempt';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { AdminRequest, FeatureAccess } from './types';
import './core.css';

export interface LegacyJournalCreateProps extends FeatureAccess { identity: PendingIdentity; allowMutations?: boolean; transactionId?: string; allocationId?: string; fixedGroupId?: string }
const FAMILY = 'operating-createjournal', RESOURCE = 'new', PERMISSION = 'ledger.manage';
type Line = { account_id: string; debit_rwf: number; credit_rwf: number; description: string };
type Intent = Record<string, unknown> & { group_id: string; description: string; allocation_id?: string | null; entries: Line[]; reason: string };
type InputLine = { account: string; debit: string; credit: string; description: string };
type Choice = { id: string; label: string; version: number };
type LinkedAllocation = { transactionId: string; allocationId: string; groupId: string; transactionVersion: number; amount: number; memberId: string | null; allocationCount: number; journalCount: number };
type Snapshot = { groupId: string; groupTitle: string; groupVersion: number; accounts: { id: string; code: string; name: string; version: number }[]; linked: LinkedAllocation | null };
type Receipt = { request_id: string; resource_type: 'journals'; resource_id: string; version: 1; status: 'succeeded' };
function invalid(): never { throw new Error('Invalid journal request'); }
function safeText(value: unknown, min: number, max: number): value is string {
  return typeof value === 'string' && value === value.trim() && value.length >= min && value.length <= max &&
    ![...value].some(char => { const code = char.codePointAt(0)!; return (code < 32 && ![9, 10, 13].includes(code)) || code === 127; });
}
function intent(value: unknown): Intent {
  if (!isObject(value) || !Object.keys(value).every(key => ['group_id', 'description', 'allocation_id', 'entries', 'reason'].includes(key)) ||
      !isId(value.group_id) || !safeText(value.description, 3, 1000) || !safeText(value.reason, 8, 1000) ||
      !(value.allocation_id === undefined || value.allocation_id === null || isId(value.allocation_id)) || !Array.isArray(value.entries) || value.entries.length < 2 || value.entries.length > 100) return invalid();
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
function parseChoices(data: Record<string, unknown>): Choice[] {
  if (data.contract_version !== undefined || data.model !== undefined || Object.keys(data).length !== 1 || !Array.isArray(data.rows) || data.rows.length > 100) return invalid();
  const seen = new Set<string>();
  return data.rows.map(row => {
    if (!isObject(row) || !isId(row.id) || seen.has(row.id) || typeof row.label !== 'string' || !row.label.trim() || row.label.length > 300 || !isSafeCount(row.version) || row.version < 1) return invalid();
    seen.add(row.id); return { id: row.id, label: row.label, version: row.version };
  });
}
function detail(data: Record<string, unknown>, type: string, id: string, actor: string): Record<string, unknown> {
  if (data.contract_version !== undefined || data.model !== undefined || data.resource_type !== type || data.current_actor_id !== actor || data.can_manage !== true || !isObject(data.resource) || data.resource.id !== id) return invalid();
  return data.resource;
}
async function linkedAllocation(request: AdminRequest, transactionId: string, allocationId: string, actor: string): Promise<LinkedAllocation> {
  if (!isId(transactionId) || !isId(allocationId)) return invalid();
  let groupId: string | null = null, transactionVersion: number | null = null, transactionAmount: number | null = null;
  let found: { amount: number; memberId: string | null } | null = null, allocationCount = -1, journalCount = -1;
  for (const relation of ['allocations', 'journals'] as const) {
    let offset = 0, total: number | null = null; const seen = new Set<string>();
    do {
      const response = await request(`operations/transactions/${transactionId}?relation=${relation}&limit=100&offset=${offset}`);
      const transaction = detail(response, 'transactions', transactionId, actor);
      if (!isId(transaction.group_id) || transaction.verification_status !== 'confirmation_recorded' || !isSafeCount(transaction.version) || transaction.version < 1 ||
          !isSafeCount(transaction.amount_rwf) || transaction.amount_rwf < 1 || (groupId !== null && groupId !== transaction.group_id) ||
          (transactionVersion !== null && transactionVersion !== transaction.version) || (transactionAmount !== null && transactionAmount !== transaction.amount_rwf)) return invalid();
      groupId = transaction.group_id; transactionVersion = transaction.version; transactionAmount = transaction.amount_rwf;
      if (!isObject(response.related) || Object.keys(response.related).length !== 1 || !Array.isArray(response.related[relation]) ||
          !isObject(response.related_pages) || Object.keys(response.related_pages).length !== 1 || !isObject(response.related_pages[relation])) return invalid();
      const rows = response.related[relation], page = response.related_pages[relation];
      if (!isSafeCount(page.total) || page.total > 10000 || (total !== null && total !== page.total) || page.limit !== 100 || page.offset !== offset ||
          rows.length !== Math.max(0, Math.min(100, page.total - offset)) || page.next_offset !== (offset + rows.length < page.total ? offset + rows.length : null) ||
          response.related_truncated !== (page.total > rows.length)) return invalid();
      total = page.total;
      for (const row of rows) {
        if (!isObject(row) || !isId(row.id) || seen.has(row.id)) return invalid();
        seen.add(row.id);
        if (relation === 'allocations' && row.id === allocationId) {
          if (found || row.transaction_id !== transactionId || row.group_id !== groupId || !isSafeCount(row.amount_rwf) || row.amount_rwf < 1 || row.amount_rwf > transactionAmount ||
              !(row.member_user_id === null || isId(row.member_user_id))) return invalid();
          found = { amount: row.amount_rwf, memberId: row.member_user_id as string | null };
        }
        if (relation === 'journals') {
          if (!(row.allocation_id === null || isId(row.allocation_id)) || !['draft', 'posted'].includes(String(row.status)) || !isSafeCount(row.version) || row.version < 1) return invalid();
          if (row.allocation_id === allocationId) throw new Error('Allocation already has a journal');
        }
      }
      if (page.next_offset === null) break;
      offset = page.next_offset as number;
    } while (offset < 10000);
    if (relation === 'allocations') allocationCount = total ?? -1; else journalCount = total ?? -1;
  }
  if (!found || !groupId || transactionVersion === null || allocationCount < 0 || journalCount < 0) return invalid();
  return { transactionId, allocationId, groupId, transactionVersion, amount: found.amount, memberId: found.memberId, allocationCount, journalCount };
}
async function source(request: AdminRequest, body: Intent, actor: string, transactionId?: string, allocationId?: string): Promise<Snapshot> {
  let linked: LinkedAllocation | null = null;
  if (body.allocation_id != null) {
    if (!isId(transactionId) || body.allocation_id !== allocationId) return invalid();
    linked = await linkedAllocation(request, transactionId, body.allocation_id, actor);
    if (linked.groupId !== body.group_id || body.entries.reduce((sum, line) => sum + BigInt(line.debit_rwf), 0n) !== BigInt(linked.amount)) return invalid();
  } else if (transactionId !== undefined || allocationId !== undefined) return invalid();
  const group = detail(await request(`operations/groups/${body.group_id}`), 'groups', body.group_id, actor);
  if (group.status !== 'active' || group.currency !== 'RWF' || group.country_code !== 'RW' || typeof group.title !== 'string' || !group.title.trim() || !isSafeCount(group.version) || group.version < 1) return invalid();
  const accounts = await Promise.all([...new Set(body.entries.map(line => line.account_id))].map(async id => {
    const account = detail(await request(`operations/accounts/${id}`), 'accounts', id, actor);
    if (account.group_id !== body.group_id || account.currency !== 'RWF' || account.status !== 'active' || !isSafeCount(account.version) || account.version < 1 ||
        typeof account.code !== 'string' || !account.code.trim() || account.code.length > 40 || typeof account.name !== 'string' || account.name.trim().length < 2 || account.name.length > 120) return invalid();
    return { id, code: account.code, name: account.name, version: account.version };
  }));
  return { groupId: body.group_id, groupTitle: group.title, groupVersion: group.version, accounts, linked };
}
function receipt(value: unknown): value is Receipt {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' && value.resource_type === 'journals' && isId(value.request_id) && isId(value.resource_id) && value.version === 1;
}
function outcome(value: unknown): { status: 'not_found' | 'pending' | 'failed' | 'succeeded'; receipt: Receipt | null } {
  if (!isObject(value) || value.contract_version !== undefined || value.model !== undefined) return invalid();
  if (value.status === 'not_found' && Object.keys(value).length === 1) return { status: 'not_found', receipt: null };
  if (!['pending', 'failed', 'succeeded'].includes(String(value.status)) || Object.keys(value).length !== 3 || !isId(value.request_id)) return invalid();
  if (value.status === 'succeeded') {
    if (!receipt(value.receipt) || value.receipt.request_id !== value.request_id) return invalid();
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
      if (match.id !== expected.request_id || match.scope !== 'journals.post' || match.status !== 'succeeded' || !receipt(match.receipt) ||
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

/** Legacy double-entry draft creation; disabled until deployment and rollback are qualified. */
export function LegacyJournalCreatePage({ request, permissions, actorId, role, authorityKey, financialModel, navigate, identity, transactionId, allocationId, fixedGroupId, allowMutations = false }: LegacyJournalCreateProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const has = (name: string) => permissions.includes(name) && stableIdentity.permissions.includes(name);
  const linked = transactionId !== undefined || allocationId !== undefined;
  const allowed = financialModel === 'transaction_journals' && (!linked || isId(transactionId) && isId(allocationId)) &&
    (fixedGroupId === undefined || !linked && isId(fixedGroupId)) && role !== 'staff' && isId(actorId) && stableIdentity.id === actorId && stableIdentity.role === role && has(PERMISSION);
  const canCheck = allowed && has('overview.read'); const canWrite = canCheck && has('ledger.read') && has('collections.read') && (!linked || has('payments.read'));
  const scope = JSON.stringify([authorityKey, financialModel, stableIdentity, [...new Set(permissions)].sort(), transactionId, allocationId, fixedGroupId]);
  const current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false), groupRef = useRef(''), lookupEpoch = useRef(0);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const active = () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now();
  const [pending, setPending] = useState<PendingAttempt | null>(null), [review, setReview] = useState<Intent | null>(null), [verified, setVerified] = useState<Snapshot | null>(null);
  const [retryAllowed, setRetryAllowed] = useState(false), [acknowledged, setAcknowledged] = useState(false), [createdId, setCreatedId] = useState('');
  const [groups, setGroups] = useState<Choice[]>([]), [accounts, setAccounts] = useState<Choice[]>([]), [groupId, setGroupId] = useState(''), [linkedInfo, setLinkedInfo] = useState<LinkedAllocation | null>(null);
  const [groupSearch, setGroupSearch] = useState(''), [accountSearch, setAccountSearch] = useState(''), [lines, setLines] = useState<InputLine[]>([emptyLine(), emptyLine()]);
  const [description, setDescription] = useState(''), [reason, setReason] = useState(''), [message, setMessage] = useState('');
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading'), [scopeLoaded, setScopeLoaded] = useState('');
  useEffect(() => {
    if (!allowed) return;
    let live = true;
    readPending(stableIdentity, FAMILY, RESOURCE).then(async saved => {
      if (saved && (saved.permission !== PERMISSION || saved.resource_id !== RESOURCE)) return invalid();
      if (saved) intent(saved.intent);
      let fixed: LinkedAllocation | null = null, choices: Choice[] = [], accountChoices: Choice[] = [];
      if (!saved && allowMutations && canWrite) {
        if (linked || fixedGroupId) {
          if (linked) {
            if (!isId(transactionId) || !isId(allocationId)) return invalid();
            fixed = await linkedAllocation(request, transactionId, allocationId, actorId);
          }
          const selectedId = fixed?.groupId ?? fixedGroupId!;
          const group = detail(await request(`operations/groups/${selectedId}`), 'groups', selectedId, actorId);
          if (group.status !== 'active' || group.currency !== 'RWF' || group.country_code !== 'RW' || typeof group.title !== 'string' || !group.title.trim() || !isSafeCount(group.version) || group.version < 1) return invalid();
          choices = [{ id: selectedId, label: group.title, version: group.version }];
          accountChoices = parseChoices(await request(`operations/lookups?kind=accounts&group_id=${selectedId}&search=&limit=100`));
        } else choices = parseChoices(await request('operations/lookups?kind=groups&search=&limit=100'));
      }
      if (!live || current.current !== scope) return;
      groupRef.current = fixed?.groupId ?? fixedGroupId ?? ''; setGroupId(fixed?.groupId ?? fixedGroupId ?? ''); setLinkedInfo(fixed); setAccounts(accountChoices); setLines([emptyLine(), emptyLine()]); setGroups(choices); setPending(saved); setScopeLoaded(scope);
      setState('ready'); setReview(null); setVerified(null); setRetryAllowed(false); setAcknowledged(false);
      setMessage(saved ? 'A previous journal draft needs recovery. Check its original request before continuing.' : !allowMutations ? 'Journal draft creation is not enabled for this workspace.' : !canWrite ? 'Ledger, group, request-history and, for linked drafts, payment read permissions are required.' : '');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('The group, linked allocation, existing journals or draft recovery data could not be verified.'); } });
    return () => { live = false; };
  }, [allowed, allowMutations, canWrite, stableIdentity, request, scope, linked, transactionId, allocationId, fixedGroupId, actorId]);
  const searchGroups = async () => {
    if (!allowMutations || !canWrite || state !== 'ready' || !active() || groupSearch.length > 200 || containsControl(groupSearch)) return;
    const seq = ++lookupEpoch.current; setMessage('');
    try {
      const query = new URLSearchParams({ kind: 'groups', search: groupSearch.trim(), limit: '100' });
      const choices = parseChoices(await request(`operations/lookups?${query}`));
      if (active() && gate.current && lookupEpoch.current === seq) setGroups(previous => [...new Map([...previous, ...choices].map(item => [item.id, item])).values()]);
    } catch { if (active()) setMessage('Groups could not be verified. Search again.'); }
  };
  const searchAccounts = async (selectedGroup: string, search: string, reset: boolean) => {
    if (!allowMutations || !canWrite || !active() || !isId(selectedGroup) || search.length > 200 || containsControl(search)) return;
    const seq = ++lookupEpoch.current; setMessage('');
    try {
      const query = new URLSearchParams({ kind: 'accounts', group_id: selectedGroup, search: search.trim(), limit: '100' });
      const choices = parseChoices(await request(`operations/lookups?${query}`));
      if (active() && gate.current && lookupEpoch.current === seq && groupRef.current === selectedGroup) setAccounts(previous => [...new Map([...(reset ? [] : previous), ...choices].map(item => [item.id, item])).values()]);
    } catch { if (active() && groupRef.current === selectedGroup) setMessage('Group accounts could not be verified. Search again.'); }
  };
  const changeGroup = (value: string) => {
    groupRef.current = value; ++lookupEpoch.current; setGroupId(value); setAccounts([]); setAccountSearch(''); setLines([emptyLine(), emptyLine()]);
    if (value) void searchAccounts(value, '', true);
  };
  const changeLine = (index: number, field: keyof InputLine, value: string) => setLines(previous => previous.map((line, i) => i === index ? { ...line, [field]: value } : line));
  const reviewRequest = async (body?: Intent) => {
    if (!allowMutations || !canWrite || busy.current || !active()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      if (pending && !body) return invalid();
      const checked = intent(body ?? { group_id: groupId, description: description.trim(), allocation_id: linked ? allocationId : null,
        entries: lines.map(line => ({ account_id: line.account, debit_rwf: amount(line.debit), credit_rwf: amount(line.credit), description: line.description.trim() })), reason: reason.trim() });
      if (fixedGroupId && checked.group_id !== fixedGroupId) return invalid();
      if (new TextEncoder().encode(JSON.stringify(checked)).byteLength > 16384) throw new Error('Recovery limit');
      const latest = await source(request, checked, actorId, transactionId, allocationId);
      if (!active() || !gate.current) return;
      setVerified(latest); setReview(checked); setRetryAllowed(false); setAcknowledged(false);
    } catch { if (active()) setMessage('Check the active group, RWF accounts, balanced whole-franc entries, confirmed allocation and reason. No draft was submitted.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const send = async (body: Intent, key: string) => {
    if (!canWrite || !allowMutations || !verified || !acknowledged || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null, dispatched = false;
    try {
      const checked = intent(body);
      await withLock(`collect-admin-legacy-journal-create:${actorId}`, async () => {
        if (pending) {
          const original = outcome(await request(`operations/requests/${key}`));
          if (!active() || !gate.current) return;
          if (original.status === 'succeeded' && original.receipt) {
            await verifyScope(request, key, original.receipt); if (!active() || !gate.current) return;
            await clearPending(stableIdentity, FAMILY, RESOURCE, key); if (!active()) return;
            setPending(null); setReview(null); setCreatedId(original.receipt.resource_id); setState('success'); setMessage('The original journal draft request was recorded.'); return;
          }
          if (original.status !== 'not_found') throw new Error('Original request unresolved');
        }
        const latest = await source(request, checked, actorId, transactionId, allocationId);
        if (JSON.stringify(latest) !== JSON.stringify(verified) || !active() || !gate.current) throw new Error('Group or account changed');
        if (!pending && await readPending(stableIdentity, FAMILY, RESOURCE)) throw new Error('Original request needs review');
        retained = await retainPending(stableIdentity, FAMILY, RESOURCE, key, PERMISSION, checked);
        if (!active() || !gate.current) return;
        setPending(retained); setRetryAllowed(false); dispatched = true;
        const direct = await request('operations/journals', { method: 'POST', body: checked, idempotencyKey: key });
        if (!active() || !receipt(direct)) throw new Error('Invalid receipt');
        const original = outcome(await request(`operations/requests/${key}`));
        if (!active() || original.status !== 'succeeded' || !original.receipt || !(['request_id', 'resource_type', 'resource_id', 'version', 'status'] as const).every(field => original.receipt![field] === direct[field])) throw new Error('Unverified receipt');
        await verifyScope(request, key, original.receipt); if (!active() || !gate.current) return;
        await clearPending(stableIdentity, FAMILY, RESOURCE, key); if (!active()) return;
        setPending(null); setReview(null); setCreatedId(direct.resource_id); setState('success'); setMessage('The journal draft was recorded.');
      });
    } catch {
      if (!active()) return;
      let storageFailed = false; const saved = retained ?? await readPending(stableIdentity, FAMILY, RESOURCE).catch(() => { storageFailed = true; return null; });
      setPending(saved); setReview(null); setVerified(null); setAcknowledged(false);
      if (storageFailed || dispatched && !saved) { setState('error'); setMessage('Recovery data could not be verified. Check the original request before another change.'); }
      else { setState('ready'); setMessage(saved ? 'The result is unconfirmed. Check the original journal draft request before continuing.' : 'The group, accounts or request lock could not be verified. No draft was submitted.'); }
    } finally { busy.current = false; }
  };
  const check = async () => {
    if (!pending || !active() || busy.current) return;
    if (!canCheck) { setMessage('Your account cannot check request history. Contact an authorized administrator.'); return; }
    busy.current = true; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const saved = intent(pending.intent), result = outcome(await request(`operations/requests/${pending.request_key}`));
      if (!active()) return;
      if (result.status === 'succeeded' && result.receipt) {
        await verifyScope(request, pending.request_key, result.receipt); if (!active()) return;
        await clearPending(stableIdentity, FAMILY, RESOURCE, pending.request_key); if (!active()) return;
        setPending(null); setCreatedId(result.receipt.resource_id); setState('success'); setMessage('The original journal draft request was recorded.'); return;
      }
      if (result.status === 'not_found') {
        const retry = allowMutations && canWrite && (!fixedGroupId || saved.group_id === fixedGroupId) && (linked ? saved.allocation_id === allocationId : saved.allocation_id == null); setRetryAllowed(retry);
        setMessage(retry ? 'No completed request was found. You may review the same request with its original reference.' : saved.allocation_id != null ? 'No completed request was found. Return to the original transaction allocation to review the same request, or keep the reference and check again.' : 'No completed request was found. Keep the reference and check again.');
      } else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh the record.' : 'The request is still pending. Check again before continuing.');
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const submitReview = (event: FormEvent) => { event.preventDefault(); void reviewRequest(); };
  return <>
    <PageHeader title="Create journal draft" subtitle="Prepare balanced legacy RWF entries for independent posting." actions={<Button type="button" onClick={() => navigate(linked && isId(transactionId) ? `/admin/transactions/${transactionId}` : fixedGroupId && isId(fixedGroupId) ? `/admin/groups/${fixedGroupId}` : '/admin/ledgers')}>{linked ? 'Back to transaction' : fixedGroupId ? 'Back to group' : 'Back to ledgers'}</Button>} />
    {!allowed ? <ErrorState title="Creation unavailable" message={financialModel === 'canonical_evidence_ledger' ? 'Double-entry journal creation is unavailable for the canonical evidence ledger.' : 'Your account cannot create journal drafts in this workspace.'} /> :
      state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> : state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Draft request recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/ledgers/${createdId}`)}>View journal</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code> · Group {String(pending.intent.group_id)}</p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewRequest(intent(pending.intent))}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && canWrite && <>
          <p>Use active accounts in the same active group. Search to find groups or accounts beyond the first 100 results.</p>
          {linkedInfo && <p>Confirmed transaction {linkedInfo.transactionId} · Allocation {linkedInfo.allocationId} · Member {linkedInfo.memberId ?? 'Not recorded'} · Required debit and credit totals: {formatMoney(linkedInfo.amount)}.</p>}
          <div className="core-edit-form">{!linked && !fixedGroupId && <><label>Search groups<input className="admin-input" value={groupSearch} maxLength={200} onChange={event => setGroupSearch(event.target.value)} /></label><Button type="button" disabled={state !== 'ready'} onClick={() => void searchGroups()}>Search groups</Button>
          <label>Group<select className="admin-input" value={groupId} onChange={event => changeGroup(event.target.value)}><option value="">Select group</option>{groups.map(group => <option key={group.id} value={group.id}>{group.label}</option>)}</select></label></>}
          {(linkedInfo || fixedGroupId) && <p>Group: {groups[0]?.label} · {linkedInfo?.groupId ?? fixedGroupId}</p>}
          <label>Search accounts<input className="admin-input" value={accountSearch} maxLength={200} onChange={event => setAccountSearch(event.target.value)} /></label><Button type="button" disabled={!groupId || state !== 'ready'} onClick={() => void searchAccounts(groupId, accountSearch, false)}>Search accounts</Button></div>
          <form className="core-edit-form" onSubmit={submitReview}><label>Journal description<textarea className="admin-input" value={description} minLength={3} maxLength={1000} required onChange={event => setDescription(event.target.value)} /></label>
            {lines.map((line, index) => <fieldset key={index}><legend>Entry {index + 1}</legend><label>Account {index + 1}<select className="admin-input" value={line.account} required onChange={event => changeLine(index, 'account', event.target.value)}><option value="">Select account</option>{accounts.map(account => <option key={account.id} value={account.id}>{account.label}</option>)}</select></label>
              <label>Debit RWF {index + 1}<input className="admin-input" inputMode="numeric" value={line.debit} onChange={event => changeLine(index, 'debit', event.target.value)} /></label><label>Credit RWF {index + 1}<input className="admin-input" inputMode="numeric" value={line.credit} onChange={event => changeLine(index, 'credit', event.target.value)} /></label><label>Entry description {index + 1}<input className="admin-input" maxLength={500} value={line.description} onChange={event => changeLine(index, 'description', event.target.value)} /></label>
              {lines.length > 2 && <Button type="button" onClick={() => setLines(previous => previous.filter((_, i) => i !== index))}>Remove entry {index + 1}</Button>}</fieldset>)}
            {lines.length < 100 && <Button type="button" onClick={() => setLines(previous => [...previous, emptyLine()])}>Add entry</Button>}
            <label>Reason for draft<textarea className="admin-input" value={reason} minLength={8} maxLength={1000} required onChange={event => setReason(event.target.value)} /></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review journal draft</Button></form>
        </>}
        {review && verified && allowMutations && canWrite && <section><h2>Review journal draft</h2><p>{review.description} · Group: {verified.groupTitle} · {verified.groupId}</p>{verified.linked && <p>Confirmed transaction {verified.linked.transactionId} · Allocation {verified.linked.allocationId} · Member {verified.linked.memberId ?? 'Not recorded'} · Allocation amount {formatMoney(verified.linked.amount)}.</p>}
          <div className="admin-table-wrap" role="region" aria-label="Draft journal entries"><table className="admin-table"><thead><tr><th scope="col">Line</th><th scope="col">Account</th><th scope="col">Debit</th><th scope="col">Credit</th><th scope="col">Description</th></tr></thead><tbody>{review.entries.map((line, index) => { const account = verified.accounts.find(item => item.id === line.account_id)!; return <tr key={index}><td>{index + 1}</td><td>{account.code} · {account.name} · {account.id}</td><td>{formatMoney(line.debit_rwf)}</td><td>{formatMoney(line.credit_rwf)}</td><td>{line.description || '—'}</td></tr>; })}</tbody></table></div>
          <p>Debit total: {formatMoney(review.entries.reduce((total, line) => total + line.debit_rwf, 0))} · Credit total: {formatMoney(review.entries.reduce((total, line) => total + line.credit_rwf, 0))}</p><p>Reason: {review.reason}. This creates a draft, not a posted journal or provider settlement.</p>
          <label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed the group, every debit and credit, and the reason.</label>
          <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); setVerified(null); setAcknowledged(false); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !acknowledged} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No draft was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm draft'}</Button>
        </section>}
      </div></Card>}
  </>;
}
