import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import {
  recordEdgeFunctionFailure,
  recordOperationalHealthEvent,
} from "../_shared/observability.ts";
import { normalizePhone, PhoneValidationError } from "../_shared/phone.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

type SmsIngestRequest = {
  sender?: string;
  smsBody?: string;
  smsReceivedAt?: string;
  deviceMessageKey?: string;
  ingestionSource?: string;
};

const parseSkippedStatuses = new Set(["processing", "parsed", "ignored"]);

function asString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }

  return null;
}

function normalizeWhitespace(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
}

function normalizeSender(value: string): string {
  return value.toLowerCase().trim().replaceAll(/[^a-z0-9]/g, "");
}

function parseReceivedAt(value: string | null): string {
  if (!value) {
    return new Date().toISOString();
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? new Date().toISOString()
    : parsed.toISOString();
}

function normalizeOptionalPhone(value: unknown): string | null {
  const raw = asString(value);
  if (!raw) {
    return null;
  }

  try {
    return normalizePhone(raw);
  } catch (error) {
    if (error instanceof PhoneValidationError) {
      return null;
    }
    throw error;
  }
}

async function buildDeviceMessageKey(options: {
  sender: string;
  smsBody: string;
  smsReceivedAt: string;
}) {
  const payload = [
    normalizeSender(options.sender),
    options.smsReceivedAt,
    normalizeWhitespace(options.smsBody),
  ].join("|");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(payload),
  );

  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function queueParseIfNeeded(options: {
  rawSmsId: string;
  parseStatus?: string | null;
  userClient: ReturnType<typeof createUserClient>;
}) {
  const normalizedParseStatus = (options.parseStatus ?? "pending").trim()
    .toLowerCase();
  if (parseSkippedStatuses.has(normalizedParseStatus)) {
    return false;
  }

  const result = await options.userClient.functions.invoke("parse-momo-sms", {
    body: { rawSmsId: options.rawSmsId },
  });

  const payload = result.data;
  if (result.error) {
    throw result.error;
  }
  if (payload && typeof payload === "object" && "success" in payload) {
    if ((payload as { success?: boolean }).success === false) {
      throw new Error(
        ((payload as { message?: string }).message ?? "Failed to parse SMS")
          .toString(),
      );
    }
  }

  return true;
}

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method !== "POST") {
    return methodNotAllowed("POST");
  }

  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return errorResponse("Authentication required", 401);
  }

  const adminClient = createAdminClient();

  try {
    const userClient = createUserClient(authorization);
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return errorResponse("Authentication required", 401);
    }

    const body = await request.json() as SmsIngestRequest;
    const sender = asString(body.sender);
    const smsBody = normalizeWhitespace(body.smsBody?.trim() ?? "");
    if (!sender || smsBody.length === 0) {
      return errorResponse("sender and smsBody are required", 400);
    }

    const smsReceivedAt = parseReceivedAt(asString(body.smsReceivedAt));
    const deviceMessageKey = await buildDeviceMessageKey({
      sender,
      smsBody,
      smsReceivedAt,
    });
    const ingestionSource = asString(body.ingestionSource) ??
      "android_sms_listener";

    const appUserResult = await adminClient
      .from("users")
      .select("phone")
      .eq("id", user.id)
      .maybeSingle();
    if (appUserResult.error) {
      throw appUserResult.error;
    }

    const otpWhatsAppNumber = normalizeOptionalPhone(
      appUserResult.data?.phone ??
        user.user_metadata?.phone ??
        user.phone,
    );

    const existingResult = await adminClient
      .from("momo_sms_raw")
      .select("id, parse_status, otp_whatsapp_number")
      .eq("user_id", user.id)
      .eq("device_message_key", deviceMessageKey)
      .maybeSingle();
    if (existingResult.error) {
      throw existingResult.error;
    }

    if (existingResult.data) {
      if (
        otpWhatsAppNumber &&
        !asString(existingResult.data.otp_whatsapp_number)
      ) {
        await adminClient
          .from("momo_sms_raw")
          .update({ otp_whatsapp_number: otpWhatsAppNumber })
          .eq("id", existingResult.data.id as string);
      }

      let parseQueued = false;
      try {
        parseQueued = await queueParseIfNeeded({
          rawSmsId: existingResult.data.id as string,
          parseStatus: asString(existingResult.data.parse_status),
          userClient,
        });
      } catch (error) {
        await recordOperationalHealthEvent(adminClient, {
          service: "sms_ingest",
          component: "sms-ingest",
          status: "warn",
          severity: "warning",
          issueCode: "parse_queue_failed",
          message: "SMS was already stored, but parse queueing failed.",
          functionName: "sms-ingest",
          userId: user.id,
          subjectType: "momo_sms_raw",
          subjectId: existingResult.data.id as string,
          metadata: {
            sender,
            ingestion_source: ingestionSource,
            error: error instanceof Error ? error.message : String(error),
          },
        });
      }

      return jsonResponse({
        success: true,
        rawSmsId: existingResult.data.id,
        inserted: false,
        parseQueued,
        otpWhatsAppNumber: asString(existingResult.data.otp_whatsapp_number) ??
          otpWhatsAppNumber,
      });
    }

    const insertResult = await adminClient
      .from("momo_sms_raw")
      .insert({
        user_id: user.id,
        device_message_key: deviceMessageKey,
        sender,
        sms_body: smsBody,
        sms_received_at: smsReceivedAt,
        ingestion_source: ingestionSource,
        otp_whatsapp_number: otpWhatsAppNumber,
        parse_status: "pending",
      })
      .select("id")
      .single();
    if (insertResult.error) {
      throw insertResult.error;
    }

    const rawSmsId = insertResult.data.id as string;
    let parseQueued = false;
    try {
      parseQueued = await queueParseIfNeeded({
        rawSmsId,
        parseStatus: "pending",
        userClient,
      });
    } catch (error) {
      await recordOperationalHealthEvent(adminClient, {
        service: "sms_ingest",
        component: "sms-ingest",
        status: "warn",
        severity: "warning",
        issueCode: "parse_queue_failed",
        message: "SMS was stored, but parse queueing failed.",
        functionName: "sms-ingest",
        userId: user.id,
        subjectType: "momo_sms_raw",
        subjectId: rawSmsId,
        metadata: {
          sender,
          ingestion_source: ingestionSource,
          error: error instanceof Error ? error.message : String(error),
        },
      });
    }

    return jsonResponse({
      success: true,
      rawSmsId,
      inserted: true,
      parseQueued,
      otpWhatsAppNumber,
    });
  } catch (error) {
    console.error("sms-ingest failed", error);
    await recordEdgeFunctionFailure(adminClient, {
      functionName: "sms-ingest",
      error,
      issueCode: "sms_ingest_failed",
    });
    return errorResponse(
      error instanceof Error ? error.message : "Failed to ingest SMS",
      500,
    );
  }
});
