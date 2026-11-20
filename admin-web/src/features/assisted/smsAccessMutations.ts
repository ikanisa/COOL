import type {AdminRequest, JsonObject} from '../../api/client';
import {clearPending, listPending, readPending, retainPending, type PendingAttempt, type PendingIdentity} from '../core/pendingAttempt';
import type {SmsAccessReceipt, SmsAccessState, SmsDecisionDetail} from './SmsControlsPage';
import {MANAGEMENT_FAMILY as FAMILY, MANAGEMENT_PERMISSION as PERMISSION, MANAGEMENT_UUID as UUID, managementIdentity, managementStorage, parseManagementPending, withManagementLock} from './smsControlRecovery';

const originals = new WeakSet<object>(), checked = new WeakSet<object>();
export interface SmsAccessContext {
  allowAccessChanges: boolean;
  authorityEpoch: number;
  identity: PendingIdentity & {principalId: string};
  request: AdminRequest;
  verifyFresh: () => Promise<boolean>;
  isCurrent: () => boolean;
  parseAccess: (body: JsonObject) => SmsAccessState;
  parseReceipt: (body: JsonObject, requestId: string) => Promise<SmsAccessReceipt>;
  parseStatus: (body: JsonObject, requestId: string) => Promise<SmsDecisionDetail>;
  storage?: Storage;
}
export interface SmsAccessOriginal {readonly requestId: string; readonly actorId: string; readonly sessionId: string; readonly principalId: string; readonly authorityEpoch: number; readonly expectedRevision: number; readonly expectedRead: boolean; readonly expectedManage: boolean; readonly enabled: boolean}
export interface SmsAccessResult {receipt: SmsAccessReceipt; currentAccess: SmsAccessState | null}
export class SmsAccessOutcomeUnknown extends Error {
  constructor(readonly checkpoint: PendingAttempt, readonly original: SmsAccessOriginal) {super('The access change is not confirmed. Check its original request before continuing.');}
}

function authority(context: SmsAccessContext, mutation = false) {
  const actor = context.identity;
  if ((mutation && context.allowAccessChanges !== true) || actor.role !== 'owner' || actor.email !== 'info@ikanisa.com' || !actor.permissions.includes(PERMISSION) || !UUID.test(actor.id) || !UUID.test(actor.sessionId) || !UUID.test(actor.principalId) || !context.isCurrent()) throw new Error('Reopen SMS controls with the current verified owner sign-in.');
}
function guarded<T>(context: SmsAccessContext, mutation: boolean, work: () => Promise<T>): Promise<T> {authority(context, mutation); return withManagementLock(context, work);}
async function verify(context: SmsAccessContext, mutation = false) {
  authority(context, mutation);
  if (!(await context.verifyFresh())) throw new Error('Verify your current owner sign-in before continuing.');
  authority(context, mutation);
}
async function exact(context: SmsAccessContext, saved: PendingAttempt) {
  const found = await readPending(managementIdentity(context), FAMILY, saved.resource_id, managementStorage(context));
  authority(context);
  if (!found || found.request_key !== saved.request_key || JSON.stringify(found.intent) !== JSON.stringify(saved.intent)) throw new Error('The original SMS controls reference could not be verified.');
  return parseManagementPending(found);
}
async function settle(context: SmsAccessContext, saved: PendingAttempt) {
  await exact(context, saved);
  await clearPending(managementIdentity(context), FAMILY, saved.resource_id, saved.request_key, managementStorage(context));
  authority(context);
}
function sameOriginal(context: SmsAccessContext, original: SmsAccessOriginal, saved: PendingAttempt) {
  return originals.has(original) && original.authorityEpoch === context.authorityEpoch && original.actorId === context.identity.id && original.sessionId === context.identity.sessionId && original.principalId === context.identity.principalId && original.requestId === saved.request_key && saved.intent.action === 'access' && saved.intent.resource_id === original.principalId && saved.intent.expected_decision_revision === original.expectedRevision;
}
async function currentAccess(context: SmsAccessContext): Promise<SmsAccessState> {
  const state = context.parseAccess(await context.request('notification-operator/access', {authenticated: true, method: 'GET'}));
  authority(context);
  return state;
}
async function dispatch(context: SmsAccessContext, saved: PendingAttempt, original: SmsAccessOriginal, replay: boolean): Promise<SmsAccessResult> {
  authority(context, true);
  let receipt: SmsAccessReceipt;
  try {
    const response = await context.request('notification-operator/access', {authenticated: true, method: 'POST', body: {request_id: original.requestId, expected_read: original.expectedRead, expected_manage: original.expectedManage, expected_decision_revision: original.expectedRevision, enabled: original.enabled, owner_confirmation: original.enabled}});
    authority(context, true);
    receipt = await context.parseReceipt(response, original.requestId);
    authority(context, true);
    if (receipt.enabled !== original.enabled || receipt.revision !== original.expectedRevision + 1 || (!replay && receipt.replay)) throw new Error('Unverified access receipt.');
    await settle(context, saved);
  } catch {throw new SmsAccessOutcomeUnknown(saved, original);}
  // Read separately; a historical decision never supplies current grants.
  try {
    const now = await currentAccess(context);
    if (now.revision < receipt.revision) throw new Error('Unverified access head.');
    return {receipt, currentAccess: now};
  } catch {return {receipt, currentAccess: null};}
}

/** The original UUID and expected decision head are retained before dispatch. */
export function changeSmsAccess(context: SmsAccessContext, expected: SmsAccessState, enabled: boolean, ownerConfirmed: boolean): Promise<SmsAccessResult> {
  return guarded(context, true, async () => {
    await verify(context, true);
    if (expected.adminId !== context.identity.id.toLowerCase() || expected.principalId !== context.identity.principalId.toLowerCase() || !Number.isSafeInteger(expected.revision) || expected.revision < 0 || expected.revision >= Number.MAX_SAFE_INTEGER || !ownerConfirmed || (enabled ? expected.canOperate : !expected.readGranted && !expected.manageGranted)) throw new Error('Refresh and confirm the current owner access first.');
    const pending = (await listPending(managementIdentity(context), FAMILY, PERMISSION, managementStorage(context))).map(parseManagementPending);
    authority(context, true);
    if (pending.length) throw new Error('Check the original SMS controls request before making another change.');
    const latest = await currentAccess(context);
    if (latest.revision !== expected.revision || latest.readGranted !== expected.readGranted || latest.manageGranted !== expected.manageGranted || latest.canOperate !== expected.canOperate) throw new Error('Owner access changed. Refresh before continuing.');
    if (typeof globalThis.crypto?.randomUUID !== 'function') throw new Error('A secure request reference is unavailable.');
    const requestId = globalThis.crypto.randomUUID();
    const original: SmsAccessOriginal = Object.freeze({requestId, actorId: context.identity.id, sessionId: context.identity.sessionId, principalId: context.identity.principalId, authorityEpoch: context.authorityEpoch, expectedRevision: expected.revision, expectedRead: expected.readGranted, expectedManage: expected.manageGranted, enabled});
    originals.add(original);
    const saved = await retainPending(managementIdentity(context), FAMILY, `access:${context.identity.principalId}`, requestId, PERMISSION, {action: 'access', resource_id: context.identity.principalId, expected_decision_revision: expected.revision}, managementStorage(context));
    authority(context, true);
    return dispatch(context, saved, original, false);
  });
}

/** Owner access references remain readable after assisted SMS self-disable. */
export function listSmsManagementPending(context: SmsAccessContext): Promise<PendingAttempt[]> {
  return guarded(context, false, async () => {await verify(context); const result = (await listPending(managementIdentity(context), FAMILY, PERMISSION, managementStorage(context))).map(parseManagementPending); authority(context); return result;});
}
export function checkSmsAccessOriginal(context: SmsAccessContext, saved: PendingAttempt, original: SmsAccessOriginal | null) {
  return guarded(context, false, async () => {
    await verify(context);
    const pending = await exact(context, parseManagementPending(saved));
    if (pending.intent.action !== 'access' || pending.intent.resource_id !== context.identity.principalId || (original && !sameOriginal(context, original, pending))) throw new Error('The original access reference could not be verified.');
    if (original) checked.delete(original);
    const response = await context.request(`notification-operator/access/operations/${pending.request_key}`, {authenticated: true, method: 'GET'});
    authority(context);
    const status = await context.parseStatus(response, pending.request_key);
    authority(context);
    if (!status.currentAccess) throw new Error('The current owner access could not be verified.');
    if (status.observed) {
      const decision = status.decision, expected = pending.intent.expected_decision_revision;
      if (!decision || (typeof expected === 'number' && decision.revision !== expected + 1) || (original && (decision.enabled !== original.enabled || decision.revision !== original.expectedRevision + 1))) throw new Error('The recorded result does not match the original access request.');
      await settle(context, pending);
    } else if (original) checked.add(original);
    return status;
  });
}
export function replaySmsAccess(context: SmsAccessContext, saved: PendingAttempt, original: SmsAccessOriginal): Promise<SmsAccessResult> {
  return guarded(context, true, async () => {
    if (!checked.has(original)) throw new Error('Check the original access request before retrying.');
    checked.delete(original);
    await verify(context, true);
    const pending = await exact(context, parseManagementPending(saved));
    if (!sameOriginal(context, original, pending)) throw new Error('The original access reference could not be verified.');
    return dispatch(context, pending, original, true);
  });
}
