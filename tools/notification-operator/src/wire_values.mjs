import {createHash} from 'node:crypto';

export const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
export const HASH = /^[a-f0-9]{64}$/;

export class OperatorError extends Error {
  constructor(code, {unknown = false} = {}) {
    super(code);
    this.name = 'OperatorError';
    this.code = code;
    this.outcomeUnknown = unknown;
  }
}

export function need(value, code = 'invalid_contract') {
  if (!value) throw new OperatorError(code);
}

export function plain(value) {
  return value !== null && typeof value === 'object' &&
    !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
}

export const sha = value => createHash('sha256').update(value).digest('hex');

export function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (plain(value)) {
    const entries = Object.keys(value).sort()
      .map(key => JSON.stringify(key) + ':' + canonical(value[key]));
    return '{' + entries.join(',') + '}';
  }
  need(value === null || typeof value === 'string' || typeof value === 'boolean' ||
    typeof value === 'number' && Number.isFinite(value), 'invalid_canonical_value');
  return JSON.stringify(value);
}

export const same = (left, right) => canonical(left) === canonical(right);

export function keys(value, required, optional = []) {
  need(plain(value), 'invalid_object');
  need(required.every(key => Object.hasOwn(value, key)) &&
    Object.keys(value).every(key => required.includes(key) || optional.includes(key)), 'unsupported_or_missing_fields');
  return value;
}

export function uuid(value) {
  need(typeof value === 'string' && UUID.test(value), 'invalid_uuid');
  return value;
}

export function hash(value) {
  need(typeof value === 'string' && HASH.test(value), 'invalid_digest');
  return value;
}

export function integer(value, min = 1, max = 999999998) {
  need(Number.isSafeInteger(value) && value >= min && value <= max, 'invalid_integer');
  return value;
}

export function timestamp(value) {
  need(typeof value === 'string' &&
    /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value) &&
    Number.isFinite(Date.parse(value)) &&
    new Date(value).toISOString() === value, 'invalid_timestamp');
  return value;
}
