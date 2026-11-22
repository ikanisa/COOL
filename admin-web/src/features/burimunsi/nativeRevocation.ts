import type {JsonObject} from '../../api/client';
import {clearPending, pendingAuthority, retainPending, sha256Text, type PendingAttempt} from '../core/pendingAttempt';
import type {FenceAccess} from '../operations/pendingFence';
import {
  checkNativeAuthority as check, guardedProvisioningPath, listNativeAttempts as groupAttempts,
  NATIVE_PROVISIONING_FAMILY as FAMILY, nativeSharedStorage as shared,
  readNativeWriteDirectory, verifyNativeFresh as fresh, withNativeFence as fence, type NativeAccessContext,
} from './nativeAccess';
import {parseBuriPending} from './recovery';

const PERMISSION = 'admin_users.manage';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/, REASON = 'Owner revoked native installation';
export type NativeRevokeContext = NativeAccessContext;
export interface NativeRevokeSnapshot {
  collectionId: string; principalId: string; scopeVersion: number; approvalVersion: number; expectedAccountVersion: number;
  accountId: string; grantId: string; installationId: string; profile: 'staff' | 'internal_receiver'; expectedGrantVersion: number;
}
export type NativeRevokePending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string} | {kind: 'unbound'; requestKey: string} | {kind: 'external' | 'foreign'};
export type NativeRevokeReview = {status: 'ready'; revision: string; snapshot: NativeRevokeSnapshot} | {status: 'pending'; pending: NativeRevokePending};
export type NativeRevokeResult = {status: 'recorded'} | {status: 'cancelled'} | {status: 'unknown'; requestKey: string} | {status: 'not_found'; requestKey: string} | {status: 'pending'; pending: NativeRevokePending};
interface Binding {version: 1; authority: string; requestId: string; receiptHash: string;}

function fail(message = 'The original native request could not be verified.'): never {throw new Error(message);}
function object(value: unknown): value is Record<string, unknown> {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function exact(value: Record<string, unknown>, keys: readonly string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function version(value: unknown): value is number {return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 && value < Number.MAX_SAFE_INTEGER;}
function receiptVersion(value: unknown): value is number {return typeof value === 'number' && Number.isSafeInteger(value) && value > 0;}
function write(context: NativeRevokeContext) {check(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Native installation changes are not enabled.');}
async function bindingKey(context: NativeRevokeContext) {return `collect.admin.buri-native-revoke.v1:${await sha256Text(context.collectionId)}`;}
async function readBinding(context: NativeRevokeContext): Promise<{kind: 'missing' | 'foreign'} | {kind: 'bound'; binding: Binding}> {
  const key = await bindingKey(context), authority = await pendingAuthority(context.identity); check(context);
  let raw: string | null; try {raw = shared(context).getItem(key);} catch {return fail('Shared request recovery is unavailable.');}
  if (raw === null) return {kind: 'missing'};
  if (raw.length > 1024) return fail();
  let parsed: unknown; try {parsed = JSON.parse(raw);} catch {return fail();}
  if (!object(parsed) || !exact(parsed, ['version', 'authority', 'requestId', 'receiptHash']) || parsed.version !== 1 ||
      typeof parsed.authority !== 'string' || !HASH.test(parsed.authority) || typeof parsed.requestId !== 'string' || !UUID.test(parsed.requestId) ||
      typeof parsed.receiptHash !== 'string' || !HASH.test(parsed.receiptHash)) return fail();
  if (parsed.authority !== authority) return {kind: 'foreign'};
  return {kind: 'bound', binding: parsed as unknown as Binding};
}
async function storeBinding(context: NativeRevokeContext, binding: Binding) {
  const key = await bindingKey(context), storage = shared(context); check(context);
  try {if (storage.getItem(key) !== null) return fail(); const raw = JSON.stringify(binding); storage.setItem(key, raw); if (storage.getItem(key) !== raw) return fail();} catch {return fail('Shared request recovery is unavailable.');}
  check(context);
}
async function removeBinding(context: NativeRevokeContext, key: string) {
  const existing = await readBinding(context); if (existing.kind === 'missing') return;
  if (existing.kind !== 'bound' || existing.binding.requestId !== key) return fail();
  const name = await bindingKey(context), storage = shared(context); check(context);
  try {storage.removeItem(name); if (storage.getItem(name) !== null) return fail();} catch {return fail('Shared request recovery is unavailable.');}
}
function projection(value: Record<string, unknown>) {
  return [value.contractVersion, value.collectionId, value.requestId, value.operation, value.principalId, value.accountId,
    value.accountVersion, value.approvalVersion, value.scopeVersion, value.applied, value.grantId, value.installationId,
    value.profile, value.grantVersion, value.active, value.deliveryExpiresAt];
}
async function expectedHash(snapshot: NativeRevokeSnapshot, requestId: string) {
  return sha256Text(JSON.stringify(projection({contractVersion: 1, collectionId: snapshot.collectionId, requestId, operation: 'revoke_installation',
    principalId: snapshot.principalId, accountId: snapshot.accountId, accountVersion: snapshot.expectedAccountVersion,
    approvalVersion: snapshot.approvalVersion, scopeVersion: snapshot.scopeVersion, applied: true, grantId: snapshot.grantId,
    installationId: snapshot.installationId, profile: snapshot.profile, grantVersion: snapshot.expectedGrantVersion + 1,
    active: false, deliveryExpiresAt: null})));
}
function snapshotFromAttempt(attempt: PendingAttempt): NativeRevokeSnapshot {
  const pending = parseBuriPending(attempt), i = pending.intent;
  if (pending.kind !== 'provisioning' || i.operation !== 'revoke_installation' || i.reason !== REASON ||
      typeof i.accountId !== 'string' || typeof i.grantId !== 'string' || typeof i.installationId !== 'string' ||
      i.profile !== 'staff' && i.profile !== 'internal_receiver' || !version(i.scopeVersion) || !version(i.approvalVersion) ||
      !version(i.expectedAccountVersion) || !version(i.expectedGrantVersion)) return fail();
  return {collectionId: pending.collectionId, principalId: pending.principalId, scopeVersion: i.scopeVersion,
    approvalVersion: i.approvalVersion, expectedAccountVersion: i.expectedAccountVersion, accountId: i.accountId,
    grantId: i.grantId, installationId: i.installationId, profile: i.profile, expectedGrantVersion: i.expectedGrantVersion};
}
async function restored(context: NativeRevokeContext, access: FenceAccess): Promise<NativeRevokePending> {
  check(context); const state = access.read(), binding = await readBinding(context), attempts = await groupAttempts(context); check(context);
  if (state.kind === 'foreign' || binding.kind === 'foreign') return {kind: 'foreign'};
  if (state.kind === 'owned') {
    if (binding.kind !== 'bound' || binding.binding.requestId !== state.requestKey) return {kind: 'unbound', requestKey: state.requestKey};
    const own = attempts.filter(entry => entry.request_key === state.requestKey);
    if (own.length > 1 || own.some(entry => entry.family !== FAMILY || entry.resource_id !== `${context.collectionId}:${parseBuriPending(entry).principalId}`)) return fail();
    if (own.length === 1 && await expectedHash(snapshotFromAttempt(own[0]), state.requestKey) !== binding.binding.receiptHash) return fail();
    return {kind: 'owned', requestKey: state.requestKey};
  }
  if (binding.kind === 'bound') {access.reserve(binding.binding.requestId, state.revision); return {kind: 'owned', requestKey: binding.binding.requestId};}
  if (attempts.length) return {kind: 'external'};
  return {kind: 'ready', revision: state.revision};
}
async function snapshot(context: NativeRevokeContext, grantId: string): Promise<NativeRevokeSnapshot> {
  if (!UUID.test(grantId)) return fail('Select a current installation.');
  const directory = await readNativeWriteDirectory(context);
  const grant = directory.grants.find(item => item.id === grantId), account = directory.accounts.find(item => item.accountId !== null && item.accountId === grant?.accountId);
  if (!grant || !grant.active || !account || !account.accountId || !directory.scopeVersion || !version(directory.scopeVersion) ||
      !version(account.version) || !version(account.approvalVersion) || !version(grant.version)) return fail('Refresh the recorded installation and custodian before reviewing it.');
  return {collectionId: context.collectionId, principalId: account.principalId, scopeVersion: directory.scopeVersion,
    approvalVersion: account.approvalVersion, expectedAccountVersion: account.version, accountId: account.accountId,
    grantId: grant.id, installationId: grant.installationId, profile: grant.profile, expectedGrantVersion: grant.version};
}
function checkpoint(review: NativeRevokeSnapshot, requestId: string) {
  return {...review, operation: 'revoke_installation', reason: REASON, requestId};
}
async function outcome(context: NativeRevokeContext, body: unknown, binding: Binding): Promise<'not_found' | 'recorded' | 'cancelled'> {
  if (!object(body) || body.contractVersion !== 1 || body.collectionId !== context.collectionId || body.requestId !== binding.requestId || typeof body.found !== 'boolean' ||
      !exact(body, ['contractVersion', 'collectionId', 'requestId', 'found', ...(body.found ? ['receipt'] : [])])) return fail();
  if (!body.found) return 'not_found';
  if (!object(body.receipt)) return fail(); const receipt = body.receipt;
  if (receipt.operation === 'cancelled') {
    if (!exact(receipt, ['contractVersion', 'collectionId', 'requestId', 'operation', 'applied']) || receipt.contractVersion !== 1 ||
        receipt.collectionId !== context.collectionId || receipt.requestId !== binding.requestId || receipt.applied !== false) return fail();
    return 'cancelled';
  }
  if (!exact(receipt, ['contractVersion', 'collectionId', 'requestId', 'operation', 'principalId', 'accountId', 'accountVersion', 'credentialVersion', 'approvalVersion', 'scopeVersion', 'applied', 'grantId', 'installationId', 'profile', 'grantVersion', 'active', 'deliveryExpiresAt']) ||
      receipt.contractVersion !== 1 || receipt.collectionId !== context.collectionId || receipt.requestId !== binding.requestId || receipt.operation !== 'revoke_installation' ||
      !['principalId', 'accountId', 'grantId', 'installationId'].every(key => typeof receipt[key] === 'string' && UUID.test(receipt[key] as string)) ||
      !['accountVersion', 'credentialVersion', 'approvalVersion', 'scopeVersion', 'grantVersion'].every(key => receiptVersion(receipt[key])) ||
      !['staff', 'internal_receiver'].includes(String(receipt.profile)) || receipt.applied !== true || receipt.active !== false || receipt.deliveryExpiresAt !== null ||
      await sha256Text(JSON.stringify(projection(receipt))) !== binding.receiptHash) return fail();
  return 'recorded';
}
async function lookup(context: NativeRevokeContext, binding: Binding) {
  const query = new URLSearchParams({collectionId: context.collectionId});
  const result = await context.request(`burimunsi/provisioning/requests/${binding.requestId}?${query}`); check(context);
  return outcome(context, result, binding);
}
async function finish(context: NativeRevokeContext, access: FenceAccess, binding: Binding) {
  const attempts = await groupAttempts(context), matching = attempts.filter(entry => entry.family === FAMILY && entry.request_key === binding.requestId);
  if (matching.length > 1) return fail();
  if (matching.length === 1) {
    const parsed = parseBuriPending(matching[0]);
    if (await expectedHash(snapshotFromAttempt(matching[0]), binding.requestId) !== binding.receiptHash) return fail();
    await clearPending(context.identity, FAMILY, matching[0].resource_id, binding.requestId, context.storage);
    if (parsed.collectionId !== context.collectionId) return fail();
  }
  check(context); access.clear(binding.requestId); await removeBinding(context, binding.requestId);
}
export async function reviewNativeRevocation(context: NativeRevokeContext, grantId: string): Promise<NativeRevokeReview> {
  write(context); await fresh(context);
  return fence(context, async access => {
    const pending = await restored(context, access); if (pending.kind !== 'ready') return {status: 'pending', pending};
    const current = await snapshot(context, grantId); write(context); return {status: 'ready', revision: pending.revision, snapshot: current};
  });
}
export async function submitNativeRevocation(context: NativeRevokeContext, review: Extract<NativeRevokeReview, {status: 'ready'}>): Promise<NativeRevokeResult> {
  write(context); await fresh(context);
  return fence(context, async access => {
    const pending = await restored(context, access); if (pending.kind !== 'ready') return {status: 'pending', pending};
    const current = await snapshot(context, review.snapshot.grantId); write(context);
    if (JSON.stringify(current) !== JSON.stringify(review.snapshot)) return fail('The installation changed. Review it again.');
    const requestId = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(requestId)) return fail('A secure request reference is unavailable.');
    const binding: Binding = {version: 1, authority: await pendingAuthority(context.identity), requestId, receiptHash: await expectedHash(current, requestId)};
    write(context); access.reserve(requestId, review.revision);
    let attempt: PendingAttempt | null = null;
    try {
      await storeBinding(context, binding);
      attempt = await retainPending(context.identity, FAMILY, `${context.collectionId}:${current.principalId}`, requestId, PERMISSION, checkpoint(current, requestId), context.storage);
      if (await expectedHash(snapshotFromAttempt(attempt), requestId) !== binding.receiptHash) return fail();
      const entries = await groupAttempts(context); if (entries.some(entry => entry.request_key !== requestId)) return fail('Check the original group request first.');
      await fresh(context); write(context);
    } catch (error) {
      // No request has been sent yet; remove only data that still matches this key.
      if (context.isCurrent()) {try {if (attempt) await clearPending(context.identity, FAMILY, attempt.resource_id, requestId, context.storage); access.clear(requestId); await removeBinding(context, requestId);} catch { /* Retain any uncertain fence for recovery. */ }}
      throw error;
    }
    try {
      const body: JsonObject = {...checkpoint(current, requestId)};
      const reply = await context.request(guardedProvisioningPath(), {method: 'POST', body, idempotencyKey: requestId, expectedStatus: 200});
      check(context); const direct = await outcome(context, {contractVersion: 1, collectionId: context.collectionId, requestId, found: true, receipt: reply}, binding);
      if (direct !== 'recorded' || await lookup(context, binding) !== direct) return fail();
      await finish(context, access, binding); return {status: 'recorded'};
    } catch {return {status: 'unknown', requestKey: requestId};}
  });
}
export async function checkNativeRevocation(context: NativeRevokeContext): Promise<NativeRevokeResult> {
  check(context); await fresh(context);
  return fence(context, async access => {
    const pending = await restored(context, access); if (pending.kind !== 'owned') return {status: 'pending', pending};
    const saved = await readBinding(context); if (saved.kind !== 'bound' || saved.binding.requestId !== pending.requestKey) return fail();
    const found = await lookup(context, saved.binding);
    if (found !== 'not_found') {await finish(context, access, saved.binding); return {status: found};}
    return {status: 'not_found', requestKey: pending.requestKey};
  });
}
export async function cancelNativeRevocation(context: NativeRevokeContext, requestKey: string): Promise<NativeRevokeResult> {
  write(context); await fresh(context);
  return fence(context, async access => {
    const pending = await restored(context, access);
    if (pending.kind !== 'owned' || pending.requestKey !== requestKey) return fail('The original request changed. Check native revocation again.');
    const saved = await readBinding(context); if (saved.kind !== 'bound' || saved.binding.requestId !== pending.requestKey) return fail();
    try {
      await fresh(context); write(context);
      const path = `burimunsi/provisioning/requests/${saved.binding.requestId}/cancel`;
      const reply = await context.request(guardedProvisioningPath(path), {method: 'POST', body: {collectionId: context.collectionId}, idempotencyKey: saved.binding.requestId, expectedStatus: 200});
      check(context); const direct = await outcome(context, {contractVersion: 1, collectionId: context.collectionId, requestId: saved.binding.requestId, found: true, receipt: reply}, saved.binding);
      if (direct === 'not_found' || await lookup(context, saved.binding) !== direct) return fail();
      await finish(context, access, saved.binding); return {status: direct};
    } catch {return {status: 'unknown', requestKey: pending.requestKey};}
  });
}
