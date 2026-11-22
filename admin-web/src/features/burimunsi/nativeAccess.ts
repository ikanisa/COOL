import {AdminRequestError, type AdminRequest} from '../../api/client';
import {isVerifiedCurrentOwner, type AdminUser} from '../../session/SessionProvider';
import {listPending, type PendingIdentity} from '../core/pendingAttempt';
import {withPendingFence, type FenceAccess, type FenceLock} from '../operations/pendingFence';
import {parseBuriProvisioning} from './contracts';
import {GUARDED_OPERATOR_FAMILY, parseBuriPending} from './recovery';

export const NATIVE_PROVISIONING_FAMILY = 'burimunsi.provisioning';
const NATIVE_FENCE_FAMILY = 'burimunsi.native-revoke';
const PERMISSION = 'admin_users.manage';
const NATIVE_PERMISSIONS = [PERMISSION, 'receivers.manage', 'receivers.read'];
const GROUP = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;

export interface NativeAccessContext {
  request: AdminRequest;
  user: AdminUser;
  identity: PendingIdentity;
  collectionId: string;
  enabled: boolean;
  isEnabled?: () => boolean;
  isCurrent: () => boolean;
  verifyFresh: () => Promise<boolean>;
  storage?: Storage;
  sharedStorage?: Storage;
  lock?: FenceLock;
  createKey?: () => string;
}

export function checkNativeAuthority(context: NativeAccessContext) {
  const {user, identity, collectionId} = context;
  const samePermissions = JSON.stringify([...new Set(user.permissions)].sort()) ===
    JSON.stringify([...new Set(identity.permissions)].sort());
  const expiresAt = Date.parse(user.expiresAt);
  if (!context.isCurrent() || !isVerifiedCurrentOwner(user) || user.financialModel !== 'canonical_evidence_ledger' ||
      !NATIVE_PERMISSIONS.every(permission => user.permissions.includes(permission) && identity.permissions.includes(permission)) ||
      !GROUP.test(collectionId) || identity.id !== user.id || identity.sessionId !== user.sessionId ||
      identity.email !== user.email || identity.role !== user.role || identity.expiresAt !== user.expiresAt ||
      !samePermissions || !Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    throw new Error('Native access is unavailable to this owner session.');
  }
}

export async function verifyNativeFresh(context: NativeAccessContext) {
  checkNativeAuthority(context);
  if (!await context.verifyFresh()) throw new Error('Verify your current owner email before continuing.');
  checkNativeAuthority(context);
}

export function nativeSharedStorage(context: NativeAccessContext): Storage {
  try {
    return context.sharedStorage ?? localStorage;
  } catch {
    throw new Error('Shared request recovery is unavailable.');
  }
}

export function withNativeFence<T>(context: NativeAccessContext, work: (access: FenceAccess) => Promise<T>) {
  return withPendingFence({
    identity: context.identity, family: NATIVE_FENCE_FAMILY, resourceId: context.collectionId,
    isCurrent: context.isCurrent, storage: context.sharedStorage, lock: context.lock,
  }, work);
}

export async function listBuriMutationAttempts(identity: PendingIdentity, storage?: Storage) {
  const families = ['burimunsi.operator', GUARDED_OPERATOR_FAMILY, NATIVE_PROVISIONING_FAMILY];
  const groups = await Promise.all(families.map(family => listPending(identity, family, PERMISSION, storage)));
  return groups.flat();
}

export async function listNativeAttempts(context: NativeAccessContext) {
  const attempts = await listBuriMutationAttempts(context.identity, context.storage);
  checkNativeAuthority(context);
  return attempts.filter(attempt => parseBuriPending(attempt).collectionId === context.collectionId);
}

export function guardedProvisioningPath(path = 'burimunsi/provisioning') {
  return `${path}?provisioningContract=2`;
}

async function requestNativeDirectory(request: AdminRequest, collectionId: string, negotiate: boolean) {
  const query = new URLSearchParams({collectionId});
  if (negotiate) query.set('provisioningContract', '2');
  return parseBuriProvisioning(await request(`burimunsi/provisioning?${query}`), collectionId, negotiate);
}

/** The review may fall back to a predecessor read. Native writes require v2. */
export async function readNativeReviewDirectory(request: AdminRequest, collectionId: string, negotiate: boolean, isCurrent: () => boolean) {
  try {
    return await requestNativeDirectory(request, collectionId, negotiate);
  } catch (error) {
    if (!negotiate || !(error instanceof AdminRequestError) || error.statusCode !== 400 ||
        error.code !== 'invalid_request' || !isCurrent()) throw error;
    return requestNativeDirectory(request, collectionId, false);
  }
}

export async function readNativeWriteDirectory(context: NativeAccessContext) {
  const directory = await requestNativeDirectory(context.request, context.collectionId, true);
  checkNativeAuthority(context);
  if (directory.provisioningContract !== 2) throw new Error('Guarded native access is unavailable. Load group access again.');
  return directory;
}
