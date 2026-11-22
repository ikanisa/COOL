import {isJsonObject, type JsonObject} from '../api/contracts';
import {parseInvitationReceipt, type InvitationReceipt} from './invitationRecovery';
import type {AdminUser} from './sessionResponses';
import type {VerificationMode} from './returnLocation';
import {TEAM_MANAGE, TEAM_MEMBER_ID, TEAM_OWNER_EMAIL} from './teamPolicy';

export interface TeamMember {
  id: string;
  email: string;
  role: 'owner' | 'admin' | 'staff';
  status: 'active' | 'invited' | 'revoked';
  displayName: string | null;
  publicId: string | null;
  emailStatus: string | null;
  invitationKind: 'auth_invite' | 'access_notice' | null;
  invitation: InvitationReceipt | null;
  invitationRequestId: string | null;
  invitationOperation: 'invite' | 'resend' | null;
}
export interface Team {currentEmail: string; canManage: boolean; contractVersion: 1 | 2; members: TeamMember[]; permissionsByRole: Record<string, string[]>}

export function teamDirectoryPath(actor: AdminUser, mode: VerificationMode, version: 1 | 2, now = Date.now()): 'team' | 'team/v2' {
  const verifiedAt = actor.emailVerifiedAt ? Date.parse(actor.emailVerifiedAt) : NaN;
  const owner = actor.role === 'owner' && actor.email.toLowerCase() === TEAM_OWNER_EMAIL && actor.permissions.includes(TEAM_MANAGE);
  return version === 2 && mode === 'email' && owner && Number.isFinite(verifiedAt) &&
    verifiedAt <= now && now - verifiedAt <= 300_000 ? 'team/v2' : 'team';
}

export function parseTeam(body: JsonObject, actor: AdminUser, allowLegacyStatus = false): Team {
  if (body.currentEmail !== actor.email || typeof body.canManage !== 'boolean' || !Array.isArray(body.members) || body.members.length > 1000 || !isJsonObject(body.permissionsByRole)) throw new Error('The team list could not be verified.');
  if (body.canManage && (actor.role !== 'owner' || actor.email.toLowerCase() !== TEAM_OWNER_EMAIL || !actor.permissions.includes(TEAM_MANAGE))) throw new Error('The team management authority could not be verified.');
  const v2 = Object.hasOwn(body, 'contractVersion');
  if (v2 && (body.contractVersion !== 2 || body.canManage !== true)) throw new Error('The team invitation version could not be verified.');
  const permissionsByRole: Record<string, string[]> = {};
  for (const [role, values] of Object.entries(body.permissionsByRole)) {
    if (!['owner', 'admin', 'staff'].includes(role) || !Array.isArray(values) || !values.every((value) => typeof value === 'string')) throw new Error('The team access policy could not be verified.');
    permissionsByRole[role] = values as string[];
  }
  const seen = new Set<string>();
  const members = body.members.map((value): TeamMember => {
    if (!isJsonObject(value) || typeof value.id !== 'string' || !value.id || value.id.length > 200 || seen.has(value.id) || typeof value.email !== 'string' || !value.email || !['owner', 'admin', 'staff'].includes(String(value.role)) || !['active', 'invited', 'revoked'].includes(String(value.status)) || (value.displayName != null && typeof value.displayName !== 'string') || (value.publicId != null && typeof value.publicId !== 'string') || (value.emailStatus != null && !['accepted', 'rejected', 'unknown', 'already_registered', ...(allowLegacyStatus ? ['failed', 'pending'] : [])].includes(String(value.emailStatus)))) throw new Error('The team list could not be verified.');
    let receipt: InvitationReceipt | null = null;
    const requestId = value.invitationRequestId ?? null, operation = value.invitationOperation ?? null;
    if (v2) {
      if (!Object.hasOwn(value, 'invitation') || Object.hasOwn(value, 'emailStatus') || Object.hasOwn(value, 'noticeStatus')) throw new Error('The team invitation could not be verified.');
      if (value.invitation !== null) {receipt = parseInvitationReceipt(value.invitation, 2); if (receipt.id !== value.id || receipt.accessStatus !== value.status) throw new Error('The team invitation target changed.');}
    } else if (!allowLegacyStatus) {
      const hasStatus = value.emailStatus != null;
      if ((requestId === null) !== (operation === null) || hasStatus !== (requestId !== null) || (requestId !== null && (typeof requestId !== 'string' || !TEAM_MEMBER_ID.test(requestId) || !['invite', 'resend'].includes(String(operation))))) throw new Error('The team invitation history could not be verified.');
    }
    seen.add(value.id);
    return {id: value.id, email: value.email, role: value.role as TeamMember['role'], status: value.status as TeamMember['status'], displayName: (value.displayName as string | null | undefined) ?? null, publicId: (value.publicId as string | null | undefined) ?? null, emailStatus: receipt?.status ?? (value.emailStatus as string | null | undefined) ?? null, invitationKind: receipt?.messageKind ?? (value.emailStatus != null ? 'auth_invite' : null), invitation: receipt, invitationRequestId: typeof requestId === 'string' ? requestId : null, invitationOperation: operation === 'invite' || operation === 'resend' ? operation : null};
  });
  return {currentEmail: body.currentEmail, canManage: body.canManage, contractVersion: v2 ? 2 : 1, members, permissionsByRole};
}

export function invitationStatus(value: string | null, kind: TeamMember['invitationKind']): string | null {
  const label = kind === 'access_notice' ? 'Access notice' : 'Invitation';
  if (value === 'accepted') return `${label} accepted for sending`;
  if (value === 'rejected') return `${label} request rejected`;
  if (value === 'unknown') return `${label} sending unconfirmed`;
  if (value === 'failed') return 'Invitation email sending could not be confirmed';
  if (value === 'pending') return 'Invitation email sending is unconfirmed';
  if (value === 'already_registered') return 'Account already registered';
  return null;
}
