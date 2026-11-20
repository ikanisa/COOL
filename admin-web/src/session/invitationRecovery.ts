/* eslint-disable no-control-regex -- Reject control characters in retained invitation data. */
import type {AdminRequest, JsonObject} from '../api/client';
import type {PendingAttempt} from '../features/core/pendingAttempt';
import {normalizeAdminEmail} from './SessionProvider';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function object(value: unknown): value is JsonObject {return !!value && typeof value === 'object' && !Array.isArray(value);}
function invalid(): never {throw new Error('The original invitation could not be verified.');}
export interface InvitationReceipt {
  id: string; requestId: string; operation: 'invite' | 'resend' | 'notice_repair';
  messageKind: 'auth_invite' | 'access_notice'; status: 'accepted' | 'rejected' | 'unknown' | 'already_registered';
  accessStatus: 'active' | 'invited' | 'revoked'; replayed: boolean; duplicate: boolean;
  sourceRequestId: string | null; contractVersion: 1 | 2;
}
export interface InvitationAttempt {checkpoint: PendingAttempt; operation: InvitationReceipt['operation']; staffId: string | null; sourceId: string | null; version: 1 | 2}

export function parseInvitationReceipt(value: unknown, version: 1 | 2): InvitationReceipt {
  if (!object(value) || typeof value.id !== 'string' || !UUID.test(value.id) || typeof value.requestId !== 'string' || !UUID.test(value.requestId) || !['invite', 'resend', 'notice_repair'].includes(String(value.operation)) || !['active', 'invited', 'revoked'].includes(String(value.accessStatus)) || typeof value.replayed !== 'boolean' || typeof value.duplicate !== 'boolean') invalid();
  if (version === 1 && (value.operation === 'notice_repair' || ['contractVersion', 'messageKind', 'noticeStatus', 'sourceRequestId'].some((key) => Object.hasOwn(value, key)))) invalid();
  if (version === 2 && (value.contractVersion !== 2 || !Object.hasOwn(value, 'sourceRequestId') || (value.sourceRequestId !== null && (typeof value.sourceRequestId !== 'string' || !UUID.test(value.sourceRequestId))))) invalid();
  const kind = version === 1 ? 'auth_invite' : value.messageKind;
  const status = kind === 'auth_invite' ? value.emailStatus : value.noticeStatus;
  if (kind === 'access_notice' && (Object.hasOwn(value, 'emailStatus') || !['accepted', 'rejected', 'unknown'].includes(String(status)) || (value.operation === 'notice_repair' && value.sourceRequestId === null))) invalid();
  if (kind === 'auth_invite' && (Object.hasOwn(value, 'noticeStatus') || value.operation === 'notice_repair' || !['accepted', 'rejected', 'unknown', 'already_registered'].includes(String(status)))) invalid();
  if (kind !== 'auth_invite' && kind !== 'access_notice') invalid();
  return {id: value.id, requestId: value.requestId, operation: value.operation as InvitationReceipt['operation'], messageKind: kind, status: status as InvitationReceipt['status'], accessStatus: value.accessStatus as InvitationReceipt['accessStatus'], replayed: value.replayed, duplicate: value.duplicate, sourceRequestId: version === 1 ? null : value.sourceRequestId as string | null, contractVersion: version};
}

/** Validate an existing Flutter-compatible checkpoint without changing it. */
export function parseInvitationAttempt(checkpoint: PendingAttempt): InvitationAttempt {
  if (checkpoint.family !== 'team-invitation' || checkpoint.permission !== 'admin_users.manage' || !/^[A-Za-z0-9._:-]{8,200}$/.test(checkpoint.request_key)) invalid();
  const value = checkpoint.intent;
  const allowed = new Set(['contract_version', 'operation', 'path', 'staff_id', 'prior_request_id', 'prior_operation', 'body']);
  if (Object.keys(value).some((key) => !allowed.has(key)) || !object(value.body)) invalid();
  const version = Object.hasOwn(value, 'contract_version') ? value.contract_version === 2 ? 2 : invalid() : 1;
  const prefix = version === 2 ? 'team/v2' : 'team';
  const operation = value.operation, staffId = value.staff_id, priorId = value.prior_request_id, prior = value.prior_operation, body = value.body;
  if (operation === 'invite') {
    if (staffId !== null || priorId !== null || prior !== null || value.path !== `${prefix}/invite` || checkpoint.resource_id !== (version === 2 ? 'v2:invite' : 'invite') || Object.keys(body).sort().join(',') !== 'displayName,email,role' || typeof body.email !== 'string' || normalizeAdminEmail(body.email) !== body.email || body.email === 'info@ikanisa.com' || !['admin', 'staff'].includes(String(body.role)) || typeof body.displayName !== 'string' || body.displayName.trim() !== body.displayName || body.displayName.length > 120 || /[\x00-\x1f\x7f-\x9f]/.test(body.displayName)) invalid();
    return {checkpoint, operation, staffId: null, sourceId: null, version};
  }
  if (typeof staffId !== 'string' || !UUID.test(staffId) || typeof priorId !== 'string' || !UUID.test(priorId) || !['invite', 'resend', 'notice_repair'].includes(String(prior))) invalid();
  if (operation === 'resend') {
    if ((version === 1 && prior === 'notice_repair') || value.path !== `${prefix}/${staffId}/resend` || checkpoint.resource_id !== `${version === 2 ? 'v2:' : ''}resend:${staffId}` || Object.keys(body).length !== 0) invalid();
    return {checkpoint, operation, staffId, sourceId: priorId, version};
  }
  if (operation === 'notice_repair' && version === 2 && prior !== 'notice_repair' && value.path === `${prefix}/${staffId}/access-notice` && checkpoint.resource_id === `v2:notice_repair:${staffId}:${priorId}` && Object.keys(body).length === 1 && body.sourceRequestId === priorId) return {checkpoint, operation, staffId, sourceId: priorId, version};
  return invalid();
}

/** Query the original key only. This function never posts, retries or clears. */
export async function lookupInvitation(request: AdminRequest, attempt: InvitationAttempt): Promise<{found: false} | {found: true; receipt: InvitationReceipt}> {
  const result = await request(attempt.version === 2 ? 'team/v2/invitation-status' : 'team/invitation-status', {authenticated: true, method: 'GET', idempotencyKey: attempt.checkpoint.request_key});
  if (result.ok !== true) invalid();
  if (result.found === false) {
    if (attempt.version === 1 ? Object.keys(result).length !== 2 : Object.keys(result).length !== 3 || result.contractVersion !== 2) invalid();
    return {found: false};
  }
  if (result.found !== true) invalid();
  const receipt = parseInvitationReceipt(result, attempt.version);
  if (receipt.operation !== attempt.operation || (attempt.staffId !== null && receipt.id !== attempt.staffId) || (attempt.operation === 'notice_repair' && receipt.sourceRequestId !== attempt.sourceId)) invalid();
  return {found: true, receipt};
}
