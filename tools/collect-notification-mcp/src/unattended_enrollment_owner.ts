import {boundedJson, withinDeadline} from "./operational_client.ts";
import {requireCurrentEmailIdentity} from "./session_renewal.ts";
import {keys, uuid, hash, utc, integer, unattendedScope} from "./unattended_contract.ts";
import {enrollmentOrigin, rpcForIntent, publicKeyMetadata, validCursor, validDirectory, checkedRevocationReason} from "./unattended_enrollment_contract.ts";
import type {EnrollmentIntent, IdentityCursor} from "./unattended_enrollment_contract.ts";
export interface EnrollmentOwner {actorId: string; sessionId: string; publicKey: string; accessToken: string}
export type OwnerRpc = (name: string, input: Record<string, unknown>, signal?: AbortSignal) => Promise<unknown>;
/** Token claims are local hygiene only; current GoTrue and every RPC establish
 * authority. Neither credentials nor Auth response bodies enter the journal. */
export async function enrollmentOwner(environment: NodeJS.ProcessEnv, fetcher: typeof fetch = fetch, now: () => number = Date.now): Promise<EnrollmentOwner> {
  try {
    if (environment.COLLECT_SUPABASE_URL !== enrollmentOrigin) throw Error();
    const key = environment.COLLECT_SUPABASE_ANON_KEY, token = environment.COLLECT_OPERATOR_ACCESS_TOKEN;
    if (!key || key.length > 16384 || !token || token.length > 16384) throw Error();
    const parts = token.split(".");
    if (parts.length !== 3 || !parts.every(part => /^[A-Za-z0-9_-]+$/.test(part))) throw Error();
    const claims = JSON.parse(Buffer.from(parts[1]!, "base64url").toString("utf8"));
    const header = JSON.parse(Buffer.from(parts[0]!, "base64url").toString("utf8"));
    const publicClaims = key.startsWith("sb_publishable_") ? {role: "anon"} : JSON.parse(Buffer.from(key.split(".")[1] ?? "", "base64url").toString("utf8"));
    if (!uuid(claims.sub) || !uuid(claims.session_id) || claims.role !== "authenticated" || claims.iss !== `${enrollmentOrigin}/auth/v1` ||
        !Number.isSafeInteger(claims.exp) || claims.exp <= Math.floor(now() / 1000) + 60 || publicClaims.role !== "anon" ||
        !["HS256", "RS256", "ES256", "EdDSA"].includes(header.alg)) throw Error();
    await requireCurrentEmailIdentity({origin: enrollmentOrigin, anon_key: key, access_token: token}, claims.sub, "info@ikanisa.com", fetcher, now);
    return {actorId: claims.sub, sessionId: claims.session_id, publicKey: key, accessToken: token};
  } catch {throw new Error("ENROLLMENT_OWNER_SESSION_REQUIRED");}
}
function allowed(name: string, input: Record<string, unknown>) {
  if (name === "admin_enroll_receipt_operations_identity_v3") return keys(input, ["p_request_id", "p_public_key_spki_base64", "p_key_sha256", "p_identity_expires_at", "p_request_expires_at"]) &&
    uuid(input.p_request_id) && utc(input.p_identity_expires_at) && utc(input.p_request_expires_at) && publicKeyMetadata({contract_version: 2, scope: unattendedScope,
      public_key_spki_base64: input.p_public_key_spki_base64, key_sha256: input.p_key_sha256});
  if (name === "admin_activate_receipt_operations_identity_v3") return keys(input, ["p_principal_id", "p_request_id", "p_expected_key_sha256", "p_request_expires_at"]) &&
    uuid(input.p_principal_id) && uuid(input.p_request_id) && hash(input.p_expected_key_sha256) && utc(input.p_request_expires_at);
  if (name === "admin_revoke_receipt_operations_identity_v3") return keys(input, ["p_principal_id", "p_request_id", "p_expected_key_sha256", "p_request_expires_at", "p_reason"]) &&
    uuid(input.p_principal_id) && uuid(input.p_request_id) && hash(input.p_expected_key_sha256) && utc(input.p_request_expires_at) &&
    typeof input.p_reason === "string" && checkedRevocationReason(input.p_reason) === input.p_reason;
  if (name === "admin_get_receipt_operations_enrollment_request_v3") return keys(input, ["p_request_id"]) && uuid(input.p_request_id);
  if (name === "admin_get_receipt_operations_identity_v3") return keys(input, ["p_principal_id"]) && uuid(input.p_principal_id);
  if (name === "admin_list_receipt_operations_identities_v3") return keys(input, ["p_limit", "p_before_created_at", "p_before_principal_id"]) && integer(input.p_limit, 1, 25) &&
    (input.p_before_created_at === null && input.p_before_principal_id === null || utc(input.p_before_created_at) && uuid(input.p_before_principal_id));
  return false;
}
export function enrollmentOwnerRpc(owner: EnrollmentOwner, fetcher: typeof fetch = fetch, timeoutMs = 5000): OwnerRpc {
  if (!uuid(owner.actorId) || !uuid(owner.sessionId) || !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  return async (name, input, parentSignal) => {
    if (!allowed(name, input)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
    const controller = new AbortController(), timer = setTimeout(() => controller.abort(), timeoutMs);
    const signal = parentSignal ? AbortSignal.any([controller.signal, parentSignal]) : controller.signal;
    let sent = false;
    try {
      signal.throwIfAborted(); sent = true;
      const response = await withinDeadline(fetcher(`${enrollmentOrigin}/rest/v1/rpc/${name}`, {method: "POST", redirect: "error", cache: "no-store", signal,
        headers: {apikey: owner.publicKey, Authorization: `Bearer ${owner.accessToken}`, Accept: "application/json", "Content-Type": "application/json"}, body: JSON.stringify(input)}), signal);
      if (!response.ok || response.redirected) {void response.body?.cancel().catch(() => {}); throw Error();}
      return await boundedJson(response, signal);
    } catch {throw new Error(sent ? "ENROLLMENT_TRANSPORT_OUTCOME_UNKNOWN" : "ENROLLMENT_TRANSPORT_UNAVAILABLE");}
    finally {clearTimeout(timer);}
  };
}
export function enrollmentWrite(rpc: OwnerRpc, intent: EnrollmentIntent, signal?: AbortSignal) {
  const call = rpcForIntent(intent); return rpc(call.name, call.input, signal);
}
export async function listEnrollmentIdentities(rpc: OwnerRpc, limit = 25, before: IdentityCursor | null = null, now: () => number = Date.now) {
  if (!integer(limit, 1, 25) || before !== null && !validCursor(before)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  const result = await rpc("admin_list_receipt_operations_identities_v3", {p_limit: limit, p_before_created_at: before?.created_at ?? null, p_before_principal_id: before?.principal_id ?? null});
  if (!validDirectory(result, limit, before, now())) throw new Error("ENROLLMENT_DIRECTORY_UNAVAILABLE");
  return result;
}
