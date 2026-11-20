/* eslint-disable no-control-regex -- Validate operator-entered account details and audit reasons. */
import {z} from 'zod';
import {withPendingFence, type FenceAccess} from '../operations/pendingFence';
import {currentLegacyPerson, type LegacyPersonSnapshot, type LegacyUserEditContext} from './legacyUserEdit';
import {clearPending, pendingAuthority, readPending, retainPending, sha256Text, type PendingAttempt} from './pendingAttempt';

const FAMILY = 'operating-updateuser', PERMISSION = 'users.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/, HASH = /^[a-f0-9]{64}$/;
const EMAIL = /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/;
const PHONE = /^\+2507[2389]\d{7}$/;
const id = z.string().regex(UUID);

/** A target-state check must be committed with the owner-authorized link. */
export const LEGACY_OPERATOR_LINK_QUALIFIED: boolean = false;
/** Email and member-type changes stay off until challenge/session behavior is qualified. */
export const LEGACY_LOGIN_IDENTITY_QUALIFIED: boolean = false;

export interface LegacyPersonAccessContext extends LegacyUserEditContext {
  contactsEnabled?: boolean;
  loginTypeEnabled?: boolean;
  operatorLinkEnabled?: boolean;
  isContactsEnabled?: () => boolean;
  isLoginTypeEnabled?: () => boolean;
  isOperatorLinkEnabled?: () => boolean;
  verifyFresh?: () => Promise<boolean>;
}
export type LegacyPersonAccessIntent =
  | {phone_e164: string | null; expected_version: number; reason: string}
  | {email: string | null; expected_version: number; reason: string}
  | {member_type: 'app' | 'direct'; expected_version: number; reason: string}
  | {operator_admin_id: string | null; expected_version: number; reason: string};
export type LegacyPersonAccessPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type LegacyPersonAccessReceipt = {requestId: string; userId: string; version: number};
export type LegacyPersonAccessResult = {status: 'succeeded'; receipt: LegacyPersonAccessReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LegacyPersonAccessPending};
export type LegacyPersonAccessLookup = {status: 'succeeded'; receipt: LegacyPersonAccessReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};

function fail(message: string): never {throw new Error(message);}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function validReason(value: unknown): value is string {return typeof value === 'string' && value === value.trim() && value.length >= 8 && value.length <= 1000 && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value);}
function check(context: LegacyPersonAccessContext) {
  const expiry = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'transaction_journals' || !UUID.test(context.actorId) || !UUID.test(context.userId) ||
      context.identity.id !== context.actorId || context.identity.role === 'staff' ||
      !['users.read', PERMISSION, 'overview.read'].every(p => context.permissions.includes(p) && context.identity.permissions.includes(p)) ||
      !Number.isFinite(expiry) || expiry <= Date.now()) fail('Person access changes are unavailable to your current account.');
}
function enabled(context: LegacyPersonAccessContext, intent: LegacyPersonAccessIntent): boolean {
  if (typeof context.verifyFresh !== 'function') return false;
  if ('operator_admin_id' in intent) return LEGACY_OPERATOR_LINK_QUALIFIED && context.identity.role === 'owner' && context.operatorLinkEnabled === true && (!context.isOperatorLinkEnabled || context.isOperatorLinkEnabled());
  if ('member_type' in intent || 'email' in intent) return LEGACY_LOGIN_IDENTITY_QUALIFIED && context.loginTypeEnabled === true && (!context.isLoginTypeEnabled || context.isLoginTypeEnabled());
  return context.contactsEnabled === true && (!context.isContactsEnabled || context.isContactsEnabled());
}
function checkWrite(context: LegacyPersonAccessContext, intent: LegacyPersonAccessIntent) {
  check(context);
  if (!enabled(context, intent) || typeof context.verifyFresh !== 'function') fail('This person access change is not enabled for this workspace.');
}

/** Only exact reviewed fields are accepted; never invent a phone login. */
export function parseLegacyPersonAccessIntent(value: unknown, person: LegacyPersonSnapshot): LegacyPersonAccessIntent {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('The person access change could not be verified.');
  const body = value as Record<string, unknown>;
  if (!Number.isSafeInteger(body.expected_version) || body.expected_version !== person.version || person.version < 1 || person.version >= Number.MAX_SAFE_INTEGER ||
      !validReason(body.reason) || person.status === 'closed') fail('The person access change could not be verified.');
  if (exact(body, ['phone_e164', 'expected_version', 'reason'])) {
    if (person.operatorId !== null || !(body.phone_e164 === null || typeof body.phone_e164 === 'string' && PHONE.test(body.phone_e164)) ||
        body.phone_e164 === null && person.email === null || body.phone_e164 === person.phone) fail('Review the person contact details.');
    return body as unknown as LegacyPersonAccessIntent;
  }
  if (exact(body, ['email', 'expected_version', 'reason'])) {
    if (person.operatorId !== null || !(body.email === null || typeof body.email === 'string' && body.email.length <= 254 && EMAIL.test(body.email)) ||
        body.email === null && (person.phone === null || person.memberType === 'app') || body.email === person.email) fail('Review the person sign-in email.');
    return body as unknown as LegacyPersonAccessIntent;
  }
  if (exact(body, ['member_type', 'expected_version', 'reason'])) {
    if (person.operatorId !== null || !['app', 'direct'].includes(String(body.member_type)) || body.member_type === person.memberType ||
        body.member_type === 'app' && !person.email || body.member_type === 'direct' && !PHONE.test(`+250${person.momoNumber.slice(1)}`)) fail('Review the person sign-in type.');
    return body as unknown as LegacyPersonAccessIntent;
  }
  if (exact(body, ['operator_admin_id', 'expected_version', 'reason'])) {
    if (!(body.operator_admin_id === null || typeof body.operator_admin_id === 'string' && UUID.test(body.operator_admin_id)) ||
        body.operator_admin_id === person.operatorId) fail('Review the operator link.');
    return body as unknown as LegacyPersonAccessIntent;
  }
  return fail('The person access change could not be verified.');
}

function store(context: LegacyPersonAccessContext): Storage {try {return context.storage ?? sessionStorage;} catch {return fail('Recovery storage is unavailable.');}}
// Shared with profile/status edits so either feature can safely inspect and
// clear an exact completed request for this same person.
function bindingKey(context: LegacyPersonAccessContext) {return `collect.admin.legacy-user-edit.context.v1:${context.userId}`;}
async function binding(context: LegacyPersonAccessContext, key: string, attempt?: PendingAttempt): Promise<{kind: 'valid'; sourceSha256: string} | {kind: 'missing' | 'foreign' | 'mismatch'}> {
  let raw: string | null; try {raw = store(context).getItem(bindingKey(context));} catch {return fail('Recovery storage is unavailable.');}
  if (raw === null) return {kind: 'missing'};
  if (raw.length > 1000) fail('The original person request could not be verified.');
  let value: unknown; try {value = JSON.parse(raw);} catch {return fail('The original person request could not be verified.');}
  const data = z.object({version: z.literal(1), request_key: id, authority_sha256: z.string().regex(HASH), intent_sha256: z.string().regex(HASH), source_sha256: z.string().regex(HASH), model: z.literal('transaction_journals')}).strict().parse(value);
  if (data.request_key !== key) fail('The original person request could not be verified.');
  if (data.authority_sha256 !== await pendingAuthority(context.identity)) return {kind: 'foreign'};
  if (attempt && data.intent_sha256 !== await sha256Text(JSON.stringify(attempt.intent))) return {kind: 'mismatch'};
  return {kind: 'valid', sourceSha256: data.source_sha256};
}
async function saveBinding(context: LegacyPersonAccessContext, key: string, attempt: PendingAttempt, source: LegacyPersonSnapshot) {
  if ((await binding(context, key)).kind !== 'missing') fail('The original person request could not be verified.');
  const storage = store(context), name = bindingKey(context), raw = JSON.stringify({version: 1, request_key: key, authority_sha256: await pendingAuthority(context.identity), intent_sha256: await sha256Text(JSON.stringify(attempt.intent)), source_sha256: await sha256Text(JSON.stringify(source)), model: 'transaction_journals'}); check(context);
  try {storage.setItem(name, raw); if (storage.getItem(name) !== raw) fail('Recovery storage is unavailable.');} catch {fail('Recovery storage is unavailable.');} check(context);
}
async function clearBinding(context: LegacyPersonAccessContext, key: string) {
  const state = await binding(context, key); if (state.kind === 'foreign') fail('The original person request could not be verified.'); if (state.kind === 'missing') return;
  const storage = store(context), name = bindingKey(context); check(context);
  try {storage.removeItem(name); if (storage.getItem(name) !== null) fail('Recovery storage is unavailable.');} catch {fail('Recovery storage is unavailable.');}
}
function verifyAttempt(context: LegacyPersonAccessContext, attempt: PendingAttempt) {
  if (attempt.family !== FAMILY || attempt.resource_id !== context.userId || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key)) fail('The original person request could not be verified.');
}
async function fence<T>(context: LegacyPersonAccessContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: FAMILY, resourceId: context.userId, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restoreUnderFence(context: LegacyPersonAccessContext, access: FenceAccess): Promise<LegacyPersonAccessPending> {
  check(context); const shared = access.read(); if (shared.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, FAMILY, context.userId, context.storage); if (attempt) verifyAttempt(context, attempt);
  const owner = attempt ? await binding(context, attempt.request_key, attempt) : {kind: 'missing' as const}; check(context);
  if (owner.kind === 'foreign') return {kind: 'foreign'};
  if (shared.kind === 'owned') {if (attempt && attempt.request_key !== shared.requestKey) fail('The original person request could not be verified.'); return {kind: 'owned', requestKey: shared.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, shared.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};} return {kind: 'ready', revision: shared.revision};
}
export async function restoreLegacyPersonAccess(context: LegacyPersonAccessContext): Promise<LegacyPersonAccessPending> {check(context); return fence(context, access => restoreUnderFence(context, access));}
async function clear(context: LegacyPersonAccessContext, access: FenceAccess, pending: Extract<LegacyPersonAccessPending, {kind: 'owned'}>) {
  await clearBinding(context, pending.requestKey); if (pending.attempt) await clearPending(context.identity, FAMILY, context.userId, pending.requestKey, context.storage); check(context); access.clear(pending.requestKey);
}
function receipt(context: LegacyPersonAccessContext, value: unknown, attempt: PendingAttempt | null): LegacyPersonAccessReceipt {
  const body = z.object({request_id: id, resource_type: z.literal('users'), resource_id: id, version: z.number().int().min(2).max(Number.MAX_SAFE_INTEGER), status: z.literal('succeeded')}).strict().parse(value);
  if (body.resource_id !== context.userId || attempt && (typeof attempt.intent.expected_version !== 'number' || !Number.isSafeInteger(attempt.intent.expected_version) || body.version !== attempt.intent.expected_version + 1)) fail('The original person receipt could not be verified.');
  return {requestId: body.request_id, userId: body.resource_id, version: body.version};
}
async function lookupUnderFence(context: LegacyPersonAccessContext, pending: Extract<LegacyPersonAccessPending, {kind: 'owned'}>): Promise<LegacyPersonAccessLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) {
    let retryAvailable = false;
    if (pending.attempt && (await binding(context, pending.requestKey, pending.attempt)).kind === 'valid') {
      try {const person = await currentLegacyPerson(context, true); retryAvailable = enabled(context, parseLegacyPersonAccessIntent(pending.attempt.intent, person));} catch { /* Unknown or changed intents stay check-only. */ }
    }
    return {status: 'not_found', retryAvailable};
  }
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original person receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail('The original person receipt could not be verified.');
  const saved = receipt(context, body.receipt, pending.attempt); if (saved.requestId !== body.request_id) fail('The original person receipt could not be verified.');
  if (!pending.attempt && (await currentLegacyPerson(context, true)).version < saved.version) fail('The person version could not be verified.');
  return {status: 'succeeded', receipt: saved};
}
async function finish(context: LegacyPersonAccessContext, access: FenceAccess, pending: Extract<LegacyPersonAccessPending, {kind: 'owned'}>, value: unknown): Promise<LegacyPersonAccessResult> {
  const direct = receipt(context, value, pending.attempt), found = await lookupUnderFence(context, pending);
  if (found.status !== 'succeeded' || JSON.stringify(found.receipt) !== JSON.stringify(direct)) fail('The original person receipt could not be verified.');
  await clear(context, access, pending); return {status: 'succeeded', receipt: direct};
}
async function verifyFresh(context: LegacyPersonAccessContext, intent: LegacyPersonAccessIntent, source: LegacyPersonSnapshot) {
  checkWrite(context, intent);
  if (!context.verifyFresh || !await context.verifyFresh()) fail('Verify your account before changing this person.');
  checkWrite(context, intent);
  const latest = await currentLegacyPerson(context, true);
  if (JSON.stringify(latest) !== JSON.stringify(source)) fail('The person changed. Review it again.');
  checkWrite(context, intent);
}
export async function submitLegacyPersonAccess(context: LegacyPersonAccessContext, input: unknown, source: LegacyPersonSnapshot, observedRevision: string): Promise<LegacyPersonAccessResult> {
  const intent = parseLegacyPersonAccessIntent(input, source); checkWrite(context, intent);
  return fence(context, async access => {
    const existing = await restoreUnderFence(context, access); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const latest = await currentLegacyPerson(context, true);
    if (JSON.stringify(latest) !== JSON.stringify(source)) fail('The person changed. Review it again.');
    await verifyFresh(context, intent, source);
    const requestKey = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, FAMILY, context.userId, requestKey, PERMISSION, {...intent}, context.storage); verifyAttempt(context, attempt); await saveBinding(context, requestKey, attempt, latest);}
    catch (error) {if (context.isCurrent()) {try {const retained = await readPending(context.identity, FAMILY, context.userId, context.storage); if (retained?.request_key === requestKey) await clearPending(context.identity, FAMILY, context.userId, requestKey, context.storage); await clearBinding(context, requestKey); access.clear(requestKey);} catch { /* Preserve an uncertain fence. */ }} throw error;}
    const pending: Extract<LegacyPersonAccessPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || !enabled(context, intent)) return {status: 'unknown', requestKey};
    try {const response = await context.request(`operations/users/${context.userId}`, {method: 'PATCH', body: {...intent}, idempotencyKey: requestKey}); checkWrite(context, intent); return await finish(context, access, pending, response);}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLegacyPersonAccess(context: LegacyPersonAccessContext, pending: LegacyPersonAccessPending): Promise<LegacyPersonAccessLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return fence(context, async access => {const saved = await restoreUnderFence(context, access); if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey) fail('The original person request could not be verified.'); const result = await lookupUnderFence(context, saved); if (result.status === 'succeeded') await clear(context, access, saved); return result;});
}
export async function retryLegacyPersonAccess(context: LegacyPersonAccessContext, pending: LegacyPersonAccessPending): Promise<LegacyPersonAccessResult> {
  check(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original person intent is unavailable.');
  return fence(context, async access => {
    const saved = await restoreUnderFence(context, access);
    if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey || !saved.attempt || JSON.stringify(saved.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original person request could not be verified.');
    const result = await lookupUnderFence(context, saved);
    if (result.status === 'succeeded') {await clear(context, access, saved); return {status: 'succeeded', receipt: result.receipt};}
    if (result.status !== 'not_found' || !result.retryAvailable) fail('The original person request remains unresolved.');
    const owner = await binding(context, saved.requestKey, saved.attempt), latest = await currentLegacyPerson(context, true), intent = parseLegacyPersonAccessIntent(saved.attempt.intent, latest);
    if (owner.kind !== 'valid' || await sha256Text(JSON.stringify(latest)) !== owner.sourceSha256) fail('The original person changed. Check the request before continuing.');
    await verifyFresh(context, intent, latest);
    try {const response = await context.request(`operations/users/${context.userId}`, {method: 'PATCH', body: {...intent}, idempotencyKey: saved.requestKey}); checkWrite(context, intent); return await finish(context, access, saved, response);}
    catch {return {status: 'unknown', requestKey: saved.requestKey};}
  });
}
