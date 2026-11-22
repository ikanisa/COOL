import {custodyKey} from '../custodyRealm';
import {sha256Text} from '../features/core/pendingAttempt';
import {logoutFingerprint} from './logoutIntent';
import type {MfaRecoveryIntent} from './mfaRecovery';

/** Only one-way digests are shared. The recovery capability stays in its original tab. */
export const MFA_TRANSITION_PREFIX = custodyKey('collect.admin.mfa-transition.v1.');
const DIGEST = /^[a-f0-9]{64}$/;

export async function mfaTransitionIdentity(intent: MfaRecoveryIntent): Promise<{key: string; session: string}> {
  return {
    key: await sha256Text(`collect.admin.mfa-transition.v1:${intent.verification_id}`),
    session: await logoutFingerprint(intent.session_id),
  };
}

export function readMfaTransitions(storage: Storage = localStorage): Map<string, string> {
  const pending = new Map<string, string>();
  try {
    for (let index = 0; index < storage.length; index++) {
      const key = storage.key(index);
      if (!key?.startsWith(MFA_TRANSITION_PREFIX)) continue;
      const digest = key.slice(MFA_TRANSITION_PREFIX.length), session = storage.getItem(key);
      if (!DIGEST.test(digest) || !session || !DIGEST.test(session)) throw new Error();
      pending.set(digest, session);
    }
  } catch {throw new Error('Authenticator recovery could not be retained.');}
  return pending;
}

export function retainMfaTransition(identity: {key: string; session: string}, storage: Storage = localStorage): void {
  if (!DIGEST.test(identity.key) || !DIGEST.test(identity.session)) throw new Error('Authenticator recovery could not be retained.');
  try {
    const key = MFA_TRANSITION_PREFIX + identity.key, previous = storage.getItem(key);
    if (previous !== null && previous !== identity.session) throw new Error();
    storage.setItem(key, identity.session);
    if (storage.getItem(key) !== identity.session) throw new Error();
  } catch {throw new Error('Authenticator recovery could not be retained.');}
}

export function clearMfaTransition(identity: {key: string; session: string}, storage: Storage = localStorage): void {
  if (!DIGEST.test(identity.key) || !DIGEST.test(identity.session)) throw new Error('Authenticator recovery could not be verified.');
  try {
    const key = MFA_TRANSITION_PREFIX + identity.key;
    if (storage.getItem(key) !== identity.session) throw new Error();
    storage.removeItem(key);
    if (storage.getItem(key) !== null) throw new Error();
  } catch {throw new Error('Authenticator recovery could not be verified.');}
}
