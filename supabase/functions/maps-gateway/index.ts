import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";
import {
  cacheTtlForAction,
  handleAction,
  isCacheableAction,
} from "./maps_gateway_actions.ts";
import {
  HttpError,
  mapsApiKeyConfig,
  MapsGatewayRequest,
  RateLimiter,
  ResponseCache,
} from "./maps_gateway_support.ts";

const rateLimiter = new RateLimiter();
const responseCache = new ResponseCache();

setInterval(() => rateLimiter.prune(), 10 * 60 * 1000);

if (!mapsApiKeyConfig.apiKey) {
  console.warn(
    "maps-gateway loaded without GOOGLE_MAPS_SERVER_API_KEY or GEMINI_API_KEY. Requests will fail until a Google credential is configured.",
  );
} else if (mapsApiKeyConfig.source == "GEMINI_API_KEY") {
  console.info(
    "maps-gateway is using GEMINI_API_KEY as its Google Maps Platform credential.",
  );
}

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
    const user = await requireUser(authorization);
    userIdForTelemetry = user.id;

    if (!rateLimiter.allow(user.id)) {
      console.warn(
        JSON.stringify({
          service: "maps-gateway",
          event: "rate_limited",
          user_id: user.id,
        }),
      );
      return errorResponse(
        "Too many requests. Please try again later.",
        429,
        { retryAfterSeconds: 60 },
      );
    }

    const body = await request.json() as MapsGatewayRequest;
    const startedAt = Date.now();
    const action = body.action;
    const cacheable = isCacheableAction(action);
    let cacheKey: string | null = null;

    if (cacheable) {
      cacheKey = ResponseCache.key(action, body as Record<string, unknown>);
      const cached = responseCache.get(cacheKey);
      if (cached) {
        return jsonResponse({ success: true, cached: true, ...cached });
      }
    }

    const response = await handleAction(body);

    if (cacheable && cacheKey) {
      responseCache.set(cacheKey, response, cacheTtlForAction(action));
    }

    console.info(
      JSON.stringify({
        service: "maps-gateway",
        user_id: user.id,
        action: body.action ?? "unknown",
        latency_ms: Date.now() - startedAt,
      }),
    );

    return jsonResponse({ success: true, ...response });
  } catch (error) {
    if (error instanceof SyntaxError) {
      return errorResponse("Invalid JSON body", 400);
    }

    if (error instanceof HttpError) {
      return errorResponse(error.message, error.status, error.details);
    }

    console.error("maps-gateway failed", error);
    await recordEdgeFunctionFailure(createAdminClient(), {
      functionName: "maps-gateway",
      error,
      userId: userIdForTelemetry,
    });
    return errorResponse(
      error instanceof Error ? error.message : "Maps gateway failed",
      500,
    );
  }
});

async function requireUser(authorization: string) {
  const client = createUserClient(authorization);
  const {
    data: { user },
    error,
  } = await client.auth.getUser();

  if (error || !user) {
    throw new HttpError(401, "Authentication required");
  }

  return user;
}
