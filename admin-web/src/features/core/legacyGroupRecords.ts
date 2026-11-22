/* eslint-disable no-control-regex -- Validate recorded legacy group text. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import { withPendingFence, type FenceAccess, type FenceLock } from '../operations/pendingFence';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
export const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const id = z.string().regex(UUID), count = z.number().int().min(1).max(Number.MAX_SAFE_INTEGER);
export const groupBindingSchema = z.object({ version: z.literal(1), request_key: id, authority_sha256: z.string().regex(HASH), intent_sha256: z.string().regex(HASH), source_sha256: z.string().regex(HASH), model: z.literal('transaction_journals') }).strict();
export interface LegacyGroupContext {
  mode: 'create' | 'edit';
  groupId?: string;
  request: AdminRequest;
  identity: PendingIdentity;
  actorId: string;
  permissions: readonly string[];
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger';
  enabled: boolean;
  isCurrent: () => boolean;
  isEnabled?: () => boolean;
  storage?: Storage;
  sharedStorage?: Storage;
  lock?: FenceLock;
  createKey?: () => string;
}
export interface LegacyOwner {
  id: string;
  publicId: string;
  displayName: string | null;
  memberType: 'app' | 'direct';
  momoNumber: string | null;
  version: number;
}
export interface LegacyGroupSnapshot {
  id: string;
  slug: string;
  title: string;
  type: string;
  description: string;
  category: string | null;
  purpose: string | null;
  cadence: string | null;
  amount: number | null;
  status: string;
  visibility: string;
  sponsored: number;
  version: number;
}
export interface LegacyGroupIntent {
  title: string;
  collection_type: 'ikimina' | 'sport' | 'church' | 'wedding' | 'other';
  description: string;
  category_subtype: string | null;
  purpose_label: string | null;
  recurring_cadence: 'weekly' | 'monthly' | 'quarterly' | 'annually' | null;
  suggested_amount_rwf: number | null;
  reason: string;
  slug?: string;
  visibility?: 'private';
  is_platform_sponsored?: false;
  status?: 'draft' | 'active';
  owner_user_id?: string;
  receiver?: {
    label: string;
    network: 'mtn_momo' | 'airtel_money';
    momo_number_or_code: string;
  };
  expected_version?: number;
}
export interface LegacyGroupReceipt {
  requestId: string;
  groupId: string;
  version: number;
}
export const groupRequestFamilies = { create: 'operating-creategroup', edit: 'operating-updategroup' } as const;
export const LEGACY_GROUP_STATUS_FAMILY = 'legacy-group-status-v2';
export const groupRequestPermissions = { create: 'collections.create', edit: 'collections.manage' } as const;
export function fail(message: string): never { throw new Error(message); }
export function exact(value: Record<string, unknown>, keys: string[]) { return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key)); }
export function groupRequestResource(context: LegacyGroupContext) { return context.mode === 'create' ? 'new' : context.groupId ?? ''; }
export function assertLegacyGroupAccess(context: LegacyGroupContext) {
  const needed = [groupRequestPermissions[context.mode], 'overview.read', ...(context.mode === 'edit' ? ['collections.read'] : context.identity.role === 'staff' ? [] : ['collections.manage'])], expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'transaction_journals' || !UUID.test(context.actorId) || context.identity.id !== context.actorId ||
    context.mode === 'edit' && (context.identity.role === 'staff' || !context.groupId || !UUID.test(context.groupId)) ||
    !needed.every(value => context.permissions.includes(value) && context.identity.permissions.includes(value)) || !Number.isFinite(expires) || expires <= Date.now())
    fail('Group changes are unavailable to your current account.');
}
export function assertLegacyGroupWrite(context: LegacyGroupContext) { assertLegacyGroupAccess(context); if (!context.enabled || context.isEnabled && !context.isEnabled())
  fail('Group changes are not enabled for this workspace.'); }
function hasOwnerAccess(context: LegacyGroupContext) { return ['users.read'].every(value => context.permissions.includes(value) && context.identity.permissions.includes(value)); }
export function safeText(value: unknown, minimum: number, maximum: number): value is string { return typeof value === 'string' && value === value.trim() && value.length >= minimum && value.length <= maximum && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value); }
export const nullableText = (value: unknown) => value === null || safeText(value, 0, 120);
function ownerFrom(value: unknown): LegacyOwner {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    fail('The group owner could not be verified.');
  const row = value as Record<string, unknown>;
  if (typeof row.id !== 'string' || !UUID.test(row.id) || typeof row.public_id !== 'string' || !/^\d{6}$/.test(row.public_id) ||
    !(row.display_name === null || safeText(row.display_name, 1, 120)) || !['app', 'direct'].includes(String(row.member_type)) ||
    !(row.momo_number === null || row.momo_number === '' || typeof row.momo_number === 'string' && /^07[2389]\d{7}$/.test(row.momo_number)) ||
    typeof row.version !== 'number' || !Number.isSafeInteger(row.version) || row.version < 1)
    fail('The group owner could not be verified.');
  return { id: row.id, publicId: row.public_id, displayName: row.display_name as string | null, memberType: row.member_type as LegacyOwner['memberType'], momoNumber: row.momo_number ? String(row.momo_number) : null, version: row.version };
}
export async function searchLegacyOwners(context: LegacyGroupContext, search: string): Promise<LegacyOwner[]> {
  assertLegacyGroupWrite(context);
  if (context.mode !== 'create' || !hasOwnerAccess(context) || search.length > 200 || /[\x00-\x1f\x7f]/.test(search))
    fail('Owner search is unavailable.');
  const query = new URLSearchParams({ kind: 'users', search: search.trim(), limit: '25' }), body = await context.request(`operations/lookups?${query}`);
  assertLegacyGroupAccess(context);
  if (!exact(body, ['rows']) || !Array.isArray(body.rows) || body.rows.length > 25)
    fail('Owner search could not be verified.');
  const rows = body.rows.map(ownerFrom);
  if (new Set(rows.map(row => row.id)).size !== rows.length)
    fail('Owner search could not be verified.');
  return rows;
}
async function currentOwner(context: LegacyGroupContext, ownerId: string): Promise<LegacyOwner> {
  if (!hasOwnerAccess(context))
    fail('Owner search is unavailable.');
  const body = await context.request(`operations/users/${ownerId}`);
  assertLegacyGroupAccess(context);
  if (body.contract_version !== undefined || body.model !== undefined || body.resource_type !== 'users' || body.current_actor_id !== context.actorId || !body.resource || typeof body.resource !== 'object' || Array.isArray(body.resource))
    fail('The group owner could not be verified.');
  const row = body.resource as Record<string, unknown>, owner = ownerFrom(row);
  if (owner.id !== ownerId || row.collect_user_id !== ownerId || row.status !== 'active' || row.display_name_recorded !== (owner.displayName !== null))
    fail('The group owner could not be verified.');
  return owner;
}
export async function readLegacyOwner(context: LegacyGroupContext, ownerId: string): Promise<LegacyOwner> { assertLegacyGroupAccess(context); return currentOwner(context, ownerId); }
export async function currentLegacyGroup(context: LegacyGroupContext, recover = false): Promise<LegacyGroupSnapshot> {
  assertLegacyGroupAccess(context);
  if (context.mode !== 'edit' || !context.groupId)
    fail('The group could not be verified.');
  const body = await context.request(`operations/groups/${context.groupId}`);
  assertLegacyGroupAccess(context);
  if (body.contract_version !== undefined || body.model !== undefined || body.resource_type !== 'groups' || body.current_actor_id !== context.actorId || body.can_manage !== true || !body.resource || typeof body.resource !== 'object' || Array.isArray(body.resource))
    fail('The group could not be verified.');
  const row = body.resource as Record<string, unknown>;
  if (row.id !== context.groupId || typeof row.slug !== 'string' || !safeText(row.title, 3, 160) || !['ikimina', 'sport', 'church', 'wedding', 'other'].includes(String(row.collection_type)) ||
    !safeText(row.description, 0, 1000) || !nullableText(row.category_subtype) || !nullableText(row.purpose_label) ||
    !(row.recurring_cadence === null || ['weekly', 'monthly', 'quarterly', 'annually'].includes(String(row.recurring_cadence))) ||
    !(row.suggested_amount_rwf === null || typeof row.suggested_amount_rwf === 'number' && Number.isSafeInteger(row.suggested_amount_rwf) && row.suggested_amount_rwf > 0) ||
    !['draft', 'active', 'suspended', 'archived'].includes(String(row.status)) || !recover && row.status === 'archived' || !['private', 'public_approved'].includes(String(row.visibility)) ||
    row.is_platform_sponsored !== 0 && row.is_platform_sponsored !== 1 || row.country_code !== 'RW' || row.currency !== 'RWF' || typeof row.version !== 'number' || !Number.isSafeInteger(row.version) || row.version < 1 || row.version >= Number.MAX_SAFE_INTEGER)
    fail('The group could not be verified.');
  return { id: context.groupId, slug: row.slug, title: row.title, type: String(row.collection_type), description: row.description, category: row.category_subtype as string | null, purpose: row.purpose_label as string | null, cadence: row.recurring_cadence as string | null, amount: row.suggested_amount_rwf as number | null, status: String(row.status), visibility: String(row.visibility), sponsored: row.is_platform_sponsored as number, version: row.version };
}
export function legacyGroupStorage(context: LegacyGroupContext): Storage { try {
  return context.storage ?? sessionStorage;
}
catch {
  return fail('Recovery storage is unavailable.');
} }
export async function withLegacyGroupFence<T>(context: LegacyGroupContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({ identity: context.identity, family: groupRequestFamilies[context.mode], resourceId: groupRequestResource(context), isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock }, work);
}
export function parseLegacyGroupReceipt(context: LegacyGroupContext, value: unknown, attempt: PendingAttempt | null): LegacyGroupReceipt {
  const body = z.object({ request_id: id, resource_type: z.literal('groups'), resource_id: id, version: count, status: z.literal('succeeded') }).strict().parse(value);
  if (context.mode === 'create' ? body.version !== 1 : body.resource_id !== context.groupId || body.version < 2 || attempt !== null && (typeof attempt.intent.expected_version !== 'number' || !Number.isSafeInteger(attempt.intent.expected_version) || body.version !== attempt.intent.expected_version + 1))
    fail('The original group receipt could not be verified.');
  return { requestId: body.request_id, groupId: body.resource_id, version: body.version };
}
