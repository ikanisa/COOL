import {AdminRequestError, type AdminRequest} from '../api/client';
import {clearLogoutIntent, logoutFingerprint, readLogoutIntents, retainLogoutIntent} from './logoutIntent';
import {clearMfaAuthorityCheckpoint, mfaIntentDigest, readMfaAuthorityCheckpoint} from './mfaAuthority';
import {clearMfaRecoveryIntent, readMfaRecoveryIntent} from './mfaRecovery';
import {clearMfaTransition, mfaTransitionIdentity, readMfaTransitions} from './mfaTransition';
import {parseLogoutSessionId, type AdminUser} from './sessionResponses';

interface ManagedLogout {
  request: AdminRequest;
  original: AdminUser | null;
  current: () => boolean;
  confirmAnonymous: () => Promise<boolean>;
}

/** Reconcile the original session and its retained intent before clearing local authority. */
export async function confirmManagedLogout({request, original, current, confirmAnonymous}: ManagedLogout): Promise<void> {
  let pending = readLogoutIntents();
  const reserve = async (sessionId: string) => {
    const fingerprint = await logoutFingerprint(sessionId);
    if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.', {outcomeUnknown: true});
    pending = readLogoutIntents();
    if (pending.size && !pending.has(fingerprint)) throw new AdminRequestError('Another sign-out is unresolved. Check the original session.', {outcomeUnknown: true});
    retainLogoutIntent(fingerprint);
    if (!readLogoutIntents().has(fingerprint)) throw new Error('Sign-out could not be retained.');
    return fingerprint;
  };
  // A pending upgrade may have replaced or lost the browser cookie while
  // logout starts. Use the exact original recovery capability even when
  // an old CSRF value remains; an ordinary empty-cookie logout can return
  // ok without proving that the pending upgrade was revoked.
  const recovery = readMfaRecoveryIntent();
  if (original && recovery && (original.sessionId !== recovery.session_id || original.id !== recovery.user_id)) throw new AdminRequestError('The pending authenticator check belongs to another session.', {outcomeUnknown: true});
  let fingerprint: string, sessionId: string;
  if (original) {sessionId = original.sessionId; fingerprint = await reserve(sessionId);}
  else if (recovery) {sessionId = recovery.session_id; fingerprint = await reserve(sessionId);}
  else {
    // Read the cookie without installing authority; bind it to the original marker.
    const body = await request('auth/session', {authenticated: false, expectedStatus: 200});
    if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.', {outcomeUnknown: true});
    const cookieSessionId = parseLogoutSessionId(body, Date.now());
    if (cookieSessionId === null) {
      for (const value of pending) clearLogoutIntent(value);
      if (readLogoutIntents().size) throw new Error('Another sign-out is unresolved.');
      if (current()) await confirmAnonymous();
      return;
    }
    sessionId = cookieSessionId; fingerprint = await reserve(sessionId);
  }
  const result = recovery
    ? await request('auth/logout', {body: {factor_id: recovery.factor_id, challenge_id: recovery.challenge_id, verification_id: recovery.verification_id}, authenticated: false, mfaRecovery: true})
    : await request('auth/logout', {body: {}, authenticated: false});
  if (!current() || result.ok !== true) throw new AdminRequestError('Sign-out was not confirmed.', {outcomeUnknown: true});
  clearLogoutIntent(fingerprint);
  // A successful exact-session logout revokes this recovery capability too.
  try {
    const retained = readMfaRecoveryIntent();
    if (retained?.session_id === sessionId) {
      const transition = await mfaTransitionIdentity(retained);
      if (!current()) throw new Error('Your session changed.');
      const checkpoint = readMfaAuthorityCheckpoint();
      if (checkpoint && checkpoint.intent !== await mfaIntentDigest(retained)) throw new Error('Authenticator authority could not be verified.');
      if (!current()) throw new Error('Your session changed.');
      const transitions = readMfaTransitions();
      if (transitions.has(transition.key)) clearMfaTransition(transition);
      if (checkpoint) clearMfaAuthorityCheckpoint(checkpoint);
      clearMfaRecoveryIntent(retained);
    }
  } catch { /* Preserve malformed or inaccessible recovery data. */ }
  if (readLogoutIntents().size) throw new AdminRequestError('Another sign-out is unresolved.', {outcomeUnknown: true});
  if (current()) await confirmAnonymous();
}
