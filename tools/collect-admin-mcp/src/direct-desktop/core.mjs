import { randomUUID } from 'node:crypto';
import {
  DesktopError, fail, validate, canonical, digest, operationKey, receiptBody, sourceFacts,
  DEFAULT_POLICY, policySnapshot, PREPARE_SCHEMA, EMPTY_SCHEMA, EXECUTE_SCHEMA, ATTEMPT_SCHEMA,
  STOP_SCHEMA, EXCEPTIONS_SCHEMA, RECONCILE_SCHEMA,
} from './contract.mjs';

const APP_IDS = { messages_native: 'com.apple.MobileSMS', whatsapp_native: 'net.whatsapp.WhatsApp' };
const unavailable = () => ({ status: 'unavailable', reason_code: 'native_adapter_unavailable' });
export const UNAVAILABLE_ADAPTER = Object.freeze({ kind: 'unconfigured' });
const control = tx => tx.get('control', 'state') ?? { stopped: false, reason: null, fence: 0, lease: null };
const timestamp = time => new Date(time).toISOString();
const blocked = reason_code => ({ status: 'blocked', reason_code, external_action: 'not_started' });
const cleanFailure = error => error instanceof DesktopError ? error.code : 'native_operation_unverified';
const outcomeRevision = attempt => digest([attempt.id, attempt.state === 'DISPATCH_ARMED' ? 'OUTCOME_UNKNOWN' : attempt.state, attempt.observation_id ?? null]);
const immutable = value => {
  if (value && typeof value === 'object') { for (const item of Object.values(value)) immutable(item); Object.freeze(value); }
  return value;
};

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
      const state = control(tx), attempts = tx.all('attempts');
      return {
        status: state.stopped ? 'stopped' : policy.mode === 'dry_run' ? 'ready_dry_run' : this.adapter.kind === 'mock' ? 'ready_mock' : 'native_unverified', mode: policy.mode, policy_revision: policy.policy_revision, policy_hash: hash,
        live_dispatch_enabled: policy.live_dispatch_enabled && this.adapter.kind !== 'unconfigured',
        native_adapter: this.adapter.kind, evidence_label: this.adapter.kind === 'mock' ? 'experimental' : 'unverified',
        journal_durable: this.journal.durable, stop: { stopped: state.stopped, reason: state.reason }, lease: state.lease,
        attempts: attempts.length, unresolved_attempts: attempts.filter(item => ['DISPATCH_ARMED', 'OUTCOME_UNKNOWN'].includes(item.state)).length,
        admin_sync_pending: attempts.filter(item => !tx.all('syncs').some(sync => sync.outcome_revision === outcomeRevision(item) && sync.state === 'SYNCED')).length,
        voice: { dialing: 'unavailable', assisted_conversation: 'unavailable', unattended_lifecycle: 'unavailable' },
      };
    });
  }
  observeAdminQueue(args = {}) {
    validate(EMPTY_SCHEMA, args);
    // Supplied snapshots are not relabelled as a native browser observation.
    return unavailable();
  }
  assertFresh(source, policy) {
    const age = this.now() - Date.parse(source.observed_at);
    if (age < -5000 || age > policy.max_source_age_seconds * 1000) fail('source_snapshot_stale');
  }
  assertEligible(ticket, snapshot, requireLive = false) {
    const { policy, hash } = snapshot;
    if (ticket.policy_hash !== hash) fail('policy_changed');
    if (!policy.approved_channels.includes(ticket.recipient.channel) || !policy.approved_purposes.includes(ticket.message.purpose) ||
        policy.excluded_recipient_keys.includes(ticket.recipient.recipient_key)) fail('policy_scope_denied');
    this.assertFresh(ticket.source, policy);
    if (!requireLive) return;
    if (policy.mode === 'dry_run' || !policy.live_dispatch_enabled) fail('live_dispatch_disabled');
    if (this.adapter.kind === 'unconfigured' || this.adapter.kind !== policy.native_adapter) fail('native_adapter_unavailable');
    if (!this.journal.durable) fail('durable_journal_required');
    if (!policy.test_gate.enabled || !policy.test_gate.owner_designated_recipient_keys.includes(ticket.recipient.recipient_key) ||
        Date.parse(policy.test_gate.expires_at) <= this.now()) fail('owner_test_gate_required');
    const binding = policy.channel_accounts[ticket.recipient.channel];
    if (!binding || binding.app_id !== APP_IDS[ticket.recipient.channel]) fail('app_account_unverified');
  }
  prepareNotification(input) {
    const supplied = validate(PREPARE_SCHEMA, input), snapshot = this.currentPolicy();
    if (supplied.message.body !== receiptBody(supplied.source)) fail('message_source_mismatch');
    const key = operationKey(supplied.source), fingerprint = digest({ ...supplied, policy_hash: snapshot.hash });
    const ticket = { id: `ticket_${fingerprint}`, operation_key: key, policy_hash: snapshot.hash, policy_revision: snapshot.policy.policy_revision,
      created_at: timestamp(this.now()), fingerprint, ...supplied };
    this.assertEligible(ticket, snapshot);
    return this.transaction(tx => {
      if (control(tx).stopped || this.localStopReason !== null) return blocked('operator_stopped');
      const current = tx.get('jobs', key);
      const attempt = tx.get('attempts', key);
      if (attempt) {
        const prior = tx.get('tickets', attempt.ticket_id);
        if (prior?.fingerprint !== fingerprint) fail('operation_already_attempted');
        return { status: 'already_attempted', ticket: prior, attempt: this.attemptView(attempt) };
      }
      if (current?.ticket_id === ticket.id) return { status: 'prepared', ticket: tx.get('tickets', ticket.id), replay: true, evidence_label: 'unverified' };
      tx.put('policies', snapshot.hash, { hash: snapshot.hash, policy: snapshot.policy });
      tx.put('tickets', ticket.id, ticket);
      tx.put('jobs', key, { operation_key: key, ticket_id: ticket.id });
      this.event(tx, 'notification_prepared', { ticket_id: ticket.id, replaces_ticket_id: current?.ticket_id ?? null });
      return { status: 'prepared', ticket, replay: false, evidence_label: 'unverified' };
    });
  }
  findTicket(tx, ticketId) {
    const ticket = tx.get('tickets', ticketId);
    if (!ticket) fail('ticket_not_found');
    if (ticket.fingerprint !== digest({ source: ticket.source, recipient: ticket.recipient, message: ticket.message, checks: ticket.checks, policy_hash: ticket.policy_hash }) ||
        ticket.id !== `ticket_${ticket.fingerprint}` || ticket.operation_key !== operationKey(ticket.source)) fail('journal_corrupt');
    validate(PREPARE_SCHEMA, { source: ticket.source, recipient: ticket.recipient, message: ticket.message, checks: ticket.checks }, 'journal_corrupt');
    if (tx.get('jobs', ticket.operation_key)?.ticket_id !== ticketId) fail('ticket_superseded');
    return immutable(ticket);
  }
  acquire(tx, executorId, purpose, seconds, operation_key, allowStopped = false) {
    const state = control(tx);
    if (!allowStopped && (state.stopped || this.localStopReason !== null)) fail('operator_stopped');
    if (state.lease) fail(state.lease.expires_at <= this.now() ? 'lease_recovery_required' : 'executor_busy');
    if (!Number.isSafeInteger(state.fence) || state.fence >= Number.MAX_SAFE_INTEGER) fail('journal_corrupt');
    const lease = immutable({ token: randomUUID(), owner: executorId, purpose, operation_key, fence: state.fence + 1, expires_at: this.now() + seconds * 1000 });
    tx.put('control', 'state', { ...state, fence: lease.fence, lease });
    this.event(tx, 'lease_acquired', lease);
    return lease;
  }
  assertLease(tx, lease, allowStopped = false) {
    const state = control(tx);
    if (!allowStopped && (state.stopped || this.localStopReason !== null)) fail('operator_stopped');
    if (canonical(state.lease) !== canonical(lease) || lease.expires_at <= this.now()) fail('lease_fence_invalid');
  }
  release(tx, lease) {
    const state = control(tx);
    if (canonical(state.lease) !== canonical(lease)) fail('lease_fence_invalid');
    tx.put('control', 'state', { ...state, lease: null });
    this.event(tx, 'lease_released', { token: lease.token, fence: lease.fence });
  }
  verifyPreflight(ticket, value, policy) {
    const binding = policy.channel_accounts[ticket.recipient.channel];
    if (!value || value.status !== 'verified' || value.evidence_label !== (this.adapter.kind === 'mock' ? 'mock' : 'host_verified') ||
        value.app_id !== binding?.app_id || value.app_version !== binding?.app_version || value.account_key !== binding?.account_key || value.sending_line_key !== binding?.sending_line_key ||
        canonical(value.recipient) !== canonical(ticket.recipient) || value.message_body !== ticket.message.body ||
        canonical(sourceFacts(value.source ?? {})) !== canonical(sourceFacts(ticket.source)) ||
        !Array.isArray(value.evidence_refs) || !value.evidence_refs.length || value.evidence_refs.length > 10 ||
        value.evidence_refs.some(ref => typeof ref !== 'string' || !ref.length || ref.length > 512)) fail('native_preflight_mismatch');
    validate(PREPARE_SCHEMA.properties.source, value.source, 'native_preflight_mismatch');
    this.assertFresh(value.source, policy);
    if (!Number.isFinite(Date.parse(value.observed_at)) || Math.abs(this.now() - Date.parse(value.observed_at)) > 5000) fail('native_preflight_stale');
  }
  observation(ticket, attempt, value) {
    const { policy } = this.currentPolicy(), binding = policy.channel_accounts[ticket.recipient.channel];
    if (!value || value.status !== 'outgoing_observed' || value.app_id !== binding?.app_id || value.app_version !== binding?.app_version ||
        value.account_key !== binding?.account_key || value.sending_line_key !== binding?.sending_line_key || value.recipient_key !== ticket.recipient.recipient_key || value.destination_e164 !== ticket.recipient.destination_e164 ||
        value.body_hash !== digest(ticket.message.body) || value.transaction_reference !== ticket.source.transaction_reference ||
        value.evidence_label !== (this.adapter.kind === 'mock' ? 'mock' : 'host_verified') || !Array.isArray(value.evidence_refs) ||
        !value.evidence_refs.length || value.evidence_refs.length > 10 || value.evidence_refs.some(ref => typeof ref !== 'string' || !ref.length || ref.length > 512) ||
        !Number.isFinite(Date.parse(value.observed_at)) || Date.parse(value.observed_at) < Date.parse(attempt.armed_at) || Date.parse(value.observed_at) > this.now() + 5000) fail('native_result_unverified');
    return { id: randomUUID(), attempt_id: attempt.id, status: value.status, app_id: value.app_id, app_version: value.app_version,
      account_key: value.account_key, sending_line_key: value.sending_line_key, recipient_key: value.recipient_key, destination_e164: value.destination_e164, body_hash: value.body_hash,
      transaction_reference: value.transaction_reference, observed_at: value.observed_at, evidence_label: value.evidence_label,
      evidence_refs: structuredClone(value.evidence_refs), delivery_state: 'unverified' };
  }
  attemptView(attempt) {
    return { ...attempt, state: attempt.state === 'DISPATCH_ARMED' ? 'OUTCOME_UNKNOWN' : attempt.state,
      ...(attempt.state === 'DISPATCH_ARMED' ? { durable_state: 'DISPATCH_ARMED', reason_code: 'armed_attempt_requires_reconciliation' } : {}), delivery_state: 'unverified' };
  }
  async dispatchPreparedNotification(input, signal) {
    const args = validate(EXECUTE_SCHEMA, input);
    let ticket, lease, attempt, boundary = false, finalized = false, invocationOpen = true;
    try {
      const initial = this.transaction(tx => {
        ticket = this.findTicket(tx, args.ticket_id);
        const prior = tx.get('attempts', ticket.operation_key);
        if (prior) return { status: 'already_attempted', attempt: this.attemptView(prior), external_action: 'not_repeated' };
        const snapshot = this.currentPolicy(); this.assertEligible(ticket, snapshot, true);
        if (signal?.aborted) fail('cancelled');
        lease = this.acquire(tx, args.executor_id, 'notification_dispatch', snapshot.policy.lease_seconds, ticket.operation_key);
        return null;
      });
      if (initial) return initial;
      this.active.add(lease.token);
      const preflight = await this.adapter.preflightNotification(ticket);
      const snapshot = this.currentPolicy(); this.assertEligible(ticket, snapshot, true); this.verifyPreflight(ticket, preflight, snapshot.policy);
      attempt = this.transaction(tx => {
        this.assertLease(tx, lease); this.findTicket(tx, ticket.id);
        this.assertEligible(ticket, this.currentPolicy(), true);
        if (signal?.aborted) fail('cancelled');
        if (tx.get('attempts', ticket.operation_key)) fail('operation_already_attempted');
        const preflightId = randomUUID();
        tx.put('observations', preflightId, { id: preflightId, ticket_id: ticket.id, status: 'preflight_verified',
          observed_at: preflight.observed_at, evidence_label: preflight.evidence_label, evidence_refs: preflight.evidence_refs });
        const armed = { id: randomUUID(), ticket_id: ticket.id, operation_key: ticket.operation_key, state: 'DISPATCH_ARMED', preflight_id: preflightId,
          fence: lease.fence, executor_id: lease.owner, armed_at: timestamp(this.now()), evidence_label: this.adapter.kind === 'mock' ? 'mock' : 'host_verified' };
        tx.put('attempts', ticket.operation_key, armed); this.event(tx, 'dispatch_armed', armed); return immutable(armed);
      });
      const beforeAction = witness => {
        if (!invocationOpen) fail('action_permit_expired');
        if (boundary) fail('action_permit_consumed');
        const current = this.currentPolicy(); this.assertEligible(ticket, current, true); this.verifyPreflight(ticket, witness, current.policy);
        this.transaction(tx => {
          this.assertLease(tx, lease);
          if (signal?.aborted) fail('cancelled');
          const retained = tx.get('attempts', ticket.operation_key);
          if (retained?.id !== attempt.id || retained.state !== 'DISPATCH_ARMED') fail('attempt_not_armed');
          this.event(tx, 'dispatch_action_boundary', { attempt_id: attempt.id, fence: lease.fence, observed_at: witness.observed_at, evidence_refs: witness.evidence_refs });
        });
        boundary = true;
        return { attempt_id: attempt.id, fence: lease.fence };
      };
      let result, observation, reason, noSendEvidence;
      try {
        result = await this.adapter.dispatchNotification(ticket, attempt, { beforeAction, signal });
        if (result?.status === 'outgoing_observed' && boundary) observation = this.observation(ticket, attempt, result);
        else if (result?.status === 'failed_no_send' && !boundary && result.action_not_started === true &&
            result.evidence_label === (this.adapter.kind === 'mock' ? 'mock' : 'host_verified') &&
            typeof result.reason_code === 'string' && /^[a-z_]{1,80}$/.test(result.reason_code) &&
            Array.isArray(result.evidence_refs) && result.evidence_refs.length > 0 && result.evidence_refs.length <= 10 &&
            result.evidence_refs.every(ref => typeof ref === 'string' && ref.length > 0 && ref.length <= 512)) {
          noSendEvidence = { id: randomUUID(), attempt_id: attempt.id, status: 'failed_no_send', action_not_started: true,
            evidence_label: result.evidence_label, reason_code: result.reason_code, evidence_refs: structuredClone(result.evidence_refs), observed_at: timestamp(this.now()) };
        } else reason = 'native_result_unverified';
      } catch (error) { reason = cleanFailure(error); }
      const state = observation ? 'OUTGOING_OBSERVED' : noSendEvidence && !reason ? 'FAILED_NO_SEND' : 'OUTCOME_UNKNOWN';
      return this.transaction(tx => {
        const retained = tx.get('attempts', ticket.operation_key);
        if (retained?.id !== attempt.id || retained.state !== 'DISPATCH_ARMED') fail('journal_corrupt');
        const outcome = { ...attempt, state, observed_at: timestamp(this.now()), reason_code: reason ?? noSendEvidence?.reason_code ?? null, observation_id: observation?.id ?? noSendEvidence?.id ?? null };
        if (observation) tx.put('observations', observation.id, observation);
        if (noSendEvidence) tx.put('observations', noSendEvidence.id, noSendEvidence);
        tx.put('attempts', ticket.operation_key, outcome); this.event(tx, 'dispatch_outcome', outcome);
        tx.put('jobs', ticket.operation_key, { operation_key: ticket.operation_key, ticket_id: ticket.id, state: 'consumed' });
        this.release(tx, lease); finalized = true;
        return { status: state.toLowerCase(), attempt: this.attemptView(outcome), external_action: state === 'FAILED_NO_SEND' ? 'not_started' : 'possible', evidence_label: attempt.evidence_label };
      });
    } catch (error) {
      if (attempt) {
        // An armed attempt survives a failed result commit. Never report it as unsent.
        if (!(error instanceof DesktopError) || ['journal_unavailable', 'journal_corrupt', 'unsafe_journal_path'].includes(error.code)) throw error;
        return this.transaction(tx => {
          const unknown = { ...attempt, state: 'OUTCOME_UNKNOWN', reason_code: cleanFailure(error), observed_at: timestamp(this.now()) };
          tx.put('attempts', ticket.operation_key, unknown); this.event(tx, 'dispatch_outcome', unknown);
          this.release(tx, lease); finalized = true;
          return { status: 'outcome_unknown', attempt: this.attemptView(unknown), external_action: 'possible' };
        });
      }
      if (error instanceof DesktopError) {
        if (ticket && !['journal_unavailable', 'journal_corrupt', 'unsafe_journal_path'].includes(error.code)) this.transaction(tx => {
          const job = tx.get('jobs', ticket.operation_key);
          if (job?.ticket_id === ticket.id && !tx.get('attempts', ticket.operation_key) && job.blocked_reason_code !== error.code) {
            tx.put('jobs', ticket.operation_key, { ...job, blocked_reason_code: error.code });
            this.event(tx, 'dispatch_refused', { ticket_id: ticket.id, reason_code: error.code });
          }
        });
        return blocked(error.code);
      }
      return blocked('native_preflight_unavailable');
    } finally {
      invocationOpen = false;
      if (lease) {
        this.active.delete(lease.token);
        if (!attempt && !finalized) this.transaction(tx => this.release(tx, lease));
      }
    }
  }
  findAttempt(tx, id) {
    const attempt = tx.all('attempts').find(value => value.id === id);
    if (!attempt) fail('attempt_not_found');
    const ticket = this.findTicket(tx, attempt.ticket_id);
    if (attempt.operation_key !== ticket.operation_key || !['DISPATCH_ARMED', 'OUTGOING_OBSERVED', 'FAILED_NO_SEND', 'OUTCOME_UNKNOWN'].includes(attempt.state)) fail('journal_corrupt');
    return { attempt: immutable(attempt), ticket };
  }
  async recoverLease(args, ticket) {
    const old = this.transaction(tx => {
      const state = control(tx), lease = state.lease;
      if (!state.stopped) fail('recovery_requires_stop');
      if (!lease || lease.token !== args.lease_token || lease.fence !== args.lease_fence || lease.operation_key !== ticket.operation_key) fail('lease_fence_invalid');
      if (lease.expires_at > this.now() || this.active.has(lease.token)) fail('executor_busy');
      return immutable(lease);
    });
    if (!this.quiescenceVerifier) fail('executor_quiescence_unverified');
    const evidence = await this.quiescenceVerifier(old);
    if (evidence?.status !== 'quiescent' || evidence.lease_token !== old.token || evidence.lease_fence !== old.fence ||
        evidence.executor_id !== old.owner || evidence.evidence_label !== (this.adapter.kind === 'mock' ? 'mock' : 'host_verified') ||
        !Array.isArray(evidence.evidence_refs) || !evidence.evidence_refs.length || evidence.evidence_refs.length > 10 ||
        evidence.evidence_refs.some(ref => typeof ref !== 'string' || !ref.length || ref.length > 512)) fail('executor_quiescence_unverified');
    this.transaction(tx => {
      const state = control(tx);
      if (!state.stopped || canonical(state.lease) !== canonical(old) || this.active.has(old.token) || state.fence >= Number.MAX_SAFE_INTEGER) fail('lease_fence_invalid');
      tx.put('control', 'state', { ...state, lease: null, fence: state.fence + 1 });
      this.event(tx, 'lease_recovered', { lease_token: old.token, old_fence: old.fence, new_fence: state.fence + 1,
        owner_review_ref: args.owner_review_ref, evidence_label: evidence.evidence_label, evidence_refs: evidence.evidence_refs });
    });
  }
  async reconcileAttempt(input) {
    const args = validate(RECONCILE_SCHEMA, input);
    const found = this.transaction(tx => this.findAttempt(tx, args.attempt_id));
    if (!['DISPATCH_ARMED', 'OUTCOME_UNKNOWN'].includes(found.attempt.state)) return { status: 'recorded', attempt: this.attemptView(found.attempt) };
    if (this.adapter.kind === 'unconfigured' || !this.adapter.inspectAttempt) return { ...unavailable(), attempt: this.attemptView(found.attempt) };
    let lease;
    try {
      const snapshot = this.currentPolicy();
      if (args.recovery) await this.recoverLease(args.recovery, found.ticket);
      lease = this.transaction(tx => this.acquire(tx, args.executor_id, 'reconciliation', snapshot.policy.lease_seconds, found.ticket.operation_key, true));
      this.active.add(lease.token);
      const result = await this.adapter.inspectAttempt(found.ticket, found.attempt);
      if (result?.status !== 'outgoing_observed') return { status: 'outcome_unknown', attempt: this.attemptView(found.attempt) };
      const observation = this.observation(found.ticket, found.attempt, result);
      return this.transaction(tx => {
        this.assertLease(tx, lease, true);
        const current = this.findAttempt(tx, args.attempt_id).attempt;
        const outcome = { ...current, state: 'OUTGOING_OBSERVED', observed_at: observation.observed_at, observation_id: observation.id, reason_code: null };
        tx.put('observations', observation.id, observation); tx.put('attempts', current.operation_key, outcome);
        this.event(tx, 'attempt_reconciled', { attempt_id: outcome.id, observation_id: observation.id });
        return { status: 'outgoing_observed', attempt: this.attemptView(outcome), evidence_label: observation.evidence_label };
      });
    } catch (error) {
      if (error instanceof DesktopError) return { ...blocked(error.code), attempt: this.attemptView(found.attempt) };
      return { status: 'outcome_unknown', attempt: this.attemptView(found.attempt) };
    } finally { if (lease) { this.active.delete(lease.token); this.transaction(tx => this.release(tx, lease)); } }
  }
  async writeAdminOutcome(input, signal) {
    const args = validate(ATTEMPT_SCHEMA, input);
    let lease, sync, invocationOpen = true;
    try {
      const { attempt, ticket } = this.transaction(tx => this.findAttempt(tx, args.attempt_id));
      const snapshot = this.currentPolicy();
      if (snapshot.policy.mode === 'dry_run' || !snapshot.policy.live_dispatch_enabled) return blocked('live_dispatch_disabled');
      if (this.adapter.kind === 'unconfigured' || this.adapter.kind !== snapshot.policy.native_adapter || !this.adapter.inspectAdminOutcome || !this.adapter.writeAdminOutcome) return unavailable();
      if (snapshot.hash !== ticket.policy_hash || !snapshot.policy.test_gate.enabled ||
          !snapshot.policy.test_gate.owner_designated_recipient_keys.includes(ticket.recipient.recipient_key) ||
          Date.parse(snapshot.policy.test_gate.expires_at) <= this.now()) return blocked('owner_test_gate_required');
      if (!this.journal.durable) return blocked('durable_journal_required');
      if (!snapshot.policy.admin_browser) return blocked('admin_browser_unverified');
      const revision = outcomeRevision(attempt);
      const setup = this.transaction(tx => {
        const previous = tx.all('syncs').filter(value => value.outcome_revision === revision);
        const done = previous.find(value => value.state === 'SYNCED');
        if (done) return done;
        lease = this.acquire(tx, args.executor_id, 'admin_outcome_writeback', snapshot.policy.lease_seconds, ticket.operation_key);
        return { uncertain: previous.find(value => ['WRITE_ARMED', 'SYNC_UNKNOWN'].includes(value.state)) ?? null };
      });
      if (setup.state === 'SYNCED') return { status: 'synced', sync: setup, replay: true };
      this.active.add(lease.token);
      const sourceMatches = value => value && value.browser_origin === snapshot.policy.admin_browser.origin && value.account_key === snapshot.policy.admin_browser.account_key &&
        canonical(value.source_facts) === canonical(sourceFacts(ticket.source)) && Number.isFinite(Date.parse(value.observed_at)) &&
        Math.abs(this.now() - Date.parse(value.observed_at)) <= 5000 && value.evidence_label === (this.adapter.kind === 'mock' ? 'mock' : 'host_verified') &&
        Array.isArray(value.evidence_refs) && value.evidence_refs.length > 0 && value.evidence_refs.length <= 10 &&
        value.evidence_refs.every(ref => typeof ref === 'string' && ref.length > 0 && ref.length <= 512);
      const sameAttempt = value => sourceMatches(value) && value.status === 'matched' && value.attempt_id === attempt.id && value.ticket_id === ticket.id &&
        value.operation_key === ticket.operation_key && value.delivery_state === 'unverified';
      const matches = value => sameAttempt(value) && value.outcome === this.attemptView(attempt).state;
      const priorSynced = value => sameAttempt(value) && this.transaction(tx => tx.all('syncs').some(prior =>
        prior.state === 'SYNCED' && prior.attempt_id === attempt.id && prior.ticket_id === ticket.id && prior.outcome === value.outcome && prior.outcome_revision !== revision));
      let existing = await this.adapter.inspectAdminOutcome(ticket, this.attemptView(attempt));
      if (setup.uncertain && !matches(existing)) fail('admin_sync_reconciliation_required');
      if (!(existing?.status === 'absent' && sourceMatches(existing)) && !matches(existing) && !priorSynced(existing)) fail('admin_source_mismatch');
      sync = this.transaction(tx => {
        this.assertLease(tx, lease);
        if (this.currentPolicy().hash !== snapshot.hash || signal?.aborted) fail('policy_changed');
        const value = { id: setup.uncertain?.id ?? randomUUID(), ticket_id: ticket.id, attempt_id: attempt.id, outcome_revision: revision, state: matches(existing) ? 'SYNCED' : 'WRITE_ARMED',
          outcome: this.attemptView(attempt).state, at: timestamp(this.now()), evidence_label: this.adapter.kind === 'mock' ? 'mock' : 'host_verified' };
        tx.put('syncs', value.id, value); this.event(tx, 'admin_sync_armed', value); return value;
      });
      let permitUsed = false;
      if (!matches(existing)) {
        await this.adapter.writeAdminOutcome(ticket, this.attemptView(attempt), { signal, beforeAction: witness => {
          if (!invocationOpen) fail('action_permit_expired');
          if (permitUsed) fail('action_permit_consumed');
          if (!(sourceMatches(witness) && (witness.status === 'absent' || matches(witness) || priorSynced(witness)))) fail('admin_source_mismatch');
          this.transaction(tx => {
            this.assertLease(tx, lease);
            if (this.currentPolicy().hash !== snapshot.hash || Date.parse(snapshot.policy.test_gate.expires_at) <= this.now() || signal?.aborted) fail('policy_changed');
            this.event(tx, 'admin_sync_action_boundary', { sync_id: sync.id, fence: lease.fence });
          });
          permitUsed = true;
        } });
        if (!permitUsed) fail('admin_write_unverified');
        existing = await this.adapter.inspectAdminOutcome(ticket, this.attemptView(attempt));
      }
      if (!matches(existing)) fail('admin_write_unverified');
      return this.transaction(tx => {
        const completed = { ...sync, state: 'SYNCED', evidence_refs: existing.evidence_refs, observed_at: timestamp(this.now()) };
        tx.put('syncs', sync.id, completed); this.event(tx, 'admin_sync_observed', { sync_id: sync.id });
        return { status: 'synced', sync: completed };
      });
    } catch (error) {
      if (sync?.state === 'WRITE_ARMED') return this.transaction(tx => {
        const unknown = { ...sync, state: 'SYNC_UNKNOWN', reason_code: cleanFailure(error) };
        tx.put('syncs', sync.id, unknown); this.event(tx, 'admin_sync_unknown', { sync_id: sync.id });
        return { status: 'sync_unknown', reason_code: cleanFailure(error), external_action: 'possible', sync: unknown };
      });
      if (error instanceof DesktopError) return blocked(error.code);
      return blocked('admin_write_unverified');
    } finally { invocationOpen = false; if (lease) { this.active.delete(lease.token); this.transaction(tx => this.release(tx, lease)); } }
  }
  getPendingExceptions(input = {}) {
    const { limit = 50 } = validate(EXCEPTIONS_SCHEMA, input);
    return this.transaction(tx => {
      const attempts = tx.all('attempts').filter(value => ['DISPATCH_ARMED', 'OUTCOME_UNKNOWN'].includes(value.state)).map(value => ({ kind: 'dispatch', ...this.attemptView(value) }));
      const syncs = tx.all('syncs').filter(value => ['WRITE_ARMED', 'SYNC_UNKNOWN'].includes(value.state)).map(value => ({ kind: 'admin_sync', ...value }));
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
