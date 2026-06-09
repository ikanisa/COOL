import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireInternalRequest, serviceClient } from "../_shared/supabase.ts";

type NotificationRequest = {
  user_id?: string;
  type?: string;
  title?: string;
  body?: string;
  collection_id?: string | null;
  deep_link?: string | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  try {
    requireInternalRequest(req);
    const payload = await req.json() as NotificationRequest;
    const userId = payload.user_id?.trim();
    const title = payload.title?.trim();
    const body = payload.body?.trim();
    const type = payload.type?.trim();
    if (!userId || !title || !body || !type) {
      return jsonResponse({ error: "Missing notification fields" }, 400);
    }
    const { data, error } = await serviceClient().rpc(
      "enqueue_notification_event",
      {
        p_user_id: userId,
        p_type: type,
        p_title: title,
        p_body: body,
        p_collection_id: payload.collection_id ?? null,
        p_deep_link: payload.deep_link ?? null,
      },
    );
    if (error) throw error;
    return jsonResponse({ ok: true, notification_event_id: data });
  } catch (error) {
    const authStatus = authErrorStatus(error);
    if (authStatus) {
      return jsonResponse({ error: safeErrorMessage(error) }, authStatus);
    }
    return jsonResponse({ error: safeErrorMessage(error) }, 500);
  }
});
