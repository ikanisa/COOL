/**
 * send-notification — Edge Function for sending push notifications.
 *
 * Callable by other Edge Functions, DB webhook triggers, or admin tooling.
 * Validates requests via service-role key (not user JWT).
 *
 * POST /send-notification
 *   Body:
 *     User-targeted:   { type: "user", user_id, title, body, data?, image_url? }
 *     Topic broadcast:  { type: "topic", topic, category, campaign_approval_id, title, body, data?, image_url? }
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
import { constantTimeEquals } from "../_shared/security.ts";
import { createAdminClient } from "../_shared/supabase.ts";

const TOPIC_RE = /^[A-Za-z0-9-_.~%]{1,128}$/;
const CATEGORY_RE = /^[a-z][a-z0-9_:-]{0,63}$/;
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_TITLE_LENGTH = 120;
const MAX_BODY_LENGTH = 500;
const MAX_DATA_KEYS = 20;
const MAX_DATA_VALUE_LENGTH = 1024;

class RequestError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

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
    return constantTimeEquals(serviceRoleKey, token);
  } catch {
    return false;
  }
}

type NotificationTarget = {
  type: "user" | "topic";
  userId?: string;
  topic?: string;
  campaignApprovalId?: string;
};

function readRequiredString(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  if (typeof value !== "string") {
    throw new RequestError(400, `Missing required field: ${field}.`);
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw new RequestError(400, `Missing required field: ${field}.`);
  }
  if (trimmed.length > maxLength) {
    throw new RequestError(400, `${field} is too long.`);
  }
  return trimmed;
}

function readOptionalString(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (trimmed.length > maxLength) {
    throw new RequestError(400, "Optional string field is too long.");
  }
  return trimmed;
}

function readCategory(value: unknown, fallback?: string): string {
  const category = readOptionalString(value, 64) ?? fallback;
  if (!category || !CATEGORY_RE.test(category)) {
    throw new RequestError(400, "Invalid notification category.");
  }
  return category;
}

function readFcmData(value: unknown): FcmData | undefined {
  if (value == null) return undefined;
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new RequestError(400, "data must be an object with string values.");
  }

  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > MAX_DATA_KEYS) {
    throw new RequestError(400, "data has too many keys.");
  }

  const data: FcmData = {};
  for (const [key, rawValue] of entries) {
    if (!CATEGORY_RE.test(key)) {
      throw new RequestError(400, "data contains an invalid key.");
    }
    if (typeof rawValue !== "string") {
      throw new RequestError(400, "data values must be strings.");
    }
    if (rawValue.length > MAX_DATA_VALUE_LENGTH) {
      throw new RequestError(400, "data value is too long.");
    }
    data[key] = rawValue;
  }

  return data;
}

type CampaignApprovalRow = {
  id: string;
  topic: string;
  category: string;
  title: string;
  body: string;
  approval_status: string;
  expires_at: string | null;
};

async function requireApprovedTopicCampaign(options: {
  adminClient: ReturnType<typeof createAdminClient>;
  approvalId: string;
  topic: string;
  category: string;
  title: string;
  body: string;
}): Promise<void> {
  if (!UUID_RE.test(options.approvalId)) {
    throw new RequestError(
      400,
      "Valid campaign_approval_id is required for topic sends.",
    );
  }

  const { data, error } = await options.adminClient
    .from("notification_campaign_approvals")
    .select("id, topic, category, title, body, approval_status, expires_at")
    .eq("id", options.approvalId)
    .maybeSingle();

  if (error) {
    throw new Error("Failed to verify campaign approval.");
  }

  const approval = data as CampaignApprovalRow | null;
  if (!approval || approval.approval_status !== "approved") {
    throw new RequestError(
      403,
      "Approved campaign record is required for topic sends.",
    );
  }
  if (
    approval.topic !== options.topic || approval.category !== options.category
  ) {
    throw new RequestError(
      403,
      "Campaign approval does not match the notification target.",
    );
  }
  if (approval.title !== options.title || approval.body !== options.body) {
    throw new RequestError(
      403,
      "Campaign approval does not match notification copy.",
    );
  }
  if (approval.expires_at && Date.parse(approval.expires_at) <= Date.now()) {
    throw new RequestError(403, "Campaign approval has expired.");
  }
}

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
  category?: string;
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
      category: options.category ?? null,
      campaign_approval_id: options.target.campaignApprovalId ?? null,
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

  try {
    const type = readOptionalString(body.type, 24)?.toLowerCase();
    const title = readRequiredString(body.title, "title", MAX_TITLE_LENGTH);
    const bodyText = readRequiredString(body.body, "body", MAX_BODY_LENGTH);
    const imageUrl = readOptionalString(body.image_url, 2048);

    const notification: FcmNotification = {
      title,
      body: bodyText,
      ...(imageUrl ? { image: imageUrl } : {}),
    };

    const data = readFcmData(body.data);
    const adminClient = createAdminClient();

    if (type === "topic") {
      const topic = readRequiredString(body.topic, "topic", 128);
      if (!TOPIC_RE.test(topic)) {
        return errorResponse("Invalid topic.", 400);
      }
      const category = readCategory(body.category);
      const campaignApprovalId = readRequiredString(
        body.campaign_approval_id ?? body.approval_id,
        "campaign_approval_id",
        80,
      );

      await requireApprovedTopicCampaign({
        adminClient,
        approvalId: campaignApprovalId,
        topic,
        category,
        title,
        body: bodyText,
      });

      const result = await sendToTopic(topic, notification, data);
      await logNotificationEvent({
        target: { type: "topic", topic, campaignApprovalId },
        notification,
        data,
        category,
        result,
      });
      return jsonResponse(result, result.success ? 200 : 502);
    }

    if (type === "user" || !type) {
      const userId = readRequiredString(body.user_id, "user_id", 80);
      if (!UUID_RE.test(userId)) {
        return errorResponse("Invalid user_id.", 400);
      }

      // Phase 5A: Check notification preferences before sending.
      // If the user has opted out of this category, skip silently.
      const category = readCategory(body.category, "general");
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
          category,
          result: skippedResult,
        });
        return jsonResponse(skippedResult, 200);
      }

      const result = await sendToUser(userId, notification, data);
      await logNotificationEvent({
        target: { type: "user", userId },
        notification,
        data,
        category,
        result,
      });
      return jsonResponse(result, result.success ? 200 : 502);
    }

    return errorResponse(`Unknown notification type: ${type}`, 400);
  } catch (error) {
    if (error instanceof RequestError) {
      return errorResponse(error.message, error.status);
    }
    console.error("[send-notification] Error:", error);
    return errorResponse("Notification send failed.", 500);
  }
});
