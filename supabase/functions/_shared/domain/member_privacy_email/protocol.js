import { ApiError, json, uuid } from "../core.js";

export const purpose = "account_deletion_request";
export const epoch = () => Math.floor(Date.now() / 1000);
export const object = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const modes = ["current_session", "portal_bootstrap"];
const verificationStates = ["not_started", "verifying", "rejected", "unconfirmed", "verified"];
const cleanupStates = ["not_started", "claimed", "confirmed", "unconfirmed"];
export const denied = () =>
  new ApiError(403, "privacy_email_denied", "This verification is unavailable.");
export const invalid = () =>
  new ApiError(400, "privacy_email_invalid", "Check the verification details.");
const unconfirmedMessage =
  "The verification result is unconfirmed. Check its status before continuing.";
export const unknown = () =>
  new ApiError(503, "privacy_email_operation_unknown", unconfirmedMessage);

export function challengeResult(result, input) {
  const c = result?.challenge;
  if (
    !object(result) || !object(c) || c.id !== input.challenge_id || c.mode !== input.mode ||
    typeof c.identity_value !== "string" || c.identity_value.length > 254 ||
    !Number.isSafeInteger(c.created_at) || !Number.isSafeInteger(c.expires_at) ||
    c.created_at <= 0 ||
    c.expires_at <= c.created_at || c.expires_at > c.created_at + 300 ||
    !["reserved", "accepted", "rejected", "unknown"].includes(c.delivery_status) ||
    !verificationStates.includes(c.verification_state) ||
    !cleanupStates.includes(c.cleanup_state) ||
    typeof c.cancelled !== "boolean"
  ) throw unknown();
  if (c.verification_operation_id !== null && c.verification_operation_id !== undefined) {
    uuid(c.verification_operation_id, "operation_id");
  }
  return result;
}

function email(value) {
  if (
    typeof value !== "string" || value.length > 254 || /[\u0000-\u001f\u007f-\u009f]/.test(value) ||
    !/^\S+@[^\s@]+\.[^\s@]+$/.test(value.trim())
  ) throw invalid();
  return value.trim().toLowerCase();
}
export function confirmedEmail(user) {
  if (
    typeof user?.email_confirmed_at !== "string" ||
    !Number.isFinite(Date.parse(user.email_confirmed_at))
  ) throw denied();
  try {
    return email(user.email);
  } catch {
    throw denied();
  }
}
function context(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(value)) throw invalid();
  try {
    const bytes = atob(value.replace(/-/g, "+").replace(/_/g, "/") + "=");
    if (
      bytes.length !== 32 ||
      btoa(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "") !== value
    ) throw 0;
  } catch {
    throw invalid();
  }
  return value;
}
export function parse(body, operation) {
  const allowed = ["contract_version", "purpose", "mode", "challenge_id", "challenge_context"];
  if (operation === "challenge") {
    allowed.push("email", "captcha_token", "allow_registration", "should_create_user");
  }
  if (operation === "verify") allowed.push("operation_id", "code", "captcha_token");
  if (operation === "status") allowed.push("operation_id");
  if (operation === "cancel") allowed.push("operation_id", "candidate_access_token");
  if (
    Object.keys(body).some((key) => !allowed.includes(key)) || body.contract_version !== 1 ||
    body.purpose !== purpose || !modes.includes(body.mode)
  ) throw invalid();
  const input = {
    ...body,
    challenge_id: uuid(body.challenge_id, "challenge_id"),
    challenge_context: context(body.challenge_context),
  };
  if (body.operation_id !== undefined && body.operation_id !== null) {
    input.operation_id = uuid(body.operation_id, "operation_id");
  } else input.operation_id = null;
  if (
    operation === "verify" &&
    (!input.operation_id || typeof body.code !== "string" || !/^\d{6,10}$/.test(body.code))
  ) throw invalid();
  if (
    body.captcha_token !== undefined &&
    (typeof body.captcha_token !== "string" || !body.captcha_token ||
      body.captcha_token.length > 8192)
  ) throw invalid();
  if (operation === "challenge") {
    if (
      body.allow_registration !== undefined && body.allow_registration !== false ||
      body.should_create_user !== undefined && body.should_create_user !== false
    ) throw invalid();
    if (body.mode === "current_session" && Object.hasOwn(body, "email")) throw invalid();
    input.email = body.mode === "portal_bootstrap" ? email(body.email) : null;
  }
  if (
    body.candidate_access_token !== undefined &&
    (typeof body.candidate_access_token !== "string" || !body.candidate_access_token ||
      body.candidate_access_token.length > 16384 || /\s/.test(body.candidate_access_token))
  ) throw invalid();
  return input;
}

export function envelope(input) {
  return {
    contract_version: 1,
    purpose,
    mode: input.mode,
    identity_type: "email",
    channel: "email",
    challenge_id: input.challenge_id,
    challenge_context: input.challenge_context,
  };
}
function destination(value) {
  const split = value.lastIndexOf("@");
  return split > 0 ? value[0] + "***@" + value.slice(split + 1) : "***";
}
export function receipt(input, result) {
  const c = result.challenge;
  return {
    ...envelope(input),
    destination_hint: destination(c.identity_value),
    retry_after: 60,
    created_at: c.created_at,
    expires_at: c.expires_at,
    delivery_status: input.mode === "portal_bootstrap" ? "not_disclosed" : c.delivery_status,
    verification_state: c.verification_state,
    operation_id: c.verification_operation_id ?? null,
    cancelled: c.cancelled,
    candidate_cleanup: c.cleanup_state === "confirmed"
      ? "confirmed"
      : c.verification_state === "not_started" && c.cleanup_state === "not_started"
      ? "not_required"
      : "unconfirmed",
  };
}
export function unresolved(input) {
  return json({
    ...envelope(input),
    code: "privacy_email_operation_unknown",
    message: unconfirmedMessage,
    operation_id: input.operation_id,
    outcome: "unconfirmed",
    candidate_cleanup: "unconfirmed",
  }, 503);
}
