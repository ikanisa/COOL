import type {AdminUser, SessionContextValue} from '../session/SessionProvider';
import {sensitiveVerificationDeadline} from '../session/sessionPolicy';

type VerificationSession = Pick<SessionContextValue, 'epoch' | 'verificationMode' | 'isCurrentAuthority' | 'isRecentSensitiveVerification' | 'recheckSensitiveEmailVerification'>;

/** The selected backend determines the proof type, even when email proof is absent. */
export async function verifySensitiveAccess(session: VerificationSession, user: AdminUser, now = Date.now()): Promise<boolean> {
  const current = () => session.isCurrentAuthority(session.epoch, user.id, user.sessionId);
  if (!current()) return false;
  if (session.verificationMode === 'email') {
    return await session.recheckSensitiveEmailVerification() && current() && session.isRecentSensitiveVerification(session.epoch, user.id, user.sessionId);
  }
  const deadline = sensitiveVerificationDeadline(user, 'cloudflare', now);
  return deadline !== null && deadline >= now && current();
}
