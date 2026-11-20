import type {AdminUser} from '../session/SessionProvider';

/** A renewed email proof is checked separately and is not a new actor/session. */
export function featureAuthorityKey(epoch: number, user: AdminUser): string {
  return JSON.stringify([epoch, user.id, user.sessionId, user.email, user.role,
    [...new Set(user.permissions)].sort(), user.assuranceLevel, user.mfaAt, user.principalId, user.financialModel]);
}
