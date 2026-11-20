/* eslint-disable no-control-regex -- Reject controls in public session identifiers. */
import {custodyKey} from '../custodyRealm';
/** Same per-tab recovery capability used by the migration Admin. No code or cookie is stored. */
export const MFA_INTENT_KEY = custodyKey('collect.admin.mfa-intent.v1');
export interface MfaRecoveryIntent {
  factor_id: string; challenge_id: string; verification_id: string; session_id: string; user_id: string;
  starting_assurance_level: 1 | 2; starting_mfa_at_ms: number | null; created_at_ms: number;
}
const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const HASH = /^[a-f0-9]{64}$/;
const keys = ['factor_id', 'challenge_id', 'verification_id', 'session_id', 'user_id', 'starting_assurance_level', 'starting_mfa_at_ms', 'created_at_ms'] as const;
function invalid(): never {throw new Error('Authenticator recovery could not be verified.');}
function identifier(value: unknown): value is string {return typeof value === 'string' && value.length > 0 && value.length <= 200 && !/[\x00-\x1f\x7f]/.test(value);}
export function parseMfaRecoveryIntent(value: unknown): MfaRecoveryIntent {
  if (!value || typeof value !== 'object' || Array.isArray(value)) invalid(); const data = value as Record<string, unknown>;
  if (Object.keys(data).length !== keys.length || !keys.every(key => Object.hasOwn(data, key)) ||
      typeof data.factor_id !== 'string' || !UUID.test(data.factor_id) || typeof data.challenge_id !== 'string' || !UUID.test(data.challenge_id) ||
      typeof data.verification_id !== 'string' || !HASH.test(data.verification_id) || !identifier(data.session_id) || !identifier(data.user_id) ||
      (data.starting_assurance_level !== 1 && data.starting_assurance_level !== 2) ||
      !(data.starting_mfa_at_ms === null || Number.isSafeInteger(data.starting_mfa_at_ms) && Number(data.starting_mfa_at_ms) > 0) ||
      data.starting_assurance_level === 2 && data.starting_mfa_at_ms === null || !Number.isSafeInteger(data.created_at_ms) || Number(data.created_at_ms) <= 0) invalid();
  return data as unknown as MfaRecoveryIntent;
}
export function readMfaRecoveryIntent(storage: Storage = sessionStorage): MfaRecoveryIntent | null {
  let raw: string | null; try {raw = storage.getItem(MFA_INTENT_KEY);} catch {return invalid();}
  if (raw === null) return null; if (raw.length > 4096) invalid();
  let value: unknown; try {value = JSON.parse(raw);} catch {return invalid();} return parseMfaRecoveryIntent(value);
}
export function writeMfaRecoveryIntent(value: MfaRecoveryIntent, storage: Storage = sessionStorage): void {
  const candidate = parseMfaRecoveryIntent(value), raw = JSON.stringify(candidate);
  try {if (storage.getItem(MFA_INTENT_KEY) !== null) invalid(); storage.setItem(MFA_INTENT_KEY, raw); if (storage.getItem(MFA_INTENT_KEY) !== raw) invalid();} catch {invalid();}
}
export function clearMfaRecoveryIntent(expected: MfaRecoveryIntent, storage: Storage = sessionStorage): void {
  const current = readMfaRecoveryIntent(storage); if (!current || keys.some(key => current[key] !== expected[key])) invalid();
  try {storage.removeItem(MFA_INTENT_KEY); if (storage.getItem(MFA_INTENT_KEY) !== null) invalid();} catch {invalid();}
}
/** Server leases require 26 seconds; expired/clock-inconsistent intents stay retained. */
export function mfaRecoveryDelay(intent: MfaRecoveryIntent, now = Date.now()): number | null {
  const age = now - intent.created_at_ms; if (!Number.isSafeInteger(now) || age < -60_000 || age > 300_000) return null;
  return Math.max(0, 26_000 - Math.max(0, age));
}
