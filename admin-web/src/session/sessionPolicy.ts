import type {AdminBackend} from '../api/client';
import type {AdminUser} from './sessionResponses';

export const OTP = /^[0-9]{6}$/;

/** Earliest expiry of the server-issued proofs required by this account policy. */
export function sensitiveVerificationDeadline(user: AdminUser, backend: AdminBackend, now = Date.now()): number | null {
  const expires = Date.parse(user.expiresAt);
  if (!Number.isFinite(now) || !Number.isFinite(expires) || expires <= now) return null;
  let verified: number;
  if (backend === 'supabase') {
    if (!user.emailVerifiedAt || !/(?:Z|\+00:00)$/.test(user.emailVerifiedAt)) return null;
    const email = Date.parse(user.emailVerifiedAt); if (!Number.isFinite(email) || email > now) return null;
    verified = email;
    if (user.mfaRequired === true) {
      if (user.assuranceLevel !== 2 || !user.mfaAt) return null;
      const mfa = Date.parse(user.mfaAt); if (!Number.isFinite(mfa) || mfa > now + 60_000) return null;
      verified = Math.min(email, mfa);
    }
  } else {
    if (user.assuranceLevel !== 2 || !user.mfaAt) return null;
    verified = Date.parse(user.mfaAt); if (!Number.isFinite(verified) || verified > now + 60_000) return null;
  }
  return Math.min(expires, verified + 300_000);
}
