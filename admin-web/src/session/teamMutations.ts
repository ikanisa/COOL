/* eslint-disable no-control-regex -- Reject controls in untrusted team details. */
import type {AdminRequest} from '../api/client';
import {clearPending, listPending, readPending, retainPending, type PendingAttempt, type PendingIdentity} from '../features/core/pendingAttempt';
import {normalizeAdminEmail} from './SessionProvider';
import {lookupInvitation, parseInvitationAttempt, parseInvitationReceipt, type InvitationAttempt, type InvitationReceipt} from './invitationRecovery';
import {sha256Text} from '../features/core/pendingAttempt';
import {withPendingFence, type FenceAccess, type FenceLock} from '../features/operations/pendingFence';

const OWNER = 'info@ikanisa.com';
const PERMISSION = 'admin_users.manage';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const inFlight = new Set<string>();
const retryable = new Map<string, {intent: string; checkedAt: number}>();
const unavailable = 'Verify your current owner sign-in before managing team access.';

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
  if (context.allowMutations !== true || actor.role !== 'owner' || actor.email !== OWNER || !actor.permissions.includes(PERMISSION) || !context.current()) throw new Error(unavailable);
}
/** Refuse storage access if the proof or authority changed during an async digest. */
class TeamCurrentStorage implements Storage {
  constructor(private readonly context: TeamMutationContext) {}
  get length() {return 0;} clear(): void {throw new Error('Unsupported recovery operation.');} key(): string | null {return null;}
  getItem(key: string): string | null {authority(this.context); return sessionStorage.getItem(key);}
  setItem(key: string, value: string): void {authority(this.context); sessionStorage.setItem(key, value);}
  removeItem(key: string): void {authority(this.context); sessionStorage.removeItem(key);}
}
function storage(context: TeamMutationContext): Storage {return new TeamCurrentStorage(context);}
function guarded<T>(context: TeamMutationContext, action: () => Promise<T>): Promise<T> {
  authority(context);
  const key = JSON.stringify([context.identity.id, context.identity.sessionId]);
  if (inFlight.has(key)) throw new Error('Wait for the current team access request.');
  inFlight.add(key);
  return action().finally(() => inFlight.delete(key));
}
async function verify(context: TeamMutationContext) {
  authority(context);
  if (!(await context.verify())) throw new Error(unavailable);
  authority(context);
}
function freshKey(): string {
  if (typeof globalThis.crypto?.randomUUID !== 'function') throw new Error('A secure request reference is unavailable.');
  return globalThis.crypto.randomUUID();
}
function target(member: TeamTarget, identity: PendingIdentity) {
  if (!UUID.test(member.id) || member.id === identity.id || member.role === 'owner' || normalizeAdminEmail(member.email) !== member.email || member.email === OWNER || member.status === 'revoked') throw new Error('This account cannot be changed here.');
}
function invitationIntent(action: InvitationAction, identity: PendingIdentity, version: 1 | 2): {resource: string; intent: Record<string, unknown>} {
  if (version !== 1 && version !== 2) throw new Error('The invitation protocol could not be verified.');
  const prefix = version === 2 ? 'team/v2' : 'team', versionField = version === 2 ? {contract_version: 2} : {};
  if (action.kind === 'invite') {
    const email = normalizeAdminEmail(action.email), name = action.displayName.trim();
    if (email === OWNER || !['admin', 'staff'].includes(action.role) || name.length > 120 || /[\x00-\x1f\x7f-\x9f]/.test(name)) throw new Error('Check the invitation details.');
    return {resource: version === 2 ? 'v2:invite' : 'invite', intent: {...versionField, operation: 'invite', path: `${prefix}/invite`, staff_id: null, prior_request_id: null, prior_operation: null, body: {email, role: action.role, displayName: name}}};
  }
  const member = action.member, prior = member.invitation;
  target(member, identity);
  if (version === 1) {
    if (action.kind !== 'resend' || member.status !== 'invited' || !['accepted', 'rejected'].includes(String(member.emailStatus)) || typeof member.invitationRequestId !== 'string' || !UUID.test(member.invitationRequestId) || !['invite', 'resend'].includes(String(member.invitationOperation))) throw new Error('A new email requires a known original invitation.');
    return {resource: `resend:${member.id}`, intent: {operation: 'resend', path: `team/${member.id}/resend`, staff_id: member.id, prior_request_id: member.invitationRequestId, prior_operation: member.invitationOperation, body: {}}};
  }
  if (!prior || prior.contractVersion !== 2 || prior.id !== member.id || prior.accessStatus !== member.status || !UUID.test(prior.requestId)) throw new Error('Check the original invitation history.');
  if (action.kind === 'resend') {
    if (member.status !== 'invited' || !['accepted', 'rejected'].includes(prior.status)) throw new Error('A new email requires a known original invitation.');
    return {resource: `v2:resend:${member.id}`, intent: {contract_version: 2, operation: 'resend', path: `team/v2/${member.id}/resend`, staff_id: member.id, prior_request_id: prior.requestId, prior_operation: prior.operation, body: {}}};
  }
  if (prior.messageKind !== 'auth_invite' || prior.status !== 'already_registered' || !['invite', 'resend'].includes(prior.operation)) throw new Error('Check the original registered-account request.');
  return {resource: `v2:notice_repair:${member.id}:${prior.requestId}`, intent: {contract_version: 2, operation: 'notice_repair', path: `team/v2/${member.id}/access-notice`, staff_id: member.id, prior_request_id: prior.requestId, prior_operation: prior.operation, body: {sourceRequestId: prior.requestId}}};
}
async function noPending(context: TeamMutationContext) {
  const invitation = await listPending(context.identity, 'team-invitation', PERMISSION, storage(context));
  const revoke = await listPending(context.identity, 'team-revoke', PERMISSION, storage(context));
  authority(context);
  if (invitation.length || revoke.length) throw new Error('Check the original team access request before starting another.');
}
async function clearExact(context: TeamMutationContext, saved: PendingAttempt) {
  authority(context);
  const current = await readPending(context.identity, saved.family, saved.resource_id, storage(context));
  authority(context);
  if (!current || current.request_key !== saved.request_key || JSON.stringify(current.intent) !== JSON.stringify(saved.intent)) throw new Error('The original checkpoint could not be verified.');
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
    const saved = await retainPending(context.identity, 'team-invitation', resource, freshKey(), PERMISSION, intent, storage(context));
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
    if (!current || current.request_key !== attempt.checkpoint.request_key || JSON.stringify(current.intent) !== JSON.stringify(attempt.checkpoint.intent)) throw new Error('The original checkpoint could not be verified.');
    const verifiedAttempt = parseInvitationAttempt(current);
    const result = await lookupInvitation(context.request, verifiedAttempt);
    authority(context);
    if (result.found && result.receipt.status !== 'unknown') await clearExact(context, current);
    if (!result.found) retryable.set(retryKey(context, current), {intent: JSON.stringify(current.intent), checkedAt: Date.now()});
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
    const otherInvitations = await listPending(context.identity, 'team-invitation', PERMISSION, storage(context));
    const removals = await listPending(context.identity, 'team-revoke', PERMISSION, storage(context));
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
    const saved = await retainPending(context.identity, 'team-revoke', member.id, freshKey(), PERMISSION, {staff_id: member.id, email: member.email, path: `team/${member.id}/revoke`}, storage(context));
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
    if (saved.family !== 'team-revoke' || saved.permission !== PERMISSION || Object.keys(intent).sort().join(',') !== 'email,path,staff_id' || typeof id !== 'string' || !UUID.test(id) || id === context.identity.id || saved.resource_id !== id || typeof email !== 'string' || normalizeAdminEmail(email) !== email || email === OWNER || intent.path !== `team/${id}/revoke`) throw new Error('The original access checkpoint could not be verified.');
    const retained = await readPending(context.identity, 'team-revoke', id, storage(context));
    authority(context);
    if (!retained || retained.request_key !== saved.request_key || JSON.stringify(retained.intent) !== JSON.stringify(saved.intent)) throw new Error('The original checkpoint could not be verified.');
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
    await clearExact(context, retained);
    return true;
  });
}

// Cloudflare's opt-in recovery protocol is deliberately distinct from the
// managed invitation contract. Its original key is resolved by the server and
// a repeated POST only reads an existing reservation; it never resends email.
const CF_FAMILY = 'team-cloudflare-v1', CF_RESOURCE = 'team', CF_PREFIX = 'team/cloudflare/v1';
export interface CloudflareTeamContext {
  identity: PendingIdentity; principalId: string; request: AdminRequest;
  allowMutations: boolean; isEnabled?: () => boolean; current: () => boolean;
  storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;
}
export interface CloudflareTeamTarget {
  memberId: string; email: string; role: 'admin' | 'staff'; accessStatus: 'active' | 'invited' | 'revoked';
  authVersion: number; invitationCount: number; canResend: boolean;
}
export type CloudflareTeamAction = {kind: 'invite'; email: string; role: 'admin' | 'staff'; displayName: string} |
  {kind: 'resend' | 'revoke'; member: CloudflareTeamTarget};
export interface CloudflareTeamReceipt {
  requestId: string; operation: 'invite' | 'resend' | 'revoke'; memberId: string; email: string; role: 'admin' | 'staff';
  accessStatus: 'invited' | 'revoked'; authVersion: number; eventId: string | null; emailStatus: 'accepted' | 'unknown' | null;
}
export type CloudflareTeamPending = {kind: 'ready'; revision: string} |
  {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type CloudflareTeamResult = {status: 'recorded' | 'unknown'; requestKey: string; receipt: CloudflareTeamReceipt} |
  {status: 'existing'; pending: CloudflareTeamPending};

function cfInvalid(): never {throw new Error('The original team request could not be verified.');}
function cfCurrent(context: CloudflareTeamContext) {
  const actor = context.identity, expires = Date.parse(actor.expiresAt);
  if (actor.role !== 'owner' || actor.email !== OWNER || !actor.permissions.includes(PERMISSION) || !UUID.test(context.principalId) ||
      !Number.isFinite(expires) || expires <= Date.now() || !context.current()) throw new Error(unavailable);
}
function cfWrite(context: CloudflareTeamContext) {
  cfCurrent(context);
  if (!context.allowMutations || context.isEnabled && !context.isEnabled()) throw new Error('Team access changes are not enabled.');
}
const cfObject = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === 'object' && !Array.isArray(value);
const cfExact = (value: Record<string, unknown>, keys: string[]) => Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
const cfPositive = (value: unknown): value is number => typeof value === 'number' && Number.isSafeInteger(value) && value >= 1;
const cfCount = (value: unknown): value is number => typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
function cfStableJson(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(cfStableJson).join(',')}]`;
  const object = value as Record<string, unknown>;
  return `{${Object.keys(object).sort().map(key => `${JSON.stringify(key)}:${cfStableJson(object[key])}`).join(',')}}`;
}
async function cfRequestId(context: CloudflareTeamContext, key: string): Promise<string> {
  const hash = await sha256Text(`collect-admin-team-v1:${context.principalId}:${key}`); cfCurrent(context);
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-4${hash.slice(13, 16)}-8${hash.slice(17, 20)}-${hash.slice(20, 32)}`;
}
async function cfPrincipalHash(context: CloudflareTeamContext): Promise<string> {
  const hash = await sha256Text(`collect-admin-team-principal-v1:${context.principalId}`); cfCurrent(context); return hash;
}
class CloudflareTeamStorage implements Storage {
  constructor(private readonly context: CloudflareTeamContext) {}
  get length() {return 0;} clear(): void {throw new Error('Unsupported recovery operation.');} key(): string | null {return null;}
  getItem(key: string): string | null {cfCurrent(this.context); return (this.context.storage ?? sessionStorage).getItem(key);}
  setItem(key: string, value: string): void {cfCurrent(this.context); (this.context.storage ?? sessionStorage).setItem(key, value);}
  removeItem(key: string): void {cfCurrent(this.context); (this.context.storage ?? sessionStorage).removeItem(key);}
}
function cfStorage(context: CloudflareTeamContext) {return new CloudflareTeamStorage(context);}
async function cfFence<T>(context: CloudflareTeamContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  cfCurrent(context);
  return withPendingFence({identity: context.identity, family: CF_FAMILY, resourceId: CF_RESOURCE, isCurrent: () => {
    try {cfCurrent(context); return true;} catch {return false;}
  }, storage: context.sharedStorage, lock: context.lock}, work);
}
function cfTarget(value: unknown, id: string, actor: PendingIdentity): CloudflareTeamTarget {
  if (!cfObject(value) || !cfExact(value, ['contractVersion','memberId','email','role','accessStatus','authVersion','invitationCount','canResend']) ||
      value.contractVersion !== 1 || value.memberId !== id || id === actor.id || !UUID.test(id) || typeof value.email !== 'string' ||
      normalizeAdminEmail(value.email) !== value.email || value.email === OWNER || !['admin','staff'].includes(String(value.role)) ||
      !['invited','active','revoked'].includes(String(value.accessStatus)) || !cfPositive(value.authVersion) || !cfCount(value.invitationCount) ||
      typeof value.canResend !== 'boolean' || value.canResend && (value.accessStatus !== 'invited' || value.invitationCount === 0)) return cfInvalid();
  return value as unknown as CloudflareTeamTarget;
}
export async function readCloudflareTeamTarget(context: CloudflareTeamContext, id: string): Promise<CloudflareTeamTarget> {
  cfCurrent(context); if (!UUID.test(id)) return cfInvalid();
  const value = await context.request(`${CF_PREFIX}/targets/${id}`, {authenticated: true}); cfCurrent(context); return cfTarget(value, id, context.identity);
}
function cfActionIntent(action: CloudflareTeamAction): Record<string, unknown> {
  if (action.kind === 'invite') {
    const email = normalizeAdminEmail(action.email), displayName = action.displayName.trim();
    if (email === OWNER || !['admin','staff'].includes(action.role) || displayName.length > 120 || displayName.length === 1 || /[\x00-\x1f\x7f-\x9f]/.test(displayName)) return cfInvalid();
    return {operation: 'invite', path: `${CF_PREFIX}/invite`, member_id: null, email, role: action.role, body: {email, role: action.role, displayName}};
  }
  const member = action.member;
  if (!UUID.test(member.memberId) || normalizeAdminEmail(member.email) !== member.email || member.email === OWNER || !['admin','staff'].includes(member.role) ||
      !cfPositive(member.authVersion) || member.accessStatus === 'revoked') return cfInvalid();
  if (action.kind === 'resend') {
    if (!member.canResend || member.accessStatus !== 'invited' || !cfPositive(member.invitationCount)) return cfInvalid();
    return {operation: 'resend', path: `${CF_PREFIX}/${member.memberId}/resend`, member_id: member.memberId, email: member.email, role: member.role,
      body: {expectedAuthVersion: member.authVersion, expectedInvitationCount: member.invitationCount}};
  }
  return {operation: 'revoke', path: `${CF_PREFIX}/${member.memberId}/revoke`, member_id: member.memberId, email: member.email, role: member.role,
    body: {expectedAuthVersion: member.authVersion, expectedStatus: member.accessStatus}};
}
async function cfAttemptValid(context: CloudflareTeamContext, saved: PendingAttempt): Promise<boolean> {
  if (saved.family !== CF_FAMILY || saved.resource_id !== CF_RESOURCE || saved.permission !== PERMISSION || !UUID.test(saved.request_key) ||
      !cfExact(saved.intent, ['model','principal_sha256','operation','path','member_id','email','role','body']) ||
      saved.intent.model !== 'canonical_evidence_ledger' || saved.intent.principal_sha256 !== await cfPrincipalHash(context) ||
      !cfObject(saved.intent.body) || typeof saved.intent.email !== 'string' || !['admin','staff'].includes(String(saved.intent.role))) return false;
  const value = saved.intent, b = value.body as Record<string, unknown>;
  try {
    if (normalizeAdminEmail(value.email as string) !== value.email || value.email === OWNER) return false;
    if (value.operation === 'invite') return value.member_id === null && value.path === `${CF_PREFIX}/invite` &&
      cfExact(b, ['email','role','displayName']) && b.email === value.email && b.role === value.role && typeof b.displayName === 'string' &&
      b.displayName === b.displayName.trim() && b.displayName.length <= 120 && b.displayName.length !== 1 && !/[\x00-\x1f\x7f-\x9f]/.test(b.displayName);
    if (typeof value.member_id !== 'string' || !UUID.test(value.member_id) || value.member_id === context.identity.id) return false;
    if (value.operation === 'resend') return value.path === `${CF_PREFIX}/${value.member_id}/resend` &&
      cfExact(b, ['expectedAuthVersion','expectedInvitationCount']) && cfPositive(b.expectedAuthVersion) && cfPositive(b.expectedInvitationCount);
    return value.operation === 'revoke' && value.path === `${CF_PREFIX}/${value.member_id}/revoke` &&
      cfExact(b, ['expectedAuthVersion','expectedStatus']) && cfPositive(b.expectedAuthVersion) && ['active','invited'].includes(String(b.expectedStatus));
  } catch {return false;}
}
async function cfRestore(context: CloudflareTeamContext, access: FenceAccess): Promise<CloudflareTeamPending> {
  cfCurrent(context); const state = access.read(); if (state.kind === 'foreign') return {kind: 'foreign'};
  const saved = await readPending(context.identity, CF_FAMILY, CF_RESOURCE, cfStorage(context));
  const attempt = saved && await cfAttemptValid(context, saved) ? saved : null; cfCurrent(context);
  if (state.kind === 'owned') {
    if (saved && state.requestKey !== saved.request_key) return cfInvalid();
    return {kind: 'owned', requestKey: state.requestKey, attempt};
  }
  if (saved) {
    if (!UUID.test(saved.request_key)) return cfInvalid();
    access.reserve(saved.request_key, state.revision); return {kind: 'owned', requestKey: saved.request_key, attempt};
  }
  return {kind: 'ready', revision: state.revision};
}
export function restoreCloudflareTeam(context: CloudflareTeamContext): Promise<CloudflareTeamPending> {
  return cfFence(context, access => cfRestore(context, access));
}
async function cfReceipt(context: CloudflareTeamContext, key: string, body: unknown, attempt: PendingAttempt | null): Promise<CloudflareTeamReceipt | null> {
  if (!cfObject(body) || body.ok !== true || typeof body.found !== 'boolean' || body.contractVersion !== 1) return cfInvalid();
  if (!body.found) {if (!cfExact(body, ['ok','found','contractVersion'])) return cfInvalid(); return null;}
  if (!cfExact(body, ['ok','found','contractVersion','requestId','operation','memberId','email','role','accessStatus','authVersion','eventId','emailStatus','intentSha256']) ||
      body.requestId !== await cfRequestId(context, key) || !['invite','resend','revoke'].includes(String(body.operation)) ||
      typeof body.intentSha256 !== 'string' || !/^[a-f0-9]{64}$/.test(body.intentSha256) ||
      typeof body.memberId !== 'string' || !UUID.test(body.memberId) || body.memberId === context.identity.id || typeof body.email !== 'string' ||
      normalizeAdminEmail(body.email) !== body.email || body.email === OWNER || !['admin','staff'].includes(String(body.role)) || !cfPositive(body.authVersion) ||
      (body.operation === 'revoke' ? body.accessStatus !== 'revoked' || body.eventId !== null || body.emailStatus !== null :
        body.accessStatus !== 'invited' || body.eventId !== body.requestId || !['accepted','unknown'].includes(String(body.emailStatus)))) return cfInvalid();
  if (attempt) {
    if (!await cfAttemptValid(context, attempt)) return cfInvalid();
    const intent = attempt.intent, source = intent.body as Record<string, unknown>;
    const intentHash = await sha256Text(cfStableJson({path: `/${String(intent.path)}`, body: source})); cfCurrent(context);
    if (body.intentSha256 !== intentHash || intent.operation !== body.operation || intent.email !== body.email || intent.role !== body.role ||
        (intent.member_id !== null && intent.member_id !== body.memberId) ||
        (body.operation === 'resend' && body.authVersion !== source.expectedAuthVersion) ||
        (body.operation === 'revoke' && body.authVersion !== (source.expectedAuthVersion as number) + 1)) return cfInvalid();
  }
  const {requestId, operation, memberId, email, role, accessStatus, authVersion, eventId, emailStatus} = body;
  return {requestId, operation, memberId, email, role, accessStatus, authVersion, eventId, emailStatus} as CloudflareTeamReceipt;
}
async function cfLookup(context: CloudflareTeamContext, saved: Extract<CloudflareTeamPending, {kind:'owned'}>): Promise<CloudflareTeamReceipt | null> {
  cfCurrent(context);
  const body = await context.request(`${CF_PREFIX}/request-status`, {authenticated: true, method: 'GET', idempotencyKey: saved.requestKey});
  cfCurrent(context); return cfReceipt(context, saved.requestKey, body, saved.attempt);
}
async function cfClear(context: CloudflareTeamContext, access: FenceAccess, saved: Extract<CloudflareTeamPending, {kind:'owned'}>) {
  if (!saved.attempt) return cfInvalid();
  await clearPending(context.identity, CF_FAMILY, CF_RESOURCE, saved.requestKey, cfStorage(context));
  cfCurrent(context); access.clear(saved.requestKey);
}
async function cfDispatch(context: CloudflareTeamContext, access: FenceAccess, saved: Extract<CloudflareTeamPending, {kind:'owned'}>): Promise<CloudflareTeamResult> {
  if (!saved.attempt || !await cfAttemptValid(context, saved.attempt)) return cfInvalid();
  try {
    cfWrite(context); const intent = saved.attempt.intent;
    const response = await context.request(intent.path as string, {authenticated: true, method: 'POST', body: intent.body as Record<string, unknown>, idempotencyKey: saved.requestKey});
    cfCurrent(context); const receipt = await cfReceipt(context, saved.requestKey, response, saved.attempt); if (!receipt) return cfInvalid();
    if (receipt.emailStatus !== 'unknown') await cfClear(context, access, saved);
    return {status: receipt.emailStatus === 'unknown' ? 'unknown' : 'recorded', requestKey: saved.requestKey, receipt};
  } catch {throw new Error('The team result is unconfirmed. Check the original request before continuing.');}
}
export async function submitCloudflareTeam(context: CloudflareTeamContext, action: CloudflareTeamAction, observedRevision: string): Promise<CloudflareTeamResult> {
  cfWrite(context); const intent = cfActionIntent(action);
  return cfFence(context, async access => {
    const existing = await cfRestore(context, access); if (existing.kind !== 'ready') return {status:'existing', pending:existing};
    const legacyInvites = await listPending(context.identity, 'team-invitation', PERMISSION, cfStorage(context));
    const legacyRemovals = await listPending(context.identity, 'team-revoke', PERMISSION, cfStorage(context));
    if (legacyInvites.length || legacyRemovals.length) throw new Error('Check the original team access request before starting another.');
    if (action.kind !== 'invite') {
      const latest = await readCloudflareTeamTarget(context, action.member.memberId);
      if (JSON.stringify(latest) !== JSON.stringify(action.member)) throw new Error('The team account changed. Review it again.');
    }
    cfWrite(context); const key = (context.createKey ?? (() => crypto.randomUUID()))(); if (!UUID.test(key)) return cfInvalid();
    const binding = await cfPrincipalHash(context); cfWrite(context); access.reserve(key, observedRevision);
    let saved: PendingAttempt;
    try {saved = await retainPending(context.identity, CF_FAMILY, CF_RESOURCE, key, PERMISSION, {model:'canonical_evidence_ledger', principal_sha256:binding, ...intent}, cfStorage(context));}
    catch {throw new Error(`The original team reference ${key} requires review.`);}
    if (!context.current() || context.isEnabled && !context.isEnabled()) throw new Error(`The original team reference ${key} requires review.`);
    return cfDispatch(context, access, {kind:'owned', requestKey:key, attempt:saved});
  });
}
/** Only the original key is checked; an unknown email state remains unresolved. */
export async function checkCloudflareTeam(context: CloudflareTeamContext, pending: CloudflareTeamPending): Promise<CloudflareTeamReceipt | null> {
  if (pending.kind !== 'owned') return cfInvalid();
  return cfFence(context, async access => {
    const saved = await cfRestore(context, access);
    if (saved.kind !== 'owned' || saved.requestKey !== pending.requestKey) return cfInvalid();
    const receipt = await cfLookup(context, saved);
    if (receipt && receipt.emailStatus !== 'unknown' && saved.attempt) await cfClear(context, access, saved);
    return receipt;
  });
}
/** The explicit retry can reserve/send once if the original never committed. */
export async function retryCloudflareTeam(context: CloudflareTeamContext, pending: CloudflareTeamPending): Promise<CloudflareTeamResult> {
  cfWrite(context); if (pending.kind !== 'owned' || !pending.attempt) return cfInvalid();
  return cfFence(context, async access => {
    const saved = await cfRestore(context, access);
    if (saved.kind !== 'owned' || !saved.attempt || saved.requestKey !== pending.requestKey || JSON.stringify(saved.attempt.intent) !== JSON.stringify(pending.attempt!.intent)) return cfInvalid();
    const receipt = await cfLookup(context, saved);
    if (receipt) {
      if (receipt.emailStatus !== 'unknown') await cfClear(context, access, saved);
      return {status:receipt.emailStatus === 'unknown'?'unknown':'recorded', requestKey:saved.requestKey, receipt};
    }
    cfWrite(context); return cfDispatch(context, access, saved);
  });
}
