import {need} from './contract.mjs';

const RECEIPT_FIELDS = [
  'job_id', 'claim_token', 'confirmation_id', 'attempt_id', 'body_sha256', 'destination_sha256',
  'destination_revision', 'worker_id', 'observation', 'evidence_reference_sha256',
];
const CONTENT_FIELDS = ['body_sha256', 'destination_sha256', 'destination_revision'];
const CLAIMED_ACTIONS = new Set(['get_claimed', 'confirm', 'record_send_start', 'release_claim']);
const SESSION_RECEIPTS = new Set(['claim', 'confirm', 'record_send_start']);
const HANDOFF_INSTRUCTION = 'Use supported Mac Computer Use to inspect Messages. Only with the recorded explicit authorization for this exact recipient and text, send once before valid_until. Inspect the exact conversation after the action. Record observed_sent only for an observed send action; uncertainty remains uncertain. Clipboard, composer population, handoff and this permit are not send or delivery proof.';

export class OperatorCustody {
  #clock;
  #epoch = null;
  #authority = null;
  #originSession = null;
  #claims = new Map();
  #contents = new Map();
  #confirmations = new Map();

  constructor(clock) {
    this.#clock = clock;
  }

  synchronize(before) {
    if (this.#epoch === before.epoch && this.#authority === before.authority) return;
    this.#claims.clear();
    this.#contents.clear();
    this.#confirmations.clear();
    this.#originSession = null;
    this.#epoch = before.epoch;
    this.#authority = before.authority;
  }

  #live(value, expiry) {
    need(value && Date.parse(value[expiry]) > this.#clock(), 'current_unexpired_claim_required');
    return value;
  }

  prepare(action, args, before) {
    if (CLAIMED_ACTIONS.has(action)) {
      const claim = this.#live(this.#claims.get(args.job_id), 'claim_expires_at');
      need(claim.claim_token === args.claim_token && claim.fence_version === args.fence_version, 'original_claim_required');
    }

    if (action === 'confirm') {
      const content = this.#live(this.#contents.get(args.job_id), 'claim_expires_at');
      need(CONTENT_FIELDS.every(key => content[key] === args[key]), 'review_exact_content_before_confirmation');
    }

    if (action !== 'record_send_start') return null;
    const confirmation = this.#live(this.#confirmations.get(args.job_id), 'expires_at');
    const content = this.#live(this.#contents.get(args.job_id), 'claim_expires_at');
    need(confirmation.confirmation_id === args.confirmation_id, 'original_confirmation_required');
    need(CONTENT_FIELDS.every(key => content[key] === confirmation[key]), 'confirmed_content_changed');

    // The original proof caps this attempt even if another verification occurs.
    const expiresAt = Math.min(
      Date.parse(content.claim_expires_at),
      Date.parse(confirmation.expires_at),
      Date.parse(before.user.expiresAt),
      Date.parse(before.emailVerifiedAt) + 300000,
    );
    return {content, expiresAt};
  }

  match(action, value, args, before) {
    for (const field of RECEIPT_FIELDS) {
      if (Object.hasOwn(args, field) && !(action === 'release_claim' && field === 'claim_token')) {
        need(value[field] === args[field], 'operation_receipt_mismatch');
      }
    }
    if (Object.hasOwn(args, 'fence_version')) {
      const increment = action === 'release_claim' ? 1 : 0;
      need(value.fence_version === args.fence_version + increment, 'operation_fence_mismatch');
    }
    if (action === 'claim') need(value.fence_version === args.expected_fence + 1, 'claim_fence_mismatch');

    if (SESSION_RECEIPTS.has(action)) {
      need(value.public_session_id === before.user.sessionId, 'original_public_session_required');
      need(this.#originSession === null || value.originating_session_id === this.#originSession, 'original_server_session_required');
      this.#originSession = value.originating_session_id;
    }
    if (action === 'get_claimed') {
      need(value.claim_expires_at === this.#claims.get(args.job_id).claim_expires_at, 'claim_expiry_mismatch');
    }
  }

  requireLiveReceipt(action, value) {
    if (action === 'claim') this.#live(value, 'claim_expires_at');
    if (action === 'confirm') this.#live(value, 'expires_at');
  }

  adopt(action, value) {
    // Returned DTOs and the stored authority state have independent references.
    if (action === 'claim') this.#claims.set(value.job_id, structuredClone(value));
    if (action === 'get_claimed') this.#contents.set(value.job_id, structuredClone(value));
    if (action === 'confirm') this.#confirmations.set(value.job_id, structuredClone(value));
    if (action === 'record_send_start' || action === 'release_claim') {
      this.#claims.delete(value.job_id);
      this.#contents.delete(value.job_id);
      this.#confirmations.delete(value.job_id);
    }
  }

  handoff(value, {content, expiresAt}, operatorSession, authorizationDigest, signal) {
    need(!signal?.aborted, 'request_cancelled');
    this.#live(content, 'claim_expires_at');
    need(expiresAt > this.#clock(), 'handoff_expired');
    return {
      ...value,
      manual_handoff: {
        mode: 'manual_mac_messages',
        authorization_reference_sha256: authorizationDigest,
        operator_session: operatorSession,
        originating_session_id: value.originating_session_id,
        attempt_id: value.attempt_id,
        confirmation_id: value.confirmation_id,
        destination_e164: content.destination_e164,
        message_body: content.message_body,
        destination_sha256: content.destination_sha256,
        body_sha256: content.body_sha256,
        valid_until: new Date(expiresAt).toISOString(),
        one_use: true,
        delivery_confirmed: false,
        provider_confirmation: false,
        settlement_status: 'not_asserted',
        instruction: HANDOFF_INSTRUCTION,
      },
    };
  }
}
