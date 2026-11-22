import type { FenceAccess } from '../operations/pendingFence';
import { clearPending, pendingAuthority, readPending, retainPending, sha256Text, type PendingAttempt } from './pendingAttempt';
import { assertLegacyGroupAccess, currentLegacyGroup, exact, fail, groupRequestFamilies, withLegacyGroupFence, groupBindingSchema, readLegacyOwner, parseLegacyGroupReceipt, safeText, LEGACY_GROUP_STATUS_FAMILY, legacyGroupStorage, UUID, assertLegacyGroupWrite, type LegacyGroupContext, type LegacyGroupReceipt, type LegacyGroupSnapshot, type LegacyOwner, } from './legacyGroupRecords';
export interface LegacyGroupStatusContext extends LegacyGroupContext {
  verifyFresh: () => Promise<boolean>;
}
export type LegacyGroupStatus = 'draft' | 'active' | 'suspended' | 'archived';
export interface LegacyGroupActivation {
  owner: LegacyOwner;
  membershipVersion: number;
  receiver: {
    id: string;
    label: string;
    network: 'mtn_momo' | 'airtel_money';
    route: string;
    version: number;
  };
}
export interface LegacyGroupStatusSource {
  group: LegacyGroupSnapshot;
  activation: LegacyGroupActivation | null;
}
export interface LegacyGroupStatusIntent {
  status: LegacyGroupStatus;
  expected_version: number;
  reason: string;
  expected_owner_id?: string;
  expected_owner_version?: number;
  expected_membership_version?: number;
  expected_receiver_id?: string;
  expected_receiver_version?: number;
}
export type LegacyGroupStatusPending = {
  kind: 'ready';
  revision: string;
} | {
  kind: 'owned';
  requestKey: string;
  attempt: PendingAttempt | null;
} | {
  kind: 'older';
} | {
  kind: 'foreign';
};
export type LegacyGroupStatusLookup = {
  status: 'succeeded';
  receipt: LegacyGroupReceipt;
  verifiedIntent: boolean;
} | {
  status: 'not_found';
  retryAvailable: boolean;
} | {
  status: 'pending' | 'failed';
};
export type LegacyGroupStatusResult = {
  status: 'succeeded';
  receipt: LegacyGroupReceipt;
} | {
  status: 'unknown';
  requestKey: string;
} | {
  status: 'existing';
  pending: LegacyGroupStatusPending;
};
const STATUS_GUARDS = ['expected_owner_id', 'expected_owner_version', 'expected_membership_version', 'expected_receiver_id', 'expected_receiver_version'];
function statusVersion(value: unknown): value is number { return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 && value < Number.MAX_SAFE_INTEGER; }
export function parseLegacyGroupStatusIntent(value: unknown): LegacyGroupStatusIntent {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    fail('The original group status could not be verified.');
  const body = value as Record<string, unknown>, guarded = body.status === 'active';
  if (!exact(body, ['status', 'expected_version', 'reason', ...(guarded ? STATUS_GUARDS : [])]) || !['draft', 'active', 'suspended', 'archived'].includes(String(body.status)) || !statusVersion(body.expected_version) || !safeText(body.reason, 8, 1000) ||
    guarded && (typeof body.expected_owner_id !== 'string' || !UUID.test(body.expected_owner_id) || !statusVersion(body.expected_owner_version) || !statusVersion(body.expected_membership_version) || typeof body.expected_receiver_id !== 'string' || !UUID.test(body.expected_receiver_id) || !statusVersion(body.expected_receiver_version)))
    fail('The original group status could not be verified.');
  return body as unknown as LegacyGroupStatusIntent;
}
export function sameLegacyGroupStatusIntent(left: LegacyGroupStatusIntent, right: LegacyGroupStatusIntent) { return JSON.stringify(Object.entries(left).sort(([a], [b]) => a.localeCompare(b))) === JSON.stringify(Object.entries(right).sort(([a], [b]) => a.localeCompare(b))); }
function statusCheck(context: LegacyGroupStatusContext) { assertLegacyGroupAccess(context); if (context.mode !== 'edit' || !context.groupId)
  fail('Group status changes are unavailable.'); }
function statusWrite(context: LegacyGroupStatusContext) { statusCheck(context); assertLegacyGroupWrite(context); }
class StatusStorage implements Storage {
  constructor(private readonly context: LegacyGroupStatusContext) { }
  get length() { return 0; }
  clear(): void { fail('Recovery operation unavailable.'); }
  key(): string | null { return null; }
  getItem(key: string) { statusCheck(this.context); return legacyGroupStorage(this.context).getItem(key); }
  setItem(key: string, value: string) { statusCheck(this.context); legacyGroupStorage(this.context).setItem(key, value); }
  removeItem(key: string) { statusCheck(this.context); legacyGroupStorage(this.context).removeItem(key); }
}
function statusStorage(context: LegacyGroupStatusContext) { return new StatusStorage(context); }
function record(value: unknown): Record<string, unknown> { if (!value || typeof value !== 'object' || Array.isArray(value))
  fail('The group status evidence could not be verified.'); return value as Record<string, unknown>; }
async function statusRelated(context: LegacyGroupStatusContext, group: LegacyGroupSnapshot, relation: 'memberships' | 'payees') {
  let offset = 0, total: number | null = null;
  const rows: Record<string, unknown>[] = [], seen = new Set<string>();
  do {
    const query = new URLSearchParams({ relation, limit: '100', offset: String(offset) }), body = await context.request(`operations/groups/${group.id}?${query}`);
    statusCheck(context);
    const resource = record(body.resource), related = record(body.related), pages = record(body.related_pages), page = record(pages[relation]);
    if (body.resource_type !== 'groups' || body.current_actor_id !== context.actorId || body.can_manage !== true || resource.id !== group.id || resource.version !== group.version || resource.status !== group.status || resource.title !== group.title ||
      !exact(related, [relation]) || !exact(pages, [relation]) || !Array.isArray(related[relation]) || !exact(page, ['total', 'limit', 'offset', 'next_offset']) || typeof page.total !== 'number' || !Number.isSafeInteger(page.total) || page.total < 0 || page.total > 1000 ||
      page.limit !== 100 || page.offset !== offset || related[relation].length !== Math.max(0, Math.min(100, page.total - offset)) || page.next_offset !== (offset + related[relation].length < page.total ? offset + related[relation].length : null) || body.related_truncated !== (page.total > related[relation].length) || total !== null && page.total !== total)
      fail('The group status evidence could not be verified.');
    total = page.total;
    for (const item of related[relation]) {
      const row = record(item), key = relation === 'memberships' ? row.user_id : row.id;
      if (typeof key !== 'string' || !UUID.test(key) || seen.has(key) || row.group_id !== group.id || !statusVersion(row.version))
        fail('The group status evidence could not be verified.');
      seen.add(key);
      rows.push(row);
    }
    offset += related[relation].length;
  } while (total !== null && offset < total);
  if (total === null || seen.size !== total)
    fail('The group status evidence could not be verified.');
  return rows;
}
export async function currentLegacyGroupStatusSource(context: LegacyGroupStatusContext, target: LegacyGroupStatus): Promise<LegacyGroupStatusSource> {
  statusCheck(context);
  const group = await currentLegacyGroup(context);
  if (!['draft', 'active', 'suspended', 'archived'].includes(target) || group.status === target)
    fail('Choose a different group status.');
  if (target !== 'active')
    return { group, activation: null };
  if (!['users.read', 'receivers.read'].every(value => context.permissions.includes(value) && context.identity.permissions.includes(value)))
    fail('Owner and receiver read access is required to activate this group.');
  const memberships = await statusRelated(context, group, 'memberships'), payees = await statusRelated(context, group, 'payees');
  const owners = memberships.filter(row => row.role === 'owner' && row.status === 'active'), receivers = payees.filter(row => row.status === 'active');
  if (owners.length !== 1 || receivers.length !== 1)
    fail('An active owner and receiver are required.');
  const member = owners[0], selected = receivers[0], owner = await readLegacyOwner(context, String(member.user_id));
  const body = await context.request(`operations/payees/${String(selected.id)}`);
  statusCheck(context);
  const receiver = record(body.resource);
  if (body.resource_type !== 'payees' || body.current_actor_id !== context.actorId || body.can_manage !== true || receiver.id !== selected.id || receiver.group_id !== group.id || receiver.status !== 'active' || receiver.version !== selected.version ||
    !safeText(receiver.label, 2, 120) || !['mtn_momo', 'airtel_money'].includes(String(receiver.network)) || typeof receiver.momo_number_or_code !== 'string' || !/^\d{4,12}$/.test(receiver.momo_number_or_code) ||
    selected.label !== receiver.label || selected.network !== receiver.network || selected.momo_number_or_code !== receiver.momo_number_or_code || receiver.currency !== 'RWF' || receiver.rail !== 'rwanda_momo' || !statusVersion(member.version))
    fail('The owner or receiver could not be verified.');
  const latest = await currentLegacyGroup(context);
  if (JSON.stringify(latest) !== JSON.stringify(group))
    fail('The group changed. Review it again.');
  return { group, activation: { owner, membershipVersion: member.version, receiver: { id: String(receiver.id), label: receiver.label, network: receiver.network as 'mtn_momo' | 'airtel_money', route: receiver.momo_number_or_code, version: receiver.version as number } } };
}
export function buildLegacyGroupStatusIntent(source: LegacyGroupStatusSource, status: LegacyGroupStatus, reason: string): LegacyGroupStatusIntent {
  const activation = source.activation;
  if (status === 'active' && !activation || status !== 'active' && activation || source.group.status === status || source.group.status === 'archived')
    fail('The group status could not be verified.');
  return parseLegacyGroupStatusIntent({ status, expected_version: source.group.version, reason: reason.trim(), ...(activation ? { expected_owner_id: activation.owner.id, expected_owner_version: activation.owner.version, expected_membership_version: activation.membershipVersion, expected_receiver_id: activation.receiver.id, expected_receiver_version: activation.receiver.version } : {}) });
}
function statusBindingKey(context: LegacyGroupStatusContext) { return `collect.admin.legacy-group-status.context.v2:${context.groupId}`; }
async function statusBinding(context: LegacyGroupStatusContext, key: string, attempt?: PendingAttempt): Promise<{
  kind: 'valid';
  sourceSha256: string;
} | {
  kind: 'missing' | 'foreign' | 'mismatch';
}> {
  let raw: string | null;
  try {
    raw = statusStorage(context).getItem(statusBindingKey(context));
  }
  catch {
    return fail('Recovery storage is unavailable.');
  }
  if (raw === null)
    return { kind: 'missing' };
  if (raw.length > 1000)
    fail('The original group status could not be verified.');
  let value: unknown;
  try {
    value = JSON.parse(raw);
  }
  catch {
    return fail('The original group status could not be verified.');
  }
  const data = groupBindingSchema.parse(value);
  if (data.request_key !== key)
    fail('The original group status could not be verified.');
  if (data.authority_sha256 !== await pendingAuthority(context.identity))
    return { kind: 'foreign' };
  if (attempt && data.intent_sha256 !== await sha256Text(JSON.stringify(attempt.intent)))
    return { kind: 'mismatch' };
  statusCheck(context);
  return { kind: 'valid', sourceSha256: data.source_sha256 };
}
async function saveStatusBinding(context: LegacyGroupStatusContext, attempt: PendingAttempt, source: LegacyGroupStatusSource) {
  if ((await statusBinding(context, attempt.request_key)).kind !== 'missing')
    fail('The original group status could not be verified.');
  const storage = statusStorage(context), name = statusBindingKey(context);
  const raw = JSON.stringify({ version: 1, request_key: attempt.request_key, authority_sha256: await pendingAuthority(context.identity), intent_sha256: await sha256Text(JSON.stringify(attempt.intent)), source_sha256: await sha256Text(JSON.stringify(source)), model: 'transaction_journals' });
  statusCheck(context);
  try {
    storage.setItem(name, raw);
    if (storage.getItem(name) !== raw)
      fail('Recovery storage is unavailable.');
  }
  catch {
    fail('Recovery storage is unavailable.');
  }
  statusCheck(context);
}
async function clearStatus(context: LegacyGroupStatusContext, access: FenceAccess, saved: Extract<LegacyGroupStatusPending, {
  kind: 'owned';
}>) {
  if (!saved.attempt || (await statusBinding(context, saved.requestKey, saved.attempt)).kind !== 'valid')
    fail('The original group status could not be verified.');
  const storage = statusStorage(context), name = statusBindingKey(context);
  statusCheck(context);
  try {
    storage.removeItem(name);
    if (storage.getItem(name) !== null)
      fail('Recovery storage is unavailable.');
  }
  catch {
    fail('Recovery storage is unavailable.');
  }
  await clearPending(context.identity, LEGACY_GROUP_STATUS_FAMILY, context.groupId!, saved.requestKey, storage);
  statusCheck(context);
  access.clear(saved.requestKey);
}
async function restoreStatus(context: LegacyGroupStatusContext, access: FenceAccess): Promise<LegacyGroupStatusPending> {
  statusCheck(context);
  const shared = access.read();
  if (shared.kind === 'foreign')
    return { kind: 'foreign' };
  const old = await readPending(context.identity, groupRequestFamilies.edit, context.groupId!, statusStorage(context)), saved = await readPending(context.identity, LEGACY_GROUP_STATUS_FAMILY, context.groupId!, statusStorage(context));
  statusCheck(context);
  if (old && saved)
    fail('Multiple group requests need recovery.');
  if (old)
    return { kind: 'older' };
  if (saved && (saved.family !== LEGACY_GROUP_STATUS_FAMILY || saved.permission !== 'collections.manage' || saved.resource_id !== context.groupId || !UUID.test(saved.request_key)))
    fail('The original group status could not be verified.');
  if (shared.kind === 'owned') {
    if (saved && saved.request_key !== shared.requestKey)
      fail('The original group status could not be verified.');
    return { kind: 'owned', requestKey: shared.requestKey, attempt: saved };
  }
  if (saved) {
    access.reserve(saved.request_key, shared.revision);
    return { kind: 'owned', requestKey: saved.request_key, attempt: saved };
  }
  if (statusStorage(context).getItem(statusBindingKey(context)) !== null)
    fail('The original group status could not be verified.');
  return { kind: 'ready', revision: shared.revision };
}
export async function restoreLegacyGroupStatus(context: LegacyGroupStatusContext) { statusCheck(context); return withLegacyGroupFence(context, access => restoreStatus(context, access)); }
async function lookupStatus(context: LegacyGroupStatusContext, saved: Extract<LegacyGroupStatusPending, {
  kind: 'owned';
}>): Promise<LegacyGroupStatusLookup> {
  const body = await context.request(`operations/requests/${saved.requestKey}`);
  statusCheck(context);
  if (body.status === 'not_found' && exact(body, ['status'])) {
    let retryAvailable = false;
    if (saved.attempt && (await statusBinding(context, saved.requestKey, saved.attempt)).kind === 'valid') {
      try {
        parseLegacyGroupStatusIntent(saved.attempt.intent);
        retryAvailable = true;
      }
      catch { /* Check-only. */ }
    }
    return { status: 'not_found', retryAvailable };
  }
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id))
    fail('The original group status could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null)
    return { status: body.status };
  if (body.status !== 'succeeded')
    fail('The original group status could not be verified.');
  const result = parseLegacyGroupReceipt(context, body.receipt, saved.attempt);
  if (result.requestId !== body.request_id)
    fail('The original group status could not be verified.');
  if (!saved.attempt || (await statusBinding(context, saved.requestKey, saved.attempt)).kind !== 'valid')
    return { status: 'succeeded', receipt: result, verifiedIntent: false };
  const intent = parseLegacyGroupStatusIntent(saved.attempt.intent), current = await currentLegacyGroup(context, true);
  if (current.version !== result.version || current.status !== intent.status)
    fail('The recorded group status could not be verified.');
  return { status: 'succeeded', receipt: result, verifiedIntent: true };
}
export async function lookupLegacyGroupStatus(context: LegacyGroupStatusContext, pending: LegacyGroupStatusPending): Promise<LegacyGroupStatusLookup> {
  statusCheck(context);
  if (pending.kind !== 'owned')
    fail('The original account must check this request.');
  return withLegacyGroupFence(context, async (access) => {
    const saved = await restoreStatus(context, access);
    if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey)
      fail('The original group status could not be verified.');
    const result = await lookupStatus(context, saved);
    if (result.status === 'succeeded' && result.verifiedIntent)
      await clearStatus(context, access, saved);
    return result;
  });
}
async function dispatchStatus(context: LegacyGroupStatusContext, access: FenceAccess, saved: Extract<LegacyGroupStatusPending, {
  kind: 'owned';
}>): Promise<LegacyGroupStatusResult> {
  if (!saved.attempt)
    fail('The original group status intent is unavailable.');
  const intent = parseLegacyGroupStatusIntent(saved.attempt.intent);
  try {
    statusWrite(context);
    const direct = parseLegacyGroupReceipt(context, await context.request(`operations/groups/${context.groupId}`, { method: 'PATCH', body: { ...intent }, idempotencyKey: saved.requestKey }), saved.attempt);
    const found = await lookupStatus(context, saved);
    if (found.status !== 'succeeded' || !found.verifiedIntent || JSON.stringify(found.receipt) !== JSON.stringify(direct))
      fail('The original group status could not be verified.');
    await clearStatus(context, access, saved);
    return { status: 'succeeded', receipt: direct };
  }
  catch {
    return { status: 'unknown', requestKey: saved.requestKey };
  }
}
export async function submitLegacyGroupStatus(context: LegacyGroupStatusContext, intent: LegacyGroupStatusIntent, expected: LegacyGroupStatusSource, revision: string): Promise<LegacyGroupStatusResult> {
  statusWrite(context);
  const body = parseLegacyGroupStatusIntent(intent);
  if (!sameLegacyGroupStatusIntent(buildLegacyGroupStatusIntent(expected, body.status, body.reason), body))
    fail('Review the exact group status.');
  return withLegacyGroupFence(context, async (access) => {
    const previous = await restoreStatus(context, access);
    if (previous.kind !== 'ready')
      return { status: 'existing', pending: previous };
    const latest = await currentLegacyGroupStatusSource(context, body.status);
    if (JSON.stringify(latest) !== JSON.stringify(expected))
      fail('The group, owner or receiver changed. Review again.');
    if (!await context.verifyFresh())
      fail('Complete current account verification before changing group status.');
    statusWrite(context);
    const key = (context.createKey ?? (() => crypto.randomUUID()))();
    if (!UUID.test(key))
      fail('A secure request reference is unavailable.');
    access.reserve(key, revision);
    let attempt: PendingAttempt;
    try {
      attempt = await retainPending(context.identity, LEGACY_GROUP_STATUS_FAMILY, context.groupId!, key, 'collections.manage', { ...body }, statusStorage(context));
      await saveStatusBinding(context, attempt, latest);
    }
    catch {
      return { status: 'unknown', requestKey: key };
    }
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled())
      return { status: 'unknown', requestKey: key };
    return dispatchStatus(context, access, { kind: 'owned', requestKey: key, attempt });
  });
}
export async function retryLegacyGroupStatus(context: LegacyGroupStatusContext, pending: LegacyGroupStatusPending): Promise<LegacyGroupStatusResult> {
  statusWrite(context);
  if (pending.kind !== 'owned' || !pending.attempt)
    fail('The original group status intent is unavailable.');
  return withLegacyGroupFence(context, async (access) => {
    const saved = await restoreStatus(context, access);
    if (saved.kind !== 'owned' || !saved.attempt || saved.requestKey !== pending.requestKey || JSON.stringify(saved.attempt.intent) !== JSON.stringify(pending.attempt?.intent))
      fail('The original group status could not be verified.');
    const previous = await lookupStatus(context, saved);
    if (previous.status === 'succeeded' && previous.verifiedIntent) {
      await clearStatus(context, access, saved);
      return { status: 'succeeded', receipt: previous.receipt };
    }
    if (previous.status !== 'not_found' || !previous.retryAvailable)
      fail('The original group status remains unresolved.');
    const intent = parseLegacyGroupStatusIntent(saved.attempt.intent), bound = await statusBinding(context, saved.requestKey, saved.attempt), latest = await currentLegacyGroupStatusSource(context, intent.status);
    if (bound.kind !== 'valid' || await sha256Text(JSON.stringify(latest)) !== bound.sourceSha256 || !sameLegacyGroupStatusIntent(buildLegacyGroupStatusIntent(latest, intent.status, intent.reason), intent))
      fail('The original group, owner or receiver changed.');
    if (!await context.verifyFresh())
      fail('Complete current account verification before retrying group status.');
    statusWrite(context);
    return dispatchStatus(context, access, saved);
  });
}
