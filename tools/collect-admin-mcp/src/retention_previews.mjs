import {
  assertBinding, canonical, digest, inspectInput, parseClaim, parseInspection, parsePlan, retentionBlocked, supportedTask,
} from './retention_contract.mjs';

const CLAIM_LEASE_SECONDS = 120;
const secondsNow = () => Math.floor(Date.now() / 1000);

export async function readRetentionPlan(session, planId, requireCurrent = false) {
  const plan = parsePlan(await session.read('status', {p_plan_id: planId}), planId);
  if (requireCurrent && !plan.policy_current) retentionBlocked('retention_approval_stale');
  return plan;
}

export async function readAvailableScope(session, input) {
  const scope = parseInspection(await session.read('inspect', input), input);
  if (scope.active_hold_count || scope.in_flight_unresolved) retentionBlocked('retention_obligations_unresolved');
  return scope;
}

export function selectRetentionTask(plan, taskId) {
  const task = plan.tasks.find(row => row.task_id === taskId);
  if (!task || task.state === 'verified' || !supportedTask(task)) retentionBlocked('retention_adapter_unavailable');
  return task;
}

export function planExpectation(plan, task = null) {
  return {
    plan_id: plan.plan_id,
    request_id: plan.request_id,
    source_id: plan.source_id,
    policy_sha256: plan.policy_sha256,
    schema_sha256: plan.schema_sha256,
    scope_snapshot_sha256: plan.scope_snapshot_sha256,
    task,
  };
}

export function reconcileExpectation(plan) {
  return {...planExpectation(plan), tasks_sha256: digest(plan.tasks), revision: plan.revision};
}

function originalPlanExpectation(saved) {
  const {claim, claim_operation, resume_from_operation, source_currentness, ...expected} = saved;
  return expected;
}

export function assertPreviewMatches(currentValue, savedValue) {
  if (canonical(currentValue) !== canonical(savedValue)) retentionBlocked('retention_preview_stale');
}

export function observedRetentionClaim(record) {
  if (record.preview.kind !== 'claim' || record.state !== 'observed') retentionBlocked('retention_claim_unresolved');
  return parseClaim(record.receipt, record.preview.input);
}

export function assertCurrentClaim(task, claim, input) {
  if (task.state !== 'claimed' || task.fence !== input.p_fence || claim.claim_id !== input.p_claim_id ||
      claim.expires_seconds <= secondsNow()) retentionBlocked('retention_lease_expired');
}

function assertLeaseReady(journal, plan, task) {
  const records = journal.list().filter(row => row.preview.kind === 'claim' && row.state === 'observed');
  const now = secondsNow();
  for (const record of records) {
    if (record.preview.input.p_plan_id !== plan.plan_id) continue;
    const claim = observedRetentionClaim(record);
    if (claim.expires_seconds > now && plan.tasks.some(current => current.task_id === claim.task_id &&
      current.state === 'claimed' && current.fence === claim.fence)) retentionBlocked('retention_lease_active');
  }

  if (task.state !== 'claimed') return;
  const known = records.find(row => row.preview.input.p_task_id === task.task_id && row.receipt?.fence === task.fence);
  if (!known || observedRetentionClaim(known).expires_seconds > now) retentionBlocked('retention_lease_unobserved');
}

function assertResumeSource(journal, session, operationId, plan, task) {
  const original = journal.operation(operationId);
  const saved = original.preview;
  if (saved.kind !== 'execute' || original.dispatches < 1 ||
    !['dispatching', 'unknown', 'observed'].includes(original.state) ||
    (original.state === 'observed' && original.receipt?.verified !== false)) {
    retentionBlocked('retention_resume_unavailable');
  }
  assertBinding(session.binding, saved.binding);
  const previous = journal.operation(saved.expected.claim_operation);
  if (previous.preview.kind !== 'claim' || previous.state !== 'observed') retentionBlocked('retention_claim_unresolved');
  assertBinding(session.binding, previous.preview.binding);
  const claim = parseClaim(previous.receipt, previous.preview.input);
  assertPreviewMatches(planExpectation(plan), {...originalPlanExpectation(saved.expected), task: null});
  if (task.task_id !== claim.task_id || task.class_name !== saved.expected.task.class_name ||
      task.action !== saved.expected.task.action || task.fence !== claim.fence ||
      saved.input.p_claim_id !== claim.claim_id || saved.input.p_fence !== claim.fence) {
    retentionBlocked('retention_resume_changed');
  }
  const completedPartial = original.state === 'observed' && original.receipt.verified === false && task.state === 'blocked';
  if (!completedPartial && claim.expires_seconds > secondsNow()) retentionBlocked('retention_lease_active');
}

function resumeExpectation(operationId) {
  return operationId ? {resume_from_operation: operationId, source_currentness: 'requires_execution_recheck'} : {};
}

export async function prepareClaimPreview(journal, session, operationId, planId, taskId, previousExecution) {
  const plan = await readRetentionPlan(session, planId, !previousExecution);
  const task = selectRetentionTask(plan, taskId);
  // A previous ambiguous or partial execution remains reserved. Its next
  // explicit claim still binds the proven prior lease and server fence.
  if (previousExecution) assertResumeSource(journal, session, previousExecution, plan, task);
  assertLeaseReady(journal, plan, task);
  return {
    input: {
      p_operation_id: operationId, p_plan_id: planId, p_task_id: taskId,
      p_expected_task_revision: task.revision, p_lease_seconds: CLAIM_LEASE_SECONDS,
    },
    expected: {...planExpectation(plan, task), ...resumeExpectation(previousExecution)},
  };
}

export async function prepareExecutionPreview(session, operationId, record, claim) {
  assertBinding(session.binding, record.preview.binding);
  const previousExecution = record.preview.expected.resume_from_operation;
  const plan = await readRetentionPlan(session, record.preview.input.p_plan_id, !previousExecution);
  const task = selectRetentionTask(plan, claim.task_id);
  const input = {p_operation_id: operationId, p_claim_id: claim.claim_id, p_fence: claim.fence};
  assertCurrentClaim(task, claim, input);
  const expected = {...planExpectation(plan, task), ...resumeExpectation(previousExecution)};
  assertPreviewMatches({...expected, task: null}, {...record.preview.expected, task: null});
  return {input, expected: {...expected, claim, claim_operation: record.preview.operation_id}};
}

export async function revalidateRetentionPreview(journal, session, preview) {
  assertBinding(session.binding, preview.binding);
  const {kind, input, expected} = preview;
  if (kind === 'plan') {
    const inspection = inspectInput(input.p_request_id, input.p_expected_review_revision, input.p_expected_source_id);
    assertPreviewMatches(await readAvailableScope(session, inspection), expected);
    return;
  }

  const plan = await readRetentionPlan(session, expected.plan_id, !expected.resume_from_operation);
  if (kind === 'reconcile') {
    assertPreviewMatches(reconcileExpectation(plan), expected);
    return;
  }

  const task = selectRetentionTask(plan, expected.task.task_id);
  assertPreviewMatches(planExpectation(plan, task), originalPlanExpectation(expected));
  if (kind === 'claim') {
    if (expected.resume_from_operation) assertResumeSource(journal, session, expected.resume_from_operation, plan, task);
    assertLeaseReady(journal, plan, task);
    return;
  }

  const original = journal.operation(expected.claim_operation);
  assertBinding(session.binding, original.preview.binding);
  assertPreviewMatches(observedRetentionClaim(original), expected.claim);
  assertCurrentClaim(task, expected.claim, input);
}
