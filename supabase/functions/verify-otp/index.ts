import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { HttpError } from "../_shared/auth.ts";
import {
  isAppCheckEnforced,
  requireAppCheckToken,
} from "../_shared/app_check.ts";
import {
  countRecentOtpRateEvents,
  extractClientIp,
  hashOtpRateActorKey,
} from "../_shared/otp_abuse.ts";
import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { normalizePhone, PhoneValidationError } from "../_shared/phone.ts";
import {
  derivePhoneEmail,
  derivePhonePassword,
  hashOtpCode,
  isReviewOtpMatch,
} from "../_shared/security.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import {
  type AdminClient,
  ensureAuthUser,
  findExistingAppUser,
  isRecoverableSignInError,
  mintSessionViaMagicLink,
  recordVerifyRateEvents,
  reportVerifyOtpFailure,
  signInWithDerivedPassword,
} from "./verify_otp_helpers.ts";

// ─── Types & constants ──────────────────────────────────────────────────────

type VerifyOtpRequest = { phone?: string; code?: string };

export type VerifyOtpHandlerDependencies = {
  createAdminClient: () => AdminClient;
  isAppCheckEnforced: () => boolean;
  requireAppCheckToken: (request: Request) => Promise<string>;
  recordEdgeFunctionFailure: typeof recordEdgeFunctionFailure;
};

const RATE_WINDOW_MS = 10 * 60 * 1000;
const MAX_IP_ATTEMPTS = 20;
const MAX_PHONE_ATTEMPTS = 9;
const MAX_OTP_CODE_ATTEMPTS = 3;
const FAILURE_MSG = "Failed to verify OTP";

const defaultDeps: VerifyOtpHandlerDependencies = {
  createAdminClient,
  isAppCheckEnforced: () =>
    isAppCheckEnforced(["ENFORCE_OTP_APP_CHECK", "ENFORCE_APP_CHECK"]),
  requireAppCheckToken,
  recordEdgeFunctionFailure,
};

// ─── Handler ─────────────────────────────────────────────────────────────────

export function createVerifyOtpHandler(deps = defaultDeps) {
  return async (request: Request): Promise<Response> => {
    const corsResponse = handleCors(request);
    if (corsResponse) return corsResponse;
    if (request.method !== "POST") return methodNotAllowed("POST", request);

    let phone: string | null = null;
    let adminClient: AdminClient | null = null;

    try {
      if (deps.isAppCheckEnforced()) {
        await deps.requireAppCheckToken(request);
      }

      // ── Parse & validate ──────────────────────────────────────────
      const body = (await request.json()) as VerifyOtpRequest;
      const normalizedPhone = normalizePhone(body.phone ?? "");
      phone = normalizedPhone;
      const code = (body.code ?? "").trim();

      if (!/^\d{6}$/.test(code)) {
        return errorResponse("Code must be 6 digits", 400, undefined, request);
      }

      adminClient = deps.createAdminClient();

      // ── Rate limiting ─────────────────────────────────────────────
      const windowStart = new Date(Date.now() - RATE_WINDOW_MS).toISOString();
      const clientIp = extractClientIp(request);
      const ipActorKey = clientIp
        ? await hashOtpRateActorKey(`verify_ip:${clientIp}`)
        : null;
      const phoneActorKey = await hashOtpRateActorKey(
        `verify_phone:${normalizedPhone}`,
      );

      if (ipActorKey) {
        const ipEvents = await countRecentOtpRateEvents(adminClient, {
          action: "verify_ip",
          actorKey: ipActorKey,
          windowStartIso: windowStart,
        });
        if (ipEvents >= MAX_IP_ATTEMPTS) {
          await recordVerifyRateEvents(adminClient, {
            ipActorKey, phoneActorKey, outcome: "blocked_ip_limit",
            phone: normalizedPhone, metadata: { limit: MAX_IP_ATTEMPTS },
          });
          return errorResponse(
            "Too many verification attempts from this network. Request a new code later.",
            429, { retryAfterSeconds: 600 }, request,
          );
        }
      }

      const phoneEvents = await countRecentOtpRateEvents(adminClient, {
        action: "verify_phone",
        actorKey: phoneActorKey,
        windowStartIso: windowStart,
      });
      if (phoneEvents >= MAX_PHONE_ATTEMPTS) {
        await recordVerifyRateEvents(adminClient, {
          ipActorKey, phoneActorKey, outcome: "blocked_phone_limit",
          phone: normalizedPhone, metadata: { limit: MAX_PHONE_ATTEMPTS },
        });
        return errorResponse(
          "Too many verification attempts for this phone number. Request a new code later.",
          429, { retryAfterSeconds: 600 }, request,
        );
      }

      // ── OTP validation ────────────────────────────────────────────
      const usingReviewOtp = isReviewOtpMatch(normalizedPhone, code);
      let otpRecordId: string | null = null;

      if (!usingReviewOtp) {
        const otpResult = await adminClient
          .from("otp_codes")
          .select("*")
          .eq("phone", normalizedPhone)
          .order("created_at", { ascending: false })
          .limit(1);

        if (otpResult.error) throw otpResult.error;

        const otp = otpResult.data?.[0];
        if (!otp) {
          await recordVerifyRateEvents(adminClient, {
            ipActorKey, phoneActorKey, outcome: "missing_otp", phone: normalizedPhone,
          });
          return errorResponse("No OTP found for this phone number", 404, undefined, request);
        }

        if ((otp.attempts ?? 0) >= MAX_OTP_CODE_ATTEMPTS) {
          await recordVerifyRateEvents(adminClient, {
            ipActorKey, phoneActorKey, outcome: "blocked_phone_attempts", phone: normalizedPhone,
          });
          return errorResponse("Too many attempts. Request a new code.", 429, undefined, request);
        }

        if (new Date(otp.expires_at).getTime() < Date.now()) {
          await recordVerifyRateEvents(adminClient, {
            ipActorKey, phoneActorKey, outcome: "expired", phone: normalizedPhone,
          });
          return errorResponse("OTP code has expired", 400, undefined, request);
        }

        const incomingHash = await hashOtpCode(normalizedPhone, code);
        if (incomingHash !== otp.code) {
          const nextAttempts = (otp.attempts ?? 0) + 1;
          await adminClient.from("otp_codes").update({ attempts: nextAttempts }).eq("id", otp.id);
          await recordVerifyRateEvents(adminClient, {
            ipActorKey, phoneActorKey, outcome: "invalid_code", phone: normalizedPhone,
            metadata: { attemptsRemaining: Math.max(0, MAX_OTP_CODE_ATTEMPTS - nextAttempts) },
          });
          return errorResponse("Invalid OTP code", 400, {
            attemptsRemaining: Math.max(0, MAX_OTP_CODE_ATTEMPTS - nextAttempts),
          }, request);
        }

        otpRecordId = otp.id;
      }

      // ── Session creation ──────────────────────────────────────────
      const existingAppUserId = await findExistingAppUser(adminClient, normalizedPhone);
      const authEmail = await derivePhoneEmail(normalizedPhone);
      const session = await obtainSession(adminClient, normalizedPhone, authEmail);

      // Clean up consumed OTP
      if (otpRecordId) {
        await adminClient.from("otp_codes").delete().eq("id", otpRecordId);
      }

      await recordVerifyRateEvents(adminClient, {
        ipActorKey, phoneActorKey,
        outcome: usingReviewOtp ? "review_success" : "success",
        phone: normalizedPhone,
      });

      return jsonResponse({
        success: true,
        session,
        access_token: session.access_token,
        refresh_token: session.refresh_token,
        isNewUser: existingAppUserId == null,
        userId: session.user?.id,
      }, 200, {}, request);
    } catch (error) {
      if (error instanceof SyntaxError) {
        return errorResponse("Invalid JSON body", 400, undefined, request);
      }
      if (error instanceof PhoneValidationError) {
        return errorResponse(error.message, 400, undefined, request);
      }
      if (error instanceof HttpError) {
        return errorResponse(error.message, error.status, undefined, request);
      }
      console.error("verify-otp failed", error);
      await reportVerifyOtpFailure(deps, adminClient, phone, error);
      return errorResponse(FAILURE_MSG, 500, undefined, request);
    }
  };
}

// ─── Session orchestration ───────────────────────────────────────────────────

/**
 * Obtain a Supabase session for the given phone number.
 *
 * Strategy (ordered by preference):
 *  1. signInWithPassword using derived email → works for existing users
 *  2. ensureAuthUser + signInWithPassword → creates/updates user, then signs in
 *  3. Admin magic link → server-side session mint as last resort
 */
async function obtainSession(
  adminClient: AdminClient,
  phone: string,
  authEmail: string,
) {
  const derivedPassword = await derivePhonePassword(phone);

  // Attempt 1: direct sign-in
  const attempt1 = await signInWithDerivedPassword(authEmail, derivedPassword);
  if (!attempt1.error && attempt1.data.session) {
    return attempt1.data.session;
  }

  if (!isRecoverableSignInError(attempt1.error)) {
    throw attempt1.error ?? new Error("Could not create session");
  }

  // Attempt 2: ensure user exists, then sign in
  const authUser = await ensureAuthUser(adminClient, phone, authEmail);
  const attempt2 = await signInWithDerivedPassword(authEmail, authUser.password);
  if (!attempt2.error && attempt2.data.session) {
    return attempt2.data.session;
  }

  // Attempt 3: magic link fallback
  console.warn(
    "signInWithPassword failed after ensureAuthUser, using magic link:",
    attempt2.error?.message ?? "no session",
  );
  const magicData = await mintSessionViaMagicLink(adminClient, authEmail);
  return magicData.session!;
}

// ─── Entrypoint ──────────────────────────────────────────────────────────────

if (import.meta.main) {
  Deno.serve(createVerifyOtpHandler());
}
