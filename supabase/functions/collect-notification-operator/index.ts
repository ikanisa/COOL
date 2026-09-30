import {
  authErrorStatus,
  corsHeaders,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { notificationOperatorCommand, OperatorInputError } from "../_shared/notification_operator.ts";
import { boundedJson, PublicError } from "../_shared/production_contract.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Cache-Control": "no-store, max-age=0",
      "Content-Type": "application/json",
      "Pragma": "no-cache",
    },
  });
}

function databaseCode(error: unknown): string | null {
  if (typeof error !== "object" || error === null || !("code" in error)) {
    return null;
  }
  const code = (error as { code?: unknown }).code;
  return typeof code === "string" ? code : null;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return response({ error: "Method not allowed" }, 405);
  }
  try {
    const { supabase, user } = await requireUser(
      request.headers.get("authorization"),
    );
    const payload = await boundedJson(request);
    const command = notificationOperatorCommand(
      payload.action,
      payload,
      user.id,
    );
    const { data: identity, error: identityError } = await supabase.rpc(
      "admin_current_user",
    );
    if (identityError) throw identityError;
    const permissions = typeof identity === "object" && identity != null &&
        Array.isArray((identity as Record<string, unknown>).permissions)
      ? (identity as Record<string, unknown>).permissions as unknown[]
      : [];
    if (!permissions.includes(command.permission)) {
      return response({ error: "forbidden" }, 403);
    }
    const { data, error } = await serviceClient().rpc(
      command.rpc,
      command.params,
    );
    if (error) {
      const code = databaseCode(error);
      if (code === "42501") return response({ error: "forbidden" }, 403);
      if (code !== null && ["P0001", "23505", "23514", "40001"].includes(code)) {
        return response({ error: "conflict" }, 409);
      }
      throw error;
    }
    return response({ ok: true, action: payload.action, result: data });
  } catch (error) {
    if (error instanceof PublicError) {
      return response({ error: error.code }, error.status);
    }
    if (error instanceof OperatorInputError) {
      return response({ error: "invalid_request" }, 400);
    }
    return response(
      { error: safeErrorMessage(error) },
      authErrorStatus(error) ?? 503,
    );
  }
});
