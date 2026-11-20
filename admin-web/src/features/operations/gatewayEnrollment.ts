/* eslint-disable no-control-regex -- Reject control characters in device and audit text. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import { clearPending, readPending, retainPending, type PendingAttempt, type PendingIdentity } from '../core';
import { parseGatewayDetail } from './contracts';
import { withPendingFence, type FenceAccess, type FenceLock } from './pendingFence';

const FAMILY = 'gateway-device-enrollment', RESOURCE = 'new', PERMISSION = 'gateway.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const APP_ID = /^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$/;
const PREFIX = '3059301306072a8648ce3d020106082a8648ce3d03010703420004';
const receiptSchema = z.object({request_id: z.string().regex(UUID), resource_type: z.literal('gateway_devices'), resource_id: z.string().regex(UUID), version: z.literal(1), status: z.literal('succeeded')}).strict();
export interface GatewayEnrollmentContext {
  request: AdminRequest;
  identity: PendingIdentity;
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger';
  /** Remains false until the backend, cross-version coordination and recovery are qualified. */
  enabled: boolean;
  isCurrent: () => boolean;
  storage?: Storage;
  sharedStorage?: Storage;
  lock?: FenceLock;
  createKey?: () => string;
}
export interface GatewayPublicIdentity {installation_id: string; public_key_spki_base64: string; key_sha256: string; signing_certificate_sha256: string;}
export interface GatewayEnrollmentIntent extends GatewayPublicIdentity {label: string; app_id: string; reason: string;}
export type EnrollmentPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export interface EnrollmentReceipt {requestId: string; deviceId: string; version: 1;}
export type EnrollmentResult = {status: 'succeeded'; receipt: EnrollmentReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: EnrollmentPending};
export type EnrollmentLookup = {status: 'succeeded'; receipt: EnrollmentReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
function fail(message: string): never {throw new Error(message);}
function check(context: GatewayEnrollmentContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.identity.role === 'staff' || !['gateway.read', PERMISSION, 'overview.read'].every((permission) => context.identity.permissions.includes(permission)) || context.financialModel !== 'transaction_journals' || !Number.isFinite(expires) || expires <= Date.now()) fail('This action is unavailable to your current account.');
}
function text(value: unknown, min: number, max: number): value is string {return typeof value === 'string' && value === value.trim() && value.length >= min && value.length <= max && !/[\x00-\x1f\x7f]/.test(value);}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));}
function object(value: unknown): value is Record<string, unknown> {return value !== null && typeof value === 'object' && !Array.isArray(value);}
async function verifyPublicKey(key: string, fingerprint: string) {
  if (!/^[A-Za-z0-9+/]{122}==$/.test(key) || !HASH.test(fingerprint) || !globalThis.crypto?.subtle) fail('The public key and fingerprint could not be verified.');
  try {
    const raw = atob(key), bytes = Uint8Array.from(raw, (character) => character.charCodeAt(0));
    if (bytes.length !== 91 || btoa(raw) !== key || [...bytes.slice(0, 27)].map((byte) => byte.toString(16).padStart(2, '0')).join('') !== PREFIX) fail('The public key could not be verified.');
    const digest = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((byte) => byte.toString(16).padStart(2, '0')).join('');
    if (digest !== fingerprint) fail('The public key and fingerprint do not match.');
    await crypto.subtle.importKey('spki', bytes, {name: 'ECDSA', namedCurve: 'P-256'}, false, ['verify']);
  } catch {fail('The public key and fingerprint could not be verified.');}
}
/** Parse the exact flat handset identity object, rejecting duplicate or extra fields. */
export async function parseGatewayPublicIdentity(raw: string): Promise<GatewayPublicIdentity> {
  if (raw.length > 4096) fail('The handset public identity is too large.');
  let index = 0;
  const space = () => {while (/[\t\r\n ]/.test(raw[index] ?? 'x')) index++;};
  const string = () => {
    if (raw[index] !== '"') fail('The handset public identity could not be verified.');
    const start = index++;
    while (index < raw.length) {
      const character = raw[index++];
      if (character === '\\') {index++; continue;}
      if (character === '"') {try {const result: unknown = JSON.parse(raw.slice(start, index)); if (typeof result === 'string') return result;} catch { /* Invalid string. */ } break;}
    }
    return fail('The handset public identity could not be verified.');
  };
  const fields: Record<string, unknown> = Object.create(null) as Record<string, unknown>;
  space(); if (raw[index++] !== '{') fail('The handset public identity could not be verified.');
  space();
  while (raw[index] !== '}') {
    const key = string(); if (Object.hasOwn(fields, key)) fail('The handset public identity contains duplicate fields.');
    space(); if (raw[index++] !== ':') fail('The handset public identity could not be verified.');
    space();
    if (raw[index] === '"') fields[key] = string();
    else if (raw[index] === '1') {fields[key] = 1; index++;}
    else fail('The handset public identity could not be verified.');
    space(); if (raw[index] === '}') break; if (raw[index++] !== ',') fail('The handset public identity could not be verified.'); space(); if (raw[index] === '}') fail('The handset public identity could not be verified.');
  }
  if (raw[index++] !== '}') fail('The handset public identity could not be verified.');
  space();
  if (index !== raw.length || !exact(fields, ['contract_version', 'installation_id', 'public_key_spki_base64', 'key_sha256', 'signing_certificate_sha256']) || fields.contract_version !== 1 || typeof fields.installation_id !== 'string' || !UUID.test(fields.installation_id) || typeof fields.public_key_spki_base64 !== 'string' || typeof fields.key_sha256 !== 'string' || typeof fields.signing_certificate_sha256 !== 'string' || !HASH.test(fields.signing_certificate_sha256)) fail('The handset public identity could not be verified.');
  await verifyPublicKey(fields.public_key_spki_base64, fields.key_sha256);
  return {installation_id: fields.installation_id, public_key_spki_base64: fields.public_key_spki_base64, key_sha256: fields.key_sha256, signing_certificate_sha256: fields.signing_certificate_sha256};
}
export async function verifyEnrollmentIntent(value: unknown): Promise<GatewayEnrollmentIntent> {
  if (!object(value) || !exact(value, ['label', 'app_id', 'installation_id', 'public_key_spki_base64', 'key_sha256', 'signing_certificate_sha256', 'reason']) ||
      !text(value.label, 2, 120) || !text(value.app_id, 3, 160) || !APP_ID.test(value.app_id) || typeof value.installation_id !== 'string' || !UUID.test(value.installation_id) ||
      typeof value.public_key_spki_base64 !== 'string' || typeof value.key_sha256 !== 'string' || typeof value.signing_certificate_sha256 !== 'string' || !HASH.test(value.signing_certificate_sha256) || !text(value.reason, 8, 1000)) fail('The device enrollment details could not be verified.');
  await verifyPublicKey(value.public_key_spki_base64, value.key_sha256);
  return {label: value.label, app_id: value.app_id, installation_id: value.installation_id, public_key_spki_base64: value.public_key_spki_base64, key_sha256: value.key_sha256, signing_certificate_sha256: value.signing_certificate_sha256, reason: value.reason};
}
async function verifyAttempt(attempt: PendingAttempt): Promise<GatewayEnrollmentIntent> {
  if (attempt.family !== FAMILY || attempt.resource_id !== RESOURCE || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key)) fail('The original enrollment request could not be verified.');
  return verifyEnrollmentIntent(attempt.intent);
}
function parseReceipt(value: unknown): EnrollmentReceipt {
  const parsed = receiptSchema.parse(value);
  return {requestId: parsed.request_id, deviceId: parsed.resource_id, version: parsed.version};
}
async function withFence<T>(context: GatewayEnrollmentContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: FAMILY, resourceId: RESOURCE, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restoreUnderFence(context: GatewayEnrollmentContext, access: FenceAccess): Promise<EnrollmentPending> {
  check(context); const fence = access.read();
  if (fence.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, FAMILY, RESOURCE, context.storage);
  if (attempt) await verifyAttempt(attempt);
  check(context);
  if (fence.kind === 'owned') {if (attempt && attempt.request_key !== fence.requestKey) fail('The original enrollment request could not be verified.'); return {kind: 'owned', requestKey: fence.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, fence.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};}
  return {kind: 'ready', revision: fence.revision};
}
export async function restoreGatewayEnrollment(context: GatewayEnrollmentContext): Promise<EnrollmentPending> {check(context); return withFence(context, (access) => restoreUnderFence(context, access));}
async function verifyDevice(context: GatewayEnrollmentContext, value: EnrollmentReceipt, attempt: PendingAttempt | null) {
  const detail = await parseGatewayDetail(await context.request(`gateway/devices/${value.deviceId}`), value.deviceId, context.identity.id, false);
  check(context);
  if (attempt) {
    const expected = await verifyAttempt(attempt), actual = detail.resource;
    if (actual.installation_id !== expected.installation_id || actual.app_id !== expected.app_id || actual.label !== expected.label || actual.key_sha256 !== expected.key_sha256 || actual.signing_certificate_sha256 !== expected.signing_certificate_sha256) fail('The enrolled device identity could not be verified.');
  }
}
async function clear(context: GatewayEnrollmentContext, access: FenceAccess, pending: Extract<EnrollmentPending, {kind: 'owned'}>) {
  if (pending.attempt) await clearPending(context.identity, FAMILY, RESOURCE, pending.requestKey, context.storage);
  check(context); access.clear(pending.requestKey);
}
async function lookupUnderFence(context: GatewayEnrollmentContext, pending: Extract<EnrollmentPending, {kind: 'owned'}>): Promise<EnrollmentLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) return {status: 'not_found', retryAvailable: pending.attempt !== null};
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original enrollment receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail('The original enrollment receipt could not be verified.');
  const saved = parseReceipt(body.receipt);
  if (saved.requestId !== body.request_id) fail('The original enrollment receipt could not be verified.');
  await verifyDevice(context, saved, pending.attempt);
  return {status: 'succeeded', receipt: saved};
}
async function settle(context: GatewayEnrollmentContext, access: FenceAccess, pending: Extract<EnrollmentPending, {kind: 'owned'}>, saved: EnrollmentReceipt): Promise<EnrollmentResult> {
  await verifyDevice(context, saved, pending.attempt); await clear(context, access, pending); return {status: 'succeeded', receipt: saved};
}
export async function submitGatewayEnrollment(context: GatewayEnrollmentContext, input: GatewayEnrollmentIntent, observedRevision: string): Promise<EnrollmentResult> {
  if (!context.enabled) fail('This action is not enabled for the current workspace.');
  check(context); const intent = await verifyEnrollmentIntent(input); check(context);
  return withFence(context, async (access) => {
    const existing = await restoreUnderFence(context, access);
    if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const requestKey = (context.createKey ?? (() => crypto.randomUUID()))();
    if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision);
    let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, FAMILY, RESOURCE, requestKey, PERMISSION, {...intent}, context.storage);} catch (error) {if (context.isCurrent()) access.clear(requestKey); throw error;}
    await verifyAttempt(attempt);
    const pending: Extract<EnrollmentPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent()) return {status: 'unknown', requestKey};
    try {const value = await context.request('gateway/devices', {method: 'POST', body: {...intent}, idempotencyKey: requestKey}); check(context); return await settle(context, access, pending, parseReceipt(value));}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupGatewayEnrollment(context: GatewayEnrollmentContext, pending: EnrollmentPending): Promise<EnrollmentLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return withFence(context, async (access) => {
    let stored = await restoreUnderFence(context, access);
    if (stored.kind === 'ready') {access.reserve(pending.requestKey, stored.revision); stored = {kind: 'owned', requestKey: pending.requestKey, attempt: null};}
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey) fail('The original enrollment request could not be verified.');
    const result = await lookupUnderFence(context, stored);
    if (result.status === 'succeeded') await clear(context, access, stored);
    return result;
  });
}
/** A retry requires explicit review, a fresh not-found lookup, and the exact stored key and intent. */
export async function retryGatewayEnrollment(context: GatewayEnrollmentContext, pending: EnrollmentPending): Promise<EnrollmentResult> {
  if (!context.enabled) fail('This action is not enabled for the current workspace.');
  check(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original enrollment intent is unavailable.');
  return withFence(context, async (access) => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original enrollment request could not be verified.');
    const previous = await lookupUnderFence(context, stored);
    if (previous.status === 'succeeded') {await clear(context, access, stored); return {status: 'succeeded', receipt: previous.receipt};}
    if (previous.status !== 'not_found') fail('The original enrollment request remains unresolved.');
    const intent = await verifyAttempt(stored.attempt); check(context);
    try {const value = await context.request('gateway/devices', {method: 'POST', body: {...intent}, idempotencyKey: stored.requestKey}); check(context); return await settle(context, access, stored, parseReceipt(value));}
    catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
