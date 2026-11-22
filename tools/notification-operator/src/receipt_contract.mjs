import {hash, integer, keys, need, plain, sha, timestamp, uuid} from './wire_values.mjs';
import {ACTIONS, observations, workerId} from './request_contract.mjs';

export const MARKER = Object.freeze({
  contract_version: 1,
  scope: 'assisted_sms_internal_record',
  delivery_confirmed: false,
  provider_confirmation: false,
  settlement_status: 'not_asserted',
});

const markerKeys = Object.keys(MARKER);
const claimKeys = ['job_id', 'claim_token', 'fence_version'];
const receiptFields = {
  list_pending: ['items', 'next_cursor'],
  claim: [...claimKeys, 'worker_id', 'claim_expires_at', 'originating_session_id', 'public_session_id'],
  get_claimed: [...claimKeys, 'destination_e164', 'destination_sha256', 'destination_revision',
    'message_body', 'body_sha256', 'payment_id', 'template_key', 'claim_expires_at'],
  confirm: [...claimKeys, 'confirmation_id', 'body_sha256', 'destination_sha256',
    'destination_revision', 'expires_at', 'originating_session_id', 'public_session_id'],
  record_send_start: [...claimKeys, 'attempt_id', 'confirmation_id', 'state', 'originating_session_id', 'public_session_id'],
  record_outcome: ['attempt_id', 'observation', 'evidence_reference_sha256', 'may_send'],
  release_claim: ['job_id', 'state', 'fence_version'],
  get_operation: ['request_id', 'observed', 'receipt', 'may_send'],
};
const fieldGroups = [
  [uuid, ['job_id', 'claim_token', 'confirmation_id', 'attempt_id', 'payment_id', 'originating_session_id', 'public_session_id', 'request_id']],
  [hash, ['body_sha256', 'destination_sha256', 'evidence_reference_sha256']],
  [integer, ['fence_version', 'destination_revision']],
  [timestamp, ['claim_expires_at', 'expires_at']],
];

function validatePending(value) {
  need(Array.isArray(value.items) && value.items.length <= 50, 'invalid_pending');
  for (const item of value.items) {
    keys(item, ['id', 'payment_id', 'state', 'created_at', 'fence', 'attempt_id']);
    uuid(item.id);
    uuid(item.payment_id);
    timestamp(item.created_at);
    integer(item.fence, 0);
    need(['queued', 'claimed', 'send_started', 'uncertain'].includes(item.state), 'invalid_pending_state');
    if (item.attempt_id !== null) uuid(item.attempt_id);
  }
  need(new Set(value.items.map(item => item.id)).size === value.items.length, 'duplicate_pending_job');
  if (value.next_cursor !== null) {
    keys(value.next_cursor, ['after_created_at', 'after_job_id']);
    timestamp(value.next_cursor.after_created_at);
    uuid(value.next_cursor.after_job_id);
  }
}

function validateClaimed(value) {
  need(typeof value.destination_e164 === 'string' && /^\+2507[2389][0-9]{7}$/.test(value.destination_e164), 'invalid_destination');
  need(typeof value.message_body === 'string' && value.message_body.length > 0 &&
    Buffer.byteLength(value.message_body) <= 4096 && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value.message_body), 'invalid_message');
  need(sha(value.message_body) === value.body_sha256 && sha(value.destination_e164) === value.destination_sha256, 'content_digest_mismatch');
  need(typeof value.template_key === 'string' && /^[A-Za-z0-9._:-]{1,100}$/.test(value.template_key), 'invalid_template');
}

function validateStart(value, stored) {
  need(value.state === 'send_started', 'invalid_start_state');
  if (stored) return;
  need(typeof value.may_send === 'boolean' && typeof value.acknowledgement === 'string' &&
    /^[a-z_]{1,100}$/.test(value.acknowledgement), 'invalid_start_ack');
  need(!value.may_send || (value.replay === false && value.acknowledgement === 'first_committed_response_only'), 'reissued_permit_refused');
}

const validate = {
  list_pending: validatePending,
  claim: value => workerId(value.worker_id),
  get_claimed: validateClaimed,
  record_send_start: validateStart,
  record_outcome: value => need(value.may_send === false && observations.includes(value.observation), 'invalid_outcome'),
  release_claim: value => need(value.state === 'queued', 'invalid_release_state'),
  get_operation: value => need(typeof value.observed === 'boolean' && value.may_send === false &&
    (value.observed ? plain(value.receipt) : value.receipt === null), 'invalid_operation_receipt'),
};

export function receipt(action, value, {stored = false} = {}) {
  need(ACTIONS.includes(action), 'unsupported_action');
  need(plain(value), 'invalid_receipt');
  for (const [key, expected] of Object.entries(MARKER)) need(value[key] === expected, 'wrong_semantic_marker');

  const acknowledgment = action === 'record_send_start' && !stored ? ['replay', 'may_send', 'acknowledgement'] : [];
  keys(value, [...markerKeys, ...receiptFields[action], ...acknowledgment], ['replay']);
  for (const [parse, names] of fieldGroups) {
    for (const name of names) if (Object.hasOwn(value, name)) parse(value[name]);
  }
  if (Object.hasOwn(value, 'replay')) need(typeof value.replay === 'boolean', 'invalid_replay');
  validate[action]?.(value, stored);
  return structuredClone(value);
}

const privateFields = new Set(['destination_e164', 'message_body', 'manual_handoff']);
export function sanitized(value) {
  if (Array.isArray(value)) return value.map(sanitized);
  if (!plain(value)) return value;
  return Object.fromEntries(Object.entries(value)
    .filter(([name]) => !privateFields.has(name))
    .map(([name, item]) => [name, name === 'may_send' ? false : sanitized(item)]));
}
