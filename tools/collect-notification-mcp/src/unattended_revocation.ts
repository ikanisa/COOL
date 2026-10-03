import {resolve} from "node:path";
import {loadUnattendedProfile} from "./unattended_profile.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {EnrollmentJournal} from "./unattended_enrollment_journal.ts";
import {keys, uuid, hash, unattendedScope} from "./unattended_contract.ts";
import {sha256, checkedRevocationReason, validIdentityObservation, sameInstant} from "./unattended_enrollment_contract.ts";
import type {EnrollmentIntent} from "./unattended_enrollment_contract.ts";
import type {OwnerRpc} from "./unattended_enrollment_owner.ts";

/** Revocation never invokes the potentially compromised signing helper. It
 * retains the original fingerprint/UUID and does not remove any local key. */
export async function revokePreparedIdentity(directory: string, profilePath: string, requestId: string, actorId: string, sessionId: string,
  rpc: OwnerRpc, rawReason: string, now: () => number = Date.now) {
  const profile = await loadUnattendedProfile(profilePath);
  if (profile.journal_directory !== resolve(directory)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  return revokeEnrollmentIdentity(directory, profile.identity.principalId, profile.identity.keySha256, requestId, actorId, sessionId,
    rpc, rawReason, now, profile.identity.expiresAt);
}
/** A pending or activation-stalled identity has no published profile. Its
 * explicit principal/fingerprint must match the fresh owner-only observation;
 * expiry is derived from that observation, never caller supplied. */
export async function revokeEnrollmentIdentity(directory: string, principalId: string, expectedKeySha: string, requestId: string,
  actorId: string, sessionId: string, rpc: OwnerRpc, rawReason: string, now: () => number = Date.now, expectedExpiry?: string) {
  const reason = checkedRevocationReason(rawReason.trim());
  if (!uuid(requestId) || !uuid(principalId) || !hash(expectedKeySha)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  const journal = new EnrollmentJournal(directory, actorId, sessionId), saved = await journal.intent(requestId);
  if (saved !== null) {
    if (saved.action !== "revoke" || saved.principal_id !== principalId || saved.key_sha256 !== expectedKeySha ||
        expectedExpiry !== undefined && !sameInstant(saved.identity_expires_at, expectedExpiry) || saved.reason_sha256 !== sha256(reason)) throw new Error("ENROLLMENT_JOURNAL_INTEGRITY_REQUIRED");
    return journal.readOriginal(requestId);
  }
  const observed = await rpc("admin_get_receipt_operations_identity_v3", {p_principal_id: principalId});
  if (!validIdentityObservation(observed, principalId, now()) || !observed.found || observed.identity === null || observed.identity.state === "revoked" ||
      observed.identity.key_sha256 !== expectedKeySha || expectedExpiry !== undefined && !sameInstant(observed.identity.expires_at, expectedExpiry)) throw new Error("ENROLLMENT_IDENTITY_UNAVAILABLE");
  const intent: EnrollmentIntent = {action: "revoke", request_id: requestId, key_sha256: expectedKeySha, principal_id: principalId,
    public_key_spki_base64: null, identity_expires_at: observed.identity.expires_at, request_expires_at: new Date(now() + 90_000).toISOString(), reason_sha256: sha256(reason)};
  return journal.once(intent, rpc, now, reason);
}
export async function localEnrollmentStatus(directory: string, requestId: string) {
  if (!uuid(requestId)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  const checkpoint = await new UnattendedStore(directory).read(`${requestId}.checkpoint.json`);
  if (!keys(checkpoint, ["contract_version", "origin", "scope", "actor_id", "session_id", "created_at", "intent"]) || checkpoint.contract_version !== 3 ||
      checkpoint.scope !== unattendedScope || !uuid(checkpoint.actor_id) || !uuid(checkpoint.session_id)) throw new Error("ENROLLMENT_JOURNAL_INTEGRITY_REQUIRED");
  const result = await new EnrollmentJournal(directory, checkpoint.actor_id, checkpoint.session_id).readOriginal(requestId);
  return {contract_version: 3, original_request_id: requestId, action: result.action, outcome: result.outcome, reason_code: result.reason_code,
    lookup_request_id: result.lookup_request_id, local_historical_evidence: true, scheduler_started: false};
}
