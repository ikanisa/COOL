import { randomUUID } from 'node:crypto';
import { DesktopError, EXECUTE_SCHEMA, fail, RECONCILE_SCHEMA, validate } from './contract.mjs';
import { actionPermit, attemptView, blocked, cleanFailure, immutable, timestamp, unavailable, unresolvedAttempt } from './execution-state.mjs';
import { acquireLease, assertLease, recoverLease, releaseLease } from './lease.mjs';
import { assertEligible, evidenceLabel, noSendObservation, outgoingObservation, verifyPreflight } from './native-evidence.mjs';
import { findAttempt, findTicket } from './receipt-records.mjs';

const storageFailure = error => ['journal_unavailable', 'journal_corrupt', 'unsafe_journal_path'].includes(error.code);

export async function dispatchPreparedNotification(runtime, input, signal) {
  const args = validate(EXECUTE_SCHEMA, input);
  let ticket, lease, attempt, permit;
  try {
    const initial = runtime.transaction(tx => {
      ticket = findTicket(tx, args.ticket_id);
      const prior = tx.get('attempts', ticket.operation_key);
      if (prior) return { status: 'already_attempted', attempt: attemptView(prior), external_action: 'not_repeated' };
      const snapshot = runtime.currentPolicy(); assertEligible(runtime, ticket, snapshot, true);
      if (signal?.aborted) fail('cancelled');
      lease = acquireLease(runtime, tx, args.executor_id, 'notification_dispatch', snapshot.policy.lease_seconds, ticket.operation_key);
      return null;
    });
    if (initial) return initial;
    runtime.active.add(lease.token);
    const preflight = await runtime.adapter.preflightNotification(ticket);
    const snapshot = runtime.currentPolicy(); assertEligible(runtime, ticket, snapshot, true); verifyPreflight(runtime, ticket, preflight, snapshot.policy);
    attempt = runtime.transaction(tx => {
      assertLease(runtime, tx, lease); findTicket(tx, ticket.id);
      assertEligible(runtime, ticket, runtime.currentPolicy(), true);
      if (signal?.aborted) fail('cancelled');
      if (tx.get('attempts', ticket.operation_key)) fail('operation_already_attempted');
      const preflightId = randomUUID();
      tx.put('observations', preflightId, { id: preflightId, ticket_id: ticket.id, status: 'preflight_verified',
        observed_at: preflight.observed_at, evidence_label: preflight.evidence_label, evidence_refs: preflight.evidence_refs });
      const armed = { id: randomUUID(), ticket_id: ticket.id, operation_key: ticket.operation_key, state: 'DISPATCH_ARMED', preflight_id: preflightId,
        fence: lease.fence, executor_id: lease.owner, armed_at: timestamp(runtime.now()), evidence_label: evidenceLabel(runtime.adapter.kind) };
      tx.put('attempts', ticket.operation_key, armed); runtime.event(tx, 'dispatch_armed', armed); return immutable(armed);
    });
    permit = actionPermit(witness => {
      const current = runtime.currentPolicy(); assertEligible(runtime, ticket, current, true); verifyPreflight(runtime, ticket, witness, current.policy);
      runtime.transaction(tx => {
        assertLease(runtime, tx, lease);
        if (signal?.aborted) fail('cancelled');
        const retained = tx.get('attempts', ticket.operation_key);
        if (retained?.id !== attempt.id || retained.state !== 'DISPATCH_ARMED') fail('attempt_not_armed');
        runtime.event(tx, 'dispatch_action_boundary', { attempt_id: attempt.id, fence: lease.fence, observed_at: witness.observed_at, evidence_refs: witness.evidence_refs });
      });
      return { attempt_id: attempt.id, fence: lease.fence };
    });
    let observation, reason, noSendEvidence;
    try {
      const result = await runtime.adapter.dispatchNotification(ticket, attempt, { beforeAction: permit.consume, signal });
      if (result?.status === 'outgoing_observed' && permit.used) observation = outgoingObservation(runtime, ticket, attempt, result);
      else if (!permit.used) noSendEvidence = noSendObservation(runtime, attempt, result);
      if (!observation && !noSendEvidence) reason = 'native_result_unverified';
    } catch (error) { reason = cleanFailure(error); }
    const state = observation ? 'OUTGOING_OBSERVED' : noSendEvidence && !reason ? 'FAILED_NO_SEND' : 'OUTCOME_UNKNOWN';
    return runtime.transaction(tx => {
      const retained = tx.get('attempts', ticket.operation_key);
      if (retained?.id !== attempt.id || retained.state !== 'DISPATCH_ARMED') fail('journal_corrupt');
      const outcome = { ...attempt, state, observed_at: timestamp(runtime.now()), reason_code: reason ?? noSendEvidence?.reason_code ?? null, observation_id: observation?.id ?? noSendEvidence?.id ?? null };
      if (observation) tx.put('observations', observation.id, observation);
      if (noSendEvidence) tx.put('observations', noSendEvidence.id, noSendEvidence);
      tx.put('attempts', ticket.operation_key, outcome); runtime.event(tx, 'dispatch_outcome', outcome);
      tx.put('jobs', ticket.operation_key, { operation_key: ticket.operation_key, ticket_id: ticket.id, state: 'consumed' });
      releaseLease(runtime, tx, lease);
      return { status: state.toLowerCase(), attempt: attemptView(outcome), external_action: state === 'FAILED_NO_SEND' ? 'not_started' : 'possible', evidence_label: attempt.evidence_label };
    });
  } catch (error) {
    if (attempt) {
      // An armed attempt survives a failed result commit. Never report it as unsent.
      if (!(error instanceof DesktopError) || storageFailure(error)) throw error;
      return runtime.transaction(tx => {
        const unknown = { ...attempt, state: 'OUTCOME_UNKNOWN', reason_code: cleanFailure(error), observed_at: timestamp(runtime.now()) };
        tx.put('attempts', ticket.operation_key, unknown); runtime.event(tx, 'dispatch_outcome', unknown);
        releaseLease(runtime, tx, lease);
        return { status: 'outcome_unknown', attempt: attemptView(unknown), external_action: 'possible' };
      });
    }
    if (error instanceof DesktopError) {
      if (ticket && !storageFailure(error)) runtime.transaction(tx => {
        const job = tx.get('jobs', ticket.operation_key);
        if (job?.ticket_id === ticket.id && !tx.get('attempts', ticket.operation_key) && job.blocked_reason_code !== error.code) {
          tx.put('jobs', ticket.operation_key, { ...job, blocked_reason_code: error.code });
          runtime.event(tx, 'dispatch_refused', { ticket_id: ticket.id, reason_code: error.code });
        }
      });
      return blocked(error.code);
    }
    return blocked('native_preflight_unavailable');
  } finally {
    permit?.close();
    if (lease) {
      runtime.active.delete(lease.token);
      if (!attempt) runtime.transaction(tx => releaseLease(runtime, tx, lease));
    }
  }
}

export async function reconcileAttempt(runtime, input) {
  const args = validate(RECONCILE_SCHEMA, input);
  const found = runtime.transaction(tx => findAttempt(tx, args.attempt_id));
  if (!unresolvedAttempt(found.attempt)) return { status: 'recorded', attempt: attemptView(found.attempt) };
  if (runtime.adapter.kind === 'unconfigured' || !runtime.adapter.inspectAttempt) return { ...unavailable(), attempt: attemptView(found.attempt) };
  let lease;
  try {
    const snapshot = runtime.currentPolicy();
    if (args.recovery) await recoverLease(runtime, args.recovery, found.ticket);
    lease = runtime.transaction(tx => acquireLease(runtime, tx, args.executor_id, 'reconciliation', snapshot.policy.lease_seconds, found.ticket.operation_key, true));
    runtime.active.add(lease.token);
    const result = await runtime.adapter.inspectAttempt(found.ticket, found.attempt);
    if (result?.status !== 'outgoing_observed') return { status: 'outcome_unknown', attempt: attemptView(found.attempt) };
    const observation = outgoingObservation(runtime, found.ticket, found.attempt, result);
    return runtime.transaction(tx => {
      assertLease(runtime, tx, lease, true);
      const current = findAttempt(tx, args.attempt_id).attempt;
      const outcome = { ...current, state: 'OUTGOING_OBSERVED', observed_at: observation.observed_at, observation_id: observation.id, reason_code: null };
      tx.put('observations', observation.id, observation); tx.put('attempts', current.operation_key, outcome);
      runtime.event(tx, 'attempt_reconciled', { attempt_id: outcome.id, observation_id: observation.id });
      return { status: 'outgoing_observed', attempt: attemptView(outcome), evidence_label: observation.evidence_label };
    });
  } catch (error) {
    if (error instanceof DesktopError) return { ...blocked(error.code), attempt: attemptView(found.attempt) };
    return { status: 'outcome_unknown', attempt: attemptView(found.attempt) };
  } finally { if (lease) { runtime.active.delete(lease.token); runtime.transaction(tx => releaseLease(runtime, tx, lease)); } }
}
