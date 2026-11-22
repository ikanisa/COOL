import {unavailable} from './config.mjs';
import {assertRetentionFields, isRetentionUuid, parseClaim, parseLookup, parseOutcome, parsePlan} from './retention_contract.mjs';

function planReceiptFields(value, input) {
  if (value.request_id !== input.p_request_id || value.policy_sha256 !== input.p_policy_sha256 ||
    value.source_id !== input.p_expected_source_id) unavailable();
}

function planWriteReceipt(value, input) {
  const plan = parsePlan(value);
  planReceiptFields(plan, input);
  return {
    plan_id: plan.plan_id,
    request_id: plan.request_id,
    operation_id: input.p_operation_id,
    policy_sha256: plan.policy_sha256,
    source_id: plan.source_id,
  };
}

function planLookupReceipt(value, input) {
  assertRetentionFields(value, ['operation_id', 'plan_id', 'policy_sha256', 'request_id', 'source_id']);
  if (!isRetentionUuid(value.plan_id) || value.operation_id !== input.p_operation_id) unavailable();
  planReceiptFields(value, input);
  return value;
}

function executionReceipt(value, preview) {
  const result = parseOutcome(value);
  if (result.source_id !== preview.expected.source_id || result.policy_sha256 !== preview.expected.policy_sha256) unavailable();
  return result;
}

export function parseRetentionDispatch(value, preview) {
  switch (preview.kind) {
    case 'plan': return planWriteReceipt(value, preview.input);
    case 'claim': return parseClaim(value, preview.input);
    case 'execute': return executionReceipt(value, preview);
    case 'reconcile': return parsePlan(value, preview.input.p_plan_id);
    default: return unavailable();
  }
}

export async function readOriginalReceipt(session, preview) {
  const lookup = parseLookup(await session.read('lookup', {
    p_operation_kind: preview.kind, p_operation_id: preview.operation_id,
  }), preview.kind, preview.operation_id);
  if (!lookup.observed) return {observed: false, receipt: null};
  const receipt = preview.kind === 'plan' ? planLookupReceipt(lookup.receipt, preview.input) :
    parseRetentionDispatch(lookup.receipt, preview);
  return {observed: true, receipt};
}

export function displayRecord(savedRecord) {
  const record = structuredClone(savedRecord);
  const {binding, ...preview} = record.preview;
  const operator = {origin: binding.origin, account_id: binding.account_id, principal_id: binding.principal_id, role: binding.role};
  return {
    preview_sha256: record.preview_sha256,
    state: record.state,
    dispatches: record.dispatches,
    preview: {...preview, operator},
    receipt: record.receipt,
    observations: record.observations,
    erasure_completed: false,
    all_data_erased: false,
    approval_created: false,
    confirmation: (record.state === 'prepared' ? 'APPLY ' : 'RETRY ') + record.preview_sha256,
  };
}
