import {useEffect, useLayoutEffect, useRef, useState} from 'react';
import type {AdminRequest} from '../../api/client';
import {sensitiveVerificationDeadline, type AdminUser} from '../../session/SessionProvider';
import {Button, Card, ErrorState, LoadingState, PageHeader, StatusBadge} from '../../ui';
import {
  canStartPrivacyClaim, privacyIntentApplies,
  type PrivacyCursor, type PrivacyDetail, type PrivacyPageData, type PrivacyPending, type RetentionContext, type RetentionInspection,
} from './contracts';
import {privacyEvidenceIsCurrent, readPrivacyDetail, readPrivacyPage, readRetentionContext, readRetentionInspection} from './evidence';
import {completePrivacyIntent, loadPrivacyJournal, type PrivacyCheckpoint} from './journal';
import {PrivacyReviewDetail, PrivacyReviewQueue} from './PrivacyReviewPanels';
import {checkOriginalReview, confirmPrivacyReview, readOriginalReview} from './reviewWorkflow';
import './privacy.css';

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const proofIsCurrent = (proofAt: number, proofUntil: number) => Number.isFinite(proofAt) && proofAt <= Date.now() && proofUntil > Date.now();
const hasNotExpired = (until: number) => until > Date.now();
const applicableNow = (intent: PrivacyPending, detail: PrivacyDetail) => privacyIntentApplies(intent, detail, Date.now());
const alreadyRecorded = 'The original operation was recorded. No data was erased. Refresh reviews for current evidence.';

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
  const [checkpoint, setCheckpoint] = useState<PrivacyCheckpoint | null>(null);
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
  const evidenceAccess = (sequence: number, signal: AbortSignal, until = proofUntil) => ({
    request, signal, current: () => current(sequence, until),
  });

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
  const open = () => void run(async (sequence, signal) => {
    const bound = await readRetentionContext(evidenceAccess(sequence, signal));
    const access = evidenceAccess(sequence, signal, bound.validUntil);
    const data = await readPrivacyPage(access, null);
    if (!access.current()) throw new Error('Review access expired.');
    setContext(bound); setPage(data); setDetail(null); setInspection(null); setHistory([null]);
    try {
      const saved = loadPrivacyJournal({actorId: user.principalId!, sessionId: user.sessionId, current: access.current});
      setJournalGeneration(saved.generation); setReview(null); setRetryReady(false);
      setCheckpoint(saved.checkpoint); setCheckpointNotice('');
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
      const data = await readPrivacyPage(evidenceAccess(sequence, signal, context.validUntil), target);
      if (current(sequence, context.validUntil)) {setPage(data); setDetail(null); setInspection(null); setHistory(trail);}
    });
  };
  const openDetail = (id: string) => {
    if (!context) return;
    void run(async (sequence, signal) => {
      const observed = await readPrivacyDetail(evidenceAccess(sequence, signal, context.validUntil), id);
      if (!current(sequence, context.validUntil)) throw new Error('Review access expired.');
      setDetail(observed); setInspection(null);
    });
  };
  const inspect = () => {
    if (!context || !detail?.item || !user.principalId) return;
    const {requestId, revision} = detail.item;
    const actorId = user.principalId;
    void run(async (sequence, signal) => {
      if (!privacyEvidenceIsCurrent(detail.checkedAt)) throw new Error('Review evidence expired.');
      const observed = await readRetentionInspection(evidenceAccess(sequence, signal, context.validUntil), context, actorId, requestId, revision);
      if (!current(sequence, context.validUntil)) throw new Error('Review access expired.');
      setInspection(observed);
    });
  };
  const checkOriginal = () => {
    if (!context || !checkpoint) return;
    void run(async (sequence, signal) => {
      const access = evidenceAccess(sequence, signal, context.validUntil);
      const {observed, receipt} = await checkOriginalReview(access, checkpoint);
      if (!access.current()) throw new Error('Review access expired.');
      if (observed && actionGate.current) {
        const next = await completePrivacyIntent({actorId: checkpoint.pending.actorId, sessionId: user.sessionId,
          current: () => access.current() && actionGate.current}, checkpoint.pending, checkpoint.generation, receipt);
        if (!access.current()) throw new Error('Review access expired.');
        setCheckpoint(null); setJournalGeneration(next); setDetail(null); setPage(null); setRetryReady(false);
        setCheckpointNotice(alreadyRecorded);
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
      const access = evidenceAccess(sequence, signal, context.validUntil);
      const refreshed = await readOriginalReview(access, checkpoint);
      if (!access.current() || !actionGate.current) throw new Error('Review access expired.');
      if (!applicableNow(checkpoint.pending, refreshed)) {
        setRetryReady(false); setCheckpointNotice('Current evidence does not allow a retry. Keep checking the original operation.'); return;
      }
      setDetail(refreshed); setInspection(null); setReview(checkpoint.pending); setRetryReady(false);
    });
  };
  const prepareReview = (kind: 'claim' | 'outcome') => {
    if (!allowActions || busy || checkpoint || journalGeneration === null || !context || !detail?.item || !user.principalId ||
        !proofValid() || !hasNotExpired(context.validUntil) || !privacyEvidenceIsCurrent(detail.checkedAt)) return;
    const item = detail.item, id = globalThis.crypto?.randomUUID?.();
    if (!id || !uuidPattern.test(id)) {setError('A secure review reference is unavailable.'); return;}
    if (kind === 'claim' && !canStartPrivacyClaim(item)) return;
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
      const access = {request, signal, current: () => current(sequence, context.validUntil) && actionGate.current};
      const result = await confirmPrivacyReview(access, detail, original, journalGeneration, retainedCheckpoint, saved => {
        setCheckpoint(saved); setJournalGeneration(saved.generation); setReview(null);
      });
      if (!access.current()) throw new Error('Review access expired.');
      setCheckpoint(null); setJournalGeneration(result.generation); setReview(null); setDetail(null); setPage(null); setInspection(null); setRetryReady(false);
      setCheckpointNotice(result.previouslyRecorded ? alreadyRecorded : original.kind === 'claim' ?
        'Review start recorded. Refresh to check current claim authority.' : 'Policy blocker recorded. No data was erased.');
    });
  };

  const proofReady = proofState?.scope === proofScope && proofState.valid;
  return <><PageHeader title="Privacy requests" subtitle="Review account-deletion requests." />
    {!access ? <ErrorState title="Access unavailable" message="Your account cannot open privacy reviews." /> : <>
      <Card className="privacy-panel"><StatusBadge tone="warning">Waiting for approved policy</StatusBadge>
        <p>Deletion is paused until a retention and erasure policy is approved. Reviews do not delete accounts or data.</p>
        {!allowActions && <p>Review actions are unavailable in this workspace. Existing requests remain unchanged.</p>}
        {!proofReady ? <Button onClick={onVerify}>Verify account</Button> : <Button disabled={busy} onClick={open}>{page ? 'Refresh reviews' : 'Open privacy reviews'}</Button>}
      </Card>
      {error && <ErrorState message={error} />}
      {busy && <LoadingState label="Checking privacy review evidence" />}
      {context && proofReady && (checkpoint || checkpointNotice) && <Card className="privacy-panel">
        <h2>Original operation</h2>{checkpoint && <><p>Operation reference: <code>{checkpoint.pending.operationId}</code></p>
          <p>Check the original operation before making another review. A missing observation does not prove it failed.</p>
          <div className="privacy-actions"><Button disabled={busy} onClick={checkOriginal}>Check original operation</Button>
            {allowActions && retryReady && <Button disabled={busy} onClick={reviewOriginal}>Review same operation</Button>}</div></>}
        {checkpointNotice && <p role="status">{checkpointNotice}</p>}
      </Card>}
      {page && context && proofReady && <PrivacyReviewQueue page={page} number={history.length} busy={busy} onOpen={openDetail}
        onPrevious={() => { const trail = history.slice(0, -1); pageTo(trail.at(-1) ?? null, trail); }}
        onNext={() => { if (page.next) pageTo(page.next, [...history, page.next]); }} />}
      {detail && context && proofReady && <PrivacyReviewDetail detail={detail} inspection={inspection} busy={busy} onInspect={inspect}
        onPrepare={allowActions && !checkpoint && journalGeneration !== null ? prepareReview : undefined}>
        {allowActions && review && <section>
          <h3>Confirm review action</h3>
          <p>{review.kind === 'claim' ? 'Start a review of this request.' : 'Record that the approved policy is unavailable.'} No account or data will be deleted.</p>
          <div className="privacy-actions">
            <Button disabled={busy} onClick={() => { setReview(null); if (checkpoint) setRetryReady(true); }}>Cancel</Button>
            <Button variant="primary" disabled={busy} onClick={confirmReview}>{checkpoint ? 'Confirm same operation' : 'Confirm review action'}</Button>
          </div>
        </section>}
      </PrivacyReviewDetail>}
    </>}
  </>;
}
