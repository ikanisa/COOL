/* eslint-disable no-control-regex -- Validate recorded profile details and audit reasons. */
import type { AdminRequest } from '../../api/client';
import { clearPending, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity } from './pendingAttempt';
import {
  assertPersonAttempt, canManageLegacyPerson, clearPersonBinding, clearPersonRequest, parsePersonReceipt,
  PERSON_EDIT_FAMILY, PERSON_EDIT_PERMISSION, readPersonBinding, restorePersonRequest, savePersonBinding, withPersonFence,
} from './legacyPersonRecovery';
import type {FenceAccess, FenceLock} from '../operations/pendingFence';

const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
export interface LegacyUserEditContext {
  request: AdminRequest; identity: PendingIdentity; actorId: string; userId: string; permissions: readonly string[]; financialModel: 'transaction_journals' | 'canonical_evidence_ledger';
  enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean; storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;
  statusEnabled?: boolean; isStatusEnabled?: () => boolean; verifyStatusFresh?: () => Promise<boolean>;
}
export interface LegacyPersonSnapshot {id: string; publicId: string; displayName: string | null; nameRecorded: boolean; memberType: 'app' | 'direct'; momoProvider: '' | 'mtn_momo' | 'airtel_money'; momoNumber: string; momoCode: string; email: string | null; phone: string | null; status: 'invited' | 'active' | 'suspended' | 'closed'; operatorId: string | null; version: number;}
export interface LegacyUserProfileIntent {display_name: string; momo_provider: '' | 'mtn_momo' | 'airtel_money'; momo_number: string; momo_pay_code: string; expected_version: number; reason: string;}
export type LegacyUserStatus = LegacyPersonSnapshot['status'];
export interface LegacyUserStatusIntent {status: LegacyUserStatus; expected_version: number; reason: string;}
export type LegacyUserEditIntent = LegacyUserProfileIntent | LegacyUserStatusIntent;
export interface LegacyUserEditReceipt {requestId: string; userId: string; version: number;}
export type LegacyUserEditPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type LegacyUserEditResult = {status: 'succeeded'; receipt: LegacyUserEditReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LegacyUserEditPending};
export type LegacyUserEditLookup = {status: 'succeeded'; receipt: LegacyUserEditReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
function fail(message: string): never {throw new Error(message);}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function safeText(value: unknown, minimum: number, maximum: number): value is string {return typeof value === 'string' && value === value.trim() && value.length >= minimum && value.length <= maximum && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value);}
function check(context: LegacyUserEditContext) {
  if (!canManageLegacyPerson(context)) fail('Person editing is unavailable to your current account.');
}
function statusIntent(intent: LegacyUserEditIntent): intent is LegacyUserStatusIntent {return 'status' in intent;}
function actionEnabled(context: LegacyUserEditContext, intent: LegacyUserEditIntent): boolean {
  return statusIntent(intent) ? context.statusEnabled === true && typeof context.verifyStatusFresh === 'function' && (!context.isStatusEnabled || context.isStatusEnabled()) :
    context.enabled && (!context.isEnabled || context.isEnabled());
}
function write(context: LegacyUserEditContext, intent: LegacyUserEditIntent) {
  check(context); if (!actionEnabled(context, intent)) fail('This person change is not enabled for this workspace.');
}
async function verifyForWrite(context: LegacyUserEditContext, intent: LegacyUserEditIntent) {
  write(context, intent);
  if (statusIntent(intent)) {
    if (!context.verifyStatusFresh || !await context.verifyStatusFresh()) fail('Verify your account before changing this status.');
    write(context, intent);
  }
}
export function parseLegacyUserEditIntent(value: unknown, memberType: 'app' | 'direct'): LegacyUserEditIntent {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('The original person change could not be verified.');
  const body = value as Record<string, unknown>;
  if (exact(body, ['status', 'expected_version', 'reason'])) {
    if (typeof body.status !== 'string' || !['invited', 'active', 'suspended', 'closed'].includes(body.status) ||
        typeof body.expected_version !== 'number' || !Number.isSafeInteger(body.expected_version) || body.expected_version < 1 ||
        body.expected_version >= Number.MAX_SAFE_INTEGER || !safeText(body.reason, 8, 1000)) fail('The original person status could not be verified.');
    return body as unknown as LegacyUserStatusIntent;
  }
  if (!exact(body, ['display_name', 'momo_provider', 'momo_number', 'momo_pay_code', 'expected_version', 'reason']) || !safeText(body.display_name, 2, 120) ||
      !['', 'mtn_momo', 'airtel_money'].includes(String(body.momo_provider)) || typeof body.momo_number !== 'string' || body.momo_number !== '' && !/^07[2389]\d{7}$/.test(body.momo_number) ||
      body.momo_number !== '' && body.momo_provider === 'mtn_momo' && !/^07[89]/.test(body.momo_number) || body.momo_number !== '' && body.momo_provider === 'airtel_money' && !/^07[23]/.test(body.momo_number) ||
      memberType === 'direct' && body.momo_number === '' || typeof body.momo_pay_code !== 'string' || body.momo_pay_code !== '' && !/^\d{4,9}$/.test(body.momo_pay_code) ||
      typeof body.expected_version !== 'number' || !Number.isSafeInteger(body.expected_version) || body.expected_version < 1 || body.expected_version >= Number.MAX_SAFE_INTEGER || !safeText(body.reason, 8, 1000)) fail('The original person change could not be verified.');
  return body as unknown as LegacyUserProfileIntent;
}
export async function currentLegacyPerson(context: LegacyUserEditContext, recovering = false): Promise<LegacyPersonSnapshot> {
  check(context); const body = await context.request(`operations/users/${context.userId}`); check(context);
  if (body.contract_version !== undefined || body.model !== undefined || body.resource_type !== 'users' || body.current_actor_id !== context.actorId || body.can_manage !== true || !body.resource || typeof body.resource !== 'object' || Array.isArray(body.resource)) fail('The person could not be verified.');
  const row = body.resource as Record<string, unknown>, provider = row.momo_provider ?? '', number = row.momo_number ?? '', code = row.momo_pay_code ?? '';
  if (row.id !== context.userId || row.collect_user_id !== context.userId || typeof row.public_id !== 'string' || !/^\d{6}$/.test(row.public_id) ||
      typeof row.display_name_recorded !== 'boolean' || !(row.display_name_recorded ? safeText(row.display_name, 2, 120) : row.display_name === null) ||
      !['app', 'direct'].includes(String(row.member_type)) || !['', 'mtn_momo', 'airtel_money'].includes(String(provider)) || typeof number !== 'string' || number !== '' && !/^07[2389]\d{7}$/.test(number) ||
      typeof code !== 'string' || code !== '' && !/^\d{4,9}$/.test(code) || !(row.email === null || typeof row.email === 'string' && row.email.length <= 254) ||
      !(row.phone_e164 === null || typeof row.phone_e164 === 'string' && /^\+2507[2389]\d{7}$/.test(row.phone_e164)) || !['invited', 'active', 'suspended', 'closed'].includes(String(row.status)) ||
      !(row.operator_admin_id === null || typeof row.operator_admin_id === 'string' && UUID.test(row.operator_admin_id)) || !recovering && (row.status === 'closed' || row.operator_admin_id !== null) ||
      typeof row.version !== 'number' || !Number.isSafeInteger(row.version) || row.version < 1 || row.version >= Number.MAX_SAFE_INTEGER) fail('The person could not be verified.');
  return {id: context.userId, publicId: row.public_id, displayName: row.display_name as string | null, nameRecorded: row.display_name_recorded, memberType: row.member_type as 'app' | 'direct', momoProvider: provider as LegacyPersonSnapshot['momoProvider'], momoNumber: number, momoCode: code, email: row.email as string | null, phone: row.phone_e164 as string | null, status: row.status as LegacyPersonSnapshot['status'], operatorId: row.operator_admin_id as string | null, version: row.version};
}
export async function restoreLegacyUserEdit(context: LegacyUserEditContext): Promise<LegacyUserEditPending> {check(context); return withPersonFence(context, access => restorePersonRequest(context, access, () => check(context)));}
async function lookupUnderFence(context: LegacyUserEditContext, pending: Extract<LegacyUserEditPending, {kind: 'owned'}>): Promise<LegacyUserEditLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) {
    let retryAvailable = false;
    if (pending.attempt && (await readPersonBinding(context, pending.requestKey, pending.attempt)).kind === 'valid') {try {retryAvailable = actionEnabled(context, parseLegacyUserEditIntent(pending.attempt.intent, 'app'));} catch { /* Unknown retained intents remain check-only. */ }}
    return {status: 'not_found', retryAvailable};
  }
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original person receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail('The original person receipt could not be verified.');
  const saved = parsePersonReceipt(context, body.receipt, pending.attempt); if (saved.requestId !== body.request_id) fail('The original person receipt could not be verified.');
  if (!pending.attempt && (await currentLegacyPerson(context, true)).version < saved.version) fail('The person version could not be verified.');
  return {status: 'succeeded', receipt: saved};
}
async function finish(context: LegacyUserEditContext, access: FenceAccess, pending: Extract<LegacyUserEditPending, {kind: 'owned'}>, value: unknown): Promise<LegacyUserEditResult> {
  const direct = parsePersonReceipt(context, value, pending.attempt), found = await lookupUnderFence(context, pending);
  if (found.status !== 'succeeded' || JSON.stringify(found.receipt) !== JSON.stringify(direct)) fail('The original person receipt could not be verified.');
  await clearPersonRequest(context, access, pending, () => check(context)); return {status: 'succeeded', receipt: direct};
}
export async function submitLegacyUserEdit(context: LegacyUserEditContext, input: unknown, source: LegacyPersonSnapshot, observedRevision: string): Promise<LegacyUserEditResult> {
  const intent = parseLegacyUserEditIntent(input, source.memberType); write(context, intent);
  if (statusIntent(intent) && (source.status === 'closed' || source.status === intent.status)) fail('Choose a different status for an open account.');
  return withPersonFence(context, async access => {
    const existing = await restorePersonRequest(context, access, () => check(context)); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const latest = await currentLegacyPerson(context);
    if (JSON.stringify(latest) !== JSON.stringify(source) || latest.version !== intent.expected_version) fail('The person changed. Review it again.');
    await verifyForWrite(context, intent);
    if (statusIntent(intent) && JSON.stringify(await currentLegacyPerson(context)) !== JSON.stringify(source)) fail('The person changed. Review it again.');
    write(context, intent); const requestKey = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, PERSON_EDIT_FAMILY, context.userId, requestKey, PERSON_EDIT_PERMISSION, {...intent}, context.storage); assertPersonAttempt(context, attempt); await savePersonBinding(context, requestKey, attempt, latest, () => check(context));}
    catch (error) {if (context.isCurrent()) {try {const retained = await readPending(context.identity, PERSON_EDIT_FAMILY, context.userId, context.storage); if (retained?.request_key === requestKey) await clearPending(context.identity, PERSON_EDIT_FAMILY, context.userId, requestKey, context.storage); await clearPersonBinding(context, requestKey, () => check(context)); access.clear(requestKey);} catch { /* Preserve the fence if cleanup is uncertain. */ }} throw error;}
    const pending: Extract<LegacyUserEditPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || !actionEnabled(context, intent)) return {status: 'unknown', requestKey};
    try {const response = await context.request(`operations/users/${context.userId}`, {method: 'PATCH', body: {...intent}, idempotencyKey: requestKey}); check(context); return await finish(context, access, pending, response);}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLegacyUserEdit(context: LegacyUserEditContext, pending: LegacyUserEditPending): Promise<LegacyUserEditLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return withPersonFence(context, async access => {const stored = await restorePersonRequest(context, access, () => check(context)); if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey) fail('The original person request could not be verified.'); const result = await lookupUnderFence(context, stored); if (result.status === 'succeeded') await clearPersonRequest(context, access, stored, () => check(context)); return result;});
}
export async function retryLegacyUserEdit(context: LegacyUserEditContext, pending: LegacyUserEditPending): Promise<LegacyUserEditResult> {
  check(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original person intent is unavailable.');
  return withPersonFence(context, async access => {
    const stored = await restorePersonRequest(context, access, () => check(context));
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original person request could not be verified.');
    const previous = await lookupUnderFence(context, stored);
    if (previous.status === 'succeeded') {await clearPersonRequest(context, access, stored, () => check(context)); return {status: 'succeeded', receipt: previous.receipt};}
    if (previous.status !== 'not_found' || !previous.retryAvailable) fail('The original person request remains unresolved.');
    const owner = await readPersonBinding(context, stored.requestKey, stored.attempt), latest = await currentLegacyPerson(context), intent = parseLegacyUserEditIntent(stored.attempt.intent, latest.memberType);
    if (owner.kind !== 'valid' || await sha256Text(JSON.stringify(latest)) !== owner.sourceSha256 || latest.version !== intent.expected_version) fail('The original person changed. Check the request before continuing.');
    if (statusIntent(intent) && (latest.status === 'closed' || latest.status === intent.status)) fail('The original person changed. Check the request before continuing.');
    await verifyForWrite(context, intent);
    if (statusIntent(intent) && JSON.stringify(await currentLegacyPerson(context)) !== JSON.stringify(latest)) fail('The original person changed. Check the request before continuing.');
    write(context, intent);
    try {const response = await context.request(`operations/users/${context.userId}`, {method: 'PATCH', body: {...intent}, idempotencyKey: stored.requestKey}); check(context); return await finish(context, access, stored, response);}
    catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
