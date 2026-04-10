import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { HttpError } from "../_shared/auth.ts";
import { requireAppCheckToken } from "../_shared/app_check.ts";
import {
  recordEdgeFunctionFailure,
  recordOperationalHealthEvent,
} from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

type CreateIntentRequest = {
  profile_public_id: string;
  match_score: number;
};

type AdminClientLike = ReturnType<typeof createAdminClient>;
type UserClientLike = {
  auth: {
    getUser(): Promise<{
      data: { user: { id: string } | null };
      error: unknown;
    }>;
  };
};

type BiopayProfileRow = {
  id: string;
  user_id: string;
  recipient_value: string;
  route_type: string;
  display_name: string;
  public_id: string;
};

type BiopayPaymentIntentRow = {
  id: string;
  nonce: string;
  ussd_code: string;
  expires_at: string;
};

type CreatePaymentIntentOptions = {
  userId: string;
  profileId: string;
  matchScore: number;
  recipientValue: string;
  routeType: string;
  ussdCode: string;
  nonce: string;
  expiresAt: string;
};

export type BiopayCreatePaymentIntentHandlerDependencies = {
  createAdminClient: () => AdminClientLike;
  createUserClient: (authorization: string) => UserClientLike;
  requireAppCheckToken: (request: Request) => Promise<string>;
  fetchActiveProfile: (
    adminClient: AdminClientLike,
    profilePublicId: string,
  ) => Promise<BiopayProfileRow | null>;
  cancelPendingIntents: (
    adminClient: AdminClientLike,
    userId: string,
  ) => Promise<void>;
  createPaymentIntent: (
    adminClient: AdminClientLike,
    options: CreatePaymentIntentOptions,
  ) => Promise<BiopayPaymentIntentRow>;
  buildUssdCode: (routeType: string, recipientValue: string) => string;
  generateNonce: () => string;
  now: () => Date;
  recordOperationalHealthEvent: (
    adminClient: AdminClientLike,
    event: Parameters<typeof recordOperationalHealthEvent>[1],
  ) => Promise<void>;
  recordEdgeFunctionFailure: (
    adminClient: AdminClientLike,
    options: Parameters<typeof recordEdgeFunctionFailure>[1],
  ) => Promise<void>;
};

/**
 * Build a MoMo USSD code server-side from profile data.
 * Mirrors the logic in biopay_dialer_service.dart but runs on the server
 * so the client never sees raw recipient values.
 */
function buildUssdCode(
  routeType: string,
  recipientValue: string,
): string {
  // Simple normalization — strip whitespace
  const cleaned = recipientValue.trim();

  switch (routeType) {
    case "phone_number":
      return `*182*1*1*${cleaned}#`;
    case "code":
      return `*182*8*1*${cleaned}#`;
    default:
      throw new Error(`Unknown route type: ${routeType}`);
  }
}

function generateNonce(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const INTENT_TTL_SECONDS = 300; // 5 minutes

const defaultDependencies: BiopayCreatePaymentIntentHandlerDependencies = {
  createAdminClient,
  createUserClient: (authorization) =>
    createUserClient(authorization) as unknown as UserClientLike,
  requireAppCheckToken,
  fetchActiveProfile: async (adminClient, profilePublicId) => {
    const { data, error } = await adminClient
      .from("biopay_profiles")
      .select(
        "id, user_id, recipient_value, route_type, display_name, public_id",
      )
      .eq("public_id", profilePublicId)
      .eq("status", "active")
      .maybeSingle();

    if (error) {
      throw error;
    }

    return (data as BiopayProfileRow | null) ?? null;
  },
  cancelPendingIntents: async (adminClient, userId) => {
    const { error } = await adminClient
      .from("biopay_payment_intents")
      .update({ status: "cancelled" })
      .eq("user_id", userId)
      .eq("status", "pending");

    if (error) {
      throw error;
    }
  },
  createPaymentIntent: async (adminClient, options) => {
    const { data, error } = await adminClient
      .from("biopay_payment_intents")
      .insert({
        user_id: options.userId,
        profile_id: options.profileId,
        match_score: options.matchScore,
        recipient_value: options.recipientValue,
        route_type: options.routeType,
        ussd_code: options.ussdCode,
        nonce: options.nonce,
        status: "pending",
        expires_at: options.expiresAt,
      })
      .select("id, nonce, ussd_code, expires_at")
      .single();

    if (error || !data) {
      throw error ?? new Error("Failed to create payment intent.");
    }

    return data as BiopayPaymentIntentRow;
  },
  buildUssdCode,
  generateNonce,
  now: () => new Date(),
  recordOperationalHealthEvent,
  recordEdgeFunctionFailure,
};

export function createBiopayCreatePaymentIntentHandler(
  dependencies: Partial<BiopayCreatePaymentIntentHandlerDependencies> = {},
) {
  const deps: BiopayCreatePaymentIntentHandlerDependencies = {
    ...defaultDependencies,
    ...dependencies,
  };

  return async (request: Request) => {
    const corsResponse = handleCors(request);
    if (corsResponse) {
      return corsResponse;
    }

    if (request.method !== "POST") {
      return methodNotAllowed("POST");
    }

    const adminClient = deps.createAdminClient();
    let requesterUserId: string | null = null;

    try {
      const authorization = request.headers.get("authorization") ??
        request.headers.get("Authorization");
      if (!authorization) {
        return errorResponse("Missing authorization header.", 401);
      }

      const userClient = deps.createUserClient(authorization);
      const { data: authData, error: authError } = await userClient.auth
        .getUser();
      if (authError || !authData.user) {
        return errorResponse("Unauthorized.", 401);
      }

      await deps.requireAppCheckToken(request);

      const userId = authData.user.id;
      requesterUserId = userId;

      const body = (await request.json()) as CreateIntentRequest;
      const { profile_public_id, match_score } = body;

      if (
        !profile_public_id ||
        typeof profile_public_id !== "string" ||
        profile_public_id.trim().length === 0
      ) {
        return errorResponse("profile_public_id is required.", 400);
      }

      if (typeof match_score !== "number" || match_score <= 0) {
        return errorResponse("match_score must be a positive number.", 400);
      }

      const profile = await deps.fetchActiveProfile(
        adminClient,
        profile_public_id,
      );
      if (!profile) {
        return errorResponse("BioPay profile not found or inactive.", 404);
      }

      await deps.cancelPendingIntents(adminClient, userId);

      const ussdCode = deps.buildUssdCode(
        profile.route_type,
        profile.recipient_value,
      );
      const nonce = deps.generateNonce();
      const expiresAt = new Date(
        deps.now().getTime() + INTENT_TTL_SECONDS * 1000,
      ).toISOString();

      const intent = await deps.createPaymentIntent(adminClient, {
        userId,
        profileId: profile.id,
        matchScore: match_score,
        recipientValue: profile.recipient_value,
        routeType: profile.route_type,
        ussdCode,
        nonce,
        expiresAt,
      });

      await deps.recordOperationalHealthEvent(adminClient, {
        service: "biopay",
        component: "payment_intent",
        status: "ok",
        severity: "info",
        message: "Payment intent created.",
        functionName: "biopay-create-payment-intent",
        userId,
        subjectType: "biopay_payment_intent",
        subjectId: intent.id,
        metadata: {
          profile_public_id,
          nonce,
          expires_at: expiresAt,
          app_check_enforced: true,
        },
      });

      return jsonResponse({
        success: true,
        data: {
          intent_id: intent.id,
          nonce: intent.nonce,
          ussd_code: intent.ussd_code,
          expires_at: intent.expires_at,
          display_name: profile.display_name,
        },
      });
    } catch (error) {
      if (error instanceof HttpError) {
        return errorResponse(error.message, error.status);
      }

      await deps.recordEdgeFunctionFailure(adminClient, {
        functionName: "biopay-create-payment-intent",
        error,
        issueCode: "biopay_create_intent_failed",
        userId: requesterUserId,
      });
      return errorResponse(
        error instanceof Error
          ? error.message
          : "Payment intent creation failed.",
        400,
      );
    }
  };
}

if (import.meta.main) {
  Deno.serve(createBiopayCreatePaymentIntentHandler());
}
