/* eslint-disable no-control-regex -- Reject control characters in audit reasons. */
import {z} from 'zod';
import type {AdminRequest} from '../../api/client';
import {clearPending, readPending, retainPending, type PendingAttempt, type PendingIdentity} from '../core';
import {parseGatewayDetail, type GatewayDevice} from './contracts';
import {withPendingFence, type FenceAccess, type FenceLock} from './pendingFence';

const FAMILY = 'gateway-device-activate', PERMISSION = 'gateway.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const receiptSchema = z.object({request_id: z.string().regex(UUID), resource_type: z.literal('gateway_devices'), resource_id: z.string().regex(UUID), version: z.number().int().min(2).max(Number.MAX_SAFE_INTEGER), status: z.literal('succeeded')}).strict();

export interface GatewayActivationContext {
  request: AdminRequest; identity: PendingIdentity; device: GatewayDevice; canManage: boolean;
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; enabled: boolean;
  isCurrent: () => boolean; isEnabled?: () => boolean;
  storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;
}
export interface GatewayActivationIntent {expected_version: number; expected_key_sha256: string; expected_signing_certificate_sha256: string; reason: string;}
export interface GatewayActivationReceipt {requestId: string; deviceId: string; version: number;}
export type GatewayActivationPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type GatewayActivationResult = {status: 'succeeded'; receipt: GatewayActivationReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: GatewayActivationPending};
export type GatewayActivationLookup = {status: 'succeeded'; receipt: GatewayActivationReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};

function fail(message: string): never {throw new Error(message);}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));}
function check(context: GatewayActivationContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.identity.role === 'staff' || !context.canManage || context.financialModel !== 'transaction_journals' ||
      !['gateway.read', PERMISSION, 'overview.read'].every((permission) => context.identity.permissions.includes(permission)) ||
      !Number.isFinite(expires) || expires <= Date.now() || !UUID.test(context.device.id)) fail('This action is unavailable to your current account.');
}
function write(context: GatewayActivationContext) {check(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('This action is not enabled for the current workspace.');}
function reasonText(reason: string) {
  const value = reason.trim();
  if (value.length < 8 || value.length > 1000 || /[\x00-\x1f\x7f]/.test(value)) fail('Provide a reason of 8 to 1000 characters.');
  return value;
}
function verifyAttempt(attempt: PendingAttempt, context: GatewayActivationContext): GatewayActivationIntent {
  const value = attempt.intent;
  if (attempt.family !== FAMILY || attempt.resource_id !== context.device.id || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key) ||
      !exact(value, ['expected_version', 'expected_key_sha256', 'expected_signing_certificate_sha256', 'reason']) ||
      typeof value.expected_version !== 'number' || !Number.isSafeInteger(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER ||
      typeof value.expected_key_sha256 !== 'string' || !HASH.test(value.expected_key_sha256) || value.expected_key_sha256 !== context.device.key_sha256 ||
      typeof value.expected_signing_certificate_sha256 !== 'string' || !HASH.test(value.expected_signing_certificate_sha256) || value.expected_signing_certificate_sha256 !== context.device.signing_certificate_sha256 ||
      typeof value.reason !== 'string' || reasonText(value.reason) !== value.reason) fail('The original device request could not be verified.');
  return {expected_version: value.expected_version, expected_key_sha256: value.expected_key_sha256, expected_signing_certificate_sha256: value.expected_signing_certificate_sha256, reason: value.reason};
}
function receipt(value: unknown, context: GatewayActivationContext, attempt: PendingAttempt | null): GatewayActivationReceipt {
  const parsed = receiptSchema.parse(value);
  if (parsed.resource_id !== context.device.id || attempt && parsed.version !== verifyAttempt(attempt, context).expected_version + 1) fail('The original device receipt could not be verified.');
  return {requestId: parsed.request_id, deviceId: parsed.resource_id, version: parsed.version};
}
async function fence<T>(context: GatewayActivationContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: FAMILY, resourceId: context.device.id, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restore(context: GatewayActivationContext, access: FenceAccess): Promise<GatewayActivationPending> {
  check(context); const state = access.read(); if (state.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, FAMILY, context.device.id, context.storage); if (attempt) verifyAttempt(attempt, context); check(context);
  if (state.kind === 'owned') {if (attempt && attempt.request_key !== state.requestKey) fail('The original device request could not be verified.'); return {kind: 'owned', requestKey: state.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, state.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};}
  return {kind: 'ready', revision: state.revision};
}
export async function restoreGatewayActivation(context: GatewayActivationContext): Promise<GatewayActivationPending> {check(context); return fence(context, (access) => restore(context, access));}
async function clear(context: GatewayActivationContext, access: FenceAccess, pending: Extract<GatewayActivationPending, {kind: 'owned'}>) {
  if (pending.attempt) await clearPending(context.identity, FAMILY, context.device.id, pending.requestKey, context.storage);
  check(context); access.clear(pending.requestKey);
}
async function currentDevice(context: GatewayActivationContext) {
  const detail = await parseGatewayDetail(await context.request(`gateway/devices/${context.device.id}`), context.device.id, context.identity.id, false); check(context);
  if (!detail.canManage || detail.resource.app_id !== context.device.app_id || detail.resource.installation_id !== context.device.installation_id ||
      detail.resource.key_sha256 !== context.device.key_sha256 || detail.resource.signing_certificate_sha256 !== context.device.signing_certificate_sha256) fail('The current device identity could not be verified.');
  return detail.resource;
}
async function verifySaved(context: GatewayActivationContext, saved: GatewayActivationReceipt) {
  const device = await currentDevice(context);
  if (device.state !== 'active' || device.version !== saved.version) fail('The device activation could not be verified.');
}
async function lookup(context: GatewayActivationContext, pending: Extract<GatewayActivationPending, {kind: 'owned'}>): Promise<GatewayActivationLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) return {status: 'not_found', retryAvailable: pending.attempt !== null};
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original device receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail('The original device receipt could not be verified.');
  const saved = receipt(body.receipt, context, pending.attempt); if (saved.requestId !== body.request_id) fail('The original device receipt could not be verified.');
  await verifySaved(context, saved); return {status: 'succeeded', receipt: saved};
}
async function settle(context: GatewayActivationContext, access: FenceAccess, pending: Extract<GatewayActivationPending, {kind: 'owned'}>, saved: GatewayActivationReceipt): Promise<GatewayActivationResult> {
  await verifySaved(context, saved); await clear(context, access, pending); return {status: 'succeeded', receipt: saved};
}
export async function submitGatewayActivation(context: GatewayActivationContext, reason: string, revision: string): Promise<GatewayActivationResult> {
  write(context); const why = reasonText(reason), device = context.device;
  if (device.state !== 'pending' || !Number.isSafeInteger(device.version) || device.version < 1 || device.version >= Number.MAX_SAFE_INTEGER || !HASH.test(device.key_sha256) || !HASH.test(device.signing_certificate_sha256)) fail('Refresh the current device before reviewing it.');
  const intent: GatewayActivationIntent = {expected_version: device.version, expected_key_sha256: device.key_sha256, expected_signing_certificate_sha256: device.signing_certificate_sha256, reason: why};
  return fence(context, async (access) => {
    const existing = await restore(context, access); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    write(context); const key = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(key)) fail('A secure request reference is unavailable.');
    access.reserve(key, revision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, FAMILY, device.id, key, PERMISSION, {...intent}, context.storage); verifyAttempt(attempt, context);}
    catch (error) {
      if (context.isCurrent()) {
        try {const saved = await readPending(context.identity, FAMILY, device.id, context.storage); if (saved?.request_key === key) await clearPending(context.identity, FAMILY, device.id, key, context.storage); access.clear(key);}
        catch { /* Keep the fence unless cleanup is confirmed. */ }
      }
      throw error;
    }
    const pending: Extract<GatewayActivationPending, {kind: 'owned'}> = {kind: 'owned', requestKey: key, attempt};
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey: key};
    try {const result = await context.request(`gateway/devices/${device.id}/activate`, {method: 'POST', body: {...intent}, idempotencyKey: key}); check(context); return await settle(context, access, pending, receipt(result, context, attempt));}
    catch {return {status: 'unknown', requestKey: key};}
  });
}
export async function lookupGatewayActivation(context: GatewayActivationContext, pending: GatewayActivationPending): Promise<GatewayActivationLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return fence(context, async (access) => {
    let stored = await restore(context, access);
    if (stored.kind === 'ready') {access.reserve(pending.requestKey, stored.revision); stored = {kind: 'owned', requestKey: pending.requestKey, attempt: null};}
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey) fail('The original device request could not be verified.');
    const result = await lookup(context, stored); if (result.status === 'succeeded') await clear(context, access, stored); return result;
  });
}
/** An explicit retry checks the original key and current device before sending the unchanged request. */
export async function retryGatewayActivation(context: GatewayActivationContext, pending: GatewayActivationPending): Promise<GatewayActivationResult> {
  write(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original device intent is unavailable.');
  const originalIntent = pending.attempt.intent;
  return fence(context, async (access) => {
    const stored = await restore(context, access);
    if (stored.kind !== 'owned' || !stored.attempt || stored.requestKey !== pending.requestKey || JSON.stringify(stored.attempt.intent) !== JSON.stringify(originalIntent)) fail('The original device request could not be verified.');
    const previous = await lookup(context, stored); if (previous.status === 'succeeded') {await clear(context, access, stored); return {status: 'succeeded', receipt: previous.receipt};}
    if (previous.status !== 'not_found') fail('The original device request remains unresolved.');
    const intent = verifyAttempt(stored.attempt, context), device = await currentDevice(context);
    if (device.state !== 'pending' || device.version !== intent.expected_version) fail('The device changed. Check the original receipt before continuing.');
    write(context);
    try {const result = await context.request(`gateway/devices/${device.id}/activate`, {method: 'POST', body: {...intent}, idempotencyKey: stored.requestKey}); check(context); return await settle(context, access, stored, receipt(result, context, stored.attempt));}
    catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
