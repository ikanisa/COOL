/* eslint-disable no-control-regex -- Reject control characters in an audit reason. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import { clearPending, readPending, retainPending, type PendingAttempt, type PendingIdentity } from '../core';
import { parseGrantDetail, type ReceiverGrant } from './contracts';
import { withPendingFence, type FenceAccess, type FenceLock } from './pendingFence';

const FAMILY = 'receiver-capture-grant', PERMISSION = 'gateway.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const receiptSchema = z.object({request_id: z.string().regex(UUID), resource_type: z.literal('receiver_capture_grants'), resource_id: z.string().regex(UUID), version: z.literal(2), status: z.literal('succeeded')}).strict();
export interface ReceiverGrantActionContext {
  request: AdminRequest;
  identity: PendingIdentity;
  grant: ReceiverGrant;
  canManage: boolean;
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger';
  /** Remains false until this backend and cross-version recovery are qualified. */
  enabled: boolean;
  isCurrent: () => boolean;
  storage?: Storage;
  sharedStorage?: Storage;
  lock?: FenceLock;
  createKey?: () => string;
}
export type GrantPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export interface GrantReceipt {requestId: string; grantId: string; version: 2;}
export type GrantResult = {status: 'succeeded'; receipt: GrantReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: GrantPending};
export type GrantLookup = {status: 'succeeded'; receipt: GrantReceipt} | {status: 'not_found'; retryAvailable: boolean};

function fail(message: string): never {throw new Error(message);}
function check(context: ReceiverGrantActionContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.identity.role === 'staff' || !context.identity.permissions.includes('gateway.read') || !context.identity.permissions.includes(PERMISSION) || !context.canManage || context.financialModel !== 'transaction_journals' || !Number.isFinite(expires) || expires <= Date.now() || !UUID.test(context.grant.id)) fail('This action is unavailable to your current account.');
}
function reasonText(reason: string): string {
  const value = reason.trim();
  if ([...value].length < 8 || value.length > 1000 || /[\x00-\x1f\x7f]/.test(value)) fail('Provide a reason of 8 to 1000 characters.');
  return value;
}
function verifyAttempt(attempt: PendingAttempt, context: ReceiverGrantActionContext) {
  if (attempt.family !== FAMILY || attempt.resource_id !== context.grant.id || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key) || Object.keys(attempt.intent).length !== 2 || attempt.intent.expected_version !== 1 || typeof attempt.intent.reason !== 'string' || reasonText(attempt.intent.reason) !== attempt.intent.reason) fail('The original request could not be verified.');
}
function receipt(value: unknown, grantId: string): GrantReceipt {
  const parsed = receiptSchema.parse(value);
  if (parsed.resource_id !== grantId) fail('The original request receipt could not be verified.');
  return {requestId: parsed.request_id, grantId: parsed.resource_id, version: parsed.version};
}
async function withFence<T>(context: ReceiverGrantActionContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: FAMILY, resourceId: context.grant.id, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restoreUnderFence(context: ReceiverGrantActionContext, access: FenceAccess): Promise<GrantPending> {
  check(context);
  const fence = access.read();
  if (fence.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, FAMILY, context.grant.id, context.storage);
  if (attempt) verifyAttempt(attempt, context);
  check(context);
  if (fence.kind === 'owned') {
    if (attempt && attempt.request_key !== fence.requestKey) fail('The original request could not be verified.');
    return {kind: 'owned', requestKey: fence.requestKey, attempt};
  }
  if (attempt) {access.reserve(attempt.request_key, fence.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};}
  return {kind: 'ready', revision: fence.revision};
}
export async function restoreGrantRevocation(context: ReceiverGrantActionContext): Promise<GrantPending> {
  check(context);
  return withFence(context, (access) => restoreUnderFence(context, access));
}
async function clear(context: ReceiverGrantActionContext, access: FenceAccess, pending: Extract<GrantPending, {kind: 'owned'}>) {
  if (pending.attempt) await clearPending(context.identity, FAMILY, context.grant.id, pending.requestKey, context.storage);
  check(context);
  access.clear(pending.requestKey);
}
async function lookupUnderFence(context: ReceiverGrantActionContext, pending: Extract<GrantPending, {kind: 'owned'}>): Promise<GrantLookup> {
  const body = await context.request(`gateway/receiver-requests/${pending.requestKey}`);
  check(context);
  if (body.found === false && Object.keys(body).length === 1) return {status: 'not_found', retryAvailable: pending.attempt !== null};
  if (body.found !== true || Object.keys(body).length !== 2 || !Object.hasOwn(body, 'receipt')) fail('The original request receipt could not be verified.');
  return {status: 'succeeded', receipt: receipt(body.receipt, context.grant.id)};
}
async function settle(context: ReceiverGrantActionContext, access: FenceAccess, pending: Extract<GrantPending, {kind: 'owned'}>, value: GrantReceipt): Promise<GrantResult> {
  await clear(context, access, pending);
  return {status: 'succeeded', receipt: value};
}
/** A new change is recorded before sending. It is never automatically replayed. */
export async function submitGrantRevocation(context: ReceiverGrantActionContext, reason: string, observedRevision: string): Promise<GrantResult> {
  if (!context.enabled) fail('This action is not enabled for the current workspace.');
  check(context);
  const why = reasonText(reason);
  if (context.grant.status !== 'active' || context.grant.version !== 1 || !context.grant.capture_authority) fail('Refresh the active grant before reviewing it.');
  return withFence(context, async (access) => {
    check(context);
    const existing = await restoreUnderFence(context, access);
    if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const requestKey = (context.createKey ?? (() => crypto.randomUUID()))();
    if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    const intent = {expected_version: 1, reason: why};
    access.reserve(requestKey, observedRevision);
    let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, FAMILY, context.grant.id, requestKey, PERMISSION, intent, context.storage);}
    catch (error) {if (context.isCurrent()) access.clear(requestKey); throw error;}
    verifyAttempt(attempt, context);
    const pending: Extract<GrantPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent()) return {status: 'unknown', requestKey};
    try {
      const response = await context.request(`gateway/receiver-grants/${context.grant.id}/revoke`, {method: 'POST', body: intent, idempotencyKey: requestKey});
      check(context);
      return await settle(context, access, pending, receipt(response, context.grant.id));
    } catch {return {status: 'unknown', requestKey};}
  });
}
/** A missing receipt retains the key and intent. A confirmed receipt clears both. */
export async function lookupGrantRevocation(context: ReceiverGrantActionContext, pending: GrantPending): Promise<GrantLookup> {
  check(context);
  if (pending.kind !== 'owned') fail('The original account must check this request.');
  return withFence(context, async (access) => {
    let stored = await restoreUnderFence(context, access);
    if (stored.kind === 'ready') {access.reserve(pending.requestKey, stored.revision); stored = {kind: 'owned', requestKey: pending.requestKey, attempt: null};}
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey) fail('The original request could not be verified.');
    const result = await lookupUnderFence(context, stored);
    if (result.status === 'succeeded') await clear(context, access, stored);
    return result;
  });
}
/** Explicit retry uses the same key and stored intent after another fresh lookup and grant check. */
export async function retryGrantRevocation(context: ReceiverGrantActionContext, pending: GrantPending): Promise<GrantResult> {
  if (!context.enabled) fail('This action is not enabled for the current workspace.');
  check(context);
  if (pending.kind !== 'owned' || !pending.attempt) fail('The original request intent is unavailable.');
  return withFence(context, async (access) => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original request could not be verified.');
    const previous = await lookupUnderFence(context, stored);
    if (previous.status === 'succeeded') return settle(context, access, stored, previous.receipt);
    const current = parseGrantDetail(await context.request(`gateway/receiver-grants/${context.grant.id}?limit=25&offset=0`), context.grant.id, context.identity.id, true, 0);
    check(context);
    const grant = current.resource;
    if (!current.canManage || grant.status !== 'active' || grant.version !== stored.attempt.intent.expected_version || grant.device_id !== context.grant.device_id || grant.payee_id !== context.grant.payee_id || grant.installation_id !== context.grant.installation_id || grant.key_sha256 !== context.grant.key_sha256) fail('The original capture grant changed. Check its receipt before continuing.');
    try {
      const response = await context.request(`gateway/receiver-grants/${grant.id}/revoke`, {method: 'POST', body: stored.attempt.intent, idempotencyKey: stored.requestKey});
      check(context);
      return await settle(context, access, stored, receipt(response, grant.id));
    } catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
