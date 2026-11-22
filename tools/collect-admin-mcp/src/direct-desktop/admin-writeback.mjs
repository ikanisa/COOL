import { randomUUID } from 'node:crypto';
import { ATTEMPT_SCHEMA, canonical, DesktopError, fail, sourceFacts, validate } from './contract.mjs';
import { actionPermit, attemptView, blocked, cleanFailure, outcomeRevision, timestamp, unavailable } from './execution-state.mjs';
import { acquireLease, assertLease, releaseLease } from './lease.mjs';
import { evidenceLabel, validEvidenceRefs } from './native-evidence.mjs';
import { findAttempt } from './receipt-records.mjs';

export function pendingWriteback(sync) {
  return sync.state === 'WRITE_ARMED' || sync.state === 'SYNC_UNKNOWN';
}

export async function writeAdminOutcome(runtime, input, signal) {
  const args = validate(ATTEMPT_SCHEMA, input);
  let lease, sync, permit;
  try {
    const { attempt, ticket } = runtime.transaction(tx => findAttempt(tx, args.attempt_id));
    const snapshot = runtime.currentPolicy();
    const { policy } = snapshot;
    const { admin_browser: browser, test_gate: testGate } = policy;
    const { adapter } = runtime;
    if (policy.mode === 'dry_run' || !policy.live_dispatch_enabled) return blocked('live_dispatch_disabled');
    if (adapter.kind === 'unconfigured' || adapter.kind !== policy.native_adapter ||
        !adapter.inspectAdminOutcome || !adapter.writeAdminOutcome) return unavailable();
    const testGateExpiresAt = Date.parse(testGate.expires_at);
    if (snapshot.hash !== ticket.policy_hash || !testGate.enabled ||
        !testGate.owner_designated_recipient_keys.includes(ticket.recipient.recipient_key) ||
        testGateExpiresAt <= runtime.now()) return blocked('owner_test_gate_required');
    if (!runtime.journal.durable) return blocked('durable_journal_required');
    if (!browser) return blocked('admin_browser_unverified');
    const revision = outcomeRevision(attempt);
    const outcome = attemptView(attempt).state;
    const setup = runtime.transaction(tx => {
      const previous = tx.all('syncs').filter(value => value.outcome_revision === revision);
      const done = previous.find(value => value.state === 'SYNCED');
      if (done) return done;
      lease = acquireLease(runtime, tx, args.executor_id, 'admin_outcome_writeback', policy.lease_seconds, ticket.operation_key);
      return { uncertain: previous.find(pendingWriteback) ?? null };
    });
    if (setup.state === 'SYNCED') return { status: 'synced', sync: setup, replay: true };
    runtime.active.add(lease.token);
    const expectedSource = canonical(sourceFacts(ticket.source));
    const sourceMatches = value => {
      if (!value || value.browser_origin !== browser.origin || value.account_key !== browser.account_key) return false;
      const observedAt = Date.parse(value.observed_at);
      return canonical(value.source_facts) === expectedSource && Number.isFinite(observedAt) &&
        Math.abs(runtime.now() - observedAt) <= 5000 && value.evidence_label === evidenceLabel(adapter.kind) &&
        validEvidenceRefs(value.evidence_refs);
    };
    const sameAttempt = value => sourceMatches(value) && value.status === 'matched' &&
      value.attempt_id === attempt.id && value.ticket_id === ticket.id &&
      value.operation_key === ticket.operation_key && value.delivery_state === 'unverified';
    const matches = value => sameAttempt(value) && value.outcome === outcome;
    const priorSynced = value => sameAttempt(value) && runtime.transaction(tx => tx.all('syncs').some(prior =>
      prior.state === 'SYNCED' && prior.attempt_id === attempt.id && prior.ticket_id === ticket.id && prior.outcome === value.outcome && prior.outcome_revision !== revision));
    let existing = await adapter.inspectAdminOutcome(ticket, attemptView(attempt));
    if (setup.uncertain && !matches(existing)) fail('admin_sync_reconciliation_required');
    if (!(existing?.status === 'absent' && sourceMatches(existing)) && !matches(existing) && !priorSynced(existing)) fail('admin_source_mismatch');
    sync = runtime.transaction(tx => {
      assertLease(runtime, tx, lease);
      if (runtime.currentPolicy().hash !== snapshot.hash || signal?.aborted) fail('policy_changed');
      const value = {
        id: setup.uncertain?.id ?? randomUUID(), ticket_id: ticket.id, attempt_id: attempt.id,
        outcome_revision: revision, state: matches(existing) ? 'SYNCED' : 'WRITE_ARMED',
        outcome, at: timestamp(runtime.now()), evidence_label: evidenceLabel(adapter.kind),
      };
      tx.put('syncs', value.id, value);
      runtime.event(tx, 'admin_sync_armed', value);
      return value;
    });
    if (!matches(existing)) {
      permit = actionPermit(witness => {
        if (!(sourceMatches(witness) && (witness.status === 'absent' || matches(witness) || priorSynced(witness)))) fail('admin_source_mismatch');
        runtime.transaction(tx => {
          assertLease(runtime, tx, lease);
          if (runtime.currentPolicy().hash !== snapshot.hash || testGateExpiresAt <= runtime.now() || signal?.aborted) fail('policy_changed');
          runtime.event(tx, 'admin_sync_action_boundary', { sync_id: sync.id, fence: lease.fence });
        });
      });
      await adapter.writeAdminOutcome(ticket, attemptView(attempt), { signal, beforeAction: permit.consume });
      if (!permit.used) fail('admin_write_unverified');
      existing = await adapter.inspectAdminOutcome(ticket, attemptView(attempt));
    }
    if (!matches(existing)) fail('admin_write_unverified');
    return runtime.transaction(tx => {
      const completed = { ...sync, state: 'SYNCED', evidence_refs: existing.evidence_refs, observed_at: timestamp(runtime.now()) };
      tx.put('syncs', sync.id, completed); runtime.event(tx, 'admin_sync_observed', { sync_id: sync.id });
      return { status: 'synced', sync: completed };
    });
  } catch (error) {
    if (sync?.state === 'WRITE_ARMED') return runtime.transaction(tx => {
      const unknown = { ...sync, state: 'SYNC_UNKNOWN', reason_code: cleanFailure(error) };
      tx.put('syncs', sync.id, unknown); runtime.event(tx, 'admin_sync_unknown', { sync_id: sync.id });
      return { status: 'sync_unknown', reason_code: cleanFailure(error), external_action: 'possible', sync: unknown };
    });
    if (error instanceof DesktopError) return blocked(error.code);
    return blocked('admin_write_unverified');
  } finally {
    permit?.close();
    if (lease) {
      runtime.active.delete(lease.token);
      runtime.transaction(tx => releaseLease(runtime, tx, lease));
    }
  }
}
