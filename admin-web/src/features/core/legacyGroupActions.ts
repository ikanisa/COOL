import type {FenceAccess} from '../operations/pendingFence';
import {clearPending, pendingAuthority, readPending, retainPending, sha256Text, type PendingAttempt} from './pendingAttempt';
import {
  assertLegacyGroupAccess, currentLegacyGroup, exact, fail, groupRequestFamilies, withLegacyGroupFence, groupBindingSchema, nullableText, groupRequestPermissions,
  readLegacyOwner, parseLegacyGroupReceipt, groupRequestResource, safeText, LEGACY_GROUP_STATUS_FAMILY, legacyGroupStorage, UUID, assertLegacyGroupWrite,
  type LegacyGroupContext, type LegacyGroupIntent, type LegacyGroupReceipt, type LegacyGroupSnapshot, type LegacyOwner,
} from './legacyGroupRecords';

export {currentLegacyGroup, readLegacyOwner, searchLegacyOwners} from './legacyGroupRecords';
export type {LegacyGroupContext, LegacyGroupIntent, LegacyGroupReceipt, LegacyGroupSnapshot, LegacyOwner} from './legacyGroupRecords';

export type LegacyGroupPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'} | {kind: 'guarded'};
export type LegacyGroupResult = {status: 'succeeded'; receipt: LegacyGroupReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LegacyGroupPending};
export type LegacyGroupLookup = {status: 'succeeded'; receipt: LegacyGroupReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
type Source = LegacyOwner | LegacyGroupSnapshot | null;
export function parseLegacyGroupIntent(value: unknown, mode: 'create' | 'edit'): LegacyGroupIntent {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('The original group details could not be verified.');
  const body = value as Record<string, unknown>;
  const base = ['title', 'collection_type', 'description', 'category_subtype', 'purpose_label', 'recurring_cadence', 'suggested_amount_rwf', 'reason'];
  const fields = mode === 'edit' ? [...base, 'expected_version'] : [...base, 'slug', 'visibility', 'is_platform_sponsored', 'status', ...(Object.hasOwn(body, 'owner_user_id') ? ['owner_user_id'] : []), ...(Object.hasOwn(body, 'receiver') ? ['receiver'] : [])];
  const receiver = body.receiver;
  if (!exact(body, fields) || !safeText(body.title, 3, 160) || !['ikimina', 'sport', 'church', 'wedding', 'other'].includes(String(body.collection_type)) ||
      !safeText(body.description, 0, 1000) || !nullableText(body.category_subtype) || !nullableText(body.purpose_label) ||
      !(body.recurring_cadence === null || ['weekly', 'monthly', 'quarterly', 'annually'].includes(String(body.recurring_cadence))) ||
      !(body.suggested_amount_rwf === null || typeof body.suggested_amount_rwf === 'number' && Number.isSafeInteger(body.suggested_amount_rwf) && body.suggested_amount_rwf > 0) || !safeText(body.reason, 8, 1000)) fail('The original group details could not be verified.');
  if (mode === 'edit') {
    if (typeof body.expected_version !== 'number' || !Number.isSafeInteger(body.expected_version) || body.expected_version < 1 || body.expected_version >= Number.MAX_SAFE_INTEGER) fail('The original group version could not be verified.');
  } else if (typeof body.slug !== 'string' || body.slug.length < 3 || body.slug.length > 100 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(body.slug) || body.visibility !== 'private' || body.is_platform_sponsored !== false ||
      !['draft', 'active'].includes(String(body.status)) || Object.hasOwn(body, 'owner_user_id') && (typeof body.owner_user_id !== 'string' || !UUID.test(body.owner_user_id)) ||
      Object.hasOwn(body, 'receiver') && (!receiver || typeof receiver !== 'object' || Array.isArray(receiver) || !exact(receiver as Record<string, unknown>, ['label', 'network', 'momo_number_or_code']) || !safeText((receiver as Record<string, unknown>).label, 2, 120) || !['mtn_momo', 'airtel_money'].includes(String((receiver as Record<string, unknown>).network)) || typeof (receiver as Record<string, unknown>).momo_number_or_code !== 'string' || !/^\d{4,12}$/.test(String((receiver as Record<string, unknown>).momo_number_or_code))) ||
      body.status === 'active' && (!body.owner_user_id || !body.receiver)) fail('The original group details could not be verified.');
  return body as unknown as LegacyGroupIntent;
}

async function source(context: LegacyGroupContext, intent: LegacyGroupIntent): Promise<Source> {
  if (context.mode === 'edit') return currentLegacyGroup(context);
  return intent.owner_user_id ? readLegacyOwner(context, intent.owner_user_id) : null;
}
function verifyAttempt(context: LegacyGroupContext, attempt: PendingAttempt) {
  if (attempt.family !== groupRequestFamilies[context.mode] || attempt.resource_id !== groupRequestResource(context) || attempt.permission !== groupRequestPermissions[context.mode] || !UUID.test(attempt.request_key)) fail('The original group request could not be verified.');
}
function bindingKey(context: LegacyGroupContext) {return `collect.admin.legacy-group-${context.mode}.context.v1:${groupRequestResource(context)}`;}
async function binding(context: LegacyGroupContext, key: string, attempt?: PendingAttempt): Promise<{kind: 'valid'; sourceSha256: string} | {kind: 'missing' | 'foreign' | 'mismatch'}> {
  let raw: string | null; try {raw = legacyGroupStorage(context).getItem(bindingKey(context));} catch {return fail('Recovery storage is unavailable.');}
  if (raw === null) return {kind: 'missing'}; if (raw.length > 1000) fail('The original group request could not be verified.');
  let value: unknown; try {value = JSON.parse(raw);} catch {return fail('The original group request could not be verified.');}
  const data = groupBindingSchema.parse(value);
  if (data.request_key !== key) fail('The original group request could not be verified.');
  if (data.authority_sha256 !== await pendingAuthority(context.identity)) return {kind: 'foreign'};
  if (attempt && data.intent_sha256 !== await sha256Text(JSON.stringify(attempt.intent))) return {kind: 'mismatch'};
  return {kind: 'valid', sourceSha256: data.source_sha256};
}
async function saveBinding(context: LegacyGroupContext, key: string, attempt: PendingAttempt, sourceValue: Source) {
  if ((await binding(context, key)).kind !== 'missing') fail('The original group request could not be verified.');
  const storage = legacyGroupStorage(context), name = bindingKey(context), raw = JSON.stringify({version: 1, request_key: key, authority_sha256: await pendingAuthority(context.identity), intent_sha256: await sha256Text(JSON.stringify(attempt.intent)), source_sha256: await sha256Text(JSON.stringify(sourceValue)), model: 'transaction_journals'}); assertLegacyGroupAccess(context);
  try {storage.setItem(name, raw); if (storage.getItem(name) !== raw) fail('Recovery storage is unavailable.');} catch {fail('Recovery storage is unavailable.');} assertLegacyGroupAccess(context);
}
async function clearBinding(context: LegacyGroupContext, key: string) {
  const state = await binding(context, key); if (state.kind === 'foreign') fail('The original group request could not be verified.'); if (state.kind === 'missing') return;
  const storage = legacyGroupStorage(context), name = bindingKey(context); assertLegacyGroupAccess(context);
  try {storage.removeItem(name); if (storage.getItem(name) !== null) fail('Recovery storage is unavailable.');} catch {fail('Recovery storage is unavailable.');}
}
async function restoreUnderFence(context: LegacyGroupContext, access: FenceAccess): Promise<LegacyGroupPending> {
  assertLegacyGroupAccess(context); const shared = access.read(); if (shared.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, groupRequestFamilies[context.mode], groupRequestResource(context), context.storage); if (attempt) verifyAttempt(context, attempt);
  const guarded = context.mode === 'edit' ? await readPending(context.identity, LEGACY_GROUP_STATUS_FAMILY, groupRequestResource(context), context.storage) : null;
  if (guarded) {
    if (attempt || shared.kind === 'owned' && shared.requestKey !== guarded.request_key) fail('Multiple group requests need recovery.');
    if (shared.kind === 'empty') access.reserve(guarded.request_key, shared.revision);
    return {kind:'guarded'};
  }
  const owner = attempt ? await binding(context, attempt.request_key, attempt) : {kind: 'missing' as const}; assertLegacyGroupAccess(context);
  if (owner.kind === 'foreign') return {kind: 'foreign'};
  if (shared.kind === 'owned') {if (attempt && attempt.request_key !== shared.requestKey) fail('The original group request could not be verified.'); return {kind: 'owned', requestKey: shared.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, shared.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};}
  return {kind: 'ready', revision: shared.revision};
}
export async function restoreLegacyGroupAction(context: LegacyGroupContext): Promise<LegacyGroupPending> {assertLegacyGroupAccess(context); return withLegacyGroupFence(context, access => restoreUnderFence(context, access));}
async function clear(context: LegacyGroupContext, access: FenceAccess, pending: Extract<LegacyGroupPending, {kind: 'owned'}>) {
  await clearBinding(context, pending.requestKey); if (pending.attempt) await clearPending(context.identity, groupRequestFamilies[context.mode], groupRequestResource(context), pending.requestKey, context.storage);
  assertLegacyGroupAccess(context); access.clear(pending.requestKey);
}
async function lookupUnderFence(context: LegacyGroupContext, pending: Extract<LegacyGroupPending, {kind: 'owned'}>): Promise<LegacyGroupLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); assertLegacyGroupAccess(context);
  if (body.status === 'not_found' && exact(body, ['status'])) {
    let retryAvailable = false; if (pending.attempt && (await binding(context, pending.requestKey, pending.attempt)).kind === 'valid') {try {parseLegacyGroupIntent(pending.attempt.intent, context.mode); retryAvailable = true;} catch { /* Other retained intents remain check-only. */ }}
    return {status: 'not_found', retryAvailable};
  }
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original group receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail('The original group receipt could not be verified.');
  const saved = parseLegacyGroupReceipt(context, body.receipt, pending.attempt); if (saved.requestId !== body.request_id) fail('The original group receipt could not be verified.');
  if (context.mode === 'edit' && !pending.attempt && (await currentLegacyGroup(context, true)).version < saved.version) fail('The group version could not be verified.');
  return {status: 'succeeded', receipt: saved};
}
async function finish(context: LegacyGroupContext, access: FenceAccess, pending: Extract<LegacyGroupPending, {kind: 'owned'}>, value: unknown): Promise<LegacyGroupResult> {
  const direct = parseLegacyGroupReceipt(context, value, pending.attempt), found = await lookupUnderFence(context, pending);
  if (found.status !== 'succeeded' || JSON.stringify(found.receipt) !== JSON.stringify(direct)) fail('The original group receipt could not be verified.');
  await clear(context, access, pending); return {status: 'succeeded', receipt: direct};
}
export async function submitLegacyGroupAction(context: LegacyGroupContext, input: unknown, expectedSource: Source, observedRevision: string): Promise<LegacyGroupResult> {
  assertLegacyGroupWrite(context); const intent = parseLegacyGroupIntent(input, context.mode);
  return withLegacyGroupFence(context, async access => {
    const existing = await restoreUnderFence(context, access); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const actual = await source(context, intent);
    if (JSON.stringify(actual) !== JSON.stringify(expectedSource) || context.mode === 'edit' && (actual as LegacyGroupSnapshot).version !== intent.expected_version) fail('The group or owner changed. Review it again.');
    assertLegacyGroupWrite(context); const requestKey = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, groupRequestFamilies[context.mode], groupRequestResource(context), requestKey, groupRequestPermissions[context.mode], {...intent}, context.storage); verifyAttempt(context, attempt); await saveBinding(context, requestKey, attempt, actual);}
    catch (error) {if (context.isCurrent()) {try {const retained = await readPending(context.identity, groupRequestFamilies[context.mode], groupRequestResource(context), context.storage); if (retained?.request_key === requestKey) await clearPending(context.identity, groupRequestFamilies[context.mode], groupRequestResource(context), requestKey, context.storage); await clearBinding(context, requestKey); access.clear(requestKey);} catch { /* Preserve the fence if cleanup is uncertain. */ }} throw error;}
    const pending: Extract<LegacyGroupPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey};
    try {const response = await context.request(context.mode === 'create' ? 'operations/groups' : `operations/groups/${context.groupId}`, {method: context.mode === 'create' ? 'POST' : 'PATCH', body: {...intent}, idempotencyKey: requestKey}); assertLegacyGroupAccess(context); return await finish(context, access, pending, response);}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLegacyGroupAction(context: LegacyGroupContext, pending: LegacyGroupPending): Promise<LegacyGroupLookup> {
  assertLegacyGroupAccess(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return withLegacyGroupFence(context, async access => {const stored = await restoreUnderFence(context, access); if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey) fail('The original group request could not be verified.'); const result = await lookupUnderFence(context, stored); if (result.status === 'succeeded' && stored.attempt) await clear(context, access, stored); return result;});
}
export async function retryLegacyGroupAction(context: LegacyGroupContext, pending: LegacyGroupPending): Promise<LegacyGroupResult> {
  assertLegacyGroupWrite(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original group intent is unavailable.');
  return withLegacyGroupFence(context, async access => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original group request could not be verified.');
    const previous = await lookupUnderFence(context, stored);
    if (previous.status === 'succeeded') {await clear(context, access, stored); return {status: 'succeeded', receipt: previous.receipt};}
    if (previous.status !== 'not_found' || !previous.retryAvailable) fail('The original group request remains unresolved.');
    const intent = parseLegacyGroupIntent(stored.attempt.intent, context.mode), owner = await binding(context, stored.requestKey, stored.attempt), actual = await source(context, intent);
    if (owner.kind !== 'valid' || await sha256Text(JSON.stringify(actual)) !== owner.sourceSha256 || context.mode === 'edit' && (actual as LegacyGroupSnapshot).version !== intent.expected_version) fail('The original group or owner changed. Check the request before continuing.');
    assertLegacyGroupWrite(context);
    try {const response = await context.request(context.mode === 'create' ? 'operations/groups' : `operations/groups/${context.groupId}`, {method: context.mode === 'create' ? 'POST' : 'PATCH', body: {...intent}, idempotencyKey: stored.requestKey}); assertLegacyGroupAccess(context); return await finish(context, access, stored, response);}
    catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
