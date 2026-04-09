import { recordOtpRateEvent } from "../_shared/otp_abuse.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { normalizePhone } from "../_shared/phone.ts";
import { derivePhonePassword } from "../_shared/security.ts";
import { createAdminClient, createAnonClient } from "../_shared/supabase.ts";
import { isMissingRelationError } from "../_shared/http.ts";

export type AdminClient = ReturnType<typeof createAdminClient>;

export type VerifyOtpFailureDependencies = {
  createAdminClient: () => AdminClient;
  recordEdgeFunctionFailure: typeof recordEdgeFunctionFailure;
};

export function isRecoverableSignInError(error: unknown): boolean {
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

export function isReviewOtpMatch(
  normalizedPhone: string,
  code: string,
): boolean {
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

export async function ensureAuthUser(
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

export async function signInWithDerivedPassword(
  email: string,
  password: string,
) {
  return await createAnonClient().auth.signInWithPassword({
    email,
    password,
  });
}

export async function findExistingAppUser(
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

export async function reportVerifyOtpFailure(
  deps: VerifyOtpFailureDependencies,
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

export async function recordVerifyRateEvents(
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
