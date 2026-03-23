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

type RevokeRequest = {
  reason?: string;
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

export type BiopayRevokeHandlerDependencies = {
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

const defaultDependencies: BiopayRevokeHandlerDependencies = {
  createAdminClient,
  createUserClient: (authorization) =>
    createUserClient(authorization) as unknown as UserClientLike,
  requireAppCheckToken,
  recordOperationalHealthEvent,
  recordEdgeFunctionFailure,
};

export function createBiopayRevokeHandler(
  dependencies: Partial<BiopayRevokeHandlerDependencies> = {},
) {
  const deps: BiopayRevokeHandlerDependencies = {
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

      const body = await request.json() as RevokeRequest;
      const { data, error } = await userClient.rpc("biopay_revoke_profile", {
        p_reason: body.reason ?? null,
      });

      if (error) {
        throw error;
      }

      const row = Array.isArray(data) ? data[0] : data;
      if (!row) {
        throw new Error("BioPay revocation did not return a profile.");
      }

      await deps.recordOperationalHealthEvent(adminClient, {
        service: "biopay",
        component: "revocation",
        status: "ok",
        severity: "info",
        message: "BioPay enrollment revoked.",
        functionName: "biopay-revoke",
        userId: authData.user.id,
        subjectType: "biopay_profile",
        subjectId: row.profile_id?.toString() ?? null,
        metadata: {
          public_id: row.public_id ?? null,
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
        functionName: "biopay-revoke",
        error,
        issueCode: "biopay_revoke_failed",
        userId: requesterUserId,
      });
      return errorResponse(
        error instanceof Error ? error.message : "BioPay revocation failed.",
        400,
      );
    }
  };
}

if (import.meta.main) {
  Deno.serve(createBiopayRevokeHandler());
}
