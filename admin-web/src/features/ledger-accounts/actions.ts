/* eslint-disable no-control-regex -- Reject prohibited control characters in recorded account changes. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import { clearPending, readPending, retainPending, type PendingAttempt, type PendingIdentity } from '../core/pendingAttempt';
import { withPendingFence, type FenceAccess, type FenceLock } from '../operations/pendingFence';
import { parseLedgerAccountDetail, type LedgerAccount } from './contracts';

const FAMILY = 'operating-updateaccount', PERMISSION = 'ledger.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const receiptSchema = z.object({request_id: z.string().regex(UUID), resource_type: z.literal('accounts'), resource_id: z.string().regex(UUID), version: z.number().int().min(2).max(Number.MAX_SAFE_INTEGER), status: z.literal('succeeded')}).strict();
export interface LedgerAccountChangeContext {
  request: AdminRequest; identity: PendingIdentity; account: LedgerAccount; canManage: boolean;
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger';
  /** Keep false until the legacy backend and cross-version recovery are qualified. */
  enabled: boolean; isCurrent: () => boolean; isEnabled?: () => boolean; storage?: Storage; sharedStorage?: Storage; lock?: FenceLock; createKey?: () => string;
}
export interface LedgerAccountIntent {name: string; status: 'active' | 'closed'; expected_version: number; reason: string;}
export interface LedgerAccountReceipt {requestId: string; accountId: string; version: number;}
export type LedgerAccountPending = {kind: 'ready'; revision: string} | {kind: 'owned'; requestKey: string; attempt: PendingAttempt | null} | {kind: 'foreign'};
export type LedgerAccountResult = {status: 'succeeded'; receipt: LedgerAccountReceipt} | {status: 'unknown'; requestKey: string} | {status: 'existing'; pending: LedgerAccountPending};
export type LedgerAccountLookup = {status: 'succeeded'; receipt: LedgerAccountReceipt} | {status: 'not_found'; retryAvailable: boolean} | {status: 'pending' | 'failed'};
function fail(message: string): never {throw new Error(message);}
function checkWrite(context: LedgerAccountChangeContext) {if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('This action is not enabled for the current workspace.');}
function exact(value: Record<string, unknown>, keys: string[]) {return Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));}
function check(context: LedgerAccountChangeContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.identity.role === 'staff' || !context.canManage || context.financialModel !== 'transaction_journals' ||
      !['ledger.read', PERMISSION, 'overview.read'].every((permission) => context.identity.permissions.includes(permission)) || !Number.isFinite(expires) || expires <= Date.now() || !UUID.test(context.account.id)) fail('This action is unavailable to your current account.');
}
export function parseLedgerAccountIntent(value: unknown): LedgerAccountIntent {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('The account change could not be verified.');
  const body = value as Record<string, unknown>;
  if (!exact(body, ['name', 'status', 'expected_version', 'reason']) || typeof body.name !== 'string' || body.name !== body.name.trim() || body.name.length < 2 || body.name.length > 120 || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(body.name) ||
      body.status !== 'active' && body.status !== 'closed' || typeof body.expected_version !== 'number' || !Number.isSafeInteger(body.expected_version) || body.expected_version < 1 || body.expected_version >= Number.MAX_SAFE_INTEGER ||
      typeof body.reason !== 'string' || body.reason !== body.reason.trim() || [...body.reason].length < 8 || body.reason.length > 1000 || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(body.reason)) fail('The account change could not be verified.');
  return {name: body.name, status: body.status, expected_version: body.expected_version, reason: body.reason};
}
function verifyAttempt(attempt: PendingAttempt, context: LedgerAccountChangeContext): LedgerAccountIntent {
  if (attempt.family !== FAMILY || attempt.resource_id !== context.account.id || attempt.permission !== PERMISSION || !UUID.test(attempt.request_key)) fail('The original account request could not be verified.');
  return parseLedgerAccountIntent(attempt.intent);
}
function parseReceipt(value: unknown, context: LedgerAccountChangeContext, attempt: PendingAttempt | null): LedgerAccountReceipt {
  const parsed = receiptSchema.parse(value);
  if (parsed.resource_id !== context.account.id || attempt && parsed.version !== verifyAttempt(attempt, context).expected_version + 1) fail('The original account receipt could not be verified.');
  return {requestId: parsed.request_id, accountId: parsed.resource_id, version: parsed.version};
}
async function withFence<T>(context: LedgerAccountChangeContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: FAMILY, resourceId: context.account.id, isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}
async function restoreUnderFence(context: LedgerAccountChangeContext, access: FenceAccess): Promise<LedgerAccountPending> {
  check(context); const fence = access.read();
  if (fence.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, FAMILY, context.account.id, context.storage);
  if (attempt) verifyAttempt(attempt, context);
  check(context);
  if (fence.kind === 'owned') {if (attempt && attempt.request_key !== fence.requestKey) fail('The original account request could not be verified.'); return {kind: 'owned', requestKey: fence.requestKey, attempt};}
  if (attempt) {access.reserve(attempt.request_key, fence.revision); return {kind: 'owned', requestKey: attempt.request_key, attempt};}
  return {kind: 'ready', revision: fence.revision};
}
export async function restoreLedgerAccountChange(context: LedgerAccountChangeContext): Promise<LedgerAccountPending> {check(context); return withFence(context, (access) => restoreUnderFence(context, access));}
async function clear(context: LedgerAccountChangeContext, access: FenceAccess, pending: Extract<LedgerAccountPending, {kind: 'owned'}>) {
  if (pending.attempt) await clearPending(context.identity, FAMILY, context.account.id, pending.requestKey, context.storage);
  check(context); access.clear(pending.requestKey);
}
async function currentAccount(context: LedgerAccountChangeContext) {
  const value = parseLedgerAccountDetail(await context.request(`operations/accounts/${context.account.id}`), context.account.id, context.identity.id, context.identity.role);
  check(context);
  const account = value.account, source = context.account;
  if (!value.canManage || account.group_id !== source.group_id || account.code !== source.code || account.account_type !== source.account_type || account.normal_side !== source.normal_side || account.currency !== source.currency) fail('The account identity could not be verified.');
  return account;
}
async function lookupUnderFence(context: LedgerAccountChangeContext, pending: Extract<LedgerAccountPending, {kind: 'owned'}>): Promise<LedgerAccountLookup> {
  const body = await context.request(`operations/requests/${pending.requestKey}`); check(context);
  if (body.status === 'not_found' && exact(body, ['status'])) return {status: 'not_found', retryAvailable: pending.attempt !== null};
  if (!exact(body, ['status', 'request_id', 'receipt']) || typeof body.request_id !== 'string' || !UUID.test(body.request_id)) fail('The original account receipt could not be verified.');
  if ((body.status === 'pending' || body.status === 'failed') && body.receipt === null) return {status: body.status};
  if (body.status !== 'succeeded') fail('The original account receipt could not be verified.');
  const saved = parseReceipt(body.receipt, context, pending.attempt);
  if (saved.requestId !== body.request_id) fail('The original account receipt could not be verified.');
  if (!pending.attempt && (await currentAccount(context)).version < saved.version) fail('The account version could not be verified.');
  return {status: 'succeeded', receipt: saved};
}
export async function submitLedgerAccountChange(context: LedgerAccountChangeContext, input: LedgerAccountIntent, observedRevision: string): Promise<LedgerAccountResult> {
  checkWrite(context);
  check(context); const intent = parseLedgerAccountIntent(input);
  if (intent.expected_version !== context.account.version || intent.name === context.account.name && intent.status === context.account.status) fail('Review the current account and choose a change.');
  return withFence(context, async (access) => {
    const existing = await restoreUnderFence(context, access);
    if (existing.kind !== 'ready') return {status: 'existing', pending: existing};
    const current = await currentAccount(context);
    if (current.version !== intent.expected_version || current.name !== context.account.name || current.status !== context.account.status) fail('The account changed. Refresh before reviewing it again.');
    checkWrite(context);
    const requestKey = (context.createKey ?? (() => crypto.randomUUID()))();
    if (!UUID.test(requestKey)) fail('A secure request reference is unavailable.');
    access.reserve(requestKey, observedRevision);
    let attempt: PendingAttempt;
    try {attempt = await retainPending(context.identity, FAMILY, context.account.id, requestKey, PERMISSION, {...intent}, context.storage);} catch (error) {if (context.isCurrent()) access.clear(requestKey); throw error;}
    verifyAttempt(attempt, context);
    const pending: Extract<LedgerAccountPending, {kind: 'owned'}> = {kind: 'owned', requestKey, attempt};
    if (!context.isCurrent() || context.isEnabled && !context.isEnabled()) return {status: 'unknown', requestKey};
    try {
      const response = await context.request(`operations/accounts/${context.account.id}`, {method: 'PATCH', body: {...intent}, idempotencyKey: requestKey});
      check(context); const saved = parseReceipt(response, context, attempt); await clear(context, access, pending); return {status: 'succeeded', receipt: saved};
    } catch {return {status: 'unknown', requestKey};}
  });
}
export async function lookupLedgerAccountChange(context: LedgerAccountChangeContext, pending: LedgerAccountPending): Promise<LedgerAccountLookup> {
  check(context); if (pending.kind !== 'owned') fail('The original account must check this request.');
  return withFence(context, async (access) => {
    let stored = await restoreUnderFence(context, access);
    if (stored.kind === 'ready') {access.reserve(pending.requestKey, stored.revision); stored = {kind: 'owned', requestKey: pending.requestKey, attempt: null};}
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey) fail('The original account request could not be verified.');
    const result = await lookupUnderFence(context, stored);
    if (result.status === 'succeeded') await clear(context, access, stored);
    return result;
  });
}
export async function retryLedgerAccountChange(context: LedgerAccountChangeContext, pending: LedgerAccountPending): Promise<LedgerAccountResult> {
  checkWrite(context);
  check(context); if (pending.kind !== 'owned' || !pending.attempt) fail('The original account intent is unavailable.');
  return withFence(context, async (access) => {
    const stored = await restoreUnderFence(context, access);
    if (stored.kind !== 'owned' || stored.requestKey !== pending.requestKey || !stored.attempt || JSON.stringify(stored.attempt.intent) !== JSON.stringify(pending.attempt?.intent)) fail('The original account request could not be verified.');
    const previous = await lookupUnderFence(context, stored);
    if (previous.status === 'succeeded') {await clear(context, access, stored); return {status: 'succeeded', receipt: previous.receipt};}
    if (previous.status !== 'not_found') fail('The original account request remains unresolved.');
    const intent = verifyAttempt(stored.attempt, context), current = await currentAccount(context);
    if (current.version !== intent.expected_version) fail('The account changed. Check the original request before continuing.');
    checkWrite(context);
    try {
      const response = await context.request(`operations/accounts/${context.account.id}`, {method: 'PATCH', body: {...intent}, idempotencyKey: stored.requestKey});
      check(context); const saved = parseReceipt(response, context, stored.attempt); await clear(context, access, stored); return {status: 'succeeded', receipt: saved};
    } catch {return {status: 'unknown', requestKey: stored.requestKey};}
  });
}
