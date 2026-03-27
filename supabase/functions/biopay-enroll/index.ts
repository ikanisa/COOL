import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { HttpError } from "../_shared/auth.ts";
import { requireAppCheckToken } from "../_shared/app_check.ts";
import { normalizeBiopayEmbedding } from "../_shared/biopay_embedding.ts";
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

type AdminClientLike = ReturnType<typeof createAdminClient>;
type UserClientLike = {
  auth: {
    getUser(): Promise<{
      data: { user: { id: string } | null };
      error: unknown;
    }>;
  };
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: unknown }>;
};

export type BiopayEnrollHandlerDependencies = {
  createAdminClient: () => AdminClientLike;
  createUserClient: (authorization: string) => UserClientLike;
  requireAppCheckToken: (request: Request) => Promise<string>;
  recordOperationalHealthEvent: (
    adminClient: AdminClientLike,
    event: Parameters<typeof recordOperationalHealthEvent>[1],
  ) => Promise<void>;
  recordEdgeFunctionFailure: (
    adminClient: AdminClientLike,
    options: Parameters<typeof recordEdgeFunctionFailure>[1],
  ) => Promise<void>;
};

const defaultDependencies: BiopayEnrollHandlerDependencies = {
  createAdminClient,
  createUserClient: (authorization) =>
    createUserClient(authorization) as unknown as UserClientLike,
  requireAppCheckToken,
  recordOperationalHealthEvent,
  recordEdgeFunctionFailure,
};

export function createBiopayEnrollHandler(
  dependencies: Partial<BiopayEnrollHandlerDependencies> = {},
) {
  const deps: BiopayEnrollHandlerDependencies = {
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
      requesterUserId = authData.user.id;

      await deps.requireAppCheckToken(request);

      const body = await request.json() as EnrollRequest;
      const embedding = normalizeBiopayEmbedding(body.embedding);
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

      await deps.recordOperationalHealthEvent(adminClient, {
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
          app_check_enforced: true,
        },
      });

      return jsonResponse({
        success: true,
        data: row,
      });
    } catch (error) {
      if (error instanceof HttpError) {
        return errorResponse(error.message, error.status);
      }

      await deps.recordEdgeFunctionFailure(adminClient, {
        functionName: "biopay-enroll",
        error,
        issueCode: "biopay_enroll_failed",
        userId: requesterUserId,
      });
      return errorResponse(
        error instanceof Error ? error.message : "BioPay enrollment failed.",
        400,
      );
    }
  };
}

if (import.meta.main) {
  Deno.serve(createBiopayEnrollHandler());
}
