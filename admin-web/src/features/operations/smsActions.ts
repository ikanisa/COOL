/* eslint-disable no-control-regex -- Reject control characters in review reasons and source metadata. */
import type { AdminRequest } from '../../api/client';
import type {PendingAttempt} from '../core/pendingAttempt';
import type { SmsReceipt } from './contracts';

import {operationRequestCustody, type OperationPending, type OperationRequestContext} from './operationRequestCustody';

const FAMILY = 'sms-extraction';
const PERMISSION = 'sms.extract';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;

export interface SmsActionContext extends OperationRequestContext {
  request: AdminRequest;
  source: SmsReceipt;
  /** Must remain false until the selected backend, old tabs and recovery are qualified. */
  enabled: boolean;
}

export type SmsPending = OperationPending;
export type ExtractionResult =
  | {status: 'succeeded'; requestKey: string; receipt: ExtractionReceipt}
  | {status: 'unknown'; requestKey: string}
  | {status: 'existing'; pending: SmsPending};
export interface ExtractionReceipt { requestId: string; factId: string; sourceKind: string; sourceId: string; }
export type ExtractionLookup = {status: 'succeeded'; receipt: ExtractionReceipt} | {status: 'failed' | 'pending' | 'not_found'};

function fail(message: string): never { throw new Error(message); }
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function exact(value: Record<string, unknown>, keys: string[]) { return Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key)); }
function reasonText(reason: string): string {
  const value = reason.trim();
  if (value.length < 8 || reason.length > 1000 || /[\x00-\x1f\x7f]/.test(reason)) fail('Provide a reason of 8 to 1000 characters.');
  return value;
}
function resource(source: SmsReceipt) { return `${source.source_kind}:${source.id}`; }
function checkCurrent(context: SmsActionContext, permission: string) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.identity.role === 'staff' || !context.identity.permissions.includes(permission) || !Number.isFinite(expires) || expires <= Date.now()) fail('This action is unavailable to your current account.');
}
function assertAttempt(attempt: PendingAttempt, source: SmsReceipt) {
  if (attempt.family !== FAMILY || attempt.resource_id !== resource(source) || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key) ||
      !exact(attempt.intent, ['reason', 'expected_source_sha256']) || typeof attempt.intent.reason !== 'string' ||
      reasonText(attempt.intent.reason) !== attempt.intent.reason || typeof attempt.intent.expected_source_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(attempt.intent.expected_source_sha256)) fail('The original request could not be verified.');
}
function receipt(value: unknown, source: SmsReceipt): ExtractionReceipt {
  if (!object(value) || !exact(value, ['request_id', 'status', 'resource_type', 'resource_id', 'source_kind', 'source_id', 'parser_version']) ||
      value.status !== 'succeeded' || value.resource_type !== 'sms_facts' || value.parser_version !== 'collect-admin-source-facts-v1' ||
      value.source_kind !== source.source_kind || value.source_id !== source.id || typeof value.request_id !== 'string' || !UUID.test(value.request_id) ||
      typeof value.resource_id !== 'string' || !UUID.test(value.resource_id)) fail('The extraction receipt could not be verified.');
  return {requestId: value.request_id, factId: value.resource_id, sourceKind: source.source_kind, sourceId: source.id};
}
const { withFence, restore: restoreUnderFence, lookupOriginal, retain, clear } = operationRequestCustody<SmsActionContext>({
  family: FAMILY,
  permission: PERMISSION,
  resourceId: context => resource(context.source),
  check: context => checkCurrent(context, PERMISSION),
  verifyAttempt: (context, attempt) => assertAttempt(attempt, context.source),
  invalidMessage: 'The original request could not be verified.',
});

export async function restoreSmsExtraction(context: SmsActionContext): Promise<SmsPending> {
  checkCurrent(context, PERMISSION);
  return withFence(context, (access) => restoreUnderFence(context, access));
}

/** Persists the original key before dispatch and never automatically replays it. */
export async function submitSmsExtraction(context: SmsActionContext, reason: string, observedRevision: string): Promise<ExtractionResult> {
  if (!context.enabled) fail('This action is not enabled for the current workspace.');
  checkCurrent(context, PERMISSION);
  const trimmed = reasonText(reason);
  return withFence(context, async (access) => {
    checkCurrent(context, PERMISSION);
    const existing = await restoreUnderFence(context, access);
    if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const intent = {reason: trimmed, expected_source_sha256: context.source.source_sha256};
    const retained = await retain(context, access, observedRevision, intent);
    const {requestKey} = retained;
    if (!context.isCurrent()) return {status: 'unknown', requestKey};
    try {
      const body = await context.request(`sms/receipts/${context.source.source_kind}/${context.source.id}/extract`, {method: 'POST', body: intent, idempotencyKey: requestKey});
      if (!context.isCurrent()) return {status: 'unknown', requestKey};
      const saved = receipt(body, context.source);
      await clear(context, access, retained);
      return {status: 'succeeded', requestKey, receipt: saved};
    } catch { return {status: 'unknown', requestKey}; }
  });
}

/** Lookup preserves an unresolved or not-found key; only a verified terminal result clears it. */
export async function lookupSmsExtraction(context: SmsActionContext, pending: SmsPending): Promise<ExtractionLookup> {
  checkCurrent(context, 'sms.read');
  if (pending.kind !== 'owned') fail('The original account must check this request.');
  return withFence(context, async (access) => {
    checkCurrent(context, 'sms.read');
    const stored = await lookupOriginal(context, access, pending.requestKey);
    const body = await context.request(`sms/requests/${pending.requestKey}`);
    if (!context.isCurrent()) fail('Your account changed. Check the original request.');
    if (body.status === 'not_found' && exact(body, ['status'])) return {status: 'not_found'};
    if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id) || !['pending', 'succeeded', 'failed'].includes(String(body.status))) fail('The original request response could not be verified.');
    if (body.status === 'succeeded') {
      const saved = receipt(body.receipt, context.source);
      if (saved.requestId !== body.request_id) fail('The original request response could not be verified.');
      await clear(context, access, stored);
      return {status: 'succeeded', receipt: saved};
    }
    if (body.receipt !== null) fail('The original request response could not be verified.');
    if (body.status === 'failed') {
      await clear(context, access, stored);
      return {status: 'failed'};
    }
    return {status: 'pending'};
  });
}

export interface RevealedSms {sender: string; body: string;}
export async function revealSmsSource(context: SmsActionContext, reason: string): Promise<RevealedSms> {
  if (!context.enabled) fail('This action is not enabled for the current workspace.');
  checkCurrent(context, 'sms.reveal');
  const body = await context.request(`sms/receipts/${context.source.source_kind}/${context.source.id}/content`, {reviewReason: reasonText(reason)});
  checkCurrent(context, 'sms.reveal');
  if (!exact(body, ['source_kind', 'source_id', 'raw_sender', 'raw_body', 'source_sha256', 'evidence_level', 'provider_confirmation']) ||
      body.source_kind !== context.source.source_kind || body.source_id !== context.source.id || body.source_sha256 !== context.source.source_sha256 ||
      body.evidence_level !== context.source.evidence_level || body.provider_confirmation !== false ||
      typeof body.raw_sender !== 'string' || !body.raw_sender.trim() || body.raw_sender.length > 96 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(body.raw_sender) ||
      typeof body.raw_body !== 'string' || !body.raw_body || body.raw_body.includes('\u0000') || new TextEncoder().encode(body.raw_body).byteLength > 16384) fail('The source content could not be verified.');
  return {sender: body.raw_sender, body: body.raw_body};
}
