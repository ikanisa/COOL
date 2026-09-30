export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-collect-signature, x-collect-timestamp, x-collect-email-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
  });
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required env var: ${name}`);
  return value;
}

const authFailureMessages = new Set([
  "Authentication required",
  "Internal function authorization failed",
  "Unauthorized",
]);

function isAuthFailure(error: unknown): boolean {
  return error instanceof Error && authFailureMessages.has(error.message);
}

export function safeErrorMessage(error: unknown): string {
  return isAuthFailure(error) ? "authentication_required" : "service_unavailable";
}

export function authErrorStatus(error: unknown): number | null {
  return isAuthFailure(error) ? 401 : null;
}
