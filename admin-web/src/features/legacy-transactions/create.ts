/* eslint-disable no-control-regex -- Validate operator input and historical request data. */
import {z} from 'zod';
import type {AdminRequest} from '../../api/client';
import {clearPending, readEvidenceContext, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity} from '../core/pendingAttempt';
import {withPendingFence, type FenceAccess, type FenceLock} from '../operations/pendingFence';
import {loadLegacyTransaction} from './actions';
import {createSourceHash, loadCreateSource, validateCreateSource, type CreateSource} from './createSource';

const FAMILY = 'legacy-guarded-transaction-create', OLD_FAMILY = 'operating-createtransaction', RESOURCE = 'new';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const id = z.string().regex(UUID), count = z.number().int().positive().safe(), hash = z.string().regex(/^[a-f0-9]{64}$/);
const text = (min: number, max: number) => z.string().min(min).max(max).refine(value => value === value.trim() && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value));
const evidence = z.object({kind: z.enum(['operator_observation', 'payer_receipt', 'receiver_statement', 'provider_statement']), reference: text(8, 500), sha256: hash}).strict();
const intent = z.object({group_id: id, payee_id: id, expected_group_version: count, expected_payee_version: count, provider_reference: text(1, 160), amount_rwf: count, observed_at: count, evidence, reason: text(8, 1000), source_fact_id:id.optional()}).strict();
const retained = z.object({group_id: id, payee_id: id, expected_group_version: count, expected_payee_version: count, evidence_sha256: hash, request_sha256: hash,
  source_fact_id:id.optional(),source_receipt_id:id.optional(),source_snapshot_sha256:hash.optional()}).strict().refine(value=>[value.source_fact_id,value.source_receipt_id,value.source_snapshot_sha256].every(item=>item===undefined)||[value.source_fact_id,value.source_receipt_id,value.source_snapshot_sha256].every(item=>item!==undefined));
const groupRow = z.object({id, label: text(3, 160), version: count}).strict();
const payeeRow = z.object({id, label: text(2, 120), version: count, network: z.enum(['mtn_momo', 'airtel_money'])}).strict();
const receiptSchema = z.object({request_id: id, resource_type: z.literal('transactions'), resource_id: id, version: z.literal(1), status: z.literal('succeeded')}).strict();

export type CreateIntent = z.infer<typeof intent>;
export type CreateReceipt = z.infer<typeof receiptSchema>;
export interface CreateContext {request: AdminRequest; identity: PendingIdentity; permissions: readonly string[]; financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean; storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;}
export interface CreateTargets {group: {id: string; title: string; version: number}; payee: {id: string; groupId: string; label: string; version: number; network: 'mtn_momo' | 'airtel_money'; route: string};}
export type CreatePending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type CreateResult = {status: 'succeeded'; receipt: CreateReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: CreatePending};
export type CreateLookup = {status: 'succeeded'; receipt: CreateReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
function fail(message = 'The original payment request could not be verified.'): never {throw new Error(message);}
function obj(value: unknown): value is Record<string, unknown> {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function exact(value: Record<string, unknown>, keys: readonly string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function check(context: CreateContext) {
  if (!context.isCurrent() || !UUID.test(context.identity.id) || context.identity.role === 'staff' || context.financialModel !== 'transaction_journals' ||
      !['collections.read', 'receivers.read', 'payments.read', 'payments.manage', 'overview.read'].every(value => context.permissions.includes(value) && context.identity.permissions.includes(value)) ||
      !Number.isFinite(Date.parse(context.identity.expiresAt)) || Date.parse(context.identity.expiresAt) <= Date.now()) fail('Payment recording is unavailable.');
}
function write(context: CreateContext) {check(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Payment recording is not enabled.');}
export function parseCreateIntent(value: unknown): CreateIntent {
  const body = intent.parse(value); if (body.observed_at > Math.floor(Date.now() / 1000) + 60) fail('The observation time is in the future.'); return body;
}
async function checkpoint(input: unknown, source?:CreateSource|null) {
  const body = parseCreateIntent(input), request_sha256 = await sha256Text(JSON.stringify(body));
  if(Boolean(body.source_fact_id)!==Boolean(source)||source&&body.source_fact_id!==source.factId)fail('Select the exact preserved source.');
  return {group_id: body.group_id, payee_id: body.payee_id, expected_group_version: body.expected_group_version, expected_payee_version: body.expected_payee_version, evidence_sha256: body.evidence.sha256, request_sha256,
    ...(source?{source_fact_id:source.factId,source_receipt_id:source.receiptId,source_snapshot_sha256:await createSourceHash(source)}:{})};
}
function verifyAttempt(value: PendingAttempt) {
  if (value.family !== FAMILY || value.resource_id !== RESOURCE || value.permission !== 'payments.manage' || !UUID.test(value.request_key)) fail(); return retained.parse(value.intent);
}
export async function verifyCreateReentry(context: CreateContext, saved: PendingAttempt, input: unknown, source?:CreateSource|null) {
  const original = verifyAttempt(saved), body = parseCreateIntent(input), candidate = await checkpoint(body,source); check(context);
  if (JSON.stringify(original) !== JSON.stringify(candidate)) fail('The re-entered payment request does not match the original.'); return body;
}
export async function recoverCreateSource(context:CreateContext,saved:PendingAttempt):Promise<CreateSource|null>{
  const original=verifyAttempt(saved);if(!original.source_fact_id)return null;
  const source=await loadCreateSource(context,original.source_receipt_id!);check(context);
  if(source.factId!==original.source_fact_id||await createSourceHash(source)!==original.source_snapshot_sha256)fail('The preserved source changed.');return source;
}
function lookupRows(value: unknown, type: 'groups' | 'payees') {
  if (!obj(value) || !exact(value, ['rows']) || !Array.isArray(value.rows) || value.rows.length > 100) fail('The lookup could not be verified.');
  const rows = type === 'groups' ? value.rows.map(row => groupRow.parse(row)) : value.rows.map(row => payeeRow.parse(row));
  if (new Set(rows.map(row => row.id)).size !== rows.length) fail('The lookup could not be verified.'); return rows;
}
export async function searchCreateGroups(context: CreateContext, search: string) {
  write(context); if (search.length > 200 || /[\x00-\x1f\x7f]/.test(search)) fail('Enter a valid search.');
  const rows = lookupRows(await context.request(`operations/lookups?${new URLSearchParams({kind: 'groups', search: search.trim(), limit: '100'})}`), 'groups'); check(context); return rows as z.infer<typeof groupRow>[];
}
export async function searchCreatePayees(context: CreateContext, groupId: string) {
  write(context); if (!UUID.test(groupId)) fail();
  const rows = lookupRows(await context.request(`operations/lookups?${new URLSearchParams({kind: 'payees', search: '', limit: '100', group_id: groupId})}`), 'payees'); check(context); return rows as z.infer<typeof payeeRow>[];
}
function detail(value: unknown, type: 'groups' | 'payees', resourceId: string, actor: string) {
  if (!obj(value) || !exact(value, ['resource_type', 'resource', 'current_actor_id', 'can_manage', 'related', 'related_pages', 'related_truncated']) || value.resource_type !== type || value.current_actor_id !== actor || value.can_manage !== true ||
      !obj(value.resource) || value.resource.id !== resourceId || !obj(value.related) || !obj(value.related_pages) || typeof value.related_truncated !== 'boolean') fail('The group or receiver could not be verified.'); return value.resource;
}
export async function loadCreateTargets(context: CreateContext, groupId: string, payeeId: string): Promise<CreateTargets> {
  check(context); if (!UUID.test(groupId) || !UUID.test(payeeId)) fail();
  const [groupBody, payeeBody] = await Promise.all([context.request(`operations/groups/${groupId}`), context.request(`operations/payees/${payeeId}`)]); check(context);
  const group = detail(groupBody, 'groups', groupId, context.identity.id), payee = detail(payeeBody, 'payees', payeeId, context.identity.id);
  if (group.status !== 'active' || group.country_code !== 'RW' || group.currency !== 'RWF' || !text(3, 160).safeParse(group.title).success || !count.safeParse(group.version).success ||
      payee.group_id !== groupId || payee.status !== 'active' || !text(2, 120).safeParse(payee.label).success || !count.safeParse(payee.version).success ||
      !['mtn_momo', 'airtel_money'].includes(String(payee.network)) || typeof payee.momo_number_or_code !== 'string' || !/^[0-9]{4,12}$/.test(payee.momo_number_or_code)) fail('The active group or receiver could not be verified.');
  return {group: {id: groupId, title: String(group.title), version: group.version as number}, payee: {id: payeeId, groupId, label: String(payee.label), version: payee.version as number, network: payee.network as CreateTargets['payee']['network'], route: payee.momo_number_or_code}};
}
export async function loadCreateGroup(context:CreateContext,groupId:string){
  write(context);if(!UUID.test(groupId))fail('The selected group could not be verified.');
  const group=detail(await context.request(`operations/groups/${groupId}`),'groups',groupId,context.identity.id);check(context);
  if(group.status!=='active'||group.country_code!=='RW'||group.currency!=='RWF'||!text(3,160).safeParse(group.title).success||!count.safeParse(group.version).success)fail('The selected group could not be verified.');
  return {id:groupId,label:String(group.title),version:group.version as number};
}
export function validateCreateTargets(targets: CreateTargets, body: CreateIntent) {
  if (targets.group.id !== body.group_id || targets.payee.id !== body.payee_id || targets.payee.groupId !== body.group_id || targets.group.version !== body.expected_group_version || targets.payee.version !== body.expected_payee_version) fail('The group or receiver changed.');
}
const browserLock: FenceLock = async (name, task) => {
  if (!navigator.locks) fail('Protected request recovery is unavailable.');
  const options: LockOptions = name === 'collect.admin.pending-fence.v2' ? {mode: 'exclusive'} : {mode: 'exclusive', ifAvailable: true};
  return navigator.locks.request(name, options, held => held ? task() : fail('Another payment request is in progress.'));
};
async function scoped<T>(context: CreateContext, task: () => Promise<T>): Promise<T> {return (context.lock ?? browserLock)('collect.admin.legacy-transaction-create', async () => {check(context); return task();});}
async function fence<T>(context: CreateContext, task: (access: FenceAccess) => Promise<T>) {return withPendingFence({identity: context.identity, family: FAMILY, resourceId: RESOURCE, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock ?? browserLock}, task);}
export async function oldCreateAttempt(context: CreateContext) {
  check(context); const saved = await readPending(context.identity, OLD_FAMILY, RESOURCE, context.storage), orphan = await readEvidenceContext(context.identity, context.storage); check(context);
  if (saved && (saved.permission !== 'payments.manage' || !UUID.test(saved.request_key))) fail();
  return {saved, orphan: !!orphan && !saved};
}
async function noOld(context: CreateContext) {const value = await oldCreateAttempt(context); if (value.saved || value.orphan) fail('An earlier payment request needs recovery.');}
async function restoreUnder(context: CreateContext, access: FenceAccess): Promise<CreatePending> {
  check(context); const shared = access.read(); if (shared.kind === 'foreign') return {kind: 'foreign'};
  const saved = await readPending(context.identity, FAMILY, RESOURCE, context.storage); if (saved) verifyAttempt(saved); check(context);
  if (shared.kind === 'owned') {if (saved && saved.request_key !== shared.requestKey) fail(); return {kind: 'owned', requestKey: shared.requestKey, attempt: saved};}
  if (saved) {access.reserve(saved.request_key, shared.revision); return {kind: 'owned', requestKey: saved.request_key, attempt: saved};} return {kind: 'ready', revision: shared.revision};
}
export async function restoreCreate(context: CreateContext) {check(context); return fence(context, access => restoreUnder(context, access));}
async function clearVerified(context: CreateContext, pending: Extract<CreatePending, {kind: 'owned'}>) {
  await fence(context, async access => {const saved = await restoreUnder(context, access);
    if (saved.kind !== 'owned' || !saved.attempt || !pending.attempt || saved.requestKey !== pending.requestKey || JSON.stringify(verifyAttempt(saved.attempt)) !== JSON.stringify(verifyAttempt(pending.attempt))) fail();
    await clearPending(context.identity, FAMILY, RESOURCE, saved.requestKey, context.storage); check(context); access.clear(saved.requestKey);});
}
async function scopeReceipt(context: CreateContext, key: string, receipt: CreateReceipt) {
  for (let offset = 0; offset < 10000; offset += 100) {
    const data = await context.request(`operations/requests?limit=100&offset=${offset}`); check(context);
    if (!exact(data, ['total', 'rows']) || !Number.isSafeInteger(data.total) || Number(data.total) < 0 || !Array.isArray(data.rows) || data.rows.length !== Math.max(0, Math.min(100, Number(data.total) - offset)) || data.rows.some(row => !obj(row))) fail();
    const row = data.rows.find(value => value.idempotency_key === key);
    if (row) {if (row.id !== receipt.request_id || row.scope !== 'transactions.post' || row.status !== 'succeeded' || JSON.stringify(receiptSchema.parse(row.receipt)) !== JSON.stringify(receipt)) fail(); return;}
    if (offset + data.rows.length >= Number(data.total)) break;
  }
  fail('The original payment request is not in bounded actor history.');
}
async function validateReceipt(context: CreateContext, input: unknown, saved: PendingAttempt | null) {
  if (!saved) fail('The original payment request identity is unavailable.');
  const result = receiptSchema.parse(input), original = verifyAttempt(saved);
  const transaction = await loadLegacyTransaction({id: result.resource_id, mode: 'add', request: context.request, identity: context.identity, permissions: context.permissions, financialModel: context.financialModel, enabled: false, isCurrent: context.isCurrent}); check(context);
  if (transaction.groupId !== original.group_id || transaction.payeeId !== original.payee_id || transaction.recordedBy !== context.identity.id || transaction.referenceSourceFactId !== (original.source_fact_id??null) ||
      !transaction.evidence.some(row => row.sha256 === original.evidence_sha256 && row.recorded_by_admin_id === context.identity.id)) fail('The original payment evidence could not be verified.');
  return result;
}
async function lookup(context: CreateContext, pending: Extract<CreatePending, {kind: 'owned'}>): Promise<CreateLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) return {status: 'not_found', retryAvailable: !!pending.attempt};
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail();
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail(); const value = await validateReceipt(context, body.receipt, pending.attempt); if (body.request_id !== value.request_id) fail();
  await scopeReceipt(context, pending.requestKey, value); return {status: 'succeeded', receipt: value};
}
async function settle(context: CreateContext, pending: Extract<CreatePending, {kind: 'owned'}>, value: unknown): Promise<CreateResult> {
  const direct = await validateReceipt(context, value, pending.attempt), original = await lookup(context, pending);
  if (original.status !== 'succeeded' || JSON.stringify(original.receipt) !== JSON.stringify(direct)) fail();
  await clearVerified(context, pending); return {status: 'succeeded', receipt: direct};
}
export async function checkCreate(context: CreateContext, pending: CreatePending): Promise<CreateLookup> {
  check(context); if (pending.kind !== 'owned') fail(); return scoped(context, async () => {
    const saved = await restoreCreate(context); if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey) fail();
    const result = await lookup(context, saved); if (result.status === 'succeeded') await clearVerified(context, saved); return result;
  });
}
/** Old Flutter/canonical checkpoints are lookup-only and are never cleared here. */
export async function checkOldCreate(context: CreateContext, previous: PendingAttempt): Promise<CreateLookup> {
  const old = await oldCreateAttempt(context); if (!old.saved || old.saved.request_key !== previous.request_key) fail();
  const body = await context.request(`operations/requests/${old.saved.request_key}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) return {status: 'not_found', retryAvailable: false};
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail();
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail(); const value = receiptSchema.parse(body.receipt); if (body.request_id !== value.request_id) fail();
  await scopeReceipt(context, previous.request_key, value); return {status: 'succeeded', receipt: value};
}
export async function submitCreate(context: CreateContext, input: unknown, reviewed: CreateTargets, revision: string, reviewedSource?:CreateSource|null): Promise<CreateResult> {
  write(context); const body = parseCreateIntent(input); validateCreateTargets(reviewed, body);
  return scoped(context, async () => {
    await noOld(context); const latest = await loadCreateTargets(context, body.group_id, body.payee_id);
    if (JSON.stringify(latest) !== JSON.stringify(reviewed)) fail('The group or receiver changed.'); validateCreateTargets(latest, body); write(context);
    if(body.source_fact_id){if(!reviewedSource)fail('Select the exact preserved source.');const current=await loadCreateSource(context,reviewedSource.receiptId);
      if(await createSourceHash(current)!==await createSourceHash(reviewedSource))fail('The preserved source changed.');validateCreateSource(current,body,latest);}
    else if(reviewedSource)fail('The preserved source was not included in the request.');
    const safe = await checkpoint(body,reviewedSource); write(context);
    const saved = await fence(context, async access => {
      const state = await restoreUnder(context, access); if (state.kind !== 'ready') return {kind: 'existing' as const, pending: state};
      write(context); const key = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(key)) fail(); access.reserve(key, revision);
      let attempt: PendingAttempt;
      try {attempt = await retainPending(context.identity, FAMILY, RESOURCE, key, 'payments.manage', safe, context.storage); verifyAttempt(attempt);}
      catch (error) {if (context.isCurrent()) {try {const pending = await readPending(context.identity, FAMILY, RESOURCE, context.storage); if (pending?.request_key === key) await clearPending(context.identity, FAMILY, RESOURCE, key, context.storage); access.clear(key);} catch { /* Preserve the fence if cleanup is uncertain. */ }} throw error;}
      return {kind: 'new' as const, pending: {kind: 'owned' as const, requestKey: key, attempt}};
    });
    if (saved.kind === 'existing') return {status: 'existing', pending: saved.pending}; const pending = saved.pending;
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey: pending.requestKey};
    try {const value = await context.request('operations/transactions', {method: 'POST', body: {...body}, idempotencyKey: pending.requestKey}); check(context); return await settle(context, pending, value);}
    catch {return {status: 'unknown', requestKey: pending.requestKey};}
  });
}
export async function retryCreate(context: CreateContext, pending: CreatePending, input: unknown, reviewed: CreateTargets, reviewedSource?:CreateSource|null): Promise<CreateResult> {
  write(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original payment request identity is unavailable.'); const original = verifyAttempt(pending.attempt);
  return scoped(context, async () => {
    const saved = await restoreCreate(context); if (saved.kind !== 'owned' || !saved.attempt || saved.requestKey !== pending.requestKey || JSON.stringify(verifyAttempt(saved.attempt)) !== JSON.stringify(original)) fail();
    const prior = await lookup(context, saved); if (prior.status === 'succeeded') {await clearVerified(context, saved); return {status: 'succeeded', receipt: prior.receipt};}
    if (prior.status !== 'not_found') fail('The original payment request is unresolved.');
    await noOld(context); const body = await verifyCreateReentry(context, saved.attempt, input,reviewedSource), latest = await loadCreateTargets(context, body.group_id, body.payee_id);
    if (JSON.stringify(latest) !== JSON.stringify(reviewed)) fail('The group or receiver changed.'); validateCreateTargets(latest, body); write(context);
    if(body.source_fact_id){if(!reviewedSource)fail('Select the exact preserved source.');const current=await loadCreateSource(context,reviewedSource.receiptId);
      if(await createSourceHash(current)!==await createSourceHash(reviewedSource))fail('The preserved source changed.');validateCreateSource(current,body,latest);write(context);}
    try {const value = await context.request('operations/transactions', {method: 'POST', body: {...body}, idempotencyKey: saved.requestKey}); check(context); return await settle(context, saved, value);}
    catch {return {status: 'unknown', requestKey: saved.requestKey};}
  });
}
