import {AdminRequestError, type AdminRequest, type JsonObject} from '../../api/client';
import {isObject} from '../core/contracts';
import {clearPending, pendingAuthority, retainPending, sha256Text, type PendingAttempt} from '../core/pendingAttempt';
import type {FenceAccess} from '../operations/pendingFence';
import {isBuriUuid, parseBuriDirectory} from './contracts';
import {checkNativeAuthority, listNativeAttempts, nativeSharedStorage, verifyNativeFresh, withNativeFence, type NativeRevokeContext} from './nativeRevocation';
import {prepareBuriApproval, type BuriApprovalDraft, type BuriApprovalDraftInput} from './operatorPreparation';
import {GUARDED_OPERATOR_FAMILY, parseBuriOperatorOutcome, parseBuriOperatorReceipt, parseBuriOutcome, parseBuriPending, type BuriOperatorReceipt} from './recovery';

const PATH = 'burimunsi/operators', PERMISSION = 'admin_users.manage';
const DIGEST = /^[a-f0-9]{64}$/;
interface ApprovalBinding {version: 1; authority: string; requestId: string; commandHash: string; receiptHash: string;}
type StoredApproval = {kind: 'ready'; revision: string} | {kind: 'blocked'} | {kind: 'tab'; attempt: PendingAttempt} | {kind: 'owned'; binding: ApprovalBinding; attempt?: PendingAttempt};
export type BuriApprovalResult = {status: 'ready' | 'blocked'} | {status: 'recorded' | 'unknown'; requestId: string} | {status: 'not_found'; requestId: string; canRetry: boolean};

function fail(message = 'The original operator approval could not be verified.'): never {throw new Error(message);}

export async function readBuriDirectory(request: AdminRequest, collectionId: string, negotiate = false, isCurrent = () => true) {
  const query = new URLSearchParams({collectionId});
  if (negotiate) {
    query.set('approvalContract', '2');
    try {return parseBuriDirectory(await request(`${PATH}?${query}`), collectionId, true);}
    catch (error) {
      // Older directory routes reject the new query parameter before reading.
      if (!(error instanceof AdminRequestError) || error.statusCode !== 400 || error.code !== 'invalid_request' || !isCurrent()) throw error;
      query.delete('approvalContract');
    }
  }
  return parseBuriDirectory(await request(`${PATH}?${query}`), collectionId);
}

export function canApplyBuriApproval(draft: BuriApprovalDraft): boolean {
  return isBuriUuid(draft.operator.adminId) && isBuriUuid(draft.operator.principalId);
}

function writeAllowed(context: NativeRevokeContext) {
  return context.enabled && (context.isEnabled?.() ?? true);
}
function requireWrite(context: NativeRevokeContext) {
  checkNativeAuthority(context);
  if (!writeAllowed(context)) fail('Guarded operator approvals are unavailable.');
}
function command(draft: BuriApprovalDraft, requestId: string) {
  return {requestId, collectionId: draft.collectionId, adminId: draft.operator.adminId, principalId: draft.operator.principalId,
    phone: draft.phone, role: draft.role, capabilities: draft.capabilities, active: draft.active, expectedVersion: draft.expectedVersion,
    sharedRole: draft.operator.role};
}
function commandHash(body: JsonObject) {
  return sha256Text(JSON.stringify([body.requestId, body.collectionId, body.adminId, body.principalId, body.phone, body.role, body.capabilities,
    body.active, body.expectedVersion, body.sharedRole]));
}
function receiptHash(collectionId: string, receipt: BuriOperatorReceipt) {
  return sha256Text(JSON.stringify([collectionId, receipt.contractVersion, receipt.requestId, receipt.principalId, receipt.version, receipt.active, receipt.applied]));
}

async function recoveryLocation(context: NativeRevokeContext) {
  const [scope, authority] = await Promise.all([sha256Text(context.collectionId), pendingAuthority(context.identity)]);
  checkNativeAuthority(context);
  return {key: `collect.admin.buri-approval.v2:${scope}`, storage: nativeSharedStorage(context), authority};
}

function decodeBinding(raw: string): ApprovalBinding {
  if (raw.length > 1024) return fail();
  const value: unknown = JSON.parse(raw);
  if (!isObject(value) || Object.keys(value).length !== 5 || value.version !== 1 || !isBuriUuid(value.requestId) ||
      [value.authority, value.commandHash, value.receiptHash].some(digest => typeof digest !== 'string' || !DIGEST.test(digest))) return fail();
  return value as unknown as ApprovalBinding;
}

async function restored(context: NativeRevokeContext, access: FenceAccess): Promise<StoredApproval> {
  const {key, storage, authority} = await recoveryLocation(context);
  const attempts = await listNativeAttempts(context), state = access.read();
  if (state.kind === 'foreign') return {kind: 'blocked'};
  const raw = storage.getItem(key);
  if (raw === null) {
    const [attempt] = attempts;
    if (attempts.length === 1 && attempt.family === GUARDED_OPERATOR_FAMILY &&
        (state.kind === 'empty' || state.requestKey === attempt.request_key)) return {kind: 'tab', attempt};
    return state.kind === 'empty' && attempts.length === 0 ? {kind: 'ready', revision: state.revision} : {kind: 'blocked'};
  }
  const binding = decodeBinding(raw);
  if (binding.authority !== authority || state.kind === 'owned' && state.requestKey !== binding.requestId) return {kind: 'blocked'};
  const attempt = attempts.find(entry => entry.family === GUARDED_OPERATOR_FAMILY && entry.request_key === binding.requestId);
  if (attempt && await commandHash(parseBuriPending(attempt).intent) !== binding.commandHash) return fail();
  if (state.kind === 'empty') access.reserve(binding.requestId, state.revision);
  return {kind: 'owned', binding, attempt};
}

async function finish(context: NativeRevokeContext, access: FenceAccess, binding: ApprovalBinding, attempt?: PendingAttempt) {
  if (attempt) await clearPending(context.identity, GUARDED_OPERATOR_FAMILY, attempt.resource_id, binding.requestId, context.storage);
  const {key, storage} = await recoveryLocation(context);
  if (storage.getItem(key) !== JSON.stringify(binding)) return fail();
  const state = access.read();
  if (state.kind === 'owned' && state.requestKey === binding.requestId) access.clear(binding.requestId);
  else if (state.kind !== 'empty') return fail();
  storage.removeItem(key);
  if (storage.getItem(key) !== null) return fail();
}

async function currentDraft(context: NativeRevokeContext, principalId: string, input: BuriApprovalDraftInput) {
  requireWrite(context);
  const directory = await readBuriDirectory(context.request, context.collectionId, true, context.isCurrent);
  requireWrite(context);
  if (directory.approvalContract !== 2) return fail('Guarded operator approvals are unavailable.');
  const draft = prepareBuriApproval(directory, principalId, input);
  if (!canApplyBuriApproval(draft)) return fail('This account needs a current Collect identity before changing access.');
  return draft;
}

async function readOriginal(context: NativeRevokeContext, requestId: string) {
  checkNativeAuthority(context);
  const query = new URLSearchParams({collectionId: context.collectionId});
  const value = await context.request(`${PATH}/requests/${requestId}?${query}`);
  checkNativeAuthority(context);
  return value;
}

async function lookup(context: NativeRevokeContext, binding: ApprovalBinding): Promise<boolean> {
  const value = await readOriginal(context, binding.requestId);
  const receipt = parseBuriOperatorOutcome(value, context.collectionId, binding.requestId);
  if (!receipt) return false;
  if (await receiptHash(context.collectionId, receipt) !== binding.receiptHash) return fail();
  checkNativeAuthority(context);
  return true;
}

async function dispatch(context: NativeRevokeContext, access: FenceAccess, binding: ApprovalBinding, attempt: PendingAttempt): Promise<BuriApprovalResult> {
  requireWrite(context);
  // sharedRole is retained for the reviewed boundary but is never client authority for the server.
  const payload = {...parseBuriPending(attempt).intent};
  delete payload.sharedRole;
  try {
    const value = await context.request(PATH, {method: 'POST', body: payload, idempotencyKey: binding.requestId, expectedStatus: 200});
    checkNativeAuthority(context);
    const receipt = parseBuriOperatorReceipt(value, binding.requestId);
    if (await receiptHash(context.collectionId, receipt) !== binding.receiptHash || !await lookup(context, binding)) return fail();
    await finish(context, access, binding, attempt);
    return {status: 'recorded', requestId: binding.requestId};
  } catch {return {status: 'unknown', requestId: binding.requestId};}
}

export async function applyBuriApproval(context: NativeRevokeContext, reviewed: BuriApprovalDraft): Promise<BuriApprovalResult> {
  requireWrite(context);
  if (context.collectionId !== reviewed.collectionId || !canApplyBuriApproval(reviewed)) return fail('Review an account with a current Collect identity.');
  await verifyNativeFresh(context);
  return withNativeFence(context, async access => {
    const state = await restored(context, access);
    if (state.kind !== 'ready') return {status: 'blocked'};
    const draft = await currentDraft(context, reviewed.operator.principalId, reviewed);
    if (JSON.stringify(draft) !== JSON.stringify(reviewed)) return fail('The account or approval changed. Load group access and review again.');
    const requestId = (context.createKey ?? (() => crypto.randomUUID()))();
    if (!isBuriUuid(requestId)) return fail('A secure request reference is unavailable.');
    const body = command(draft, requestId), {key, storage, authority} = await recoveryLocation(context);
    const binding: ApprovalBinding = {version: 1, authority, requestId, commandHash: await commandHash(body),
      receiptHash: await receiptHash(context.collectionId, {contractVersion: 1, requestId, principalId: body.principalId,
        version: body.expectedVersion + 1, active: body.active, applied: true})};
    requireWrite(context);
    const raw = JSON.stringify(binding);
    if (storage.getItem(key) !== null) return fail();
    let attempt: PendingAttempt | undefined;
    try {
      storage.setItem(key, raw);
      if (storage.getItem(key) !== raw) return fail();
      access.reserve(requestId, state.revision);
      attempt = await retainPending(context.identity, GUARDED_OPERATOR_FAMILY, `${context.collectionId}:${body.principalId}`, requestId, PERMISSION, body, context.storage);
      await verifyNativeFresh(context);
      requireWrite(context);
    } catch (error) {
      // The request has yet to be dispatched. Remove only this exact checkpoint.
      if (context.isCurrent()) {try {await finish(context, access, binding, attempt);} catch { /* Preserve an uncertain checkpoint. */ }}
      throw error;
    }
    return dispatch(context, access, binding, attempt);
  });
}

export async function checkBuriApproval(context: NativeRevokeContext, retryRequestId?: string): Promise<BuriApprovalResult> {
  await verifyNativeFresh(context);
  return withNativeFence(context, async access => {
    const state = await restored(context, access);
    if (state.kind === 'tab') {
      const pending = parseBuriPending(state.attempt), requestId = pending.requestId;
      if (retryRequestId !== undefined) return fail('Check the original approval before retrying.');
      try {
        const outcome = parseBuriOutcome(await readOriginal(context, requestId), pending);
        if (outcome !== 'recorded') return {status: 'not_found', requestId, canRetry: false};
        checkNativeAuthority(context);
        await clearPending(context.identity, GUARDED_OPERATOR_FAMILY, state.attempt.resource_id, requestId, context.storage);
        const fence = access.read();
        if (fence.kind === 'owned' && fence.requestKey === requestId) access.clear(requestId);
        return {status: 'recorded', requestId};
      } catch {return {status: 'unknown', requestId};}
    }
    if (state.kind !== 'owned') return {status: state.kind};
    const {binding, attempt} = state;
    if (retryRequestId !== undefined && retryRequestId !== binding.requestId) return fail('The original approval changed. Check the current request.');
    let found: boolean;
    try {found = await lookup(context, binding);}
    catch {return {status: 'unknown', requestId: binding.requestId};}
    if (found) {
      await finish(context, access, binding, attempt);
      return {status: 'recorded', requestId: binding.requestId};
    }
    if (retryRequestId === undefined) return {status: 'not_found', requestId: binding.requestId, canRetry: !!attempt && writeAllowed(context)};
    if (!attempt) return fail();
    const pending = parseBuriPending(attempt);
    const draft = await currentDraft(context, pending.principalId, pending.intent as unknown as BuriApprovalDraftInput);
    if (await commandHash(command(draft, binding.requestId)) !== binding.commandHash) return fail('The approval changed. Keep the original request reference for reconciliation.');
    await verifyNativeFresh(context);
    return dispatch(context, access, binding, attempt);
  });
}
