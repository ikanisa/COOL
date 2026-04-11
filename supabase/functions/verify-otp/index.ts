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
} from "../_shared/security.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import {
  type AdminClient,
  ensureAuthUser,
  findExistingAppUser,
  isRecoverableSignInError,
  isReviewOtpMatch,
  recordVerifyRateEvents,
  reportVerifyOtpFailure,
  signInWithDerivedPassword,
} from "./verify_otp_helpers.ts";

type VerifyOtpRequest = {
  phone?: string;
  code?: string;
};

export type VerifyOtpHandlerDependencies = {
  createAdminClient: () => AdminClient;
  isAppCheckEnforced: () => boolean;
  requireAppCheckToken: (request: Request) => Promise<string>;
  recordEdgeFunctionFailure: typeof recordEdgeFunctionFailure;
};

const verifyRateLimitWindowMs = 10 * 60 * 1000;
const maxVerifyAttemptsPerIpPerWindow = 20;
const maxVerifyAttemptsPerPhonePerWindow = 9;
const verifyOtpFailureMessage = "Failed to verify OTP";

const defaultVerifyOtpHandlerDependencies: VerifyOtpHandlerDependencies = {
  createAdminClient,
  isAppCheckEnforced: () =>
    isAppCheckEnforced(["ENFORCE_OTP_APP_CHECK", "ENFORCE_APP_CHECK"]),
  requireAppCheckToken,
  recordEdgeFunctionFailure,
};

export function createVerifyOtpHandler(
  deps: VerifyOtpHandlerDependencies = defaultVerifyOtpHandlerDependencies,
) {
  return async (request: Request): Promise<Response> => {
    const corsResponse = handleCors(request);
    if (corsResponse) {
      return corsResponse;
    }

    if (request.method != "POST") {
      return methodNotAllowed("POST", request);
    }

    let normalizedPhoneForTelemetry: string | null = null;
    let adminClient: AdminClient | null = null;

    try {
      if (deps.isAppCheckEnforced()) {
        await deps.requireAppCheckToken(request);
      }

      const body = await request.json() as VerifyOtpRequest;
      const normalizedPhone = normalizePhone(body.phone ?? "");
      normalizedPhoneForTelemetry = normalizedPhone;
      const code = (body.code ?? "").trim();

      if (!/^\d{6}$/.test(code)) {
        return errorResponse("Code must be 6 digits", 400, undefined, request);
      }

      adminClient = deps.createAdminClient();
      const clientIp = extractClientIp(request);
      const windowStart = new Date(Date.now() - verifyRateLimitWindowMs)
        .toISOString();
      const ipActorKey = clientIp == null
        ? null
        : await hashOtpRateActorKey(`verify_ip:${clientIp}`);
      const phoneActorKey = await hashOtpRateActorKey(
        `verify_phone:${normalizedPhone}`,
      );
      if (ipActorKey != null) {
        const recentIpEvents = await countRecentOtpRateEvents(adminClient, {
          action: "verify_ip",
          actorKey: ipActorKey,
          windowStartIso: windowStart,
        });
        if (recentIpEvents >= maxVerifyAttemptsPerIpPerWindow) {
          await recordVerifyRateEvents(adminClient, {
            ipActorKey,
            phoneActorKey,
            outcome: "blocked_ip_limit",
            phone: normalizedPhone,
            metadata: { limit: maxVerifyAttemptsPerIpPerWindow },
          });
          return errorResponse(
            "Too many verification attempts from this network. Request a new code later.",
            429,
            { retryAfterSeconds: 600 },
            request,
          );
        }
      }
      const recentPhoneEvents = await countRecentOtpRateEvents(adminClient, {
        action: "verify_phone",
        actorKey: phoneActorKey,
        windowStartIso: windowStart,
      });
      if (recentPhoneEvents >= maxVerifyAttemptsPerPhonePerWindow) {
        await recordVerifyRateEvents(adminClient, {
          ipActorKey,
          phoneActorKey,
          outcome: "blocked_phone_limit",
          phone: normalizedPhone,
          metadata: { limit: maxVerifyAttemptsPerPhonePerWindow },
        });
        return errorResponse(
          "Too many verification attempts for this phone number. Request a new code later.",
          429,
          { retryAfterSeconds: 600 },
          request,
        );
      }
      const usingReviewOtp = isReviewOtpMatch(normalizedPhone, code);

      let otpRecord:
        | {
          id: string;
          attempts?: number | null;
          expires_at: string;
          code: string;
        }
        | null = null;

      if (!usingReviewOtp) {
        const otpResult = await adminClient
          .from("otp_codes")
          .select("*")
          .eq("phone", normalizedPhone)
          .order("created_at", { ascending: false })
          .limit(1);

        if (otpResult.error) {
          throw otpResult.error;
        }

        otpRecord = otpResult.data?.[0] ?? null;
        if (!otpRecord) {
          await recordVerifyRateEvents(adminClient, {
            ipActorKey,
            phoneActorKey,
            outcome: "missing_otp",
            phone: normalizedPhone,
          });
          return errorResponse(
            "No OTP found for this phone number",
            404,
            undefined,
            request,
          );
        }

        if ((otpRecord.attempts ?? 0) >= 3) {
          await recordVerifyRateEvents(adminClient, {
            ipActorKey,
            phoneActorKey,
            outcome: "blocked_phone_attempts",
            phone: normalizedPhone,
          });
          return errorResponse(
            "Too many attempts. Request a new code.",
            429,
            undefined,
            request,
          );
        }

        if (new Date(otpRecord.expires_at).getTime() < Date.now()) {
          await recordVerifyRateEvents(adminClient, {
            ipActorKey,
            phoneActorKey,
            outcome: "expired",
            phone: normalizedPhone,
          });
          return errorResponse(
            "OTP code has expired",
            400,
            undefined,
            request,
          );
        }

        const incomingHash = await hashOtpCode(normalizedPhone, code);
        if (incomingHash != otpRecord.code) {
          const nextAttempts = (otpRecord.attempts ?? 0) + 1;
          const updateAttemptsResult = await adminClient
            .from("otp_codes")
            .update({ attempts: nextAttempts })
            .eq("id", otpRecord.id);

          if (updateAttemptsResult.error) {
            throw updateAttemptsResult.error;
          }

          await recordVerifyRateEvents(adminClient, {
            ipActorKey,
            phoneActorKey,
            outcome: "invalid_code",
            phone: normalizedPhone,
            metadata: { attemptsRemaining: Math.max(0, 3 - nextAttempts) },
          });

          return errorResponse(
            "Invalid OTP code",
            400,
            {
              attemptsRemaining: Math.max(0, 3 - nextAttempts),
            },
            request,
          );
        }
      }

      const existingAppUserId = await findExistingAppUser(
        adminClient,
        normalizedPhone,
      );

      const authEmail = await derivePhoneEmail(normalizedPhone);

      // Existing users can often sign in directly once the custom OTP has been
      // validated. This avoids brittle admin lookups when older auth rows were
      // stored with a slightly different phone representation.
      const derivedPassword = await derivePhonePassword(normalizedPhone);
      let signInResult = await signInWithDerivedPassword(
        authEmail,
        derivedPassword,
      );

      let authUserId = signInResult.data.user?.id ?? signInResult.data.session
        ?.user.id;

      if (signInResult.error || !signInResult.data.session) {
        if (!isRecoverableSignInError(signInResult.error)) {
          throw signInResult.error ?? new Error("Could not create session");
        }

        // Supabase Auth does not directly mint a session for an externally-
        // verified WhatsApp OTP flow, so we provision a deterministic internal
        // email identity and sign in with its derived password.
        const authUser = await ensureAuthUser(
          adminClient,
          normalizedPhone,
          authEmail,
        );
        authUserId = authUser.userId;
        signInResult = await signInWithDerivedPassword(
          authEmail,
          authUser.password,
        );

        if (signInResult.error || !signInResult.data.session) {
          throw signInResult.error ?? new Error("Could not create session");
        }
      }

      if (otpRecord != null) {
        const deleteOtpResult = await adminClient
          .from("otp_codes")
          .delete()
          .eq("id", otpRecord.id);

        if (deleteOtpResult.error) {
          throw deleteOtpResult.error;
        }
      }

      await recordVerifyRateEvents(adminClient, {
        ipActorKey,
        phoneActorKey,
        outcome: usingReviewOtp ? "review_success" : "success",
        phone: normalizedPhone,
      });

      const session = signInResult.data.session;
      return jsonResponse(
        {
          success: true,
          session,
          access_token: session.access_token,
          refresh_token: session.refresh_token,
          isNewUser: existingAppUserId == null,
          userId: authUserId,
        },
        200,
        {},
        request,
      );
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
      await reportVerifyOtpFailure(
        deps,
        adminClient,
        normalizedPhoneForTelemetry,
        error,
      );
      return errorResponse(verifyOtpFailureMessage, 500, undefined, request);
    }
  };
}

if (import.meta.main) {
  Deno.serve(createVerifyOtpHandler());
}
