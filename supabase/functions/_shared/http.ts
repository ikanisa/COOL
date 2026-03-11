export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function handleCors(request: Request): Response | null {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  return null;
}

export function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...extraHeaders,
    },
  });
}

export function errorResponse(
  message: string,
  status = 400,
  details?: unknown,
): Response {
  return jsonResponse(
    details === undefined
      ? { success: false, message }
      : { success: false, message, details },
    status,
  );
}

export function methodNotAllowed(allowed = "POST"): Response {
  return errorResponse("Method not allowed", 405, { allowed });
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
