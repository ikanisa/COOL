import {isId, isObject, isSafeCount} from './contracts';

interface JournalLine {
  account_id: string;
  debit_rwf: number;
  credit_rwf: number;
  description?: string;
}

export interface JournalLineInput {
  account: string;
  debit: string;
  credit: string;
  description: string;
}

interface DraftFields extends Record<string, unknown> {
  description: string;
  entries: JournalLine[];
  reason: string;
}

export interface JournalCreateIntent extends DraftFields {
  group_id: string;
  allocation_id?: string | null;
}

export interface JournalEditIntent extends DraftFields {
  expected_version: number;
}

export function invalidJournal(): never {
  throw new Error('Invalid journal request');
}

function safeText(value: unknown, min: number, max: number): value is string {
  return typeof value === 'string' && value === value.trim() && value.length >= min && value.length <= max &&
    ![...value].some(char => {
      const code = char.codePointAt(0)!;
      return (code < 32 && ![9, 10, 13].includes(code)) || code === 127;
    });
}

function validateDraftFields(value: Record<string, unknown>): asserts value is DraftFields {
  if (!safeText(value.description, 3, 1000) || !safeText(value.reason, 8, 1000) ||
      !Array.isArray(value.entries) || value.entries.length < 2 || value.entries.length > 100) return invalidJournal();

  let debit = 0n, credit = 0n;
  for (const line of value.entries) {
    if (!isObject(line) || !Object.keys(line).every(key => ['account_id', 'debit_rwf', 'credit_rwf', 'description'].includes(key)) ||
        !isId(line.account_id) || !isSafeCount(line.debit_rwf) || !isSafeCount(line.credit_rwf) ||
        ((line.debit_rwf === 0) === (line.credit_rwf === 0)) ||
        !(line.description === undefined || safeText(line.description, 0, 500))) return invalidJournal();
    debit += BigInt(line.debit_rwf);
    credit += BigInt(line.credit_rwf);
  }
  if (debit === 0n || debit !== credit || debit > BigInt(Number.MAX_SAFE_INTEGER)) return invalidJournal();
}

export function parseJournalCreateIntent(value: unknown): JournalCreateIntent {
  if (!isObject(value) || !Object.keys(value).every(key => ['group_id', 'description', 'allocation_id', 'entries', 'reason'].includes(key)) ||
      !isId(value.group_id) || !(value.allocation_id == null || isId(value.allocation_id))) return invalidJournal();
  validateDraftFields(value);
  return value as JournalCreateIntent;
}

export function parseJournalEditIntent(value: unknown): JournalEditIntent {
  if (!isObject(value) || !Object.keys(value).every(key => ['expected_version', 'description', 'entries', 'reason'].includes(key)) ||
      !isSafeCount(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER) return invalidJournal();
  validateDraftFields(value);
  return value as JournalEditIntent;
}

export function parseJournalPostingIntent(value: unknown) {
  if (!isObject(value) || Object.keys(value).length !== 2 || !isSafeCount(value.expected_version) ||
      value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER ||
      !safeText(value.reason, 8, 1000)) return invalidJournal();
  return {expected_version: value.expected_version, reason: value.reason};
}

function amount(value: string): number {
  const text = value.trim();
  if (!text) return 0;
  if (!/^(?:0|[1-9][0-9]*)$/.test(text)) return invalidJournal();
  const parsed = BigInt(text);
  if (parsed > BigInt(Number.MAX_SAFE_INTEGER)) return invalidJournal();
  return Number(parsed);
}

export function journalLineFromInput(line: JournalLineInput): JournalLine {
  return {account_id: line.account, debit_rwf: amount(line.debit), credit_rwf: amount(line.credit), description: line.description.trim()};
}

export function emptyJournalLine(): JournalLineInput {
  return {account: '', debit: '', credit: '', description: ''};
}
