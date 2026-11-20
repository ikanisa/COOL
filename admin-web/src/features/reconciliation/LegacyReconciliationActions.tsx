import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Button, Card, LoadingState } from '../../ui';
import { formatMoney, isId } from '../core/contracts';
import type { PendingIdentity } from '../core/pendingAttempt';
import type { FeatureAccess } from '../core/types';
import type { ReconciliationSnapshot } from './actions';
import { currentLegacyDecision, listLegacyProposals, lookupLegacyDecision, makeLegacyProposal, makeLegacyReview, parseLegacyDecisionIntent, restoreLegacyDecision, retryLegacyDecision, searchLegacyReconciliationMembers, submitLegacyDecision, type LegacyDecisionContext, type LegacyDecisionIntent, type LegacyDecisionPending, type LegacyDecisionSource, type LegacyMember, type LegacyProposal } from './legacyActions';

export interface LegacyReconciliationActionsProps {detail: ReconciliationSnapshot; access: FeatureAccess; identity: PendingIdentity; allowMutations?: boolean; verifyFresh: () => Promise<boolean>; onCompleted: () => void;}

/** Writes are disabled until the backend and coexistence are qualified. */
export function LegacyReconciliationActions({detail, access, identity, allowMutations = false, verifyFresh, onCompleted}: LegacyReconciliationActionsProps) {
  const identityKey = JSON.stringify([...new Set(identity.permissions)].sort()), permissionKey = JSON.stringify([...new Set(access.permissions)].sort());
  const user = useMemo<PendingIdentity>(() => ({id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role, permissions: JSON.parse(identityKey) as string[], expiresAt: identity.expiresAt}), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, identityKey]);
  const permissions = useMemo<readonly string[]>(() => JSON.parse(permissionKey) as string[], [permissionKey]), id = String(detail.resource.id);
  const allowed = access.financialModel === 'transaction_journals' && isId(id) && isId(access.actorId) && user.id === access.actorId && user.role === access.role && permissions.includes('reconciliations.read') && user.permissions.includes('reconciliations.read');
  const scope = JSON.stringify([access.authorityKey, id, user.id, user.sessionId, user.role, user.expiresAt, identityKey, permissionKey]), current = useRef(scope), gate = useRef(allowMutations), verify = useRef(verifyFresh), busy = useRef(false);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = allowMutations; return () => {gate.current = false;};}, [allowMutations]);
  useLayoutEffect(() => {verify.current = verifyFresh;}, [verifyFresh]);
  const context = useMemo<LegacyDecisionContext>(() => ({transactionId: id, request: access.request, identity: user, actorId: access.actorId, permissions, financialModel: access.financialModel, enabled: allowMutations,
    isCurrent: () => current.current === scope && Date.parse(user.expiresAt) > Date.now(), isEnabled: () => gate.current, verifyFresh: () => verify.current()}), [id, access.request, access.actorId, access.financialModel, user, permissions, allowMutations, scope]);
  const [pending, setPending] = useState<LegacyDecisionPending | null>(null), [loadedScope, setLoadedScope] = useState(''), [state, setState] = useState<'loading' | 'ready' | 'busy' | 'error'>('loading');
  const [message, setMessage] = useState(''), [search, setSearch] = useState(''), [members, setMembers] = useState<LegacyMember[]>([]), [page, setPage] = useState<{search: string; offset: number; total: number; nextOffset: number | null} | null>(null), [selected, setSelected] = useState<LegacyMember | null>(null);
  const [proposals, setProposals] = useState<LegacyProposal[]>([]), [proposal, setProposal] = useState<LegacyProposal | null>(null), [amount, setAmount] = useState(''), [reason, setReason] = useState('');
  const [review, setReview] = useState<LegacyDecisionIntent | null>(null), [source, setSource] = useState<LegacyDecisionSource | null>(null), [revision, setRevision] = useState(''), [confirmed, setConfirmed] = useState(false), [retryAllowed, setRetryAllowed] = useState(false);
  useEffect(() => {
    if (!allowed) return; let live = true;
    restoreLegacyDecision(context).then(value => {if (live && context.isCurrent()) {setPending(value); setLoadedScope(scope); setState('ready'); setMessage(value.kind !== 'ready' ? 'A previous reconciliation request needs recovery.' : !allowMutations ? 'Reconciliation changes are not enabled for this workspace.' : '');}})
      .catch(() => {if (live && context.isCurrent()) {setLoadedScope(scope); setState('error'); setMessage('Reconciliation recovery data could not be verified.');}});
    return () => {live = false;};
  }, [allowed, allowMutations, context, scope]);
  const unresolved = pending && pending.kind !== 'ready' ? pending : null, ready = pending?.kind === 'ready' ? pending : null;
  const searchMembers = async (event?: FormEvent, offset = 0) => {
    event?.preventDefault(); if (!ready || !allowMutations || busy.current || !context.isCurrent() || !detail.canPropose) return;
    const query = offset === 0 ? search : page?.search ?? ''; busy.current = true; setState('busy'); setMessage('');
    try {const result = await searchLegacyReconciliationMembers(context, query, offset); if (context.isCurrent()) {setMembers(result.rows); setPage({search: query.trim(), offset, total: result.total, nextOffset: result.nextOffset}); setSelected(null); setProposal(null); if (!result.rows.length) setMessage('No eligible members were found.');}}
    catch {if (context.isCurrent()) setMessage('Current members could not be verified. Refresh the payment before continuing.');}
    finally {busy.current = false; if (context.isCurrent()) setState('ready');}
  };
  const loadProposals = async () => {
    if (!ready || !allowMutations || busy.current || !context.isCurrent() || !detail.canReview) return;
    busy.current = true; setState('busy'); setMessage('');
    try {const rows = await listLegacyProposals(context); if (context.isCurrent()) {const eligible = rows.filter(item => item.status === 'pending' && item.proposed_by_admin_id !== context.actorId); setProposals(eligible); setProposal(null); setSelected(null); if (!eligible.length) setMessage('No independent pending proposals were found.');}}
    catch {if (context.isCurrent()) setMessage('Current proposals could not be verified. Refresh the payment before continuing.');}
    finally {busy.current = false; if (context.isCurrent()) setState('ready');}
  };
  const prepare = async (outcome?: 'approved' | 'rejected') => {
    if (!ready || !allowMutations || busy.current || !context.isCurrent() || outcome && !proposal || !outcome && !selected) return;
    busy.current = true; setState('busy'); setMessage('');
    try {
      const n = Number(amount.trim()); if (!outcome && (!/^[1-9]\d*$/.test(amount.trim()) || !Number.isSafeInteger(n))) throw new Error('Invalid amount');
      const intent = outcome ? makeLegacyReview(context, detail.resource, proposal!, outcome, reason) : makeLegacyProposal(context, detail.resource, selected!, n, reason), latest = await currentLegacyDecision(context, intent);
      if (!outcome && JSON.stringify(latest.member) !== JSON.stringify(selected) || outcome && JSON.stringify(latest.proposal) !== JSON.stringify(proposal)) throw new Error('Changed record');
      if (context.isCurrent() && gate.current) {setReview(intent); setSource(latest); setRevision(ready.revision); setConfirmed(false);}
    } catch {if (context.isCurrent()) setMessage('The payment, member, receiver or proposal could not be verified. Refresh before continuing.');}
    finally {busy.current = false; if (context.isCurrent()) setState('ready');}
  };
  const send = async () => {
    if (!allowMutations || !review || !source || !confirmed || busy.current || !context.isCurrent() || unresolved?.kind === 'foreign' || unresolved?.kind === 'owned' && !retryAllowed) return;
    busy.current = true; setState('busy'); setMessage('');
    try {
      const result = unresolved?.kind === 'owned' ? await retryLegacyDecision(context, unresolved) : await submitLegacyDecision(context, review, source, revision);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setMessage(result.receipt.status === 'approved' ? 'The independent approval and allocation were recorded. Provider settlement is not asserted.' : result.receipt.status === 'rejected' ? 'The independent rejection was recorded.' : 'The proposal was recorded for independent review.'); onCompleted();}
      else if (result.status === 'existing') {setPending(result.pending); setMessage('A previous reconciliation request needs recovery.');}
      else {setPending({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unconfirmed. Keep request reference ${result.requestKey} and check the original request.`); try {setPending(await restoreLegacyDecision(context));} catch { /* Keep the original reference visible. */ }}
    } catch {if (context.isCurrent()) {setMessage('The payment, review or recovery data could not be verified. Check the original request before continuing.'); try {setPending(await restoreLegacyDecision(context));} catch {setPending(null); setState('error');}}}
    finally {busy.current = false; if (context.isCurrent()) {setState(previous => previous === 'error' ? previous : 'ready'); setReview(null); setSource(null); setConfirmed(false); setRetryAllowed(false);}}
  };
  const lookup = async () => {
    if (!unresolved || unresolved.kind !== 'owned' || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('busy'); setMessage(''); setRetryAllowed(false);
    try {const result = await lookupLegacyDecision(context, unresolved); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setMessage('The original reconciliation request was recorded. Provider settlement is not asserted.'); onCompleted();}
      else if (result.status === 'not_found') {setRetryAllowed(result.retryAvailable && allowMutations); setMessage(result.retryAvailable && allowMutations ? 'No completed request was found. You may review the same request using its original reference.' : 'No completed request was found. Keep its reference; the original intent cannot be verified for retry.');}
      else setMessage(result.status === 'failed' ? 'The original request failed. Keep its reference and refresh before another change.' : 'The original request is still pending. Check again before continuing.');}
    catch {if (context.isCurrent()) setMessage('The original request could not be verified. Keep its reference and check again.');}
    finally {busy.current = false; if (context.isCurrent()) setState('ready');}
  };
  const reviewSame = async () => {
    if (!unresolved || unresolved.kind !== 'owned' || !unresolved.attempt || !retryAllowed || !allowMutations || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('busy'); setMessage('');
    try {const original = parseLegacyDecisionIntent(unresolved.attempt.intent, context, unresolved.attempt.permission), latest = await currentLegacyDecision(context, original); if (context.isCurrent() && gate.current) {setReview(original); setSource(latest); setConfirmed(false);}}
    catch {if (context.isCurrent()) {setRetryAllowed(false); setMessage('The current payment or proposal could not be verified. Check the original request again.');}}
    finally {busy.current = false; if (context.isCurrent()) setState('ready');}
  };
  if (!allowed) return null;
  if (state === 'loading' || loadedScope !== scope) return <LoadingState label="Checking reconciliation recovery" />;
  return <Card><div className="core-detail"><h2>Reconciliation decisions</h2><p>Approval records an allocation after independent review; it does not post a journal or establish provider settlement. The recorded source state is checked with each decision.</p>{message && <p role="alert">{message}</p>}
    {unresolved?.kind === 'foreign' && <p>Another account or session has an unresolved reconciliation request. The original account must check it.</p>}
    {unresolved?.kind === 'owned' && <section><h3>Original request needs review</h3><p>Request reference: <code>{unresolved.requestKey}</code></p>{!unresolved.attempt && <p>The original form is unavailable. Keep this reference and check the request.</p>}<Button type="button" disabled={state !== 'ready'} onClick={() => void lookup()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same request</Button>}</section>}
    {!unresolved && ready && allowMutations && state !== 'error' && !review && <>
      {detail.canPropose && <><form className="core-search" onSubmit={event => void searchMembers(event)}><label>Search eligible members<input className="admin-input" maxLength={200} value={search} onChange={event => setSearch(event.target.value)} /></label><Button type="submit" disabled={state !== 'ready'}>Search members</Button></form>
        {page && <div><p>{page.total} matching members</p><Button type="button" disabled={state !== 'ready' || page.offset === 0} onClick={() => void searchMembers(undefined, Math.max(0, page.offset - 25))}>Previous members</Button><Button type="button" disabled={state !== 'ready' || page.nextOffset === null} onClick={() => void searchMembers(undefined, page.nextOffset!)}>Next members</Button></div>}
        {members.length > 0 && <label>Member<select className="admin-input" value={selected?.member_user_id ?? ''} onChange={event => {setSelected(members.find(value => value.member_user_id === event.target.value) ?? null); setProposal(null);}}><option value="">Select member</option>{members.map(value => <option key={value.member_user_id} value={value.member_user_id}>{value.payment_identity.display_name} · {value.public_id}</option>)}</select></label>}</>}
      {detail.canReview && <><Button type="button" disabled={state !== 'ready'} onClick={() => void loadProposals()}>Load independent proposals</Button>{proposals.length > 0 && <label>Proposal<select className="admin-input" value={proposal?.id ?? ''} onChange={event => {setProposal(proposals.find(value => value.id === event.target.value) ?? null); setSelected(null);}}><option value="">Select proposal</option>{proposals.map(value => <option key={value.id} value={value.id}>{value.payment_identity.display_name} · {formatMoney(value.amount_rwf)}</option>)}</select></label>}</>}
      {(selected || proposal) && <><p>Recorded member: {(selected?.payment_identity ?? proposal?.payment_identity)?.display_name} · MoMo {(selected?.payment_identity ?? proposal?.payment_identity)?.momo_number}</p>{selected && <label>Amount (RWF)<input className="admin-input" inputMode="numeric" value={amount} onChange={event => setAmount(event.target.value)} /></label>}<label>Reason<textarea className="admin-input" minLength={8} maxLength={1000} value={reason} onChange={event => setReason(event.target.value)} /></label>{selected ? <Button type="button" variant="primary" disabled={state !== 'ready'} onClick={() => void prepare()}>Review proposal</Button> : <><Button type="button" disabled={state !== 'ready'} onClick={() => void prepare('rejected')}>Review rejection</Button><Button type="button" variant="primary" disabled={state !== 'ready'} onClick={() => void prepare('approved')}>Review approval</Button></>}</>}
    </>}
    {review && source && allowMutations && <section><h3>Confirm reconciliation {review.proposal_id ? String(review.body.outcome) : 'proposal'}</h3><p>Group: {String(source.transaction.group_title)} · Receiver: {String(source.transaction.payee_name)} · {String(source.transaction.payee_momo)}</p><p>Payment reference: {String(source.transaction.provider_reference)} · {formatMoney(source.transaction.amount_rwf)} · unallocated {formatMoney(source.transaction.unallocated_amount_rwf)}</p><p>Recorded member: {(source.member?.payment_identity ?? source.proposal?.payment_identity)?.display_name} · MoMo {(source.member?.payment_identity ?? source.proposal?.payment_identity)?.momo_number} · amount {formatMoney(source.proposal?.amount_rwf ?? review.body.amount_rwf)}</p><p>Source: {String(source.transaction.source_link_basis ?? 'not recorded')} · {(source.transaction.source_kind ? String(source.transaction.source_kind) : 'source not recorded')}. Provider confirmation is not asserted.</p><p>Reason: {String(review.body.reason)}</p>{unresolved && <p>The same original request will be used; it may make this change if the earlier request did not commit.</p>}<label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} /> I reviewed the evidence, member, receiver, amount and reason.</label><Button type="button" disabled={state !== 'ready'} onClick={() => {setReview(null); setSource(null); setConfirmed(false);}}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !confirmed} onClick={() => void send()}>{unresolved ? 'Confirm same request' : 'Confirm reconciliation'}</Button></section>}
  </div></Card>;
}
