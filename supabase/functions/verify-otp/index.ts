import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  countRecentOtpRateEvents,
  extractClientIp,
  hashOtpRateActorKey,
  recordOtpRateEvent,
} from "../_shared/otp_abuse.ts";
import {
  errorResponse,
  handleCors,
  isMissingRelationError,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { normalizePhone, PhoneValidationError } from "../_shared/phone.ts";
import {
  derivePhoneEmail,
  derivePhonePassword,
  hashOtpCode,
} from "../_shared/security.ts";
import { createAdminClient, createAnonClient } from "../_shared/supabase.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

type VerifyOtpRequest = {
  phone?: string;
  code?: string;
};

export type VerifyOtpHandlerDependencies = {
  createAdminClient: () => AdminClient;
  recordEdgeFunctionFailure: typeof recordEdgeFunctionFailure;
};

const verifyRateLimitWindowMs = 10 * 60 * 1000;
const maxVerifyAttemptsPerIpPerWindow = 20;
const maxVerifyAttemptsPerPhonePerWindow = 9;
const verifyOtpFailureMessage = "Failed to verify OTP";

const defaultVerifyOtpHandlerDependencies: VerifyOtpHandlerDependencies = {
  createAdminClient,
  recordEdgeFunctionFailure,
};

function comparablePhone(value: string | null | undefined): string | null {
  if (!value?.trim()) {
    return null;
  }

  try {
    return normalizePhone(value);
  } catch (_) {
    const digitsOnly = value.replace(/\D/g, "");
    if (digitsOnly.length < 8 || digitsOnly.length > 15) {
      return null;
    }

    return `+${digitsOnly}`;
  }
}

function phonesMatch(
  left: string | null | undefined,
  right: string | null | undefined,
): boolean {
  const normalizedLeft = comparablePhone(left);
  const normalizedRight = comparablePhone(right);
  return normalizedLeft != null && normalizedLeft == normalizedRight;
}

function isRecoverableSignInError(error: unknown): boolean {
  if (!error) {
    return false;
  }

  const message = error instanceof Error
    ? error.message.toLowerCase()
    : JSON.stringify(error).toLowerCase();

  return message.includes("invalid login credentials") ||
    message.includes("user not found") ||
    message.includes("email not confirmed") ||
    message.includes("invalid grant");
}

function isReviewOtpMatch(normalizedPhone: string, code: string): boolean {
  const configuredPhone = Deno.env.get("OTP_TEST_PHONE")?.trim();
  const configuredCode = Deno.env.get("OTP_TEST_CODE")?.trim();
  if (!configuredPhone || !configuredCode) {
    return false;
  }

  if (!/^\d{6}$/.test(configuredCode)) {
    console.error("OTP_TEST_CODE must be exactly 6 digits.");
    return false;
  }

  try {
    return normalizePhone(configuredPhone) == normalizedPhone &&
      configuredCode == code;
  } catch (error) {
    console.error("OTP_TEST_PHONE is invalid.", error);
    return false;
  }
}

async function findAuthUserByPhone(
  adminClient: AdminClient,
  phone: string,
  email: string,
) {
  const result = await adminClient.rpc("find_auth_user_by_phone_or_email", {
    p_phone: phone,
    p_email: email,
  });

  if (result.error) {
    throw result.error;
  }

  const rows = Array.isArray(result.data) ? result.data : [];
  const userId = rows[0]?.user_id?.toString().trim();
  if (!userId) {
    return null;
  }

  const userResult = await adminClient.auth.admin.getUserById(userId);
  if (userResult.error || !userResult.data.user) {
    throw userResult.error ?? new Error("Could not load auth user");
  }

  return userResult.data.user;
}

async function ensureAuthUser(
  adminClient: AdminClient,
  phone: string,
  email: string,
) {
  const password = await derivePhonePassword(phone);
  const existingUser = await findAuthUserByPhone(adminClient, phone, email);

  if (existingUser) {
    const updateResult = await adminClient.auth.admin.updateUserById(
      existingUser.id,
      {
        email,
        email_confirm: true,
        password,
        user_metadata: {
          ...(existingUser.user_metadata ?? {}),
          phone,
          auth_strategy: "custom_whatsapp_otp",
          country: "RW",
          language_code: "en",
          market: "RW",
          ui_language: "en",
        },
      },
    );

    if (updateResult.error) {
      throw updateResult.error;
    }

    return {
      userId: existingUser.id,
      password,
      created: false,
    };
  }

  const createResult = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      phone,
      auth_strategy: "custom_whatsapp_otp",
      country: "RW",
      language_code: "en",
      market: "RW",
      ui_language: "en",
    },
  });

  if (createResult.error || !createResult.data.user) {
    throw createResult.error ?? new Error("Could not create auth user");
  }

  return {
    userId: createResult.data.user.id,
    password,
    created: true,
  };
}

async function signInWithDerivedPassword(email: string, password: string) {
  return await createAnonClient().auth.signInWithPassword({
    email,
    password,
  });
}

async function findExistingAppUser(
  adminClient: AdminClient,
  phone: string,
) {
  try {
    const usersResult = await adminClient
      .from("users")
      .select("id")
      .eq("phone", phone)
      .limit(1)
      .maybeSingle();

    if (!usersResult.error && usersResult.data) {
      return usersResult.data.id?.toString() ?? null;
    }

    if (usersResult.error && !isMissingRelationError(usersResult.error)) {
      throw usersResult.error;
    }
  } catch (error) {
    if (!isMissingRelationError(error)) {
      throw error;
    }
  }

  return null;
}

export function createVerifyOtpHandler(
  deps: VerifyOtpHandlerDependencies = defaultVerifyOtpHandlerDependencies,
) {
  return async (request: Request): Promise<Response> => {
    const corsResponse = handleCors(request);
    if (corsResponse) {
      return corsResponse;
    }

    if (request.method != "POST") {
      return methodNotAllowed("POST");
    }

    let normalizedPhoneForTelemetry: string | null = null;
    let adminClient: AdminClient | null = null;

    try {
      const body = await request.json() as VerifyOtpRequest;
      const normalizedPhone = normalizePhone(body.phone ?? "");
      normalizedPhoneForTelemetry = normalizedPhone;
      const code = (body.code ?? "").trim();

      if (!/^\d{6}$/.test(code)) {
        return errorResponse("Code must be 6 digits", 400);
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
          return errorResponse("No OTP found for this phone number", 404);
        }

        if ((otpRecord.attempts ?? 0) >= 3) {
          await recordVerifyRateEvents(adminClient, {
            ipActorKey,
            phoneActorKey,
            outcome: "blocked_phone_attempts",
            phone: normalizedPhone,
          });
          return errorResponse("Too many attempts. Request a new code.", 429);
        }

        if (new Date(otpRecord.expires_at).getTime() < Date.now()) {
          await recordVerifyRateEvents(adminClient, {
            ipActorKey,
            phoneActorKey,
            outcome: "expired",
            phone: normalizedPhone,
          });
          return errorResponse("OTP code has expired", 400);
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

          return errorResponse("Invalid OTP code", 400, {
            attemptsRemaining: Math.max(0, 3 - nextAttempts),
          });
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
      return jsonResponse({
        success: true,
        session,
        access_token: session.access_token,
        refresh_token: session.refresh_token,
        isNewUser: existingAppUserId == null,
        userId: authUserId,
      });
    } catch (error) {
      if (error instanceof SyntaxError) {
        return errorResponse("Invalid JSON body", 400);
      }
      if (error instanceof PhoneValidationError) {
        return errorResponse(error.message, 400);
      }
      console.error("verify-otp failed", error);
      await reportVerifyOtpFailure(
        deps,
        adminClient,
        normalizedPhoneForTelemetry,
        error,
      );
      return errorResponse(verifyOtpFailureMessage, 500);
    }
  };
}

if (import.meta.main) {
  Deno.serve(createVerifyOtpHandler());
}

async function reportVerifyOtpFailure(
  deps: VerifyOtpHandlerDependencies,
  adminClient: AdminClient | null,
  normalizedPhoneForTelemetry: string | null,
  error: unknown,
) {
  try {
    await deps.recordEdgeFunctionFailure(
      adminClient ?? deps.createAdminClient(),
      {
        functionName: "verify-otp",
        error,
        subjectType: "otp_phone",
        subjectId: normalizedPhoneForTelemetry,
        metadata: {
          phone_suffix: normalizedPhoneForTelemetry == null
            ? null
            : normalizedPhoneForTelemetry.substring(
              normalizedPhoneForTelemetry.length - 4,
            ),
        },
      },
    );
  } catch (reportError) {
    console.error("verify-otp telemetry failed", reportError);
  }
}

async function recordVerifyRateEvents(
  adminClient: AdminClient,
  options: {
    ipActorKey: string | null;
    phoneActorKey: string;
    outcome: string;
    phone: string;
    metadata?: Record<string, unknown>;
  },
) {
  const writes = [
    recordOtpRateEvent(adminClient, {
      action: "verify_phone",
      actorKey: options.phoneActorKey,
      outcome: options.outcome,
      phone: options.phone,
      metadata: options.metadata,
    }),
  ];

  if (options.ipActorKey != null) {
    writes.push(
      recordOtpRateEvent(adminClient, {
        action: "verify_ip",
        actorKey: options.ipActorKey,
        outcome: options.outcome,
        phone: options.phone,
        metadata: options.metadata,
      }),
    );
  }

  await Promise.all(writes);
}
