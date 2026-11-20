import {useEffect, useLayoutEffect, useRef, useState} from 'react';
import type {AdminRequest} from '../../api/client';
import {sensitiveVerificationDeadline, type AdminUser} from '../../session/SessionProvider';
import {Button, Card, EmptyState, ErrorState, LoadingState, PageHeader, StatusBadge} from '../../ui';
import {parsePrivacyDetail, parsePrivacyJournal, parsePrivacyOperation, parsePrivacyPage, parseRetentionContext, parseRetentionInspection, privacyIntentApplies, privacyJournalKey, type PrivacyCursor, type PrivacyDetail, type PrivacyPageData, type PrivacyPending, type RetentionContext, type RetentionInspection} from './contracts';
import {completePrivacyIntent, reservePrivacyIntent} from './journal';
import './privacy.css';

const labels: Record<string, string> = {not_started: 'Not started', awaiting_review: 'Awaiting review', claim_active: 'Review in progress', claim_expired: 'Review claim expired', blocked: 'Waiting for approved policy'};
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const formatDate = (value: number) => new Date(value).toISOString().replace('T', ' ').replace(/\.\d{3}Z$/, ' UTC');
const proofIsCurrent = (proofAt: number, proofUntil: number) => Number.isFinite(proofAt) && proofAt <= Date.now() && proofUntil > Date.now();
const hasNotExpired = (until: number) => until > Date.now();
const evidenceIsCurrent = (checkedAt: number) => checkedAt <= Date.now() && Date.now() - checkedAt < 600_000;
const applicableNow = (intent: PrivacyPending, detail: PrivacyDetail) => privacyIntentApplies(intent, detail, Date.now());

// Permit a subsecond server clock lead to elapse; the parsers still require actual fresh evidence.
async function waitForEvidenceClock(value: Record<string, unknown>, signal: AbortSignal) {
  const checked = typeof value.checked_at === 'string' ? Date.parse(value.checked_at) : NaN;
  const fraction = typeof value.checked_at === 'string' ? value.checked_at.match(/\.(\d+)Z$/)?.[1] ?? '' : '';
  const delay = checked - Date.now() + (/[1-9]/.test(fraction.slice(3)) ? 1 : 0);
  if (!Number.isFinite(delay) || delay <= 0 || delay >= 1000) return;
  await new Promise<void>((resolve, reject) => {
    const abort = () => {clearTimeout(timer); reject(new Error('Request cancelled.'));};
    const timer = setTimeout(() => {signal.removeEventListener('abort', abort); resolve();}, Math.ceil(delay) + 1);
    if (signal.aborted) abort(); else signal.addEventListener('abort', abort, {once: true});
  });
}

export function PrivacyPage({user, epoch, verificationMode, request, verifyFresh, isCurrentAuthority, onVerify, allowActions = false}: {
  user: AdminUser; epoch: number; verificationMode: 'email' | 'authenticator'; request: AdminRequest;
  verifyFresh: () => Promise<boolean>; isCurrentAuthority: (epoch: number, actorId: string, sessionId: string) => boolean; onVerify: () => void; allowActions?: boolean;
}) {
  const proof = verificationMode === 'email' ? user.emailVerifiedAt : user.assuranceLevel === 2 ? user.mfaAt : null;
  const proofUntil = sensitiveVerificationDeadline(user, verificationMode === 'email' ? 'supabase' : 'cloudflare') ?? NaN;
  const proofAt = Number.isFinite(proofUntil) && proof ? Math.min(Date.parse(proof), user.mfaRequired && user.mfaAt ? Date.parse(user.mfaAt) : Infinity) : NaN;
  const [context, setContext] = useState<RetentionContext | null>(null);
  const [page, setPage] = useState<PrivacyPageData | null>(null);
  const [detail, setDetail] = useState<PrivacyDetail | null>(null);
  const [inspection, setInspection] = useState<RetentionInspection | null>(null);
  const [checkpoint, setCheckpoint] = useState<{key: string; raw: string; pending: PrivacyPending; generation: number} | null>(null);
  const [checkpointNotice, setCheckpointNotice] = useState('');
  const [journalGeneration, setJournalGeneration] = useState<number | null>(null);
  const [review, setReview] = useState<PrivacyPending | null>(null);
  const [retryReady, setRetryReady] = useState(false);
  const [history, setHistory] = useState<(PrivacyCursor | null)[]>([null]);
  const [busy, setBusy] = useState(false), [error, setError] = useState('');
  const proofScope = JSON.stringify([verificationMode, proof, user.mfaRequired, user.mfaAt, user.assuranceLevel, user.expiresAt]);
  const [proofState, setProofState] = useState<{scope: string; valid: boolean} | null>(null);
  const controller = useRef<AbortController | null>(null), timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const alive = useRef(false), inFlight = useRef(false), generation = useRef(0);
  const actionGate = useRef(allowActions);
  const access = user.permissions.includes('privacy.review') && !!user.principalId && uuidPattern.test(user.principalId) && uuidPattern.test(user.sessionId);
  const proofValid = () => proofIsCurrent(proofAt, proofUntil);
  const current = (sequence: number, until = proofUntil) => alive.current && generation.current === sequence && isCurrentAuthority(epoch, user.id, user.sessionId) && proofValid() && hasNotExpired(until);

  useLayoutEffect(() => {actionGate.current = allowActions;}, [allowActions]);

  useEffect(() => {
    let clock: ReturnType<typeof setTimeout>;
    const update = () => {
      const now = Date.now(), valid = Number.isFinite(proofAt) && proofAt <= now && proofUntil > now;
      setProofState({scope: proofScope, valid});
      if (valid) clock = setTimeout(update, Math.max(1, proofUntil - now));
    };
    clock = setTimeout(update, 0);
    return () => clearTimeout(clock);
  }, [proofAt, proofUntil, proofScope]);

  useEffect(() => {
    const generationRef = generation;
    alive.current = true;
    return () => {alive.current = false; generationRef.current++; controller.current?.abort(); if (timer.current) clearTimeout(timer.current);};
  }, []);

  const run = async (operation: (sequence: number, signal: AbortSignal) => Promise<void>) => {
    if (inFlight.current || !access || !proofValid() || !isCurrentAuthority(epoch, user.id, user.sessionId)) return;
    inFlight.current = true; setBusy(true); setError('');
    const sequence = ++generation.current, abort = new AbortController(); controller.current = abort;
    try {
      if (!await verifyFresh() || !current(sequence)) throw new Error('Verify your account before opening privacy reviews.');
      await operation(sequence, abort.signal);
    } catch {
      if (current(sequence)) setError('Privacy review evidence could not be verified. Refresh or verify your account again.');
    } finally {
      if (alive.current && generation.current === sequence) {inFlight.current = false; setBusy(false); controller.current = null;}
    }
  };
  const fetchPage = async (bound: RetentionContext, before: PrivacyCursor | null, sequence: number, signal: AbortSignal) => {
    if (!current(sequence, bound.validUntil)) throw new Error('Review access expired.');
    const raw = await request('privacy/admin_list_account_deletion_reviews_v1', {body: {p_limit: 25,
      p_before_accepted_at: before?.acceptedAtWire ?? null, p_before_request_id: before?.requestId ?? null}, signal});
    await waitForEvidenceClock(raw, signal);
    if (!current(sequence, bound.validUntil)) throw new Error('Review access expired.');
    return parsePrivacyPage(raw, 25, before);
  };
  const open = () => void run(async (sequence, signal) => {
    const raw = await request('privacy/admin_get_account_retention_context_v1', {body: {}, signal});
    await waitForEvidenceClock(raw, signal);
    if (!current(sequence)) throw new Error('Review access expired.');
    const bound = parseRetentionContext(raw), data = await fetchPage(bound, null, sequence, signal);
    if (!current(sequence, bound.validUntil)) throw new Error('Review access expired.');
    setContext(bound); setPage(data); setDetail(null); setInspection(null); setHistory([null]);
    try {
      const key = privacyJournalKey(user.principalId!, user.sessionId), stored = localStorage.getItem(key);
      const saved = parsePrivacyJournal(stored, user.principalId!, user.sessionId);
      setJournalGeneration(saved.generation); setReview(null); setRetryReady(false);
      setCheckpoint(saved.pending && stored ? {key, raw: stored, pending: saved.pending, generation: saved.generation} : null); setCheckpointNotice('');
    } catch {setCheckpoint(null); setJournalGeneration(null); setReview(null); setCheckpointNotice('The retained review reference could not be verified. Do not repeat a review until its original request is checked.');}
    if (timer.current) clearTimeout(timer.current);
    const duration = Math.max(0, Math.min(proofUntil, bound.validUntil) - Date.now());
    timer.current = setTimeout(() => {
      generation.current++; controller.current?.abort(); inFlight.current = false;
      if (alive.current) {setBusy(false); setContext(null); setPage(null); setDetail(null); setInspection(null); setCheckpoint(null); setJournalGeneration(null); setReview(null); setRetryReady(false); setCheckpointNotice(''); setError('Review access expired. Verify your account and reopen the queue.');}
    }, duration);
  });
  const pageTo = (target: PrivacyCursor | null, trail: (PrivacyCursor | null)[]) => {
    if (!context) return;
    void run(async (sequence, signal) => {
      const data = await fetchPage(context, target, sequence, signal);
      if (current(sequence, context.validUntil)) {setPage(data); setDetail(null); setInspection(null); setHistory(trail);}
    });
  };
  const openDetail = (id: string) => {
    if (!context) return;
    void run(async (sequence, signal) => {
      if (!current(sequence, context.validUntil)) throw new Error('Review access expired.');
      const raw = await request('privacy/admin_get_account_deletion_review_v1', {body: {p_request_id: id}, signal});
      await waitForEvidenceClock(raw, signal);
      if (!current(sequence, context.validUntil)) throw new Error('Review access expired.');
      setDetail(parsePrivacyDetail(raw, id)); setInspection(null);
    });
  };
  const inspect = () => {
    if (!context || !detail?.item || !user.principalId) return;
    const original = detail.item;
    void run(async (sequence, signal) => {
      if (!current(sequence, context.validUntil) || Date.now() < detail.checkedAt || Date.now() - detail.checkedAt >= 600_000) throw new Error('Review evidence expired.');
      const raw = await request('privacy/admin_inspect_account_retention_scope_v1', {body: {p_request_id: original.requestId,
        p_expected_review_revision: original.revision, p_expected_source_id: context.sourceId}, signal});
      if (!current(sequence, context.validUntil)) throw new Error('Review access expired.');
      setInspection(parseRetentionInspection(raw, original.requestId, context.sourceId, user.principalId!));
    });
  };
  const checkOriginal = () => {
    if (!context || !checkpoint) return;
    void run(async (sequence, signal) => {
      if (!current(sequence, context.validUntil) || localStorage.getItem(checkpoint.key) !== checkpoint.raw) throw new Error('The saved request changed.');
      const raw = await request('privacy/admin_get_account_deletion_review_operation_v1', {body: {p_operation_kind: checkpoint.pending.kind,
        p_operation_id: checkpoint.pending.operationId}, signal});
      await waitForEvidenceClock(raw, signal);
      if (!current(sequence, context.validUntil) || localStorage.getItem(checkpoint.key) !== checkpoint.raw) throw new Error('The saved request changed.');
      const observed = parsePrivacyOperation(raw, checkpoint.pending);
      if (observed && actionGate.current) {
        const next = await completePrivacyIntent({actorId: checkpoint.pending.actorId, sessionId: user.sessionId,
          current: () => current(sequence, context.validUntil) && actionGate.current}, checkpoint.pending, checkpoint.generation, raw.receipt);
        if (!current(sequence, context.validUntil)) throw new Error('Review access expired.');
        setCheckpoint(null); setJournalGeneration(next); setDetail(null); setPage(null); setRetryReady(false);
        setCheckpointNotice('The original operation was recorded. No data was erased. Refresh reviews for current evidence.');
      } else {
        setRetryReady(!observed && actionGate.current);
        setCheckpointNotice(observed ? 'The original operation was recorded. Its retained reference has not been cleared here.' :
          'No record was observed. This does not prove the original operation failed; keep its reference.');
      }
    });
  };
  const reviewOriginal = () => {
    if (!allowActions || !retryReady || !context || !checkpoint) return;
    void run(async (sequence, signal) => {
      if (!current(sequence, context.validUntil) || localStorage.getItem(checkpoint.key) !== checkpoint.raw) throw new Error('The saved request changed.');
      const raw = await request('privacy/admin_get_account_deletion_review_v1', {body: {p_request_id: checkpoint.pending.requestId}, signal});
      await waitForEvidenceClock(raw, signal);
      if (!current(sequence, context.validUntil) || localStorage.getItem(checkpoint.key) !== checkpoint.raw) throw new Error('The saved request changed.');
      const refreshed = parsePrivacyDetail(raw, checkpoint.pending.requestId);
      if (!applicableNow(checkpoint.pending, refreshed)) {
        setRetryReady(false); setCheckpointNotice('Current evidence does not allow a retry. Keep checking the original operation.'); return;
      }
      setDetail(refreshed); setInspection(null); setReview(checkpoint.pending); setRetryReady(false);
    });
  };
  const prepareReview = (kind: 'claim' | 'outcome') => {
    if (!allowActions || busy || checkpoint || journalGeneration === null || !context || !detail?.item || !user.principalId ||
        !proofValid() || !hasNotExpired(context.validUntil) || !evidenceIsCurrent(detail.checkedAt)) return;
    const item = detail.item, id = globalThis.crypto?.randomUUID?.();
    if (!id || !uuidPattern.test(id)) {setError('A secure review reference is unavailable.'); return;}
    if (kind === 'claim' && (!['not_started', 'awaiting_review', 'claim_expired'].includes(item.state) || item.revision >= 999_999_999)) return;
    if (kind === 'outcome' && (!detail.ownClaim || !detail.claim || !hasNotExpired(detail.claim.expiresAt))) return;
    const parameters = kind === 'claim' ? {p_request_id: item.requestId, p_claim_request_id: id, p_expected_revision: item.revision, p_lease_seconds: 60} :
      {p_outcome_request_id: id, p_claim_id: detail.claim!.claimId, p_fence: detail.claim!.fence, p_outcome_code: 'policy_authority_unavailable'};
    const intent = {kind, operationId: id, requestId: item.requestId, actorId: user.principalId, sessionId: user.sessionId, parameters};
    if (applicableNow(intent, detail)) setReview(intent);
  };
  const confirmReview = () => {
    if (!allowActions || !review || !context || journalGeneration === null || !detail?.item || detail.item.requestId !== review.requestId) return;
    const original = review, retainedCheckpoint = checkpoint;
    if (retainedCheckpoint && retainedCheckpoint.pending.operationId !== original.operationId) return;
    void run(async (sequence, signal) => {
      const valid = () => current(sequence, context.validUntil) && actionGate.current;
      if (!valid() || !applicableNow(original, detail)) throw new Error('Review evidence expired.');
      const journal = {actorId: original.actorId, sessionId: original.sessionId, current: valid};
      let next: number;
      if (retainedCheckpoint) {
        if (localStorage.getItem(retainedCheckpoint.key) !== retainedCheckpoint.raw) throw new Error('The saved request changed.');
        const lookup = await request('privacy/admin_get_account_deletion_review_operation_v1', {body: {p_operation_kind: original.kind, p_operation_id: original.operationId}, signal});
        await waitForEvidenceClock(lookup, signal);
        if (!valid() || localStorage.getItem(retainedCheckpoint.key) !== retainedCheckpoint.raw) throw new Error('The saved request changed.');
        if (parsePrivacyOperation(lookup, original)) {
          const completed = await completePrivacyIntent(journal, original, retainedCheckpoint.generation, lookup.receipt);
          if (!valid()) throw new Error('Review access expired.');
          setCheckpoint(null); setJournalGeneration(completed); setReview(null); setDetail(null); setPage(null);
          setCheckpointNotice('The original operation was recorded. No data was erased. Refresh reviews for current evidence.'); return;
        }
        const raw = await request('privacy/admin_get_account_deletion_review_v1', {body: {p_request_id: original.requestId}, signal});
        await waitForEvidenceClock(raw, signal);
        if (!valid() || localStorage.getItem(retainedCheckpoint.key) !== retainedCheckpoint.raw || !applicableNow(original, parsePrivacyDetail(raw, original.requestId))) throw new Error('Current evidence does not allow a retry.');
        next = retainedCheckpoint.generation;
      } else {
        next = await reservePrivacyIntent(journal, original, journalGeneration);
        const key = privacyJournalKey(original.actorId, original.sessionId), retained = localStorage.getItem(key);
        if (!retained || !valid()) throw new Error('The original reference could not be retained.');
        setCheckpoint({key, raw: retained, pending: original, generation: next}); setJournalGeneration(next);
      }
      setReview(null);
      const operation = original.kind === 'claim' ? 'admin_claim_account_deletion_review_v1' : 'admin_record_account_deletion_review_v1';
      const receipt = await request(`privacy/${operation}`, {body: original.parameters, signal});
      if (!valid()) throw new Error('Review access expired.');
      const completed = await completePrivacyIntent(journal, original, next, receipt);
      if (!valid()) throw new Error('Review access expired.');
      setCheckpoint(null); setJournalGeneration(completed); setDetail(null); setPage(null); setInspection(null); setRetryReady(false);
      setCheckpointNotice(original.kind === 'claim' ? 'Review start recorded. Refresh to check current claim authority.' : 'Policy blocker recorded. No data was erased.');
    });
  };

  return <><PageHeader title="Privacy requests" subtitle="Review account-deletion requests." />
    {!access ? <ErrorState title="Access unavailable" message="Your account cannot open privacy reviews." /> : <>
      <Card className="privacy-panel"><StatusBadge tone="warning">Waiting for approved policy</StatusBadge>
        <p>Deletion is paused until a retention and erasure policy is approved. Reviews do not delete accounts or data.</p>
        {!allowActions && <p>Review actions are unavailable in this workspace. Existing requests remain unchanged.</p>}
        {proofState?.scope !== proofScope || !proofState.valid ? <Button onClick={onVerify}>Verify account</Button> : <Button disabled={busy} onClick={open}>{page ? 'Refresh reviews' : 'Open privacy reviews'}</Button>}
      </Card>
      {error && <ErrorState message={error} />}
      {busy && <LoadingState label="Checking privacy review evidence" />}
      {context && proofState?.scope === proofScope && proofState.valid && (checkpoint || checkpointNotice) && <Card className="privacy-panel">
        <h2>Original operation</h2>{checkpoint && <><p>Operation reference: <code>{checkpoint.pending.operationId}</code></p>
          <p>Check the original operation before making another review. A missing observation does not prove it failed.</p>
          <div className="privacy-actions"><Button disabled={busy} onClick={checkOriginal}>Check original operation</Button>
            {allowActions && retryReady && <Button disabled={busy} onClick={reviewOriginal}>Review same operation</Button>}</div></>}
        {checkpointNotice && <p role="status">{checkpointNotice}</p>}
      </Card>}
      {page && context && proofState?.scope === proofScope && proofState.valid && <Card className="privacy-panel"><h2>Requests · page {history.length}</h2>
        {page.items.length === 0 ? <EmptyState title="No privacy requests on this page" description="Refresh to check again." /> :
          <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th scope="col">Request identifier</th><th scope="col">State</th><th scope="col">Accepted</th><th scope="col">Open</th></tr></thead>
            <tbody>{page.items.map(entry => <tr key={entry.requestId}><td><code>{entry.requestId}</code></td><td><StatusBadge tone="warning">{labels[entry.state]}</StatusBadge></td><td>{formatDate(entry.acceptedAt)}</td><td><Button disabled={busy} onClick={() => openDetail(entry.requestId)}>Open request</Button></td></tr>)}</tbody></table></div>}
        <div className="privacy-actions"><Button disabled={busy || history.length < 2} onClick={() => {const trail = history.slice(0, -1); pageTo(trail.at(-1) ?? null, trail);}}>Previous requests</Button>
          <Button disabled={busy || !page.next} onClick={() => {if (page.next) pageTo(page.next, [...history, page.next]);}}>Next requests</Button></div>
      </Card>}
      {detail && context && proofState?.scope === proofScope && proofState.valid && <Card className="privacy-panel"><h2>Request details</h2>{detail.item ? <dl className="privacy-details">
        <div><dt>Request identifier</dt><dd>{detail.item.requestId}</dd></div><div><dt>State</dt><dd>{labels[detail.item.state]}</dd></div>
        <div><dt>Accepted</dt><dd>{formatDate(detail.item.acceptedAt)}</dd></div><div><dt>Observed revision</dt><dd>{detail.item.revision}</dd></div>
        <div><dt>Evidence checked</dt><dd>{formatDate(detail.checkedAt)}</dd></div>
        {detail.item.claimExpiresAt !== null && <div><dt>Review claim expires</dt><dd>{formatDate(detail.item.claimExpiresAt)}</dd></div>}
        {detail.item.outcomeRecordedAt !== null && <div><dt>Policy blocker recorded</dt><dd>{formatDate(detail.item.outcomeRecordedAt)}</dd></div>}
      </dl> : <p>This request is no longer available.</p>}
      {detail.ownClaim && <p>The current session owns this review claim.</p>}
      {allowActions && detail.item && !checkpoint && journalGeneration !== null && <div className="privacy-actions">
        <Button disabled={busy || !['not_started', 'awaiting_review', 'claim_expired'].includes(detail.item.state)} onClick={() => prepareReview('claim')}>Start review</Button>
        <Button disabled={busy || !detail.ownClaim} onClick={() => prepareReview('outcome')}>Record policy blocker</Button>
      </div>}
      {allowActions && review && <section><h3>Confirm review action</h3><p>{review.kind === 'claim' ? 'Start a review of this request.' : 'Record that the approved policy is unavailable.'} No account or data will be deleted.</p>
        <div className="privacy-actions"><Button disabled={busy} onClick={() => {setReview(null); if (checkpoint) setRetryReady(true);}}>Cancel</Button><Button variant="primary" disabled={busy} onClick={confirmReview}>{checkpoint ? 'Confirm same operation' : 'Confirm review action'}</Button></div></section>}
      {detail.item && <section><h3>Retained information</h3><p>Inspect retained information, legal holds and unresolved work. Retained records are not automatically eligible for erasure.</p>
        <Button disabled={busy} onClick={inspect}>Inspect retained scope</Button>
        {inspection && <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th scope="col">Field</th><th scope="col">Value</th></tr></thead><tbody>
          <tr><td>Stored objects</td><td>{inspection.objectCount}</td></tr><tr><td>Active legal holds</td><td>{inspection.activeHoldCount}</td></tr>
          <tr><td>Unresolved work</td><td>{inspection.inFlightUnresolved ? 'Present' : 'None observed'}</td></tr>
          {Object.entries(inspection.tableCounts).map(([name, value]) => <tr key={name}><td>{name}</td><td>{value}</td></tr>)}
          <tr><td>Source fingerprint</td><td><code>{inspection.sourceId}</code></td></tr><tr><td>Schema fingerprint</td><td><code>{inspection.schemaSha256}</code></td></tr>
          <tr><td>Scope fingerprint</td><td><code>{inspection.snapshotSha256}</code></td></tr>
        </tbody></table></div>}
      </section>}</Card>}
    </>}
  </>;
}
