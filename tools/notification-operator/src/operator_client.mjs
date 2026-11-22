import {ACTIONS, WRITES, OperatorError, need, keys, uuid, hash, request, receipt, hasFreshEmailVerification} from './contract.mjs';
import {OperatorCustody} from './operator_custody.mjs';
import {recoveredReceipt, requireOriginalAuthority, requireOriginalRequest, retainedReceipt, withoutSendPermit} from './operator_receipts.mjs';

function localInput(action, input) {
  need(ACTIONS.includes(action), 'unsupported_action');
  need(input && typeof input === 'object', 'invalid_input');
  const {operator_session, resume_original_request, manual_authorization, ...untrustedArgs} = input;
  uuid(operator_session);
  need(resume_original_request === undefined || WRITES.has(action) &&
    typeof resume_original_request === 'boolean', 'unsupported_resume');

  let authorizationDigest = null;
  if (action === 'record_send_start') {
    keys(manual_authorization, ['user_authorized', 'authorization_reference_sha256']);
    need(manual_authorization.user_authorized === true, 'per_message_human_authorization_required');
    authorizationDigest = hash(manual_authorization.authorization_reference_sha256);
  } else {
    need(manual_authorization === undefined, 'unsupported_manual_authorization');
  }
  return {
    operatorSession: operator_session,
    resume: resume_original_request === true,
    authorizationDigest,
    args: request(action, untrustedArgs),
  };
}

export class OperatorClient {
  #http;
  #journal;
  #clock;
  #custody;
  #serial = Promise.resolve();

  constructor({http, journal, clock = Date.now}) {
    this.#http = http;
    this.#journal = journal;
    this.#clock = clock;
    this.#custody = new OperatorCustody(clock);
  }

  metadata() {
    return {
      ...this.#http.metadata(),
      contract_version: 1,
      transport: 'supabase_same_origin_admin_cookie',
      messages_automation: false,
      delivery_confirmed: false,
      provider_confirmation: false,
      settlement_status: 'not_asserted',
    };
  }

  call(action, input, options = {}) {
    const result = this.#serial.then(() => this.#call(action, input, options));
    this.#serial = result.catch(() => {});
    return result;
  }

  #current(before) {
    const current = this.#http.snapshot();
    const now = this.#clock();
    need(current?.epoch === before.epoch && current?.authority === before.authority &&
      current?.emailVerifiedAt === before.emailVerifiedAt, 'session_changed_during_operation');
    need(hasFreshEmailVerification(before, now) && hasFreshEmailVerification(current, now), 'fresh_verified_email_required');
  }

  async #resolve(args, before, signal) {
    const id = args.request_id;
    const record = await this.#journal.load(id);
    const raw = await this.#http.operator('get_operation', args, before, {signal});
    const result = receipt('get_operation', raw);
    need(result.request_id === id, 'operation_receipt_mismatch');
    if (record) {
      requireOriginalAuthority(record, before);
      const expected = {expectedLastSha256: record.last_sha256};
      if (result.observed) {
        const action = record.intent.action;
        const value = retainedReceipt(action, result.receipt);
        this.#custody.match(action, value, record.intent.args, before);
        this.#current(before);
        await this.#journal.append(id, {phase: 'resolved', receipt: value}, expected);
        this.#current(before);
        this.#custody.adopt(action, value);
        result.receipt = value;
      } else {
        need(record.last.phase !== 'resolved', 'recorded_operation_disappeared');
        this.#current(before);
        await this.#journal.append(id, {phase: 'not_observed'}, expected);
      }
    } else if (result.observed) {
      result.receipt = recoveredReceipt(result.receipt);
    }
    this.#current(before);
    return result;
  }

  async #read(action, args, before, signal) {
    this.#custody.prepare(action, args, before);
    const value = receipt(action, await this.#http.operator(action, args, before, {signal}));
    this.#custody.match(action, value, args, before);
    this.#current(before);
    this.#custody.adopt(action, value);
    return value;
  }

  async #recordAttempt(action, args, before, existing) {
    let original = existing;
    if (!original) {
      const started = await this.#journal.begin({action, args, session: before.user.sessionId, authority: before.authority});
      original = started.record;
      if (!started.created) {
        requireOriginalRequest(original, action, args, before);
        throw new OperatorError('resolve_original_operation_before_explicit_retry');
      }
    }

    try {
      // Every attempt is durable before HTTP dispatch. A lost acknowledgement
      // leaves the same operation eligible for resolution by its original ID.
      return await this.#journal.append(args.request_id, {phase: 'unknown'}, {expectedLastSha256: original.last_sha256});
    } catch (error) {
      if (error.code === 'operation_journal_advanced' || error.code === 'EEXIST') {
        throw new OperatorError('resolve_original_operation_before_explicit_retry');
      }
      throw error;
    }
  }

  async #write(action, input, before, signal) {
    const {args, resume, operatorSession, authorizationDigest} = input;
    const id = args.request_id;
    const existing = await this.#journal.load(id);
    if (existing) {
      requireOriginalRequest(existing, action, args, before);
      if (existing.last.phase === 'resolved') {
        this.#current(before);
        return retainedReceipt(action, existing.last.receipt);
      }
      need(existing.last.phase === 'not_observed' && resume, 'resolve_original_operation_before_explicit_retry');
    }

    const handoff = this.#custody.prepare(action, args, before);
    this.#current(before);
    let record = await this.#recordAttempt(action, args, before, existing);
    try {
      need(!signal?.aborted, 'request_cancelled');
      this.#current(before);
      const value = receipt(action, await this.#http.operator(action, args, before, {signal}));
      this.#custody.match(action, value, args, before);
      this.#current(before);
      this.#custody.requireLiveReceipt(action, value);
      const persisted = action === 'record_send_start' ? withoutSendPermit(value) : value;
      record = await this.#journal.append(id, {phase: 'resolved', receipt: persisted}, {expectedLastSha256: record.last_sha256});
      this.#current(before);
      this.#custody.adopt(action, value);
      if (action !== 'record_send_start') return value;
      return value.may_send ? this.#custody.handoff(value, handoff, operatorSession, authorizationDigest, signal) : persisted;
    } catch (error) {
      let recorded = true;
      const errorCode = error instanceof OperatorError ? error.code : 'operation_outcome_unknown';
      try {
        await this.#journal.append(id, {phase: 'unknown', error_code: errorCode}, {expectedLastSha256: record.last_sha256});
      } catch {
        recorded = false;
      }
      const code = recorded ? 'operation_outcome_unknown' : 'operation_outcome_unknown_journal_unavailable';
      throw new OperatorError(code, {unknown: true});
    }
  }

  async #call(action, input, {signal} = {}) {
    const parsed = localInput(action, input);
    need(!signal?.aborted, 'request_cancelled');
    const permission = action === 'list_pending' ? 'assisted_sms.read' : 'assisted_sms.manage';
    const before = await this.#http.ensure(parsed.operatorSession, permission, {signal});
    this.#custody.synchronize(before);
    if (action === 'get_operation') return this.#resolve(parsed.args, before, signal);
    if (WRITES.has(action)) return this.#write(action, parsed, before, signal);
    return this.#read(action, parsed.args, before, signal);
  }
}
