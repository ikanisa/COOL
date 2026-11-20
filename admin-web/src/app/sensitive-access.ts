import type {AdminUser, SessionContextValue} from '../session/SessionProvider';

type VerificationSession = Pick<SessionContextValue, 'epoch' | 'verificationMode' | 'isCurrentAuthority' | 'isRecentSensitiveVerification' | 'recheckSensitiveEmailVerification'>;

/** The selected backend determines the proof type, even when email proof is absent. */
export async function verifySensitiveAccess(session: VerificationSession, user: AdminUser, now = Date.now()): Promise<boolean> {
  const current = () => session.isCurrentAuthority(session.epoch, user.id, user.sessionId);
  if (!current()) return false;
  if (session.verificationMode === 'email') {
    return await session.recheckSensitiveEmailVerification() && current() && session.isRecentSensitiveVerification(session.epoch, user.id, user.sessionId);
  }
  if (user.assuranceLevel !== 2 || !user.mfaAt) return false;
  const at = Date.parse(user.mfaAt);
  return Number.isFinite(at) && at <= now + 60_000 && now - at <= 300_000 && Date.parse(user.expiresAt) > now && current();
}
