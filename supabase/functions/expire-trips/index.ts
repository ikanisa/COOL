import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  isMissingRelationError,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient } from "../_shared/supabase.ts";

class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

function requireCronSecret(request: Request): void {
  const configuredSecret = Deno.env.get("CRON_JOB_SECRET")?.trim();
  if (!configuredSecret) {
    throw new HttpError(500, "CRON_JOB_SECRET is not configured.");
  }

  const authorization = request.headers.get("authorization");
  const bearerToken = authorization?.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length).trim()
    : null;
  const providedSecret = bearerToken ??
    request.headers.get("x-cron-secret")?.trim();

  if (!providedSecret || providedSecret !== configuredSecret) {
    throw new HttpError(401, "Unauthorized.");
  }
}

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method !== "POST") {
    return methodNotAllowed("POST");
  }

  try {
    requireCronSecret(request);

    const threshold = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const supabase = createAdminClient();
    // Query canonical column (travel_time); also catch any legacy rows
    // that may still use departure_at.
    const result = await supabase
      .from("mobility_trips")
      .update({
        status: "expired",
        updated_at: new Date().toISOString(),
      })
      .in("status", ["open", "active"])
      .or(`travel_time.lt.${threshold},departure_at.lt.${threshold}`)
      .select("id");

    if (result.error) {
      if (isMissingRelationError(result.error)) {
        return jsonResponse({
          success: true,
          expiredCount: 0,
          skipped: true,
          reason: "public.mobility_trips table not found",
        });
      }

      throw result.error;
    }

    return jsonResponse({
      success: true,
      expiredCount: result.data?.length ?? 0,
    });
  } catch (error) {
    if (error instanceof HttpError) {
      return errorResponse(error.message, error.status);
    }
    console.error("expire-trips failed", error);
    await recordEdgeFunctionFailure(createAdminClient(), {
      functionName: "expire-trips",
      error,
      subjectType: "mobility_trips",
    });
    return errorResponse(
      error instanceof Error ? error.message : "Failed to expire trips",
      500,
    );
  }
});
