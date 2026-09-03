import {
  authErrorStatus,
  corsHeaders,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { notificationOperatorCommand } from "../_shared/notification_operator.ts";
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
    const payload = await request.json() as Record<string, unknown>;
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
      return response({ error: `${command.permission} is required` }, 403);
    }
    const { data, error } = await serviceClient().rpc(
      command.rpc,
      command.params,
    );
    if (error) throw error;
    return response({ ok: true, action: payload.action, result: data });
  } catch (error) {
    const message = safeErrorMessage(error);
    return response(
      { error: message },
      authErrorStatus(error) ??
        (/required|invalid|unsupported|must/i.test(message) ? 400 : 409),
    );
  }
});
