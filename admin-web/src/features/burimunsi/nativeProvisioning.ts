import type {JsonObject} from '../../api/client';
import {clearPending, pendingAuthority, retainPending, sha256Text, type PendingAttempt} from '../core/pendingAttempt';
import type {FenceAccess} from '../operations/pendingFence';
import {parseBuriPending} from './recovery';
import {
  checkNativeAuthority, guardedProvisioningPath, listNativeAttempts, NATIVE_PROVISIONING_FAMILY as FAMILY,
  nativeSharedStorage, readNativeWriteDirectory, verifyNativeFresh, withNativeFence, type NativeAccessContext,
} from './nativeAccess';

const PERMISSION = 'admin_users.manage';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/, PIN_REASON = 'Owner approved native PIN setup', GRANT_REASON = 'Owner approved managed installation';
export const NATIVE_PROTECTED_DELIVERY_QUALIFIED = false;
export type ProvisionOperation = 'set_pin' | 'grant_installation';
type Mode = 'pin-new' | 'pin-existing' | 'grant-new' | 'grant-existing';
export interface NativeProvisionContext extends NativeAccessContext {isVisible: () => boolean; signal?: AbortSignal;}
export interface NativeProvisionSnapshot {
  operation: ProvisionOperation; collectionId: string; principalId: string; scopeVersion: number; approvalVersion: number;
  expectedAccountVersion: number; accountId: string | null; grantId: string | null; installationId: string | null;
  profile: 'staff' | 'internal_receiver' | null; expectedGrantVersion: number | null;
}
export interface NativeGrantReceipt {requestId: string; collectionId: string; installationId: string; profile: 'staff' | 'internal_receiver'; grantVersion: number; deliveryExpiresAt: number;}
export type NativeProvisionPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; operation: ProvisionOperation} | {kind: 'unbound'; requestKey: string} | {kind: 'external' | 'foreign'};
export type NativeProvisionReview = {status: 'ready'; revision: string; snapshot: NativeProvisionSnapshot} | {status: 'pending'; pending: NativeProvisionPending};
export type NativeProvisionResult = {status: 'recorded'} | {status: 'cancelled'} | {status: 'delivery'; receipt: NativeGrantReceipt} | {status: 'unknown'; requestKey: string; operation: ProvisionOperation} | {status: 'not_found'; requestKey: string; operation: ProvisionOperation} | {status: 'pending'; pending: NativeProvisionPending};
interface Binding {version: 1; authority: string; requestId: string; mode: Mode; receiptHash: string;}

function fail(message = 'The original native request could not be verified.'): never {throw new Error(message);}
function object(value: unknown): value is Record<string, unknown> {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function exact(value: Record<string, unknown>, keys: readonly string[]) {return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));}
function positive(value: unknown): value is number {return typeof value === 'number' && Number.isSafeInteger(value) && value > 0;}
function expected(value: unknown, minimum = 0): value is number {return typeof value === 'number' && Number.isSafeInteger(value) && value >= minimum && value < Number.MAX_SAFE_INTEGER;}
function mode(snapshot: NativeProvisionSnapshot): Mode {return snapshot.operation === 'set_pin' ? snapshot.accountId ? 'pin-existing' : 'pin-new' : snapshot.grantId ? 'grant-existing' : 'grant-new';}
function operation(value: Mode): ProvisionOperation {return value.startsWith('pin-') ? 'set_pin' : 'grant_installation';}
function write(context: NativeProvisionContext) {checkNativeAuthority(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('This native access change is not enabled.');}
function visible(context: NativeProvisionContext) {checkNativeAuthority(context); if (!context.isVisible() || context.signal?.aborted) fail('Return to this owner session before continuing.');}
async function bindingKey(context: NativeProvisionContext) {return `collect.admin.buri-native-provision.v1:${await sha256Text(context.collectionId)}`;}
async function readBinding(context: NativeProvisionContext): Promise<{kind: 'missing' | 'foreign'} | {kind: 'bound'; binding: Binding}> {
  const key = await bindingKey(context), authority = await pendingAuthority(context.identity); checkNativeAuthority(context);
  let raw: string | null; try {raw = nativeSharedStorage(context).getItem(key);} catch {return fail('Shared request recovery is unavailable.');}
  if (raw === null) return {kind: 'missing'}; if (raw.length > 1024) return fail();
  let value: unknown; try {value = JSON.parse(raw);} catch {return fail();}
  if (!object(value) || !exact(value, ['version', 'authority', 'requestId', 'mode', 'receiptHash']) || value.version !== 1 ||
      typeof value.authority !== 'string' || !HASH.test(value.authority) || typeof value.requestId !== 'string' || !UUID.test(value.requestId) ||
      !['pin-new', 'pin-existing', 'grant-new', 'grant-existing'].includes(String(value.mode)) || typeof value.receiptHash !== 'string' || !HASH.test(value.receiptHash)) return fail();
  if (value.authority !== authority) return {kind: 'foreign'};
  return {kind: 'bound', binding: value as unknown as Binding};
}
async function storeBinding(context: NativeProvisionContext, binding: Binding) {
  const key = await bindingKey(context), storage = nativeSharedStorage(context); checkNativeAuthority(context);
  try {if (storage.getItem(key) !== null) return fail(); const raw = JSON.stringify(binding); storage.setItem(key, raw); if (storage.getItem(key) !== raw) return fail();} catch {return fail('Shared request recovery is unavailable.');}
  checkNativeAuthority(context);
}
async function removeBinding(context: NativeProvisionContext, requestId: string) {
  const saved = await readBinding(context); if (saved.kind === 'missing') return;
  if (saved.kind !== 'bound' || saved.binding.requestId !== requestId) return fail();
  const key = await bindingKey(context), storage = nativeSharedStorage(context); checkNativeAuthority(context);
  try {storage.removeItem(key); if (storage.getItem(key) !== null) return fail();} catch {return fail('Shared request recovery is unavailable.');}
}
function projection(value: Record<string, unknown>, receiptMode: Mode) {
  const common = [value.contractVersion, value.collectionId, value.requestId, value.operation, value.principalId,
    receiptMode === 'pin-new' ? null : value.accountId, value.accountVersion, value.approvalVersion, value.scopeVersion, value.applied];
  return receiptMode.startsWith('pin-') ? common : [...common, receiptMode === 'grant-new' ? null : value.grantId,
    value.installationId, value.profile, value.grantVersion, value.active];
}
async function receiptHash(snapshot: NativeProvisionSnapshot, requestId: string): Promise<string> {
  const receiptMode = mode(snapshot);
  return sha256Text(JSON.stringify(projection({contractVersion: 1, collectionId: snapshot.collectionId, requestId, operation: snapshot.operation,
    principalId: snapshot.principalId, accountId: snapshot.accountId, accountVersion: snapshot.expectedAccountVersion + (snapshot.operation === 'set_pin' ? 1 : 0),
    approvalVersion: snapshot.approvalVersion, scopeVersion: snapshot.scopeVersion, applied: true, grantId: snapshot.grantId,
    installationId: snapshot.installationId, profile: snapshot.profile, grantVersion: snapshot.expectedGrantVersion === null ? null : snapshot.expectedGrantVersion + 1, active: true}, receiptMode)));
}
function fromAttempt(attempt: PendingAttempt): NativeProvisionSnapshot {
  const pending = parseBuriPending(attempt), i = pending.intent;
  if (pending.kind !== 'provisioning' || i.operation !== 'set_pin' && i.operation !== 'grant_installation' ||
      i.reason !== (i.operation === 'set_pin' ? PIN_REASON : GRANT_REASON) || !expected(i.scopeVersion, 1) || !expected(i.approvalVersion, 1) ||
      !expected(i.expectedAccountVersion) || !(i.accountId === null || typeof i.accountId === 'string') ||
      !(i.grantId === null || typeof i.grantId === 'string') || !(i.installationId === null || typeof i.installationId === 'string') ||
      !(i.profile === null || i.profile === 'staff' || i.profile === 'internal_receiver') || !(i.expectedGrantVersion === null || expected(i.expectedGrantVersion))) return fail();
  return {operation: i.operation, collectionId: pending.collectionId, principalId: pending.principalId, scopeVersion: i.scopeVersion, approvalVersion: i.approvalVersion,
    expectedAccountVersion: i.expectedAccountVersion, accountId: i.accountId, grantId: i.grantId, installationId: i.installationId,
    profile: i.profile, expectedGrantVersion: i.expectedGrantVersion};
}
async function restored(context: NativeProvisionContext, access: FenceAccess): Promise<NativeProvisionPending> {
  checkNativeAuthority(context); const state = access.read(), saved = await readBinding(context), attempts = await listNativeAttempts(context); checkNativeAuthority(context);
  if (state.kind === 'foreign' || saved.kind === 'foreign') return {kind: 'foreign'};
  if (state.kind === 'owned') {
    if (saved.kind !== 'bound' || saved.binding.requestId !== state.requestKey) return {kind: 'unbound', requestKey: state.requestKey};
    const same = attempts.filter(entry => entry.request_key === state.requestKey);
    if (same.length > 1 || same.some(entry => entry.family !== FAMILY)) return fail();
    if (same.length && (mode(fromAttempt(same[0])) !== saved.binding.mode || await receiptHash(fromAttempt(same[0]), state.requestKey) !== saved.binding.receiptHash)) return fail();
    return {kind: 'owned', requestKey: state.requestKey, operation: operation(saved.binding.mode)};
  }
  if (saved.kind === 'bound') {access.reserve(saved.binding.requestId, state.revision); return {kind: 'owned', requestKey: saved.binding.requestId, operation: operation(saved.binding.mode)};}
  if (attempts.length) {
    // Adopt only a verified same-tab Flutter PIN/grant intent; this creates no
    // server request and never replays the original. Other intents stay external.
    if (attempts.length !== 1 || attempts[0].family !== FAMILY) return {kind: 'external'};
    let original: NativeProvisionSnapshot; try {original = fromAttempt(attempts[0]);} catch {return {kind: 'external'};}
    const requestId = attempts[0].request_key, binding: Binding = {version: 1, authority: await pendingAuthority(context.identity), requestId, mode: mode(original), receiptHash: await receiptHash(original, requestId)};
    checkNativeAuthority(context); access.reserve(requestId, state.revision);
    try {await storeBinding(context, binding);} catch (error) {if (context.isCurrent()) {try {access.clear(requestId);} catch { /* Preserve the fence if cleanup is uncertain. */ }} throw error;}
    return {kind: 'owned', requestKey: requestId, operation: original.operation};
  }
  return {kind: 'ready', revision: state.revision};
}
async function snapshot(context: NativeProvisionContext, requested: Pick<NativeProvisionSnapshot, 'operation' | 'principalId' | 'installationId' | 'profile'>): Promise<NativeProvisionSnapshot> {
  if (!UUID.test(requested.principalId)) return fail('Select a current approved account.');
  const directory = await readNativeWriteDirectory(context);
  const account = directory.accounts.find(item => item.principalId === requested.principalId);
  if (!directory.configured || !directory.scopeVersion || !expected(directory.scopeVersion, 1) || !account || !account.approved || account.removed ||
      !expected(account.version) || !expected(account.approvalVersion, 1) || (account.accountId === null) !== (account.version === 0)) return fail('Refresh the approved account before reviewing native access.');
  if (requested.operation === 'set_pin') {
    if (requested.installationId !== null || requested.profile !== null) return fail();
    return {operation: 'set_pin', collectionId: context.collectionId, principalId: account.principalId, scopeVersion: directory.scopeVersion,
      approvalVersion: account.approvalVersion, expectedAccountVersion: account.version, accountId: account.accountId, grantId: null, installationId: null, profile: null, expectedGrantVersion: null};
  }
  if (!account.accountId || !account.active || !expected(account.version, 1) || !requested.installationId || !UUID.test(requested.installationId) ||
      requested.profile !== 'staff' && requested.profile !== 'internal_receiver' || requested.profile === 'internal_receiver' && account.role !== 'admin') return fail('Check the approved account, installation and profile.');
  const grant = directory.grants.find(item => item.installationId === requested.installationId);
  if (grant && (grant.accountId !== account.accountId || grant.profile !== requested.profile || !expected(grant.version, 1))) return fail('This installation belongs to a different account or profile.');
  return {operation: 'grant_installation', collectionId: context.collectionId, principalId: account.principalId, scopeVersion: directory.scopeVersion,
    approvalVersion: account.approvalVersion, expectedAccountVersion: account.version, accountId: account.accountId, grantId: grant?.id ?? null,
    installationId: requested.installationId, profile: requested.profile, expectedGrantVersion: grant?.version ?? 0};
}
function checkpoint(value: NativeProvisionSnapshot, requestId: string) {
  return {...value, reason: value.operation === 'set_pin' ? PIN_REASON : GRANT_REASON, requestId};
}
function requestBody(value: NativeProvisionSnapshot, requestId: string): JsonObject {
  const common = {operation: value.operation, collectionId: value.collectionId, principalId: value.principalId, scopeVersion: value.scopeVersion,
    approvalVersion: value.approvalVersion, expectedAccountVersion: value.expectedAccountVersion, reason: value.operation === 'set_pin' ? PIN_REASON : GRANT_REASON, requestId};
  return value.operation === 'set_pin' ? common : {...common, accountId: value.accountId, grantId: value.grantId, installationId: value.installationId, profile: value.profile, expectedGrantVersion: value.expectedGrantVersion};
}
async function outcome(context: NativeProvisionContext, input: unknown, binding: Binding): Promise<{status: 'not_found'} | {status: 'recorded'} | {status: 'cancelled'} | {status: 'delivery'; receipt: NativeGrantReceipt}> {
  if (!object(input) || input.contractVersion !== 1 || input.collectionId !== context.collectionId || input.requestId !== binding.requestId || typeof input.found !== 'boolean' ||
      !exact(input, ['contractVersion', 'collectionId', 'requestId', 'found', ...(input.found ? ['receipt'] : [])])) return fail();
  if (!input.found) return {status: 'not_found'};
  if (!object(input.receipt)) return fail(); const r = input.receipt;
  if (r.operation === 'cancelled') {
    if (!exact(r, ['contractVersion', 'collectionId', 'requestId', 'operation', 'applied']) || r.contractVersion !== 1 || r.collectionId !== context.collectionId || r.requestId !== binding.requestId || r.applied !== false) return fail();
    return {status: 'cancelled'};
  }
  const grant = operation(binding.mode) === 'grant_installation';
  if (!exact(r, ['contractVersion', 'collectionId', 'requestId', 'operation', 'principalId', 'accountId', 'accountVersion', 'credentialVersion', 'approvalVersion', 'scopeVersion', 'applied', ...(grant ? ['grantId', 'installationId', 'profile', 'grantVersion', 'active', 'deliveryExpiresAt'] : [])]) ||
      r.contractVersion !== 1 || r.collectionId !== context.collectionId || r.requestId !== binding.requestId || r.operation !== operation(binding.mode) || r.applied !== true ||
      typeof r.principalId !== 'string' || !UUID.test(r.principalId) || typeof r.accountId !== 'string' || !UUID.test(r.accountId) ||
      !['accountVersion', 'credentialVersion', 'approvalVersion', 'scopeVersion'].every(key => positive(r[key])) || await sha256Text(JSON.stringify(projection(r, binding.mode))) !== binding.receiptHash) return fail();
  if (!grant) return {status: 'recorded'};
  if (typeof r.grantId !== 'string' || !UUID.test(r.grantId) || typeof r.installationId !== 'string' || !UUID.test(r.installationId) ||
      r.profile !== 'staff' && r.profile !== 'internal_receiver' || !positive(r.grantVersion) || r.active !== true || !positive(r.deliveryExpiresAt)) return fail();
  return {status: 'delivery', receipt: {requestId: binding.requestId, collectionId: context.collectionId, installationId: r.installationId, profile: r.profile, grantVersion: r.grantVersion, deliveryExpiresAt: r.deliveryExpiresAt}};
}
async function lookup(context: NativeProvisionContext, binding: Binding) {
  const query = new URLSearchParams({collectionId: context.collectionId});
  const response = await context.request(`burimunsi/provisioning/requests/${binding.requestId}?${query}`); checkNativeAuthority(context);
  return outcome(context, response, binding);
}
async function finish(context: NativeProvisionContext, access: FenceAccess, binding: Binding) {
  const attempts = await listNativeAttempts(context), same = attempts.filter(entry => entry.family === FAMILY && entry.request_key === binding.requestId);
  if (same.length > 1) return fail();
  if (same.length) {
    if (mode(fromAttempt(same[0])) !== binding.mode || await receiptHash(fromAttempt(same[0]), binding.requestId) !== binding.receiptHash) return fail();
    await clearPending(context.identity, FAMILY, same[0].resource_id, binding.requestId, context.storage);
  }
  checkNativeAuthority(context); access.clear(binding.requestId); await removeBinding(context, binding.requestId);
}
export async function reviewNativeProvisioning(context: NativeProvisionContext, requested: Pick<NativeProvisionSnapshot, 'operation' | 'principalId' | 'installationId' | 'profile'>): Promise<NativeProvisionReview> {
  if (requested.operation === 'grant_installation' && !NATIVE_PROTECTED_DELIVERY_QUALIFIED) return fail('Protected installation delivery is unavailable.');
  write(context); visible(context); await verifyNativeFresh(context);
  return withNativeFence(context, async access => {
    const pending = await restored(context, access); if (pending.kind !== 'ready') return {status: 'pending', pending};
    const current = await snapshot(context, requested); write(context); visible(context); return {status: 'ready', revision: pending.revision, snapshot: current};
  });
}
/** `takePin` reads and clears the uncontrolled fields only at dispatch time. */
export async function submitNativeProvisioning(context: NativeProvisionContext, review: Extract<NativeProvisionReview, {status: 'ready'}>, takePin?: () => string): Promise<NativeProvisionResult> {
  if (review.snapshot.operation === 'grant_installation' && !NATIVE_PROTECTED_DELIVERY_QUALIFIED) return fail('Protected installation delivery is unavailable.');
  write(context); visible(context); await verifyNativeFresh(context);
  return withNativeFence(context, async access => {
    const pending = await restored(context, access); if (pending.kind !== 'ready') return {status: 'pending', pending};
    const current = await snapshot(context, review.snapshot); write(context); visible(context);
    if (JSON.stringify(current) !== JSON.stringify(review.snapshot)) return fail('The approved account or installation changed. Review it again.');
    const requestId = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(requestId)) return fail('A secure request reference is unavailable.');
    const binding: Binding = {version: 1, authority: await pendingAuthority(context.identity), requestId, mode: mode(current), receiptHash: await receiptHash(current, requestId)};
    write(context); visible(context); access.reserve(requestId, review.revision); let attempt: PendingAttempt | null = null; const secret: {pin?: string} = {};
    try {
      await storeBinding(context, binding);
      attempt = await retainPending(context.identity, FAMILY, `${context.collectionId}:${current.principalId}`, requestId, PERMISSION, checkpoint(current, requestId), context.storage);
      if (mode(fromAttempt(attempt)) !== binding.mode || await receiptHash(fromAttempt(attempt), requestId) !== binding.receiptHash) return fail();
      const attempts = await listNativeAttempts(context); if (attempts.some(entry => entry.request_key !== requestId)) return fail('Check the original group request first.');
      await verifyNativeFresh(context); write(context); visible(context);
      if (current.operation === 'set_pin') {secret.pin = takePin?.() ?? ''; if (!/^\d{4}$/.test(secret.pin) || PIN_REASON.includes(secret.pin)) return fail('Enter matching four-digit PINs.');}
      else if (takePin) return fail();
      write(context); visible(context);
    } catch (error) {
      delete secret.pin;
      if (context.isCurrent()) {try {if (attempt) await clearPending(context.identity, FAMILY, attempt.resource_id, requestId, context.storage); access.clear(requestId); await removeBinding(context, requestId);} catch { /* Preserve uncertain recovery state. */ }}
      throw error;
    }
    const body = requestBody(current, requestId); if (current.operation === 'set_pin') body.pin = secret.pin; delete secret.pin;
    try {
      const reply = await context.request(guardedProvisioningPath(), {method: 'POST', body, idempotencyKey: requestId, expectedStatus: 200, signal: context.signal});
      delete body.pin; checkNativeAuthority(context);
      const direct = await outcome(context, {contractVersion: 1, collectionId: context.collectionId, requestId, found: true, receipt: reply}, binding), found = await lookup(context, binding);
      if (direct.status !== found.status || direct.status !== (current.operation === 'set_pin' ? 'recorded' : 'delivery')) return fail();
      if (direct.status === 'delivery' && found.status === 'delivery' && JSON.stringify(direct.receipt) !== JSON.stringify(found.receipt)) return fail();
      if (found.status === 'recorded') {await finish(context, access, binding); return {status: 'recorded'};}
      if (found.status === 'delivery') return found;
      return fail();
    } catch {return {status: 'unknown', requestKey: requestId, operation: current.operation};}
    finally {delete body.pin;}
  });
}
export async function checkNativeProvisioning(context: NativeProvisionContext): Promise<NativeProvisionResult> {
  checkNativeAuthority(context); await verifyNativeFresh(context);
  return withNativeFence(context, async access => {
    const pending = await restored(context, access); if (pending.kind !== 'owned') return {status: 'pending', pending};
    const saved = await readBinding(context); if (saved.kind !== 'bound' || saved.binding.requestId !== pending.requestKey) return fail();
    const result = await lookup(context, saved.binding);
    if (result.status === 'not_found') return {status: 'not_found', requestKey: pending.requestKey, operation: pending.operation};
    if (result.status === 'recorded' || result.status === 'cancelled') {await finish(context, access, saved.binding); return {status: result.status};}
    return result;
  });
}
export async function cancelNativeProvisioning(context: NativeProvisionContext, requestKey: string, reviewedOperation: ProvisionOperation): Promise<NativeProvisionResult> {
  write(context); visible(context); await verifyNativeFresh(context);
  return withNativeFence(context, async access => {
    const pending = await restored(context, access);
    if (pending.kind !== 'owned' || pending.requestKey !== requestKey || pending.operation !== reviewedOperation) return fail('The original request changed. Check native setup again.');
    const saved = await readBinding(context); if (saved.kind !== 'bound' || saved.binding.requestId !== pending.requestKey) return fail();
    try {
      await verifyNativeFresh(context); write(context); visible(context);
      const path = guardedProvisioningPath(`burimunsi/provisioning/requests/${pending.requestKey}/cancel`);
      const reply = await context.request(path, {method: 'POST', body: {collectionId: context.collectionId}, idempotencyKey: pending.requestKey, expectedStatus: 200, signal: context.signal});
      checkNativeAuthority(context); const direct = await outcome(context, {contractVersion: 1, collectionId: context.collectionId, requestId: pending.requestKey, found: true, receipt: reply}, saved.binding), found = await lookup(context, saved.binding);
      if (direct.status !== found.status) return fail();
      if (found.status === 'cancelled' || found.status === 'recorded') {await finish(context, access, saved.binding); return {status: found.status};}
      if (direct.status === 'delivery' && found.status === 'delivery' && JSON.stringify(direct.receipt) === JSON.stringify(found.receipt)) return found;
      return fail();
    } catch {return {status: 'unknown', requestKey: pending.requestKey, operation: pending.operation};}
  });
}
/** The sink must display transiently and clear on visibility or authority loss. */
export async function openNativeDelivery(context: NativeProvisionContext, requestKey: string, show: (token: string, expiresAt: number) => void): Promise<NativeGrantReceipt> {
  if (!NATIVE_PROTECTED_DELIVERY_QUALIFIED) return fail('Protected installation delivery is unavailable.');
  write(context); visible(context); await verifyNativeFresh(context);
  return withNativeFence(context, async access => {
    const pending = await restored(context, access);
    if (pending.kind !== 'owned' || pending.operation !== 'grant_installation' || pending.requestKey !== requestKey) return fail('The original request changed. Check native setup again.');
    const saved = await readBinding(context); if (saved.kind !== 'bound' || saved.binding.requestId !== pending.requestKey) return fail();
    const found = await lookup(context, saved.binding); if (found.status !== 'delivery') return fail('Confirm the original installation grant first.');
    await verifyNativeFresh(context); write(context); visible(context);
    const r = await context.request(`burimunsi/provisioning/requests/${pending.requestKey}/delivery`, {method: 'POST', body: {collectionId: context.collectionId, installationId: found.receipt.installationId, profile: found.receipt.profile, grantVersion: found.receipt.grantVersion}, expectedStatus: 200, signal: context.signal});
    try {
      write(context); visible(context);
      if (!exact(r, ['contractVersion', 'collectionId', 'requestId', 'installationId', 'profile', 'grantVersion', 'expiresAt', 'installationToken']) ||
          r.contractVersion !== 1 || r.collectionId !== context.collectionId || r.requestId !== pending.requestKey || r.installationId !== found.receipt.installationId ||
          r.profile !== found.receipt.profile || r.grantVersion !== found.receipt.grantVersion || r.expiresAt !== found.receipt.deliveryExpiresAt ||
          !positive(r.expiresAt) || r.expiresAt <= Date.now() || typeof r.installationToken !== 'string' || !/^[a-f0-9]{64}$/.test(r.installationToken)) return fail('The protected installation delivery could not be verified.');
      show(r.installationToken, r.expiresAt); return found.receipt;
    } finally {delete r.installationToken;}
  });
}
export async function closeNativeDelivery(context: NativeProvisionContext, requestKey: string): Promise<void> {
  visible(context); await verifyNativeFresh(context);
  return withNativeFence(context, async access => {
    const pending = await restored(context, access);
    if (pending.kind !== 'owned' || pending.operation !== 'grant_installation' || pending.requestKey !== requestKey) return fail('The original request changed. Check native setup again.');
    const saved = await readBinding(context); if (saved.kind !== 'bound' || saved.binding.requestId !== pending.requestKey) return fail();
    const result = await lookup(context, saved.binding); if (result.status !== 'delivery') return fail('Confirm the original grant before closing delivery.');
    checkNativeAuthority(context); visible(context); await finish(context, access, saved.binding);
  });
}
