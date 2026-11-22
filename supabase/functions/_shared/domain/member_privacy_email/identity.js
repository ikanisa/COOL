import { first } from "../core.js";
import { verifyToken } from "../../auth-http.js";
import { bearerToken } from "../member_auth/support.js";
import { confirmedEmail, denied, epoch, object, purpose, unknown } from "./protocol.js";

function bearer(request) {
  const value = bearerToken(request);
  if (!value || value.length > 16384) throw denied();
  return value;
}
async function existingMember(env, verified, { cleanup = false } = {}) {
  env.DB.setClaims(verified.claims);
  const managed = await first(
    env,
    "SELECT private.is_managed_session(?::uuid,?::uuid) AS allowed",
    verified.user.id,
    verified.claims.session_id,
  );
  if (managed?.allowed !== true) throw denied();
  if (cleanup) {
    const link = await first(
      env,
      "SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?",
      verified.user.id,
    );
    if (!link || typeof link.user_id !== "string" || !link.user_id) throw denied();
    return link;
  }
  const member = await first(
    env,
    "SELECT l.user_id,u.access_status,u.revision FROM private.auth_principal_links l JOIN users u ON u.id=l.user_id WHERE l.auth_user_id=?",
    verified.user.id,
  );
  if (
    !member || member.access_status !== "active" || !Number.isSafeInteger(member.revision) ||
    member.revision < 1
  ) throw denied();
  return member;
}
export function assertNative(original, c) {
  if (
    c.mode !== "current_session" || c.expected_auth_user_id !== original.verified.user.id ||
    c.expected_user_id !== original.member.user_id ||
    c.initiating_session_id !== original.verified.claims.session_id ||
    c.initiating_user_revision !== original.member.revision ||
    c.identity_value !== original.email
  ) throw denied();
}
export async function nativeAuthority(request, env, c = null) {
  const verified = await verifyToken(env, bearer(request));
  const member = await existingMember(env, verified),
    session = await first(
      env,
      "SELECT * FROM auth_sessions WHERE id=?",
      verified.claims.session_id,
    );
  if (
    !session || session.user_id !== member.user_id || session.surface !== "member" ||
    session.revoked_at !== null ||
    !Number.isSafeInteger(session.expires_at) || session.expires_at <= epoch()
  ) throw denied();
  const original = { verified, member, email: confirmedEmail(verified.user) };
  if (c) assertNative(original, c);
  return original;
}
export async function authority(request, env, input) {
  if (input.mode === "current_session") return nativeAuthority(request, env);
  if (request.headers.has("Authorization")) throw denied();
  env.DB.setClaims({});
  return null;
}
export function install(env, original) {
  env.DB.setClaims(original?.verified.claims ?? {});
}

export function assertLive(c) {
  const at = epoch();
  if (c.cancelled || c.created_at > at || c.expires_at < at) throw denied();
}
function otpEvent(verified, c) {
  const at = epoch();
  assertLive(c);
  let found = null;
  for (const entry of Array.isArray(verified.claims.amr) ? verified.claims.amr : []) {
    if (
      object(entry) && entry.method === "otp" && Number.isSafeInteger(entry.timestamp) &&
      entry.timestamp > 0 && entry.timestamp >= c.created_at && entry.timestamp <= at &&
      entry.timestamp >= at - 300
    ) {
      found = found === null ? entry.timestamp : Math.min(found, entry.timestamp);
    }
  }
  if (found === null) throw denied();
  return found;
}
export function tokens(data, verified) {
  if (
    !object(data) || typeof data.access_token !== "string" || !data.access_token ||
    data.access_token.length > 16384 || /\s/.test(data.access_token) ||
    typeof data.refresh_token !== "string" || !data.refresh_token ||
    data.refresh_token.length > 4096 || /\s/.test(data.refresh_token) ||
    verified.token !== data.access_token
  ) throw unknown();
  return {
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    token_type: "bearer",
    expires_at: verified.claims.exp,
    expires_in: Math.max(1, verified.claims.exp - epoch()),
  };
}
export async function candidate(env, verified, c, original, { cleanup = false } = {}) {
  const member = await existingMember(env, verified, { cleanup });
  if (!cleanup && confirmedEmail(verified.user) !== c.identity_value) throw denied();
  if (c.mode === "current_session") {
    if (original) assertNative(original, c);
    if (
      verified.user.id !== c.expected_auth_user_id || member.user_id !== c.expected_user_id ||
      verified.claims.session_id === c.initiating_session_id
    ) throw denied();
  }
  // Cleanup uses immutable recorded proof even after local cancellation/expiry.
  const event = cleanup ? c.verified_amr_at : otpEvent(verified, c);
  if (cleanup) {
    if (
      c.verified_session_id !== verified.claims.session_id || !Number.isSafeInteger(event) ||
      event <= 0 ||
      !Array.isArray(verified.claims.amr) || !verified.claims.amr.some((entry) =>
        object(entry) && entry.method === "otp" && entry.timestamp === event
      )
    ) {
      throw denied();
    }
  } else if (c.mode === "current_session" && member.revision !== c.initiating_user_revision) {
    throw denied();
  }
  return { member, event };
}

export function proof(result, input, verified, member, event) {
  const p = result.proof, c = result.challenge;
  if (
    !object(p) || p.purpose !== purpose || p.challenge_id !== input.challenge_id ||
    p.user_id !== member.user_id || p.auth_user_id !== verified.user.id ||
    p.session_id !== verified.claims.session_id ||
    p.initiating_session_id !==
      (input.mode === "current_session" ? c.initiating_session_id : null) ||
    p.method !== "otp" || p.authenticated_at !== event || p.expires_at !== c.expires_at ||
    c.verified_session_id !== verified.claims.session_id || c.verified_amr_at !== event ||
    c.verification_state !== "verified" || c.verification_operation_id !== input.operation_id ||
    c.cancelled
  ) throw unknown();
  return {
    purpose,
    challenge_id: p.challenge_id,
    user_id: p.user_id,
    auth_user_id: p.auth_user_id,
    initiating_session_id: p.initiating_session_id,
    session_id: p.session_id,
    method: "otp",
    authenticated_at: p.authenticated_at,
    expires_at: p.expires_at,
  };
}
