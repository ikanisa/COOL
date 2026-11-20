import type {AdminRequest, JsonObject} from '../../api/client';
import {clearPending, listPending, readPending, retainPending, type PendingAttempt, type PendingIdentity} from '../core/pendingAttempt';
import type {SmsDecisionDetail, SmsPolicyState} from './SmsControlsPage';
import {MANAGEMENT_FAMILY as FAMILY, MANAGEMENT_PERMISSION as PERMISSION, MANAGEMENT_UUID as UUID, managementIdentity as identity, managementStorage as storage, parseManagementPending, withManagementLock} from './smsControlRecovery';

const originals = new WeakSet<object>(), checked = new WeakSet<object>();

export interface SmsPolicyContext {
  allowPolicyChanges: boolean;
  /** Separate qualification gate: policy enablement remains disabled by default. */
  allowPolicyEnabling?: boolean;
  authorityEpoch: number;
  identity: PendingIdentity & {principalId: string};
  request: AdminRequest;
  verifyFresh: () => Promise<boolean>;
  isCurrent: () => boolean;
  mutationCurrent?: () => boolean;
  enablementCurrent?: () => boolean;
  parsePolicy: (body: JsonObject, collectionId: string) => SmsPolicyState;
  parseReceipt: (body: JsonObject, requestId: string) => Promise<NonNullable<SmsDecisionDetail['decision']>>;
  parseStatus: (body: JsonObject, requestId: string) => Promise<SmsDecisionDetail>;
  storage?: Storage;
}
export interface SmsPolicyOriginal {readonly requestId: string; readonly collectionId: string; readonly expectedRevision: number; readonly enabled: boolean; readonly actorId: string; readonly sessionId: string; readonly principalId: string; readonly authorityEpoch: number}
export class SmsPolicyOutcomeUnknown extends Error {
  constructor(readonly checkpoint: PendingAttempt, readonly original: SmsPolicyOriginal) {
    super('The policy change is not confirmed. Check its original request before continuing.');
  }
}

function authority(context: SmsPolicyContext, mutation = false) {
  const actor = context.identity;
  if ((mutation && (context.allowPolicyChanges !== true || context.mutationCurrent?.() === false)) || actor.role !== 'owner' || actor.email !== 'info@ikanisa.com' || !actor.permissions.includes(PERMISSION) || !actor.permissions.includes('assisted_sms.manage') || !UUID.test(actor.id) || !UUID.test(actor.sessionId) || !UUID.test(actor.principalId) || !context.isCurrent()) throw new Error('Reopen SMS controls with the current verified owner sign-in.');
}
function enableAllowed(context: SmsPolicyContext): boolean {return context.allowPolicyEnabling === true && context.enablementCurrent?.() !== false;}
function guarded<T>(context: SmsPolicyContext, mutation: boolean, work: () => Promise<T>): Promise<T> {
  authority(context, mutation);
  return withManagementLock(context, work);
}
async function verify(context: SmsPolicyContext, mutation = false) {
  authority(context, mutation);
  if (!(await context.verifyFresh())) throw new Error('Verify your current owner sign-in before continuing.');
  authority(context, mutation);
}
async function exact(context: SmsPolicyContext, saved: PendingAttempt) {
  const found = await readPending(identity(context), FAMILY, saved.resource_id, storage(context));
  authority(context);
  if (!found || found.request_key !== saved.request_key || JSON.stringify(found.intent) !== JSON.stringify(saved.intent)) throw new Error('The original SMS controls reference could not be verified.');
  return parseManagementPending(found);
}
async function settle(context: SmsPolicyContext, saved: PendingAttempt) {
  await exact(context, saved);
  await clearPending(identity(context), FAMILY, saved.resource_id, saved.request_key, storage(context));
  authority(context);
}
function sameOriginal(context: SmsPolicyContext, original: SmsPolicyOriginal, saved: PendingAttempt) {
  return originals.has(original) && original.authorityEpoch === context.authorityEpoch && original.actorId === context.identity.id && original.sessionId === context.identity.sessionId && original.principalId === context.identity.principalId && original.requestId === saved.request_key && saved.intent.action === 'policy' && saved.intent.resource_id === original.collectionId;
}
async function dispatch(context: SmsPolicyContext, saved: PendingAttempt, original: SmsPolicyOriginal) {
  authority(context, true);
  if (original.enabled && !enableAllowed(context)) throw new Error('Policy enablement is unavailable.');
  try {
    const response = await context.request(`notification-operator/policies/${original.collectionId}`, {authenticated: true, method: 'POST', body: {request_id: original.requestId, expected_revision: original.expectedRevision, enabled: original.enabled, owner_confirmation: original.enabled}});
    authority(context, true);
    if (original.enabled && !enableAllowed(context)) throw new Error('Policy enablement is unavailable.');
    const receipt = await context.parseReceipt(response, original.requestId);
    authority(context, true);
    if (original.enabled && !enableAllowed(context)) throw new Error('Policy enablement is unavailable.');
    if (receipt.collectionId !== original.collectionId || receipt.revision !== original.expectedRevision + 1 || receipt.enabled !== original.enabled) throw new Error('Unverified policy receipt.');
    await settle(context, saved);
    return receipt;
  } catch {throw new SmsPolicyOutcomeUnknown(saved, original);}
}

/** An exact, stored original reference is retained before the first policy POST. */
export function disableSmsPolicy(context: SmsPolicyContext, expected: SmsPolicyState) {
  return guarded(context, true, async () => {
    await verify(context, true);
    if (!UUID.test(expected.collectionId) || !expected.enabled || !expected.configured || expected.revision < 1 || expected.revision > 999_999_998) throw new Error('Refresh the current enabled group policy first.');
    const refs = (await listPending(identity(context), FAMILY, PERMISSION, storage(context))).map(parseManagementPending);
    authority(context, true);
    if (refs.length) throw new Error('Check the original SMS controls request before making another change.');
    const latest = context.parsePolicy(await context.request(`notification-operator/policies/${expected.collectionId}`, {authenticated: true, method: 'GET'}), expected.collectionId);
    authority(context, true);
    if (!latest.enabled || latest.revision !== expected.revision) throw new Error('The group policy changed. Refresh before continuing.');
    if (typeof globalThis.crypto?.randomUUID !== 'function') throw new Error('A secure request reference is unavailable.');
    const requestId = globalThis.crypto.randomUUID();
    const original: SmsPolicyOriginal = Object.freeze({requestId, collectionId: expected.collectionId, expectedRevision: expected.revision, enabled: false, actorId: context.identity.id, sessionId: context.identity.sessionId, principalId: context.identity.principalId, authorityEpoch: context.authorityEpoch});
    originals.add(original);
    const saved = await retainPending(identity(context), FAMILY, `policy:${expected.collectionId}`, requestId, PERMISSION, {action: 'policy', resource_id: expected.collectionId}, storage(context));
    authority(context, true);
    return dispatch(context, saved, original);
  });
}

/** Explicitly confirmed policy enablement is separately disabled until qualified. */
export function enableSmsPolicy(context: SmsPolicyContext, expected: SmsPolicyState, ownerConfirmed: boolean) {
  return guarded(context, true, async () => {
    if (!enableAllowed(context) || ownerConfirmed !== true) throw new Error('Confirm the exact group policy before enabling it.');
    await verify(context, true);
    if (!UUID.test(expected.collectionId) || expected.enabled || !expected.collectionActive || !Number.isSafeInteger(expected.revision) || expected.revision < 0 || expected.revision > 999_999_998 || expected.configured !== (expected.revision > 0)) throw new Error('Refresh the current active group policy first.');
    const refs = (await listPending(identity(context), FAMILY, PERMISSION, storage(context))).map(parseManagementPending);
    authority(context, true);
    if (refs.length) throw new Error('Check the original SMS controls request before making another change.');
    const latest = context.parsePolicy(await context.request(`notification-operator/policies/${expected.collectionId}`, {authenticated: true, method: 'GET'}), expected.collectionId);
    authority(context, true);
    if (!enableAllowed(context) || latest.enabled || !latest.collectionActive || latest.configured !== expected.configured || latest.revision !== expected.revision) throw new Error('The group policy changed. Refresh before continuing.');
    if (typeof globalThis.crypto?.randomUUID !== 'function') throw new Error('A secure request reference is unavailable.');
    const requestId = globalThis.crypto.randomUUID();
    const original: SmsPolicyOriginal = Object.freeze({requestId, collectionId: expected.collectionId, expectedRevision: expected.revision, enabled: true, actorId: context.identity.id, sessionId: context.identity.sessionId, principalId: context.identity.principalId, authorityEpoch: context.authorityEpoch});
    originals.add(original);
    const saved = await retainPending(identity(context), FAMILY, `policy:${expected.collectionId}`, requestId, PERMISSION, {action: 'policy', resource_id: expected.collectionId}, storage(context));
    try {
      authority(context, true);
      if (!enableAllowed(context)) throw new Error('Policy enablement is unavailable.');
      return await dispatch(context, saved, original);
    } catch {throw new SmsPolicyOutcomeUnknown(saved, original);}
  });
}

export function listSmsControlPending(context: SmsPolicyContext): Promise<PendingAttempt[]> {
  return guarded(context, false, async () => {await verify(context); const result = (await listPending(identity(context), FAMILY, PERMISSION, storage(context))).map(parseManagementPending); authority(context); return result;});
}

/** A missing receipt remains unknown; an in-memory original alone permits a deliberate same-request replay. */
export function checkSmsPolicyOriginal(context: SmsPolicyContext, saved: PendingAttempt, original: SmsPolicyOriginal | null) {
  return guarded(context, false, async () => {
    await verify(context);
    const pending = await exact(context, parseManagementPending(saved));
    if (pending.intent.action !== 'policy' || (original && !sameOriginal(context, original, pending))) throw new Error('The original policy reference could not be verified.');
    if (original) checked.delete(original);
    const response = await context.request(`notification-operator/policies/operations/${pending.request_key}`, {authenticated: true, method: 'GET'});
    authority(context);
    const status = await context.parseStatus(response, pending.request_key);
    authority(context);
    if (status.observed) {
      const decision = status.decision;
      if (!decision || decision.collectionId !== pending.intent.resource_id || (original && (decision.enabled !== original.enabled || decision.revision !== original.expectedRevision + 1))) throw new Error('The recorded result does not match the original policy request.');
      await settle(context, pending);
    } else if (original) checked.add(original);
    return status;
  });
}

export function replaySmsPolicy(context: SmsPolicyContext, saved: PendingAttempt, original: SmsPolicyOriginal) {
  return guarded(context, true, async () => {
    if (!checked.has(original)) throw new Error('Check the original policy request before retrying.');
    if (original.enabled && !enableAllowed(context)) throw new Error('Policy enablement is unavailable.');
    checked.delete(original);
    await verify(context, true);
    const pending = await exact(context, parseManagementPending(saved));
    if (!sameOriginal(context, original, pending)) throw new Error('The original policy reference could not be verified.');
    return dispatch(context, pending, original);
  });
}
