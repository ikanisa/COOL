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

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { sendToTopic, sendToUser } from "../_shared/fcm.ts";
import type { FcmData, FcmNotification } from "../_shared/fcm.ts";
import { createAdminClient } from "../_shared/supabase.ts";

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

type NotificationTarget = {
  type: "user" | "topic";
  userId?: string;
  topic?: string;
};

function notificationSendStatus(result: {
  success: boolean;
  sent_count: number;
  failed_count: number;
}): "sent" | "partial" | "failed" {
  if (result.success && result.failed_count == 0) {
    return "sent";
  }
  if (result.sent_count > 0) {
    return "partial";
  }
  return "failed";
}

async function logNotificationEvent(options: {
  target: NotificationTarget;
  notification: FcmNotification;
  data?: FcmData;
  result: {
    success: boolean;
    sent_count: number;
    failed_count: number;
    cleaned_tokens: number;
    errors: string[];
  };
}) {
  try {
    const adminClient = createAdminClient();
    const sendStatus = notificationSendStatus(options.result);
    const sentAt = options.result.sent_count > 0
      ? new Date().toISOString()
      : null;

    await adminClient.from("notification_events").insert({
      target_type: options.target.type,
      user_id: options.target.userId ?? null,
      topic: options.target.topic ?? null,
      title: options.notification.title,
      body: options.notification.body,
      route: options.data?.route ?? null,
      image_url: options.notification.image ?? null,
      data: options.data ?? {},
      provider: "fcm",
      send_status: sendStatus,
      sent_count: options.result.sent_count,
      failed_count: options.result.failed_count,
      cleaned_tokens: options.result.cleaned_tokens,
      errors: options.result.errors,
      sent_at: sentAt,
    });
  } catch (error) {
    console.error(
      "[send-notification] Failed to log notification event:",
      error,
    );
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
      await logNotificationEvent({
        target: { type: "topic", topic },
        notification,
        data,
        result,
      });
      return jsonResponse(result, result.success ? 200 : 502);
    }

    if (type === "user" || !type) {
      const userId = body.user_id as string;
      if (!userId) {
        return errorResponse("Missing required field: user_id.", 400);
      }

      // Phase 5A: Check notification preferences before sending.
      // If the user has opted out of this category, skip silently.
      const category = (body.category as string) ?? "general";
      const adminClient = createAdminClient();
      const { data: prefResult } = await adminClient.rpc(
        "is_notification_enabled",
        { p_user_id: userId, p_category: category, p_channel: "push" },
      );

      if (prefResult === false) {
        const skippedResult = {
          success: true,
          sent_count: 0,
          failed_count: 0,
          cleaned_tokens: 0,
          errors: [],
          skipped: true,
          reason: "user_opted_out",
        };
        await logNotificationEvent({
          target: { type: "user", userId },
          notification,
          data,
          result: skippedResult,
        });
        return jsonResponse(skippedResult, 200);
      }

      const result = await sendToUser(userId, notification, data);
      await logNotificationEvent({
        target: { type: "user", userId },
        notification,
        data,
        result,
      });
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
