/* eslint-disable no-control-regex -- Reject controls in untrusted team details. */
import type {AdminRequest} from '../api/client';
import {clearPending, listPending, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity} from '../features/core/pendingAttempt';
import {withPendingFence, type FenceAccess, type FenceLock} from '../features/operations/pendingFence';
import {normalizeAdminEmail} from './adminEmail';
import {bindTeamStorage, TEAM_MANAGE, TEAM_MEMBER_ID, TEAM_OWNER_EMAIL, TEAM_VERIFICATION_REQUIRED} from './teamPolicy';

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
  if (actor.role !== 'owner' || actor.email !== TEAM_OWNER_EMAIL || !actor.permissions.includes(TEAM_MANAGE) || !TEAM_MEMBER_ID.test(context.principalId) ||
      !Number.isFinite(expires) || expires <= Date.now() || !context.current()) throw new Error(TEAM_VERIFICATION_REQUIRED);
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
function cfStorage(context: CloudflareTeamContext): Storage {
  return bindTeamStorage(() => cfCurrent(context), () => context.storage ?? sessionStorage);
}
async function cfFence<T>(context: CloudflareTeamContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  cfCurrent(context);
  return withPendingFence({identity: context.identity, family: CF_FAMILY, resourceId: CF_RESOURCE, isCurrent: () => {
    try {cfCurrent(context); return true;} catch {return false;}
  }, storage: context.sharedStorage, lock: context.lock}, work);
}
function cfTarget(value: unknown, id: string, actor: PendingIdentity): CloudflareTeamTarget {
  if (!cfObject(value) || !cfExact(value, ['contractVersion','memberId','email','role','accessStatus','authVersion','invitationCount','canResend']) ||
      value.contractVersion !== 1 || value.memberId !== id || id === actor.id || !TEAM_MEMBER_ID.test(id) || typeof value.email !== 'string' ||
      normalizeAdminEmail(value.email) !== value.email || value.email === TEAM_OWNER_EMAIL || !['admin','staff'].includes(String(value.role)) ||
      !['invited','active','revoked'].includes(String(value.accessStatus)) || !cfPositive(value.authVersion) || !cfCount(value.invitationCount) ||
      typeof value.canResend !== 'boolean' || value.canResend && (value.accessStatus !== 'invited' || value.invitationCount === 0)) return cfInvalid();
  return value as unknown as CloudflareTeamTarget;
}
export async function readCloudflareTeamTarget(context: CloudflareTeamContext, id: string): Promise<CloudflareTeamTarget> {
  cfCurrent(context); if (!TEAM_MEMBER_ID.test(id)) return cfInvalid();
  const value = await context.request(`${CF_PREFIX}/targets/${id}`, {authenticated: true}); cfCurrent(context); return cfTarget(value, id, context.identity);
}
function cfActionIntent(action: CloudflareTeamAction): Record<string, unknown> {
  if (action.kind === 'invite') {
    const email = normalizeAdminEmail(action.email), displayName = action.displayName.trim();
    if (email === TEAM_OWNER_EMAIL || !['admin','staff'].includes(action.role) || displayName.length > 120 || displayName.length === 1 || /[\x00-\x1f\x7f-\x9f]/.test(displayName)) return cfInvalid();
    return {operation: 'invite', path: `${CF_PREFIX}/invite`, member_id: null, email, role: action.role, body: {email, role: action.role, displayName}};
  }
  const member = action.member;
  if (!TEAM_MEMBER_ID.test(member.memberId) || normalizeAdminEmail(member.email) !== member.email || member.email === TEAM_OWNER_EMAIL || !['admin','staff'].includes(member.role) ||
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
  if (saved.family !== CF_FAMILY || saved.resource_id !== CF_RESOURCE || saved.permission !== TEAM_MANAGE || !TEAM_MEMBER_ID.test(saved.request_key) ||
      !cfExact(saved.intent, ['model','principal_sha256','operation','path','member_id','email','role','body']) ||
      saved.intent.model !== 'canonical_evidence_ledger' || saved.intent.principal_sha256 !== await cfPrincipalHash(context) ||
      !cfObject(saved.intent.body) || typeof saved.intent.email !== 'string' || !['admin','staff'].includes(String(saved.intent.role))) return false;
  const value = saved.intent, b = value.body as Record<string, unknown>;
  try {
    if (normalizeAdminEmail(value.email as string) !== value.email || value.email === TEAM_OWNER_EMAIL) return false;
    if (value.operation === 'invite') return value.member_id === null && value.path === `${CF_PREFIX}/invite` &&
      cfExact(b, ['email','role','displayName']) && b.email === value.email && b.role === value.role && typeof b.displayName === 'string' &&
      b.displayName === b.displayName.trim() && b.displayName.length <= 120 && b.displayName.length !== 1 && !/[\x00-\x1f\x7f-\x9f]/.test(b.displayName);
    if (typeof value.member_id !== 'string' || !TEAM_MEMBER_ID.test(value.member_id) || value.member_id === context.identity.id) return false;
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
    if (!TEAM_MEMBER_ID.test(saved.request_key)) return cfInvalid();
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
      typeof body.memberId !== 'string' || !TEAM_MEMBER_ID.test(body.memberId) || body.memberId === context.identity.id || typeof body.email !== 'string' ||
      normalizeAdminEmail(body.email) !== body.email || body.email === TEAM_OWNER_EMAIL || !['admin','staff'].includes(String(body.role)) || !cfPositive(body.authVersion) ||
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
    const legacyInvites = await listPending(context.identity, 'team-invitation', TEAM_MANAGE, cfStorage(context));
    const legacyRemovals = await listPending(context.identity, 'team-revoke', TEAM_MANAGE, cfStorage(context));
    if (legacyInvites.length || legacyRemovals.length) throw new Error('Check the original team access request before starting another.');
    if (action.kind !== 'invite') {
      const latest = await readCloudflareTeamTarget(context, action.member.memberId);
      if (JSON.stringify(latest) !== JSON.stringify(action.member)) throw new Error('The team account changed. Review it again.');
    }
    cfWrite(context); const key = (context.createKey ?? (() => crypto.randomUUID()))(); if (!TEAM_MEMBER_ID.test(key)) return cfInvalid();
    const binding = await cfPrincipalHash(context); cfWrite(context); access.reserve(key, observedRevision);
    let saved: PendingAttempt;
    try {saved = await retainPending(context.identity, CF_FAMILY, CF_RESOURCE, key, TEAM_MANAGE, {model:'canonical_evidence_ledger', principal_sha256:binding, ...intent}, cfStorage(context));}
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
