import {custodyKey} from '../custodyRealm';
import {sha256Text} from '../features/core/pendingAttempt';
import {orderedPermissions} from './sessionAuthority';
import type {AdminUser} from './sessionResponses';
import type {MfaRecoveryIntent} from './mfaRecovery';

/** Companion to the MFA intent in the current service. Only one-way digests are stored. */
export const MFA_AUTHORITY_KEY = custodyKey('collect.admin.mfa-authority.v1');
export interface MfaAuthorityCheckpoint {version: 1; intent: string; authority: string}
const HASH = /^[a-f0-9]{64}$/;
function invalid(): never {throw new Error('Authenticator authority could not be verified.');}

export async function mfaIntentDigest(intent: MfaRecoveryIntent): Promise<string> {
  return sha256Text(JSON.stringify(['collect.admin.mfa-authority-intent.v1', intent.factor_id, intent.challenge_id, intent.verification_id,
    intent.session_id, intent.user_id, intent.starting_assurance_level, intent.starting_mfa_at_ms, intent.created_at_ms]));
}

export async function mfaActorDigest(user: AdminUser): Promise<string> {
  return sha256Text(JSON.stringify(['collect.admin.mfa-authority.v1', user.id, user.sessionId, user.email, user.role,
    orderedPermissions(user.permissions), user.principalId, user.financialModel, user.mfaAvailable ?? false, user.mfaRequired ?? false, user.ownerIdentity ?? null]));
}

export async function createMfaAuthorityCheckpoint(intent: MfaRecoveryIntent, user: AdminUser): Promise<MfaAuthorityCheckpoint> {
  const [intentHash, authority] = await Promise.all([mfaIntentDigest(intent), mfaActorDigest(user)]);
  return {version: 1, intent: intentHash, authority};
}

function parse(value: unknown): MfaAuthorityCheckpoint {
  if (!value || typeof value !== 'object' || Array.isArray(value)) invalid();
  const data = value as Record<string, unknown>;
  if (Object.keys(data).length !== 3 || !['version', 'intent', 'authority'].every(key => Object.hasOwn(data, key)) || data.version !== 1 || typeof data.intent !== 'string' || !HASH.test(data.intent) || typeof data.authority !== 'string' || !HASH.test(data.authority)) invalid();
  return {version: 1, intent: data.intent, authority: data.authority};
}

export function readMfaAuthorityCheckpoint(storage: Storage = sessionStorage): MfaAuthorityCheckpoint | null {
  let raw: string | null;
  try {raw = storage.getItem(MFA_AUTHORITY_KEY);} catch {return invalid();}
  if (raw === null) return null;
  if (raw.length > 1024) invalid();
  let data: unknown; try {data = JSON.parse(raw);} catch {return invalid();}
  return parse(data);
}

export function writeMfaAuthorityCheckpoint(value: MfaAuthorityCheckpoint, storage: Storage = sessionStorage): void {
  const raw = JSON.stringify(parse(value));
  try {if (storage.getItem(MFA_AUTHORITY_KEY) !== null) invalid(); storage.setItem(MFA_AUTHORITY_KEY, raw); if (storage.getItem(MFA_AUTHORITY_KEY) !== raw) invalid();} catch {invalid();}
}

export function clearMfaAuthorityCheckpoint(expected: MfaAuthorityCheckpoint, storage: Storage = sessionStorage): void {
  const current = readMfaAuthorityCheckpoint(storage);
  if (!current || current.intent !== expected.intent || current.authority !== expected.authority) invalid();
  try {storage.removeItem(MFA_AUTHORITY_KEY); if (storage.getItem(MFA_AUTHORITY_KEY) !== null) invalid();} catch {invalid();}
}
