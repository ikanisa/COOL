import { reserveOtp } from "./capacity.ts";
import type { Context } from "npm:hono@4.13.13";
import { application } from "./auth.ts";
import { makeMessage, messageInsert } from "./messages.ts";
import type { AppEnv } from "./types.ts";
import {
  ApiError,
  after,
  canonical,
  hmac,
  isoNow,
  phone,
  randomCode,
  sha256,
  string,
  uid,
} from "./util.ts";
export async function createChallenge(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  const p = application(c, "otp", "otp"),
    destination = phone(body.phone),
    purpose = string(body.purpose, "purpose", 1, 80);
  if (
    !c.env.OTP_HMAC_KEY ||
    c.env.OTP_HMAC_KEY.length < 32 ||
    c.env.OTP_HMAC_KEY.startsWith("REPLACE_")
  )
    throw new ApiError(
      503,
      "otp_unconfigured",
      "OTP verification is not configured",
    );
  if(c.env.DISPATCH_PAUSED === "true") throw new ApiError(503,"dispatch_paused","Dispatch is paused for maintenance or reconciliation");
  const requireGateway =
    c.env.OTP_REQUIRE_READY_GATEWAY !== "false" &&
    (c.env.OTP_REQUIRE_READY_GATEWAY === "true" ||
      c.env.ENVIRONMENT !== "development");
  if (requireGateway) {
    const available = await c.env.DB.prepare(
      "SELECT 1 AS available FROM devices d WHERE d.revoked_at IS NULL AND d.ready=1 AND d.last_seen_at>=? AND EXISTS(SELECT 1 FROM json_each(d.allowed_kinds) WHERE value='otp') LIMIT 1",
    )
      .bind(new Date(Date.now() - 45_000).toISOString())
      .first();
    if (!available)
      throw new ApiError(
        503,
        "otp_gateway_unavailable",
        "No recently active OTP gateway is available; try again shortly",
      );
  }
  const id = uid("challenge"),
    now = isoNow(),
    expiresAt = after(180_000),
    resendAfter = after(30_000),
    code = randomCode();
  const verifier = await hmac(c.env.OTP_HMAC_KEY, `${p.id}\n${id}\n${code}`);
  const m = await makeMessage({
    message_id: uid("msg"),
    application_id: p.id,
    kind: "otp",
    to: destination,
    text: `Your ${purpose} code is ${code}. It expires in 3 minutes.`,
    request_digest: await sha256(canonical({ challenge_id: id })),
    idempotency_key: `otp:${id}`,
    priority: 120,
    not_after: after(30_000),
    available_at: now,
    created_at: now,
    otp_challenge_id: id,
  });
  // All dependent writes are guarded by the exact newly installed challenge.
  const results = await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO otp_slots(application_id,phone,purpose,generation,current_challenge_id,resend_after) VALUES(?,?,?,1,?,?) ON CONFLICT(application_id,phone,purpose) DO UPDATE SET generation=otp_slots.generation+1,current_challenge_id=excluded.current_challenge_id,resend_after=excluded.resend_after WHERE otp_slots.resend_after<=?`,
    ).bind(p.id, destination, purpose, id, resendAfter, now),
    c.env.DB.prepare(
      "INSERT INTO otp_challenges(challenge_id,application_id,phone,purpose,generation,verifier,expires_at,remaining_attempts,created_at) SELECT ?,application_id,phone,purpose,generation,?,?,5,? FROM otp_slots WHERE application_id=? AND phone=? AND purpose=? AND current_challenge_id=?",
    ).bind(id, verifier, expiresAt, now, p.id, destination, purpose, id),
    messageInsert(c.env.DB, m, { challengeGuard: id }),
    ...(requireGateway ? reserveOtp(c.env,m) : []),
    c.env.DB.prepare(
      `UPDATE messages SET cancel_requested=1,state=CASE WHEN owner_installation_id IS NULL THEN 'cancelled' ELSE state END,updated_at=? WHERE otp_challenge_id IN(SELECT challenge_id FROM otp_challenges WHERE application_id=? AND phone=? AND purpose=? AND challenge_id<>?) AND state NOT IN('sent','delivered','failed','expired','cancelled') AND EXISTS(SELECT 1 FROM otp_challenges WHERE challenge_id=?)`,
    ).bind(now, p.id, destination, purpose, id, id),
  ]);
  if (!results[0]!.meta.changes)
    throw new ApiError(
      429,
      "resend_cooldown",
      "Wait before requesting another code for this phone and purpose",
    );
  return c.json(
    { challenge_id: id, expires_at: expiresAt, resend_after: resendAfter },
    201,
  );
}
export async function verifyChallenge(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  const p = application(c, "otp", "otp"),
    id = string(body.challenge_id, "challenge_id", 1, 100),
    code = string(body.code, "code", 6, 6);
  if (!/^\d{6}$/.test(code))
    throw new ApiError(
      400,
      "invalid_code",
      "The code is invalid or no longer active",
    );
  if (
    !c.env.OTP_HMAC_KEY ||
    c.env.OTP_HMAC_KEY.length < 32 ||
    c.env.OTP_HMAC_KEY.startsWith("REPLACE_")
  )
    throw new ApiError(
      503,
      "otp_unconfigured",
      "OTP verification is not configured",
    );
  const candidate = await hmac(c.env.OTP_HMAC_KEY, `${p.id}\n${id}\n${code}`),
    now = isoNow();
  const row = await c.env.DB.prepare(
    `UPDATE otp_challenges SET remaining_attempts=remaining_attempts-1,consumed_at=CASE WHEN verifier=? THEN ? ELSE consumed_at END WHERE challenge_id=? AND application_id=? AND consumed_at IS NULL AND expires_at>? AND remaining_attempts>0 AND EXISTS(SELECT 1 FROM otp_slots s WHERE s.application_id=otp_challenges.application_id AND s.phone=otp_challenges.phone AND s.purpose=otp_challenges.purpose AND s.current_challenge_id=otp_challenges.challenge_id AND s.generation=otp_challenges.generation) RETURNING challenge_id,phone,purpose,consumed_at`,
  )
    .bind(candidate, now, id, p.id, now)
    .first<{
      challenge_id: string;
      phone: string;
      purpose: string;
      consumed_at: string | null;
    }>();
  if (!row?.consumed_at)
    throw new ApiError(
      400,
      "invalid_code",
      "The code is invalid or no longer active",
    );
  return c.json({
    verified: true,
    challenge_id: row.challenge_id,
    phone: row.phone,
    purpose: row.purpose,
    verified_at: row.consumed_at,
  });
}
