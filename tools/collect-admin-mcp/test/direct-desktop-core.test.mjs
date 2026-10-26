import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DirectDesktopCore } from '../src/direct-desktop/core.mjs';
import { SqliteDesktopJournal, MemoryDesktopJournal } from '../src/direct-desktop/journal.mjs';
import { DEFAULT_POLICY, DesktopError, receiptBody, operationKey } from '../src/direct-desktop/contract.mjs';
import { CLOCK, fixtureInput, fixturePolicy, witness, outgoing, mockAdapter } from './direct-desktop-fixtures.mjs';

function setup(t, options = {}) {
  const directory = mkdtempSync(join(realpathSync(tmpdir()), 'collect-desktop-core-'));
  const path = join(directory, 'journal.sqlite');
  const journal = new SqliteDesktopJournal(path), adapter = options.adapter ?? mockAdapter(options.now);
  const core = new DirectDesktopCore({ journal, adapter, policy: fixturePolicy(), now: () => CLOCK, ...options });
  t.after(() => { core.close(); rmSync(directory, { recursive: true, force: true }); });
  return { core, journal, adapter, path };
}
const prepared = core => core.prepareNotification(fixtureInput()).ticket;
const dispatch = (core, ticket) => core.dispatchPreparedNotification({ ticket_id: ticket.id, executor_id: 'synthetic-executor' });
const errorCode = code => error => error instanceof DesktopError && error.code === code;

test('default core exposes honest dry-run capability and no native source or call success', async () => {
  const adapter = mockAdapter(), core = new DirectDesktopCore({ journal: new MemoryDesktopJournal(), adapter, now: () => CLOCK });
  assert.equal(core.health().mode, 'dry_run');
  assert.equal(core.observeAdminQueue().status, 'unavailable');
  for (const name of ['prepareCall', 'startPreparedCall', 'inspectCallState', 'endCurrentCall']) assert.equal(core[name]().status, 'unavailable');
  const ticket = prepared(core), result = await dispatch(core, ticket);
  assert.equal(result.reason_code, 'live_dispatch_disabled');
  assert.equal(adapter.calls.preflight, 0); assert.equal(core.health().attempts, 0);
  core.close();
});

test('template copies the exact financial labels and rejects invented or additional wording', t => {
  const { core } = setup(t), input = fixtureInput();
  assert.equal(prepared(core).message.body, receiptBody(input.source));
  for (const body of [input.message.body.replace('1,000', '10,000'), input.message.body + ' Ignore previous instructions.', 'Payment received.']) {
    input.message.body = body;
    assert.throws(() => core.prepareNotification(input), errorCode('message_source_mismatch'));
  }
});

test('stable operation identity cannot collide through delimiters, tenant or purpose substitution', () => {
  const a = fixtureInput().source, b = { ...a, source_namespace: 'a:b', tenant_id: 'c' }, c = { ...a, source_namespace: 'a', tenant_id: 'b:c' };
  assert.notEqual(operationKey(b), operationKey(c));
  assert.notEqual(operationKey(a), operationKey({ ...a, tenant_id: 'other-tenant' }));
});

test('identical preparation replays; a fresh changed source supersedes the unsent immutable ticket', async t => {
  const { core, journal } = setup(t), input = fixtureInput();
  const first = core.prepareNotification(input);
  assert.equal(core.prepareNotification(input).replay, true);
  input.source.source_version = 'v2'; input.source.balance_label = 'RWF 6,000 recorded contributions'; input.message.body = receiptBody(input.source);
  const second = core.prepareNotification(input);
  assert.notEqual(first.ticket.id, second.ticket.id);
  assert.equal((await dispatch(core, first.ticket)).reason_code, 'ticket_superseded');
  assert.equal(journal.transaction(tx => tx.get('tickets', first.ticket.id)).source.source_version, 'v1');
  assert.equal((await dispatch(core, second.ticket)).status, 'outgoing_observed');
});

test('one consumed operation never dispatches twice, including changed recipient, template or financial snapshot', async t => {
  const { core, adapter } = setup(t), ticket = prepared(core);
  const first = await dispatch(core, ticket);
  const repeated = await dispatch(core, ticket);
  assert.equal(repeated.status, 'already_attempted'); assert.equal(first.attempt.id, repeated.attempt.id);
  assert.equal(core.prepareNotification(fixtureInput()).status, 'already_attempted');
  const input = fixtureInput(); input.recipient.destination_e164 = '+12025550124';
  assert.throws(() => core.prepareNotification(input), errorCode('operation_already_attempted'));
  assert.equal(adapter.calls.dispatch, 1);
});

test('native preflight verifies source version, tenant, recipient, text, app version and business account before arming', async t => {
  for (const change of [
    value => { value.source.source_version = 'v2'; }, value => { value.source.tenant_id = 'wrong'; },
    value => { value.recipient.destination_e164 = '+12025550124'; }, value => { value.message_body += 'x'; },
    value => { value.app_version = 'unexpected-upgrade'; }, value => { value.account_key = 'personal-account'; },
    value => { value.app_id = 'wrong-app'; }, value => { value.observed_at = new Date(CLOCK - 6000).toISOString(); },
    value => { value.sending_line_key = 'personal-line'; }, value => { value.evidence_refs = []; },
  ]) {
    const adapter = mockAdapter(); adapter.preflightNotification = async ticket => { const result = witness(ticket); change(result); return result; };
    const { core } = setup(t, { adapter });
    assert.equal((await dispatch(core, prepared(core))).status, 'blocked');
    assert.equal(core.health().attempts, 0); assert.equal(adapter.calls.dispatch, 0);
  }
});

test('policy revision, freshness, exclusions, test gate, account binding and durable journal are enforced before native access', async t => {
  const policies = [
    policy => { policy.test_gate.enabled = false; }, policy => { policy.test_gate.owner_designated_recipient_keys = ['someone-else']; },
    policy => { policy.test_gate.expires_at = new Date(CLOCK).toISOString(); }, policy => { policy.channel_accounts = {}; },
  ];
  for (const change of policies) {
    const policy = fixturePolicy(); change(policy);
    const { core, adapter } = setup(t, { policy });
    assert.equal((await dispatch(core, prepared(core))).status, 'blocked'); assert.equal(adapter.calls.preflight, 0);
  }
  const memory = new DirectDesktopCore({ journal: new MemoryDesktopJournal(), adapter: mockAdapter(), policy: fixturePolicy(), now: () => CLOCK });
  assert.equal((await dispatch(memory, prepared(memory))).reason_code, 'durable_journal_required'); memory.close();
  let policy = fixturePolicy(), time = CLOCK;
  const { core, adapter } = setup(t, { policyProvider: () => policy, now: () => time });
  const ticket = prepared(core); policy = { ...policy, policy_revision: 'changed' };
  assert.equal((await dispatch(core, ticket)).reason_code, 'policy_changed');
  policy = fixturePolicy(); time += 300_001;
  assert.equal((await dispatch(core, ticket)).reason_code, 'source_snapshot_stale'); assert.equal(adapter.calls.preflight, 0);
});

test('native adapter sees a committed DISPATCH_ARMED record and a single-use action permit', async t => {
  const { core, adapter, journal } = setup(t);
  adapter.dispatchNotification = async (ticket, attempt, context) => {
    assert.equal(journal.transaction(tx => tx.get('attempts', ticket.operation_key)).state, 'DISPATCH_ARMED');
    assert.equal(journal.events().some(event => event.type === 'dispatch_armed'), true);
    context.beforeAction(witness(ticket));
    assert.throws(() => context.beforeAction(witness(ticket)), errorCode('action_permit_consumed'));
    return outgoing(ticket, attempt);
  };
  const result = await dispatch(core, prepared(core));
  assert.equal(result.status, 'outgoing_observed'); assert.equal(result.evidence_label, 'mock');
  assert.equal(result.attempt.delivery_state, 'unverified');
});

test('single GUI lease rejects overlapping executors across tickets and monotonically fences subsequent work', async t => {
  const { core, adapter } = setup(t), first = prepared(core), second = core.prepareNotification(fixtureInput('SYNTHETIC-RECEIPT-2')).ticket;
  let release;
  adapter.preflightNotification = ticket => new Promise(resolve => { release = () => resolve(witness(ticket)); });
  const running = dispatch(core, first);
  assert.equal((await dispatch(core, second)).reason_code, 'executor_busy');
  assert.equal((await dispatch(core, first)).reason_code, 'executor_busy');
  release(); const result = await running;
  adapter.preflightNotification = async ticket => witness(ticket);
  const next = await dispatch(core, second);
  assert.equal(next.attempt.fence, result.attempt.fence + 1);
});

test('stop during preparation inhibits the irreversible boundary and remains durable after restart', async t => {
  const { core, adapter, journal, path } = setup(t), ticket = prepared(core);
  adapter.dispatchNotification = async (value, attempt, context) => {
    const stopped = core.stopAll({ reason: 'synthetic-owner-stop' });
    assert.equal(stopped.new_dispatch_inhibited, true); assert.equal(stopped.delegated_tasks_and_schedules, 'not_verified');
    context.beforeAction(witness(value)); return outgoing(value, attempt);
  };
  const outcome = await dispatch(core, ticket);
  assert.equal(outcome.status, 'outcome_unknown'); assert.equal(outcome.attempt.reason_code, 'operator_stopped');
  const reopened = new DirectDesktopCore({ journal: new SqliteDesktopJournal(path), now: () => CLOCK });
  assert.equal(reopened.health().status, 'stopped'); reopened.close();
  assert.equal(journal.events().some(event => event.type === 'dispatch_action_boundary'), false);
});

test('a stopped runtime refuses preparation, dispatch and Admin writes without invoking adapters', async t => {
  const { core, adapter } = setup(t), ticket = prepared(core);
  const outcome = await dispatch(core, ticket);
  core.stopAll({ reason: 'stop' });
  assert.equal(core.prepareNotification(fixtureInput('new')).reason_code, 'operator_stopped');
  assert.equal((await core.writeAdminOutcome({ attempt_id: outcome.attempt.id, executor_id: 'executor' })).reason_code, 'operator_stopped');
  assert.equal(adapter.calls.write, 0);
});

test('policy revocation and app interference are checked again at the last possible action boundary', async t => {
  let policy = fixturePolicy();
  const { core, adapter, journal } = setup(t, { policyProvider: () => policy });
  adapter.dispatchNotification = async (ticket, attempt, context) => {
    policy = { ...policy, policy_revision: 'revoked' };
    context.beforeAction(witness(ticket)); return outgoing(ticket, attempt);
  };
  const result = await dispatch(core, prepared(core));
  assert.equal(result.status, 'outcome_unknown'); assert.equal(result.attempt.reason_code, 'policy_changed');
  assert.equal(journal.events().some(event => event.type === 'dispatch_action_boundary'), false);
});

test('expired leases fail closed at Send; no executor steals an abandoned lease', async t => {
  let time = CLOCK;
  const { core, adapter, journal } = setup(t, { now: () => time });
  adapter.dispatchNotification = async (ticket, attempt, context) => { time += 60_001; context.beforeAction(witness(ticket, time)); return outgoing(ticket, attempt, time); };
  const result = await dispatch(core, prepared(core));
  assert.equal(result.status, 'outcome_unknown');
  assert.equal(['lease_fence_invalid', 'owner_test_gate_required'].includes(result.attempt.reason_code), true);
  time = CLOCK;
  const second = core.prepareNotification(fixtureInput('SECOND')).ticket;
  journal.transaction(tx => tx.put('control', 'state', { stopped: false, reason: null, fence: 99,
    lease: { token: 'abandoned', owner: 'old-process', purpose: 'notification_dispatch', fence: 99, expires_at: CLOCK - 1 } }));
  assert.equal((await dispatch(core, second)).reason_code, 'lease_recovery_required');
  assert.equal(core.getPendingExceptions().rows.some(row => row.kind === 'lease'), true);
});

test('an exception or mismatched native observation after arming is unknown and cannot be retried', async t => {
  for (const implementation of [
    async (ticket, attempt, context) => { context.beforeAction(witness(ticket)); throw new Error('sensitive-native-diagnostic'); },
    async (ticket, attempt, context) => { context.beforeAction(witness(ticket)); return { ...outgoing(ticket, attempt), destination_e164: '+12025550124' }; },
    async (ticket, attempt) => outgoing(ticket, attempt),
  ]) {
    const { core, adapter } = setup(t); adapter.dispatchNotification = implementation;
    const ticket = prepared(core), result = await dispatch(core, ticket);
    assert.equal(result.status, 'outcome_unknown');
    assert.equal(JSON.stringify(result).includes('sensitive-native-diagnostic'), false);
    assert.equal((await dispatch(core, ticket)).status, 'already_attempted');
  }
});

test('a positively evidenced pre-action failure is retained once; an unsupported no-send assertion stays unknown', async t => {
  for (const valid of [true, false]) {
    const { core, adapter, journal } = setup(t), ticket = prepared(core);
    adapter.dispatchNotification = async () => valid ? { status: 'failed_no_send', action_not_started: true,
      reason_code: 'compose_control_unavailable', evidence_label: 'mock', evidence_refs: ['synthetic:before-action-failure'] } : { status: 'failed_no_send' };
    const result = await dispatch(core, ticket);
    assert.equal(result.status, valid ? 'failed_no_send' : 'outcome_unknown');
    assert.equal((await dispatch(core, ticket)).status, 'already_attempted');
    assert.equal(journal.transaction(tx => tx.all('observations').filter(value => value.status === 'failed_no_send')).length, valid ? 1 : 0);
  }
});

test('arming commit failure prevents sending; outcome commit failure preserves durable uncertainty', async t => {
  for (const failedEvent of ['dispatch_armed', 'dispatch_outcome']) {
    const { core, journal, adapter, path } = setup(t);
    const ticket = prepared(core), original = journal.transaction.bind(journal);
    journal.transaction = action => original(tx => action({ ...tx, append(event) {
      if (event.type === failedEvent) throw new DesktopError('journal_unavailable');
      tx.append(event);
    } }));
    if (failedEvent === 'dispatch_armed') {
      const result = await dispatch(core, ticket);
      assert.equal(result.reason_code, 'journal_unavailable'); assert.equal(adapter.calls.dispatch, 0);
    } else {
      await assert.rejects(dispatch(core, ticket), errorCode('journal_unavailable'));
      assert.equal(adapter.calls.dispatch, 1);
      const reopened = new DirectDesktopCore({ journal: new SqliteDesktopJournal(path), now: () => CLOCK });
      assert.equal(reopened.getPendingExceptions().rows[0].durable_state, 'DISPATCH_ARMED');
      assert.equal((await dispatch(reopened, ticket)).status, 'already_attempted'); reopened.close();
    }
    journal.transaction = original;
  }
});

test('crash-recovered arming is always exposed as unknown, never as an unsent fresh job', async t => {
  const { core, journal, path } = setup(t), ticket = prepared(core);
  journal.transaction(tx => tx.put('attempts', ticket.operation_key, { id: 'synthetic-crash-attempt', ticket_id: ticket.id, operation_key: ticket.operation_key,
    state: 'DISPATCH_ARMED', fence: 1, executor_id: 'crashed-executor', armed_at: new Date(CLOCK).toISOString(), evidence_label: 'mock' }));
  const reopened = new DirectDesktopCore({ journal: new SqliteDesktopJournal(path), adapter: mockAdapter(), policy: fixturePolicy(), now: () => CLOCK });
  assert.equal(reopened.getPendingExceptions().rows[0].state, 'OUTCOME_UNKNOWN');
  assert.equal((await dispatch(reopened, ticket)).status, 'already_attempted');
  assert.equal((await reopened.reconcileAttempt({ attempt_id: 'synthetic-crash-attempt', executor_id: 'reviewer' })).status, 'outgoing_observed');
  assert.equal((await dispatch(reopened, ticket)).status, 'already_attempted'); reopened.close();
});

test('absence of an outgoing bubble does not establish no-send during reconciliation', async t => {
  const { core, adapter } = setup(t), ticket = prepared(core);
  adapter.dispatchNotification = async () => { throw new Error('interrupted'); };
  const result = await dispatch(core, ticket);
  adapter.inspectAttempt = async () => ({ status: 'failed_no_send', evidence_refs: ['synthetic:no-bubble'] });
  assert.equal((await core.reconcileAttempt({ attempt_id: result.attempt.id, executor_id: 'reviewer' })).status, 'outcome_unknown');
  assert.equal((await dispatch(core, ticket)).status, 'already_attempted');
});

test('UI writeback records only the retained outcome, remains separate from delivery, and replays locally', async t => {
  const { core, adapter } = setup(t), result = await dispatch(core, prepared(core));
  const args = { attempt_id: result.attempt.id, executor_id: 'ui-writer' };
  const synced = await core.writeAdminOutcome(args);
  assert.equal(synced.status, 'synced'); assert.equal(synced.sync.outcome, 'OUTGOING_OBSERVED');
  assert.equal((await core.writeAdminOutcome(args)).replay, true);
  assert.equal(adapter.calls.write, 1); assert.equal(adapter.calls.dispatch, 1); assert.equal(core.health().admin_sync_pending, 0);
});

test('failed Admin writeback is retained for reconciliation and never resends the notification', async t => {
  const { core, adapter } = setup(t), ticket = prepared(core), result = await dispatch(core, ticket);
  adapter.writeAdminOutcome = async (value, attempt, context) => { context.beforeAction(await adapter.inspectAdminOutcome(value, attempt)); adapter.calls.write++; throw new Error('lost-ui-result'); };
  const args = { attempt_id: result.attempt.id, executor_id: 'ui-writer' };
  const unknown = await core.writeAdminOutcome(args);
  assert.equal(unknown.status, 'sync_unknown'); assert.equal(unknown.external_action, 'possible');
  assert.equal(core.getPendingExceptions().rows.some(row => row.kind === 'admin_sync' && row.state === 'SYNC_UNKNOWN'), true);
  assert.equal((await core.writeAdminOutcome(args)).reason_code, 'admin_sync_reconciliation_required');
  assert.equal((await dispatch(core, ticket)).status, 'already_attempted');
  assert.equal(adapter.calls.dispatch, 1); assert.equal(adapter.calls.write, 1);
});

test('dry-run policy inhibits Admin writes even when an earlier attempt exists', async t => {
  let policy = fixturePolicy();
  const { core, adapter } = setup(t, { policyProvider: () => policy }), result = await dispatch(core, prepared(core));
  policy = structuredClone(DEFAULT_POLICY);
  assert.equal((await core.writeAdminOutcome({ attempt_id: result.attempt.id, executor_id: 'writer' })).reason_code, 'live_dispatch_disabled');
  assert.equal(adapter.calls.write, 0);
});

test('a lost writeback reply is resolved by matching UI readback without a second write', async t => {
  const { core, adapter } = setup(t), ticket = prepared(core), result = await dispatch(core, ticket);
  const original = adapter.writeAdminOutcome;
  adapter.writeAdminOutcome = async (...args) => { await original(...args); throw new Error('lost-reply-after-write'); };
  const args = { attempt_id: result.attempt.id, executor_id: 'ui-writer' };
  const unknown = await core.writeAdminOutcome(args);
  assert.equal(unknown.status, 'sync_unknown'); assert.equal(unknown.external_action, 'possible');
  assert.equal((await core.writeAdminOutcome(args)).status, 'synced');
  assert.equal(adapter.calls.write, 1); assert.equal(adapter.calls.dispatch, 1);
  assert.equal(core.getPendingExceptions().rows.some(row => row.kind === 'admin_sync'), false);
});

test('a wrong Admin tenant, account, source or stale observation blocks outcome writeback', async t => {
  for (const change of [
    value => { value.source_facts.tenant_id = 'other-tenant'; }, value => { value.account_key = 'other-admin'; },
    value => { value.browser_origin = 'https://other.example.test'; }, value => { value.source_facts.source_version = 'changed'; },
    value => { value.observed_at = new Date(CLOCK - 6000).toISOString(); },
  ]) {
    const { core, adapter } = setup(t), result = await dispatch(core, prepared(core)), original = adapter.inspectAdminOutcome;
    adapter.inspectAdminOutcome = async (...args) => { const value = await original(...args); change(value); return value; };
    assert.equal((await core.writeAdminOutcome({ attempt_id: result.attempt.id, executor_id: 'writer' })).reason_code, 'admin_source_mismatch');
    assert.equal(adapter.calls.write, 0);
  }
});

test('cancelled work cannot arm or pass the Send boundary', async t => {
  const { core, adapter } = setup(t), abort = new AbortController(), ticket = prepared(core);
  abort.abort();
  assert.equal((await core.dispatchPreparedNotification({ ticket_id: ticket.id, executor_id: 'executor' }, abort.signal)).reason_code, 'cancelled');
  assert.equal(adapter.calls.preflight, 0);
});

test('adapter mutation cannot replace the validated execution ticket, recipient, body or attempt identity', async t => {
  for (const phase of ['preflight', 'dispatch']) {
    const { core, adapter, journal } = setup(t), ticket = prepared(core);
    if (phase === 'preflight') adapter.preflightNotification = async value => { value.recipient.destination_e164 = '+12025550124'; return witness(value); };
    else adapter.dispatchNotification = async (value, attempt, context) => {
      value.message.body = 'mutated'; attempt.id = 'changed'; context.beforeAction(witness(value)); return outgoing(value, attempt);
    };
    const result = await dispatch(core, ticket);
    assert.equal(result.status, phase === 'preflight' ? 'blocked' : 'outcome_unknown');
    assert.equal(adapter.calls.dispatch, 0);
    const retained = journal.transaction(tx => tx.get('tickets', ticket.id));
    assert.equal(retained.recipient.destination_e164, ticket.recipient.destination_e164); assert.equal(retained.message.body, ticket.message.body);
  }
});

test('a failed durable Stop still inhibits this process before the Send boundary and persists when storage returns', async t => {
  const { core, adapter, journal } = setup(t), ticket = prepared(core), original = journal.transaction.bind(journal);
  adapter.dispatchNotification = async (value, attempt, context) => {
    journal.transaction = action => original(tx => action({ ...tx, append(event) {
      if (event.type === 'stop_all') throw new DesktopError('journal_unavailable'); tx.append(event);
    } }));
    assert.throws(() => core.stopAll({ reason: 'owner-stop-during-disk-failure' }), errorCode('journal_unavailable'));
    journal.transaction = original;
    context.beforeAction(witness(value)); adapter.calls.dispatch++; return outgoing(value, attempt);
  };
  const result = await dispatch(core, ticket);
  assert.equal(result.status, 'outcome_unknown'); assert.equal(result.attempt.reason_code, 'operator_stopped');
  assert.equal(adapter.calls.dispatch, 0); assert.equal(core.health().stop.stopped, true);
  assert.equal(journal.transaction(tx => tx.get('control', 'state')).stopped, true);
});

test('a retained action callback expires when dispatch exits, even when the result commit also fails', async t => {
  const { core, adapter, journal } = setup(t), ticket = prepared(core), original = journal.transaction.bind(journal);
  let retainedPermit;
  adapter.dispatchNotification = async (value, attempt, context) => { retainedPermit = context.beforeAction; throw new Error('abandoned-adapter-call'); };
  journal.transaction = action => original(tx => action({ ...tx, append(event) {
    if (event.type === 'dispatch_outcome') throw new DesktopError('journal_unavailable'); tx.append(event);
  } }));
  await assert.rejects(dispatch(core, ticket), errorCode('journal_unavailable'));
  journal.transaction = original;
  assert.throws(() => retainedPermit(witness(ticket)), errorCode('action_permit_expired'));
  assert.equal(journal.events().some(event => event.type === 'dispatch_action_boundary'), false);
});

test('reconciliation can update the same attempt from previously synchronized UNKNOWN to observed outgoing', async t => {
  const { core, adapter } = setup(t), ticket = prepared(core);
  adapter.dispatchNotification = async () => { throw new Error('uncertain'); };
  const result = await dispatch(core, ticket), args = { attempt_id: result.attempt.id, executor_id: 'ui-writer' };
  assert.equal((await core.writeAdminOutcome(args)).sync.outcome, 'OUTCOME_UNKNOWN');
  assert.equal((await core.reconcileAttempt(args)).status, 'outgoing_observed');
  assert.equal(core.health().admin_sync_pending, 1);
  assert.equal((await core.writeAdminOutcome(args)).sync.outcome, 'OUTGOING_OBSERVED');
  assert.equal(core.health().admin_sync_pending, 0); assert.equal(adapter.calls.write, 2);
  assert.equal((await dispatch(core, ticket)).status, 'already_attempted');
});

test('real crash residue requires Stop, an exact expired fence, and independently verified executor quiescence before read-only reconciliation', async t => {
  const { core, journal, adapter, path } = setup(t), ticket = prepared(core), original = journal.transaction.bind(journal);
  adapter.dispatchNotification = async () => { throw new Error('crash-before-result'); };
  journal.transaction = action => original(tx => action({ ...tx, append(event) {
    if (event.type === 'dispatch_outcome') throw new DesktopError('journal_unavailable'); tx.append(event);
  } }));
  await assert.rejects(dispatch(core, ticket), errorCode('journal_unavailable')); journal.transaction = original;
  const state = journal.transaction(tx => tx.get('control', 'state')), attempt = journal.transaction(tx => tx.get('attempts', ticket.operation_key));
  const time = CLOCK + 61_000, restartedAdapter = mockAdapter(() => time);
  const restarted = new DirectDesktopCore({ journal: new SqliteDesktopJournal(path), policy: fixturePolicy(), adapter: restartedAdapter, now: () => time });
  t.after(() => restarted.close());
  const args = { attempt_id: attempt.id, executor_id: 'recovery-reviewer', recovery: {
    lease_token: state.lease.token, lease_fence: state.lease.fence, owner_review_ref: 'synthetic:owner-reviewed-executor-exit' } };
  assert.equal((await restarted.reconcileAttempt(args)).reason_code, 'recovery_requires_stop');
  restarted.stopAll({ reason: 'explicit-recovery-stop' });
  assert.equal((await restarted.reconcileAttempt(args)).reason_code, 'executor_quiescence_unverified');
  restarted.quiescenceVerifier = async lease => ({ status: 'quiescent', lease_token: lease.token, lease_fence: lease.fence,
    executor_id: lease.owner, evidence_label: 'mock', evidence_refs: ['synthetic:executor-exit-observed'] });
  assert.equal((await restarted.reconcileAttempt({ ...args, recovery: { ...args.recovery, lease_fence: 999 } })).reason_code, 'lease_fence_invalid');
  assert.equal((await restarted.reconcileAttempt(args)).status, 'outgoing_observed');
  assert.equal(restarted.health().stop.stopped, true); assert.equal(restarted.health().lease, null);
  assert.equal(restarted.journal.events().some(event => event.type === 'lease_recovered' && event.payload.new_fence > state.lease.fence), true);
  assert.equal((await dispatch(restarted, ticket)).status, 'already_attempted');
  assert.equal(restartedAdapter.calls.dispatch, 0);
});

const mutations = [
  input => { input.source.payment_state = 'pending'; }, input => { input.source.extra = 'untrusted-command'; },
  input => { input.recipient.single_recipient = false; }, input => { input.recipient.destination_e164 = '0780000000'; },
  input => { input.recipient.country_context = ''; }, input => { input.message.source_derived = false; },
  input => { input.checks.previous_attempt_checked = false; }, input => { input.checks.consent_or_authority_visible = false; },
  input => { input.source.observed_at = '2026-02-30T00:00:00Z'; }, input => { input.message.body += 'unsafe'; },
];
for (let index = 0; index < 100; index++) test(`synthetic invalid source/recipient/content case ${index + 1} cannot prepare or reach an adapter`, () => {
  const adapter = mockAdapter(), core = new DirectDesktopCore({ journal: new MemoryDesktopJournal(), adapter, now: () => CLOCK });
  const input = fixtureInput(`SYNTHETIC-INVALID-${index}`); mutations[index % mutations.length](input);
  assert.throws(() => core.prepareNotification(input), error => error instanceof DesktopError);
  assert.equal(core.health().attempts, 0); assert.equal(adapter.calls.preflight + adapter.calls.dispatch, 0); core.close();
});
