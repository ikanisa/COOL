import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { HttpError, requireAdminCaller } from "../_shared/auth.ts";
import { normalizePhone, PhoneValidationError } from "../_shared/phone.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient } from "../_shared/supabase.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

type AdminCreateUserRequest = {
  fullName?: string;
  phone?: string;
  country?: string;
  grantPlatformAdmin?: boolean;
  notes?: string;
};

type AuthUserLike = {
  id: string;
  phone?: string | null;
  user_metadata?: Record<string, unknown> | null;
};

export type AdminCreateUserHandlerDependencies = {
  createAdminClient: () => AdminClient;
  requireAdminCaller: typeof requireAdminCaller;
  recordEdgeFunctionFailure: typeof recordEdgeFunctionFailure;
};

const defaultDeps: AdminCreateUserHandlerDependencies = {
  createAdminClient,
  requireAdminCaller,
  recordEdgeFunctionFailure,
};

const DEFAULT_COUNTRY = "RW";
const DEFAULT_LANGUAGE = "en";

function normalizeCountry(value: string | undefined): string {
  const trimmed = value?.trim().toUpperCase();
  return trimmed && trimmed.length > 0 ? trimmed : DEFAULT_COUNTRY;
}

function normalizeStoredPhone(value: unknown): string | null {
  if (typeof value !== "string" || value.trim().length === 0) {
    return null;
  }

  try {
    return normalizePhone(value);
  } catch {
    const digitsOnly = value.replace(/[^\d]/g, "");
    if (!digitsOnly) {
      return null;
    }
    try {
      return normalizePhone(`+${digitsOnly}`);
    } catch {
      return null;
    }
  }
}

async function findAuthUserByPhone(
  adminClient: AdminClient,
  normalizedPhone: string,
): Promise<AuthUserLike | null> {
  const perPage = 200;
  let page = 1;

  while (true) {
    const result = await adminClient.auth.admin.listUsers({ page, perPage });
    if (result.error) {
      throw result.error;
    }

    const users = (result.data?.users ?? []) as AuthUserLike[];
    const matched = users.find((user) => {
      const metadataPhone = user.user_metadata?.["phone"];
      return normalizeStoredPhone(user.phone) === normalizedPhone ||
        normalizeStoredPhone(metadataPhone) === normalizedPhone;
    });
    if (matched) {
      return matched;
    }

    if (users.length < perPage) {
      return null;
    }

    page += 1;
  }
}

async function ensurePlatformAdminAssignment(
  adminClient: AdminClient,
  options: {
    callerUserId: string;
    targetUserId: string;
    notes: string | null;
  },
) {
  const existingResult = await adminClient
    .from("admin_role_assignments")
    .select("id, is_active")
    .eq("user_id", options.targetUserId)
    .eq("role", "admin")
    .is("partner_scope_id", null)
    .order("granted_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existingResult.error) {
    throw existingResult.error;
  }

  if (existingResult.data?.id) {
    const updateResult = await adminClient
      .from("admin_role_assignments")
      .update({
        is_active: true,
        revoked_at: null,
        granted_by: options.callerUserId,
        granted_at: new Date().toISOString(),
        notes: options.notes,
      })
      .eq("id", existingResult.data.id);
    if (updateResult.error) {
      throw updateResult.error;
    }
    return;
  }

  const insertResult = await adminClient
    .from("admin_role_assignments")
    .insert({
      user_id: options.targetUserId,
      role: "admin",
      partner_scope_id: null,
      granted_by: options.callerUserId,
      is_active: true,
      notes: options.notes,
    });
  if (insertResult.error) {
    throw insertResult.error;
  }
}

export function createAdminCreateUserHandler(
  deps: AdminCreateUserHandlerDependencies = defaultDeps,
) {
  return async (request: Request): Promise<Response> => {
    const corsResponse = handleCors(request);
    if (corsResponse) {
      return corsResponse;
    }

    if (request.method !== "POST") {
      return methodNotAllowed("POST", request);
    }

    let adminClient: AdminClient | null = null;
    let actorUserId: string | null = null;

    try {
      const caller = await deps.requireAdminCaller(request);
      actorUserId = caller.userId;

      const body = await request.json() as AdminCreateUserRequest;
      const fullName = body.fullName?.trim() ?? "";
      const normalizedPhone = normalizePhone(body.phone ?? "");
      const country = normalizeCountry(body.country);
      const notes = body.notes?.trim() || null;
      const grantPlatformAdmin = body.grantPlatformAdmin === true;

      if (!fullName) {
        return errorResponse("Full name is required.", 400, undefined, request);
      }

      adminClient = deps.createAdminClient();

      const existingUserResult = await adminClient
        .from("users")
        .select("id, full_name, phone")
        .eq("phone", normalizedPhone)
        .maybeSingle();
      if (existingUserResult.error) {
        throw existingUserResult.error;
      }
      if (existingUserResult.data?.id) {
        return errorResponse(
          "A user with this phone number already exists.",
          409,
          { userId: existingUserResult.data.id },
          request,
        );
      }

      const existingAuthUser = await findAuthUserByPhone(
        adminClient,
        normalizedPhone,
      );

      let authUserId = existingAuthUser?.id ?? null;
      if (!authUserId) {
        const createResult = await adminClient.auth.admin.createUser({
          phone: normalizedPhone,
          phone_confirm: true,
          user_metadata: {
            phone: normalizedPhone,
            full_name: fullName,
            country,
            language_code: DEFAULT_LANGUAGE,
            auth_strategy: "custom_whatsapp_otp",
          },
        });
        if (createResult.error || !createResult.data.user) {
          throw createResult.error ?? new Error("Failed to create auth user.");
        }
        authUserId = createResult.data.user.id;
      }

      const upsertUserResult = await adminClient
        .from("users")
        .upsert({
          id: authUserId,
          phone: normalizedPhone,
          full_name: fullName,
          country,
          language_code: DEFAULT_LANGUAGE,
          is_admin: grantPlatformAdmin,
          is_mock: false,
        }, { onConflict: "id" });
      if (upsertUserResult.error) {
        throw upsertUserResult.error;
      }

      if (grantPlatformAdmin) {
        await ensurePlatformAdminAssignment(adminClient, {
          callerUserId: caller.userId,
          targetUserId: authUserId,
          notes,
        });
      }

      return jsonResponse(
        {
          success: true,
          userId: authUserId,
          phone: normalizedPhone,
          grantPlatformAdmin,
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

      console.error("admin-create-user failed", error);
      try {
        await deps.recordEdgeFunctionFailure(
          adminClient ?? deps.createAdminClient(),
          {
            functionName: "admin-create-user",
            error,
            userId: actorUserId,
            subjectType: "user",
            subjectId: actorUserId,
          },
        );
      } catch (reportError) {
        console.error("admin-create-user telemetry failed", reportError);
      }

      return errorResponse(
        error instanceof Error ? error.message : "Failed to create user.",
        500,
        undefined,
        request,
      );
    }
  };
}

if (import.meta.main) {
  Deno.serve(createAdminCreateUserHandler());
}
