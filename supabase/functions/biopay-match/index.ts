import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

type MatchRequest = {
  embedding?: unknown;
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

async function getMatchThreshold(
  adminClient: ReturnType<typeof createAdminClient>,
): Promise<number> {
  const { data, error } = await adminClient
    .from("app_config")
    .select("value")
    .eq("key", "biopay_match_threshold")
    .limit(1)
    .maybeSingle();

  if (error) {
    throw error;
  }

  const parsed = Number(data?.value ?? "0.72");
  return Number.isFinite(parsed) ? parsed : 0.72;
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

    const body = await request.json() as MatchRequest;
    const embedding = normalizeEmbedding(body.embedding);
    const threshold = await getMatchThreshold(adminClient);

    const { data, error } = await adminClient.rpc("match_biopay_profile", {
      p_embedding: embedding,
    });
    if (error) {
      throw error;
    }

    const row = Array.isArray(data) ? data[0] : data;
    const score = Number(row?.score ?? 0);
    const hasMatch = !!row && Number.isFinite(score) && score >= threshold;

    await adminClient.from("biopay_match_events").insert({
      requester_user_id: authData.user.id,
      matched_profile_id: hasMatch ? row.profile_id : null,
      matched: hasMatch,
      score: Number.isFinite(score) ? score : 0,
      threshold_used: threshold,
      metadata: {
        route_type: row?.route_type ?? null,
        public_id: row?.public_id ?? null,
      },
    });

    if (!hasMatch) {
      return jsonResponse({
        success: true,
        data: {
          match: false,
          score: Number.isFinite(score) ? score : 0,
        },
      });
    }

    return jsonResponse({
      success: true,
      data: {
        match: true,
        ...row,
      },
    });
  } catch (error) {
    await recordEdgeFunctionFailure(adminClient, {
      functionName: "biopay-match",
      error,
      issueCode: "biopay_match_failed",
    });
    return errorResponse(
      error instanceof Error ? error.message : "BioPay match failed.",
      400,
    );
  }
});
