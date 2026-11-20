import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import type {AdminRequest} from '../../api/client';
import {Button, Card, Field, LoadingState} from '../../ui';
import type {PendingAttempt, PendingIdentity} from '../core/pendingAttempt';
import {checkCreate, checkOldCreate, loadCreateGroup, loadCreateTargets, oldCreateAttempt, parseCreateIntent, recoverCreateSource, restoreCreate, retryCreate, searchCreateGroups, searchCreatePayees, submitCreate, validateCreateTargets, verifyCreateReentry,
  type CreateContext, type CreateIntent, type CreatePending, type CreateTargets} from './create';
import {searchCreateSources, validateCreateSource, type CreateSource} from './createSource';
import '../core/core.css';

export interface LegacyTransactionCreateProps {
  request: AdminRequest; identity: PendingIdentity; permissions: readonly string[]; financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; authorityKey: string;
  /** Must fence the current authenticated epoch, actor and session. */
  isCurrent: () => boolean; allowMutations?: boolean; initialGroupId?:string; onCreated: (transactionId: string) => void;
}
type Group = {id: string; label: string; version: number};
type Payee = {id: string; label: string; version: number; network: 'mtn_momo' | 'airtel_money'};
type Draft = {reference: string; amount: string; observed: string; kind: string; evidenceReference: string; digest: string; reason: string};
const initial: Draft = {reference: '', amount: '', observed: '', kind: 'operator_observation', evidenceReference: '', digest: '', reason: ''};
function time(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.000)?Z$/.test(value)) throw new Error('Use a UTC time.');
  const normalized = value.includes('.') ? value : value.replace('Z', '.000Z'), date = new Date(normalized);
  if (!Number.isFinite(date.getTime()) || date.toISOString() !== normalized || date.getTime() <= 0) throw new Error('Use a valid UTC time.'); return date.getTime() / 1000;
}
function amount(value: string) {if (!/^[1-9][0-9]*$/.test(value)) throw new Error('Use whole RWF.'); const exact = BigInt(value); if (exact > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('Amount too large.'); return Number(exact);}

/** Requires the paired atomic backend guard and an explicitly qualified rollout. */
export function LegacyTransactionCreate(props: LegacyTransactionCreateProps) {
  const key = JSON.stringify([props.authorityKey, props.financialModel, props.allowMutations ?? false, props.initialGroupId, props.identity.id, props.identity.sessionId, props.identity.email, props.identity.role, props.identity.expiresAt, [...props.identity.permissions].sort(), [...props.permissions].sort()]);
  return <LegacyTransactionCreatePanel key={key} {...props} />;
}
function LegacyTransactionCreatePanel({request, identity, permissions, financialModel, authorityKey, isCurrent, allowMutations = false, initialGroupId, onCreated}: LegacyTransactionCreateProps) {
  const identityGrants = JSON.stringify([...new Set(identity.permissions)].sort()), grants = JSON.stringify([...new Set(permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.parse(identityGrants) as string[], expiresAt: identity.expiresAt}), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, identityGrants]);
  const stablePermissions = useMemo<readonly string[]>(() => JSON.parse(grants) as string[], [grants]);
  const scope = JSON.stringify([authorityKey, financialModel, stableIdentity, stablePermissions]), current = useRef(scope), live = useRef(isCurrent), gate = useRef(allowMutations), busyRef = useRef(false);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]); useLayoutEffect(() => {live.current = isCurrent;}, [isCurrent]);
  useLayoutEffect(() => {gate.current = allowMutations; return () => {gate.current = false;};}, [allowMutations]);
  const context = useMemo<CreateContext>(() => ({request, identity: stableIdentity, permissions: stablePermissions, financialModel, enabled: allowMutations,
    isCurrent: () => current.current === scope && live.current() && Date.parse(stableIdentity.expiresAt) > Date.now(), isEnabled: () => gate.current}), [request, stableIdentity, stablePermissions, financialModel, allowMutations, scope]);
  const allowed = financialModel === 'transaction_journals' && stableIdentity.role !== 'staff' && ['collections.read', 'receivers.read', 'payments.read', 'payments.manage', 'overview.read'].every(value => stableIdentity.permissions.includes(value) && stablePermissions.includes(value));
  const [pending, setPending] = useState<CreatePending | null>(null), [previous, setPrevious] = useState<PendingAttempt | null>(null), [orphan, setOrphan] = useState(false), [loadedScope, setLoadedScope] = useState('');
  const [groups, setGroups] = useState<Group[]>([]), [payees, setPayees] = useState<Payee[]>([]), [group, setGroup] = useState<Group | null>(null), [payee, setPayee] = useState<Payee | null>(null), [search, setSearch] = useState('');
  const [sourceSearch,setSourceSearch]=useState(''),[sources,setSources]=useState<CreateSource[]>([]),[selectedSource,setSelectedSource]=useState<CreateSource|null>(null),[reviewedSource,setReviewedSource]=useState<CreateSource|null>(null),[truncated,setTruncated]=useState(false);
  const [draft, setDraft] = useState<Draft>(initial), [targets, setTargets] = useState<CreateTargets | null>(null), [review, setReview] = useState<CreateIntent | null>(null), [revision, setRevision] = useState('');
  const [retryAvailable, setRetryAvailable] = useState(false), [confirmed, setConfirmed] = useState(false), [message, setMessage] = useState(''), [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!allowed) return; let active = true;
    (async () => {const saved = await restoreCreate(context), old = await oldCreateAttempt(context);let initial:Group|null=null,initialError=false;
      if(initialGroupId!==undefined&&allowMutations&&saved.kind==='ready'&&!old.saved&&!old.orphan){try{initial=await loadCreateGroup(context,initialGroupId);}catch{initialError=true;}}
      return {saved, old, initial, initialError};})().then(({saved, old, initial, initialError}) => {
      if (active && context.isCurrent()) {setPending(saved); setPrevious(old.saved); setOrphan(old.orphan);if(initial){setGroups([initial]);setGroup(initial);}setLoadedScope(scope); setMessage(saved.kind !== 'ready' || old.saved || old.orphan ? 'An earlier payment request needs recovery.' : !allowMutations ? 'Payment recording is not enabled for this workspace.' : initialError?'The selected group could not be verified.':'');}
    }).catch(() => {if (active && context.isCurrent()) {setLoadedScope(scope); setMessage('Payment recovery data could not be verified.');}});
    return () => {active = false;};
  }, [allowed, allowMutations, context, scope, initialGroupId]);
  if (!allowed) return null;
  if (loadedScope !== scope) return <LoadingState label="Checking payment request recovery" />;
  const ready = pending?.kind === 'ready' && !previous && !orphan ? pending : null, original = pending && pending.kind !== 'ready' ? pending : null;
  const findGroups = async () => {
    if (!allowMutations || !ready || busyRef.current || !context.isCurrent()) return; busyRef.current = true; setBusy(true); setMessage('');
    try {const rows = await searchCreateGroups(context, search); if (context.isCurrent() && gate.current) {setGroups(rows); setGroup(null); setPayees([]); setPayee(null);setSources([]);setSelectedSource(null); if (!rows.length) setMessage('No active groups found.');}}
    catch {if (context.isCurrent()) setMessage('Active groups could not be verified.');} finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const findPayees = async () => {
    if (!allowMutations || !ready || !group || busyRef.current || !context.isCurrent()) return; busyRef.current = true; setBusy(true); setMessage('');
    try {const rows = await searchCreatePayees(context, group.id); if (context.isCurrent() && gate.current) {setPayees(rows); setPayee(null);setSources([]);setSelectedSource(null); if (!rows.length) setMessage('No active receivers found for this group.');}}
    catch {if (context.isCurrent()) setMessage('Active receivers could not be verified.');} finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const canReadSms=stableIdentity.permissions.includes('sms.read')&&stablePermissions.includes('sms.read');
  const findSources=async()=>{
    if(!allowMutations||!ready||!payee||!canReadSms||busyRef.current||!context.isCurrent())return;busyRef.current=true;setBusy(true);setMessage('');
    try{const result=await searchCreateSources(context,sourceSearch,payee.id);if(context.isCurrent()&&gate.current){setSources(result.choices);setSelectedSource(null);setTruncated(result.truncated);if(!result.choices.length)setMessage('No eligible receiver sources were found on this page.');}}
    catch{if(context.isCurrent())setMessage('Preserved receiver sources could not be verified.');}finally{busyRef.current=false;if(context.isCurrent())setBusy(false);}
  };
  const makeReview = async (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || busyRef.current || !context.isCurrent() || !ready && !(retryAvailable && original?.kind === 'owned' && original.attempt && !previous && !orphan)) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {
      const source = original?.kind === 'owned' ? targets : group && payee ? await loadCreateTargets(context, group.id, payee.id) : null;
      if (!source || ready && (!group || !payee || source.group.title !== group.label || source.group.version !== group.version || source.payee.label !== payee.label || source.payee.version !== payee.version || source.payee.network !== payee.network)) throw new Error('Selection changed');
      const body = parseCreateIntent({group_id: source.group.id, payee_id: source.payee.id, expected_group_version: source.group.version, expected_payee_version: source.payee.version,
        provider_reference: draft.reference.trim(), amount_rwf: amount(draft.amount.trim()), observed_at: time(draft.observed.trim()), evidence: {kind: draft.kind, reference: draft.evidenceReference.trim(), sha256: draft.digest.trim()}, reason: draft.reason.trim(),...(selectedSource?{source_fact_id:selectedSource.factId}:{})});
      validateCreateTargets(source, body);if(selectedSource)validateCreateSource(selectedSource,body,source); if (original?.kind === 'owned' && original.attempt) await verifyCreateReentry(context, original.attempt, body,selectedSource);
      if (context.isCurrent() && gate.current) {setTargets(source);setReviewedSource(selectedSource); setReview(body); setRevision(ready?.revision ?? ''); setConfirmed(false);}
    } catch {if (context.isCurrent()) setMessage('Check the current group, receiver, selected source, whole RWF amount, UTC time, evidence and reason. A retry must match the original request.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const checkOld = async () => {
    if (!previous || busyRef.current || !context.isCurrent()) return; busyRef.current = true; setBusy(true); setMessage('');
    try {const result = await checkOldCreate(context, previous); if (context.isCurrent()) setMessage(result.status === 'succeeded' ? `Earlier request recorded. Reference ${result.receipt.request_id}. Resolve it in its original workflow.` : result.status === 'not_found' ? 'No receipt was found. Keep the earlier reference; this panel cannot retry it.' : 'The earlier request is unresolved. Keep its reference and check again.');}
    catch {if (context.isCurrent()) setMessage('The earlier request could not be verified. Keep its reference.');} finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const checkOriginal = async () => {
    if (original?.kind !== 'owned' || busyRef.current || !context.isCurrent()) return; busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = await checkCreate(context, original); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setMessage(`Original payment request recorded. Reference ${result.receipt.request_id}.`); onCreated(result.receipt.resource_id);}
      else if (result.status === 'not_found' && result.retryAvailable && original.attempt && gate.current && !previous && !orphan) {
        const saved = original.attempt.intent;
        if(initialGroupId!==undefined&&saved.group_id!==initialGroupId){setMessage('No receipt was found. This request belongs to another group; open its original group to review any retry.');return;}
        const source = await loadCreateTargets(context, String(saved.group_id), String(saved.payee_id));
        if (source.group.version !== saved.expected_group_version || source.payee.version !== saved.expected_payee_version) throw new Error('Group or receiver changed');
        const originalSource=await recoverCreateSource(context,original.attempt);
        if (context.isCurrent() && gate.current) {setTargets(source);setSelectedSource(originalSource); setDraft({...initial, digest: String(saved.evidence_sha256)}); setRetryAvailable(true); setReview(null); setMessage('No receipt was found. Re-enter the original payment details, evidence and reason to review the same request.');}
      } else setMessage(result.status === 'not_found' ? 'No receipt was found. Keep the original reference and check again.' : 'The original request is unresolved. Keep its reference and check again.');
    } catch {if (context.isCurrent()) setMessage('The original request, current group, receiver or preserved source could not be verified. Keep the reference.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const submit = async () => {
    if (!allowMutations || !review || !targets || !confirmed || busyRef.current || !context.isCurrent() || original?.kind === 'foreign' || original?.kind === 'owned' && !retryAvailable) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {
      const result = original?.kind === 'owned' ? await retryCreate(context, original, review, targets,reviewedSource) : await submitCreate(context, review, targets, revision,reviewedSource);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setMessage(`Payment evidence recorded. Reference ${result.receipt.request_id}.`); onCreated(result.receipt.resource_id);}
      else if (result.status === 'existing') {setPending(result.pending); setMessage('An earlier payment request needs recovery.');}
      else {setDraft(initial); setPending({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unconfirmed. Keep request reference ${result.requestKey} and check the original request.`); try {setPending(await restoreCreate(context));} catch { /* Keep the reference visible. */ }}
    } catch {if (context.isCurrent()) {setMessage('The payment request or recovery data could not be verified.'); try {setPending(await restoreCreate(context));} catch {setPending(null);}}}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false); setRetryAvailable(false);}}
  };
  return <Card className="core-detail"><h2>Record payment evidence</h2><p>This records an evidence claim. It does not send money or confirm provider settlement.</p>{message && <p role="status">{message}</p>}
    {original?.kind === 'foreign' && <p>Another account or session has an unresolved payment request. The original account must check it.</p>}
    {original?.kind === 'owned' && <section><h3>Original request</h3><p>Reference: <code>{original.requestKey}</code></p><Button disabled={busy} onClick={() => void checkOriginal()}>Check original request</Button></section>}
    {previous && <section><h3>Earlier request</h3><p>Reference: <code>{previous.request_key}</code></p><Button disabled={busy} onClick={() => void checkOld()}>Check earlier request</Button><p>Resolve it in its original workflow before recording another payment.</p></section>}
    {orphan && <p>Earlier recovery context remains. Resolve it in its original workflow.</p>}
    {allowMutations && ready && !review && <section>{initialGroupId===undefined&&<><Field label="Find active group" htmlFor="create-group-search"><input id="create-group-search" className="admin-input" maxLength={200} value={search} onChange={event => setSearch(event.target.value)} /></Field><Button disabled={busy} onClick={() => void findGroups()}>Find groups</Button></>}
      {groups.length > 0 && <><Field label="Group" htmlFor="create-group"><select id="create-group" className="admin-input" disabled={initialGroupId!==undefined} value={group?.id ?? ''} onChange={event => {setGroup(groups.find(row => row.id === event.target.value) ?? null); setPayees([]); setPayee(null);setSources([]);setSelectedSource(null);}}><option value="">Select a group</option>{groups.map(row => <option key={row.id} value={row.id}>{row.label}</option>)}</select></Field><Button disabled={busy || !group} onClick={() => void findPayees()}>Find receivers</Button></>}
      {payees.length > 0 && <Field label="Receiver" htmlFor="create-receiver"><select id="create-receiver" className="admin-input" value={payee?.id ?? ''} onChange={event => {setPayee(payees.find(row => row.id === event.target.value) ?? null);setSources([]);setSelectedSource(null);}}><option value="">Select a receiver</option>{payees.map(row => <option key={row.id} value={row.id}>{row.label} · {row.network}</option>)}</select></Field>}
      {payee&&canReadSms&&<><Field label="Find preserved receiver SMS facts" htmlFor="create-source-search"><input id="create-source-search" className="admin-input" value={sourceSearch} maxLength={200} onChange={event=>setSourceSearch(event.target.value)}/></Field><Button disabled={busy} onClick={()=>void findSources()}>Find receiver sources</Button>
        {truncated&&<p>Only the first 100 results are shown. Search to narrow the source list.</p>}
        {sources.length>0&&<Field label="Preserved receiver source (optional)" htmlFor="create-source"><select id="create-source" className="admin-input" value={selectedSource?.factId??''} onChange={event=>setSelectedSource(sources.find(row=>row.factId===event.target.value)??null)}><option value="">No preserved source</option>{sources.map(row=><option key={row.factId} value={row.factId}>{row.payerName??'Unknown payer'} · {row.reference} · RWF {new Intl.NumberFormat('en-RW').format(row.amount)}</option>)}</select></Field>}
        <p>Parsed receiver observations are unverified. The reference and amount entered below must match the selected source.</p></>}
    </section>}
    {allowMutations && (ready && group && payee || retryAvailable && original?.kind === 'owned' && original.attempt && !previous && !orphan && targets) && !review && <form className="core-edit-form" onSubmit={event => void makeReview(event)}>
      {retryAvailable && targets && <p>Original group {targets.group.title} · receiver {targets.payee.label} · versions {targets.group.version}/{targets.payee.version}.{selectedSource?` Preserved source ${selectedSource.factId}.`:''}</p>}
      <Field label="Provider reference" htmlFor="create-provider-ref"><input id="create-provider-ref" className="admin-input" required maxLength={160} value={draft.reference} onChange={event => setDraft({...draft, reference: event.target.value})} /></Field>
      <Field label="Payment amount (RWF)" htmlFor="create-payment-amount"><input id="create-payment-amount" className="admin-input" inputMode="numeric" required value={draft.amount} onChange={event => setDraft({...draft, amount: event.target.value})} /></Field>
      <Field label="Observed at (UTC)" htmlFor="create-observed" hint="Example: 2026-10-04T12:00:00Z"><input id="create-observed" className="admin-input" required value={draft.observed} onChange={event => setDraft({...draft, observed: event.target.value})} /></Field>
      <Field label="Evidence type" htmlFor="create-evidence-kind"><select id="create-evidence-kind" className="admin-input" value={draft.kind} onChange={event => setDraft({...draft, kind: event.target.value})}><option value="operator_observation">Operator observation</option><option value="payer_receipt">Payer receipt</option><option value="receiver_statement">Receiver statement</option><option value="provider_statement">Provider statement</option></select></Field>
      <Field label="Evidence reference" htmlFor="create-evidence-reference"><input id="create-evidence-reference" className="admin-input" minLength={8} maxLength={500} required value={draft.evidenceReference} onChange={event => setDraft({...draft, evidenceReference: event.target.value})} /></Field>
      <Field label="Evidence SHA-256" htmlFor="create-evidence-digest"><input id="create-evidence-digest" className="admin-input" pattern="[a-f0-9]{64}" required value={draft.digest} onChange={event => setDraft({...draft, digest: event.target.value})} /></Field>
      <Field label="Reason" htmlFor="create-evidence-reason"><textarea id="create-evidence-reason" className="admin-input" minLength={8} maxLength={1000} required value={draft.reason} onChange={event => setDraft({...draft, reason: event.target.value})} /></Field>
      <Button type="submit" variant="primary" disabled={busy}>Review payment evidence</Button>
    </form>}
    {review && targets && allowMutations && <section><h3>{original ? 'Review identical request' : 'Review payment evidence'}</h3><dl><div><dt>Group</dt><dd>{targets.group.title} · {targets.group.id} · version {targets.group.version}</dd></div><div><dt>Receiver</dt><dd>{targets.payee.label} · {targets.payee.id} · {targets.payee.network} · {targets.payee.route} · version {targets.payee.version}</dd></div><div><dt>Provider reference</dt><dd>{review.provider_reference}</dd></div><div><dt>Amount</dt><dd>RWF {new Intl.NumberFormat('en-RW').format(review.amount_rwf)}</dd></div><div><dt>Observed (UTC)</dt><dd>{new Date(review.observed_at * 1000).toISOString()}</dd></div>{reviewedSource&&<div><dt>Preserved receiver source</dt><dd>{reviewedSource.factId} · source {reviewedSource.receiptId} · {reviewedSource.sourceSha256}</dd></div>}<div><dt>Evidence</dt><dd>{review.evidence.kind} · {review.evidence.reference} · {review.evidence.sha256}</dd></div><div><dt>Reason</dt><dd>{review.reason}</dd></div></dl>
      {original && <p>Retrying the same key may record the payment if the original did not complete.</p>}<label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} disabled={busy} /> I reviewed the payment, receiving account, evidence and reason.</label>
      <Button disabled={busy} onClick={() => {setReview(null); setConfirmed(false);}}>Cancel</Button><Button variant="primary" disabled={busy || !confirmed} onClick={() => void submit()}>{original ? 'Confirm same request' : 'Confirm payment evidence'}</Button>
    </section>}
  </Card>;
}
