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
import {
  loadApprovedMomoSmsSenderTokens,
} from "../_shared/momo_sms_sender_allowlist.ts";
import { normalizePhone, PhoneValidationError } from "../_shared/phone.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";
import {
  asString,
  buildDeviceMessageKey,
  normalizeIngestionSource,
  normalizeSender,
  normalizeWhitespace,
  parseReceivedAt,
} from "./rules.ts";

type SmsIngestMessage = {
  sender?: string;
  smsBody?: string;
  smsReceivedAt?: string;
  deviceMessageKey?: string;
  ingestionSource?: string;
};

type SmsIngestRequest = SmsIngestMessage & {
  messages?: SmsIngestMessage[];
};

type NormalizedIncomingMessage = {
  sender: string;
  smsBody: string;
  smsReceivedAt: string;
  deviceMessageKey: string;
  ingestionSource: string;
};

type ProcessMessageResult = {
  success: boolean;
  deviceMessageKey: string;
  inserted: boolean;
  parseQueued: boolean;
  rawSmsId?: string;
  otpWhatsAppNumber?: string | null;
  error?: string;
  rateLimited?: boolean;
};

const parseSkippedStatuses = new Set(["processing", "parsed", "ignored"]);
const rateLimitPerHour = 5000;

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

async function normalizeIncomingMessage(
  input: SmsIngestMessage,
): Promise<NormalizedIncomingMessage | { error: string }> {
  const sender = asString(input.sender);
  const smsBody = normalizeWhitespace(input.smsBody?.trim() ?? "");
  if (!sender || smsBody.length === 0) {
    return { error: "sender and smsBody are required" };
  }

  const smsReceivedAt = parseReceivedAt(asString(input.smsReceivedAt));
  const deviceMessageKey = await buildDeviceMessageKey({
    sender,
    smsBody,
    smsReceivedAt,
  });
  return {
    sender,
    smsBody,
    smsReceivedAt,
    deviceMessageKey,
    ingestionSource: normalizeIngestionSource(input.ingestionSource),
  };
}

async function processMessage(options: {
  input: SmsIngestMessage;
  userId: string;
  approvedSenderTokens: Set<string>;
  otpWhatsAppNumber: string | null;
  remainingInsertSlots: number;
  userClient: ReturnType<typeof createUserClient>;
  adminClient: ReturnType<typeof createAdminClient>;
}) {
  const normalizedInput = await normalizeIncomingMessage(options.input);
  if ("error" in normalizedInput) {
    return {
      result: {
        success: false,
        deviceMessageKey: "",
        inserted: false,
        parseQueued: false,
        error: normalizedInput.error,
      } satisfies ProcessMessageResult,
      insertedNewRow: false,
    };
  }

  const {
    sender,
    smsBody,
    smsReceivedAt,
    deviceMessageKey,
    ingestionSource,
  } = normalizedInput;

  if (!options.approvedSenderTokens.has(normalizeSender(sender))) {
    return {
      result: {
        success: false,
        deviceMessageKey,
        inserted: false,
        parseQueued: false,
        error: "Unsupported SMS sender",
      } satisfies ProcessMessageResult,
      insertedNewRow: false,
    };
  }

  const existingResult = await options.adminClient
    .from("momo_sms_raw")
    .select("id, parse_status, otp_whatsapp_number")
    .eq("user_id", options.userId)
    .eq("device_message_key", deviceMessageKey)
    .maybeSingle();
  if (existingResult.error) {
    throw existingResult.error;
  }

  if (existingResult.data) {
    if (
      options.otpWhatsAppNumber &&
      !asString(existingResult.data.otp_whatsapp_number)
    ) {
      await options.adminClient
        .from("momo_sms_raw")
        .update({ otp_whatsapp_number: options.otpWhatsAppNumber })
        .eq("id", existingResult.data.id as string);
    }

    let parseQueued = false;
    try {
      parseQueued = await queueParseIfNeeded({
        rawSmsId: existingResult.data.id as string,
        parseStatus: asString(existingResult.data.parse_status),
        userClient: options.userClient,
      });
    } catch (error) {
      await recordOperationalHealthEvent(options.adminClient, {
        service: "sms_ingest",
        component: "sms-ingest",
        status: "warn",
        severity: "warning",
        issueCode: "parse_queue_failed",
        message: "SMS was already stored, but parse queueing failed.",
        functionName: "sms-ingest",
        userId: options.userId,
        subjectType: "momo_sms_raw",
        subjectId: existingResult.data.id as string,
        metadata: {
          sender,
          ingestion_source: ingestionSource,
          error: error instanceof Error ? error.message : String(error),
        },
      });
    }

    return {
      result: {
        success: true,
        deviceMessageKey,
        rawSmsId: existingResult.data.id as string,
        inserted: false,
        parseQueued,
        otpWhatsAppNumber:
          asString(existingResult.data.otp_whatsapp_number) ??
          options.otpWhatsAppNumber,
      } satisfies ProcessMessageResult,
      insertedNewRow: false,
    };
  }

  if (options.remainingInsertSlots <= 0) {
    return {
      result: {
        success: false,
        deviceMessageKey,
        inserted: false,
        parseQueued: false,
        error: `Rate limit exceeded. Max ${rateLimitPerHour} SMS per hour.`,
        rateLimited: true,
      } satisfies ProcessMessageResult,
      insertedNewRow: false,
    };
  }

  const insertResult = await options.adminClient
    .from("momo_sms_raw")
    .insert({
      user_id: options.userId,
      device_message_key: deviceMessageKey,
      sender,
      sms_body: smsBody,
      sms_received_at: smsReceivedAt,
      ingestion_source: ingestionSource,
      otp_whatsapp_number: options.otpWhatsAppNumber,
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
      userClient: options.userClient,
    });
  } catch (error) {
    await recordOperationalHealthEvent(options.adminClient, {
      service: "sms_ingest",
      component: "sms-ingest",
      status: "warn",
      severity: "warning",
      issueCode: "parse_queue_failed",
      message: "SMS was stored, but parse queueing failed.",
      functionName: "sms-ingest",
      userId: options.userId,
      subjectType: "momo_sms_raw",
      subjectId: rawSmsId,
      metadata: {
        sender,
        ingestion_source: ingestionSource,
        error: error instanceof Error ? error.message : String(error),
      },
    });
  }

  return {
    result: {
      success: true,
      deviceMessageKey,
      rawSmsId,
      inserted: true,
      parseQueued,
      otpWhatsAppNumber: options.otpWhatsAppNumber,
    } satisfies ProcessMessageResult,
    insertedNewRow: true,
  };
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

    const requestBody = await request.json() as SmsIngestRequest;
    const requestedMessages = Array.isArray(requestBody.messages)
      ? requestBody.messages
      : [requestBody];
    if (requestedMessages.length === 0) {
      return errorResponse("At least one message is required", 400);
    }
    const isBatchRequest = Array.isArray(requestBody.messages);

    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count: recentCount, error: countError } = await adminClient
      .from("momo_sms_raw")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", oneHourAgo);
    if (countError) {
      throw countError;
    }

    const approvedSenderTokens = await loadApprovedMomoSmsSenderTokens(
      async () =>
        await adminClient
          .from("momo_sms_sender_allowlist")
          .select("sender_token, sender_display")
          .eq("active", true)
          .order("sort_order", { ascending: true }),
    );
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

    let remainingInsertSlots = Math.max(
      0,
      rateLimitPerHour - (recentCount ?? 0),
    );
    const results: ProcessMessageResult[] = [];
    for (const message of requestedMessages) {
      const processed = await processMessage({
        input: message,
        userId: user.id,
        approvedSenderTokens,
        otpWhatsAppNumber,
        remainingInsertSlots,
        userClient,
        adminClient,
      });
      if (processed.insertedNewRow) {
        remainingInsertSlots = Math.max(0, remainingInsertSlots - 1);
      }
      results.push(processed.result);
    }

    const insertedCount = results.filter((row) => row.success && row.inserted)
      .length;
    const duplicateCount = results.filter((row) =>
      row.success && !row.inserted
    ).length;
    const failedCount = results.filter((row) => !row.success).length;
    const rateLimited = results.some((row) => row.rateLimited === true);

    if (!isBatchRequest) {
      const first = results[0];
      if (!first.success) {
        const status = first.rateLimited ? 429 : 400;
        return errorResponse(first.error ?? "Failed to ingest SMS", status);
      }
      return jsonResponse({
        success: true,
        rawSmsId: first.rawSmsId,
        inserted: first.inserted,
        parseQueued: first.parseQueued,
        otpWhatsAppNumber: first.otpWhatsAppNumber,
        results,
      });
    }

    return jsonResponse({
      success: failedCount == 0,
      rateLimited,
      insertedCount,
      duplicateCount,
      failedCount,
      results,
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
