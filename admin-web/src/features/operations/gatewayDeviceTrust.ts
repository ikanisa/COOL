/* eslint-disable no-control-regex -- Reject control characters in audit reasons. */
import {z} from 'zod';
import type {AdminRequest, JsonObject} from '../../api/client';
import type {PendingAttempt} from '../core/pendingAttempt';
import type {FinancialModel} from '../core/types';
import {parseGatewayDetail, type GatewayDevice} from './contracts';
import {operationRequestCustody, type OperationPending, type OperationRequestContext, type OwnedOperationRequest} from './operationRequestCustody';
import type {FenceAccess} from './pendingFence';

const PERMISSION = 'gateway.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const invalidRequest = 'The original device request could not be verified.';
const invalidReceipt = 'The original device receipt could not be verified.';
const receiptSchema = z.object({
  request_id: z.string().regex(UUID),
  resource_type: z.literal('gateway_devices'),
  resource_id: z.string().regex(UUID),
  version: z.number().int().min(2).max(Number.MAX_SAFE_INTEGER),
  status: z.literal('succeeded'),
}).strict();

type TrustAction = 'activate' | 'revoke';

export interface GatewayTrustContext extends OperationRequestContext {
  request: AdminRequest;
  device: GatewayDevice;
  canManage: boolean;
  financialModel: FinancialModel;
  enabled: boolean;
  isEnabled?: () => boolean;
}

interface DeviceTrustIntent {
  expected_version: number;
  expected_key_sha256: string;
  expected_signing_certificate_sha256: string;
  reason: string;
}

interface DeviceTrustReceipt {requestId: string; deviceId: string; version: number}
type DeviceTrustResult =
  | {status: 'succeeded'; receipt: DeviceTrustReceipt}
  | {status: 'unknown'; requestKey: string}
  | {status: 'existing'; pending: OperationPending};
type DeviceTrustLookup =
  | {status: 'succeeded'; receipt: DeviceTrustReceipt}
  | {status: 'not_found'; retryAvailable: boolean}
  | {status: 'pending' | 'failed'};

function exact(value: JsonObject, keys: string[]) {
  return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}

function check(context: GatewayTrustContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || !context.canManage || context.identity.role === 'staff' ||
      context.financialModel !== 'transaction_journals' || !UUID.test(context.device.id) ||
      !['gateway.read', PERMISSION, 'overview.read'].every(permission => context.identity.permissions.includes(permission)) ||
      !Number.isFinite(expires) || expires <= Date.now()) {
    throw new Error('This action is unavailable to your current account.');
  }
}

function writesEnabled(context: GatewayTrustContext) {
  return context.enabled && (context.isEnabled?.() ?? true);
}

function write(context: GatewayTrustContext) {
  check(context);
  if (!writesEnabled(context)) throw new Error('This action is not enabled for the current workspace.');
}

function reasonText(reason: string) {
  const value = reason.trim();
  if (value.length < 8 || value.length > 1000 || /[\x00-\x1f\x7f]/.test(value)) {
    throw new Error('Provide a reason of 8 to 1000 characters.');
  }
  return value;
}

function validVersion(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 1 && value < Number.MAX_SAFE_INTEGER;
}

async function currentDevice(context: GatewayTrustContext) {
  const expected = context.device;
  const detail = await parseGatewayDetail(await context.request(`gateway/devices/${expected.id}`), expected.id, context.identity.id, false);
  check(context);
  const {resource} = detail;
  if (!detail.canManage || resource.app_id !== expected.app_id || resource.installation_id !== expected.installation_id ||
      resource.key_sha256 !== expected.key_sha256 || resource.signing_certificate_sha256 !== expected.signing_certificate_sha256) {
    throw new Error('The current device identity could not be verified.');
  }
  return resource;
}

function gatewayTrustAction(
  action: TrustAction,
  eligibleStates: ReadonlyArray<GatewayDevice['state']>,
  recordedState: GatewayDevice['state'],
  unverifiedChange: string,
) {
  const family = `gateway-device-${action}`;

  function verifyAttempt(context: GatewayTrustContext, attempt: PendingAttempt): DeviceTrustIntent {
    const {intent} = attempt;
    if (attempt.family !== family || attempt.resource_id !== context.device.id || attempt.permission !== PERMISSION ||
        !UUID.test(attempt.request_key) || !exact(intent, ['expected_version', 'expected_key_sha256', 'expected_signing_certificate_sha256', 'reason']) ||
        !validVersion(intent.expected_version) || typeof intent.expected_key_sha256 !== 'string' || !HASH.test(intent.expected_key_sha256) ||
        typeof intent.expected_signing_certificate_sha256 !== 'string' || !HASH.test(intent.expected_signing_certificate_sha256) ||
        intent.expected_key_sha256 !== context.device.key_sha256 ||
        intent.expected_signing_certificate_sha256 !== context.device.signing_certificate_sha256 ||
        typeof intent.reason !== 'string' || reasonText(intent.reason) !== intent.reason) {
      throw new Error(invalidRequest);
    }
    return {
      expected_version: intent.expected_version, expected_key_sha256: intent.expected_key_sha256,
      expected_signing_certificate_sha256: intent.expected_signing_certificate_sha256, reason: intent.reason,
    };
  }

  const custody = operationRequestCustody<GatewayTrustContext>({
    family, permission: PERMISSION, resourceId: context => context.device.id,
    check, verifyAttempt, invalidMessage: invalidRequest,
  });

  function receipt(value: unknown, context: GatewayTrustContext, attempt: PendingAttempt | null): DeviceTrustReceipt {
    const parsed = receiptSchema.parse(value);
    if (parsed.resource_id !== context.device.id || attempt && parsed.version !== verifyAttempt(context, attempt).expected_version + 1) {
      throw new Error(invalidReceipt);
    }
    return {requestId: parsed.request_id, deviceId: parsed.resource_id, version: parsed.version};
  }

  async function verifySaved(context: GatewayTrustContext, saved: DeviceTrustReceipt) {
    const device = await currentDevice(context);
    if (device.state !== recordedState || device.version !== saved.version) throw new Error(unverifiedChange);
  }

  async function lookupReceipt(context: GatewayTrustContext, pending: OwnedOperationRequest): Promise<DeviceTrustLookup> {
    const body = await context.request(`operations/requests/${pending.requestKey}`);
    check(context);
    if (body.status === 'not_found' && exact(body, ['status'])) return {status: 'not_found', retryAvailable: pending.attempt !== null};
    if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) {
      throw new Error(invalidReceipt);
    }
    if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
    if (body.status !== 'succeeded') throw new Error(invalidReceipt);
    const saved = receipt(body.receipt, context, pending.attempt);
    if (saved.requestId !== body.request_id) throw new Error(invalidReceipt);
    await verifySaved(context, saved);
    return {status: 'succeeded', receipt: saved};
  }

  async function dispatch(context: GatewayTrustContext, access: FenceAccess, pending: OwnedOperationRequest, intent: DeviceTrustIntent): Promise<DeviceTrustResult> {
    const {requestKey} = pending;
    if (!context.isCurrent() || !writesEnabled(context)) return {status: 'unknown', requestKey};
    try {
      check(context);
      const value = await context.request(`gateway/devices/${context.device.id}/${action}`, {
        method: 'POST', body: {...intent}, idempotencyKey: requestKey,
      });
      check(context);
      const saved = receipt(value, context, pending.attempt);
      await verifySaved(context, saved);
      await custody.clear(context, access, pending);
      return {status: 'succeeded', receipt: saved};
    } catch {
      return {status: 'unknown', requestKey};
    }
  }

  async function restore(context: GatewayTrustContext) {
    check(context);
    return custody.withFence(context, access => custody.restore(context, access));
  }

  async function submit(context: GatewayTrustContext, reason: string, revision: string): Promise<DeviceTrustResult> {
    write(context);
    const why = reasonText(reason), {device} = context;
    if (!eligibleStates.includes(device.state) || !validVersion(device.version) ||
        !HASH.test(device.key_sha256) || !HASH.test(device.signing_certificate_sha256)) {
      throw new Error('Refresh the current device before reviewing it.');
    }
    const intent = {
      expected_version: device.version, expected_key_sha256: device.key_sha256,
      expected_signing_certificate_sha256: device.signing_certificate_sha256, reason: why,
    };
    return custody.withFence(context, async access => {
      const existing = await custody.restore(context, access);
      if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
      write(context);
      const pending = await custody.retain(context, access, revision, intent);
      return dispatch(context, access, pending, intent);
    });
  }

  async function lookup(context: GatewayTrustContext, pending: OperationPending): Promise<DeviceTrustLookup> {
    check(context);
    if (pending.kind !== 'owned') throw new Error('The original account must check this request.');
    return custody.withFence(context, async access => {
      const original = await custody.lookupOriginal(context, access, pending.requestKey);
      const result = await lookupReceipt(context, original);
      if (result.status === 'succeeded') await custody.clear(context, access, original);
      return result;
    });
  }

  async function retry(context: GatewayTrustContext, pending: OperationPending): Promise<DeviceTrustResult> {
    write(context);
    if (pending.kind !== 'owned' || !pending.attempt) throw new Error('The original device intent is unavailable.');
    const original = pending.attempt;
    return custody.withFence(context, async access => {
      const saved = await custody.requireOriginal(context, access, pending.requestKey, original);
      const previous = await lookupReceipt(context, saved);
      if (previous.status === 'succeeded') {
        await custody.clear(context, access, saved);
        return previous;
      }
      if (previous.status !== 'not_found') throw new Error('The original device request remains unresolved.');
      const intent = verifyAttempt(context, saved.attempt), device = await currentDevice(context);
      if (!eligibleStates.includes(device.state) || device.version !== intent.expected_version) {
        throw new Error('The device changed. Check the original receipt before continuing.');
      }
      write(context);
      return dispatch(context, access, saved, intent);
    });
  }

  return {restore, submit, lookup, retry};
}

export const gatewayTrustActions = {
  activate: gatewayTrustAction('activate', ['pending'], 'active', 'The device activation could not be verified.'),
  revoke: gatewayTrustAction('revoke', ['pending', 'active'], 'revoked', 'The device revocation could not be verified.'),
};
