import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Button, Card, LoadingState } from '../../ui';
import { formatMoney, isObject } from '../core/contracts';
import { readPending } from '../core/pendingAttempt';
import type { PendingAttempt, PendingIdentity } from '../core/pendingAttempt';
import type { FeatureAccess } from '../core/types';
import { parseReconciliationDetail } from './contracts';
import { FinancialAttemptError, lookupFinancialAttempt, parseFinancialIntent, parseReconciliationMembers, prepareProposal, prepareReview, RECONCILIATION_FAMILY, retryFinancialAttempt, submitFinancialAttempt } from './actions';
import type { FinancialIntent, ReconciliationMember, ReconciliationSnapshot } from './actions';

export interface CanonicalActionsProps {
  detail: ReconciliationSnapshot;
  access: FeatureAccess;
  identity: PendingIdentity;
  allowMutations?: boolean;
  verifyFresh: () => Promise<boolean>;
  onCompleted: () => void;
}

function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  if (isObject(value)) return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${stable(value[key])}`).join(',')}}`;
  return JSON.stringify(value) ?? 'null';
}

function authorityIsCurrent(current: {current: string}, scope: string, expiresAt: string): boolean {
  return current.current === scope && Date.parse(expiresAt) > Date.now();
}

export function CanonicalReconciliationActions({ detail, access, identity, allowMutations = false, verifyFresh, onCompleted }: CanonicalActionsProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email,
    role: identity.role, permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }),
  [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const id = String(detail.resource.id);
  const scope = JSON.stringify([access.authorityKey, id, access.principalId]);
  const current = useRef(scope);
  useLayoutEffect(() => { current.current = scope; return () => { current.current = ''; }; }, [scope]);
  const writeGate = useRef(allowMutations);
  useLayoutEffect(() => { writeGate.current = allowMutations; return () => { writeGate.current = false; }; }, [allowMutations]);
  const isCurrent = () => authorityIsCurrent(current, scope, stableIdentity.expiresAt);
  const [pendingState, setPendingState] = useState<{scope: string; value: PendingAttempt | null; error: boolean} | null>(null);
  const pending = pendingState?.scope === scope ? pendingState.value : null;
  const [members, setMembers] = useState<ReconciliationMember[]>([]);
  const [memberPage, setMemberPage] = useState<{ search: string; offset: number; total: number; nextOffset: number | null } | null>(null);
  const [selected, setSelected] = useState<ReconciliationMember | null>(null);
  const [proposal, setProposal] = useState<Record<string, unknown> | null>(null);
  const [reason, setReason] = useState('');
  const [search, setSearch] = useState('');
  const [acknowledged, setAcknowledged] = useState(false);
  const [review, setReview] = useState<FinancialIntent | null>(null);
  const [retryAllowed, setRetryAllowed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const operationBusy = useRef(false);
  useEffect(() => {
    let live = true;
    readPending(stableIdentity, RECONCILIATION_FAMILY, id).then(value => {
      if (value) parseFinancialIntent(value.intent, id, value.permission);
      if (live) setPendingState({scope, value, error: false});
    }).catch(() => { if (live) setPendingState({scope, value: null, error: true}); });
    return () => { live = false; };
  }, [stableIdentity, id, scope]);

  const loadMembers = async (query: string, offset = 0) => {
    if (!access.permissions.includes('users.read') || operationBusy.current || !isCurrent()) return;
    if (query.length > 200 || [...query].some(char => { const code = char.codePointAt(0)!; return code < 0x20 || code === 0x7f; })) { setMessage('Check the member search.'); return; }
    operationBusy.current = true; setBusy(true); setMessage('');
    try {
      const params = new URLSearchParams({ transaction_id: id, search: query.trim(), limit: '25', offset: String(offset) });
      const data = await access.request(`reconciliations/members?${params.toString()}`);
      const page = parseReconciliationMembers(data, detail, 25, offset);
      if (!isCurrent()) return;
      setMembers(page.rows); setMemberPage({ search: query.trim(), offset, total: page.total, nextOffset: page.nextOffset });
      setSelected(null); setAcknowledged(false);
    } catch { if (isCurrent()) setMessage('Current members could not be verified. Reopen the payment before continuing.'); }
    finally { operationBusy.current = false; if (isCurrent()) setBusy(false); }
  };

  const prepare = (outcome?: 'approved' | 'rejected') => {
    if (!allowMutations || pending || !acknowledged || !isCurrent()) return;
    try {
      const intent = outcome ? prepareReview(detail, proposal!, outcome, reason, access.principalId!, access.role, access.permissions,
        members.find(member => member.member_user_id === proposal?.member_user_id)) : prepareProposal(detail, selected!, reason, access.permissions);
      setReview(intent); setMessage('');
    } catch { setMessage('The current payment, member, receiver or review permissions do not match. Refresh before continuing.'); }
  };

  const revalidate = async (intent: FinancialIntent): Promise<boolean> => {
    const query = new URLSearchParams({ limit: '25', offset: '0' });
    const raw = await access.request(`reconciliations/${id}?${query.toString()}`);
    const fresh = parseReconciliationDetail(raw, 'canonical_evidence_ledger', id, access.actorId, access.principalId, access.permissions, access.role);
    const currentProposal = intent.kind === 'review' ? fresh.related.proposals.rows.find(row => row.id === intent.proposal_id) : null;
    const publicId = intent.kind === 'propose' ? selected?.public_id ?? (isObject(intent.body.expected_payment_identity) ? intent.body.expected_payment_identity.momo_number : null) : currentProposal?.member_public_id;
    let currentMember: ReconciliationMember | undefined;
    if (typeof publicId === 'string') {
      const params = new URLSearchParams({ transaction_id: id, search: publicId, limit: '25', offset: '0' });
      const data = await access.request(`reconciliations/members?${params.toString()}`);
      const page = parseReconciliationMembers(data, fresh, 25, 0);
      const memberId = intent.kind === 'propose' ? intent.body.member_user_id : currentProposal?.member_user_id;
      currentMember = page.rows.find(row => row.member_user_id === memberId);
    }
    const expected = intent.kind === 'propose' && currentMember ? prepareProposal(fresh, currentMember, String(intent.body.reason), access.permissions) :
      intent.kind === 'review' && currentProposal && access.principalId ? prepareReview(fresh, currentProposal, intent.body.outcome as 'approved' | 'rejected', String(intent.body.reason), access.principalId, access.role, access.permissions, currentMember) : null;
    return expected !== null && stable(expected) === stable(intent);
  };

  const submit = async () => {
    if (!review || !allowMutations || pending || operationBusy.current || !isCurrent()) return;
    const key = globalThis.crypto?.randomUUID?.();
    if (!key) { setMessage('A secure request reference is unavailable.'); return; }
    operationBusy.current = true; setBusy(true); setMessage('');
    try {
      await submitFinancialAttempt(access, stableIdentity, review, key, allowMutations, verifyFresh, () => isCurrent() && writeGate.current, revalidate);
      if (!isCurrent()) return;
      setReview(null); setMessage('The reviewed request was recorded. Provider settlement is not asserted.'); onCompleted();
    } catch (error) {
      if (!isCurrent()) return;
      let storageFailed = false;
      const retained = await readPending(stableIdentity, RECONCILIATION_FAMILY, id).catch(() => { storageFailed = true; return null; });
      // If recovery storage itself failed, keep the action blocked: an attempted
      // request must never be replaced by a fresh key based on uncertainty.
      setPendingState({scope, value: retained, error: storageFailed || (!retained && (!(error instanceof FinancialAttemptError) || error.possiblySubmitted))}); setReview(null);
      setMessage(retained ? 'The result is unconfirmed. Check the original request before making another change.' : 'The request could not be verified. Refresh before continuing.');
    } finally { operationBusy.current = false; if (isCurrent()) setBusy(false); }
  };

  const check = async () => {
    if (!pending || operationBusy.current || !isCurrent()) return;
    operationBusy.current = true; setBusy(true); setMessage(''); setRetryAllowed(false); setReview(null);
    try {
      const status = await lookupFinancialAttempt(access, stableIdentity, pending, isCurrent);
      if (!isCurrent()) return;
      if (status === 'succeeded' || status === 'cancelled') {
        setPendingState({scope, value: null, error: false});
        setMessage(status === 'succeeded' ? 'The original request was recorded.' : 'The original request was cancelled.');
        onCompleted();
      } else {
        setRetryAllowed(status === 'not_found' && allowMutations);
        setMessage(status === 'not_found' ? 'No completed request was found. This does not establish failure; check again or review the same request.' : 'The original request is unconfirmed. Check again before continuing.');
      }
    } catch { if (isCurrent()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { operationBusy.current = false; if (isCurrent()) setBusy(false); }
  };

  const retry = async () => {
    if (!pending || !review || !retryAllowed || !acknowledged || !allowMutations || operationBusy.current || !isCurrent()) return;
    if (stable(review) !== stable(parseFinancialIntent(pending.intent, id, pending.permission))) return;
    operationBusy.current = true; setBusy(true); setMessage(''); setRetryAllowed(false);
    try {
      const status = await retryFinancialAttempt(access, stableIdentity, pending, allowMutations, verifyFresh, () => isCurrent() && writeGate.current, revalidate);
      if (!isCurrent()) return;
      setPendingState({scope, value: null, error: false}); setReview(null); setAcknowledged(false);
      setMessage(status === 'cancelled' ? 'The original request was cancelled.' : 'The original request was recorded. Provider settlement is not asserted.');
      onCompleted();
    } catch {
      if (!isCurrent()) return;
      let storageFailed = false;
      const retained = await readPending(stableIdentity, RECONCILIATION_FAMILY, id).catch(() => { storageFailed = true; return null; });
      setPendingState({scope, value: retained, error: storageFailed || !retained}); setReview(null); setAcknowledged(false);
      setMessage(retained ? 'The original request still needs review. Check it again before continuing.' : 'The request could not be verified. Refresh before continuing.');
    } finally { operationBusy.current = false; if (isCurrent()) setBusy(false); }
  };

  if (!pendingState || pendingState.scope !== scope) return <LoadingState label="Checking retained requests" />;
  if (pendingState.error) return <Card><div className="core-detail"><p role="alert">Recovery data could not be verified. Check the original request before continuing.</p></div></Card>;
  if (pending) {
    const original = parseFinancialIntent(pending.intent, id, pending.permission);
    const retainedProposal = original.kind === 'review' ? detail.related.proposals?.rows.find(row => row.id === original.proposal_id) : null;
    return <Card><div className="core-detail"><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p>
    <p>A lost response does not prove that the request failed.</p>{message && <p role="status">{message}</p>}
    <Button type="button" onClick={() => void check()} disabled={busy || !access.permissions.includes('account.manage')}>Check original request</Button>
    {!access.permissions.includes('account.manage') && <p>Your account cannot check request history. Contact an authorized administrator.</p>}
    {retryAllowed && !review && allowMutations && (original.kind !== 'review' || retainedProposal && isObject(retainedProposal.payment_identity)) && <Button type="button" disabled={busy} onClick={() => { setReview(original); setAcknowledged(false); }}>Review same request</Button>}
    {retryAllowed && review && allowMutations && <section><h3>Review the original request</h3><p>{review.kind === 'propose' ? 'Propose this member attribution' : `Record ${review.body.outcome}`}. The same request reference will be used.</p>
      {review.kind === 'propose' && isObject(review.body.expected_payment_identity) && <dl><div><dt>Recorded member</dt><dd>{String(review.body.expected_payment_identity.display_name)}</dd></div><div><dt>MoMo number</dt><dd>{String(review.body.expected_payment_identity.momo_number)}</dd></div><div><dt>Amount</dt><dd>{formatMoney(review.body.amount_rwf)}</dd></div></dl>}
      {review.kind === 'review' && retainedProposal && isObject(retainedProposal.payment_identity) && <dl><div><dt>Member ID</dt><dd>{String(retainedProposal.member_public_id)}</dd></div><div><dt>Recorded member</dt><dd>{String(retainedProposal.payment_identity.display_name)}</dd></div><div><dt>MoMo number</dt><dd>{String(retainedProposal.payment_identity.momo_number)}</dd></div></dl>}
      <p>Reason: {String(review.body.reason)}. Provider settlement is not asserted.</p><label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed this same request and its recorded identity.</label>
      <Button type="button" disabled={busy} onClick={() => { setReview(null); setAcknowledged(false); }}>Cancel</Button><Button type="button" variant="primary" disabled={busy || !acknowledged} onClick={() => void retry()}>Confirm same request</Button></section>}
  </div></Card>;
  }
  if (!allowMutations || (!detail.canPropose && !detail.canReview)) return null;
  const proposals = detail.related.proposals?.rows.filter(item => item.status === 'proposed' && item.proposed_by_principal_id !== access.principalId && item.snapshot_available === true) ?? [];
  return <Card><div className="core-detail"><h2>Reconciliation review</h2><p>Decisions record evidence and do not confirm provider settlement.</p>
    {message && <p role="alert">{message}</p>}
    {!review && <>
      {detail.canReview && proposals.length > 0 && <label>Proposal to review <select className="admin-input" value={proposal ? String(proposal.id) : ''} onChange={event => {
        const item = proposals.find(value => value.id === event.target.value) ?? null;
        setProposal(item); setSelected(null); setAcknowledged(false); setMembers([]); setMemberPage(null);
        if (item && typeof item.member_public_id === 'string') void loadMembers(item.member_public_id);
      }}><option value="">Select a proposal</option>{proposals.map(item => <option key={String(item.id)} value={String(item.id)}>Member {String(item.member_public_id)}</option>)}</select></label>}
      {!proposal && detail.canPropose && <>
        <form className="core-search" onSubmit={event => { event.preventDefault(); void loadMembers(search); }}><label>Find a group member <input className="admin-input" value={search} maxLength={200} onChange={event => setSearch(event.target.value)} /></label><Button type="submit" disabled={busy}>Find members</Button></form>
        {memberPage && <><div className="admin-table-wrap"><table className="admin-table"><thead><tr><th scope="col">Member ID</th><th scope="col">Recorded name</th><th scope="col">MoMo number</th><th scope="col">Select</th></tr></thead><tbody>{members.map(member => <tr key={member.member_user_id}><td>{String(member.public_id)}</td><td>{String(member.display_name)}</td><td>{String(member.momo_number)}</td><td><Button type="button" disabled={busy} onClick={() => { setSelected(member); setAcknowledged(false); }}>{selected?.member_user_id === member.member_user_id ? 'Selected' : 'Select'}</Button></td></tr>)}</tbody></table></div><div className="core-pager"><span>{memberPage.total} matching members</span><div><Button type="button" disabled={busy || memberPage.offset === 0} onClick={() => void loadMembers(memberPage.search, Math.max(0, memberPage.offset - 25))}>Previous</Button><Button type="button" disabled={busy || memberPage.nextOffset === null} onClick={() => void loadMembers(memberPage.search, memberPage.nextOffset!)}>Next</Button></div></div></>}
      </>}
      {proposal && <><p>Review member {String(proposal.member_public_id)} and the retained payment identity. Current member details must still match for approval.</p>{isObject(proposal.payment_identity) && <dl><div><dt>Recorded name</dt><dd>{String(proposal.payment_identity.display_name)}</dd></div><div><dt>MoMo provider</dt><dd>{String(proposal.payment_identity.momo_provider)}</dd></div><div><dt>MoMo number</dt><dd>{String(proposal.payment_identity.momo_number)}</dd></div><div><dt>MoMo code</dt><dd>{String(proposal.payment_identity.momo_pay_code || 'Not recorded')}</dd></div></dl>}</>}
      {(selected || proposal) && <><p>Recorded amount: {formatMoney(detail.resource.amount_rwf)}</p><label>Reason <textarea className="admin-input" value={reason} minLength={8} maxLength={500} onChange={event => setReason(event.target.value)} /></label><label><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} /> I reviewed the evidence, member and recorded payment identity.</label>
        {proposal ? <><Button type="button" disabled={busy || !acknowledged} onClick={() => prepare('rejected')}>Review rejection</Button><Button type="button" variant="primary" disabled={busy || !acknowledged} onClick={() => prepare('approved')}>Review approval</Button></> : <Button type="button" variant="primary" disabled={busy || !acknowledged} onClick={() => prepare()}>Review attribution</Button>}</>}
    </>}
    {review && <section><h3>Confirm reviewed request</h3><p>{review.kind === 'propose' ? 'Propose this member attribution' : `Record ${review.body.outcome}`}. This does not move money or assert provider settlement.</p><p>Reason: {String(review.body.reason)}</p>{review.kind === 'propose' && isObject(review.body.expected_payment_identity) && <dl><div><dt>Recorded member</dt><dd>{String(review.body.expected_payment_identity.display_name)}</dd></div><div><dt>MoMo number</dt><dd>{String(review.body.expected_payment_identity.momo_number)}</dd></div><div><dt>Amount</dt><dd>{formatMoney(review.body.amount_rwf)}</dd></div></dl>}<Button type="button" disabled={busy} onClick={() => setReview(null)}>Cancel</Button><Button type="button" variant="primary" disabled={busy} onClick={() => void submit()}>Confirm reviewed request</Button></section>}
  </div></Card>;
}
