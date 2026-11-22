/* eslint-disable no-control-regex -- Reject control characters in an audit reason. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import type {PendingAttempt} from '../core/pendingAttempt';
import { parseGrantDetail, type ReceiverGrant } from './contracts';

import type {FenceAccess} from './pendingFence';
import {operationRequestCustody, type OperationPending, type OperationRequestContext} from './operationRequestCustody';

const FAMILY = 'receiver-capture-grant', PERMISSION = 'gateway.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const receiptSchema = z.object({request_id: z.string().regex(UUID), resource_type: z.literal('receiver_capture_grants'), resource_id: z.string().regex(UUID), version: z.literal(2), status: z.literal('succeeded')}).strict();
export interface ReceiverGrantActionContext extends OperationRequestContext {
  request: AdminRequest;
  grant: ReceiverGrant;
  canManage: boolean;
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger';
  /** Remains false until this backend and cross-version recovery are qualified. */
  enabled: boolean;
}
export type GrantPending = OperationPending;
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
const { withFence, restore: restoreUnderFence, lookupOriginal, requireOriginal, retain, clear } = operationRequestCustody<ReceiverGrantActionContext>({
  family: FAMILY,
  permission: PERMISSION,
  resourceId: context => context.grant.id,
  check: check,
  verifyAttempt: (context, attempt) => verifyAttempt(attempt, context),
  invalidMessage: 'The original request could not be verified.',
});

export async function restoreGrantRevocation(context: ReceiverGrantActionContext): Promise<GrantPending> {
  check(context);
  return withFence(context, (access) => restoreUnderFence(context, access));
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
    const intent = {expected_version: 1, reason: why};
    const pending = await retain(context, access, observedRevision, {...intent});
    const {requestKey} = pending;
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
    const stored = await lookupOriginal(context, access, pending.requestKey);
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
  const original = pending.attempt;
  return withFence(context, async (access) => {
    const stored = await requireOriginal(context, access, pending.requestKey, original);
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
