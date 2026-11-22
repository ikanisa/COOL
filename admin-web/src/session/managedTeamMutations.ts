/* eslint-disable no-control-regex -- Reject controls in untrusted team details. */
import type {AdminRequest} from '../api/client';
import {clearPending, listPending, readPending, retainPending, type PendingAttempt, type PendingIdentity} from '../features/core/pendingAttempt';
import {normalizeAdminEmail} from './adminEmail';
import {lookupInvitation, parseInvitationAttempt, parseInvitationReceipt, type InvitationAttempt, type InvitationReceipt} from './invitationRecovery';
import {bindTeamStorage, TEAM_MANAGE, TEAM_MEMBER_ID, TEAM_OWNER_EMAIL, TEAM_VERIFICATION_REQUIRED} from './teamPolicy';

const inFlight = new Set<string>();
const retryable = new Map<string, {intent: string; checkedAt: number}>();

export interface TeamMutationContext {
  /** Callers must explicitly opt in after qualifying the target deployment. */
  allowMutations: boolean;
  /** Managed invitation protocol version; never inferred from a failed request. */
  invitationVersion?: 1 | 2;
  identity: PendingIdentity;
  request: AdminRequest;
  verify: () => Promise<boolean>;
  current: () => boolean;
}
export interface TeamTarget {
  id: string; email: string; role: 'owner' | 'admin' | 'staff'; status: 'active' | 'invited' | 'revoked';
  invitation: InvitationReceipt | null;
  emailStatus?: string | null; invitationRequestId?: string | null; invitationOperation?: 'invite' | 'resend' | null;
}
export type InvitationAction = {kind: 'invite'; email: string; role: 'admin' | 'staff'; displayName: string} |
  {kind: 'resend' | 'notice_repair'; member: TeamTarget};

function authority(context: TeamMutationContext) {
  const actor = context.identity;
  if (context.allowMutations !== true || actor.role !== 'owner' || actor.email !== TEAM_OWNER_EMAIL || !actor.permissions.includes(TEAM_MANAGE) || !context.current()) throw new Error(TEAM_VERIFICATION_REQUIRED);
}
/** Refuse storage access if the proof or authority changed during an async digest. */
function storage(context: TeamMutationContext): Storage {
  return bindTeamStorage(() => authority(context));
}
function guarded<T>(context: TeamMutationContext, action: () => Promise<T>): Promise<T> {
  authority(context);
  const key = JSON.stringify([context.identity.id, context.identity.sessionId]);
  if (inFlight.has(key)) throw new Error('Wait for the current team access request.');
  inFlight.add(key);
  return action().finally(() => inFlight.delete(key));
}
async function verify(context: TeamMutationContext) {
  authority(context);
  if (!(await context.verify())) throw new Error(TEAM_VERIFICATION_REQUIRED);
  authority(context);
}
function freshKey(): string {
  if (typeof globalThis.crypto?.randomUUID !== 'function') throw new Error('A secure request reference is unavailable.');
  return globalThis.crypto.randomUUID();
}
function target(member: TeamTarget, identity: PendingIdentity) {
  if (!TEAM_MEMBER_ID.test(member.id) || member.id === identity.id || member.role === 'owner' || normalizeAdminEmail(member.email) !== member.email || member.email === TEAM_OWNER_EMAIL || member.status === 'revoked') throw new Error('This account cannot be changed here.');
}
function invitationIntent(action: InvitationAction, identity: PendingIdentity, version: 1 | 2): {resource: string; intent: Record<string, unknown>} {
  if (version !== 1 && version !== 2) throw new Error('The invitation protocol could not be verified.');
  const prefix = version === 2 ? 'team/v2' : 'team', versionField = version === 2 ? {contract_version: 2} : {};
  if (action.kind === 'invite') {
    const email = normalizeAdminEmail(action.email), name = action.displayName.trim();
    if (email === TEAM_OWNER_EMAIL || !['admin', 'staff'].includes(action.role) || name.length > 120 || /[\x00-\x1f\x7f-\x9f]/.test(name)) throw new Error('Check the invitation details.');
    return {resource: version === 2 ? 'v2:invite' : 'invite', intent: {...versionField, operation: 'invite', path: `${prefix}/invite`, staff_id: null, prior_request_id: null, prior_operation: null, body: {email, role: action.role, displayName: name}}};
  }
  const member = action.member, prior = member.invitation;
  target(member, identity);
  if (version === 1) {
    if (action.kind !== 'resend' || member.status !== 'invited' || !['accepted', 'rejected'].includes(String(member.emailStatus)) || typeof member.invitationRequestId !== 'string' || !TEAM_MEMBER_ID.test(member.invitationRequestId) || !['invite', 'resend'].includes(String(member.invitationOperation))) throw new Error('A new email requires a known original invitation.');
    return {resource: `resend:${member.id}`, intent: {operation: 'resend', path: `team/${member.id}/resend`, staff_id: member.id, prior_request_id: member.invitationRequestId, prior_operation: member.invitationOperation, body: {}}};
  }
  if (!prior || prior.contractVersion !== 2 || prior.id !== member.id || prior.accessStatus !== member.status || !TEAM_MEMBER_ID.test(prior.requestId)) throw new Error('Check the original invitation history.');
  if (action.kind === 'resend') {
    if (member.status !== 'invited' || !['accepted', 'rejected'].includes(prior.status)) throw new Error('A new email requires a known original invitation.');
    return {resource: `v2:resend:${member.id}`, intent: {contract_version: 2, operation: 'resend', path: `team/v2/${member.id}/resend`, staff_id: member.id, prior_request_id: prior.requestId, prior_operation: prior.operation, body: {}}};
  }
  if (prior.messageKind !== 'auth_invite' || prior.status !== 'already_registered' || !['invite', 'resend'].includes(prior.operation)) throw new Error('Check the original registered-account request.');
  return {resource: `v2:notice_repair:${member.id}:${prior.requestId}`, intent: {contract_version: 2, operation: 'notice_repair', path: `team/v2/${member.id}/access-notice`, staff_id: member.id, prior_request_id: prior.requestId, prior_operation: prior.operation, body: {sourceRequestId: prior.requestId}}};
}
async function noPending(context: TeamMutationContext) {
  const invitation = await listPending(context.identity, 'team-invitation', TEAM_MANAGE, storage(context));
  const revoke = await listPending(context.identity, 'team-revoke', TEAM_MANAGE, storage(context));
  authority(context);
  if (invitation.length || revoke.length) throw new Error('Check the original team access request before starting another.');
}
function requireCheckpoint(saved: PendingAttempt, current: PendingAttempt | null): PendingAttempt {
  if (!current || current.request_key !== saved.request_key || JSON.stringify(current.intent) !== JSON.stringify(saved.intent)) {
    throw new Error('The original checkpoint could not be verified.');
  }
  return current;
}
async function clearExact(context: TeamMutationContext, saved: PendingAttempt) {
  authority(context);
  const current = await readPending(context.identity, saved.family, saved.resource_id, storage(context));
  authority(context);
  requireCheckpoint(saved, current);
  await clearPending(context.identity, saved.family, saved.resource_id, saved.request_key, storage(context));
  authority(context);
}
function retryKey(context: TeamMutationContext, saved: PendingAttempt) {return JSON.stringify([context.identity.id, context.identity.sessionId, saved.request_key]);}
async function dispatchInvitation(context: TeamMutationContext, saved: PendingAttempt): Promise<InvitationReceipt> {
  const attempt = parseInvitationAttempt(saved), intent = saved.intent;
  authority(context);
  try {
    const body = await context.request(intent.path as string, {authenticated: true, method: 'POST', body: intent.body as Record<string, unknown>, idempotencyKey: saved.request_key});
    authority(context);
    const receipt = parseInvitationReceipt(body, attempt.version);
    if (body.ok !== true || body.outcome !== 'accepted' || receipt.status !== 'accepted' || receipt.duplicate || receipt.operation !== attempt.operation || (attempt.staffId !== null && receipt.id !== attempt.staffId) || (attempt.operation === 'notice_repair' && receipt.sourceRequestId !== attempt.sourceId)) throw new Error('unconfirmed');
    await clearExact(context, saved);
    return receipt;
  } catch {
    throw new Error('The invitation result is not confirmed. Check the original request before continuing.');
  }
}

/** The checkpoint is written and read back before sending, and never automatically replayed. */
export function submitTeamInvitation(context: TeamMutationContext, action: InvitationAction): Promise<InvitationReceipt> {
  return guarded(context, async () => {
    await verify(context);
    const {resource, intent} = invitationIntent(action, context.identity, context.invitationVersion ?? 2);
    await noPending(context);
    const saved = await retainPending(context.identity, 'team-invitation', resource, freshKey(), TEAM_MANAGE, intent, storage(context));
    authority(context);
    return dispatchInvitation(context, saved);
  });
}

/** Check the retained key; only a terminal, correlated receipt clears its checkpoint. */
export function checkTeamInvitation(context: TeamMutationContext, attempt: InvitationAttempt) {
  return guarded(context, async () => {
    await verify(context);
    retryable.delete(retryKey(context, attempt.checkpoint));
    const current = await readPending(context.identity, 'team-invitation', attempt.checkpoint.resource_id, storage(context));
    authority(context);
    const matched = requireCheckpoint(attempt.checkpoint, current);
    const verifiedAttempt = parseInvitationAttempt(matched);
    const result = await lookupInvitation(context.request, verifiedAttempt);
    authority(context);
    if (result.found && result.receipt.status !== 'unknown') await clearExact(context, matched);
    if (!result.found) retryable.set(retryKey(context, matched), {intent: JSON.stringify(matched.intent), checkedAt: Date.now()});
    return result;
  });
}

/** Only an explicit original-key not-found check permits one same-intent retry. */
export function retryTeamInvitation(context: TeamMutationContext, attempt: InvitationAttempt): Promise<InvitationReceipt> {
  return guarded(context, async () => {
    await verify(context);
    const key = retryKey(context, attempt.checkpoint), proof = retryable.get(key);
    retryable.delete(key);
    if (!proof || Date.now() - proof.checkedAt > 300_000 || Date.now() < proof.checkedAt) throw new Error('Check the original request before retrying.');
    const saved = await readPending(context.identity, 'team-invitation', attempt.checkpoint.resource_id, storage(context));
    const otherInvitations = await listPending(context.identity, 'team-invitation', TEAM_MANAGE, storage(context));
    const removals = await listPending(context.identity, 'team-revoke', TEAM_MANAGE, storage(context));
    authority(context);
    if (!saved || saved.request_key !== attempt.checkpoint.request_key || JSON.stringify(saved.intent) !== proof.intent || JSON.stringify(saved.intent) !== JSON.stringify(attempt.checkpoint.intent) || otherInvitations.length !== 1 || otherInvitations[0].request_key !== saved.request_key || removals.length) throw new Error('The original checkpoint could not be verified.');
    return dispatchInvitation(context, saved);
  });
}

/** Revoke has no server idempotency protocol. Its local reference is never sent as an idempotency key. */
export function removeTeamAccess(context: TeamMutationContext, member: TeamTarget): Promise<void> {
  return guarded(context, async () => {
    if (context.invitationVersion === 1) throw new Error('Original removal recovery is unavailable for this team mode.');
    await verify(context); target(member, context.identity); await noPending(context);
    const saved = await retainPending(context.identity, 'team-revoke', member.id, freshKey(), TEAM_MANAGE, {staff_id: member.id, email: member.email, path: `team/${member.id}/revoke`}, storage(context));
    authority(context);
    try {
      const body = await context.request(`team/${member.id}/revoke`, {authenticated: true, method: 'POST', body: {}});
      authority(context);
      if (body.ok !== true) throw new Error('unconfirmed');
      await clearExact(context, saved);
    } catch {
      throw new Error('The removal result is not confirmed. Check the current team access before continuing.');
    }
  });
}

/** A fresh revoked status establishes the desired state, not which request caused it. */
export function checkTeamRemoval(context: TeamMutationContext, saved: PendingAttempt): Promise<boolean> {
  return guarded(context, async () => {
    await verify(context);
    const intent = saved.intent, id = intent.staff_id, email = intent.email;
    if (saved.family !== 'team-revoke' || saved.permission !== TEAM_MANAGE || Object.keys(intent).sort().join(',') !== 'email,path,staff_id' || typeof id !== 'string' || !TEAM_MEMBER_ID.test(id) || id === context.identity.id || saved.resource_id !== id || typeof email !== 'string' || normalizeAdminEmail(email) !== email || email === TEAM_OWNER_EMAIL || intent.path !== `team/${id}/revoke`) throw new Error('The original access checkpoint could not be verified.');
    const retained = await readPending(context.identity, 'team-revoke', id, storage(context));
    authority(context);
    const matched = requireCheckpoint(saved, retained);
    const version = context.invitationVersion ?? 2;
    if (version !== 1 && version !== 2) throw new Error('The team protocol could not be verified.');
    const body = await context.request(version === 1 ? 'team' : 'team/v2', {authenticated: true, method: 'GET'});
    authority(context);
    if ((version === 2 ? body.contractVersion !== 2 : Object.hasOwn(body, 'contractVersion')) || body.canManage !== true || body.currentEmail !== context.identity.email || !Array.isArray(body.members)) throw new Error('The current team access could not be verified.');
    const matches = body.members.filter((value: unknown) => value !== null && typeof value === 'object' && !Array.isArray(value) && (value as Record<string, unknown>).id === id);
    if (matches.length !== 1) throw new Error('The current team access could not be verified.');
    const member = matches[0] as Record<string, unknown>;
    if (member.email !== email || !['admin', 'staff'].includes(String(member.role)) || !['active', 'invited', 'revoked'].includes(String(member.status))) throw new Error('The current team access could not be verified.');
    if (member.status !== 'revoked') return false;
    await clearExact(context, matched);
    return true;
  });
}
