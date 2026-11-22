import {OperatorError, canonical, need, receipt, same, sha} from './contract.mjs';

export function withoutSendPermit(value) {
  return {...value, replay: true, may_send: false, acknowledgement: 'client_receipt_permit_not_reissued'};
}

export function retainedReceipt(action, value) {
  if (action === 'record_send_start') {
    const {may_send, acknowledgement, replay, ...stored} = value;
    receipt(action, stored, {stored: true});
    return withoutSendPermit(stored);
  }
  return {...receipt(action, value), replay: true};
}

export function recoveredReceipt(value) {
  if (value?.state === 'send_started') return retainedReceipt('record_send_start', value);
  if (Object.hasOwn(value ?? {}, 'worker_id')) return receipt('claim', value);
  if (Object.hasOwn(value ?? {}, 'confirmation_id')) return receipt('confirm', value);
  if (Object.hasOwn(value ?? {}, 'observation')) return receipt('record_outcome', value);
  if (value?.state === 'queued') return receipt('release_claim', value);
  throw new OperatorError('unknown_operation_receipt');
}

export function requireOriginalAuthority(record, before) {
  need(record.intent.operator_session === before.user.sessionId &&
    record.intent.authority_sha256 === sha(before.authority), 'original_operation_authority_required');
}

export function requireOriginalRequest(record, action, args, before) {
  const {intent} = record;
  need(intent.action === action && intent.args_sha256 === sha(canonical(args)) &&
    same(intent.args, args), 'original_operation_payload_required');
  requireOriginalAuthority(record, before);
}
