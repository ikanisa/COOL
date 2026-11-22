import {isId, isObject, isSafeCount} from './contracts';
import type {AdminRequest} from './types';

const receiptFields = ['request_id', 'resource_type', 'resource_id', 'version', 'status'] as const;
type JournalScope = 'journals.post' | 'journals.patch' | 'journals.post.post';
type JournalReceipt = {
  request_id: string;
  resource_type: 'journals';
  resource_id: string;
  version: number;
  status: 'succeeded';
};
type JournalOutcome =
  | {status: 'succeeded'; receipt: JournalReceipt}
  | {status: 'not_found' | 'pending' | 'failed'; receipt: null};

function invalid(): never {
  throw new Error('The original journal request could not be verified.');
}

export function isLegacyJournalReceipt(value: unknown, version: number, id?: string): value is JournalReceipt {
  return isObject(value) && Object.keys(value).length === receiptFields.length &&
    value.status === 'succeeded' && value.resource_type === 'journals' && isId(value.request_id) &&
    (id === undefined ? isId(value.resource_id) : value.resource_id === id) && value.version === version;
}

export function parseLegacyJournalOutcome(value: unknown, version: number, id?: string): JournalOutcome {
  if (!isObject(value) || value.contract_version !== undefined || value.model !== undefined) return invalid();
  if (value.status === 'not_found' && Object.keys(value).length === 1) return {status: 'not_found', receipt: null};
  if (Object.keys(value).length !== 3 || !isId(value.request_id)) return invalid();
  if (value.status === 'succeeded') {
    if (!isLegacyJournalReceipt(value.receipt, version, id) || value.receipt.request_id !== value.request_id) return invalid();
    return {status: 'succeeded', receipt: value.receipt};
  }
  if ((value.status !== 'pending' && value.status !== 'failed') || value.receipt !== null) return invalid();
  return {status: value.status, receipt: null};
}

export async function verifyLegacyJournalScope(request: AdminRequest, key: string, expected: JournalReceipt, scope: JournalScope): Promise<void> {
  // A single-key legacy lookup does not expose the action that produced the receipt.
  for (let offset = 0; offset < 10000; offset += 100) {
    const history = await request(`operations/requests?limit=100&offset=${offset}`);
    if (history.contract_version !== undefined || history.model !== undefined || !isSafeCount(history.total) || !Array.isArray(history.rows) ||
        history.rows.length !== Math.max(0, Math.min(100, history.total - offset)) || history.rows.some(row => !isObject(row))) return invalid();
    const match = history.rows.find(row => row.idempotency_key === key);
    if (match) {
      if (match.id !== expected.request_id || match.scope !== scope || match.status !== 'succeeded' ||
          !isLegacyJournalReceipt(match.receipt, expected.version, expected.resource_id) ||
          !receiptFields.every(field => match.receipt[field] === expected[field])) return invalid();
      return;
    }
    if (offset + history.rows.length >= history.total) break;
  }
  return invalid();
}

export async function withLegacyJournalLock<T>(name: string, operation: () => Promise<T>): Promise<T> {
  if (!navigator.locks) throw new Error('Protected request lock unavailable');
  return navigator.locks.request(name, {ifAvailable: true}, lock => {
    if (!lock) throw new Error('Another request is in progress');
    return operation();
  });
}
