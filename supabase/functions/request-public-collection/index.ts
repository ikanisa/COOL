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
    const { collection_id } = await req.json();
    const { data, error } = await supabase.rpc("request_public_collection", {
      collection: collection_id,
    });
    if (error) throw error;
    return jsonResponse({ ok: true, request_id: data });
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
