/**
 * send-notification — Edge Function for sending push notifications.
 *
 * Callable by other Edge Functions, DB webhook triggers, or admin tooling.
 * Validates requests via service-role key (not user JWT).
 *
 * POST /send-notification
 *   Body:
 *     User-targeted:   { type: "user", user_id, title, body, data?, image_url? }
 *     Topic broadcast:  { type: "topic", topic, title, body, data?, image_url? }
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { handleCors, jsonResponse, errorResponse, methodNotAllowed } from "../_shared/http.ts";
import { sendToUser, sendToTopic } from "../_shared/fcm.ts";
import type { FcmNotification, FcmData } from "../_shared/fcm.ts";

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing env: ${name}`);
  }
  return value;
}

function isServiceRole(request: Request): boolean {
  const authHeader = request.headers.get("authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return false;

  // Compare against the service role key.
  try {
    const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
    return token === serviceRoleKey;
  } catch {
    return false;
  }
}

Deno.serve(async (request) => {
  // CORS preflight.
  const corsResponse = handleCors(request);
  if (corsResponse) return corsResponse;

  if (request.method !== "POST") {
    return methodNotAllowed();
  }

  // Only allow service-role calls (internal, not user-facing).
  if (!isServiceRole(request)) {
    return errorResponse("Unauthorized: service-role key required.", 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return errorResponse("Invalid JSON body.", 400);
  }

  const type = (body.type as string)?.toLowerCase();
  const title = body.title as string;
  const bodyText = body.body as string;

  if (!title || !bodyText) {
    return errorResponse("Missing required fields: title, body.", 400);
  }

  const notification: FcmNotification = {
    title,
    body: bodyText,
    ...(body.image_url ? { image: body.image_url as string } : {}),
  };

  const data: FcmData | undefined = body.data
    ? (body.data as FcmData)
    : undefined;

  try {
    if (type === "topic") {
      const topic = body.topic as string;
      if (!topic) {
        return errorResponse("Missing required field: topic.", 400);
      }

      const result = await sendToTopic(topic, notification, data);
      return jsonResponse(result, result.success ? 200 : 502);
    }

    if (type === "user" || !type) {
      const userId = body.user_id as string;
      if (!userId) {
        return errorResponse("Missing required field: user_id.", 400);
      }

      const result = await sendToUser(userId, notification, data);
      return jsonResponse(result, result.success ? 200 : 502);
    }

    return errorResponse(`Unknown notification type: ${type}`, 400);
  } catch (error) {
    console.error("[send-notification] Error:", error);
    return errorResponse(
      error instanceof Error ? error.message : "Internal error",
      500,
    );
  }
});
