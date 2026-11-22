/* eslint-disable no-control-regex -- Reject control characters in session identifiers. */
import {AdminRequestError, isJsonObject, isVerificationUuid, type JsonObject} from '../api/contracts';
import {isAdminIdentityId, parseOwnerIdentitySession, type AdminOwnerIdentity} from './ownerIdentity';

export interface AdminUser {
  id: string;
  email: string;
  role: 'owner' | 'admin' | 'staff';
  sessionId: string;
  expiresAt: string;
  permissions: readonly string[];
  assuranceLevel: 1 | 2;
  mfaAt: string | null;
  mfaAvailable?: boolean;
  mfaRequired?: boolean;
  emailVerifiedAt: string | null;
  principalId: string | null;
  financialModel: 'transaction_journals' | 'canonical_evidence_ledger';
  /** Server-attested protected owner, available only from auth/session. */
  ownerIdentity?: AdminOwnerIdentity | null;
}

export interface OtpReceipt {
  challengeId: string;
  retryAfterSeconds: number;
  expiresInSeconds: number;
  deliveryUnknown: boolean;
}

const sessionFields = ['user', 'expiresAt', 'csrfToken', 'ownerEmail'] as const;
const authenticatorSessionFields = new Set<string>([...sessionFields, 'ownerIdentity']);

function isIntegerBetween(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= minimum && value <= maximum;
}

function hasSessionFields(body: JsonObject): boolean {
  return sessionFields.every(key => Object.hasOwn(body, key));
}

function isCsrfToken(value: unknown): boolean {
  return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
}

/** Account details returned by sign-in. Only the authenticated session can attest the owner. */
export function parseAdminUser(body: JsonObject, now = Date.now()): AdminUser {
  const user = body.user;
  if (!isJsonObject(user) || typeof user.id !== 'string' || !user.id ||
      typeof user.email !== 'string' || typeof user.sessionId !== 'string' || !user.sessionId ||
      !Array.isArray(user.permissions) || !user.permissions.every(permission => typeof permission === 'string')) {
    throw new Error('Invalid account response.');
  }
  if (user.role !== 'owner' && user.role !== 'admin' && user.role !== 'staff') {
    throw new Error('Invalid account role.');
  }
  if (typeof body.expiresAt !== 'string' || !Number.isFinite(Date.parse(body.expiresAt)) || Date.parse(body.expiresAt) <= now) {
    throw new Error('Expired account response.');
  }
  const level = user.assuranceLevel ?? 1;
  const mfaAt = user.mfaAt ?? null;
  const mfaAvailable = user.mfaAvailable ?? false;
  const mfaRequired = user.mfaRequired ?? false;
  const principalId = user.principalId ?? null;
  const financialModel = user.financialModel ?? 'transaction_journals';
  // Combined email and authenticator proof requires a separate recovery flow.
  if (typeof mfaAvailable !== 'boolean' || typeof mfaRequired !== 'boolean' || mfaRequired) {
    throw new Error('The account verification policy is unavailable.');
  }
  if ((level !== 1 && level !== 2) ||
      (mfaAt !== null && (typeof mfaAt !== 'string' || !Number.isFinite(Date.parse(mfaAt)) || Date.parse(mfaAt) > now + 60_000)) ||
      (level === 2 && mfaAt === null) || (level === 1 && mfaAt !== null) ||
      (principalId !== null && !isAdminIdentityId(principalId)) ||
      (financialModel !== 'transaction_journals' && financialModel !== 'canonical_evidence_ledger')) {
    throw new Error('Invalid account verification.');
  }
  return {
    id: user.id, email: user.email, role: user.role, sessionId: user.sessionId,
    expiresAt: body.expiresAt, permissions: Object.freeze([...user.permissions] as string[]),
    assuranceLevel: level, mfaAt, mfaAvailable, mfaRequired, emailVerifiedAt: null, principalId, financialModel,
  };
}

export function parseSessionUser(body: JsonObject, now: number): AdminUser {
  const user = parseAdminUser(body, now);
  const proof = parseOwnerIdentitySession(body);
  const ownerIdentity = proof && user.role === 'owner' && proof.adminId === user.id &&
    proof.principalId === user.principalId && proof.email === user.email ? proof : null;
  return {...user, ownerIdentity};
}

export function parseAuthenticatorSession(body: JsonObject, now: number): AdminUser {
  if (Object.keys(body).some(key => !authenticatorSessionFields.has(key)) || !hasSessionFields(body) || !isCsrfToken(body.csrfToken)) {
    throw new AdminRequestError('The authenticator session could not be verified.', {outcomeUnknown: true});
  }
  if (body.user === null) {
    throw new AdminRequestError('The authenticator result could not be confirmed.', {outcomeUnknown: true});
  }
  return parseSessionUser(body, now);
}

/** Read the cookie session identity needed to finish a pending sign-out. */
export function parseLogoutSessionId(body: JsonObject, now: number): string | null {
  if (!hasSessionFields(body)) throw new Error('Invalid sign-out session response.');
  if (body.user === null) {
    if (body.expiresAt !== null || body.csrfToken !== null) throw new Error('Invalid sign-out session response.');
    return null;
  }
  const user = body.user;
  if (!isJsonObject(user) || typeof user.sessionId !== 'string' || !user.sessionId ||
      user.sessionId.length > 200 || /[\x00-\x1f\x7f]/.test(user.sessionId) ||
      !isCsrfToken(body.csrfToken) || typeof body.expiresAt !== 'string' ||
      !Number.isFinite(Date.parse(body.expiresAt)) || Date.parse(body.expiresAt) <= now) {
    throw new Error('Invalid sign-out session response.');
  }
  return user.sessionId;
}

export function parseEmailProof(body: JsonObject, user: AdminUser, now: number): string | null {
  if (Object.keys(body).length !== 3 || body.contractVersion !== 1 || body.sessionId !== user.sessionId || !Object.hasOwn(body, 'emailVerifiedAt')) {
    throw new Error('Invalid email verification response.');
  }
  const proof = body.emailVerifiedAt;
  if (proof === null) return null;
  if (typeof proof !== 'string' || !/(?:Z|\+00:00)$/.test(proof) || !Number.isFinite(Date.parse(proof)) || Date.parse(proof) > now) {
    throw new Error('Invalid email verification time.');
  }
  return proof;
}

export function parseSignInOtpReceipt(body: JsonObject): OtpReceipt {
  const id = body.challenge_id, retry = body.retry_after, expires = body.expires_in;
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,200}$/.test(id) ||
      !isIntegerBetween(retry, 60, 3600) || !isIntegerBetween(expires, 60, 3600) ||
      (body.emailStatus !== undefined && body.emailStatus !== 'accepted') ||
      (body.delivery_status !== undefined && body.delivery_status !== 'accepted' && body.delivery_status !== 'unknown')) {
    throw new AdminRequestError('The code request could not be confirmed. Check before requesting another code.', {outcomeUnknown: true});
  }
  return {challengeId: id, retryAfterSeconds: retry, expiresInSeconds: expires, deliveryUnknown: body.delivery_status === 'unknown'};
}

export function parseSensitiveOtpReceipt(body: JsonObject): OtpReceipt {
  const id = body.challenge_id, retry = body.retry_after, expires = body.expires_in;
  if (Object.keys(body).length !== 4 || !isVerificationUuid(id) ||
      retry !== 60 || !isIntegerBetween(expires, 0, 300) ||
      (body.delivery_status !== 'accepted' && body.delivery_status !== 'unknown')) {
    throw new AdminRequestError('The code request could not be confirmed. Check verification.', {outcomeUnknown: true});
  }
  return {challengeId: id, retryAfterSeconds: retry, expiresInSeconds: expires, deliveryUnknown: body.delivery_status === 'unknown'};
}
