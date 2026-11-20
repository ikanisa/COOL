/* eslint-disable no-control-regex -- Validate legacy group details and audit reasons. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import { clearPending, pendingAuthority, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity } from './pendingAttempt';
import { withPendingFence, type FenceAccess, type FenceLock } from '../operations/pendingFence';

const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/, HASH = /^[a-f0-9]{64}$/;
const id = z.string().regex(UUID), count = z.number().int().min(1).max(Number.MAX_SAFE_INTEGER);
export interface LegacyGroupContext {
  mode: 'create' | 'edit'; groupId?: string; request: AdminRequest; identity: PendingIdentity; actorId: string; permissions: readonly string[];
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean;
  storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;
}
export interface LegacyOwner {id: string; publicId: string; displayName: string | null; memberType: 'app' | 'direct'; momoNumber: string | null; version: number;}
export interface LegacyGroupSnapshot {id: string; slug: string; title: string; type: string; description: string; category: string | null; purpose: string | null; cadence: string | null; amount: number | null; status: string; visibility: string; sponsored: number; version: number;}
export interface LegacyGroupIntent {title: string; collection_type: 'ikimina' | 'sport' | 'church' | 'wedding' | 'other'; description: string; category_subtype: string | null; purpose_label: string | null; recurring_cadence: 'weekly' | 'monthly' | 'quarterly' | 'annually' | null; suggested_amount_rwf: number | null; reason: string; slug?: string; visibility?: 'private'; is_platform_sponsored?: false; status?: 'draft' | 'active'; owner_user_id?: string; receiver?: {label: string; network: 'mtn_momo' | 'airtel_money'; momo_number_or_code: string}; expected_version?: number;}
export interface LegacyGroupReceipt {requestId: string; groupId: string; version: number;}
export type LegacyGroupPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'} | {kind: 'guarded'};
export type LegacyGroupResult = {status: 'succeeded'; receipt: LegacyGroupReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LegacyGroupPending};
export type LegacyGroupLookup = {status: 'succeeded'; receipt: LegacyGroupReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
type Source = LegacyOwner | LegacyGroupSnapshot | null;
const families = {create: 'operating-creategroup', edit: 'operating-updategroup'} as const;
const STATUS_FAMILY = 'legacy-group-status-v2';
const permission = {create: 'collections.create', edit: 'collections.manage'} as const;
function fail(message: string): never {throw new Error(message);}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function resource(context: LegacyGroupContext) {return context.mode === 'create' ? 'new' : context.groupId ?? '';}
function check(context: LegacyGroupContext) {
  const needed = [permission[context.mode], 'overview.read', ...(context.mode === 'edit' ? ['collections.read'] : context.identity.role === 'staff' ? [] : ['collections.manage'])], expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'transaction_journals' || !UUID.test(context.actorId) || context.identity.id !== context.actorId ||
      context.mode === 'edit' && (context.identity.role === 'staff' || !context.groupId || !UUID.test(context.groupId)) ||
      !needed.every(value => context.permissions.includes(value) && context.identity.permissions.includes(value)) || !Number.isFinite(expires) || expires <= Date.now()) fail('Group changes are unavailable to your current account.');
}
function write(context: LegacyGroupContext) {check(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Group changes are not enabled for this workspace.');}
function hasOwnerAccess(context: LegacyGroupContext) {return ['users.read'].every(value => context.permissions.includes(value) && context.identity.permissions.includes(value));}
function safeText(value: unknown, minimum: number, maximum: number): value is string {return typeof value === 'string' && value === value.trim() && value.length >= minimum && value.length <= maximum && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value);}
const nullableText = (value: unknown) => value === null || safeText(value, 0, 120);
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
function ownerFrom(value: unknown): LegacyOwner {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('The group owner could not be verified.');
  const row = value as Record<string, unknown>;
  if (typeof row.id !== 'string' || !UUID.test(row.id) || typeof row.public_id !== 'string' || !/^\d{6}$/.test(row.public_id) ||
      !(row.display_name === null || safeText(row.display_name, 1, 120)) || !['app', 'direct'].includes(String(row.member_type)) ||
      !(row.momo_number === null || row.momo_number === '' || typeof row.momo_number === 'string' && /^07[2389]\d{7}$/.test(row.momo_number)) ||
      typeof row.version !== 'number' || !Number.isSafeInteger(row.version) || row.version < 1) fail('The group owner could not be verified.');
  return {id: row.id, publicId: row.public_id, displayName: row.display_name as string | null, memberType: row.member_type as LegacyOwner['memberType'], momoNumber: row.momo_number ? String(row.momo_number) : null, version: row.version};
}
export async function searchLegacyOwners(context: LegacyGroupContext, search: string): Promise<LegacyOwner[]> {
  write(context); if (context.mode !== 'create' || !hasOwnerAccess(context) || search.length > 200 || /[\x00-\x1f\x7f]/.test(search)) fail('Owner search is unavailable.');
  const query = new URLSearchParams({kind: 'users', search: search.trim(), limit: '25'}), body = await context.request(`operations/lookups?${query}`); check(context);
  if (!exact(body, ['rows']) || !Array.isArray(body.rows) || body.rows.length > 25) fail('Owner search could not be verified.');
  const rows = body.rows.map(ownerFrom); if (new Set(rows.map(row => row.id)).size !== rows.length) fail('Owner search could not be verified.'); return rows;
}
async function currentOwner(context: LegacyGroupContext, ownerId: string): Promise<LegacyOwner> {
  if (!hasOwnerAccess(context)) fail('Owner search is unavailable.');
  const body = await context.request(`operations/users/${ownerId}`); check(context);
  if (body.contract_version !== undefined || body.model !== undefined || body.resource_type !== 'users' || body.current_actor_id !== context.actorId || !body.resource || typeof body.resource !== 'object' || Array.isArray(body.resource)) fail('The group owner could not be verified.');
  const row = body.resource as Record<string, unknown>, owner = ownerFrom(row);
  if (owner.id !== ownerId || row.collect_user_id !== ownerId || row.status !== 'active' || row.display_name_recorded !== (owner.displayName !== null)) fail('The group owner could not be verified.');
  return owner;
}
export async function readLegacyOwner(context: LegacyGroupContext, ownerId: string): Promise<LegacyOwner> {check(context); return currentOwner(context, ownerId);}
export async function currentLegacyGroup(context: LegacyGroupContext, recover = false): Promise<LegacyGroupSnapshot> {
  check(context); if (context.mode !== 'edit' || !context.groupId) fail('The group could not be verified.');
  const body = await context.request(`operations/groups/${context.groupId}`); check(context);
  if (body.contract_version !== undefined || body.model !== undefined || body.resource_type !== 'groups' || body.current_actor_id !== context.actorId || body.can_manage !== true || !body.resource || typeof body.resource !== 'object' || Array.isArray(body.resource)) fail('The group could not be verified.');
  const row = body.resource as Record<string, unknown>;
  if (row.id !== context.groupId || typeof row.slug !== 'string' || !safeText(row.title, 3, 160) || !['ikimina', 'sport', 'church', 'wedding', 'other'].includes(String(row.collection_type)) ||
      !safeText(row.description, 0, 1000) || !nullableText(row.category_subtype) || !nullableText(row.purpose_label) ||
      !(row.recurring_cadence === null || ['weekly', 'monthly', 'quarterly', 'annually'].includes(String(row.recurring_cadence))) ||
      !(row.suggested_amount_rwf === null || typeof row.suggested_amount_rwf === 'number' && Number.isSafeInteger(row.suggested_amount_rwf) && row.suggested_amount_rwf > 0) ||
      !['draft', 'active', 'suspended', 'archived'].includes(String(row.status)) || !recover && row.status === 'archived' || !['private', 'public_approved'].includes(String(row.visibility)) ||
      row.is_platform_sponsored !== 0 && row.is_platform_sponsored !== 1 || row.country_code !== 'RW' || row.currency !== 'RWF' || typeof row.version !== 'number' || !Number.isSafeInteger(row.version) || row.version < 1 || row.version >= Number.MAX_SAFE_INTEGER) fail('The group could not be verified.');
  return {id: context.groupId, slug: row.slug, title: row.title, type: String(row.collection_type), description: row.description, category: row.category_subtype as string | null, purpose: row.purpose_label as string | null, cadence: row.recurring_cadence as string | null, amount: row.suggested_amount_rwf as number | null, status: String(row.status), visibility: String(row.visibility), sponsored: row.is_platform_sponsored as number, version: row.version};
}
async function source(context: LegacyGroupContext, intent: LegacyGroupIntent): Promise<Source> {
  if (context.mode === 'edit') return currentLegacyGroup(context);
  return intent.owner_user_id ? currentOwner(context, intent.owner_user_id) : null;
}
function verifyAttempt(context: LegacyGroupContext, attempt: PendingAttempt) {
  if (attempt.family !== families[context.mode] || attempt.resource_id !== resource(context) || attempt.permission !== permission[context.mode] || !UUID.test(attempt.request_key)) fail('The original group request could not be verified.');
}
function store(context: LegacyGroupContext): Storage {try {return context.storage ?? sessionStorage;} catch {return fail('Recovery storage is unavailable.');}}
function bindingKey(context: LegacyGroupContext) {return `collect.admin.legacy-group-${context.mode}.context.v1:${resource(context)}`;}
async function binding(context: LegacyGroupContext, key: string, attempt?: PendingAttempt): Promise<{kind: 'valid'; sourceSha256: string} | {kind: 'missing' | 'foreign' | 'mismatch'}> {
  let raw: string | null; try {raw = store(context).getItem(bindingKey(context));} catch {return fail('Recovery storage is unavailable.');}
  if (raw === null) return {kind: 'missing'}; if (raw.length > 1000) fail('The original group request could not be verified.');
  let value: unknown; try {value = JSON.parse(raw);} catch {return fail('The original group request could not be verified.');}
  const data = z.object({version: z.literal(1), request_key: id, authority_sha256: z.string().regex(HASH), intent_sha256: z.string().regex(HASH), source_sha256: z.string().regex(HASH), model: z.literal('transaction_journals')}).strict().parse(value);
  if (data.request_key !== key) fail('The original group request could not be verified.');
  if (data.authority_sha256 !== await pendingAuthority(context.identity)) return {kind: 'foreign'};
  if (attempt && data.intent_sha256 !== await sha256Text(JSON.stringify(attempt.intent))) return {kind: 'mismatch'};
  return {kind: 'valid', sourceSha256: data.source_sha256};
}
async function saveBinding(context: LegacyGroupContext, key: string, attempt: PendingAttempt, sourceValue: Source) {
  if ((await binding(context, key)).kind !== 'missing') fail('The original group request could not be verified.');
  const storage = store(context), name = bindingKey(context), raw = JSON.stringify({version: 1, request_key: key, authority_sha256: await pendingAuthority(context.identity), intent_sha256: await sha256Text(JSON.stringify(attempt.intent)), source_sha256: await sha256Text(JSON.stringify(sourceValue)), model: 'transaction_journals'}); check(context);
  try {storage.setItem(name, raw); if (storage.getItem(name) !== raw) fail('Recovery storage is unavailable.');} catch {fail('Recovery storage is unavailable.');} check(context);
}
async function clearBinding(context: LegacyGroupContext, key: string) {
  const state = await binding(context, key); if (state.kind === 'foreign') fail('The original group request could not be verified.'); if (state.kind === 'missing') return;
  const storage = store(context), name = bindingKey(context); check(context);
  try {storage.removeItem(name); if (storage.getItem(name) !== null) fail('Recovery storage is unavailable.');} catch {fail('Recovery storage is unavailable.');}
}
async function fence<T>(context: LegacyGroupContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: families[context.mode], resourceId: resource(context), isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restoreUnderFence(context: LegacyGroupContext, access: FenceAccess): Promise<LegacyGroupPending> {
  check(context); const shared = access.read(); if (shared.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, families[context.mode], resource(context), context.storage); if (attempt) verifyAttempt(context, attempt);
  const guarded = context.mode === 'edit' ? await readPending(context.identity, STATUS_FAMILY, resource(context), context.storage) : null;
  if (guarded) {
    if (attempt || shared.kind === 'owned' && shared.requestKey !== guarded.request_key) fail('Multiple group requests need recovery.');
    if (shared.kind === 'empty') access.reserve(guarded.request_key, shared.revision);
    return {kind:'guarded'};
  }
  const owner = attempt ? await binding(context, attempt.request_key, attempt) : {kind: 'missing' as const}; check(context);
  if (owner.kind === 'foreign') return {kind: 'foreign'};
  if (shared.kind === 'owned') {if (attempt && attempt.request_key !== shared.requestKey) fail('The original group request could not be verified.'); return {kind: 'owned', requestKey: shared.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, shared.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};}
  return {kind: 'ready', revision: shared.revision};
}
export async function restoreLegacyGroupAction(context: LegacyGroupContext): Promise<LegacyGroupPending> {check(context); return fence(context, access => restoreUnderFence(context, access));}
async function clear(context: LegacyGroupContext, access: FenceAccess, pending: Extract<LegacyGroupPending, {kind: 'owned'}>) {
  await clearBinding(context, pending.requestKey); if (pending.attempt) await clearPending(context.identity, families[context.mode], resource(context), pending.requestKey, context.storage);
  check(context); access.clear(pending.requestKey);
}
function receipt(context: LegacyGroupContext, value: unknown, attempt: PendingAttempt | null): LegacyGroupReceipt {
  const body = z.object({request_id: id, resource_type: z.literal('groups'), resource_id: id, version: count, status: z.literal('succeeded')}).strict().parse(value);
  if (context.mode === 'create' ? body.version !== 1 : body.resource_id !== context.groupId || body.version < 2 || attempt !== null && (typeof attempt.intent.expected_version !== 'number' || !Number.isSafeInteger(attempt.intent.expected_version) || body.version !== attempt.intent.expected_version + 1)) fail('The original group receipt could not be verified.');
  return {requestId: body.request_id, groupId: body.resource_id, version: body.version};
}
async function lookupUnderFence(context: LegacyGroupContext, pending: Extract<LegacyGroupPending, {kind: 'owned'}>): Promise<LegacyGroupLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) {
    let retryAvailable = false; if (pending.attempt && (await binding(context, pending.requestKey, pending.attempt)).kind === 'valid') {try {parseLegacyGroupIntent(pending.attempt.intent, context.mode); retryAvailable = true;} catch { /* Other retained intents remain check-only. */ }}
    return {status: 'not_found', retryAvailable};
  }
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original group receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail('The original group receipt could not be verified.');
  const saved = receipt(context, body.receipt, pending.attempt); if (saved.requestId !== body.request_id) fail('The original group receipt could not be verified.');
  if (context.mode === 'edit' && !pending.attempt && (await currentLegacyGroup(context, true)).version < saved.version) fail('The group version could not be verified.');
  return {status: 'succeeded', receipt: saved};
}
async function finish(context: LegacyGroupContext, access: FenceAccess, pending: Extract<LegacyGroupPending, {kind: 'owned'}>, value: unknown): Promise<LegacyGroupResult> {
  const direct = receipt(context, value, pending.attempt), found = await lookupUnderFence(context, pending);
  if (found.status !== 'succeeded' || JSON.stringify(found.receipt) !== JSON.stringify(direct)) fail('The original group receipt could not be verified.');
  await clear(context, access, pending); return {status: 'succeeded', receipt: direct};
}
export async function submitLegacyGroupAction(context: LegacyGroupContext, input: unknown, expectedSource: Source, observedRevision: string): Promise<LegacyGroupResult> {
  write(context); const intent = parseLegacyGroupIntent(input, context.mode);
  return fence(context, async access => {
    const existing = await restoreUnderFence(context, access); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const actual = await source(context, intent);
    if (JSON.stringify(actual) !== JSON.stringify(expectedSource) || context.mode === 'edit' && (actual as LegacyGroupSnapshot).version !== intent.expected_version) fail('The group or owner changed. Review it again.');
    write(context); const requestKey = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, families[context.mode], resource(context), requestKey, permission[context.mode], {...intent}, context.storage); verifyAttempt(context, attempt); await saveBinding(context, requestKey, attempt, actual);}
    catch (error) {if (context.isCurrent()) {try {const retained = await readPending(context.identity, families[context.mode], resource(context), context.storage); if (retained?.request_key === requestKey) await clearPending(context.identity, families[context.mode], resource(context), requestKey, context.storage); await clearBinding(context, requestKey); access.clear(requestKey);} catch { /* Preserve the fence if cleanup is uncertain. */ }} throw error;}
    const pending: Extract<LegacyGroupPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey};
    try {const response = await context.request(context.mode === 'create' ? 'operations/groups' : `operations/groups/${context.groupId}`, {method: context.mode === 'create' ? 'POST' : 'PATCH', body: {...intent}, idempotencyKey: requestKey}); check(context); return await finish(context, access, pending, response);}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLegacyGroupAction(context: LegacyGroupContext, pending: LegacyGroupPending): Promise<LegacyGroupLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return fence(context, async access => {const stored = await restoreUnderFence(context, access); if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey) fail('The original group request could not be verified.'); const result = await lookupUnderFence(context, stored); if (result.status === 'succeeded' && stored.attempt) await clear(context, access, stored); return result;});
}
export async function retryLegacyGroupAction(context: LegacyGroupContext, pending: LegacyGroupPending): Promise<LegacyGroupResult> {
  write(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original group intent is unavailable.');
  return fence(context, async access => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original group request could not be verified.');
    const previous = await lookupUnderFence(context, stored);
    if (previous.status === 'succeeded') {await clear(context, access, stored); return {status: 'succeeded', receipt: previous.receipt};}
    if (previous.status !== 'not_found' || !previous.retryAvailable) fail('The original group request remains unresolved.');
    const intent = parseLegacyGroupIntent(stored.attempt.intent, context.mode), owner = await binding(context, stored.requestKey, stored.attempt), actual = await source(context, intent);
    if (owner.kind !== 'valid' || await sha256Text(JSON.stringify(actual)) !== owner.sourceSha256 || context.mode === 'edit' && (actual as LegacyGroupSnapshot).version !== intent.expected_version) fail('The original group or owner changed. Check the request before continuing.');
    write(context);
    try {const response = await context.request(context.mode === 'create' ? 'operations/groups' : `operations/groups/${context.groupId}`, {method: context.mode === 'create' ? 'POST' : 'PATCH', body: {...intent}, idempotencyKey: stored.requestKey}); check(context); return await finish(context, access, stored, response);}
    catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}

export interface LegacyGroupStatusContext extends LegacyGroupContext {verifyFresh:()=>Promise<boolean>;}
export type LegacyGroupStatus = 'draft'|'active'|'suspended'|'archived';
export interface LegacyGroupActivation {owner:LegacyOwner; membershipVersion:number; receiver:{id:string;label:string;network:'mtn_momo'|'airtel_money';route:string;version:number};}
export interface LegacyGroupStatusSource {group:LegacyGroupSnapshot;activation:LegacyGroupActivation|null;}
export interface LegacyGroupStatusIntent {status:LegacyGroupStatus;expected_version:number;reason:string;expected_owner_id?:string;expected_owner_version?:number;expected_membership_version?:number;expected_receiver_id?:string;expected_receiver_version?:number;}
export type LegacyGroupStatusPending = {kind:'ready';revision:string}|{kind:'owned';requestKey:string;attempt:PendingAttempt|null}|{kind:'older'}|{kind:'foreign'};
export type LegacyGroupStatusLookup = {status:'succeeded';receipt:LegacyGroupReceipt;verifiedIntent:boolean}|{status:'not_found';retryAvailable:boolean}|{status:'pending'|'failed'};
export type LegacyGroupStatusResult = {status:'succeeded';receipt:LegacyGroupReceipt}|{status:'unknown';requestKey:string}|{status:'existing';pending:LegacyGroupStatusPending};
const STATUS_GUARDS=['expected_owner_id','expected_owner_version','expected_membership_version','expected_receiver_id','expected_receiver_version'];
function statusVersion(value:unknown):value is number{return typeof value==='number'&&Number.isSafeInteger(value)&&value>0&&value<Number.MAX_SAFE_INTEGER;}
export function parseLegacyGroupStatusIntent(value:unknown):LegacyGroupStatusIntent{
  if(!value||typeof value!=='object'||Array.isArray(value))fail('The original group status could not be verified.');const body=value as Record<string,unknown>,guarded=body.status==='active';
  if(!exact(body,['status','expected_version','reason',...(guarded?STATUS_GUARDS:[])])||!['draft','active','suspended','archived'].includes(String(body.status))||!statusVersion(body.expected_version)||!safeText(body.reason,8,1000)||
      guarded&&(typeof body.expected_owner_id!=='string'||!UUID.test(body.expected_owner_id)||!statusVersion(body.expected_owner_version)||!statusVersion(body.expected_membership_version)||typeof body.expected_receiver_id!=='string'||!UUID.test(body.expected_receiver_id)||!statusVersion(body.expected_receiver_version)))fail('The original group status could not be verified.');
  return body as unknown as LegacyGroupStatusIntent;
}
function sameStatusIntent(left:LegacyGroupStatusIntent,right:LegacyGroupStatusIntent){return JSON.stringify(Object.entries(left).sort(([a],[b])=>a.localeCompare(b)))===JSON.stringify(Object.entries(right).sort(([a],[b])=>a.localeCompare(b)));}
function statusCheck(context:LegacyGroupStatusContext){check(context);if(context.mode!=='edit'||!context.groupId)fail('Group status changes are unavailable.');}
function statusWrite(context:LegacyGroupStatusContext){statusCheck(context);write(context);}
class StatusStorage implements Storage {
  constructor(private readonly context:LegacyGroupStatusContext){}
  get length(){return 0;}clear():void{fail('Recovery operation unavailable.');}key():string|null{return null;}
  getItem(key:string){statusCheck(this.context);return store(this.context).getItem(key);}
  setItem(key:string,value:string){statusCheck(this.context);store(this.context).setItem(key,value);}
  removeItem(key:string){statusCheck(this.context);store(this.context).removeItem(key);}
}
function statusStorage(context:LegacyGroupStatusContext){return new StatusStorage(context);}
function record(value:unknown):Record<string,unknown>{if(!value||typeof value!=='object'||Array.isArray(value))fail('The group status evidence could not be verified.');return value as Record<string,unknown>;}
async function statusRelated(context:LegacyGroupStatusContext,group:LegacyGroupSnapshot,relation:'memberships'|'payees'){
  let offset=0,total:number|null=null;const rows:Record<string,unknown>[]=[],seen=new Set<string>();
  do{
    const query=new URLSearchParams({relation,limit:'100',offset:String(offset)}),body=await context.request(`operations/groups/${group.id}?${query}`);statusCheck(context);
    const resource=record(body.resource),related=record(body.related),pages=record(body.related_pages),page=record(pages[relation]);
    if(body.resource_type!=='groups'||body.current_actor_id!==context.actorId||body.can_manage!==true||resource.id!==group.id||resource.version!==group.version||resource.status!==group.status||resource.title!==group.title||
       !exact(related,[relation])||!exact(pages,[relation])||!Array.isArray(related[relation])||!exact(page,['total','limit','offset','next_offset'])||typeof page.total!=='number'||!Number.isSafeInteger(page.total)||page.total<0||page.total>1000||
       page.limit!==100||page.offset!==offset||related[relation].length!==Math.max(0,Math.min(100,page.total-offset))||page.next_offset!==(offset+related[relation].length<page.total?offset+related[relation].length:null)||body.related_truncated!==(page.total>related[relation].length)||total!==null&&page.total!==total)fail('The group status evidence could not be verified.');
    total=page.total;
    for(const item of related[relation]){const row=record(item),key=relation==='memberships'?row.user_id:row.id;
      if(typeof key!=='string'||!UUID.test(key)||seen.has(key)||row.group_id!==group.id||!statusVersion(row.version))fail('The group status evidence could not be verified.');
      seen.add(key);rows.push(row);}
    offset+=related[relation].length;
  }while(total!==null&&offset<total);
  if(total===null||seen.size!==total)fail('The group status evidence could not be verified.');return rows;
}
export async function currentLegacyGroupStatusSource(context:LegacyGroupStatusContext,target:LegacyGroupStatus):Promise<LegacyGroupStatusSource>{
  statusCheck(context);const group=await currentLegacyGroup(context);
  if(!['draft','active','suspended','archived'].includes(target)||group.status===target)fail('Choose a different group status.');
  if(target!=='active')return {group,activation:null};
  if(!['users.read','receivers.read'].every(value=>context.permissions.includes(value)&&context.identity.permissions.includes(value)))fail('Owner and receiver read access is required to activate this group.');
  const memberships=await statusRelated(context,group,'memberships'),payees=await statusRelated(context,group,'payees');
  const owners=memberships.filter(row=>row.role==='owner'&&row.status==='active'),receivers=payees.filter(row=>row.status==='active');
  if(owners.length!==1||receivers.length!==1)fail('An active owner and receiver are required.');
  const member=owners[0],selected=receivers[0],owner=await currentOwner(context,String(member.user_id));
  const body=await context.request(`operations/payees/${String(selected.id)}`);statusCheck(context);const receiver=record(body.resource);
  if(body.resource_type!=='payees'||body.current_actor_id!==context.actorId||body.can_manage!==true||receiver.id!==selected.id||receiver.group_id!==group.id||receiver.status!=='active'||receiver.version!==selected.version||
     !safeText(receiver.label,2,120)||!['mtn_momo','airtel_money'].includes(String(receiver.network))||typeof receiver.momo_number_or_code!=='string'||!/^\d{4,12}$/.test(receiver.momo_number_or_code)||
     selected.label!==receiver.label||selected.network!==receiver.network||selected.momo_number_or_code!==receiver.momo_number_or_code||receiver.currency!=='RWF'||receiver.rail!=='rwanda_momo'||!statusVersion(member.version))fail('The owner or receiver could not be verified.');
  const latest=await currentLegacyGroup(context);if(JSON.stringify(latest)!==JSON.stringify(group))fail('The group changed. Review it again.');
  return {group,activation:{owner,membershipVersion:member.version,receiver:{id:String(receiver.id),label:receiver.label,network:receiver.network as 'mtn_momo'|'airtel_money',route:receiver.momo_number_or_code,version:receiver.version as number}}};
}
export function buildLegacyGroupStatusIntent(source:LegacyGroupStatusSource,status:LegacyGroupStatus,reason:string):LegacyGroupStatusIntent{
  const activation=source.activation;
  if(status==='active'&&!activation||status!=='active'&&activation||source.group.status===status||source.group.status==='archived')fail('The group status could not be verified.');
  return parseLegacyGroupStatusIntent({status,expected_version:source.group.version,reason:reason.trim(),...(activation?{expected_owner_id:activation.owner.id,expected_owner_version:activation.owner.version,expected_membership_version:activation.membershipVersion,expected_receiver_id:activation.receiver.id,expected_receiver_version:activation.receiver.version}:{})});
}
function statusBindingKey(context:LegacyGroupStatusContext){return `collect.admin.legacy-group-status.context.v2:${context.groupId}`;}
async function statusBinding(context:LegacyGroupStatusContext,key:string,attempt?:PendingAttempt):Promise<{kind:'valid';sourceSha256:string}|{kind:'missing'|'foreign'|'mismatch'}>{
  let raw:string|null;try{raw=statusStorage(context).getItem(statusBindingKey(context));}catch{return fail('Recovery storage is unavailable.');}if(raw===null)return {kind:'missing'};if(raw.length>1000)fail('The original group status could not be verified.');
  let value:unknown;try{value=JSON.parse(raw);}catch{return fail('The original group status could not be verified.');}
  const data=z.object({version:z.literal(1),request_key:id,authority_sha256:z.string().regex(HASH),intent_sha256:z.string().regex(HASH),source_sha256:z.string().regex(HASH),model:z.literal('transaction_journals')}).strict().parse(value);
  if(data.request_key!==key)fail('The original group status could not be verified.');if(data.authority_sha256!==await pendingAuthority(context.identity))return {kind:'foreign'};
  if(attempt&&data.intent_sha256!==await sha256Text(JSON.stringify(attempt.intent)))return {kind:'mismatch'};statusCheck(context);return {kind:'valid',sourceSha256:data.source_sha256};
}
async function saveStatusBinding(context:LegacyGroupStatusContext,attempt:PendingAttempt,source:LegacyGroupStatusSource){
  if((await statusBinding(context,attempt.request_key)).kind!=='missing')fail('The original group status could not be verified.');const storage=statusStorage(context),name=statusBindingKey(context);
  const raw=JSON.stringify({version:1,request_key:attempt.request_key,authority_sha256:await pendingAuthority(context.identity),intent_sha256:await sha256Text(JSON.stringify(attempt.intent)),source_sha256:await sha256Text(JSON.stringify(source)),model:'transaction_journals'});statusCheck(context);
  try{storage.setItem(name,raw);if(storage.getItem(name)!==raw)fail('Recovery storage is unavailable.');}catch{fail('Recovery storage is unavailable.');}statusCheck(context);
}
async function clearStatus(context:LegacyGroupStatusContext,access:FenceAccess,saved:Extract<LegacyGroupStatusPending,{kind:'owned'}>){
  if(!saved.attempt||(await statusBinding(context,saved.requestKey,saved.attempt)).kind!=='valid')fail('The original group status could not be verified.');const storage=statusStorage(context),name=statusBindingKey(context);statusCheck(context);
  try{storage.removeItem(name);if(storage.getItem(name)!==null)fail('Recovery storage is unavailable.');}catch{fail('Recovery storage is unavailable.');}
  await clearPending(context.identity,STATUS_FAMILY,context.groupId!,saved.requestKey,storage);statusCheck(context);access.clear(saved.requestKey);
}
async function restoreStatus(context:LegacyGroupStatusContext,access:FenceAccess):Promise<LegacyGroupStatusPending>{
  statusCheck(context);const shared=access.read();if(shared.kind==='foreign')return {kind:'foreign'};
  const old=await readPending(context.identity,families.edit,context.groupId!,statusStorage(context)),saved=await readPending(context.identity,STATUS_FAMILY,context.groupId!,statusStorage(context));statusCheck(context);
  if(old&&saved)fail('Multiple group requests need recovery.');if(old)return {kind:'older'};
  if(saved&&(saved.family!==STATUS_FAMILY||saved.permission!=='collections.manage'||saved.resource_id!==context.groupId||!UUID.test(saved.request_key)))fail('The original group status could not be verified.');
  if(shared.kind==='owned'){if(saved&&saved.request_key!==shared.requestKey)fail('The original group status could not be verified.');return {kind:'owned',requestKey:shared.requestKey,attempt:saved};}
  if(saved){access.reserve(saved.request_key,shared.revision);return {kind:'owned',requestKey:saved.request_key,attempt:saved};}
  if(statusStorage(context).getItem(statusBindingKey(context))!==null)fail('The original group status could not be verified.');return {kind:'ready',revision:shared.revision};
}
export async function restoreLegacyGroupStatus(context:LegacyGroupStatusContext){statusCheck(context);return fence(context,access=>restoreStatus(context,access));}
async function lookupStatus(context:LegacyGroupStatusContext,saved:Extract<LegacyGroupStatusPending,{kind:'owned'}>):Promise<LegacyGroupStatusLookup>{
  const body=await context.request(`operations/requests/${saved.requestKey}`);statusCheck(context);
  if(body.status==='not_found'&&exact(body,['status'])){let retryAvailable=false;if(saved.attempt&&(await statusBinding(context,saved.requestKey,saved.attempt)).kind==='valid'){try{parseLegacyGroupStatusIntent(saved.attempt.intent);retryAvailable=true;}catch{/* Check-only. */}}return {status:'not_found',retryAvailable};}
  if(!exact(body,['status','request_id','receipt'])||typeof body.request_id!=='string'||!UUID.test(body.request_id))fail('The original group status could not be verified.');
  if((body.status==='pending'||body.status==='failed')&&body.receipt===null)return {status:body.status};if(body.status!=='succeeded')fail('The original group status could not be verified.');
  const result=receipt(context,body.receipt,saved.attempt);if(result.requestId!==body.request_id)fail('The original group status could not be verified.');
  if(!saved.attempt||(await statusBinding(context,saved.requestKey,saved.attempt)).kind!=='valid')return {status:'succeeded',receipt:result,verifiedIntent:false};
  const intent=parseLegacyGroupStatusIntent(saved.attempt.intent),current=await currentLegacyGroup(context,true);
  if(current.version!==result.version||current.status!==intent.status)fail('The recorded group status could not be verified.');return {status:'succeeded',receipt:result,verifiedIntent:true};
}
export async function lookupLegacyGroupStatus(context:LegacyGroupStatusContext,pending:LegacyGroupStatusPending):Promise<LegacyGroupStatusLookup>{
  statusCheck(context);if(pending.kind!=='owned')fail('The original account must check this request.');return fence(context,async access=>{
    const saved=await restoreStatus(context,access);if(saved.kind!=='owned'||saved.requestKey!==pending.requestKey)fail('The original group status could not be verified.');
    const result=await lookupStatus(context,saved);if(result.status==='succeeded'&&result.verifiedIntent)await clearStatus(context,access,saved);return result;});
}
async function dispatchStatus(context:LegacyGroupStatusContext,access:FenceAccess,saved:Extract<LegacyGroupStatusPending,{kind:'owned'}>):Promise<LegacyGroupStatusResult>{
  if(!saved.attempt)fail('The original group status intent is unavailable.');const intent=parseLegacyGroupStatusIntent(saved.attempt.intent);
  try{statusWrite(context);const direct=receipt(context,await context.request(`operations/groups/${context.groupId}`,{method:'PATCH',body:{...intent},idempotencyKey:saved.requestKey}),saved.attempt);
    const found=await lookupStatus(context,saved);if(found.status!=='succeeded'||!found.verifiedIntent||JSON.stringify(found.receipt)!==JSON.stringify(direct))fail('The original group status could not be verified.');
    await clearStatus(context,access,saved);return {status:'succeeded',receipt:direct};}catch{return {status:'unknown',requestKey:saved.requestKey};}
}
export async function submitLegacyGroupStatus(context:LegacyGroupStatusContext,intent:LegacyGroupStatusIntent,expected:LegacyGroupStatusSource,revision:string):Promise<LegacyGroupStatusResult>{
  statusWrite(context);const body=parseLegacyGroupStatusIntent(intent);if(!sameStatusIntent(buildLegacyGroupStatusIntent(expected,body.status,body.reason),body))fail('Review the exact group status.');
  return fence(context,async access=>{const previous=await restoreStatus(context,access);if(previous.kind!=='ready')return {status:'existing',pending:previous};
    const latest=await currentLegacyGroupStatusSource(context,body.status);if(JSON.stringify(latest)!==JSON.stringify(expected))fail('The group, owner or receiver changed. Review again.');
    if(!await context.verifyFresh())fail('Complete current account verification before changing group status.');statusWrite(context);
    const key=(context.createKey??(()=>crypto.randomUUID()))();if(!UUID.test(key))fail('A secure request reference is unavailable.');access.reserve(key,revision);let attempt:PendingAttempt;
    try{attempt=await retainPending(context.identity,STATUS_FAMILY,context.groupId!,key,'collections.manage',{...body},statusStorage(context));await saveStatusBinding(context,attempt,latest);}catch{return {status:'unknown',requestKey:key};}
    if(!context.isCurrent()||context.isEnabled&&!context.isEnabled())return {status:'unknown',requestKey:key};return dispatchStatus(context,access,{kind:'owned',requestKey:key,attempt});});
}
export async function retryLegacyGroupStatus(context:LegacyGroupStatusContext,pending:LegacyGroupStatusPending):Promise<LegacyGroupStatusResult>{
  statusWrite(context);if(pending.kind!=='owned'||!pending.attempt)fail('The original group status intent is unavailable.');return fence(context,async access=>{
    const saved=await restoreStatus(context,access);if(saved.kind!=='owned'||!saved.attempt||saved.requestKey!==pending.requestKey||JSON.stringify(saved.attempt.intent)!==JSON.stringify(pending.attempt?.intent))fail('The original group status could not be verified.');
    const previous=await lookupStatus(context,saved);if(previous.status==='succeeded'&&previous.verifiedIntent){await clearStatus(context,access,saved);return {status:'succeeded',receipt:previous.receipt};}
    if(previous.status!=='not_found'||!previous.retryAvailable)fail('The original group status remains unresolved.');
    const intent=parseLegacyGroupStatusIntent(saved.attempt.intent),bound=await statusBinding(context,saved.requestKey,saved.attempt),latest=await currentLegacyGroupStatusSource(context,intent.status);
    if(bound.kind!=='valid'||await sha256Text(JSON.stringify(latest))!==bound.sourceSha256||!sameStatusIntent(buildLegacyGroupStatusIntent(latest,intent.status,intent.reason),intent))fail('The original group, owner or receiver changed.');
    if(!await context.verifyFresh())fail('Complete current account verification before retrying group status.');statusWrite(context);return dispatchStatus(context,access,saved);});
}
