import { createHash } from 'node:crypto';
import { REQUEST_KEY, invalid, isRequestKey, isUuid, object, strictKeys, unavailable } from '../config.mjs';
import { marker, page, pageQuery, paging, readTool, schema, validatePage } from './contracts.mjs';

export function canonicalRequestId(principalId, key) {
  if (!isUuid(principalId) || !isRequestKey(key)) invalid();
  const digest = createHash('sha256').update(`collect-admin:${principalId}:${key}`).digest('hex');
  return `${digest.slice(0, 8)}-${digest.slice(8, 12)}-4${digest.slice(13, 16)}-8${digest.slice(17, 20)}-${digest.slice(20, 32)}`;
}
function receiptResourceId(type, id) {
  if (typeof id !== 'string') return false;
  if (type !== 'memberships') return isUuid(id);
  const parts = id.split('/');
  return parts.length === 2 && parts.every(part => isUuid(part));
}
function receipt(value, requestId) {
  if (!object(value) || value.status !== 'succeeded' || value.request_id !== requestId ||
      !['groups', 'users', 'memberships', 'payees', 'transactions', 'reconciliation_proposals', 'operator_notes'].includes(value.resource_type) ||
      !receiptResourceId(value.resource_type, value.resource_id) || !Number.isSafeInteger(value.version) || value.version < 1) unavailable();
}
function recovery(value, principalId, key) {
  marker(value);
  if (!['succeeded', 'unconfirmed', 'cancelled', 'not_found'].includes(value.status)) unavailable();
  if (value.status === 'not_found') {
    if (value.request_id !== undefined || value.receipt !== undefined) unavailable();
  } else {
    if (value.request_id !== canonicalRequestId(principalId, key)) unavailable();
    if (value.status === 'succeeded') receipt(value.receipt, value.request_id);
    else if (value.receipt !== null) unavailable();
  }
  return { ...value, recovery: { automatic_retry: false, write_permitted: false,
    guidance: value.status === 'succeeded' ? 'Use the retained receipt and review the recorded resource.' :
      value.status === 'cancelled' ? 'The original key is retained as cancelled; do not replay it.' :
      'Keep the original key and review its state in Admin. Absence or uncertainty is not permission to replay or create a replacement key.' } };
}

export const requestTools = [
  readTool('collect_admin_list_requests', 'Own request history',
    'Read one page of the current operator’s retained request aliases and receipts. Never another account’s history.',
    schema(page), args => {
      strictKeys(args, ['limit', 'offset']);
      const requested = paging(args);
      return {
        permission: 'account.manage',
        read: async ({ get, user }) => {
          const value = validatePage(await get(`/api/admin/operations/requests?${pageQuery(requested)}`), requested);
          for (const row of value.rows) {
            if (!isRequestKey(row.idempotency_key) || row.id !== canonicalRequestId(user.principalId, row.idempotency_key) ||
                !['succeeded', 'unconfirmed', 'cancelled'].includes(row.status)) unavailable();
            if (row.status === 'succeeded') receipt(row.receipt, row.id);
            else if (row.receipt !== null) unavailable();
          }
          return value;
        },
      };
    }),
  readTool('collect_admin_get_request_status', 'Exact request recovery status',
    'Read the exact ORIGINAL idempotency key under the current canonical principal. Distinguishes succeeded, unconfirmed, cancelled and not_found. Never retries/cancels an operation or creates another key; not_found does not prove a write failed.',
    schema({ idempotency_key: { type: 'string', pattern: REQUEST_KEY.source } }, ['idempotency_key']), args => {
      strictKeys(args, ['idempotency_key']);
      const key = args.idempotency_key;
      if (!isRequestKey(key)) invalid();
      return {
        permission: 'account.manage',
        read: async ({ get, user }) => recovery(await get(`/api/admin/operations/requests/${key}`), user.principalId, key),
      };
    }),
];
