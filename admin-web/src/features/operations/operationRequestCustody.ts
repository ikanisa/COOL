import {clearPending, readPending, retainPending, type PendingAttempt, type PendingIdentity} from '../core/pendingAttempt';
import {withPendingFence, type FenceAccess, type FenceLock} from './pendingFence';

const REQUEST_KEY = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;

export interface OperationRequestContext {
  identity: PendingIdentity;
  isCurrent: () => boolean;
  storage?: Storage;
  sharedStorage?: Storage;
  lock?: FenceLock;
  createKey?: () => string;
}

export type OwnedOperationRequest = {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null};
type RetainedOperationRequest = OwnedOperationRequest & {attempt: PendingAttempt};
export type OperationPending = {kind: 'ready'; revision: string} | OwnedOperationRequest | {kind: 'foreign'};

interface CustodyPolicy<Context> {
  family: string;
  permission: string;
  resourceId: (context: Context) => string;
  check: (context: Context) => void;
  verifyAttempt: (context: Context, attempt: PendingAttempt) => unknown;
  invalidMessage: string;
}

function sameIntent(left: PendingAttempt, right: PendingAttempt) {
  return left.permission === right.permission && JSON.stringify(left.intent) === JSON.stringify(right.intent);
}

/** Owns the tab's stored intent and its same-origin reservation. Callers still
 * decide which server response is terminal and whether a retry can write. */
export function operationRequestCustody<Context extends OperationRequestContext>(policy: CustodyPolicy<Context>) {
  const {family, permission, resourceId, check, verifyAttempt, invalidMessage} = policy;
  const read = (context: Context) => readPending(context.identity, family, resourceId(context), context.storage);

  function withFence<Result>(context: Context, work: (access: FenceAccess) => Promise<Result>) {
    return withPendingFence({
      identity: context.identity, family, resourceId: resourceId(context), isCurrent: context.isCurrent,
      storage: context.sharedStorage, lock: context.lock,
    }, work);
  }

  async function restore(context: Context, access: FenceAccess): Promise<OperationPending> {
    check(context);
    const fence = access.read();
    if (fence.kind === 'foreign') return {kind: 'foreign'};
    const attempt = await read(context);
    if (attempt) await verifyAttempt(context, attempt);
    check(context);
    if (fence.kind === 'owned') {
      if (attempt && attempt.request_key !== fence.requestKey) throw new Error(invalidMessage);
      return {kind: 'owned', requestKey: fence.requestKey, attempt};
    }
    if (!attempt) return {kind: 'ready', revision: fence.revision};
    access.reserve(attempt.request_key, fence.revision);
    return {kind: 'owned', requestKey: attempt.request_key, attempt};
  }

  async function lookupOriginal(context: Context, access: FenceAccess, requestKey: string): Promise<OwnedOperationRequest> {
    const pending = await restore(context, access);
    if (pending.kind === 'ready') {
      access.reserve(requestKey, pending.revision);
      return {kind: 'owned', requestKey, attempt: null};
    }
    if (pending.kind !== 'owned' || pending.requestKey !== requestKey) throw new Error(invalidMessage);
    return pending;
  }

  async function requireOriginal(context: Context, access: FenceAccess, requestKey: string, attempt: PendingAttempt): Promise<RetainedOperationRequest> {
    const saved = await restore(context, access);
    if (saved.kind !== 'owned' || saved.requestKey !== requestKey || !saved.attempt || !sameIntent(saved.attempt, attempt)) {
      throw new Error(invalidMessage);
    }
    return {...saved, attempt: saved.attempt};
  }

  async function clear(context: Context, access: FenceAccess, pending: OwnedOperationRequest) {
    check(context);
    if (pending.attempt) {
      const original = pending.attempt;
      await clearPending(context.identity, family, resourceId(context), pending.requestKey, context.storage, undefined,
        attempt => {
          check(context);
          return sameIntent(attempt, original);
        });
    }
    check(context);
    access.clear(pending.requestKey);
  }

  async function retain(context: Context, access: FenceAccess, observedRevision: string, intent: Record<string, unknown>): Promise<RetainedOperationRequest> {
    check(context);
    const requestKey = (context.createKey ?? (() => globalThis.crypto?.randomUUID?.()))();
    if (!requestKey || !REQUEST_KEY.test(requestKey)) throw new Error('A secure request reference is unavailable.');
    const resource = resourceId(context);
    access.reserve(requestKey, observedRevision);
    try {
      const attempt = await retainPending(context.identity, family, resource, requestKey, permission, intent, context.storage);
      await verifyAttempt(context, attempt);
      return {kind: 'owned', requestKey, attempt};
    } catch (error) {
      if (context.isCurrent()) {
        try {
          const saved = await read(context);
          if (!saved || saved.request_key === requestKey) {
            await clear(context, access, {kind: 'owned', requestKey, attempt: saved});
          }
        } catch {
          // A failed write can reach storage before read-back fails. Keep the
          // shared reservation until cleanup of the exact key is verified.
        }
      }
      throw error;
    }
  }

  return {withFence, restore, lookupOriginal, requireOriginal, retain, clear};
}
