import { MOMO_SCHEMA_VERSION, validateMomoExtraction } from '../momo_pipeline.js';
import {
  approvedProfile,
  exactData,
  incomingMatches,
  markerBoundary,
  matchesProviderSender,
  plainData,
  referenceMatches,
  sourceTextValid,
  wellFormed,
} from './sms-evidence-input.js';

// This module observes an unbound SMS. It does not establish the sender's
// authenticity, select a receiving account, or authorize a financial action.
// The caller supplies one trusted, already-approved provider-profile tuple.
const RULE_KEYS = ['role', 'kind', 'prefix', 'suffix', 'digit_count', 'format'];
const RECIPIENT_KINDS = new Set(['public_code', 'phone_number', 'account_number']);

function plainArray(value) {
  if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype || Object.getOwnPropertySymbols(value).length) return false;
  const descriptors = Object.getOwnPropertyDescriptors(value), length = descriptors.length?.value;
  if (!Number.isInteger(length) || length < 0 || length > 20) return false;
  if (Object.keys(descriptors).some(key => key !== 'length' && (!/^(0|[1-9][0-9]*)$/.test(key) || Number(key) >= length))) return false;
  return Array.from({length}, (_, index) => descriptors[index]).every(d => d && Object.hasOwn(d, 'value'));
}

function sourceValid(source) { return sourceTextValid(source) && source.completeness === 'complete'; }

function range(body, text) {
  if (typeof text !== 'string' || !text.length) return null;
  const start = body.indexOf(text);
  if (start < 0 || body.indexOf(text, start + 1) !== -1) return null;
  return {start, end: start + text.length};
}

function recipientRules(profile) {
  if (!Object.hasOwn(profile, 'recipient_rules')) return {reason: 'recipient_grammar_missing'};
  const rules = profile.recipient_rules;
  if (!Array.isArray(rules) || !rules.length || rules.length > 30) return {reason: 'recipient_grammar_invalid'};
  const prefixes = [];
  for (const rule of rules) {
    if (!exactData(rule, RULE_KEYS) || rule.role !== 'recipient' || !RECIPIENT_KINDS.has(rule.kind) ||
        typeof rule.prefix !== 'string' || !rule.prefix.trim() || rule.prefix.length > 160 ||
        !/\p{L}/u.test(rule.prefix) || typeof rule.suffix !== 'string' || !rule.suffix.length || rule.suffix.length > 160 ||
        !wellFormed(rule.prefix) || !wellFormed(rule.suffix) ||
        /[\0\u202a-\u202e\u2066-\u2069\p{N}*•…]/u.test(rule.prefix + rule.suffix) ||
        /[xX#]\s*$/u.test(rule.prefix) || !/^[\s\p{P}\p{S}]+$/u.test(rule.suffix) ||
        /(?:\.\s*){2,}/u.test(rule.suffix) ||
        !Number.isInteger(rule.digit_count) || rule.digit_count < 1 || rule.digit_count > 32 ||
        !['digits', 'plus_digits'].includes(rule.format)) {
      return {reason: 'recipient_grammar_invalid'};
    }
    const normalized = rule.prefix.trim().toLocaleLowerCase('en');
    if (prefixes.some(prefix => prefix.includes(normalized) || normalized.includes(prefix))) {
      return {reason: 'recipient_grammar_ambiguous'};
    }
    // An approved transaction label cannot simultaneously establish a
    // receiving role. Other role semantics remain the profile owner's duty.
    if (profile.transaction_id_prefixes.some(label => {
      const token = label.trim().toLocaleLowerCase('en');
      return token.includes(normalized) || normalized.includes(token);
    })) {
      return {reason: 'recipient_grammar_conflicts_with_transaction'};
    }
    prefixes.push(normalized);
  }
  return {rules};
}

function recipientEvidence(body, profile) {
  const configured = recipientRules(profile);
  if (!configured.rules) return {state: 'unresolved', reason: configured.reason};
  const observations = [];
  let malformed = false;
  for (const rule of configured.rules) {
    for (let at = body.indexOf(rule.prefix); at !== -1; at = body.indexOf(rule.prefix, at + 1)) {
      if (!markerBoundary(body, at, rule.prefix)) continue;
      const start = at + rule.prefix.length;
      const width = rule.digit_count + (rule.format === 'plus_digits' ? 1 : 0);
      const raw = body.slice(start, start + width);
      const digits = rule.format === 'plus_digits' ? raw.startsWith('+') && raw.slice(1) : raw;
      const end = start + width;
      if (typeof digits !== 'string' || !new RegExp(`^[0-9]{${rule.digit_count}}$`).test(digits) ||
          !body.startsWith(rule.suffix, end)) {
        malformed = true;
        continue;
      }
      // Do not accept the beginning of a longer, masked or decimal token.
      const after = body.slice(end + rule.suffix.length).match(/^\s*(.)/u)?.[1] ?? null;
      if (after && (/[\p{N}*•…xX#]/u.test(after) || after === '.' && rule.suffix.endsWith('.'))) {
        malformed = true;
        continue;
      }
      observations.push({kind: rule.kind, raw, identifier: {start, end}, role: {start: at, end: end + rule.suffix.length}});
      if (observations.length > 1) return {state: 'unresolved', reason: 'recipient_evidence_ambiguous'};
    }
  }
  if (malformed) return {state: 'unresolved', reason: 'recipient_evidence_invalid'};
  if (!observations.length) return {state: 'unresolved', reason: 'recipient_evidence_missing'};
  return {state: 'candidate', ...observations[0]};
}

function deterministicOutput(body, profile) {
  const incoming = incomingMatches(body, profile), references = referenceMatches(body, profile);
  if (incoming.length !== 1 || references.length !== 1) return null;
  const match = incoming[0], reference = references[0];
  const currency = match[2] ?? match[5], amount = match[3] ?? match[4];
  if (!profile.currency_aliases.includes(currency)) return null;
  return {
    schema_version: MOMO_SCHEMA_VERSION, event_kind: 'incoming_receipt', payment_outcome: 'successful',
    transaction_id_raw: reference.value, original_transaction_id_raw: null, transaction_datetime_raw: null,
    principal_amount_raw: amount, currency_raw: currency, payer_name_raw: null, payer_identifier_raw: null,
    payment_reference_raw: null, fee_amount_raw: null, wallet_balance_after_raw: null,
    evidence: {incoming_success: match[0], principal: match[0], transaction_id: body.slice(reference.start, reference.end),
      transaction_datetime: null, payer: null, fee: null, wallet_balance_after: null}, issues: [],
  };
}

function supportedFacts(output, source, tuple, profile) {
  if (!plainData(output) || !plainData(output.evidence) || !plainArray(output.issues)) return null;
  const validation = validateMomoExtraction(output, source, tuple, profile);
  if (!validation.accepted) return null;
  const incoming = incomingMatches(source.raw_body, profile);
  const references = referenceMatches(source.raw_body, profile, output.transaction_id_raw);
  const incomingEvidence = range(source.raw_body, output.evidence.incoming_success);
  const principalEvidence = range(source.raw_body, output.evidence.principal);
  if (incoming.length !== 1 || references.length !== 1 || !incomingEvidence || !principalEvidence) return null;
  const result = {
    event_kind: {value: 'incoming_receipt', evidence: incomingEvidence},
    principal: {raw: output.principal_amount_raw, amount_minor: validation.facts.amount_minor,
      currency: validation.facts.currency, evidence: principalEvidence, role_evidence: incomingEvidence},
    transaction_id: {raw: output.transaction_id_raw, evidence: {start: references[0].start, end: references[0].end}},
  };
  for (const [rawKey, evidenceKey, resultKey, valueKey] of [
    ['transaction_datetime_raw', 'transaction_datetime', 'transaction_time', 'transaction_at'],
    ['fee_amount_raw', 'fee', 'fee', 'fee_minor'],
    ['wallet_balance_after_raw', 'wallet_balance_after', 'wallet_balance_after', 'wallet_balance_after_minor'],
  ]) {
    if (output[rawKey] === null) continue;
    const evidence = range(source.raw_body, output.evidence[evidenceKey]);
    if (!evidence) return null;
    result[resultKey] = {raw: output[rawKey], value: validation.facts[valueKey], evidence};
  }
  // Existing payer validation proves a substring, not its receiving/payer
  // role for every carrier. Omit payer and arbitrary model reference fields.
  return result;
}

/**
 * Return provisional observations only. Evidence offsets are UTF-16 indices
 * into the unchanged `source.raw_body`; no account ID or posting authority is
 * accepted or returned. A profile's optional recipient_rules are explicit
 * approved literal grammars, not provider defaults or model suggestions.
 */
export function parseUnresolvedEvidence(input = {}) {
  const empty = reason => ({kind: 'provisional_sms_evidence', facts: null, facts_state: 'unavailable',
    recipient: {state: 'unresolved', reason}});
  try {
    if (!plainData(input) || !Object.hasOwn(input, 'source') || !Object.hasOwn(input, 'providerProfile') ||
        Object.keys(input).some(key => !['source', 'providerProfile', 'modelOutput'].includes(key))) return empty('invalid_input');
    const {source, providerProfile, modelOutput} = input;
    if (!sourceValid(source)) return empty('invalid_or_incomplete_source');
    const profile = approvedProfile(providerProfile);
    if (!profile) return empty('provider_profile_unverified');
    if (!matchesProviderSender(source, profile)) {
      return empty('provider_sender_unrecognised');
    }
    const recipient = recipientEvidence(source.raw_body, profile);
    const supplied = modelOutput !== undefined && modelOutput !== null;
    const output = supplied ? modelOutput : deterministicOutput(source.raw_body, profile);
    const facts = output ? supportedFacts(output, source, providerProfile, profile) : null;
    return {kind: 'provisional_sms_evidence', facts, facts_state: facts ? 'supported' : supplied ? 'unsupported' : 'unavailable', recipient};
  } catch {
    return empty('invalid_evidence');
  }
}

/** Observe a recipient quote in the exact retained native text. This is not
 * a completeness, carrier-authenticity, settlement or posting claim. A
 * catch-up source stays incomplete even when its visible quote is intact. */
export function parseNativeRecipientQuote(input = {}) {
  const unavailable = reason => ({kind:'native_recipient_quote',state:'unavailable',reason});
  try {
    if (!exactData(input, ['source','providerProfile'])) return unavailable('invalid_input');
    const {source,providerProfile}=input;
    if (!sourceTextValid(source) || source.provenance!=='native_observation_unverified' ||
      !((source.source_mode==='live'&&source.complete===true)||(source.source_mode==='catch_up'&&source.complete===false)))
      return unavailable('invalid_native_source');
    const profile=approvedProfile(providerProfile);
    if (!profile) return unavailable('provider_profile_unverified');
    if (!matchesProviderSender(source, profile))
      return unavailable('provider_sender_unrecognised');
    const recipient=recipientEvidence(source.raw_body,profile);
    if (recipient.state!=='candidate') return unavailable(recipient.reason);
    return {kind:'native_recipient_quote',state:'quoted',source_mode:source.source_mode,
      source_complete:source.complete,recipient};
  } catch {return unavailable('invalid_evidence');}
}
