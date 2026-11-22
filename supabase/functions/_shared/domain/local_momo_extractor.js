import {exactMinor, validateMomoExtraction, validateProviderProfile} from './momo_pipeline.js';

// This narrowly scoped candidate is not called by the live processing pipeline.
// The template is based on owner-supplied examples, not carrier qualification.
// Matching an SMS or sender never establishes its origin, account ownership,
// settlement, member/group identity, or authority to credit a transaction.
export const LOCAL_MOMO_EXTRACTOR_VERSION = 'collect.momo-local.mtn-received.v1';
export const LOCAL_MOMO_TEMPLATE_ID = 'mtn-received-owner-observed.v1';

const number = String.raw`(?:0|[1-9][0-9]{0,15}|[1-9][0-9]{0,2}(?:,[0-9]{3}){1,5})`;
const name = String.raw`[\p{L}](?:[\p{L}\p{M}' -]{0,118}[\p{L}\p{M}])?`;
const date = String.raw`[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}`;
// Exactly three visible digits; do not infer the rest of the payer's number.
const mask = String.raw`\*{2,64}[0-9]{3}`;
const transactionId = String.raw`[0-9]{4,64}`;
const template = new RegExp(
  String.raw`^(?<incoming>You have received (?<principal>(?<amount>${number}) (?<currency>RWF))) from (?<payer>(?<payerName>${name}) \((?<payerId>${mask})\)) (?<timeEvidence>at (?<time>${date}))\. (?<balanceEvidence>Balance: (?<balance>${number}) RWF)\. (?<transactionEvidence>FT Id: (?<transactionId>${transactionId}))\.(?![\s\S])`,
  'u',
);
// A direction phrase inside the apparent name makes the masked number's role
// unclear. This conservative English filter is not a general role verifier.
const ambiguousName = /(?:^|[^\p{L}\p{M}])(?:to|from|for|via|by|through|behalf|recipient|receiver|beneficiary|payee)(?=$|[^\p{L}\p{M}])/iu;
const unsupported = code => ({status: 'unsupported', code, extraction: null});

/**
 * Extract candidate facts from one complete, owner-shaped MTN receipt.
 *
 * `account` must be the separately bound receiving account, including its
 * approved profile. The pure parser cannot verify that binding or the claimed
 * sender. The observed balance is copied from the message; its wallet scope is
 * unverified here. The returned extraction can independently pass the canonical
 * validator and produce candidate facts. A committing processor must first
 * establish source-to-account binding and preserve all financial safeguards.
 */
export function extractLocalMomo(source, account) {
  if (!source || typeof source !== 'object' || Array.isArray(source) ||
      typeof source.raw_sender !== 'string' || source.raw_sender.length < 1 || source.raw_sender.length > 96 ||
      typeof source.raw_body !== 'string' || source.raw_body.length < 1 || source.raw_body.length > 16384 ||
      source.raw_body.includes('\0') || new TextEncoder().encode(source.raw_body).length > 16384 ||
      source.completeness !== 'complete') return unsupported('invalid_or_incomplete_source');

  if (typeof account?.profile_json !== 'string' || account.profile_json.length > 65536) {
    return unsupported('unverified_or_unsupported_profile');
  }
  const profile = validateProviderProfile(account);
  const admission = profile?.local_momo_extractor;
  if (!profile || account.provider !== 'mtn_momo' || account.timezone !== 'Africa/Kigali' ||
      profile.date_format !== 'YMD_HMS' || profile.utc_offset_minutes !== 120 ||
      !profile.incoming_prefixes.includes('You have received') ||
      !profile.transaction_id_prefixes.includes('FT Id:') || !profile.currency_aliases.includes('RWF') ||
      !admission || typeof admission !== 'object' || Array.isArray(admission) ||
      Object.keys(admission).length !== 2 || !Object.hasOwn(admission, 'version') || !Object.hasOwn(admission, 'template') ||
      admission.version !== LOCAL_MOMO_EXTRACTOR_VERSION ||
      admission.template !== LOCAL_MOMO_TEMPLATE_ID ||
      !['outgoing_markers', 'failure_markers', 'reversal_markers'].every(key =>
        profile[key] === undefined || Array.isArray(profile[key]) && profile[key].length <= 30)) {
    return unsupported('unverified_or_unsupported_profile');
  }
  if (!profile.sender_allowlist.some(sender => sender.toLocaleLowerCase('en') === source.raw_sender.toLocaleLowerCase('en'))) {
    return unsupported('sender_not_allowed');
  }

  const match = template.exec(source.raw_body);
  if (!match) return unsupported('unsupported_template');
  const g = match.groups;
  if (ambiguousName.test(g.payerName)) return unsupported('ambiguous_payer_role');
  const amount = exactMinor(g.amount), balance = exactMinor(g.balance);
  if (amount === null || amount <= 0 || balance === null) return unsupported('invalid_amount');

  const extraction = {
    schema_version: 'momo-extraction.v1',
    event_kind: 'incoming_receipt',
    payment_outcome: 'successful',
    transaction_id_raw: g.transactionId,
    original_transaction_id_raw: null,
    transaction_datetime_raw: g.time,
    principal_amount_raw: g.amount,
    currency_raw: g.currency,
    payer_name_raw: g.payerName,
    payer_identifier_raw: g.payerId,
    payment_reference_raw: null,
    fee_amount_raw: null,
    wallet_balance_after_raw: g.balance,
    evidence: {
      incoming_success: g.incoming,
      principal: g.principal,
      transaction_id: g.transactionEvidence,
      transaction_datetime: g.timeEvidence,
      payer: g.payer,
      fee: null,
      wallet_balance_after: g.balanceEvidence,
    },
    issues: [],
  };
  const validation = validateMomoExtraction(extraction, source, account, profile);
  if (!validation.accepted) return unsupported('canonical_validation_failed');
  return {
    status: 'extracted',
    extractor_version: LOCAL_MOMO_EXTRACTOR_VERSION,
    template_id: LOCAL_MOMO_TEMPLATE_ID,
    source_observation: {
      kind: 'unbound_received_sms_observation',
      source_binding: 'unverified',
      balance_scope: 'unverified',
      amount_rwf: amount,
      sender_name: g.payerName,
      sender_last3: g.payerId.slice(-3),
      observed_balance_rwf: balance,
      transaction_id: g.transactionId,
    },
    extraction,
  };
}
