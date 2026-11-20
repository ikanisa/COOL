/* eslint-disable no-control-regex -- Validate operator-entered person details and audit reason. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import { clearPending, pendingAuthority, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity } from './pendingAttempt';
import { withPendingFence, type FenceAccess, type FenceLock } from '../operations/pendingFence';

const FAMILY = 'operating-createuser', RESOURCE = 'new', PERMISSION = 'users.manage';
const BINDING_KEY = 'collect.admin.legacy-user-create.context.v1';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const email = /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/;
const id = z.string().regex(UUID);
const receiptSchema = z.object({request_id: id, resource_type: z.literal('users'), resource_id: id, version: z.literal(1), status: z.literal('succeeded')}).strict();

export interface LegacyUserCreateContext {
  request: AdminRequest; identity: PendingIdentity; actorId: string; permissions: readonly string[]; financialModel: 'transaction_journals' | 'canonical_evidence_ledger';
  /** Disabled until backend and Flutter/React coexistence are qualified. */
  enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean; storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;
}
export interface LegacyUserIntent {
  display_name: string; member_type: 'app' | 'direct'; momo_provider: '' | 'mtn_momo' | 'airtel_money'; momo_number: string; momo_pay_code: string;
  email: string | null; phone_e164?: string | null; status: 'invited' | 'active' | 'suspended' | 'closed'; reason: string;
}
export interface LegacyUserReceipt {requestId: string; userId: string; version: 1;}
export type LegacyUserPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type LegacyUserResult = {status: 'succeeded'; receipt: LegacyUserReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LegacyUserPending};
export type LegacyUserLookup = {status: 'succeeded'; receipt: LegacyUserReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
function fail(message: string): never {throw new Error(message);}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function check(context: LegacyUserCreateContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'transaction_journals' || !UUID.test(context.actorId) || context.identity.id !== context.actorId || context.identity.role === 'staff' ||
      ![PERMISSION, 'overview.read'].every(permission => context.permissions.includes(permission) && context.identity.permissions.includes(permission)) ||
      !Number.isFinite(expires) || expires <= Date.now()) fail('Person creation is unavailable to your current account.');
}
function checkWrite(context: LegacyUserCreateContext) {check(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Person creation is not enabled for the current workspace.');}
export function parseLegacyUserIntent(value: unknown): LegacyUserIntent {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('The original person details could not be verified.');
  const body = value as Record<string, unknown>;
  const keys = ['display_name', 'member_type', 'momo_provider', 'momo_number', 'momo_pay_code', 'email', 'status', 'reason', ...(body.member_type === 'app' ? ['phone_e164'] : [])];
  const validText = (input: unknown, minimum: number, maximum: number) => typeof input === 'string' && input === input.trim() && input.length >= minimum && input.length <= maximum && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(input);
  if (!exact(body, keys) || !validText(body.display_name, 2, 120) || body.member_type !== 'app' && body.member_type !== 'direct' ||
      body.momo_provider !== '' && body.momo_provider !== 'mtn_momo' && body.momo_provider !== 'airtel_money' ||
      typeof body.momo_number !== 'string' || body.momo_number !== '' && !/^07[2389]\d{7}$/.test(body.momo_number) ||
      body.momo_number !== '' && body.momo_provider === 'mtn_momo' && !/^07[89]/.test(body.momo_number) ||
      body.momo_number !== '' && body.momo_provider === 'airtel_money' && !/^07[23]/.test(body.momo_number) ||
      typeof body.momo_pay_code !== 'string' || body.momo_pay_code !== '' && !/^\d{4,9}$/.test(body.momo_pay_code) ||
      !(body.email === null || typeof body.email === 'string' && body.email.length <= 254 && email.test(body.email)) ||
      body.member_type === 'app' && !(body.phone_e164 === null || typeof body.phone_e164 === 'string' && /^\+2507[2389]\d{7}$/.test(body.phone_e164)) ||
      body.member_type === 'app' && body.email === null && body.phone_e164 === null || body.member_type === 'direct' && body.momo_number === '' ||
      !['invited', 'active', 'suspended', 'closed'].includes(String(body.status)) || !validText(body.reason, 8, 1000)) fail('The original person details could not be verified.');
  return body as unknown as LegacyUserIntent;
}
function verifyAttempt(attempt: PendingAttempt) {
  if (attempt.family !== FAMILY || attempt.resource_id !== RESOURCE || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key)) fail('The original person request could not be verified.');
}
function store(context: LegacyUserCreateContext): Storage {try {return context.storage ?? sessionStorage;} catch {return fail('Recovery storage is unavailable.');}}
async function binding(context: LegacyUserCreateContext, key: string, attempt?: PendingAttempt): Promise<'valid' | 'missing' | 'foreign' | 'mismatch'> {
  let raw: string | null; try {raw = store(context).getItem(BINDING_KEY);} catch {return fail('Recovery storage is unavailable.');}
  if (raw === null) return 'missing';
  if (raw.length > 1000) fail('The original person request could not be verified.');
  let value: unknown; try {value = JSON.parse(raw);} catch {return fail('The original person request could not be verified.');}
  const data = z.object({version: z.literal(1), request_key: id, authority_sha256: z.string().regex(HASH), intent_sha256: z.string().regex(HASH), model: z.literal('transaction_journals')}).strict().parse(value);
  if (data.request_key !== key) fail('The original person request could not be verified.');
  if (data.authority_sha256 !== await pendingAuthority(context.identity)) return 'foreign';
  return attempt && data.intent_sha256 !== await sha256Text(JSON.stringify(attempt.intent)) ? 'mismatch' : 'valid';
}
async function saveBinding(context: LegacyUserCreateContext, key: string, attempt: PendingAttempt) {
  if (await binding(context, key) !== 'missing') fail('The original person request could not be verified.');
  const storage = store(context), raw = JSON.stringify({version: 1, request_key: key, authority_sha256: await pendingAuthority(context.identity), intent_sha256: await sha256Text(JSON.stringify(attempt.intent)), model: 'transaction_journals'}); check(context);
  try {storage.setItem(BINDING_KEY, raw); if (storage.getItem(BINDING_KEY) !== raw) fail('Recovery storage is unavailable.');} catch {fail('Recovery storage is unavailable.');}
  check(context);
}
async function clearBinding(context: LegacyUserCreateContext, key: string) {
  const state = await binding(context, key); if (state === 'foreign') fail('The original person request could not be verified.'); if (state === 'missing') return;
  const storage = store(context); check(context);
  try {storage.removeItem(BINDING_KEY); if (storage.getItem(BINDING_KEY) !== null) fail('Recovery storage is unavailable.');} catch {fail('Recovery storage is unavailable.');}
}
async function withFence<T>(context: LegacyUserCreateContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: FAMILY, resourceId: RESOURCE, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restoreUnderFence(context: LegacyUserCreateContext, access: FenceAccess): Promise<LegacyUserPending> {
  check(context); const fence = access.read(); if (fence.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, FAMILY, RESOURCE, context.storage); if (attempt) verifyAttempt(attempt);
  const owner = attempt ? await binding(context, attempt.request_key, attempt) : 'missing'; check(context);
  if (owner === 'foreign') return {kind: 'foreign'};
  if (fence.kind === 'owned') {if (attempt && attempt.request_key !== fence.requestKey) fail('The original person request could not be verified.'); return {kind: 'owned', requestKey: fence.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, fence.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};}
  return {kind: 'ready', revision: fence.revision};
}
export async function restoreLegacyUserCreate(context: LegacyUserCreateContext): Promise<LegacyUserPending> {check(context); return withFence(context, access => restoreUnderFence(context, access));}
async function clear(context: LegacyUserCreateContext, access: FenceAccess, pending: Extract<LegacyUserPending, {kind: 'owned'}>) {
  await clearBinding(context, pending.requestKey);
  if (pending.attempt) await clearPending(context.identity, FAMILY, RESOURCE, pending.requestKey, context.storage);
  check(context); access.clear(pending.requestKey);
}
function receipt(value: unknown): LegacyUserReceipt {
  const body = receiptSchema.parse(value); return {requestId: body.request_id, userId: body.resource_id, version: body.version};
}
async function lookupUnderFence(context: LegacyUserCreateContext, pending: Extract<LegacyUserPending, {kind: 'owned'}>): Promise<LegacyUserLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) {
    let retryAvailable = false;
    if (pending.attempt && await binding(context, pending.requestKey, pending.attempt) === 'valid') {try {parseLegacyUserIntent(pending.attempt.intent); retryAvailable = true;} catch { /* Unknown Flutter intents are check-only. */ }}
    return {status: 'not_found', retryAvailable};
  }
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original person receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail('The original person receipt could not be verified.');
  const result = receipt(body.receipt); if (result.requestId !== body.request_id) fail('The original person receipt could not be verified.');
  return {status: 'succeeded', receipt: result};
}
async function finishResponse(context: LegacyUserCreateContext, access: FenceAccess, pending: Extract<LegacyUserPending, {kind: 'owned'}>, response: unknown): Promise<LegacyUserResult> {
  const direct = receipt(response), verified = await lookupUnderFence(context, pending);
  if (verified.status !== 'succeeded' || JSON.stringify(verified.receipt) !== JSON.stringify(direct)) fail('The original person receipt could not be verified.');
  await clear(context, access, pending); return {status: 'succeeded', receipt: direct};
}
export async function submitLegacyUserCreate(context: LegacyUserCreateContext, input: unknown, observedRevision: string): Promise<LegacyUserResult> {
  checkWrite(context); const intent = parseLegacyUserIntent(input);
  return withFence(context, async access => {
    const existing = await restoreUnderFence(context, access); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    checkWrite(context); const requestKey = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, FAMILY, RESOURCE, requestKey, PERMISSION, {...intent}, context.storage); verifyAttempt(attempt); await saveBinding(context, requestKey, attempt);}
    catch (error) {if (context.isCurrent()) {try {const retained = await readPending(context.identity, FAMILY, RESOURCE, context.storage); if (retained?.request_key === requestKey) await clearPending(context.identity, FAMILY, RESOURCE, requestKey, context.storage); await clearBinding(context, requestKey); access.clear(requestKey);} catch { /* Preserve the fence if cleanup is uncertain. */ }} throw error;}
    const pending: Extract<LegacyUserPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey};
    try {const response = await context.request('operations/users', {method: 'POST', body: {...intent}, idempotencyKey: requestKey}); check(context); return await finishResponse(context, access, pending, response);}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLegacyUserCreate(context: LegacyUserCreateContext, pending: LegacyUserPending): Promise<LegacyUserLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return withFence(context, async access => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey) fail('The original person request could not be verified.');
    const result = await lookupUnderFence(context, stored); if (result.status === 'succeeded') await clear(context, access, stored); return result;
  });
}
export async function retryLegacyUserCreate(context: LegacyUserCreateContext, pending: LegacyUserPending): Promise<LegacyUserResult> {
  checkWrite(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original person intent is unavailable.');
  return withFence(context, async access => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original person request could not be verified.');
    const previous = await lookupUnderFence(context, stored);
    if (previous.status === 'succeeded') {await clear(context, access, stored); return {status: 'succeeded', receipt: previous.receipt};}
    if (previous.status !== 'not_found' || !previous.retryAvailable) fail('The original person request remains unresolved.');
    const intent = parseLegacyUserIntent(stored.attempt.intent); checkWrite(context);
    try {const response = await context.request('operations/users', {method: 'POST', body: {...intent}, idempotencyKey: stored.requestKey}); check(context); return await finishResponse(context, access, stored, response);}
    catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
