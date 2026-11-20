import {sha256Text} from '../features/core/pendingAttempt';
import {custodyKey} from '../custodyRealm';

/** A public-session fingerprint only; no cookie, CSRF value, or token is stored. */
export const LOGOUT_INTENT_PREFIX = custodyKey('collect.admin.logout-intent.v1.');
const FINGERPRINT = /^[a-f0-9]{64}$/;

export async function logoutFingerprint(sessionId: string): Promise<string> {
  if (!sessionId || sessionId.length > 200) throw new Error('Sign-out could not be retained.');
  return sha256Text(`collect.admin.logout.v1:${sessionId}`);
}

export function readLogoutIntents(storage: Storage = localStorage): Set<string> {
  const pending = new Set<string>();
  try {
    for (let index = 0; index < storage.length; index++) {
      const key = storage.key(index);
      if (!key?.startsWith(LOGOUT_INTENT_PREFIX)) continue;
      const fingerprint = key.slice(LOGOUT_INTENT_PREFIX.length);
      if (!FINGERPRINT.test(fingerprint) || storage.getItem(key) !== '1') throw new Error();
      pending.add(fingerprint);
    }
  } catch {throw new Error('Sign-out could not be retained.');}
  return pending;
}

export function retainLogoutIntent(fingerprint: string, storage: Storage = localStorage): void {
  if (!FINGERPRINT.test(fingerprint)) throw new Error('Sign-out could not be retained.');
  try {
    storage.setItem(LOGOUT_INTENT_PREFIX + fingerprint, '1');
    if (storage.getItem(LOGOUT_INTENT_PREFIX + fingerprint) !== '1') throw new Error();
  } catch {throw new Error('Sign-out could not be retained.');}
}

export function clearLogoutIntent(fingerprint: string, storage: Storage = localStorage): void {
  if (!FINGERPRINT.test(fingerprint)) throw new Error('Sign-out could not be verified.');
  try {
    storage.removeItem(LOGOUT_INTENT_PREFIX + fingerprint);
    if (storage.getItem(LOGOUT_INTENT_PREFIX + fingerprint) !== null) throw new Error();
  } catch {throw new Error('Sign-out could not be verified.');}
}
