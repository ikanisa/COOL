import { clearPending, type PendingAttempt, type PendingIdentity } from '../core/pendingAttempt';

export function sameReconciliationAttempt(current: PendingAttempt | null, original: PendingAttempt): boolean {
  return current !== null && current.family === original.family && current.resource_id === original.resource_id &&
    current.request_key === original.request_key && current.permission === original.permission &&
    current.created_at === original.created_at && JSON.stringify(current.intent) === JSON.stringify(original.intent);
}

export async function clearOriginalReconciliationAttempt(identity: PendingIdentity, original: PendingAttempt,
  isCurrent: () => boolean, storage?: Storage): Promise<void> {
  // clearPending checks this after its asynchronous authority digest and immediately before storage mutation.
  await clearPending(identity, original.family, original.resource_id, original.request_key, storage, undefined,
    current => isCurrent() && Date.parse(identity.expiresAt) > Date.now() && sameReconciliationAttempt(current, original));
}
