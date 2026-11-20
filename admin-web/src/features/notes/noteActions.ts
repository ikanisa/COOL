/* eslint-disable no-control-regex -- Reject disallowed control characters in private note content. */
import type {AdminRequest} from '../../api/client';
import {canonicalRequestId, clearPending, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity} from '../core/pendingAttempt';
import {isId, isObject} from '../core/contracts';
import {withPendingFence, type FenceLock} from '../operations/pendingFence';
import {parseLookup} from '../requests/contracts';

export type NoteArea = 'groups' | 'users';
const FAMILY = 'operator-note';
const DIGEST = /^[a-f0-9]{64}$/;

export interface NoteContext {
  identity: PendingIdentity; actorId: string; principalId: string | null;
  permissions: readonly string[]; area: NoteArea; id: string; request: AdminRequest;
  isCurrent: () => boolean; allowMutations: boolean;
  pendingStorage?: Storage; fenceStorage?: Storage; lock?: FenceLock;
}
const permission = (area: NoteArea) => area === 'groups' ? 'collections.read' : 'users.read';
const resource = (context: NoteContext) => `${context.area}:${context.id}`;
function invalid(): never {throw new Error('The note request could not be verified. Check the original reference.');}
function validate(context: NoteContext, writing = false): void {
  const needed = permission(context.area);
  if (!isId(context.id) || !isId(context.principalId) || context.identity.id !== context.actorId ||
      !context.permissions.includes(needed) || !context.identity.permissions.includes(needed) ||
      !context.permissions.includes('account.manage') || !context.identity.permissions.includes('account.manage') ||
      !Number.isFinite(Date.parse(context.identity.expiresAt)) || Date.parse(context.identity.expiresAt) <= Date.now() ||
      (writing && !context.allowMutations) || !context.isCurrent()) invalid();
}
function bodyText(value: string): string {
  const body = value.trim();
  if (!body || body.length > 2000 || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(body)) invalid();
  return body;
}
function checkPending(context: NoteContext, pending: PendingAttempt): void {
  if (pending.family !== FAMILY || pending.resource_id !== resource(context) || pending.permission !== permission(context.area) ||
      !isId(pending.request_key) || Object.keys(pending.intent).length !== 1 || typeof pending.intent.body_sha256 !== 'string' ||
      !DIGEST.test(pending.intent.body_sha256)) invalid();
}
async function currentPending(context: NoteContext, expected?: PendingAttempt): Promise<PendingAttempt | null> {
  const value = await readPending(context.identity, FAMILY, resource(context), context.pendingStorage);
  if (value) checkPending(context, value);
  if (expected && (!value || value.request_key !== expected.request_key || JSON.stringify(value.intent) !== JSON.stringify(expected.intent))) invalid();
  if (!context.isCurrent()) invalid();
  return value;
}
async function receipt(value: unknown, context: NoteContext, key: string): Promise<boolean> {
  return isObject(value) && Object.keys(value).length === 5 && value.status === 'succeeded' &&
    value.request_id === await canonicalRequestId(context.principalId!, key) && value.resource_type === 'operator_notes' &&
    isId(value.resource_id) && value.version === 1;
}
async function outcome(context: NoteContext, pending: PendingAttempt): Promise<'not_found' | 'unconfirmed' | 'cancelled' | 'succeeded'> {
  const result = await context.request(`operations/requests/${pending.request_key}`, {authenticated: true});
  if (!context.isCurrent()) invalid();
  const value = await parseLookup(result, 'canonical_evidence_ledger', context.principalId, pending.request_key);
  if (value.status === 'succeeded' && (!isObject(result) || !await receipt(result.receipt, context, pending.request_key))) invalid();
  if (!context.isCurrent()) invalid();
  if (!['not_found', 'unconfirmed', 'cancelled', 'succeeded'].includes(value.status)) invalid();
  return value.status as 'not_found' | 'unconfirmed' | 'cancelled' | 'succeeded';
}
function fence(context: NoteContext) {
  return {identity: context.identity, family: FAMILY, resourceId: resource(context), isCurrent: context.isCurrent,
    storage: context.fenceStorage, lock: context.lock};
}

/** Restores only the Flutter-compatible digest and key; never the note text. */
export async function readNoteAttempt(context: NoteContext): Promise<PendingAttempt | null> {
  validate(context); return currentPending(context);
}

/** A fresh note is sent once; an uncertain response leaves its original key and digest. */
export async function submitNote(context: NoteContext, text: string): Promise<void> {
  validate(context, true); const body = bodyText(text), hash = await sha256Text(body), key = globalThis.crypto?.randomUUID?.();
  if (!key || !isId(key)) invalid();
  await withPendingFence(fence(context), async access => {
    validate(context, true); const state = access.read();
    if (state.kind !== 'empty' || await currentPending(context)) invalid();
    await retainPending(context.identity, FAMILY, resource(context), key, permission(context.area), {body_sha256: hash}, context.pendingStorage);
    access.reserve(key, state.revision);
    validate(context, true);
    const value = await context.request(`operations/${context.area}/${context.id}/notes`, {method: 'POST', authenticated: true, idempotencyKey: key, body: {body}});
    if (!context.isCurrent() || !await receipt(value, context, key) || !context.isCurrent()) invalid();
    access.clear(key);
    await clearPending(context.identity, FAMILY, resource(context), key, context.pendingStorage);
  });
}

/** Check the original request; only terminal server outcomes clear its reference. */
export async function checkNote(context: NoteContext, expected: PendingAttempt): Promise<'not_found' | 'unconfirmed' | 'cancelled' | 'succeeded'> {
  validate(context); checkPending(context, expected);
  return withPendingFence(fence(context), async access => {
    const pending = (await currentPending(context, expected))!; const shared = access.read();
    if (shared.kind === 'foreign' || (shared.kind === 'owned' && shared.requestKey !== pending.request_key)) invalid();
    const result = await outcome(context, pending);
    if (result === 'succeeded' || result === 'cancelled') {
      if (!context.isCurrent()) invalid();
      if (shared.kind === 'owned') access.clear(pending.request_key);
      await clearPending(context.identity, FAMILY, resource(context), pending.request_key, context.pendingStorage);
    }
    return result;
  });
}

/** An explicit retry rechecks the server and requires the exact original note. */
export async function retryNote(context: NoteContext, expected: PendingAttempt, text: string): Promise<'succeeded' | 'cancelled'> {
  validate(context, true); checkPending(context, expected);
  const body = bodyText(text); if (await sha256Text(body) !== expected.intent.body_sha256) invalid();
  return withPendingFence(fence(context), async access => {
    validate(context, true); const pending = (await currentPending(context, expected))!; const shared = access.read();
    if (shared.kind === 'foreign' || (shared.kind === 'owned' && shared.requestKey !== pending.request_key)) invalid();
    const status = await outcome(context, pending);
    if (status === 'succeeded' || status === 'cancelled') {
      if (!context.isCurrent()) invalid();
      if (shared.kind === 'owned') access.clear(pending.request_key);
      await clearPending(context.identity, FAMILY, resource(context), pending.request_key, context.pendingStorage);
      return status;
    }
    if (status !== 'not_found') invalid();
    if (shared.kind === 'empty') access.reserve(pending.request_key, shared.revision);
    validate(context, true);
    const value = await context.request(`operations/${context.area}/${context.id}/notes`, {method: 'POST', authenticated: true, idempotencyKey: pending.request_key, body: {body}});
    if (!context.isCurrent() || !await receipt(value, context, pending.request_key) || !context.isCurrent()) invalid();
    access.clear(pending.request_key);
    await clearPending(context.identity, FAMILY, resource(context), pending.request_key, context.pendingStorage);
    return 'succeeded';
  });
}
