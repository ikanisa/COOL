import {z} from 'zod';
import {withPendingFence, type FenceAccess} from '../operations/pendingFence';
import type {LegacyPersonSnapshot, LegacyUserEditContext, LegacyUserEditPending, LegacyUserEditReceipt} from './legacyUserEdit';
import {clearPending, pendingAuthority, readPending, sha256Text, type PendingAttempt} from './pendingAttempt';

export const PERSON_EDIT_FAMILY = 'operating-updateuser';
export const PERSON_EDIT_PERMISSION = 'users.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const id = z.string().regex(UUID);
const hash = z.string().regex(/^[a-f0-9]{64}$/);
const bindingSchema = z.object({
  version: z.literal(1), request_key: id, authority_sha256: hash, intent_sha256: hash,
  source_sha256: hash, model: z.literal('transaction_journals'),
}).strict();
const receiptSchema = z.object({
  request_id: id, resource_type: z.literal('users'), resource_id: id,
  version: z.number().int().min(2).max(Number.MAX_SAFE_INTEGER), status: z.literal('succeeded'),
}).strict();

type PersonContext = LegacyUserEditContext;
type Binding = {kind: 'valid'; sourceSha256: string} | {kind: 'missing' | 'foreign' | 'mismatch'};
const invalidRequest = 'The original person request could not be verified.';
const invalidStorage = 'Recovery storage is unavailable.';

export function canManageLegacyPerson(context: PersonContext): boolean {
  const expiry = Date.parse(context.identity.expiresAt);
  return context.isCurrent() && context.financialModel === 'transaction_journals' && UUID.test(context.actorId) && UUID.test(context.userId) &&
    context.identity.id === context.actorId && context.identity.role !== 'staff' && Number.isFinite(expiry) && expiry > Date.now() &&
    ['users.read', PERSON_EDIT_PERMISSION, 'overview.read'].every(permission =>
      context.permissions.includes(permission) && context.identity.permissions.includes(permission));
}

function storageFor(context: PersonContext): Storage {
  return context.storage ?? sessionStorage;
}

// Profile, status and access changes share this predecessor slot.
function bindingKey(context: PersonContext): string {
  return `collect.admin.legacy-user-edit.context.v1:${context.userId}`;
}

export function assertPersonAttempt(context: PersonContext, attempt: PendingAttempt): void {
  if (attempt.family !== PERSON_EDIT_FAMILY || attempt.resource_id !== context.userId ||
      attempt.permission !== PERSON_EDIT_PERMISSION || !UUID.test(attempt.request_key)) throw new Error(invalidRequest);
}

export async function readPersonBinding(context: PersonContext, key: string, attempt?: PendingAttempt): Promise<Binding> {
  let raw: string | null;
  try {raw = storageFor(context).getItem(bindingKey(context));} catch {throw new Error(invalidStorage);}
  if (raw === null) return {kind: 'missing'};
  if (raw.length > 1000) throw new Error(invalidRequest);
  let value: unknown;
  try {value = JSON.parse(raw);} catch {throw new Error(invalidRequest);}
  const data = bindingSchema.parse(value);
  if (data.request_key !== key) throw new Error(invalidRequest);
  if (data.authority_sha256 !== await pendingAuthority(context.identity)) return {kind: 'foreign'};
  if (attempt && data.intent_sha256 !== await sha256Text(JSON.stringify(attempt.intent))) return {kind: 'mismatch'};
  return {kind: 'valid', sourceSha256: data.source_sha256};
}

export async function savePersonBinding(context: PersonContext, key: string, attempt: PendingAttempt, source: LegacyPersonSnapshot, assertCurrent: () => void) {
  if ((await readPersonBinding(context, key)).kind !== 'missing') throw new Error(invalidRequest);
  const raw = JSON.stringify({
    version: 1, request_key: key, authority_sha256: await pendingAuthority(context.identity),
    intent_sha256: await sha256Text(JSON.stringify(attempt.intent)), source_sha256: await sha256Text(JSON.stringify(source)),
    model: 'transaction_journals',
  });
  assertCurrent();
  try {
    const storage = storageFor(context), name = bindingKey(context);
    storage.setItem(name, raw);
    if (storage.getItem(name) !== raw) throw new Error(invalidStorage);
  } catch {throw new Error(invalidStorage);}
  assertCurrent();
}

export async function clearPersonBinding(context: PersonContext, key: string, assertCurrent: () => void) {
  const state = await readPersonBinding(context, key);
  if (state.kind === 'foreign') throw new Error(invalidRequest);
  if (state.kind === 'missing') return;
  assertCurrent();
  try {
    const storage = storageFor(context), name = bindingKey(context);
    storage.removeItem(name);
    if (storage.getItem(name) !== null) throw new Error(invalidStorage);
  } catch {throw new Error(invalidStorage);}
}

export function withPersonFence<T>(context: PersonContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  return withPendingFence({identity: context.identity, family: PERSON_EDIT_FAMILY, resourceId: context.userId,
    isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock}, work);
}

export async function restorePersonRequest(context: PersonContext, access: FenceAccess, assertCurrent: () => void): Promise<LegacyUserEditPending> {
  assertCurrent();
  const shared = access.read();
  if (shared.kind === 'foreign') return {kind: 'foreign'};
  const attempt = await readPending(context.identity, PERSON_EDIT_FAMILY, context.userId, context.storage);
  if (attempt) assertPersonAttempt(context, attempt);
  const bound = attempt ? await readPersonBinding(context, attempt.request_key, attempt) : {kind: 'missing'};
  assertCurrent();
  if (bound.kind === 'foreign') return {kind: 'foreign'};
  if (shared.kind === 'owned') {
    if (attempt && attempt.request_key !== shared.requestKey) throw new Error(invalidRequest);
    return {kind: 'owned', requestKey: shared.requestKey, attempt};
  }
  if (attempt) {
    access.reserve(attempt.request_key, shared.revision);
    return {kind: 'owned', requestKey: attempt.request_key, attempt};
  }
  return {kind: 'ready', revision: shared.revision};
}

export async function clearPersonRequest(
  context: PersonContext,
  access: FenceAccess,
  pending: Extract<LegacyUserEditPending, {kind: 'owned'}>,
  assertCurrent: () => void,
) {
  await clearPersonBinding(context, pending.requestKey, assertCurrent);
  if (pending.attempt) await clearPending(context.identity, PERSON_EDIT_FAMILY, context.userId, pending.requestKey, context.storage);
  assertCurrent();
  access.clear(pending.requestKey);
}

export function parsePersonReceipt(context: PersonContext, value: unknown, attempt: PendingAttempt | null): LegacyUserEditReceipt {
  const body = receiptSchema.parse(value);
  const version = attempt?.intent.expected_version;
  if (body.resource_id !== context.userId ||
      (attempt && (typeof version !== 'number' || !Number.isSafeInteger(version) || body.version !== version + 1))) {
    throw new Error('The original person receipt could not be verified.');
  }
  return {requestId: body.request_id, userId: body.resource_id, version: body.version};
}
