/* eslint-disable no-control-regex -- Reject control characters in an audit reason. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import {canonicalRequestId, type PendingAttempt} from '../core/pendingAttempt';
import { type FinancialModel } from '../core/types';
import { parseLookup } from '../requests/contracts';

import {operationRequestCustody, type OperationPending, type OperationRequestContext} from './operationRequestCustody';

const FAMILY = 'email-dispatch';
const RESOURCE = 'queue';
const PERMISSION = 'email.manage';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
export interface EmailDispatchContext extends OperationRequestContext {
  request: AdminRequest;
  financialModel: FinancialModel;
  principalId: string | null;
  /** Must remain false until backend, side effects and cross-version recovery are qualified. */
  enabled: boolean;
}
export interface EmailReceipt {requestId: string; accepted: number; uncertain: number; suppressed: number;}
export type EmailPending = OperationPending;
export type EmailDispatchResult = {status: 'succeeded'; requestKey: string; receipt: EmailReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: EmailPending};
export type EmailLookup = {status: 'succeeded'; receipt: EmailReceipt} | {status: 'pending' | 'unconfirmed' | 'failed' | 'cancelled' | 'not_found'};

const receiptSchema = z.object({
  request_id: z.string().regex(UUID), status: z.literal('succeeded'), resource_type: z.literal('email_dispatch'),
  resource_id: z.string().regex(UUID), version: z.literal(1), accepted: z.number().int().min(0).max(20),
  uncertain: z.number().int().min(0).max(20), suppressed: z.number().int().min(0).max(20),
}).strict().superRefine((value, ctx) => {
  if (value.resource_id !== value.request_id || value.accepted + value.uncertain + value.suppressed > 20) ctx.addIssue({code: 'custom', message: 'Invalid dispatch receipt.'});
});
function fail(message: string): never {throw new Error(message);}
function reasonText(reason: string) {
  const value = reason.trim();
  if (value.length < 8 || reason.length > 1000 || /[\x00-\x1f\x7f]/.test(reason)) fail('Provide a reason of 8 to 1000 characters.');
  return value;
}
function check(context: EmailDispatchContext, permission = PERMISSION) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.identity.role === 'staff' || !context.identity.permissions.includes(permission) || !Number.isFinite(expires) || expires <= Date.now()) fail('This action is unavailable to your current account.');
}
function assertAttempt(attempt: PendingAttempt) {
  if (attempt.family !== FAMILY || attempt.resource_id !== RESOURCE || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key) ||
      Object.keys(attempt.intent).length !== 1 || typeof attempt.intent.reason !== 'string' || reasonText(attempt.intent.reason) !== attempt.intent.reason) fail('The original request could not be verified.');
}
async function parseReceipt(input: unknown, context: EmailDispatchContext, key: string): Promise<EmailReceipt> {
  const value = receiptSchema.parse(input);
  if (context.financialModel === 'canonical_evidence_ledger' && (!context.principalId || value.request_id !== await canonicalRequestId(context.principalId, key))) fail('The dispatch receipt could not be verified.');
  return {requestId: value.request_id, accepted: value.accepted, uncertain: value.uncertain, suppressed: value.suppressed};
}
const { withFence, restore: restoreUnderFence, lookupOriginal, retain, clear } = operationRequestCustody<EmailDispatchContext>({
  family: FAMILY,
  permission: PERMISSION,
  resourceId: () => RESOURCE,
  check: check,
  verifyAttempt: (_context, attempt) => assertAttempt(attempt),
  invalidMessage: 'The original request could not be verified.',
});

export async function restoreEmailDispatch(context: EmailDispatchContext): Promise<EmailPending> {
  check(context);
  return withFence(context, (access) => restoreUnderFence(context, access));
}

export async function submitEmailDispatch(context: EmailDispatchContext, reason: string, observedRevision: string): Promise<EmailDispatchResult> {
  if (!context.enabled) fail('This action is not enabled for the current workspace.');
  check(context);
  const trimmed = reasonText(reason);
  return withFence(context, async (access) => {
    check(context);
    const existing = await restoreUnderFence(context, access);
    if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const intent = {reason: trimmed};
    const retained = await retain(context, access, observedRevision, intent);
    const {requestKey} = retained;
    if (!context.isCurrent()) return {status: 'unknown', requestKey};
    try {
      const body = await context.request('email/dispatch', {method: 'POST', body: intent, idempotencyKey: requestKey});
      if (!context.isCurrent()) return {status: 'unknown', requestKey};
      const saved = await parseReceipt(body, context, requestKey);
      await clear(context, access, retained);
      return {status: 'succeeded', requestKey, receipt: saved};
    } catch {return {status: 'unknown', requestKey};}
  });
}

export async function lookupEmailDispatch(context: EmailDispatchContext, pending: EmailPending): Promise<EmailLookup> {
  check(context, 'overview.read');
  if (pending.kind !== 'owned') fail('The original account must check this request.');
  return withFence(context, async (access) => {
    check(context, 'overview.read');
    const stored = await lookupOriginal(context, access, pending.requestKey);
    const body = await context.request(`operations/requests/${pending.requestKey}`);
    if (!context.isCurrent()) fail('Your account changed. Check the original request.');
    if (context.financialModel !== 'canonical_evidence_ledger') {
      const expected = body.status === 'not_found' ? ['status'] : ['status', 'request_id', 'receipt'];
      if (Object.keys(body).length !== expected.length || !expected.every((key) => Object.hasOwn(body, key)) || body.status !== 'succeeded' && body.status !== 'not_found' && body.receipt !== null) fail('The original request response could not be verified.');
    }
    const lookup = await parseLookup(body, context.financialModel, context.principalId, pending.requestKey);
    if (lookup.status === 'succeeded') {
      if (lookup.receipt?.resourceType !== 'email_dispatch') fail('The original request response could not be verified.');
      const saved = await parseReceipt(body.receipt, context, pending.requestKey);
      if (saved.requestId !== lookup.requestId) fail('The original request response could not be verified.');
      await clear(context, access, stored);
      return {status: 'succeeded', receipt: saved};
    }
    if (lookup.status === 'failed' || lookup.status === 'cancelled') {
      if (body.receipt !== null) fail('The original request response could not be verified.');
      await clear(context, access, stored);
      return {status: lookup.status};
    }
    if (lookup.status !== 'pending' && lookup.status !== 'unconfirmed' && lookup.status !== 'not_found') fail('The original request response could not be verified.');
    return {status: lookup.status};
  });
}
