import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

type DeleteAccountRequest = {
  confirm?: boolean;
};

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method != "POST") {
    return methodNotAllowed("POST");
  }

  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return errorResponse("Authentication required", 401);
  }

  let userIdForTelemetry: string | null = null;

  try {
    const body =
      (await request.json().catch(() => ({}))) as DeleteAccountRequest;
    if (body.confirm !== true) {
      return errorResponse("Account deletion was not confirmed", 400);
    }

    const userClient = createUserClient(authorization);
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return errorResponse("Authentication required", 401);
    }
    userIdForTelemetry = user.id;

    const adminClient = createAdminClient();
    const phone = user.phone ?? user.user_metadata?.phone?.toString();
    if (phone && phone.trim().isNotEmpty) {
      const cleanupResult = await adminClient
        .from("otp_codes")
        .delete()
        .eq("phone", phone.trim());
      if (cleanupResult.error) {
        throw cleanupResult.error;
      }
    }

    const deleteResult = await adminClient.auth.admin.deleteUser(user.id);
    if (deleteResult.error) {
      throw deleteResult.error;
    }

    return jsonResponse({ success: true });
  } catch (error) {
    if (error instanceof SyntaxError) {
      return errorResponse("Invalid JSON body", 400);
    }
    console.error("delete-account failed", error);
    await recordEdgeFunctionFailure(createAdminClient(), {
      functionName: "delete-account",
      error,
      userId: userIdForTelemetry,
      subjectType: "user",
      subjectId: userIdForTelemetry,
    });
    return errorResponse(
      error instanceof Error ? error.message : "Failed to delete account",
      500,
    );
  }
});
