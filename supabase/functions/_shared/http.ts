/**
 * Allowed origins for CORS.
 * Mobile Flutter clients don't send an Origin header, so requests without
 * Origin are accepted. Browser-based callers (PWA) must match this list.
 */
const ALLOWED_ORIGINS: string[] = [
  "https://pwa.cool.app",
  "https://cool.app",
  "https://cool.ikanisa.com",
];

function resolveAllowedOrigin(request: Request): string {
  const origin = request.headers.get("origin")?.trim();
  if (!origin) {
    // Mobile client or server-to-server: no browser Origin header.
    return ALLOWED_ORIGINS[0];
  }

  if (ALLOWED_ORIGINS.includes(origin)) {
    return origin;
  }

  // Development / local: allow Supabase local dev origins.
  if (
    origin.startsWith("http://localhost:") ||
    origin.startsWith("http://127.0.0.1:")
  ) {
    return origin;
  }

  // Unknown origin — return the first allowed origin (browser will block).
  return ALLOWED_ORIGINS[0];
}

export function buildCorsHeaders(request: Request): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": resolveAllowedOrigin(request),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-cron-secret, x-firebase-appcheck",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Vary": "Origin",
  };
}

/** @deprecated Use buildCorsHeaders(request) for origin-aware CORS. */
export const corsHeaders = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGINS[0],
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret, x-firebase-appcheck",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function handleCors(request: Request): Response | null {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: buildCorsHeaders(request) });
  }

  return null;
}

export function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders: HeadersInit = {},
  request?: Request,
): Response {
  const cors = request ? buildCorsHeaders(request) : corsHeaders;
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      ...extraHeaders,
    },
  });
}

export function errorResponse(
  message: string,
  status = 400,
  details?: unknown,
  request?: Request,
): Response {
  return jsonResponse(
    details === undefined
      ? { success: false, message }
      : { success: false, message, details },
    status,
    {},
    request,
  );
}

export function methodNotAllowed(allowed = "POST", request?: Request): Response {
  return errorResponse("Method not allowed", 405, { allowed }, request);
}

export function isMissingRelationError(error: unknown): boolean {
  if (!error) {
    return false;
  }

  const message = error instanceof Error
    ? error.message
    : JSON.stringify(error);

  return message.includes("Could not find the table") ||
    message.includes("relation") && message.includes("does not exist");
}
