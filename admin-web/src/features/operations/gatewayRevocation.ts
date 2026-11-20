/* eslint-disable no-control-regex -- Reject control characters in audit reasons. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import { clearPending, readPending, retainPending, type PendingAttempt, type PendingIdentity } from '../core';
import { parseGatewayDetail, type GatewayDevice } from './contracts';
import { withPendingFence, type FenceAccess, type FenceLock } from './pendingFence';

const FAMILY = 'gateway-device-revoke', PERMISSION = 'gateway.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const receiptSchema = z.object({request_id: z.string().regex(UUID), resource_type: z.literal('gateway_devices'), resource_id: z.string().regex(UUID), version: z.number().int().min(2).max(Number.MAX_SAFE_INTEGER), status: z.literal('succeeded')}).strict();
export interface GatewayRevocationContext {
  request: AdminRequest;
  identity: PendingIdentity;
  device: GatewayDevice;
  canManage: boolean;
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger';
  /** Remains false until the backend and cross-version recovery are qualified. */
  enabled: boolean;
  isCurrent: () => boolean;
  storage?: Storage;
  sharedStorage?: Storage;
  lock?: FenceLock;
  createKey?: () => string;
}
export interface GatewayRevocationIntent {expected_version: number; expected_key_sha256: string; expected_signing_certificate_sha256: string; reason: string;}
export interface GatewayRevocationReceipt {requestId: string; deviceId: string; version: number;}
export type GatewayRevocationPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type GatewayRevocationResult = {status: 'succeeded'; receipt: GatewayRevocationReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: GatewayRevocationPending};
export type GatewayRevocationLookup = {status: 'succeeded'; receipt: GatewayRevocationReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
function fail(message: string): never {throw new Error(message);}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));}
function check(context: GatewayRevocationContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.identity.role === 'staff' || !context.canManage || context.financialModel !== 'transaction_journals' || !['gateway.read', PERMISSION, 'overview.read'].every((permission) => context.identity.permissions.includes(permission)) || !Number.isFinite(expires) || expires <= Date.now() || !UUID.test(context.device.id)) fail('This action is unavailable to your current account.');
}
function reasonText(reason: string) {
  const value = reason.trim();
  if (value.length < 8 || value.length > 1000 || /[\x00-\x1f\x7f]/.test(value)) fail('Provide a reason of 8 to 1000 characters.');
  return value;
}
function verifyAttempt(attempt: PendingAttempt, context: GatewayRevocationContext): GatewayRevocationIntent {
  const value = attempt.intent;
  if (attempt.family !== FAMILY || attempt.resource_id !== context.device.id || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key) || !exact(value, ['expected_version', 'expected_key_sha256', 'expected_signing_certificate_sha256', 'reason']) ||
      typeof value.expected_version !== 'number' || !Number.isSafeInteger(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER ||
      typeof value.expected_key_sha256 !== 'string' || !HASH.test(value.expected_key_sha256) || typeof value.expected_signing_certificate_sha256 !== 'string' || !HASH.test(value.expected_signing_certificate_sha256) ||
      value.expected_key_sha256 !== context.device.key_sha256 || value.expected_signing_certificate_sha256 !== context.device.signing_certificate_sha256 || typeof value.reason !== 'string' || reasonText(value.reason) !== value.reason) fail('The original device request could not be verified.');
  return {expected_version: value.expected_version, expected_key_sha256: value.expected_key_sha256, expected_signing_certificate_sha256: value.expected_signing_certificate_sha256, reason: value.reason};
}
function parseReceipt(value: unknown, context: GatewayRevocationContext, attempt: PendingAttempt | null): GatewayRevocationReceipt {
  const parsed = receiptSchema.parse(value);
  if (parsed.resource_id !== context.device.id || attempt && parsed.version !== verifyAttempt(attempt, context).expected_version + 1) fail('The original device receipt could not be verified.');
  return {requestId: parsed.request_id, deviceId: parsed.resource_id, version: parsed.version};
}
async function withFence<T>(context: GatewayRevocationContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: FAMILY, resourceId: context.device.id, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restoreUnderFence(context: GatewayRevocationContext, access: FenceAccess): Promise<GatewayRevocationPending> {
  check(context); const fence = access.read();
  if (fence.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, FAMILY, context.device.id, context.storage);
  if (attempt) verifyAttempt(attempt, context);
  check(context);
  if (fence.kind === 'owned') {if (attempt && attempt.request_key !== fence.requestKey) fail('The original device request could not be verified.'); return {kind: 'owned', requestKey: fence.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, fence.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};}
  return {kind: 'ready', revision: fence.revision};
}
export async function restoreGatewayRevocation(context: GatewayRevocationContext): Promise<GatewayRevocationPending> {check(context); return withFence(context, (access) => restoreUnderFence(context, access));}
async function clear(context: GatewayRevocationContext, access: FenceAccess, pending: Extract<GatewayRevocationPending, {kind: 'owned'}>) {
  if (pending.attempt) await clearPending(context.identity, FAMILY, context.device.id, pending.requestKey, context.storage);
  check(context); access.clear(pending.requestKey);
}
async function currentDevice(context: GatewayRevocationContext) {
  const current = await parseGatewayDetail(await context.request(`gateway/devices/${context.device.id}`), context.device.id, context.identity.id, false);
  check(context);
  if (!current.canManage || current.resource.app_id !== context.device.app_id || current.resource.installation_id !== context.device.installation_id || current.resource.key_sha256 !== context.device.key_sha256 || current.resource.signing_certificate_sha256 !== context.device.signing_certificate_sha256) fail('The current device identity could not be verified.');
  return current.resource;
}
async function verifySaved(context: GatewayRevocationContext, saved: GatewayRevocationReceipt) {
  const device = await currentDevice(context);
  if (device.state !== 'revoked' || device.version !== saved.version) fail('The device revocation could not be verified.');
}
async function lookupUnderFence(context: GatewayRevocationContext, pending: Extract<GatewayRevocationPending, {kind: 'owned'}>): Promise<GatewayRevocationLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) return {status: 'not_found', retryAvailable: pending.attempt !== null};
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original device receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail('The original device receipt could not be verified.');
  const saved = parseReceipt(body.receipt, context, pending.attempt);
  if (saved.requestId !== body.request_id) fail('The original device receipt could not be verified.');
  await verifySaved(context, saved);
  return {status: 'succeeded', receipt: saved};
}
async function settle(context: GatewayRevocationContext, access: FenceAccess, pending: Extract<GatewayRevocationPending, {kind: 'owned'}>, saved: GatewayRevocationReceipt): Promise<GatewayRevocationResult> {
  await verifySaved(context, saved); await clear(context, access, pending); return {status: 'succeeded', receipt: saved};
}
export async function submitGatewayRevocation(context: GatewayRevocationContext, reason: string, observedRevision: string): Promise<GatewayRevocationResult> {
  if (!context.enabled) fail('This action is not enabled for the current workspace.');
  check(context); const why = reasonText(reason), device = context.device;
  if (!['pending', 'active'].includes(device.state) || !Number.isSafeInteger(device.version) || device.version < 1 || device.version >= Number.MAX_SAFE_INTEGER) fail('Refresh the current device before reviewing it.');
  const intent: GatewayRevocationIntent = {expected_version: device.version, expected_key_sha256: device.key_sha256, expected_signing_certificate_sha256: device.signing_certificate_sha256, reason: why};
  return withFence(context, async (access) => {
    const existing = await restoreUnderFence(context, access);
    if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const requestKey = (context.createKey ?? (() => crypto.randomUUID()))();
    if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision);
    let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, FAMILY, device.id, requestKey, PERMISSION, {...intent}, context.storage);} catch (error) {if (context.isCurrent()) access.clear(requestKey); throw error;}
    verifyAttempt(attempt, context);
    const pending: Extract<GatewayRevocationPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent()) return {status: 'unknown', requestKey};
    try {const value = await context.request(`gateway/devices/${device.id}/revoke`, {method: 'POST', body: {...intent}, idempotencyKey: requestKey}); check(context); return await settle(context, access, pending, parseReceipt(value, context, attempt));}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupGatewayRevocation(context: GatewayRevocationContext, pending: GatewayRevocationPending): Promise<GatewayRevocationLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return withFence(context, async (access) => {
    let stored = await restoreUnderFence(context, access);
    if (stored.kind === 'ready') {access.reserve(pending.requestKey, stored.revision); stored = {kind: 'owned', requestKey: pending.requestKey, attempt: null};}
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey) fail('The original device request could not be verified.');
    const result = await lookupUnderFence(context, stored);
    if (result.status === 'succeeded') await clear(context, access, stored);
    return result;
  });
}
/** Explicit retry rechecks the original key and device identity before replaying the exact intent. */
export async function retryGatewayRevocation(context: GatewayRevocationContext, pending: GatewayRevocationPending): Promise<GatewayRevocationResult> {
  if (!context.enabled) fail('This action is not enabled for the current workspace.');
  check(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original device intent is unavailable.');
  return withFence(context, async (access) => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original device request could not be verified.');
    const previous = await lookupUnderFence(context, stored);
    if (previous.status === 'succeeded') {await clear(context, access, stored); return {status: 'succeeded', receipt: previous.receipt};}
    if (previous.status !== 'not_found') fail('The original device request remains unresolved.');
    const intent = verifyAttempt(stored.attempt, context), device = await currentDevice(context);
    if (!['pending', 'active'].includes(device.state) || device.version !== intent.expected_version) fail('The device changed. Check the original receipt before continuing.');
    try {const value = await context.request(`gateway/devices/${device.id}/revoke`, {method: 'POST', body: {...intent}, idempotencyKey: stored.requestKey}); check(context); return await settle(context, access, stored, parseReceipt(value, context, stored.attempt));}
    catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
