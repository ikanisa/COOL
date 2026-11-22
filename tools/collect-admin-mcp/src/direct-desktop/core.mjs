import { randomUUID } from 'node:crypto';
import {
  DEFAULT_POLICY, digest, EMPTY_SCHEMA, EXCEPTIONS_SCHEMA, fail, operationKey,
  policySnapshot, PREPARE_SCHEMA, receiptBody, STOP_SCHEMA, validate,
} from './contract.mjs';
import { pendingWriteback, writeAdminOutcome } from './admin-writeback.mjs';
import { attemptView, blocked, control, immutable, outcomeRevision, timestamp, unavailable, unresolvedAttempt } from './execution-state.mjs';
import { assertEligible } from './native-evidence.mjs';
import { dispatchPreparedNotification, reconcileAttempt } from './notification-operations.mjs';

export const UNAVAILABLE_ADAPTER = Object.freeze({ kind: 'unconfigured' });

export class DirectDesktopCore {
  constructor({ journal, policy = DEFAULT_POLICY, policyProvider, adapter = UNAVAILABLE_ADAPTER, quiescenceVerifier, now = Date.now }) {
    this.journal = journal;
    this.policyProvider = policyProvider ?? (() => structuredClone(policy));
    this.adapter = adapter;
    this.now = now;
    this.active = new Set();
    this.localStopReason = null;
    this.quiescenceVerifier = quiescenceVerifier;
    this.currentPolicy();
  }
  currentPolicy() { return immutable(policySnapshot(this.policyProvider())); }
  event(tx, type, payload) { tx.append({ id: randomUUID(), type, at: timestamp(this.now()), payload }); }
  transaction(action) {
    return this.journal.transaction(tx => {
      const state = control(tx);
      if (this.localStopReason !== null && !state.stopped) {
        tx.put('control', 'state', { ...state, stopped: true, reason: this.localStopReason });
        this.event(tx, 'latched_stop_persisted', { reason: this.localStopReason });
      }
      return action(tx);
    });
  }
  health(args = {}) {
    validate(EMPTY_SCHEMA, args);
    const { policy, hash } = this.currentPolicy();
    return this.transaction(tx => {
      const state = control(tx);
      const attempts = tx.all('attempts');
      const synced = attempts.length ? tx.all('syncs').filter(sync => sync.state === 'SYNCED') : [];
      const syncedRevisions = new Set(synced.map(sync => sync.outcome_revision));
      return {
        status: state.stopped ? 'stopped' : policy.mode === 'dry_run' ? 'ready_dry_run' : this.adapter.kind === 'mock' ? 'ready_mock' : 'native_unverified', mode: policy.mode, policy_revision: policy.policy_revision, policy_hash: hash,
        live_dispatch_enabled: policy.live_dispatch_enabled && this.adapter.kind !== 'unconfigured',
        native_adapter: this.adapter.kind, evidence_label: this.adapter.kind === 'mock' ? 'experimental' : 'unverified',
        journal_durable: this.journal.durable, stop: { stopped: state.stopped, reason: state.reason }, lease: state.lease,
        attempts: attempts.length, unresolved_attempts: attempts.filter(unresolvedAttempt).length,
        admin_sync_pending: attempts.filter(item => !syncedRevisions.has(outcomeRevision(item))).length,
        voice: { dialing: 'unavailable', assisted_conversation: 'unavailable', unattended_lifecycle: 'unavailable' },
      };
    });
  }
  observeAdminQueue(args = {}) {
    validate(EMPTY_SCHEMA, args);
    // Supplied snapshots are not relabelled as a native browser observation.
    return unavailable();
  }

  prepareNotification(input) {
    const supplied = validate(PREPARE_SCHEMA, input), snapshot = this.currentPolicy();
    if (supplied.message.body !== receiptBody(supplied.source)) fail('message_source_mismatch');
    const key = operationKey(supplied.source), fingerprint = digest({ ...supplied, policy_hash: snapshot.hash });
    const ticket = { id: `ticket_${fingerprint}`, operation_key: key, policy_hash: snapshot.hash, policy_revision: snapshot.policy.policy_revision,
      created_at: timestamp(this.now()), fingerprint, ...supplied };
    assertEligible(this, ticket, snapshot);
    return this.transaction(tx => {
      if (control(tx).stopped || this.localStopReason !== null) return blocked('operator_stopped');
      const current = tx.get('jobs', key);
      const attempt = tx.get('attempts', key);
      if (attempt) {
        const prior = tx.get('tickets', attempt.ticket_id);
        if (prior?.fingerprint !== fingerprint) fail('operation_already_attempted');
        return { status: 'already_attempted', ticket: prior, attempt: attemptView(attempt) };
      }
      if (current?.ticket_id === ticket.id) return { status: 'prepared', ticket: tx.get('tickets', ticket.id), replay: true, evidence_label: 'unverified' };
      tx.put('policies', snapshot.hash, { hash: snapshot.hash, policy: snapshot.policy });
      tx.put('tickets', ticket.id, ticket);
      tx.put('jobs', key, { operation_key: key, ticket_id: ticket.id });
      this.event(tx, 'notification_prepared', { ticket_id: ticket.id, replaces_ticket_id: current?.ticket_id ?? null });
      return { status: 'prepared', ticket, replay: false, evidence_label: 'unverified' };
    });
  }

  dispatchPreparedNotification(input, signal) {
    return dispatchPreparedNotification(this, input, signal);
  }

  reconcileAttempt(input) {
    return reconcileAttempt(this, input);
  }

  writeAdminOutcome(input, signal) {
    return writeAdminOutcome(this, input, signal);
  }

  getPendingExceptions(input = {}) {
    const { limit = 50 } = validate(EXCEPTIONS_SCHEMA, input);
    return this.transaction(tx => {
      const attempts = tx.all('attempts').filter(unresolvedAttempt).map(value => ({ kind: 'dispatch', ...attemptView(value) }));
      const syncs = tx.all('syncs').filter(pendingWriteback).map(value => ({ kind: 'admin_sync', ...value }));
      const jobs = tx.all('jobs').filter(value => value.blocked_reason_code).map(value => ({ kind: 'blocked_job', ...value }));
      const state = control(tx), rows = [...attempts, ...syncs, ...jobs];
      if (state.lease && state.lease.expires_at <= this.now()) rows.push({ kind: 'lease', reason_code: 'lease_recovery_required', lease: state.lease });
      return { status: 'recorded', rows: rows.slice(0, limit), total: rows.length, truncated: rows.length > limit };
    });
  }
  stopAll(input) {
    const { reason } = validate(STOP_SCHEMA, input);
    this.localStopReason = reason;
    return this.transaction(tx => {
      const state = control(tx); tx.put('control', 'state', { ...state, stopped: true, reason });
      this.event(tx, 'stop_all', { reason });
      return { status: 'stopped', new_dispatch_inhibited: true, active_lease: state.lease,
        scope: 'local_runtime_only', call_termination: 'no_owned_call', audio_gate: 'not_configured',
        delegated_tasks_and_schedules: 'not_verified', requires_human_action: Boolean(state.lease) };
    });
  }
  prepareCall(args = {}) { validate(EMPTY_SCHEMA, args); return { status: 'unavailable', reason_code: 'native_call_workflow_unverified' }; }
  startPreparedCall(args = {}) { return this.prepareCall(args); }
  inspectCallState(args = {}) { return this.prepareCall(args); }
  endCurrentCall(args = {}) { return this.prepareCall(args); }
  close() { if (this.active.size) fail('executor_busy'); this.journal.close(); }
}
