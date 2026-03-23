import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { normalizeBiopayLivenessMetadata } from "../_shared/biopay_liveness.ts";
import {
  recordEdgeFunctionFailure,
  recordOperationalHealthEvent,
} from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

type EnrollRequest = {
  display_name?: string;
  consent_version?: string;
  embedding?: unknown;
  liveness?: unknown;
  model_version?: string;
  quality_score?: number;
};

function normalizeEmbedding(input: unknown): number[] {
  if (!Array.isArray(input) || input.length !== 128) {
    throw new Error("BioPay embedding must contain exactly 128 values.");
  }

  return input.map((value) => {
    const numberValue = typeof value === "number" ? value : Number(value);
    if (!Number.isFinite(numberValue)) {
      throw new Error("BioPay embedding contains a non-numeric value.");
    }
    return numberValue;
  });
}

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

    const body = await request.json() as EnrollRequest;
    const embedding = normalizeEmbedding(body.embedding);
    const liveness = normalizeBiopayLivenessMetadata(body.liveness);
    const { data, error } = await userClient.rpc("biopay_upsert_enrollment", {
      p_display_name: body.display_name ?? null,
      p_consent_version: body.consent_version ?? "biopay-v1",
      p_embedding: embedding,
      p_model_version: body.model_version ?? "mobilefacenet_int8_v1",
      p_quality_score: body.quality_score ?? null,
    });

    if (error) {
      throw error;
    }

    const row = Array.isArray(data) ? data[0] : data;
    if (!row) {
      throw new Error("BioPay enrollment did not return a profile.");
    }

    await recordOperationalHealthEvent(adminClient, {
      service: "biopay",
      component: "enrollment",
      status: "ok",
      severity: "info",
      message: "BioPay enrollment completed.",
      functionName: "biopay-enroll",
      userId: authData.user.id,
      subjectType: "biopay_profile",
      subjectId: row.id?.toString() ?? null,
      metadata: {
        route_type: row.route_type ?? null,
        country_code: row.country_code ?? null,
        liveness,
      },
    });

    return jsonResponse({
      success: true,
      data: row,
    });
  } catch (error) {
    await recordEdgeFunctionFailure(adminClient, {
      functionName: "biopay-enroll",
      error,
      issueCode: "biopay_enroll_failed",
    });
    return errorResponse(
      error instanceof Error ? error.message : "BioPay enrollment failed.",
      400,
    );
  }
});
