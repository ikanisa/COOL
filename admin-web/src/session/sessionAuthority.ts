import type {AdminUser} from './sessionResponses';

export function orderedPermissions(values: readonly string[]): string[] {
  return [...new Set(values)].sort();
}

export function workspaceAuthorityFields(user: AdminUser) {
  return [user.id, user.sessionId, user.email, user.role, orderedPermissions(user.permissions),
    user.assuranceLevel, user.mfaAt, user.principalId, user.financialModel] as const;
}

export function authorityKey(user: AdminUser): string {
  return JSON.stringify([...workspaceAuthorityFields(user), user.mfaAvailable ?? false,
    user.mfaRequired ?? false, user.ownerIdentity ?? null]);
}

export function matchesPredecessorAuthenticator(before: AdminUser, after: AdminUser, now = Date.now()): boolean {
  const proofTime = after.mfaAt === null ? NaN : Date.parse(after.mfaAt);
  return before.id === after.id && before.email === after.email && before.sessionId === after.sessionId &&
    before.principalId === after.principalId && before.role === after.role &&
    JSON.stringify(orderedPermissions(before.permissions)) === JSON.stringify(orderedPermissions(after.permissions)) &&
    after.assuranceLevel === 2 && proofTime >= now - 300_000 && proofTime <= now + 60_000;
}
