import {canonical, keys, need, timestamp, uuid} from './wire_values.mjs';

const USER_FIELDS = [
  'id', 'email', 'role', 'sessionId', 'expiresAt', 'permissions',
  'assuranceLevel', 'mfaAt', 'principalId', 'financialModel',
];

export function publicSession(value, now = Date.now()) {
  keys(value, USER_FIELDS);
  for (const key of ['id', 'sessionId', 'principalId']) uuid(value[key]);
  timestamp(value.expiresAt);
  need(Date.parse(value.expiresAt) > now, 'session_expired');
  need(typeof value.email === 'string' && value.email.length <= 254 &&
    ['owner', 'admin', 'staff'].includes(value.role), 'invalid_session_user');
  need(value.financialModel === 'canonical_evidence_ledger' &&
    [1, 2].includes(value.assuranceLevel), 'invalid_session_assurance');
  const permissions = value.permissions;
  need(Array.isArray(permissions) && permissions.length <= 256 &&
    new Set(permissions).size === permissions.length &&
    permissions.every(item => typeof item === 'string' && /^[a-z][a-z0-9_.]{1,100}$/.test(item)), 'invalid_permissions');
  if (value.assuranceLevel === 2) timestamp(value.mfaAt);
  else need(value.mfaAt === null, 'invalid_session_assurance');
  return structuredClone(value);
}

export function authorityKey(user) {
  return canonical({
    id: user.id,
    principalId: user.principalId,
    sessionId: user.sessionId,
    role: user.role,
    permissions: [...user.permissions].sort(),
    expiresAt: user.expiresAt,
    assuranceLevel: user.assuranceLevel,
    mfaAt: user.mfaAt,
  });
}

// Email proof has its own DTO and remains bound to the original public session.
export function emailVerification(value, sessionId, now = Date.now()) {
  keys(value, ['contractVersion', 'sessionId', 'emailVerifiedAt']);
  uuid(sessionId);
  uuid(value.sessionId);
  need(sessionId !== '00000000-0000-0000-0000-000000000000', 'email_verification_session_mismatch');
  need(value.contractVersion === 1 && value.sessionId === sessionId, 'email_verification_session_mismatch');
  if (value.emailVerifiedAt !== null) {
    timestamp(value.emailVerifiedAt);
    need(Date.parse(value.emailVerifiedAt) <= now, 'future_email_verification_refused');
  }
  return structuredClone(value);
}

export function sensitiveAuthorityKey(user, emailVerifiedAt) {
  return canonical({actor: authorityKey(user), verification_method: 'email', email_verified_at: emailVerifiedAt});
}

export function hasFreshEmailVerification(snapshot, now = Date.now(), maxAgeMs = 300000) {
  const proof = Date.parse(snapshot?.emailVerifiedAt ?? '');
  return Number.isSafeInteger(maxAgeMs) && maxAgeMs >= 0 && maxAgeMs <= 300000 &&
    snapshot?.proofState === 'available' && Number.isFinite(proof) && proof <= now &&
    proof >= now - maxAgeMs && Date.parse(snapshot.user.expiresAt) > now;
}
