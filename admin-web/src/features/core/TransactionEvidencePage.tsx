import { useEffect, useLayoutEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, formatMoney, isId, isObject, isSafeCount, parseCoreRow } from './contracts';
import { clearEvidenceContext, clearPending, readEvidenceContext, readPending, retainEvidenceContext, retainPending, sha256Text } from './pendingAttempt';
import {lookupCanonicalMutation, matchesCanonicalReceipt} from './canonicalMutation';
import {usePendingIdentity} from './usePendingIdentity';
import type { EvidenceContext, PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { DataRow, FeatureAccess } from './types';
import './core.css';

export interface TransactionEvidenceProps extends FeatureAccess {
  identity: PendingIdentity;
  allowMutations?: boolean;
  verifyFresh: () => Promise<boolean>;
}
const FAMILY = 'operating-createtransaction', RESOURCE = 'new', PERMISSION = 'payments.manage';
const EVIDENCE_REFERENCE = 'Exact text must be re-entered to retry after reloading';
const FIELDS = ['group_id', 'payee_id', 'provider_reference', 'amount_rwf', 'observed_at', 'payer_name', 'evidence', 'reason'];
interface Targets { group: DataRow; receiver: DataRow }
type Draft = { provider_reference: string; amount_rwf: string; observed_at: string; payer_name: string; evidence: string; reason: string };
const initial: Draft = { provider_reference: '', amount_rwf: '', observed_at: '', payer_name: '', evidence: '', reason: '' };
function normalizedEvidence(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length < 8 || value.trim().length > 4000) throw new Error('Invalid evidence');
  return value.trim();
}
function observationTime(value: string): string {
  const input = value.trim(), match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,3}))?Z$/.exec(input);
  if (!match) throw new Error('Invalid time');
  const expected = `${match[1]}.${(match[2] ?? '').padEnd(3, '0')}Z`, date = new Date(input);
  if (!Number.isFinite(date.valueOf()) || date.toISOString() !== expected) throw new Error('Invalid time');
  return expected;
}
function validIntent(value: unknown, evidenceKind: 'raw' | 'retained'): Record<string, unknown> {
  if (!isObject(value) || Object.keys(value).length !== FIELDS.length || !FIELDS.every(key => key in value) ||
      !isId(value.group_id) || value.payee_id !== value.group_id || !isSafeCount(value.amount_rwf) || value.amount_rwf < 1 ||
      !(value.provider_reference === null || typeof value.provider_reference === 'string' && value.provider_reference.length <= 200 && !containsControl(value.provider_reference)) ||
      typeof value.payer_name !== 'string' || value.payer_name.length > 100 || containsControl(value.payer_name) ||
      typeof value.observed_at !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value.observed_at) ||
      !Number.isFinite(Date.parse(value.observed_at)) || new Date(value.observed_at).toISOString() !== value.observed_at || Date.parse(value.observed_at) <= 0 || Date.parse(value.observed_at) > Date.now() + 60000 ||
      typeof value.reason !== 'string' || value.reason.trim().length < 8 || value.reason.length > 500) throw new Error('Invalid evidence request');
  if (evidenceKind === 'raw') { if (normalizedEvidence(value.evidence) !== value.evidence) throw new Error('Invalid evidence'); }
  else if (!isObject(value.evidence) || Object.keys(value.evidence).length !== 3 || value.evidence.kind !== 'retained_operator_text' ||
      value.evidence.reference !== EVIDENCE_REFERENCE || typeof value.evidence.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(value.evidence.sha256)) throw new Error('Invalid retained evidence');
  return value;
}
function parseLookup(value: unknown, kind: 'groups' | 'payees', groupId: string | null): DataRow[] {
  if (!isObject(value) || Object.keys(value).length !== 6 || value.contract_version !== 2 || value.model !== 'canonical_evidence_ledger' || value.kind !== kind || value.group_id !== groupId ||
      !Array.isArray(value.rows) || !isSafeCount(value.total) || value.rows.length !== Math.min(100, value.total)) throw new Error('Lookup unavailable');
  const rows = value.rows.map(item => {
    if (!isObject(item) || typeof item.label !== 'string' || item.label !== item.name || item.label !== item.title) throw new Error('Lookup unavailable');
    const row = parseCoreRow(kind, 'canonical_evidence_ledger', item);
    if (row.status !== 'active' || !isSafeCount(row.version) || row.version < 1 || (kind === 'payees' && (row.group_id !== groupId || row.id !== groupId || row.receiver_basis !== 'operator_recorded'))) throw new Error('Lookup unavailable');
    return row;
  });
  if (new Set(rows.map(row => row.id)).size !== rows.length || (kind === 'payees' && rows.length > 1)) throw new Error('Lookup unavailable');
  return rows;
}
async function currentTargets(request: FeatureAccess['request'], groupId: string, actorId: string): Promise<Targets> {
  const groupData = await request(`operations/groups/${groupId}`), payeeData = await request(`operations/payees/${groupId}`);
  if (groupData.contract_version !== 2 || groupData.model !== 'canonical_evidence_ledger' || groupData.resource_type !== 'groups' || groupData.current_actor_id !== actorId ||
      groupData.can_manage !== true || !Array.isArray(groupData.allowed_operations) || !groupData.allowed_operations.includes('createTransaction') || !isObject(groupData.resource) || groupData.resource.id !== groupId ||
      payeeData.contract_version !== 2 || payeeData.model !== 'canonical_evidence_ledger' || payeeData.resource_type !== 'payees' || payeeData.current_actor_id !== actorId || !isObject(payeeData.resource) || payeeData.resource.id !== groupId) throw new Error('Group or receiver unavailable');
  const group = parseCoreRow('groups', 'canonical_evidence_ledger', groupData.resource), receiver = parseCoreRow('payees', 'canonical_evidence_ledger', payeeData.resource);
  if (group.status !== 'active' || receiver.status !== 'active' || receiver.group_id !== groupId || receiver.receiver_basis !== 'operator_recorded' ||
      !isSafeCount(group.version) || group.version < 1 || receiver.version !== group.version) throw new Error('Group or receiver unavailable');
  return { group, receiver };
}
async function targetHash(targets: Targets): Promise<string> {
  return sha256Text(JSON.stringify({ group_id: targets.group.id, group_version: targets.group.version, group_title: targets.group.title,
    payee_id: targets.receiver.id, receiver_title: targets.receiver.title, receiver_network: targets.receiver.network, receiver_route: targets.receiver.momo_number_or_code }));
}
async function withLock<T>(name: string, fn: () => Promise<T>): Promise<T> {
  if (!navigator.locks) throw new Error('A protected request lock is unavailable.');
  return navigator.locks.request(name, { ifAvailable: true }, lock => { if (!lock) throw new Error('Another request is in progress.'); return fn(); });
}

/** Record retained evidence only when explicitly enabled after migration qualification. */
export function TransactionEvidencePage({ request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh }: TransactionEvidenceProps) {
  const stableIdentity = usePendingIdentity(identity);
  const allowed = financialModel === 'canonical_evidence_ledger' && role !== 'staff' && typeof principalId === 'string' && isId(principalId) &&
    ['payments.read', PERMISSION].every(permission => permissions.includes(permission) && stableIdentity.permissions.includes(permission)) && stableIdentity.id === actorId && stableIdentity.role === role;
  const canWrite = allowed && ['payments.write', 'collections.read', 'receivers.read'].every(permission => permissions.includes(permission) && stableIdentity.permissions.includes(permission));
  const [draft, setDraft] = useState<Draft>(initial), [search, setSearch] = useState(''), [groups, setGroups] = useState<DataRow[]>([]);
  const [group, setGroup] = useState<DataRow | null>(null), [receiver, setReceiver] = useState<DataRow | null>(null), [snapshot, setSnapshot] = useState<Targets | null>(null);
  const [pending, setPending] = useState<PendingAttempt | null>(null), [context, setContext] = useState<EvidenceContext | null>(null), [review, setReview] = useState<Record<string, unknown> | null>(null);
  const [retryAllowed, setRetryAllowed] = useState(false), [reentry, setReentry] = useState(''), [acknowledged, setAcknowledged] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'searching' | 'sending' | 'checking' | 'success' | 'error'>('loading');
  const [scopeLoaded, setScopeLoaded] = useState(''), [message, setMessage] = useState(''), [createdId, setCreatedId] = useState('');
  const scope = JSON.stringify([authorityKey, financialModel]), current = useRef(scope), gate = useRef(allowMutations), busy = useRef(false), lookupEpoch = useRef(0);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const active = () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now();
  useEffect(() => {
    if (!allowed) return;
    let live = true; const epoch = lookupEpoch;
    Promise.all([readPending(stableIdentity, FAMILY, RESOURCE), readEvidenceContext(stableIdentity)]).then(([saved, retainedContext]) => {
      if (saved && saved.permission !== PERMISSION || saved && retainedContext && saved.request_key !== retainedContext.request_key) throw new Error('Invalid recovery');
      if (!live || current.current !== scope) return;
      setPending(saved); setContext(retainedContext); setScopeLoaded(scope);
      if (!saved && retainedContext) { setState('error'); setMessage(`An earlier evidence request needs review. Check request ${retainedContext.request_key} before continuing.`); return; }
      setState('ready');
      if (saved) setMessage('A previous evidence request needs recovery. Check its original reference before continuing.');
      else if (!allowMutations) setMessage('Recording evidence is not enabled for this workspace.');
      else if (!canWrite) setMessage('Recording evidence also requires the payment-write, group and receiver permissions.');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('The recovery record could not be verified.'); } });
    return () => { live = false; epoch.current++; };
  }, [allowed, allowMutations, canWrite, stableIdentity, scope]);
  const findGroups = async (event: FormEvent) => {
    event.preventDefault(); const term = search.trim();
    if (!allowMutations || !canWrite || !active() || pending || busy.current || term.length > 200 || containsControl(term)) return;
    const epoch = ++lookupEpoch.current; setState('searching'); setGroup(null); setReceiver(null); setMessage('');
    try {
      const query = new URLSearchParams({ kind: 'groups', search: term, limit: '100' });
      const rows = parseLookup(await request(`operations/lookups?${query.toString()}`), 'groups', null);
      if (!active() || epoch !== lookupEpoch.current) return;
      setGroups(rows); if (!rows.length) setMessage('No active groups found.');
    } catch { if (active() && epoch === lookupEpoch.current) { setGroups([]); setMessage('The group search could not be verified.'); } }
    finally { if (active() && epoch === lookupEpoch.current) setState('ready'); }
  };
  const chooseGroup = async (id: string) => {
    if (!allowMutations || !canWrite || !active() || pending || busy.current) return;
    const chosen = groups.find(item => item.id === id) ?? null, epoch = ++lookupEpoch.current;
    setGroup(chosen); setReceiver(null); if (!chosen) return;
    setState('searching'); setMessage('');
    try {
      const query = new URLSearchParams({ kind: 'payees', search: '', limit: '100', group_id: chosen.id });
      const rows = parseLookup(await request(`operations/lookups?${query.toString()}`), 'payees', chosen.id);
      if (!active() || epoch !== lookupEpoch.current) return;
      if (rows.length !== 1 || rows[0].version !== chosen.version) throw new Error('Receiver unavailable');
      setReceiver(rows[0]);
    } catch { if (active() && epoch === lookupEpoch.current) setMessage('The recorded receiver could not be verified.'); }
    finally { if (active() && epoch === lookupEpoch.current) setState('ready'); }
  };
  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || !canWrite || !group || !receiver || pending || state !== 'ready' || !active()) return;
    try {
      const amountText = draft.amount_rwf.trim(); if (!/^[1-9]\d*$/.test(amountText)) throw new Error('Invalid amount');
      const amount = BigInt(amountText); if (amount > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('Invalid amount');
      const body = validIntent({ group_id: group.id, payee_id: receiver.id, provider_reference: draft.provider_reference.trim() || null,
        amount_rwf: Number(amount), observed_at: observationTime(draft.observed_at), payer_name: draft.payer_name.trim(), evidence: normalizedEvidence(draft.evidence), reason: draft.reason.trim() }, 'raw');
      setSnapshot({group, receiver}); setReview(body); setAcknowledged(false); setMessage('');
    } catch { setMessage('Check the exact whole RWF amount, UTC observation time, recorded evidence and reason.'); }
  };
  const send = async (body: Record<string, unknown>, key: string) => {
    if (!canWrite || !allowMutations || !principalId || !snapshot || !active() || !acknowledged || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null, createdContext = false, dispatched = false;
    try {
      const checked = validIntent(body, 'raw'), raw = normalizedEvidence(checked.evidence), digest = await sha256Text(raw);
      const retainedBody = validIntent({ ...checked, evidence: { kind: 'retained_operator_text', reference: EVIDENCE_REFERENCE, sha256: digest } }, 'retained');
      await withLock(`collect-admin-record-evidence:${principalId}:${checked.group_id}`, async () => {
        if (pending) {
          if (!permissions.includes('overview.read') || !permissions.includes('account.manage')) throw new Error('Request lookup unavailable');
          const outcome = await lookupCanonicalMutation(request, principalId, key);
          if (!active() || !gate.current) throw new Error('Request lookup unavailable');
          if (outcome.status !== 'not_found') {
            if (outcome.status === 'succeeded') {
              if (!await matchesCanonicalReceipt(outcome.receipt, principalId, key, {resourceType: 'transactions', version: 1})) throw new Error('Invalid receipt');
              await clearEvidenceContext(stableIdentity, key); await clearPending(stableIdentity, FAMILY, RESOURCE, key);
              if (!active()) return;
              setPending(null); setContext(null); setReview(null); setSnapshot(null); setCreatedId((outcome.receipt as Record<string, unknown>).resource_id as string);
              setState('success'); setMessage('The original evidence was recorded. Provider settlement is not asserted.'); return;
            }
            if (outcome.status === 'cancelled') {
              await clearEvidenceContext(stableIdentity, key); await clearPending(stableIdentity, FAMILY, RESOURCE, key);
              if (!active()) return;
              setPending(null); setContext(null); setReview(null); setSnapshot(null); setState('error'); setMessage('The original request was cancelled. Reopen evidence recording to start a new request.'); return;
            }
            throw new Error('Original request is unconfirmed');
          }
        }
        const currentTargetsValue = await currentTargets(request, String(checked.group_id), actorId), receiverHash = await targetHash(currentTargetsValue);
        if (!active() || !gate.current || receiverHash !== await targetHash(snapshot)) throw new Error('Receiver changed');
        if (pending) {
          const storedContext = await readEvidenceContext(stableIdentity);
          if (!storedContext || storedContext.request_key !== key || storedContext.group_id !== checked.group_id || storedContext.payee_id !== checked.payee_id ||
              storedContext.group_version !== currentTargetsValue.group.version || storedContext.receiver_sha256 !== receiverHash || JSON.stringify(pending.intent) !== JSON.stringify((await readPending(stableIdentity, FAMILY, RESOURCE))?.intent)) throw new Error('Original context unavailable');
        } else {
          if (await readPending(stableIdentity, FAMILY, RESOURCE) || await readEvidenceContext(stableIdentity)) throw new Error('Original request needs review');
        }
        if (!active() || !gate.current || !await verifyFresh() || !active() || !gate.current) throw new Error('Verification required');
        if (!pending) {
          await retainEvidenceContext(stableIdentity, { request_key: key, group_id: String(checked.group_id), payee_id: String(checked.payee_id), group_version: currentTargetsValue.group.version as number, receiver_sha256: receiverHash });
          createdContext = true;
        }
        retained = await retainPending(stableIdentity, FAMILY, RESOURCE, key, PERMISSION, retainedBody);
        if (!active() || !gate.current) return;
        setPending(retained); setRetryAllowed(false); dispatched = true;
        const receipt = await request('operations/transactions', { method: 'POST', body: checked, idempotencyKey: key });
        if (!active() || !await matchesCanonicalReceipt(receipt, principalId, key, {resourceType: 'transactions', version: 1})) throw new Error('Invalid receipt');
        await clearEvidenceContext(stableIdentity, key); await clearPending(stableIdentity, FAMILY, RESOURCE, key);
        if (!active()) return;
        setPending(null); setContext(null); setReview(null); setSnapshot(null); setCreatedId(receipt.resource_id as string); setState('success'); setMessage('The evidence was recorded. Provider settlement is not asserted.');
      });
    } catch {
      if (!active()) return;
      let storageFailed = false;
      const saved = retained ?? await readPending(stableIdentity, FAMILY, RESOURCE).catch(() => { storageFailed = true; return null; });
      if (!saved && createdContext && !dispatched && !storageFailed) await clearEvidenceContext(stableIdentity, key).catch(() => { storageFailed = true; });
      setPending(saved); setReview(null); setSnapshot(null); setAcknowledged(false);
      if (storageFailed || dispatched && !saved) { setState('error'); setMessage('Recovery storage could not be verified. Check the original request before another change.'); }
      else { setState('ready'); setMessage(saved ? 'The result is unconfirmed. Check the original request before recording more evidence.' : 'The group, receiver or verification could not be confirmed. No evidence was submitted.'); }
    } finally { busy.current = false; }
  };
  const check = async () => {
    if (!pending || !principalId || !active() || busy.current) return;
    if (!permissions.includes('overview.read') || !permissions.includes('account.manage')) { setMessage('Your account cannot check request history. Contact an authorized administrator.'); return; }
    busy.current = true; const original = pending; setState('checking'); setMessage(''); setRetryAllowed(false); setReview(null);
    try {
      const data = await lookupCanonicalMutation(request, principalId, original.request_key);
      if (!active()) return;
      if (data.status === 'not_found') {
        let retryable = false;
        try { validIntent(original.intent, 'retained'); const savedContext = await readEvidenceContext(stableIdentity); retryable = allowMutations && canWrite && savedContext?.request_key === original.request_key; setContext(savedContext); } catch { /* Other retained requests may still be checked. */ }
        setRetryAllowed(retryable); setMessage(retryable ? 'No completed request was found. Re-enter the exact original evidence before reviewing the same request.' : 'No completed request was found. Keep this reference and check again; the original receiver context is unavailable for a retry.');
      } else {
        if (data.status === 'succeeded') {
          if (!await matchesCanonicalReceipt(data.receipt, principalId, original.request_key, {resourceType: 'transactions', version: 1})) throw new Error('Invalid receipt');
          await clearEvidenceContext(stableIdentity, original.request_key); await clearPending(stableIdentity, FAMILY, RESOURCE, original.request_key);
          if (!active()) return;
          setPending(null); setContext(null); setCreatedId((data.receipt as Record<string, unknown>).resource_id as string); setState('success'); setMessage('The original evidence was recorded. Provider settlement is not asserted.'); return;
        }
        if (data.status === 'cancelled') {
          await clearEvidenceContext(stableIdentity, original.request_key); await clearPending(stableIdentity, FAMILY, RESOURCE, original.request_key);
          if (!active()) return;
          setPending(null); setContext(null); setState('error'); setMessage('The original request was cancelled. Reopen evidence recording to start a new request.'); return;
        }
        setMessage('The request is still unconfirmed. Check again before continuing.');
      }
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };
  const reviewSame = async () => {
    if (!pending || !context || !retryAllowed || !allowMutations || !canWrite || busy.current || !active()) return;
    busy.current = true; setState('checking'); setMessage('');
    try {
      const original = validIntent(pending.intent, 'retained'), raw = normalizedEvidence(reentry);
      if (!isObject(original.evidence) || await sha256Text(raw) !== original.evidence.sha256 || context.request_key !== pending.request_key) throw new Error('Evidence changed');
      const targets = await currentTargets(request, String(original.group_id), actorId);
      if (context.group_id !== original.group_id || context.payee_id !== original.payee_id || context.group_version !== targets.group.version || context.receiver_sha256 !== await targetHash(targets) || !active() || !gate.current) throw new Error('Receiver changed');
      setSnapshot(targets); setReview(validIntent({ ...original, evidence: raw }, 'raw')); setAcknowledged(false); setRetryAllowed(false);
    } catch { if (active()) { setRetryAllowed(false); setMessage('The exact original evidence and its recorded receiver could not be verified. Check the request again.'); } }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };

  return <>
    <PageHeader title="Record payment evidence" subtitle="Record the observed amount and exact evidence for the selected group." actions={<Button type="button" onClick={() => navigate('/admin/transactions')}>Back to transactions</Button>} />
    {!allowed ? <ErrorState title="Recording unavailable" message={financialModel === 'transaction_journals' ? 'This workspace uses the legacy financial model. Its evidence recording workflow is not available here yet.' : 'Your account cannot record evidence in this workspace.'} /> : state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> :
      state === 'error' ? <ErrorState message={message} /> : state === 'success' ? <Card><div className="core-detail" role="status"><h2>Evidence recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/transactions/${createdId}`)}>View transaction</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <><label>Re-enter original evidence text<textarea className="admin-input" value={reentry} maxLength={4000} onChange={event => setReentry(event.target.value)} /></label><Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button></>}</section>}
        {!pending && !review && allowMutations && canWrite && <><form className="core-search" onSubmit={event => void findGroups(event)}><label>Search groups<input className="admin-input" value={search} maxLength={200} onChange={event => setSearch(event.target.value)} /></label><Button type="submit" disabled={state !== 'ready'}>Find groups</Button></form>
          {groups.length > 0 && <label>Group<select className="admin-input" value={group?.id ?? ''} onChange={event => void chooseGroup(event.target.value)}><option value="">Select group</option>{groups.map(item => <option key={item.id} value={item.id}>{item.title}</option>)}</select></label>}
          {receiver && <p>Recorded receiver: {receiver.title} · {String(receiver.network)} · {String(receiver.momo_number_or_code)}</p>}
          <form className="core-edit-form" onSubmit={makeReview}><label>Evidence reference<input className="admin-input" value={draft.provider_reference} maxLength={200} onChange={event => setDraft({ ...draft, provider_reference: event.target.value })} /></label><label>Recorded amount (RWF)<input className="admin-input" inputMode="numeric" value={draft.amount_rwf} required onChange={event => setDraft({ ...draft, amount_rwf: event.target.value })} /></label><label>Observed at (UTC)<input className="admin-input" value={draft.observed_at} placeholder="2026-10-15T12:00:00Z" required onChange={event => setDraft({ ...draft, observed_at: event.target.value })} /></label><label>Recorded payer name<input className="admin-input" value={draft.payer_name} maxLength={100} onChange={event => setDraft({ ...draft, payer_name: event.target.value })} /></label><label>Exact evidence text<textarea className="admin-input" value={draft.evidence} minLength={8} maxLength={4000} required onChange={event => setDraft({ ...draft, evidence: event.target.value })} /></label><label>Reason for recording<textarea className="admin-input" value={draft.reason} minLength={8} maxLength={500} required onChange={event => setDraft({ ...draft, reason: event.target.value })} /></label><p>This records evidence; it does not move money or establish provider settlement. Raw evidence is not stored in browser recovery data.</p><Button type="submit" variant="primary" disabled={state !== 'ready' || !group || !receiver}>Review evidence</Button></form>
        </>}
        {review && snapshot && allowMutations && canWrite && <section><h2>Review evidence request</h2><p>Group: {snapshot.group.title}. Recorded receiver: {snapshot.receiver.title} · {String(snapshot.receiver.network)} · {String(snapshot.receiver.momo_number_or_code)}.</p><p>Amount: {formatMoney(review.amount_rwf)}. Observed: {String(review.observed_at)}. Payer: {String(review.payer_name || 'Not recorded')}.</p><p>Evidence: {String(review.evidence)}</p><p>Reference: {String(review.provider_reference ?? 'Not recorded')}. Reason: {String(review.reason)}.</p><label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed the recorded group, receiver, amount and exact evidence.</label><p>Provider settlement is not asserted.</p><Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); setSnapshot(null); setAcknowledged(false); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !acknowledged} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No evidence was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm evidence'}</Button></section>}
      </div></Card>}
  </>;
}
