import {createHash, createPublicKey} from "node:crypto";
import {keys, uuid, hash, utc, integer, unattendedScope} from "./unattended_contract.ts";

export const enrollmentOrigin = "https://lhbowpbcpwoiparwnwgt.supabase.co";
export type EnrollmentAction = "enroll" | "activate" | "revoke";
export interface EnrollmentReceipt {
  contract_version: 3; action: EnrollmentAction; request_id: string; principal_id: string;
  state_at_action: "pending" | "active" | "revoked"; scope: typeof unattendedScope; key_sha256: string;
  identity_expires_at: string; recorded_at: string; request_expires_at: string;
  reason_sha256?: string;
}
export interface EnrollmentIntent {
  action: EnrollmentAction; request_id: string; key_sha256: string; request_expires_at: string;
  public_key_spki_base64: string | null; principal_id: string | null; identity_expires_at: string;
  reason_sha256?: string;
}
export interface PublicKeyMetadata {contract_version: 2; scope: typeof unattendedScope; public_key_spki_base64: string; key_sha256: string}
export interface CurrentIdentity {
  principal_id: string; key_sha256: string; state: "pending" | "active" | "revoked"; scope: typeof unattendedScope;
  created_at: string; expires_at: string; activated_at: string | null; revoked_at: string | null;
}
export interface IdentityObservation {contract_version: 3; checked_at: string; sample_valid_until: string; found: boolean; identity: CurrentIdentity | null}
export interface EnrollmentLookup {
  contract_version: 3; request_id: string; action: EnrollmentAction | null; status: "recorded" | "not_recorded" | "in_progress";
  checked_at: string; sample_valid_until: string; request_expires_at: string | null; receipt: EnrollmentReceipt | null;
}
export interface IdentityCursor {created_at: string; principal_id: string}
export interface IdentityDirectory {contract_version: 3; checked_at: string; sample_valid_until: string; rows: CurrentIdentity[]; next_cursor: IdentityCursor | null}
const instantKey = (value: string) => value.slice(0, 19) + "." + (value.slice(19, -1).replace(/^\./, "")).padEnd(6, "0") + "Z";
export const sha256 = (bytes: Uint8Array | string) => createHash("sha256").update(bytes).digest("hex");
export function sameInstant(left: string, right: string) {
  return utc(left) && utc(right) && instantKey(left) === instantKey(right);
}
export function publicKeyMetadata(value: unknown): value is PublicKeyMetadata {
  try {
    if (!keys(value, ["contract_version", "scope", "public_key_spki_base64", "key_sha256"]) || value.contract_version !== 2 ||
        value.scope !== unattendedScope || !hash(value.key_sha256) || typeof value.public_key_spki_base64 !== "string" ||
        value.public_key_spki_base64.length > 256) return false;
    const bytes = Buffer.from(value.public_key_spki_base64, "base64");
    if (bytes.toString("base64") !== value.public_key_spki_base64 || sha256(bytes) !== value.key_sha256) return false;
    const key = createPublicKey({key: bytes, type: "spki", format: "der"});
    return key.asymmetricKeyType === "ec" && key.asymmetricKeyDetails?.namedCurve === "prime256v1" &&
      key.export({type: "spki", format: "der"}).equals(bytes);
  } catch {return false;}
}
export function validIntent(value: unknown): value is EnrollmentIntent {
  const fields = ["action", "request_id", "key_sha256", "request_expires_at", "public_key_spki_base64", "principal_id", "identity_expires_at"];
  if (!keys(value, value !== null && typeof value === "object" && "action" in value && value.action === "revoke" ? [...fields, "reason_sha256"] : fields) ||
      !uuid(value.request_id) || !hash(value.key_sha256) || !utc(value.request_expires_at) || !utc(value.identity_expires_at)) return false;
  if (value.action === "revoke") return uuid(value.principal_id) && value.public_key_spki_base64 === null && hash(value.reason_sha256);
  if (value.action === "activate") return uuid(value.principal_id) && value.public_key_spki_base64 === null;
  return value.action === "enroll" && value.principal_id === null && publicKeyMetadata({contract_version: 2, scope: unattendedScope,
    public_key_spki_base64: value.public_key_spki_base64, key_sha256: value.key_sha256});
}
export function validReceipt(value: unknown, intent?: EnrollmentIntent): value is EnrollmentReceipt {
  const fields = ["contract_version", "action", "request_id", "principal_id", "state_at_action", "scope", "key_sha256", "identity_expires_at", "recorded_at", "request_expires_at"];
  if (!keys(value, value !== null && typeof value === "object" && "action" in value && value.action === "revoke" ? [...fields, "reason_sha256"] : fields) ||
      value.contract_version !== 3 || (value.action !== "enroll" && value.action !== "activate" && value.action !== "revoke") || !uuid(value.request_id) || !uuid(value.principal_id) ||
      value.scope !== unattendedScope || !hash(value.key_sha256) || !utc(value.identity_expires_at) || !utc(value.recorded_at) || !utc(value.request_expires_at) ||
      value.state_at_action !== (value.action === "enroll" ? "pending" : value.action === "activate" ? "active" : "revoked") || Date.parse(value.recorded_at) >= Date.parse(value.request_expires_at) ||
      (value.action !== "revoke" && Date.parse(value.recorded_at) >= Date.parse(value.identity_expires_at)) || value.action === "revoke" && !hash(value.reason_sha256)) return false;
  return !intent || (value.action === intent.action && value.request_id === intent.request_id && value.key_sha256 === intent.key_sha256 &&
    sameInstant(value.request_expires_at, intent.request_expires_at) && sameInstant(value.identity_expires_at, intent.identity_expires_at) &&
    (intent.principal_id === null || value.principal_id === intent.principal_id) && (intent.action !== "revoke" || value.reason_sha256 === intent.reason_sha256));
}
export function freshSample(value: Record<string, unknown>, now: number): boolean {
  return utc(value.checked_at) && utc(value.sample_valid_until) && Date.parse(value.sample_valid_until) === Date.parse(value.checked_at) + 60_000 &&
    Date.parse(value.checked_at) <= now + 10_000 && now < Date.parse(value.sample_valid_until);
}
export function validIdentityRow(value: unknown): value is CurrentIdentity {
  if (!keys(value, ["principal_id", "key_sha256", "state", "scope", "created_at", "expires_at", "activated_at", "revoked_at"]) ||
      !uuid(value.principal_id) || !hash(value.key_sha256) || value.scope !== unattendedScope ||
      !["pending", "active", "revoked"].includes(value.state as string) || typeof value.state !== "string" ||
      !utc(value.created_at) || !utc(value.expires_at) || Date.parse(value.created_at) >= Date.parse(value.expires_at) ||
      (value.activated_at !== null && (!utc(value.activated_at) || Date.parse(value.activated_at) < Date.parse(value.created_at))) ||
      (value.revoked_at !== null && (!utc(value.revoked_at) || Date.parse(value.revoked_at) < Date.parse(value.created_at)))) return false;
  if (value.state === "pending") return value.activated_at === null && value.revoked_at === null;
  if (value.state === "active") return value.activated_at !== null && value.revoked_at === null;
  return value.revoked_at !== null && (value.activated_at === null || Date.parse(value.revoked_at) >= Date.parse(value.activated_at as string));
}
export function validIdentityObservation(value: unknown, principal: string, now: number): value is IdentityObservation {
  return keys(value, ["contract_version", "checked_at", "sample_valid_until", "found", "identity"]) && value.contract_version === 3 &&
    freshSample(value, now) && typeof value.found === "boolean" && (value.found ? validIdentityRow(value.identity) && value.identity.principal_id === principal &&
      observedIdentityTimes(value.identity, value.checked_at as string) : value.identity === null);
}
function observedIdentityTimes(row: CurrentIdentity, checked: string) {
  return [row.created_at, row.activated_at, row.revoked_at].every(value => value === null || instantKey(value) <= instantKey(checked));
}
export function validCursor(value: unknown): value is IdentityCursor {return keys(value, ["created_at", "principal_id"]) && utc(value.created_at) && uuid(value.principal_id);}
export function validDirectory(value: unknown, limit: number, before: IdentityCursor | null, now: number): value is IdentityDirectory {
  if (!integer(limit, 1, 25) || before !== null && !validCursor(before) || !keys(value, ["contract_version", "checked_at", "sample_valid_until", "rows", "next_cursor"]) ||
      value.contract_version !== 3 || !freshSample(value, now) || !Array.isArray(value.rows) || value.rows.length > limit) return false;
  const seen = new Set<string>(); let prior = before;
  for (const row of value.rows) {
    if (!validIdentityRow(row) || !observedIdentityTimes(row, value.checked_at as string) || seen.has(row.principal_id) || prior !== null &&
        (instantKey(row.created_at) > instantKey(prior.created_at) || sameInstant(row.created_at, prior.created_at) && row.principal_id >= prior.principal_id)) return false;
    seen.add(row.principal_id); prior = {created_at: row.created_at, principal_id: row.principal_id};
  }
  return value.next_cursor === null || validCursor(value.next_cursor) && value.rows.length === limit && prior !== null &&
    sameInstant(value.next_cursor.created_at, prior.created_at) && value.next_cursor.principal_id === prior.principal_id;
}
export function validLookup(value: unknown, intent: EnrollmentIntent, now: number): value is EnrollmentLookup {
  if (!keys(value, ["contract_version", "request_id", "action", "status", "checked_at", "sample_valid_until", "request_expires_at", "receipt"]) ||
      value.contract_version !== 3 || value.request_id !== intent.request_id || !freshSample(value, now) ||
      !["recorded", "not_recorded", "in_progress"].includes(value.status as string) || typeof value.status !== "string") return false;
  if (value.status === "recorded") return value.action === intent.action && utc(value.request_expires_at) && sameInstant(value.request_expires_at, intent.request_expires_at) && validReceipt(value.receipt, intent) &&
    instantKey(value.receipt.recorded_at) <= instantKey(value.checked_at as string);
  return value.action === null && value.request_expires_at === null && value.receipt === null;
}
export function checkedRevocationReason(value: string) {
  if (typeof value !== "string" || value !== value.trim() || [...value].length < 8 || [...value].length > 500 || /[\x00-\x1f\x7f]/.test(value)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  return value;
}
export function rpcForIntent(intent: EnrollmentIntent, reason?: string) {
  if (!validIntent(intent)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  if (intent.action === "revoke") {
    if (typeof reason !== "string" || sha256(checkedRevocationReason(reason)) !== intent.reason_sha256) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
    return {name: "admin_revoke_receipt_operations_identity_v3", input: {p_principal_id: intent.principal_id, p_request_id: intent.request_id,
      p_expected_key_sha256: intent.key_sha256, p_request_expires_at: intent.request_expires_at, p_reason: reason}};
  }
  return intent.action === "enroll" ? {name: "admin_enroll_receipt_operations_identity_v3", input: {p_request_id: intent.request_id,
    p_public_key_spki_base64: intent.public_key_spki_base64, p_key_sha256: intent.key_sha256,
    p_identity_expires_at: intent.identity_expires_at, p_request_expires_at: intent.request_expires_at}} :
    {name: "admin_activate_receipt_operations_identity_v3", input: {p_principal_id: intent.principal_id,
      p_request_id: intent.request_id, p_expected_key_sha256: intent.key_sha256, p_request_expires_at: intent.request_expires_at}};
}
