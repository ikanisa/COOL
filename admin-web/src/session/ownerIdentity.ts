/* eslint-disable no-control-regex -- Reject controls in server-supplied identity fields. */
import type {JsonObject} from '../api/client';
import type {AdminUser} from './sessionResponses';

/** Protected-owner attestation from the versioned authenticated session only. */
export interface AdminOwnerIdentity {schemaVersion: 1; adminId: string; principalId: string; email: string;}
/** Managed Admin links identify Collect users by their original PostgreSQL text. */
export function isAdminIdentityId(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= 200 &&
    value === value.trim() && !/[\x00-\x1f\x7f-\x9f\uD800-\uDFFF]/u.test(value);
}
function email(value: unknown): value is string {
  if (typeof value !== 'string' || value.length > 254 || value !== value.trim().toLowerCase() || /[\s\x00-\x1f\x7f]/.test(value)) return false;
  const parts = value.split('@'), local = parts[0];
  return parts.length === 2 && !!local && local.length <= 64 && !local.startsWith('.') && !local.endsWith('.') && !local.includes('..') && /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$/.test(local) &&
    parts[1].split('.').length >= 2 && parts[1].split('.').every(label => !!label && label.length <= 63 && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label));
}
export function parseOwnerIdentitySession(body: JsonObject): AdminOwnerIdentity | null {
  const value = body.ownerIdentity;
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const owner = value as JsonObject;
  if (Object.keys(owner).length !== 4 || !['schemaVersion', 'adminId', 'principalId', 'email'].every(key => Object.hasOwn(owner, key)) || owner.schemaVersion !== 1 ||
      !isAdminIdentityId(owner.adminId) || !isAdminIdentityId(owner.principalId) || !email(owner.email) || body.ownerEmail !== owner.email) return null;
  return Object.freeze({schemaVersion: 1, adminId: owner.adminId, principalId: owner.principalId, email: owner.email});
}
/** A role or email alone never proves that the current actor is the owner. */
export function isVerifiedCurrentOwner(user: AdminUser): boolean {
  const owner = user.ownerIdentity;
  return user.role === 'owner' && !!owner && owner.adminId === user.id && owner.principalId === user.principalId && owner.email === user.email;
}
