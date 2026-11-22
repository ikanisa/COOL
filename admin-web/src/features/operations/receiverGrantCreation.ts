/* eslint-disable no-control-regex -- Reject controls in operator and backend text. */
import {z} from 'zod';
import type {AdminRequest} from '../../api/client';
import {parseCorePage} from '../core/contracts';
import type {PendingAttempt} from '../core/pendingAttempt';
import type {DataRow} from '../core/types';
import {parseGatewayDetail, parseGatewayPage, parseGrantDetail, type GatewayDevice} from './contracts';
import type {FenceLock} from './pendingFence';
import {operationRequestCustody, type OperationPending, type OperationRequestContext} from './operationRequestCustody';

const FAMILY = 'receiver-capture-grant', RESOURCE = 'new', PERMISSION = 'gateway.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const text = (min: number, max: number) => z.string().min(min).max(max).refine(value => value === value.trim() && !/[\x00-\x1f\x7f]/.test(value));
const identifier = z.string().regex(UUID), version = z.number().int().min(1).max(Number.MAX_SAFE_INTEGER);
const intentSchema = z.object({device_id: identifier, expected_device_version: version, payee_id: identifier, expected_payee_version: version, reason: text(8, 1000)}).strict();
const payeeSchema = z.object({id: identifier, group_id: identifier, label: text(2, 120), network: z.enum(['mtn_momo', 'airtel_money']), momo_number_or_code: z.string().regex(/^[0-9]{4,12}$/), status: z.literal('active'), version}).passthrough();
const receiptSchema = z.object({request_id: identifier, resource_type: z.literal('receiver_capture_grants'), resource_id: identifier, version: z.literal(1), status: z.literal('succeeded')}).strict();
export type GrantCreateIntent = z.infer<typeof intentSchema>;
export type GrantPayee = z.infer<typeof payeeSchema>;
export interface GrantTargets {device: GatewayDevice; payee: GrantPayee;}
export interface GrantCreateContext extends OperationRequestContext {
  request: AdminRequest; financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; enabled: boolean;
  isEnabled?: () => boolean;
}
export type GrantCreatePending = OperationPending;
export interface GrantCreateReceipt {requestId: string; grantId: string; version: 1;}
export type GrantCreateResult = {status: 'succeeded'; receipt: GrantCreateReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: GrantCreatePending};
export type GrantCreateLookup = {status: 'succeeded'; receipt: GrantCreateReceipt} | {status: 'not_found'; retryAvailable: boolean};

function fail(message: string): never {throw new Error(message);}
function object(value: unknown): value is Record<string, unknown> {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function current(context: GrantCreateContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'transaction_journals' || context.identity.role === 'staff' ||
      !['gateway.read', PERMISSION, 'receivers.read'].every(permission => context.identity.permissions.includes(permission)) ||
      !Number.isFinite(expires) || expires <= Date.now()) fail('Capture access is unavailable to your current account.');
}
function write(context: GrantCreateContext) {current(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Capture access is not enabled for this workspace.');}
function verifyAttempt(attempt: PendingAttempt): GrantCreateIntent {
  if (attempt.family !== FAMILY || attempt.resource_id !== RESOURCE || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key)) fail('The original capture request could not be verified.');
  return intentSchema.parse(attempt.intent);
}
function parsePayee(value: unknown, id: string, actor: string): GrantPayee {
  if (!object(value) || value.resource_type !== 'payees' || value.current_actor_id !== actor || value.can_manage !== true ||
      !object(value.related) || Object.keys(value.related).length !== 0 || !object(value.related_pages) || Object.keys(value.related_pages).length !== 0 || value.related_truncated !== false ||
      Object.keys(value).length !== 7 || value.contract_version !== undefined || value.model !== undefined) fail('The receiving account could not be verified.');
  const payee = payeeSchema.parse(value.resource); if (payee.id !== id) fail('The receiving account could not be verified.'); return payee;
}
export async function loadGrantDevices(context: GrantCreateContext, offset: number) {
  current(context); if (!Number.isSafeInteger(offset) || offset < 0 || offset > 2147483647) fail('Select a valid device page.');
  const query = new URLSearchParams({limit: '25', offset: String(offset), state: 'active'});
  const page = parseGatewayPage(await context.request(`gateway/devices?${query}`), offset, 'active'); current(context); return page;
}
export async function loadGrantPayees(context: GrantCreateContext, offset: number, search: string) {
  current(context); if (!Number.isSafeInteger(offset) || offset < 0 || offset > 2147483647 || search.length > 200 || /[\x00-\x1f\x7f]/.test(search)) fail('Select a valid receiver page.');
  const query = new URLSearchParams({search: search.trim(), status: 'active', limit: '25', offset: String(offset), sort: 'created_at_desc', country: 'RW'});
  const page = parseCorePage(await context.request(`core/payees?${query}`), 'payees', 'transaction_journals', 25, offset, 'active'); current(context); return page;
}
export async function loadGrantTargets(context: GrantCreateContext, deviceId: string, payeeId: string): Promise<GrantTargets> {
  current(context); if (!UUID.test(deviceId) || !UUID.test(payeeId)) fail('Choose a valid device and receiver.');
  const [deviceBody, payeeBody] = await Promise.all([context.request(`gateway/devices/${deviceId}`), context.request(`operations/payees/${payeeId}`)]); current(context);
  const device = await parseGatewayDetail(deviceBody, deviceId, context.identity.id, false); current(context);
  const payee = parsePayee(payeeBody, payeeId, context.identity.id);
  if (!device.canManage || device.resource.state !== 'active') fail('The selected device is not active.');
  return {device: device.resource, payee};
}
export function verifyGrantSelection(targets: GrantTargets, device: GatewayDevice, payee: DataRow) {
  const selected = targets.device, receiver = targets.payee;
  if (selected.id !== device.id || selected.version !== device.version || selected.state !== device.state || selected.installation_id !== device.installation_id ||
      selected.app_id !== device.app_id || selected.key_sha256 !== device.key_sha256 || selected.signing_certificate_sha256 !== device.signing_certificate_sha256 ||
      receiver.id !== payee.id || receiver.group_id !== payee.group_id || receiver.label !== payee.title || receiver.network !== payee.network || receiver.momo_number_or_code !== payee.momo_number_or_code) fail('The selected device or receiver changed. Refresh before continuing.');
}
function targetIdentity(target: GrantTargets) {
  const {device, payee} = target;
  return JSON.stringify([device.id, device.version, device.state, device.app_id, device.installation_id, device.key_sha256, device.signing_certificate_sha256,
    payee.id, payee.version, payee.status, payee.group_id, payee.label, payee.network, payee.momo_number_or_code]);
}
async function exactTargets(context: GrantCreateContext, intent: GrantCreateIntent) {
  const targets = await loadGrantTargets(context, intent.device_id, intent.payee_id); current(context);
  if (targets.device.version !== intent.expected_device_version || targets.payee.version !== intent.expected_payee_version) fail('The original device or receiver changed. Check the original request.');
  return targets;
}
export async function loadOriginalGrantTargets(context: GrantCreateContext, pending: GrantCreatePending): Promise<GrantTargets> {
  current(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original capture intent is unavailable.');
  return exactTargets(context, verifyAttempt(pending.attempt));
}
const { withFence: fence, restore, lookupOriginal, requireOriginal, retain, clear } = operationRequestCustody<GrantCreateContext>({
  family: FAMILY,
  permission: PERMISSION,
  resourceId: () => RESOURCE,
  check: current,
  verifyAttempt: (_context, attempt) => verifyAttempt(attempt),
  invalidMessage: 'The original capture request could not be verified.',
});

// Serialize only this grant-creation workflow across tabs. The shared fence is
// held briefly for checkpoint updates, never for network requests; unrelated
// enrollment and other workflows retain their own independent checkpoints.
async function scoped<T>(context: GrantCreateContext, work: () => Promise<T>): Promise<T> {
  const lock: FenceLock = context.lock ?? (async (name, task) => {
    if (!navigator.locks) fail('Shared request recovery is unavailable.');
    return navigator.locks.request(name, {mode: 'exclusive', ifAvailable: true}, held => held ? task() : fail('This capture request is already being checked.'));
  });
  return lock('collect.admin.receiver-grant-create.v1', async () => {current(context); return work();});
}

export async function restoreGrantCreation(context: GrantCreateContext) {current(context); return fence(context, access => restore(context, access));}
async function verifyReceipt(context: GrantCreateContext, value: unknown, attempt: PendingAttempt | null): Promise<GrantCreateReceipt> {
  if (!attempt) fail('The original capture intent is unavailable.');
  const saved = receiptSchema.parse(value), original = verifyAttempt(attempt);
  const detail = parseGrantDetail(await context.request(`gateway/receiver-grants/${saved.resource_id}?limit=25&offset=0`), saved.resource_id, context.identity.id, true, 0); current(context);
  if (!detail.canManage || detail.resource.device_id !== original.device_id || detail.resource.payee_id !== original.payee_id || detail.resource.created_by_admin_id !== context.identity.id) fail('The original capture receipt could not be verified.');
  return {requestId: saved.request_id, grantId: saved.resource_id, version: 1};
}
async function lookup(context: GrantCreateContext, pending: Extract<GrantCreatePending, {kind: 'owned'}>): Promise<GrantCreateLookup> {
  const result = await context.request(`gateway/receiver-requests/${pending.requestKey}`); current(context);
  if (result.found === false && Object.keys(result).length === 1) return {status: 'not_found', retryAvailable: pending.attempt !== null};
  if (result.found !== true || Object.keys(result).length !== 2 || !Object.hasOwn(result, 'receipt')) fail('The original capture receipt could not be verified.');
  return {status: 'succeeded', receipt: await verifyReceipt(context, result.receipt, pending.attempt)};
}
async function clearVerified(context: GrantCreateContext, pending: Extract<GrantCreatePending, {kind: 'owned'}>) {
  if (!pending.attempt) fail('The original capture request could not be verified.');
  const original = pending.attempt;
  await fence(context, async access => {
    const saved = await requireOriginal(context, access, pending.requestKey, original);
    await clear(context, access, saved);
  });
}
async function settle(context: GrantCreateContext, pending: Extract<GrantCreatePending, {kind: 'owned'}>, value: unknown): Promise<GrantCreateResult> {
  const receipt = await verifyReceipt(context, value, pending.attempt); await clearVerified(context, pending); return {status: 'succeeded', receipt};
}
export async function submitGrantCreation(context: GrantCreateContext, targets: GrantTargets, reason: string, revision: string): Promise<GrantCreateResult> {
  write(context);
  const intent = intentSchema.parse({device_id: targets.device.id, expected_device_version: targets.device.version, payee_id: targets.payee.id, expected_payee_version: targets.payee.version, reason: reason.trim()});
  return scoped(context, async () => {
    const latest = await exactTargets(context, intent); if (targetIdentity(latest) !== targetIdentity(targets)) fail('The reviewed device or receiver changed.');
    write(context);
    const checkpoint = await fence(context, async access => {
      const saved = await restore(context, access); if (saved.kind !== 'ready') return {kind: 'existing' as const, pending: saved};
      write(context);
      const pending = await retain(context, access, revision, {...intent});
      return {kind: 'new' as const, pending};
    });
    if (checkpoint.kind === 'existing') return {status: 'existing', pending: checkpoint.pending};
    const pending = checkpoint.pending;
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey: pending.requestKey};
    try {const result = await context.request('gateway/receiver-grants', {method: 'POST', body: {...intent}, idempotencyKey: pending.requestKey}); current(context); return await settle(context, pending, result);}
    catch {return {status: 'unknown', requestKey: pending.requestKey};}
  });
}
export async function lookupGrantCreation(context: GrantCreateContext, pending: GrantCreatePending): Promise<GrantCreateLookup> {
  current(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return scoped(context, async () => {
    const saved = await fence(context, access => lookupOriginal(context, access, pending.requestKey));
    const result = await lookup(context, saved); if (result.status === 'succeeded') await clearVerified(context, saved); return result;
  });
}
export async function retryGrantCreation(context: GrantCreateContext, pending: GrantCreatePending, reviewed: GrantTargets): Promise<GrantCreateResult> {
  write(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original capture intent is unavailable.');
  const original = pending.attempt;
  return scoped(context, async () => {
    const saved = await fence(context, access => requireOriginal(context, access, pending.requestKey, original));
    const prior = await lookup(context, saved); if (prior.status === 'succeeded') {await clearVerified(context, saved); return {status: 'succeeded', receipt: prior.receipt};}
    const intent = verifyAttempt(saved.attempt), latest = await exactTargets(context, intent);
    if (targetIdentity(latest) !== targetIdentity(reviewed)) fail('The reviewed device or receiver changed.');
    write(context);
    try {const result = await context.request('gateway/receiver-grants', {method: 'POST', body: {...intent}, idempotencyKey: saved.requestKey}); current(context); return await settle(context, saved, result);}
    catch {return {status: 'unknown', requestKey: saved.requestKey};}
  });
}
