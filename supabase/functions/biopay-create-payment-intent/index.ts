import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
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

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method !== "POST") {
    return methodNotAllowed("POST");
  }

  const adminClient = createAdminClient();

  try {
    // ── Auth ──────────────────────────────────────────────────
    const authorization = request.headers.get("authorization") ??
      request.headers.get("Authorization");
    if (!authorization) {
      return errorResponse("Missing authorization header.", 401);
    }

    const userClient = createUserClient(authorization);
    const { data: authData, error: authError } = await userClient.auth
      .getUser();
    if (authError || !authData.user) {
      return errorResponse("Unauthorized.", 401);
    }

    await requireAppCheckToken(request);

    const userId = authData.user.id;

    // ── Parse request ────────────────────────────────────────
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

    // ── Lookup profile ───────────────────────────────────────
    const { data: profile, error: profileError } = await adminClient
      .from("biopay_profiles")
      .select(
        "id, user_id, recipient_value, route_type, display_name, public_id",
      )
      .eq("public_id", profile_public_id)
      .eq("status", "active")
      .maybeSingle();

    if (profileError || !profile) {
      return errorResponse("BioPay profile not found or inactive.", 404);
    }

    // ── Invalidate any existing pending intents for this user ─
    await adminClient
      .from("biopay_payment_intents")
      .update({ status: "cancelled" })
      .eq("user_id", userId)
      .eq("status", "pending");

    // ── Build USSD code server-side ──────────────────────────
    const ussdCode = buildUssdCode(
      profile.route_type,
      profile.recipient_value,
    );

    // ── Create the intent ────────────────────────────────────
    const nonce = generateNonce();
    const expiresAt = new Date(
      Date.now() + INTENT_TTL_SECONDS * 1000,
    ).toISOString();

    const { data: intent, error: insertError } = await adminClient
      .from("biopay_payment_intents")
      .insert({
        user_id: userId,
        profile_id: profile.id,
        match_score,
        recipient_value: profile.recipient_value,
        route_type: profile.route_type,
        ussd_code: ussdCode,
        nonce,
        status: "pending",
        expires_at: expiresAt,
      })
      .select("id, nonce, ussd_code, expires_at")
      .single();

    if (insertError || !intent) {
      throw insertError ?? new Error("Failed to create payment intent.");
    }

    // ── Telemetry ────────────────────────────────────────────
    await recordOperationalHealthEvent(adminClient, {
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
    await recordEdgeFunctionFailure(adminClient, {
      functionName: "biopay-create-payment-intent",
      error,
      issueCode: "biopay_create_intent_failed",
    });
    return errorResponse(
      error instanceof Error
        ? error.message
        : "Payment intent creation failed.",
      400,
    );
  }
});
