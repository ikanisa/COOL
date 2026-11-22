import {randomUUID} from 'node:crypto';
import {SafeError, invalid} from './config.mjs';
import {
  assertBinding, hasUnresolvedRetentionOperation, inspectInput, isRetentionHash, isRetentionUuid,
  isUnconfirmedRetentionState, parseContext, parseInspection, retentionBlocked, supportedTask,
} from './retention_contract.mjs';
import {
  observedRetentionClaim, prepareClaimPreview, prepareExecutionPreview, readAvailableScope,
  readRetentionPlan, reconcileExpectation, revalidateRetentionPreview,
} from './retention_previews.mjs';
import {displayRecord, parseRetentionDispatch, readOriginalReceipt} from './retention_receipts.mjs';

export {displayRecord} from './retention_receipts.mjs';

function requireUuid(value) {
  if (!isRetentionUuid(value)) invalid();
  return value;
}

export class RetentionOperator {
  constructor(api, journal) {
    this.api = api;
    this.journal = journal;
  }

  async context() {
    return this.api.withSession(async session => parseContext(await session.read('context')));
  }

  async inspect(request, revision, source) {
    const input = inspectInput(request, revision, source);
    return this.api.withSession(async session => parseInspection(await session.read('inspect', input), input));
  }

  async status(planId) {
    requireUuid(planId);
    return this.api.withSession(async session => {
      const value = await readRetentionPlan(session, planId);
      const supported = [], unsupported = [];
      for (const task of value.tasks) (supportedTask(task) ? supported : unsupported).push(task.task_id);
      return {...value, supported_tasks: supported, unsupported_tasks: unsupported};
    });
  }

  #assertScopeAvailable(kind, input) {
    if (hasUnresolvedRetentionOperation(this.journal.list(), kind, input)) {
      retentionBlocked('retention_original_operation_unresolved');
    }
  }

  async #prepare(kind, build) {
    const operation = randomUUID();
    const preview = await this.api.withSession(async session => {
      const {input, expected} = await build(session, operation);
      return {
        contract_version: 1, scope: 'approved_eligible_data_disposition', kind, operation_id: operation,
        binding: session.binding, input, expected, created_at: new Date().toISOString(),
      };
    });
    return displayRecord(this.journal.save(preview));
  }

  async previewPlan(request, revision, source, policy) {
    const inspection = inspectInput(request, revision, source);
    if (!isRetentionHash(policy)) invalid();
    this.#assertScopeAvailable('plan', inspection);
    return this.#prepare('plan', async (session, operation) => {
      const context = parseContext(await session.read('context'));
      if (context.source_id !== source) retentionBlocked('retention_source_changed');
      const expected = await readAvailableScope(session, inspection);
      return {input: {...inspection, p_policy_sha256: policy, p_operation_id: operation}, expected};
    });
  }

  async previewClaim(planId, taskId) {
    requireUuid(planId);
    requireUuid(taskId);
    this.#assertScopeAvailable('claim', {p_plan_id: planId});
    return this.#prepare('claim', (session, operation) =>
      prepareClaimPreview(this.journal, session, operation, planId, taskId));
  }

  async previewResumeClaim(executeOperation) {
    const original = this.journal.operation(requireUuid(executeOperation));
    const planId = original.preview.expected.plan_id;
    if (original.preview.kind !== 'execute' || !isRetentionUuid(planId)) retentionBlocked('retention_resume_unavailable');
    this.#assertScopeAvailable('claim', {p_plan_id: planId});
    return this.#prepare('claim', (session, operation) =>
      prepareClaimPreview(this.journal, session, operation, planId, original.preview.expected.task.task_id, executeOperation));
  }

  async previewExecute(claimOperation) {
    const record = this.journal.operation(requireUuid(claimOperation));
    const claim = observedRetentionClaim(record);
    this.#assertScopeAvailable('execute', {p_claim_id: claim.claim_id});
    return this.#prepare('execute', (session, operation) =>
      prepareExecutionPreview(session, operation, record, claim));
  }

  async previewReconcile(planId) {
    requireUuid(planId);
    return this.#prepare('reconcile', async session => {
      const plan = await readRetentionPlan(session, planId, true);
      return {input: {p_plan_id: planId}, expected: reconcileExpectation(plan)};
    });
  }

  async apply(hash, confirm, {retry = false} = {}) {
    const record = this.journal.get(hash);
    const {preview} = record;
    if (typeof confirm !== 'function' || (!retry && record.state !== 'prepared') ||
        (retry && (!isUnconfirmedRetentionState(record.state) || preview.kind === 'reconcile'))) {
      retentionBlocked('retention_confirmation_required');
    }
    const phrase = (retry ? 'RETRY ' : 'APPLY ') + hash;
    if (await confirm(displayRecord(record), phrase) !== phrase) {
      throw new SafeError('cancelled', 'Confirmation did not match. No retention action was dispatched.');
    }

    let dispatched;
    try {
      const result = await this.api.withSession(async session => {
        assertBinding(session.binding, preview.binding);
        // Recover the immutable receipt before considering a repeat. An
        // explicit retry can only reuse the saved UUID and exact request.
        if (retry) {
          const recovered = await readOriginalReceipt(session, preview);
          if (recovered.observed) return recovered.receipt;
        }
        await revalidateRetentionPreview(this.journal, session, preview);
        dispatched = this.journal.begin(hash, {retry, expectedDispatches: record.dispatches});
        return parseRetentionDispatch(await session.write(preview.kind, preview.input), preview);
      });
      if (dispatched) this.journal.finish(hash, dispatched.dispatches, 'observed', result);
      else this.journal.observe(hash, {checked_at: new Date().toISOString(), observed: true}, {receipt: result, committed: true});
      return displayRecord(this.journal.get(hash));
    } catch (error) {
      if (!dispatched) throw error;
      try {
        this.journal.finish(hash, dispatched.dispatches, 'unknown', null);
      } catch {
        // Durable dispatch marker remains if completion persistence fails.
      }
      throw new SafeError('retention_outcome_unknown',
        `The original ${preview.kind} outcome is unconfirmed. Preserve operation ${preview.operation_id}. Run recover with that reference; no automatic retry occurred.`);
    }
  }

  async recover(operationId) {
    const record = this.journal.operation(requireUuid(operationId));
    const {preview} = record;
    if (record.dispatches < 1) retentionBlocked('retention_not_dispatched');
    const reconcile = preview.kind === 'reconcile';
    const result = await this.api.withSession(async session => {
      assertBinding(session.binding, preview.binding);
      if (reconcile) return {observed: false, receipt: await readRetentionPlan(session, preview.input.p_plan_id)};
      return readOriginalReceipt(session, preview);
    });
    // Reconcile lacks an immutable receipt endpoint. A current status read
    // adds evidence while the original call remains unresolved.
    const observation = {
      checked_at: new Date().toISOString(),
      observed: result.observed,
      ...(reconcile ? {current_plan: result.receipt, currentness_not_asserted: true} : {}),
    };
    return displayRecord(this.journal.observe(record.preview_sha256, observation, {
      receipt: reconcile ? null : result.receipt,
      committed: result.observed,
    }));
  }

  list() {
    return this.journal.list().map(row => ({
      operation_id: row.preview.operation_id, preview_sha256: row.preview_sha256, kind: row.preview.kind,
      state: row.state, dispatches: row.dispatches, created_at: row.preview.created_at,
    }));
  }

  show(hash) { return displayRecord(this.journal.get(hash)); }
  cancel(hash) { return displayRecord(this.journal.cancel(hash)); }
}
