import {HASH, UUID, hash, integer, keys, need, timestamp, uuid} from './wire_values.mjs';

export const ACTIONS = Object.freeze([
  'list_pending', 'claim', 'get_claimed', 'confirm',
  'record_send_start', 'record_outcome', 'release_claim', 'get_operation',
]);
export const WRITES = new Set(['claim', 'confirm', 'record_send_start', 'record_outcome', 'release_claim']);

export const REQUESTS = Object.freeze({
  list_pending: {required: [], optional: ['limit', 'after_created_at', 'after_job_id']},
  claim: {required: ['job_id', 'request_id', 'worker_id', 'expected_fence'], optional: []},
  get_claimed: {required: ['job_id', 'claim_token', 'fence_version'], optional: []},
  confirm: {required: [
    'job_id', 'claim_token', 'fence_version', 'request_id', 'confirmation_id',
    'body_sha256', 'destination_sha256', 'destination_revision', 'user_confirmation',
  ], optional: []},
  record_send_start: {required: ['job_id', 'claim_token', 'fence_version', 'request_id', 'confirmation_id'], optional: []},
  record_outcome: {required: ['attempt_id', 'request_id', 'observation', 'evidence_reference_sha256'], optional: []},
  release_claim: {required: ['job_id', 'claim_token', 'fence_version', 'request_id'], optional: []},
  get_operation: {required: ['request_id'], optional: []},
});

export const observations = Object.freeze(['observed_sent', 'failed_no_send', 'uncertain']);
export const workerIdPattern = /^[A-Za-z0-9._:-]{3,80}$/;

export function workerId(value) {
  need(typeof value === 'string' && workerIdPattern.test(value), 'invalid_worker');
}

export const uuidSchema = {type: 'string', pattern: UUID.source};
export const digestSchema = {type: 'string', pattern: HASH.source};
const uuidField = {schema: uuidSchema, validate: uuid};
const digestField = {schema: digestSchema, validate: hash};

function integerField(minimum, maximum) {
  return {schema: {type: 'integer', minimum, maximum}, validate: value => integer(value, minimum, maximum)};
}

const versionField = integerField(1, 999999998);
const fields = {
  job_id: uuidField,
  request_id: uuidField,
  claim_token: uuidField,
  confirmation_id: uuidField,
  attempt_id: uuidField,
  after_job_id: uuidField,
  body_sha256: digestField,
  destination_sha256: digestField,
  evidence_reference_sha256: digestField,
  expected_fence: integerField(0, 999999997),
  fence_version: versionField,
  destination_revision: versionField,
  limit: integerField(1, 50),
  worker_id: {schema: {type: 'string', pattern: workerIdPattern.source}, validate: workerId},
  after_created_at: {schema: {type: 'string', format: 'date-time'}, validate: timestamp},
  user_confirmation: {schema: {const: true}, validate: value => need(value === true, 'explicit_confirmation_required')},
  observation: {schema: {enum: observations}, validate: value => need(observations.includes(value), 'invalid_observation')},
};

export function fieldSchema(name) {
  return fields[name].schema;
}

export function request(action, input) {
  need(ACTIONS.includes(action), 'unsupported_action');
  const spec = REQUESTS[action];
  keys(input, spec.required, spec.optional);
  for (const [name, value] of Object.entries(input)) fields[name].validate(value);
  need(Object.hasOwn(input, 'after_created_at') === Object.hasOwn(input, 'after_job_id'), 'incomplete_cursor');
  need(Buffer.byteLength(JSON.stringify({action, ...input})) <= 4096, 'request_too_large');
  return structuredClone(input);
}
