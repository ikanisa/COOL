import { exactMinor } from '../momo_pipeline.js';
import {
  approvedProfile,
  escaped,
  exactData,
  incomingMatches,
  markerBoundary,
  matchesProviderSender,
  plainData,
  pointBefore,
  referenceMatches,
  sourceTextValid,
  word,
} from './sms-evidence-input.js';

const SECRET =
  /\b(?:otp|one[ -]time|password|passcode|verification(?:[ -]code)?|activation[ -]code|security[ -]code|pin(?:[ -]code)?|authori[sz]ation[ -]code|mot\s+de\s+passe)\b/iu;

// For incomplete inbox text, visible quotations are not full-message facts.
// Count all visible labels, including malformed ones, so an intact first
// label cannot hide a second truncated or conflicting label.
function visibleLabels(body, labels) {
  const spans = [];
  for (const label of labels) {
    const pattern = new RegExp(`(?=(${escaped(label)}))`, 'giu');
    for (const match of body.matchAll(pattern)) {
      if (markerBoundary(body, match.index, match[1])) {
        spans.push({ start: match.index, end: match.index + match[1].length });
      }
    }
  }
  spans.sort((a, b) => a.start - b.start || b.end - a.end);
  const groups = [];
  for (const span of spans) {
    const prior = groups.at(-1);
    if (prior && span.start < prior.end) prior.end = Math.max(prior.end, span.end);
    else groups.push({ ...span });
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
  const markers = [
    'reversed',
    'reversal',
    'failed',
    'cancelled',
    'pending',
    'declined',
    'withdrawal',
    'you have sent',
    'you have paid',
    ...(profile.outgoing_markers ?? []),
    ...(profile.failure_markers ?? []),
    ...(profile.reversal_markers ?? []),
  ];
  for (const marker of markers) {
    const pattern = new RegExp(escaped(marker), 'giu');
    for (const match of body.matchAll(pattern)) {
      const first = String.fromCodePoint(marker.codePointAt(0));
      const last = String.fromCodePoint(marker.codePointAt(marker.length - 1));
      const afterIndex = match.index + match[0].length;
      const after = afterIndex < body.length ? String.fromCodePoint(body.codePointAt(afterIndex)) : null;
      if ((!word(first) || !word(pointBefore(body, match.index))) && (!word(last) || !word(after))) {
        return true;
      }
    }
  }
  return false;
}

function partialAmountMatch(body, profile) {
  const matches = incomingMatches(body, profile, { allowPartialTail: true });
  if (matches.length !== 1) return null;
  const match = matches[0], currency = match[2] ?? match[5], amount = match[3] ?? match[4];
  const end = match.index + match[0].length, minor = exactMinor(amount);
  if (
    !profile.currency_aliases.includes(currency) || minor === null || minor <= 0 ||
    !partialTailIsDelimited(body, end)
  ) return null;
  return { start: match.index, end, minor };
}

function partialReferenceMatch(body, profile) {
  const references = referenceMatches(body, profile);
  if (references.length !== 1) return null;
  const ref = references[0];
  return /[xX]{2,}/u.test(ref.value) || !partialTailIsDelimited(body, ref.end) ? null : ref;
}

function readPartialQuotes(input) {
  if (!exactData(input, ['source', 'providerProfile'])) return { reason: 'invalid_input' };
  const { source, providerProfile } = input;
  if (
    !sourceTextValid(source) || source.source_mode !== 'catch_up' || source.complete !== false ||
    Object.hasOwn(source, 'completeness') && source.completeness !== 'incomplete'
  ) {
    return { reason: 'invalid_inbox_source' };
  }
  const profile = approvedProfile(providerProfile);
  if (
    !profile ||
    !['outgoing_markers', 'failure_markers', 'reversal_markers'].every((key) =>
      profile[key] === undefined || Array.isArray(profile[key]) && profile[key].length <= 30
    )
  ) {
    return { reason: 'provider_profile_unverified' };
  }
  if (!matchesProviderSender(source, profile)) return { reason: 'provider_sender_unrecognised' };
  const body = source.raw_body;
  if (SECRET.test(body)) return { reason: 'unsupported_message' };
  const amountLabels = visibleLabels(body, profile.incoming_prefixes).length;
  const referenceLabels = visibleLabels(body, profile.transaction_id_prefixes).length;
  // Duplicate labels make the entire quotation ambiguous, even if one token is complete.
  if (amountLabels > 1 || referenceLabels > 1 || visibleConflict(body, profile)) return { body };
  return {
    body,
    amount: amountLabels === 1 ? partialAmountMatch(body, profile) : null,
    reference: referenceLabels === 1 ? partialReferenceMatch(body, profile) : null,
  };
}

function quote(body, kind, { start, end }) {
  return { kind, text: body.slice(start, end), evidence: { start, end } };
}

/**
 * A distinct, display-only result for an incomplete inbox row. No model output,
 * receiving candidate, canonical extraction, attribution or posting is emitted.
 * The returned quote and UTF-16 span describe visible bytes only; later unseen
 * text can change the message's meaning. The input is never rewritten as complete.
 */
export function parsePartialInboxEvidence(input = {}) {
  const unavailable = (reason) => ({
    kind: 'partial_inbox_display_only',
    state: 'unavailable',
    hints: [],
    recipient: { state: 'unresolved', reason },
  });
  try {
    const { body, reason, amount, reference } = readPartialQuotes(input);
    if (reason) return unavailable(reason);
    const hints = [];
    if (amount) hints.push(quote(body, 'quoted_incoming_amount', amount));
    if (reference) hints.push(quote(body, 'quoted_reference', reference));
    return {
      kind: 'partial_inbox_display_only',
      state: 'partial',
      source_complete: false,
      hints,
      recipient: { state: 'unresolved', reason: 'incomplete_source' },
    };
  } catch {
    return unavailable('invalid_evidence');
  }
}

/** Match a reference and amount only when both complete tokens appear in the retained text. */
export function matchesPartialInboxFinancialQuotes(input = {}) {
  try {
    if (
      !exactData(input, ['source', 'providerProfile', 'reference', 'amountMinor', 'currency']) ||
      !plainData(input.providerProfile) ||
      typeof input.reference !== 'string' || !input.reference.length || input.reference.length > 160 ||
      !Number.isSafeInteger(input.amountMinor) || input.amountMinor <= 0 ||
      input.currency !== input.providerProfile?.currency
    ) return false;
    const { amount, reference } = readPartialQuotes({
      source: input.source,
      providerProfile: input.providerProfile,
    });
    return reference?.value === input.reference && amount?.minor === input.amountMinor;
  } catch {
    return false;
  }
}
