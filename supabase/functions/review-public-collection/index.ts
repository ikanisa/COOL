import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  try {
    const { supabase } = await requireUser(req.headers.get("authorization"));
    const payload = await req.json();
    const { error } = await supabase.rpc("review_public_collection", {
      request_id: payload.request_id,
      approved: payload.approved,
      p_admin_note: payload.admin_note ?? null,
    });
    if (error) throw error;
    return jsonResponse({ ok: true });
  } catch (error) {
    const authStatus = authErrorStatus(error);
    if (authStatus) {
      return jsonResponse({ error: safeErrorMessage(error) }, authStatus);
    }
    return jsonResponse({
      error: safeErrorMessage(error),
    }, 500);
  }
});
