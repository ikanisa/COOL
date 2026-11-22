import { DesktopError } from './contract.mjs';

const MESSAGES = Object.freeze({
  journal_unavailable: 'Desktop journal is unavailable.',
  journal_corrupt: 'Desktop journal is corrupt or incompatible.',
  unsafe_journal_path: 'Desktop journal path is unsafe.',
});

export const TABLES = Object.freeze([
  'tickets', 'jobs', 'attempts', 'observations', 'policies', 'syncs', 'control',
]);
export const MAX_JSON_BYTES = 1024 * 1024;
const MAX_RESULT_BYTES = 16 * MAX_JSON_BYTES;
const MAX_ROWS = 100_000;
const MAX_NODES = 100_000;
const MAX_DEPTH = 64;
export function journalFailure(code) {
  return new DesktopError(code, MESSAGES[code]);
}

export function normalizeJournalFailure(error) {
  if (error instanceof DesktopError) return error;
  if (['ELOOP', 'ENOTDIR'].includes(error?.code)) return journalFailure('unsafe_journal_path');
  const code = Number(error?.errcode) & 255;
  return journalFailure([11, 17, 19, 26].includes(code) ? 'journal_corrupt' : 'journal_unavailable');
}

function validateJson(value, code) {
  let nodes = 0;
  let bytes = 0;
  const ancestors = new Set();
  function visit(item, depth) {
    if (++nodes > MAX_NODES || depth > MAX_DEPTH) throw journalFailure(code);
    if (item === null || typeof item === 'boolean') return;
    if (typeof item === 'number') {
      if (!Number.isFinite(item)) throw journalFailure(code);
      return;
    }
    if (typeof item === 'string') {
      bytes += Buffer.byteLength(item);
    } else if (typeof item === 'object') {
      if (ancestors.has(item)) throw journalFailure(code);
      const array = Array.isArray(item);
      const prototype = Object.getPrototypeOf(item);
      if (!array && prototype !== Object.prototype && prototype !== null) throw journalFailure(code);
      if (Object.getOwnPropertySymbols(item).length) throw journalFailure(code);
      const keys = Object.keys(item);
      if (keys.length > MAX_NODES || (array && keys.length !== item.length)) throw journalFailure(code);
      ancestors.add(item);
      for (const key of keys) {
        if (array && (!/^(0|[1-9][0-9]*)$/.test(key) || Number(key) >= item.length)) throw journalFailure(code);
        bytes += Buffer.byteLength(key);
        if (bytes > MAX_JSON_BYTES) throw journalFailure(code);
        const descriptor = Object.getOwnPropertyDescriptor(item, key);
        if (!descriptor || !Object.hasOwn(descriptor, 'value')) throw journalFailure(code);
        visit(descriptor.value, depth + 1);
      }
      ancestors.delete(item);
    } else {
      throw journalFailure(code);
    }
    if (bytes > MAX_JSON_BYTES) throw journalFailure(code);
  }
  visit(value, 0);
}

export function encodeJournalValue(value) {
  try {
    validateJson(value, 'journal_unavailable');
    const data = JSON.stringify(value);
    if (typeof data !== 'string' || Buffer.byteLength(data) > MAX_JSON_BYTES) throw journalFailure('journal_unavailable');
    return data;
  } catch {
    throw journalFailure('journal_unavailable');
  }
}

export function decodeJournalValue(data) {
  try {
    if (typeof data !== 'string' || Buffer.byteLength(data) > MAX_JSON_BYTES) throw journalFailure('journal_corrupt');
    const value = JSON.parse(data);
    validateJson(value, 'journal_corrupt');
    return value;
  } catch {
    throw journalFailure('journal_corrupt');
  }
}

export function decodeJournalRows(rows) {
  const result = [];
  let bytes = 0;
  for (const data of rows) {
    if (typeof data !== 'string') throw journalFailure('journal_corrupt');
    bytes += Buffer.byteLength(data);
    if (result.length >= MAX_ROWS || bytes > MAX_RESULT_BYTES) throw journalFailure('journal_corrupt');
    result.push(decodeJournalValue(data));
  }
  return result;
}

export function journalTable(table) {
  if (!TABLES.includes(table)) throw journalFailure('journal_unavailable');
  return table;
}

export function journalKey(key) {
  if (typeof key !== 'string' || Buffer.byteLength(key) > 4096 || key.includes('\0')) {
    throw journalFailure('journal_unavailable');
  }
  return key;
}

export function runJournalAction(action, operations) {
  let active = true;
  let failed;
  const tx = Object.freeze(Object.fromEntries(Object.entries(operations).map(([name, operation]) => [
    name, (...args) => {
      if (!active) throw journalFailure('journal_unavailable');
      if (failed) throw failed;
      try {
        return operation(...args);
      } catch (error) {
        failed = normalizeJournalFailure(error);
        throw failed;
      }
    },
  ])));
  try {
    if (typeof action !== 'function') throw journalFailure('journal_unavailable');
    const result = action(tx);
    if (result !== null && (typeof result === 'object' || typeof result === 'function')
        && typeof result.then === 'function') {
      // Consume a rejected async continuation after its transaction has been revoked.
      Promise.resolve(result).catch(() => {});
      throw journalFailure('journal_unavailable');
    }
    if (failed) throw failed;
    return result;
  } finally {
    active = false;
  }
}
