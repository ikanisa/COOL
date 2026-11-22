import { validateProviderProfile } from '../momo_pipeline.js';
import { parseWire } from './wire/runtime.mjs';

const PROFILE_KEYS = [
  'provider',
  'status',
  'profile_status',
  'profile_version',
  'profile_json',
  'currency',
  'timezone',
];
export const word = (value) => typeof value === 'string' && /^[\p{L}\p{N}\p{M}_]$/u.test(value);
export const escaped = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export function plainData(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) return false;
  if (Object.getOwnPropertySymbols(value).length) return false;
  return Object.values(Object.getOwnPropertyDescriptors(value)).every((d) => Object.hasOwn(d, 'value'));
}

export function exactData(value, keys) {
  return plainData(value) && Object.keys(value).length === keys.length &&
    keys.every((key) => Object.hasOwn(value, key));
}

export function wellFormed(text) {
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = text.charCodeAt(++i);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) return false;
  }
  return true;
}

export function sourceTextValid(source) {
  return plainData(source) && typeof source.raw_sender === 'string' && source.raw_sender.length > 0 &&
    source.raw_sender.length <= 96 && typeof source.raw_body === 'string' && source.raw_body.length > 0 &&
    source.raw_body.length <= 16384 &&
    new TextEncoder().encode(source.raw_body).length <= 16384 &&
    wellFormed(source.raw_sender) && wellFormed(source.raw_body) &&
    !/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/u.test(source.raw_sender + source.raw_body);
}

export function approvedProfile(tuple) {
  if (
    !exactData(tuple, PROFILE_KEYS) || typeof tuple.provider !== 'string' ||
    !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(tuple.provider) ||
    typeof tuple.profile_version !== 'string' || !tuple.profile_version.trim() ||
    tuple.profile_version.length > 160 ||
    typeof tuple.profile_json !== 'string' || tuple.profile_json.length > 65536
  ) return null;
  // Refuse duplicate JSON keys and malformed Unicode before using the shared
  // provider validator; the profile remains an externally approved input.
  try {
    if (!plainData(parseWire(tuple.profile_json, 65536))) return null;
  } catch {
    return null;
  }
  return validateProviderProfile(tuple);
}

export function pointBefore(body, index) {
  if (index <= 0) return null;
  const unit = body.charCodeAt(index - 1);
  const start = unit >= 0xdc00 && unit <= 0xdfff && index > 1 &&
      body.charCodeAt(index - 2) >= 0xd800 && body.charCodeAt(index - 2) <= 0xdbff
    ? index - 2
    : index - 1;
  return body.slice(start, index);
}

export function markerBoundary(body, index, prefix) {
  const first = String.fromCodePoint(prefix.codePointAt(0));
  return !word(first) || !word(pointBefore(body, index));
}

export function incomingMatches(body, profile, { allowPartialTail = false } = {}) {
  const prefixes = profile.incoming_prefixes.map(escaped).join('|');
  const currencies = profile.currency_aliases.map(escaped).join('|');
  const endGuard = allowPartialTail ? '' : '(?![\\p{N}.,])';
  const pattern = new RegExp(
    `(${prefixes})\\s+(?:(${currencies})\\s+([0-9][0-9,]*)|([0-9][0-9,]*)\\s+(${currencies}))${endGuard}`,
    'giu',
  );
  return [...body.matchAll(pattern)].filter((match) => markerBoundary(body, match.index, match[1]));
}

export function referenceMatches(body, profile, expected = null) {
  const references = [];
  for (const prefix of profile.transaction_id_prefixes) {
    const value = expected === null ? '[A-Za-z0-9_-]{1,160}' : escaped(expected);
    const pattern = new RegExp(
      `(${escaped(prefix)})\\s*(${value})(?![\\p{L}\\p{N}\\p{M}_/-]|\\.[\\p{L}\\p{N}\\p{M}])`,
      'giu',
    );
    for (const match of body.matchAll(pattern)) {
      if (!markerBoundary(body, match.index, match[1]) || expected !== null && match[2] !== expected) {
        continue;
      }
      const idStart = match.index + match[0].length - match[2].length;
      const previous = references.find((row) => row.idStart === idStart);
      if (!previous) {
        references.push({ idStart, value: match[2], start: match.index, end: match.index + match[0].length });
        if (references.length > 1) return references;
      } else if (match.index < previous.start) previous.start = match.index;
    }
  }
  return references;
}

export function matchesProviderSender(source, profile) {
  const sender = source.raw_sender.toLocaleLowerCase('en');
  return profile.sender_allowlist.some((allowed) => allowed.toLocaleLowerCase('en') === sender);
}
