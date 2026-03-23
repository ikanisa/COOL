import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import {
  recordEdgeFunctionFailure,
  recordOperationalHealthEvent,
} from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

type RevokeRequest = {
  reason?: string;
};

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

    await recordOperationalHealthEvent(adminClient, {
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
      },
    });

    return jsonResponse({
      success: true,
      data: row,
    });
  } catch (error) {
    await recordEdgeFunctionFailure(adminClient, {
      functionName: "biopay-revoke",
      error,
      issueCode: "biopay_revoke_failed",
    });
    return errorResponse(
      error instanceof Error ? error.message : "BioPay revocation failed.",
      400,
    );
  }
});
