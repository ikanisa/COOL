/* eslint-disable no-control-regex -- Reject control characters in reviewed receiver data. */
import type { AdminRequest } from '../../api/client';
import { isId, isObject, isSafeCount } from '../core/contracts';
import { clearPending, pendingAuthority, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity } from '../core/pendingAttempt';
import { withPendingFence, type FenceAccess, type FenceLock } from '../operations/pendingFence';

const FLUTTER_FAMILY = 'operating-updatepayee', GUARDED_FAMILY = 'legacy-payee-update-guarded', PERMISSION = 'receivers.manage', HASH = /^[a-f0-9]{64}$/;
export interface LegacyPayeeContext {id: string; request: AdminRequest; identity: PendingIdentity; actorId: string; permissions: readonly string[]; financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean; verifyFresh: () => Promise<boolean>; storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;}
export interface LegacyPayeeSource {payee: {id: string; groupId: string; label: string; network: 'mtn_momo' | 'airtel_money'; route: string; status: 'active' | 'inactive'; version: number}; group: {id: string; title: string; status: 'draft' | 'active' | 'suspended' | 'archived'; version: number}; activePayeeId: string | null; total: number;}
export interface LegacyPayeeIntent {label: string; status: 'active' | 'inactive'; expected_version: number; expected_group_version: number; reason: string;}
export interface LegacyPayeeReceipt {requestId: string; payeeId: string; version: number;}
export type LegacyPayeePending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type LegacyPayeeLookup = {status: 'succeeded'; receipt: LegacyPayeeReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
export type LegacyPayeeResult = {status: 'succeeded'; receipt: LegacyPayeeReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LegacyPayeePending};
function fail(message = 'The receiver request could not be verified.'): never {throw new Error(message);}
function exact(value: Record<string, unknown>, keys: readonly string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function text(value: unknown, min: number, max: number): value is string {return typeof value === 'string' && value === value.trim() && value.length >= min && value.length <= max && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value);}
function version(value: unknown): value is number {return isSafeCount(value) && value > 0 && value < Number.MAX_SAFE_INTEGER;}
function check(context: LegacyPayeeContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'transaction_journals' || !isId(context.id) || !isId(context.actorId) || context.identity.id !== context.actorId || context.identity.role === 'staff' ||
      !Number.isFinite(expires) || expires <= Date.now() || !['receivers.read', 'receivers.manage', 'collections.read', 'overview.read'].every(value => context.permissions.includes(value) && context.identity.permissions.includes(value))) fail('Receiver editing is unavailable to your current account.');
}
function write(context: LegacyPayeeContext) {check(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Receiver changes are not enabled for this workspace.');}
export function parseLegacyPayeeIntent(value: unknown): LegacyPayeeIntent {
  if (!isObject(value) || !exact(value, ['label', 'status', 'expected_version', 'expected_group_version', 'reason']) || !text(value.label, 2, 120) || !['active', 'inactive'].includes(String(value.status)) ||
      !version(value.expected_version) || !version(value.expected_group_version) || !text(value.reason, 8, 1000)) fail('The original receiver request could not be verified.');
  return value as unknown as LegacyPayeeIntent;
}
async function payee(context: LegacyPayeeContext) {
  const body = await context.request(`operations/payees/${context.id}`); check(context);
  if (body.contract_version !== undefined || body.model !== undefined || body.resource_type !== 'payees' || body.current_actor_id !== context.actorId || body.can_manage !== true || !isObject(body.resource)) fail('The receiver could not be verified.');
  const row = body.resource;
  if (row.id !== context.id || !isId(row.group_id) || !text(row.label, 2, 120) || !['mtn_momo', 'airtel_money'].includes(String(row.network)) || typeof row.momo_number_or_code !== 'string' || !/^\d{4,12}$/.test(row.momo_number_or_code) ||
      !['active', 'inactive'].includes(String(row.status)) || !version(row.version) || row.rail !== 'rwanda_momo' || row.currency !== 'RWF') fail('The receiver could not be verified.');
  return {id: context.id, groupId: row.group_id, label: row.label, network: row.network as LegacyPayeeSource['payee']['network'], route: row.momo_number_or_code, status: row.status as LegacyPayeeSource['payee']['status'], version: row.version};
}
export async function currentLegacyPayee(context: LegacyPayeeContext, recovering = false): Promise<LegacyPayeeSource> {
  check(context); const current = await payee(context); let offset = 0, total: number | null = null, group: LegacyPayeeSource['group'] | null = null, targetSeen = false, activePayeeId: string | null = null; const seen = new Set<string>();
  do {
    const query = new URLSearchParams({relation: 'payees', limit: '100', offset: String(offset)}), body = await context.request(`operations/groups/${current.groupId}?${query}`); check(context);
    if (body.contract_version !== undefined || body.model !== undefined || body.resource_type !== 'groups' || body.current_actor_id !== context.actorId || body.can_manage !== true || !isObject(body.resource) || body.resource.id !== current.groupId || !isObject(body.related) || !exact(body.related, ['payees']) || !Array.isArray(body.related.payees) || !isObject(body.related_pages) || !exact(body.related_pages, ['payees']) || !isObject(body.related_pages.payees)) fail('The receiver group could not be verified.');
    const record = body.resource, page = body.related_pages.payees, rows = body.related.payees;
    if (!text(record.title, 3, 160) || !['draft', 'active', 'suspended', 'archived'].includes(String(record.status)) || !recovering && record.status === 'archived' || !version(record.version) || record.country_code !== 'RW' || record.currency !== 'RWF' ||
        !exact(page, ['total', 'limit', 'offset', 'next_offset']) || !isSafeCount(page.total) || page.total > 1000 || page.limit !== 100 || page.offset !== offset || rows.length !== Math.max(0, Math.min(100, page.total - offset)) || page.next_offset !== (offset + rows.length < page.total ? offset + rows.length : null) || body.related_truncated !== (page.total > rows.length) || total !== null && page.total !== total) fail('The receiver group could not be verified.');
    const groupNow = {id: current.groupId, title: record.title, status: record.status as LegacyPayeeSource['group']['status'], version: record.version};
    if (group && JSON.stringify(group) !== JSON.stringify(groupNow)) fail('The group changed. Review it again.'); group = groupNow; total = page.total;
    for (const row of rows) {
      if (!isObject(row) || !isId(row.id) || seen.has(row.id) || row.group_id !== current.groupId || !['active', 'inactive'].includes(String(row.status)) || !version(row.version)) fail('The receiver list could not be verified.');
      seen.add(row.id); if (row.status === 'active') {if (activePayeeId !== null) fail('The active receiver could not be verified.'); activePayeeId = row.id;}
      if (row.id === context.id) {targetSeen = true; if (row.version !== current.version || row.status !== current.status || row.label !== current.label || row.network !== current.network || row.momo_number_or_code !== current.route) fail('The receiver changed. Review it again.');}
    }
    offset += rows.length;
  } while (total !== null && offset < total);
  if (!group || total === null || seen.size !== total || !targetSeen) fail('The receiver group could not be verified.');
  return {payee: current, group, activePayeeId, total};
}
function verifySource(context: LegacyPayeeContext, intent: LegacyPayeeIntent, source: LegacyPayeeSource) {
  if (source.payee.id !== context.id || source.payee.groupId !== source.group.id || source.group.status === 'archived' || source.payee.version !== intent.expected_version || source.group.version !== intent.expected_group_version ||
      intent.status === 'inactive' && source.payee.status === 'active' && source.group.status === 'active' || intent.status === 'active' && source.activePayeeId !== null && source.activePayeeId !== context.id) fail('The receiver or group changed. Review it again.');
}
function storage(context: LegacyPayeeContext): Storage {try {return context.storage ?? sessionStorage;} catch {return fail('Recovery storage is unavailable.');}}
function bindingKey(context: LegacyPayeeContext) {return `collect.admin.legacy-payee-update.context.v1:${context.id}`;}
async function binding(context: LegacyPayeeContext, requestKey: string, attempt?: PendingAttempt): Promise<{kind: 'valid'; sourceHash: string} | {kind: 'missing' | 'foreign' | 'mismatch'}> {
  let raw: string | null; try {raw = storage(context).getItem(bindingKey(context));} catch {return fail('Recovery storage is unavailable.');}
  if (raw === null) return {kind: 'missing'}; if (raw.length > 1000) fail(); let value: unknown; try {value = JSON.parse(raw);} catch {return fail();}
  if (!isObject(value) || !exact(value, ['version', 'request_key', 'authority_sha256', 'intent_sha256', 'source_sha256', 'model']) || value.version !== 1 || value.request_key !== requestKey || value.model !== 'transaction_journals' ||
      typeof value.authority_sha256 !== 'string' || !HASH.test(value.authority_sha256) || typeof value.intent_sha256 !== 'string' || !HASH.test(value.intent_sha256) || typeof value.source_sha256 !== 'string' || !HASH.test(value.source_sha256)) fail();
  if (value.authority_sha256 !== await pendingAuthority(context.identity)) return {kind: 'foreign'};
  if (attempt && value.intent_sha256 !== await sha256Text(JSON.stringify(attempt.intent))) return {kind: 'mismatch'}; return {kind: 'valid', sourceHash: value.source_sha256};
}
async function saveBinding(context: LegacyPayeeContext, attempt: PendingAttempt, source: LegacyPayeeSource) {
  if ((await binding(context, attempt.request_key)).kind !== 'missing') fail(); const store = storage(context), name = bindingKey(context);
  const raw = JSON.stringify({version: 1, request_key: attempt.request_key, authority_sha256: await pendingAuthority(context.identity), intent_sha256: await sha256Text(JSON.stringify(attempt.intent)), source_sha256: await sha256Text(JSON.stringify(source)), model: 'transaction_journals'}); check(context);
  try {store.setItem(name, raw); if (store.getItem(name) !== raw) fail();} catch {fail('Recovery storage is unavailable.');} check(context);
}
async function clearBinding(context: LegacyPayeeContext, requestKey: string) {
  const value = await binding(context, requestKey); if (value.kind === 'foreign') fail(); if (value.kind === 'missing') return;
  const store = storage(context), name = bindingKey(context); check(context); try {store.removeItem(name); if (store.getItem(name) !== null) fail();} catch {fail('Recovery storage is unavailable.');}
}
async function fence<T>(context: LegacyPayeeContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {return withPendingFence({identity: context.identity, family: FLUTTER_FAMILY, resourceId: context.id, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);}
async function restoreUnderFence(context: LegacyPayeeContext, access: FenceAccess): Promise<LegacyPayeePending> {
  check(context); const shared = access.read(); if (shared.kind === 'foreign') return {kind: 'foreign'};
  const guarded = await readPending(context.identity, GUARDED_FAMILY, context.id, context.storage), flutter = await readPending(context.identity, FLUTTER_FAMILY, context.id, context.storage);
  if (guarded && flutter) fail('Multiple original receiver requests need review.'); const attempt = guarded ?? flutter;
  if (attempt && (![GUARDED_FAMILY, FLUTTER_FAMILY].includes(attempt.family) || attempt.resource_id !== context.id || attempt.permission !== PERMISSION || !isId(attempt.request_key))) fail();
  const owner = attempt ? await binding(context, attempt.request_key, attempt) : {kind: 'missing' as const}; check(context); if (owner.kind === 'foreign') return {kind: 'foreign'};
  if (shared.kind === 'owned') {if (attempt && attempt.request_key !== shared.requestKey) fail(); return {kind: 'owned', requestKey: shared.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, shared.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};} return {kind: 'ready', revision: shared.revision};
}
export async function restoreLegacyPayee(context: LegacyPayeeContext): Promise<LegacyPayeePending> {check(context); return fence(context, access => restoreUnderFence(context, access));}
async function clear(context: LegacyPayeeContext, access: FenceAccess, pending: Extract<LegacyPayeePending, {kind: 'owned'}>) {
  await clearBinding(context, pending.requestKey); if (pending.attempt) await clearPending(context.identity, pending.attempt.family, context.id, pending.requestKey, context.storage); check(context); access.clear(pending.requestKey);
}
function receipt(context: LegacyPayeeContext, value: unknown, attempt: PendingAttempt | null): LegacyPayeeReceipt {
  if (!isObject(value) || !exact(value, ['request_id', 'resource_type', 'resource_id', 'version', 'status']) || !isId(value.request_id) || value.resource_type !== 'payees' || value.resource_id !== context.id || value.status !== 'succeeded' || !isSafeCount(value.version) || value.version < 2 ||
      attempt && (!version(attempt.intent.expected_version) || value.version !== attempt.intent.expected_version + 1)) fail('The original receiver receipt could not be verified.');
  return {requestId: value.request_id, payeeId: context.id, version: value.version};
}
async function lookupUnderFence(context: LegacyPayeeContext, pending: Extract<LegacyPayeePending, {kind: 'owned'}>): Promise<LegacyPayeeLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) {let retryAvailable = false;
    if (pending.attempt?.family === GUARDED_FAMILY && (await binding(context, pending.requestKey, pending.attempt)).kind === 'valid') {try {parseLegacyPayeeIntent(pending.attempt.intent); retryAvailable = true;} catch { /* Unbound attempts remain check-only. */ }} return {status: 'not_found', retryAvailable};}
  if (!exact(body, ['status', 'request_id', 'receipt']) || !isId(body.request_id)) fail('The original receiver receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded' || pending.attempt && (await binding(context, pending.requestKey, pending.attempt)).kind === 'mismatch') fail('The original receiver receipt could not be verified.');
  const saved = receipt(context, body.receipt, pending.attempt); if (saved.requestId !== body.request_id) fail('The original receiver receipt could not be verified.');
  if (!pending.attempt && (await payee(context)).version < saved.version) fail('The receiver version could not be verified.'); return {status: 'succeeded', receipt: saved};
}
async function finish(context: LegacyPayeeContext, access: FenceAccess, pending: Extract<LegacyPayeePending, {kind: 'owned'}>, response: unknown): Promise<LegacyPayeeResult> {
  const direct = receipt(context, response, pending.attempt), original = await lookupUnderFence(context, pending); if (original.status !== 'succeeded' || JSON.stringify(direct) !== JSON.stringify(original.receipt)) fail('The original receiver receipt could not be verified.');
  await clear(context, access, pending); return {status: 'succeeded', receipt: direct};
}
export async function submitLegacyPayee(context: LegacyPayeeContext, input: LegacyPayeeIntent, source: LegacyPayeeSource, revision: string): Promise<LegacyPayeeResult> {
  write(context); const intent = parseLegacyPayeeIntent(input); verifySource(context, intent, source);
  return fence(context, async access => {
    const existing = await restoreUnderFence(context, access); if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const latest = await currentLegacyPayee(context); verifySource(context, intent, latest); if (JSON.stringify(source) !== JSON.stringify(latest)) fail('The receiver or group changed. Review it again.');
    if (!await context.verifyFresh()) fail('Complete current account verification before changing the receiver.'); write(context);
    const current = await restoreUnderFence(context, access); if (current.kind !== 'ready') return {status: 'existing', pending: current};
    const requestKey = (context.createKey ?? (() => crypto.randomUUID()))(); if (!isId(requestKey)) fail('A secure request reference is unavailable.'); access.reserve(requestKey, revision);
    let attempt: PendingAttempt; try {attempt = await retainPending(context.identity, GUARDED_FAMILY, context.id, requestKey, PERMISSION, {...intent}, context.storage); await saveBinding(context, attempt, latest);}
    catch (error) {if (context.isCurrent()) {try {const retained = await readPending(context.identity, GUARDED_FAMILY, context.id, context.storage); if (retained?.request_key === requestKey) await clearPending(context.identity, GUARDED_FAMILY, context.id, requestKey, context.storage); await clearBinding(context, requestKey); access.clear(requestKey);} catch { /* Preserve the fence when cleanup is uncertain. */ }} throw error;}
    const pending: Extract<LegacyPayeePending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt}; if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey};
    try {const response = await context.request(`operations/payees/${context.id}`, {method: 'PATCH', body: {...intent}, idempotencyKey: requestKey}); check(context); return await finish(context, access, pending, response);}
    catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLegacyPayee(context: LegacyPayeeContext, pending: LegacyPayeePending): Promise<LegacyPayeeLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return fence(context, async access => {const saved = await restoreUnderFence(context, access); if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey) fail(); const result = await lookupUnderFence(context, saved); if (result.status === 'succeeded') await clear(context, access, saved); return result;});
}
export async function retryLegacyPayee(context: LegacyPayeeContext, pending: LegacyPayeePending): Promise<LegacyPayeeResult> {
  write(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original receiver intent is unavailable.');
  return fence(context, async access => {
    const saved = await restoreUnderFence(context, access); if (saved.kind !== 'owned' || !saved.attempt || saved.requestKey !== pending.requestKey || JSON.stringify(saved.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail();
    const status = await lookupUnderFence(context, saved); if (status.status === 'succeeded') {await clear(context, access, saved); return {status: 'succeeded', receipt: status.receipt};}
    if (status.status !== 'not_found' || !status.retryAvailable) fail('The original receiver request remains unresolved.');
    const intent = parseLegacyPayeeIntent(saved.attempt.intent), owner = await binding(context, saved.requestKey, saved.attempt), latest = await currentLegacyPayee(context); verifySource(context, intent, latest);
    if (owner.kind !== 'valid' || await sha256Text(JSON.stringify(latest)) !== owner.sourceHash) fail('The original receiver or group changed. Check the request before continuing.');
    if (!await context.verifyFresh()) fail('Complete current account verification before retrying the receiver change.'); write(context);
    try {const response = await context.request(`operations/payees/${context.id}`, {method: 'PATCH', body: {...intent}, idempotencyKey: saved.requestKey}); check(context); return await finish(context, access, saved, response);}
    catch {return {status: 'unknown', requestKey: saved.requestKey};}
  });
}
