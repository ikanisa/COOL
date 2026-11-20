/* eslint-disable no-control-regex -- Reject prohibited control characters in cancellation reasons. */
import type {AdminRequest} from '../../api/client';
import {clearPending, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity} from '../core/pendingAttempt';
import {withPendingFence, type FenceAccess, type FenceLock} from '../operations/pendingFence';
import {parseLookup, validRequestKey, type RequestLookup} from './contracts';

export const CANCELLATION_FAMILY = 'request-cancellation-v1';
const PERMISSION = 'account.manage';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;

export interface CancellationContext {
  request: AdminRequest;
  identity: PendingIdentity;
  principalId: string;
  targetKey: string;
  financialModel: 'canonical_evidence_ledger' | 'transaction_journals';
  enabled: boolean;
  isEnabled?: () => boolean;
  isCurrent: () => boolean;
  verifyFresh: () => Promise<boolean>;
  storage?: Storage;
  sharedStorage?: Storage;
  lock?: FenceLock;
  createKey?: () => string;
}

export type CancellationPending = {kind: 'ready'; revision: string} |
  {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type CancellationResult = {status: 'confirmed'; outcome: RequestLookup} |
  {status: 'target_changed'; outcome: RequestLookup} | {status: 'unknown'; requestKey: string} |
  {status: 'existing'; pending: CancellationPending};

function fail(message: string): never {throw new Error(message);}
function current(context: CancellationContext) {
  const expiry = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'canonical_evidence_ledger' || !UUID.test(context.principalId) ||
      !validRequestKey(context.targetKey) || !['overview.read', PERMISSION].every((permission) => context.identity.permissions.includes(permission)) ||
      !Number.isFinite(expiry) || expiry <= Date.now()) fail('Request cancellation is unavailable to this account.');
}
function write(context: CancellationContext) {
  current(context);
  if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Request cancellation is not enabled.');
}
export function cancellationReason(value: string): string {
  const reason = value.trim();
  if (reason.length < 8 || reason.length > 500 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(reason)) fail('Provide a cancellation reason of 8 to 500 characters.');
  return reason;
}
class CurrentStorage implements Storage {
  constructor(private readonly base: Storage, private readonly context: CancellationContext) {}
  get length() {return 0;}
  clear(): void {throw new Error('Unsupported recovery operation.');}
  key(): string | null {return null;}
  getItem(key: string): string | null {current(this.context); return this.base.getItem(key);}
  setItem(key: string, value: string): void {current(this.context); this.base.setItem(key, value);}
  removeItem(key: string): void {current(this.context); this.base.removeItem(key);}
}
function storage(context: CancellationContext): Storage {return new CurrentStorage(context.storage ?? sessionStorage, context);}
async function principalHash(context: CancellationContext): Promise<string> {
  const hash = await sha256Text(`collect-admin-cancellation-principal-v1:${context.principalId}`); current(context); return hash;
}
async function validIntent(context: CancellationContext, attempt: PendingAttempt): Promise<boolean> {
  if (attempt.family !== CANCELLATION_FAMILY || attempt.resource_id !== context.targetKey || attempt.permission !== PERMISSION ||
      !UUID.test(attempt.request_key) || attempt.request_key === context.targetKey || Object.keys(attempt.intent).length !== 3 ||
      attempt.intent.model !== 'canonical_evidence_ledger' || typeof attempt.intent.principal_sha256 !== 'string' || !HASH.test(attempt.intent.principal_sha256) ||
      typeof attempt.intent.reason !== 'string') return false;
  try {if (cancellationReason(attempt.intent.reason) !== attempt.intent.reason) return false;} catch {return false;}
  return attempt.intent.principal_sha256 === await principalHash(context);
}
async function fence<T>(context: CancellationContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  current(context);
  return withPendingFence({identity: context.identity, family: CANCELLATION_FAMILY, resourceId: context.targetKey,
    isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restore(context: CancellationContext, access: FenceAccess): Promise<CancellationPending> {
  current(context);
  const state = access.read();
  if (state.kind === 'foreign') return {kind: 'foreign'};
  const saved = await readPending(context.identity, CANCELLATION_FAMILY, context.targetKey, storage(context));
  const attempt = saved && await validIntent(context, saved) ? saved : null;
  current(context);
  if (state.kind === 'owned') {
    if (saved && saved.request_key !== state.requestKey) fail('The original cancellation could not be verified.');
    return {kind: 'owned', requestKey: state.requestKey, attempt};
  }
  if (saved) {
    if (!UUID.test(saved.request_key)) fail('The original cancellation could not be verified.');
    access.reserve(saved.request_key, state.revision);
    return {kind: 'owned', requestKey: saved.request_key, attempt};
  }
  return {kind: 'ready', revision: state.revision};
}
export async function restoreCancellation(context: CancellationContext): Promise<CancellationPending> {
  return fence(context, (access) => restore(context, access));
}
async function lookup(context: CancellationContext): Promise<RequestLookup> {
  current(context);
  const body = await context.request(`operations/requests/${context.targetKey}`);
  current(context);
  const outcome = await parseLookup(body, context.financialModel, context.principalId, context.targetKey);
  current(context);
  return outcome;
}
/** A target lookup is read-only and does not prove which cancellation key made an alias. */
export async function checkCancellation(context: CancellationContext, pending: CancellationPending): Promise<RequestLookup> {
  if (pending.kind !== 'owned') fail('The original cancellation owner must check this request.');
  return fence(context, async (access) => {
    const saved = await restore(context, access);
    if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey) fail('The original cancellation could not be verified.');
    return lookup(context);
  });
}
async function dispatch(context: CancellationContext, access: FenceAccess, saved: Extract<CancellationPending, {kind: 'owned'}>): Promise<CancellationResult> {
  if (!saved.attempt || !await validIntent(context, saved.attempt)) fail('The original cancellation intent is unavailable.');
  try {
    write(context);
    const response = await context.request(`operations/requests/${context.targetKey}/cancel`, {method: 'POST',
      body: {reason: saved.attempt.intent.reason}, idempotencyKey: saved.requestKey});
    current(context);
    const recorded = await parseLookup(response, context.financialModel, context.principalId, context.targetKey);
    if (!['succeeded', 'cancelled'].includes(recorded.status)) fail('The cancellation response was not terminal.');
    const outcome = await lookup(context);
    if (JSON.stringify(recorded) !== JSON.stringify(outcome)) fail('The original request status changed.');
    await clearPending(context.identity, CANCELLATION_FAMILY, context.targetKey, saved.requestKey, storage(context));
    current(context); access.clear(saved.requestKey);
    return {status: 'confirmed', outcome};
  } catch {return {status: 'unknown', requestKey: saved.requestKey};}
}
/** Check the target, retain the separate cancellation key and exact intent, then submit once. */
export async function submitCancellation(context: CancellationContext, reason: string, observedRevision: string): Promise<CancellationResult> {
  write(context); const trimmed = cancellationReason(reason);
  return fence(context, async (access) => {
    const pending = await restore(context, access);
    if (pending.kind !== 'ready') return {status: 'existing', pending};
    const outcome = await lookup(context);
    if (outcome.status === 'unconfirmed') fail('The original request is still unconfirmed.');
    if (outcome.status !== 'not_found') return {status: 'target_changed', outcome};
    write(context); if (!await context.verifyFresh()) fail('Complete current verification before cancellation.'); write(context);
    const key = (context.createKey ?? (() => crypto.randomUUID()))();
    if (!UUID.test(key) || key === context.targetKey) fail('A separate secure cancellation reference is unavailable.');
    const intent = {reason: trimmed, model: 'canonical_evidence_ledger', principal_sha256: await principalHash(context)};
    write(context); access.reserve(key, observedRevision);
    let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, CANCELLATION_FAMILY, context.targetKey, key, PERMISSION, intent, storage(context));}
    catch {return {status: 'unknown', requestKey: key};}
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey: key};
    return dispatch(context, access, {kind: 'owned', requestKey: key, attempt});
  });
}
/** A deliberate same-key retry is a write and may cancel an as-yet uncommitted original. */
export async function retryCancellation(context: CancellationContext, pending: CancellationPending): Promise<CancellationResult> {
  write(context);
  if (pending.kind !== 'owned' || !pending.attempt) fail('The original cancellation intent is unavailable.');
  return fence(context, async (access) => {
    const saved = await restore(context, access);
    if (saved.kind !== 'owned' || !saved.attempt || saved.requestKey !== pending.requestKey ||
        JSON.stringify(saved.attempt.intent) !== JSON.stringify(pending.attempt!.intent)) fail('The original cancellation could not be verified.');
    const outcome = await lookup(context);
    if (outcome.status === 'unconfirmed') fail('The original request is still unconfirmed.');
    if (!['not_found', 'succeeded', 'cancelled'].includes(outcome.status)) fail('The original request status could not be verified.');
    write(context); if (!await context.verifyFresh()) fail('Complete current verification before retrying cancellation.'); write(context);
    return dispatch(context, access, saved);
  });
}
