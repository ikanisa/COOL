import {MOMO_SCHEMA_VERSION, exactMinor, validateMomoExtraction, validateProviderProfile} from '../momo_pipeline.js';
import {parseWire} from './wire/runtime.mjs';

// This module observes an unbound SMS. It does not establish the sender's
// authenticity, select a receiving account, or authorize a financial action.
// The caller supplies one trusted, already-approved provider-profile tuple.
const PROFILE_KEYS = ['provider', 'status', 'profile_status', 'profile_version', 'profile_json', 'currency', 'timezone'];
const RULE_KEYS = ['role', 'kind', 'prefix', 'suffix', 'digit_count', 'format'];
const RECIPIENT_KINDS = new Set(['public_code', 'phone_number', 'account_number']);
const SECRET = /\b(?:otp|one[ -]time|password|passcode|verification(?:[ -]code)?|activation[ -]code|security[ -]code|pin(?:[ -]code)?|authori[sz]ation[ -]code|mot\s+de\s+passe)\b/iu;
const word = value => typeof value === 'string' && /^[\p{L}\p{N}\p{M}_]$/u.test(value);
const escaped = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function plainData(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) return false;
  if (Object.getOwnPropertySymbols(value).length) return false;
  return Object.values(Object.getOwnPropertyDescriptors(value)).every(d => Object.hasOwn(d, 'value'));
}

function exactData(value, keys) {
  return plainData(value) && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}

function plainArray(value) {
  if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype || Object.getOwnPropertySymbols(value).length) return false;
  const descriptors = Object.getOwnPropertyDescriptors(value), length = descriptors.length?.value;
  if (!Number.isInteger(length) || length < 0 || length > 20) return false;
  if (Object.keys(descriptors).some(key => key !== 'length' && (!/^(0|[1-9][0-9]*)$/.test(key) || Number(key) >= length))) return false;
  return Array.from({length}, (_, index) => descriptors[index]).every(d => d && Object.hasOwn(d, 'value'));
}

function wellFormed(text) {
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = text.charCodeAt(++i);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) return false;
  }
  return true;
}

function sourceTextValid(source) {
  return plainData(source) && typeof source.raw_sender === 'string' && source.raw_sender.length > 0 &&
    source.raw_sender.length <= 96 && typeof source.raw_body === 'string' && source.raw_body.length > 0 && source.raw_body.length <= 16384 &&
    new TextEncoder().encode(source.raw_body).length <= 16384 &&
    wellFormed(source.raw_sender) && wellFormed(source.raw_body) &&
    !/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/u.test(source.raw_sender + source.raw_body);
}

function sourceValid(source) { return sourceTextValid(source) && source.completeness === 'complete'; }

function approvedProfile(tuple) {
  if (!exactData(tuple, PROFILE_KEYS) || typeof tuple.provider !== 'string' ||
      !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(tuple.provider) ||
      typeof tuple.profile_version !== 'string' || !tuple.profile_version.trim() || tuple.profile_version.length > 160 ||
      typeof tuple.profile_json !== 'string' || tuple.profile_json.length > 65536) return null;
  // Refuse duplicate JSON keys and malformed Unicode before using the shared
  // provider validator; the profile remains an externally approved input.
  try { if (!plainData(parseWire(tuple.profile_json, 65536))) return null; } catch { return null; }
  return validateProviderProfile(tuple);
}

function range(body, text) {
  if (typeof text !== 'string' || !text.length) return null;
  const start = body.indexOf(text);
  if (start < 0 || body.indexOf(text, start + 1) !== -1) return null;
  return {start, end: start + text.length};
}

function pointBefore(body, index) {
  if (index <= 0) return null;
  const unit = body.charCodeAt(index - 1);
  const start = unit >= 0xdc00 && unit <= 0xdfff && index > 1 &&
    body.charCodeAt(index - 2) >= 0xd800 && body.charCodeAt(index - 2) <= 0xdbff ? index - 2 : index - 1;
  return body.slice(start, index);
}

function markerBoundary(body, index, prefix) {
  const first = String.fromCodePoint(prefix.codePointAt(0));
  return !word(first) || !word(pointBefore(body, index));
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
  if (observations.length !== 1) return {state: 'unresolved', reason: 'recipient_evidence_ambiguous'};
  return {state: 'candidate', ...observations[0]};
}

function incomingMatches(body, profile) {
  const prefixes = profile.incoming_prefixes.map(escaped).join('|');
  const currencies = profile.currency_aliases.map(escaped).join('|');
  const pattern = new RegExp(`(${prefixes})\\s+(?:(${currencies})\\s+([0-9][0-9,]*)|([0-9][0-9,]*)\\s+(${currencies}))(?![\\p{N}.,])`, 'giu');
  return [...body.matchAll(pattern)].filter(match => markerBoundary(body, match.index, match[1]));
}

function referenceMatches(body, profile, expected = null) {
  const references = [];
  for (const prefix of profile.transaction_id_prefixes) {
    const value = expected === null ? '[A-Za-z0-9_-]{1,160}' : escaped(expected);
    const pattern = new RegExp(`(${escaped(prefix)})\\s*(${value})(?![\\p{L}\\p{N}\\p{M}_/-]|\\.[\\p{L}\\p{N}\\p{M}])`, 'giu');
    for (const match of body.matchAll(pattern)) {
      if (!markerBoundary(body, match.index, match[1]) || expected !== null && match[2] !== expected) continue;
      const idStart = match.index + match[0].length - match[2].length;
      const previous = references.find(row => row.idStart === idStart);
      if (!previous) {
        references.push({idStart, value: match[2], start: match.index, end: match.index + match[0].length});
        if (references.length > 1) return references;
      }
      else if (match.index < previous.start) previous.start = match.index;
    }
  }
  return references;
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
    if (!profile.sender_allowlist.some(sender => sender.toLocaleLowerCase('en') === source.raw_sender.toLocaleLowerCase('en'))) {
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
    if (!profile.sender_allowlist.some(sender=>sender.toLocaleLowerCase('en')===source.raw_sender.toLocaleLowerCase('en')))
      return unavailable('provider_sender_unrecognised');
    const recipient=recipientEvidence(source.raw_body,profile);
    if (recipient.state!=='candidate') return unavailable(recipient.reason);
    return {kind:'native_recipient_quote',state:'quoted',source_mode:source.source_mode,
      source_complete:source.complete,recipient};
  } catch {return unavailable('invalid_evidence');}
}

// For incomplete inbox text, visible quotations are not full-message facts.
// Count all visible labels, including malformed ones, so an intact first
// label cannot hide a second truncated or conflicting label.
function visibleLabels(body, labels) {
  const spans = [];
  for (const label of labels) {
    const pattern = new RegExp(`(?=(${escaped(label)}))`, 'giu');
    for (const match of body.matchAll(pattern)) {
      if (markerBoundary(body, match.index, match[1])) spans.push({start: match.index, end: match.index + match[1].length});
    }
  }
  spans.sort((a, b) => a.start - b.start || b.end - a.end);
  const groups = [];
  for (const span of spans) {
    const prior = groups.at(-1);
    if (prior && span.start < prior.end) prior.end = Math.max(prior.end, span.end);
    else groups.push({...span});
  }
  return groups;
}

function partialTailIsDelimited(body, end) {
  if (end >= body.length) return false;
  const tail = body.slice(end);
  const first = String.fromCodePoint(tail.codePointAt(0));
  if (!/^[\s\p{P}\p{S}]$/u.test(first) || /[+\-/*•…#]/u.test(first)) return false;
  const remaining = tail.trimStart();
  if (!remaining) return false;
  if (/^[.,]/u.test(remaining)) {
    const after = remaining.slice(1).trimStart();
    return Boolean(after) && !/^[\p{N}.,*•…xX#]/u.test(after);
  }
  return !/^[\p{N}*•…xX#]/u.test(remaining);
}

function visibleConflict(body, profile) {
  const markers = ['reversed', 'reversal', 'failed', 'cancelled', 'pending', 'declined',
    'withdrawal', 'you have sent', 'you have paid', ...(profile.outgoing_markers ?? []),
    ...(profile.failure_markers ?? []), ...(profile.reversal_markers ?? [])];
  for (const marker of markers) {
    const pattern = new RegExp(escaped(marker), 'giu');
    for (const match of body.matchAll(pattern)) {
      const first = String.fromCodePoint(marker.codePointAt(0));
      const last = String.fromCodePoint(marker.codePointAt(marker.length - 1));
      const afterIndex = match.index + match[0].length;
      const after = afterIndex < body.length ? String.fromCodePoint(body.codePointAt(afterIndex)) : null;
      if ((!word(first) || !word(pointBefore(body, match.index))) && (!word(last) || !word(after))) return true;
    }
  }
  return false;
}

function partialAmountMatch(body, profile) {
  if (visibleLabels(body, profile.incoming_prefixes).length !== 1) return null;
  const prefixes = profile.incoming_prefixes.map(escaped).join('|');
  const currencies = profile.currency_aliases.map(escaped).join('|');
  const pattern = new RegExp(`(${prefixes})\\s+(?:(${currencies})\\s+([0-9][0-9,]*)|([0-9][0-9,]*)\\s+(${currencies}))`, 'giu');
  const matches = [...body.matchAll(pattern)].filter(match => markerBoundary(body, match.index, match[1]));
  if (matches.length !== 1) return null;
  const match = matches[0], currency = match[2] ?? match[5], amount = match[3] ?? match[4];
  const end = match.index + match[0].length, minor = exactMinor(amount);
  if (!profile.currency_aliases.includes(currency) || minor === null || minor <= 0 || !partialTailIsDelimited(body, end)) return null;
  return {start: match.index, end, minor};
}

function partialAmountQuotes(body, profile) {
  const match = partialAmountMatch(body, profile);
  return match ? [{kind: 'quoted_incoming_amount', text: body.slice(match.start, match.end),
    evidence: {start: match.start, end: match.end}}] : [];
}

function partialReferenceQuotes(body, profile) {
  if (visibleLabels(body, profile.transaction_id_prefixes).length !== 1) return [];
  const references = referenceMatches(body, profile);
  if (references.length !== 1) return [];
  const ref = references[0];
  if (/[xX]{2,}/u.test(ref.value) || !partialTailIsDelimited(body, ref.end)) return [];
  return [{kind: 'quoted_reference', text: body.slice(ref.start, ref.end), evidence: {start: ref.start, end: ref.end}}];
}

/**
 * A distinct, display-only result for an incomplete inbox row. No model output,
 * receiving candidate, canonical extraction, attribution or posting is emitted.
 * The returned quote and UTF-16 span describe visible bytes only; later unseen
 * text can change the message's meaning. The input is never rewritten as complete.
 */
export function parsePartialInboxEvidence(input = {}) {
  const unavailable = reason => ({kind: 'partial_inbox_display_only', state: 'unavailable', hints: [],
    recipient: {state: 'unresolved', reason}});
  try {
    if (!plainData(input) || !exactData(input, ['source', 'providerProfile'])) return unavailable('invalid_input');
    const {source, providerProfile} = input;
    if (!sourceTextValid(source) || source.source_mode !== 'catch_up' || source.complete !== false ||
        Object.hasOwn(source, 'completeness') && source.completeness !== 'incomplete') return unavailable('invalid_inbox_source');
    const profile = approvedProfile(providerProfile);
    if (!profile || !['outgoing_markers', 'failure_markers', 'reversal_markers'].every(key =>
      profile[key] === undefined || Array.isArray(profile[key]) && profile[key].length <= 30)) return unavailable('provider_profile_unverified');
    if (!profile.sender_allowlist.some(sender => sender.toLocaleLowerCase('en') === source.raw_sender.toLocaleLowerCase('en'))) {
      return unavailable('provider_sender_unrecognised');
    }
    const body = source.raw_body;
    if (SECRET.test(body)) return unavailable('unsupported_message');
    // A partial message with duplicate incoming or transaction labels is
    // ambiguous as a whole: do not show the other label as if it were paired.
    const duplicateLabels=visibleLabels(body,profile.incoming_prefixes).length>1||
      visibleLabels(body,profile.transaction_id_prefixes).length>1;
    const hints = visibleConflict(body, profile)||duplicateLabels ? [] : [...partialAmountQuotes(body, profile), ...partialReferenceQuotes(body, profile)];
    return {kind: 'partial_inbox_display_only', state: 'partial', source_complete: false, hints,
      recipient: {state: 'unresolved', reason: 'incomplete_source'}};
  } catch {
    return unavailable('invalid_evidence');
  }
}

/** Compare complete visible tokens without upgrading an incomplete source or
 * treating a model/provider claim as evidence. This is separate from the
 * display-only result so its existing wire shape remains unchanged. */
export function matchesPartialInboxFinancialQuotes(input = {}) {
  try {
    if (!exactData(input, ['source', 'providerProfile', 'reference', 'amountMinor', 'currency']) || !plainData(input.providerProfile) ||
        typeof input.reference !== 'string' || !input.reference.length || input.reference.length > 160 ||
        !Number.isSafeInteger(input.amountMinor) || input.amountMinor <= 0 ||
        input.currency !== input.providerProfile?.currency) return false;
    const partial = parsePartialInboxEvidence({source: input.source, providerProfile: input.providerProfile});
    if (partial.state !== 'partial' || partial.hints.length !== 2 ||
        !partial.hints.some(h => h.kind === 'quoted_reference') ||
        !partial.hints.some(h => h.kind === 'quoted_incoming_amount')) return false;
    const profile = approvedProfile(input.providerProfile);
    if (!profile) return false;
    const body = input.source.raw_body, references = referenceMatches(body, profile), amount = partialAmountMatch(body, profile);
    return references.length === 1 && references[0].value === input.reference &&
      amount !== null && amount.minor === input.amountMinor;
  } catch { return false; }
}
