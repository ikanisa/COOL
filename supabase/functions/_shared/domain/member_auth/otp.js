import { ApiError, digest, first, id, uuid } from "../core.js";
import { authRequest, verifyToken } from "../../auth-http.js";
import { resolveDeploymentProfile } from "../../deployment-profile.js";
import { adminEmailCodeTtlSeconds } from "../admin_email_code_policy.js";
import {
  assertManagedEmailOtp,
  assertManagedEmailOtpDispatch,
  reserveManagedEmailOtp,
} from "../burimunsi/managed-email-otp.js";
import { projectSession } from "./session.js";
import { confirmedIdentity, fail, unix } from "./support.js";

function identity(body) {
  const surface = body.surface ?? "member";
  if (!["member", "admin"].includes(surface) || (body.phone == null) === (body.email == null)) {
    fail("invalid_request", 400);
  }
  if (body.phone != null) {
    if (
      surface === "admin" || typeof body.phone !== "string" ||
      !/^\+2507[2389][0-9]{7}$/.test(body.phone)
    ) fail("invalid_phone", 400);
    return { type: "phone", value: body.phone, surface, channel: body.channel ?? "whatsapp" };
  }
  if (
    typeof body.email !== "string" || body.email.length > 254 ||
    !/^\S+@[^\s@]+\.[^\s@]+$/.test(body.email.trim())
  ) fail("invalid_email", 400);
  return { type: "email", value: body.email.trim().toLowerCase(), surface, channel: "email" };
}

function phoneChannelEnabled(env, channel) {
  const flag = channel === "sms" ? "AUTH_SMS_ENABLED" : "AUTH_WHATSAPP_ENABLED";
  return env[flag] !== undefined
    ? env[flag] === "true"
    : env.COLLECT_DEPLOYMENT_PROFILE === undefined && env.AUTH_PHONE_ENABLED !== "false";
}
export async function startOtp(env, body, { nativeAdmission = null } = {}) {
  const target = identity(body);
  if (target.type === "phone" && !["sms", "whatsapp"].includes(target.channel)) {
    fail("invalid_channel", 400);
  }
  if (nativeAdmission !== null && (target.type !== "email" || target.surface !== "admin")) {
    fail("native_email_admission_denied", 403);
  }
  const otpPath = target.type === "email" && target.surface === "admin"
    ? "/otp?redirect_to=" + encodeURIComponent(resolveDeploymentProfile(env).admin_origin)
    : "/otp";
  const ttl = target.type === "email" && target.surface === "admin"
    ? adminEmailCodeTtlSeconds(env)
    : 300;
  if (target.type === "phone") {
    if (!phoneChannelEnabled(env, target.channel)) fail(target.channel + "_unavailable", 503);
  }
  const existing = nativeAdmission !== null
    ? { native: true }
    : target.surface === "admin"
    ? await first(
      env,
      "SELECT a.id FROM admin_users a JOIN admin_principal_links l ON l.admin_user_id=a.id JOIN users u ON u.id=l.user_id WHERE a.email=? AND a.status IN('active','invited') AND u.access_status='active'",
      target.value,
    )
    : target.type === "email"
    ? await first(
      env,
      `SELECT id FROM users WHERE lower(email)=? AND access_status='active' UNION SELECT l.user_id AS id FROM admin_principal_links l JOIN admin_users a ON a.id=l.admin_user_id JOIN users u ON u.id=l.user_id WHERE a.email=? AND a.status IN('active','invited') AND u.access_status='active'`,
      target.value,
      target.value,
    )
    : await first(
      env,
      `SELECT id FROM users WHERE phone=? AND access_status='active'`,
      target.value,
    );
  const registration = target.surface === "member" &&
    env.AUTH_MEMBER_REGISTRATION_ENABLED === "true" && body.allow_registration !== false &&
    body.should_create_user !== false;
  if (!existing && !registration) {
    fail(
      target.surface === "admin" ? "admin_access_not_approved" : "registration_unavailable",
      403,
    );
  }
  const key = await digest(target.type + ":" + target.value), at = unix();
  let expiresAt = at + ttl;
  const challenge = id(), guard = id();
  if (nativeAdmission !== null) {
    expiresAt =
      (await reserveManagedEmailOtp(env, nativeAdmission, target.value, challenge, ttl)).expiresAt;
  } else {try {
      await env.DB.batch([
        env.DB.prepare(
          "INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN NOT EXISTS(SELECT 1 FROM private.supabase_otp_challenges WHERE identity_hash=? AND created_at>?) THEN 1 ELSE 0 END",
        ).bind(guard, key, at - 60),
        env.DB.prepare(
          "INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status) VALUES(?,?,?,?,?,?,?,?,'reserved')",
        ).bind(
          challenge,
          key,
          target.type,
          target.value,
          target.surface,
          Number(registration),
          at,
          expiresAt,
        ),
        env.DB.prepare("DELETE FROM admin_bridge_guards WHERE id=?").bind(guard),
      ]);
    } catch (error) {
      if (/admin_bridge_guards|check constraint|otp_cooldown/.test(String(error))) {
        fail("auth_rate_limited", 429);
      }
      throw error;
    }}
  if (nativeAdmission !== null) assertManagedEmailOtpDispatch(env, nativeAdmission, challenge);
  let outcome = "accepted";
  try {
    await authRequest(env, otpPath, {
      admin: nativeAdmission !== null,
      body: {
        [target.type]: target.value,
        create_user: nativeAdmission !== null
          ? false
          : registration || target.surface === "admin" ||
            Boolean(existing) && body.allow_registration !== false &&
              body.should_create_user !== false,
        ...(target.type === "phone" ? { channel: target.channel } : {}),
        gotrue_meta_security: { captcha_token: body.captcha_token },
      },
    });
  } catch (error) {
    outcome = error instanceof ApiError && [400, 401, 403, 422, 429].includes(error.status)
      ? "rejected"
      : "unknown";
    await env.DB.prepare("UPDATE private.supabase_otp_challenges SET delivery_status=? WHERE id=?")
      .bind(outcome, challenge).run();
    if (outcome === "rejected") throw error;
  }
  if (outcome === "accepted") {
    await env.DB.prepare("UPDATE private.supabase_otp_challenges SET delivery_status=? WHERE id=?")
      .bind(outcome, challenge).run();
  }
  return {
    challenge_id: challenge,
    retry_after: 60,
    expires_in: Math.max(0, Math.min(ttl, expiresAt - unix())),
    channel: target.channel,
    delivery_status: outcome,
  };
}
export async function verifyOtp(env, body, { project = true } = {}) {
  const challenge = await env.DB.prepare(
    `UPDATE private.supabase_otp_challenges pending SET attempts=pending.attempts+1 WHERE pending.id=? AND pending.consumed_at IS NULL AND pending.expires_at>? AND pending.attempts<5 AND pending.delivery_status IN('accepted','unknown') AND pending.surface=?
  AND NOT EXISTS(SELECT 1 FROM private.supabase_otp_challenges newer WHERE newer.identity_hash=pending.identity_hash AND newer.surface=pending.surface AND newer.created_at>pending.created_at) RETURNING pending.*`,
  ).bind(uuid(body.challenge_id, "challenge_id"), unix(), body.surface ?? "member").first();
  if (!challenge || typeof body.code !== "string" || !/^\d{6,10}$/.test(body.code)) {
    fail("invalid_credentials");
  }
  if (challenge.native_preauth === true) await assertManagedEmailOtp(env, challenge.id);
  const data = await authRequest(env, "/verify", {
    body: {
      [challenge.identity_type]: challenge.identity_value,
      token: body.code,
      type: challenge.identity_type === "email" ? "email" : "sms",
      gotrue_meta_security: { captcha_token: body.captcha_token },
    },
  });
  // The provider's verify response is not a phone/email assertion. Re-read
  // the actual managed user and bind its confirmed identity to this challenge
  // before consuming the local one-shot admission.
  const verified = await verifyToken(env, data.access_token);
  const actual = confirmedIdentity(verified.user, challenge.identity_type);
  if (actual !== challenge.identity_value) {
    await authRequest(env, "/logout?scope=local", { token: data.access_token }).catch(() => {});
    fail("verified_identity_mismatch", 403);
  }
  let consumed;
  if (challenge.native_preauth === true) {
    try {
      await assertManagedEmailOtp(env, challenge.id, verified.user.id, { consume: true });
      consumed = { id: challenge.id };
    } catch (error) {
      await authRequest(env, "/logout?scope=local", { token: data.access_token }).catch(() => {});
      throw error;
    }
  } else {consumed = await env.DB.prepare(
      `UPDATE private.supabase_otp_challenges pending SET consumed_at=? WHERE pending.id=? AND pending.consumed_at IS NULL
  AND NOT EXISTS(SELECT 1 FROM private.supabase_otp_challenges newer WHERE newer.identity_hash=pending.identity_hash AND newer.surface=pending.surface AND newer.created_at>pending.created_at) RETURNING pending.id`,
    ).bind(unix(), challenge.id).first();}
  if (!consumed) {
    await authRequest(env, "/logout?scope=local", { token: data.access_token }).catch(() => {});
    fail("challenge_consumed");
  }
  if (!project) return data;
  const actor = await projectSession(env, verified, { surface: challenge.surface });
  if (challenge.identity_type === "phone" && challenge.surface === "member") {
    const proof = await first(
      env,
      "SELECT private.record_managed_phone_verification(?) AS challenge_id",
      challenge.id,
    );
    if (proof?.challenge_id !== challenge.id) fail("phone_proof_unconfirmed", 503);
  }
  return { ...data, user: actor.user };
}

// Keep the existing WhatsApp preference for compatible configurations. SMS is
// offered only when explicitly enabled by the configured provider.
export function otpDeliveryChannel(env) {
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return null;
  if (
    (env.AUTH_WHATSAPP_ENABLED !== undefined || env.AUTH_PHONE_ENABLED === "true") &&
    phoneChannelEnabled(env, "whatsapp")
  ) return "whatsapp";
  if (env.AUTH_SMS_ENABLED === "true" && phoneChannelEnabled(env, "sms")) return "sms";
  return null;
}
export const otpDeliveryAvailable = (env) => otpDeliveryChannel(env) !== null;
