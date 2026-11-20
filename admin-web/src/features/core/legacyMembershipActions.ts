/* eslint-disable no-control-regex -- Validate operator search and audit input. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import { clearPending, pendingAuthority, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity } from './pendingAttempt';
import { withPendingFence, type FenceAccess, type FenceLock } from '../operations/pendingFence';

const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/, HASH = /^[a-f0-9]{64}$/;
const id = z.string().regex(UUID), PERMISSION = 'users.manage', families = {create: 'operating-createmembership', edit: 'operating-updatemembership'} as const;
const roles = ['admin', 'receiver', 'member', 'contributor', 'viewer'] as const, statuses = ['active', 'invited', 'removed', 'left'] as const;
export interface LegacyMembershipContext {
  mode: 'create' | 'edit'; groupId: string; userId?: string; request: AdminRequest; identity: PendingIdentity; actorId: string; permissions: readonly string[];
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean; verifyFresh: () => Promise<boolean>;
  storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;
}
export interface LegacyMemberChoice {id: string; publicId: string; displayName: string | null; memberType: 'app' | 'direct'; momoNumber: string | null; version: number;}
export interface LegacyMembershipSource {group: {id: string; title: string; status: 'draft' | 'active' | 'suspended' | 'archived'; version: number}; member: LegacyMemberChoice & {status: 'invited' | 'active' | 'suspended' | 'closed'}; membership: {role: string; status: string; version: number} | null; total: number;}
export interface LegacyMembershipIntent {group_id?: string; user_id?: string; role: typeof roles[number]; status: typeof statuses[number]; expected_version?: number; reason: string;}
export interface LegacyMembershipReceipt {requestId: string; groupId: string; userId: string; version: number;}
export type LegacyMembershipPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type LegacyMembershipResult = {status: 'succeeded'; receipt: LegacyMembershipReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LegacyMembershipPending};
export type LegacyMembershipLookup = {status: 'succeeded'; receipt: LegacyMembershipReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
function fail(message: string): never {throw new Error(message);}
function object(value: unknown): value is Record<string, unknown> {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function safeText(value: unknown, minimum: number, maximum: number): value is string {return typeof value === 'string' && value === value.trim() && value.length >= minimum && value.length <= maximum && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value);}
function resource(context: LegacyMembershipContext) {return context.mode === 'create' ? 'new' : `${context.groupId}:${context.userId ?? ''}`;}
function check(context: LegacyMembershipContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'transaction_journals' || !UUID.test(context.actorId) || !UUID.test(context.groupId) || context.mode === 'edit' && (!context.userId || !UUID.test(context.userId)) ||
      context.identity.id !== context.actorId || context.identity.role === 'staff' || !['collections.read', 'users.read', PERMISSION, 'overview.read'].every(value => context.permissions.includes(value) && context.identity.permissions.includes(value)) ||
      !Number.isFinite(expires) || expires <= Date.now()) fail('Membership changes are unavailable to your current account.');
}
function write(context: LegacyMembershipContext) {check(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Membership changes are not enabled for this workspace.');}
export function parseLegacyMembershipIntent(value: unknown, context: LegacyMembershipContext): LegacyMembershipIntent {
  if (!object(value)) fail('The original membership request could not be verified.');
  const fields = context.mode === 'create' ? ['group_id', 'user_id', 'role', 'status', 'reason'] : ['role', 'status', 'reason', 'expected_version'];
  if (!exact(value, fields) || !roles.includes(value.role as typeof roles[number]) || !statuses.includes(value.status as typeof statuses[number]) || !safeText(value.reason, 8, 1000) ||
      context.mode === 'create' && (value.group_id !== context.groupId || typeof value.user_id !== 'string' || !UUID.test(value.user_id) || !['active', 'invited'].includes(String(value.status))) ||
      context.mode === 'edit' && (typeof value.expected_version !== 'number' || !Number.isSafeInteger(value.expected_version) || value.expected_version < 1 || value.expected_version >= Number.MAX_SAFE_INTEGER)) fail('The original membership request could not be verified.');
  return value as unknown as LegacyMembershipIntent;
}
function choice(value: unknown): LegacyMemberChoice {
  if (!object(value) || typeof value.id !== 'string' || !UUID.test(value.id) || typeof value.public_id !== 'string' || !/^\d{6}$/.test(value.public_id) ||
      !(value.display_name === null || safeText(value.display_name, 1, 120)) || !['app', 'direct'].includes(String(value.member_type)) ||
      !(value.momo_number === null || value.momo_number === '' || typeof value.momo_number === 'string' && /^07[2389]\d{7}$/.test(value.momo_number)) ||
      typeof value.version !== 'number' || !Number.isSafeInteger(value.version) || value.version < 1) fail('The member could not be verified.');
  return {id: value.id, publicId: value.public_id, displayName: value.display_name as string | null, memberType: value.member_type as 'app' | 'direct', momoNumber: value.momo_number ? String(value.momo_number) : null, version: value.version};
}
export async function searchLegacyMembers(context: LegacyMembershipContext, search: string): Promise<LegacyMemberChoice[]> {
  write(context); if (context.mode !== 'create' || search.length > 200 || /[\x00-\x1f\x7f]/.test(search)) fail('Member search is unavailable.');
  const query = new URLSearchParams({kind: 'users', search: search.trim(), limit: '25'}), body = await context.request(`operations/lookups?${query}`); check(context);
  if (!exact(body, ['rows']) || !Array.isArray(body.rows) || body.rows.length > 25) fail('Member search could not be verified.');
  const rows = body.rows.map(choice); if (new Set(rows.map(row => row.id)).size !== rows.length) fail('Member search could not be verified.'); return rows;
}
async function member(context: LegacyMembershipContext, userId: string): Promise<LegacyMembershipSource['member']> {
  const body = await context.request(`operations/users/${userId}`); check(context);
  if (body.contract_version !== undefined || body.model !== undefined || body.resource_type !== 'users' || body.current_actor_id !== context.actorId || !object(body.resource)) fail('The member could not be verified.');
  const row = body.resource, selected = choice(row);
  if (selected.id !== userId || row.collect_user_id !== userId || !['invited', 'active', 'suspended', 'closed'].includes(String(row.status)) || row.display_name_recorded !== (selected.displayName !== null)) fail('The member could not be verified.');
  return {...selected, status: row.status as LegacyMembershipSource['member']['status']};
}
export async function currentLegacyMembership(context: LegacyMembershipContext, userId: string, recovering = false): Promise<LegacyMembershipSource> {
  check(context); if (!UUID.test(userId) || context.mode === 'edit' && userId !== context.userId) fail('The membership could not be verified.');
  let offset = 0, total: number | null = null, group: LegacyMembershipSource['group'] | null = null, found: LegacyMembershipSource['membership'] = null, memberRow: Record<string, unknown> | null = null;
  const seen = new Set<string>();
  do {
    const query = new URLSearchParams({relation: 'memberships', limit: '100', offset: String(offset)}), body = await context.request(`operations/groups/${context.groupId}?${query}`); check(context);
    if (body.contract_version !== undefined || body.model !== undefined || body.resource_type !== 'groups' || body.current_actor_id !== context.actorId || body.can_manage !== true || !object(body.resource) || body.resource.id !== context.groupId ||
        !object(body.related) || !exact(body.related, ['memberships']) || !Array.isArray(body.related.memberships) || !object(body.related_pages) || !exact(body.related_pages, ['memberships']) || !object(body.related_pages.memberships)) fail('The membership could not be verified.');
    const g = body.resource, page = body.related_pages.memberships, rows = body.related.memberships;
    if (!safeText(g.title, 3, 160) || !['draft', 'active', 'suspended', 'archived'].includes(String(g.status)) || !recovering && g.status === 'archived' || g.country_code !== 'RW' || g.currency !== 'RWF' ||
        typeof g.version !== 'number' || !Number.isSafeInteger(g.version) || g.version < 1 || g.version >= Number.MAX_SAFE_INTEGER ||
        !exact(page, ['total', 'limit', 'offset', 'next_offset']) || typeof page.total !== 'number' || !Number.isSafeInteger(page.total) || page.total < 0 || page.total > 1000 || page.limit !== 100 || page.offset !== offset ||
        rows.length !== Math.max(0, Math.min(100, page.total - offset)) || page.next_offset !== (offset + rows.length < page.total ? offset + rows.length : null) || body.related_truncated !== (page.total > rows.length) || total !== null && total !== page.total) fail('The membership could not be verified.');
    const current = {id: context.groupId, title: g.title, status: g.status as LegacyMembershipSource['group']['status'], version: g.version};
    if (group && JSON.stringify(group) !== JSON.stringify(current)) fail('The group changed. Review it again.'); group = current; total = page.total;
    for (const row of rows) {
      if (!object(row) || row.group_id !== context.groupId || typeof row.user_id !== 'string' || !UUID.test(row.user_id) || seen.has(row.user_id) ||
          !['owner', ...roles].includes(String(row.role)) || !statuses.includes(row.status as typeof statuses[number]) || typeof row.version !== 'number' || !Number.isSafeInteger(row.version) || row.version < 1 || row.version >= Number.MAX_SAFE_INTEGER) fail('The membership could not be verified.');
      seen.add(row.user_id); if (row.user_id === userId) {found = {role: String(row.role), status: String(row.status), version: row.version}; memberRow = row;}
    }
    offset += rows.length;
  } while (total !== null && offset < total);
  if (!group || total === null || seen.size !== total) fail('The membership could not be verified.');
  const person = await member(context, userId);
  if (memberRow && (memberRow.group_title !== group.title || memberRow.public_id !== person.publicId || memberRow.display_name !== person.displayName || memberRow.member_type !== person.memberType ||
      (memberRow.display_name_recorded !== 0 && memberRow.display_name_recorded !== 1) || (memberRow.display_name_recorded === 1) !== (person.displayName !== null) ||
      (memberRow.momo_number || null) !== person.momoNumber)) fail('The membership identity could not be verified.');
  if (!recovering && (person.status === 'closed' || context.mode === 'create' && (person.status !== 'active' || found !== null) || context.mode === 'edit' && (!found || found.role === 'owner'))) fail('The membership is unavailable for this action.');
  return {group, member: person, membership: found, total};
}
function verifySource(context: LegacyMembershipContext, intent: LegacyMembershipIntent, source: LegacyMembershipSource) {
  const userId = context.mode === 'create' ? intent.user_id : context.userId;
  if (source.group.id !== context.groupId || source.member.id !== userId || source.group.status === 'archived' || source.member.status === 'closed' ||
      intent.status === 'active' && source.member.status !== 'active' || context.mode === 'create' && source.membership !== null ||
      context.mode === 'edit' && (!source.membership || source.membership.role === 'owner' || source.membership.version !== intent.expected_version)) fail('The group or membership changed. Review it again.');
}
function verifyAttempt(context: LegacyMembershipContext, attempt: PendingAttempt) {if (attempt.family !== families[context.mode] || attempt.resource_id !== resource(context) || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key)) fail('The original membership request could not be verified.');}
function store(context: LegacyMembershipContext): Storage {try {return context.storage ?? sessionStorage;} catch {return fail('Recovery storage is unavailable.');}}
function bindingKey(context: LegacyMembershipContext) {return `collect.admin.legacy-membership-${context.mode}.context.v1:${resource(context)}`;}
async function binding(context: LegacyMembershipContext, key: string, attempt?: PendingAttempt): Promise<{kind: 'valid'; sourceSha256: string} | {kind: 'missing' | 'foreign' | 'mismatch'}> {
  let raw: string | null; try {raw = store(context).getItem(bindingKey(context));} catch {return fail('Recovery storage is unavailable.');}
  if (raw === null) return {kind: 'missing'}; if (raw.length > 1000) fail('The original membership request could not be verified.');
  let value: unknown; try {value = JSON.parse(raw);} catch {return fail('The original membership request could not be verified.');}
  const data = z.object({version: z.literal(1), request_key: id, authority_sha256: z.string().regex(HASH), intent_sha256: z.string().regex(HASH), source_sha256: z.string().regex(HASH), model: z.literal('transaction_journals')}).strict().parse(value);
  if (data.request_key !== key) fail('The original membership request could not be verified.'); if (data.authority_sha256 !== await pendingAuthority(context.identity)) return {kind: 'foreign'};
  if (attempt && data.intent_sha256 !== await sha256Text(JSON.stringify(attempt.intent))) return {kind: 'mismatch'}; return {kind: 'valid', sourceSha256: data.source_sha256};
}
async function saveBinding(context: LegacyMembershipContext, key: string, attempt: PendingAttempt, source: LegacyMembershipSource) {
  if ((await binding(context, key)).kind !== 'missing') fail('The original membership request could not be verified.');
  const storage = store(context), name = bindingKey(context), raw = JSON.stringify({version: 1, request_key: key, authority_sha256: await pendingAuthority(context.identity), intent_sha256: await sha256Text(JSON.stringify(attempt.intent)), source_sha256: await sha256Text(JSON.stringify(source)), model: 'transaction_journals'}); check(context);
  try {storage.setItem(name, raw); if (storage.getItem(name) !== raw) fail('Recovery storage is unavailable.');} catch {fail('Recovery storage is unavailable.');} check(context);
}
async function clearBinding(context: LegacyMembershipContext, key: string) {
  const state = await binding(context, key); if (state.kind === 'foreign') fail('The original membership request could not be verified.'); if (state.kind === 'missing') return;
  const storage = store(context), name = bindingKey(context); check(context); try {storage.removeItem(name); if (storage.getItem(name) !== null) fail('Recovery storage is unavailable.');} catch {fail('Recovery storage is unavailable.');}
}
async function fence<T>(context: LegacyMembershipContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {return withPendingFence({identity: context.identity, family: families[context.mode], resourceId: resource(context), isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);}
async function restoreUnderFence(context: LegacyMembershipContext, access: FenceAccess): Promise<LegacyMembershipPending> {
  check(context); const shared = access.read(); if (shared.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, families[context.mode], resource(context), context.storage); if (attempt) verifyAttempt(context, attempt);
  const owner = attempt ? await binding(context, attempt.request_key, attempt) : {kind: 'missing' as const}; check(context); if (owner.kind === 'foreign') return {kind: 'foreign'};
  if (shared.kind === 'owned') {if (attempt && attempt.request_key !== shared.requestKey) fail('The original membership request could not be verified.'); return {kind: 'owned', requestKey: shared.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, shared.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};} return {kind: 'ready', revision: shared.revision};
}
export async function restoreLegacyMembership(context: LegacyMembershipContext): Promise<LegacyMembershipPending> {check(context); return fence(context, access => restoreUnderFence(context, access));}
async function clear(context: LegacyMembershipContext, access: FenceAccess, pending: Extract<LegacyMembershipPending, {kind: 'owned'}>) {await clearBinding(context, pending.requestKey); if (pending.attempt) await clearPending(context.identity, families[context.mode], resource(context), pending.requestKey, context.storage); check(context); access.clear(pending.requestKey);}
function receipt(context: LegacyMembershipContext, value: unknown, attempt: PendingAttempt | null): LegacyMembershipReceipt {
  const body = z.object({request_id: id, resource_type: z.literal('memberships'), resource_id: z.string(), version: z.number().int().min(1).max(Number.MAX_SAFE_INTEGER), status: z.literal('succeeded')}).strict().parse(value);
  const parts = body.resource_id.split('/');
  if (parts.length !== 2 || parts[0] !== context.groupId || !UUID.test(parts[1]) || context.mode === 'create' && (body.version !== 1 || attempt !== null && (attempt.intent.group_id !== context.groupId || attempt.intent.user_id !== parts[1])) ||
      context.mode === 'edit' && (parts[1] !== context.userId || body.version < 2 || attempt !== null && (typeof attempt.intent.expected_version !== 'number' || !Number.isSafeInteger(attempt.intent.expected_version) || body.version !== attempt.intent.expected_version + 1))) fail('The original membership receipt could not be verified.');
  return {requestId: body.request_id, groupId: parts[0], userId: parts[1], version: body.version};
}
async function lookupUnderFence(context: LegacyMembershipContext, pending: Extract<LegacyMembershipPending, {kind: 'owned'}>): Promise<LegacyMembershipLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) {let retryAvailable = false; if (pending.attempt && (await binding(context, pending.requestKey, pending.attempt)).kind === 'valid') {try {parseLegacyMembershipIntent(pending.attempt.intent, context); retryAvailable = true;} catch { /* Other retained intents remain check-only. */ }} return {status: 'not_found', retryAvailable};}
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original membership receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status}; if (body.status !== 'succeeded') fail('The original membership receipt could not be verified.');
  if (pending.attempt && (await binding(context, pending.requestKey, pending.attempt)).kind === 'mismatch') fail('The original membership request could not be verified.');
  const saved = receipt(context, body.receipt, pending.attempt); if (saved.requestId !== body.request_id) fail('The original membership receipt could not be verified.');
  if (context.mode === 'edit' && !pending.attempt) {const current = await currentLegacyMembership(context, saved.userId, true); if (!current.membership || current.membership.version < saved.version) fail('The membership version could not be verified.');}
  return {status: 'succeeded', receipt: saved};
}
async function finish(context: LegacyMembershipContext, access: FenceAccess, pending: Extract<LegacyMembershipPending, {kind: 'owned'}>, value: unknown): Promise<LegacyMembershipResult> {
  const direct = receipt(context, value, pending.attempt), found = await lookupUnderFence(context, pending); if (found.status !== 'succeeded' || JSON.stringify(found.receipt) !== JSON.stringify(direct)) fail('The original membership receipt could not be verified.');
  await clear(context, access, pending); return {status: 'succeeded', receipt: direct};
}
export async function submitLegacyMembership(context: LegacyMembershipContext, input: unknown, source: LegacyMembershipSource, observedRevision: string): Promise<LegacyMembershipResult> {
  write(context); const intent = parseLegacyMembershipIntent(input, context); verifySource(context, intent, source);
  return fence(context, async access => {
    const existing = await restoreUnderFence(context, access); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const latest = await currentLegacyMembership(context, source.member.id); verifySource(context, intent, latest); if (JSON.stringify(latest) !== JSON.stringify(source)) fail('The group or membership changed. Review it again.');
    if (!await context.verifyFresh()) fail('Complete current account verification before recording the membership.');
    write(context); const requestKey = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision); let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, families[context.mode], resource(context), requestKey, PERMISSION, {...intent}, context.storage); verifyAttempt(context, attempt); await saveBinding(context, requestKey, attempt, latest);}
    catch (error) {if (context.isCurrent()) {try {const retained = await readPending(context.identity, families[context.mode], resource(context), context.storage); if (retained?.request_key === requestKey) await clearPending(context.identity, families[context.mode], resource(context), requestKey, context.storage); await clearBinding(context, requestKey); access.clear(requestKey);} catch { /* Preserve the fence if cleanup is uncertain. */ }} throw error;}
    const pending: Extract<LegacyMembershipPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt}; if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey};
    try {const response = await context.request(context.mode === 'create' ? 'operations/memberships' : `operations/memberships/${context.groupId}/${context.userId}`, {method: context.mode === 'create' ? 'POST' : 'PATCH', body: {...intent}, idempotencyKey: requestKey}); check(context); return await finish(context, access, pending, response);}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLegacyMembership(context: LegacyMembershipContext, pending: LegacyMembershipPending): Promise<LegacyMembershipLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return fence(context, async access => {const stored = await restoreUnderFence(context, access); if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey) fail('The original membership request could not be verified.'); const result = await lookupUnderFence(context, stored); if (result.status === 'succeeded') await clear(context, access, stored); return result;});
}
export async function retryLegacyMembership(context: LegacyMembershipContext, pending: LegacyMembershipPending): Promise<LegacyMembershipResult> {
  write(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original membership intent is unavailable.');
  return fence(context, async access => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original membership request could not be verified.');
    const previous = await lookupUnderFence(context, stored); if (previous.status === 'succeeded') {await clear(context, access, stored); return {status: 'succeeded', receipt: previous.receipt};}
    if (previous.status !== 'not_found' || !previous.retryAvailable) fail('The original membership request remains unresolved.');
    const intent = parseLegacyMembershipIntent(stored.attempt.intent, context), owner = await binding(context, stored.requestKey, stored.attempt), userId = context.mode === 'create' ? intent.user_id! : context.userId!, latest = await currentLegacyMembership(context, userId); verifySource(context, intent, latest);
    if (owner.kind !== 'valid' || await sha256Text(JSON.stringify(latest)) !== owner.sourceSha256) fail('The original group or membership changed. Check the request before continuing.');
    if (!await context.verifyFresh()) fail('Complete current account verification before retrying the membership.');
    write(context);
    try {const response = await context.request(context.mode === 'create' ? 'operations/memberships' : `operations/memberships/${context.groupId}/${context.userId}`, {method: context.mode === 'create' ? 'POST' : 'PATCH', body: {...intent}, idempotencyKey: stored.requestKey}); check(context); return await finish(context, access, stored, response);}
    catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
