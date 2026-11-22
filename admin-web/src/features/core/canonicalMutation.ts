import {parseLookup} from '../requests/contracts';
import {isId, isObject} from './contracts';
import {canonicalRequestId, clearPending, type PendingAttempt, type PendingIdentity} from './pendingAttempt';
import type {AdminRequest} from './types';

interface ReceiptExpectation {
  resourceType: 'groups' | 'users' | 'payees' | 'memberships' | 'transactions';
  version: number;
  resourceId?: string;
}

export async function matchesCanonicalReceipt(
  value: unknown,
  principalId: string,
  key: string,
  {resourceType, resourceId, version}: ReceiptExpectation,
): Promise<boolean> {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' &&
    value.resource_type === resourceType && value.version === version &&
    (resourceId === undefined ? isId(value.resource_id) : value.resource_id === resourceId) &&
    value.request_id === await canonicalRequestId(principalId, key);
}

export async function lookupCanonicalMutation(request: AdminRequest, principalId: string, key: string) {
  const response = await request(`operations/requests/${key}`);
  const {status} = await parseLookup(response, 'canonical_evidence_ledger', principalId, key);
  // Mutation recovery also verifies the original resource and version.
  return {status, receipt: response.receipt};
}

export function clearOriginalAttempt(
  identity: PendingIdentity,
  original: PendingAttempt,
  isCurrent: () => boolean,
): Promise<void> {
  return clearPending(identity, original.family, original.resource_id, original.request_key, undefined, undefined,
    retained => isCurrent() && retained.permission === original.permission && retained.created_at === original.created_at &&
      JSON.stringify(retained.intent) === JSON.stringify(original.intent));
}
