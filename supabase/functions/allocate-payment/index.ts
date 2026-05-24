import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireInternalRequest, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  try {
    requireInternalRequest(req);
    const { parsed_event_id } = await req.json();
    const { data, error } = await serviceClient().rpc(
      "allocate_parsed_payment_event",
      {
        event_id: parsed_event_id,
      },
    );
    if (error) throw error;
    return jsonResponse({ ok: true, allocation_status: data });
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
