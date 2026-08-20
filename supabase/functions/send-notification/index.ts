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
  template_key?: string;
  context?: Record<string, string | number | boolean | null>;
  collection_id?: string | null;
  deep_link?: string | null;
  locale?: string;
};

async function requestDispatch(): Promise<boolean> {
  try {
    const response = await fetch(
      `${Deno.env.get("SUPABASE_URL")}/functions/v1/dispatch-notifications`,
      {
        method: "POST",
        headers: {
          apikey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
          "Content-Type": "application/json",
          "x-collect-signature": Deno.env.get("INTERNAL_FUNCTION_SECRET") ?? "",
        },
        body: JSON.stringify({ limit: 100 }),
      },
    );
    return response.ok;
  } catch {
    return false;
  }
}

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
    if (!userId) {
      return jsonResponse({ error: "Missing notification user" }, 400);
    }
    const title = payload.title?.trim();
    const body = payload.body?.trim();
    const type = payload.type?.trim();
    const templateKey = payload.template_key?.trim();
    if (templateKey) {
      const { data, error } = await serviceClient().rpc(
        "enqueue_notification_template_event",
        {
          p_user_id: userId,
          p_template_key: templateKey,
          p_context: payload.context ?? {},
          p_collection_id: payload.collection_id ?? null,
          p_deep_link: payload.deep_link ?? null,
          p_locale: payload.locale?.trim() || "en",
        },
      );
      if (error) throw error;
      const dispatchRequested = data === null ? false : await requestDispatch();
      return jsonResponse({
        ok: data !== null,
        skipped: data === null,
        notification_event_id: data,
        dispatch_requested: dispatchRequested,
      });
    }
    if (!title || !body || !type) {
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
    const dispatchRequested = data === null ? false : await requestDispatch();
    return jsonResponse({
      ok: data !== null,
      skipped: data === null,
      notification_event_id: data,
      dispatch_requested: dispatchRequested,
    });
  } catch (error) {
    const authStatus = authErrorStatus(error);
    if (authStatus) {
      return jsonResponse({ error: safeErrorMessage(error) }, authStatus);
    }
    return jsonResponse({ error: safeErrorMessage(error) }, 500);
  }
});
