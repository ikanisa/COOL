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
    const { data, error } = await supabase.rpc(
      "manual_allocate_parsed_payment_event",
      {
        event_id: payload.parsed_event_id,
        target_collection_id: payload.collection_id,
        target_payment_intent_id: payload.payment_intent_id ?? null,
        reason: payload.reason,
      },
    );
    if (error) throw error;
    return jsonResponse({ ok: true, payment_id: data });
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
