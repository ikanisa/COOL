/* eslint-disable no-control-regex -- Validate operator-entered account details and audit reasons. */
import type {FenceAccess} from '../operations/pendingFence';
import {currentLegacyPerson, type LegacyPersonSnapshot, type LegacyUserEditContext} from './legacyUserEdit';
import {clearPending, readPending, retainPending, sha256Text, type PendingAttempt} from './pendingAttempt';
import {
  assertPersonAttempt, canManageLegacyPerson, clearPersonBinding, clearPersonRequest, parsePersonReceipt,
  PERSON_EDIT_FAMILY, PERSON_EDIT_PERMISSION, readPersonBinding, restorePersonRequest, savePersonBinding, withPersonFence,
} from './legacyPersonRecovery';

const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const EMAIL = /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/;
const PHONE = /^\+2507[2389]\d{7}$/;

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
  if (!canManageLegacyPerson(context)) fail('Person access changes are unavailable to your current account.');
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

export async function restoreLegacyPersonAccess(context: LegacyPersonAccessContext): Promise<LegacyPersonAccessPending> {check(context); return withPersonFence(context, access => restorePersonRequest(context, access, () => check(context)));}
async function lookupUnderFence(context: LegacyPersonAccessContext, pending: Extract<LegacyPersonAccessPending, {kind: 'owned'}>): Promise<LegacyPersonAccessLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) {
    let retryAvailable = false;
    if (pending.attempt && (await readPersonBinding(context, pending.requestKey, pending.attempt)).kind === 'valid') {
      try {const person = await currentLegacyPerson(context, true); retryAvailable = enabled(context, parseLegacyPersonAccessIntent(pending.attempt.intent, person));} catch { /* Unknown or changed intents stay check-only. */ }
    }
    return {status: 'not_found', retryAvailable};
  }
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original person receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail('The original person receipt could not be verified.');
  const saved = parsePersonReceipt(context, body.receipt, pending.attempt); if (saved.requestId !== body.request_id) fail('The original person receipt could not be verified.');
  if (!pending.attempt && (await currentLegacyPerson(context, true)).version < saved.version) fail('The person version could not be verified.');
  return {status: 'succeeded', receipt: saved};
}
async function finish(context: LegacyPersonAccessContext, access: FenceAccess, pending: Extract<LegacyPersonAccessPending, {kind: 'owned'}>, value: unknown): Promise<LegacyPersonAccessResult> {
  const direct = parsePersonReceipt(context, value, pending.attempt), found = await lookupUnderFence(context, pending);
  if (found.status !== 'succeeded' || JSON.stringify(found.receipt) !== JSON.stringify(direct)) fail('The original person receipt could not be verified.');
  await clearPersonRequest(context, access, pending, () => check(context)); return {status: 'succeeded', receipt: direct};
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
  return withPersonFence(context, async access => {
    const existing = await restorePersonRequest(context, access, () => check(context)); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const latest = await currentLegacyPerson(context, true);
    if (JSON.stringify(latest) !== JSON.stringify(source)) fail('The person changed. Review it again.');
    await verifyFresh(context, intent, source);
    const requestKey = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, PERSON_EDIT_FAMILY, context.userId, requestKey, PERSON_EDIT_PERMISSION, {...intent}, context.storage); assertPersonAttempt(context, attempt); await savePersonBinding(context, requestKey, attempt, latest, () => check(context));}
    catch (error) {if (context.isCurrent()) {try {const retained = await readPending(context.identity, PERSON_EDIT_FAMILY, context.userId, context.storage); if (retained?.request_key === requestKey) await clearPending(context.identity, PERSON_EDIT_FAMILY, context.userId, requestKey, context.storage); await clearPersonBinding(context, requestKey, () => check(context)); access.clear(requestKey);} catch { /* Preserve an uncertain fence. */ }} throw error;}
    const pending: Extract<LegacyPersonAccessPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || !enabled(context, intent)) return {status: 'unknown', requestKey};
    try {const response = await context.request(`operations/users/${context.userId}`, {method: 'PATCH', body: {...intent}, idempotencyKey: requestKey}); checkWrite(context, intent); return await finish(context, access, pending, response);}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLegacyPersonAccess(context: LegacyPersonAccessContext, pending: LegacyPersonAccessPending): Promise<LegacyPersonAccessLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return withPersonFence(context, async access => {const saved = await restorePersonRequest(context, access, () => check(context)); if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey) fail('The original person request could not be verified.'); const result = await lookupUnderFence(context, saved); if (result.status === 'succeeded') await clearPersonRequest(context, access, saved, () => check(context)); return result;});
}
export async function retryLegacyPersonAccess(context: LegacyPersonAccessContext, pending: LegacyPersonAccessPending): Promise<LegacyPersonAccessResult> {
  check(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original person intent is unavailable.');
  return withPersonFence(context, async access => {
    const saved = await restorePersonRequest(context, access, () => check(context));
    if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey || !saved.attempt || JSON.stringify(saved.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original person request could not be verified.');
    const result = await lookupUnderFence(context, saved);
    if (result.status === 'succeeded') {await clearPersonRequest(context, access, saved, () => check(context)); return {status: 'succeeded', receipt: result.receipt};}
    if (result.status !== 'not_found' || !result.retryAvailable) fail('The original person request remains unresolved.');
    const owner = await readPersonBinding(context, saved.requestKey, saved.attempt), latest = await currentLegacyPerson(context, true), intent = parseLegacyPersonAccessIntent(saved.attempt.intent, latest);
    if (owner.kind !== 'valid' || await sha256Text(JSON.stringify(latest)) !== owner.sourceSha256) fail('The original person changed. Check the request before continuing.');
    await verifyFresh(context, intent, latest);
    try {const response = await context.request(`operations/users/${context.userId}`, {method: 'PATCH', body: {...intent}, idempotencyKey: saved.requestKey}); checkWrite(context, intent); return await finish(context, access, saved, response);}
    catch {return {status: 'unknown', requestKey: saved.requestKey};}
  });
}
