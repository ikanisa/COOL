import "jsr:@supabase/functions-js/edge-runtime.d.ts";

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

type VerifyOtpRequest = {
  phone?: string;
  code?: string;
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
  adminClient: ReturnType<typeof createAdminClient>,
  phone: string,
  email: string,
) {
  let page = 1;
  const perPage = 200;

  while (true) {
    const result = await adminClient.auth.admin.listUsers({
      page,
      perPage,
    });

    if (result.error) {
      throw result.error;
    }

    const matchedUser = result.data.users.find((user) => {
      const userWithPhoneChange = user as typeof user & {
        phone_change?: string | null;
      };

      return user.email == email ||
        phonesMatch(user.phone, phone) ||
        phonesMatch(userWithPhoneChange.phone_change, phone) ||
        phonesMatch(user.user_metadata?.phone?.toString(), phone);
    });
    if (matchedUser) {
      return matchedUser;
    }

    if (result.data.users.length < perPage) {
      return null;
    }

    page += 1;
  }
}

async function ensureAuthUser(
  adminClient: ReturnType<typeof createAdminClient>,
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
  adminClient: ReturnType<typeof createAdminClient>,
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

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method != "POST") {
    return methodNotAllowed("POST");
  }

  let normalizedPhoneForTelemetry: string | null = null;

  try {
    const body = await request.json() as VerifyOtpRequest;
    const normalizedPhone = normalizePhone(body.phone ?? "");
    normalizedPhoneForTelemetry = normalizedPhone;
    const code = (body.code ?? "").trim();

    if (!/^\d{6}$/.test(code)) {
      return errorResponse("Code must be 6 digits", 400);
    }

    const adminClient = createAdminClient();
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
        return errorResponse("No OTP found for this phone number", 404);
      }

      if ((otpRecord.attempts ?? 0) >= 3) {
        return errorResponse("Too many attempts. Request a new code.", 429);
      }

      if (new Date(otpRecord.expires_at).getTime() < Date.now()) {
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
    await recordEdgeFunctionFailure(createAdminClient(), {
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
    });
    return errorResponse(
      error instanceof Error ? error.message : "Failed to verify OTP",
      500,
    );
  }
});
